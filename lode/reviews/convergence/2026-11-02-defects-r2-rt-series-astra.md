# rt-series — Round 2 Static Audit

**HEAD:** `6fc9fbcd088058c9abdeb85e2ca8672006027b6d`  
**Code remediation:** `96e1fe6610b031052a8cde3f230b85dcb394e86f`

**Round-1 remediation is incomplete.** The strongest remaining risks are false qualification results, host execution being credited to foreign architectures, and signal tests that still do not establish their advertised guarantees.

The inspected implementation inventory comprises **16 files / 5,512 physical lines**: the Makefile, eight tooling scripts, the catalogue wrapper, four C fixtures, and two headers. Inspection covered these modules and remediation changes; some large command outputs were truncated, so this is not a claim of exhaustive line-by-line coverage.

Exactly **seven batched shell inspections** were used. No builds, compilers, QEMU, Docker, or test scripts were intentionally executed; no files were changed. Git’s system launcher emitted Xcode initialization/cache diagnostics.

There is no translator `src/` implementation here. Sibling ISA decoders, JITs, VM implementations, locks, and signal restoration remain outside this audit.

Source inspection supports several Round-1 corrections: endian-neutral cross-page expectations, preservation of the unstripped executable, clock-error propagation, stricter skip handling, shared remote parsing, and reduced C-file size. HEAD itself changes only `DEFECTS.md`; its blanket closure claim is not supported by the remaining defects below.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 0 | 2 | 0 | 0 | 0 | 0 | 2 |
| Medium | 5 | 7 | 1 | 0 | 0 | 1 | 14 |
| Low | 0 | 0 | 0 | 1 | 1 | 0 | 2 |
| **Total** | **5** | **9** | **1** | **1** | **1** | **1** | **18** |

## 1. Bugs & Defects

### Critical

No confirmed findings.

### High

- [ ] **RTS-R2-1 — High — DEFECT — Qualification accepts unrelated tests as software-tier evidence**
  - **Where**: `tools/run_catalogue.sh:107-141` (`check_parity_categories`).
  - **What breaks / Why**: The RTS-6 remediation accepts `hello` as T2 evidence, ISA cases as T1 evidence, and FP/thread cases as T3 evidence. `p3-torture` itself also matches the T3 `p3-` alternative. Matching searches the entire row rather than its case field, and requires no per-ABI or per-engine coverage. A small collection of passing runtime fixtures can therefore qualify a repository without executing compression/database tools, scripting runtimes, or the full required ABI/engine matrix.
  - **Fix**: Parse tab-separated fields and require explicit category evidence for every required ABI/engine tuple. Map only tests that actually implement the category; require separate guest-payload tier results.

- [ ] **RTS-R2-2 — High — DEFECT — Grind still credits host execution to selected foreign architectures**
  - **Where**: `tools/run_grind.sh:69-72` (`resolve_arch_defaults`), `tools/run_grind.sh:442-485` (`run_libc_ltp_suite`), `tools/run_grind.sh:489-529` (`run_lmbench_suite`).
  - **What breaks / Why**: `--arch all` returns without constructing a translator matrix. Even with an explicit foreign architecture, libc/LTP and lmbench binaries execute directly, ignoring the resolved translator wrappers. Native binaries can produce PASS results under a foreign-architecture campaign heading; foreign binaries instead fail direct execution. RTS-4 is only partially fixed.
  - **Fix**: Expand `all` into explicit architecture jobs. Route every guest suite through a validated architecture/backend runner, and record native diagnostics separately from translator qualification.

### Medium

- [ ] **RTS-R2-3 — Medium — BUG — Grind chooses executable format before resolving the backend**
  - **Where**: `tools/run_grind.sh:73-98`, `tools/run_grind.sh:115-123` (`resolve_arch_defaults`, `BACKEND`).
  - **What breaks / Why**: Discovery prefers `*-darwin-arm64`, then Linux, based only on executable permission. Backend selection happens afterward and does not influence the runner. A Linux host with both artifacts selects Mach-O; Darwin can select a Linux ELF when its native artifact is absent. `GRIND_BACKEND=hl` never adds an `hl` launcher.
  - **Fix**: Resolve and validate the backend first. Select matching binary formats and construct explicit native-Linux, Darwin, or hyper-linux commands.

