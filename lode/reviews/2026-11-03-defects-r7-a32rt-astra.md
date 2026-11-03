Static audit completed across every file in `src/interp/` and the related emitters, CPU state, exclusive-monitor, and trap paths. No builds, tests, or edits were performed.

### A32-R7-1 — BUG — HIGH

- **Summary**: `UDF.W` executes a syscall instead of raising SIGILL.
- **Locations**: [interp_thumb.c:762](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:762), [dbt_jit_run.c:492](/Users/angerman/Projects/zw3rk/a32rt/src/dbt/dbt_jit_run.c:492).
- **Evidence & Root Cause**: `F7F0 A000`, encoding `UDF.W #0`, returns `A32_EXIT_SVC`. Both interpreter execution and the JIT’s UNDEF fallback subsequently dispatch the syscall selected by `r7`. An instruction intended to trap can therefore perform an external side effect.
- **Remediation**: Decode this family as UNDEF, retain the faulting PC and IT state, and prevent syscall dispatch.

### A32-R7-2 — BUG — HIGH

- **Summary**: Thumb decoder masks turn loads and byte stores into unrelated operations.
- **Locations**: [interp_thumb.c:159](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:159), [interp_thumb.c:277](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:277), [interp_thumb.c:340](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:340).
- **Evidence & Root Cause**: The broad `0x4xxx` branch captures literal loads before their decoder: `0x4800` doubles `r0` instead of loading `[Align(PC+4,4)]`. Incorrect memory-class masks also send `0x7008` (`STRB r0,[r1]`) to the SP-relative word-store fallback, writing four bytes at `sp+32`. Actual `0x9xxx` SP-relative transfers are excluded.
- **Remediation**: Use disjoint architectural masks, explicit SP-relative decoding, and rejection of unmatched encodings.

### A32-R7-3 — BUG — HIGH

- **Summary**: Nonword exclusives, doubleword exclusives, and SWP fall into arithmetic decoding.
- **Locations**: [interp_a32.c:166](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:166), [interp_a32.c:504](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:504).
- **Evidence & Root Cause**: LDREXB/H and STREXB/H use incorrect opcode comparisons. LDREXD/STREXD and SWP lack interpreter dispatch. For example, `E1D10F9F` (`LDREXB r0,[r1]`) reaches the broad multiply decoder and modifies arithmetic registers instead of loading memory. SWP likewise matches that fallback.
- **Remediation**: Decode these families before generic data processing, correct their masks, and provide an eight-byte exclusive reservation implementation.

### A32-R7-4 — BUG — HIGH

- **Summary**: JIT flag elimination destroys the APSR state required at a fault.
- **Locations**: [interp_a32_ctl.c:605](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_ctl.c:605), [interp_t32_mem.c:661](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_t32_mem.c:661), [signals.c:463](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:463).
- **Evidence & Root Cause**: Backward liveness considers flag consumers and overwriters, but not intervening faultable instructions. In `ADDS; LDR [unmapped]; CMP`, the ADDS flag update can be removed because CMP overwrites it. The fault handler then captures stale host NZCV rather than the flags preceding LDR.
- **Remediation**: Treat possible synchronous exits as flag-observation points, or retain sufficient metadata to reconstruct eliminated flags.

### A32-R7-5 — BUG — HIGH

- **Summary**: Synchronous signal frames can contain stale floating-point registers and status.
- **Locations**: [core_emit_alu.c:629](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_alu.c:629), [core_emit_mem.c:170](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:170), [signals.c:448](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:448), [trampoline.S:219](/Users/angerman/Projects/zw3rk/a32rt/src/trampoline.S:219).
- **Evidence & Root Cause**: Eligible self-loops retain modified guest FP registers in host SIMD registers and skip flushing before memory accesses. Fault recovery restores only GPRs and NZCV, then serializes stale `ctx->vfp_d`. Native FPSR exceptions are also merged only after signal-frame construction. Returning from the handler can discard completed FP work and exception flags.
- **Remediation**: Materialize or reconstruct interrupted FP registers and FPSR before constructing the guest frame.

### A32-R7-6 — BUG — MEDIUM

