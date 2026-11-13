## Round-7 remediation review: commit e9eaa7a (static only, no builds or tests run)

**Bottom line:** 23 of 30 items verified, 6 partial, 1 regression. The regression is serious: the rewritten `srad`/`sradi` carry mask selects the kept bits instead of the discarded bits, so CA is set for every negative operand. That breaks the common `sradi; addze` signed-division idiom. The `addex` executor case is also unreachable dead code.

### Per-defect classification

| ID | Status | Notes |
|---|---|---|
| R7-1 darn | VERIFIED | Host `getrandom`/`getentropy`, all-ones sentinel on failure, L=0 truncates to 32 bits. Pre-existing: `ra > 2` also rejects reserved bits 18:20 that the ISA ignores. |
| R7-2 lqarx/stqcx atomicity | PARTIAL | 16-byte LR/SC now go through `vm_atomic_slow` with epoch plus both-halves validation. `fp_write` and `str_write` now route through `interp_mem_write`. Residual: the 16-byte path is still read/compare/write with no lock or 128-bit CAS, so it is exact only single-threaded (the code comments admit this). |
| R7-3 TLB index | VERIFIED | Uses `PPC64_TLB_SIZE - 1`. |
| R7-4 GPR pair order | VERIFIED | RT = EA+8 half, RT+1 = EA half on both atomic and fallback paths, store mirrors it. |
| R7-5 dcbt vs lhbrx | VERIFIED | Table now 790/918. The cache-hint handler at `src/interp/interp.c:568` still covers 246/278. |
| R7-6 XA/XB bits | VERIFIED | `src/interp/fp_vsx.c:39`. The xscmpudp helper in power10.h was already correct. |
| R7-7 VSX arithmetic | PARTIAL | Scalar add/sub/mul/div and all fused forms (sp and dp) implemented with correct a/m operand mapping. `xvadddp/xvsubdp/xvmuldp/xvdivdp` implemented. SPEC §2.2 also requires `xvmadd*`, which still traps. No vector single-precision forms. |
| R7-8 shift counts | REGRESSION | `slw/srw/sld/srd/sraw` are correct. `srad/sradi` are now wrong: see finding 1. |
| R7-9 srad CA32 | REGRESSION | CA is copied into CA32 as required, but CA itself is now wrong (finding 1). |
| R7-10 subfo | VERIFIED | `interp_alu_ov(cpu, y^x, y^r2)` is the correct subtraction overflow predicate. Sticky SO set, CA untouched. |
| R7-11 div by zero OV | VERIFIED | Both widths set `ov = true`, OE-gated. |
| R7-12 addex | PARTIAL | Decode narrowed to CY=0 and header text fixed. The executor `case 85u` is unreachable and semantically wrong (finding 2). Net behaviour: addex still traps illegal. |
| R7-13 prtyw | VERIFIED | |
| R7-14 setnbc | VERIFIED | 0 / all-ones. |
| R7-15 crnor/crorc | VERIFIED | Exec adds XO 33, decoder CRORC at 417, CRNOR at 33 already present. |
| R7-16 prefix validation | PARTIAL | Non-splat pairs now go through `decode_prefixed`, which rejects wrong form and reserved bits 18,19,21:23. Splat forms (nibble 2/3) still bypass the decoder, and prefix bits 9:15 of the 8RR form are not checked. |
| R7-17 plxssp/pstxsd/pstxssp | VERIFIED | 8LS-only, VSR[RT+32], lane 1 zeroed on load, faults carry length 8. |
| R7-18 64-byte boundary | PARTIAL | Trap at prefix PC with `INST_MISALIGNED` before suffix fetch. `SPEC.md:78` still describes a "cross-page 8-byte prefixed" fallback that can no longer occur. |
| R7-19 update-form order | VERIFIED | Check moved ahead of the transfer in `mem_access`. FP D-form updates already validated first. |
| R7-20 lqarx overlaps | VERIFIED | Matches QEMU `gen_lqarx`. |
| R7-21 mtvsrdd RA=0 | VERIFIED | Both fp.c and vec.c paths. |
| R7-22 TX bit | VERIFIED | mtvsrwa, mtvsrws, mfvsrwz, mtvsrwz, mfvsrld all use the 6-bit index. |
| R7-23 vsumsws | VERIFIED | Reads VB lane 0. |
| R7-24 VSCR/SAT | VERIFIED | mfvscr/mtvscr at shifted XO 770/802 with zero-field checks. SAT (bit 0) set by vaddubs, vsububs, vsumsws. |
| R7-25 fcfid | PARTIAL | Guest rounding installed, XX and FPRF recorded. FI is not cleared when the conversion is exact (stale FI survives). Inexact test needs a long double wider than 64 bits, true on the aarch64-linux target but not on a macOS host build. |
| R7-26 fcmpu FPCC | VERIFIED | FPCC bits 12:15 and VXSNAN; xscmpudp uses the same helper. |
| R7-27 single overflow | VERIFIED | `|ref| > FLT_MAX` catches the RZ case. Minor over-report in the band below FLT_MAX plus half an ulp, where unbounded-exponent rounding would give FLT_MAX without overflow. |
| R7-28 double rounding | VERIFIED | Removing the `LDBL_MANT_DIG` guard lets the absorb nudges run on binary128. The 1+2^-24 + 2^-200 case now rounds up. mul is exact in 113 bits and div satisfies the 2p+2 rule. |
| R7-29 VX causes | VERIFIED | `ppc64_fp_invalid_cause` classifies ISI/IDI/ZDZ/IMZ for scalar, vector, and fused forms with correct sign and operand roles. |
| R7-30 XER frames | VERIFIED | Shared `ppc64_xer_to_guest` / `ppc64_xer_from_guest` in cpu.h, used by mfxer, mtxer, and both sigframe directions. No other verbatim XER copies found in os/vm/dbt. |

