Static audit completed across all interpreter files and related decoder, CPU-state, SIMD, atomic, and trap paths. No builds, tests, or edits were performed. Examples below are deductions from the code, not executed reproducers.

### I686-R7-1 — BUG — HIGH

- **Summary**: Subpage recovery can read beyond the guest permissions it validated.
- **Locations**: [signals_subpage.c:330](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_subpage.c:330), [signals_subpage.c:795](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_subpage.c:795).
- **Evidence & Root Cause**: The classifier treats most F3 operands as four bytes and F2 operands as eight. Packed instructions including `CVTTPS2DQ`, `PSHUFHW`, and `PSHUFLW` read sixteen bytes. Recovery validates the smaller span, opens the enclosing host-page cover, then executes the full interpreter access. An operand near a guest subpage boundary can therefore read a neighboring protected subpage.
- **Remediation**: Derive access width and direction from the exact opcode/prefix form. Validate the complete operand before opening host-page covers.

### I686-R7-2 — BUG — HIGH

- **Summary**: LES/LDS/LSS/LFS/LGS read zero bytes and load zero values.
- **Locations**: [h_seg.c:92](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:92), [h_seg.c:318](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:318).
- **Evidence & Root Cause**: `mem_load()` expects a width in bits and calculates `n = width / 8`. `h_seg_lxs()` passes `bytes`—two or four—for the offset and `2u` for the selector. Every call consequently executes zero loop iterations and returns zero. The destination becomes zero and the segment loader receives a null selector, regardless of operand contents.
- **Remediation**: Pass bit widths consistently, or change the helper to an explicitly byte-counted interface. Reject register-only encodings before computing a memory address.

### I686-R7-3 — DEFECT — HIGH

- **Summary**: Immediate 32-bit far CALL/JMP cannot represent their targets and invoke undefined shifts.
- **Locations**: [decode.c:366](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:366), [decode.h:62](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.h:62), [h_seg.c:212](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:212).
- **Evidence & Root Cause**: A 16:32 far pointer is packed into the 32-bit `insn->imm`. Encoding the selector shifts a `uint32_t` left by 32; extraction shifts it right by 32. Both are undefined C operations, and the field cannot retain all 48 target bits.
- **Remediation**: Represent the offset and selector separately, or use a sufficiently wide immediate representation with bounded shifts.

### I686-R7-4 — BUG — HIGH

- **Summary**: Several ModR/M forms select DS where SS is required.
- **Locations**: [decode.c:106](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:106), [h_sse_internal.h:133](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:133).
- **Evidence & Root Cause**: Default-segment selection requires `modrm_mod != 0` before selecting SS. However, `[ESP]` through SIB and 16-bit `[BP+SI]`/`[BP+DI]` use SS with `mod=00`. When DS and SS differ, these instructions access the wrong segment and potentially the wrong memory.
- **Remediation**: Select the default segment from the decoded base register. The decoder already represents displacement-only forms with no base.

### I686-R7-5 — BUG — HIGH

- **Summary**: SIMD interpreter and common DBT addressing omit 16-bit effective-address wrapping.
- **Locations**: [h_sse_internal.h:120](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:120), [emit_exit.c:117](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:117).
- **Evidence & Root Cause**: Both implementations add complete 32-bit registers without masking the completed offset to sixteen bits. For example, `67 MOV EAX,[BX]` under DBT with `EBX=0x12345678` accesses offset `0x12345678` instead of `0x5678`. SIMD interpreter accesses have the same defect.
- **Remediation**: Apply address-size wrapping before segment-base addition. Reuse the shared EA semantics or decline unsupported DBT forms.

### I686-R7-6 — BUG — MEDIUM

- **Summary**: SIMD mandatory-prefix decoding changes incorrectly with CS.D.
- **Locations**: [decode.c:509](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:509), [h_sse.c:562](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:562), [h_sse_int.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:383).
- **Evidence & Root Cause**: The decoder converts `pfx_opsize` into an effective scalar operand-size flag by XORing it with the code-segment default. SIMD handlers also use that field to identify mandatory `66`. In a D=0 segment, unprefixed ADDPS becomes ADDPD, and unprefixed MMX MOVQ becomes an XMM move.
- **Remediation**: Preserve raw mandatory-prefix identity separately from effective scalar operand size.

### I686-R7-7 — BUG — MEDIUM

