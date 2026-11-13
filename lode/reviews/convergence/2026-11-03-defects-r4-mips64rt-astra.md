Found **10 actionable issues** at `f7c6924`. The Round-3 staged-copyout changes, single-call vectored I/O, and post-fable CAS changes are present, but edge cases remain.

Used exactly **seven shell inspection commands**, including the requested `git log -n 5 --oneline`, `git show HEAD~1 --stat`, and `git show HEAD`. No Markdown documents, builds, tests, Docker, or QEMU were run. Findings below are static conclusions, not runtime reproductions.

**M64-R4-1 — File writes can leave stale translated code**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:530`
- **Evidence & Root Cause:** `vm_inode_apply_write_locked()` passes file offsets `off` and `wend` to `vm_inode_invalidate_maps()` at line 582. That function compares them against guest virtual addresses `maps[i].va`. For a file mapped at guest `0x100000`, a write to file offset zero fails the overlap check. Fallback bytes can be refreshed while the corresponding DBT translation survives; native mappings also miss invalidation.
- **Concrete Fix:** Intersect the write interval with each mapping’s `[file_offset, file_offset + len)` interval, translate that intersection into guest VA, and invalidate it. Add coverage for executable aliases at different VAs and nonzero file offsets.

**M64-R4-2 — Shared fallback stores past EOF extend the backing file**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:654`
- **Evidence & Root Cause:** `mips_vm_file_shared_sync()` clips stores to the mapping but not to `in->size`. It issues `pwrite()` for the entire intersection. On a fallback shared mapping of a one-byte file, a guest store at offset two extends the file to three bytes. The zero-filled tail of the final mapped page must not become file content merely through a mapped store. The function also ignores short writes and errors before marking the range clean and refreshing aliases.
- **Concrete Fix:** Limit backing-file writes to bytes below EOF. Preserve final-page tail bytes without extending the file. Handle short writes and failures before publishing clean/coherent state. Cover partial-page EOF and failed writeback.

**M64-R4-3 — File refresh helpers violate the 16 KiB host-page strategy**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:377`
- **Evidence & Root Cause:** `mips_vm_inode_refresh_span()` derives host writability from guest permissions and calls `mprotect(p, 4096, ...)` on a guest-page address. `mips_vm_inode_zero_span()` does the same at line 349. On a 16 KiB host, a guest page at host-page offset `0x1000` is not a valid protection boundary: these helpers return without refreshing or zeroing it. On an aligned first subpage, restoring guest permissions can instead alter protection for neighboring subpages, defeating the RW host cover. Callers subsequently advance reconciliation sequence numbers.
- **Concrete Fix:** Make both helpers obey the existing large-host-page cover policy. Keep guest subpage permissions in software; use host-aligned protection changes only where required and propagate failures. Cover refresh and truncation on all four subpages, including mixed guest permissions.

**M64-R4-4 — File-tracking exhaustion silently loses backing metadata**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/vm/vm_file.c:371`
- **Evidence & Root Cause:** `vm_inode_split_at()` silently skips splitting when the 128-entry map table is full. Its `fcntl()` duplication can also fail, yet the new record is committed with `fd_dup == -1`. The middle-unmap path at lines 473–484 discards the right-hand record when full and only sets `wide`. That flag broadens DBT invalidation; it cannot restore missing EOF, coherence, or remap metadata. Mapping registration similarly returns silently when inode allocation fails.
- **Concrete Fix:** Reserve metadata capacity and duplicate descriptors before committing VM changes. Return failures through the map/split/remap interfaces and preserve existing records on failure. Reclaim empty inode slots or grow the repo-local tables. Add capacity and descriptor-exhaustion cases.

**M64-R4-5 — Round-3 absorbed-operand correction is asymmetric**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:678`
- **Evidence & Root Cause:** The correction detects only `qd == a`, where the second operand disappears. With `a = 2^-126`, `b = 1.0f`, and ADD.S, binary64 `qd` equals `b`; the condition fails. Consequently `q == r == 1`, Inexact is omitted, and rounding toward positive infinity incorrectly returns `0x3f800000` instead of `0x3f800001`. The new regression table always puts the larger finite operand first.
- **Concrete Fix:** Detect absorption of either effective operand, preserving the smaller operand’s residual sign after subtraction. Extend tests to both operand orders, both signs, ADD/SUB, and all four rounding modes.

**M64-R4-6 — Paired-single arithmetic ignores guest rounding mode**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp_ps.c:103`
- **Evidence & Root Cause:** `fp_ps_lane()` receives neither FCSR nor a rounding mode. ADD.PS, SUB.PS, and MUL.PS return the host-rounded result directly. For example, `1.0f + 2^-24` under guest rounding toward positive infinity must select the next float, but this path returns the host nearest-even result. Its direct `long double` reference also retains the absorbed-operand problem fixed separately for scalar operations.
- **Concrete Fix:** Share a repo-local single-precision arithmetic implementation that accepts the guest rounding mode and returns result bits plus exceptions. Use it for scalar and paired lanes, preserving whole-destination trap suppression. Test each lane under every mode.

