**Focused performance audit: RV64GC, RV32GC, and LoongArch64 — 2026-10-28**

The strongest investigation targets are FP operand/state traffic for `vfp_simd`, native block-to-block transfers for `calls_ibtc` and branch-heavy `coremark`, and register caching for integer bodies. Both implementations already have a seven-instruction scalar Soft-TLB hit sequence. FPSR/FCSR batching is already present in the inspected working trees and is not a new recommendation. LoongArch still programs FPCR per operation; that is a separate issue.

These are source-supported optimization candidates, **not measured speedup findings**. The supplied TSV measures whole workloads, not translator phases. No runtime changes, instrumentation, builds, or benchmark executions were performed in this audit. Follow the project instrumentation-first rule before selecting or implementing a performance fix: commit default-off phase timers, measure the current candidate on the benchmark host, then test the hypothesis and remeasure. Instruction counts below describe emitted structure, not time attribution.

Paths beginning `rvrt/` and `loongarch64rt/` are relative to `/Users/angerman/Projects/zw3rk/`. Line references describe the inspected working trees. RV HEAD was `de7f1d2c549225e561359d52f654397462dc1d38`, with existing changes in `src/darwin_dbt.c`, `src/dbt_emit_fp.c`, and `src/dbt_emit_fp.h`. LA64 HEAD was `05f2e862ef35bc935ec8973d62e4049d6444a67e`, with existing changes in `src/dbt/{a64_emit.h,dbt.c,emit_fp.c,emit_fp_mem.c,emit_fp_mem.h,emit_int.h}`. Those changes were preserved. The TSV does not pin binary hashes or establish timings for these dirty trees.

The requested RV files `src/dbt_emit.c` and `src/dbt_emit_mem.c` do not exist in this checkout. The relevant implementation is in `src/darwin_dbt.c`, `src/dbt_emit_fp.h`, and `src/dbt/emit_mem.c`. The standalone Linux target shares the Darwin DBT sources (`rvrt/Makefile:8535`, `:8555`); the full Linux runtime is a different path. Record the deployed binary identity before attributing Linux results to a particular build.

**Measured workload priorities and achievable targets**

Source: `docs/bench/results-darwin5-full.tsv:41`–`:43` and `:52`–`:54`. Each cell is translator / QEMU time in microseconds, followed by the ratio. The quoted totals are **Linux**, despite the TSV filename; native Darwin totals are 89,860 / 87,567 / 96,406 µs (`:8`–`:10`). The remote scripts run Linux and QEMU in the Lima VM (`tools/remote_bench.sh:135`, `:143`; `tools/remote_linux_inner.sh:40`).

| Workload | RV64GC | RV32GC | LoongArch64 |
|---|---:|---:|---:|
| coremark | 13,948 / 1,631 · 8.55× | 14,221 / 1,621 · 8.77× | 16,610 / 2,160 · 7.69× |
| chacha20 | 4,940 / 1,279 · 3.86× | 5,203 / 1,292 · 4.03× | 3,358 / 1,455 · 2.31× |
| vfp_simd | 46,754 / 12,338 · 3.79× | 46,895 / 8,813 · 5.32× | 52,658 / 30,863 · 1.71× |
| calls_ibtc | 25,853 / 12,500 · 2.07× | 22,082 / 11,805 · 1.87× | 26,686 / 7,936 · 3.36× |
| syscalls | 946 / 943 · 1.00× | 947 / 940 · 1.01× | 1,076 / 1,124 · 0.96× |
| Total | 92,441 / 28,691 · 3.22× | 89,348 / 24,471 · 3.65× | 100,388 / 43,538 · 2.31× |

FP accounts for 50.6%, 52.5%, and 52.5% of these translator totals; calls account for 28.0%, 24.7%, and 26.6%. Syscalls account for about 1%, so optimizing `getpid` cannot close the gap. Keep ChaCha20 as an integer register-pressure control and a necessary RV32 improvement target.

| Hypothetical equal reduction of coremark + vfp_simd + calls_ibtc only | RV64GC total | RV32GC total | LA64 total |
|---|---:|---:|---:|
| 2× | 49,163.5 µs | 47,749 µs | 52,411 µs |
| 4× | 27,524.75 µs | 26,949.5 µs | 28,422.5 µs |
| Reduction needed to tie QEMU total, other workloads unchanged | 3.795× | 4.541× | 2.454× |

Thus 2–4× in the named workloads could beat QEMU overall for RV64 and LA64, but **4× is insufficient for RV32**. Beating QEMU on each individual workload is a stronger target: coremark needs 7.69–8.77× and RV32 FP needs 5.32×. These figures are arithmetic bounds, not predictions. Removing a phase entirely yields 2× only if it occupied at least 50% of runtime, and 4× only if it occupied at least 75%; measure those fractions before promising either.

