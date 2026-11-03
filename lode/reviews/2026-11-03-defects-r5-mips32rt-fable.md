# Round-5 Post-Remediation Verification — `mips32rt` @ `0d5e3b1`

**Scope:** static verification of commit `0d5e3b1` ("mips32rt: remediate Round-5 defects (M32-R5-1..11)") against `lode/reviews/2026-11-03-defects-r5-mips32rt-astra.md`. Four tool turns used (defect list, `git show --stat`/full diff/`wc -l`, one call-site grep pass). No builds, tests, containers, or QEMU were run. Line numbers below are post-commit.

## Summary

| Item | Severity | Verdict | One-line reason |
|---|---|---|---|
| M32-R5-1 | High | **VERIFIED** (caveat) | `dbt_compile` returns the single-step code under regime A2 before any block is emitted. AOT install path not inspected. |
| M32-R5-2 | High | **PARTIAL** | WAIT / WAIT_BITSET / CMP_REQUEUE values are byte-swapped correctly. The new BE `FUTEX_WAKE_OP` emulation has wrong wake gating (see new finding N-1). |
| M32-R5-3 | High | **VERIFIED** | Arg 4 (`to_va`) is forwarded as the count for REQUEUE / CMP_REQUEUE / WAKE_OP. |
| M32-R5-4 | High | **REGRESSION** | Leak is fixed by a tkill-probe reaper, but the record is published to the reap list before the parent's handshake reads it, creating a use-after-free window (new finding N-2). |
| M32-R5-5 | High | **PARTIAL** | Robust-list walk exists but does not terminate on the circular sentinel; it relies on the 2048 bound and re-visits entries (new finding N-3). |
| M32-R5-6 | High | **VERIFIED** (caveat) | `read`/`readv` stage into host buffers and commit via `rt32_vm_copy_to`. Epoch bump inside `rt32_vm_copy_to` not re-confirmed within budget. |
| M32-R5-7 | High | **VERIFIED** | Flush/sync return `int`; sync stages with EINTR/short-read loop and only commits on success. |
| M32-R5-8 | Medium | **VERIFIED** | Reserved same-format CVT.S/CVT.D now trap with the file's reserved-encoding code before writeback. No regression test added. |
| M32-R5-9 | High (validation) | **VERIFIED** | Exit ≥ 124, non-numeric exit, and empty trace/regs now fail. Explicit expected-exit configuration not added. |
| M32-R5-10 | Low | **PARTIAL** | `host_stack` now consumed. `mips_live_clones` still has no reader, and a new write-only TLS `mips_self` was added. |
| M32-R5-11 | Low | **PARTIAL** | 64-bit pair assembly extracted; the signed-32 validation branch and arg fetch remain duplicated in both variants. |

Cross-cutting: the commit adds **no tests** although items 2, 3, 4, 5, and 8 each asked for one. All claims below are from reading the diff; nothing was executed.

## Per-item evidence

### M32-R5-1 — DBT bypasses subpage permissions on A2 hosts — VERIFIED (caveat)
- `src/dbt/dbt.c:654-656`: `if (ctx->vm_regime == MIPS32_VM_REGIME_A2) return 1;` placed after `dbt_cache_ensure` and before the SPEC 2.2 page-end check at `dbt.c:659-660`, which uses the same `return 1` single-step convention. The caller at `dbt.c:801` consumes that code. Because no block is ever compiled under A2, the code cache stays empty and the trampoline's `[xG,wAddr,uxtw]` accesses are never reached.
- `src/vm/vm32.h:87` defines `MIPS32_VM_REGIME_A2`; regime is derived from host page size at init, so the gate is static for the process lifetime.
- Caveat: `grep vm_regime src/dbt/aot*.c` returned nothing. If an AOT cache can install blocks without passing through `dbt_compile`, that path is ungated. Not confirmed either way.
- Consequence: A2 hosts (Darwin 16 KiB pages) run interpreter-only. This is correct but is a large performance regression on the primary macOS target; it should be recorded as a known limitation.

