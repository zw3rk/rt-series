# Review: `docs/PERF-PLAN-P13.md` (Wave P13) — `fable` (`claude-fable-5-1`)

**Lane P13-1 critique**

**CRITICAL**
- **A4 `d24..d31` clobber by C helpers.** `v16..v31` are caller-saved in AAPCS64; gcc freely uses them in `ppc64_vm_tlb_miss` and any other helper. The "either/or" wording must become a hard requirement: `common` saves `q24..q31` (4× `stp`/`ldp`, `SP_FRAME` += 64), and *every* other `blr` to C (syscall, D2, `divd` trap) flushes via `e_flush_fpr_cache`. Same for `ppc32rt` B2: `d16..d23` are dead across `vm_smc_invalidate_page`, align/perm fault stubs. Flush before those calls.
- **B1 `stfs`/`stfiwx` are not transparent.** `FCVT Sd, Dn` sets `IXC/OFC/UFC` in host `FPSR`, polluting the open batch's sticky accumulation. Exclude `stfs*` (and any `frsp`-style narrowing) from the lookahead whitelist, or emit them with `FPSR` save/restore.

**HIGH**
- **A1 SMC-retire `+4` is wrong for update forms.** `stdu/stwu/stfdu` write `rA` after the store; retiring at `pc+4` from `common` skips the update if the GPR write is emitted after the store site. Either emit the `rA` update before the store or encode an `is_update` bit in `ppc64_mem_site_t` and let `tlb_miss` apply it.
- **A1 async/host faults.** Non-TLB faults (host `SIGBUS` on a mapped page, async signals) still see stale `ctx->nip`. Keep a per-block site table so the signal handler recovers `nip` from the faulting host PC.
- **A2 `ra == 0` encodes `x0`, not `XZR`.** `e_add_imm(e, 1, 13, 0, si)` uses `rn = 0`. Use `31` for the zero register.
- **A3 `w17` budget is not safe.** `x16/x17` are clobbered by *any* C call and PLT veneers, not just `common`. Save them in every helper trampoline, or reload budget from `[sp,#96]` after helper returns only (still removes the IBTC hot-path spills).

**MEDIUM**
- **A2 `RLDIC` all-ones mask.** `rldic rd,rs,0,0` yields `~0ULL`, not logical-imm encodable; fall back to `MOV`. Preserve `rc=1` CR0 compare on every fast path.
- **A1 `uint16_t guest_pc_delta`.** If bytes, cap block length at 64 KiB in the translator, or assert.
- **B1 mid-batch fault drops uncommitted `FPSCR` sticky bits.** Commit `FPSR` to `FPSCR` in the cold fault stub, or document the imprecision.
- **A3** dropping `x29` breaks frame-pointer unwinding in `perf`; accept, but gate under a flag.

**Lane P13-2 critique**

- **CRITICAL — `d24..d31` are caller-saved under AAPCS64.** Patching the Soft-TLB miss stub only protects one call site. Every other `blr` to a C helper (FTINT/FCVT helpers, FCSR trap, syscall, signal exit) clobbers the cache silently. Fix: use `d8..d15` instead. AAPCS64 preserves the low 64 bits of `v8..v15`, which is exactly a scalar double, so no stub frame change is needed. Verify `safe_syscall_a64.S` and the dispatcher never touch `v8..v15`.

- **CRITICAL — `.S`-then-`.D` aliasing is wrong under the proposed `fpr_is_single` scheme.** After an `.S` write, the cached slot's upper 32 bits are zero, but the guest's `vr[fd].w[1]` is the old value. A later `.D` read of the same register returns garbage. Fix: drop `fpr_is_single`. On an `.S` write to a slot that is not already 64-bit-valid, fill with `LDR Dslot, [x19, #off]` then merge via `INS Vslot.S[0], Vtmp.S[0]`. The slot then always holds the full 64-bit value and flush is always `STR Dslot`.

- **HIGH — FPCR state machine is underspecified.** Two booleans (`fpcr_checked`, `fpcr_dirty`) cannot express "block is in dynamic mode, this op is fixed-RZ, next op must return to dynamic." The plan's "restore to `xzr`" after a fixed op silently downgrades the rest of the block to RN. Fix: one `enum { FPCR_DEFAULT, FPCR_DYN, FPCR_FIXED }` plus the fixed mode value; transitions emit `msr fpcr` only on change; `FPCR_FIXED -> FPCR_DYN` reloads from the hoisted FCSR copy, not from zero.

