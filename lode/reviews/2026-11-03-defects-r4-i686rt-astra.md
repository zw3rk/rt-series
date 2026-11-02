Found **12 actionable issues** at HEAD `ca4c9a2`. The Round-3 and follow-up changes are present, but fork locking, remap rollback, and file-backing paths remain incomplete.

Used seven shell inspection commands, including the requested history commands. No builds, tests, containers, or QEMU ran. Findings below are static conclusions, not runtime reproductions. The line-count scan found no `.c`, `.h`, or `.S` file over 900 lines; no separate CLEAN finding is asserted.

**I686-R4-1 — Fork preparation reverses the A2 futex lock order**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm32.c:89`
- **Evidence & Root Cause:** `i686_vm32_fork_prepare()` acquires `s_subpage_mtx`, then `s_futex_mtx`. `i686_vm32_futex()` acquires `s_futex_mtx` at line 351 and calls `vm32_futex_load_u32()`, which acquires the subpage lock at line 295. Concurrent fork and A2 `FUTEX_WAIT` can each hold the mutex the other needs. `FUTEX_CMP_REQUEUE` has the same inversion.
- **Concrete Fix:** Establish one lock order for fork, futex value validation, and waiter registration. Preserve atomic check-and-enqueue semantics when restructuring; simply releasing the futex mutex before checking introduces lost wakeups.

**I686-R4-2 — Fork shares address-space protection metadata**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:126`
- **Evidence & Root Cause:** `s_prot`, `s_state`, and `s_flags` use `MAP_SHARED | MAP_ANONYMOUS`. Fork handlers reset locks but do not privatize these arrays. A child's `munmap()` clears protection and mapped flags through `rt32_vm_file_sync_prot_locked()` (`src/rt32/rt32_vm.c:232`), changing the parent's metadata despite separate VMAs. A2 permission checks and host-page protection reconstruction consequently use another process's mapping state.
- **Concrete Fix:** Make per-address-space protection, presence, and private-COW state fork-private. Keep any genuinely shared file-object state separate and keyed by backing identity rather than guest address.

**I686-R4-3 — Truncate maintenance writes directly into inaccessible file pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:336`
- **Evidence & Root Cause:** `i686_pass_r_ftruncate64()` invokes `i686_vm_file_note_ftruncate()` after successful host truncation. That function calls `i686_vm_file_note_shrink()`, which blindly `memset()`s entire pages past EOF. Read-only staged mappings are not writable; native file mappings wholly beyond the new EOF can raise SIGBUS even when writable. The hook also traverses `s_maps` without the VM lock, racing mapping removal and replacement.
- **Concrete Fix:** Serialize tracking changes. Let native mappings retain host EOF behavior without touching invalidated pages. For staged mappings, maintain explicit EOF validity and update accessible partial-page bytes through a checked protection window. Do not implement beyond-EOF pages as ordinarily readable zero pages.

**I686-R4-4 — A2 remap copies through protections that have already been restored**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:525`
- **Evidence & Root Cause:** The provisional destination comes from `vm_mmap2_locked()`, which restores A2 covering-page protections and releases the subpage lock before returning. Relocation then performs raw `memcpy()` at line 534. A valid writable destination sharing a 16 KiB host page with an unmapped subpage can therefore be host `PROT_NONE`. The source workaround at line 529 also passes a merely 4 KiB-aligned address to `mprotect()` and ignores failure.
- **Concrete Fix:** Copy staged mappings under the subpage exclusion protocol, temporarily opening aligned source and destination host-page covers. Check protection changes and restore every opened cover on success and failure.

**I686-R4-5 — File remap rollback can discard the original backing record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:409`
- **Evidence & Root Cause:** In-place growth removes tracking for the entire expanded range before installing its replacement. `i686_vm_file_track_map()` can fail when duplicating the backing descriptor (`src/vm/vm_file.c:348`). The error branch only unmaps the extension; it never restores the original mapping's tracking. HEAD's `rec_rc` check fixes one earlier failure ordering, but does not make this replacement transactional.
- **Concrete Fix:** Prepare the replacement record and owned descriptor before deleting existing records. Commit the replacement atomically under the VM lock; preserve the original record and descriptor on every failure.

**I686-R4-6 — Signal-action lookup returns a process-global scratch object**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sys_pass.c:29`
- **Evidence & Root Cause:** Every `i686_gsig_tab()` call overwrites the same static `v`. Concurrent deliveries for different signals retain pointers to that object while building frames and reading flags and masks. One thread can substitute another signal's action mid-delivery. Concurrent `rt_sigaction()` also reads and writes `s_sigact` without synchronization, allowing torn actions and C data races.
- **Concrete Fix:** Return an action snapshot into caller-owned storage. Synchronize publication and reads of the complete action, using a mechanism suitable for every calling context. Carry that single snapshot through delivery and frame construction.

