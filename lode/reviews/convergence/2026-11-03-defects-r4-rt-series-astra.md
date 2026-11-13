Found **7 actionable issues** at `5e6cbc0`: **6 Medium, 1 Low**. Findings concern this repository’s harness and fixtures; there is no tracked `src/` translator implementation here.

The Round-3 changes add strict warning flags, separate TestFloat engine runs, require foreign upstream adapters, and restrict `hl` rerouting to automatically selected wrappers. The follow-up LL/SC guard and cleanup verification still have gaps.

**RTS-R4-1 — LL/SC capability guard enables unsupported probe implementations**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tests/p3_llsc.h:26`
- **Evidence & Root Cause:** `P3_HAVE_LLSC` accepts every `__arm__` and `__riscv` target. However, `llsc_pair()` implements ARM only when `__ARM_ARCH >= 6` (line 69), and RISC-V only with `__riscv_atomic` (line 80). Other configurations reach the fallback at line 131, which always sets `stored = 0`. The no-signal control therefore fails all 32 attempts, and `t_llsc_reservation()` reports a translator failure despite executing no LL/SC instructions. This contradicts the follow-up’s claimed exact architecture guard.
- **Concrete Fix:** Make `P3_HAVE_LLSC` match the implementation predicates exactly, including ARM version, RISC-V atomic support, and consistent PowerPC/LoongArch aliases. Make an enabled-but-unimplemented branch a preprocessing error rather than a silent fallback.

**RTS-R4-2 — Extracted LL/SC header does not invalidate guest binaries**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/build_uniform_guests.sh:112`
- **Evidence & Root Cause:** `already_built()` checks only the modification times of `p3_torture.c` and `smoke_tcg.c`. Since `b4f5131`, the reservation implementation lives in `tests/p3_llsc.h`. Changing that header alone leaves every existing P3 guest classified as up to date, allowing qualification to exercise obsolete probe code.
- **Concrete Fix:** Add `tests/p3_llsc.h` to the P3 dependency check. Also invalidate artifacts when the build recipe or compilation flags change, using a dependency/build stamp or equivalent explicit tracking.

**RTS-R4-3 — Container cleanup verification treats inspection failure as success**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/build_uniform_guests.sh:67`
- **Evidence & Root Cause:** Both cleanup and verification suppress `docker ps` failures with `|| true` (lines 47 and 67). Verification interprets empty output as no remaining containers. Failed `docker inspect` calls are likewise converted to empty names, which cannot match the ownership suffix. Consequently, `on_uniform_exit()` can preserve exit status zero even when container removal could not be verified.
- **Concrete Fix:** Track the exact container names or IDs created by this invocation. Propagate listing failures and distinguish a confirmed absent container from an inspection failure. Bound cleanup and inspection commands with timeouts.

**RTS-R4-4 — Sub-page permission fixture never checks write protection**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tests/tcg/smoke_tcg.c:270`
- **Evidence & Root Cause:** `t_test_mmap()` requests RW/RX/RO/NONE pages, but checks only the RW page and a read fault on NONE. It never accesses RX or RO to verify readable contents or rejected writes, yet reports `test-mmap sub-page permissions`. A backend that incorrectly leaves both RX and RO writable passes this fixture.
- **Concrete Fix:** Initialize all pages before protection changes. Use explicit volatile accesses to verify reads from RX/RO and write faults on each, checking fault addresses. Recheck the neighboring RW page after each protection transition to detect widened host-page permissions.

**RTS-R4-5 — Grind compilation and generators can run without a time limit**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:361`
- **Evidence & Root Cause:** Guest execution is bounded, but GCC torture compilation is not. The same omission affects builtin compilation at line 537, Csmith generation/compilation at lines 752–753, and Yarpgen generation/compilation at lines 767, 783, and 794. A stalled generator or compiler prevents the suite from reaching its bounded execution and summary paths.
- **Concrete Fix:** Apply explicit `timeout --kill-after=30s` budgets to each generator and compiler invocation. Report timeout separately from an unsupported-source compilation skip, and clean up temporary artifacts on interruption.

**RTS-R4-6 — Remote benchmark parser returns success for invalid results**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/remote_bench_common.sh:141`
- **Evidence & Root Cause:** `parse_and_print()` extracts fields without validating record counts or workload status. Missing fields become `-`; a missing summary becomes `FAIL`. Its final `printf` still returns success. Thus an executable that exits zero with empty or malformed output can produce a failed-looking result row while `remote_linux_inner.sh` and `remote_bench.sh` complete successfully. The local harness has substantially stricter validation at `tools/bench_harness.sh:388`.
- **Concrete Fix:** Move benchmark record validation into a shared repo-local helper. Require exactly one valid PASS record for each workload and one valid ALL_PASS summary. Have remote callers propagate validation failure as a nonzero exit status.

**RTS-R4-7 — Signal-safe fault-address encoding is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `tests/p3_torture.c:90`
- **Evidence & Root Cause:** The three-word, 22-bit signal-address bridge, width assertion, store routine, and load routine are duplicated in `tests/tcg/smoke_tcg.c:84`. Only the names differ. Changes to this portability-sensitive representation must currently be synchronized manually.
- **Concrete Fix:** Introduce one repo-local test header containing the bridge type, assertion, and static inline encode/decode helpers. Keep a separate bridge instance in each fixture.

Seven shell inspection invocations were used, including the requested history commands, source-filtered commit diffs, numbered source reads, searches, and line counts. No builds, tests, containers, or QEMU were run; no files changed. The requested unrestricted `git show HEAD` exposed Markdown diffs; those were not used as finding evidence.

All inspected C/header files are below 900 lines; the largest is `tests/p3_torture.c` at 750. The targeted scan found no prohibited string calls, `.c` inclusions, or explicit `x18`/`w18` operands. No additional CLEAN or YAGNI finding was sufficiently established. These static checks do not qualify sibling translator semantics.

- [ ] **RTS-R4-1:** Match LL/SC capability guards to implemented probes.
- [ ] **RTS-R4-2:** Rebuild uniform guests when included headers or recipes change.
- [ ] **RTS-R4-3:** Fail cleanup verification when container state cannot be established.
- [ ] **RTS-R4-4:** Test RX/RO write rejection and adjacent-page isolation.
- [ ] **RTS-R4-5:** Bound grind generators and compiler invocations.
- [ ] **RTS-R4-6:** Validate remote benchmark records and propagate failure.
- [ ] **RTS-R4-7:** Unify the signal-safe fault-address bridge.