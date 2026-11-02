Found **18 actionable issues** at HEAD `1907d96`. The Round-3 and post-fable changes are present, but several fixes remain incomplete.

Used seven shell inspection invocations. Read no Markdown documents; ran no project builds, tests, containers, or QEMU. `git status --short` was clean. `include/` and `tools/` are absent. The source line-count scan found no `.c`, `.h`, or `.S` files over 900 lines. Findings below are static conclusions, not runtime reproductions.

**LA64-R4-1 — Masked FCSR writes corrupt unrelated fields**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_mem.c:43`
- **Evidence & Root Cause:** For field 1, the emitter clears the old enable bits in `x11`, then overwrites all of `x11` with `x10 & 31`; rounding, cause, and sticky fields disappear. For field 2, lines 47–50 extract the two exception fields and recombine them in reversed positions. The interpreter correctly performs `(old & ~mask) | (input & mask)` at `src/interp/fp.c:658`.
- **Concrete Fix:** Emit that masked merge directly for each selector. Add interpreter/DBT comparisons with distinct cause/sticky patterns and nonzero rounding bits.

**LA64-R4-2 — FP-to-integer checks precede rounding and permit undefined casts**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp.c:224`
- **Evidence & Root Cause:** `fp_ftint_wd()` accepts `2147483647.75`, then nearest rounding produces `2147483648.0`; casting that to `int32_t` is undefined. The lower-bound literals in `fp_ftint_w()`, `fp_ftint_l()`, and `fp_ftint_ld()` also round to the minimum representable integer, so their strict comparison incorrectly rejects that valid endpoint.
- **Concrete Fix:** Handle NaNs explicitly, round first, validate the rounded value using exactly representable bounds, then cast. Preserve the required invalid/inexact flags. Cover both endpoints and fractional overflow under every rounding mode.

**LA64-R4-3 — Staged `MAP_SHARED` mappings are independent private copies**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:332`
- **Evidence & Root Cause:** The fallback populates private arena storage with `pread`. Stores become visible to aliases only through explicit `staged_propagate()`, and that scans only process-local records. Two aliases therefore disagree immediately after a store; forked processes retain separate copies. `vmfile_write_hook()` updates metadata without refreshing staged bytes, so later whole-range writeback can overwrite newer file contents.
- **Concrete Fix:** Give mappings of the same inode/file page genuinely shared backing, including across fork, or implement coherent mediated accesses with dirty tracking. Explicit `msync` copying alone cannot provide `MAP_SHARED` semantics.

**LA64-R4-4 — Middle unmap silently loses the surviving tail record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:523`
- **Evidence & Root Cause:** Unmapping the middle page of a three-page mapping takes the `else` branch and shortens the existing record to the head. No tail record is created, although the tail remains mapped. Subsequent sync, truncate, protection bookkeeping, and inode reclamation no longer account for it.
- **Concrete Fix:** Reserve a second record before mutation, split head and tail, adjust the tail’s GVA/HVA/file offset, and acquire its inode reference. Handle record exhaustion before changing mappings.

**LA64-R4-5 — Protection changes suppress dirty writeback for unrelated pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:356`
- **Evidence & Root Cause:** `vmfile_note_protect()` assigns the new protection to every overlapping *whole record*. Protecting one page read-only therefore marks writable siblings read-only in this table. `staged_writeback()` then skips the entire record at line 410. Even a full-range writable-to-read-only transition can leave dirty bytes that still require writeback.
- **Concrete Fix:** Split records at protection boundaries and update them only after successful protection changes. Track dirt independently of current permissions; removing write permission must not discard pending modifications.

**LA64-R4-6 — Truncate discard compares file offsets with guest addresses**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:684`
- **Evidence & Root Cause:** `cut` is an aligned file size, but `start = max(maps[i].gva, cut)` treats it as a guest address and ignores `file_off`. For a private mapping at GVA `0x40000`, file offset zero, shrinking to 4096 selects the entire mapping, discarding dirty bytes in the first page even though that page survives.
- **Concrete Fix:** Intersect the removed file-offset interval with each mapping’s file interval, then translate that intersection back to GVA/HVA. Preserve surviving private pages and partial EOF pages.

