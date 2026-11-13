Round 3 found **11 actionable issues** at `4a759c6`, including remaining correctness defects in thread identity, sub-page isolation, mapping bookkeeping, and fork handling.

This was a static review using seven shell inspection turns: `git log -n 5 --oneline`, `git show HEAD~1`, `git show HEAD`, and targeted source reads/searches. No builds, tests, Docker, or QEMU ran. No files changed. Findings below are source-derived; this bounded review does not establish complete ISA or backend correctness.

**I686-R3-1 — Clone publishes inconsistent thread IDs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/clone.c:472`
- **Evidence & Root Cause:** `thread_entry()` rekeys the registry to the host TID, then immediately assigns `tid = pre_tid` and writes that synthetic ID into the parent/child TID words. `r_clone()` also returns the synthetic ID, while `sys_gettid()` reads the rekeyed registry. Consequently, targeting the returned clone ID can produce `ESRCH`, and libc ownership words can disagree with robust recovery’s host TID.
- **Concrete Fix:** Choose one guest TID namespace consistently. Given Linux PI-futex forwarding, synchronize child startup so the parent receives the actual host TID and both SETTID words contain it before clone returns. Remove the unsynchronized synthetic counter or protect any remaining allocation.

**I686-R3-2 — Staged mmap bypasses sub-page quiescence**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm.c:126`
- **Evidence & Root Cause:** `rt32_vm_mmap2_staged_a2_locked()` makes the entire host-page cover writable before zeroing or loading the requested sub-pages. Its caller holds the VM bookkeeping lock, but neither path acquires `i686_vm32_subpage_lock()`. Guest execution does not take the bookkeeping lock. A sibling can therefore access a protected neighboring sub-page during this window, including writing through an SMC-protected cover.
- **Concrete Fix:** Quiesce guest execution around every staged mapping protection change, content update, and permission restoration. Establish a consistent lock order and restore restrictive protections on every failure path.

**I686-R3-3 — Anonymous MAP_FIXED leaves stale file registrations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:106`
- **Evidence & Root Cause:** File-map removal occurs only when the *new* mapping is file-backed. Replacing a file mapping with `MAP_FIXED | MAP_ANONYMOUS` leaves the old file association and owned FD registered. File hooks can subsequently treat the anonymous replacement as part of the old file. For an A2 staged shared-file predecessor, state zero also satisfies the refresh condition in `i686_vm_file_note_pwrite()`.
- **Concrete Fix:** Remove overlapping backing registrations for every successful replacement, including anonymous mappings. Reserve required split capacity before changing host mappings, and register new backing only when applicable.

**I686-R3-4 — Mapping registry failures are ignored after mmap succeeds**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/rt32_vm_mmap.c:103`
- **Evidence & Root Cause:** The results of `rt32_vm_record_region_locked()`, `i686_vm_file_untrack_map()`, and `i686_vm_file_track_map()` are discarded. Region exhaustion, backing-table exhaustion, or FD duplication failure can therefore yield a successful guest mmap with absent or stale metadata. Later permission checks, file updates, and remapping operate on a different mapping model from the host.
- **Concrete Fix:** Preallocate metadata slots and backing references before committing the host mapping. Propagate allocation failures and make host mapping plus metadata publication transactional.

**I686-R3-5 — VMA split exhaustion silently changes requested semantics**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm.c:404`
- **Evidence & Root Cause:** When an interior mprotect requires two region slots and capacity is exhausted, the fallback assigns `r->prot = prot` to the entire original region. Other split failures similarly broaden the update. Interior unmap failure at line 346 instead leaves the original region intact. These helpers cannot report failure to callers, which continue returning success.
- **Concrete Fix:** Calculate and reserve split capacity before modifying mappings. Return an error without mutation when capacity is unavailable; never substitute whole-region protection changes or retain a supposedly unmapped interval.

**I686-R3-6 — Guest-copy failure escapes the syscall’s cleanup path**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/marshal.c:110`
- **Evidence & Root Cause:** On an unrecoverable copy fault, `s_copy_tolerant()` jumps to the outer engine checkpoint whenever one exists instead of returning `-I686_EFAULT`. Runtime syscall callers normally have that checkpoint. Their error handling and cleanup are bypassed. For example, A2 `sys_read()` allocates a temporary buffer before `i686_copy_to_guest()`; a fault after a concurrent mapping change skips its `free()` and syscall error return.
- **Concrete Fix:** Make syscall copy helpers contain faults and return `-EFAULT` after restoring protections and releasing locks. Keep guest-instruction fault propagation in a separate interface.

