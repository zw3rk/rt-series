# Round-3 Remediation Review: `0aa8075` vs `a86a161` (mips32rt)

**Outcome:** six of eight items are fully resolved. M32-R3-2 is a sound mitigation but not the coherent-backing fix the audit asked for, and M32-R3-5 over-corrects: plain `kill(2)` now returns `-EAGAIN` where Linux silently merges. No regression was found in the VMA generation sync, Darwin protection restoration, LL/SC copyout serialization, execve signal state, or `$sp` preservation. Hygiene scans are clean. Nothing was built or executed, so link success of the new regression test is taken from the commit, not verified.

## Per-item verification

### M32-R3-1 — brk marks stale VMA snapshots current: **VERIFIED**

`vm_sync_brk_to_ctx` (`src/rt32/vm.c:105`) now bumps the generation and then calls `vm_copy_state_to_ctx`, which copies brk fields, the mmap cursor, the full region table, and stamps the generation last. Every call site in `rt32_vm_brk` is under `g_vm_lock`, including all the early-return paths at `src/rt32/vm.c:621..702`. The fast path in `rt32_vm_sync_ctx` loads the generation with acquire ordering and still re-syncs under the lock when it differs. A peer that observes the new generation can no longer match it without having the matching table. Regression probe T1 exists in `tests/test_r3_regress.c`.

### M32-R3-2 — Darwin shared-alias flushing overwrites newer data: **PARTIAL**

`vm_writeback_darw_locked` (`src/rt32/vm_darw.c:99`) now reads the file baseline chunk by chunk, propagates only bytes where the source differs from the baseline to aliases, then merges those bytes into the baseline and writes the result. I traced the offset arithmetic (`soff = rel + (coff - foff)`, `dst[k]` vs `filebuf[rel + k]`) and it is consistent. The ordering comment is correct: propagation must run before the baseline merge. The audit's concrete scenario (stale A flushed before fresh B) is fixed, because A's bytes equal the baseline and contribute nothing.

What remains, and is documented in the file header:

- Same-byte conflicts stay first-flushed-wins. A revert-to-file-value through alias B while alias A holds a different dirty value loses B's write.
- Ordinary stores still give no immediate cross-alias visibility until a flush point. The audit asked for coherent shared backing; this commit chose dirty-diffing instead.
- No regression probe covers R3-2. The test header lists probes for R3-1, 3, 4, 5, 6, 7 only.

Writes remain clamped to `st_size`, and past-EOF bytes baseline to zero, which is the right Linux `MAP_SHARED` behavior.

### M32-R3-3 — Darwin protection restoration can disable adjacent guest pages: **VERIFIED**

`vm_union_host_prot_locked` (`src/rt32/vm.c:112`) ORs `mips32_host_prot` across every VMA overlapping the host-rounded range, and `vm_host_restore_locked` applies it. Call sites checked:

| Path | Location | Restore after elevation |
|---|---|---|
| brk grow (Apple) | `src/rt32/vm.c:675` | union, after region record |
| brk shrink (Apple) | `src/rt32/vm.c:690` | unmap regions first, then union |
| mmap record failure unwind | `src/rt32/vm_mmap.c:221` | union |
| mmap shadow populate | `src/rt32/vm_mmap.c:229` | union |
| munmap (Apple) | `src/rt32/vm_mmap.c:362` | unmap first, then union |
| shared-fd resync | `src/rt32/vm_mmap.c:655` | union |
| Darwin writeback, incl. ENOMEM path | `src/rt32/vm_darw.c:147,155,254,262` | union for source and every alias |
| mprotect (Apple) | `src/rt32/vm_mmap.c:294..307` | inline union loop, not the shared helper |

The ordering of unmap-then-restore on the shrink and munmap paths is correct: restoring first would compute the union with the dying VMA still present. The mprotect path duplicates the union logic rather than calling `vm_union_host_prot_locked`; it is functionally equivalent as far as I can see but is a maintenance seam. Probe T2 exists.

### M32-R3-4 — Guest copyout bypasses LL/SC reservation tracking: **VERIFIED** (one unverified lock-order edge, see follow-ups)

`rt32_vm_copy_to` (`src/rt32/vm.c:780`) validates the range under `g_vm_lock` and then calls `mips_guest_store_commit`, which wraps the existing `mips_store_locked` primitive. That primitive keeps the fast path when no LL has ever been recorded, otherwise takes the LL lock, copies, bumps epochs over the whole range, and breaks the caller's own reservation on overlap. Thread-TID writes go through `mips_sc_copy_to` → `rt32_vm_copy_to` (`src/os/threads.c:170`), so `CHILD_SETTID` and `CLEARTID` are covered. Both mremap copy paths (`src/rt32/vm_mmap.c:520,572`) are routed the same way. The fork protocol acquires VM, signal, SMC, then LL, matching the documented order. Probe T3 exists.

### M32-R3-5 — Real-time queue overflow silently loses signals: **PARTIAL**

`mips_signal_pend` (`src/os/sigqueue.c:881`) now returns `-EAGAIN` on a full RT queue without setting the pending bit, and the single caller in `mips_sc_kill` (`src/os/kill.c:222`) propagates `-EAGAIN`. That is correct Linux behavior for `tkill`, `tgkill`, and `rt_sigqueueinfo`.

It is not correct for plain `kill(2)` with `si_code == SI_USER`. In Linux `__send_signal_locked`, a queue-full RT signal with `SI_USER` takes the "silent loss of information" branch: the pending bit is still set and the call returns 0. Only non-`SI_USER` senders get `-EAGAIN`. After this commit, a guest calling `kill(getpid(), SIGRTMIN)` 65 times while blocked gets an `EAGAIN` that real kernels never return, and the 65th occurrence is not merged into the pending bit at all. The file already has `KILL_SI_USER` and `KILL_SI_TKILL` constants, so the distinction is cheap to make. Probe T4 exists but asserts the uniform `-EAGAIN`.

