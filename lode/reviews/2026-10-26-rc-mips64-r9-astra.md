RC-U12-mips64-r9 at `82b6cd6` still has one **P1** issue. Findings 1 and 3 are resolved; finding 2 is not fully closed.

1. **Resolved — Cross-process table serialization.** The `MAP_SHARED` atomic lock protects registration and compaction. When the pipe succeeds, the parent retains exclusion until child registration finishes. See [vm_file.c:89](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:89).

2. **P1 — Pending-child shrink history can still expire when `pipe()` fails.** The fallback releases the shared lock before fork, permitting the parent to proceed before child registration. The replacement history unconditionally evicts its oldest entry when full. See [fallback:145](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:145) and [eviction:289](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:289).

   Source-derived counterexample: start with an 8192-byte private mapping containing a dirty second page. Let `pipe()` fail with `EMFILE`, fork succeed, and the child remain unscheduled. The parent truncates to zero, then grows through 32 sizes: `256, 512, …, 8192`. This evicts the zero-size watermark. Child registration finds no history entry old enough and retains its original minimum, so reconciliation preserves the dirty page that truncation should have discarded. This violates Rev 4 §5.1 and requires only two mapping records.

3. **Resolved — Signal handler PC preservation.** The new guard detects cleared `in_delay_slot`, clears the pending target, and bypasses `mips_npc_resume_step()`, preserving the delivered handler PC. See [mem_recover.c:503](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:503).

`git diff --check ad705b2..82b6cd6`: **PASS**, exit 0, no diagnostics. No files modified or suites rerun; supplied runtime results were reused. The remaining counterexample is from source inspection.

Verdict: FAIL