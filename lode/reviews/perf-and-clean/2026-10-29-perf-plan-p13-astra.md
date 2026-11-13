**P13 should not proceed as written.** It contains incorrect instruction substitutions, incomplete fault-state contracts, and stale assumptions about the live `rvrt` and `i686rt` implementations.

Verification limit: I used exactly three shell commands, without subagents. One failed because heredocs required a temporary file; the final read succeeded but its output was truncated. Consequently, this is **not a complete source-verified sign-off**. Below, concrete defects in the proposed sequences are distinguished from correctness obligations that remain unverified. No builds, differential tests, or benchmarks ran.

**Lane P13-1 — `ppc64rt` + `ppc32rt`**

- **CRITICAL — Removing `e_set_nip` requires a precise-state recovery contract, not just assigning `nip` on helper return.** The [proposal](/Users/angerman/Projects/zw3rk/rt-series/docs/PERF-PLAN-P13.md:31) changes normal loads/stores, atomics, FP pairs, and VSX memory operations together. Setting `nip` in `ppc64_vm_tlb_miss` covers only exits through that helper. It does not establish recovery for a host fault on the inline access, another atomic/helper path, or an observer reached inside the miss helper before its final return. Saving dirty GPR/FPR host registers on the stack also does **not** materialize architectural `ctx` state.

  **Fix:** classify each memory path separately. At every observable fault exit, reconstruct the faulting PC and commit the pre-instruction dirty-register snapshot. On a successfully completed SMC store, commit its architectural effects and use the following PC. Keep existing PC stores for paths without this recovery mechanism. Audit update-form base-register writes and multi-access FP/vector operations for partial completion. Blanket removal is unjustified by the plan.

- **HIGH — The proposed `RLWINM` → `srwi` encoding is wrong.** [Line 48](/Users/angerman/Projects/zw3rk/rt-series/docs/PERF-PLAN-P13.md:48) recognizes `mb == 32 - sh`, but emits `LSR #sh`. For example, `sh=24, mb=8, me=31` implements a right shift by **8**, not 24.

  **Fix:** emit `LSR #(32-sh)` for that recognized case. Handle `sh=0` separately. Full-width masks also need a move/rotate special case because an all-ones A64 logical immediate is unavailable. Keep the existing wrapped-mask semantics, including any required replicated-word behavior. For every fast path, retain the `rc=1` CR0 update, including XER.SO; the advertised “one/two instructions” excludes this architectural work. `RLWNM`, `RLWIMI`, and `RLDIMI` need separate variable-count and insertion proofs; the heading does not supply them.

- **HIGH — The immediate-EA proposal confuses architectural zero with host register zero.** [Line 64](/Users/angerman/Projects/zw3rk/rt-series/docs/PERF-PLAN-P13.md:64) uses `ba = 0` for guest `RA=0`. As an emitted register number, that means **x0**, not a zero value.

  **Fix:** materialize the signed displacement directly for `RA=0`; otherwise use ADD/SUB immediate on the mapped base. Do not substitute register 31 blindly: ADD-immediate interprets that operand as SP.

- **CRITICAL — Frameless blocks require preserving LR and chaining registers at every call site.** Saving `x16/x17/x29/x30` only in `common` does not establish the proposed private ABI. `x16`, `x17`, and `x30` cannot remain live across arbitrary C calls. Any `divdo`, system, fallback, or other helper call can invalidate the scheme.

  **Fix:** retain frames until every emitted `BL`/`BLR` and helper tail exit has been audited. Either provide a common call wrapper preserving the private live-register set, or make only proven leaf blocks frameless. Include the new FPR save area when recalculating frame size and keep SP 16-byte aligned.

- **HIGH — Scalar FPR caching must implement bidirectional VSX coherence.** Flushing before a full-width VSX read is necessary; invalidating scalar aliases after a VSX write is equally necessary. The same rule applies to scalar VSX operations that overlap FPR storage.

  **Fix:** route accesses through alias-aware read/write barriers. Preserve the untouched VSR portion on scalar writes. Flush architectural state before observing helpers and fault exits; preserving `d24..d31` across C calls alone is insufficient.

