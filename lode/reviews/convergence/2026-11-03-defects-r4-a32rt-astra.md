Found **9 actionable issues** at HEAD `5561e7e`. The Round-3 fixes are present, but several replacement, remapping, fork, and exec paths remain incomplete.

Used exactly **7 shell inspection commands**, including the requested history commands. No Markdown files, builds, tests, containers, or QEMU were read or run. These are static findings; runtime reproduction remains outstanding. The working tree is clean.

**A32-R4-1 — Repeated private-file `mremap` loses backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_mremap.c:194`
- **Evidence & Root Cause:** In-place growth creates a separate file-tracking record for the extension. Only shared mappings receive the attempted record merge at line 207. A subsequent private remap spanning the enlarged range fails `mremap_priv_lookup()`’s single-record coverage requirement at line 66. The caller treats this as anonymous backing: further growth supplies zero-filled pages, and relocation drops file identity and EOF behavior. Descriptor-duplication failure also silently takes this anonymous fallback.
- **Concrete Fix:** Coalesce compatible private backing records after growth, or resolve backing across contiguous records with matching inode and offsets. Distinguish absent backing from lookup/resource errors and propagate errors. Add regressions for grow→grow and grow→move, including descriptor exhaustion.

**A32-R4-2 — Darwin anonymous replacement retains old storage and sharing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:77`
- **Evidence & Root Cause:** The replacement branch uses `mprotect`, optional `memset`, and `minherit`; it never replaces the backing object. Replacing a shared-file mapping with private anonymous memory therefore writes zeros into the shared file and leaves subsequent accesses attached to it. Separately, anonymous `PROT_NONE` replacement skips zeroing entirely; a later `mprotect` exposes bytes from the previous mapping.
- **Concrete Fix:** Install genuinely fresh anonymous backing. For sub-page replacements, preserve unaffected 4 KiB siblings while replacing the necessary host-page storage, and retain shared aliases correctly. Add shared-file→anonymous replacement and `PROT_NONE`→read/write zero-fill regressions on Darwin.

**A32-R4-3 — Fork resumes parent threads before restoring protections**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:226`
- **Evidence & Root Cause:** The snapshot path changes guest clusters to `PROT_NONE` at lines 211–218. Immediately after `fork()`, the parent calls `a32_jit_fork_parent()`, clearing the execution barrier and releasing the JIT lock. Guest protections are restored only at lines 250–255. Another guest thread can resume inside this interval and fault on valid memory.
- **Concrete Fix:** Keep parent execution blocked until all guest protections are restored, including the failed-fork path. Check restoration failures before reopening execution. Add a concurrent memory-access/fork regression.

**A32-R4-4 — Fork snapshot reads inaccessible EOF pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:208`
- **Evidence & Root Cause:** Snapshot selection uses VMA permissions, then copies each entire region. File mappings retain their requested VMA permissions even when `a32_vm32_set_eof_cut()` makes trailing pages inaccessible on A1. A readable mapping extending beyond EOF consequently reaches this unconditional `memcpy` over protected pages. Signals are blocked during the operation. The new EOF-aware `mremap` handling has no equivalent here.
- **Concrete Fix:** Snapshot accessible file-backed prefixes page by page, respecting EOF cuts. Preserve cut metadata and protections during restoration rather than applying VMA permissions across the whole region. Add fork coverage for fresh beyond-EOF mappings and mappings truncated before fork.

**A32-R4-5 — Same-start prefix replacement defeats the new capacity preflight**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:151`
- **Evidence & Root Cause:** `a32_vmfile_check_replace()` treats any record beginning at `start_gva` as reusable. If the replacement covers only its prefix, retirement moves that record’s start to `unmap_end` at lines 664–666; its slot remains occupied by the surviving suffix. With a full table, preflight nevertheless succeeds. `a32_vm_mmap_locked()` retires metadata at line 635, then fails its second capacity check at line 639, leaving the old host prefix mapped without its previous tracking.
- **Concrete Fix:** Count same-start records as freed only when fully covered. Reserve replacement and split resources before retiring anything. Add a full-table test replacing only the first page of a larger file mapping.

**A32-R4-6 — Failed backing splits silently preserve records over unmapped memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:634`
- **Evidence & Root Cause:** Middle splits silently `continue` when a slot or duplicated descriptor cannot be obtained; the private-record path does likewise at lines 673–678. The caller receives no error. `munmap` has already replaced the host range, and anonymous `MAP_FIXED` bypasses the file replacement preflight. Old backing records can therefore cover holes or unrelated anonymous mappings. Later file truncation can apply EOF cuts to that unrelated memory.
- **Concrete Fix:** Make backing retirement fallible and reserve all split slots/descriptors before host or VMA mutation. Propagate failure without changing the mapping. Exercise both table exhaustion and `EMFILE` during middle unmap/replacement.

