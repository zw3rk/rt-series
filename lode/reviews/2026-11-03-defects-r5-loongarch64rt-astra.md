Found **9 concrete issues**. This was a static audit using **eight shell invocations**; no Markdown files, builds, tests, Docker, or QEMU were run. No files changed. Local tooling is in `tests/`; shared tooling is in `../rt-series/tools/`.

1. **[LA64-R5-1] BUG — Hole selection can overlap an existing arena mapping.**  
   **Location:** [src/os/mem_min.c:707](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:707), [src/os/syscalls_mem.c:322](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:322).  
   `la64_mem_find_hole()` checks arena occupancy only at `cand`. If the first page is free but a later page overlaps an arena mapping, it returns the occupied span. `sys_mmap()` then falls through to `la64_mem_map()`, whose overlap checks cover only its own region table. A non-fixed hinted mapping can therefore create overlapping guest mappings with different backing stores.  
   **Fix:** Check the entire candidate range against both ownership tables, advance past every intersecting mapping, and repeat the check under the mutation lock.

2. **[LA64-R5-2] BUG / YAGNI — Shared-map store propagation is implemented but never called.**  
   **Location:** [src/vm/vm_file_sync.c:208](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:208), [src/interp/interp_mem.h:102](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:102), [src/dbt/dbt_mem.c:298](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:298).  
   The repository-wide C/header search finds only the declaration and definition of `vmfile_note_store()`. Interpreter stores never notify it, and DBT writable TLB entries bypass it too. On staged shared mappings, a store through one alias remains invisible through another until later synchronization. The dirty-tracking machinery consequently cannot distinguish guest stores from external file changes reliably.  
   **Fix:** Connect post-store notification to scalar, vector, atomic, and syscall copyout paths. Keep staged shared pages off the unrestricted DBT store path unless emitted stores perform equivalent tracking.

3. **[LA64-R5-3] BUG — Inode-level descriptor reuse substitutes the wrong access mode.**  
   **Location:** [src/vm/vm_file.c:362](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:362), [src/vm/vm_file.c:512](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:512), [src/vm/vm_file.c:656](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:656).  
   Registration retains the first process-local descriptor for an inode. Subsequent mappings prefer that descriptor over the descriptor supplied by the caller. If a write notification first registers an `O_WRONLY` descriptor, a later private mapping through a readable descriptor attempts `pread` on the cached write-only descriptor and fails. Conversely, a cached writable descriptor can bypass restrictions of a later read-only mapping descriptor.  
   **Fix:** Validate mapping rights against the supplied descriptor and retain suitable descriptors per mapping or capability. Inode identity alone does not establish equivalent descriptor permissions.

4. **[LA64-R5-4] BUG — Outside-arena file mappings incorrectly require read permission.**  
   **Location:** [src/os/syscalls_mem.c:178](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:178), [src/os/syscalls_mem.c:186](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:186).  
   `mmap_file_fill()` installs the final guest protection before tracking obtains the backing pointer using `la64_mem_ptr(..., 0)`. That lookup requires guest read permission. A valid private file mapping outside the arena with `PROT_NONE`, write-only, or execute-only protection is unmapped and reported as `ENOMEM`.  
   **Fix:** Retain the backing pointer during population, or add an internal ownership lookup independent of guest access permission. Publish final protection after tracking succeeds.

5. **[LA64-R5-5] BUG — DBT accumulates FCSR Cause across multiple instructions.**  
   **Location:** [src/dbt/emit_fp_mem.c:145](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:145), [src/dbt/emit_fp_mem.c:295](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:295), [src/interp/fp_vec_priv.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:48).  
   DBT clears FPSR once per accumulation interval and copies the accumulated exceptions into both guest sticky Flags and Cause. The interpreter replaces Cause after each operation. An exceptional FP operation followed by an exact FP operation and `MOVFCSR2GR` therefore exposes different Cause bits between engines.  
   **Fix:** Track the latest operation’s exceptions separately from accumulated sticky flags. Preserve that distinction at FCSR reads and block exits; add a two-operation regression that reads the complete FCSR.

6. **[LA64-R5-6] DEFECT — Shared file overlay installation occurs outside quiescence.**  
   **Location:** [src/vm/vm_file.c:653](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:653), [src/vm/vm64.c:470](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:470).  
   The shared-map path calls `vm64_map()` with final permissions, which commits and releases quiescence. It then replaces the backing with `rt_host_map_file()`. The next `vm64_prepare_mutation()` happens only after replacement. A peer can observe accessible zero-filled staging bytes or access the HVA during backing replacement.  
   **Fix:** Install backing and publish final page state in one transaction. Keep the range inaccessible until the host operation and tracking record succeed, and handle preparation failure before mutating backing.

7. **[LA64-R5-7] DEFECT — Malformed `PT_INTERP` silently becomes “no interpreter.”**  
   **Location:** [src/loader.c:279](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:279), [src/loader.c:288](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:288), [src/loader.c:657](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:657).  
   `read_interp_path()` returns the same result for absence, malformed length, and failed reads. Its caller treats every failure as a static executable and proceeds to the executable entry point. It also appends a terminator rather than requiring the interpreter record itself to contain one.  
   **Fix:** Return distinct absent/present/error outcomes. Reject malformed or unreadable interpreter records with an executable-format error and validate their termination before loading.

8. **[LA64-R5-8] BUG — CoreMark parity can pass when every execution fails.**  
   **Location:** [tests/parity_suite.sh:538](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:538), [tests/parity_suite.sh:551](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:551).  
   CRC extraction suppresses failure and permits empty files. The verdict requires only equal exit codes and equal extracted CRC files. If oracle, interpreter, and DBT all time out before producing CRCs, equal timeout statuses plus three empty files produce `PASS`. This branch also omits comparison with committed CoreMark goldens.  
   **Fix:** Require successful execution, all expected CRC records, and agreement with committed CRC goldens. Treat timeout and setup failures explicitly.

9. **[LA64-R5-9] DRY — Duplicate parity comparators have already diverged.**  
   **Location:** [tests/parity_suite.sh:417](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:417), [tests/parity_suite.sh:505](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:505).  
   The generic Docker comparator checks oracle output and committed goldens. The separately implemented dynamic-loader comparator checks only oracle agreement, despite writing goldens during refresh. A jointly changed oracle/runtime result can pass the dynamic case without matching its committed baseline.  
   **Fix:** Factor result normalization and oracle/golden comparison into one helper within this repository. Keep case-specific execution separate.

**Cross-runtime propagation:** Check `rvrt` first for the copied VM, file-provider, and mutation patterns in findings 1–4 and 6. Check sibling AArch64 DBTs that batch FPSR updates for finding 5, ELF loaders with separate interpreter-path probes for finding 7, and sibling `tests/parity_suite.sh` implementations for findings 8–9. These are propagation targets, not verified sibling defects.

**CLEAN:** The counted source and test `.c`, `.h`, and `.S` files stayed within 900 lines. Targeted searches found no calls to `sprintf`, `strcpy`, or `strcat`. No standalone CLEAN finding warranted inclusion. Runtime reproduction and exhaustive ISA coverage remain unverified under the requested static-only budget.