### M32-R5-2 — BE futex comparisons — PARTIAL
- `src/os/threads.c:735-738` (FUTEX_WAIT) and `:740-747` (WAIT_BITSET): `hv = be ? __builtin_bswap32(val) : val` is passed to the host. Correct.
- `src/os/threads.c:779-781`: `hv3` is swapped only when `base_op == MIPS_FUTEX_CMP_REQUEUE && be`. Correct (plain REQUEUE ignores val3).
- `src/os/threads.c:796-797`: BE WAKE_OP routes to `futex_wake_op_be` (`threads.c:584-650`). The CAS loop with `__builtin_bswap32` is atomic against host waiters and correct for the arithmetic. **The wake gating is wrong** — see N-1.
- No raw BE futex test with a non-byte-symmetric value was added.

### M32-R5-3 — Requeue/wake-op discard argument four — VERIFIED
- `src/os/threads.c:689`: `to_va = mips_sc_arg(ctx, sp, 3, &ok);` (raw, no pointer validation).
- Timeout-pointer validation is confined to the WAIT branch at `threads.c:720-721`.
- `threads.c:778` (`nr`), `:797` (`to_va` → `n2`), `:799` (`nr2`) forward it as the integer count. Correct.

### M32-R5-4 — Thread resources never reclaimed — REGRESSION
- Fix: `struct mips_thread.next` (`threads.c:128`), reaper list under `mips_reap_lock` (`threads.c:164-166`), `mips_reap_done()` at `threads.c:168-200` probes `tkill(tid, 0)` and on `ESRCH` unlinks, `munmap`s the 2 MiB stack and `free`s the record. Called from `mips_sc_clone` at `threads.c:429`. The leak is addressed.
- Rollback on `pthread_create` failure unlinks and decrements (`threads.c:527-548`).
- **Regression:** the record is linked into the reap list at `threads.c:510-513` *before* `pthread_create`, and the parent then dereferences `t` after the child may already have exited: `t->started` spin at `:551-554`, `t->child_tid` at `:556-557`, `t->set_ctid` / `t->parent_settid` at `:563-564`. See N-2.
- Residual (benign): TID reuse before the next clone makes the probe miss (record leaks, no UAF). Reaping happens only on the next `clone`, so a program that spawns N threads and never spawns again retains all N records; bounded, acceptable.

### M32-R5-5 — Robust-list registration without owner-death processing — PARTIAL
- `mips_robust_wake()` at `threads.c:206-259`, invoked first in `mips_thread_finish` at `threads.c:319`. Reads the 12-byte O32 head with `mips_sc_copy_from`, BE-aware loads, bounded by `MIPS_ROBUST_LIST_LIMIT 2048`, sets `OWNER_DIED` and wakes one waiter when `WAITERS` is set. Faults are tolerated (checked copies).
- **Defect:** the loop at `threads.c:228-258` terminates only on `cur == 0` or the limit. Linux robust lists are circular and terminate when `entry == &head->list` (that is, `cur == ctx->robust_list_head`). See N-3.
- Minor: the PI low bit of entry pointers is not masked; `list_op_pending` is only visited when the limit is hit (which, given N-3, is always); the kernel's `entry != pending` de-dup is absent.
- No "thread exits holding a robust mutex" test added.

### M32-R5-6 — read/readv epoch window — VERIFIED (caveat)
- `src/os/syscall_min.c:155-171`: `sc_read` mallocs a host staging buffer, `read`s into it, and commits with `rt32_vm_copy_to` at `:166`; frees on every path; `count == 0` short-circuits at `:147-149`.
- `src/os/syscalls.c:650-659`: `readv` legs allocate per-iovec `tmps[i]`; writes stay direct. Commit loop at `:683-695` copies in iovec order and respects partial transfer (`rem`). All `tmps` freed on every exit path (`:631-636`, `:642-647`, `:653-658`, `:669-674`, `:696-699`, `:704-707`).
- Caveat: the grep for the body of `rt32_vm_copy_to` returned nothing within budget, so the claim that it takes the LL lock and advances epochs (the whole point) is inferred from the Round-4 N-0..N-2 commit, not re-read here.
- Perf note (do not act without measuring): one `malloc`/`free` per `read` syscall is new overhead on the hot I/O path.

