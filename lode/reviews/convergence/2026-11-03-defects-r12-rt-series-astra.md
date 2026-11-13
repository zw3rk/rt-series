# Round-12 Deep-Dive 6 Audit — Syscall ABI / Marshaling / `/proc/self` / Host Contract

Scope: read-only static audit. No builds, tests, or file modifications. Files inspected: `tests/check_abi_invariants.c`, `tests/bench_sys.h`, `tests/bench_suite.c`, `include/a32host.h`, `docs/HOST-CONTRACT.md`, `docs/UNIFICATION-PLAN.md`, `SPEC.md`, `lode/ISA-TRAP-AND-ABI-MATRIX.md`.

## Verdict

**0 defects found.** Subsystem converged. No `BUG`/`DEFECT` to report per annealing rule.

## Coverage checked

- `include/a32host.h:65-68` ioctl encodings match `docs/HOST-CONTRACT.md:102` and `tests/check_abi_invariants.c:28`: `0x81006101`, `0xc0186102`, `0x40106103`, `0x40406104`. Size asserts (`24`, `16`, `64`, `256`) consistent.
- Caps bits `0-11` (`a32host.h:40-51`) match `HOST-CONTRACT.md:108-117`, including `HW_TSO` bit 9, `FIXADE` bit 10, `SOFT_TLB_256M` bit 11.
- Error polarity (`SPEC.md:88` D7) matches matrix §3 and per-arch SPEC sections: `-errno` for ARM/x86/RISC-V/LoongArch/`scv 0`; `$a3=1/$v0=+errno` for MIPS; `CR0.SO=1/r3=+errno` for PPC `sc`; `PSR.C=1` for SPARC32; `icc.C=xcc.C=1` for SPARC64.
- Signal frames: RV32 `944B`/`uc+160`, i386 `_fpstate 624B`, SPARC32 `344B`, SPARC64 `528B`, MIPS `24B` prefix — identical offsets in `check_abi_invariants.c`, `SPEC.md:238,299,364-375,505-515`, matrix §3.
- `bench_sys.h:96-99,122-126,157-160,190-193,216-219,243-250,272-275`: `write/getpid/exit_group/clock_gettime` numbers correct per-arch; MIPS `a3` conversion (`bench_sys.h:154`) correct; PPC/SPARC flag-ignoring safe for current `rc!=0` call sites.
- `HOST-CONTRACT.md:36-47` page rules, `SPEC.md:92` D11, matrix TASK_SIZE: `4096` except `sparc64rt 8192` — consistent.
- Translator dispatch (`HOST-CONTRACT.md:183-198`) matches SPEC admission (`EM_ARM`, `EM_386`, `EM_RISCV`, `EM_MIPS`, `EM_PPC`, `EM_SPARC`, `EM_LOONGARCH`, `EM_PPC64`, `EM_SPARCV9`); Provider A/B vs authority policies show no contradiction.

No surgical fixes required.

