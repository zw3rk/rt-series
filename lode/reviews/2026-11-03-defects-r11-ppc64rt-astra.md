# Round-11 Static Audit Report — Signal Multiplexing, Fault Recovery, `sigaltstack`, `safe_syscall_a64.S`, PPC64LE ELFv2 RT Signal Frames

**Scope (read-only, no builds, no tests, no subagents):** `src/os/sigframe.c`, `src/os/sigframe.h`, `src/os/sigframe_ppc64rt.h`, `src/run/sigdeliver.c`, `src/os/safe_syscall_a64.S`, `src/os/syscalls.c`, plus `src/os/syscalls_access.c`, `src/os/syscalls_conv.c`, `src/os/syscalls_p4.c`, `src/os/backend_block.c`, `src/os/backend_proc.c`, `src/os/backend_linux.c`, `src/run/core.c`, `src/run/run.h`, `src/os/syscall_nr.h`, `docs/lanes/phase-4.md`.

**Verdict: 0 defects found.** Each area below was checked line-by-line against its contract; no concrete, demonstrable behavioral bug survives the annealing bar.

## 1. `rt_sigaction` / `rt_sigprocmask` / `rt_sigpending` / `rt_sigsuspend` / `rt_sigtimedwait`

Clean. `SIGKILL`/`SIGSTOP` immutability holds on every path: `run_sig_record` rejects dispositions for 9/19 with `EINVAL` and strips handler-mask bits via `~RUN_SIG_UNMASKABLE` ([sigdeliver.c:248-276]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)); `ppc64_sigmask_apply` strips them ([sigframe.c:426-445]( /Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c)); `ppc64_syscall_sigmask_set` strips them ([syscalls_access.c:209-212]( /Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_access.c)); `run_deliver` re-strips after OR-ing the handler mask ([sigdeliver.c:429-432]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)); exec-restore skips 9/19 ([sigdeliver.c:211-214]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)). The 8-byte `sigset_t` contract is enforced (`args[3] != 8 → EINVAL`) in both backends, and pending/masked delivery drains `pending & ~mask` lowest-signal-first, clearing the bit before delivery ([sigdeliver.c:441-465]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)). `rt_sigpending`/`rt_sigsuspend`/`rt_sigtimedwait` are out of Phase-4 scope per [phase-4.md]( /Users/angerman/Projects/zw3rk/ppc64rt/docs/lanes/phase-4.md) (which names only `rt_sigaction`, `rt_sigprocmask`, `sigaltstack`, `rt_sigreturn`) and honestly return `ENOSYS` through the dispatch default — correct, not a bug.

## 2. `sigaltstack`

Clean. `MINSIGSTKSZ` (2048) enforced with `ENOMEM` on install and on `rt_sigreturn` restore ([sigdeliver.c:338-339,490-491]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)); `SS_ONSTACK` in a new stack → `EINVAL`, changing while on-stack → `EPERM` (1), `SS_DISABLE` clears, unknown flags → `EINVAL`, and only `SS_AUTODISARM` is retained — all matching Linux. Query reporting and `SS_AUTODISARM` disarm/re-arm across delivery/`rt_sigreturn` are coherent ([sigdeliver.c:291-347,467-499]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)).

## 3. PPC64LE ELFv2 `rt_sigframe`

Clean. Geometry is pinned by `_Static_assert`s: full 1528 B `sigcontext` in the `uc_mcontext` slot, `gp_regs[48]`/`fp_regs[33]`, `v_regs` canonical at `vmx_base+8` (16-aligned), `VRSAVE` at +528, `vsr_low[32]` at +544, total resident 2176 B, with hand-verified frame offsets (`FRAME_SC_SIGNAL` 200, `FRAME_PINFO` 1744, `FRAME_INFO` 1760, payload 1776). `r12 = handler`, `r3/r4/r5` = signo/siginfo/ucontext, no `+8` ([sigframe.c:174-186]( /Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c)). `tramp` is intentionally zero-filled: the translator never executes the in-frame trampoline (restorer-or-magic-`blr` design, [sigdeliver.c:349-357]( /Users/angerman/Projects/zw3rk/ppc64rt/src/run/sigdeliver.c)), so unwritten `tramp[6]` is not guest-observable. Reservation state across signals matches the translator's software-reservation model; no oracle divergence is demonstrable statically, so no finding is filed.

## 4. Host fault recovery and `safe_syscall_a64.S`

Clean. No `x18` anywhere in the window; `[begin, after_svc)` brackets exactly the `ldar`/`cmp`/`b.ne`+`svc` sequence with the abort path outside, so rewind can never re-trigger. Every router leg bumps `sig_seq` and rewinds in-window PCs ([backend_block.c:125-142]( /Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_block.c)); the installer uses `SA_SIGINFO|SA_ONSTACK` without `SA_RESTART` so interruptions surface as `EINTR` ([backend_proc.c:197-218]( /Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_proc.c)).

No surgical fixes proposed. Nothing here meets the `BUG`/`DEFECT` bar; per the annealing rule I report **0 defects** rather than quota-fill.
