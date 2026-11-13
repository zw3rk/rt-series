# Round-11 Deep-Dive 5 static audit: signal multiplexing and fault recovery

Read-only audit. No subagents spawned, no files modified, no builds or tests run.

## Scope

Audited `/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.c`, [signal.h](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.h), [signal_frame.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal_frame.c), [signal_frame.h](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal_frame.h), `src/linux/rv32_frame.c`, `src/linux/rv32_frame.h`, `src/linux/signal_exec.c`, plus `src/runtime/native_signal.c`, [native_signal.h](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/native_signal.h), `native_signal_capture_internal.h`, and [safe_syscall_a64.S](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/safe_syscall_a64.S). There are no `src/runtime/signal*.c` or `src/runtime/host_fault*.c` files; host-fault behavior lives in the checked-mapping path plus the files above.

## Verdict

**0 defects found.** Each area below matches its pinned contract in [RVRT.md](/Users/angerman/Projects/zw3rk/rvrt/RVRT.md) and `docs/SUPPORT.md`, with no concrete behavioral divergence.

1. `rt_sigaction`/`procmask`/`pending`/`sigsuspend`: `SIGKILL`/`SIGSTOP` install rejected but queries allowed (`signal.c:426`), all masks stripped of `UNBLOCKABLE` (`signal.c:23,473,568,805`), 8-byte size enforced for action/mask/suspend with pending sizes 0–8 (`signal.c:412,467,667,685`), updates applied before old-state copyout, synchronous-class priority mask `0x400004d8` correct (`signal.c:138`), directed-before-shared dequeue correct (`signal.c:132`). `rt_sigtimedwait` (137) and `rt_sigqueueinfo` (138) fall through to `-ENOSYS` (`runtime_main_syscall_leaf.c:511`); `SUPPORT.md` documents only 129–136 and 139 as supported, so this is intended, not a defect.
2. `sigaltstack`: `SS_ONSTACK`/`SS_DISABLE`/`SS_AUTODISARM` values, `EPERM`-first ordering (`signal.c:274`), 2048 minimum (`signal.c:283`), no backing validation, and autodisarm-then-restore across delivery and `rt_sigreturn` (`signal.c:809,588`) all match the contract.
3. Frames: RV64 offsets match the pinned table exactly (info 0, stack 144, mask 168, PC 304, FP 560, FCSR 816, reserved 1076); trampoline bytes are `li a7,139; ecall` (`signal.c:307`); all GPRs/FPRs/FCSR/PC/mask/altstack round-trip with `x0` pinned to zero; reservations cleared on delivery (`signal.c:813`) and fully on return (`signal_frame.c:132`). The deliver-only-`valid` clear leaves dead address/token fields, which `interp.c:215` gates behind `valid`, so it is unobservable.
4. Host faults and `safe_syscall_a64.S`: there is intentionally no host `SIGSEGV`/`SIGBUS` handler; guest faults come from checked accesses with `RV_FAULT_RESOURCE`/`INTERNAL` kept out of guest delivery (`signal.c:838,792`). The safe-call window, `ldar`/`cbnz` abort, `after_svc` result preservation, and `x12`-suppressed origin write for unauthorized flights are correct as written.

No `BUG` or `DEFECT` items to file. Nothing further to fix in this subsystem.

