I have everything needed. Here is the report.

# Static review: commit 6d4d356 (LA64-R7-1..26 remediation)

Scope: diff of 6d4d356 against its parent plus the post-commit tree in `src/interp/`, `src/os/`, `src/vm/`, cross-checked against the Round-7 report and DEFECTS.md Section 7. QEMU master sources were consulted read-only for oracle semantics. No builds, guest binaries, or tests were run.

Headline: 17 items VERIFIED, 8 PARTIAL, 1 REGRESSION. The commit also introduces four new defects in the vector FP engine, one of which (vector compare) breaks every ordered `VFCMP`/`XVFCMP` condition.

## Summary table

| Item | Verdict | One-line reason |
|---|---|---|
| R7-1 | VERIFIED | `ld_bytes` returns status; `ld_sx`/`ld_zx` callers return before writeback |
| R7-2 | VERIFIED | AMO/vector/FP faults are guest signals; `die_at` only for undecoded ops |
| R7-3 | PARTIAL | Enables now trap before writeback, but Flags are set even when trapping |
| R7-4 | VERIFIED | Every store path calls `la64_vm_file_note_store`; failed CAS/SC do not |
| R7-5 | VERIFIED | Propagation invalidates reservations over destination alias ranges |
| R7-6 | PARTIAL | Address and trap fixed; signal/code and comparison signedness diverge |
| R7-7 | PARTIAL | W/WU fixed; 64-bit bounds still allow an undefined cast at 2^63 / 2^64 |
| R7-8 | PARTIAL | Decoder split is correct; new `VFFINT.S.WU`/`VFFINT.D.L` swap and LASX geometry bugs |
| R7-9 | REGRESSION | Families implemented, but `VFCMP` conditions and `VLDI` mode table are now wrong |
| R7-10 | VERIFIED | 32-bit seed, IEEE vs Castagnoli polynomial, complement removed |
| R7-11 | VERIFIED | `REVB.2H/4H/2W` match QEMU permutations |
| R7-12 | VERIFIED | Both words zero-extended |
| R7-13 | VERIFIED | Decoder rejects `msb < lsb`; `interp_step` turns decode failure into `SIGILL` |
| R7-14 | VERIFIED | Fetch alignment check and `amo_align` on all LL/SC/AM paths |
| R7-15 | PARTIAL | Reported `rd==rj` case rejected; exemptions diverge from oracle |
| R7-16 | VERIFIED | `amo_sx_n` applied at every width |
| R7-17 | VERIFIED | Zero-magnitude test before sign ordering in scalar and vector compare |
| R7-18 | VERIFIED | Sources snapshotted before writeback in all narrowing paths |
| R7-19 | PARTIAL | Cause cleared once and staged, but lanes overwrite instead of OR |
| R7-20 | VERIFIED | `.S` uses the signed low word |
| R7-21 | PARTIAL | Ties and sNaN handling fixed; two qNaNs return default NaN, oracle returns `fj` |
| R7-22 | VERIFIED | sNaN quieted with Invalid in both widths |
| R7-23 | VERIFIED | `FRSQRTE` estimates sync status |
| R7-24 | VERIFIED | Provisional Inexact cleared before Invalid |
| R7-25 | PARTIAL | Pre-round negation correct; NaN addend sign still flipped for FMSUB/FNMSUB |
| R7-26 | VERIFIED | Code field ignored, dispatch unconditional |

## Item notes (non-VERIFIED only)

**R7-3 (PARTIAL).** `fp_sync_checked` in `src/interp/fp_vec_priv.h:312` calls `fp_sync`, which ORs the new bits into Flags, then traps. QEMU's `update_fcsr0_mask` only applies `UPDATE_FP_FLAGS` on the non-trapping branch. The report's remediation explicitly asked for the nontrapping Flags rule. Same issue in `vfp_commit_checked` at line 328 and in `v_fp_step`. Staging of results is otherwise complete across all scalar paths. The one remaining plain `fp_sync` at `src/interp/fp.c:637` only covers register moves and `movgr2fcsr`, which is fine.

**R7-6 (PARTIAL).** `ldck_sx`/`stck` in `src/interp/interp_mem.h:153` now assert first and access `rj`. Two divergences remain. The fault is delivered as `SIGBUS`/`BUS_ADRALN`; Linux delivers `SIGSEGV`/`SEGV_BNDERR` for BCE and QEMU user-mode delivers `SIGSYS`/`SI_KERNEL`. Neither matches. The comparison is signed; QEMU's `helper_asrtgt_d`/`helper_asrtle_d` compare `target_ulong` operands, so addresses straddling the sign bit diverge from the oracle.

**R7-7 (PARTIAL).** `vf_cvt_lane` now rounds first. The 32-bit bounds are exact, but at `src/interp/fp_vec_priv.h:142` the literal `9223372036854775807.0` rounds to 2^63, so `rr == 2^63` passes and `(int64_t)rr` is undefined. Line 150 has the same problem with `18446744073709551615.0` and 2^64. The scalar `fp_ftint_ld` uses `>= 2^63` correctly.

**R7-8 (PARTIAL).** The `0x38A3`/`0x38A4` split by `esz` and the `0x38A5` family are correct against `insns.decode`. Two new bugs in `src/interp/fp_vec_cvt.c` are described under N2 and N3.

