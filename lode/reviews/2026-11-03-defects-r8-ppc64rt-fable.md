I now have all the evidence needed. Here's the review.

---

## Round-8 Remediation Review — commit `3d42489`

### P64-R8-1: Shift count truncated — **VERIFIED**

**Defect:** Register-form shifts masked the count with 5/6 bits (`31u`/`63u`) instead of the ISA-required 6/7 bits (`63u`/`127u`), and AArch64 `LSLV`/`LSRV`/`ASRV` reduce modulo the register width, so counts >= 32/64 wrapped instead of yielding zero or sign-fill.

**Evidence (emit_int.c:349):** Mask widened to `is64 ? 127u : 63u`, matching `interp.h:579–580,589–590,601,629`.

Three distinct code paths now handle the `n >= lim` overflow:

| Path | Lines | Behavior |
|---|---|---|
| Logical shifts (`SLW`/`SRW`/`SLD`/`SRD`) | 352–368 | `CMP R_U, lim`; branch to `big` on CS; normal path emits `LSLV`/`LSRV` + optional 32→64 extension; big path emits `R_R = 0`. Matches `interp.h:582–583,592–593`. |
| Arithmetic immediate (`SRAWI`/`SRADI`) | 372–378 | No bound check needed — immediate `d->sh` is masked to 5/6 bits, always < lim. Direct ASR + `e_sra64_ca()`. Correct. |
| Arithmetic register (`SRAW`/`SRAD`) | 380–401 | `CMP R_U, lim`; big path: `ASR R_A, #63` (sign-fill), then CA = `(R_A < 0) AND (R_A != 0)` via `CSET`+`AND`+`e_xer_store_ca`. Matches `interp.h:608–613,633–640`. |

The `e_add_reg(e, 1u, 31u, R_U, R_T3, true, true)` encodes `SUBS xzr, R_U, lim` — carry set when `R_U >= lim` (`emit_core.h:240–246`). Branch/patch pattern (`e_bcond` → `at26` → `patch5` → `patch26`) is the standard forward-branch-over used elsewhere in the file.

**Test coverage:** `tests/test_dbt_if.c:272–334` — 14 new inline-asm checks covering `slw/33`, `srw/32`, `srw/63`, `sld/64`, `srd/64`, `sld/127`, `sraw/32`(neg+pos), `sraw/63`, `srad/64`, `srad/127`.

---

### P64-R8-2: SUBFO OV missing — **VERIFIED**

**Defect:** `e_xo()` only computed `OV`/`OV32`/`SO` for `ADD` with `OE`, not `SUBF` with `OE`. SUBFO fell through to `e_alu_tail` with XER unchanged.

**Evidence (emit_int.c:155–161):** Condition widened to `(d->id == PPC64_OP_ADD || d->id == PPC64_OP_SUBF) && d->oe`. SUBF branch computes:
- `T1 = R_B ^ R_A` (= y ^ x)
- `T2 = R_B ^ R_R` (= y ^ result)

This matches the interpreter at `interp.c:652`: `interp_alu_ov(cpu, y ^ x, y ^ r2)` where `y = GPR[RB]`, `x = GPR[RA]`, `r2 = y - x`.

`e_ov2` (`emit_int.c:83–86`) computes `MSB(s1 AND s2)` at both 64-bit (OV) and 32-bit (OV32) widths, then stores OV, OV32, and sticky SO via `e_xer_store_ov`. Correct.

The result computation at line 136 is `e_add_reg(sf=1, rd=R_R, rn=R_B, rm=R_A, sub=true)` = `R_R = R_B - R_A`, which is the PPC64 `SUBF` semantic. OV operands are derived after the result is in `R_R`, so no ordering issue.

**No double-update:** ADD/SUBF bypass the `xtab` loop (carrying forms, lines 140–153) and never enter `e_addsub`'s own OE path at line 116–124.

**Test coverage:** `tests/test_dbt_if.c:504–520` — three SUBFO cases: 64-bit overflow, 32-bit overflow, no-overflow.

---

### P64-R8-3: Prefix boundary ignored — **VERIFIED**

**Defect:** `ppc64_dbt_fetch()` accepted a prefixed instruction (PO=1) at `PC % 64 == 60`, which straddles the 64-byte boundary. The interpreter rejects this as `INST_MISALIGNED`.

**Evidence (fetch.c:115–118):**
```c
if ((pc & UINT64_C(63)) == UINT64_C(60))
    return false;
```

Placed after detecting PO=1 (line 113: `(w0 >> 26u) == 1u`) and before fetching the suffix word. `return false` forces fallback to `ppc64_step()`, which raises `PPC64_TRAP_INST_MISALIGNED` (interp.c:99). Matches the ISA v3.1 §1.9 requirement.

**Test coverage:** `tests/test_dbt_fetch.c` — four scenarios: prefix at offset 60 (declined), prefix at offset 52 (accepted, len=8), plain word at offset 60 (accepted, len=4), misaligned start (declined). Uses a stub `ppc64_mem_ops_t` with LE byte order matching `ppc64_dbt_fetch_word` (fetch.c:30–31).

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None (`grep -rn` clean) |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| `_Generic` / `<threads.h>` / Annex K | None |
| File sizes | `emit_int.c`: 740, `fetch.c`: 166, `test_dbt_fetch.c`: 121, `test_dbt_if.c`: 585 — all <= 900 |

---

### Newly Introduced Bugs

None found. Specific checks:

1. **Register pressure in the big paths:** `R_T3` is clobbered by the CMP but is re-loaded from `OFF_XER` in both `e_sra64_ca` (normal path) and the manual CA computation (big path). No stale-register issue.
2. **Arithmetic shift CA for SRAW in big path:** After `e_sbfm(R_A, R_A, 31u)` sign-extends the 32-bit source to 64-bit, `CMP R_A, xzr` correctly sets N (=neg32) and Z (=zero32). `CA = neg32 AND lo!=0` is correct.
3. **SRAWI/SRADI immediate early return:** Immediate shift amounts are already bounded below `lim` (5/6-bit field), so the early return at line 378 without a bound check is safe.
4. **Makefile test target:** Links `fetch.c`, `decode.c`, `decode_fp.c` with `-Isrc`, matching `test_dbt_fetch.c`'s `#include "dbt/fetch.h"`.
5. **SUBFO test values:** `0x7FFFFFFFFFFFFFFF - 0xFFFFFFFFFFFFFFFF = 0x8000000000000000` (overflows), `0x7FFFFFFF - 0xFFFFFFFF = 0xFFFFFFFF80000000` (OV32), `3 - 10 = 0xFFFFFFFFFFFFFFF9` (no overflow). All correct.
