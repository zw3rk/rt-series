I now have all the evidence needed. Here is the complete review of commit `2ccfe8b` against all 32 items.

---

## Round-7 ISA Interpreter Remediation Review — Commit `2ccfe8b`

### Curated C11 Compliance

| Check | Status |
|---|---|
| No VLAs | **PASS** — grep found none |
| No `.c` includes | **PASS** — grep found none |
| All files ≤ 900 lines | **PASS** — largest is `signals.c` at 897 |
| Fixed-width types | **PASS** — all arithmetic uses `uint32_t`, `uint64_t`, etc. |
| No forbidden functions | **PASS** |

---

### Per-Item Classification

#### A32-R7-1 — UDF.W executes syscall — **VERIFIED**
`interp_thumb.c:~799`: UDF.W (`F7F0 A000`) now calls `i_undef(ctx)` and returns `A32_EXIT_UNDEF` instead of setting `svc_imm` and returning `A32_EXIT_SVC`.

#### A32-R7-2 — Thumb decoder masks — **VERIFIED**
`interp_thumb.c:~162-415`: The `0x4xxx` check changed from `(hw >> 12) == 0x4U` to `(hw & 0xF800U) == 0x4000U`, excluding literal loads `0x4800-0x4FFF`. Memory-class masks split into disjoint branches: register offset (`0x5xxx`), word/byte immediate (`011x`), halfword immediate (`1000`), and SP-relative (`1001`).

#### A32-R7-3 — Nonword/doubleword exclusives, SWP — **VERIFIED**
`interp_a32.c:~517-648`: Unified exclusive mask `(insn & 0x0F8000F0U) == 0x01800090U` with `ex_op` selecting word/doubleword/byte/halfword and load/store. New `do_ldrex64`/`do_strex64` (lines 52-107) provide 8-byte exclusive reservation. SWP/SWPB dispatched via `(insn & 0x0FB00FF0U) == 0x01000090U` with proper atomic load/store and `copyout_invalidate`.

#### A32-R7-4 — Flag elimination destroys APSR at fault — **VERIFIED**
`interp_a32_ctl.c:158-213`: New `a32_insn_may_exit_sync()` identifies SVC, BKPT, UDF, SWP, exclusives, coprocessor, memory transfers, and block transfers as flag-observation points. Liveness backward pass updated at line 674: `a32_insn_reads_flags(insn) || a32_insn_may_exit_sync(insn)`. Matching T32 fix in `interp_t32_mem.c:533-607,739`.

#### A32-R7-5 — Stale FP in signal frames — **VERIFIED**
`core_emit_mem.c:170-214`: Removed `!b->self_loop_vfp_active &&` guard — VFP cache now always flushes before faultable memory accesses. `core_emit_shared.c:513-515`: Same for LDM/STM. `signals.c:473-484`: Host FPSR cumulative bits merged into guest `fpscr` before signal-frame construction.

#### A32-R7-6 — Alignment enforcement — **PARTIAL**
`interp_a32_mem.c:47-50`: LDRD/STRD check `(acc & 3U) != 0U`. `interp_a32_mem.c:139-143`: LDM/STM check `(addr & 3U) != 0U`. `interp_a32.c:~552`: Exclusives use size-based `align_mask` and deliver `A32_EXIT_FAULT` instead of UNDEF. **Missing**: VFP VLDR/VSTR in `interp_vfp.c:454` still accesses `base + off` without alignment checks; the interpreter VFP transfer path has no word-alignment enforcement.

#### A32-R7-7 — Exclusive reservations survive writes — **VERIFIED**
`interp_a32.c:27-50`: `do_ldrex` now uses a seqlock — samples epoch before/after the load and retries on mismatch. `interp_a32_mem.c:61-62`: STRD routed through `i_store_u32` which calls `a32_vm32_copyout_invalidate`, bumping reservation epochs. `vm32.c:436-604`: 64-bit reservation functions added; `a32_vm32_reservation_bump` for explicit invalidation. `vm32.c:33`: `val` field widened to `uint64_t`.

#### A32-R7-8 — STM probe observability — **VERIFIED**
`core_emit_shared.c:542-556`: Pre-validation probes changed from read-modify-write to read-only: both load and store paths now use `a64_emit_ldrb_imm_w(b, A64_ZR, ...)` — reads to the zero register, never touching guest memory.

#### A32-R7-9 — SWP Rd overwrite before completion — **VERIFIED**
`interp_a32.c:616-648` (interpreter): Loaded value held in local `tmp`; `ctx->regs[rd] = tmp` only after store succeeds. `interp_a32_dp.c:108-133` (JIT): Load targets `A64_TMP0` scratch register; `a64_emit_mov_w(b, rd, A64_TMP0)` emitted after the STXR loop.

