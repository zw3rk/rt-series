# i686rt Round-10 Deep-Dive 4 Audit Report: Threading / Lifecycle / Futex

Scope: `src/os/clone.c`, `src/os/sys_thread.c`, `src/os/ldt.c`, `src/os/syscalls.c` (fork/exec), `src/os/sys_pass.c` (futex), `src/vm/vm32.c`, `src/os/backend_*.c`. Read-only; no builds, no tests, no subagents. Kernel contract cross-checked against `signal(7)`.

## Summary

| ID | Area | Finding | Severity |
|---|---|---|---|
| I686-R10-1 | execve | Stack-local path stored in `ctx` | High |
| I686-R10-2 | execve | Sibling threads never terminated | High |
| I686-R10-3 | fork/vfork | Child inherits pending signals | Medium |
| I686-R10-4 | futex | No timespec validation on vm32 path | Medium |

Clean, 0 defects: `clone` thread path (TLS/GS install, `eax=0`, cleartid+wake, registry reserve/commit, robust walk ordering), `tkill`/`tgkill` raise + quiescence (masked stays asleep, ignored discarded, sig-0 probe, ESRCH ordering), `atfork` lock order (VM > registry > futex > subpage, unlock-before-destroy honored), `wait4`/`waitpid`, futex value comparison and lost-wakeup freedom (slot registered under the same lock the wake takes; pre-wake recheck in the backend), exec signal reset (caught→DFL, IGN kept) and CLOEXEC sweep.

## I686-R10-1 — `execve` stores a dead stack pointer in `ctx->exec_path`

In [syscalls.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:738), `r_execve` ends with `ctx->exec_path = path;` where `path` is the function's own `char path[4096]` local. After return the frame is gone, but two post-exec readers dereference it: [proc.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/proc.c:284) (`/proc/self/exe`) and [sys_pass_fs.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass_fs.c:284) (`readlink /proc/self/exe`). (The third reader, [rt32_stack32.c](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_stack32.c:105), runs inside `r_execve` while the frame is live, so it is unaffected.)

Reproduction: guest calls `execve` successfully, then `readlink("/proc/self/exe")` or re-`exec`s `/proc/self/exe` (busybox applet dispatch). The pointer now aliases reused stack memory, so the guest gets garbage or `-ENOENT`.

Fix: `char *cp = strdup(path); if (!cp) return -ENOMEM; ctx->exec_path = cp;` (do not free the old value: initial images point at process `argv` per [main.c](/Users/angerman/Projects/zw3rk/i686rt/src/main.c:366)).

## I686-R10-2 — `execve` in a multithreaded guest leaves siblings running the old image

`r_execve` ([syscalls.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:648)) has no registry, thread, or futex-slot interaction: no sibling termination, no rejection, no registry prune, no `s_futex_slots` reset. Yet `rt32_vm_reset_for_exec` ([rt32_vm.c](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:749)) unmaps the whole window while sibling host threads keep executing old-image EIPs, and stale registry entries plus orphaned futex waiters (64-slot table) survive into the new image, causing misdirected `tgkill` and eventual slot exhaustion.

Reproduction: guest clones a thread that spins or futex-waits, then the main thread `execve`s a new ELF. The sibling runs on torn-down memory (crash/hang) instead of dying per `execve` semantics.

Fix (surgical): at `r_execve` entry, reject when more than the caller is registered (e.g. return `-ENOSYS`); on the success path, prune the registry to the caller and add a slot-clear entry point for `s_futex_slots`.

## I686-R10-3 — `fork`/`vfork` child inherits the parent's pending signals

`signal(7)` is explicit: a `fork` child starts with an empty pending set (mask inherited, pending preserved across `execve` — so `r_execve` correctly leaves it alone). But neither [r_fork](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:351), nor the `CLONE_VM|CLONE_VFORK` fork path in [r_clone](/Users/angerman/Projects/zw3rk/i686rt/src/os/clone.c:674), nor [fork_child](/Users/angerman/Projects/zw3rk/i686rt/src/os/clone.c:817) clears `pending_signals`; the COW copy keeps the parent's bits. The thread path does clear it ([clone.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/clone.c:699)), confirming the omission is accidental.

Reproduction: block `SIGUSR1`, raise it to self (now pending), `fork`, unmask in the child. Native: handler never runs in the child. Translator: the inherited bit delivers.

Fix: in `fork_child`, inside the `surviving != NULL` block, `__atomic_store_n(&surviving->pending_signals, 0ULL, __ATOMIC_SEQ_CST);`. One site covers every host-fork path; mask and dispositions stay inherited per spec.

## I686-R10-4 — Missing `timespec_valid` check on the vm32 futex path

`sys_futex` copies the guest `{sec,nsec}` with no range check ([sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:339)), and `i686_vm32_futex` validates only `bitset == 0` ([vm32.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/../vm/vm32.c:358)). Consequences by regime: Darwin converts with wrapping unsigned arithmetic ([backend_darwin_net.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:491)), so a negative `tv_sec` becomes a ~16.7 s sleep instead of `-EINVAL`; Linux-A2 passes relative waits to the host (correct) but converts absolute `WAIT_BITSET` timeouts before validation ([backend_linux_sys.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_linux_sys.c:464)), turning `-EINVAL` cases into sleeps/`-ETIMEDOUT`. Linux-A1 is host-backed and correct.

Reproduction (A2/Darwin): `FUTEX_WAIT` with `{0, 2000000000}`. Kernel: immediate `-EINVAL`. Translator: sleeps ~2 s.

Fix: before dispatch in `i686_vm32_futex` (or `sys_futex`), `if (timeout && (sec < 0 || nsec < 0 || nsec >= 1000000000)) return -EINVAL;`.

