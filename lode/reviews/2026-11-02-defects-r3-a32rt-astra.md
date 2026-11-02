Found **7 issues** at `a76285b`, including a mapping-registration ordering defect that can discard newly installed file backing.

Reviewed `git log -n 5 --oneline`, both recent commits, and selected VM, JIT, interpreter, signal, syscall, build, and test paths. This was static inspection only; no builds, tests, Docker, or QEMU ran. Findings below are code-derived, not runtime reproductions.

**A32-R3-1 — Region registration deletes newly installed file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:621`; `src/vm.c:235`; `src/vm/vm_file.c:592`
- **Evidence & Root Cause:** `vm_mmap2_locked()` installs the mapping and records its file backing before calling `vm_record_region_locked()`. That function unconditionally calls `vm_unmap_regions_locked()`, which removes file tracking for the same range. Thus registration deletes the metadata just created. On hosts with pages larger than 4 KiB, deleting a fully covered shared entry also replaces its host mapping with anonymous private memory. A successful shared mmap can therefore immediately lose sharing and file contents.
- **Concrete Fix:** Separate removal of the previous mapping from insertion of the new region. Retire old backing before installation, then publish new region and backing metadata together. Do not invoke backing teardown from a generic region-registration helper.

**A32-R3-2 — Initial staged mappings permit accesses wholly beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:284`; `src/vm/vm_file.c:297`
- **Evidence & Root Cause:** Private-file population records `max(file_offset + len, st_size)` as the inode size and clears EOF restrictions across the entire mapping. A2 uses anonymous staging, so the host cannot supply the missing file-backed fault. Mapping 8 KiB from a 4 KiB file consequently leaves the second page accessible. The mapping extent also corrupts the size baseline used to distinguish file growth from shrinkage. This remains incorrect after fixing A32-R3-1.
- **Concrete Fix:** Track the actual file size separately from mapping extent. Mark pages wholly beyond rounded EOF inaccessible when committing the mapping; zero only the last partial page. Preserve these restrictions through region publication.

**A32-R3-3 — Private file mappings lose their backing during mremap**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:784`; `src/vm.c:817`; `src/vm.c:866`
- **Evidence & Root Cause:** Only shared mappings retain a file descriptor and offset in `a32_vm_mremap()`. Private mappings grow through anonymous extension; moving them allocates anonymous memory and copies existing bytes. For a private mapping of the first page of a two-page file, expansion returns zeros instead of the second file page. Moving also drops future file-size/EOF tracking.
- **Concrete Fix:** Carry private backing identity and offsets through both growth and relocation. Populate newly exposed file pages while preserving existing private modifications and EOF state. Transfer backing metadata with the mapping.

**A32-R3-4 — Fork inherits JIT leases belonging to vanished threads**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:157`; `src/vm/vm_jit_mem.c:115`
- **Evidence & Root Cause:** Fork copies the process-global `g_jit_exec_readers`, `g_jit_reset_pending`, and JIT lock state. Their references contain no child-side reinitialization or fork coordination. If another thread holds an execution lease at fork, the child inherits its reader count without that thread. A later cache reset waits forever. Inheriting a held lock or pending reset similarly prevents progress.
- **Concrete Fix:** Coordinate fork with JIT execution and mutation: stop new entrants, quiesce readers, and serialize cache state before fork. Restore parent execution afterward and initialize child synchronization state consistently. Resetting counters alone is insufficient if the snapshot captures partially mutated cache data.

**A32-R3-5 — File-tracking capacity exhaustion silently disables semantics**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:94`; `src/vm/vm_file.c:523`; `src/vm/vm_file.c:606`
- **Evidence & Root Cause:** The inode table has 64 entries and never releases `used` entries. Mapping 64 distinct files over the process lifetime exhausts it, even after unmapping them. Mapping and shared-backing tables also silently discard records on exhaustion or descriptor-duplication failure. A middle unmap truncates the original record before securing the right-hand record, so allocation failure loses tracking for still-mapped memory.
- **Concrete Fix:** Reclaim inode entries when their last mapping disappears. Make backing registration and splitting return errors, and reserve required slots/descriptors before mutation. Either grow these tables or reject operations before changing memory when tracking cannot be maintained.

**A32-R3-6 — Single-step execution acquires its lease after code can be recycled**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/dbt_jit_run.c:579`; `src/dbt/dbt_jit_run.c:590`
- **Evidence & Root Cause:** `a32_jit_compile_block()` returns through `compile_block_internal(..., false)`, releasing the JIT lock without an execution lease. Single-step then reacquires the lock, seals the batch, and increments the reader count. Another thread can reset and reuse the cache between compilation and lease acquisition. The saved `code` pointer is not revalidated before execution.
- **Concrete Fix:** Compile, seal, and acquire the execution lease within one locked operation. Reuse the lease-bearing lookup path or introduce an explicit compiled-block lease API.

**A32-R3-7 — Fixture build recipes do not consistently enforce requested C flags**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:125`; `Makefile:131`; `Makefile:250`
- **Evidence & Root Cause:** Runtime `CFLAGS` include the requested warning policy, but fixture flags omit `-Werror`; the recipe at line 250 also omits `-pedantic`. Consequently, the policy is not enforced consistently across repository C code.
- **Concrete Fix:** Define a shared C warning-policy variable and use it in applicable runtime and fixture recipes, keeping architecture-specific options separate.

The inspected `.c`, `.h`, and `.S` files stayed below 900 lines; the largest was `src/vm.c` at 897. The source/header scan found no forbidden string calls, `.c` inclusions, or literal `x18`/`w18` register references. That scan does not establish reservation of register 18 in numeric instruction encoders. No additional DRY or YAGNI finding was sufficiently substantiated within this review budget.

- [ ] **A32-R3-1:** Separate mapping teardown from registration.
- [ ] **A32-R3-2:** Enforce initial EOF boundaries.
- [ ] **A32-R3-3:** Preserve private-file backing across mremap.
- [ ] **A32-R3-4:** Coordinate fork with JIT leases and locks.
- [ ] **A32-R3-5:** Make backing-table allocation transactional and reclaim entries.
- [ ] **A32-R3-6:** Acquire single-step leases before releasing compiled code.
- [ ] **A32-R3-7:** Apply C warning flags consistently.