### M32-R5-7 — Darwin sync suppresses errors / zeroes mappings — VERIFIED
- `src/rt32/rt32.h:58-59`: both functions now return `int`.
- `src/rt32/vm_mmap.c:665-684`: flush returns `-EBADF`, `-errno`, or the `vm_flush_darw_inode_locked` result (that helper already returned `int`, see `vm_mmap.c:146`).
- `src/rt32/vm_mmap.c:686-752`: sync stages into a zeroed `malloc` buffer, `pread` loop retries `EINTR` and short reads (`:721-735`), breaks on error without touching the mapping (`:737-740`), then `memcpy`s and restores protection (`:744-748`). Only the verified beyond-EOF tail stays zero.
- Callers propagate: `syscall_min.c:198-201` / `:208-211` (write), `syscalls.c:667-674` / `:713-716` (writev), `vm_file.c:86-97` (truncate).
- Note: a sync failure after a successful `write` returns an error to the guest even though bytes hit the file. Defensible, but it is a visible semantic choice and should be documented.
- Not verified: whether any other caller of flush/sync remains unchecked (my grep for that errored on a zsh glob and I had no turn left).

### M32-R5-8 — Reserved FP conversions use uninitialized `v` — VERIFIED
- `src/interp/fp.c:751-759`: function 32 with `f == 0` and function 33 with `f != 0` now call `mips_trap(ctx, 4, pc)` and return `MIPS_FAULT` before any `fp_write_*`. Code 4 is the file's reserved-encoding convention (`fp.c:699`, `:771`, `:792`, `:870`).
- No raw-instruction regression test was added.

### M32-R5-9 — Difftest certifies two failed launches — VERIFIED
- `tests/difftest/run_difftest.sh:83-98`: per leg, non-numeric exit, exit ≥ 124, empty `.trace`, and empty `.regs` all call `fail` (defined at `:27`).
- Residual: no explicit "expected guest exit" configuration; two legs that both exit with a matching code < 124 *and* produce non-empty traces still pass, which is the intended behaviour but leaves intentional-nonzero cases unexpressed.

### M32-R5-10 — Lifecycle bookkeeping without consumer — PARTIAL
- `host_stack` is now read at `threads.c:192` (reaper `munmap`). The live count is incremented before startup at `:508` with rollback at `:544`. Comments at `:160-163` and `:311-313` now describe machinery that exists.
- Still write-only: `mips_live_clones` is only stored at `threads.c:267, 303, 322, 508, 544`; no read anywhere in `src/os/*.c`.
- New write-only state: `static __thread struct mips_thread *mips_self` (`threads.c:166`) is assigned at `:352` and never read.

### M32-R5-11 — Truncate length decoding duplicated — PARTIAL
- `src/vm/vm_file.c:78-82`: `o32_trunc64_len()` shared by both variants (`:138`, `:177`).
- The signed-32 (`len32`) validation branch and the a2/a3 fetch + `!ok` check remain duplicated in both call sites. Astra asked for a decoder "returning a validated length or error". Low priority.

## New findings introduced by `0d5e3b1`

**N-1 — BE `FUTEX_WAKE_OP` emulation wakes the wrong sets (High).** `src/os/threads.c:633` gates the uaddr1 wake on `mo` (cmp of the *old* value) and `:642` gates the uaddr2 wake on `mn` (cmp of the *new* value). Linux `futex_wake_op` wakes up to `nr_wake` waiters on uaddr1 **unconditionally** and wakes up to `nr_wake2` on uaddr2 **iff** `cmp(oldval, cmparg)`. Failure scenario: glibc's legacy `pthread_cond_broadcast` issues `FUTEX_OP(SET, 0, CMP_GT, 1)`; with an uncontended mutex (`old == 1`) the emulation computes `mo = 0` and never wakes the condvar waiter, which hangs. Also `FUTEX_OP_OPARG_SHIFT` (`op & 8`) is rejected with `EINVAL` instead of applying `1 << oparg`. The epoch bump at `:620` happens after the CAS, the same post-hoc pattern astra flagged in R5-6.