- **HIGH — PPC32 lookahead cannot treat faulting loads/stores as unconditionally transparent.** An intervening fault can expose pending FPSCR exceptions and the preceding arithmetic result’s FPRF/FR/FI. Merely restoring host FPCR does not recover those guest fields. `stfs` also requires scrutiny because conversion can affect host FP status. SMC helper calls introduce another preservation boundary.

  **Fix:** initially stop batching at memory/helper boundaries. Extend it only with explicit pending-FPSCR state and cold-exit materialization. For `lfd`, invalidate/replace a cache entry only after a successful load; for `stfd`, read the dirty cached value. Elide the second SMC-page check only when the access is proven not to cross a page, including address wrap.

**Lane P13-2 — `loongarch64rt`**

- **HIGH — `fpcr_checked` must represent current execution state, not an earlier check.** The plan itself describes restoring FPCR while retaining `fpcr_checked=1`. That permits subsequent operations to skip guest rounding setup.

  **Fix:** the conservative repair is to clear the checked/active state whenever restoring FPCR. True hoisting needs an explicit active region: enter once, restore on every outgoing edge, and terminate/reestablish the region around FCSR changes and helpers. At conditional joins, retain “active” only when every predecessor establishes the same state. A translation-time Boolean alone cannot represent divergent runtime paths.

- **HIGH — `.S`, `.D`, and LSX need one alias contract.** A scalar `.S` write to an A64 SIMD register does not automatically produce the guest’s required 64-bit boxed representation. A dirty scalar cache can also make an LSX read stale, while an LSX write can leave a cached scalar stale.

  **Fix:** track scalar width/boxing explicitly. Flush before aliased vector reads and invalidate after vector writes; preserve unaffected vector bits. Save/restore `d24..d31` in `common`, and separately commit dirty values before any fault/helper path that observes `ctx`. Verify FPCR restoration on unsuccessful memory operations and block exits. These paths remain unqualified by the available source evidence.

**Lane P13-3 — `mips32rt` + `mips64rt`**

- **HIGH — Extending `fp_batch_is_any` does not fix early-return paths.** If `ABS`/`MOV`/`NEG` bypass the batch-finalization logic, making them transparent can leave FPCR active or exceptions uncommitted when translation ends, control transfers, or the next memory operation faults.

  **Fix:** make batch termination independent of individual arithmetic emitters’ return paths. Keep a batch open only across instructions proven safe, and emit finalization on every exit. Do not broaden both lookahead and lazy writeback without first establishing this invariant.

- **CRITICAL — Double caching must respect the guest FPR storage mode.** In a paired 32-bit register model, a double cache entry aliases two single registers. A single write to either half must preserve the other half and invalidate/update the double entry. A single read must see the corresponding half of a dirty cached double. Conversely, do not impose paired-register semantics on a 64-bit FPR mode where adjacent registers are independent.

  **Fix:** derive aliasing from each runtime’s supported FPR mode and existing load/store helpers. Apply barriers to **all** `MTC1`, `MFC1`, `DMTC1`, `DMFC1`, `LWC1`, `SWC1`, `LDC1`, and `SDC1` paths, including endian-sensitive half selection. Eviction must write back the old architectural owner before changing its tag.

- **HIGH — `mips64rt` miss stubs must preserve caller-saved cached FPRs.** `d16..d23` are not protected by ordinary C calling conventions.

  **Fix:** save/restore all live cache registers around the Soft-TLB helper, or flush and reload them with consistent metadata. On fault exits, materialize dirty architectural state rather than merely restoring host registers. Include delayed-branch fault PC/state in targeted regressions.

**Lane P13-4 — `sparc32rt`**

- **HIGH — Inline window rotation needs the exact existing window-state machine.** `%g0..%g7` do not rotate; `%o/%l/%i` do. Computing `rs1 + operand2` after rotating changes the meaning of a windowed source, especially when `rs1 == rd`.

  **Fix:** snapshot the arithmetic operands before rotation; check the target window’s availability; flush dirty old-window registers before changing its identity; rotate/update metadata; then write `rd` in the new window. Preserve cached globals only if the emitted scratch-register allocation also preserves their host registers. Derive `cwp`, `wim`, and any `canrestore` transitions from the existing helper rather than borrowing SPARC64 rules. Exact equivalence remains unverified here.