- **Summary**: Instructions requiring alignment accept misaligned addresses or deliver the wrong trap.
- **Locations**: [core_emit_shared.c:508](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:508), [core_emit_mem.c:197](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:197), [interp_a32.c:491](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:491), [interp_vfp_core.c:166](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp_core.c:166).
- **Evidence & Root Cause**: LDM/STM, LDRD/STRD, and VFP transfers use ordinary A64 accesses or `memcpy` without the required alignment checks. `LDRD` from `mapped_page+1` consequently succeeds. Interpreter word exclusives instead report UNDEF for misalignment. These differ from architectural alignment faults. [Arm alignment requirements](https://support.arm.com/documentation/100748/0624/Alignment-support-in-Arm-Compiler-for-Embedded-6/Aligned-and-unaligned-accesses).
- **Remediation**: Enforce instruction-specific alignment and deliver the appropriate guest alignment fault before committing state.

### A32-R7-7 — BUG — HIGH

- **Summary**: Software exclusive reservations can survive intervening writes and incorrectly succeed.
- **Locations**: [interp_a32.c:29](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:29), [interp_a32.c:566](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:566), [vm32.c:439](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:439), [vm32.c:480](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:480).
- **Evidence & Root Cause**: LDREX loads memory before recording the reservation epoch. Intervening writes can therefore occur before its snapshot. Additionally, raw STRD stores and native JIT stores bypass software reservation invalidation. A peer’s A→B→A writes can leave both the saved epoch and compared value unchanged, allowing STREX to succeed.
- **Remediation**: Establish the load/reservation atomically and ensure every overlapping guest write participates in a coherent monitor protocol.

### A32-R7-8 — BUG — MEDIUM

- **Summary**: STM permission probes introduce observable byte writes and torn words.
- **Locations**: [core_emit_shared.c:550](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:550).
- **Evidence & Root Cause**: Validation reads and writes back endpoint bytes before executing STM. Suppose the last word is `0x11223344`: the probe reads `0x11`, a peer stores `0x55667788`, then the probe restores `0x11`. Another thread can observe `0x11667788`, a value produced by neither architectural word store.
- **Remediation**: Validate permissions without modifying guest memory.

### A32-R7-9 — BUG — MEDIUM

- **Summary**: Faulting native SWP overwrites its destination register before completing.
- **Locations**: [interp_a32_dp.c:110](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_dp.c:110), [signals.c:448](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:448).
- **Evidence & Root Cause**: The SWP loop loads directly into guest `Rd` before STXR succeeds. In direct-memory mode, readable but read-only memory permits LDXR and faults on STXR. Signal recovery exposes the loaded value in `Rd`, although the faulting swap has not completed.
- **Remediation**: Hold the loaded value in a temporary and assign `Rd` only after successful completion.

### A32-R7-10 — BUG — MEDIUM

- **Summary**: TPIDRURW aliases TPIDRURO and corrupts the guest TLS pointer.
- **Locations**: [core_emit_shared.c:481](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:481), [interp_a32.c:848](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:848).
- **Evidence & Root Cause**: Both CP15 reads return `ctx->tls_tp`; writing TPIDRURW overwrites that same field. Thus `MCR p15,0,r0,c13,c0,2` changes subsequent TPIDRURO reads and `__kuser_get_tls`. These are distinct architectural registers. [Arm register descriptions](https://documentation-service.arm.com/static/5e7b64757158f500bd5bd08e).
- **Remediation**: Maintain separate per-thread TPIDRURW and TPIDRURO state, including lifecycle handling.

### A32-R7-11 — BUG — HIGH

- **Summary**: Thumb ADD/SUB decodes the immediate-selector and subtraction bits backwards.
- **Locations**: [interp_thumb.c:80](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:80).
- **Evidence & Root Cause**: Bit 9 selects immediate operands and bit 10 selects subtraction in the implementation; the encoding assigns those roles oppositely. `0x1C88`, `ADDS r0,r1,#2`, executes `r1-r2`.
- **Remediation**: Decode bit 10 as the immediate selector and bit 9 as ADD/SUB selection.

### A32-R7-12 — BUG — HIGH

- **Summary**: Thumb instructions incorrectly update implicit flags inside IT blocks.
- **Locations**: [interp_thumb.c:93](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:93), [interp_thumb.c:138](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:138), [interp_thumb.c:221](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:221).
- **Evidence & Root Cause**: Several arithmetic, MOV, and logical paths update flags without checking `use_it`. With Z set, `ITT EQ; MOVEQ r0,#1; MOVEQ r1,#2` clears Z after the first MOV and skips the second. These encodings suppress their implicit flag writes inside IT.
- **Remediation**: Apply each encoding’s `setflags = !InITBlock()` rule while preserving explicit comparison flag updates.

### A32-R7-13 — BUG — HIGH

- **Summary**: Interpreter IT progression is incorrect across taken branches and undefined-instruction traps.
- **Locations**: [interp_thumb.c:581](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:581), [interp_thumb.c:799](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:799), [interp.c:214](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:214).
- **Evidence & Root Cause**: Successful T32 instructions advance IT only when the resulting PC equals `pc+4`. A taken branch in the final IT slot leaves stale predication at its target. Conversely, UNDEF advances IT while the outer stepper restores the faulting PC, making retry use the next slot’s condition.
- **Remediation**: Advance IT according to instruction completion, independently of branch destination; preserve pre-instruction IT for retryable traps.

### A32-R7-14 — BUG — HIGH

- **Summary**: Signal frames do not expose or restore architectural CPSR.IT.
- **Locations**: [signals.c:285](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:285), [signals.c:312](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:312), [signals.c:779](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:779).
- **Evidence & Root Cause**: IT exists separately in `ctx->itstate`, but `arm_cpsr` receives plain `ctx->cpsr`. Sigreturn ignores user-supplied IT bits and reconstructs predication from a private trailer and PC-distance heuristic. A handler cannot reliably inspect, clear, or replace the interrupted IT state through its architectural context.
- **Remediation**: Pack IT into CPSR when creating frames and restore it from validated `arm_cpsr`, following the architectural signal-context contract. [Linux ARM signal implementation](https://github.com/torvalds/linux/blob/master/arch/arm/kernel/signal.c).

### A32-R7-15 — BUG — HIGH

- **Summary**: A32 BLX immediate never enters Thumb and drops the H displacement bit.
- **Locations**: [interp_a32.c:318](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:318).
- **Evidence & Root Cause**: The target is always `pc+8+(imm24<<2)`, then passed to an interworking helper with bit 0 clear. `FA000000` remains in ARM instead of entering Thumb; `FB000000` also loses the additional two-byte displacement.
- **Remediation**: Include `H<<1` and explicitly select Thumb state for BLX immediate.

### A32-R7-16 — BUG — HIGH

- **Summary**: A32 LDR into PC loses interworking and address writeback.
- **Locations**: [interp_a32.c:813](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:813), [interp_a32.c:831](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:831).
- **Evidence & Root Cause**: The PC-load branch uses non-interworking semantics and returns before writeback. `LDR pc,[sp],#4` with an odd saved return address neither enters Thumb nor increments SP.
- **Remediation**: Complete permitted base writeback and apply architectural LoadWritePC interworking.

### A32-R7-17 — BUG — HIGH

- **Summary**: Thumb ALU writes to PC incorrectly switch into ARM state.
- **Locations**: [interp_thumb.c:261](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:261).
- **Evidence & Root Cause**: MOV/ADD into PC explicitly clear CPSR.T when the result is even. Thumb `MOV pc,r0` and `ADD pc,r0` use non-interworking branch semantics and must retain Thumb state. An even destination consequently executes the target under the wrong decoder.
- **Remediation**: Use Thumb BranchWritePC semantics without changing T.

### A32-R7-18 — BUG — MEDIUM

- **Summary**: Several interpreter paths use the wrong architectural PC value.
- **Locations**: [interp_thumb.c:239](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:239), [interp_vfp.c:306](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:306), [interp_a32.c:386](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:386), [interp_a32.c:826](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:826).
- **Evidence & Root Cause**: Thumb ALU PC reads incorrectly align `pc+4`; at `0x1002`, `MOV r0,pc` returns `0x1004` instead of `0x1006`. Thumb VLDR literals instead use ARM’s `pc+8`. A32 BX/STR with PC read raw `ctx->regs[15]`, omitting the architectural pipeline offset.
- **Remediation**: Centralize instruction-specific PC reads, distinguishing ALU, literal-address, branch-register, and stored-PC semantics.

### A32-R7-19 — BUG — MEDIUM

- **Summary**: A32 logical flag-setting instructions clear V.
- **Locations**: [interp_a32.c:252](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:252), [interp_a32.c:273](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:273).
- **Evidence & Root Cause**: Logical operations retain the initial `ov=false` and pass it to `i_set_nzcv`. With V initially set, `MOVS r0,#0` clears V, although logical instructions must preserve it while updating NZ and shifter carry.
- **Remediation**: Preserve existing V for logical operations and use arithmetic overflow only for arithmetic classes.

### A32-R7-20 — BUG — MEDIUM

- **Summary**: Interpreter MRS/MSR decoding mishandles register and field selection.
- **Locations**: [interp_a32.c:443](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:443), [interp_a32.c:451](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:451).
- **Evidence & Root Cause**: The MRS mask retains destination-register bits, recognizing only `r0`; `MRS r1,cpsr` falls through. MSR unconditionally replaces both NZCVQ and GE, so an NZCVQ-only write also changes GE.
- **Remediation**: Exclude Rd from MRS matching and update only the status fields selected by MSR.

### A32-R7-21 — BUG — MEDIUM

- **Summary**: Thumb LDM loads its base register from the wrong list position.
- **Locations**: [interp_thumb.c:441](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:441), [interp_thumb.c:451](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:451).
- **Evidence & Root Cause**: When Rn appears in the list, its normal load is skipped and replaced with a load from the final word. For `LDMIA r0,{r0,r1}`, memory words X,Y produce `r0=Y,r1=Y` rather than X,Y.
- **Remediation**: Retain the value from Rn’s actual list position and suppress writeback as required.

### A32-R7-22 — BUG — MEDIUM

- **Summary**: Interpreter BKPT can be skipped and reports the following instruction’s PC.
- **Locations**: [interp_thumb.c:48](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:48), [interp_a32.c:361](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:361), [interp.c:214](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:214).
- **Evidence & Root Cause**: Thumb IT condition checking gates BKPT, although BKPT is unconditional inside IT. Executed ARM and Thumb breakpoints advance PC before returning, and the outer stepper does not restore it for BKPT. Debuggers and SIGTRAP handlers consequently receive the wrong PC. [Arm BKPT specification](https://support.arm.com/documentation/ddi0597/2021-09/Base-Instructions/BKPT--Breakpoint-?lang=en).
- **Remediation**: Handle BKPT outside IT condition suppression and retain its instruction PC and trap-appropriate IT state.

### A32-R7-23 — BUG — MEDIUM

- **Summary**: Thumb NOP raises an undefined-instruction trap.
- **Locations**: [interp_thumb.c:70](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:70).
- **Evidence & Root Cause**: The explicit UNDEF branch includes `hw == 0xBF00`, the ordinary Thumb NOP encoding. Executing compiler padding or an intentional NOP under `--interp` therefore raises SIGILL.
- **Remediation**: Decode NOP as successful completion and advance IT normally.

### A32-R7-24 — BUG — HIGH

- **Summary**: Native NEON floating-point operations inherit scalar VFP controls.
- **Locations**: [interp_neon_alu.c:396](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_neon_alu.c:396), [interp_neon_mem.c:616](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_neon_mem.c:616), [trampoline.S:64](/Users/angerman/Projects/zw3rk/a32rt/src/trampoline.S:64).
- **Evidence & Root Cause**: Guest FPSCR controls populate host FPCR, and NEON lowering uses that unchanged environment. ARMv7 NEON requires standard round-to-nearest, flush-to-zero, and default-NaN behavior. With scalar rounding upward, NEON `1.0 + 2^-24` rounds upward instead of ties-to-even. [Arm FPU control rules](https://documentation-service.arm.com/static/5e8e11a2fd977155116a2d1a).
- **Remediation**: Apply standard NEON FP controls around affected operations, restoring scalar controls afterward.

### A32-R7-25 — BUG — MEDIUM

- **Summary**: Interpreter scalar FP arithmetic ignores FPSCR.FZ and FPSCR.DN.
- **Locations**: [interp_vfp.c:26](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:26), [interp_vfp.c:591](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:591).
- **Evidence & Root Cause**: The host FP wrapper sets rounding only. Operand/result processing never applies FZ or DN, and exception accumulation omits IDC. With FZ set, multiplying the smallest normal float by 0.5 can produce a subnormal instead of zero; DN leaves NaN payload behavior to the host. [Arm FPU control rules](https://documentation-service.arm.com/static/5e8e11a2fd977155116a2d1a).
- **Remediation**: Implement the full guest FP environment, including denormal processing, default NaNs, and cumulative exceptions.

### A32-R7-26 — BUG — MEDIUM

- **Summary**: Valid NEON modified-immediate instructions silently zero destinations.
- **Locations**: [interp_vfp.c:670](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:670).
- **Evidence & Root Cause**: The decoder accepts the whole family but constructs values only for selected cmodes. Remaining cases store initialized `val64=0` and report success. `VMOV.I16 d0,#1` produces zero rather than `0x0001000100010001`; VORR/VBIC immediates also lose their destination-merging behavior.
- **Remediation**: Implement each accepted cmode and its operation, or reject unsupported encodings before mutating state.

### A32-R7-27 — BUG — MEDIUM

- **Summary**: VFP/NEON halfword lane moves execute as word moves.
- **Locations**: [interp_vfp.c:180](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:180), [interp_vfp.c:212](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:212), [interp_vfp.c:238](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:238).
- **Evidence & Root Cause**: The decoder discards `opc2` and always extracts or replaces 32 bits in accepted CP11 transfers. With D0=`0x5566778811223344`, `VMOV.U16 r0,d0[1]` returns `0x11223344` instead of `0x1122`. The reverse transfer overwrites an entire word.
- **Remediation**: Decode element width, lane index, and signedness from both opcode fields.

### A32-R7-28 — BUG — MEDIUM

- **Summary**: `VREV64.16` reverses bytes within halfwords.
- **Locations**: [interp_vfp.c:701](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:701).
- **Evidence & Root Cause**: The halfword case reverses element positions and applies `bswap16` to every element. Input `0x1122334455667788` becomes `0x8877665544332211` instead of `0x7788556633441122`. The matching mask also fixes Q to zero, making the purported Q-register handling unreachable.
- **Remediation**: Reverse halfword positions without changing their byte order; correct Q matching and validate register pairing.

### A32-R7-29 — BUG — MEDIUM

- **Summary**: Interpreter fused and non-fused multiply-accumulate instructions share identical semantics.
- **Locations**: [interp_vfp.c:605](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:605), [interp_vfp.c:622](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:622).
- **Evidence & Root Cause**: VMLA and VFMA use the same C expression. For single-precision operands `a=1+2^-23`, `b=1-2^-23`, and accumulator `-1`, separately rounded VMLA yields zero while VFMA yields `-2^-46`. Compiler contraction cannot make one expression correctly implement both.
- **Remediation**: Use explicit fused operations for fused encodings and enforce separate rounding for non-fused encodings.

### A32-R7-30 — BUG — MEDIUM

- **Summary**: Interpreter VCMP fails to record invalid operation for signaling NaNs.
- **Locations**: [interp_vfp.c:467](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:467).
- **Evidence & Root Cause**: The NaN path sets IOC only for VCMPE. Ordinary VCMP with S0=`0x7f800001` and S1=0 leaves IOC clear, although the operand is a signaling NaN. This path also bypasses host-exception collection.
- **Remediation**: Classify NaNs from their bits and set IOC for signaling NaNs in both instructions, and all NaNs in VCMPE.

### A32-R7-31 — BUG — MEDIUM

- **Summary**: Native 16-bit float-to-fixed conversion saturates without setting IOC.
- **Locations**: [interp_vfp_core.c:411](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp_core.c:411).
- **Evidence & Root Cause**: Lowering converts to a 32-bit integer, then clamps to 16 bits using integer comparisons. `VCVT.S16.F32 s0,s0,#1` with input 16384.0 converts to 32768 and clamps to 32767 without generating a host invalid exception or explicitly setting guest IOC.
- **Remediation**: Detect overflow against the actual destination width and accumulate the required conversion exceptions.

### A32-R7-32 — DEFECT — MEDIUM

- **Summary**: Valid guest arithmetic and backward branches invoke C undefined behavior.
- **Locations**: [interp_a32.c:210](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:210), [interp_a32.c:795](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:795), [interp_a32_ctl.c:598](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_ctl.c:598), [interp_t16.c:461](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_t16.c:461).
- **Evidence & Root Cause**: SMLAL adds its accumulator using signed `int64_t`, overflowing for `INT64_MAX + 1`. Post-index subtraction can negate `INT32_MIN`. Branch translation left-shifts negative signed displacements. These are valid modular guest operations but undefined C operations.
- **Remediation**: Perform wrapping arithmetic and displacement shifts in unsigned types, using signed values only where their range is proven safe.
