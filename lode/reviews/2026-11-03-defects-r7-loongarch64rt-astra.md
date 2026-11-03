Read all 13 files in `src/interp/` and the relevant CPU, FP/vector, and trap headers end-to-end. There is no `include/` directory in this checkout. No builds or tests were run; the counterexamples below follow from static analysis.

### LA64-R7-1 — BUG — HIGH

- **Summary**: A faulting integer load overwrites the newly installed signal-handler state.
- **Locations**: [interp_mem.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:48), [interp.c:481](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:481), [sigframe.c:262](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:262).
- **Evidence & Root Cause**: `la64_signal_fault()` installs the handler context and returns, despite its header claiming otherwise. `ld_bytes()` then returns zero, which the caller writes into `rd`. A faulting `ld.d a0,...` therefore replaces the handler’s signal-number argument with zero; targeting `sp` destroys its stack pointer. The final PC-change check occurs after this write.
- **Remediation**: Return an explicit fault status and stop instruction execution before destination writeback. Correct the signal helper’s return contract.

### LA64-R7-2 — BUG — HIGH

- **Summary**: Atomic memory faults and rejected FP encodings terminate the translator instead of delivering guest signals.
- **Locations**: [interp_amo.c:28](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:28), [interp.c:617](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:617), [interp.c:835](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:835), [interp_mem.h:32](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:32).
- **Evidence & Root Cause**: Atomic helpers return strings for inaccessible memory; `interp_step()` passes them to `die_at()`, which calls `exit(3)`. Illegal FP comparison conditions follow the same path. Guest `SIGSEGV`/`SIGILL` handlers cannot recover, unlike equivalent faults elsewhere in the interpreter.
- **Remediation**: Replace string-only failures with structured guest faults carrying signal, code, address, and faulting PC. Reserve translator termination for internal failures.

### LA64-R7-3 — BUG — HIGH

- **Summary**: Floating-point exception enables are ignored.
- **Locations**: [fp_vec_priv.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:48), [fp.c:474](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:474).
- **Evidence & Root Cause**: `fp_sync()` never checks FCSR Enables. With `fcsr0=8`, `FDIV.D(1.0,0.0)` commits infinity and continues. Most scalar callers commit their destination before synchronizing exceptions. [QEMU’s FCSR handling](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/fpu_helper.c) checks Enables and raises FPE before returning a result.
- **Remediation**: Stage results, update Cause, check Enables, and deliver guest `SIGFPE` before destination writeback. Apply the corresponding nontrapping Flags rules.

### LA64-R7-4 — BUG — HIGH

- **Summary**: Atomic, scalar-FP, and vector stores bypass shared-file alias propagation.
- **Locations**: [interp_amo.c:45](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:45), [fp_vec.c:54](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:54), [interp_vec.c:109](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_vec.c:109), [fp_shuf.c:136](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_shuf.c:136), [fp_vec_lasx.c:620](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_lasx.c:620).
- **Evidence & Root Cause**: These store paths omit `la64_vm_file_note_store()`, which ordinary integer stores call. For staged `MAP_SHARED` mappings of the same file offset at A and B, an `AMADD.W`, successful `SC.W`, `FST`, or vector store through A leaves B stale. This fails within one thread.
- **Remediation**: Notify the shared-file layer after every successful store, including indexed vector stores, while preserving serialization. Failed CAS/SC operations must not report a write.

### LA64-R7-5 — BUG — HIGH

- **Summary**: LL/SC can succeed after an interfering write through another shared-memory alias.
- **Locations**: [interp_amo.c:242](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:242), [interp_amo.c:264](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:264), [clone.c:739](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:739), [vm_file_sync.c:200](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:200).
- **Evidence & Root Cause**: SC checks only `ll_valid` and the guest address. Reservation invalidation compares guest-address ranges, while shared-alias propagation changes the backing bytes without invalidating reservations at other addresses. Worker A can LL through one alias, worker B store through another, and worker A subsequently SC successfully over the intervening update. Scheduler turns preserve the reservation.
- **Remediation**: Track reservations by backing-memory identity and invalidate across aliases. Comparing `ll_val` alone would still miss ABA writes.

### LA64-R7-6 — BUG — HIGH

- **Summary**: Bounds-checking loads/stores access the wrong address and suppress required traps.
- **Locations**: [interp.c:696](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:696).
- **Evidence & Root Cause**: `LDGT/LDLE/STGT/STLE` compare `rj` with `rk`, but access memory at `rk`. Failed comparisons silently skip stores or copy `rj` into the load destination. These instructions must access `rj` after a successful bounds assertion and raise a bounds exception otherwise. [QEMU’s implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_memory.c.inc) demonstrates both requirements.
- **Remediation**: Perform the bounds assertion first, deliver the appropriate guest fault on failure, and use `rj` as the memory address.

