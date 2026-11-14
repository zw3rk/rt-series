# Round 19 Post-Remediation Review — Track C2a (NEON Float/Load-Store & Darwin Trap Interpreter, `claude-fable-5-1`)

Review complete. Verdict first, then the item-by-item findings.

**Result: 5 residual defects in the listed files, 1 item not verifiable within the mandated read set.** The fallthrough chain and the VLDn/VSTn pre-flight range checks are sound. The `.F32` arithmetic has one decode bug and three semantic deviations. The Thumb Darwin trap works but ignores IT predication. The ARM-mode trap is not in the lines I was permitted to read.

## Item 1: Fallthrough chain

`VERIFIED`. `i_vfp_neon` tries VLD1-multi, VMOV-imm, VREV, integer VADD/VSUB, bitwise, `.F32` three-register, `.F32` two-register-misc, and by-scalar, then calls `i_vfp_neon_ext` at `src/interp/interp_vfp_neon.c:803`. The ext layer tries `x_vld_vst`, `x_misc`, `x_perm`, `x_alu`, then `i_vfp_neon_int` at `src/interp/interp_vfp_neon_ext.c:888`. Masks are disjoint between layers (0xF4 load/store, 0xF3B two-register misc, bit 23 clear for three-register), and the ext VLD/VST handler explicitly rejects the VLD1 types already consumed upstream at `interp_vfp_neon_ext.c:252`. No encoding is claimed twice and no handled encoding returns true without advancing `regs[15]`.

## Item 2: Standard FPSCR `.F32` semantics

**Defect 1 (HIGH): VRECPE/VRSQRTE two-register-misc op5 decode is off by the F bit.** `src/interp/interp_vfp_neon.c:643-694`. In the two-register-misc group with A=11, bits 11:7 are `0 1 0 F x`: F is bit 8, bit 7 selects VRSQRTE over VRECPE. So op5 8 = VRECPE.U32, 9 = VRSQRTE.U32, 10 = VRECPE.F32, 11 = VRSQRTE.F32 (e.g. `vrecpe.f32 d0,d1` = 0xF3BB0501 gives op5 = 10). The code treats 8/9 as the float reciprocal and rsqrt estimates, and treats 10/11 as Newton step ops reading Dd (`2 - Dd*Dm`, `(3 - Dd*Dm)/2`). Consequences: VRECPE.F32 and VRSQRTE.F32 return garbage dependent on the old Dd, and VRECPE.U32/VRSQRTE.U32 get float results. There is no two-register step instruction; the real VRECPS/VRSQRTS are three-register and already handled at line 432-439. Fix: move the bodies at 644-671 to op5 10/11, implement integer estimates for 8/9, delete the 672-694 branch.

**Defect 2 (MEDIUM): VRECPS/VRSQRTS miss the inf×0 special case.** `src/interp/interp_vfp_neon.c:434,438`. `FPRecipStep`/`FPRSqrtStep` define product = +0 when one operand is infinite and the other zero, giving 2.0 and 1.5 respectively. The code computes `inf*0 = NaN` and canonicalizes, so the standard refinement sequence `VRECPE` then `VRECPS` on a zero divisor yields NaN instead of inf. Fix: before the multiply, if `(isinf(a) && b == 0) || (a == 0 && isinf(b))` set the product to 0.0f.

**Defect 3 (LOW): VMLA/VMLS.F32 intermediate product is not flushed.** `src/interp/interp_vfp_neon.c:335-336` (vector) and `:785-787` (by-scalar). The architecture rounds the product through FPMul under FZ=1, so a subnormal product becomes zero before the add. The code adds the unflushed subnormal, which changes the result when Dd is a small normal (e.g. Dd = 2^-126, product = 2^-130: hardware 0x00800000, code 0x00880000). Fix: `p = neon_f32_finish(p)`. The scalar VFP path has the same gap when FPSCR.FZ is set at `src/interp/interp_vfp.c:783,789,811,817`; wrap the product in `vfp_fz_out_*`.

**Defect 4 (LOW): NEON VABS/VNEG.F32 are not bit operations.** `src/interp/interp_vfp_neon.c:604-638`. `FPAbs` and `FPNeg` are defined as `'0' : op<30:0>` and `NOT(op<31>) : op<30:0>`, with no unpack, no flush, no default-NaN. The code flushes subnormal inputs to signed zero and replaces any NaN with 0x7FC00000, so `vabs.f32` of 0x80000001 gives 0 instead of 0x00000001, and `vneg.f32` of 0x7FC00000 gives 0x7FC00000 instead of 0xFFC00000. Fix: operate on the raw word, `w & 0x7FFFFFFF` or `w ^ 0x80000000`, with no canon/finish. The scalar VFP VABS/VNEG at `interp_vfp.c:598,620` are already correct.

`VERIFIED`: VADD, VSUB, VMUL, VFMA, VFMS, VABD, VMAX, VMIN, VPADD, VPMAX, VPMIN, VMAXNM, VMINNM, VCEQ, VCGE, VCGT, VACGE, VACGT, VCEQ/VCGE/VCGT/VCLE/VCLT #0, VCVT (both directions, RZ saturation, NaN to 0), and the by-scalar VMUL. Input flush via `neon_f32_canon_in`, output flush and 0x7FC00000 via `neon_f32_finish`, signed-zero max/min tie rules, and the NaN-to-false compare rule are all correct. Scalar VFP under real FPSCR honours FZ/DN, IDC/UFC, rounding mode, and the fused/non-fused split.

## Item 3: Pre-flight memory checks

`VERIFIED`. Every load/store handler calls `i_mem_ok` on the full byte range with the correct protection before touching a register or memory: VLD1/VST1 multi at `interp_vfp_neon.c:79`, single-lane at `interp_vfp_neon_ext.c:137`, all-lanes at `:207`, VLD2/VST2 at `:263,320`, VLD3/VST3 and VLD4/VST4 at `:383`. The multi-structure loads additionally buffer all memory before writing any register. Lane index and `inc` decoding from `index_align` matches the architecture for sizes 0/1/2 across VLD1 to VLD4. Writeback skips rm = 15 and uses the literal size for rm = 13.

## Item 4: Darwin trap `0xDEFE` / `0xE7FFDEFE`

**Defect 5 (LOW): Thumb `0xDEFE` traps even when its IT condition fails.** `src/interp/interp_thumb.c:60-64`. The check runs before `skip` is computed, so a predicated-false UDF inside an IT block raises SIGTRAP. UDF executes under `ConditionPassed()`; only BKPT is architecturally unconditional. The generic UDF path at line 89 does honour `skip`, so the two paths disagree. Fix: move the `0xDEFE && is_ios` test inside `if (!skip)` ahead of line 89, keeping `regs[15] = pc`.

**ARM mode `0xE7FFDEFE`: UNVERIFIED within scope.** `src/interp/interp_a32.c:1-95` contains only the LDREX/STREX helpers. The defect ledger points to `interp_a32_ctl.c`, which was outside the mandated read set, so I make no claim about it.

One out-of-portion observation for the integer track, not counted here: `x_alu` VQADD with size = 3 reaches `x_sat_s(s, 64)` at `interp_vfp_neon_ext.c:24`, where `1LL << 63` and the preceding `int64_t` add are undefined behaviour.

**5 RESIDUAL DEFECTS**
