Production wiring uses a real atomic callback, so the CAS fallback hazard is harness-only. I have everything needed; writing the report now.

# Round-7 static review: commit 73b70b2 (S64-R7-1..35)

**Verdict.** 32 of 35 items are VERIFIED, 3 are PARTIAL, none is a REGRESSION. Two new defects were introduced, both low severity. No builds, guest binaries, or tests were run; the `check-r7` target and the DBT difftest remain unexecuted, so compile cleanliness and dual-engine parity are unverified.

## Per-item classification

| Item | Class | Evidence (static) |
|---|---|---|
| R7-1 | VERIFIED | `exec_cti` now publishes `(delay_pc, target)` and returns when the delay slot holds a CTI; the dispatcher runs the nested transfer as its own entry. `dbt_delay_continuation` already uses the same publish shape (`src/dbt/dbt.c:337`), so parity is plausible but needs a difftest run. |
| R7-2 | VERIFIED | `qq_commit`/`qd_commit`/`qc_commit` delegate to `sparc64_fp_commit`; every quad path goes through `*_publish*` helpers that commit before writing dest. `qc_cmp` writes FCC only after commit. FTT=1 set on trap. |
| R7-3 | VERIFIED | `sd_pack`, `qq_pack`, `qd_pack`, `qc_pack` all require `g\|r\|s` for directed increments. |
| R7-4 | VERIFIED | `sd_addsub` and `qq_addsub` keep 3 guard bits plus sticky through alignment, subtract with a one-ulp borrow when sticky is set, normalize, then round once. The borrow path is only reachable with `d >= 4`, where cancellation is at most one bit, so the sticky approximation stays correct. |
| R7-5 | VERIFIED | Tiny branch keeps `shi & 0xFFFF_FFFF_FFFF`; `shift == 113/114` derive exact g/r/s. Carry into the hidden bit after rounding correctly falls through to the min-normal encoding. |
| R7-6 | VERIFIED | All four binary32 packing branches use `neg << 31`. |
| R7-7 | VERIFIED | Exact 48-bit product, normalized to 53 bits; exponent `ua.exp + ub.exp + m - 47` matches the `sig * 2^(E-52)` convention. |
| R7-8 | VERIFIED | STQF stores `d[2qi]` then `d[2qi+1]` as four word pieces. Docs updated. |
| R7-9 | VERIFIED | Decoder no longer classifies LDDA/STDA as FPU; `exec_load`/`exec_store` handle them; `sparc64_fp_ldst` rejects them defensively. |
| R7-10 | VERIFIED | Alignment check in `exec_atomic` precedes the host fast path; `sparc64_cas`/`sparc64_swap` also check before either backend. Mapped to SIGBUS/BUS_ADRALN in `sync_sig.c`. |
| R7-11 | VERIFIED | Tag sets `icc.V` only; TV traps on `icc.V`. |
| R7-12 | VERIFIED | SIR special case removed. |
| R7-13 | **PARTIAL** | See below. |
| R7-14 | VERIFIED | Shift-then-add, `icc.N^V` into bit 31, old `Y[0]` gates the addend, `rd = sum`. |
| R7-15 | VERIFIED | New `sparc64_win_flush_callers` skips `cwp` and never writes the live window. |
| R7-16 | VERIFIED | `op2 == 6` decodes as FBR with FCC0, `disp22`, no pred. |
| R7-17 | VERIFIED | `fp_movr_reg` dispatched on `(opf & 0x11C) == 0x004`; FMOVcc mask `0x13C` excludes bit 2, so no overlap. rcond set `{1,2,3,5,6,7}`, full 64-bit `rs1`. |
| R7-18 | VERIFIED | Divergent `fp_cctest` deleted; `sparc64_eval_fcond` reused. |
| R7-19 | VERIFIED | `ALIGNADDRL` stores `(-sum) & 7`; `d->opf` is populated for the ALIGN class. |
| R7-20 | VERIFIED | `trapno = (rs1 + (imm7 \| rs2)) & 0x7F`; decoder extracts bits 6:0 with reserved 10:7 checked. |
| R7-21 | VERIFIED | JMPL/RETURN misalignment returns `LOAD_MISALIGNED` with the target as tval before `rd` write or RESTORE. |
| R7-22 | VERIFIED | Publication tracked against entry `pc`/`npc` snapshot; zero is no longer a sentinel. |
| R7-23 | VERIFIED | `asi_resolve` applied before `sparc64_asi_check` in load/store/atomic; CAS `rs2` decoded from bits 4:0 regardless of `i`. |
| R7-24 | **PARTIAL** | See below. |
| R7-25 | VERIFIED | LDD/STD require 8-byte alignment; LDD stages both halves before publishing. |
| R7-26 | VERIFIED | LDDF/STDF/LDQF/STQF accept word alignment via staged 4-byte pieces; LE assembly order is correct for doubles. |
| R7-27 | VERIFIED | `cas_link` issues a same-value SC on mismatch; `cas_fallback` issues a same-value store. Both fault on read-only pages. |
| R7-28 | VERIFIED | `sparc64_cas` masks `expect`/`swap` to 32 bits once for `size == 4`. |
| R7-29 | VERIFIED | `rd` restricted to 0/1; writable masks `0xDF800FFF` / `0x3FDF800FFF` preserve ftt/qne/ver and fcc1-3 on the 32-bit form; FTT cleared after a successful store. |
| R7-30 | VERIFIED | Every FP register write site in `src/interp` (56 sites) is paired with a DL/DU mark; counts match per file. |
| R7-31 | VERIFIED | Normalization targets bit 23/52 with full fraction masks. |
| R7-32 | **PARTIAL** | See below. |
| R7-33 | VERIFIED | Same-sign zero sum keeps the operand sign; RD only decides opposite-sign cancellation. |
| R7-34 | VERIFIED | `ca == 3` handled before `cb == 0`. |
| R7-35 | VERIFIED | Trap path selects OF, else UF, alone in CEXC. Note: when `OFM=0, NXM=1` the fix reports OF rather than NX. This matches the finding's literal wording ("including when NXM causes the trap") but V9 Table 5-? may call for `nxc` alone in that row; worth a spec check, not a defect against the finding. |

