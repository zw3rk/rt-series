Found **8 issues** in the current checkout. There is no `src/` directory here, so this report covers `rt-series` tools and test fixtures—not sibling interpreter, DBT, VM, OS, or ELF implementations.

Used **8 read-only shell invocations**. No Markdown files, builds, tests, Docker, or QEMU were run. Findings are based on static inspection; sibling propagation notes identify follow-up scope, not verified sibling defects.

1. **[RTS-R5-1] BUG / DRY — Duplicate architecture lists omit RV32 from benchmark execution**

   **Evidence:** [tools/bench_harness.sh:78](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:78), [tools/bench_harness.sh:549](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:549), [tools/remote_bench_common.sh:10](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:10).

   `arch_repo` accepts `riscv32`, and the builder contains an RV32 compilation path, but `ALL_ARCHES` excludes it. Consequently, `smoke --arch riscv32` matches zero jobs; `--arch all` silently omits RV32. The shared remote matrix includes it.

   **Fix:** Derive local and remote execution matrices from one repository-local architecture definition. Ensure every accepted architecture filter either selects an executable matrix entry or is explicitly rejected.

   **Propagation:** Check `rvrt` RV32 qualification and scripts consuming these benchmark results.

2. **[RTS-R5-2] BUG — Throughput calculation overstates rates by truncating elapsed milliseconds**

   **Evidence:** [tests/bench_suite.c:112](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:112).

   For workloads exceeding 4,000 operations, the calculation divides by `floor(us / 1000)`. For example, 8,000 operations in 1,999 µs report 8,000,000 ops/s instead of approximately 4,002,001. This introduces a large discontinuity around millisecond boundaries.

   **Fix:** Calculate `iters * 1000000 / us` with sufficiently wide arithmetic, including compatible division support for freestanding targets. Define handling for results exceeding the output type.

   **Propagation:** All runtimes using `bench_suite.c`; previously reported `ops_sec` values may need recalculation from recorded microseconds.

3. **[RTS-R5-3] DEFECT — VM restoration check can pass without issuing a load**

   **Evidence:** [tests/p3_torture.c:620](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:620), [tests/p3_torture.c:637](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:637).

   The RW restoration check writes `0xCC` through an ordinary pointer and immediately compares the same location against `0xCC`. The compiler may eliminate that comparison, so it does not establish that a subsequent guest load observes the restored mapping. The deliberately faulting RO store likewise lacks an explicit volatile access.

   **Fix:** Use volatile-qualified accesses for deliberate memory probes, including initialization, faulting accesses, and post-restoration verification. Keep the expected value independently computed.

   **Propagation:** Check equivalent Soft-TLB and permission-transition fixtures in all ten runtimes.

4. **[RTS-R5-4] DEFECT — Cross-page test never creates the claimed protection-generation difference**

   **Evidence:** [tests/p3_torture.c:497](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:497), [tests/p3_torture.c:507](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:507), [tests/p3_torture.c:528](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:528).

   The test claims to cover a crossing access when the second page has a different protection generation. It maps both pages RW and never changes either page’s protection. It therefore cannot detect a crossing-access bug triggered specifically by independently invalidated page permissions.

   **Fix:** Warm both pages, change the second page’s protection independently, then check crossing accesses with explicit expected success and fault outcomes. Retain the existing byte-order checks.

   **Propagation:** All runtime Soft-TLB slow paths, especially independently protected sub-pages under `hyper-linux`.

5. **[RTS-R5-5] BUG / YAGNI — `LTP_DIR` enables a branch that never runs LTP**

   **Evidence:** [tools/run_grind.sh:600](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:600), [tools/run_grind.sh:608](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:608).

   Without a manifest, either `LIBC_TEST_DIR` or `LTP_DIR` sets `_found`. The subsequent execution loop only constructs paths from `LIBC_TEST_DIR`. Setting `LTP_DIR` alone instead probes `/bin/functional`, `/bin/math`, and `/bin/pthread`; no LTP executable is selected.

   **Fix:** Implement explicit LTP selection and invocation, or remove the ineffective `LTP_DIR` fallback and require an LTP manifest. Report libc and LTP coverage separately.

   **Propagation:** All sibling nightly/weekly jobs relying on `LTP_DIR` for syscall coverage.

6. **[RTS-R5-6] BUG — Cancellation traps remove working files without terminating the script**

   **Evidence:** [tools/run_grind.sh:25](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:25), [tools/run_catalogue.sh:299](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:299).

   Both scripts install cleanup-only handlers for `INT` and `TERM`. A trapped signal does not itself terminate the shell. Execution can resume after cleanup, potentially continuing suites with deleted inputs or starting additional work after cancellation.

   **Fix:** Use separate signal handlers that exit with 130/143 and an EXIT handler that performs cleanup while preserving status. Ensure active owned child jobs terminate before their files are removed.

   **Propagation:** Check sibling shell runners for the same `trap 'cleanup' EXIT INT TERM` pattern.

7. **[RTS-R5-7] DEFECT — Benchmark extraction accepts lines excluded by validation**

   **Evidence:** [tools/remote_bench_common.sh:147](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:147), [tools/remote_bench_common.sh:172](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:172).

   Validation counts anchored, fully formatted records. Extraction subsequently matches unanchored substrings such as `/BENCH coremark/`. Output containing one valid record plus a diagnostic like `debug BENCH coremark us=123` passes validation but yields multiple values, corrupting the emitted TSV row.

   **Fix:** Validate and extract using the same exact record grammar, preferably in one parser. Emit a result only after establishing one value per required field.

   **Propagation:** All remote benchmark consumers and sibling wrappers that add diagnostic output.

8. **[RTS-R5-8] CLEAN — Catalogue runner exceeds the requested size threshold**

   **Evidence:** [tools/run_catalogue.sh:293](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:293), [tools/run_catalogue.sh:976](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:976).

   The file contains **1,146 lines**, combining guest payloads, embedded programs, parity parsing, container checks, and host orchestration. These independently changing responsibilities make failure paths harder to review.

   **Fix:** Preserve the public entry point while extracting repository-local guest payload and host-gate components. Keep the guest invocation self-contained or explicitly package its dependencies.

   **Propagation:** No runtime implementation change required; preserve sibling callers’ existing command interface.