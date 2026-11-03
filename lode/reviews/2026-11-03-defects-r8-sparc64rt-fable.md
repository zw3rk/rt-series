I have all the evidence. Here is the full static review.

---

## Round-8 DBT/JIT Remediation Review — commit `f9ac1f8`

**Scope:** 4 files, +19/−6 lines. Static diff + file inspection only.

---

### S64-R8-1 — TCC immediate ignores rs1: **VERIFIED**

**Review doc:** `emit_cond.c:469` — immediate path computed `trapno = imm & 0x7F`, dropping `rs1`. Interp does `(R[rs1] + imm) & 0x7F`.

**Fix at `emit_cond.c:470-473`:**
```c
e_ld64(b, ES0, d->rs1);
sb_mov_imm64(b, ES1, (uint64_t)d->imm);
sb_add_reg(b, true, false, ES0, ES0, ES1);
sb_ubfm(b, true, ES0, ES0, 0U, 6U);
```

Now structurally identical to the register path (lines 475-478). Loads `rs1` into ES0, adds the immediate, masks bits [6:0]. Matches interp semantics exactly.

---

### S64-R8-2 — ADDXCC/SUBXCC icc nibble from stale flags: **VERIFIED**

**Review doc:** `emit_int.c:242` — `e_emit_addsubcc` used no-S ADC/SBC for the with-carry 32-bit pass, so `e_host_to_nibble` read stale host flags from the carry reseed CMP rather than the actual result.

**Fix at `emit_int.c:679-683`:** The dispatch table now routes ADDXCC/SUBXCC to `e_emit_alu_helper` (the C runtime helper `s64_rt_alu`) instead of `e_emit_addsubcc`:

```c
case SPARC64_OP3_ADDCC:
case SPARC64_OP3_SUBCC:
    return e_emit_addsubcc(ec, d);   /* no carry — inline flags work */
case SPARC64_OP3_ADDXCC:
case SPARC64_OP3_SUBXCC:
    return e_emit_alu_helper(ec, d); /* carry — delegate to C helper */
```

Pre-commit, all four cases fell through to `e_emit_addsubcc`. The helper computes flags correctly via the interpreter backend. Trade-off: helper-call overhead for ADDXCC/SUBXCC, but correctness is restored. `e_emit_addsubcc` remains correct for the non-carry ADDCC/SUBCC paths.

---

### S64-R8-3 — WR %asi missing &0xFF: **VERIFIED**

**Review doc:** `emit_int.c:438` — stored the full XOR result without masking. Interp does `asi = (a ^ b) & 0xFF`.

**Fix at `emit_int.c:439-440`:**
```c
case SPARC64_ASR_ASI:
    sb_ubfm(b, false, ES1, ES1, 0U, 7U);   /* & 0xFF */
    sb_ldst_imm(b, false, false, ES1, ECTX, E_OFF_ASI);  /* STRB */
    break;
```

`UBFM W, W, #0, #7` extracts bits [7:0], equivalent to `& 0xFF`. The subsequent byte store writes the masked value. Matches interp.

---

### S64-R8-4 — ALIGNADDRL decoded as ALIGNADDR: **VERIFIED**

**Review doc:** `emit_int.c:453` — `e_emit_align` always extracted `sum & 7` regardless of opf. Interp: ALIGNADDRL uses `(0 - sum) & 7`.

**Fix at `emit_int.c:464-469`:**
```c
if (d->opf == SPARC64_OPF_ALIGNADDRL) {
    sb_sub_reg(b, true, false, ES1, 31U, ES0);   /* ES1 = 0 - sum */
    sb_ubfm(b, false, ES1, ES1, 0U, 2U);         /* & 7 */
} else {
    sb_ubfm(b, false, ES1, ES0, 0U, 2U);         /* sum & 7 */
}
```