The benchmark is CoreMark-style, not the official CoreMark suite (`tests/bench_suite.c:431`). `vfp_simd` combines FP32 recurrence and FP64 Mandelbrot arithmetic (`:665`, `:681`), disables FP contraction (`:637`), and does not establish that guest vector instructions execute. `calls_ibtc` combines recursive Fibonacci and a four-target function-pointer loop (`:716`, `:762`, `:768`). Split those two phases when profiling before attributing all of its time to IBTC misses. Inspect the exact benchmark ELF disassembly: compiler optimization changes the dynamic mix. Full runs discard trial zero and report the minimum of four timed trials (`:455`, `:545`); `total_us` sums workload minima (`:843`), not process wall time.

**1. Remove C from the warm chaining path; preserve a common native block ABI.**

RV: `rvrt/src/dbt/trampoline_a64.S:43`–`:61` returns from each eligible block, calls `rv_darwin_dbt_chain_next`, then calls the next block. `rvrt/src/darwin_dbt.c:791`–`:815` probes an IBTC, checks generation/validity, and updates counters; its miss fallback linearly scans blocks (`rvrt/src/dbt/cache.c:163`). This is already chaining, but still crosses the C ABI on a hit. The trampoline admits BRANCH/INDIRECT, not FALLTHROUGH. A 64-instruction fallthrough therefore also merits a measured exit-reason count (`darwin_dbt.c:29`, `:798`).

LA64: `loongarch64rt/src/dbt/trampoline_a64.S:60`–`:73` calls `dbt_chain_next`; `src/dbt/dbt_chain.c:79` polls signals then calls `dbt_lookup_code`. The separate `dbt_ibtc_lookup` at `dbt_chain.c:41` has no production callers. The active cache lookup is already indexed (`dbt.c:227`), so merely invoking the dormant IBTC from C is not an established improvement. Stable-SMC lookups already skip guest-byte rehashing (`dbt.c:234`–`:247`); do not propose removing a per-block hash that is absent on that path.

After measuring warm chain/lookup time, implement an assembly fast lookup using a compact entry containing full guest PC, current generation/epoch information, and native entry. Hit: validate and branch natively; miss, invalidation, pending work, or budget exhaustion: return to the existing C path. Include a slow-path pending-signal gate and bounded polling. Do not merely omit LA64's `la64_signal_poll`, whose delivery can redirect guest PC. RV self-loops already branch directly with a 1,024-iteration budget (`darwin_dbt.c:558`, `:597`); they will not receive the same benefit as cross-block edges.

For static edges, follow with per-exit mutable RW link slots pointing to validated native block entries. RV already requires mutable links in RW data in `AGENTS.md`; this is the first implementation choice. Evaluate direct A64 `B` patching only after showing link loads remain material and resolving that invariant. Direct patching also needs branch-range handling, W^X publication/I-cache synchronization, incoming-link retirement, and safe code lifetime on arena reuse. A naked branch to today's entry is insufficient: RV pushes LR and reloads CPU/budget per block (`darwin_dbt.c:632`–`:635`) and pops it at `:694`. Define separate external entry and chained body entry, balanced helper calls, and one bounded native dispatch frame. LA64's exit helpers are at `dbt.c:308`, `:320`.

Expected affected workloads: calls first, then branch-heavy coremark; FP only to the extent it crosses blocks. Record direct/indirect/fallthrough/self-loop frequencies and IBTC hits/collisions, but use sampled time or phase timers to establish cost. Do not multiply a guessed chaining speedup by a guessed cache speedup: their savings overlap.

RV's IBTC indexes with `pc >> 2` (`src/dbt/cache.c:206`, `:217`), so distinct compressed-instruction targets in one four-byte word collide. Measure those conflicts before trying halfword-aware hashing or associativity; a collision count alone does not establish its runtime cost.

**2. Keep FP operands in host FP registers; address FPCR separately from FPSR.**

RV: `src/dbt_emit_fp.c:103`–`:110` loads/stores the CPU FPR array for every operation. The ALU sequence at `:288`–`:305` then transfers operands GPR→FPR and results back, performs boxing/canonicalization, and stores again. LA64 has the equivalent boundary at `src/dbt/emit_fp.c:162`–`:182`. Introduce a block-local FPR mapping with dirty bits and type/boxing facts. Load once on first use, retain dependent arithmetic in host S/D registers, and spill only at observable state boundaries. Direct FP loads/stores are a smaller candidate for uncached operands; they do not remove the need to validate RV S operands.

