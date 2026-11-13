# Round-10 Deep-Dive 4 Static Audit: Threading, `clone`/`fork`/`vfork`/`execve`, Family Coordination, Scheduler, Futex

**Verdict: 0 defects found.** The subsystem has converged; no concrete, demonstrable behavioral bug was found in scope. No files were modified and no builds or tests were run.

## Coverage

| Area | Key files audited | Result |
|---|---|---|
| `clone`/`fork`/`vfork` flags, `tp`, TID stores, slot lifetime | `src/linux/thread.c:20-46`, `src/linux/process.c:14-42`, `src/runtime/runtime_main_syscall_leaf.c:146-232`, `src/runtime/runtime_main_fork_spawn.c:353-779`, `src/runtime/runtime_main_syscall.c:37-57` | 0 defects |
| Same-PID `execve`, `--image-fd`, `O_CLOEXEC`, signal reset | `src/runtime/exec_launch.c:89-255`, `src/runtime/runtime_main_fork_spawn.c:8-299`, `src/runtime/runtime_main_startup.c:440-541`, `src/runtime/runtime_main_startup.c:654-720`, `src/linux/fd_handoff.c:58-86`, `src/linux/fd_handoff.c:226-268`, `src/linux/signal_exec.c:64-142` | 0 defects |
| `futex`, FIFO turn scheduler, `tgkill` quiescence, lock ordering, `atfork` | `src/linux/futex.c:54-487`, `src/linux/futex_internal.h:89-350`, `src/linux/futex_key.c:54-159`, `src/runtime/scheduler.c:14-680`, `src/runtime/scheduler_internal.h:58-432`, `src/runtime/quiescence.c:10-101`, `src/linux/signal.c:614-649` | 0 defects |
| Family `mm`/`shmem`/`file`, `rv_file_caps` SCM broker | `src/runtime/family_lifecycle.c:9-199`, `src/runtime/family_lifecycle.c:246-552`, `src/runtime/family_wait.c:81-198`, `src/runtime/family_mm.c`, `src/runtime/family_shmem.c:97-204`, `src/runtime/exec_tid.c:163-516`, `src/runtime/vfork_completion.c:24-204` | 0 defects |

## Why each hot spot holds

- **Flag validation:** thread `clone` requires the full mandatory set (`src/linux/thread.c:25-35`); process `fork`/`clone` accepts only `SIGCHLD|VM|VFORK|SETTID/CLEARTID` (`src/linux/process.c:20-28`). `CLONE_THREAD` without the thread set, and thread flags on the process path, are rejected. Narrow scope is documented intent, not a behavioral defect.
- **TLS:** `child->cpu.x[4] = request.tls` only under `CLONE_SETTLS` (`src/runtime/runtime_main_syscall_leaf.c:177-178`); `x[2]` only when a stack is given; reservation cleared. Fork child likewise honors `child_stack` (`src/runtime/runtime_main_fork_spawn.c:640-646`).
- **`set_tid`/`clear_tid`:** parent and child stores are best-effort under the guard with `internal_failure` escalation (`src/runtime/runtime_main_syscall_leaf.c:220-225`, `src/runtime/runtime_main_fork_spawn.c:538-542`, `src/runtime/runtime_main_fork_spawn.c:699-703`); exit clears via `rv_linux_futex_clear_tid` plus a 1-waiter `FUTEX_WAKE` (`src/linux/futex.c:441-476`, `src/runtime/runtime_main_syscall.c:41-46`).
- **`vfork` unblock:** `CLONE_VM` child sends `JOIN` (`src/runtime/runtime_main_fork_spawn.c:741-752`); post-`exec` child sends `E` and closes (`src/runtime/runtime_main_startup.c:523-531`); plain exit resolves via close/`EOF` to the `vfork_exit` branch (`src/runtime/runtime_main_fork_spawn.c:310-350`, `src/runtime/vfork_completion.c:74-133`). No orphaned waiter.
- **`execve` handoff:** capability distinctness, `runtime_fd` ELF validation, and `CLOEXEC` activate/restore pairing (`src/runtime/exec_launch.c:97-180`); `filter_cloexec` drops only `guest_cloexec` entries while retaining descriptions shared with surviving fds, and decode rejects any surviving `CLOEXEC` record (`src/linux/fd_handoff.c:58-86`, `src/linux/fd_handoff.c:334-342`); resume validates `old_mm_root`/service/`VFORK` coherence (`src/runtime/runtime_main_startup.c:684-698`, `src/runtime/exec_state.c:226-247`).
- **Signal reset:** capture records only ignored mask plus blocked/pending with `siginfo` (`src/linux/signal_exec.c:64-100`); restore zeroes caught handlers, preserves ignored set and blocked mask, disables altstack (`src/linux/signal_exec.c:114-141`).
- **Futex atomicity:** value check, enqueue, `WAKE`/`REQUEUE`/`WAKE_OP` all execute under the held family guard; the waiter commits its shared row before parking and rescues a pre-park wake via the `woken` flag plus a self `scheduler_wake` (`src/runtime/runtime_main_syscall_leaf.c:253-352`, `src/linux/futex_internal.h:176-350`). `REQUEUE` correctly ignores bitsets; `BITSET 0` and negative counts return `EINVAL` (`src/linux/futex.c:119-176`, `src/linux/futex.c:231-267`).
- **Scheduler FIFO/quiescence:** `queue_push` appends, `select_next` takes the head, quiesce moves the queue to suspended and re-admits on abort (`src/runtime/scheduler_internal.h:91-172`, `src/runtime/scheduler.c:176-206`, `src/runtime/scheduler.c:462-487`). `tgkill` cross-view routing is intentionally scoped to `USR1`/`USR2`/`TERM` with `ESRCH`/`EOPNOTSUPP` otherwise (`src/linux/signal.c:614-649`).
- **`atfork`/copied locks:** no `pthread_atfork` is registered; native `fork` fires only from the quiesced owner with `io_flights == 0`, and the child path never inspects a copied mutex (`src/runtime/scheduler.c:631-680`, `src/runtime/family_lifecycle.c:595-659`).

No `RV-R10-N` defect IDs are issued this round.

