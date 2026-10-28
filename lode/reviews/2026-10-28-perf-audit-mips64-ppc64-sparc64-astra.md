**The next priorities are MIPS64’s remaining native FP overhead, PPC64’s per-block trampoline round trip and register traffic, and SPARC64’s window slow paths.** All three already have the intended scalar Soft-TLB probe shape; a general VM rewrite is a lower-priority candidate.

This was a read-only audit of `src/dbt/`, `src/vm/`, their recovery paths, and the benchmark binaries. The workload source in these checkouts is [tests/bench_suite.c](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:443); `tests/bench/rt_bench.c` was absent. I accounted for the changes underway and made no edits.

The stored Linux results establish workload priorities:

| Runtime | coremark | chacha20 | vfp_simd | calls_ibtc | syscalls | Total | QEMU total |
|---|---:|---:|---:|---:|---:|---:|---:|
| mips64rt | 7,145 | 2,685 | 174,496 | 9,836 | 2,184 | 196,346 | 42,470 |
| ppc64rt | 37,665 | 20,672 | 312,974 | 358,026 | 9,785 | 739,122 | 80,411 |
| sparc64rt | 13,167 | 5,434 | 41,887 | 335,211 | 804 | 396,503 | 69,242 |

All values are microseconds, from the [recorded results](/Users/angerman/Projects/zw3rk/rt-series/docs/SOFTWARE-CATALOGUE.md:211). They predate the pending changes. **They establish which workloads matter, but do not attribute time to individual mechanisms.** The recommendations below need phase measurements before their ordering or speedups can be confirmed.

**MIPS64: measure FP again immediately after the delay-slot change.**

FP accounts for **88.9%** of the recorded total. Capstone inspection of the existing guest binary found its benchmark FP opcodes already covered by the current emitters; two `ADD.D` delay slots match the work underway. There is no evidence here for another missing hot FP opcode.

- **Hoist repeated FCSR admission checks, then cache FPRs within blocks.** Each arithmetic instruction reloads operands, checks the same mode mask, checks its result, and stores the destination. The insertion points are [ef_fill/ef_spill](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:220), [ef_mode_guard](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:243), and [ef_arith](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:353). Check eligibility once per uninterrupted FP region; invalidate that proof at FCSR writes, helpers, fallback and context boundaries. Retain per-operation exceptional-result handling. Start FPR caching through the existing accessors, preserving FR=1’s untouched upper half on single-precision writes. Keep destinations tentative until guards pass.

- **Add block-local GPR caching and two small instruction-selection improvements.** [ei_gld/ei_gst](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:44) accesses context memory for every nonzero register read/write. A small cache over register-only spans targets ChaCha and CoreMark without requiring a cross-block allocation ABI. Separately, [ROTR lowering](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_alu.c:49) materializes a constant then uses `RORV`; use immediate `ROR`, preserving MIPS word-result sign extension. [Effective-address generation](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:119) materializes every signed displacement; use `ADD/SUB` immediate where encodable.

  Dirty caching requires explicit recovery support: [memory recovery](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:434) reconstructs operands from `ctx`. Initially flush before faultable operations, helpers, guards and exits; otherwise faults can observe stale guest state.

- **Preserve supported prefixes when a later instruction declines—but first check whether declines remain hot.** [dbt_emit_int](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:643) discards the whole prefix on an unsupported branch/slot; ordinary instruction refusal does likewise. [compile_decline](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:398) then caches only one interpreted instruction. Checkpoint emission and memory-site state, retain a nonempty supported prefix, and exit at the declining instruction. For unsupported delay slots, terminate **before the branch**. This is a confirmed structural amplification mechanism, but its remaining benchmark exposure after the FP fix is unmeasured.