**LA64-R4-7 — Child reference acquisition races with parent reclamation**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:78`
- **Evidence & Root Cause:** Inherited references are acquired only when the child reaches `vmfile_fork_child_reset()`. The parent can return from `fork`, unmap its final record, and clear or reuse the shared row first. The child then either skips its missing row or increments a replacement row. The new test waits for the child before the parent unmaps, excluding this ordering.
- **Concrete Fix:** Reserve inherited references before `fork` under family-table synchronization, roll them back on failure, and transfer ownership to the child without a second increment. Add a parent-first-unmap regression.

**LA64-R4-8 — Shared inode rows contain process-local descriptor numbers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:152`
- **Evidence & Root Cause:** `itable` is shared across processes, but `dupfd` belongs to the registering process’s descriptor table. A row created after fork is visible to peers that do not possess that descriptor. Their writeback or reclamation can use or close an unrelated descriptor with the same number. Atomic reference counting does not fix descriptor ownership.
- **Concrete Fix:** Keep retained descriptors in process-local inode-handle tables. Share only stable identity and synchronization metadata; explicitly transfer descriptors when a peer needs access.

**LA64-R4-9 — `MS_INVALIDATE` discards dirty staged data**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:596`
- **Evidence & Root Cause:** Any flags containing bit 2 take the `pread` branch instead of writeback. Thus `MS_SYNC | MS_INVALIDATE` overwrites dirty staged bytes with old file contents and propagates those old bytes to aliases.
- **Concrete Fix:** Validate flags before mutation. Complete required dirty writeback before invalidation, and refresh only where coherence rules permit. Test combined flags on a forced staged mapping.

**LA64-R4-10 — Guest `msync` bypasses Darwin flag and page-size translation**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls.c:509`
- **Evidence & Root Cause:** After `vmfile_msync()`, the handler calls libc `msync()` directly with Linux flags. The Darwin translation already exists in `rt_host_msync()`. It also submits the guest-address-derived pointer directly: a valid 4 KiB guest boundary need not be a valid 16 KiB host boundary. Writeback can complete before the syscall reports a host validation error.
- **Concrete Fix:** Validate guest arguments first and dispatch by backing type. Staged anonymous storage should complete through its file-writeback path; direct overlays should use translated flags and valid host spans.

**LA64-R4-11 — File installation and removal occur outside VM quiescence**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:245`
- **Evidence & Root Cause:** `vm64_map()` commits and resumes peers before `map_bytes_in_place()` performs `pread` and publishes its record. The direct-overlay path likewise installs the host overlay after `vm64_map()` returns. Conversely, `sys_munmap_range()` calls `vmfile_unmap()`—including backing repair—before `vm64_unmap()` obtains quiescence. Peers can access partially installed or replaced bytes through still-valid translations.
- **Concrete Fix:** Make backing changes, population, record changes, page-state publication, and TLB/LL invalidation one transaction. Add internal mapping primitives that operate under an already-held mutation gate.

**LA64-R4-12 — `SA_RESETHAND` redirects execution to address zero**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:243`
- **Evidence & Root Cause:** `act` points into `sf_actions`. Delivery sets `sf_actions[sig].handler = LA64_SIG_DFL`, then line 251 reads `act->handler` into `ctx->pc`. The first delivery therefore uses the reset disposition instead of the registered handler.
- **Concrete Fix:** Snapshot the action before modifying the shared disposition. Redirect using the saved handler and reset only the installed action.

**LA64-R4-13 — Signal delivery loses pending events and uses unsafe async updates**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:240`
- **Evidence & Root Cause:** Polling removes one selected pending source, but `sf_deliver_locked()` subsequently clears the signal from both thread and process queues. If both contain that signal, one event disappears. Separately, `la64_host_signal_note()` performs ordinary read-modify-write operations on `sf_proc_pending` while polling clears it; these are neither atomic nor protected from asynchronous interruption.
- **Concrete Fix:** Remove only the selected queue entry. Use an async-signal-safe publication mechanism and synchronized consumption, including metadata ordering. Test simultaneous process/thread pending signals and arrivals during polling.

**LA64-R4-14 — Failed clone leaves signal records referring to freed contexts**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/clone.c:588`
- **Evidence & Root Cause:** `la64_signal_clone_inherit()` allocates child signal state before parent-TID copyout, child-TID validation, and `pthread_create`. Failure paths at lines 588, 602, and 613 free the child without calling `la64_signal_thread_exit()`. The fixed signal table retains stale entries and can exhaust capacity across failures using distinct allocations.
- **Concrete Fix:** Add signal-state cleanup to every post-inheritance failure path, preferably through one cleanup helper, or defer publication until clone setup can commit.