#### A32-R7-10 — TPIDRURW aliases TPIDRURO — **VERIFIED**
`a32rt.h:85`: New `tls_tpidrurw` field (offset 88, replaces `pad_it`), with `_Static_assert`. `interp_a32.c:831-848`: TPIDRURO read (`0x0E1D0F70`) → `ctx->tls_tp`; TPIDRURW read (`0x0E1D0F50`) → `ctx->tls_tpidrurw`; write (`0x0E0D0F50`) → `ctx->tls_tpidrurw`. `core_emit_shared.c:482-498`: JIT emitter mirrors the same split.

#### A32-R7-11 — Thumb ADD/SUB bits reversed — **VERIFIED**
`interp_thumb.c:76-100`: `is_imm = (sel >> 1) & 1U` (bit 10) selects immediate; `is_sub = sel & 1U` (bit 9) selects subtraction — matches the architectural encoding.

#### A32-R7-12 — Thumb flags inside IT blocks — **VERIFIED**
`interp_thumb.c:97,149,166,174`: `!use_it` guards added around all implicit flag writes (ADD/SUB r/imm3, MOV imm8, ADD/SUB imm8). `interp_thumb.c:238-252`: T16 ALU ops: explicit flag ops (TST `0x8`, CMP `0xA`, CMN `0xB`) always update; all others gated on `!use_it`.

#### A32-R7-13 — IT progression across branches/UNDEF — **VERIFIED**
`interp_thumb.c:615-620`: New `trap_ret` label preserves pre-instruction IT for retryable traps. All UNDEF exits changed from `goto adv_it_ret` to `goto trap_ret`. `interp_thumb.c:835-850`: T32 IT now advances on `A32_EXIT_NONE` unconditionally (removing the `regs[15] == pc + 4` branch guard), and UNDEF explicitly skips advancement.

#### A32-R7-14 — Signal frames lack CPSR.IT — **VERIFIED**
`a32rt.h:27-29`: `A32_CPSR_IT_72_MASK`, `A32_CPSR_IT_10_MASK`, `A32_CPSR_IT_MASK` defined. `signals.c:308-322`: IT bits packed from `ctx->itstate` into `arm_cpsr` for frame construction. `signals.c:785-810`: Sigreturn extracts IT from `arm_cpsr` with validation (zero-out on OOB), replacing the PC-distance heuristic.

#### A32-R7-15 — BLX immediate misses Thumb/H-bit — **VERIFIED**
`interp_a32.c:371-390`: H-bit: `uint32_t h_bit = ((insn >> 24) & 1U) << 1`. Target: `(pc + 8U) + ((uint32_t)imm24 << 2) + h_bit`. Forces Thumb: `i_set_pc_branch(ctx, target | 1U, true)`. Sign extension fixed via manual check. JIT path also corrected in `interp_a32_ctl.c:288,335,659`.

#### A32-R7-16 — LDR PC loses interworking/writeback — **VERIFIED**
`interp_a32.c:775-800`: LDR byte/word to PC: writeback emitted before the branch (`ctx->regs[rn] = wb`), then `i_set_pc_branch(ctx, v, true)` with interworking enabled (second arg `true`, was `false`).

#### A32-R7-17 — Thumb ALU writes to PC clear T — **VERIFIED**
`interp_thumb.c:286-292`: `i_set_pc_branch(ctx, r, false)` — non-interworking (Thumb BranchWritePC semantics). The `ctx->cpsr &= ~A32_CPSR_T` block is removed entirely. Comment: "Thumb BranchWritePC: an even target stays in Thumb state; never clear CPSR.T here."

#### A32-R7-18 — Wrong architectural PC value — **PARTIAL**
`interp_a32.c:184-191`: New `reg_rd_pc_adjust()` returns `pc + (t ? 4 : 8)` for r15 reads. Used at BX/BLX register (line 453, 458) and shift-register DP (lines 286, 291, 295, 760). Thumb ALU PC reads: `(pc + 4U)` without spurious `& ~3U` (lines 262, 270). A32 STR-PC: `stv = (rt == 15U) ? pc + 8U : ctx->regs[rt]` (line 803). **Missing**: `interp_vfp.c:454` VLDR literal base still uses `(pc + 8U)` unconditionally — wrong for Thumb mode where it should be `Align(pc + 4, 4)`.