### New defects introduced

1. **srad/sradi carry mask inverted (HIGH).** `src/interp/interp.h:611` computes the discarded bits as `a & (0 - (1 << n))`, which is the mask of bits n..63, not 0..n-1. The old code `a & ~(~0 << n)` was correct. For any negative RS and 1 <= n <= 63, bit 63 is inside the mask, so CA and CA32 are always set. Example: `sradi r3,r3,1` with r3 = -2 should give CA = 0; it now gives CA = 1, and the following `addze` yields 0 instead of -1. Compilers emit this sequence for signed division by powers of two.

2. **addex executor unreachable and wrong (MEDIUM).** The switch at `src/interp/interp.c:655` keys on `xo9 = (raw >> 1) & 0x1FF`, which is 170 for addex, so `case 85u` never matches and the instruction still falls to the illegal default. The case body also writes CA/CA32 and preserves OV, whereas the ISA and QEMU consume OV as carry-in and write the carry-out to OV/OV32 with CA/CA32 unchanged.

3. **DBT parity risk (not verified).** Shift, carry, and subfo semantics changed only in the interpreter. `src/dbt/` was not touched, so `--difftest` will diverge wherever the DBT kept the older rules. This needs a run, which was outside this review.

4. **Cosmetic.** `src/interp/fp_pack.c` lacks a trailing newline.

### Build-shape checks (static)

- The Makefile collects sources with `find src -name '*.c'`, so the two new files `fp_conv.c` and `fp_pack.c` are picked up without edits.
- All touched files stay under the 900-line ceiling. Largest is `src/interp/interp.c` at 815 lines.
- The `ppc64_vm_reserve` signature change updated every caller and the test stub in `tests/test_vm_prova.c`.
- `tests/test_vm_prova.c` still links against `fp_cmpu`; it now lives in `fp_conv.c`, which the wildcard includes.

Recommended next step: fix finding 1 by restoring `a & ((UINT64_C(1) << n) - 1)` for the 1..63 case, then rekey addex on `xo9 == 170` with OV/OV32 as the carry chain, and run the interpreter oracle tests plus `--difftest`.