**LA64-R4-15 — New regression fixture reads past its stack buffer**

- **Severity:** Medium
- **Category:** CLEAN
- **Location:** `tests/test_u0_soft_tlb.c:796`
- **Evidence & Root Cause:** `probe` has 16 bytes, but `write(fd, probe, 100)` requests 100 bytes. The test reads beyond the object and writes unrelated stack contents into its fixture. It violates the no-undefined-behavior requirement and can trigger compiler diagnostics.
- **Concrete Fix:** Use an initialized 100-byte fixture buffer, or create the required file size separately and write only `sizeof probe`.

**LA64-R4-16 — Target backend selection is disconnected from test recipes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:65`
- **Evidence & Root Cause:** `U0_TEST_SRCS` and `RC_TEST_SRCS` hard-code Linux backend files and `safe_syscall_a64.S`. Although lines 108–113 compute `U0_TARGET_BACKEND`, neither source list uses it. Native Darwin checks consequently do not exercise the selected Darwin backend.
- **Concrete Fix:** Build both source lists from common sources plus the target-selected backend. Account for Make’s immediate `:=` expansion by defining the selector first or using deferred expansion.

**LA64-R4-17 — FP memory instruction classification is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/dbt/dbt_mem.c:161`
- **Evidence & Root Cause:** `mem_miss_fp()` and `la64_emit_fp_mem()` at `src/dbt/emit_fp_mem.c:386` independently encode the same opcode acceptance, width, store/load, and indexed-mode decisions. A change to one can make generated accesses disagree with their retry decoder.
- **Concrete Fix:** Introduce one repo-local DBT classification helper returning those fields. Keep the independent interpreter/oracle validation separate.

**LA64-R4-18 — Obsolete Linux source-list variable remains unused**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `Makefile:63`
- **Evidence & Root Cause:** `U0_LINUX_SRCS` has no consumers. `U0_LINUX_BACKEND` separately lists the same C files plus assembly, leaving two apparent definitions of the Linux backend source set.
- **Concrete Fix:** Delete the unused variable and retain one authoritative backend source list.

- [ ] **LA64-R4-1:** Correct masked FCSR emission.
- [ ] **LA64-R4-2:** Validate rounded FP conversion results before casting.
- [ ] **LA64-R4-3:** Provide coherent shared-file backing.
- [ ] **LA64-R4-4:** Preserve both survivors of middle unmaps.
- [ ] **LA64-R4-5:** Separate protection boundaries from dirty tracking.
- [ ] **LA64-R4-6:** Translate truncate offsets into mapping coordinates.
- [ ] **LA64-R4-7:** Reserve inherited references before fork.
- [ ] **LA64-R4-8:** Keep retained descriptors process-local.
- [ ] **LA64-R4-9:** Preserve dirty data during invalidation.
- [ ] **LA64-R4-10:** Correct guest-to-host `msync` handling.
- [ ] **LA64-R4-11:** Keep complete backing mutations under quiescence.
- [ ] **LA64-R4-12:** Snapshot handlers before `SA_RESETHAND`.
- [ ] **LA64-R4-13:** Fix pending-source consumption and async publication.
- [ ] **LA64-R4-14:** Clean up signal state after failed clone.
- [ ] **LA64-R4-15:** Fix the fixture’s out-of-bounds write source.
- [ ] **LA64-R4-16:** Wire target backend selection into tests.
- [ ] **LA64-R4-17:** Unify DBT FP-memory classification.
- [ ] **LA64-R4-18:** Remove the unused Linux source-list variable.