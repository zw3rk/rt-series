# rt-series — static audit report

**HEAD:** `4e4512dbd0b50b9e0bae83afc83c2bdf6a02ef19`

**Scope:** 15 source/build files, **5,091 physical lines**: four C fixtures, one ABI header, eight shell scripts, `Makefile`, and `flake.nix`. Also inspected relevant catalogue requirements and host-contract excerpts.

Completed **seven batched shell inspections**. No builds, compilers, QEMU, Docker, or test scripts were intentionally invoked; no files were edited. The system Git launcher emitted Xcode initialization/cache errors during metadata inspection.

This repository contains coordination tooling and test fixtures, **not translator implementations**. ISA decoding, DBT lowering, runtime Soft-TLB/COW/W^X behavior, syscall translation, and signal restoration in sibling repositories remain unverified. Findings below concern code present in `rt-series`; they do not establish defects in sibling runtimes.

**Principal risks:** fixtures reject correct big-endian/32-bit execution, several gates can report success without the promised coverage, and benchmark results can misidentify engines or ignore execution failures.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 1 | 5 | 1 | 0 | 0 | 0 | 7 |
| Medium | 6 | 6 | 1 | 0 | 1 | 0 | 14 |
| Low | 0 | 0 | 0 | 2 | 0 | 2 | 4 |
| **Total** | **7** | **11** | **2** | **2** | **1** | **2** | **25** |

## 1. Bugs & Defects

### High

- [ ] **RTS-1 — High — BUG — Cross-page fixture rejects correct big-endian execution**
  - **Where**: `tests/p3_torture.c:361-374` (`t_unaligned_cross_page`)
  - **What breaks / Why**: `memcpy(&got, edge, sizeof(got))` interprets the bytes in native guest byte order, but `want` always places `edge[0]` in the least significant byte. The nonuniform byte pattern therefore fails on supported big-endian guests, including PPC32, SPARC, and big-endian MIPS, even when memory translation is correct.
  - **Fix**: Construct the reference in native byte order using an independent aligned byte buffer, or explicitly select the expected assembly order for each endianness.

- [ ] **RTS-2 — High — DEFECT — Assembler/linker test substitutes a shell script and reports PASS**
  - **Where**: `tools/run_catalogue.sh:652-691` (`run_guest_payload`, Tier 4)
  - **What breaks / Why**: Linux assembly is provided only for AArch64 and x86-64. Every other machine writes a shell script containing `exit 42`, then reports `as+ld .s link + exit 42` as passed. Consequently, the foreign architectures this catalogue primarily targets can pass without invoking either assembler or linker.
  - **Fix**: Supply assembly fixtures for the supported guest ISAs, or record an explicit unsupported/GAP result. Require an actual linked guest ELF before awarding this pass.

- [ ] **RTS-3 — High — DEFECT — Benchmark PASS ignores process failure**
  - **Where**: `tools/bench_harness.sh:318-331`, `tools/bench_harness.sh:344-353`, `tools/bench_harness.sh:364-399` (`run_one_target`)
  - **What breaks / Why**: Execution uses `... || true`, discarding translator, container, and timeout status. A process that prints `ALL_PASS` and subsequently crashes or hangs until timeout is accepted. Conversely, any QEMU failure without that marker—including a genuine checksum mismatch—is converted to SKIP.
  - **Fix**: Capture exit status separately. Require exit zero and a complete, anchored result record. Classify unavailable prerequisites before execution; treat crashes, timeouts, and checksum mismatches as failures.

- [ ] **RTS-4 — High — DEFECT — Grind architecture selection does not select a translator**
  - **Where**: `tools/run_grind.sh:39-46`, `tools/run_grind.sh:116-130`, `tools/run_grind.sh:164-207`, `tools/run_grind.sh:464-482` (`ARCH_FILTER`, grind dispatch)
  - **What breaks / Why**: `ARCH_FILTER` is parsed and printed but never controls execution. Stress-ng executes directly from host `PATH`; GCC torture defaults to host `cc` and requires a direct native execution before optional wrappers. `grind-nightly --arch mips32rt` can therefore report host-only passes without running MIPS32. Setting a cross compiler instead makes the mandatory native baseline unsuitable unless separate execution support exists.
  - **Fix**: Resolve the selected repository/ABI to its guest compiler, artifacts, and explicit engine runners. Execute the same guest ELF through the selected oracle/interpreter/DBT paths, and distinguish native-only diagnostics from translator qualification.

