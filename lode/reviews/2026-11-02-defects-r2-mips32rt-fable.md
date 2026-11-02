# mips32rt — Round-2 Remediation Review

| Field | Value |
|---|---|
| Repository | `mips32rt` (`/Users/angerman/Projects/zw3rk/mips32rt`) |
| Commit reviewed | `d75013f2d858fb030cfe34ab987bb2dbc49d76d3` ("Fix Round-2 static audit defects (M32-R2-1..M32-R2-16)") |
| Baseline audit | `rt-series/lode/reviews/2026-11-02-defects-r2-mips32rt-astra.md` (audited `366ca9b`) |
| Reviewer | `claude-fable-5-1` |
| Date | 2026-11-02 |
| Overall Verdict | **NEEDS_FOLLOWUP** |

Evidence gathered: full `git show HEAD` diff, targeted reads of `src/os/mem.c`, `src/os/kill.c`, `src/os/syscalls.c`, `src/interp/interp.c`, `src/rt32/vm.c`, `src/rt32/vm_mmap.c`, `src/mips32rt.h`, `src/os/proc.c`; forced native rebuild (`make -B build-darwin`, exit 0 under `-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror`); `make check-line-limits` (ok); `make check-abi-invariants` (69 checks, 0 failures). Not run: the cross-compiled Linux build, the QEMU parity suite, and `--difftest`. Behavioural claims below are from static reading only.

---

## Section 1 — Per-Finding Verification