**A32-R4-7 — Exec signal variables survive in the guest environment and override fresh state**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/main.c:349`
- **Evidence & Root Cause:** The guest stack receives `envp` before `exec_signal_restore()` unsets the three transport variables at line 357. Unsetting the host environment does not remove the guest’s copied strings. On another exec, `os_sys_sig_time.c:669` copies those old entries and appends new entries with identical names. Startup `getenv()` can consequently consume the earlier, stale signal mask, ignored set, and pending set. The claimed native-child cleanup is also incomplete because native exec receives the guest-supplied environment.
- **Concrete Fix:** Consume and remove transport entries before constructing the guest environment. Filter existing transport keys when composing subsequent exec environments, then insert exactly one current value per key. Add repeated-exec tests that change masks and dispositions between execs.

**A32-R4-8 — VMA exhaustion makes partial `mprotect` alter unrelated metadata**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:280`
- **Evidence & Root Cause:** When splitting a VMA cannot allocate entries, `vm_mprotect_regions_locked()` substitutes `r->prot = prot` for the whole original region. Similar fallbacks exist at lines 288 and 297. Host permissions and Soft-TLB permissions are changed only for the requested range, while the VMA records claim broader changes. The syscall still reports success, leaving contradictory permission state for subsequent VM operations.
- **Concrete Fix:** Preflight required VMA splits before changing host permissions. Return `-ENOMEM` without mutation when capacity is insufficient; never widen the metadata update. Add a saturated-region-table partial-`mprotect` regression.

**A32-R4-9 — Epoll output validation covers only one event**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/os_sys_fs_arm.c:89`
- **Evidence & Root Cause:** Both `epoll_wait` and `epoll_pwait` validate only `sizeof(struct epoll_event)` bytes, then pass guest memory directly to the kernel with guest-controlled `maxevents`. Additional returned events can cross guest protection boundaries. This matters on A2 Linux hosts, where host-page permissions can permit writes that guest 4 KiB permissions prohibit.
- **Concrete Fix:** Check the complete bounded output extent, or receive events into a host buffer and perform checked guest copyout for the returned count. Share that validation/copyout helper between both branches. Add a multiple-ready-event test with the buffer ending immediately before a protected guest page.

The inspected source files satisfy the 900-line limit, and the targeted search found no forbidden string functions, unity includes, or literal `x18` use. Warning policy includes the requested C11 flags. This was not compilation-based compliance verification. No sufficiently supported standalone DRY, YAGNI, or CLEAN finding emerged; ISA/FPU and concurrency coverage is not exhaustive within the inspection budget.

- [ ] **A32-R4-1:** Preserve private backing across repeated remaps and propagate lookup errors.
- [ ] **A32-R4-2:** Replace Darwin anonymous backing without retaining old bytes or file aliases.
- [ ] **A32-R4-3:** Restore parent protections before reopening JIT execution.
- [ ] **A32-R4-4:** Make fork snapshots and restoration respect EOF cuts.
- [ ] **A32-R4-5:** Correct capacity accounting for same-start prefix replacements.
- [ ] **A32-R4-6:** Reserve backing-split resources before mutation and propagate failures.
- [ ] **A32-R4-7:** Remove stale exec signal transport entries from guest environments.
- [ ] **A32-R4-8:** Reject partial protection changes when VMA splits cannot be represented.
- [ ] **A32-R4-9:** Validate or safely copy out the complete epoll result.