LA64 additionally executes `MRS FPCR` at `emit_fp.c:98` and `MSR FPCR` at `:158` for each operation, including the purported RN fast path. Lines `:116`–`:118` reload/test FCSR each time. Hoist FPCR setup/restore over a region with unchanged guest rounding/trap controls, preserving the caller's FPCR and restoring it before C/helpers/exits. RV's dynamic rounding guard (`dbt_emit_fp.c:194`, used at `:285`) can similarly be shared within a region that cannot change `frm`. A helper or CSR/FCSR write ends that proof; unsupported rounding modes retain fallback. Neither change duplicates the completed FPSR batching.

Start within blocks, then preserve a fixed FP mapping across native links once the chain ABI supports it. Account for AArch64 callee-save requirements when adding live FP registers to the trampoline; C calls can clobber cached vector values. LA64 scalar FPRs alias vector state, so preserve architecturally required upper lanes and invalidate mapping/type facts on LSX/LASX and raw moves. Materialize precise state before faults, signal delivery, interpreter/difftest entry, and control-register reads. Benchmark FP32 and FP64 phases separately to distinguish boxing from general register/state overhead.

**3. Cache GPRs within blocks, then across hot native edges.**

RV: `src/dbt_emit_fp.h:261`–`:277` emits a CPU-array load/store on every nonzero GPR access. LA64: `src/dbt/emit_int.c:44`–`:55` does the same. These are CPU-context accesses, separate from guest-memory Soft-TLB accesses. Add a small allocator with valid/dirty state and explicit scratch ownership, shared by integer, branch, memory, and FP-conversion emitters. Start with write-through caching or spill dirty values before potentially faulting operations/helpers; then add precise side-exit spill maps if measurements justify it. Blocks with long arithmetic dependency chains and ChaCha20 are useful discriminators.

Carry a compatible fixed mapping over native block links only after implementing entry reconciliation and complete cold-exit state materialization. Avoid host register assignments that conflict with the existing pins: RV x19/x20/x21/x22/x23/x24/x28 and LA64 x19/x21/x22/x23/x28 already have uses. Keep x18 reserved. Preserve RV x0, RV32 wrapping, RV64 word sign extension, LA64 r0 and `.W` sign extension. A TLB miss must resume at the correct instruction without exposing later cached results. This is the main integer-body candidate for coremark/ChaCha20; source structure alone does not establish a 2× gain.

**4. Eliminate redundant RV boxing checks using facts, not benchmark assumptions.**

`rvrt/src/dbt_emit_fp.c:113`–`:122` checks the high word for every S operand; `:142`–`:146` boxes every S result. `:125` and `:149` emit NaN canonicalization for S/D arithmetic. Track `known_boxed_S`, raw/unknown, and D values in the FPR cache. FLW, FMV.W.X, and S results establish boxing; raw D writes, helpers, and incompatible merges kill that fact. Skip unboxing checks only when proven, and defer physical boxing until a raw consumer or spill needs the complete 64-bit architectural value. Preserve canonical NaNs, signaling-NaN flags, raw bit moves, and guest `fcsr` semantics. LA64's scalar loader already reads the low word without RV-style validation (`emit_fp.c:169`); do not transplant RV boxing rules onto it.

Consider host default-NaN mode only as a separately measured and validated FP-mode specialization. It requires exact NaN/flag/rounding/subnormal behavior and scoped host FPCR restoration; it is not justification for globally dropping canonicalization. Do not fuse multiply/add across guest instructions: this benchmark explicitly disables contraction and guest rounding must remain exact.

**5. Wire a real return predictor after the warm indirect dispatch path.**

RV has unused RAS helpers (`src/dbt/cache.c:223`–`:240`); JAL/JALR lowering is in `src/darwin_dbt.c:552`/`:568`. LA64 has unused pop logic at `src/dbt/dbt_chain.c:56`; `src/dbt/dbt.c:724` pushes arbitrary dispatcher resume PCs, not architectural call return addresses. This is not a functioning return predictor. LA64 BL/JIRL lowering is at `src/dbt/emit_branch.c:135`/`:141`.

Use a per-execution-context shadow RAS storing guest return PC, native continuation, and generation. Push at recognized calls; for recognized returns, compare the computed architectural target with the predicted guest PC and validate target lifetime before branching. On mismatch, overflow, longjmp, signal transitions, or stale code, safely fall back to the IBTC. RV must respect x1/x5 call/return hints, compressed instruction lengths, and RV32 address wrapping; LA64 must distinguish JIRL calls/returns from arbitrary indirect jumps. Measure Fibonacci separately from the vtable loop: RAS predicts returns, not the four-target indirect calls. Native `BL`/`RET` alone cannot replace guest call semantics.

**6. Keep the seven-instruction Soft-TLB hit path; optimize its surroundings only if measured.**