### LA64-R7-7 — BUG — HIGH

- **Summary**: Vector float-to-integer conversion permits undefined C casts.
- **Locations**: [fp_vec.c:374](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:374), [fp_vec.c:497](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:497).
- **Evidence & Root Cause**: `vf_cvt_lane()` checks the unrounded value, then casts `rint(x)` to `int32_t`. Under nearest-even rounding, `2147483647.75` passes the check but rounds to `2147483648`, making the cast undefined. Negative boundary values fail similarly under downward rounding. `VFTINT.W.D` and its LASX counterpart reach this code.
- **Remediation**: Round provisionally, validate the rounded value, and only then cast. Generate the architectural invalid-conversion result explicitly.

### LA64-R7-8 — BUG — HIGH

- **Summary**: The vector decoder conflates distinct conversion instructions.
- **Locations**: [fp_vec.c:631](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:631), [fp_vec.c:677](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:677).
- **Evidence & Root Cause**: Dispatch uses `k15 >> 2`, discarding distinguishing opcode bits. `VFCVT.H.S` and `VFCVT.S.D` both execute double-to-single conversion; `VFFINT.S.L` and `VFTINT.W.D` both execute double-to-integer conversion. Integer source lanes containing `1` consequently produce zero for `VFFINT.S.L`, rather than floating-point `1.0`. LASX shares this decoder. [QEMU’s encoding table](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/insns.decode) distinguishes these instructions.
- **Remediation**: Match complete conversion opcodes and implement each source width, destination width, and conversion direction separately.

### LA64-R7-9 — DEFECT — HIGH

- **Summary**: Advertised LSX/LASX support includes valid instructions that unconditionally terminate execution.
- **Locations**: [interp_mem.h:166](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:166), [fp_vec.c:584](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:584), [fp_vec.c:717](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:717), [fp_shuf.c:169](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_shuf.c:169).
- **Evidence & Root Cause**: CPUCFG advertises both extensions, but vector FMA, vector square root, conversion families, and mode-table `VLDI` forms explicitly return “unhandled” errors. The interpreter converts those errors into `exit(3)`. Programs selecting these instructions from the advertised feature profile fail deterministically.
- **Remediation**: Complete the advertised instruction families. Until then, expose an accurate capability profile and retain proper guest illegal-instruction handling.

### LA64-R7-10 — BUG — MEDIUM