#### A32-R7-19 — Logical flag ops clear V — **VERIFIED**
`interp_a32.c:323-336`: Logical opcodes (0x0, 0x1, 0x8, 0x9, 0xC-0xF) preserve existing V via `ov = (ctx->cpsr & A32_CPSR_V) != 0U`. Arithmetic opcodes keep their computed overflow.

#### A32-R7-20 — MRS/MSR decoding — **VERIFIED**
`interp_a32.c:505-538`: MRS mask changed from `0x0FBFFFF0U` to `0x0FBF0FFFU` — Rd bits excluded. MSR unified mask `0x0DB0FF00U` captures both register and immediate forms (bit 25 excluded); `field = (insn >> 16) & 0xFU` selects NZCVQ (bit 19), GE (bit 18) independently.

#### A32-R7-21 — Thumb LDM loads Rn from wrong position — **VERIFIED**
`interp_thumb.c:458-483`: New `rn_val` temporary captures Rn's value from its actual list position. Final assignment: `ctx->regs[rn] = rn_val` instead of re-loading from the last word. Writeback suppressed when Rn is in the list.

#### A32-R7-22 — BKPT skipped / wrong PC — **VERIFIED**
`interp_thumb.c:48-53`: Thumb BKPT moved before IT condition gating, making it unconditional. Returns `A32_EXIT_BKPT` without advancing PC. `interp_a32.c:422-426`: ARM BKPT sets `ctx->regs[15] = pc` (was `pc + 4U`).

#### A32-R7-23 — Thumb NOP raises UNDEF — **VERIFIED**
`interp_thumb.c:69-72`: `hw == 0xBF00U` decoded separately as NOP — advances PC to `next`, falls through to `adv_it`. Removed from the UNDEF condition.

#### A32-R7-24 — NEON FP inherits scalar controls — **PARTIAL**
No changes to NEON FP environment isolation. The audit references `interp_neon_alu.c`, `interp_neon_mem.c`, and `trampoline.S` — none modified by this commit. The new `interp_vfp_neon.c` contains only integer NEON (VADD/VSUB/bitwise/VMOV-imm/VREV/VLDn). No FPCR save/restore around NEON FP operations is present.

#### A32-R7-25 — Scalar FP ignores FPSCR.FZ/DN — **VERIFIED**
`interp_vfp.c:25-102`: `vfp_fz()`, `vfp_dn()`, `vfp_fz_in_f/d()`, `vfp_fz_out_f/d()`, `vfp_dn_f/d()` helpers added. Input subnormals flushed to signed zero with IDC accumulation. Output subnormals flushed. DN produces canonical quiet NaN. Applied throughout: arithmetic (lines 763-810), VSQRT (lines 597-607), conversions (lines 657-689), VCVT-to-int (lines 689-694).

#### A32-R7-26 — VMOV immediate silently zeros — **PARTIAL**
`interp_vfp_neon.c:51-77`: Code moved verbatim from `interp_vfp.c`. Only cmodes `{0,2,4,6}` (even <8, 32-bit shifted) and `{0xE/op=0, 0xE/op=1}` are handled. **Missing**: cmodes 1,3,5,7 (VORR/VBIC immediates), 8-11 (16-bit shifted), 12-13 (shift-ones), 0xF/op=0 (F32 immediate). Unhandled cmodes still write `val64 = 0ULL` — the original bug.

#### A32-R7-27 — VFP halfword lane moves — **VERIFIED**
`interp_vfp.c:260-395`: Full byte/halfword/signed lane decode added for `vfp_mcr_mrc`. Load paths: U8 (opc1 6/7), U16 (opc1 4/5), S8 (opc1 2/3), S16 (opc1 0/1 w/ opc2≠0) with correct lane indexing. Store paths: byte (opc1 2/3) and halfword (opc1 0/1 w/ opc2≠0) via mask-and-insert.

#### A32-R7-28 — VREV64.16 byte reversal — **PARTIAL**
`interp_vfp_neon.c:79-101`: Code moved verbatim. For `size==1` (`.16`), each halfword is position-reversed AND byte-swapped via `__builtin_bswap16`. The bswap is spurious: VREV64.16 should only reverse halfword positions within the 64-bit element. Input `0x1122334455667788` produces `0x8877665544332211` instead of correct `0x7788556633441122`.

#### A32-R7-29 — Fused/non-fused MAC identical — **VERIFIED**
`interp_vfp.c:25-18`: `#pragma STDC FP_CONTRACT OFF` prevents compiler contraction. `interp_vfp.c:744-810`: `bool fused = (opc1 & 8U) != 0U` distinguishes VFMA/VFMS (fused) from VMLA/VMLS (non-fused). Fused paths use `fma()`/`fmaf()`; non-fused use separately-rounded `d + a * b`.