- [ ] **RTS-5 — High — DEFECT — Grind converts executed failures into tolerated skips**
  - **Where**: `tools/run_grind.sh:262-270`, `tools/run_grind.sh:409-435`, `tools/run_grind.sh:490-498` (`run_testfloat_suite`, `run_lmbench_suite`, final gate)
  - **What breaks / Why**: A nonzero TestFloat verifier exit becomes SKIP. Executed lmbench commands that fail or time out also become SKIP. The final gate ignores skips whenever another suite passes. The advertised `GRIND_ALLOW_SKIP` setting is never read, so setting it to zero cannot make this strict.
  - **Fix**: Reserve SKIP for positively identified unavailable prerequisites. Treat nonzero exits and timeouts from launched tests as failures, and implement an explicit strict skip policy.

- [ ] **RTS-6 — High — DEFECT — Qualification checks fixture presence without requiring execution evidence**
  - **Where**: `tools/run_catalogue.sh:99-118`, `tools/run_catalogue.sh:751-780`, `tools/run_catalogue.sh:832-848` (`check_uniform_guests`, `run_repo_gate`, `run_host_qualify`)
  - **What breaks / Why**: Qualification checks executable bits on uniform guests, then delegates to a parity script or generic `make check`. It neither invokes the uniform fixtures/payload itself nor validates required result rows. A successful delegated check can omit P3, TCG, dynamic loading, or T1–T4 entirely. This does not enforce the execution requirement in `docs/lanes/wave-c2-uniform-catalogue.md:43`.
  - **Fix**: Require a manifest of successful ABI/engine/category rows from delegated gates, or explicitly execute the required guests. Reject missing execution evidence even when artifacts exist and the delegated command exits zero.

### Medium

- [ ] **RTS-7 — Medium — BUG — Tier 4 strips the symbol it later requires**
  - **Where**: `tools/run_catalogue.sh:553-560`, `tools/run_catalogue.sh:696-700` (`run_guest_payload`)
  - **What breaks / Why**: The C executable is stripped in place, then `objdump -d` must contain `main`. A normal stripped executable need not retain that symbol, so a working compiler/binutils stack fails this check.
  - **Fix**: Disassemble and inspect the unstripped artifact first, or retain a separate unstripped copy and validate the stripped copy by execution.

- [ ] **RTS-8 — Medium — BUG — Requested benchmark engine is not consistently passed**
  - **Where**: `tools/bench_harness.sh:306-327`, `tools/bench_harness.sh:344-349`, `tools/bench_harness.sh:364-377` (`run_one_target`)
  - **What breaks / Why**: Darwin/Linux paths omit engine selection for `a32rt`, `i686rt`, and `rvrt`; the `hl` path omits it for every translator. Output still labels results with `$ENGINE`. Thus `--engine interp` can report default-engine execution as interpreter performance. The repository’s remote runners already show distinct selection mechanisms for `rvrt` and `i686rt`.
  - **Fix**: Use a per-translator command adapter for engine selection across all targets. Reject unsupported engine combinations and report the engine actually selected.

- [ ] **RTS-9 — Medium — DEFECT — Empty benchmark matrices succeed**
  - **Where**: `tools/bench_harness.sh:301-304`, `tools/bench_harness.sh:311-401`, `tools/bench_harness.sh:404-420` (`run_one_target`, `run_matrix`)
  - **What breaks / Why**: An unknown architecture matches no loop iterations. An unknown target has no rejecting `case` branch. Missing binaries return success as SKIP, and no final executed/pass count is required. These paths can exit successfully after running zero benchmarks.
  - **Fix**: Validate option values before dispatch, count matched/executed/passed cases, and fail when the selected matrix has no successful execution or required artifacts are missing.

- [ ] **RTS-10 — Medium — BUG — Optional grind settings become fatal unset-variable expansions**
  - **Where**: `tools/run_grind.sh:191-193`, `tools/run_grind.sh:234-235` (`run_gcc_torture_suite`, `run_testfloat_suite`)
  - **What breaks / Why**: With `set -u`, the `eval` lookup expands an unset `GRIND_QEMU`, `GRIND_INTERP`, or `GRIND_DBT` without a default, aborting after the native test. Weekly TestFloat similarly expands `$TESTFLOAT_ROUNDS` when both round overrides are unset, despite computing a default in `_rounds` immediately beforehand.
  - **Fix**: Read wrapper variables with explicit empty defaults, preferably without `eval`. Use `${TESTFLOAT_ROUNDS_WEEKLY:-$_rounds}` for the weekly fallback.

- [ ] **RTS-11 — Medium — DEFECT — Existing binaries bypass source changes**
  - **Where**: `tools/build_uniform_guests.sh:43-48`, `tools/bench_harness.sh:146-174`, `tools/bench_harness.sh:212-221` (`already_built`, `build_guest_bins`)
  - **What breaks / Why**: Build decisions test only executable presence. Editing a fixture and rerunning the normal builder leaves old binaries in place. Qualification also checks only presence, so a source fix can appear qualified while the previous executable is still being tested.
  - **Fix**: Track source/compiler/flags fingerprints or proper build dependencies. Publish outputs atomically after successful compilation and verify their provenance before qualification.