- [ ] **RTS-R2-4 — Medium — DEFECT — Weekly differential checks never compare results**
  - **Where**: `tools/run_grind.sh:537-575` (`run_weekly_soak`).
  - **What breaks / Why**: Csmith and Yarpgen run one selected wrapper and accept exit zero. Csmith output is never compared; Yarpgen output is discarded. Both report “differential OK.” A translator returning incorrect generated-program checksums can pass. The new RTS-22 implementation therefore adds execution without the claimed correctness oracle.
  - **Fix**: Run the identical generated binary through an independent oracle and each required engine. Compare complete outputs and exit statuses before reporting differential success.

- [ ] **RTS-R2-5 — Medium — BUG — Yarpgen compilation passes unmatched source globs**
  - **Where**: `tools/run_grind.sh:560-574` (`run_weekly_soak`, Yarpgen branch).
  - **What breaks / Why**: The compiler receives both `"$_ydir"/*.c` and `"$_ydir"/*.cpp`. In POSIX shell, an unmatched glob remains a literal filename. A generated corpus containing only C++ or only C sources therefore supplies a nonexistent input and fails compilation. This becomes a tolerated SKIP under the default policy. The selected C compiler also does not explicitly provide C++ linkage.
  - **Fix**: Select the generator’s language explicitly, collect only existing source files, and use the matching compiler/linker. Treat compilation failure after successful prerequisite discovery as a failure.

- [ ] **RTS-R2-6 — Medium — DEFECT — Signal remediation still does not test interrupted reservations or register restoration reliably**
  - **Where**: `tests/p3_torture.c:202-240`, `tests/p3_torture.c:272-293`, `tests/p3_torture.c:313-359` (`t_sig_frame_gpr`, `t_sig_frame_fpr`).
  - **What breaks / Why**: The atomic load precedes delivery, but the compare-exchange starts afterward; no LL/SC reservation spans the signal. A value-changing handler makes the later CAS fail even if reservation invalidation is entirely broken. Ordinary C variables across `raise()` do not guarantee particular registers remain live. The FP fallback similarly invokes a normal function call while operands reside in volatile memory, and the handler neither changes rounding mode nor deliberately raises the exception flags being checked.
  - **Fix**: Use small per-ISA fixtures to establish live registers and an actual exclusive-load/store interval across controlled delivery. Explicitly alter handler FP state and verify resumed state. Keep the portable cases, but label their narrower guarantees accurately.

- [ ] **RTS-R2-7 — Medium — DEFECT — SPARC smoke binary bypasses the new freshness checks**
  - **Where**: `tools/bench_harness.sh:213-217`, `tools/bench_harness.sh:248-255`, `tools/bench_harness.sh:284-289`, `tools/bench_harness.sh:373-375`.
  - **What breaks / Why**: The fast builder refreshes `bench-sparc32`, while smoke execution prefers any existing `bench-sparc32-smoke`. The latter is rebuilt only by the broad fallback container. After a source/header change, a successful fast rebuild leaves the old smoke executable selected, so RTS-11 remains reproducible on this path.
  - **Fix**: Use one executable with `--smoke`, or apply the same dependency checks and rebuild/publication rules to both artifacts before selection.

- [ ] **RTS-R2-8 — Medium — BUG — Benchmark EXIT trap references an expired local variable**
  - **Where**: `tools/bench_harness.sh:257-301`, `tools/bench_harness.sh:532-535` (`build_guest_bins`).
  - **What breaks / Why**: The EXIT trap stores a deferred reference to local `cname`. After a successful build returns, that local no longer exists. At shell exit, `set -u` makes its expansion fail. Cleanup can emit an unbound-variable error and does not reliably address the intended container. The trap also remains installed for later execution.
  - **Fix**: Scope the trap to a subshell whose lifetime owns the local variable, or maintain explicit invocation-level container ownership. Clear traps after successful cleanup.