| ID | Title | Status | Technical Notes |
|---|---|---|---|
| M32-R2-1 | FP delay-slot fetch failure delivers the same fault twice | **VERIFIED** | `fp_bc1` and `fetch_decode` now re-raise only when `exit_reason == NONE && sig_depth == pre_depth && pc == pre_pc`. `guest_ld32` already calls `mips_fault` → `mips_trap` (mem.c:599/607/625), which on delivery bumps `sig_depth` and redirects `pc`, so the guard suppresses the second frame. Terminal faults keep `EXIT_FAULT`. `exec_branch` additionally rewinds `pc` to the branch on terminal slot faults (Linux EPC/BD shape); DBT parity for that terminal-PC shape was not re-run. No regression test was added as the audit requested. |
| M32-R2-2 | Darwin sub-page MAP_SHARED mappings are independent snapshots | **INCOMPLETE** (mitigated) | New `(dev, ino)` backing keys, `vm_flush_darw_inode_locked` before a new MAP_SHARED mapping, alias copy inside `vm_writeback_darw_locked`, and re-read after `write`/`writev`/`ftruncate`. Coherence is still only at sync points: two live sub-page aliases do not observe each other's stores until a flush, writeback still pushes the whole shadow span over the file (can clobber bytes written by another process), and the mapping is still advertised as MAP_SHARED rather than rejected. See also new finding N-2. |
| M32-R2-3 | Darwin writeback after mapping became inaccessible / replaced | **VERIFIED** | Writeback moved out of `vm_remove_region_at`/`vm_unmap_regions_locked` into `vm_flush_darw_range_locked`, called before `vm_reserve_prot_none` in `vm_munmap_locked`, before host `MAP_FIXED` in `vm_mmap2_ext_locked`, before brk shrink, and before exec reset. `vm_host_temp_prot` handles non-readable regions. `pwrite` errors now propagate through `msync`; `munmap`/`mmap` still discard them (`(void)`), which matches Linux `munmap` semantics. |
| M32-R2-4 | mprotect preflight disagrees with mutation | **VERIFIED** | Both `vm_can_mprotect_regions_locked` and `vm_mprotect_regions_locked` now skip `r->prot == prot`; both run coalesce-first under the same lock hold (`vm_mmap.c:374` preflight precedes host `mprotect`). Insert results are still ignored in the mutation, but preflight guarantees capacity. |
| M32-R2-5 | munmap reports success when metadata split fails | **VERIFIED** | New `vm_can_unmap_regions_locked` computes peak table occupancy (straddling region → +1) and `vm_munmap_locked` returns `-ENOMEM` before any host mutation. Same preflight on brk shrink. |
| M32-R2-6 | mmap can fail after replacing live memory | **VERIFIED** | Order is now: capacity preflight → `fcntl`/`fstat` → `F_DUPFD_CLOEXEC` → flush → host `mmap`/populate → record. Every post-dup failure closes the dup; record cannot fail after preflight. `O_WRONLY`/MAP_SHARED-write `EACCES` check now covers the aligned path too (previously unaligned-only). |
| M32-R2-7 | Pending delivery after sigreturn skips an unexecuted syscall | **VERIFIED** | Instruction-word probing removed. `sc_pc_advanced` is set to 1 by `dbt_main` (pre-advanced) and 0 by interp `exec_syscall`; `mips_sc_advance_pc_once` advances at most once; `mips_signal_deliver_pending` no longer touches `pc`, so the sigreturn path saves the restored PC unchanged. `mips_sc_clone` child PC derivation updated consistently. Interp returns `2` when `pc != before`, so no double advance. Low-severity edge noted in N-5. |
| M32-R2-8 | A2 private-file population writes through read-only mappings | **VERIFIED** | The post-`mmap` `mips32_file_populate_private` call is gone; population now happens only inside the Darwin unaligned branch after the explicit RW `mprotect`, before final protections. No A2 populate remains on the Linux `#else` path (A2 on Linux is not a supported regime here; unverified). |
| M32-R2-9 | Real-time pending signals coalesced | **VERIFIED** | 64-entry per-thread FIFO (`sig_rt_signo/sig_rt_code`), `l4a_pop_pending` preserves FIFO per signo and keeps the pending bit while more entries exist; standard 1..31 remain bit-coalesced. Queue cleared on clone, fork (correct: child starts with empty pending set), and exec. Overflow silently degrades to one coalesced delivery (bounded by design). `mips_signal_pend` has a single caller (`kill.c:217`, synchronous) so no new async race. |
| M32-R2-10 | errno translation handles only ENOSYS | **INCOMPLETE** | `mips_errno_from_host` now covers ~55 codes with correct MIPS values and is used by `mips_sc_ret`, `proc_ret`, and `syscall_min.c`. **Missing `ENAMETOOLONG`**: Linux host 36 passes through as MIPS 36 = `EIDRM`; Darwin host 63 passes through as MIPS 63 = `ENOSR`. MIPS value is 78. Also missing Darwin `ENOTSUP` (45 → MIPS `EDEADLK`). Rare Linux-only mismatches remain (`ENOTUNIQ`, `EBADFD`, `ENOMEDIUM`, `ERFKILL`, `EHWPOISON`). |
| M32-R2-11 | Interpreter headers not in `HDRS` | **VERIFIED** | `$(wildcard src/interp/*.h)` added to `HDRS`. Compiler dep-file generation was not added (the audit's weaker "at minimum" option was taken). |
| M32-R2-12 | Atomic generation counters do not protect root-context snapshots | **REGRESSION** | The data race is fixed: cross-thread writes to `g_vm_root_ctx` were removed from `vm_sync_to_ctx`/`vm_sync_brk_to_ctx`, `rt32_vm_copy_from/to` now validate against the global table under `g_vm_lock` via `vm_range_ok_locked`, and `vm_sync_brk_to_ctx` bumps the generation. **But** the new `rt32_vm_sync_ctx` fast path is `if (gen == 0 \|\| (ctx->vm_gen == gen && ctx->brk_base == 0U)) return;`. Every loaded process has `brk_base != 0`, so the generation cache never short-circuits: each call takes the spinlock and `memcpy`s the whole region table. `mips32_range_ok` (mips32rt.h:308) calls it unconditionally, and `mem.c:range_covered` routes every interpreter `guest_ld*/st*` check through it. Functionally safe, but a hot-path lock + bulk copy per guest access. Intended condition is almost certainly `ctx->vm_gen == gen`. Not benchmarked. |
| M32-R2-13 | Signal guest-memory access races with VM mutation | **VERIFIED** | `rt_sigaction`, `rt_sigprocmask`, `sigaltstack`, `mips_raise_guest_code` (full 776-byte frame), and `mips_rt_sigreturn` serialize to local buffers and use `mips_sc_copy_from/to` → `rt32_vm_copy_from/to` (validate + copy under one lock hold). Raw `l4a_put*/get*`, `memset(mips32_guest_ptr…)` removed. Sigtramp/altstack mapped-checks sync first. |
| M32-R2-14 | Duplicated guest arg/return helpers | **INCOMPLETE** (accepted residual) | `signals.c` and `syscall_min.c` now delegate to `mips_sc_arg/mips_sc_ret`. `proc.c` keeps `proc_ret`, `proc_arg`, `proc_ld32/st32`, `proc_swap32` plus `proc_copy_from/to` wrappers (weak-symbol fallback) so `tests/run_p5.sh` can compile `proc.c` standalone. Divergence is removed (endian-aware, lock-held), duplication is not. Low severity. |
| M32-R2-15 | Unused COW state constants | **VERIFIED** | `MIPS32_PAGE_ANON/COW_CLEAN/COW_DIRTY/SHARED/HAS_CODE/HAS_SW_RESERVATION` removed from `vm32.h`; no remaining references in `src/`, `tests/`, `include/`; build passes. |
| M32-R2-16 | File-backing comments claim nonexistent machinery | **VERIFIED** | `vm_file.c` header and function comments now describe populate/truncate/sysroot behaviour only. |
| X-R2-3 (cross-cutting) | `/proc/self` synthesis not wired | **VERIFIED** | `sc_openat` and `mips_sc_readlinkat` call `mips_proc_classify`; `mips_proc_open` returns fd or `-errno` (consistent with `mips_sc_ret`), `mips_proc_readlink` returns length or `-errno`, copied via `mips_sc_copy_to`. Constants moved to `syscalls_priv.h`. `close_cloexec_fds(keep_fd)` now runs before `rt32_elf_load` creates new `FD_CLOEXEC` backing dups (correct ordering fix). |

---

## Section 2 — Cross-Cutting & Hygiene Verification

| Check | Result |
|---|---|
| Unity includes (`#include "*.c"`) in `src/`, `include/`, `tests/` | None |
| File size ≤ 900 lines | `make check-line-limits` → ok. Largest: `emit_int.c` 899, `emit_fp.c` 897, `fp.c` 894, `proc.c` 891, `signals.c` 877 |
| C11 flag set | Native Darwin rebuild from clean objects with `-std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror=vla -Werror -pedantic` → exit 0, no diagnostics. Linux flag set in `Makefile:21` identical plus `-D_POSIX_C_SOURCE`. Cross-compile not executed this review |
| `x18` reserved | Only match in `src/` is the comment at `mips32rt.h:427` ("x18 is never touched"); no `x18`/`w18` operands in `.S` or emitters |
| No cross-repo library extraction | All changes are in-tree; `proc.c` uses weak symbols for harness isolation, not a shared library |
| ABI-locked offsets | `make check-abi-invariants` → 69 checks, 0 failures. New `mips32_ctx_t` fields appended after `sig_depth` |
| Lock discipline | All new VM helpers (`vm_can_unmap_regions_locked`, `vm_flush_darw_*`, `vm_writeback_darw_locked`, `rt32_vm_sync_shared_fd`) run under `g_vm_lock`; `rt32_vm_msync_shared` and `rt32_vm_sync_shared_fd` acquire it themselves |
| fd hygiene | Every post-dup failure path in `vm_mmap2_ext_locked` closes the `F_DUPFD_CLOEXEC` descriptor; `vm_maybe_close_fd_locked` unchanged |
| Test tooling | `parity_suite.sh`/`run_p5.sh` changes are cache/image reuse only; no assertions weakened |

---

## Section 3 — Remaining or Newly Introduced Consequential Findings

- **N-1 — High — REGRESSION — `rt32_vm_sync_ctx` fast path unreachable for any loaded process** (`src/rt32/vm.c:757-775`). `(ctx->vm_gen == gen && ctx->brk_base == 0U)` is false whenever `brk_base != 0`, so every `mips32_range_ok` call (interpreter `guest_ld*/st*` via `mem.c:range_covered`, every `mips_sc_range_ok`, every signal-path mapped check) takes the VM spinlock and copies up to 512 regions. Fix: drop the `brk_base` clause (brk is now covered by the generation bump in `vm_sync_brk_to_ctx`). Measure interp throughput before/after to confirm.

- **N-2 — Medium — BUG (Darwin only) — `rt32_vm_sync_shared_fd` discards unflushed shadow stores** (`src/rt32/vm_mmap.c:669-700`, called from `sc_write`, `sc_readv_writev`, `mips32_file_truncate_at`). After a host `write()`/`ftruncate()` it `memset`s and `pread`s every `darw_sync` region of that inode, overwriting guest stores made through the MAP_SHARED shadow that were never written back. Linux semantics make those stores visible in the file immediately. Fix: `vm_flush_darw_inode_locked(dev, ino)` *before* the host call, then re-read after.

- **N-3 — Medium — BUG — `ENAMETOOLONG` not translated** (`src/os/syscalls_priv.h:mips_errno_from_host`). Guest receives `EIDRM` (Linux host) or `ENOSR` (Darwin host) instead of 78. Also add Darwin `ENOTSUP` → 122. Add a focused test: `open()` on a 5 000-byte path must return `-78` in `$v0`.

- **N-4 — Medium — INCOMPLETE — Sub-page MAP_SHARED remains eventually consistent** (M32-R2-2 residual). Either document the limitation in `SPEC.md` and reject sub-page `MAP_SHARED` with `-EINVAL`, or implement a per-inode shared shadow page so aliases observe each other's stores without a flush.

- **N-5 — Low — DEFECT — `rt_sigprocmask` now advances PC unconditionally in the interpreter** (`src/os/signals.c:470`). Previously only a delivered handler advanced. If `syscall` sits in a branch delay slot, `exec_syscall` returns 2 and `exec_branch` (`rc == 2 → rc = 0`) returns without installing the branch target, so the branch is lost. Hand-written assembly only; same hazard already existed for `kill`. Consider deferring the advance to the delivery branch inside `mips_signal_deliver_pending` or making `exec_branch` honour the taken target when `rc == 2`.

- **N-6 — Low — unverified** — `rt32_vm_reset_for_exec` now re-reserves `[0x10000, 0xFFFE0000)` instead of the full window; harmless because `MIPS32_TASK_SIZE_TOP` is `0x7FFF8000`, and the old expression overflowed to a no-op on Darwin. `exec_branch`'s new terminal-fault PC rewind was not checked against DBT `--difftest`; run the parity suite before RC sign-off.
