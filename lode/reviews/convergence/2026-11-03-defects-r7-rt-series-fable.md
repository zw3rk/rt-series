Review complete. Seven of eight items verified, one partial, and one newly reachable defect found. The full report is saved at `lode/reviews/2026-11-03-defects-r7-rt-series-fable.md` (the empty untracked file that was waiting for it).

# Verification report: rt-series commit `005f3c4` vs. RTS-R7-1..8

**Method.** Diff review of the three changed files against the astra review and DEFECTS.md Section 11. Cross-checked against the frozen sibling headers in `sparc32rt` and `mips64rt`, the upstream Berkeley TestFloat-3 sources and docs, and upstream lmbench `lat_proc.c`. The torture test was built on the macOS AArch64 host with the documented flags and run. Not run: `run_grind.sh` (no TestFloat or lmbench binaries here), any guest translator.

## Summary

| Item | Severity | Verdict | Reason |
|---|---|---|---|
| RTS-R7-1 TestFloat pipeline | HIGH | **PARTIAL** | Invocation and mandatory guest-runner stage fixed, but the retained pass/fail grep matches the verifier's clean-run summary, so a correct run is reported as FAIL. |
| RTS-R7-2 volatile `memcmp` UB | MEDIUM | **VERIFIED** | Plain `double` snapshots compared. Builds clean under `-pedantic -Werror`. |
| RTS-R7-3 `siginfo` not checked | MEDIUM | **VERIFIED** | Non-null `info` required. Handler `signo` and `info->si_signo` asserted independently. `si_code` check retained. |
| RTS-R7-4 nested alt-stack delivery | MEDIUM | **VERIFIED** | Alt stack installed first, both handlers `SA_ONSTACK`, `raise` rc, count, nesting order and `SS_ONSTACK` residency all asserted. |
| RTS-R7-5 SPARC V8 annul rule | MEDIUM | **VERIFIED** | Untaken-conditional, taken-conditional and `ba,a` documented separately with `pc`/`npc`. |
| RTS-R7-6 MIPS64 N64/N32 ucontext | MEDIUM | **VERIFIED** | 24 B prefix, N64 `uc_mcontext` at 40, N32 at 24. Matches the frozen header's static asserts. |
| RTS-R7-7 lmbench arguments | MEDIUM | **VERIFIED** | Per-tool dispatch with a prepared 4 MiB page-fault file. `procedure` confirmed as the exact upstream keyword. |
| RTS-R7-8 SPARC32 frame size | LOW | **VERIFIED** | 344 B, extent `0x158`. Matches `SPARC32_RT_SIGFRAME_SIZE 344U` and every offset in the frozen header. |

## RTS-R7-1 detail

**Fixed as prescribed.** The generator now runs in type mode with `-n` and a type derived from the op. A new `TESTFLOAT_RUNNER` executes the operation on the guest, and the suite skips loudly without one. The host verifier receives `-r<mode> <function>`. A positive result-line count is required. I confirmed against upstream source that `-n` is parsed as used, that a trailing `1` after an integer type is silently absorbed, and that all six rounding spellings are accepted by the verifier.

**Why PARTIAL.** The retained check at `tools/run_grind.sh:454` is

```sh
grep -Eqi 'fail|error|mismatch' /tmp/grind_testfloat_$$.log
```

Upstream `verCases_common.c` prints `In N tests, no errors found in <function>, rounding <mode>.` to stdout on a clean run. The `error` alternative matches `no errors found`, so every clean verification reports `verifier reported failures`. This regex predates the commit, but the corrected pipeline now makes it the gate. Fix: trust the exit status (`verCases_exitWithStatus` already returns failure on any error) or anchor on `^Errors found in`.

## New findings

1. **MEDIUM, counts against R7-1.** Clean TestFloat runs misclassified as failures, as above.
2. **LOW.** Runner stderr and verifier output share one log path with `>`, so a verifier failure overwrites the runner diagnostics.
3. **LOW.** The new env contract (`TESTFLOAT_RUNNER`, `TESTFLOAT_OP`, `TESTFLOAT_ROUNDING`, `TESTFLOAT_TYPE`) lives only in script comments. The catalogue still describes the old two-stage pipeline, and no runner exists in-tree, so the suite skips everywhere until one is written.
4. **INFO.** `si_code == 0` is still accepted for BSD/macOS portability, so a Linux translator reporting zero would pass that sub-check. Pre-existing.
5. **INFO.** DEFECTS.md Section 11 checkboxes remain at 0 of 8 and await this verification.