**I686-R4-7 — Default x87 logarithm handling rejects valid inputs and reverses infinity signs**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/h_x87_math.c:534`
- **Evidence & Root Cause:** The default binary64 path rejects every `a < 0.0`, including valid `FYL2XP1` inputs such as `a = -0.25`. For `FYL2X` with `a = 0` and positive `b`, line 542 produces positive infinity, although `b × log2(0)` is negative infinity. Zero multipliers also need invalid-operation handling rather than unconditional infinity.
- **Concrete Fix:** Separate the two instructions' domain checks. Handle zero, signed multiplier, infinities, and invalid products explicitly before the ordinary logarithm calculation. Add focused cases for negative valid `FYL2XP1` inputs and `FYL2X` zero operands.

**I686-R4-8 — Positioned I/O bypasses A2 guest-buffer marshalling**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sys_pass_io.c:436`
- **Evidence & Root Cause:** `sys_pread64()` and `sys_pwrite64()` pass `i686_guest_ptr()` directly to host I/O after checking only the lower address bound. A valid guest buffer on a restrictive A2 covering page returns host `EFAULT`; kernel copy faults do not enter the runtime's user-space healing checkpoint. These paths also omit the guest-span overflow validation provided by the copy helpers.
- **Concrete Fix:** Use bounded host buffers with checked guest copy-in/copy-out, or a complete validated and synchronized host-access window. Preserve short-I/O semantics and route successful copyout through the required memory-write bookkeeping.

**I686-R4-9 — Darwin file-copy backend ignores the explicit output offset**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/backend_darwin_io.c:280`
- **Evidence & Root Cause:** `rt_host_copy_file_range()` calculates `out` from `*off_out`, then calls `rt_host_sendfile()`. That helper uses `write(out_fd, ...)`, so copying occurs at the descriptor's current position and advances it. The function nevertheless reports advancement of the supplied explicit offset. This differs from the Linux backend contract. No guest syscall caller was found, so this is currently a backend API defect.
- **Concrete Fix:** Implement positioned writes when `off_out` is supplied, leaving the descriptor position unchanged. Advance only the offsets corresponding to bytes actually copied, and reject unsupported flags.

**I686-R4-10 — x86_64 incremental builds ignore header changes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:74`
- **Evidence & Root Cause:** The x86_64 object rule depends only on `src/%.c`, unlike the ordinary and Darwin rules that include `$(HDRS)`. Editing context layouts, decoder declarations, or inline helpers can leave stale interpreter objects and produce an inconsistent binary.
- **Concrete Fix:** Add `$(HDRS)` to this rule, or generate and include compiler dependency files consistently across object variants.

**I686-R4-11 — File-map replacement capacity logic is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/vm/vm_file.c:405`
- **Evidence & Root Cause:** `i686_vm_file_can_replace()` and `i686_vm_file_untrack_map()` independently calculate free slots and interior splits. Their validation already differs: only the former rejects zero-length or beyond-window spans. This duplicates the rules governing a mutation-sensitive operation.
- **Concrete Fix:** Introduce one repo-local replacement planner that validates the span and computes required slots and splits. Use its result for both preflight and commit, including preparation of required descriptors.

**I686-R4-12 — The old registry host-TID setter is unused**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/clone.c:158`
- **Evidence & Root Cause:** Round-3 removed the setter's call from `thread_entry()` in favor of the startup handshake. Source searches found only its declaration and definition, with no callers or public-header declaration. The compatibility comment now preserves unused mutation machinery.
- **Concrete Fix:** Remove `i686_thread_registry_set_host_tid()` and its obsolete compatibility comment.

- [ ] **I686-R4-1:** Unify fork and A2 futex lock ordering.
- [ ] **I686-R4-2:** Make address-space metadata fork-private.
- [ ] **I686-R4-3:** Repair truncate protection, EOF, and synchronization handling.
- [ ] **I686-R4-4:** Copy A2 remaps through checked protection windows.
- [ ] **I686-R4-5:** Make file-remap tracking replacement transactional.
- [ ] **I686-R4-6:** Publish and consume coherent signal-action snapshots.
- [ ] **I686-R4-7:** Correct x87 logarithm domain and exceptional results.
- [ ] **I686-R4-8:** Marshal positioned-I/O guest buffers safely.
- [ ] **I686-R4-9:** Honor Darwin file-copy output offsets.
- [ ] **I686-R4-10:** Track headers in x86_64 incremental builds.
- [ ] **I686-R4-11:** Unify file-map replacement planning.
- [ ] **I686-R4-12:** Remove the unused registry setter.