I now have all the evidence needed. Here is the complete review.

---

## Round-8 Remediation Review — commit `0cd58c7`

### P32-R8-1 — `bclr`/`bcctr` target missing `& ~3` — **VERIFIED**

**File:** `src/dbt/emit_int.c:544-547`

The fix inserts `MOV w12, #0xFFFFFFFC` + `AND w15, w15, w12` (32-bit W-register AND) after loading LR/CTR and before `a64_emit_exit_branch_reg`. This clears the low 2 bits, matching the oracle's `branch_to: nip = target & ~3U` at `src/interp/interp.h:405`. Placement is correct — after the conditional `ei_store_lr(b, next)` and before the exit stub.

---

### P32-R8-2 — `fp_fprf` C-bit misclassifies Inf, `-0.0`, NaN — **VERIFIED**

**File:** `src/dbt/emit_fp_class.c:48-103`

Two bugs fixed:

1. **Pattern reload** (lines 70-74): The old code extracted mantissa from `x12` after it had been clobbered by `ei_cset(b, EI_T2, ...)` (which writes `w12`). The new code re-emits `FMOV x12, D(vd)` before the mantissa extract. Without this, `isMantZero` was computed from the isZeroExp flag (0 or 1), not the actual bit pattern.

2. **C-bit formula** (lines 78-98): Old formula `C = isInf | isDenorm`. New formula `C = isQNaN | isDenorm | isNegZero`, computed as:
   - `EI_B = isZeroExp & ~isMantZero` (isDenorm)
   - `EI_T2 = isZeroExp & isMantZero & sign` (isNegZero)
   - `EI_T = isMaxExp & ~isMantZero & quiet` (isQNaN)
   - `C = EI_T | EI_B | EI_T2`

Cross-checked against oracle `fp_fprf64` (`src/interp/fp.h:174`): +Inf→0x05(C=0), -Inf→0x09(C=0), -0→0x12(C=1), QNaN→0x11(C=1), +denorm→0x14(C=1). All match.

---

### P32-R8-3 — `frsp` widens the low word instead of rounding — **VERIFIED** (false positive in report)

**File:** `src/dbt/emit_fp.c:583,589`

The defect report stated the narrow step (FCVT S0, D0) was missing. However, the narrow was already emitted by the `base` parameter line at `emit_fp.c:583`:
```c
a64_emit(b, base | (((in >= 3U) ? 11U : 0U) << 5) | 0U);
```
The caller at line 850 passes `base = 0x1E624000U` (FCVT S0, D0), confirmed unchanged in the parent commit. The commit annotates this with a comment `(base line above, P32-R8-3)` but makes no functional change for P32-R8-3 specifically. The narrow-then-widen sequence was already correct.

---

### P32-R8-4 — `fcmpu`/`fcmpo` leaves stale FPSCR FPRF — **VERIFIED**

**File:** `src/dbt/emit_fp.c:433-436`

The fix inserts after the VXVC check:
```c
BIC  w9, w9, #0xF000       // clear FPCC [15:12]
ORR  w9, w9, w11, LSL #12  // insert compare field
```

Mask `0xF000` covers bits [15:12] only, preserving bit 16 (C class bit). This matches the oracle exactly: `ctx->fpscr = (fpscr & ~0xf000) | ret<<12`. EI_R (w11) is still live from `fp_nzcv_field` — no intervening code clobbers it.

---

### P32-R8-5 — FPSCR FR never maintained — **VERIFIED**

**Files:** `emit_fp.c:204`, `emit_fp.h:63-78`, `emit_fp_class.c:214-321`

Three-part fix:

1. **`fp_conv_end` (line 204):** Now clears both `FP_FI | FP_FR` (was only `0x00020000` = FI). Matches oracle's `fp_flags_arith` which clears both per-op.

2. **`fp_fr_arith` (emit_fp_class.c:220-284):** Post-store FR fixup for arithmetic. Dispatches on rounding mode:
   - **RN (mode=0):** Saves RN result in d6, switches FPCR to RZ via `ORR 0x00C00000`, redoes the op into d5, restores FPCR via BIC. FR iff `|d6| > |d5|` (FABS + FCMP HI). The BIC restore is safe because this path only executes when guest mode is RN (FPCR RMode = 0b00).
   - **RZ (mode=1):** FR=0 always (truncation never rounds up). Correct.
   - **RP (mode=2):** FR iff result > +0 (positive result rounds up). Correct.
   - **RM (mode=3):** FR iff result < -0 (negative result rounds up). Correct.

