I have all the evidence. Here's the complete review.

---

## Round-8 DBT/JIT Remediation Review — Commit `0c7cf01`

### Per-Item Verdicts

**LA64-R8-1 — LDPTR/STPTR wide offset** | **VERIFIED**
- `emit_ldst.c:107`: Guard `if (d->rj != 0u && (d->imm < -4095 || d->imm > 4095)) return -1;` placed before any emission. Falls back to interp for offsets outside the 12-bit `a64e_add_imm` range. The `rj == 0` exemption is correct: that path takes the full 64-bit `a64e_mov_imm64` at line 112-113, which has no width restriction.

**LA64-R8-2 — REVB_2W emits word swap, not byte-reverse** | **VERIFIED**
- `emit_int.c:648`: Was `e_extr(..., 32)` (EXTR = ROR #32 word swap). Now `e_1op(e, d, 0xDAC00800u)` = REV32 X. Encoding verified: `0xDAC00800` = `1101_1010_1100_0000_0000_10nn_nnnd_dddd`. Matches interp `bswap32` per-word at `interp.c:390-396`.

**LA64-R8-3 — REVB_4H emits REV32 X, needs REV16 X** | **VERIFIED**
- `emit_int.c:645`: Was `0xDAC00800u` (REV32 X). Now `0xDAC00400u` (REV16 X). Encoding verified: `0xDAC00400` = REV16 Xd, Xn. Matches interp halfword-swap at `interp.c:382-387`.

**LA64-R8-4 — REVB_2H misses mask and SXTW** | **VERIFIED**
- `emit_int.c:630-641`: Was `e_1op(e, d, 0xDAC00400u)` (REV16 X full-width, no sign-extend). Now:
  - `0x5AC00400u` = REV16 **W**d, Wn (32-bit form, upper 32 zeroed)
  - `0x93407C00u` = SXTW (sign-extend bit 31 to 64)
  - Uses `e_get_gpr` + explicit `rd == 0` early-return. When `rj == 0`, `e_get_gpr` returns XZR (31u), producing 0 → correct.
  - Matches interp `sx32(halfword_swap(low32))` at `interp.c:373-380`.

**LA64-R8-5 — MULW_D_WU sign-extends rj instead of zero-extending** | **VERIFIED**
- `emit_int.c:488`: Was `e_1s(e, 0x93407C00u, HT, aj)` (SXTW = sign-extend). Now `e_rrr(e, 0x2A000000u, HT, 31, aj)` = ORR WHT, WZR, Waj = MOV WHT, Waj. The W-form implicitly zeroes bits [63:32]. Both operands now zero-extended before `MUL X` at line 490. Matches interp unsigned cast at `interp.c:211-212`.

**LA64-R8-7 — FMOV.S skips nanbox, mistags cache** | **VERIFIED**
- `emit_fp.c:258-259`: For `.S` (`is_d == 0u`), applies `a64e_log_imm(e, 1, 0, HJ, HJ, 1, 32, 31)` = ORR Xd, Xn, #0xFFFFFFFF00000000 (forces upper 32 to ones = nanbox). Encoding verified via `a64e_log_imm` base table: `is_or=1, is_w=0` → `0xb2000000` (ORR imm 64-bit), N=1 immr=32 imms=31 decodes to mask `0xFFFFFFFF00000000`.
- `emit_fp.c:261`: Cache tag changed from always `1u` (double) to `is_d != 0u ? 1u : 0u` — tags `.S` as single, `.D` as double. Matches interp `fp_set_s` nanbox at `fp_vec_priv.h:400`.

**LA64-R8-8 — MOVGR2FRH.W shifts wrong way** | **VERIFIED**
- `emit_fp.c:306`: Was `a64e_ubfm(e, 0, HT, HJ, 32, 63)` — UBFM with immr=32, imms=63 → LSR #32 (shift right, discards the value). Now `a64e_ubfm(e, 0, HT, HJ, 32, 31)` — immr=32, imms=31 < immr → UBFIZ #32, #32 (extract low 32 bits, shift left by 32). The full sequence: clear HK upper half (AND #0xFFFFFFFF at line 305), deposit shifted HJ via ORR (line 307). Matches interp deposit at `fp.c:573-576`.

**LA64-R8-9 — VAND.V/VORN.V ignores vk** | **NOT APPLICABLE (false positive in defect report)**
- The commit title says "LA64-R8-1..9" but the diff contains **no change** to the `0x3893/0x3894` vector logic path. Pre-commit `emit_fp.c:693` already reads `v_halves3(e, vd, vj, vk, ...)` where `vk` is decoded from the instruction word at line 648 (`unsigned vk = (w >> 10u) & 31u`). The defect was falsified — the code was already correct.

### Collateral Change

**Makefile line 63**: Adds `src/os/safe_syscall_a64.S` to `U0_DARWIN_SRCS`. Pre-commit, this was missing while the companion `U0_DARWIN_BACKEND` (line 65) already had it. This is a legitimate Darwin build fix, not an R8 defect item.

### Newly Introduced Bugs

None found. All encoding constants verified against the AArch64 ISA. The REVB refactoring correctly untangled a one-off rotation where each case had the *next* case's instruction (2H→4H's encoding, 4H→2W's encoding, 2W→word-swap instead of byte-reverse).

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| `_Generic` / `<threads.h>` / Annex K | None |
| File sizes | `emit_int.c` 819, `emit_fp.c` 866, `emit_ldst.c` 174 — all <= 900 |

### Summary

7 of 8 listed items (R8-1..5, R8-7, R8-8) are **VERIFIED** with correct AArch64 encodings matching the interpreter oracle. R8-9 was a **false positive** — the code was already correct before this commit. No regressions, no C11 violations.
