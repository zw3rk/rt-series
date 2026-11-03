# LA64 Round-11 Deep-Dive 5 — Signal Multiplexing / Fault Recovery Audit

**Verdict: 0 defects found.** No concrete, demonstrable behavioral bugs in the audited subsystem. No `BUG`/`DEFECT` IDs issued.

## Coverage (read-only)

| Area | Files checked | Result |
|---|---|---|
| `rt_sigaction`/`procmask` immutability + 8B `sigset_t` | [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:481), [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:532) | Clean |
| Pending/masked delivery | [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:290), [sigstate.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigstate.c:22) | Clean |
| `sigaltstack` | [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:584) | Clean |
| `rt_sigframe` + `rt_sigreturn` + LL clearing | [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:171), [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:378) | Clean |
| Host fault + `safe_syscall_a64.S` | [signal_core.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/signal_core.c:55), [safe_syscall_a64.S](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/safe_syscall_a64.S:47), [backend_linux_sync.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_linux_sync.c:544) | Clean |

## Notes

- `rt_sigaction` rejects `SIGKILL`/`SIGSTOP` installs with `EINVAL` but allows query ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:497)), enforces `sigsetsize==8` ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:495)), and masks `KILL`/`STOP` from handler masks ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:526)). `rt_sigprocmask` does the same ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:570)).
- `rt_sigpending` (127) / `rt_sigsuspend` (133) / `rt_sigtimedwait` (137) have no numbers in [syscall_nr.h](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscall_nr.h:50) and return `-ENOSYS` via [minsys.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:793). Out of Phase-4 scope (SPEC 2.3, `docs/lanes/phase-4.md` L4a); clean `ENOSYS` is by design, not reported.
- `sigaltstack` enforces `MINSIGSTKSZ=2048` ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:34), [sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:639)), `EPERM` when on-stack ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:630)), and `SS_ONSTACK`/`SS_DISABLE` query semantics ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:618)). `SS_AUTODISARM` returns `EINVAL`; no gate guest or SPEC path requires it — not reported.
- Frame geometry (`128+448+288+544+16+1056+16=2496`, `UC_OFF=128`, `EXT_OFF=576`, `LASX_OFF=1424`, `END_OFF=2480`) matches [sigframe.h](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.h:90); trampoline `0x02822c0b`+`0x002b0000` (`a7=139; syscall 0`) matches [sigframe.h](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.h:101); `r[0..31]`/`pc`/`FCC`/`FCSR0`/FPU+LSX+LASX round-trip and LL clearing on entry ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:250)) and `sigreturn` ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:475)) are present. `src/linux/signal_frame_loongarch64rt.c` is unreferenced dead arithmetic; payload-size deltas there are not guest-observable — not reported per annealing rule.
- Host bridge preserves crash semantics ([signal_core.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/signal_core.c:55)) and `x18` is never touched in [safe_syscall_a64.S](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/safe_syscall_a64.S:24).