### M32-R3-6 — execve incorrectly clears inherited signal state: **VERIFIED**

`mips32_signals_reset_for_exec` (`src/os/signals.c:765`) now resets only entries that are installed and not `SIG_IGN`, and no longer touches `sig_blocked`, `sig_pending`, `sig_pending_code`, or `sig_rt_count`. Frame bookkeeping and the alternate stack are cleared. This matches Linux `flush_signal_handlers(force_default=0)` with one trivial difference: Linux also zeroes `sa_flags`, `sa_mask`, and `sa_restorer` on the `SIG_IGN` entries, whereas this keeps them. The only observable effect is a stale `oact.sa_flags` on a later `sigaction` query for an ignored signal. The fork child still clears its pending set, which is correct for fork. Probe T7 exists.

### M32-R3-7 — Signal delivery alters the interrupted stack pointer: **VERIFIED**

The register loop in `mips_raise_guest_code` stores `ctx->gpr[i]` unmodified for all 32 registers. Alignment is applied only to `newsp` (`src/os/signals.c:516`), which is the handler frame address. `rt_sigreturn` therefore restores the exact interrupted value. Probe T6 exists.

### M32-R3-8 — New errno regression test is disconnected from verification: **VERIFIED** (build unverified)

`make test` now compiles and runs `test_errno_map` and `test_r3_regress` (`Makefile:86..90`), with failures propagating through the `&&` chain, and `check` depends on `test`. The regression test supplies stubs for the syscall glue, default-disposition helpers, DBT invalidation, and host probe entry points, and links `vm.c`, `vm_init.c`, `vm_mmap.c`, `vm_darw.c`, `mem.c`, `signals.c`, `sigqueue.c`. I did not run the build, so I cannot confirm the link closes with no undefined symbols. `vm_darw.c` is compiled unconditionally but its host-specific logic is under `#ifdef __APPLE__`, so Linux `make test` should still compile it.

## Hygiene and invariants

- No `.c`, `.h`, or `.S` file exceeds 900 lines. The commit split `fork.c`, `sigqueue.c`, `vm_darw.c`, and `vm_init.c` out specifically to stay under the limit.
- No `#include "*.c"`. No `sprintf`, `strcpy`, or `strcat`. No `x18`/`w18` operands outside comments.
- `_GNU_SOURCE` is defined before any include in `vm_darw.c`; the new code is C11-clean by inspection.
- `vm_priv.h` grew exported `g_vm_gen`, `g_vm_brk_*`, the union helpers, fork stages, and `mips_guest_store_commit`. This widens the private header surface but does not touch the frozen headers.

## Cross-RT fork protocol (new in this commit)

`mips_proc_fork` (`src/os/fork.c:232`) quiesces VM, signal, SMC, and LL locks before `fork()`, releases them in both parent and child, and rebuilds the child's clone counter, LL reservation, and pending set. The weak-symbol stage hooks are fine for the standalone test harness. `fork_ret` now maps host errno through `mips_errno_from_host`, fixing a latent raw-errno leak on Darwin that the old `proc_ret` path had. No defect found.

## Summary

| Item | Title | Status |
|---|---|---|
| M32-R3-1 | brk publishes full VMA snapshot with generation | VERIFIED |
| M32-R3-2 | Darwin alias flush dirty-diff against file baseline | PARTIAL |
| M32-R3-3 | Host-page protection union on restore | VERIFIED |
| M32-R3-4 | Copyout and mremap through LL/SC-locked bulk store | VERIFIED |
| M32-R3-5 | RT queue overflow returns -EAGAIN | PARTIAL |
| M32-R3-6 | execve preserves mask, pending, ignored dispositions | VERIFIED |
| M32-R3-7 | Exact interrupted $sp in signal frame | VERIFIED |
| M32-R3-8 | errno and R3 regression tests wired into make test | VERIFIED |

## Newly discovered consequential follow-ups

1. **M32-R3-5 over-correction for `SI_USER`.** `mips_sc_kill` should distinguish `si_code`: on queue overflow with `KILL_SI_USER`, set the pending bit (merge) and return 0; return `-EAGAIN` only for `KILL_SI_TKILL` and queued-info senders. Adjust probe T4 accordingly.

2. **LL-lock-inside-VM-lock introduces a new wait-for edge.** Before this commit no VM-lock holder ever waited on the LL lock. Now `rt32_vm_copy_to` does. If a DBT inline LL/SC sequence or interp store faults while holding the LL lock, and the host fault handler enters `rt32_vm_sync_ctx` or `vm_lock_acquire` before `mips_ll_abandon` releases the LL lock, two threads can deadlock. I could not locate the fault handler within budget to confirm the ordering. Verify that `mips_ll_abandon` runs before any VM-lock acquisition in the SIGSEGV/SIGBUS path.

3. **No regression probe for M32-R3-2.** Add a two-alias probe: write through the higher-address alias, flush the inode, assert the lower alias and the file both carry the new bytes.

4. **Minor, M32-R3-6:** clear `flags`, `mask`, and `restorer` on `SIG_IGN` entries during exec reset to match `flush_signal_handlers`.

5. **Minor, M32-R3-3:** the Apple mprotect path at `src/rt32/vm_mmap.c:294..307` re-implements the union loop; route it through `vm_union_host_prot_locked` so a future change to the union rule cannot diverge.
