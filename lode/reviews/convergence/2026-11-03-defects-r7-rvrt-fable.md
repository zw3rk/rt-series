## Review of commit 55ad5c0 (Round-7 remediation RV-R7-1..5)

**Verdict: all five items are VERIFIED. No regressions found. No regression tests were added for four of the five items.**

The repository was not modified. Existing suites were run inside `nix develop`, and two throwaway probes were built against both this commit and its parent 2b6759c so each fix is shown to discriminate.

### Classification

| Item | Severity | Classification | Evidence |
|---|---|---|---|
| RV-R7-1 RV32 syscall result canonicalization | HIGH | VERIFIED (code read; not executed) | Masking at the shared retirement point in `src/runtime/runtime_main_syscall.c:755`, after all raw-value comparisons. Signal delivery also canonicalizes x1, x2, a0, a1, a2. |
| RV-R7-2 FLT/FLE condition codes | HIGH | VERIFIED (executed) | `src/dbt_emit_fp.c:676` now emits LO for FLT and LS for FLE. Probe passes on this commit, parent fails with FLE(1,1)=0. |
| RV-R7-3 C.FLWSP f0 rejected | MEDIUM | VERIFIED (executed) | Rejection removed at `src/core/rv32_expand.c:224`. New unit case 0x6002 passes here and fails on the parent. C.LWSP x0 stays illegal. |
| RV-R7-4 single-precision reload drops boxing check | MEDIUM | VERIFIED (executed) | `src/darwin_dbt_emit.c:116` repeats the boxing check on rejoin. Probe passes here; parent yields f3=2.0 instead of canonical NaN. |
| RV-R7-5 overflowing altstack frame written before rejection | MEDIUM | VERIFIED (executed) | `src/linux/signal.c:782` gates both frame writers on `valid`. Probe passes here; parent writes 576 bytes below the alternate stack. |

### Per-item notes

**RV-R7-1.** The leaf dispatcher is only reachable through the worker syscall function, so one retirement point covers both files named in the review. All internal raw-value checks sit above the mask: file-call completion, the `-EINTR` interrupted-read comparison, and the futex EINTR restart test. Early `break` paths bypass the mask only for process exit or a sigreturn, and the RV32 frame reader already zero-extends every register. The Darwin runtime already masked a0 before this commit. Other external writers, such as clone child setup and restart argument reloads, copy values that were canonical at entry. Limitation: the Linux runtime cannot run on this macOS host and no Lima runner is installed, so this path was verified by reading only.

**RV-R7-2.** The `cset` helper inverts the condition internally, so passing LO (0x3) and LS (0x9) yields CSET LO and CSET LS. Both are ordered conditions after FCMP, so the existing VS-based unordered mask is now redundant but harmless. The probe exercised S and D precision with less, equal, greater, and NaN on either side for FLT, FLE, and FEQ, and compared against the interpreter.

**RV-R7-3.** The DBT and JIT both decode RV32 compressed forms through `rv32_expand`, so the fix covers all engines. The RV64 expander already accepted C.FLDSP f0.

**RV-R7-4.** The rejoin check uses w2 as scratch, which is dead after both helper calls. For FP single loads the post-load snapshot marks the destination as boxed, which is correct because the helper writes a boxed value. The reload for a dirty single flushed with raw bits still re-checks and finds the upper half all ones, so no value changes. The `test-u5b-dbt-mem` emission-word checks still pass with the extra words.

**RV-R7-5.** The `already_on_stack` overflow check matches Linux's `get_sigframe`. When switching onto the alternate stack neither Linux nor rvrt checks for underflow below the base, so that pre-existing behavior is unchanged and consistent with the kernel.

### Test results

```
u5c-rv32-units          passed   (includes new 0x6002 and 0x4002 cases)
test-core               passed
test-core-fp            passed
test-u5b-dbt-mem        passed
test-u5b-dbt-cache      passed
test-u5b-difftest       passed
test-linux-signal       passed
test-signal-frame       passed
test-linux-restart      passed
test-linux-signal-suspend passed
test-core-atomic        FAILS TO COMPILE (pre-existing, see below)
```

Probe results, fixed commit vs parent:

```
probe_dbt    fixed: passed     parent: FLE(1.0,1.0) returned 0; f3 = 0xffffffff40000000 (2.0)
probe_signal fixed: passed     parent: 576 bytes modified below alternate stack
```

### New bugs or regressions

None attributable to this commit.

- **Pre-existing, not a regression.** `test-core-atomic` fails to compile on both this commit and its parent because `test/core_atomic.c:21` does not handle the `RV_FAULT_RETRY` enum value under `-Wswitch -Werror`. That value was introduced by earlier memory-refresh commits.
- **Cosmetic.** The syscall trace line still prints the raw 64-bit result before RV32 masking.

### Gaps worth closing

- **No regression tests for RV-R7-1, R7-2, R7-4, R7-5.** The review asked for emitted-code coverage of R7-2 and R7-4 and the commit added only the R7-3 expansion case. The probes under `/tmp/rvrt-r7-probes/` already discriminate and could be folded into `test/u5b_difftest.c` and `test/test_linux_signal.c`.
- **R7-3 coverage is expansion-only.** The review asked for a load into f0 with NaN-boxing to be executed; only decoding is checked.
- **Checklist not updated.** Section 6 of `rt-series/DEFECTS.md` still shows `0 / 5` resolved with all boxes unchecked.