RV's active standalone path is `src/darwin_dbt.c:249`–`:281`: index, entry address, paired tag/addend load, width-sensitive mask, compare, miss branch, memory operation, excluding EA construction and CPU-register traffic. The generic substrate also emits seven words (`src/dbt/emit_mem.c:150`–`:157`). LA64 does the same at `src/dbt/emit_mem.c:231`–`:247`. A proposal to “replace helpers with a seven-instruction TLB” is already implemented for these accesses.

For RV, outline inline miss/helper stubs so hits fall through instead of taking the skip branch at `darwin_dbt.c:291`–`:309`; measure code layout/front-end effects. For both, GPR/FPR caching removes surrounding context loads/stores. Measure actual misses, conflicts, misalignment, and fallback time before changing capacity or adding same-page reuse. Preserve read/write tag separation, permissions, COW, reservation/SMC handling, full-width addresses, RV32 EA wrap, cross-page checks, and signal rewind metadata. LA64's miss/refill path is `src/dbt/dbt_mem.c:248`–`:326`; it is not the seven-instruction hit emitter.

LA64 also branches around an inline miss epilogue (`src/dbt/emit_ldst.c:62`–`:77`); outlining it is the corresponding layout experiment. Its EA materialization at `emit_ldst.c:103`–`:106` is another narrow candidate for immediate ADD/SUB folding where legal.

**Focused correctness probes required at these optimization boundaries**

Two source-level concerns surfaced; neither was executed as a reproducer or used to explain the measured slowdown. Before FP caching/boxing changes, test RV FMADD.S with a nontrivial third operand: `dbt_emit_fp.c:587`–`:588` passes x3 to `emit_unbox_s`, whose `:116`–`:118` uses x3 as scratch, overwriting that operand before `:591`. Before faster LA64 links, test repeated writes to already-translated code: `dbt_mem.c:315` bumps SMC state on the miss, but `:324` regrants a writable TLB tag, so later native stores may bypass that notification. Do not assume the existing unversioned LA64 IBTC pointer is safe (`dbt_chain.c:21`–`:47`) or bypass epoch/SMC checks (`dbt.c:232`–`:247`).

Validation for the selected change should cover current CRCs plus precise fault/reentry state, helpers clobbering cached registers, guest rounding changes, valid/invalid boxing, qNaN/sNaN, raw FP moves, code invalidation, RAS mismatch, and signal/difftest boundaries as applicable. Preserve correctness expectations instead of relaxing the benchmark or differential oracle.

**Bounded measurement and implementation order**

First commit default-off instrumentation in the exact deployed paths: RV `darwin_dbt.c:624`, `:791`, `:818`, helper entry points at `:231`; LA64 `dbt.c:227`, `:326`, `:654`, `dbt_chain.c:73`, `dbt_mem.c:248`. Collect translation, chain lookup/polling, guest execution, helper/TLB-miss, fallback, and syscall time with explicit inclusive/exclusive accounting. Use sampling or batched timing for tiny edges; a clock call per block can dominate the effect being measured. Record counters as per-workload deltas, including block-length/exit distributions, self-loops, fallback opcodes, IBTC hit/miss/collision, and TLB misses. Counters are not elapsed-time evidence. Cross-check instrumentation overhead against an uninstrumented build.

RV's existing `steps`, `blocks_compiled`, `blocks_executed`, and `fallback_steps` output (`src/darwin_main.c:592`–`:598`) is insufficient: in-block interpreter helpers at `darwin_dbt.c:231` do not increment the outer `fallback_steps` counter at `:780`, and native self-loop iterations do not each increment `blocks_executed`. Instrument both seams rather than inferring a low helper/self-loop cost from those totals.

Then select the measured dominant cause: FP region/caching for FP; native chain ABI plus GPR cache for control flow; RAS only if return traffic remains material. Separate variants so improvements and regressions are attributable. Reuse the same guest ELFs, host, build flags, warmup, and four timed trials; record binary/source hashes and trial dispersion. Re-run all five workloads for the integrated candidate and require unchanged CRCs. Bound each selected guest invocation with `timeout --kill-after=30s 120s`; serialize benchmark runs. Do not invoke the all-architecture campaign for this focused comparison. No new measured split or promised 2–4× result is claimed here.

Audit verification: inspected applicable instructions and source using bounded `rg`, `nl -ba ... | sed -n ...`, and `git ... status --short` / `rev-parse HEAD`; parsed the TSV with Python `csv.reader(..., delimiter='\t')` to compute ratios, workload shares, and the Amdahl tables; checked the audit document with `git diff --check`. No benchmark was rerun, no remote host was accessed, and no translator source or existing user changes were modified.
