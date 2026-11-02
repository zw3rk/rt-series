Found **11 actionable issues** at HEAD `5232650`. The Round-3 fixes improve registry growth, worker registration, and cache invalidation, but leave important failure paths incomplete.

Used **seven shell inspection commands**, including `git log -n 5 --oneline`, `git show HEAD~1 --stat`, and `git show HEAD`. No Markdown files, builds, tests, Docker, or QEMU were read or run. `tools/` does not exist in this checkout. Findings below are static traces, not runtime reproductions.

**S64-R4-1 — Negative 32-bit integer-to-float conversions use the wrong magnitude**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp_conv.c:191`
- **Evidence & Root Cause:** `cv_itos()` computes negative magnitude as `UINT64_C(0) - (uint64_t)(uint32_t)v`. For `v == -1`, this produces `0xffffffff00000001`, not `1`. Both FITOS and FITOD then convert that enormous magnitude with a negative sign. The DBT uses signed AArch64 conversion instructions, so this also creates interpreter/DBT divergence.
- **Concrete Fix:** Sign-extend before unsigned negation: `UINT64_C(0) - (uint64_t)(int64_t)v`, or negate after widening to `int64_t`. Add FITOS/FITOD vectors for `-1`, `INT32_MIN`, and negative values around single-precision rounding boundaries.

**S64-R4-2 — Directed rounding increments exactly representable integers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp_conv.c:168`
- **Evidence & Root Cause:** `cv_int_bits()` sets `up = neg == 0U` for upward rounding and `up = neg != 0U` for downward rounding, regardless of discarded bits. Thus converting positive integer `1` under upward rounding returns the next representable float above `1`, while reporting NX clear. The helper serves FITOS, FITOD, FXTOS, and FXTOD.
- **Concrete Fix:** Require inexactness for directed increments: `up = (*nx != 0U) && …`. Test exact positive and negative integers under all four rounding modes, checking result bits and FSR flags.

**S64-R4-3 — Failed relocated mremap leaves the source moved and skips the shared code epoch**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem.c:697`
- **Evidence & Root Cause:** The substrate publishes the relocation before `sysmem_file_fill_growth()`. On `-12`, cleanup removes only the growth tail; the original bytes remain at `dest`, and the source has already disappeared. The syscall returns `-ENOMEM`, leaving callers with an invalid original pointer. For FIXED relocation, replaced destination mappings are also lost. `vm64_stxn_abort()` only clears transaction state; unlike commit, it does not bump `vm64_code_epoch`, so sleeping threads can retain translations for mappings that changed.
- **Concrete Fix:** Prepare and populate the entire candidate before publishing relocation, or retain enough backing and registry state to restore both source and replaced destination completely. Fault-inject growth-fill failure and verify mappings, contents, metadata, and cache visibility remain unchanged.

**S64-R4-4 — Retained-fd failures silently turn file growth into anonymous zero-filled memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:207`
- **Evidence & Root Cause:** `sysmem_file_note_map()` marks an entry live and returns success even when descriptor duplication fails. Split paths likewise accept failed duplicates. `sysmem_file_fill_overlap()` explicitly returns success for `slot->fd < 0` at `src/os/sysmem_file_fill.c:184`, leaving zero-filled growth pages and bypassing EOF/BUS classification. Descriptor exhaustion therefore changes observable mapping semantics.
- **Concrete Fix:** Acquire required descriptors before publishing mapping changes and propagate acquisition failures. Prefer a repository-local reference-counted backing-description object so splitting ranges does not require additional host descriptors. Test descriptor exhaustion during initial registration and splitting.

**S64-R4-5 — munmap allocation failure silently discards metadata for a surviving mapping**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem.c:410`
- **Evidence & Root Cause:** `sparc64_sysmem_munmap()` ignores the registry reservation result. When a middle excision subsequently cannot claim a tail slot, `sysmem_file_drop_map()` trims the head and continues at line 341 without tracking the still-mapped tail. Later truncation cannot update that tail’s EOF faults; later growth cannot recover its file backing. This contradicts the Round-3 claim that live tracking is never evicted.
- **Concrete Fix:** Return `-ENOMEM` before mutation when required split metadata cannot be reserved, or provide a representation that preserves both survivors without allocation. Add a forced-allocation-failure case for middle-page unmapping.

**S64-R4-6 — Truncation can restore permissions revoked by mprotect**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:488`
- **Evidence & Root Cause:** File registration records `slot->prot`, but `sparc64_sysmem_mprotect()` changes only the address-space pages and caches. Truncate shrink passes the stale `slot->prot` to `sparc64_space_map_bus()`; subsequent growth passes it to `sparc64_space_replace()` at line 511. A mapping originally writable, then made read-only or inaccessible, can regain its original permissions after shrink/growth.
- **Concrete Fix:** Preserve current per-page permissions when changing backing/BUS state, or split and update registry permissions transactionally on every successful `mprotect`. Test whole-range and partial-range permission changes followed by truncate shrink and regrowth.

