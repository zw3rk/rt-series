# Round 19 Post-Remediation Review — Track C2b (NEON Integer, Shift, Narrow/Long & Scalar Interpreter, `claude-fable-5-1`)

Review complete. The three files are mostly sound in their arithmetic helpers, but the same-length register block in `interp_vfp_neon_int.c` has several hard functional errors, and VEXT and VQMOVN.S compute wrong results.

## Residual defects

**1. Register shift B/op mapping swapped** — `src/interp/interp_vfp_neon_int.c:567-568`
ARM encodes A=0100 B=0 VSHL, A=0100 B=1 VQSHL, A=0101 B=0 VRSHL, A=0101 B=1 VQRSHL. The code sets `rounding = b4; sat_op = (op == 5)`. So VQSHL (reg) executes as a rounding, non-saturating shift and VRSHL executes as a saturating, non-rounding shift. Only VSHL and VQRSHL land correctly by coincidence.
```c
bool rounding = (op == 5U);
bool sat_op = b4;
```

**2. Register shift operands swapped** — `src/interp/interp_vfp_neon_int.c:575-577`
Pseudocode: `shift = SInt(Elem[D[n]]<7:0>)`, data is `Elem[D[m]]` (syntax `VSHL Dd, Dm, Dn`). The code takes data from `n0` and shift amounts from `m0`. Swap the two reads:
```c
uint64_t a  = ni_get(ctx->vfp_d[m0], k0, esz);   /* data   */
uint64_t mb = ni_get(ctx->vfp_d[n0], k0, esz);   /* shifts */
```

**3. Signed right shift by ≥ esize returns 0 instead of sign fill** — `src/interp/interp_vfp_neon_int.c:593-594`
For negative shift counts with `t >= e`, the code yields 0 for both signedness. ARM's `Int(elem) << shift` with signed elem and shift ≤ -esize gives -1 (all ones) for negative lanes. Example: VSHL.S8 with lane -1, shift -8 must produce 0xFF, code produces 0x00.
```c
if (!u) {
    r = (uint64_t)ni_asr(ni_sext(a, e), t) & ni_emask(e);
} else {
    r = (t >= e) ? 0ULL : (a >> t) & ni_emask(e);
}
```

**4. `ni_qshl` signed 64-bit threshold overflows** — `src/interp/interp_vfp_neon_int.c:177`
For `e == 64`, `smax == INT64_MAX`, so `smax + 1` is signed overflow (UB). Under wrap semantics `thr` becomes `+2^(63-s)` for `s >= 1`, so every negative 64-bit lane saturates to INT64_MIN and sets QC. VQRSHL.S64 (and VQSHL.S64 once defect 1 is fixed) with lane -1, shift 1 returns 0x8000000000000000 instead of -2. Compare magnitudes unsigned:
```c
uint64_t lim = (1ULL << (e - 1U)) >> s;          /* |smin| >> s */
uint64_t mag = 0ULL - (uint64_t)sv;
if (mag > lim) { *sat = true; return ((uint64_t)smin) & ni_emask(e); }
```

**5. Valid Q-form 64-bit same-length ops rejected** — `src/interp/interp_vfp_neon_int.c:453` and `:562`
`VQSUB.{S,U}64 Qd,Qn,Qm` and `VSHL/VRSHL/VQSHL/VQRSHL.{S,U}64 Qd,Qm,Qn` are architecturally valid (size=11, Q=1 is allowed; only odd register numbers are UNDEFINED). Both guards return false, so the instructions fall through the dispatch chain. Drop `(size < 3U || !is_q)` at line 562 (the loop already handles `esz == 3`, `per == 2`), and at line 453 drop `(size == 3U && is_q)` and loop the 64-bit scalar body over `half = 0..nregs-1`.

**6. VEXT operand order swapped** — `src/interp/interp_vfp_neon_int.c:276-277, 293-296`
ARM: `hival = D[m]; lval = D[n]; D[d] = (hival:lval)<pos+63:pos>`. The code puts Dm low and Dn high in both D and Q forms, so `VEXT.8 d0,d1,d2,#3` yields `{d2[3..7], d1[0..2]}` instead of `{d1[3..7], d2[0..2]}`. Swap `lo`/`hi` (D form) and load `words[0..1]` from Qn, `words[2..3]` from Qm (Q form).

**7. VQMOVN.S saturates to the unsigned range** — `src/interp/interp_vfp_neon_int.c:334`
`dst_u = (op5 == 4U) ? is_q : true` makes `dst_u` true for op=10 (VQMOVN signed, Q=0). The signed-to-signed branch at line 351 is then skipped and `ni_sat_su` runs, so input -1 becomes 0 with QC set instead of 0xFF. ARM: `dest_unsigned = op<0>` for both op5 values.
```c
bool dst_u = is_q;
```

## VERIFIED

- **Bitmasks and fields**: shift guard `0xFE800010/0xF2800010`, long/scalar guard `0xFE800010/0xF2800000`, VEXT/narrow `0xFFB00010`, VDUP core (cp11, bit4, L=0, B:E=11 rejected, Rt=15 rejected), D/N/M extraction, scalar `Vm<2:0>` + `M:Vm<3>` indexing. Modified-immediate space (`imm6<5:3>==000`, L=0) is correctly excluded from all shift paths.
- **Odd-register guards**: VMOVL/VSHLL Vd, narrowing shifts Vm, Q-form imm shifts Vd/Vm, VADDHN/VSUBHN Qn/Qm, VADDW Qd/Qn, all Q-dest long ops, VDUP Q. `ni_same`, `ni_narrow`, `ni_vext` round odd Q numbers down with `& ~1U` instead of trapping; lenient but not a result error.
- **Dispatch wiring**: int → shift → long chain; guards are mutually exclusive on bit 23 and bits 27:24. Note `ni_same` only pins bits 27:25 and 23 and relies on the caller having established `insn[31:28] == 1111`.
- **Saturation/QC**: VQSUB 64-bit overflow test, VQSHLU, VQSHL imm (S/U, incl. 64-bit), VQSHRUN/VQRSHRUN/VQSHRN/VQRSHRN, VQMOVUN/VQMOVN.U, VQDMLAL/VQDMLSL/VQDMULL (min×min doubling + saturating accumulate), VQDMULH/VQRDMULH (vector and scalar).
- **Rounding**: VRHADD, VRSHR/VRSRA (`sh_rshr_u/s` carry-safe at `rsh == 64`), VRSHRN, VRADDHN/VRSUBHN (`round` added before truncating modulo 2·esize), VQRDMULH round constant, `ni_rshr` for VRSHL semantics.
- **64-bit edges**: L=1, `imm6 == 0` → `rsh = 64`: VSHR/VSRA (0 or sign fill), VRSHR (MSB carry), VSRI mask collapses to 0 (Dd unchanged). VSRI mask `emask >> rsh`, VSLI mask `(emask << lsh) & emask` correct.
- **Aliasing**: imm shifts snapshot both D halves before writing. All long/scalar/narrow/VEXT/VSHLL paths read every source before the first write. Same-lane element ops in `ni_same` (including VABA accumulate) write lane k after reading lane k and never read a lane already written.
- VMULL.P8 carry-less multiply and the ARMv8-only VMULL.P64 path are arithmetically correct.

**7 RESIDUAL DEFECTS**
