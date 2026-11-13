Read every file in `src/interp/` and the relevant CPU, window, trap, and FPU headers end-to-end. Findings below are from static inspection; no builds, tests, or modifications were performed.

### S32-R7-1 — BUG — HIGH

- **Summary**: SAVE/RESTORE loses outgoing-register state across window rotations.
- **Locations**: [interp_win.c:143](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:143), lines 143–155, 183–185, 206–209.
- **Evidence & Root Cause**: SAVE replaces `%i*` and `%l*` but leaves the previous window’s `%o*` in place. RESTORE caches only `%l*`/`%i*`. With resident windows: set CWP6 `%o0=0x11`; SAVE to CWP5; set `%o0=0x22`; RESTORE; SAVE again. The interpreter produces `%o0=0x11`, losing CWP5’s `0x22`. The backing representation does not preserve the physical overlap between outgoing and neighboring incoming registers.
- **Remediation**: Model the overlapping register bank explicitly, or synchronize outgoing registers with the neighboring window’s input storage on every rotation.

### S32-R7-2 — BUG — MEDIUM

- **Summary**: Modifying `%i6` can make RESTORE spuriously fault or replace resident registers from memory.
- **Locations**: [interp_win.c:182](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:182), lines 182–204.
- **Evidence & Root Cause**: RESTORE treats a valid target window as missing when its recorded stack address differs from current `%i6`. After two SAVEs, set `%i6=0` and execute `restore %g0,%g0,%g0`. The target window is resident, but the interpreter attempts a fill from address zero. With a mapped replacement address, it instead substitutes memory contents for the resident locals/inputs.
- **Remediation**: Base fills on explicit window validity. An ordinary register change must not implicitly invalidate a resident window.

### S32-R7-3 — BUG — HIGH