- [ ] **RTS-R2-9 — Medium — BUG — Linux benchmark load check selects an unsupported sysctl key**
  - **Where**: `tools/bench_harness.sh:303-319` (`check_calm_host`).
  - **What breaks / Why**: Presence of `sysctl` selects `vm.loadavg`, a Darwin/BSD key. Linux commonly has `sysctl` but exposes load through `/proc/loadavg`. The failed pipeline, combined with `set -euo pipefail`, aborts normal `run` before reaching benchmarks; the `/proc` fallback is never attempted.
  - **Fix**: Select the load source by platform or successful query, validate the numeric result, and fall back to `/proc/loadavg` when appropriate.

- [ ] **RTS-R2-10 — Medium — DEFECT — Catalogue ignores failed summary counters**
  - **Where**: `tools/run_catalogue.sh:79-104`, `tools/run_catalogue.sh:896-907` (`check_parity_no_skip`, `run_repo_gate`).
  - **What breaks / Why**: Despite its updated contract, the checker extracts only `skip`. A delegated command returning zero with `PARITY_SUMMARY ... pass=0 fail=1 gap=0 skip=0` passes this check if no matching FAIL row exists. Smoke mode also accepts an empty log because category validation is disabled there.
  - **Fix**: Validate summary presence and syntax, repository identity, positive pass count, and zero failure/gap counts. Explicitly distinguish a supported non-parity fallback from malformed parity output.

- [ ] **RTS-R2-11 — Medium — DEFECT — Benchmark success does not require complete workload records**
  - **Where**: `tools/bench_harness.sh:349-361` (`check_bench_output`).
  - **What breaks / Why**: Exit zero plus any `ALL_PASS` substring is sufficient. The five workload records, their checksums/statuses, and a valid final timing record are not required; absent timing is printed as `?`. This leaves RTS-3’s requested complete-record validation unfinished. Truncated or incorrectly forwarded output can still receive PASS.
  - **Fix**: Require exactly one valid record for each expected workload and one anchored final summary. Reject missing, duplicate, malformed, or contradictory records.

- [ ] **RTS-R2-12 — Medium — BUG — Concurrent catalogue runs overwrite each other’s evidence**
  - **Where**: `tools/run_catalogue.sh:896-930` (`run_repo_gate`).
  - **What breaks / Why**: Logs use `/tmp/cat-$CMD-$_repo.log` without an invocation identifier. Concurrent runs for the same repository truncate and write the same file. Validation can read another run’s PASS rows or a mixed log, producing false results and destroying diagnostic evidence.
  - **Fix**: Allocate a unique invocation directory and pass its log paths through execution and validation. Preserve failed logs and clean up only owned files.

- [ ] **RTS-R2-13 — Medium — DEFECT — Benchmark container cleanup remains incomplete on timeout and interruption**
  - **Where**: `tools/bench_harness.sh:213-243`, `tools/bench_harness.sh:448-457`, `tools/bench_harness.sh:468-485`.
  - **What breaks / Why**: Fast-path build containers have no cleanup trap or explicit removal after timeout. Runtime containers are removed only after command substitution completes; interrupting the harness bypasses that code. `--rm` removes a container when it exits, but terminating a Docker client does not establish that the daemon-owned workload exited. Removal failures are swallowed without verification.
  - **Fix**: Track all owned container IDs, install invocation-scoped exit/signal cleanup, and verify removal after success, failure, timeout, and interruption.

- [ ] **RTS-R2-14 — Medium — DEFECT — Golden-update failures can return success**
  - **Where**: `tools/parity_contract.sh:89-101` (`parity_check_golden`).
  - **What breaks / Why**: Update mode executes `mkdir` and `cp`, then unconditionally returns zero. When called in an `if` or other tested context, shell `errexit` does not reliably terminate on those failures. Missing input or an unwritable golden can therefore be reported as a successful update.
  - **Fix**: Explicitly propagate directory-creation and copy errors. Copy to a temporary file and atomically rename only after successful completion.