**No regressions.** All seven torture sub-tests pass on the host (pass=7 fail=0 skip=0). Alt-stack teardown runs on every exit path, and no other test depends on the SIGUSR1/SIGUSR2 dispositions. Residual nits in the report: `memset` inside handlers is not formally async-signal-safe, and the lmbench pass criterion is still exit 0 plus non-empty output rather than per-tool output validation.

**Next.** Fix the grep at `run_grind.sh:454` to close R7-1, then tick Section 11 in DEFECTS.md and commit the review file.
exitWithStatus` returns `EXIT_FAILURE` whenever any error was recorded), or anchor on `^Errors found in`.

Residuals (low):
- `:425,431` runner stderr and `:447` verifier output share `/tmp/grind_testfloat_$$.log` with `>`; a verifier failure overwrites the runner diagnostics.
- One op/rounding per invocation. A sweep is only reachable by re-running with different `TESTFLOAT_OP`/`TESTFLOAT_ROUNDING`; acceptable but worth a note in `docs/CATALOGUE-TODO.md`, which still describes the old two-stage pipeline and does not mention `TESTFLOAT_RUNNER`. No runner exists in-tree, so the suite SKIPs everywhere until one is written.

## RTS-R7-2 — volatile `memcmp` — VERIFIED

`tests/p3_torture.c:475-484`: `b` and `ref` are read into `double b_snap`/`ref_snap` and the snapshots are compared with `memcmp`. No volatile-discarding cast remains. Host build with `-pedantic -Werror` is clean and `sig-frame-fpr` passes.

## RTS-R7-3 — `siginfo` checks — VERIFIED

- `:117-126` handler records `g_usr1_has_info`, `g_usr1_info_signo = info->si_signo` and `si_code` only when `info != NULL`.
- `:367-378` asserts handler `signo == SIGUSR1` ("handler signo mismatch"), `g_usr1_has_info` ("missing siginfo"), and `info->si_signo == SIGUSR1` ("si_signo mismatch") as three independent checks; `:381-389` retains the kill-family `si_code` check.
- All flags reset at `:297-307` before the raise.

Residual (low, pre-existing, portability-motivated): `si_code == 0` is still accepted alongside `SI_USER`/`SI_TKILL` for BSD/macOS, so a Linux translator reporting `si_code 0` would still pass this particular sub-check.

## RTS-R7-4 — nested alternate-stack delivery — VERIFIED

- `:282-290` installs `g_nest_stack` (64 KiB static) via `sigaltstack` before any handler; `:291-292` installs both `SIGUSR1` and `SIGUSR2` with `SA_ONSTACK`.
- `:153` captures `raise(SIGUSR2)` return; `:160-172` nested handler counts deliveries, records `g_nest_depth == 1` (order) and `SS_ONSTACK` residency; `:128-131` SIGUSR1 handler records its own residency.
- `:394-409` asserts `raise` rc 0, exactly one SIGUSR2, nested-inside-USR1 ordering, and alt-stack residency for both handlers.
- `:173-184` `drop_nest_stack` is called on the sigaction-skip path (`:295`), the raise-failure path (`:333`), and the normal path (`:340`), before any reporting. The disabled alt stack does not interfere with `t_sigaltstack` (`:508`), which installs its own stack on `SIGURG`.
- Header claim at `:8` is now true. Host run: `sig-frame-gpr ... nested altstack ...` PASS.

Notes: residency is proven via `sigaltstack(NULL,&ss)`/`SS_ONSTACK`, the same technique as the existing `t_sigaltstack`, not via SP range; `g_nest_depth` is never reset but the increment/decrement is balanced; `memset` inside handlers is not on the POSIX async-signal-safe list (harmless in practice, synchronous `raise`).

## RTS-R7-5 — SPARC V8 annul rule — VERIFIED

`lode/ISA-TRAP-AND-ABI-MATRIX.md:37` now lists: untaken conditional (delay annulled, `pc = npc + 4, npc = npc + 8`), taken conditional (delay executes, `pc = target, npc = target + 4`), and unconditional `ba,a` (delay skipped, `pc = target, npc = target + 4`). This matches SPARC V8 B.21. Nit: the taken-conditional values describe state after the delay slot retires; the immediate post-branch state is `pc = npc, npc = target`. Not misleading in context.

## RTS-R7-6 — MIPS64 N64/N32 signal frame — VERIFIED

`:58` now states the 24 B prefix, 64-bit `uc_flags`/`uc_link`/stack with `uc_mcontext` at 40 for N64, 32-bit fields with `uc_mcontext` at 24 for N32. Matches `sigframe_mips64rt.h` static asserts (`N64 uc_mcontext == 40`, `N32 uc_mcontext == 24` with a 4 B pad after the 12 B N32 `stack_t`, `rs_info` at 24, `rs_uc` at 152 for both). Frame totals (808/792) are not in the row; not required.

## RTS-R7-7 — lmbench arguments — VERIFIED

`tools/run_grind.sh:718-731`: `lat_syscall -P 1 null`, `lat_proc -P 1 procedure` (exact `strcmp` keyword upstream), `lat_ctx -P 1 2`, `lat_pagefault -P 1 <4 MiB zero file>` created with `dd` and removed at `:742`; setup failure FAILs and `continue`s. `set -eu` safe (`_lm_pf` only expanded on the `lat_pagefault` arm). Residual: the pass criterion is still "exit 0 and non-empty output"; the astra remediation also asked to validate each tool's completion output. Low value here because lmbench exits non-zero on usage errors.

## RTS-R7-8 — SPARC32 frame size — VERIFIED

`:55` now reads 344 B with `rwin_save_ptr` at `0x154` giving extent `0x158`, and distinguishes structure size from stack-placement padding. Matches `SPARC32_RT_SIGFRAME_SIZE 344U` and `SPARC32_RT_OFF_STACK 0x144`, `_EXTRA_SIZE 0x150`, `_RWIN_SAVE 0x154` in the frozen header.

---

## New findings and regressions

1. **MEDIUM (counts against RTS-R7-1)** — `tools/run_grind.sh:454`: `grep -Eqi 'fail|error|mismatch'` matches the verifier's clean-run line `In N tests, no errors found in ...`, so a correct TestFloat run is reported as `verifier reported failures`. Pre-existing regex, newly reachable now that the pipeline is valid.
2. **LOW** — `tools/run_grind.sh:425/431/447`: runner stderr log is overwritten by the verifier log; diagnostics lost on verifier failure.
3. **LOW** — New env contract (`TESTFLOAT_RUNNER`, `TESTFLOAT_OP`, `TESTFLOAT_ROUNDING`, `TESTFLOAT_TYPE`) is documented only in script comments; `docs/CATALOGUE-TODO.md` still describes `testfloat_gen | guest testfloat_ver`. No in-tree runner exists, so the suite SKIPs until one is provided (correct, but should be visible in the catalogue).
4. **INFO** — `DEFECTS.md` Section 11 checkboxes remain `0 / 8`; to be updated with this verification.
5. **No regressions found** in `tests/p3_torture.c`: all seven sub-tests PASS on the host (`pass=7 fail=0 skip=0`), alt-stack teardown is complete on every path, and no other test depends on the `SIGUSR1`/`SIGUSR2` dispositions.

## Evidence

```
cc -std=c11 -Wall -Wextra -Werror -Werror=vla -pedantic -O1 -pthread tests/p3_torture.c -o /tmp/rts-r7-review/p3_torture   # rc=0
/tmp/rts-r7-review/p3_torture
PASS [p3]: sig-frame-gpr si_signo/si_code/ucontext + nested altstack + stolen reservation
PASS [p3]: llsc-reservation control stores; signal return clears
PASS [p3]: sig-frame-fpr FP env + values survive async handler
PASS [p3]: sigaltstack SS_ONSTACK verified
PASS [p3]: unaligned-cross-page straddling load/store exact
PASS [p3]: mprotect/munmap immediacy + si_addr page check
PASS [p3]: atomic-race 2x200000 fetch_add exact
P3_TORTURE RESULT: pass=7 fail=0 skip=0
```

Not run: `tools/run_grind.sh` (no TestFloat/lmbench binaries on this host; `shellcheck` unavailable), any guest translator.