- **For `syscalls`, measure empty file-reconciliation work.** [mips_vm_file_reconcile](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:658) calls `getpid`, locks and scans the inode table; it runs from syscall and memory-recovery paths. A synchronized “no nonnative tracked mappings” guard or family-change epoch could avoid unnecessary scans. Do not gate this solely on shared mappings: private clean mappings also need reconciliation after file changes. This is lower priority because syscalls contribute only about 1.1% historically.

MIPS already has [in-trampoline IBTC chaining](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/trampoline_a64.S:68), a 4,096-block budget, and the [six-instruction TLB probe plus access](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:145). Adding those again would not address the remaining problem.

**PPC64: remove dispatch overhead, preserve native prefixes, and simplify generated arithmetic.**

Calls plus FP account for **90.8%** historically. The pending opcode additions may change that split substantially.

- **Move the dispatch loop inside the trampoline.** Despite its comment, [ppc64_dbt_step](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:797) calls `ppc64_dbt_enter()` for every block at line 816. The [trampoline](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/trampoline_a64.S:38) allocates and saves a 128-byte frame, then restores it after every block.

  The surgical first implementation is a loop immediately after `blr x9`: on a normal exit, decrement a budget, check pending work/invalidation, probe `cpu->nip`, and enter the next valid native block. Return to C for misses, fallback entries, syscalls, traps, SMC or budget exhaustion. Preserve the **last executed entry’s metadata**, because syscall PC and instruction length currently come from the C loop’s entry. Increasing `DBT_CHAIN_BUDGET`, which also changed during this audit, does not remove this per-block round trip.

- **Stop rejecting an entire mixed block for one unsupported instruction.** [emit_mixed.c:107](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mixed.c:107) returns zero after any decline, even after a substantial supported prefix. [dbt.c:705](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:705) caches the starting PC as fallback; execution then interprets one instruction.

  Return the accepted instruction count with emitted size and publish the prefix. Update snapshot length, revalidation, SMC coverage, AOT hash and exit metadata together. Sum actual **4/8-byte instruction lengths**. Only a refusal at the first instruction should create a one-instruction fallback entry. Measure lost-prefix lengths after the opcode additions before estimating its payoff.

- **Introduce local GPR/VSR caching, then CR/XER caching.** The common accessors in [emit_core.h:315](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:315) and scalar FP accessors in [emit_fp_vs.c:88](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:88) are suitable seams. Begin with register-only spans and flush at fault/helper/exit boundaries. Route memory writebacks and GPR↔VSR transfers through the same cache so they cannot stale entries. Preserve FPR/VSR aliases and untouched lanes; full 128-bit VSR caching needs more preservation than the ABI guarantees for `d8–d15`.

  [CR generation](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:56) constructs nibbles and repeatedly loads/stores CR and XER; [e_cr_put](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:378) performs another field read/modify/write. Cache these values and use bitfield insertion. Compare-to-branch forwarding is a later narrow optimization. Preserve compare-time `XER.SO`, sticky SO, CA/CA32, OV/OV32 and partial CR updates; a branch does not make CR architecturally dead.

- **Specialize `rotlwi`, constant shifts and simple masks.** [e_rot](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:367) sends full-mask `RLWINM` through generic masking, insertion and high-half reconstruction. Emit:
  `ROR Wd,Wn,#((-SH)&31)` for `MB=0, ME=31`, retaining required zero extension and Rc handling. Use immediate shifts and suitable `UBFM/SBFM/EXTR` forms for matching clear/rotate masks. The inspected binary contains 36 static `rotlwi` sites in `main`, plus one in `vop_rol`; this proves exposure, not time attribution.

- **Fix demonstrable TLB refill gaps before changing the hit sequence.** [vm64.c:601](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm64.c:601) permits fills only for widths ≤8, while [emit_mem.c:410](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.c:410) supports aligned 16-byte accesses. Vector-only accesses can repeatedly miss until a scalar access fills the page. Count these misses; permit eligible 16-byte fills after full validation, retaining permissions, COW, reservations and code-write gates. The scalar [seven-instruction hit sequence](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.c:391) is already compact.