- **HIGH — `VM32_PROT_FAST_WRITE` must be a maintained invariant.** A stale writable fast bit after code marking bypasses SMC handling.

  **Fix:** define bit 3 from the complete fast-store eligibility predicate and centralize recomputation. Audit `vm32_protect`, `vm_mark_code_page`, `vm_smc_invalidate_page`, and `vm32_reset`, plus mapping replacement/unmapping and any additional eligibility restrictions. Clear the bit whenever a required condition disappears. Code invalidation does not automatically mean a page can permanently stop being tracked as code.

- **CRITICAL — Live flags need operation-dependent condition mapping.** For subtraction, A64 C represents **no borrow**, opposite SPARC’s borrow flag. For addition, carry agrees. Logic operations clear guest C and V.

  The required mapping is:

  | SPARC condition | SUBcc host flags | ADDcc host flags |
  |---|---|---|
  | BN / BA | never / always | never / always |
  | BE / BNE | EQ / NE | EQ / NE |
  | BLE / BG | LE / GT | LE / GT |
  | BL / BGE | LT / GE | LT / GE |
  | BLEU | LS | `CS OR EQ` |
  | BGU | HI | `CC AND NE` |
  | BCS / BCC | CC / CS | CS / CC |
  | BNEG / BPOS | MI / PL | MI / PL |
  | BVS / BVC | VS / VC | VS / VC |

  For logic, simplify using `C=V=0`: BLEU becomes EQ, BGU becomes NE, BCS/BVS never, BCC/BVC always.

  **Fix:** track flag origin and invalidate liveness on every emitted flag writer: permission/alignment checks, TLB comparisons, FP comparisons, SMC paths, helper calls, and arithmetic scratch operations. Test the branch condition before a delay-slot instruction can overwrite flags.

- **HIGH — Double-cache aliasing and NaN optimization need separate proofs.** `f0..f31` single accesses overlap cached doubles.

  **Fix:** flush the aliased pair before a single read; flush then invalidate/update before a single write. Preserve guest word order. A result-only NaN check can select canonical NaN for operations whose NaN behavior is established, but does not by itself preserve signaling-NaN exceptions or trap timing. Keep those semantics separate from result canonicalization.

**Lane P13-5 — `sparc64rt`**

- **HIGH — Cache preservation across memory operations needs a path-correct continuation.** Moving `cont_idx` before `e_set_gpr` is sound only if both predecessors provide the same architectural value in `ES0`.

  **Fix:** let the fast path complete sign extension and byte swapping before the join; let the miss path supply the helper’s already finalized result. Do not reapply transformations to only one predecessor. Treat pair loads and atomics separately. Invalidate destination slots using the actual register-to-slot mapping, not `rd & 7`. Save `x7/x8` before first clobber; account for their 16-byte save and the 64-byte `d16..d23` save in every stack-relative access and exit.

- **CRITICAL — The proposed four-instruction CCR reconstruction has the wrong bit ordering.** SPARC’s nibble is `N Z V C`; A64 NZCV is `N Z C V`. Shifting the nibble and XORing bit 29 does not swap C and V.

  **Fix:** explicitly permute the bits, then invert C only for the chosen normalized subtraction-style branch mapping. For a guest nibble `g`, that normalized host nibble is:
  ```c
  h = (g & 0xc) | ((g & 1) << 1) | ((g & 2) >> 1);
  h ^= 2;
  ```
  Emit `h << 28` into NZCV. Share the condition-origin rules from P13-4.

- **CRITICAL — Reordering the 32/64-bit flag passes requires immutable operands.** If the first pass writes the architectural destination or a host register aliasing a source, the second pass can use the first result when `rd == rs1` or `rd == rs2`.

  **Fix:** snapshot both full-width operands before either pass; compute each flags result from those snapshots; commit the architectural 64-bit result once afterward. Include both alias cases and `rs1 == rs2` in tests. Do not accept the proposed instruction count until scratch-register allocation is established.

- **HIGH — A single `ADD` cannot encode arbitrary `x19`-relative structure offsets.** ADD-immediate supports a 12-bit value, optionally shifted by 12; it does not cover every large offset.

  **Fix:** compute and validate each actual `offsetof` difference. Use one instruction only when encodable, otherwise high/low additions or a materialized offset. Exact offsets were not established by this inspection.