- [ ] **RTS-12 — Medium — BUG — Uniform container names collide and cleanup is not guaranteed**
  - **Where**: `tools/build_uniform_guests.sh:52-83`, `tools/build_uniform_guests.sh:259-296` (container build functions and dispatch)
  - **What breaks / Why**: Container names contain the literal suffix `23194`, so concurrent invocations collide. There is no cleanup trap or removal verification despite the header’s claim. Killing a timed-out Docker client does not guarantee the daemon-owned container has stopped.
  - **Fix**: Allocate a unique invocation identifier or CID file, install cleanup traps for owned containers, and verify removal after success, failure, timeout, and interruption.

- [ ] **RTS-13 — Medium — DEFECT — Remote benchmark execution has no wall-clock bound**
  - **Where**: `tools/remote_bench.sh:98-145`, `tools/remote_linux_inner.sh:40-75` (matrix execution)
  - **What breaks / Why**: Native binaries, translators, QEMU, and Lima commands run without timeouts. A guest deadlock or translator loop blocks the entire campaign indefinitely. These scripts do not satisfy the repository’s explicit bounded-process requirement.
  - **Fix**: Bound each execution with a wall-clock timeout and owned-process cleanup. Bound both the remote orchestration command and the process inside the VM.

- [ ] **RTS-14 — Medium — BUG — Failed clock reads produce valid-looking benchmark timings**
  - **Where**: `tests/bench_suite.c:32-38`, `tests/bench_suite.c:291-304`, `tests/bench_suite.c:390-400` (`get_monotonic_time`, `elapsed_us_between`)
  - **What breaks / Why**: Both clock implementations discard syscall errors and leave zeroed timestamps. Two failed reads yield zero elapsed time, which is converted to one microsecond. Workload correctness can still pass, producing fabricated performance numbers for a broken clock implementation.
  - **Fix**: Return and propagate clock-read status. Reject invalid or unavailable timing samples and distinguish correctness-only success from measured performance.

- [ ] **RTS-15 — Medium — BUG — Alternate-stack error paths free a registered stack**
  - **Where**: `tests/p3_torture.c:313-338` (`t_sigaltstack`)
  - **What breaks / Why**: After registering the alternate stack, handler-installation and `raise` failures free its storage without disabling it. The normal cleanup also ignores failure from `sigaltstack(SS_DISABLE)`. The process can retain a registered pointer into freed memory.
  - **Fix**: Use one cleanup path that restores the previous handler and alternate stack. Check restoration before freeing the allocation.

- [ ] **RTS-16 — Medium — DEFECT — Signal torture passes without exercising the claimed register/reservation conditions**
  - **Where**: `tests/p3_torture.c:173-235`, `tests/p3_torture.c:238-293` (`t_sig_frame_gpr`, `t_sig_frame_fpr`)
  - **What breaks / Why**: The GPR case checks only that `ucontext` is non-null; it never checks or modifies saved registers. Its CAS happens after `raise` returns, so no LL/SC reservation spans delivery. The FP case permits delivery after computation via `raise`, and its reference computation can receive the still-armed alarm. A pass therefore does not establish cached-register restoration or interrupted-reservation correctness.
  - **Fix**: Add per-ISA fixtures that hold known register values and reservations across controlled delivery, inspect/modify saved context, and verify resumed state. Ensure the FP signal occurs during the measured computation and cancel the timer before the reference run.

- [ ] **RTS-17 — Medium — DEFECT — Missing core fixture capabilities still produce ALL_OK**
  - **Where**: `tests/p3_torture.c:531-550`, `tests/tcg/smoke_tcg.c:443-461` (`main`)
  - **What breaks / Why**: Both fixtures succeed whenever at least one case passes and none explicitly fails, regardless of skipped cases. Failures to provide `sigaction`, `sigaltstack`, `mmap`, or threads may become skips earlier in execution. Basic arithmetic/hash success can therefore coexist with `ALL_OK` despite missing required runtime facilities.
  - **Fix**: Make qualification mode reject skipped required cases. Represent genuine platform exclusions explicitly and keep them separate from runtime API failures.

## 2. Curated C11 & UB Issues

- [ ] **RTS-18 — High — C11 — Thread arithmetic overflows signed long on 32-bit guests**
  - **Where**: `tests/tcg/smoke_tcg.c:265-284` (`thread_fn`, `t_testthread`)
  - **What breaks / Why**: With `n = 200000`, the sum is `19,999,900,000`; the reference multiplication is `39,999,800,000` before division. Both exceed 32-bit signed `long`. The worker accumulation and reference expression invoke signed-overflow UB on supported ILP32 guests, invalidating the oracle.
  - **Fix**: Use `int64_t` consistently for accumulation, result storage, and reference arithmetic, ensuring widening occurs before multiplication.

