Read all eight files in `src/interp/` end-to-end, plus the CPU, trap, signal-state, and FPU headers and relevant callers. No builds or tests were run; no files were changed. Examples below are derived from static inspection.

### M32-R7-1 — BUG — HIGH

- **Summary**: FR=0 double-precision registers do not alias their even/odd word pairs.
- **Locations**: [fpmove.c:104](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:104), [fp.c:62](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:62), [fp.c:716](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:716), [fp.c:876](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:876).
- **Evidence & Root Cause**: Every double occupies one independent `fpr[n]`; `fr_mode` only controls selected parity checks. With FR=0 and initially zero registers, writing `0` to `$f0` and `0x3ff00000` to `$f1` should construct double `1.0`, but double operations read zero from `fpr[0]`. Conversely, `LDC1 $f0` does not update the word read through `$f1`. [QEMU’s FR-aware accessors](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/translate.c) explicitly assemble and split these pairs.
- **Remediation**: Centralize FR-aware word, doubleword, and high-word accessors and use them throughout memory moves, arithmetic, conversions, and state serialization.

### M32-R7-2 — BUG — HIGH

- **Summary**: Delay-slot syscalls can lose the branch target or overwrite a signal-handler redirect.
- **Locations**: [interp.c:108](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:108), [interp.c:808](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:808), [fp.c:838](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:838), [syscalls.c:52](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:52).
- **Evidence & Root Cause**: `rt_sigprocmask` always advances PC through `mips_sc_advance_pc_once()`. In an integer branch’s delay slot, this makes `exec_syscall()` return `2`; `exec_branch()` preserves branch-PC+8 instead of taking the branch. Conversely, `fp_bc1()` calls `interp_step()`, which normalizes redirected-syscall completion to zero, then overwrites the redirected PC with its branch destination. A self-signaling syscall can therefore create a handler frame without executing the handler.
- **Remediation**: Preserve distinct outcomes for ordinary completion, syscall completion, and architectural redirection. Record the post-delay-slot destination before entering syscall handling.

### M32-R7-3 — BUG — HIGH

- **Summary**: Faulting unaligned merge operations deliver the same fault twice.
- **Locations**: [unaligned.c:36](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/unaligned.c:36), [unaligned.c:54](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/unaligned.c:54), [signals.c:576](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:576).
- **Evidence & Root Cause**: `guest_ld8()` and `guest_st8()` already deliver memory faults. Successful delivery clears `exit_reason` to `NONE`. The merge helpers interpret that state as an undelivered fault and call `mips_fault()` again. One `LWL/LWR/SWL/SWR` fault consequently creates a second frame saving the handler’s PC; `SA_RESETHAND` can turn the second delivery into termination.
- **Remediation**: Propagate the memory helper’s `MIPS_FAULT` without delivering another fault.

### M32-R7-4 — BUG — MEDIUM

- **Summary**: Signed MADD/MSUB accumulation invokes C undefined behavior.
- **Locations**: [interp.c:301](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:301), [interp.c:323](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:323).
- **Evidence & Root Cause**: Both instructions add or subtract into an `int64_t` accumulator. `HI:LO=0x7fffffffffffffff`, `rs=rt=1`, followed by `MADD` overflows signed C arithmetic. `MSUB` from `0x8000000000000000` similarly underflows. Architectural accumulation must wrap modulo 2⁶⁴.
- **Remediation**: Keep the accumulator unsigned and convert the signed 32×32 product to `uint64_t` before accumulation.

### M32-R7-5 — BUG — HIGH

- **Summary**: SYNC does not enforce memory ordering.
- **Locations**: [interp.c:197](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:197), [mem.c:510](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:510).
- **Evidence & Root Cause**: SYNC immediately returns without a fence. Ordinary accesses do not supply equivalent ordering: loads use ordinary memory reads, and stores before LL activation use plain `memcpy`. The surrounding acquire loads do not provide the required preceding-store-to-following-load ordering. Two threads executing `store; SYNC; load` can therefore admit forbidden store-buffering outcomes on AArch64.
- **Remediation**: Implement the required compiler and host memory barriers, including full ordering for `SYNC 0`.

### M32-R7-6 — BUG — MEDIUM

- **Summary**: Alignment exceptions are misclassified as mapping faults.
- **Locations**: [interp.c:538](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:538), [decode.c:65](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/decode.c:65), [fpmove.c:77](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:77), [mem.c:248](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:248).
- **Evidence & Root Cause**: Misaligned LL/SC, instruction fetches, and FP accesses call the generic `mips_fault()`. With default FIXADE enabled, that function always selects SIGSEGV, including for accesses explicitly rejected for alignment. Even with FIXADE disabled, an eight-byte FP access at address `4 mod 8` is classified as SIGSEGV because the classifier checks only two address bits.
- **Remediation**: Pass an explicit alignment/mapping/permission fault cause and access width. Alignment exceptions must not be inferred from FIXADE or address bits alone.

