Reviewed all 18 files in `src/interp/` and the relevant CPU, window, FPU, VIS, and trap headers end-to-end using read-only review lanes. No builds or tests were run; no files were changed. Counterexamples below are static traces.

### S64-R7-1 — BUG — HIGH

- **Summary**: Nested delay-slot branches permit unbounded host recursion.
- **Locations**: [interp.c:244](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:244), [interp.c:349](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:349).
- **Evidence & Root Cause**: `exec_delay` recursively invokes `exec_cti`, which invokes `exec_delay` again. Two adjacent, non-annulled `ba` instructions, each targeting itself, alternate indefinitely through these calls. Guest code can exhaust the translator’s stack and prevent return to the dispatcher.
- **Remediation**: Execute delayed control transfers through an iterative PC/nPC state machine with bounded work per dispatcher entry.

### S64-R7-2 — BUG — HIGH

- **Summary**: Quad FP exceptions corrupt architectural state before trapping.
- **Locations**: [fp_quad.c:167](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:167), [fp_qdiv.c:111](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:111), [fp_qconv.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:119).
- **Evidence & Root Cause**: Quad handlers publish destinations/FCC before checking TEM, accrue trapped exceptions, and omit IEEE `FTT`. For `FDIVQ(1,+0)` with initial FSR `0x01000000`, the destination becomes infinity and FSR becomes `0x01000042`. The signal layer consequently classifies it as SIGILL. Quad integer conversions also bypass exception-state completion entirely.
- **Remediation**: Use the shared exception-commit helper before publishing results. Preserve destinations, FCC, and AEXC on enabled exceptions; complete successful conversions through the same helper.

### S64-R7-3 — BUG — HIGH

- **Summary**: Directed rounding changes exact results.
- **Locations**: [fp_sd.c:285](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:285), [fp_quad.c:310](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:310), [fp_qdiv.c:245](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:245), [fp_qconv.c:268](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:268).
- **Evidence & Root Cause**: Upward/downward rounding increments based solely on sign, without requiring discarded bits. Upward `FADDS(1,1)` produces `0x40000001` instead of `0x40000000`, with NX clear. The same defect affects double and quad operations and narrowing conversions.
- **Remediation**: Require `g || r || s` before any directed-rounding increment.

### S64-R7-4 — BUG — HIGH

- **Summary**: FP addition/subtraction discards information needed for correct arithmetic.
- **Locations**: [fp_sd.c:374](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:374), [fp_sd.c:417](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:417), [fp_quad.c:411](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:411).
- **Evidence & Root Cause**: Single/double alignment collapses discarded bits into sticky before arithmetic. Subtraction omits their borrow; quad subtraction likewise fails to incorporate its separated fractional bits during subtraction and normalization. `FSUBS(0x3f800000,0x3f7fffff)` produces `2^-23` with NX instead of exact `2^-24`.
- **Remediation**: Retain an extended significand through alignment, subtraction, and normalization; round only afterward.

### S64-R7-5 — BUG — HIGH

- **Summary**: Quad subnormal packing loses retained fraction bits and boundary rounding information.
- **Locations**: [fp_quad.c:286](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:286), [fp_quad.c:356](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:356), [fp_qdiv.c:221](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:221), [fp_qdiv.c:290](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:290).
- **Evidence & Root Cause**: Subnormal output retains `slo` but discards the fraction in `shi`. Thus `FMULQ(2^-16382,0.5)` returns zero instead of an exact nonzero subnormal. Additionally, `shift >= 113` clears guard/round, making nearest-rounded `min_subnormal × 0.75` incorrectly become zero.
- **Remediation**: Preserve both fraction halves and compute guard/round/sticky correctly at the 113-bit boundary.

### S64-R7-6 — BUG — HIGH

- **Summary**: `FQTOS` loses the sign of negative finite results.
- **Locations**: [fp_qconv.c:344](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:344), [fp_qconv.c:379](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:379), [fp_qconv.c:792](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:792).
- **Evidence & Root Cause**: Binary32 packing places the sign in bit **32**. The destination assignment then casts to `uint32_t`, discarding it. `FQTOS(-1.0Q)` therefore yields positive `0x3f800000`. Finite negative overflow and underflow paths have the same defect.
- **Remediation**: Place the binary32 sign in bit 31 in every packing branch.

### S64-R7-7 — BUG — HIGH