**R7-9 (REGRESSION).** Vector FMA, sqrt/recip/rsqrt/logb/class, conversions, and `VLDI` mode broadcast are now implemented, and all residual "unhandled" strings route to guest `SIGILL`. CPUCFG at `src/interp/interp_mem.h:224` still advertises LSX/LASX unconditionally. The regression classification is driven by N1 and N4 below, which turn two previously loud failures into silent wrong behaviour on common instructions.

**R7-15 (PARTIAL).** `src/interp/interp_amo.c:217` rejects `rd == rj` for W/D AM ops and AMCAS W/D. QEMU's `gen_am` rejects `rd != 0 && (rd == rj || rd == rk)` for all `amswap`/`amadd` forms including B/H, and `gen_cas` has no overlap check at all. So the fix exempts B/H forms the oracle rejects, rejects AMCAS W/D the oracle accepts, and never exempts `rd == r0`. The reported `amswap.d r4,r5,r4` case is fixed.

**R7-19 (PARTIAL).** `fp_lane_take` at `src/interp/fp_vec_priv.h:354` sets Cause to the latest nonzero lane. QEMU's `UPDATE_FP_CAUSE` is `|=` and runs after `vec_clear_cause`, so vector Cause is the OR over all lanes. Lane 0 Invalid followed by lane 1 Inexact yields `I` here and `V|I` in QEMU. The comment claiming QEMU uses latest-nonzero is incorrect.

**R7-21 (PARTIAL).** `fp_max_u` at `src/interp/fp_vec_priv.h:482` returns the default NaN for two qNaNs without Invalid. QEMU's `float64_maxnum` uses `float_2nan_prop_s_ab`, which returns `fj`'s qNaN with payload intact. The spurious Invalid, sNaN quieting, and signed tie ordering are fixed.

**R7-25 (PARTIAL).** The non-NaN path `fma(-x, y, ±z0)` negates before rounding, correct. In the fallback path at `src/interp/fp.c:286` and `:308` (and `src/interp/fp_vec.c:493`, `:512`), kinds 1 and 3 still pass `-z0` to the host fma. If `fa` is the propagated NaN, its sign is flipped. QEMU picks the NaN before applying `negate_c`.

## New defects introduced by this commit

**N1. Vector FCMP rejects nearly every valid condition (HIGH).** `src/interp/fp_vec.c:357` admits only `cond` values 0, 8, 12, 16, 20 and returns "illegal vector fcmp condition" for all others. The 5-bit `fcond` field is valid for 0..0x11, 0x14, 0x15, 0x18, 0x19. `VFCMP.CLT.S` (2), `VFCMP.CEQ.S` (4), `VFCMP.CLE.S` (6) and so on now deliver `SIGILL`. The removed check on `cc = fcond >> 1` in {9, 11, 13, 14, 15} was correct. This affects LSX and LASX.

**N2. `VFFINT.S.WU` and `VFFINT.D.L` are swapped (HIGH).** `src/interp/fp_vec_cvt.c:440` maps `m10` 0..3 to `cvt = 4 + m10`, but `cvt_same` decodes 5 as D.L and 6 as S.WU while the encoding has `m10 = 1` as S.WU and `m10 = 2` as D.L. Both instructions silently produce the other's result. Previously these exited with "unhandled vector convert op".

**N3. 256-bit widening conversions use the wrong lane geometry (MEDIUM).** `cvt_wide` at `src/interp/fp_vec_cvt.c:246` reads source lanes `0..n-1` or `n..2n-1` flat. QEMU's `vfcvtl_d_s`, `vfcvth_d_s`, `vfcvtl_s_h`, `vffintl_d_w`, `vftintl_l_s` operate per 128-bit half: for 256 bits, destination D2,D3 come from W4,W5 (L) or W6,W7 (H), not W2,W3 or W6,W7 flat. `fp_lasx_try_step` does not claim k15 0x0E53B/C/D, so `XVFCVTL/H`, `XVFFINTL/H`, `XVFTINTL/H` all reach this code. LSX (16-byte) results are unaffected.

**N4. `VLDI` mode table is wrong for 12 of 13 modes (HIGH).** `vldi_mode_value` in `src/interp/fp_shuf.c:15` returns `{0,1,3,7,15,31,63,127}` for modes 0..7, `imm & 0xFF` for mode 8, and ad-hoc shifts for 10..12. QEMU's `vldi_get_value` broadcasts `imm[7:0]` into specific byte positions for modes 0..8 (e.g. mode 0 is `(t<<32)|t`, mode 8 replicates `t` into all eight bytes) and builds float32/float64 immediates for modes 10..12. Only mode 9 matches. Compilers emit mode-table `VLDI` for common constants, so this is a silent miscompute where there used to be a translator exit.

## Other observations

- Lock ordering for R7-5 is vmfile lock then store lock (via `la64_clone_invalidate_ll`). I found no path taking them in the opposite order; `la64_mem_ptr` does not touch the vmfile lock and all store paths call `note_store` after releasing the store lock.
- All changed files stay at or below 900 lines; `src/vm/vm_file_sync.c` sits exactly at 900.
- The `neg_errno` include-guard dance only matters for `src/os/backend_darwin_fs.c`, the sole TU including both headers, and the reordering there keeps the guest-mapping definition.
- `FSCALEB.S` clamps to ±0x1000 where QEMU clamps to ±0x200. Any magnitude ≥ 0x200 already saturates a float, so this is not observable.

Recommended next step: fix N1, N2, N4 first since they regress working or loud-failing behaviour into silent errors, then N3 and the R7-19 OR semantics together since they share the vector conversion code.
