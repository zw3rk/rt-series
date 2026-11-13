The highest-priority work is **repairing broken fast paths, then reducing state traffic across instructions and blocks**. I found concrete PPC IBTC defects, inverted SPARC FP guards, and missing i686 indirect-call lowering. MIPS needs immediate profiling of a compilation/fallback pathology before allocator tuning.

These are source findings ranked against recorded workload timings—not measured speedup claims. The TSV lacks the phase breakdown needed to attribute time to individual mechanisms.

The requested `tests/bench/rt_bench.c` is absent; the harness builds [tests/bench_suite.c](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:1). Its full run discards one warmup, takes the minimum of four timed trials per workload, and sums those minima. The ARM **8,028 µs** reference is Linux; Darwin is **10,785 µs**.

Using matching Linux rows from [results-darwin5-full.tsv](/Users/angerman/Projects/zw3rk/rt-series/docs/bench/results-darwin5-full.tsv):

| Engine | DBT total µs | QEMU total µs | DBT/QEMU time | Largest DBT components |
|---|---:|---:|---:|---|
| a32rt | 8,028 | 22,134 | **0.36×** | Calls 47% |
| i686rt | 56,909 | 31,492 | **1.81×** | Calls 41%, ChaCha 25% |
| mips32rt | 2,012,667 | 39,717 | **50.68×** | CoreMark 67%, FP 17%, calls 15% |
| ppc32rt | 70,736 | 67,832 | **1.04×** | FP 60%, calls 26% |
| sparc32rt | 439,135 | 67,889 | **6.47×** | FP 69%, CoreMark 15%, calls 14% |

a32rt provides useful implementation patterns: [resident guest GPRs](/Users/angerman/Projects/zw3rk/a32rt/src/trampoline.S:81), [generated direct edges and self-loops](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:567), [inline RAS/IBTC](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:686), and [FP-cache loop preheaders](/Users/angerman/Projects/zw3rk/a32rt/src/dbt/dbt_jit_query.c:121). Its timing is not a transferable prediction for another guest ISA.

**i686rt: fix indirect calls, then flags and dispatch**

1. **Implement `I686_OP_CALL_Ev` before redesigning the IBTC.**  
   [emit_branch.c:386](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_branch.c:386) implements direct `CALL_Jz`; there is no `CALL_Ev` lowering anywhere in `src/dbt`. It therefore reaches [interpret-one fallback](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/translate.c:296).

   Disassembly of the local benchmark confirms the vtable loop executes:

   ```asm
   0804a2bc: calll *0x90(%esp,%eax,4)
   ```

   Add register/memory indirect-call lowering beside `CALL_Jz`: capture the target using the original ESP, perform the fault-aware return-address push, then use the indirect dispatch path. Preserve operand-size, segment, and stack-fault semantics. This removes a known fallback from the measured workload; its time contribution still needs counting.

2. **Use direct successor slots for direct branches; add a real return predictor.**  
   [emit_branch.c:144](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_branch.c:144) writes exit state and returns; [trampoline.S:76](/Users/angerman/Projects/zw3rk/i686rt/src/trampoline.S:76) hashes every branch through the same IBTC. Direct branches needlessly compete with indirect targets.

   Add validated successor slots for unconditional/conditional edges and a RAS for CALL/RET. Check the actual popped return PC against the predicted entry and retain invalidation and signal-budget checks. The uncommitted trampoline change already removes GPR spill/reload on successful chains; do not duplicate that work. Generic exits still spill in [emit_exit.c:73](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:73).

3. **Reduce flag bookkeeping without discarding fault-visible state.**  
   [emit_alu.c:236](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:236) writes a multi-field lazy descriptor. [emit_branch.c:184](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_branch.c:184) can spill all guest GPRs, call a materializer, reload, and rebuild NZCV.

   Extend flag liveness and producer/consumer fusion where measured hot blocks justify it. Gate the generated [flags-elided counter sequence](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/flags_dbt.c:47) behind profiling.

   **Qualification blocker:** the dirty [translate.c:95](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/translate.c:95) treats memory operations as transparent to flag elimination. Recovering only EIP/ESP does not make EFLAGS unobservable. For example, `ADD; faulting MOV; XOR` must expose ADD’s flags to the fault handler. Retain fault barriers until recovery metadata reconstructs the correct state.

4. **Cache XMM values; the benchmark uses SSE, not x87.**  
   [emit_sse.c:668](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:668), [712](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:712), and [1173](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:1173) reload operands from `ctx->xmm` and store results after each operation. Introduce a block-local eight-XMM cache with dirty tracking, reconciling at helpers, faults, fallback, and exits. Preserve scalar upper lanes, MXCSR behavior, and exception semantics.