### Low

No additional BUG/DEFECT findings.

## 2. Curated C11 & UB Issues

- [ ] **RTS-R2-15 — Medium — C11 — Fault handlers communicate through ordinary static address objects**
  - **Where**: `tests/p3_torture.c:84-88`, `tests/p3_torture.c:163-172`, `tests/p3_torture.c:529-545`; `tests/tcg/smoke_tcg.c:80-96`, `tests/tcg/smoke_tcg.c:160-175` (`g_segv_addr`, `g_got_addr`).
  - **What breaks / Why**: Both handlers assign ordinary static `uintptr_t` objects that normal execution subsequently reads. These objects have neither the `volatile sig_atomic_t` signal-communication guarantee nor lock-free atomic semantics. The deliberate fault probes necessarily depend on platform extensions, but that does not establish portable C11 signal communication for these address fields.
  - **Fix**: Use a demonstrably lock-free atomic address representation supported by the target, or an explicitly documented platform signal bridge. Verify lock-free support before entering the handler; do not introduce a locking atomic helper there.

No banned-function calls, textual `.c` includes, explicit `x18` references, `_Generic`, or `<threads.h>` references were returned by the source search. All inventoried `.c`/`.h` files are below 900 lines; the largest is `tests/p3_torture.c` at 658 lines. These observations are not compiler or sanitizer validation.

## 3. DRY — Intra-Repo Duplication

- [ ] **RTS-R2-16 — Low — DRY — Translator invocation policy is duplicated across runners**
  - **Where**: `tools/bench_harness.sh:322-347` (`build_rt_args`), `tools/run_grind.sh:83-97` (`resolve_arch_defaults`), `tools/remote_bench.sh:26-88`, `tools/remote_linux_inner.sh:36-68`.
  - **What breaks / Why**: Four paths independently encode engine flags, environment variables, separators, and backend invocation. They already differ: remote `rvrt` interpreter execution uses `--engine interp`, while benchmark/grind construction uses `--interp`; other engines alternate between environment and command-line selection. Each future CLI change requires synchronized edits.
  - **Fix**: Centralize the architecture/backend invocation contract in a repository-local helper, retaining argument boundaries. This is tooling reuse within `rt-series`, not a shared translator C library.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RTS-R2-17 — Low — YAGNI — Fault signal code is recorded but never checked**
  - **Where**: `tests/p3_torture.c:87-87`, `tests/p3_torture.c:167-169`, `tests/p3_torture.c:539-599` (`g_segv_code`, `t_mprotect_munmap`).
  - **What breaks / Why**: `g_segv_code` is write-only. The fixture collects fault provenance but never distinguishes protection faults from unmapped-address faults. Later probes also omit fresh address validation, despite the combined success message claiming fault-address checking.
  - **Fix**: Reset and validate signal number, platform-appropriate code, and fault address for each probe. Otherwise remove unused collection and narrow the advertised coverage.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RTS-R2-18 — Medium — CLEAN — HEAD declares complete remediation despite demonstrably incomplete fixes**
  - **Where**: `DEFECTS.md:14-14`, `DEFECTS.md:28-29` (remediation status and `rt-series` verification row).
  - **What breaks / Why**: HEAD declares all findings resolved and `rt-series` fully verified. Current code still has incomplete RTS-4 architecture routing, RTS-6 qualification evidence, RTS-11 freshness handling, and RTS-16 signal coverage. Reported passing gates cannot establish those missing semantics.
  - **Fix**: Reopen the affected original findings and distinguish implemented changes, executed checks, and remaining verification gaps. Retain historical results without presenting them as proof of complete remediation.

The 900-line C/header ceiling is satisfied. The 1,059-line catalogue shell script is outside that specific ceiling; its size alone is not counted as a violation.