### M32-R7-7 — BUG — MEDIUM

- **Summary**: SC with an invalid reservation checks read permission instead of write permission.
- **Locations**: [interp.c:553](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:553), [mem.c:774](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:774).
- **Evidence & Root Cause**: The dead-reservation path calls `guest_ld32()`, bypassing `guest_sc32()`’s write validation. SC against readable, read-only memory returns zero instead of a store-access exception. The [MIPS instruction specification](https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00086-2B-MIPS32BIS-AFP-05.04.pdf) performs store-address translation before testing LLbit.
- **Remediation**: Route every SC through store-access validation, then evaluate reservation success without modifying memory on failure.

### M32-R7-8 — BUG — MEDIUM

- **Summary**: Arithmetic traps lose their specific exception cause.
- **Locations**: [interp.c:241](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:241), [fp.c:42](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:42), [mips32rt.h:468](/Users/angerman/Projects/zw3rk/mips32rt/src/mips32rt.h:468), [signals.c:473](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:473).
- **Evidence & Root Cause**: The trap interface carries only signal number and address; signal construction assigns `FPE_FLTINV` to every SIGFPE. Integer overflow and enabled FP divide-by-zero, overflow, underflow, and inexact exceptions consequently reach handlers with incorrect `si_code`. [QEMU’s signal mapping](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/linux-user/mips/cpu_loop.c) preserves these distinctions.
- **Remediation**: Carry the architectural trap cause through delivery and map it to the corresponding Linux `FPE_*` code.

### M32-R7-9 — BUG — MEDIUM

- **Summary**: BREAK and register-trap codes are discarded.
- **Locations**: [interp.c:194](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:194), [interp.c:277](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:277).
- **Evidence & Root Cause**: These paths always deliver SIGTRAP without examining the instruction’s code field. Linux MIPS uses codes 6 and 7 for arithmetic overflow and division by zero; compiler-generated checks therefore receive the wrong signal. [QEMU’s Linux-compatible handling](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/linux-user/mips/cpu_loop.c) maps them to SIGFPE with `FPE_INTOVF` and `FPE_INTDIV`.
- **Remediation**: Decode and preserve BREAK/TRAP codes, including Linux’s BREAK encoding compatibility handling, before selecting signal and `si_code`.

### M32-R7-10 — BUG — HIGH

- **Summary**: FP ADD/SUB discards information required for correct rounding.
- **Locations**: [fp.c:309](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:309).
- **Evidence & Root Cause**: Exponent alignment shifts the smaller mantissa before adding guard/round/sticky positions. Discarded bits become only a Boolean sticky value. Under nearest-even, single-precision `1.0 + 0x33c00000`—an addition of 0.75 ULP—therefore produces `0x3f800000` instead of `0x3f800001`. Subtraction also loses the discarded tail’s direction.
- **Remediation**: Extend mantissas before alignment and preserve guard, round, and sticky information through addition/subtraction and normalization.

### M32-R7-11 — BUG — HIGH

- **Summary**: Directed FP overflow returns NaN instead of maximum finite magnitude.
- **Locations**: [fp.c:248](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:248).
- **Evidence & Root Cause**: The finite-saturation branch combines an all-ones exponent with an all-ones fraction. With round-toward-zero, `FLT_MAX * 2` produces `0x7fffffff`, rather than `0x7f7fffff`. The double-precision path has the same error.
- **Remediation**: Use the largest finite exponent, one below the all-ones exponent, when saturation is required.

### M32-R7-12 — BUG — MEDIUM

- **Summary**: Extreme underflow bypasses directed rounding.
- **Locations**: [fp.c:212](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:212).
- **Evidence & Root Cause**: When denormalization shifts the retained mantissa to zero, the function returns signed zero immediately despite a nonzero sticky tail. With rounding toward positive infinity, positive minimum-subnormal multiplied by `1/16` must round to positive minimum-subnormal; this path returns zero.
- **Remediation**: Continue through rounding when the retained mantissa is zero but discarded bits are nonzero.

### M32-R7-13 — BUG — HIGH

- **Summary**: FP comparisons misorder zero and small finite values.
- **Locations**: [fp.c:86](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:86), [fp.c:525](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:525).
- **Evidence & Root Cause**: Unpacking leaves zero’s exponent at zero. Comparison special-cases only two zero operands; otherwise it compares exponents before mantissas. Thus `C.LT.S(+0,+0.5)` evaluates false, while the reversed comparison evaluates true. The wrong FCC subsequently changes BC1 and conditional-move behavior.
- **Remediation**: Handle either-zero comparisons explicitly, or compare normalized sign/magnitude encodings with signed-zero equivalence.

