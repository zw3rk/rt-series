Completed the static review of all 13 files in `src/interp/` and the related CPU/FPU/VMX/VSX/trap headers. There is no `include/` directory in this checkout. No builds or tests were run; the counterexamples below come from static analysis.

### P64-R7-1 — BUG — HIGH

- **Summary**: `darn` returns a predictable sequence as successful random output.
- **Locations**: [interp.c:29](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:29), [interp.c:458](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:458), [profile.h:77](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/profile.h:77).
- **Evidence & Root Cause**: The implementation uses xorshift with a public constant seed, restored by `ppc64_interp_reset()`. It returns this sequence without indicating failure while advertising DARN support. Guest software using DARN for entropy can therefore generate predictable secrets. QEMU instead obtains guest random bytes and returns the architectural failure value when that fails. [QEMU DARN implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/int_helper.c).
- **Remediation**: Use the host’s established cryptographic random interface, implement the DARN forms and failure sentinel correctly, and remove the fixed-seed generator from this instruction.

### P64-R7-2 — BUG — HIGH

- **Summary**: Quadword reservation operations bypass the atomic backend and can succeed after intervening writes.
- **Locations**: [vec.c:116](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:116), [vec.c:151](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:151), [atomic.h:23](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/atomic.h:23), [fp_str.c:33](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:33).
- **Evidence & Root Cause**: Both atomic-backend branches require `w <= 8`. Thus `lqarx` performs an ordinary read and records a local Boolean reservation; `stqcx.` consumes that Boolean, releases its lock, and performs an ordinary write. It neither atomically checks memory nor validates a shared write epoch. A sequence `lqarx; stxv` to the same address; `stqcx.` can report success because `str_write()` bypasses the interpreter reservation invalidator. Concurrent writes can also occur between reservation checking and committing.
- **Remediation**: Extend the shared atomic interface to 128-bit values and make reservation validation plus conditional commit atomic. Route every relevant store through the same reservation authority.

### P64-R7-3 — BUG — HIGH

- **Summary**: Load-reserve invalidates the wrong Soft-TLB entry for three quarters of the table.
- **Locations**: [vec.c:112](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:112), [cpu.h:38](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:38), [vm64.c:506](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm64.c:506).
- **Evidence & Root Cause**: The reservation path indexes with `(ea >> 12) & 1023`, but the shared TLB contains 4096 entries and uses a 4095 mask. For `EA = 0x400000`, the live entry is 1024 while this code clears entry 0. A previously warmed writable entry remains usable by DBT stores, bypassing reservation epoch updates. An intervening A→B→A write sequence can consequently leave a later store-conditional reporting success.
- **Remediation**: Derive the index from `PPC64_TLB_SIZE` and ensure reservation establishment revokes every applicable writable fast path.

### P64-R7-4 — BUG — HIGH