- **HIGH — invalidation on FCSR writes.** `MOVGR2FCSR` and the FCSR trap helper mutate guest rounding mode mid-block. The hoisted FPCR must be re-derived (`state = FPCR_DEFAULT` after `fpcr_restore`) at those points, not just at block exit.

- **MEDIUM — whole-cache flush before every LSX op** defeats the cache in mixed scalar/vector loops. Flush and invalidate only the slot aliasing the LSX operand registers.

- **MEDIUM — round-robin eviction** thrashes with more than eight live FPRs. Prefer evicting clean slots first, then oldest dirty.

- **MEDIUM — host runs helpers and signal handlers with non-RN FPCR** while `FPCR_DYN` is live. Flush FPCR before any `blr`, and document that async signal delivery inherits the guest rounding mode.

**Lane P13-3 critique**

- **CRITICAL — `fmov s(16+slot), wN` zeroes bits 32..127.** Caching a `.D` pair in `d(16+slot)` and then writing a single to the same slot destroys the odd half (FR=0 pairs). Fix: write halves with `ins v(16+slot).s[0|1], wN`, read with `umov wN, v(16+slot).s[1]`, and key slots by `reg & ~1u` only. Make `fpr_cache_is_d` a per-slot bitmask or drop it and always cache pairs.

- **CRITICAL — `msr fpcr, xzr` on every block return is the wrong place.** It costs a serializing system write per exit and still misses the real hole: a SIGSEGV/SIGBUS inside an open batch leaves host FPCR *and* FPSR unsynced when `interp_step` or the handler reads `ctx->fcsr`. Fix: in the fault handler, take `fpsr`/`fpcr` from `fpsimd_context`, fold them via a C `fp_finish_op` equivalent, and zero `fpcr` in the saved context. Keep the trampoline hot path untouched.

- **HIGH — lazy FPR dirty state is invisible to the fault path.** `LDC1`/`SDC1`/`LWC1` can fault mid-block; the handler must spill `d16..d23` into `ctx->fpr[]` or guest state is lost. Fix: extend the P12 GPR fault-time spill map with `fpr_slot_reg[]`/`fpr_dirty`, keyed by exit PC, for both translators.

- **HIGH — `d16..d23` are caller-saved.** Saving them only in the mips64rt Soft-TLB miss stub misses every other C call-out (syscall, `EXIT_UNDEF`→`interp_step`, FCSR helpers). Fix: either route all call-outs through one `call_c_fp_save` macro, or use callee-saved `d8..d15` and save once at trampoline entry/exit. With chaining, entry/exit is rare, so prefer `d8..d15`.

- **HIGH — lookahead barrier set is incomplete.** `EXIT_UNDEF` fallback, `CVT.*`, `C.cond` (writes FCSR), and anything consulting `fcsr` must terminate deferral. Fix: whitelist (FP arith, FP load/store, non-faulting ALU) instead of blacklisting.

- **MEDIUM — no measurement.** "~45 instructions per `MADD.D`" is a code read, not a profile. Fix: add a default-off `fp_finish_op` exit counter, measure a Linpack-style MIPS run before and after, and record both numbers in `docs/PERF-PLAN-P13.md`.

- **MEDIUM — `ABS`/`MOV`/`NEG` early return.** Fix is correct but should also handle `fp_defer_finish == 1` by simply leaving the batch open; add a regression where `MOV.D` is the last instruction before a `CFC1`.

**Lane P13-4 critique**

- **CRITICAL, item 3: icc bit order is wrong.** AArch64 NZCV is N,Z,C,V in bits 31..28. SPARC PSR icc is N,Z,V,C in bits 23..20. The proposed `LSR w9, w9, #8` and the 4-instruction `LSL #8 ; MSR NZCV` restore both swap C and V. Fix: keep a host-order shadow `ctx->icc_nzcv` and convert only in `RDPSR`/`WRPSR`:
  ```
  mrs  x9, nzcv
  eor  w9, w9, #(1u << 29)      ; SUBcc only
  str  w9, [x19, #icc_nzcv]     ; commit, 2-3 insns
  ldr  w9, [x19, #icc_nzcv] ; msr nzcv, x9   ; restore, 2 insns
  ```

