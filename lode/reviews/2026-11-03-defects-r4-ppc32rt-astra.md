Found **13 actionable issues** at `f083489`, including data corruption, incorrect syscall results, and a fork deadlock.

Used seven shell inspection commands. No Markdown documents, builds, tests, Docker, or QEMU were read or run. History confirms the Round-3 operand snapshot, signal synchronization, and exec-mask changes are present; the VM and fork fixes remain incomplete. Findings below are static code-path conclusions, not runtime reproductions.

**P32-R4-1 — Successful `readv` returns zero**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:198`
- **Evidence & Root Cause:** `sys_vec()` accumulates transferred bytes in `total`, then subtracts those bytes while walking destinations for SMC invalidation. Line 216 returns the depleted `total`. An ordinary successful `readv` therefore reports zero despite modifying its buffers. Earlier error returns after partial progress also bypass this invalidation pass.
- **Concrete Fix:** Preserve the transferred count separately. Invalidate each completed destination range as transfers finish, and return the preserved count on success or subsequent failure. Add regressions for successful and partially successful `readv`.

**P32-R4-2 — Growing a staging object copies the wrong file bytes**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:356`
- **Evidence & Root Cause:** When an existing group grows, `vm_file_shared_acquire()` calls `stage_fill(..., file_offset, old, need - old)` at line 500. The destination incorporates `stage_off`, but `pread()` uses only `file_off + done`. The extension receives bytes from the beginning of the mapped file range instead of `file_offset + old`.
- **Concrete Fix:** Include `stage_off` in the source offset, or explicitly pass `file_offset + old` with a clearly documented helper contract. Test two same-offset aliases with different host-rounded lengths and distinct file-page patterns.

**P32-R4-3 — Overlapping shared mappings do not share storage**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:472`
- **Evidence & Root Cause:** Staging reuse requires identical `(dev, ino, file_offset)`. Overlapping mappings starting at different offsets receive different backing objects. Host-aligned mappings bypass staging altogether through `shared_direct` in `src/rt32/ppc32_vm.c:430`. Stores therefore fail to propagate between overlapping staged aliases or between staged and direct aliases.
- **Concrete Fix:** Track shared storage by inode and covered file pages, with consistent backing for every overlapping alias. Integrate ordinary file I/O with that storage. Extend the existing identical-offset alias test to overlapping offsets and direct/staged combinations.

**P32-R4-4 — Refresh writeback overwrites newer file contents**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:479`
- **Evidence & Root Cause:** The HEAD follow-up detects changed size/mtime, then drains the entire existing staging extent before refilling it. `stage_drain_locked()` writes every byte without dirty tracking. A file write made after staging can therefore be overwritten by stale staged bytes when another alias is mapped. Host-rounded padding is included in the drain.
- **Concrete Fix:** Never resolve a detected file change by blindly writing the old snapshot back. Implement coherent file mutation handling and dirty-range ownership; exclude untouched padding. Test a file update followed by alias acquisition and verify both the file and aliases retain the update.

**P32-R4-5 — Partial unmap discards a live staging group**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:785`
- **Evidence & Root Cause:** GC recognizes a reference only when the VMA’s current `offset` exactly equals the staging group’s original offset. Front trimming changes that offset at line 362. GC then closes and forgets the group even though the remaining mapping still references its host backing. Later aliases receive another object, and subsequent stores through the survivor lose their writeback association.
- **Concrete Fix:** Store a stable backing-object identity and object-relative offset in each VMA fragment. Preserve that identity through splitting, coalescing, and remapping; reclaim only after the last reference disappears. Test front-unmap followed by alias creation and writeback.

**P32-R4-6 — Automatic placement bypasses the new shared-tail guard**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:700`
- **Evidence & Root Cause:** HEAD adds `ppc32_vm_a2_host_page_busy()` checks to fixed and hint placement, but `vm_find_free_gap_aligned_locked()` checks only guest VMAs. For a private allocation, its alignment is 4 KiB, so its scan can choose the unpublished tail of a live 16 KiB shared host page. The A2 private path then zeroes or populates bytes in that shared backing.
- **Concrete Fix:** Make every placement path account for occupied host backing extents. Apply the same rule to cursor placement and fallback gap scans. Test automatic private allocation after a fixed, one-guest-page shared mapping on A2.

**P32-R4-7 — EOF trapping misses empty files and mappings entirely beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:258`
- **Evidence & Root Cause:** `vm_file_trap_beyond_eof()` returns for an empty file and also when rounded EOF precedes `map_offset`. Both cases require trapping the entire mapping. Additionally, `vm_mmap2_locked()` invokes this helper only for shared mappings, leaving A2 private file mappings populated with accessible zeroes beyond EOF.
- **Concrete Fix:** Treat zero length as a valid EOF. Clamp the first trap offset to `max(map_offset, rounded_eof)` and mark the resulting mapped suffix. Apply EOF handling to private file mappings as well. Cover empty files, wholly beyond-EOF offsets, and partial final pages.

**P32-R4-8 — Fork and truncate acquire locks in opposite orders**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/proc.c:122`
- **Evidence & Root Cause:** Fork acquires TLB then inode locks. Conversely, `vm_file_on_truncate_fd()` holds the inode lock while `file_apply_truncate()` calls `vm32_tlb_invalidate_range()` and `vm32_mark_eof_trap()`. A fork thread holding TLB and a truncate thread holding inode can wait permanently for each other. The truncate syscall does not acquire the outer VM lock to serialize these paths.
- **Concrete Fix:** Establish one lock order across fork, truncate, and file mutation paths. Serialize mutation through the VM layer and avoid inode-to-TLB nesting that conflicts with fork. Add a bounded concurrent fork/truncate regression using the translator’s syscall paths.