**S64-R4-7 — Failed execve closes descriptors, including newly retained mapping descriptors**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/proc.c:492`
- **Evidence & Root Cause:** `proc_close_cloexec()` runs before host `execve()` or guest image loading can fail. Its process-wide scan closes every CLOEXEC descriptor numbered three or higher. A failed exec therefore destroys guest descriptors that should survive failure. HEAD’s new `F_DUPFD_CLOEXEC` mapping descriptors are also swept up, while existing registry entries retain their numeric fd values. Subsequent descriptor reuse can make those entries reference unrelated files.
- **Concrete Fix:** Apply guest CLOEXEC closure only at successful guest-image commit, using explicit guest descriptor ownership. Let host `execve()` perform its own atomic CLOEXEC handling. Keep translator-owned retained descriptors outside the guest close sweep. Test failed exec followed by descriptor use and file-backed mremap.

**S64-R4-8 — Signal masks, pending signals, and alternate stacks remain process-global**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sync_sig.c:74`
- **Evidence & Root Cause:** `sync_blocked`, `sync_pending`, and alternate-stack fields are single static variables. The thread structure contains no corresponding per-thread state, and engine lock handoff does not save or restore it. Consequently, one guest thread’s mask or alternate-stack change affects siblings; pending delivery can consume another thread’s state. Serializing execution with the big lock does not provide per-thread semantics.
- **Concrete Fix:** Store thread-specific signal state in the guest thread record and resolve it through the active context. Keep shared dispositions separate. Implement clone inheritance and alternate-stack reset rules explicitly. Add two-thread tests with different masks and alternate stacks.

**S64-R4-9 — Retried relative futex waits restart the full timeout**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_darwin.c:238`
- **Evidence & Root Cause:** After backend `-EINTR`, the Darwin loop updates `expected_seq` and retries using the original relative `ts`. The backend computes a new deadline from the current time on every invocation. Repeated interruptions can therefore extend a finite WAIT indefinitely. The Linux retry loop in `src/os/threads.c:456` also resubmits the unchanged relative timeout.
- **Concrete Fix:** Compute a monotonic deadline once for relative WAIT and pass the remaining duration on internal retries. Distinguish internal preemption from guest-visible signal interruption. Add a timed-wait case with repeated internal wakeups and an unchanged futex word.

**S64-R4-10 — Round-3 registry tests omit the syscall transaction paths they claim to cover**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:155`
- **Evidence & Root Cause:** `check-r3` links the registry, population, memory, and VM files, but excludes `guest_run_sysmem.c`. Its tests exercise registry helpers directly and use counting stubs for invalidation. They cannot exercise mmap/mremap/munmap transaction ordering, mprotect metadata maintenance, or the failing relocation cleanup in S64-R4-3. Successful helper tests therefore leave the consequential integration paths unchecked.
- **Concrete Fix:** Add focused tests that invoke the actual syscall shells, with injectable allocation, descriptor, and fill failures. Assert address-space and registry state before and after failure, plus epoch behavior. Retain the existing helper tests.

**S64-R4-11 — Floating-point exception commit logic is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/interp/fp_conv.c:82`
- **Evidence & Root Cause:** `cv_commit()` duplicates the FSR current-exception update, accrued-exception update, TEM check, and trap construction in `sd_commit()` at `src/interp/fp_sd.c:71`. Both implement the same architectural operation, so future exception corrections require synchronized edits.
- **Concrete Fix:** Introduce one repository-local FP exception-commit helper in an internal header/source pair. Use it from both paths and keep result-publication ordering explicit.

The source-length inspection found no `.c`, `.h`, or `.S` file above 900 lines; the largest was `src/os/threads.c` at 897. The prohibited-call scan found `strcpy`/`strcat` in the libc string test, including intentional coverage of those functions. No confirmed YAGNI finding emerged from the bounded inspection. These checks do not establish complete C11 compliance or prove that encoded JIT instructions avoid `x18`.

- [ ] **S64-R4-1:** Correct negative 32-bit conversion magnitudes.
- [ ] **S64-R4-2:** Gate directed-rounding increments on inexactness.
- [ ] **S64-R4-3:** Make failed mremap relocation fully transactional.
- [ ] **S64-R4-4:** Handle retained-descriptor acquisition failures.
- [ ] **S64-R4-5:** Preserve surviving mapping metadata on allocation failure.
- [ ] **S64-R4-6:** Preserve current permissions across truncate transitions.
- [ ] **S64-R4-7:** Defer CLOEXEC closure until successful exec commit.
- [ ] **S64-R4-8:** Make signal masks, pending state, and alternate stacks thread-specific.
- [ ] **S64-R4-9:** Preserve futex deadlines across retries.
- [ ] **S64-R4-10:** Test actual syscall transaction and failure paths.
- [ ] **S64-R4-11:** Unify FP exception commit logic locally.