## Partial items, new defects, and limits

**R7-13 PARTIAL.** `interp_win.c:535-545` and `:667-690`: SDIV/SDIVcc do not saturate. `q = dvd / dvs` is written as `(int32_t)q` sign-extended, so `Y=1, rs1=0, rs2=1` yields `0` instead of `0x7FFFFFFF`. SDIVcc sets `icc.V` correctly but publishes the truncated result. The `INT64_MIN / -1` guard writes zero-extended `0x80000000`; the true quotient is `+2^63`, which should saturate to `0x7FFFFFFF` (QEMU `do_sdiv` behaves this way). UDIV/UDIVcc saturation and the split CCR nibbles are correct. The test at `tests/test_r7_interp.c:324` covers only UDIV saturation and SDIV `-1`.

**R7-24 PARTIAL.** `src/os/threads.c:843-850` still admits ASI `0x82`/`0x8A` for CASA/CASXA/SWAP/LDSTUB, and `exec_atomic` calls the fast path before its no-fault rejection. On mapped memory, an atomic through a no-fault ASI succeeds. The regression test stubs `sparc64_threads_try_host_atomic` to return false, so this path is untested. Loads, stores, FP loads, and the generic atomic path are fixed.

**R7-32 PARTIAL.** `fp_qconv.c:607-625`: for `exp == limit` the quad path accepts only an exact `-2^limit`. A quad value such as `-2147483648.5` (exactly representable in binary128) truncates to `INT32_MIN`, which is representable, but the code raises NV instead of NX. The double path (`cv_dtoi32`) was fixed correctly for the same case. NV-alone on invalid is correct everywhere.

**New defect 1 (low): UDIVcc `xcc.N`.** `interp_win.c:645-647` derives `xcc.N` from bit 63 of the unsaturated 64-bit quotient. V9 A.10 sets `xcc.N` from `r[rd]<63>`, and `r[rd]` is the zero-extended saturated 32-bit result, so it must be 0. Trigger: `Y >= 0x80000000`, divisor 1.

**New defect 2 (latent): non-atomic CAS fallback store-back.** `interp_mem.c:233-238`: on mismatch, `cas_fallback` writes the stale `cur` back with a plain store. Between the load and the store another writer can be overwritten. Production wires `guest_mem_atomic` (`src/os/guest_run_mem.c:104`), so only harnesses with a NULL `atomic` callback reach this path. The `cas_link` variant is safe because the SC carries the reservation.

**Unverified limits.** No compile was run; `cv_clz64`, `sparc64_eval_rcond`, and `d->pred` all exist, and `fp_quad.c` sits at exactly 900 lines, the limit. The `check-r7` target links `interp_mem.c` without `src/os`, relying on the test's stub. DBT difftest after the R7-1 step-shape change is the main outstanding runtime risk.
