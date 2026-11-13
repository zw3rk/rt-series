# Round-8 Deep-Dive 2 — DBT/JIT Static Audit (`ppc32rt`)

Read-only audit. Every file in `src/dbt/*`, `src/rt32/*a64*`, `src/dbt/trampoline_a64.S`, plus `src/ppc32rt.h` and the `src/interp` oracle (`fp.h`, `fp.c`, `interp.h`, `interp.c`, `fp_spe.c`) for parity checks. No files modified, no builds or tests run.

## Summary

| ID | Location | Defect | Fix |
|----|----|----|----|
| P32-R8-1 | `emit_int.c:527` | Indirect branch target not masked | `BIC w15, w15, #3` after LR/CTR load |
| P32-R8-2 | `emit_fp_class.c:42` | FPRF C-bit wrong for Inf, -0, NaN | Classify C from sign/quiet/mantissa |
| P32-R8-3 | `emit_fp.c:555` | `frsp` never narrows, widens low word | Emit `FCVT S0,D0` first |
| P32-R8-4 | `emit_fp.c:382` | `fcmp[u/o]` never writes FPSCR FPCC | Store `EI_R<<12` under `0xF000` |
| P32-R8-5 | `emit_fp.c:198` | FPSCR FR never set or cleared | Maintain FR from round-up test |
| P32-R8-6 | `emit_fp.c:311` | VXISI/MZ/ZD/DI folded into VXSNAN | Mirror `fp_inv2` input checks |

## Bugs

### P32-R8-1 — `bclr`/`bcctr` target missing `& ~3` — [emit_int.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_int.c:527)

`ei_bcxr` loads LR/CTR into `A64_TMP0` and calls `a64_emit_exit_branch_reg` with no low-bit masking, while direct branches mask (`ei_branch_target` does `& ~3U`) and the oracle masks every target (`branch_to`: `ctx->nip = target & ~3U` in [interp.h](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:405)).

Repro: `mtspr LR, rX` with `rX` odd (e.g. `0x1001`), then `bclr`. Interp lands on `0x1000`; DBT commits `nip = 0x1001` and looks up IBTC key `0x1001`, diverging every time.

Fix at the load site:

```c
ei_ctx_ld(b, A64_TMP0, ...);
a64_emit_mov_imm32(b, EI_T2, 0xFFFFFFFCU);
a64_emit_and_reg_w(b, false, A64_TMP0, A64_TMP0, EI_T2, A64_SHIFT_LSL, 0U);
```

### P32-R8-2 — `fp_fprf` C-bit misclassifies Inf, `-0.0`, NaN — [emit_fp_class.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp_class.c:42)

The class bit is `isMaxExp&isMantZero | isZeroExp&~isMantZero` (Inf | subnormal). The oracle ([fp.h](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:174) `fp_fprf64`, matching qemu) sets C for QNaN, ±denormals, and `-0`, and clears it for ±Inf:

- `+Inf`: DBT `0x14`, oracle `0x05` (repro: `fdiv 1.0, 0.0`).
- `-Inf`: DBT `0x18`, oracle `0x09`.
- `-0.0`: DBT `0x02`, oracle `0x12` (repro: `fsub +0, +0` with sign, or `fneg` of zero-producing op).
- QNaN result: DBT `0x01`, oracle `0x11` (repro: `fadd` with QNaN input — ARM raises no IOC, result NaN).

Fix: compute sign from the result word plus `isQNaN = maxExp & mant & quiet`, then `C = isQNaN | isDenorm | (isZero & sign)`; keep `[LT,GT,EQ,UN]` from the existing `fcmp`.

### P32-R8-3 — `frsp` widens the low word instead of rounding — [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:555)

The `in == 2U` path emits only `FCVT D0, S0` (`0x1E22C000`), widening the low 32 bits of the double pattern. The single-precision value is never produced. Repro: `frsp` of `1.5` (`0x3FF8000000000000`, low word zero) yields `+0.0` instead of `1.5f` widened. The comment even says "narrow D->S, widen back" but the narrow half is missing.

Fix: emit `FCVT S0, D0` (`0x1E624000 | (0U << 5) | 0U`) before the existing widen.

### P32-R8-4 — `fcmpu`/`fcmpo` leaves stale FPSCR FPRF — [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:382)

`fp_cmp` writes the CR field but never the FPSCR FPCC bits. The oracle overwrites them unconditionally (`ctx->fpscr = (fpscr & ~0xf000) | ret<<12`, preserving C). Repro: `fadd` (FPRF normal) then unordered `fcmpu` — DBT keeps the old field, oracle writes `0x1`. `difftest` compares full `fpscr`, so this fires on any compare after arithmetic.

Fix: after `fp_nzcv_field`, merge `EI_R` into `EI_A` at shift 12 under mask `0xF000` (not `FP_FPRF_MASK`, to preserve C per the oracle) and store.

