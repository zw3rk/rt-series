Found five concrete bugs. This checkout has no `src/interp/`; the interpreter lives in `src/core/`. Reviewed that implementation and related ISA, FP, atomic, CPU-state, and trap paths. No builds or tests ran; no files changed.

### RV-R7-1 — BUG — HIGH

- **Summary**: RV32 syscall errors leave noncanonical register values that cause incorrect integer comparisons.
- **Locations**: [runtime_main_syscall_leaf.c:511](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_syscall_leaf.c:511), [runtime_main_syscall.c:673](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_syscall.c:673), [internal.h:26](/Users/angerman/Projects/zw3rk/rvrt/src/core/internal.h:26), [interp.c:128](/Users/angerman/Projects/zw3rk/rvrt/src/core/interp.c:128).
- **Evidence & Root Cause**: This implementation deliberately stores RV32 registers **zero-extended**, but syscall handlers directly write 64-bit negative results. An unknown syscall leaves `a0=0xffffffffffffffda` (`-ENOSYS`); a subsequent `li t0,-38` produces `0x00000000ffffffda` through `rv_put()`. `beq a0,t0,expected` incorrectly falls through because BEQ compares the complete 64-bit containers. Neither syscall completion nor the interpreter entry normalizes the result.
- **Remediation**: Canonicalize RV32 syscall results at the shared retirement boundary, preserving internal restart/error comparisons before normalization. Apply the same register-write convention to other external CPU-state writers.

### RV-R7-2 — BUG — HIGH

- **Summary**: The A64 FP path implements `FLT.S/D` as less-than-or-equal and `FLE.S/D` as greater-than.
- **Locations**: [dbt_emit_fp.c:656](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:656), particularly lines 674–679; [dbt_emit_fp.h:198](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:198).
- **Evidence & Root Cause**: `FLT` selects condition `0xd` (`LE`), while `FLE` selects `0xc` (`GT`). Consequently, `FLT(1.0,1.0)` returns 1, `FLE(1.0,2.0)` returns 0, and `FLE(2.0,1.0)` returns 1. The subsequent unordered-result mask cannot correct finite comparisons. Both precisions and guest XLENs are affected in the Darwin/fast-Linux DBT. [Arm condition definitions](https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/condition-codes-4-floating-point-comparisons-using-vfp).
- **Remediation**: Use ordered `LO` (`0x3`) for FLT and `LS` (`0x9`) for FLE. Cover less/equal/greater/unordered operands through emitted-code execution.

### RV-R7-3 — BUG — MEDIUM

- **Summary**: Valid RV32 `C.FLWSP` instructions targeting `f0` trap as illegal instructions.
- **Locations**: [rv32_expand.c:224](/Users/angerman/Projects/zw3rk/rvrt/src/core/rv32_expand.c:224).
- **Evidence & Root Cause**: The `C.FLWSP` case rejects `rd==0`, incorrectly applying the integer stack-load restriction to a floating-point destination. Encoding `0x6002` means `c.flwsp f0,0(sp)` and must load writable register `f0`; instead, expansion fails and execution raises an illegal-instruction trap. The restriction applies to `C.LWSP`/`C.LDSP`, whereas `C.FLWSP` permits `f0`. [RISC-V compressed-instruction specification](https://docs.riscv.org/reference/isa/v20260120/unpriv/c-st-ext.html).
- **Remediation**: Remove the `rd==0` rejection from `C.FLWSP`, retaining it for integer stack loads. Cover successful loading and NaN-boxing into `f0`.

### RV-R7-4 — BUG — MEDIUM

- **Summary**: A memory slow path can turn a malformed single-precision operand from canonical NaN into a finite value.
- **Locations**: [dbt_emit_fp.c:184](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:184), [darwin_dbt_emit.c:98](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt_emit.c:98), [darwin_dbt_emit.c:192](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt_emit.c:192).
- **Evidence & Root Cause**: `emit_load_unboxed_s()` substitutes canonical NaN for malformed boxing and caches that substituted value, leaving architectural `f[]` unchanged. After a successful memory-helper call, `emit_reload_caches()` reloads single entries using raw `LDR S`, without validating their upper halves. Starting with `f1=0x000000003f800000`, the sequence `fadd.s f2,f1,f1`; successful first-touch integer load; `fadd.s f3,f1,f1` within one block produces NaN first, then `2.0`. The reload replaces cached NaN with raw `1.0`, violating [NaN-boxing semantics](https://riscv.github.io/riscv-unified-db/manual/html/isa/isa_20240411/chapters/d-st-ext.html).
- **Remediation**: Preserve boxing validation when reconstructing single cache entries. The helper rejoin must satisfy the cache assumptions already embedded in subsequent instructions.

### RV-R7-5 — BUG — MEDIUM

- **Summary**: Trap delivery writes an overflowing alternate-stack signal frame before rejecting it.
- **Locations**: [signal.c:775](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.c:775), especially the unconditional frame writes at lines 783–789.
- **Evidence & Root Cause**: For an RV64 nested trap with aligned alternate-stack base `B` and `sp=B+512`, the 1088-byte frame starts at `B-576`. The overflow check sets `valid=false`, but `rv_signal_frame_write()` still writes the frame if the surrounding memory is writable. Only afterward does delivery reject it and force SIGSEGV. RV32 has the same issue with its 944-byte frame. Rejected trap delivery therefore corrupts memory below the alternate stack. Linux checks overflow before writing the frame. [Linux v6.18 RISC-V signal implementation](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/kernel/signal.c).
- **Remediation**: Short-circuit frame construction when validation fails, before invoking either frame writer, and retain the existing bad-frame handling.
