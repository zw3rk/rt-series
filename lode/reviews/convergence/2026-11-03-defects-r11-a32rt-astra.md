# Round-11 Deep-Dive 5: Signal Multiplexing and Fault Recovery

**Verdict: 0 defects found.** Read-only static audit only. No files modified. No builds or tests run.

Scope was `src/signals.c`, `src/os/os_sys_sig_time.c`, `src/os/os_sys_thread_sig.c`, `src/os/sys_priv.h`, `src/trampoline.S`, plus fault, exclusive, and frame code reached from those paths.

## 1. `rt_sigaction`, mask, pending, suspend, timedwait, `signalfd4`

No defect. `SIGKILL` and `SIGSTOP` are immutable at every entry point checked:

- `src/signals.c:666` rejects them in `rt_sigaction`.
- `src/signals.c:739` strips them from `rt_sigprocmask` inputs.
- `src/os/os_sys_sig_time.c:56` strips them from `rt_sigtimedwait` waits.
- `src/os/os_sys_sig_time.c:118` strips them from `rt_sigsuspend` masks.

Mask width is enforced as 8 bytes at `src/signals.c:669`, `src/signals.c:726`, `src/os/os_sys_sig_time.c:34`, `src/os/os_sys_sig_time.c:114`, `src/os/os_sys_sig_time.c:44`, and `src/os/os_sys_sock.c:322`. Pending, masked-delivery, `EINTR` versus `EAGAIN`, and `signalfd4` read semantics at `src/os/os_sys_thread_sig.c:312` match the surrounding `check_pending` and `pwait` handling.

## 2. `sigaltstack`

No defect. `src/signals.c:860` enforces 2048-byte `MINSIGSTKSZ` with `ENOMEM`. `src/signals.c:195` and `src/signals.c:203` implement active-range and `SS_ONSTACK` reporting. `src/signals.c:844` returns `EPERM` when already on the alternate stack. `src/signals.c:851` rejects spare flag bits while permitting `SS_DISABLE` and `SS_AUTODISARM`. Disarm and save behavior at `src/signals.c:298` agrees with the repository contract in `tests/test_m3_part3.c`, including re-arm after `rt_sigreturn` and preservation of a handler-installed `SS_DISABLE`.

## 3. `rt_sigframe`, `ucontext`, VFP, `rt_sigreturn`, `CPSR.T`, `LDREX`

No defect. Frame alignment at `src/signals.c:268`, `r0`-`r15` plus `cpsr` round-trip at `src/signals.c:321` and `src/signals.c:789`, IT packing at `src/signals.c:314` with unpacking at `src/signals.c:793`, VFP `d0`-`d31` and `fpscr` handling at `src/signals.c:326` and `src/signals.c:811`, and interworking entry and return through `a32_set_pc_interwork` and `a32_normalize_pc` preserve `CPSR.T`. The default restorer at `src/signals.c:345` matches the populated helper at `src/elf32.c:531`.

## 4. Host `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP` recovery

No defect. `src/signals.c:451` maps host PC back through the JIT side table and terminates faults outside translated code at `src/signals.c:454`. Register, `NZCV`, `FPSR`, `fault_addr`, and `si_code` handling at `src/signals.c:458` through `src/signals.c:522`, combined with Soft-TLB `A32_EXIT_FAULT` exits carrying explicit guest `fault_addr` and `ITSTATE`, preserves host redirect state and guest fault identity for the paths covered by the current tests.

