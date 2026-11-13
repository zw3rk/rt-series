# ppc32rt Round-11 Deep-Dive 5: Signal Multiplexing & Host Fault Recovery

**Scope audited (read-only):** `src/os/signals.c`, `src/os/signals.h`, `src/os/sigframe_ppc32.h`, `src/os/signals_priv.h`, `src/os/hostfault.c`, `src/os/syscalls.c` dispatch, `src/main.c` fault tails, `src/os/threads.c` signal enqueue. Phase scope per `docs/lanes/phase-4.md` (L4a: `rt_sigaction`, `rt_sigprocmask`, `rt_sigreturn`, `sigaltstack` + sync delivery) confirmed; legacy `sigaction`/`sigsuspend`/`sigpending`/`sigreturn` (67/72/73/119) and `rt_sigtimedwait`/`rt_sigqueueinfo`/`rt_sigsuspend` (176/177/178) returning `-ENOSYS` is intended out-of-scope behavior, not a defect.

## Summary

| ID | Site | Impact |
|---|---|---|
| P32-R11-1 | `signals.c:627`, `syscalls.c:525` | bad-frame `rt_sigreturn` spins forever |
| P32-R11-2 | `signals.c:711` | self `kill(pid,0)` wrongly fails |
| P32-R11-3 | `signals.c:485` | ignored sync fault loops, never dies |
| P32-R11-4 | `signals.c:136,541` | `sigaction` on KILL/STOP wrongly succeeds |
| P32-R11-5 | `signals.c:443` | SIGTRAP frame carries wrong trap vector |
| P32-R11-6 | `main.c:408`, `signals.c:423` | store faults mislabeled as loads |

## P32-R11-1: failed `rt_sigreturn` re-executes the `sc` forever

`sys_rt_sigreturn` ([signals.c:627-633](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:627)) returns the `-EFAULT` from `ppc32_sig_restore_frame` with `nip` still at the `sc`. The dispatch hook ([syscalls.c:524-532](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:524)) skips both `sys_apply_ret` and `nip += 4` for the no-advance number, then `syscall_dispatch` resets `exit_reason` to `NONE` ([main.c:520](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:520)). Repro: guest sets `r1` to an unmapped VA and executes `sc` 172. Result: the same `sc` re-executes at 100% CPU forever; native Linux kills the process with `SIGSEGV`. Fix: on restore failure, route through `ppc32_sig_deliver_sync(ctx, SIGSEGV, …)` and let a fatal result terminate via a `FAULT` exit the driver does not clobber, instead of returning to the `sc` loop.

## P32-R11-2: `kill(getpid(), 0)` returns `-EINVAL` instead of 0

`ppc32_sig_kill` rejects `sig < 1U` ([signals.c:711](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:711)), but `sig == 0` is the existence probe and must succeed. Repro: guest `kill(getpid(), 0)` gets `-EINVAL`; native returns 0, and the foreign-pid path in the same function forwards to host `kill(pid, 0)` and returns 0, so self-probe is internally inconsistent too. (`tkill`/`tgkill` already handle `0` correctly at [signals.c:862,881](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:862).) Fix: change the check to `sig > PPC32_NSIG → -EINVAL` and return 0 early for `sig == 0` (self → 0, foreign → host probe result).

## P32-R11-3: `SIG_IGN` on a synchronous fault loops instead of dying

`ppc32_sig_deliver_sync` returns 1 for `SIG_IGN` ([signals.c:485-487](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:485)), and the driver treats 1 as "re-execute" ([main.c:410-414](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:410)). Repro: guest ignores `SIGSEGV`, then touches unmapped memory. Native kills via `force_sig` (ignore is forced to default on sync faults — ignoring `SIGSEGV` never saves a real process); here the faulting instruction re-executes and re-faults forever. The header comment's "may re-fault like native" ([signals.h:186-188](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.h:186)) is incorrect for synchronous faults. Fix: treat `SIG_IGN` as fatal in `deliver_sync` (`return -EFAULT`); async `SIG_IGN` is already discarded separately in `ppc32_sig_pump_pending`, so no async path is affected.

## P32-R11-4: `rt_sigaction` accepts a new disposition for `SIGKILL`/`SIGSTOP`

`ppc32_sigaction_set_raw` only rejects KILL/STOP when the handler is not `SIG_DFL` ([signals.c:136-138](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:136)), so `rt_sigaction(SIGKILL, {DFL,…}, NULL, 8)` returns 0. The kernel rejects any non-NULL act for `SIGKILL`/`SIGSTOP` with `-EINVAL`, even one installing `SIG_DFL`. Repro: the call above succeeds here, fails natively. Fix: in `sys_rt_sigaction`, `if (have_new && !ppc32_sig_is_catchable((int)sig)) return -EINVAL;` (queries with `act == NULL` keep working, matching the kernel).

## P32-R11-5: `SIGTRAP` frame reports trace vector `0xD00`, hardware reports `0x700`

`sig_default_trap` maps `SIGTRAP` to `PPC32_TRAP_TRACE` ([signals.c:442-446](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:442)). The only in-system `SIGTRAP` producer is `EXIT_TRAP` from `tw`/`td` ([main.c:399-401](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:399)), and trap instructions raise the Program exception (`0x700`); `0xD00` is the debug/trace vector this emulator never generates. Repro: guest `tw` with a `SIGTRAP` handler inspecting `mc_gregs[40]` reads `0xD00` instead of `0x700`. Fix: use `PPC32_TRAP_PROGRAM` for the `SIGTRAP` case.

## P32-R11-6: store faults always report the load `DSISR` class

`is_store` is plumbed through `deliver_sync` but every call site passes `0U` (notably [main.c:408](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:408)), so `mc_dsisr` is always `DSISR_LOAD_CLASS` even for faulting stores. Repro: guest store to a read-only page; handler reads `mc_gregs[42]` and sees the load class instead of the store class. Fix direction: record access direction at the fault sites (`interp.h` store paths already know `is_store=true`; host-fault path needs a recorded direction) into `ctx` and pass it through instead of the constant `0U`.

## Evaluated, no finding

8-byte `sigset_t` layout and word order; `SIGKILL`/`SIGSTOP` stripping in `rt_sigprocmask`, delivery mask, restore mask, and pump; `rt_sigpending` as pending-blocked; `MINSIGSTKSZ`/disable/on-stack/`SS_ONSTACK`-ignored `sigaltstack` handling; 1536 B frame geometry (`uc` at `0x80`, `abigap` at `0x520`), big-endian marshaling, `FPSCR` high-word slot, `SPE` overlay gated on `is_spe`, in-abigap `li r0,172; sc` trampoline; `res_valid` clearing on build, restore, syscall entry, and fault revival; `SA_RESETHAND` atomicity; `SA_NODEFER`; host-fault window discrimination and `EOF_TRAP→SIGBUS` override; `SS_AUTODISARM` rejection (kernel-parity gap only if a guest uses it — no in-scope user observed).