- **Summary**: `lqarx` and `stqcx.` reverse the architectural GPR-pair order in little-endian mode.
- **Locations**: [vec.c:134](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:134), [vec.c:180](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:180).
- **Evidence & Root Cause**: The code assigns the doubleword at `EA` to `RT`, and `EA+8` to `RT+1`, then stores using the same order. These instructions place the high half in the even register and the low half in its successor, including little-endian execution. Memory containing low half `1`, high half `2` therefore produces `{RT=1, RT+1=2}` instead of `{2,1}`. [QEMU quadword reservation implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Correct the register-to-memory half mapping independently of the atomicity repair.

### P64-R7-5 — BUG — HIGH

- **Summary**: `dcbt` executes as a byte-reversed halfword load and can corrupt a GPR or fault.
- **Locations**: [interp.h:634](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:634), [interp.c:499](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:499), [interp.c:526](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:526).
- **Evidence & Root Cause**: The memory table assigns XO 278 to the halfword reverse-load operation. XO 278 is `dcbt`; the table executes before the cache-hint handler. Consequently, ordinary `dcbt` reads memory and overwrites the GPR selected by its TH field, commonly GPR0. The reverse-halfword entries use 278/406 instead of the architectural 790/918, also leaving real `lhbrx`/`sthbrx` unsupported. [IBM opcode reference](https://www.ibm.com/docs/en/aix/7.3.0?topic=reference-appendix-b-instruction-set-sorted-by-mnemonic).
- **Remediation**: Correct both reverse-halfword opcodes and verify that cache-hint encodings cannot enter memory-transfer dispatch.

### P64-R7-6 — BUG — HIGH

- **Summary**: VSX XX3 instructions interchange the XA and XB register-extension bits.
- **Locations**: [fp_vsx.c:24](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:24), [fp_vsx.c:36](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:36).
- **Evidence & Root Cause**: `ax` comes from raw bit 1 and `bx` from bit 2; XA requires bit 2 and XB bit 1. For example, `xxlor vs0,vs1,vs34` reads `vs33` and `vs2`. Logical operations, merges, and permutations using sources from different VSR banks silently consume unrelated registers. [QEMU XX-form field definitions](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/insn32.decode).
- **Remediation**: Correct the extension-bit extraction and share it across XX3 handlers.

### P64-R7-7 — DEFECT — HIGH

- **Summary**: Required scalar and vector VSX floating-point arithmetic has no interpreter implementation.
- **Locations**: [fp_vsx.c:21](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:21), [interp.c:329](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:329), [SPEC.md:56](/Users/angerman/Projects/zw3rk/ppc64rt/SPEC.md:56).
- **Evidence & Root Cause**: The PO60 executor handles logical operations, permutations, merges, splats, comparisons, and sign operations, then declines everything else. Instructions explicitly required by SPEC §2.2—including `xsadddp`, `xssubdp`, `xsmuldp`, `xsdivdp`, and the listed vector arithmetic families—reach the illegal-instruction path. For example, neither XSADDDP’s XO8 32 nor XVADDDP’s XO8 96 has an execution case.
- **Remediation**: Implement the promised arithmetic families in the reference interpreter, including FPSCR effects and VSR overlap semantics.

### P64-R7-8 — BUG — MEDIUM

- **Summary**: Register-controlled shifts wrap oversized counts instead of producing the required zero or sign-filled result.
- **Locations**: [interp.h:566](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:566), [interp.h:576](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:576), [interp.h:602](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:602).
- **Evidence & Root Cause**: Word logical shifts reduce the actual shift to `n & 31`; doubleword shifts discard count bit 6. Arithmetic shifts similarly discard their oversized-count indicator. Thus `slw(1,32)` and `sld(1,64)` return `1` instead of `0`. Negative `sraw`/`srad` operands shifted by 32/64 retain their original value and clear carry instead of sign-filling. The `n < 64` checks cannot reject counts already masked below 64.
- **Remediation**: Decode six count bits for word operations and seven for doubleword operations, then handle oversized counts explicitly before performing C shifts.

### P64-R7-9 — BUG — MEDIUM

- **Summary**: `srad` and `sradi` compute CA32 differently from the required CA result.
- **Locations**: [interp.h:580](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:580).
- **Evidence & Root Cause**: CA examines all discarded bits, while CA32 examines only discarded bits from the low word. With `RS=0x8000000100000000` and shift 40, the implementation sets CA but clears CA32. These instructions copy the same carry result into both fields. [QEMU arithmetic-shift implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Calculate the architectural carry once and assign it to both CA and CA32.

### P64-R7-10 — BUG — MEDIUM

- **Summary**: `subfo` ignores OE and leaves overflow state unchanged.
- **Locations**: [interp.c:605](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:605).
- **Evidence & Root Cause**: The `subf` case computes `y - x` and exits without invoking overflow handling, although the surrounding dispatcher decoded OE. With RA=`1`, RB=`INT64_MIN`, and clear XER, `subfo` returns `INT64_MAX` without setting OV/SO. Non-overflowing operations also fail to clear previous overflow state; the record form consequently copies stale SO into CR0.
- **Remediation**: Apply the subtraction overflow calculation when OE is set, including OV32 and sticky SO, while preserving carry fields.

### P64-R7-11 — BUG — MEDIUM

- **Summary**: Overflow-enabled integer division clears overflow on division by zero.
- **Locations**: [interp.h:395](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:395).
- **Evidence & Root Cause**: Both zero-divisor branches assign a quotient but leave `ov=false`. The final OE handler therefore clears OV and OV32 instead of setting overflow and sticky SO. This affects signed and unsigned word and doubleword division. The defect concerns defined exception flags, independently of the quotient chosen for this exceptional case. [QEMU division implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Include a zero divisor in the overflow predicate for every divide variant.

### P64-R7-12 — DEFECT — MEDIUM

- **Summary**: `addex` is decoded but never executed.
- **Locations**: [decode.c:495](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:495), [decode.h:52](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.h:52), [interp.c:589](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:589).
- **Evidence & Root Cause**: The decoder recognizes ADDEX, but no interpreter dispatch case implements it. Valid CY=0 instructions reach the illegal-instruction path. The header’s description also incorrectly identifies CA32 as its carry input; ADDEX uses the OV/OV32 carry chain. [QEMU ADDEX implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Implement the supported CY semantics and correct the instruction metadata, keeping ADDEX’s carry chain distinct from ordinary CA arithmetic.

### P64-R7-13 — BUG — MEDIUM

- **Summary**: `prtyw` discards the upper word’s parity result.
- **Locations**: [vec.c:294](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:294), [interp.h:505](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:505).
- **Evidence & Root Cause**: `prtyw` calls `interp_prty64(s,4)`, examining only the low four bytes and returning one bit. It must produce separate parity results for both words. With `RS=0x0000000100000000`, the expected result has bit 32 set, but this implementation returns zero. [QEMU parity implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Calculate both word parities and place them in bits 0 and 32.

### P64-R7-14 — BUG — MEDIUM

- **Summary**: `setnbc` implements inverted Boolean semantics instead of negative Boolean semantics.
- **Locations**: [power10.h:57](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/power10.h:57).
- **Evidence & Root Cause**: XO 448 is grouped with `setbcr` as an inversion. Consequently, a clear CR bit returns `1`, and a set bit returns `0`. `setnbc` must return `0` or all ones, respectively. The misleading comment reinforces the same mistake. [QEMU Boolean-condition implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Separate Boolean reversal from arithmetic negation and implement each mnemonic’s result independently.

### P64-R7-15 — BUG — MEDIUM

- **Summary**: CR logical instructions disagree between decoding and execution.
- **Locations**: [decode.c:131](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:131), [interp.c:157](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:157).
- **Evidence & Root Cause**: The decoder recognizes `crnor` at XO 33, but the interpreter omits it, so valid `crnor` and the common `crnot` alias trap. Separately, the decoder identifies XO 321 as `crorc`, while the executor correctly uses XO 417. This rejects the valid encoding during decoding and misclassifies a different encoding. [IBM opcode reference](https://www.ibm.com/docs/en/aix/7.3.0?topic=reference-appendix-b-instruction-set-sorted-by-mnemonic).
- **Remediation**: Add CRNOR execution and correct CRORC’s decode entry. Keep the accepted encoding set consistent across both paths.

### P64-R7-16 — BUG — MEDIUM

- **Summary**: Prefixed execution bypasses prefix-format and reserved-bit validation.
- **Locations**: [interp.c:313](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:313), [prefix.c:58](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:58), [decode.c:626](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:626).
- **Evidence & Root Cause**: Eight-byte instructions enter `ppc64_exec_prefixed()` directly. That executor dispatches primarily by suffix opcode without applying the decoder’s prefix-form and reserved-bit checks. For example, prefix `0x04000000` followed by `0x38600001` executes as `paddi r3,0,1`, although PADDI requires the MLS prefix form. Prefix `0x06040000` likewise executes despite a reserved bit rejected by `decode_prefixed()`.
- **Remediation**: Validate the complete instruction pair before any state or memory effect, using one authoritative encoding validator that also covers supported prefixed splats.

### P64-R7-17 — DEFECT — MEDIUM

- **Summary**: Valid prefixed scalar VSX transfers are decoded but missing from execution.
- **Locations**: [decode.c:644](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:644), [prefix.c:110](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:110), [prefix.c:199](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:199).
- **Evidence & Root Cause**: The decoder accepts PLXSSP, PSTXSD, and PSTXSSP at suffix primary opcodes 43, 46, and 47. None appears in the executor’s transfer cases. Valid pairs such as `04000000 AC200000`, `04000000 B8200000`, and `04000000 BC200000` therefore trap instead of transferring data.
- **Remediation**: Implement these forms with the correct VSR bank, single-precision conversion, displacement, and fault behavior.

### P64-R7-18 — BUG — MEDIUM

- **Summary**: Prefixed instructions crossing a 64-byte boundary do not raise the required alignment exception.
- **Locations**: [interp.c:54](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:54).
- **Evidence & Root Cause**: Fetch checks only four-byte alignment and unconditionally fetches the suffix. A prefix at `PC % 64 == 60` therefore executes when both words are readable. At a page boundary it can instead report a suffix access fault. Power ISA requires an alignment exception for this placement before fetching the suffix. [QEMU implementation referencing ISA §1.9](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Detect the forbidden boundary immediately after recognizing a prefix, report the alignment trap at the prefix PC, and reconcile any contrary cross-page expectations in the project specification.

### P64-R7-19 — BUG — MEDIUM

- **Summary**: Invalid update-form loads and stores modify architectural state before reporting illegal instruction.
- **Locations**: [interp.c:258](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:258).
- **Evidence & Root Cause**: `mem_access()` performs the memory transfer and writes the load destination before checking `RA==0` or update-load `RA==RT`. Thus `lwzu r3,0(r3)` can overwrite r3 and then trap; an update store with RA zero can modify memory before trapping. Inaccessible addresses also produce an access fault before the invalid operands are recognized.
- **Remediation**: Validate update-form operands before callbacks, destination writes, or reservation invalidation.

### P64-R7-20 — BUG — MEDIUM

- **Summary**: `lqarx` accepts prohibited destination/address-register overlaps.
- **Locations**: [vec.c:102](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:102).
- **Evidence & Root Cause**: Validation checks only that RT is even. It omits the restrictions against RT equaling RA or RB, so prohibited forms perform the load, overwrite registers, and establish a reservation. The independent implementation rejects these overlaps before memory access. [QEMU LQARX validation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Enforce all LQARX register restrictions before calculating or accessing memory.

### P64-R7-21 — BUG — MEDIUM

- **Summary**: `mtvsrdd` reads GPR0 when RA zero requires a literal zero.
- **Locations**: [fp.c:514](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:514), [vec.c:362](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:362).
- **Evidence & Root Cause**: Both implementations assign `cpu->gpr[ra]` to the high VSR half unconditionally. With RA=0 and nonzero GPR0, they inject that value instead of zero. This violates MTVSRDD’s special RA-zero rule. [Power ISA v3.0C, MTVSRDD](https://ftp.libre-soc.org/PowerISA_public.v3.0C.pdf#page=135).
- **Remediation**: Apply the literal-zero rule in both paths, preferably through a shared implementation.

### P64-R7-22 — BUG — MEDIUM

- **Summary**: VSX word transfers reject the extension bit needed to access VSR32–63.
- **Locations**: [fp.c:522](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:522), [vec.c:375](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:375).
- **Evidence & Root Cause**: `mtvsrwa` treats raw bit 0 as forbidden Rc, despite calculating a TX-extended register index. `mfvsrwz` and `mtvsrwz` likewise reject that bit and use only the five-bit register number. Valid transfers involving VSR32–63 consequently trap. Bit 0 is the VSR extension for these instructions. [Power ISA v3.0C, register-transfer instructions](https://ftp.libre-soc.org/PowerISA_public.v3.0C.pdf#page=133).
- **Remediation**: Decode TX instead of Rc and use the complete six-bit VSR index consistently.

### P64-R7-23 — BUG — MEDIUM

- **Summary**: `vsumsws` adds the wrong word from VB.
- **Locations**: [fp_str.c:851](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:851).
- **Evidence & Root Cause**: The accumulator reads `pack_get(blo,bhi,3,32)`, selecting the highest numerical word. VSUMSWS adds architectural VB bits 96–127, which correspond to the lowest word in this representation. With VA zero, VB low word `1`, and VB high word `2`, the implementation produces `2` instead of `1`. [AltiVec instruction reference](https://www.nxp.com/docs/en/reference-manual/ALTIVECPEM.pdf#page=278).
- **Remediation**: Read VB through the lane index corresponding to architectural word 3—index zero in these little-endian packing helpers.

### P64-R7-24 — BUG — MEDIUM

- **Summary**: VMX saturation status and VSCR access are unimplemented.
- **Locations**: [fp_str.c:782](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:782), [fp_str.c:851](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:851), [cpu.h:62](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:62), [SPEC.md:57](/Users/angerman/Projects/zw3rk/ppc64rt/SPEC.md:57).
- **Evidence & Root Cause**: `vaddubs`, `vsububs`, and `vsumsws` clamp results but never set `cpu->vscr`. For example, unsigned byte `255+1` yields 255 while leaving SAT clear. No interpreter implementation reads or writes VSCR, and the explicitly required `mfvscr`/`mtvscr` instructions are absent. Saturation must set the sticky SAT state. [AltiVec programming reference](https://www.nxp.com/docs/en/reference-manual/ALTIVECPOWERISAPEM.pdf).
- **Remediation**: Implement VSCR transfers and set sticky SAT whenever any affected lane saturates, preserving unrelated VSCR fields.

### P64-R7-25 — BUG — MEDIUM

- **Summary**: `fcfid` ignores guest rounding and required FPSCR updates.
- **Locations**: [fp.c:421](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:421).
- **Evidence & Root Cause**: Conversion is a bare `(double)s` without installing FPSCR[RN] or recording rounding/classification flags. Under round-toward-positive-infinity, integer `2^53+1` should become `2^53+2`; with the normal host nearest mode it becomes `2^53`. Inexact and result-status fields remain stale, and the record form copies stale FPSCR status into CR1. [IBM assembler reference](https://www.ibm.com/docs/ssw_aix_71/assembler/assembler_pdf.pdf).
- **Remediation**: Perform conversion under guest rounding semantics and update all defined FPSCR fields before applying Rc.

### P64-R7-26 — BUG — MEDIUM

- **Summary**: `fcmpu` and `xscmpudp` update CR but leave FPSCR comparison and exception state stale.
- **Locations**: [fp.c:331](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:331), [power10.h:122](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/power10.h:122).
- **Evidence & Root Cause**: Both handlers call the value-only `fp_cmpu()` helper and write only the selected CR field. Neither updates FPSCR[FPCC], and signaling NaNs do not set VXSNAN and its summaries. Even an ordinary finite comparison leaves a previous FPCC result observable through `mffs`. [QEMU floating-point comparison implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/fpu_helper.c).
- **Remediation**: Use a stateful comparison helper that distinguishes signaling NaNs and updates CR and FPSCR together.

### P64-R7-27 — BUG — MEDIUM

- **Summary**: Single-precision overflow is missed when directed rounding produces the largest finite value.
- **Locations**: [fp_single.c:159](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:159).
- **Evidence & Root Cause**: `fp1_single()` sets OX only when `isinf(f)` is true. Under round-toward-zero, `fmuls` with operands `FLT_MAX` and `2` produces finite `FLT_MAX`; the implementation records only inexact. The mathematical result overflowed the single-precision range regardless of the finite rounded endpoint.
- **Remediation**: Determine overflow from the operation’s range and rounding semantics, rather than testing whether the final representation is infinity.

### P64-R7-28 — BUG — MEDIUM

- **Summary**: The long-double intermediate can double-round single-precision arithmetic incorrectly.
- **Locations**: [fp_single.c:159](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:159), [fp_single.c:242](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:242), [fp_single.c:354](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:354).
- **Evidence & Root Cause**: Arithmetic first rounds into `long double`, then into `float`. On the AArch64 Linux binary128 path, nearest-mode `fadds` with FRA=`1+2^-24` and FRB=`2^-200` loses the small positive addend in the intermediate. The subsequent binary32 tie rounds to `1`, although the exact sum lies above the midpoint and must round to `1+2^-23`. The absorbed-addend correction explicitly returns when `LDBL_MANT_DIG != 53`. The instruction operates on the full significands before rounding its result. [IBM PowerPC instruction reference](https://datasheets.chipdb.org/IBM/PowerPC/750/750cx_um3-17-05.pdf).
- **Remediation**: Preserve discarded information through the final rounding step, or use an established correctly rounded implementation. A wider intermediate alone is insufficient.

### P64-R7-29 — BUG — MEDIUM

- **Summary**: Floating-point arithmetic records generic invalid-operation status without its required cause bits.
- **Locations**: [fp_single.c:78](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:78), [fp_single.c:138](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:138), [fp_single.c:228](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:228).
- **Evidence & Root Cause**: The exception interface reduces invalid arithmetic to `exc |= 16`, which `fp1_record()` maps only to VX. Starting with clear FPSCR, `fdiv 0,0` therefore omits VXZDZ; `fsub +Inf,+Inf` omits VXISI. Software inspecting the architected invalid-cause fields cannot distinguish these operations. [QEMU FP exception handling](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/fpu_helper.c).
- **Remediation**: Classify invalid operations from opcode and operand classes, set their specific sticky causes, and derive VX/FEX/FX consistently.

### P64-R7-30 — BUG — MEDIUM

- **Summary**: Signal frames expose the internal XER encoding instead of the guest architectural encoding.
- **Locations**: [cpu.h:19](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:19), [vec.c:212](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:212), [sigframe.c:246](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c:246), [sigframe.c:339](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c:339).
- **Evidence & Root Cause**: CPU state stores SO/OV/CA in numerical bits 63/62/61. `mfxer` and `mtxer` explicitly translate these to/from guest bits 31/30/29, but signal serialization copies `ctx->xer` verbatim in both directions. After `mtxer 0x20000000`, PT_XER consequently contains `0x2000000000000000`. Conversely, a signal handler setting architectural CA in its saved context restores a value that `adde` does not recognize as carry.
- **Remediation**: Introduce shared architectural XER pack/unpack helpers and use them for SPR access and signal-frame save/restore, preserving CA32 and OV32.