`SPARC64_OPF_ALIGNADDRL` is `0x1A` (defined at `interp.h:76`). The SUB uses register 31 (XZR) as first source, giving `0 - ES0`. The UBFM W-form extracts bits [2:0]. Interp at `interp.c:142`: `(UINT64_C(0) - sum) & UINT64_C(7)`. Semantics match — low 3 bits of the 64-bit negate are width-independent.

---

### S64-R8-5 — regasi lost in pack_b: **VERIFIED**

**Review doc:** `emit_mem.h:92` — `s64_jrt_mem` never unpacked `regasi`; `e_call_mem` never packed it. Alternate-ASI loads (`lda [%g1]%asi,%g2`) saw `asi=0xFF` instead of the live `%asi` register value.

**Fix (unpack) at `emit_mem.h:94`:**
```c
d.regasi = (uint8_t)((pack_b >> 40) & 1U);
```

**Fix (pack) at `emit_mem.h:188-189`:**
```c
uint64_t pack_b = ((uint64_t)(uint32_t)d->imm) |
    ((uint64_t)d->asi << 32) |
    ((uint64_t)(d->regasi & 1U) << 40);
```

pack_b layout: bits [31:0] = imm, [39:32] = asi, [40] = regasi. No field collision. The comment at line 76-77 is updated to document bit 40. Pre-commit, `d.regasi` in `s64_jrt_mem` was left uninitialized — now explicitly unpacked. The `sparc64_exec_load/store/atomic` backends use `d.regasi` to resolve via `cpu->asi`.

---

### S64-R8-6 — dbt_step_one allows chaining: **VERIFIED**

**Review doc:** `dbt.c:604` — `false` selected `sparc64_dbt_enter` (live epoch, chaining on). Single-step must use `enter_step` (zero epoch).

**Fix at `dbt.c:604`:**
```c
return dbt_enter_block(ctx, mem, mc, dbt, code, true);
```

`dbt_enter_block` (lines 449-453): `single=true` calls `sparc64_dbt_enter_step` which passes a zero epoch word, preventing probe chains. Correct for difftest single-step.

---

### Newly Introduced Bugs: **None found**

- **S64-R8-1:** The `is_imm` and register paths are now structurally parallel — no asymmetry introduced.
- **S64-R8-2:** ADDCC/SUBCC still reach `e_emit_addsubcc` (non-carry inline path unchanged). ADDXCC/SUBXCC degrade to helper but are correct.
- **S64-R8-3:** The UBFM precedes the store; no clobber risk (ES1 is the same source and dest).
- **S64-R8-4:** Only ALIGNADDRL (`opf == 0x1A`) takes the negate branch; ALIGNADDR falls through to the original code.
- **S64-R8-5:** Bit 40 is free in pack_b (bits 41+ are unused). No truncation risk — `d->regasi` is a `uint8_t` masked to `& 1U`.
- **S64-R8-6:** Boolean flip; `dbt_enter_block` already handles both paths correctly.

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| File sizes | `dbt.c`=742, `emit_cond.c`=494, `emit_int.c`=738, `emit_mem.h`=271 — all **<= 900** |
| VLAs | None |
| `.c` includes | None |
| Banned functions (`sprintf`/`strcpy`/`strcat`/Annex K) | None |
| `_Generic` / `<threads.h>` | None |

---

### Verdict Summary

| ID | Status | Evidence |
|---|---|---|
| S64-R8-1 | **VERIFIED** | `emit_cond.c:470-473` — rs1+imm path mirrors register path |
| S64-R8-2 | **VERIFIED** | `emit_int.c:679-683` — ADDXCC/SUBXCC rerouted to C helper |
| S64-R8-3 | **VERIFIED** | `emit_int.c:439` — UBFM mask before STRB |
| S64-R8-4 | **VERIFIED** | `emit_int.c:464-469` — opf branch + SUB-from-zero |
| S64-R8-5 | **VERIFIED** | `emit_mem.h:94,188-189` — regasi packed/unpacked at bit 40 |
| S64-R8-6 | **VERIFIED** | `dbt.c:604` — `true` selects `enter_step` |

All 6 items verified. No regressions. C11 discipline holds.