- **Summary**: CRC instructions use an oversized accumulator, and CRCC uses the wrong polynomial.
- **Locations**: [interp_bit.h:145](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_bit.h:145), [interp.c:623](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:623).
- **Evidence & Root Cause**: `crc_step()` initializes a 64-bit accumulator from all of `rk`; high bits shift into the checksum. With data zero and seed `0x100000000`, `CRC.W.B.W` produces `0x01000000` instead of zero. CRCC complements the IEEE CRC result instead of using Castagnoli: zero data and zero seed produce `0xffffffff` instead of zero. The [ISA CRC definitions](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html#_crcc_w_bhwd_w) specify a 32-bit seed and separate polynomials.
- **Remediation**: Use a `uint32_t` accumulator and select `0xedb88320` or `0x82f63b78`; remove the CRCC complement.

### LA64-R7-11 — BUG — MEDIUM

- **Summary**: Three byte-reversal instructions implement the wrong permutations.
- **Locations**: [interp.c:366](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:366).
- **Evidence & Root Cause**: `REVB.2H` swaps bytes across all four halfwords without sign-extending the low word. `REVB.4H` reverses bytes within words. `REVB.2W` exchanges words. For input `0x1122334455667788`, `REVB.4H` should produce `0x2211443366558877`, and `REVB.2W` should produce `0x4433221188776655`. [QEMU’s reversal helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_bit.c.inc) corroborate the required permutations.
- **Remediation**: Implement each element width explicitly and apply low-word sign extension for `REVB.2H`.

### LA64-R7-12 — BUG — MEDIUM

- **Summary**: `MULW.D.WU` treats its first operand as signed.
- **Locations**: [interp.c:203](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:203).
- **Evidence & Root Cause**: The expression converts `rj` through `int32_t`, while only `rk` is zero-extended. With `rj=0xffffffff` and `rk=1`, it returns `0xffffffffffffffff` instead of `0x00000000ffffffff`. Both inputs are unsigned words. [QEMU’s arithmetic dispatch](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_arith.c.inc) zero-extends both.
- **Remediation**: Multiply two `uint64_t` values obtained from `uint32_t` operands.

### LA64-R7-13 — BUG — MEDIUM

- **Summary**: Invalid BSTRINS/BSTRPICK ranges execute fabricated operations.
- **Locations**: [decode.c:419](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/decode.c:419), [interp.c:448](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:448).
- **Evidence & Root Cause**: Neither decoding nor execution rejects `msb < lsb`. Unsigned width arithmetic produces zero or wraps to a large value, selecting empty or full-width masks. For example, `msb=0, lsb=2` becomes a full-width operation. [QEMU rejects these encodings](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_bit.c.inc), so the interpreter also violates its oracle contract.
- **Remediation**: Validate the range before computing its width and route rejected encodings through guest `SIGILL`.

### LA64-R7-14 — BUG — MEDIUM

- **Summary**: Mandatory instruction-fetch and atomic alignment checks are missing.
- **Locations**: [interp.c:59](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:59), [interp_amo.c:28](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:28).
- **Evidence & Root Cause**: Fetch accepts any mapped four-byte span without checking `pc & 3`. Atomic helpers access bytes individually without checking natural alignment. Thus an unaligned executable PC can execute, and `AMADD.D` at an address ending in `...001` modifies memory successfully. UAL does not waive these alignment requirements. [ISA alignment rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html), [QEMU atomic alignment](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_atomic.c.inc).
- **Remediation**: Check alignment before fetching or committing atomic effects, then deliver the appropriate guest address/alignment fault.

### LA64-R7-15 — BUG — MEDIUM

- **Summary**: AM word/doubleword instructions execute forbidden destination/address overlap.
- **Locations**: [interp_amo.c:177](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:177), [interp_amo.c:361](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:361).
- **Evidence & Root Cause**: `amswap.d r4,r5,r4` performs a memory write and replaces `r4`; no overlap validation exists. The [ISA’s AM W/D rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html) require an undefined-instruction exception for this combination. By contrast, `rd==rk` has an architecturally uncertain result and is not itself reported here as a mandatory-trap defect.
- **Remediation**: Reject prohibited `rd==rj` combinations before accessing memory, using instruction-specific restrictions.

### LA64-R7-16 — BUG — MEDIUM

- **Summary**: Byte and halfword atomic results are zero-extended.
- **Locations**: [interp_amo.c:141](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:141), [interp_amo.c:167](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:167).
- **Evidence & Root Cause**: `am_cas()` and `am_rmw()` explicitly zero-extend B/H old values. An old byte `0x80` returns `0x80` instead of `0xffffffffffffff80`. This affects AMCAS, AMSWAP, and AMADD, including `_DB`. [QEMU’s B/H memory types](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_atomic.c.inc) are signed.
- **Remediation**: Apply `amo_sx_n(old,n)` at every supported width.

### LA64-R7-17 — BUG — MEDIUM

- **Summary**: Scalar and vector FP comparisons incorrectly order signed zeros.
- **Locations**: [fp.c:371](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:371), [fp_vec.c:469](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:469).
- **Evidence & Root Cause**: Equality compares raw representations. `-0.0` and `+0.0` therefore enter the sign-order branch, producing unequal and less-than results. This corrupts FCC-controlled branches/FSEL and vector comparison masks. [SoftFloat comparison handling](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) treats both zeros as equal.
- **Remediation**: Recognize two zero magnitudes as equal before sign-based ordering.

### LA64-R7-18 — BUG — MEDIUM

- **Summary**: Narrowing vector conversions overwrite unread aliased source lanes.
- **Locations**: [fp_vec.c:480](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:480), [fp_vec.c:530](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:530).
- **Evidence & Root Cause**: Results are written one word at a time while subsequent doubleword sources remain in the destination register. For `vftint.w.d vr0,vr0,vr1`, with `vr0.D={1.0,2.0}` and `vr1.D={3.0,4.0}`, the first two writes destroy the source for result lane 2, yielding `{3,4,0,2}` instead of `{3,4,1,2}`. LASX has the same problem.
- **Remediation**: Snapshot the sources or stage the complete destination before writeback, as [QEMU’s narrowing helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/vec_helper.c) do.

### LA64-R7-19 — BUG — MEDIUM

- **Summary**: Vector FCSR Cause records only the last lane.
- **Locations**: [fp_vec.c:418](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:418), [fp_vec.c:529](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:529), [fp_vec_priv.h:62](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:62).
- **Evidence & Root Cause**: Every lane invokes scalar `fp_sync()`, overwriting Cause. A vector division with `0/0` in lane 0 and exact `1/1` operations afterward finishes with Invalid Cause cleared. [QEMU’s vector helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/vec_helper.c) accumulate exceptions across the instruction.
- **Remediation**: Clear Cause once per vector instruction, aggregate lane exceptions, and perform final exception handling before architectural writeback.

### LA64-R7-20 — BUG — MEDIUM

- **Summary**: `FSCALEB.S` consumes the wrong exponent width.
- **Locations**: [fp.c:525](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:525).
- **Evidence & Root Cause**: Both widths interpret the exponent as `int64_t`. With value `1.0f` and exponent bits `0xffffffff00000001`, `.S` clamps to `-4096` and produces zero instead of `2.0f`. Its exponent is the signed low word, as implemented by [QEMU’s scalar helper](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/fpu_helper.c).
- **Remediation**: Sign-extend the low 32 bits for `.S`; retain the full signed 64-bit exponent for `.D`.

### LA64-R7-21 — BUG — MEDIUM

- **Summary**: FP min/max mishandles NaNs and equal magnitudes.
- **Locations**: [fp.c:53](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:53), [fp_vec.c:322](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:322).
- **Evidence & Root Cause**: The duplicated helpers return the numeric operand for sNaN plus number, spuriously raise Invalid for two qNaNs, and always retain `fj` on magnitude ties. Consequently `FMAXA(-1,+1)` returns `-1`, and `FMINA(+1,-1)` returns `+1`. [SoftFloat min/max semantics](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) distinguish these cases.
- **Remediation**: Implement correct NaN selection/quieting and exception rules; resolve magnitude ties using ordinary signed min/max ordering. Apply the correction to scalar, LSX, and LASX paths.

### LA64-R7-22 — BUG — MEDIUM

- **Summary**: `FLOGB` returns signaling NaNs without quieting or Invalid.
- **Locations**: [fp.c:124](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:124), [fp.c:146](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:146).
- **Evidence & Root Cause**: Both NaN branches return the input directly. For `.D` input `0x7ff0000000000001`, the signaling representation survives and no Invalid exception is raised. This contradicts the [ISA NaN-propagation rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html).
- **Remediation**: Classify NaNs by bits, raise Invalid for sNaNs, and quiet the selected NaN while preserving its payload.

### LA64-R7-23 — BUG — MEDIUM

- **Summary**: `FRSQRTE.S/D` discards floating-point exception status.
- **Locations**: [fp.c:624](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:624), [fp.c:718](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:718).
- **Evidence & Root Cause**: The major-9 group sets `sync=0`, including its arithmetic estimate cases. `FRSQRTE(+0)` produces infinity without recording Divide-by-zero; negative inputs lose Invalid. The [ISA estimate rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html) retain these special-input exceptions.
- **Remediation**: Enable exception synchronization for the estimate cases while retaining no-status-update behavior for register moves.

### LA64-R7-24 — BUG — MEDIUM

- **Summary**: Invalid scalar FP-to-word conversions can also report spurious Inexact.
- **Locations**: [fp.c:243](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:243).
- **Evidence & Root Cause**: `fp_ftint_wd()` calls `rint()` before checking range. For nearest-even `FTINT.W.D(2147483647.5)`, rounding raises Inexact, then the range check adds Invalid without removing that provisional exception. The conversion reports `V|I`; [SoftFloat’s conversion rules](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) report Invalid for this overflow.
- **Remediation**: Compute conversion status independently of intermediate host arithmetic, suppressing provisional Inexact when conversion is invalid.

### LA64-R7-25 — BUG — MEDIUM

- **Summary**: Negated fused operations negate after rounding and alter propagated NaN signs.
- **Locations**: [fp.c:403](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:403).
- **Evidence & Root Cause**: FNMADD/FNMSUB compute `fma()` and then negate its rounded result. Under upward rounding, `FNMADD.D(1,1,2^-53)` returns `-(1+2^-52)` instead of `-1`. [QEMU’s LoongArch mapping](https://raw.githubusercontent.com/qemu/qemu/v10.0.0/target/loongarch/tcg/insn_trans/trans_farith.c.inc) requests pre-round result negation in [SoftFloat](https://raw.githubusercontent.com/qemu/qemu/v10.0.0/fpu/softfloat-parts.c.inc). The explicit operand/result negations also flip selected NaN signs.
- **Remediation**: Apply numerical negation before final rounding, preserving directed-rounding semantics. Handle NaN propagation before numerical sign transformations.

### LA64-R7-26 — BUG — MEDIUM

- **Summary**: Nonzero SYSCALL code fields terminate execution.
- **Locations**: [interp.c:651](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:651).
- **Evidence & Root Cause**: Any nonzero immediate reaches `die_at()` instead of syscall dispatch. The [ISA defines SYSCALL as unconditional](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html); its code field does not make the instruction invalid. The existing Linux dispatch already obtains the syscall number from `a7`.
- **Remediation**: Accept the code field and dispatch through the guest syscall ABI instead of terminating the translator.
