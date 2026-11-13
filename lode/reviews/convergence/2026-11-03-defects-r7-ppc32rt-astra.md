Read all nine files in `src/interp/` and the relevant CPU, trap, FPU/SPE, and signal-state headers end-to-end. Findings below are static; no builds or tests were run, and no files were changed.

### P32-R7-1 — BUG — HIGH

- **Summary**: Failed memory accesses still commit registers, update addresses, and advance NIP.
- **Locations**: [interp.h:474](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:474), [interp.h:554](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:554), [interp.c:572](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:572), [fp_spe.c:29](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:29).
- **Evidence & Root Cause**: Checked `ld*` helpers return zero after recording a fault; `st*` helpers return without writing. Integer handlers do not check that outcome. For example, `lwzu` targeting a mapped `PROT_NONE` page writes zero into RT, updates RA, and advances NIP despite `PPC32_EXIT_FAULT`. Multiple/string operations continue accessing subsequent elements, potentially replacing the original fault address. SPE loads similarly commit fabricated results.
- **Remediation**: Propagate access success explicitly. Stop immediately on failure, preserve faulting NIP, and commit destination/base updates only after successful accesses.

### P32-R7-2 — BUG — HIGH

- **Summary**: Instruction-fetch faults are overwritten with undefined-instruction exits.
- **Locations**: [interp.c:43](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:43), [interp.h:286](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:286), [interp.c:750](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:750).
- **Evidence & Root Cause**: A failed `fetch_raw()` records `PPC32_EXIT_FAULT` and returns zero. `interp_step()` nevertheless decodes zero, then overwrites the exit with `PPC32_EXIT_UNDEF`. Consequently, branching into an inaccessible or EOF-trapped page bypasses the driver's normal SIGSEGV/SIGBUS delivery.
- **Remediation**: Return immediately when instruction fetch records a fault; never decode the placeholder value.

### P32-R7-3 — BUG — HIGH

- **Summary**: Interpreter instruction fetch bypasses guest execute permissions.
- **Locations**: [interp.h:367](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:367), [vm32_tlb.c:192](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm32_tlb.c:192).
- **Evidence & Root Cause**: `fetch_raw()` uses the ordinary `ld32()` path. The TLB checks only read permission for non-store accesses; no surrounding interpreter check requires guest execute permission. A readable guest buffer lacking `PROT_EXEC` can therefore supply executed instructions. This defeats guest NX enforcement; it does not demonstrate execution outside the host JIT's W^X protections.
- **Remediation**: Add a distinct instruction-fetch access check using guest execute permissions, preserving those permissions separately from host mapping permissions.

### P32-R7-4 — BUG — HIGH

- **Summary**: `stwcx.` can succeed after another thread invalidates its reservation.
- **Locations**: [llsc.c:113](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/llsc.c:113), [llsc.c:152](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/llsc.c:152), [interp.h:344](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:344).
- **Evidence & Root Cause**: SC validates the reservation epoch before its compare-exchange. Ordinary stores perform their memory write and epoch increment without taking the LL lock. Thread A can validate a reservation on `x=0`; thread B then completes a same-value `stw x=0` and invalidation; A's CAS subsequently writes `1` and reports success because the value still matches. The atomic epoch does not make validation and conditional storage indivisible.
- **Remediation**: Serialize invalidating writes and reservation updates against the entire SC validation/write operation. Locking only the epoch increment is insufficient.

### P32-R7-5 — BUG — HIGH

- **Summary**: Classic floating-point record forms overwrite CR6 instead of CR1.
- **Locations**: [fp.h:228](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:228).
- **Evidence & Root Cause**: `fp_cr1()` inserts FPSCR's top nibble at shift `4`. In this context's CR layout, that is CR6; CR1 requires shift `24`. Thus instructions such as `fadd.` leave CR1 stale and destroy an unrelated condition field.
- **Remediation**: Replace the mask and insertion shift with `24`, preserving every other CR field.

### P32-R7-6 — BUG — MEDIUM

- **Summary**: Floating-point addition uses subtraction's infinity-invalid predicate.
- **Locations**: [fp.h:292](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:292), [fp.h:329](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:329), [fp.c:125](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:125).
- **Evidence & Root Cause**: Both helpers classify same-sign infinities as invalid for both addition and subtraction. Consequently, `+∞ + +∞` produces NaN instead of `+∞`. Conversely, `+∞ + −∞` reaches host arithmetic without setting `VXISI`; `fp_end()` does not capture host `FE_INVALID`.
- **Remediation**: Distinguish addition's opposite-sign infinity case from subtraction's same-sign case.

