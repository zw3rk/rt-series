# RVRT Round-8 Deep-Dive 2 — DBT/JIT Static Audit (Read-Only)

Scope: `src/dbt/*`, `src/jit/*`, `src/darwin_dbt*`, `src/*trampoline*`, `src/dbt_emit_fp.*`, `src/dbt_emit_m.c`, `src/runtime/safe_syscall_a64.S`, `src/os/backend*.c/h` (W^X only). No files modified/created/deleted; no builds/tests run. Every file below was read line-by-line.

## Summary table

| ID | File:Line | Bug | Repro | Fix |
|----|-----------|-----|-------|-----|
| — | — | No concrete demonstrable behavioral bugs found; no IDs issued | — | — |

## Per-file verdicts

- [a64.c](/Users/angerman/Projects/zw3rk/rvrt/src/jit/a64.c): 0 bugs.
- [a64.h](/Users/angerman/Projects/zw3rk/rvrt/src/jit/a64.h): 0 bugs.
- [emit.h](/Users/angerman/Projects/zw3rk/rvrt/src/jit/emit.h): 0 bugs.
- [cache.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/cache.c): 0 bugs.
- [cache.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/cache.h): 0 bugs.
- [dbt.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/dbt.h): 0 bugs.
- [emit_mem.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c): 0 bugs.
- [emit_mem.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.h): 0 bugs.
- [aot_v4.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/aot_v4.c): 0 bugs.
- [aot_v4.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/aot_v4.h): 0 bugs.
- [difftest.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/difftest.c): 0 bugs.
- [difftest.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/difftest.h): 0 bugs.
- [trampoline_a64.S](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/trampoline_a64.S): 0 bugs.
- [darwin_dbt.c](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c): 0 bugs.
- [darwin_dbt_emit.c](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt_emit.c): 0 bugs.
- [darwin_dbt.h](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.h): 0 bugs.
- [dbt_emit_fp.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c): 0 bugs.
- [dbt_emit_fp.h](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h): 0 bugs.
- [dbt_emit_m.c](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_m.c): 0 bugs.
- [safe_syscall_a64.S](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/safe_syscall_a64.S): 0 bugs.
- [backend_darwin.c](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c), [backend_linux.c](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c), [backend.h](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend.h): 0 bugs for W^X/I-cache behavior.

## Findings by area

1. AArch64 encoding: `MOVZ/K`, `LDR/STR (unsigned-offset)`, `ORR/MOV`, `ADD/SUB (imm12)`, `ADD/SUB/AND/ORR/EOR (reg)`, `LSLV/LSRV/ASRV`, `MUL`, `CMP`, `CSET/CSEL`, `B/B.cond/CBNZ/CBZ`, `SBFM/SXTW`, `REV16/REVW/REVX`, FP `FMUL/FADD/FCMP/FMOV/LDR-D/S/STR-D/S` bases and `AND (imm)` masks with `immr=52/imms=51+log2w`, `UBFX x,addr,#12,#12`, `ADD base,idx,LSL#5` for 32-byte TLB entries, and `LDP` tag/addend pairs all match documented shapes; branch patch arithmetic (`target-branch` in words, 19-bit `CBNZ/B.cond` and 26-bit `B` ranges, block size <2048 words) stays in range.

2. Registers/`x18`: no emitter or trampoline references `x18`; pinned `x19=ctx`, `x20=TLB`, `x21=cpu`, `x22=self-loop`, `x23/chain`, `x26/IBTC`, `x28=epoch` are saved/restored by the trampoline and never written by blocks except their designated roles; scratch `x0-x9`/`v0-v3` use is caller-saved-consistent; `rv_dbt_reg_usable()` rejects `{1,2,3,4,18,19,20,21,31}`.

3. RV64GC vs RV32GC: `W`-forms for RV32 ALU (`ADDW/SUBW` equivalent via cleared `SF`), `SXTW` after RV64W, `UXTW` address truncation, `rv32_wrap()` PC wrap, `LWU/LD/SD` rejection on RV32, RVC `length 2/4` PC increments, and `rv32_expand`/`rv_expand_rv64c` lowering are consistently applied.

4. Soft-TLB: tag+alignment combined `AND`/`CMP`/`BNE`, `x4=loaded-tag` vs computed-tag discipline, `TLB reuse` + `MOVN x4,#0` (`-1`, never a valid page tag) poisoning, and miss tails preserving `x1=addr`/`x2=value` with exact faulting `pc`/`spec`/`len` and pre-instruction cache restores are correct.

5. Chaining/IBTC/RAS/W^X/I-cache: `IBTC (pc>>1)&4095`, 16-byte entries, trampoline + block-tail probes, `chain_next` metadata-only use, and `mmap(RW)->memcpy->__builtin___clear_cache()->mprotect(RX)` / Darwin `MAP_JIT` + `pthread_jit_write_protect_np` + `__builtin___clear_cache()` sequencing are correct; no RAS predictor exists in-tree and none is claimed — 0 bugs.

6. `EXIT_*` commit: there are no `EXIT_UNDEF/SYSCALL/TRAP` symbols; actual `RV_DBT_EXIT_FALLTHROUGH/BRANCH/INDIRECT/HELPER/FAULT` + `RV_STEP_*` discipline commits `cpu->pc/exit_pc`, write-through GPRs, flushed FPR/FPSR, and `pending_result` before `rv_step` fallback — 0 bugs.

