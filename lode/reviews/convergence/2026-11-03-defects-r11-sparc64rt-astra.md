# `sparc64rt` Round-11 Deep-Dive 5 — Signal Multiplexing / `sigaltstack` / Signal Frames / Host Fault Recovery

Scope (read-only): `src/os/sync_sig.c`, `src/os/sync_sig.h`, `src/os/sigframe_sparc64rt.h`, `src/os/safe_syscall_a64.S`, `src/os/syscalls_min.c`, plus `src/os/syscalls_sig.c`, `src/os/syscalls_sig.h`, `src/os/guest_engines.c`, `src/os/backend_linux.c`, `src/main.c`, `src/core/cpu.h`.

## Summary

| ID | Severity | Location | Finding |
|----|----------|----------|---------|
| `S64-R11-1` | `BUG` | `src/os/sync_sig.c:475-477`, `src/os/sync_sig.c:674-676` | `SIG_IGN` (`handler == 1`) kill-family / pending signals treated as fatal instead of ignored |

`0` further defects found in SPARC signal numbering, `sigaltstack` `MINSIGSTKSZ` / `SS_ONSTACK` / `SS_DISABLE`, `rt_signal_frame` geometry / bias / alignment / big-endian marshaling / window spill / `tpc`/`tnpc` restoration, `rt_sigreturn` (`101`) / `SA_RESTORER` (`o5` → `%o7`), and `safe_syscall_a64.S` / host fault recovery. No quota-filling findings per annealing rule.

## `S64-R11-1`: `SIG_IGN` async signals forced fatal

### Evidence

`src/os/sync_sig.c:475-477` (`sparc64_sync_sig_queue`):

```c
handler = sync_handler[(unsigned)signo];
if (handler == UINT64_C(0) || handler == UINT64_C(1)) {
    return -1;
}
```

`src/os/sync_sig.c:674-676` (`sparc64_sync_sig_deliver_pending`):

```c
if (sync_handler[(unsigned)signo] == UINT64_C(0) ||
    sync_handler[(unsigned)signo] == UINT64_C(1)) {
    return -1;
}
```

Both conflate `SIG_DFL` (`0`) with `SIG_IGN` (`1`). Callers treat `-1` as fatal:

- `src/os/syscalls_sig.c:295-298`: `sig_deliver_self` → `sig_force_fatal` (disarms all handlers, parks `pc=0`).
- `src/os/syscalls_sig.c:192-195`: `rt_sigprocmask` unblock → `sig_force_fatal`.

`SIG_IGN` is a supported disposition in this subsystem: `sparc64_sync_sig_install_full` explicitly accepts `handler == 1` (`src/os/sync_sig.c:141-148`), and `sparc64_sync_sig_exec_reset` explicitly preserves `SIG_IGN` across `execve` while resetting caught dispositions (`src/os/sync_sig.c:284-293`). Mishandling it contradicts the module's own contract.

Fault-trap delivery (`src/os/sync_sig.c:514-515`, `537-538`) correctly returns `-1` for `0`/`1`; synchronous faults stay fatal even when ignored on Linux, so that path is left alone.

### Reproduction (no execution; static path)

1. Guest: `rt_sigaction(30, {handler=1, flags=SA_SIGINFO, restorer=0, mask=0}, NULL, 0, 8)` → returns `0`, installs `SIG_IGN` for `SIGUSR1`.
2. Guest: `kill(getpid(), 30)` (same via `tkill`/`tgkill` self, or block → kill → `rt_sigprocmask(UNBLOCK)`).
3. Expected Linux: `kill` returns `0`, signal discarded, guest continues.
4. Actual: `sparc64_sync_sig_queue` returns `-1` (or `deliver_pending` returns `-1` on unblock) → `sig_force_fatal`, translator parked on unmapped zero page instead of ignoring.

Blocked-`SIG_IGN` variant also wrong: an ignored signal must be discarded, not queued in `pending`; current code returns `-1` before the blocked check.

### Minimal surgical fix

Scope fix to async (`SI_USER`) paths only; leave fault `deliver` fatal semantics intact:

- In `sparc64_sync_sig_queue`, after loading `handler`, handle `1` as ignore: clear the pending bit and return `0` (before the blocked check, since ignored signals are discarded even when blocked).
- In `sparc64_sync_sig_deliver_pending`, when `handler == 1`, clear that signal's pending bit and `continue` to the next pending signal instead of returning `-1`. Keep `handler == 0` → `-1` (preserves current `DFL` behavior; default-ignore/default-stop tables are out of scope for this finding).

## Explicit `0`-finding modules

- SPARC numbering (`SIGBUS=10`, `SIGSTOP=17`, `SIGUSR1=30`, `SIGUSR2=31`, `SIGKILL_BIT=1<<8`, `SIGSTOP_BIT=1<<16`, dispatch `kill=37` / `tkill=187` / `tgkill=211` / `sigaltstack=28` / `rt_sigaction=102` / `rt_sigprocmask=103` / `rt_sigpending=104` / `rt_sigreturn=101` / `wait4=7`): mask arithmetic and dispatch correct.
- `sigaltstack` enable/disable validation, `MINSIGSTKSZ=2048` → `-ENOMEM`, overflow/`TASK_SIZE` → `-ENOMEM`, `SS_ONSTACK` rejected on set / reported dynamically on get, alias-safe `uss`/`uoss` order: correct.
- Frame `528`/`0x210` + `280` tail, `STACK_BIAS=2047`, `16`-byte `base`, `ss/info/regs/fpu_save/stack/mask/rwin_save` offsets, `BE` helpers, `%o0/%o1==%o2/%o7`, `win_flush_all`, `tstate`/`tpc`/`tnpc`/`y`/`magic`, `sigreturn` validation/restoration: correct.
- `safe_syscall_a64.S`: no `x18` use, `ldar`/`cbnz`/`svc`/`-EINTR`/`stlr` shape intact; host `SEGV`/`BUS`/preempt handler install and no-recovery re-raise by design: no proven defect.