- **CRITICAL, item 4: `d16..d23` are caller-saved.** Every C helper call (`sparc32_rt_store`, `sparc32_rt_window`, D2 fallback) clobbers them. Use `d8..d15`, whose low 64 bits are callee-saved, and add `stp d8..d15` save/restore to `trampoline_a64.S`.

- **CRITICAL, item 1: window rotate must clear dirty bits, not just valid bits.** Invalidating `gpr_cache_valid` while leaving `gpr_cache_dirty` set lets the next flush write old-window values into new-window slots. Fix: `b->gpr_cache_valid &= GLOBAL_MASK; b->gpr_cache_dirty &= GLOBAL_MASK;` for slots with `reg >= 8`.

- **HIGH, item 3: delay slots.** SPARC evaluates the Bicc condition before the delay-slot instruction executes, but the delay slot may itself be a `cc` op. With live NZCV, either emit the conditional branch before the delay slot and duplicate the slot on both edges, or snapshot with `cset w9, cond` before emitting the slot and branch on `cbnz w9`.

- **HIGH, item 2: bit 3 invariant has many writers.** `mmap`, `mprotect`, `munmap`, `vm_mark_code_page`, `vm_smc_invalidate_page`, and signal-stack setup all touch `g_vm32_prot`/`g_vm32_state`. One missed site silently skips SMC invalidation. Fix: a single `vm32_set_page(vpn, prot, state)` that recomputes bit 3, with all direct array writes removed.

- **HIGH, item 4: double word order.** SPARC `f[2n]` is the high word. A native `str d8, [x19, #f + 8n]` stores the low word first. Either flush via `fmov x9, d8 ; ror x9, x9, #32 ; str x9` or index singles as `f[i ^ 1]` in both DBT and interpreter.

- **MEDIUM, item 2:** materialize `x25` once in the trampoline entry instead of per block. `g_vm32_prot` is a fixed address, so `prot_base_valid` is unnecessary.

- **MEDIUM, item 4:** set `FPCR.DN` in the trampoline. AArch64 default NaN equals the SPARC canonical QNaN, so `fp_canon` can be deleted entirely rather than reduced to 2 instructions.

- **MEDIUM, item 1:** if `sparc32_rt_window` also updates `PSR.CWP` bits, the fast path must mirror that write, or `RDPSR` reads a stale CWP.

Architectural critique of Lane P13-5 (`sparc64rt`), ordered by severity.

- **CRITICAL: `stp x7, x8, [sp, #-16]!` in `mem_emit_common` is unbalanced on the fault path.** `sparc64_mem_miss` can deliver `SIGSEGV`/`SIGBUS` and exit the block instead of returning to `cont_insn_offset`. The 16 bytes then leak every fault, and the dispatcher's `sp` drifts. Fix: make the exit stub reset `sp` from the saved dispatcher frame (`mov sp, x_frame`), or pop in the fault branch before `b exit_stub`. Same for any `d16..d23` save.

- **HIGH: `d16..d23` are caller-saved under AAPCS64.** Saving them only in `mem_emit_common` leaves every other C call-out (`fp_sync_fsr`, syscall, trap, `sparc64_fast_win` spill path) free to clobber them silently. Fix: use `d8..d15` (callee-saved), save once in `sparc64_dbt_enter`, and keep the FPR cache write-through like the GPR cache so helpers reading `ctx->f[]` see current values. Delete the `mem_emit_common` FP frame.

- **HIGH: the 4-instruction `e_nib_to_flags` fallback is wrong.** CCR nibble is `n z v c` (bits 3..0); host NZCV is `N Z C V` (bits 31..28). `LSL #28` swaps C and V. Fix: a 16-entry `nzcv_tab[]` in `sparc64_cpu_t`:
  ```
  LDRB w9, [x19, #ccr]; UBFX w9, w9, #(use_xcc?4:0), #4
  ADD x10, x19, #tab_off; LDR w9, [x10, w9, uxtw #2]; MSR NZCV, x9
  ```
  Drop the `EOR #(1<<29)`: stored CCR holds guest C, no inversion.