**P32-R4-9 — Truncate writes through inaccessible guest mappings**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:801`
- **Evidence & Root Cause:** After host `ftruncate()` succeeds, `file_apply_truncate()` unconditionally `memset()`s the resized guest span. A read-only private mapping can fault on that write; a direct mapping beyond the newly shortened EOF can fault with SIGBUS. The inode lock remains held across this access, while host-fault recovery releases only LL/SC and VM locks.
- **Concrete Fix:** Separate direct kernel-backed mappings from staged mappings. Let the kernel handle direct mapping truncation; update staged storage through a safe backing access path. Do not perform fault-prone guest accesses while holding an unrecoverable lock. Test truncation with read-only and beyond-EOF mappings.

**P32-R4-10 — File tracking loses aliases and depends on reusable fd numbers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:105`
- **Evidence & Root Cause:** `file_register()` overwrites the existing record when the same fd creates another mapping, losing the earlier mapping’s range. Truncate matching additionally requires the original fd number at line 863, so truncating through a duplicate or reopened descriptor misses mappings of the same inode. `vm_file_hook_write()` matches only the fd number, allowing descriptor reuse to affect stale records.
- **Concrete Fix:** Track every mapping independently using stable backing identity and retained descriptor ownership. Match file mutations by inode identity rather than descriptor number. Test multiple mappings from one fd, mutation through `dup`, and close/reuse.

**P32-R4-11 — Syscall memory access bypasses guest sub-page permissions**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/os/syscalls.c:118`
- **Evidence & Root Cause:** Read/write and vectored I/O validate only numerical address bounds before passing guest pointers to host syscalls. Likewise, `ppc32_copyin/out()` in `src/os/convert.c:123` use unchecked `memcpy`. On A2, an accessible neighboring sub-page can make the host page writable while the target guest page is read-only or unmapped. These accesses then succeed despite guest permissions.
- **Concrete Fix:** Consolidate syscall access through repo-local, permission-aware copy helpers. Use stable checked buffers or suitable mapping synchronization for blocking I/O, preserving partial-transfer semantics. Cover inaccessible sub-pages sharing an accessible host page.

**P32-R4-12 — Safe copyout does not invalidate peer reservations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:679`
- **Evidence & Root Cause:** `ppc32_vm_copyout_safe()` writes with `memcpy` without updating reservation epochs or synchronizing with `vm32_sc_attempt()`. Syscall entry invalidates only the calling context’s reservation. Another guest thread can retain a reservation across a syscall copyout that writes the same value, allowing its compare-exchange to succeed incorrectly.
- **Concrete Fix:** Route copyout through a common guest-write mechanism that serializes against SC and invalidates every affected reservation granule. Apply it to signal/thread copyouts and syscall I/O destinations. Test a peer reservation followed by same-value copyout.

**P32-R4-13 — Unused broadcast truncate API remains exposed**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/vm/vm_file.c:829`
- **Evidence & Root Cause:** Repository references to `vm_file_on_truncate()` consist only of its definition and header declaration. Its implementation applies one file size to every registered mapping regardless of file identity, while the actual syscall uses the fd-specific variant.
- **Concrete Fix:** Remove the unused broadcast function and declaration. Keep one identity-aware mutation interface.

The source scan found no files exceeding 900 lines and no matches for prohibited string functions, `atoi`, or `.c` includes. Textual `x18`/`w18` matches were comments; encoded register usage and full C11 compliance were not exhaustively verified. No separate DRY or CLEAN finding is asserted.

- [ ] **P32-R4-1:** Preserve `readv` results and invalidate completed transfers.
- [ ] **P32-R4-2:** Correct staging-extension source offsets.
- [ ] **P32-R4-3:** Unify backing for overlapping shared aliases.
- [ ] **P32-R4-4:** Prevent stale staging writeback from overwriting file updates.
- [ ] **P32-R4-5:** Preserve backing identity across VMA splits.
- [ ] **P32-R4-6:** Guard shared host-page tails during automatic placement.
- [ ] **P32-R4-7:** Correct empty-file and beyond-EOF trapping.
- [ ] **P32-R4-8:** Remove the fork/truncate lock-order inversion.
- [ ] **P32-R4-9:** Make truncate updates safe for inaccessible mappings.
- [ ] **P32-R4-10:** Track all aliases independently of fd numbers.
- [ ] **P32-R4-11:** Enforce guest permissions for syscall memory access.
- [ ] **P32-R4-12:** Invalidate peer reservations on copyout.
- [ ] **P32-R4-13:** Remove the unused broadcast truncate API.