5. **Simplify effective-address and ALU sequences after profiling.**  
   [emit_exit.c:111](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:111) emits redundant W-register zero-extension and repeated segment-base loads. Use W-register arithmetic directly; specialize flat segments only behind a valid guard/invalidation contract. [emit_alu.c:185](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:185) also routes full-width operands through scratch copies: emit directly against the already-resident guest registers where aliasing permits.

The 72 µs syscall result is not general syscall superiority: [sys_getpid](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:120) returns stored context state.

**ppc32rt: repair IBTC and SMC before tuning**

1. **Fix the IBTC pointer type.**  
   [cache.c:144](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:144) stores executable address `e->entry`. Generated lookup at [ppc32_a64_emit2.c:397](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:397) dereferences it as block metadata containing `{key|epoch, host_code}`.

   Set `slot->entry = (void *)e`; retain `slot->host_code`. Validate warmed indirect calls, eviction, and invalidation.

2. **Make the emitted hash match the C hash.**  
   [ppc32rt.h:300](/Users/angerman/Projects/zw3rk/ppc32rt/src/ppc32rt.h:300) indexes 4,096 entries, while [ppc32_a64_emit2.c:394](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:394) emits a ten-bit index.

   Derive both from one definition. For the existing encoding, twelve-bit extraction changes `0x53022E11` to `0x53023611`. Exercise both missing index bits before considering associativity or larger tables.

3. **Fix a correctness defect in the store guard.**  
   [dbt.c:247](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/dbt.c:247) puts `len` in `w2`, then overwrites **x2** with the bitmap pointer. The range calculation and helper subsequently receive the corrupted length. [cache.c:538](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:538) rejects lengths above 4,096, potentially suppressing real SMC invalidation.

   Keep the bitmap pointer in a distinct register. Test ordinary, cross-page, wrapping, and linked-code stores. Do not “optimize away” this guard.

4. **Add block-local GPR caching and CR fusion.**  
   [emit_int.h:108](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_int.h:108) loads every operand from context; `ei_st` immediately writes every result back. Start with a small read/dirty cache, flushing at observable boundaries. Then fuse eligible compare/branch sequences around [emit_int.c:497](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_int.c:497), retaining CR-field state, XER.SO, and CTR/BO semantics.

5. **Optimize FP state traffic even though PPC already beats QEMU on FP.**  
   FP consumes 42,415 µs—60% of total. [emit_fp.c:114](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:114), [146](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:146), and [377](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:377) repeatedly synchronize controls, load/store FPRs, accumulate exceptions, and classify results.

   Cache FPRs and establish FP control state once per safe region. Defer dead FPRF production, preserving FPSCR observers, Rc/CR1, enabled exceptions, invalid-operation subtypes, and single-precision rounding. Blind cumulative FPSR merging is insufficient.

After those changes, investigate constant-rotate and immediate-address peepholes at [emit_int.c:444](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_int.c:444). Direct chaining and a RAS already exist.

**mips32rt: diagnose the pathological slowdown first**

1. **Measure repeated compilation failure before anything else.**  
   CoreMark takes **1,358,142 µs**, versus **158,834 µs in the interpreter**. That strongly prioritizes compilation/fallback pathology.

   [emit_int.c:804](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:804) discards an overflowing translation; [dbt.c:637](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:637) returns fallback; [dbt.c:755](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:755) interprets one instruction and retries at the next PC.

   Count failures by reason and PC, attempted bytes, and compilation time. If confirmed, publish the maximal fitting prefix, reserve exit space, and treat branch/delay-slot pairs atomically. Avoid repeatedly attempting an unchanged impossible translation. The dirty tree already increases staging from 4 KiB to 64 KiB; that is an unmeasured mitigation, not a complete solution.

2. **Remove unnecessary state traffic around memory accesses.**  
   [emit_mem.c:47](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:47) flushes all sixteen cached GPRs before every faultable access. Track dirty registers first. Later, precise host-PC/state maps can replace eager spills, but the fault handler must recover live values.

   Ordinary stores at [emit_mem.c:273](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:273) also acquire the shared LL/SC lock, update epochs, and release it. Profile synchronization separately. A guarded single-writer execution mode could remove much of this cost; checking only the current thread’s reservation is insufficient because another thread’s LL must observe even same-value stores.

3. **Replace C-mediated “chaining” with register-preserving edges.**  
   [trampoline_a64.S:57](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/trampoline_a64.S:57) calls C `dbt_chain_next` between blocks. Generated entries/exits reload and flush the cached register set at [emit_int.c:104](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:104).

   Introduce separate cold entry and chained entry points, inline key/version checks, and two successors for conditional branches. Put RAS updates on actual chained calls/returns. Preserve budgets, signals, invalidation, and quiescence.

