**RC-U12-mips64-r6 at `eb16420` still has two findings:**

- **P1 — Remap restores stale permissions.** [vm_file.c:779](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:779) recreates native mappings using the original `m->prot`; `mips_mem_protect` updates only host permissions and `g_regions`. A shared mapping created read-only, changed to read/write, then moved becomes host-read-only while guest metadata remains writable. [Rollback restoration:698](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:698) has the same defect and remaps the entire overlapping file span. This violates Rev 4 §4.5’s state-preservation requirement. Restore current per-region permissions.

- **P2 — Fork preparation leaks parent descriptors.** [vm_file.c:116](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:116) duplicates mapping descriptors before fork, but `vm_atfork_parent` never closes the parent copies. Child registration transfers record ownership to the child, leaving those parent descriptors untracked. Repeated forks can exhaust descriptors; failed forks also leave pending mapping records.

Item 1’s full-probe retry, item 3b’s EOF-safe snapshot path, and item 4’s removal of bounded truncation history pass source inspection. Item 3a remains incomplete.

`git diff --check ad705b2..eb16420` passed. Accepted the supplied execution results; no tests or Docker containers rerun, and no files changed.

Verdict: FAIL