3. **`fp_fr_mag` (emit_fp_class.c:292-321):** Post-store FR fixup for converts (frsp/fctiw). Skips IOC (invalid) and exact ops. For to_int, uses `SCVTF W→D` to get comparable double. FR iff `|converted| > |original|`. Matches oracle `fp_rounded_up`.

Callers verified: `fp_arith:400` (arithmetic), `spe_cvtf:596` (frsp), `spe_cvti:681` (fctiw). All save inputs to d7 before the operation and call the appropriate FR fixup after `fp_round_end`/`fp_conv_end`.

---

### P32-R8-6 — Invalid-arithmetic sub-bit always VXSNAN — **VERIFIED**

**Files:** `emit_fp.c:371-373,437-438`, `emit_fp.h:67-72`, `emit_fp_class.c:148-212`

The fix replaces the hard-coded `ioc_sub = FP_VXSNAN` with a preclassification step `fp_inv_classify` that sets w17 per-operation:

| iop | Condition | Sub-bit | Oracle reference |
|-----|-----------|---------|-----------------|
| 0 (add) | Both Inf, opposite signs (fcmp NE) | VXISI | `fp_inv2` op==0 |
| 1 (sub) | Both Inf, same signs (fcmp EQ) | VXISI | `fp_inv2` op==1 |
| 2 (mul) | 0×Inf either way (zeroA&infB \| zeroB&infA) | VXIMZ | `fp_inv2` op==2 |
| 3 (div) | 0/0 then Inf/Inf (checked sequentially) | VXZDZ / VXIDI | `fp_inv2` op==3 |
| >3 | Default (fused/sqrt/compare) | VXSNAN | — |

Cross-checked each lane against oracle `fp_inv2` (`src/interp/fp.h:364-387`): sign polarity, commutativity, and mutual exclusion all match. The `fp_isinf` helper checks bit patterns in integer registers (no FPSR side effects). The `fcmp` in the add/sub sign check cannot produce spurious IOC (only fires for SNaN, which the actual FP op would also flag). `fp_accum` (line 150) now ORs w17 from the IOC path instead of a hard-coded mask.

For compares (`fp_cmp:437-438`): w17 is set to `FP_VXSNAN | FP_VX | FP_FX` (compare invalid is always VXSNAN; VXVC is handled separately at line 429). Correct.

New `#define` constants in `emit_fp.h:49-54` match the PowerPC FPSCR bit definitions.

---

### Newly Introduced Bugs

**None found.** Verified:

- No FPSR contamination from `fp_inv_classify`'s pre-operation `fcmp` (SNaN → IOC set, but actual op also sets IOC; non-SNaN Inf → no IOC from fcmp).
- v1/v2 operand registers survive through to `fp_fr_arith`'s redo (no intermediate writes).
- `fp_fr_arith` FPCR RZ/restore via ORR/BIC is correct for the RN-only path.
- `fp_fr_arith`/`fp_fr_mag` reload fpscr after the main store, so the FR fixup is additive.

---

### Curated C11 Compliance

| Check | Result |
|-------|--------|
| VLAs | None |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| `emit_fp.c` | **899 lines** (limit 900 — 1 line headroom) |
| `emit_fp.h` | 80 lines |
| `emit_fp_class.c` | 321 lines |
| `emit_int.c` | 790 lines |

All files pass `<= 900` lines. `emit_fp.c` at 899 is at the boundary — any future addition will require splitting or moving code.

---

### Verdict

| Item | Status | Notes |
|------|--------|-------|
| P32-R8-1 | **VERIFIED** | Correct `& ~3` mask on indirect branch target |
| P32-R8-2 | **VERIFIED** | Pattern reload + correct C = QNaN\|denorm\|neg-zero |
| P32-R8-3 | **VERIFIED** | Narrow was already present via `base`; commit annotates |
| P32-R8-4 | **VERIFIED** | FPCC stored under 0xF000, preserving C bit |
| P32-R8-5 | **VERIFIED** | FR cleared per-op, set by post-store fixups |
| P32-R8-6 | **VERIFIED** | Per-op IOC mask mirrors oracle `fp_inv2` |
| New bugs | **0** | — |
| C11 compliance | **PASS** | emit_fp.c at 899/900 |