#### A32-R7-30 — VCMP misses sNaN IOC — **VERIFIED**
`interp_vfp.c:87-102`: `vfp_snan_f/d()` classify signaling NaNs from mantissa top bit. `interp_vfp.c:619-637`: VCMP NaN path: `if (n_bit || vfp_snan_d(a) || vfp_snan_d(b))` — IOC set for VCMPE (all NaNs) and for VCMP (signaling NaNs only).

#### A32-R7-31 — 16-bit VCVT saturation missing IOC — **VERIFIED**
`interp_vfp_core.c:8-19`: New `vfp_sat_set_ioc()` conditionally ORs `FPSCR.IOC` using `CSEL` based on the saturation comparison condition. Applied at lines 431, 436 (unsigned), 437, 440 (signed high/low bounds).

#### A32-R7-32 — C undefined behavior — **VERIFIED**
`interp_a32.c:253-268`: SMLAL accumulator in `uint64_t full = acc + (uint64_t)prod`. `interp_a32.c:770`: Post-index writeback: `u ? base + off : base - off` (unsigned). `interp_a32_ctl.c:288,335,659`: Branch shifts `((uint32_t)imm24 << 2)` — parenthesized cast before shift. `interp_t16.c:478`: `((uint32_t)imm11 << 1)`.

---

### Summary Table

| Item | Severity | Verdict | Notes |
|---|---|---|---|
| R7-1 | HIGH | **VERIFIED** | |
| R7-2 | HIGH | **VERIFIED** | |
| R7-3 | HIGH | **VERIFIED** | |
| R7-4 | HIGH | **VERIFIED** | |
| R7-5 | HIGH | **VERIFIED** | |
| R7-6 | MEDIUM | **PARTIAL** | VFP VLDR/VSTR lacks alignment checks |
| R7-7 | HIGH | **VERIFIED** | |
| R7-8 | MEDIUM | **VERIFIED** | |
| R7-9 | MEDIUM | **VERIFIED** | |
| R7-10 | MEDIUM | **VERIFIED** | |
| R7-11 | HIGH | **VERIFIED** | |
| R7-12 | HIGH | **VERIFIED** | |
| R7-13 | HIGH | **VERIFIED** | |
| R7-14 | HIGH | **VERIFIED** | |
| R7-15 | HIGH | **VERIFIED** | |
| R7-16 | HIGH | **VERIFIED** | |
| R7-17 | HIGH | **VERIFIED** | |
| R7-18 | MEDIUM | **PARTIAL** | VLDR literal in Thumb still uses pc+8 |
| R7-19 | MEDIUM | **VERIFIED** | |
| R7-20 | MEDIUM | **VERIFIED** | |
| R7-21 | MEDIUM | **VERIFIED** | |
| R7-22 | MEDIUM | **VERIFIED** | |
| R7-23 | MEDIUM | **VERIFIED** | |
| R7-24 | HIGH | **PARTIAL** | NEON FP control isolation not addressed |
| R7-25 | MEDIUM | **VERIFIED** | |
| R7-26 | MEDIUM | **PARTIAL** | Unhandled cmodes still zero destination |
| R7-27 | MEDIUM | **VERIFIED** | |
| R7-28 | MEDIUM | **PARTIAL** | VREV64.16 still applies spurious bswap16 |
| R7-29 | MEDIUM | **VERIFIED** | |
| R7-30 | MEDIUM | **VERIFIED** | |
| R7-31 | MEDIUM | **VERIFIED** | |
| R7-32 | MEDIUM | **VERIFIED** | |

**Totals**: 27 VERIFIED, 5 PARTIAL, 0 REGRESSION.

### Newly Introduced Concerns

1. **SWP non-atomic composite** (`interp_a32.c:636-643`): The interpreter SWP uses separate `__atomic_load_n` + `__atomic_store_n` instead of `__atomic_exchange_n`. A concurrent write between load and store is silently lost. The JIT path (`interp_a32_dp.c`) correctly uses LDXR/STXR in a loop. Low practical risk since SWP is deprecated and rare, but semantically incorrect for multi-threaded guests.

2. **Thumb BKPT doesn't set regs[15]** (`interp_thumb.c:48-53`): Unlike the ARM BKPT handler which explicitly sets `ctx->regs[15] = pc`, the Thumb handler returns without touching `regs[15]`. Correctness depends on the invariant that `regs[15]` already holds the current instruction PC on entry — true in normal flow but fragile if the caller convention changes.