**N-2 — Use-after-free window in `mips_sc_clone` (High).** Record `t` is pushed onto `mips_reap_head` at `threads.c:510-513` before `pthread_create`. If the child starts, publishes its tid, runs, and exits via raw `SYS_exit` while the parent is still between `:551` and `:564`, any *other* guest thread entering `clone` runs `mips_reap_done()` (`:429`), sees `tkill` → `ESRCH`, and `free(t)` + `munmap(stack)`. The parent then reads `t->started`, `t->child_tid`, `t->set_ctid`, `t->parent_settid` from freed memory. Fix direction: link the record into the reap list only after the handshake completes, or hold a "parent still observing" flag that the reaper honours.

**N-3 — Robust-list walk never sees the circular terminator (Medium).** `threads.c:228-258` must stop when `cur == ctx->robust_list_head`; it does not, so even an empty list (head self-pointing) runs 2048 iterations, and each pass evaluates the word at `head + futex_off` inside the dying thread's descriptor as if it were a mutex. With a negative `futex_off` (glibc and musl both use one) and a descriptor field whose low 30 bits happen to equal the tid, the code ORs `OWNER_DIED` into that descriptor field. With one real robust mutex it is marked ~1024 times and, if `WAITERS` is set, issues ~1024 spurious `FUTEX_WAKE`s on each thread exit.

## Curated C11 and line-limit hygiene

| File | Lines | Note |
|---|---|---|
| `src/os/syscalls.c` | 900 | At the limit. The 35-line provenance header (unistd_o32.h citations, O32 convention, Phase-4 notes) was deleted to fit. Information loss; consider moving it to a `.h` or doc rather than dropping it. |
| `src/interp/fp.c` | 898 | At the limit. |
| `src/dbt/dbt.c` | 894 | At the limit. |
| `src/os/threads.c` | 845 | OK (+253 lines; next split candidate: futex handling). |
| `src/rt32/vm_mmap.c` | 758 | OK |
| `src/os/syscall_min.c` | 524 | OK |
| `src/vm/vm_file.c` | 220 | OK |
| `src/rt32/rt32.h` | 96 | OK |
| `tests/difftest/run_difftest.sh` | 137 | OK |

All touched files are ≤ 900 lines. No VLAs, Annex K, `<threads.h>`, `_Generic`, `sprintf`/`strcpy`/`strcat` introduced. Deviations worth a follow-up:
- `__thread` at `threads.c:166` is a GNU keyword; Curated C11 spelling is `_Thread_local`.
- `__atomic_load_n` / `__atomic_compare_exchange_n` at `threads.c:600`, `:614` are GCC builtins. They are the pragmatic choice for a non-`_Atomic` guest word, but they should be noted as a deliberate exception (as `__builtin_bswap32` presumably already is).
- `(int32_t)(val3 >> 12 & 0xFFFU)` at `threads.c:588` is correct by precedence but reads as a bug; parenthesize.

## Recommended Round-6 actions, in priority order
1. Fix N-2 (reap-list publication ordering) — memory safety.
2. Fix N-1 (WAKE_OP gating + OPARG_SHIFT) — lost wakeups on BE guests.
3. Fix N-3 (robust-list terminator, PI bit, pending de-dup).
4. Add the tests astra requested for R5-2/3/4/5/8; the commit shipped none.
5. Confirm AOT install is gated by `vm_regime` (R5-1 caveat) and that `rt32_vm_copy_to` advances LL/SC epochs (R5-6 caveat).
6. Either consume `mips_live_clones` / `mips_self` or delete them (R5-10).