- [ ] **RTS-19 — Medium — C11 — Thread error path can leave a pointer to an expired stack object**
  - **Where**: `tests/tcg/smoke_tcg.c:265-267`, `tests/tcg/smoke_tcg.c:283-310` (`thread_fn`, `t_testthread`)
  - **What breaks / Why**: The worker receives `&n`, a local variable. If `munmap` fails after `pthread_create`, the function returns without joining the thread. A worker that has not yet loaded its argument can then dereference an object whose lifetime has ended. The join-error path also abandons ownership.
  - **Fix**: After successful creation, join the worker on every subsequent path before returning or releasing its argument storage. Handle unrecoverable join failure without continuing as though cleanup succeeded.

No textual `.c` unity includes, explicit `x18` uses, or calls to `sprintf`, `strcpy`, `strcat`, or `atoi` were found in the inspected implementation files. No `.c`, `.h`, or `.S` file exceeds 900 lines. This is static inspection evidence, not compiler or sanitizer validation.

## 3. DRY — Intra-Repo Duplication

- [ ] **RTS-20 — Low — DRY — Remote benchmark parser and architecture matrix are duplicated**
  - **Where**: `tools/remote_bench.sh:15-31`, `tools/remote_linux_inner.sh:14-30` (`ARCH_LIST`, `parse_and_print`)
  - **What breaks / Why**: Both scripts independently carry the same architecture mappings and seven-field output parser. Changes to workload names, result validation, or supported ABIs require synchronized edits and deployment of both copies.
  - **Fix**: Put the matrix and parser in one repository-local shell helper and deploy it alongside both scripts. This introduces no shared translator runtime dependency.

- [ ] **RTS-21 — Low — DRY — Uniform guest builders repeat the same build procedure fourteen times**
  - **Where**: `tools/build_uniform_guests.sh:52-255`, `tools/build_uniform_guests.sh:259-277` (`build_*`)
  - **What breaks / Why**: Each ABI repeats skip logic, directory creation, timeout/container invocation, and two compiler commands. The same fixed container suffix and omitted `-pedantic` flag recur throughout, illustrating the maintenance cost of updating common policy separately.
  - **Fix**: Use a repository-local build function driven by ABI/compiler/image/flags data, retaining explicit special handling where necessary. Apply strict C flags and lifecycle handling once.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RTS-22 — Medium — YAGNI — Weekly soak is permanently skipped scaffolding**
  - **Where**: `tools/run_grind.sh:438-452`, `tools/run_grind.sh:474-482` (`run_weekly_soak`)
  - **What breaks / Why**: Both branches for Csmith and Yarpgen always skip, even when installed. The upstream-check message directs users to `make catalogue-grind-weekly`, which reaches this same unconditional skip. Weekly mode therefore cannot perform its advertised additional workloads.
  - **Fix**: Implement concrete corpus/upstream runners with explicit inputs, or mark weekly soak unsupported and remove the circular instruction. Do not count a nightly-only run as completed weekly coverage.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RTS-23 — Low — CLEAN — Catalogue status documentation contradicts current skip behavior**
  - **Where**: `docs/CATALOGUE-TODO.md:3-3`, `docs/CATALOGUE-TODO.md:47-47`; implementation at `tools/run_catalogue.sh:733-747`
  - **What breaks / Why**: The document presents its tables as current script behavior and says missing T2–T4 tools still yield `ALL_OK` and exit zero. Current code rejects `skip > 0` unless `CATALOGUE_ALLOW_SKIP=1`. This misdirects qualification planning and diagnosis.
  - **Fix**: Update the status description to match the current implementation, or clearly date and label it as historical evidence.

- [ ] **RTS-24 — Low — CLEAN — Benchmark implementation is seven lines below the C file ceiling**
  - **Where**: `tests/bench_suite.c:1-893` (entire translation unit)
  - **What breaks / Why**: The file combines seven architecture-specific startup/syscall paths, formatting, timing, and five workloads in 893 lines. It complies today, but routine fixes have almost no room under the required 900-line ceiling.
  - **Fix**: Split repository-local startup/platform support and workloads into separately compiled translation units with a small header. Preserve freestanding link behavior; do not use textual `.c` includes or introduce a cross-repository C library.

- [ ] **RTS-25 — Medium — DEFECT — Stderr normalization hides input failures**
  - **Where**: `tools/parity_contract.sh:72-77` (`parity_norm_stderr`)
  - **What breaks / Why**: `grep ... > "$_pns_out" ... || true` treats both “no retained lines” and an actual read failure as success. A missing input file can leave an empty normalized output indistinguishable from clean stderr; comparison against an empty golden can then pass.
  - **Fix**: Check input readability and distinguish grep status 1 from status greater than 1. Propagate read/write failures and publish normalized output only after successful processing.