**M64-R4-7 — Quiet comparisons fail to raise Invalid for signaling NaNs**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:791`
- **Evidence & Root Cause:** Comparison handling raises Invalid only when the predicate’s signaling bit, `cond & 8`, is set. It never calls `fp_issn_s()` or `fp_issn_d()`. Thus a quiet predicate such as C.EQ.S with a legacy signaling-NaN operand produces an unordered result without Invalid or an enabled exception trap. The DBT explicitly falls back to this interpreter path for unordered operands.
- **Concrete Fix:** Raise Invalid when either operand is signaling NaN, or when a signaling predicate receives any NaN. Preserve FCC on an enabled trap. Cover quiet/signaling predicates against both NaN classes in S and D formats.

**M64-R4-8 — `sigaltstack` returns a mixture of old and new state**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigact.c:429`
- **Evidence & Root Cause:** `reported` is computed from the original stack at lines 385–388. The function then overwrites `ctx->sigalt_sp` and `ctx->sigalt_size`, and serializes those updated fields into `oss`. Calling `sigaltstack(&new_stack, &old_stack)` therefore returns the new address and size with the old status flags. Disabling an installed stack similarly loses its previous address and size.
- **Concrete Fix:** Snapshot the complete old stack before processing `ss`, and serialize that snapshot into `oss`. Cover replacement, disabling, and aliased input/output buffers for N64 and N32.

**M64-R4-9 — Two syscall copyout implementations duplicate the commit protocol**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/syscalls_sync.c:206`
- **Evidence & Root Cause:** `l2a_commit_guest_write()` duplicates the lock, copy, reservation invalidation, COW clearing, code retirement, and shared-file synchronization sequence in `mips_sc_copyout()` (`src/os/syscalls.c:156`). They already differ in range validation and explicit `ctx->llbit` clearing. Future corrections must reach both paths.
- **Concrete Fix:** Route scalar/vector commits through `mips_sc_copyout()`, retaining partial-byte accounting in `l2a_vec_copyout()`. Alternatively, factor one internal commit primitive with explicit validation requirements. Keep the helper repository-local.

**M64-R4-10 — Superseded signal-mask and deferred-copyout scaffolding remains**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/syscalls_sync.c:120`
- **Evidence & Root Cause:** `l2a_sigmask` and `mips_sc_rt_sigprocmask()` remain despite dispatch selecting `mips_l4a_rt_sigprocmask()` at `src/os/syscall_min.c:700`; repository references show no caller of the old implementation. Separately, all remaining `guest_range()` calls use read mode, leaving its write branch, `g_sync_*` queue, and dispatcher flush obsolete after HEAD’s copyout migration.
- **Concrete Fix:** Remove the unused signal-mask implementation and declaration. Remove the deferred write queue and flush call; make `guest_range()` explicitly read-only and update its declarations.

The CLEAN inspection found no over-900-line `.c`, `.h`, or `.S` files, prohibited string functions, source-file includes, or literal `x18` assembly use. `Makefile:22` contains the required warning flags. This is not compiler validation or a complete audit of generated register encodings. The requested `include/` and `tools/` directories do not exist at this HEAD.

- [ ] **M64-R4-1:** Translate file offsets to guest addresses before DBT invalidation.
- [ ] **M64-R4-2:** Bound shared writeback by EOF and handle write failures.
- [ ] **M64-R4-3:** Make refresh/zero helpers respect 16 KiB host-page coverage.
- [ ] **M64-R4-4:** Preserve backing metadata on capacity or descriptor exhaustion.
- [ ] **M64-R4-5:** Correct absorbed operands in both operand orders.
- [ ] **M64-R4-6:** Honor FCSR rounding in paired-single arithmetic.
- [ ] **M64-R4-7:** Raise Invalid for signaling NaNs in quiet comparisons.
- [ ] **M64-R4-8:** Return a complete old alternate-stack snapshot.
- [ ] **M64-R4-9:** Unify syscall copyout commit logic.
- [ ] **M64-R4-10:** Remove superseded mask and deferred-copyout scaffolding.