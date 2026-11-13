# Round-3 Remediation Review: `sparc32rt` `7396a37` vs `b40924b`

Static review only. Five inspection turns, no build, test, Docker, or QEMU run. The commit's own claim of a clean curated C11 build and a 31/31 parity pass is reported, not reproduced.

Overall result: 6 of 10 items are verified, 3 are partial, and 1 introduced a regression. The regression is in the rewritten `tkill`/`tgkill` path and silently drops default-disposition signals sent to a live guest thread, which breaks musl `raise()` and `abort()`.

## Per-item verification

**S32-R3-1: context reclamation vs async handlers. VERIFIED.**
The host handler now only does an atomic `fetch_or` on `g_process_pending` in `sparc32_thr_note_signal` and never reads `thr_live[]`. `thr_drop_context` deregisters under `thr_live_lock` and then frees. Every remaining registry reader holds the lock across load and pending-bit update. One new hole in the same class sits in `thr_kill_tid`: the lock is released and then `target->host_tid` is dereferenced for the host `tgkill` wakeup. A target that reaches `thr_thread_finish` in that window has already been freed. See follow-up 2.

**S32-R3-2: coordinated fork. PARTIAL.**
`sparc32_thr_fork_prepare` takes `thr_live_lock`, then `g_dbt_lock` with runner drain, then the VM spinlock without a second drain. The child unlocks, destroys, and reinitialises all three, zeroes DBT runner counts and VM reader state, clears the registry, and re-registers only the survivor. This resolves the audited deadlocks. The commit also introduced two new process-wide mutexes, `sigact_lock` and `thr_fd_lock`, and neither is part of the fork protocol. A sibling inside `rt_sigaction` or `open` at fork time leaves the child with a permanently locked mutex. See follow-up 3.

**S32-R3-3: DBT generated-access quiescence. VERIFIED.**
`vm_lock_acquire` now calls `dbt_quiesce_begin`, which takes `g_dbt_lock`, sets `g_dbt_writer_waiting`, bumps the epoch so chained loops exit at block end, and waits for `g_dbt_active_runners` to reach zero. The lock is held across the whole mutation and released after the VM spinlock. I checked the deadlock hazard of a syscall dispatched while still a runner: `dbt_exec_enter` brackets only the trampoline with enter and leave, and `dbt_run` handles the syscall after return. The lock order `g_dbt_lock` then VM spinlock matches fork prepare. `vm_invalidate_jit` runs after release, so no re-entrant `g_dbt_lock` acquire was found.

**S32-R3-4: execve sibling retirement. PARTIAL.**
The VM replacement is now entirely under the writer lock in `rt32_vm_reset_for_exec` and old translations are retired. Sibling retirement is weaker than the commit message states:
- The clone thread loop in `thr_thread_entry` polls `sparc32_thr_is_retired` only at the top of the outer loop. The inner `interp_step` loop runs until a syscall or fault. A compute-bound sibling never observes the flag.
- Siblings blocked in a host syscall are not interrupted. The code admits this and relies on a 2 s bounded wait.
- `sparc32_thr_exec_retire_wait` clears `g_exec_retiring` after the wait. Leftover siblings therefore see "not retired" forever and keep executing their old PC against the new image, including issuing syscalls. This is the exact hazard the audit described.
- Every multithreaded exec with one blocked sibling now stalls for 2 s.
See follow-up 4.

**S32-R3-5: per-thread masks and altstacks. VERIFIED.**
`ctx->sig_mask` is the whole mask, all merge sites are gone, and `sparc32_l2a_set_blocked_mask` sanitises SIGKILL and SIGSTOP. Altstack state lives in `ctx->altstack_*`, which already existed in the frozen header, so no header change was needed. Delivery, `sigaltstack`, and `sigreturn` all use the context variants. Clone copies the mask via struct copy and zeroes the altstack. Exec zeroes both. The legacy stubs have zero remaining callers. Minor: `syscalls_min.h` says exec leaves the mask and pending queues untouched, while `threads_exec.c` clears both. Linux preserves the blocked mask across exec. That deviation predates this commit.

**S32-R3-6: SIG_IGN handling. VERIFIED.**
Dispositions are a three-state `kind`. `sig_host_sync` mirrors each state to the host, so fatal defaults are applied by the kernel and ignored signals never reach a handler. Installing `SIG_IGN` discards queued bits in both queues. `oact` reports handler 1 for ignored. `sparc32_signal_reset_for_exec` keeps ignored dispositions, matching POSIX. The re-raise dance is gone.

**S32-R3-7: signal recipient routing. REGRESSION.**
The claim design is sound: thread bits first, then a CAS single-winner claim on the process word with echo attribution through `sparc32_thr_thread_has_pending`. The `kill(2)` path is correct because it performs the host `kill` before `thr_kill_self`. The `tkill`/`tgkill` path is not. In `thr_kill_tid`, when the target is a live guest thread and the disposition is default, no host syscall is issued at all. For a self-target, `thr_kill_self` sets the process bit, and the next poll claims it, finds no handler, and drops it. Consequences:
- musl `raise()` uses `tkill(gettid(), sig)`, so `raise(SIGTERM)` returns 0 and nothing happens. `abort()` no longer exits with SIGABRT.
- `tkill(self, SIGKILL)` is swallowed.
- `pthread_kill(other, SIGTERM)` with default disposition is lost.
Before this commit the host `tgkill` ran unconditionally. The only test touching `raise` uses `SIGUSR1` with a handler, so the parity suite could not catch this. A narrower duplicate-delivery window also remains for thread-directed caught signals. See follow-ups 1 and 5.