### M32-R7-14 — BUG — MEDIUM

- **Summary**: Invalid unordered comparisons incorrectly force FCC false.
- **Locations**: [fp.c:520](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:520), [fp.c:543](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:543).
- **Evidence & Root Cause**: `invalid` unconditionally assigns `res=0`. For `C.UN.S` on an sNaN with Invalid disabled, the unordered condition must remain true while Invalid is recorded. [QEMU’s comparison helpers](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c) keep condition evaluation separate from exception delivery.
- **Remediation**: Compute the condition independently; suppress FCC writeback only when an enabled exception actually traps.

### M32-R7-15 — BUG — MEDIUM

- **Summary**: ROUND/TRUNC/CEIL/FLOOR suppress required Inexact reporting.
- **Locations**: [fp.c:618](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:618), [fp.c:742](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:742).
- **Evidence & Root Cause**: Every explicit-rounding conversion passes `no_inexact=1`. `TRUNC.W.S(1.5)` returns one without Cause.I/Flags.I and does not trap when Enable.I is set. Explicit rounding selects the rounding mode; it does not suppress Inexact. See the [MIPS ROUND.W exception specification](https://www.cs.umd.edu/class/fall2024/cmsc411/resources/MIPS_Vol2.pdf).
- **Remediation**: Remove this suppression and commit Inexact through the normal FP exception path.

### M32-R7-16 — BUG — MEDIUM

- **Summary**: Legacy NaN format conversion can produce infinity.
- **Locations**: [fp.c:112](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:112), [fp.c:663](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:663).
- **Evidence & Root Cause**: `CVT.D.S` on legacy sNaN `0x7fc00000` shifts its sole fraction bit into the double signaling-bit position, then `fp_quiet()` clears it. The committed result becomes `0x7ff0000000000000`: infinity. The reverse conversion has the analogous failure.
- **Remediation**: Apply the legacy default-NaN rule, or otherwise ensure quieting cannot eliminate the entire NaN fraction.

### M32-R7-17 — BUG — MEDIUM

- **Summary**: NAN2008 integer conversions return legacy invalid-result values.
- **Locations**: [fp.c:569](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:569), [fp.c:742](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:742), [fp.c:762](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:762).
- **Evidence & Root Cause**: Invalid conversions always produce positive signed maximum, ignoring `nan2008`; callers overwrite the helper’s result with that constant again. For NAN2008 `CVT.W.S` of qNaN `0x7fc00000`, the expected Invalid-disabled result is zero, as implemented by [QEMU’s NAN2008 conversions](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c).
- **Remediation**: Implement mode-specific invalid-result rules centrally and preserve the helper’s selected result.

### M32-R7-18 — BUG — HIGH

- **Summary**: Valid FP conditional moves raise SIGILL.
- **Locations**: [fp.c:724](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:724).
- **Evidence & Root Cause**: S/D function codes 17, 18, and 19—`MOVF/MOVT`, `MOVZ`, and `MOVN`—have no dispatch cases and fall into the reserved-instruction trap. This happens even when the condition requires leaving the destination unchanged. These are supported pre-R6 instructions in [QEMU’s decoder](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/translate.c).
- **Remediation**: Implement conditional bitwise FPR moves using the selected FCC or GPR condition and FR-aware accessors.

### M32-R7-19 — BUG — MEDIUM

- **Summary**: FPU control-register moves omit required FCSR semantics.
- **Locations**: [fpmove.c:162](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:162).
- **Evidence & Root Cause**: CTC1 blindly replaces FCSR and returns. Writing Cause.V plus Enable.V (`0x10800`) therefore fails to raise the pending FP exception. Writes also overwrite mode indicators, while CFC1/CTC1 reject the defined FCCR/FEXR/FENR aliases 25/26/28. [QEMU’s control helpers](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c) implement masks, aliases, and pending-exception detection.
- **Remediation**: Centralize control-register reads/writes with the admitted profile’s writable masks, alias mappings, and immediate exception check.

### M32-R7-20 — DEFECT — MEDIUM

- **Summary**: The FPU header assigns incorrect encoding values to W and L formats.
- **Locations**: [emit_fp_priv.h:26](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp_priv.h:26), [emit_fp.c:886](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:886), [fp.c:887](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:887).
- **Evidence & Root Cause**: `FP_FMT_W` and `FP_FMT_L` are defined as 18 and 19, although the instruction formats are 20 and 21, correctly recognized by the interpreter. The emitter consequently recognizes reserved format encodings as integer conversions while legitimate conversions miss that dispatch path.
- **Remediation**: Correct the constants and share authoritative format definitions between interpreter and emitter; reserved encodings must remain rejected.
