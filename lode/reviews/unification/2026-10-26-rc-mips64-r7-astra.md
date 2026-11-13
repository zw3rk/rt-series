Source review at `21cc023` found four issues:

- **P1 — Child mapping registration races with parent changes.** [vm_file.c:161](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:161) copies live parent records after fork. If the parent unmaps before the child registers, the inherited mapping loses file tracking; later truncation cannot enforce EOF on its private pages. Preserve fork-time mapping metadata.

- **P1 — A later fork erases an outstanding child’s shrink history.** [vm_file.c:109](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:109) resets the shared `fork_min_size`. Fork A → shrink → regrow → fork B → A registers can leave A’s inherited dirty bytes intact, violating Rev 4 §5.1. Preserve the watermark separately for each outstanding fork.

- **P1 — U0 delay-slot faults save the wrong PC.** [mem_recover.c:420](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:420) delivers alignment and permission faults before restoring `in_delay_slot`. Consequently, the signal frame records the slot PC instead of the branch PC, losing branch behavior on return.

- **P2 — Remap still loses subregion tags.** [mem_table.c:715](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem_table.c:715) passes saved names to `insert_region`, but its merge conditions compare only permissions. Adjacent regions with equal permissions and different tags collapse.

The original stale-permission restoration and parent descriptor-leak fixes are present: native remap/rollback reapplies current region permissions, rollback bounds its slices, and fork preparation no longer duplicates descriptors or creates pending records. The defects above prevent full acceptance.

`git diff --check eb16420..21cc023`: **PASS**. Accepted the supplied test results; no tests or Docker containers rerun. No files changed.

Verdict: FAIL