**I686-R3-7 — File refresh races mapping mutation and ignores protected destinations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:517`
- **Evidence & Root Cause:** `i686_vm_file_note_pwrite()` walks ordinary `s_maps` fields and uses their owned FDs without the VM lock; `sys_pwrite64()` invokes it directly. Concurrent unmap can modify entries and close those FDs. Refresh also calls `pread()` directly into guest pages without opening restrictive A2 covers. A destination fault makes `pread()` fail, but the loop silently stops and still increments `refreshed`.
- **Concrete Fix:** Serialize backing lookup and lifetime management with mapping mutations. Refresh through a checked, quiesced copy path, handle host I/O failures explicitly, and invalidate translations for changed executable bytes.

**I686-R3-8 — Fork retains vanished-thread registry entries and locks**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:353`
- **Evidence & Root Cause:** The fork child only changes `ctx->host_tid`. The only registered atfork handler found resets `vm32` state; it does not reset `s_registry_lock`, `g_vm_lock`, or rebuild the thread registry. Forking while another thread owns either lock can leave the child permanently blocked. Forking from a worker also retains the old main-context pointer and registry entries for threads that no longer exist.
- **Concrete Fix:** Add coordinated fork preparation and parent/child handling for runtime-owned locks. Rebuild the child registry around the surviving context, update its process/thread identity, and discard vanished-thread state.

**I686-R3-9 — Shared anonymous mremap silently falls back to losing sharing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:409`
- **Evidence & Root Cause:** The new Linux path attempts host `mremap()` to preserve shared anonymous backing. If it fails, execution falls through to `memcpy()` into a newly allocated shared anonymous mapping and returns success. That new object no longer shares identity with an existing fork peer. The fallback therefore defeats the semantic guarantee the new path was added to preserve.
- **Concrete Fix:** Propagate host-mremap failure and clean up the provisional destination. Use copying only where backing identity is irrelevant; other backends need a backing-preserving implementation for this case.

**I686-R3-10 — Exec-reader registration handshake is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/vm/vm32.c:150`
- **Evidence & Root Cause:** `i686_vm32_subpage_unlock()` duplicates the writer-wait, reader-increment, writer-recheck, and rollback loop from `i686_vm32_exec_enter()`. This is consequential concurrency logic whose memory-ordering fixes must remain identical.
- **Concrete Fix:** Extract one private reader-registration helper. Keep the context/regime eligibility checks in `exec_enter()` and call the shared helper when restoring a dropped registration.

**I686-R3-11 — Obsolete lane ownership lists remain in Makefile**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `Makefile:243`
- **Evidence & Root Cause:** `U3_OWNED` and `P13_OWNED` are defined but never referenced. Their surrounding comments describe lane-scoped enforcement, while `check-line-limits` now scans all of `src`, `include`, and `tests`.
- **Concrete Fix:** Remove both unused lists and replace the obsolete lane commentary with a short description of repository-wide enforcement.

The inspected `.c`, `.h`, and `.S` files under `src`, `include`, and `tests` were all within 900 lines. The Makefile contains the requested warning flags. Those observations are static hygiene checks, not evidence of a warning-clean build.

Checklist summary:

- [ ] **I686-R3-1:** Unify clone, SETTID, registry, and gettid identities.
- [ ] **I686-R3-2:** Quiesce staged A2 mmap protection windows.
- [ ] **I686-R3-3:** Remove stale backing records on anonymous replacement.
- [ ] **I686-R3-4:** Handle mapping metadata allocation failures transactionally.
- [ ] **I686-R3-5:** Reject VMA split exhaustion without changing semantics.
- [ ] **I686-R3-6:** Return syscall copy faults through caller cleanup.
- [ ] **I686-R3-7:** Synchronize and safely apply file refreshes.
- [ ] **I686-R3-8:** Reinitialize runtime ownership and registry state after fork.
- [ ] **I686-R3-9:** Preserve shared backing or fail mremap.
- [ ] **I686-R3-10:** Deduplicate reader registration.
- [ ] **I686-R3-11:** Remove unused Makefile lane lists.