- **Summary**: Illegal LOCK prefixes execute instead of raising #UD.
- **Locations**: [interp.c:305](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:305), [interp.c:432](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:432), [decode.c:635](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:635).
- **Evidence & Root Cause**: Central validation rejects only single shifts and rotates. It does not enforce the opcode tables’ lockability information or require a memory destination. Consequently, forms such as `LOCK MOV`, `LOCK ADD EAX,1`, `LOCK BT`, and `LOCK SHLD` reach ordinary handlers.
- **Remediation**: Validate LOCK legality centrally against the resolved opcode and operand form before any instruction side effect.

### I686-R7-8 — BUG — HIGH

- **Summary**: Null and nonexistent selectors become usable segments.
- **Locations**: [seg.c:124](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:124), [seg.c:174](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:174), [seg.c:202](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:202), [seg.c:318](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:318).
- **Evidence & Root Cause**: Selector zero bypasses load validation even for CS/SS. Null data selectors subsequently bypass access checks because they are GDT selectors. Other unrecognized GDT indices are synthesized as flat data descriptors. This suppresses required selector faults and turns invalid selectors into unrestricted flat addressing. Null SS loads and null data-segment accesses must fault. [Intel instruction reference](https://cdrdv2-public.intel.com/868140/253666-089-sdm-vol-2a.pdf).
- **Remediation**: Recognize all null selectors, reject null CS/SS, track unusable data segments, and reject nonexistent GDT entries.

### I686-R7-9 — BUG — HIGH

- **Summary**: Segment protection is bypassed by multiple memory paths and DBT eligibility.
- **Locations**: [seg.c:308](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:308), [h_bit.c:78](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_bit.c:78), [h_sse_internal.h:146](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:146), [engine.c:642](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:642).
- **Evidence & Root Cause**: Strings, bit operations, x87/SIMD accesses, and several direct-memory helpers bypass segment-limit validation. The shared check also lacks read/write intent, so it cannot prohibit writes through read-only descriptors. Instruction fetch does not enforce CS limits. DBT eligibility checks only CS, allowing limited or nonflat data segments to execute through unchecked emitted accesses.
- **Remediation**: Centralize segment validation with access kind and full width. Gate DBT on every segment assumption until equivalent checks exist.

### I686-R7-10 — BUG — HIGH

- **Summary**: Expand-down segment limits are interpreted as expand-up limits.
- **Locations**: [seg.c:325](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:325).
- **Evidence & Root Cause**: The expand-down branch requires `(d.type & 0x18u) == 0`, but installed data descriptors include bit `0x10`. Types `0x14`/`0x16` therefore never enter it. Valid offsets above the limit fault, while invalid offsets below it can pass. The unreachable branch also incorrectly allows the limit itself and omits the upper bound and operand extent.
- **Remediation**: Correct type classification and validate the complete access against `(limit, upper_bound]`, with the upper bound derived from B.

### I686-R7-11 — BUG — HIGH

- **Summary**: Stack operations ignore SS.B; PUSHF/POPF also ignore SS.base.
- **Locations**: [h_mov.c:360](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_mov.c:360), [h_branch.c:85](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_branch.c:85), [h_flagsops.c:110](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_flagsops.c:110), [emit_mov.c:531](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_mov.c:531).
- **Evidence & Root Cause**: Push/pop/call/return helpers always calculate with full ESP. A sixteen-bit stack therefore uses ESP’s upper half instead of wrapping SP. PUSHF/POPF directly address `guest_ptr(sp)`, omitting SS.base entirely. DBT stack accesses likewise use raw ESP while nonflat SS remains eligible.
- **Remediation**: Separate stack-address size from operand size and use shared SS-aware, limit-checked stack helpers.

### I686-R7-12 — BUG — MEDIUM

- **Summary**: Operand-size-overridden ENTER/LEAVE corrupt frame addressing.
- **Locations**: [h_mov.c:477](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_mov.c:477).
- **Evidence & Root Cause**: `66 ENTER` replaces full EBP rather than BP and traverses nested frames using full-width EBP arithmetic. `66 LEAVE` combines old ESP’s upper half with BP, although a 32-bit stack requires `ESP=EBP` before popping BP. With ESP=`0x20001000` and EBP=`0x10002000`, it reads `0x20002000` instead of `0x10002000`.
- **Remediation**: Implement the independent operand-size and stack-address-size rules, preserving upper register halves where required.

### I686-R7-13 — BUG — HIGH

- **Summary**: Faulting segment pops and far transfers expose partially committed state.
- **Locations**: [h_seg.c:172](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:172), [h_seg.c:220](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:220), [h_seg.c:267](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:267).
- **Evidence & Root Cause**: POP segment, RETF, and IRET increment ESP before validating the selector. Their synthetic fault returns do not pass through the host-fault ESP rollback. Far CALL commits the new CS/base/default size before faultable stack stores; host recovery does not restore that segment state. Retrying therefore starts with an altered stack or code segment.
- **Remediation**: Validate and stage the complete transfer before committing architectural registers. Preserve the original state on every fault path.

### I686-R7-14 — BUG — MEDIUM

- **Summary**: `modify_ldt` readback generates malformed descriptors.
- **Locations**: [ldt.c:212](/Users/angerman/Projects/zw3rk/i686rt/src/os/ldt.c:212).
- **Evidence & Root Cause**: Raw descriptor encoding drops the S bit using `d->type & 0x0f`. The granularity flag is represented as `0x8000` and then truncated into an eight-bit field, losing G. Page-granular byte limits are also emitted without converting back to their encoded twenty-bit limit.
- **Remediation**: Encode the architectural descriptor fields explicitly, including S, G, and the inverse granularity conversion.

### I686-R7-15 — BUG — HIGH

- **Summary**: Fault recovery preserves flags from instructions that did not complete.
- **Locations**: [h_alu.c:408](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:408), [emit_alu.c:643](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:643), [h_string.c:186](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_string.c:186), [interp.c:497](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:497).
- **Evidence & Root Cause**: Interpreter ALU operations and DBT immediate shifts publish flags before faultable stores. Recovery restores only selected registers. `STC; ADC [read_only_zero],0` can thus fault with CF already cleared; retrying loses the carry. Repeated comparisons also retain intermediate flags when a later iteration faults, rather than restoring their initial EFLAGS.
- **Remediation**: Commit flags after successful writes. Preserve the complete initial flag state for faulting repeated comparisons while retaining completed index/count progress.

### I686-R7-16 — BUG — HIGH

- **Summary**: LODSB/LODSW overwrite all of EAX.
- **Locations**: [h_string.c:241](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_string.c:241), [decode.c:82](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:82).
- **Evidence & Root Cause**: `lods_core()` passes byte counts one or two to `x86_reg_write()`, which expects bit widths eight or sixteen. Both take its full-register assignment path. EAX=`0x12345678` followed by LODSB of `0xAB` becomes `0x000000AB`.
- **Remediation**: Pass `w * 8U` and make width units explicit throughout the string helpers.

### I686-R7-17 — BUG — HIGH

- **Summary**: Failed CMPXCHG comparisons bypass destination write protection.
- **Locations**: [h_alu.c:746](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:746), [interp.c:769](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:769).
- **Evidence & Root Cause**: On mismatch, CMPXCHG performs only a load before updating the accumulator and flags. Unaligned CMPXCHG8B has the same omission. A mismatching operation against read-only memory therefore succeeds instead of faulting. The architectural destination write cycle occurs for either comparison outcome. [Intel CMPXCHG reference](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/itanium-architecture-vol-4-manual.pdf).
- **Remediation**: Enforce writable destination semantics on both outcomes, retaining LOCK atomicity and committing registers only after the memory operation succeeds.

### I686-R7-18 — BUG — MEDIUM

- **Summary**: XADD with identical register operands loses its sum.
- **Locations**: [h_alu.c:809](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:809).
- **Evidence & Root Cause**: The handler writes the destination sum, then overwrites the source with the old destination. When both operands name the same register, the second assignment destroys the result. `XADD EAX,EAX` with EAX=3 leaves 3 rather than 6.
- **Remediation**: Handle register aliasing explicitly or order register assignments so the final destination receives the sum.

### I686-R7-19 — BUG — HIGH

- **Summary**: Signal delivery and sigreturn corrupt lazy EFLAGS.
- **Locations**: [signals_i386.c:217](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:217), [signals_i386.c:419](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:419).
- **Evidence & Root Cause**: Signal-frame construction copies `ctx->eflags` without materializing pending arithmetic flags. Sigreturn restores explicit EFLAGS without clearing the handler’s lazy descriptor. The frame can contain stale flags, and the next flag consumer can overwrite restored flags with the handler’s last arithmetic result.
- **Remediation**: Materialize before saving and clear lazy state when restoring explicit architectural flags.

### I686-R7-20 — BUG — HIGH

- **Summary**: Successful sigreturn replaces restored EAX with zero.
- **Locations**: [signals_i386.c:417](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:417), [signals_i386.c:705](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:705), [syscalls.c:803](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:803).
- **Evidence & Root Cause**: Sigreturn restores `sc.eax`, but its syscall adapter returns zero. The common syscall completion path then unconditionally assigns that return value to EAX. An interrupted nonzero EAX never survives a successful signal return.
- **Remediation**: Distinguish syscalls that restore the complete register state from ordinary syscall-return assignment.

### I686-R7-21 — BUG — HIGH

- **Summary**: Sigreturn restores the x87 status word without restoring TOP.
- **Locations**: [signals_i386.c:443](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:443), [x87.c:95](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:95).
- **Evidence & Root Cause**: FP restoration copies `fstat`, tags, and register contents, but never updates `ctx->x87_top`. Stack-relative accesses use that separate field. A handler that changes TOP therefore leaves subsequent ST(i) references mapped to the wrong restored physical registers.
- **Remediation**: Restore TOP from the saved status word and keep both representations synchronized.

### I686-R7-22 — BUG — HIGH

- **Summary**: Several synchronous faults bypass guest signal handlers.
- **Locations**: [interp.c:583](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:583), [engine.c:694](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:694), [engine.c:730](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:730).
- **Evidence & Root Cause**: Interpreter decode failures and missing handlers return directly. DBT’s direct TRAP case also returns without delivery, while its interpreter fallback delivers FAULT/TRAP but excludes UNDEF. Consequently, DBT INT3 and UD2 can terminate execution despite installed SIGTRAP/SIGILL handlers.
- **Remediation**: Route all architectural synchronous exits through one delivery path, preserving fault versus trap EIP semantics.

### I686-R7-23 — BUG — MEDIUM

- **Summary**: Privileged-instruction behavior incorrectly depends on whether CS is flat.
- **Locations**: [h_seg.c:386](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:386).
- **Evidence & Root Cause**: CLI/STI raise a protection fault only for nonflat CS. Under ordinary flat user-mode execution they directly modify IF. HLT advances EIP and returns a diagnostic halt. The runtime models CPL=3, so these paths suppress the required privilege faults for normal user processes.
- **Remediation**: Apply CPL/IOPL privilege rules independently of segment flatness and deliver the appropriate synchronous fault.

### I686-R7-24 — BUG — HIGH

- **Summary**: Exact-mode single-precision stores discard negative signs.
- **Locations**: [x87_80_conv.c:582](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:582), [x87_80_conv.c:645](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:645).
- **Evidence & Root Cause**: The shared IEEE conversion helper always places the sign in bit 63. Its float32 caller truncates the result to `uint32_t`, discarding that sign. In `--x87-80`, storing finite −1 through `FSTP m32` produces +1. Negative finite overflow/underflow results also lose their signs.
- **Remediation**: Parameterize the destination sign position or construct the float32 sign before narrowing.

### I686-R7-25 — DEFECT — HIGH

- **Summary**: Exact x87 rounding invokes undefined shifts and loses significand carry.
- **Locations**: [x87_80_internal.h:416](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_internal.h:416), [x87_80_internal.h:490](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_internal.h:490).
- **Evidence & Root Cause**: Default precision allows `eff==64`, making `1ULL << eff` undefined. Separately, rounding increments a 64-bit significand before carry detection; `UINT64_MAX+1` wraps to zero. A value rounding upward across a power-of-two boundary therefore loses the carry needed for normalization.
- **Remediation**: Return an explicit carry from significand rounding and handle full-width precision without shifting by 64.

### I686-R7-26 — DEFECT — HIGH

- **Summary**: x87 integer stores contain undefined fractional conversions and omit exception status.
- **Locations**: [x87.c:403](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:403), [h_x87_internal.h:428](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:428).
- **Evidence & Root Cause**: For exact-mode 0.5, `drop=63-eff` becomes 64; both mask construction and right shifting are undefined. Smaller fractions produce larger shift counts. The store API also returns only an integer: overflow to a narrow destination and inexact conversion never set IE/PE. For example, FIST of 32768 to m16 writes the indefinite integer without IE.
- **Remediation**: Handle subunit magnitudes before shifting and return conversion status alongside the value, including destination-width overflow.

### I686-R7-27 — BUG — HIGH

- **Summary**: FCMOV instructions execute comparisons, sometimes popping the x87 stack.
- **Locations**: [insn_tab_groups.h:142](/Users/angerman/Projects/zw3rk/i686rt/src/x86/insn_tab_groups.h:142), [h_x87_arith.c:277](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_arith.c:277).
- **Evidence & Root Cause**: DA register forms `/0`, `/1`, and `/2` map to FCOM, FUCOM, and FCOMP handlers. Those encodings are FCMOVB, FCMOVE, and FCMOVBE. `DA D1`, for example, compares and pops instead of conditionally copying ST(1) according to EFLAGS. [Intel FCMOVcc reference](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf).
- **Remediation**: Decode and execute the actual conditional moves without comparison or stack-pop side effects.

### I686-R7-28 — BUG — HIGH

- **Summary**: FXSAVE/FXRSTOR corrupt x87 stack occupancy.
- **Locations**: [h_x87_math.c:386](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:386), [h_x87_math.c:419](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:419), [x87.c:338](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:338).
- **Evidence & Root Cause**: FXSAVE writes abridged tag bits with reversed polarity: one means empty in this implementation. FXRSTOR reverses them similarly, then calls setters that classify every restored slot and overwrite the restored empty tags. Even an internal save/restore of an empty stack makes its slots nonempty.
- **Remediation**: Correct tag polarity, restore raw register contents, and reconstruct tags while preserving empty slots.

### I686-R7-29 — BUG — HIGH

- **Summary**: Legacy x87 environment/state images have incorrect layouts and sizes.
- **Locations**: [h_x87_math.c:352](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:352), [h_x87_math.c:431](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:431).
- **Evidence & Root Cause**: FNSAVE writes status at offset 2 and an abridged tag at offset 4 instead of the legacy environment’s status at 4 and full tag at 8. Other fields and register ordering are also incompatible. Callers omit operand size: `66 FNSTENV` writes 28 rather than 14 bytes; `66 FNSAVE` writes 108 rather than 94. FNSTENV additionally fails to mask exceptions after saving.
- **Remediation**: Implement explicit operand-size-dependent legacy formats, correct tag/register ordering, and the required post-save control-word update.

### I686-R7-30 — BUG — HIGH

- **Summary**: Unmasked floating-point exceptions do not produce architectural guest traps.
- **Locations**: [h_sse.c:153](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:153), [x87.c:571](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:571), [h_branch.c:329](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_branch.c:329).
- **Evidence & Root Cause**: SSE helpers set MXCSR status and commit results without testing exception masks. x87 sets ES/B but continues result/stack updates, and WAIT is a no-op. Unmasking divide-by-zero therefore does not cause the required fault and completion suppression.
- **Remediation**: Integrate exception masks into instruction completion. Implement SIMD fault delivery and x87 pending-exception checks, including inhibited stores/pops.

### I686-R7-31 — BUG — HIGH

- **Summary**: x87 stack underflow and overflow silently read or overwrite register storage.
- **Locations**: [x87.c:78](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:78), [x87.c:290](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:290).
- **Evidence & Root Cause**: Push decrements TOP without checking the destination tag. Operand reads return values without checking emptiness. Nine FLD1 instructions overwrite a full stack; arithmetic after FNINIT consumes empty-slot storage without the required IE/SF handling or masked indefinite result.
- **Remediation**: Validate stack operands and push destinations before changing state, implementing masked and unmasked stack-fault rules.

### I686-R7-32 — DEFECT — HIGH

- **Summary**: Exact x87 rounding modes race between guest threads and can remain stale within one thread.
- **Locations**: [x87_80.c:10](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:10), [h_x87_internal.h:285](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:285), [h_x87_math.c:213](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:213).
- **Evidence & Root Cause**: Softfloat RC/PC reside in mutable process globals. Concurrent guest threads overwrite each other’s arithmetic environment, creating C data races and wrong rounding. Some handlers, including exact FSIN/FCOS/FSCALE, do not refresh that environment after FLDCW.
- **Remediation**: Pass an explicit per-context arithmetic environment through every operation; remove shared mutable mode state.

### I686-R7-33 — BUG — MEDIUM

- **Summary**: Exact FRNDINT corrupts large integers and rounds some fractions incorrectly.
- **Locations**: [h_x87_math.c:306](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:306), [x87_80_conv.c:451](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:451).
- **Evidence & Root Cause**: FRNDINT converts through signed int64, so an already integral `2^64` becomes the integer-indefinite value. Its converter also rounds every nearest-even value with exponent below zero to zero; 0.75 therefore becomes zero instead of one.
- **Remediation**: Round the extended significand directly, preserving already integral large values and correctly distinguishing half-way cases.

### I686-R7-34 — BUG — MEDIUM

- **Summary**: MOVSS/MOVSD memory loads retain stale upper XMM lanes.
- **Locations**: [h_sse.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:383).
- **Evidence & Root Cause**: The handler copies the old destination and overwrites only four or eight bytes. Legacy scalar memory loads must clear the remaining XMM bits; preservation applies to register-source forms. A previous all-ones destination therefore leaves unwanted upper lanes after a scalar load. [Intel MOVSS reference](https://cdrdv2-public.intel.com/835752/253667-sdm-vol-2b.pdf).
- **Remediation**: Zero the destination buffer for scalar memory loads before copying the source.

### I686-R7-35 — BUG — MEDIUM

- **Summary**: Packed quadword shifts wrap oversized counts.
- **Locations**: [h_sse_int.c:500](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:500), [h_sse_int.c:528](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:528).
- **Evidence & Root Cause**: PSRLQ/PSLLQ use `imm & 63`. A count of 64 leaves the operand unchanged and 65 shifts by one. Both MMX and XMM forms must produce zero lanes for counts above 63.
- **Remediation**: Check the full immediate before shifting and zero oversized results.

### I686-R7-36 — BUG — MEDIUM

- **Summary**: Floating comparison handlers misclassify quiet-NaN exceptions.
- **Locations**: [h_sse_int.c:34](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:34), [h_x87_arith.c:534](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_arith.c:534).
- **Evidence & Root Cause**: SSE compares use `pred<=2` as the signaling set. Equality predicate 0 is quiet, while predicates 5/6 should signal on quiet NaNs. Separately, FUCOMI/FUCOMIP share a helper that sets IE for every unordered result, incorrectly signaling on quiet NaNs.
- **Remediation**: Preserve comparison identity and encode quiet/signaling rules explicitly, with independent signaling-NaN handling.

### I686-R7-37 — BUG — MEDIUM

- **Summary**: FXRSTOR clears supported DAZ state and accepts reserved MXCSR bits.
- **Locations**: [h_x87_math.c:408](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:408).
- **Evidence & Root Cause**: MXCSR restoration uses `& 0xffbf`, silently clearing DAZ bit 6 and discarding reserved bits. This conflicts with the runtime’s supported DAZ handling and LDMXCSR validation. A save/restore changes subsequent denormal behavior; an invalid image succeeds instead of faulting.
- **Remediation**: Validate against the supported MXCSR mask before changing any state, then restore all supported bits.

### I686-R7-38 — BUG — MEDIUM

- **Summary**: Trigonometric range handling corrupts C2 and stack behavior.
- **Locations**: [x87_80_trig.c:323](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:323), [x87_80_trig.c:411](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:411), [h_x87_math.c:213](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:213).
- **Evidence & Root Cause**: Exact helpers leave the range-result boolean false for finite magnitudes at least `2^63`, returning IE instead. Callers consequently clear C2 or perform FSINCOS/FPTAN pushes despite range failure. Default-mode successful paths also fail to clear previously set C2.
- **Remediation**: Return an explicit range outcome, preserve operands/TOP on range failure, and set or clear C2 on every completion.

### I686-R7-39 — BUG — MEDIUM

- **Summary**: Default x87 directed rounding selects the wrong neighboring value.
- **Locations**: [h_x87_internal.h:238](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:238), [h_x87_internal.h:349](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:349).
- **Evidence & Root Cause**: Division passes the residual `a-s*b` as the quotient-error direction without accounting for a negative divisor. Single-precision RC=3 stores step toward the exact value even when the nearest result is already on the toward-zero side: `1+2^-25` becomes `1+2^-23` instead of 1.
- **Remediation**: Correct residual direction using divisor sign; adjust toward-zero conversions only when the rounded magnitude exceeds the exact magnitude.

### I686-R7-40 — BUG — MEDIUM

- **Summary**: Exporting binary64 subnormals to extended precision doubles their values.
- **Locations**: [x87.c:190](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:190).
- **Evidence & Root Cause**: Subnormal normalization starts at exponent −1022 while normalizing toward fraction bit 51. It needs −1023. The smallest binary64 subnormal is emitted with exponent −1073 rather than −1074, affecting m80 stores and saved state.
- **Remediation**: Correct the normalization exponent and preserve exact binary64-to-extended conversion.

### I686-R7-41 — BUG — MEDIUM

- **Summary**: MMX operations do not establish their architectural x87 alias state.
- **Locations**: [h_sse_internal.h:192](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:192), [x87.c:355](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:355).
- **Evidence & Root Cause**: MMX helpers only copy the low 64 bits. They do not mark the x87 tags valid or set the written physical register’s upper sixteen bits appropriately. After FNINIT and MOVD to MM0, the runtime still reports an empty x87 stack.
- **Remediation**: Centralize MMX state transitions and maintain the architectural tag and register-alias representation.

### I686-R7-42 — BUG — MEDIUM

- **Summary**: Exact FPREM1 incorrectly returns the dividend for some nonzero nearest quotients.
- **Locations**: [x87_80.c:395](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:395).
- **Evidence & Root Cause**: Shared remainder code returns immediately whenever the dividend exponent is smaller than the divisor exponent. That shortcut works for truncating FPREM but not FPREM1. With dividend 0.75 and divisor 1, FPREM1 should select quotient 1 and remainder −0.25; this returns +0.75.
- **Remediation**: Handle nearest-even quotient selection for exponent difference −1 before taking the shortcut.

### I686-R7-43 — BUG — MEDIUM

- **Summary**: Aligned SIMD and FP-state instructions omit required alignment faults.
- **Locations**: [h_sse.c:414](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:414), [h_sse_int.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:383), [h_x87.c:327](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87.c:327), [emit_sse2.c:404](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:404).
- **Evidence & Root Cause**: MOVAPS/MOVAPD/MOVDQA and FXSAVE/FXRSTOR use ordinary memory accesses without their required alignment checks. Corresponding DBT moves have the same omission. Mapped but misaligned operands therefore succeed rather than raising #GP.
- **Remediation**: Check instruction-specific alignment before any memory or architectural-state side effect.

### I686-R7-44 — BUG — MEDIUM

- **Summary**: Default x87 arithmetic sets incorrect exception flags for invalid operands.
- **Locations**: [h_x87_internal.h:187](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:187), [h_x87_internal.h:243](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:243).
- **Evidence & Root Cause**: `d_exc()` raises IE when a NaN result originated from a NaN operand, but omits IE for invalid non-NaN combinations such as `0*∞` or `+∞+-∞`. Division sets ZE for `0/0`, and IE/ZE for `∞/0`, misclassifying both cases.
- **Remediation**: Classify operands and exceptional operations explicitly before host arithmetic, distinguishing quiet/signaling NaNs and invalid/divide-by-zero cases.

### I686-R7-45 — DEFECT — MEDIUM

- **Summary**: FSCALE and FXTRACT can invoke undefined host integer operations.
- **Locations**: [h_x87_math.c:711](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:711), [h_x87_math.c:736](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:736).
- **Evidence & Root Cause**: Default FSCALE casts arbitrary `trunc(b)` to `int`; NaN, infinity, and out-of-range finite values are not checked. FXTRACT negates `ilogb(a)` without handling zero or special values; on implementations returning INT_MIN for zero, that negation overflows.
- **Remediation**: Handle special values and architectural exponent ranges before host integer conversion or negation.

### I686-R7-46 — BUG — MEDIUM

- **Summary**: Exact FPATAN selects the wrong quadrant for positive infinite X.
- **Locations**: [x87_80_trig.c:464](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:464).
- **Evidence & Root Cause**: When both operands are infinite, the implementation always selects magnitude `3π/4`, ignoring X’s sign. `atan2(+∞,+∞)` therefore returns approximately `3π/4` instead of `π/4`.
- **Remediation**: Select `π/4` versus `3π/4` using X’s sign, then apply Y’s sign.

### I686-R7-47 — BUG — MEDIUM

- **Summary**: DBT unsigned MUL uses signed overflow rules.
- **Locations**: [emit_alu_ext2.c:174](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu_ext2.c:174).
- **Evidence & Root Cause**: MUL and IMUL choose different widening multiplies but share a comparison against sign-extension of the low product half. Unsigned `0x80000000 * 1` consequently sets CF/OF despite EDX being zero. The sixteen-bit form has the same error.
- **Remediation**: For unsigned MUL, derive CF/OF from whether the upper half is nonzero.

### I686-R7-48 — BUG — HIGH

- **Summary**: DBT MMX logical instructions modify XMM registers and overread memory.
- **Locations**: [emit_sse.c:480](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:480), [emit_sse.c:777](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:777).
- **Evidence & Root Cause**: Unprefixed PAND/PANDN/POR/PXOR reach an emitter that always operates on 128-bit XMM slots. `PXOR MM0,MM0` clears XMM0 and leaves MM0 unchanged. Memory forms load sixteen bytes for an eight-byte operand, potentially faulting beyond valid memory.
- **Remediation**: Distinguish MMX from mandatory-66 XMM forms and implement the correct register bank/access width or fall back.

### I686-R7-49 — BUG — MEDIUM

- **Summary**: DBT PUNPCKHDQ interleaves the wrong lanes.
- **Locations**: [emit_sse.c:313](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:313).
- **Evidence & Root Cause**: The emitter constructs `{d1,s1,d3,s3}` instead of `{d2,s2,d3,s3}`. Destination `[10,11,12,13]` and source `[20,21,22,23]` produce `[11,21,13,23]`.
- **Remediation**: Select lane 2 for the first pair or emit the corresponding ZIP2 operation.

### I686-R7-50 — BUG — MEDIUM

- **Summary**: DBT byte shifts reverse direction and encode incorrect counts.
- **Locations**: [emit_sse2.c:505](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:505), [emit_sse_shared.h:564](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse_shared.h:564).
- **Evidence & Root Cause**: PSRLDQ emits the EXT sequence for a left shift; PSLLDQ emits the right-shift sequence. The encoder additionally starts from `0x6E001800`, which already sets immediate-field bits. OR-ing the requested immediate makes the actual count `imm4|3`.
- **Remediation**: Use an EXT base with a zero immediate field and correct the source ordering/count for each direction.

### I686-R7-51 — BUG — HIGH

- **Summary**: DBT floating-point arithmetic and conversions ignore essential MXCSR semantics.
- **Locations**: [emit_sse.c:514](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:514), [emit_sse2.c:352](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:352).
- **Evidence & Root Cause**: Arithmetic guards only FTZ/DAZ and otherwise runs under host FP settings without updating guest exception status. Masked DIVSS by zero does not set guest ZE. Packed conversions directly use A64 saturating conversions, which differ from x86 integer-indefinite results for NaN/overflow; CVTPS2DQ also hardcodes nearest rounding.
- **Remediation**: Implement guest rounding/status/result conversion semantics or decline these paths until they match the interpreter contract.

### I686-R7-52 — BUG — HIGH

- **Summary**: vm86 entry ignores supplied ESP, and sixteen-bit writes destroy upper register halves.
- **Locations**: [v86.c:620](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:620), [v86_internal.h:49](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86_internal.h:49).
- **Evidence & Root Cause**: Entry installs the supplied GPRs except ESP, leaving the protected-mode stack register active for vm86 pushes/pops. Separately, `r16_set()` assigns the entire register instead of preserving its upper sixteen bits. Even `MOV AX,imm16` corrupts EAX’s upper half.
- **Remediation**: Install `ks->regs.esp` on entry and preserve upper halves for sixteen-bit register writes.

### I686-R7-53 — BUG — MEDIUM

- **Summary**: vm86 effective-address decoding uses incorrect registers and ignores address-size override.
- **Locations**: [v86.c:227](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:227), [v86.c:258](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:258), [v86.c:290](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:290).
- **Evidence & Root Cause**: The base table maps `[DI]` to register 6, SI. BP-based `mod=00` forms incorrectly select DS. Prefix `67` is discarded without recording it, so subsequent memory operands still execute with sixteen-bit decoding despite comments promising rejection.
- **Remediation**: Correct the base/segment tables and preserve address-size state, implementing or explicitly rejecting unsupported addressing forms.

### I686-R7-54 — BUG — HIGH

- **Summary**: A vm86 prefix stream can trap the host interpreter in an unbounded loop.
- **Locations**: [v86.c:283](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:283), [v86_internal.h:159](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86_internal.h:159), [v86.c:649](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:649).
- **Evidence & Root Cause**: Prefix scanning has no byte limit, while fetch wraps IP at sixteen bits. A code segment filled with recognized prefix bytes loops forever inside one `v86_step()`. The outer instruction guard never advances, and pending signals are not checked there.
- **Remediation**: Enforce the instruction-length limit inside fetch/prefix decoding and return the appropriate fault.

### I686-R7-55 — BUG — MEDIUM

- **Summary**: Protected-mode decoding does not enforce one consistent fifteen-byte fetch budget.
- **Locations**: [decode.c:478](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:478), [decode.c:223](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:223), [decode.c:637](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:637).
- **Evidence & Root Cause**: Prefix parsing stops after twelve prefixes, while ModR/M, displacement, and immediate reads proceed without a remaining-length budget. Length is rejected only afterward. This both rejects long prefix sequences prematurely and permits overlength instruction decoding to touch bytes beyond the architectural limit before returning an error.
- **Remediation**: Use a checked instruction-stream cursor shared by every fetch, with explicit length-fault handling.

BCD instructions are explicitly excluded by the current decoder; there is no implemented DAA/DAS/AAA/AAS/AAM/AAD algorithm to validate. No style-only findings are included.
