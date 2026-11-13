# Round-10 Deep-Dive 4 static audit: threading / lifecycle / futex

Scope: `src/os/threads.c`, `src/os/proc.c`, `src/os/futex.c`, `src/os/syscalls.c`, plus `src/os/exec.c`, `src/os/syscall_min.c`, `src/os/sigact.c`, `src/os/quiesce.c` as related lifecycle code. Read-only; no builds or tests run.

## Summary

| ID | Severity | Location | Finding |
|----|----------|----------|---------|
| M64-R10-1 | BUG | [exec.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/exec.c) (`400-403`, `542-555`) | Leader `execve` with live thread group neither refuses nor terminates siblings; workers survive with dangling `guest_base` |
| M64-R10-2 | BUG | [sigact.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c) (`468-492`), [exec.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/exec.c) (`351-365`) | `execve` reset discards explicit `SIG_IGN` and clears the blocked mask; Linux preserves both |

All other in-scope areas are clean: `clone` TLS/`$v0=0,$a3=0`/`clear_child_tid`+wake/slot lifecycle, `fork`/`wait4`/`waitid` LL clearing and lease handling, `futex` endian comparison and timeout validation, `tgkill` lookup, `atfork` reset ordering. No `clone3`/`vfork` defects (absent numbers correctly fall through to `ENOSYS`/`clone`).

## M64-R10-1: `execve` from leader with live workers leaves peers running

- Code: [exec.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/exec.c:400) refuses only `ctx->is_thread_clone` (`-EPERM`). A leader (`is_thread_clone == false`) with `mips_thread_group_live() > 0` proceeds. The success path ([exec.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/exec.c:542)) reloads only the caller, does `exec_close_cloexec()`, `munmap`s the old reservation (`550-551`), and resets only caller state. It never kills, joins, or clears `l4b_slots[]` peers.
- Repro: main thread `clone(CLONE_VM|CLONE_THREAD|CLONE_SIGHAND, stack)` a spinning worker, then main `execve()` a new image. Expected: single-threaded new image. Actual: workers keep running with copied `ctx->guest_base` pointing at the now-`munmap`ped old reservation; next access faults or executes stale bytes; `mips_thread_group_live()` stays nonzero.
- Fix: before `mips_load_elf`, check `mips_thread_group_live() > 0` and either return `-EPERM`, or (Linux behavior) terminate/join peers, clear their slots, and reset QS/DBT/TLB under one `mips_qs_begin/commit`.

## M64-R10-2: `execve` signal reset loses `SIG_IGN` (and blocked mask)

- Code: [sigact.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:475) sets every `handler = 0` unconditionally; explicit `handler == 1` (`SIG_IGN`) is not preserved. [exec.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/exec.c:354) clears `sig_blocked[]`; `signal(7)` preserves the mask across `execve`.
- Repro: guest `rt_sigaction(SIGPIPE, {SIG_IGN})`, then `execve()`, then write to a closed pipe. Expected: `EPIPE` return. Actual: disposition is `DFL`, process dies. Similarly, a previously blocked signal becomes deliverable after `execve`.
- Fix: in `mips64_signals_reset_for_exec`, keep `handler == 1` entries (flags/mask/restorer as-is); in `reset_state_for_exec`, do not clear `sig_blocked` (still clear `pend_*`, altstack, `clear_child_tid`, robust list, LL).