4. **Cache FP registers and amortize FP control handling.**  
   [emit_fp.c:141](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:141) and [482](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:482) expose operand round-trips and repeated FP-state maintenance. Start with block-local FPR caching, then safe control-state regions. MIPS Cause is replaced per operation while Flags accumulate; enabled exceptions and legacy NaNs prevent unconditional deferral.

   **Pending-change blocker:** newly admitted FP delay slots can clobber the JR/JALR target held in x23, and delay-slot emission ignores some declined instructions. Inspect [emit_int.c:622](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:622) against [emit_fp.c:265](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:265). Qualify these paths before accepting faster timings.

ChaCha is only **0.14%** of current MIPS total. ARX peepholes are presently a poor whole-suite priority.

**sparc32rt: the default FP fast path is inverted**

1. **Correct both FP guards.**  
   [emit_fp.c:57](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:57) and [64](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:64) pass `true` to the branch helper, which means **CBNZ**. They branch over fallback when RD/TEM are nonzero—the reverse of the intended condition.

   Change these branches to CBZ. Count default-mode arithmetic/compare fallbacks before and after. Also preserve the JMPL target: [emit_int.c:615](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:615) keeps it in w22, while [emit_fp.c:289](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:289) overwrites x22. Fixing the guard can expose that delay-slot collision.

2. **Make pending direct chaining safe before measuring it.**  
   [dbt.c:451](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/dbt.c:451) reuses direct-mapped metadata; [a64_emit_fp.c:350](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/a64_emit_fp.c:350) checks epoch without checking target PC. Same-epoch replacement by a PC separated by `0x1000` can redirect an old incoming link.

   Validate full key plus epoch, or use stable entry identities with incoming-link invalidation. Test chaining enabled: the differential mode disables chaining.

3. **Unify the RAS convention.**  
   C [dbt.c:540](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/dbt.c:540) increments top before writing; generated [a64_emit_fp.c:276](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/a64_emit_fp.c:276) writes before incrementing and pops `top−1`. Standardize next-free-top semantics. Return the actual final chained entry to the dispatcher so new links attach to the correct source.

4. **Cache integer registers and lazy ICC.**  
   [emit_int.c:80](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:80) repeatedly accesses `ctx->r[]`; [emit_cc.c:38](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_cc.c:38) materializes condition codes that branches subsequently reconstruct.

   Add block-local dirty GPR caching and compare/branch fusion. Reconcile on SAVE/RESTORE, helpers, faults, and exits. Keep `%g0` constant and preserve SPARC borrow semantics. Register-window fast paths should target ordinary cached rotations, retaining overflow/underflow helpers.

5. **Inline guarded FP memory operations and cache FPRs.**  
   [emit_fpmem.c:117](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fpmem.c:117) calls C for every FP load/store. Add aligned, permission-checked LDF/STF/LDDF/STDF paths with endian conversion and helper fallback. [emit_fp.c:149](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:149) is the FPR-cache seam.

   Preserve overlapping single/double registers and the distinction between last-operation `cexc` and cumulative `aexc`. The benchmark explicitly disables FP contraction.

Even eliminating all SPARC FP time leaves **134,131 µs**, almost twice QEMU’s entire suite. Integer/control improvements are necessary.

**Measurement and acceptance**

Before implementing the profile-dependent changes, add and commit default-off timers for lookup, decode/emission, publication, JIT execution, interpreter replay, helpers, and OS dispatch. Record per-workload counter deltas for fallback opcode/reason, overflow, cache eviction, direct/IBTC/RAS outcomes, and memory slow paths. Existing counters do not consistently count chained execution.

Then change one mechanism at a time, retain correctness checks, and repeat settled measurements with profiling disabled. A concrete initial “wide margin” gate is **at least 2× QEMU** on the same host and guest binary:

| Engine | Required total |
|---|---:|
| i686rt | ≤15,746 µs |
| mips32rt | ≤19,858 µs |
| ppc32rt | ≤33,916 µs |
| sparc32rt | ≤33,944 µs |

Those are acceptance targets, not predicted outcomes. Validate faults, SMC/invalidation, FP modes, delay slots, and chaining separately from benchmark CRCs.

I made no edits. Verification comprised source/diff inspection, TSV arithmetic, and bounded i686 ELF disassembly; no rebuilds or timing reruns were performed. MIPS disassembly was unavailable in the installed Apple objdump. Several engines contain pre-existing uncommitted optimizations, and a32rt advanced during the audit, so the supplied TSV cannot be assumed to measure these exact worktrees.