### P32-R7-7 — BUG — HIGH

- **Summary**: Enabled invalid-operation and zero-divide exceptions still overwrite the destination.
- **Locations**: [fp.c:40](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:40), [fp.c:65](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:65), [fp.h:371](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:371).
- **Evidence & Root Cause**: Exception handling updates FPSCR but unconditionally reaches `fp_done()`. With `FPSCR.VE=1`, `fsqrt(-1)` overwrites FRT with NaN; enabled zero division similarly commits infinity. These exceptions require destination-update suppression, independently of whether MSR permits exception delivery. [PowerPC programming manual, §3.3.6](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Separate exception recording from result commitment. Apply enable-dependent destination/FPRF suppression and the appropriate guest exception-delivery policy.

### P32-R7-8 — BUG — HIGH

- **Summary**: SPE vector floating comparisons produce incorrect results and corrupt neighboring CR fields.
- **Locations**: [fp.h:404](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:404), [fp_spe.c:197](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:197).
- **Evidence & Root Cause**: Scalar comparisons return `0` or `4`, but `fp_fcmp_merge()` treats them as one-bit booleans. Both lanes true produce `0x3c`, after which `fp_set_crf_bleed()` deliberately writes excess bits into the preceding field. From `CR=0`, equal finite lanes compared into CR1 produce `0x3c000000`, rather than `0x0f000000`. The architectural result occupies one nibble. [SPE manual, p. 5-95](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Normalize lane results to `0/1`, construct the four comparison bits, and update only the selected field.

### P32-R7-9 — BUG — MEDIUM

- **Summary**: SPE vector sign operations modify only the upper float.
- **Locations**: [fp_spe.c:234](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:234).
- **Evidence & Root Cause**: `evfsabs`, `evfsnabs`, and `evfsneg` share the scalar-double mask path, which changes only bit 63. For `rA=0xbf800000bf800000`, `evfsabs` produces `0x3f800000bf800000`, leaving the lower −1.0 unchanged.
- **Remediation**: Use separate vector-single masks affecting both sign bits, including `0x8000000080000000`.

### P32-R7-10 — BUG — HIGH

- **Summary**: Implemented SPE MAC operations lose vector lanes and apply incorrect accumulator semantics.
- **Locations**: [fp_spe.h:117](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:117), [fp_spe.c:306](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:306).
- **Evidence & Root Cause**: The whole-word helper multiplies only low words and returns a zero-extended result. Its `acc` path adds old `rD.low` without updating ACC. For `evmwhsmia`, `rA=rB=0x0001000000010000` and `rD=ACC=0`, it produces `rD=1, ACC=0`; the instruction requires `rD=ACC=0x0000000100000001`. The guarded halfword path also concatenates products where a sign-extended product is required. [SPE manual, pp. 5-140 and 5-185](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Implement the distinct per-lane, accumulator-copy, and guarded-accumulation operations explicitly; replace the incorrect flag-table mappings.

### P32-R7-11 — BUG — HIGH

- **Summary**: SPE fractional conversions swap signedness and use the wrong signed scale.
- **Locations**: [fp_spe.c:261](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:261), [fp_spe.h:41](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:41), [fp_spe.h:80](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:80).
- **Evidence & Root Cause**: All three conversion tables map `CFUF` to the signed helper and `CFSF` to the unsigned helper. Additionally, signed fractions use `2^32` instead of `2^31`. Thus `efscfsf(0xc0000000)` returns `+0.75` instead of `−0.5`; `efsctsf(+0.25)` returns `0x40000000` instead of `0x20000000`. [SPE manual, §3.2](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Correct both dispatch signedness and scaling across scalar-single, scalar-double, and vector forms.

### P32-R7-12 — BUG — HIGH

- **Summary**: SPE float-to-integer saturation permits undefined out-of-range C casts.
- **Locations**: [fp.h:469](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:469), [fp.h:488](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:488).
- **Evidence & Root Cause**: `2147483647.0f` rounds to `2^31`, and `4294967295.0f` rounds to `2^32`. The strict `>` comparisons therefore allow those exact boundary values to reach casts to `int32_t` and `uint32_t`, respectively. Both casts are outside the destination range and invoke undefined behavior.
- **Remediation**: Reject `r >= 0x1p31f` and `r >= 0x1p32f` before casting, returning the required saturated value.

### P32-R7-13 — DEFECT — HIGH

- **Summary**: SPEFSCR register access and execution semantics are missing.
- **Locations**: [interp.h:703](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:703), [fp.h:379](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:379), [fp_spe.c:213](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:213).
- **Evidence & Root Cause**: `mfspr`/`mtspr` reject SPR 512. No SPE arithmetic helper reads or updates `ctx->spefscr`; conversions use host rounding and leave guest exception/status bits unchanged. SPEFSCR is user-accessible, as explicitly clarified by the [e500 manual errata, §2.14.1](https://www.nxp.com.cn/docs/en/reference-manual/e500CORERMAD.pdf).
- **Remediation**: Implement SPR 512 access and apply SPEFSCR rounding, status, saturation, and exception controls throughout SPE execution.

### P32-R7-14 — BUG — MEDIUM

- **Summary**: SPE halfword-vector loads access beyond their operand.
- **Locations**: [fp_spe.c:29](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:29).
- **Evidence & Root Cause**: `evlwhe[x]`, `evlwhou[x]`, and `evlwhos[x]` read `ld32(ea+2)` and discard its low half. Their operand occupies four bytes, but the implementation accesses six. At `EA=page_end−4`, an inaccessible following page causes a fault despite all operand bytes being available. The common initial check also incorrectly assumes eight-byte width. [SPE manual, p. 5-124](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Read one word or two halfwords, validate the actual instruction width, and commit only after success.

### P32-R7-15 — DEFECT — MEDIUM

- **Summary**: Interpreter instruction admission ignores the selected Classic/SPE profile.
- **Locations**: [fp.c:550](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:550), [fp_spe.c:367](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:367).
- **Evidence & Root Cause**: Neither dispatch path checks `profile` or `is_spe`. Consequently, Classic mode executes `evaddw`, while SPE mode executes Classic FPU instructions such as `lfd` and `fadd`, contrary to the project's declared CPU profiles and `decode.h`'s admission contract.
- **Remediation**: Reject unavailable instruction families before any architectural or memory side effects.

### P32-R7-16 — BUG — MEDIUM

- **Summary**: `lswi` preserves stale bytes in its partially filled final register.
- **Locations**: [interp.c:600](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:600).
- **Evidence & Root Cause**: Each destination accumulator starts from `ctx->gpr[reg]`. With `r3=0x11223344`, a one-byte `lswi` loading `0xaa` produces `0xaa223344`; the required result is `0xaa000000`. Unfilled bytes must be cleared. [PowerPC Book I, string loads](https://powerpc.dev/general/PPC_Vers202_Book1_public.pdf).
- **Remediation**: Initialize each destination accumulator to zero before inserting transferred bytes.

### P32-R7-17 — DEFECT — MEDIUM

- **Summary**: `lswx` and `stswx` decode successfully but have no interpreter implementation.
- **Locations**: [decode.c:525](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:525), [decode.c:550](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:550), [interp.c:750](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:750).
- **Evidence & Root Cause**: The decoder produces dedicated opcode IDs, but neither has a case in `interp_step()`. Every valid indexed string transfer reaches `PPC32_EXIT_UNDEF`, including zero-count operations. These instructions obtain their byte count from XER. [IBM `lswx` definition](https://www.ibm.com/docs/en/aix/7.1.0?topic=set-lswx-lsx-load-string-word-indexed-instruction).
- **Remediation**: Implement indexed address calculation, XER byte counts, register wrapping, partial-word clearing, and fault handling.

### P32-R7-18 — BUG — MEDIUM

- **Summary**: FPSCR writes and exception-summary maintenance violate derived and sticky-bit rules.
- **Locations**: [fp.c:475](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:475), [fp.c:491](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:491), [fp.h:128](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:128).
- **Evidence & Root Cause**: `mtfsb*` and `mtfsfi` directly mutate bits without recomputing summaries. From zero, `mtfsb1 7` sets VXSNAN but omits VX and FX. Conversely, `fp_raise()` reasserts a software-cleared FX during exact arithmetic merely because an old exception bit remains set. [IBM FPSCR bit-setting rules](https://www.ibm.com/docs/en/aix/7.1.0?topic=set-mtfsb1-move-fpscr-bit-1-instruction).
- **Remediation**: Centralize FPSCR mutation with correct derived-field recomputation and event-based sticky-summary updates.

### P32-R7-19 — BUG — MEDIUM

- **Summary**: FPSCR.FR does not describe the latest rounding operation.
- **Locations**: [fp.h:234](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:234), [fp.c:395](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:395).
- **Evidence & Root Cause**: Arithmetic deliberately retains FR, and integer conversion updates FI without calculating FR. An exact `fadd(1,1)` leaves a previously set FR intact; nearest-even `fctiw(1.5)` produces `2` without setting FR. FR must reflect the current result's rounding. [PowerPC programming manual, §3.3.5](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Calculate FR alongside FI and clear it for exact operations.

### P32-R7-20 — BUG — MEDIUM

- **Summary**: `fctiw[z]` rejects representable rounded results.
- **Locations**: [fp.c:359](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:359).
- **Evidence & Root Cause**: Range checking precedes rounding. `fctiwz(2147483647.25)` and `fctiwz(−2147483648.25)` therefore raise VXCVI, although truncation produces valid signed integers. The conversion model rounds before checking the integer range. [PowerPC programming manual, Appendix D.4.2](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Handle NaNs/infinities, round under the selected mode, then check representability and select valid-inexact versus invalid status.

### P32-R7-21 — BUG — MEDIUM

- **Summary**: FMA NaN propagation suppresses a required invalid-multiplication indication.
- **Locations**: [fp.c:204](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:204).
- **Evidence & Root Cause**: The first NaN causes an early return before the zero-times-infinity check. Thus `fmadd` with multiplicands `0` and `+∞` and a quiet-NaN addend never sets VXIMZ. A NaN addend does not eliminate that multiplication exception. [PowerPC programming manual, §4.2.2.2](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Determine applicable multiplication exceptions before completing NaN-result propagation.

### P32-R7-22 — BUG — MEDIUM

- **Summary**: Single-precision subnormal results receive normal-number FPRF classifications.
- **Locations**: [fp.h:236](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:236), [fp.c:65](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:65).
- **Evidence & Root Cause**: Result classification always uses `fp_fprf64()` after expansion into the double-format FPR representation. Exact `fmuls(2^-126, 0.5)` consequently records `0x04`, because `2^-127` is normal as a double; its single-result classification is `0x14`. [PowerPC programming manual, Table 3-16](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Pass result precision into classification and classify single results before expansion.

### P32-R7-23 — BUG — MEDIUM

- **Summary**: Floating comparisons overwrite FPSCR.C.
- **Locations**: [fp.c:337](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:337).
- **Evidence & Root Cause**: `fp_fcmp()` clears all five FPRF bits with `~(0x1f << 12)`, although comparison updates only the four FPCC bits. Starting with C set, `fcmpu(1,1)` incorrectly clears it. The ordered-NaN path additionally forces C to one. [PowerPC programming manual, `fcmpu`/`fcmpo`](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Update only `0xf << 12`; preserve C rather than treating comparison as arithmetic-result classification.

### P32-R7-24 — DEFECT — MEDIUM

- **Summary**: Architectural time-base reads are missing or permanently return zero.
- **Locations**: [decode.c:335](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:335), [interp.h:707](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:707).
- **Evidence & Root Cause**: Primary-31 dispatch lacks XO 371, the standard `mftb` encoding. Reads routed through `mfspr` for TB/TBU instead return constant zero. Valid timer code therefore encounters an undefined-instruction exit or a clock that never advances. [PowerPC Book II, time-base facility](https://powerpc.dev/general/PPC_Vers202_Book2_public.pdf).
- **Remediation**: Decode the time-base instruction and provide coherent TB/TBU values from a defined guest time-base clock.

### P32-R7-25 — DEFECT — MEDIUM

- **Summary**: Integer update-form validation omits prohibited register combinations.
- **Locations**: [interp.h:479](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:479), [interp.h:563](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:563).
- **Evidence & Root Cause**: Update loads reject RA==0 but accept RA==RT. Indexed update stores accept RA==0 by silently disabling writeback. Consequently, `lwzu r3,4(r3)` leaves the address in r3, while `lwzux r3,r3,r4` leaves loaded data. These are invalid forms; this finding concerns the requested validation policy, not a claim that every processor must trap boundedly undefined encodings. [PowerPC Book I](https://powerpc.dev/general/PPC_Vers202_Book1_public.pdf).
- **Remediation**: Before accessing memory, require RA!=0 for every update form and RA!=RT for integer update loads.