**S32-R3-8: coherent sigaction snapshots. VERIFIED.**
All reads and writes of `sigact[]` are under `sigact_lock`, and the host handler no longer consults the table, so no async-signal-safety requirement remains. No host fault handler reaches `sparc32_signal_get`: `interp_try_deliver_sync` is called only from `main.c`, `difftest.c`, and `thr_thread_entry` in normal context. Lock order `thr_live_lock` then `sigact_lock` in `thr_kill_tid` has no reverse path. The fork gap is covered under S32-R3-2.

**S32-R3-9: close-on-exec. PARTIAL.**
`threads_fd.c` tracks open, openat, creat, dup, dup2, `F_DUPFD`, `F_SETFD`, pipe, and pipe2, and `sparc32_fd_cloexec_sweep` runs before the image is replaced. Plan and backing fds stay untracked, as intended. Gaps:
- `dup2(fd, fd)` clears the tracked CLOEXEC flag. Linux keeps it when old equals new.
- Inherited descriptors, including 0, 1, and 2, are never tracked, so a guest `fcntl(fd, F_SETFD, FD_CLOEXEC)` on them is ignored at exec.
- dup3, accept, socketpair, eventfd, and epoll_create are not dispatched today, so no leak there yet. They will need a note call when added.

**S32-R3-10: ELF span DRY. VERIFIED.**
`load_elf32_image` now emits the validated `[page_start, map_end)` span per PT_LOAD into `rt32_elf_plan_t`, and the overlap check in `rt32_elf_prepare` consumes it. `elf_collect_spans` is deleted. `RT32_ELF_MAX_SPANS` matches the 64-entry phdr array.

**Curated C11 and repository invariants.**
No `#include "*.c"` anywhere. Largest files: `vm.c` 883, `syscalls.c` 881, `threads.c` 861, `fp_arith.c` 861 lines. `x18` appears only in comments. `<stdatomic.h>` and `_Atomic` are permitted C11. One latent defect: `sparc32_thr_sigbit` in `src/os/threads.h:29` is a `static inline` placed before the include guard at line 38 and before `<stdint.h>` is included. It compiles today only because no translation unit includes the header twice.

## Summary

| Item | Topic | Status |
|---|---|---|
| S32-R3-1 | Context reclamation vs async handlers | VERIFIED |
| S32-R3-2 | Coordinated fork | PARTIAL |
| S32-R3-3 | DBT access quiescence | VERIFIED |
| S32-R3-4 | Exec sibling retirement | PARTIAL |
| S32-R3-5 | Per-thread masks and altstacks | VERIFIED |
| S32-R3-6 | SIG_IGN handling | VERIFIED |
| S32-R3-7 | Signal recipient routing | REGRESSION |
| S32-R3-8 | Coherent sigaction snapshots | VERIFIED |
| S32-R3-9 | Close-on-exec | PARTIAL |
| S32-R3-10 | ELF span DRY | VERIFIED |

## Newly discovered consequential follow-ups

1. **High. Default-disposition tkill/tgkill to a live guest thread is dropped.** In `thr_kill_tid` in `src/os/threads.c`, when `target != NULL` and the kind is `SPARC32_SIG_DISP_DFL`, issue the host `tgkill` to `target->host_tid` so the kernel applies the default. Do this for the self case too, before `thr_kill_self`. Add a parity test for `abort()` exit status 134 and `raise(SIGTERM)`.

2. **Medium. Use-after-free read of `target->host_tid` in `thr_kill_tid`.** Copy `host_tid` into a local while `thr_live_lock` is held and use the local after unlock.

3. **Medium. Fork protocol omits `sigact_lock` and `thr_fd_lock`.** Acquire both in `sparc32_thr_fork_prepare` after `thr_live_lock`, release in `sparc32_thr_fork_parent`, and unlock, destroy, and reinit in `sparc32_thr_fork_child`. Lock order stays `thr_live_lock`, `sigact_lock`, `thr_fd_lock`, `g_dbt_lock`, VM spinlock.

4. **Medium. Exec retirement does not reach compute-bound or blocked siblings.** Poll `sparc32_thr_is_retired` inside the inner `interp_step` loop of `thr_thread_entry`. Mark retirement per context under `thr_live_lock` instead of clearing a global flag after the wait. Interrupt siblings in host blocking calls with a dedicated host signal installed without `SA_RESTART`. Replace the fixed 2 s sleep loop with a condition wait on deregistration.

5. **Low. Duplicate delivery window for thread-directed caught signals.** The wakeup reuses the guest signal number, so the host echo can land after the target already consumed the echo slot. Use a dedicated internal wakeup signal whose handler is a no-op and which never maps to a guest bit.

6. **Low. FD table edge cases.** Preserve CLOEXEC when `dup2` old equals new. Register fds 0 to 2 as guest-owned at startup so `F_SETFD` on them is honoured.

7. **Low. Header and dead-code hygiene.** Move `sparc32_thr_sigbit` inside the include guard after `<stdint.h>`. Remove the inert `sparc32_l2a_blocked_mask`, `sparc32_sigaltstack_state`, and `sparc32_sigaltstack_set_onstack` stubs. Align the `sparc32_signal_reset_for_exec` comment in `syscalls_min.h` with what `threads_exec.c` actually clears.
