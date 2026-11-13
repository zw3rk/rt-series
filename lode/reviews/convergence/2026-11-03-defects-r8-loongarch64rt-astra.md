# Round-8 Deep-Dive 2 Static Audit: AArch64 DBT/JIT

**Scope:** `src/dbt/*`, `src/os/jit_wx.h`, `src/os/safe_syscall_a64.S`, `src/vm/vm64_dispatch.c`, related headers. Read-only; no builds/tests. Ground truth for behavior is `src/interp/*` (the `--difftest` oracle).

## Summary table

| ID | File:line | Defect | Fix |
|---|---|---|---|
| LA64-R8-1 | `emit_ldst.c:106` | LDPTR/STPTR wide offset corrupts | Range-check before emit |
| LA64-R8-2 | `emit_int.c:636` | REVB_2W emits ROR, not REV | Use REV32 |
| LA64-R8-3 | `emit_int.c:631` | REVB_4H uses REV32, needs REV16 | Use REV16 X |
| LA64-R8-4 | `emit_int.c:629` | REVB_2H misses mask and SXTW | REV16 W plus SXTW |
| LA64-R8-5 | `emit_int.c:486` | MULW_D_WU signs rj wrongly | Zero-extend rj |
| LA64-R8-7 | `emit_fp.c:253` | FMOV.S skips nanbox, mistags | Nanbox, tag `.S` |
| LA64-R8-8 | `emit_fp.c:299` | MOVGR2FRH.W shifts wrong way | UBFM `#32,#31` |
| LA64-R8-9 | `emit_fp.c:694` | VAND.V/VORN.V ignores vk | Pass vk, not 0 |

(An initial DIV zero-path suspect was falsified: the W-form `CSEL` plus `SXTW` already canonicalizes. It is not listed.)

### LA64-R8-1
`la64_emit_ldst` emits the EA `ADD` before checking the 12-bit range. `LDPTR`/`STPTR` carry `si14<<2` (up to ±32764, [decode.c:442]( /Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/decode.c:442)), so `a64e_add_imm` sets `e->err` mid-word while the partial bytes (wrong EA, unpatched `CBNZ`-slot NOP) are kept by `translate_block`. Repro: `ldptr.w rd, rj, 1024` (offset 4096) with the base page mapped. Effect: wrong-address native store, or wild host access through a stale addend on tag mismatch. Fix: decline before emitting anything when `rj != 0` and the offset is outside ±4095.

### LA64-R8-2
`REVB_2W` emits `EXTR X, Hj, Hj, #32` (word swap). Interp byte-reverses each word ([interp.c:390]( /Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:390)). Repro: `r0 = 0x0102030405060708` diverges. Fix: `e_1op(e, d, 0xDAC00800u)` (REV32 X).

### LA64-R8-3
`REVB_4H` emits REV32 X. Interp swaps bytes within each halfword, which is REV16 X ([interp.c:382]( /Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:382)). Fix: `e_1op(e, d, 0xDAC00400u)`.

### LA64-R8-4
`REVB_2H` emits full-width REV16 X with no masking or sign extension. Interp operates on the low 32 bits then applies `sx32` ([interp.c:373]( /Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:373)). Repro: nonzero upper input, or negative low result. Fix: `REV16 W` (`0x5AC00400`) followed by `SXTW`.

### LA64-R8-5
`MULW_D_WU` applies `SXTW` to `rj`. Interp multiplies two unsigned words ([interp.c:209]( /Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:209)). Repro: `rj = 0xFFFFFFFF, rk = 0xFFFFFFFF`. Fix: zero-extend (`ORR W, XZR, Wj`) instead of `SXTW`.

### LA64-R8-7
`FMOV.S` (`s_absneg_mov`, `op == 2`, `.S`) copies the full 64 bits. Interp nanboxes through `fp_set_s` (upper 32 forced to ones). It also tags the FPR-cache slot full, so later `.D` reads see wrong bits. Repro: `movcf2fr` then `fmov.s`. Fix: ORR the nanbox mask for `.S` and note the slot `.S`.

### LA64-R8-8
`MOVGR2FRH.W` emits `UBFM X, Ht, Hj, #32, #63`, which is `LSR #32` (per this repo's own `e_lsr` convention), yielding zero. It must deposit `rj` into bits [63:32]. Repro: nonzero `rj` low word. Fix: `UBFM X, Ht, Hj, #32, #31` (`LSL #32`).

### LA64-R8-9
Vector logic `0x3893/0x3894` (`VAND.V`/`VOR.V`/`VXOR.V`/`VANDN.V`/`VORN.V`) calls `v_halves3` with `vk = 0` (guest `v0`) instead of the decoded `vk`, while interp uses the real `vk` (`alu3`). Repro: any such op with `vk != v0` and `v0` differing. Fix: pass `vk`.

## Files with 0 bugs

`a64_emit.h`, `a64_emit.c`, `emit_mem.h`, `emit_mem.c`, `emit_branch.h`, `emit_branch.c`, `emit_fp_cache.h`, `emit_fp_mem.h`, `emit_fp_mem.c`, `emit_int.h`, `dbt.h`, `dbt.c`, `dbt_chain.c`, `dbt_code.c`, `dbt_smc.c`, `dbt_mem.c`, `trampoline_a64.S`, `jit_wx.h`, `safe_syscall_a64.S`, `vm64_dispatch.c`.

Notes: `x18` is never emitted (integer helpers gate it; the only `18` is vector `v18`, a separate SIMD file register). No `RAS` unit exists (IBTC-only chaining); that is a missing feature, not a bug. `EXIT_TRAP` does not exist as an exit code; traps decline via `EXIT_UNDEF` with exact `pc` and write-through registers, which is correct.