FPSCR batching is not an identified PPC benchmark opportunity: the inspected benchmark arithmetic has no `fdiv`, while the current [sticky-status path](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:151) is specific to division. VSR traffic is the better candidate to measure.

**SPARC64: distinguish unnecessary window helpers from real spills before optimizing either.**

Calls account for **84.5%** historically. The actual compiled `fib_rec` retains deep recursion, but GCC converts the second recursive expression into a loop; the benchmark’s source-level call count is not the dynamic guest CALL count.

- **Allow zero-counter SAVE transitions that do not require a spill.** [sparc64_fast_win](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_fast.c:197) goes slow whenever `cansave == 0`. But [sparc64_win_save](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:107) spills only when the target window is valid. For an invalid target, zero exhaustion merely adjusts the counter before rotation.

  Count zero-counter-only transitions separately from actual spills. Then retain the invalid-target case inline, reproducing lazy initialization and exact counter updates. Do not apply the same simplification blindly to RESTORE: its [counter reset is conditional on filling](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:167).

- **Add a guarded 128-byte spill/fill path.** Real spills still use [win_spill_to/win_fill_from](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:52), endian packing, callbacks and general memory validation. This remains separate from the resident-window `LDP/STP` conversion underway.

  Start with the common aligned, single-page stack case: validate the complete span and backing once, transfer with endian conversion and paired operations, then commit window state. Preserve `winsp[tgt]+2047` for spills and `old_i[6]+2047` for fills. Retain the existing helper for straddles, faults, file/COW cases and code-bearing pages. An inline bulk sequence also needs explicit preemption recovery: [vm64.c:460](/Users/angerman/Projects/zw3rk/sparc64rt/src/vm/vm64.c:460) recognizes the existing scalar memory sequence, not arbitrary bulk transfers.

- **Cache local GPRs and FP values next.** Ordinary registers funnel through [e_ld64/e_st64](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_priv.h:675). Start locally; invalidate `%o/%l/%i` cache mappings on window rotation and preserve `%g0`. FP arithmetic similarly reloads and stores every operand/result at [emit_fp.c:177](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_fp.c:177). Cache operands and eligible mode state, but preserve single/double aliases, per-instruction `cexc`, cumulative `aexc`, trapping PC and NaN replay. Accumulating host FPSR across an entire block would not preserve those semantics.

- **Shorten existing chaining only after repairing its validation controls.** [trampoline_a64.S:65](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/trampoline_a64.S:65) already chains through IBTC, block and page-version checks. Profile direct edges versus indirect transfers, then consider guarded successor slots for direct calls/backedges. The current loop has **no block budget**.

  Two concrete correctness issues affect qualification:
  - [fp_clear_cexc at line 92](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_fp.c:92) emits a 32-bit **load**, rather than the intended store of the cleared FSR.
  - [step_one at line 677](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:677) selects normal entry; additionally, the chain probe reads the epoch through `x27`, ignoring the zero-epoch `x28` mechanism described by `enter_step`. Verify single-step behavior with a warmed IBTC before trusting differential validation.

**The first implementation batch should be instrumentation and a fresh baseline after the current edits settle.** Add default-off phase timing for dispatch/build, native execution, fallback, TLB service, window helpers and syscalls. Split `calls_ibtc` into recursion and vtable phases; record fallback reasons and actual spill/fill counts. Instrument assembly chaining itself: existing C-side block/hit counters omit chained executions.

Then test each candidate against the same guest binary and host conditions, retaining all trials and CRCs. Focused checks should cover fault-state recovery, delayed branches, mixed-width PPC instructions, SPARC recursion depths around window exhaustion, cross-page window faults, and FP flags after exceptional followed by exact operations.

No fresh runtime benchmarks or speedup claims were produced. The source audit and Capstone inspection identify concrete candidates; they do **not yet establish that the pending or proposed changes beat QEMU**.