- **Summary**: `FSMULD` truncates its widened product.
- **Locations**: [fp_conv.c:579](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:579), [fp_sd.c:663](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:663).
- **Evidence & Root Cause**: The caller requests a 24-bit product, discards its GRS bits, and widens the truncated significand. Multiplying two single values `0x3f800001` yields double `0x3ff0000040000000` instead of `0x3ff0000040000040`. The full product fits exactly in double precision, as reflected in [QEMU’s widening implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/fop_helper.c).
- **Remediation**: Preserve the complete 48-bit significand product before encoding the double result.

### S64-R7-8 — BUG — HIGH

- **Summary**: `STQF` stores the high half twice.
- **Locations**: [fp_ldst.c:208](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:208).
- **Evidence & Root Cause**: Both eight-byte stores use `cpu->fp.d[2U * qi]`. The low 64 bits are never read. Every quad value with unequal halves is corrupted when stored; the comment intentionally reproducing an oracle quirk does not implement the register’s contents.
- **Remediation**: Store `cpu->fp.d[2U * qi + 1U]` at `va + 8`.

### S64-R7-9 — BUG — HIGH

- **Summary**: Integer `LDDA/STDA` access floating-point registers.
- **Locations**: [decode.c:481](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:481), [fp_ldst.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:119), [fp_ldst.c:218](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:218).
- **Evidence & Root Cause**: The decoder unconditionally classifies integer alternate doubleword instructions as FPU operations. For example, `ldda [addr] 0x80,%l0` writes `fp.d[8]` and leaves `%l0/%l1` unchanged. `STDA` correspondingly stores unrelated FPR contents.
- **Remediation**: Route integer doubleword instructions to integer handlers; distinguish specialized ASIs without changing the architectural register file.

### S64-R7-10 — BUG — HIGH

- **Summary**: Misaligned atomics become fatal internal errors.
- **Locations**: [interp_mem.c:302](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:302), [interp_mem.c:357](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:357), [threads.c:861](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.c:861), [mem_space_write.c:615](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/mem_space_write.c:615).
- **Evidence & Root Cause**: Misaligned CASA/CASXA/SWAP are declined by the host fast path, then forwarded without alignment validation to the atomic substrate. Its rejection becomes `SPARC64_STEP_INTERNAL`, terminating execution instead of delivering a recoverable guest alignment signal.
- **Remediation**: Check natural alignment before either atomic backend and return the architectural misalignment trap.

### S64-R7-11 — BUG — MEDIUM

- **Summary**: Tagged arithmetic incorrectly sets `xcc.V` and traps on 64-bit overflow.
- **Locations**: [interp_win.c:644](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:644).
- **Evidence & Root Cause**: Nonzero tags set both overflow bits, and trapping variants test `icc.V | xcc.V`. Consequently, `TADDcc(1,0)` wrongly sets `xcc.V`; `TADDccTV(0x7fffffff00000000,0x100000000)` wrongly traps. Tag overflow affects `icc.V`; 64-bit overflow alone does not trigger the tagged trap. [V9 tagged-arithmetic specification](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=260).
- **Remediation**: Apply tag bits only to `icc.V` and base the TV exception solely on tag/32-bit overflow.

### S64-R7-12 — BUG — MEDIUM

- **Summary**: A valid `TADDcc` encoding is misclassified as SIR.
- **Locations**: [decode.c:198](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:198).
- **Evidence & Root Cause**: `op3=TADDcc, rd=31, rs1=0, i=1` is forcibly classified privileged. Thus `taddcc %g0,0,%i7` traps instead of writing zero and updating CCR. SIR uses the WRASR encoding, not this arithmetic opcode.
- **Remediation**: Remove the false SIR special case from the ALU decoder.

### S64-R7-13 — BUG — MEDIUM

- **Summary**: Legacy integer division truncates overflow, mishandles signed results, and copies incorrect flags into `xcc`.
- **Locations**: [interp_win.c:502](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:502), [interp_win.c:591](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:591).
- **Evidence & Root Cause**: UDIV with `Y=1`, low dividend zero, divisor one returns zero instead of saturated `0xffffffff`. SDIV producing `-1` zero-extends it. The `cc` variants calculate flags from truncated results and assign identical nibbles, incorrectly propagating 32-bit overflow to `xcc.V`. [V9 division rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=178).
- **Remediation**: Saturate before publishing results, sign-extend signed quotients, and calculate each CCR nibble separately.

### S64-R7-14 — BUG — MEDIUM

