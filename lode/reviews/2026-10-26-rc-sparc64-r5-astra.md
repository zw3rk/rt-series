Confirmed clean `master` at `2f2ce13`. All three cited Round-4 gaps are **RESOLVED within the requested static-review scope**.

| Finding | Status | Evidence |
|---|---|---|
| **#4 Subrange mremap + relocation growth** | **RESOLVED** | Splits preserve unmoved head/tail ranges and rebase the middle with adjusted file offsets: [guest_run_sysmem_file.c:468](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem_file.c:468). Growth covers the extension for both whole entries and split pieces without requiring `dest == old_base`: [line 447](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem_file.c:447), [line 490](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem_file.c:490). |
| **#5 Populate states + runtime COW promotion** | **RESOLVED** | Populate receives `&lo`/`&hi` and records the resulting state: [guest_run_sysmem_file.c:650](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem_file.c:650). Runtime writes consume and promote `COW_CLEAN` states: [line 615](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem_file.c:615), wired through guest stores/atomics at [guest_run_mem.c:77](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_mem.c:77) and syscall copyout at [guest_run_sysmem.c:101](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem.c:101). |
| **A1 Pre-effect continuation** | **RESOLVED** | JMPL/RETURN target is stashed before the destination-register write, window restore, and delay slot: [emit_int.c:631](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_int.c:631). Dispatcher reads that snapshot: [dbt.c:404](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:404); declaration and lifetime contract: [mem_sites.h:56](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/mem_sites.h:56). |

Existing registry capacity limits remain. No files modified; no builds, tests, or Docker run.

Verdict: PASS