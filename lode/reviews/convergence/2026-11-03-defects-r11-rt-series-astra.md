# Round-11 Deep-Dive 5: Signal Multiplexing / Fault Recovery Audit

Scope: read-only static audit only. No edits, builds, or tests run.

## Summary

| ID | Location | Mismatch | Fix |
|---|---|---|---|
| RTS-R11-1 | `check_abi` vs SPEC | 348B vs 344B frame | drop word, reorder stack |

One direct specification contradiction found. No other `BUG`/`DEFECT` in scope.

## RTS-R11-1: SPARC32 `rt_signal_frame` size and field order

Contradiction between frozen layouts:

- [check_abi_invariants.c](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:205): defines `sparc32_rt_signal_frame_t` as `ss` + `info` + `regs` + `mask[2]` + `fpu_save` + `insns[2]` + `extramask[1]` + `extra_size` + `rwin_save` + `stack`, with `stack` at `0x150` and size `348`.
- [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:364): freezes `rt_signal_frame32` as `344` bytes / `0x158`, with `stack` at `0x144`, `extra_size` at `0x150`, `rwin_save` at `0x154`.
- [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:55): same `344B`, extent `0x158`, `stack_t` at `0x144`.

`348` is not 8-byte aligned; `344` is. The extra `extramask[1]` word breaks the frozen extent.

Minimal fix: align [check_abi_invariants.c](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:205) with the frozen SPEC order. Remove `extramask[1]`, place `stack` before `extra_size`/`rwin_save`, assert `stack` at `0x144`, `extra_size` at `0x150`, `rwin_save` at `0x154`, size `344`.

## Checked clean

- [p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:63) handlers and [sig_fault_addr.h](/Users/angerman/Projects/zw3rk/rt-series/tests/sig_fault_addr.h:31): bridge uses only `volatile sig_atomic_t` stores, `sigsetjmp(...,1)` plus `siglongjmp` mask restore, descending volatile fault store, no indeterminate locals after jump. No demonstrable async-safety, mask, or UB defect.
- Other 9 arch frames, MIPS/SPARC numbering, `rt_sigreturn` numbers: `RV32 944`, `SPARC64 528`, `i386 624`, `MIPS O32 4193`, `MIPS64 5211/6211`, `PPC 172`, `SPARC 101`, `RISC-V/LoongArch 139` consistent across [check_abi_invariants.c](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:1), [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:1), and [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:1).