### P32-R8-5 — FPSCR FR never maintained — [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:198)

`fp_conv_end` clears FI (`0x20000`) and `fp_accum` re-sets it exactly when IXC fires (via the `0x20000` folded into the XX mask), so FI is correct. But FR (bit 18) is never set and never cleared, while the oracle clears it per op and sets it when rounding increases magnitude ([fp.h](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:305)). Repro: any inexact single/double op that rounds away from zero — oracle `FR=1`, DBT `FR=0`; also a stale `FR=1` (e.g. via `mtfsb1`) survives an exact op in DBT but is cleared by the oracle.

Fix: clear bit 18 alongside FI in `fp_conv_end`, and set it from a rounded-up test (exact-vs-rounded magnitude compare, as `fp_rounded_up` does).

### P32-R8-6 — Invalid-arithmetic sub-bit always VXSNAN — [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:311)

`fp_round_end` hard-codes `ioc_sub = FP_VXSNAN`, so `Inf-Inf` (`fsub`/`fadd`), `0*Inf`, `0/0`, `Inf/Inf` all raise VXSNAN. The oracle raises VXISI/VXIMZ/VXZDZ/VXIDI respectively ([fp.h](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h) `fp_inv2`). Result values agree (both QNaN), only the sticky sub-bit differs — still a `difftest` `fpscr` mismatch. Repro: `fdiv 0.0, 0.0` — DBT `VXSNAN|VX`, oracle `VXZDZ|VX`.

Fix: classify the inputs before `fp_accum` mirroring `fp_inv2` (Inf/zero lane checks), selecting the sub-bit instead of the constant.

## Explicitly clean (0 bugs)

- `src/rt32/ppc32_a64_emit.h`, `ppc32_a64_emit.c`, `ppc32_a64_emit2.c`: all integer/logical/shift/bitfield/multiply/divide/exclusive/crypto encodings, guest `[xG, wAddr, uxtw]` forms, REV/REV16, NZCV/CSEL/CSNEG, branch-patch math, RAS push/pop, slot/IBTC/RAS chaining, and exit stubs verified word-by-word; all `offsetof` immediates (`ras_top` 640/4, `ras` entry 680/8, `ibtc` entry 2728/8, `pending_signals` 584/8) are in range and aligned. Stale `#480`/`#504` comments do not match the (correct) computed immediates, but comments are not behavior. Dead helpers (`arm_shift_reg_w`, `update_nzc_*`, `xt_add`, `pkh`, `usad8`, `sml*`, `umaal`, `mull`, `guest_ldrd/strd`, crypto, LDXR/STXR) have no callers.
- `src/dbt/trampoline_a64.S`: offsets (`nip` 0x100, `guest_base` 0x228, `chain_hits` 0x260, `exit_reason` 0x288, `exit_dest` 0x294) match the pinned asserts; TRAP/FAULT nip discipline, `x24` fold, callee-saved restores all correct. `x18` never referenced in any emitter, trampoline, or raw word (spot-decoded all `Rm/Rn/Rd` fields).
- `src/dbt/dbt.c`: block budget/page-cut/fallback termination, FP-lookahead batching (closes before every FPSCR observer, exit, and cut), SMC hook register preservation (`w22` live, `w0-w7`/`d16-d23`/`x30` spilled, `x19-x22`/`x27` intact, NZCV dead), CBNZ/B skip polarity, and SYSCALL/UNDEF/TRAP/FAULT commit discipline all match the oracle conventions (`sc` rewind `exit_dest-4`, trap `nip` at the word).
- `src/dbt/cache.c`: W^X flip-then-execute with exact-span I-cache invalidation on both OS paths, epoch/pagever/snapshot-miss handling, skip-severing of the executing entry, and range math (32-bit wrap flushes) correct.
- `src/dbt/emit_int.h`, `src/dbt/emit_int.c`: GPR write-through cache, EA wrap, overlap/writeback ordering, `sraw` CA rule, `adde/subfe` double-carry, `ME/ZE` carry rules, OE overflow forms, `rlwinm` mask wrap, BO/BI decoding, TO-bit mapping, `sc` reservation handling, `dcbz` alignment, and `lmw/stmw/lswi/stswi` loop/exit shapes all match the oracle.
- `src/dbt/emit_fp.h`, `src/dbt/aot/*`, `src/dbt/difftest.*`: no live defects (AOT note-path uses only `site_count=0`; `AOT_RUN_COUNT_OFF` 12 matches the header layout).
- Scope notes: no Soft-TLB inline fast-path exists in the DBT subsystem — all guest traffic uses direct `[xG, w22, uxtw]` mapping with host-MMU faults plus the low-guard check, so item 4 has nothing to fault; `gpr_hi` split storage with cache invalidation on pair stores is sound; no `A32H_CAP_ICACHE_TRAP_IALLU` handling lives in this subsystem.