- **HIGH — Window spill/fill TLB access needs the runtime’s actual tag and permission format.** The proposed equality is not sufficient evidence that read/write permissions, invalid entries, or code-page restrictions are handled.

  **Fix:** reuse the authoritative TLB lookup predicate, table-size constant, and tag construction. Apply stack bias exactly once. Prove the full 128-byte range is in one eligible page; preserve big-endian conversion; retain the original checked path otherwise. Ensure direct stores cannot bypass SMC/COW handling. Use alias-safe accesses where the host backing’s C representation requires them.

- **HIGH — Deferred `fp_sync_fsr` needs precise trap boundaries.** Sticky host IOC supports eventual accumulation, but does not establish correct guest trap timing or state at intervening exits.

  **Fix:** defer only within regions with no observable boundary and compatible trap policy. Flush on faults, helpers, FSR reads/writes, and exits. Add single/double alias barriers to the proposed cache. The “9 instruction” logic sequence also lists **12 instructions**, so its cost claim needs correction.

**Lane P13-6 — `rvrt` + `i686rt`**

- **CRITICAL — The `rvrt` design targets stale cache interfaces and risks corrupting miss-path state.** The live [load implementation](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:316) uses **16 slots**, `rd & 15`, `uint16_t` masks, `fpr_cache_is_d`, and architectural storage addressed through **x21**. It does not match the proposed eight-bit masks, `fpr_cache_box`, or x19-relative register-file accesses.

  More seriously, the miss branch precedes the fast-path eviction/replacement, while [miss flushing](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:361) is emitted after translation metadata has been updated for the hit path. Marking the replacement dirty naïvely can make the miss flush write the **old runtime slot contents under the new guest-register identity**.

  **Fix:** preserve pre-instruction cache metadata for miss emission. Flush old dirty owners before the helper, retain pre-instruction destination state on failure, and establish identical post-load ownership/width state on successful hit and miss paths. Use the actual 16-slot interfaces.

- **HIGH — Direct `FSD` must account for cached single representations.** An A64 S-register write clears upper bits; a boxed guest single requires upper ones. A raw `FMOV x2,dN` can therefore store the wrong 64-bit representation.

  **Fix:** reconstruct boxing for `FSD` when the slot holds a single-format value; `FSW` uses the low word. The live [store miss path](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:418) already preserves the store value around FPR/FPSR flushing and passes it to a helper. Adapt that contract rather than assuming the helper necessarily rereads `ctx->f[rs2]`.

- **HIGH — XMM preservation across `sse_flags_sync` is mandatory.** The live [COMIS path](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:1373) explicitly recognizes caller-saved clobbering and loads operands after synchronization.

  **Fix:** flush dirty XMMs before the call and invalidate/reload afterward, or preserve full **Q** registers around helpers proven not to modify architectural XMM state. Saving only D registers loses upper halves. Do this at the actual SSE helper-call seam, not solely through a GPR-flush function that the seam may bypass.

- **HIGH — Scalar merge versus replacement must be explicit.** The proposed distinction is correct: scalar arithmetic/register moves preserve destination upper lanes; memory `MOVSS`/`MOVSD` replace and zero them.

  **Fix:** use separate full-write and partial-write APIs. Partial writes must first load the old destination, then insert the result lane. Full replacements can skip loading it. Include destination/source overlap, memory faults, and dirty XMM state at signal/fault recovery boundaries.

- **MEDIUM — The SSE size and interface assumptions are already stale.** The inspected [emit_sse.c](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:648) has **1,977 lines**, not 871, and uses `i686_emit_ctx_t`.

  **Fix:** plan the split against the current file and actual emitter context. Meeting a 900-line limit is already required work, not a conditional consequence of adding caching.

**Cross-lane acceptance — HIGH:** The plan labels source instruction counts as measured “root causes.” End-to-end timings do not establish that attribution, and fewer instructions need not reduce cycles when dependencies, register pressure, helper costs, or instruction-cache footprint change. Follow the repository’s instrument → measure → hypothesize sequence before claiming gains.

Smoke tests and four benchmark differentials are insufficient for these changes. Add focused checks for dirty-cache faults, forced TLB misses, SMC retirement, helper clobbers, register aliasing, all branch conditions, rounding modes, and signaling NaNs. Those checks should qualify the concrete risks above before full benchmark execution.