- **Summary**: A delayed transfer in a delay slot repeatedly executes itself.
- **Locations**: [interp.c:562](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:562), lines 622–633.
- **Evidence & Root Cause**: Before recursively calling `interp_cti(ctx, npc, &dd)`, the outer transfer never updates `ctx->npc`. For `ba T1` followed by non-annulled `ba T2`, the inner call fetches the same second branch as its own delay slot, indefinitely. This prevents return to signal/retirement polling and may exhaust the host stack depending on optimization. Unconditional DCTI couples have defined sequencing. [V8 §5, Table 5-12](https://research.swtch.com/sparcv8.pdf#page=55).
- **Remediation**: Advance architectural PC/nPC before executing the delay instruction; avoid recursive execution of transfers using stale context.

### S32-R7-4 — BUG — HIGH

- **Summary**: CALL/Bicc/FBfcc delay-slot faults save the wrong PC/nPC.
- **Locations**: [interp.c:622](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:622), lines 622–643; [interp_signal.c:226](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:226).
- **Evidence & Root Cause**: Only JMPL repairs PC/nPC when delay fetch or execution fails. Other transfers leave PC at the branch and nPC at its delay slot. Signal delivery copies those values directly into the frame. A faulting instruction at `B+4` therefore reports `PC=B`, and its pending branch target is lost. Handler recovery can retry the branch or fail to skip the actual faulting instruction.
- **Remediation**: Record the delay instruction’s PC and already-selected successor before fetching or executing it, for every transfer class.

### S32-R7-5 — BUG — HIGH

- **Summary**: Ticc instructions in delay slots become illegal instructions.
- **Locations**: [interp.c:506](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:506), lines 506–547, 635; [interp.c:685](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:685).
- **Evidence & Root Cause**: Ticc is implemented only in the top-level `interp_step()` path. Delay slots go through `interp_single()`, which has no `SPARC32_OP_TRAP` case. Thus a delay-slot `ta 0x10` never invokes its syscall; even a never-taken `tn` produces `EXIT_UNDEF`.
- **Remediation**: Share Ticc execution between ordinary and delay-slot paths, preserving the delay instruction’s architectural PC/nPC.

### S32-R7-6 — BUG — HIGH

- **Summary**: Integer division truncates overflowing quotients instead of saturating.
- **Locations**: [interp.c:267](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:267), lines 267–324.
- **Evidence & Root Cause**: UDIV/SDIV cast the full quotient to 32 bits. Their `cc` variants detect overflow but still commit the truncated value and derive N/Z from it. For `Y=1`, `rs1=0`, divisor `1`, UDIV returns zero instead of `0xffffffff`; UDIVcc also sets Z incorrectly. The `INT64_MIN / -1` special case returns negative saturation despite a positive quotient. [V8 B.19](https://research.swtch.com/sparcv8.pdf#page=113).
- **Remediation**: Saturate all four divide forms before committing the result. Derive N/Z from that result and V from overflow.

### S32-R7-7 — BUG — HIGH

- **Summary**: MULSCC implements the wrong multiply-step algorithm.
- **Locations**: [interp.c:342](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:342), lines 342–360.
- **Evidence & Root Cause**: The code selects the addend using `N xor V`, adds before shifting, and inserts `Y[0]` into the result’s high bit. The required operation shifts `rs1` with `N xor V`, then conditionally adds using `Y[0]`. With `rs1=0`, operand2=`2`, `Y=1`, and clear ICC, this implementation returns `0x80000000` with Z set instead of `2`. [QEMU’s MULSCC implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Correct the operand selection and operation order; calculate ICC from the actual addition.

### S32-R7-8 — BUG — MEDIUM

- **Summary**: UMULcc/SMULcc incorrectly set ICC.V.
- **Locations**: [interp.c:182](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:182), lines 182–193, 257–265.
- **Evidence & Root Cause**: `interp_mulcc()` sets V when the signed product does not fit 32 bits. For example, `0x40000000 * 2` sets V. V8 specifies V=0 for both multiply-with-condition-code forms. The comment’s claimed signed-overflow rule is incorrect. [V8 B.18](https://research.swtch.com/sparcv8.pdf#page=111).
- **Remediation**: Set N/Z from the low product word and clear V/C.

### S32-R7-9 — BUG — MEDIUM

- **Summary**: Trapping tagged arithmetic commits ICC before raising the trap.
- **Locations**: [interp.c:332](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:332), lines 332–340.
- **Evidence & Root Cause**: TADDccTV/TSUBccTV call the ICC-mutating helpers before checking arithmetic/tag overflow. A tagged operand such as `1` therefore changes ICC despite trapping. These instructions must preserve both destination and ICC on overflow. [V8 B.14/B.16](https://research.swtch.com/sparcv8.pdf#page=107).
- **Remediation**: Compute prospective result and flags separately; commit them only after the trap checks pass.

### S32-R7-10 — BUG — HIGH

- **Summary**: CASA’s immediate-ASI encoding is rejected because the `i` bit check is reversed.
- **Locations**: [decode.c:258](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:258), lines 258–269.
- **Evidence & Root Cause**: The decoder requires `i=1` while interpreting bits 12:5 as an immediate ASI. Immediate-ASI CASA uses `i=0`. LLVM’s LEON encoding example `0xd5e60156` is consequently rejected. Conversely, the decoder accepts the register-ASI form and treats its bits as an immediate. The historical experiment even records disassembly using `%asi`, exposing this confusion. [LLVM LEON CASA encoding](https://reviews.llvm.org/D20098).
- **Remediation**: Accept the immediate-ASI form with `i=0`; reject unsupported register-ASI forms. Correct the encoding constants and associated documentation.

### S32-R7-11 — BUG — MEDIUM

- **Summary**: Real STBAR instructions are decoded as privileged ASR reads.
- **Locations**: [decode.h:121](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.h:121), `SPARC32_OP3_STBAR`; [decode.c:184](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:184); [interp.c:380](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:380).
- **Evidence & Root Cause**: STBAR is assigned op3 `0x2c`. Its real encoding is the RDASR form with op3 `0x28`, `rs1=15`, and `rd=0`. Thus `0x8143c000` reaches `interp_rdwr()` and traps because ASR15 is nonzero. [V8 B.30](https://research.swtch.com/sparcv8.pdf#page=134).
- **Remediation**: Recognize STBAR’s special encoding before generic RDASR dispatch; remove the invented op3 assignment.

### S32-R7-12 — BUG — HIGH

- **Summary**: Instruction fetch bypasses VM synchronization and authoritative shared permissions.
- **Locations**: [decode.c:405](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:405), lines 405–441; [vm.c:237](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm.c:237).
- **Evidence & Root Cause**: Fetch checks `ctx->regions`, then directly dereferences guest memory without the VM access gate. A sibling can unmap or revoke access between validation and the load, causing a host fault instead of a recoverable guest fault. Region snapshots also become stale: mutations synchronize the caller and root context, not every sibling. A sibling can therefore continue fetching after execute permission is removed while host-readable bytes remain.
- **Remediation**: Hold the VM access gate across fetch validation and copying. Validate against authoritative shared page permissions rather than context snapshots.

### S32-R7-13 — BUG — MEDIUM

- **Summary**: Doubleword stores can partially commit across mapping changes.
- **Locations**: [interp.c:478](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:478), lines 478–486; [fp.c:265](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:265); [interp_mem.c:110](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:110).
- **Evidence & Root Cause**: STD validates eight bytes outside the VM gate, then performs two independently gated stores. STDF likewise uses separate stores. A sibling can revoke permissions after the first word, making the second fault after memory has already changed. LDD/LDDF similarly permit their two reads to observe different mappings.
- **Remediation**: Hold one VM access gate across validation and the complete doubleword transfer. Preserve all-or-nothing fault behavior.

### S32-R7-14 — BUG — MEDIUM

- **Summary**: Misaligned JMPL targets can be classified as SIGSEGV instead of SIGBUS.
- **Locations**: [interp.c:591](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:591); [interp_signal.c:754](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:754).
- **Evidence & Root Cause**: JMPL detects target misalignment before its delay slot runs. The classifier nevertheless skips every JMPL and derives alignment from the following instruction. A target of `0x1001` with an `ldub` delay slot is classified using width one and produces SIGSEGV.
- **Remediation**: Record the fault’s cause and required alignment directly, distinguishing target-alignment faults from delay-slot memory faults.

### S32-R7-15 — BUG — HIGH

- **Summary**: Integer and illegal-instruction traps terminate execution instead of invoking installed guest handlers.
- **Locations**: [interp.c:158](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:158); [interp_signal.c:149](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:149); [main.c:259](/Users/angerman/Projects/zw3rk/sparc32rt/src/main.c:259), lines 259–277.
- **Evidence & Root Cause**: Divide-by-zero and tagged overflow produce `EXIT_TRAP`; illegal instructions produce `EXIT_UNDEF`. The run loop attempts synchronous delivery only for `EXIT_FAULT`, and the delivery helper accepts only SIGBUS/SIGSEGV. An installed SIGFPE or SIGILL handler is therefore bypassed; the translator prints a diagnostic and returns status 1.
- **Remediation**: Map architectural traps to guest signals and `si_code`, preserving fault PC/nPC and invoking the normal synchronous delivery path.

### S32-R7-16 — BUG — HIGH

- **Summary**: FSR.TEM never enables floating-point traps.
- **Locations**: [fp_arith.c:85](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:85); [fp.c:103](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:103), lines 103–152.
- **Evidence & Root Cause**: `fp_raise()` always updates current/accrued flags without checking TEM. Callers then commit destination registers or FCC and return success. With DZM enabled, `FDIVS(1.0, 0.0)` stores infinity and continues. Enabled exceptions require a trap before normal result/accrual commit. [QEMU exception handling](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/fop_helper.c).
- **Remediation**: Centralize FP completion: check prospective exceptions against TEM, record FTT/trap state, and suppress normal destination/FCC/accrual updates when trapping.

### S32-R7-17 — BUG — MEDIUM

- **Summary**: Valid FDTOS instructions targeting odd single registers decode as illegal.
- **Locations**: [decode.c:45](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:45), lines 45–47, 207–209; [fp.h:63](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.h:63).
- **Evidence & Root Cause**: `fpu_double_dest()` labels opcode `0x0c6` as `FiTOd`. The execution header correctly identifies it as `FDTOS`, whose destination is single precision. Consequently, `fdtos %f0,%f1` is rejected before execution. FITOD is `0x0c8`.
- **Remediation**: Correct the precision classification and use consistent opcode metadata for decoder and executor validation.

### S32-R7-18 — BUG — MEDIUM

- **Summary**: LDFSR overwrites read-only state, and successful FP operations retain stale FTT.
- **Locations**: [fp.c:224](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:224); [fp_arith.c:80](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:80).
- **Evidence & Root Cause**: `ctx->fsr = v` accepts every loaded bit, including FTT, QNE, and version state. Subsequent `fp_clear_cexc()` clears only CEXC. A guest can load a nonzero FTT and observe it survive a successful FMOVS. LDFSR must preserve FTT, while successful FPop completion clears it. [V8 FSR definition](https://research.swtch.com/sparcv8.pdf#page=35).
- **Remediation**: Apply an architectural writable-field mask and implement FTT lifecycle in shared FP completion handling.

### S32-R7-19 — BUG — MEDIUM

- **Summary**: Quiet comparisons spuriously accrue an invalid-operation exception.
- **Locations**: [fp_arith.c:837](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:837), lines 837–840, 856–859.
- **Evidence & Root Cause**: Both comparison helpers unconditionally set `FP_FSR_NVA_BIT` for unordered operands. Starting with clear FSR, `FCMPS(qNaN, 1.0)` therefore produces `aexc.NV=1` despite `cexc.NV=0`. Quiet FCMP with no signaling NaN must not raise invalid. [V8 Appendix N.4](https://research.swtch.com/sparcv8.pdf#page=292).
- **Remediation**: Accrue NV only when the comparison is signaling or an operand is a signaling NaN.

### S32-R7-20 — BUG — MEDIUM

- **Summary**: FSMULD misses invalid-operation handling for zero times infinity.
- **Locations**: [fp.c:153](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:153), lines 153–173.
- **Evidence & Root Cause**: After checking NaN operands, FSMULD performs a native double multiplication without inspecting exceptions. `0.0f * +Infinity` consequently stores a host NaN with CEXC cleared and AEXC unchanged. The ordinary FMULS/FMULD helpers explicitly handle this same invalid case.
- **Remediation**: Detect zero/infinity operands and route the invalid result through the common FP exception-completion path.

### S32-R7-21 — BUG — MEDIUM

- **Summary**: FDTOI rejects negative fractional inputs whose truncated integer is representable.
- **Locations**: [fp_arith.c:245](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:245), lines 245–249; [fp.c:191](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:191).
- **Evidence & Root Cause**: The helper rejects values below `-2147483648.0` before applying truncation toward zero. For `-2147483648.5`, the integer result is representable `INT32_MIN`, but the code raises NV instead of NX. Once TEM is implemented, this also selects the wrong trap.
- **Remediation**: Determine representability after the instruction’s rounding operation, using a safe intermediate.

### S32-R7-22 — BUG — MEDIUM

- **Summary**: Directed double-to-single conversion can return infinity without overflow flags.
- **Locations**: [fp_arith.c:290](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:290), lines 290–333.
- **Evidence & Root Cause**: Overflow is checked only before directed-rounding adjustment. For input double bits `0x47efffffe0000001` with `RD=RP`, the initial nearest-rounded cast yields maximum finite binary32. `nextafterf()` then changes it to infinity, but the function returns with only NX set. OFC/OFA are missing. The negative/RM case is symmetric.
- **Remediation**: Classify the final directed-rounded result and apply overflow flags after adjustment.

### S32-R7-23 — DEFECT — MEDIUM

- **Summary**: FP execution ignores the FPop1/FPop2 encoding distinction.
- **Locations**: [decode.c:201](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:201), lines 201–212; [fp.c:71](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:71), lines 71–78.
- **Evidence & Root Cause**: Both instruction groups are passed to an executor that switches solely on `opf`. An FADDS opcode placed under FPop2 therefore performs addition, and an FCMP opcode placed under FPop1 performs comparison. The instruction’s major FP operation group is never validated.
- **Remediation**: Validate the `(op3, opf)` pair against the supported V8 instruction table before reading operands or changing FP state.
