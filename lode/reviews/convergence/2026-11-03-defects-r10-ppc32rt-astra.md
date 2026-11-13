# Round-10 Static Audit: Threading / `clone` / `fork` / `execve` / Futex

**Scope:** `src/os/threads.c`, `src/os/proc.c`, `src/os/futex_ulock.c`, `src/os/signals.c`, `src/os/syscalls.c`, `src/os/backend_*.c`, `src/rt32/ppc32_vm.c`, `src/rt32/ppc32_elf32.c`, `src/dbt/cache.c`, `src/main.c`. Read-only; no builds, no tests, no subagents.

## Summary

| ID | Severity | Location | Finding |
|----|----------|----------|---------|
| P32-R10-1 | High | [threads.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:378) | `FUTEX_WAIT_BITSET` (op 9) rejected with `-ENOSYS`; NPTL bitset waits cannot work |
| P32-R10-2 | High | [proc.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:348) | `execve` never quiesces or collapses sibling threads; stale table hangs later `exit` |
| P32-R10-3 | High | [proc.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:348) | `execve` never closes `O_CLOEXEC` fds; they leak into the new image |
| P32-R10-4 | High | [ppc32_vm.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:181) | `execve` path never invalidates the DBT translation cache; stale host code can execute |
| P32-R10-5 | Medium | [threads.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:566) | `CHILD_CLEARTID` validated with read prot (`1U`) but the exit path writes it |
| P32-R10-6 | Medium | [syscalls.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:701) | Fork-style `clone` (no `CLONE_VM`) validates TID addresses only after `fork()` |
| P32-R10-7 | High | [threads.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:84) | `clone`-reap vs `thread_join` race: double `pthread_join` + double `free` |

## Verified clean (no finding)

`r2` TLS (`threads.c:595`, `TP=2`), child `r3=0, CR0.SO=0` (`threads.c:589`), BE `clear_child_tid` zero-store + `FUTEX_WAKE` (`threads.c:699`), `atfork` order sig→thread→cache→VM→TLB→file→LL with exact reverse release (`proc.c:124`), `lwarx/stwcx` clearing on every entry point, single-threaded child reset (mask/altstack inherited, pending/robust/TID cleared), `tgkill`/`tkill` pend+nudge+pump chain, and `execve` signal-disposition reset (`CAUGHT→DFL`, `IGN` preserved).

## Findings

**P32-R10-1 — `FUTEX_WAIT_BITSET` unsupported.** The gate at `threads.c:378` accepts only `WAIT/WAKE/REQUEUE/CMP_REQUEUE`; op 9 (`FUTEX_WAIT_BITSET`, `137` with `PRIVATE_FLAG`) falls to `-ENOSYS`. Repro: any threaded guest libc issuing `futex(uaddr, 137, val, abs_timeout, 0, bitset)` (standard NPTL mutex/condvar wait) gets `-38` instead of blocking. Fix: accept cmd `9`, require `val3 (bitset) != 0` else `-EINVAL`, pass `val3` through **unswapped** (it is a mask, not a memory comparand) to the host `futex` with the absolute timeout; extend the Darwin emul wait path likewise.

**P32-R10-2 — `execve` ignores siblings.** `ppc32_proc_execve` (`proc.c:348`) contains zero thread-table handling (confirmed by search: only fork-path lines reference threads). Repro: two live threads, one calls `execve` — the sibling keeps running while `ppc32_vm_reset_for_exec` unmaps the shared window (`ppc32_vm.c:203`), and the stale table keeps `ppc32_thread_count() > 1`, so a later plain `exit` spins forever in `main.c:508`. Fix: before `ppc32_vm_reset_for_exec`, if `ppc32_thread_count() > 1`, terminate/join siblings (or reject), collapse the table to the caller, and set `is_thread_clone = false`.

**P32-R10-3 — `execve` leaks `FD_CLOEXEC` fds.** Guest fds are identity-mapped host fds, and the translator's `execve` is image replacement, not host `execve`, so host close-on-exec never fires; `ppc32_proc_execve` closes only its probe fd. Repro: `open(path, O_CLOEXEC)` then `execve` — the fd remains usable in the new image. Fix: walk open fds and `close()` those with `FD_CLOEXEC` set before loading the new image.

**P32-R10-4 — `execve` leaves stale DBT blocks.** `ppc32_vm_reset_for_exec` invalidates the TLB and bumps the LL generation but never touches `g_cache_epoch`; `ppc32_elf_load` writes segments via raw `pread` into the guest window (`ppc32_elf32.c:557`), bypassing both `vm_invalidate_jit` and `vm32_store_invalidate_range`. Block validity is epoch-gated (`cache.c:66`), and nothing on the exec path bumps it. Repro (`--dbt`): execute guest A (caches block at VA X), `execve` guest B with different code at the same VA X — the stale cached block executes. Fix: one `ppc32_cache_invalidate_all(ctx)` after `ppc32_vm_reset_for_exec` (`dbt/dbt.h` is already included by `proc.c`).

**P32-R10-5 — `CHILD_CLEARTID` under-validated.** `PARENT_SETTID` and `CHILD_SETTID` require write prot (`2U`, lines 557, 562), but `CHILD_CLEARTID` requires only read (`1U`, line 566) although the exit path writes it. Repro: read-only `ctid` page → `clone` succeeds → `thread_exit`'s store fails silently → no zero, no `FUTEX_WAKE` → ctid waiter hangs. Fix: `1U` → `2U` on line 566.

**P32-R10-6 — fork-style `clone` validates after the side effect.** The no-`CLONE_VM` path forks first (`syscalls.c:708`), then range-checks `parent_tid`/`child_tid` and silently skips bad stores (lines 714–724), while the `CLONE_VM` path validates up front and returns `-EFAULT` (`threads.c:557`). Repro: `clone(SIGCHLD|CHILD_SETTID, bad_addr)` creates a child and returns its pid instead of `-EFAULT` with no child. Fix: validate both addresses with write-prot `ppc32_vm_range_prot_ok` before `ppc32_proc_fork`.

**P32-R10-7 — clone-reap vs join double-free.** `thread_claim_locked` zeroes an exited slot under lock, then unlocks to `pthread_join`/`free` (`threads.c:84`); `ppc32_thread_join` copies the handle, unlocks to join, then unconditionally `free`s (`threads.c:647`). Interleaving: joiner copies `(H,C)` and blocks in `pthread_join`; a concurrent `clone` reaps the same slot, joins `H`, frees `C`; the joiner then re-joins `H` (UB) and frees `C` again (its second lookup finds nothing, but the `free` is unconditional, line 685). Fix: detach the slot under the first lock in `thread_join` (or add a joining mark the reaper skips).