- **Summary**: `MULScc` implements the wrong multiply-step algorithm.
- **Locations**: [interp_win.c:671](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:671).
- **Evidence & Root Cause**: It uses `xcc.N xor xcc.V` to select the addend, adds before shifting, and inserts `Y[0]` into the result. With `rs1=0`, `rs2=2`, `Y=1`, and CCR zero, it returns `0x80000000` instead of low-word `2`. [QEMU’s implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c) follows the required shift-then-add sequence.
- **Remediation**: Shift using `icc.N xor icc.V`, select the multiplicand using old `Y[0]`, then add and update ICC.

### S64-R7-15 — BUG — MEDIUM

- **Summary**: `FLUSHW` unnecessarily spills the current window.
- **Locations**: [interp.c:152](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:152), [interp_win.c:249](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:249).
- **Evidence & Root Cause**: Architectural `FLUSHW` calls a runtime snapshot helper that always writes the current `%l/%i` image. A second FLUSHW after all caller windows have been flushed still writes 128 bytes, or faults if the current stack pointer is unmapped. Architectural FLUSHW excludes the current window. [V9 A.21](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=193).
- **Remediation**: Separate architectural caller-window flushing from full runtime snapshots.

### S64-R7-16 — BUG — MEDIUM

- **Summary**: Legacy `FBfcc` instructions always decode as illegal.
- **Locations**: [decode.c:121](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:121).
- **Evidence & Root Cause**: Only `op2=5` is handled. The code explicitly rejects `op2=6`, which is the legacy floating branch with `disp22` and FCC0. Valid floating branches therefore trap before condition or annul handling. Both families are implemented independently in [QEMU’s SPARC translator](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Decode `op2=6` with FCC0 and signed `disp22`, retaining the existing predicted form.

### S64-R7-17 — BUG — MEDIUM

- **Summary**: Register-conditioned `FMOVr` instructions are unimplemented.
- **Locations**: [fp.c:424](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:424), [fp.c:558](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:558).
- **Evidence & Root Cause**: The function named `fp_movr` implements integer-CCR-conditioned FMOVcc. Actual FMOVr encodings, such as `FMOVRsZ` with `opf=0x025`, match neither dispatch condition and always trap.
- **Remediation**: Decode the register-conditioned family separately, evaluate full-width `rs1`, and implement single/double/quad copies.

### S64-R7-18 — BUG — MEDIUM

- **Summary**: Floating conditional moves use the wrong “unordered or greater” predicate.
- **Locations**: [fp.c:341](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:341), [fp.c:397](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:397).
- **Evidence & Root Cause**: Condition 5 returns `fcc != 2`, accepting equal/less/unordered and rejecting greater. The already-correct shared evaluator uses `fcc == 3 || fcc == 2`. This causes unwanted destination writes and missed moves.
- **Remediation**: Reuse `sparc64_eval_fcond` instead of maintaining a divergent predicate table.

### S64-R7-19 — BUG — MEDIUM

- **Summary**: `ALIGNADDRL` computes the wrong GSR alignment offset.
- **Locations**: [decode.c:318](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:318), [interp.c:135](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:135).
- **Evidence & Root Cause**: ALIGNADDR and ALIGNADDRL share a handler that always stores `sum & 7`. ALIGNADDRL requires `(-sum) & 7`; a sum ending in one should set seven. Subsequent FALIGNDATA therefore splices the wrong bytes. [QEMU ALIGNADDRL implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Select the negated low-three-bit offset for ALIGNADDRL while preserving the aligned destination address.

### S64-R7-20 — BUG — MEDIUM

- **Summary**: Immediate `Tcc` ignores `rs1` when calculating the trap number.
- **Locations**: [interp.c:368](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:368).
- **Evidence & Root Cause**: Immediate form uses `d->imm` alone. With `%g2=0x60`, `ta %g2+0x0d` should select trap `0x6d`, but instead takes the generic trap path. The inverse can incorrectly invoke the syscall gate. [V9 Tcc definition](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=264).
- **Remediation**: Always add `rs1` to the selected second operand, mask to seven bits, and carry that evaluated number through dispatch.

### S64-R7-21 — BUG — MEDIUM

- **Summary**: Misaligned `JMPL/RETURN` targets produce the wrong signal and fault value.
- **Locations**: [interp.c:298](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:298), [interp.c:316](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:316).
- **Evidence & Root Cause**: Both paths return `SPARC64_TRAP_ILLEGAL` with the instruction word. The signal layer delivers SIGILL instead of the alignment signal, and loses the target address. Misaligned jump targets require an alignment exception. [V9 JMPL definition](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=195).
- **Remediation**: Return an alignment-specific trap carrying the target, with correct SIGBUS mapping and pre-commit state.

### S64-R7-22 — BUG — MEDIUM

- **Summary**: A pending branch target of zero is destroyed on a delay-slot trap.
- **Locations**: [interp.c:482](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:482).
- **Evidence & Root Cause**: Trap cleanup treats `cpu->npc == 0` as missing state. After a branch to zero whose delay instruction traps, the branch has already published the correct nPC, but cleanup replaces it with `delay_pc + 4`. Signal recovery resumes along the wrong path.
- **Remediation**: Track whether PC/nPC were published explicitly; never use a guest address as an initialization sentinel.

### S64-R7-23 — BUG — MEDIUM

- **Summary**: Integer alternate accesses reject valid `%asi` register forms.
- **Locations**: [decode.c:468](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:468), [interp_mem.c:412](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:412), [interp_mem.c:450](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:450).
- **Evidence & Root Cause**: The decoder uses `asi=0xff` for `i=1`; integer handlers pass it unchanged to validation, which rejects it. Thus writing `%asi=0x80` cannot enable ordinary register-ASI loads/stores or CAS. CASA/CASXA decoding also leaves their compare-register field zero in this form.
- **Remediation**: Resolve `regasi` from CPU state before validation and decode CAS `rs2` independently of the `i` bit.

### S64-R7-24 — BUG — MEDIUM

- **Summary**: No-fault ASIs behave like ordinary writable ASIs.
- **Locations**: [interp_mem.c:416](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:416), [interp_mem.c:549](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:549), [fp_ldst.c:218](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:218).
- **Evidence & Root Cause**: ASIs `0x82/0x8a` affect only byte order. An aligned no-fault load from unmapped memory traps instead of returning zero; stores through those ASIs modify memory. FP loads and host atomic admission share the omission. [QEMU ASI helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/ldst_helper.c).
- **Remediation**: Preserve no-fault semantics through execution, suppress only eligible guest access faults, and reject stores/atomics through no-fault ASIs.

### S64-R7-25 — BUG — MEDIUM

- **Summary**: `LDD/STD` accept addresses lacking doubleword alignment.
- **Locations**: [interp_mem.c:475](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:475), [interp_mem.c:571](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:571).
- **Evidence & Root Cause**: Two independent four-byte accesses enforce only four-byte alignment. Address `0x1004` succeeds. Four bytes before an inaccessible page, LDD commits its first register and STD writes its first word before faulting, instead of rejecting the original misaligned access.
- **Remediation**: Check eight-byte alignment first and stage the complete load before publishing either register.

### S64-R7-26 — BUG — MEDIUM

- **Summary**: FP double/quad memory operations reject valid word-aligned addresses.
- **Locations**: [fp_ldst.c:190](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:190), [fp_ldst.c:219](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:219), [fp_ldst.c:232](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:232).
- **Evidence & Root Cause**: LDDF/STDF inherit eight-byte alignment checks; LDQF/STQF explicitly require sixteen. V9 permits word alignment, with software emulation for optional stricter hardware traps. This user-mode implementation instead delivers SIGBUS for addresses such as `0x1004`. [V9 FP memory alignment](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=197).
- **Remediation**: Support word-aligned transfers using staged four-byte pieces or equivalent checked byte access.

### S64-R7-27 — BUG — MEDIUM

- **Summary**: CAS can succeed on read-only memory when comparison fails.
- **Locations**: [interp_mem.c:228](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:228), [interp_mem.c:254](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:254).
- **Evidence & Root Cause**: After the writable-memory fast path declines, fallback LR requires only read permission. A mismatch immediately returns success. A read-only word containing one with compare operand two therefore avoids the required write-permission fault. CAS requires writability even on mismatch. [V9 A.9](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=177).
- **Remediation**: Validate read/write access for the entire atomic operation before comparison.

### S64-R7-28 — BUG — MEDIUM

- **Summary**: Generic CASA paths compare the unused upper 32 bits.
- **Locations**: [interp_mem.c:232](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:232), [interp_mem.c:275](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:275), [interp_mem.c:645](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:645).
- **Evidence & Root Cause**: Generic callback/fallback execution compares a zero-extended memory word with the full 64-bit compare register. Memory `1` and compare register `0x100000001` incorrectly mismatch. The host fast path truncates correctly, making behavior backend-dependent.
- **Remediation**: Mask compare and replacement operands to the requested atomic width before selecting any backend.

### S64-R7-29 — BUG — MEDIUM

- **Summary**: FSR transfers overwrite preserved state and omit required completion effects.
- **Locations**: [interp_mem.c:515](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:515), [interp_mem.c:590](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:590).
- **Evidence & Root Cause**: LDFSR replaces the whole FSR, clearing FCC1–FCC3. Both load forms accept unrestricted values instead of applying writable-field masks. Successful STFSR/STXFSR never clear FTT. Reserved `rd=2..31` forms also fall through as valid transfers. [V9 FSR transfer rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=249).
- **Remediation**: Validate encodings, preserve unaffected/read-only fields, and clear FTT only after successful stores.

### S64-R7-30 — BUG — MEDIUM

- **Summary**: FP register writes never update FPRS dirty bits.
- **Locations**: [fp.c:201](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:201), [fp_ldst.c:223](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:223), [interp.c:95](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:95).
- **Evidence & Root Cause**: Destination writes modify only the FP file. After clearing dirty bits with `wr %g0,4,%fprs`, modifying `%f2` still leaves readable FPRS equal to four. Upper-bank writes similarly omit DU.
- **Remediation**: Set the corresponding DL/DU bits on committed FP writes, including loads, conversions, and VIS operations.

### S64-R7-31 — BUG — MEDIUM

- **Summary**: Widening subnormal single/double values to quad changes their values.
- **Locations**: [fp_qconv.c:651](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:651), [fp_qconv.c:702](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:702).
- **Evidence & Root Cause**: Normalization targets bit 22/51 instead of 23/52, then packs the remaining fraction at the normal scale. Single input bits `0x00000003` become `2.5 × 2^-149` instead of `3 × 2^-149`. Double input bits `3` have the analogous error.
- **Remediation**: Normalize at the actual hidden-bit position and remove that bit using the full fraction mask.

### S64-R7-32 — BUG — MEDIUM

- **Summary**: Float-to-integer conversions reject valid boundary values and raise spurious overflow.
- **Locations**: [fp_conv.c:274](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:274), [fp_conv.c:307](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:307), [fp_qconv.c:568](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:568).
- **Evidence & Root Cause**: Quad conversion rejects exact `-2^31/-2^63`; double-to-int32 rejects `-2147483648.5` before truncation. Invalid paths commit NV|OF, so enabling only OF can trap an invalid conversion whose NV is masked.
- **Remediation**: Check representability after truncation, permit the negative endpoint, and raise NV alone for invalid conversions.

### S64-R7-33 — BUG — MEDIUM

- **Summary**: Quad zero addition/subtraction ignores operand signs.
- **Locations**: [fp_quad.c:671](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:671).
- **Evidence & Root Cause**: Both-zero handling chooses the result sign solely from rounding direction. Nearest `FADDQ(-0,-0)` returns +0; downward `FADDQ(+0,+0)` returns -0. These are same-sign additions, not cancellation.
- **Remediation**: Preserve a common effective operand sign; use rounding direction only for opposite-sign cancellation.

### S64-R7-34 — BUG — MEDIUM

- **Summary**: `FDIVQ` raises divide-by-zero for infinity divided by zero.
- **Locations**: [fp_qdiv.c:556](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:556).
- **Evidence & Root Cause**: The zero-denominator branch precedes the infinite-numerator branch. Consequently, `+Inf / +0` sets DZ and can trap, although the result is infinity without an exception. The single/double implementation already handles this case correctly.
- **Remediation**: Handle an infinite numerator before the finite-nonzero divided-by-zero case.

### S64-R7-35 — BUG — MEDIUM

- **Summary**: Enabled FP overflow/underflow traps publish multiple current-exception bits.
- **Locations**: [fp_commit.c:21](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_commit.c:21), [fp.c:159](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:159).
- **Evidence & Root Cause**: Trap commitment copies all fresh flags into CEXC. Overflow supplies `0x09`, leaving OF|NX when trapping. A trapped overflow/underflow must report the corresponding exception alone, including when NXM causes the trap. [V9 CEXC rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=71).
- **Remediation**: Select the architectural trapped exception before writing CEXC; retain combined flags only for nontrapping completion.
