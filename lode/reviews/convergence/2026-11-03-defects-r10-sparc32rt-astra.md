# sparc32rt Round-10 Deep-Dive 4 audit: threading, lifecycle, tgkill, futex

Scope: `src/os/threads.c`, `src/os/threads_exec.c`, `src/os/threads_fd.c`, `src/os/threads_kill.c`, `src/os/threads_sig.c`, `src/os/futex.c`, `src/rt32/thread_entry.S`, plus `src/os/threads.h`, `src/os/syscalls_min.c`, `src/os/syscalls_time.c`, `src/os/syscalls_sig.c`, `src/sparc32rt.h`, `src/rt32/stack32.c`. Read-only; no builds, tests, or subagents.

## Verdict

**0 defects found.** The subsystem is converged for the four audit axes below.

## What was verified

**`clone`.** Parent gets `o0 = tid, o1 = 0` and the child gets `o0 = 0, o1 = 1` with carry clear via the shared dispatch tail ([syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_min.c:887)). Child `pc/npc` resume past the trap and `%g7` is set only under `CLONE_SETTLS` ([threads.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:825)). Exit clears the guest word big-endian and issues `FUTEX_WAKE` ([threads.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:648)). Register windows are isolated per thread through the `_Thread_local` save/restore pair. `thread_entry.S` never touches `x18`, clears `NZCV`, keeps `SP` 16-aligned, and uses the documented `0x138/0x144/0x168` offsets.

**`fork`/`vfork`/`wait4`.** `fork_prepare` acquires in the documented `thr_live_lock -> sigact -> thr_fd -> g_dbt -> VM` order and the child destroys and rebuilds each inherited mutex ([threads.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:411)). Fork dual-return (`o1 = 1` child, `o1 = 0` parent) is correct ([threads.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:474)). `wait4`/`waitpid` validate the status and `rusage` ranges, translate `WTERMSIG`/`WSTOPSIG` back to SPARC numbers, and store the status big-endian.

**`execve`.** Siblings are retired under the lock with sticky marks and a bounded wait, `CAUGHT` handlers reset while `IGN` survives ([threads_exec.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_exec.c:152)), close-on-exec descriptors are swept without touching translator-owned plan fds, and the VM path invalidates the JIT across the full range. The apparent `ctx->exec_path = path` borrow is safe because `rt32_stack_setup` replaces it with a heap copy before return ([stack32.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/stack32.c:393)).

**`futex`/`tgkill`/`atfork`.** The Linux path byte-swaps the `WAIT` comparator so the host compare matches the big-endian guest word, and `WAKE` needs no value conversion ([syscalls_time.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_time.c:272)). The emulation holds one mutex across value-check and sleep, so no wakeup is lost between check and wait ([futex.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:145)). `tgkill` copies the target TID under the live lock and never dereferences after unlock ([threads_kill.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_kill.c:186)). No lock-order reversal against the documented order was found.

Two narrow items were checked and left unreported per the annealing rule: the `clone` flag mask omits `CLONE_CHILD_SETTID`, but the pinned oracle flag set `0x2D0F00` does not use it; and `vfork` aliases `fork` without parent suspension, which matches the lane's documented scope. Neither is a demonstrable divergence in this subsystem.

