**Round 3 verdict: changes required.** Six findings remain at `37a9af0`, including a path that credits host tests to foreign translators.

Reviewed recent history, the Round-2 and follow-up changes, shared headers, fixtures, Makefile, and relevant runners in six shell inspection turns. No builds, tests, containers, or QEMU were run. This repository has no `src/`; translator ISA, VM, and backend implementations therefore remain outside this audit’s verified scope.

**RTS-R3-1 — Weekly upstream checks can falsely qualify foreign translators**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:690`
- **Evidence & Root Cause:** Each foreign-architecture job executes plain `make -C "$UPSTREAM_CHECK_DIR" check`. Neither the selected translator nor a target-specific execution hook is passed. Success increments `GRIND_PASS` under `CURRENT_ARCH`. With `--arch all`, the same host check can produce ten architecture-labelled passes, even when translator-dependent suites skip.
- **Concrete Fix:** Require an explicit target-aware upstream test adapter for foreign jobs. Pass the selected engine, guest artifacts, and execution wrapper through that adapter. Without it, report SKIP; reserve unwrapped `make check` for `--arch host`.

**RTS-R3-2 — Grind bypasses the repaired RVRT host-policy selector**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/run_grind.sh:174`
- **Evidence & Root Cause:** The `hl` wrapper is constructed as `$_hl_bin $_interp_cmd` or `$_hl_bin $_dbt_cmd`, omitting `--rvrt-native`. HEAD repairs this selector in `rt_run_bounded_hl`, but grind never calls that helper. The inspected `hyper-linux/src/hl.c:854` selects RVRT policy from explicit RVRT launch state; ordinary invocation of an AArch64 translator does not itself establish that state.
- **Concrete Fix:** Route grind through a common executable wrapper that uses `rt_run_bounded_hl`, including its RVRT selector and guest environment. Avoid separately assembling a second `hl` command policy.

**RTS-R3-3 — Reservation probe does not isolate signal-return invalidation**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tests/p3_torture.c:217`
- **Evidence & Root Cause:** Every architecture branch places a libc `raise()` call between LL and SC. That interval also contains nested signal delivery and `atomic_store(&g_cas_cell, 2)` in `usr1_handler`. Library synchronization, handler atomics, and intervening execution can destroy the reservation independently of the signal-return behavior under review. The test accepts any SC failure and has no successful-reservation control, so an implementation that always fails SC also passes this probe.
- **Concrete Fix:** Separate this from the GPR/CAS fixture. Use a minimal dedicated handler and architecture-specific assembly around a controlled delivery boundary. Add a bounded no-signal control demonstrating successful LL/SC, and document precisely which boundary the interrupted case validates.

**RTS-R3-4 — TestFloat defaults to interpreter-only coverage**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:373`
- **Evidence & Root Cause:** `_tf_wrap="${GRIND_INTERP:-${GRIND_DBT:-}}"` selects the interpreter whenever both default wrappers exist. Consequently, the TestFloat suite can pass without executing the DBT FPU implementation.
- **Concrete Fix:** Feed the same generated vectors to both configured engines and report their outcomes separately. Require both for dual-engine qualification; explicitly label any intentionally single-engine run.

**RTS-R3-5 — Uniform guest builder retains nonterminating signal traps**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/build_uniform_guests.sh:52`
- **Evidence & Root Cause:** `trap cleanup_containers EXIT INT TERM` handles INT and TERM by cleaning containers and returning. It does not explicitly terminate the script, so interruption can resume the build sequence depending on the interrupted command’s status. Cleanup also suppresses removal errors, and its EXIT path does not perform the final lingering-container check. The corresponding benchmark trap was repaired in HEAD, leaving this duplicate behavior inconsistent.
- **Concrete Fix:** Add terminating INT/TERM handlers with exit codes 130/143. On EXIT, preserve the original failure status, verify owned-container removal, and turn cleanup failure into a nonzero result.

**RTS-R3-6 — Build recipes omit the requested general warning gate**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:9`
- **Evidence & Root Cause:** Default `CFLAGS` contain `-Werror=vla` but omit `-Werror`. The same omission appears in `tools/build_uniform_guests.sh:67` and benchmark compilation recipes. Warnings other than VLAs therefore do not fail these builds.
- **Concrete Fix:** Add `-Werror` to first-party host and guest compilation flags, keeping necessary architecture-specific exceptions narrow and explicit.

The inspected C/H files satisfy the 900-line limit; the largest is `tests/p3_torture.c` at 819 lines. The hygiene search found no banned string functions, unity `.c` includes, `_Generic`, `<threads.h>`, or explicit `x18`/`w18` references. These are static observations, not compilation evidence.

- [ ] **RTS-R3-1:** Prevent host upstream checks from qualifying foreign translators.
- [ ] **RTS-R3-2:** Preserve RVRT host policy in grind execution.
- [ ] **RTS-R3-3:** Isolate reservation invalidation and add a successful control.
- [ ] **RTS-R3-4:** Run TestFloat against both engines.
- [ ] **RTS-R3-5:** Terminate builder signal traps and verify cleanup.
- [ ] **RTS-R3-6:** Enforce general `-Werror` for first-party builds.