- **HIGH: `nzcv_state` has no clobber tracking.** The Soft-TLB probe (`cmp`), `fp_nan_check` (`fcmp`), `CASA`, and `mem_emit_common` all write host NZCV between a `SUBcc` and its `BPcc`. Fix: add `e_nzcv_clobber(b)` (sets `nzcv_state = 0`) and call it from every emitter that emits a flag-setting A64 op; reset at block entry. For `SUBcc` (bit 2 set) swap `CS/CC` and `HI/LS` in `e_cond_to_a64`, not just `CC/CS`.

- **MEDIUM: `e_emit_delay` and `SAVE`/`RESTORE` interact.** Keeping the cache live into a delay slot that is `RESTORE` or `SAVE` rotates windows under cached `%o`/`%i` slots. Fix: `sparc64_fast_win` must mask `reg >= 8` slots even when invoked from the delay slot.

- **MEDIUM: `ADD x, x19, #off` is imm12-bounded (4095).** Check `offsetof(win_file) - offsetof(ctx)`; fall back to `ADD ... lsl #12` plus `ADD` if larger.

- **MEDIUM: `fp_nan_check` shortcut must gate on `FSR.TEM == 0`.** With traps enabled the deferred `fp_sync_fsr` misses the trap point.

- **MEDIUM: nit.** The "9-instruction" `e_emit_logiccc` sequence lists 12 instructions.

**Lane P13-6 critique**

**rvrt: lazy FLW/FLD writeback**

- **CRITICAL: NaN-box lost in register.** `FMOV s(16+f), w3` leaves bits 32..63 zero. A later `FSD`/`FMV.X.D`/`FEQ.D` of that slot reads the *register*, not the flushed box. Fix: box before the move, one instruction, no store:
  ```c
  /* ORR x3, x3, #0xFFFFFFFF00000000 */
  a64_emit(b->buf, 0xB26083E3u);
  a64_fmov_d_x(b->buf, 16u + fslot, 3);   /* then drop fpr_cache_box */
  ```
- **CRITICAL: dirty state across the cold miss.** `rv_dbt_mem_helper` may fault (SIGSEGV/SIGBUS to guest) and the signal path reads `ctx->f[]`. Flush all dirty slots in the miss stub *before* the helper, and set `valid/dirty` only at the join point. On miss, reload `d(16+fslot)` and mark it valid-clean, never dirty.
- **HIGH: slot eviction in `emit_inline_store`.** `dbt_fpr_slot(b, rs2, true)` can evict a dirty slot inside the TLB-check sequence, clobbering `x2`/`x3`. Allocate and flush before the TLB probe; read `FMOV x2, d(16+f)` only after the slot is stable.
- **MEDIUM:** `FSW` of a slot loaded by `FLD` must still store low 32 bits; `FMOV w2, s` is correct, but assert `fpr_cache_valid` covers it on the miss branch too.

**i686rt: XMM in v16..v23**

- **CRITICAL: v16..v23 are caller-saved (AAPCS64).** Every C call (`sse_flags_sync`, syscall, helper, signal delivery) destroys them. Invalidate `xmm_valid` and flush `xmm_dirty` before *every* call site and in the fault trampoline; otherwise `ctx->xmm[]` is stale when the signal handler runs.
- **HIGH: wrong INS encodings.** `0x4E041C00`/`0x4E081C00` are `INS Vd.S[0], Wn` (GPR source). The element form is:
  ```c
  0x6E040400u | (0u << 5) | (16u + reg)  /* INS Vd.S[0], V0.S[0] */
  0x6E080400u | (0u << 5) | (16u + reg)  /* INS Vd.D[0], V0.D[0] */
  ```
- **HIGH: direct `ctx->xmm[]` readers.** `FXSAVE/FXRSTOR`, `MOVD/MOVQ` GPR paths, and any `emit_fpu.c` code touching `0x108+reg*16` bypass the cache. Route them through `i686_xmm_reg()` or flush first.
- **MEDIUM:** `MOVQ xmm,xmm` zeroes bits 64..127; must write `d(16+reg)`, not `INS .d[0]`. Split `emit_sse2.c` before adding code, not after.

