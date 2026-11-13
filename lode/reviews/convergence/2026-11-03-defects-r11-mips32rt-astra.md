# Round-11 Static Audit: Signal Multiplexing & Fault Recovery

Read-only audit completed. No files modified, no builds run, no subagents used.

Path notes: `src/os/signals.h` and `src/os/safe_syscall_a64.S` do not exist. Audited actual locations: `src/os/signals.c`, `src/os/sigqueue.c`, `src/os/kill.c`, `src/os/proc.c` (wait4), `src/os/hostfault.c`, `src/os/syscalls.c`, `src/os/syscall_min.c`, `src/os/syscalls_priv.h`, `src/os/syscall_nr.h`, `src/os/sigframe_mips32rt.h`, `src/os/mem.c`, `src/os/threads.c`, `src/os/backend_linux.c`, `src/interp/interp.c`, `src/dbt/dbt.c`, `src/rt32/safe_syscall_a64.S`, `src/mips32rt.h`.

## Summary

| ID | Where | Bug | Fix |
|---|---|---|---|
| M32-R11-1 | `signals.c:670,684` | Death raise uses MIPS number | Translate to host signal |
| M32-R11-2 | `proc.c:486-490` | wait4 status signals untranslated | Map stop/term signals to MIPS |
| M32-R11-3 | `kill.c:195-201` | `tkill/tgkill` signo-0 skips tid check | Validate tid first |
| M32-R11-4 | `signals.c:271-299` | No delivery after handler install | Call deliver-pending on install |

## M32-R11-1: `mips_trap` / `mips_trap_code` raise host with untranslated MIPS number

[signals.c](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:664) (`mips_trap`) and the explicit-code variant below it call `(void)raise(signo)` with the MIPS O32 number, then `_Exit(128 + signo)`. Where MIPS and host (AArch64 Linux) numbering differ, the wrong host signal is raised. `kill.c` already carries the correct table (`mips_to_host_fatal_sig`, [kill.c](/Users/angerman/Projects/zw3rk/mips32rt/src/os/kill.c:99)), so this is internally inconsistent, not a design choice.

Concrete cases: MIPS `SIGBUS=10` raises host 10 (`SIGUSR1`, host `SIGBUS=7`); MIPS `SIGSYS=12` raises host `SIGUSR2`; MIPS `SIGPWR=19` raises host 19 (`SIGSTOP` on the host) — a guest dying by `SIGPWR` stops the whole translator instead of terminating. Repro: install no `SIGBUS` handler, trigger a `BUS_ADRERR` fault; host observer sees `SIGUSR1`, never `SIGBUS`. Fix: route both `raise()` sites through the shared MIPS-to-host mapping (fall back to `_Exit`-only when there is no host equivalent, e.g. `SIGEMT=7`).

## M32-R11-2: `wait4`/`waitpid` passes host signal numbers through in status

[proc.c](/Users/angerman/Projects/zw3rk/mips32rt/src/os/proc.c:451) (`proc_wait_common`) copies the host `waitpid` status verbatim into the guest word. The comment at lines 447–449 claims MIPS encoding matches the host; the bit layout matches, but the signal numbers do not. `WTERMSIG`/`WSTOPSIG` arrive in host numbering. Repro: child stops on `SIGSTOP`; guest `WSTOPSIG` reads 19 (host) instead of 23 (MIPS). `SIGBUS` death reports 7 instead of 10; `SIGCONT` reports 18 instead of 25. Fix: decode the status, map the term/stop signal field host-to-MIPS, re-encode; leave exit codes, `0x7f` stop flag, `0xFFFF` continued, and core bit untouched.

## M32-R11-3: `tkill`/`tgkill` signo-0 existence check bypasses tid validation

[kill.c](/Users/angerman/Projects/zw3rk/mips32rt/src/os/kill.c:195) handles `signo == 0` before the `tid != self_tid` check at line 205. For `tkill`/`tgkill` the pid is forced to self, so the existence branch always succeeds. Repro: `tkill(0xdeadbeef, 0)` returns 0; Linux returns `ESRCH`. Fix: perform the tid liveness check before the signo-0 early return.

## M32-R11-4: `rt_sigaction` installing a handler does not deliver an already-pending signal

[mips_sc_rt_sigaction](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:215) records the new disposition and returns without calling `mips_signal_deliver_pending` (compare `rt_sigprocmask` line 374 and `rt_sigreturn` line 660, which do). Linux delivers a pending, unblocked signal on every return to userspace, including the `sigaction` return path. Repro: block `SIGUSR1`, raise it to self (pending), then `sigaction(SIGUSR1, handler)` — on hardware the handler runs before the next instruction; here it stays pending until an unrelated `sigprocmask`/`sigreturn`. Fix: after installing a real handler, call `mips_signal_deliver_pending(ctx)` before returning.

## Clean modules (0 findings)

- `rt_sigframe` layout and offsets in `signals.c` match `sigframe_mips32rt.h` (`siginfo` at +24, `uc` at +152, `sc_pc` at +184, 64-bit `sc_regs`/`sc_fpregs`/`sc_mdhi`/`sc_mdlo`, mask at +768); `$a0`/`$a1`/`$a2`/`$t9`/`$ra` assignment, 8-byte alignment consistent with the `sigreturn` check, delay-slot `branch_pc`, and `LLbit` clearing on entry/return/syscall/fault/`fork`/`clone` all verified.
- `sigaltstack` (`MINSIGSTKSZ=2048`, `SS_ONSTACK`/`SS_DISABLE`, on-stack `EPERM`) verified; `SS_AUTODISARM` rejection left as-is (no in-repo contract requiring it — not reported per annealing rule).
- `safe_syscall_a64.S` verified correct standalone (acquire-checked generation gate, abort returns `-EINTR`, no `x18` use); no caller wires it yet, but all host-syscall sites handle `EINTR` by retry, so no demonstrable guest-visible race — no finding.
- `hostfault.c` pool-range check, ancestral `sigsetjmp` frame, `mips_ll_abandon`, and `savemask=0` rationale verified; signal-number remapping, mask scrub of `SIGKILL`/`SIGSTOP`, RT-queue `EAGAIN` vs `SI_USER` merge, `exec` reset, and `clone`/`fork` mask inheritance verified.

