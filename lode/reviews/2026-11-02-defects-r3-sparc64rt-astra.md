Found **7 actionable findings** at `001f2b1`. Inspection used **7 shell turns**, including `git log -n 5 --oneline`, `git show HEAD~1`, `git show HEAD`, targeted source reads, reference searches, and source line counts. No builds, tests, Docker, or QEMU ran; no files changed.

The findings below distinguish active guest-path defects from defects in currently unwired backend helpers. Static inspection does not establish full ISA/FPU or runtime correctness.

**S64-R3-1 — VM mutations do not invalidate sleeping threads’ DBT caches**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:578`; `src/os/guest_run_sysmem.c:640`; `src/os/threads.c:410`
- **Evidence & Root Cause:** VM preparation increments each peer’s `dbt_epoch`, but the repository contains no reader of that field. Mapping operations invalidate only `g->dbt`, while `run_dbt` explicitly keeps separate DBT instances per thread. After a futex wait reacquires the execution lock, only the register-window cache is invalidated. A thread can therefore resume cached code after another thread replaces, unmaps, or removes execute permission from its code pages.
- **Concrete Fix:** Connect a shared address-space code generation to every DBT instance. Check it upon lock reacquisition and before cached execution, flushing stale blocks and chaining entries. Validate with a thread that caches code, sleeps, and resumes after a peer changes that mapping.

**S64-R3-2 — File-backed `mremap` growth produces anonymous zero pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/mem_space.c:623`; `src/os/guest_run_sysmem_file.c:447`
- **Evidence & Root Cause:** Guest file `mmap` populates ordinary space pages through `sysmem_file_fill` and records file identity separately. Remap extends backing from `original->file`, which this population path does not attach. The registry update merely expands coverage and assigns chunk states; it does not load the corresponding file bytes or establish beyond-EOF BUS pages. Growing an 8 KiB mapping of a larger file therefore exposes zeros instead of the next file page.
- **Concrete Fix:** Preserve a retained file-backing object and offset on mapped pages. Grow through the file-population/EOF path, including beyond-EOF fault classification, before committing the remap.

**S64-R3-3 — File-range registry silently discards live mapping semantics**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:117`
- **Evidence & Root Cause:** `sysmem_file_note_map` selects `sysmem_file_next % 64` and overwrites that entry without checking whether it is live. The source explicitly acknowledges that eviction leaves stale readable bytes. After 65 live file mappings, truncating the first file can leave its mapping readable instead of producing the required beyond-EOF fault. Split handling also drops survivors when no slot is available.
- **Concrete Fix:** Store this metadata with live mappings or use a growable registry. If allocation fails, reject the operation before mutation; never silently remove correctness metadata for an existing mapping.

**S64-R3-4 — Darwin backend fixes remain disconnected from guest futex dispatch**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/os/threads.c:402`
- **Evidence & Root Cause:** The active futex wait path calls `thr_host_futex` only under `__linux__`; its Darwin branch assigns `-ENOSYS`. The newly repaired `rt_host_futex_wait_bitset`, wake, and requeue implementations have no callers outside their backend definitions. Consequently, the Round-2 Darwin futex repairs do not provide guest-thread synchronization on the standalone Darwin runtime.
- **Concrete Fix:** Route guest futex operations through the backend contract, including worker signal state, validated keys, and pinned backing lifetime. Exercise the actual guest dispatch path rather than testing backend helpers alone.

**S64-R3-5 — Darwin worker registration leaks slots across thread lifetimes**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin_sync.c:78`; `src/vm/vm64.c:710`
- **Evidence & Root Cause:** `darwin_worker_register` fills a fixed 256-entry table, but no path removes entries. `vm64_worker_unregister` even calls `rt_host_register_self` before clearing only the separate VM worker table. Once enough distinct thread IDs have accumulated, registration silently fails and `rt_host_preempt_worker` cannot locate new live workers.
- **Concrete Fix:** Add backend worker unregistration and invoke it during thread teardown. Propagate table exhaustion instead of reporting successful registration, and synchronize lookup with worker lifetime.

**S64-R3-6 — Directory-cache eviction loses unread entries**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:456`
- **Evidence & Root Cause:** When all 32 directory slots are occupied, `rt_host_getdents64` closes slot zero’s `DIR *` and discards its pending entry. `readdir` may have buffered multiple entries while advancing the shared underlying descriptor offset. Recreating a stream from `dup(fd)` cannot recover that discarded buffer or pending entry, so interleaved pagination across 33 directories can skip entries.
- **Concrete Fix:** Retain streams until their associated open descriptions close, or reject new cache allocation without disturbing existing streams. Track duplicated descriptors through shared directory state.
- **Reachability:** This is a backend API defect; the inspected guest getdents path does not call this helper.

**S64-R3-7 — Wake-pipe sleep can return success before the requested deadline**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin_sync.c:496`
- **Evidence & Root Cause:** `rt_host_clock_nanosleep` floors fractional milliseconds, caps long waits at `INT_MAX` milliseconds, performs one `poll`, and treats its timeout as successful completion. It neither rounds the full duration upward nor checks the original deadline afterward. Long requests are shortened to the cap, and fractional requests can finish early.
- **Concrete Fix:** Maintain a validated deadline, round each bounded poll interval upward, and recompute remaining time until the deadline is reached. Preserve remaining-time reporting on interruption.
- **Reachability:** This helper currently has no guest-dispatch caller; the defect affects its backend contract.

The source line-count inspection found no `.c`, `.h`, or `.S` file under `src/`, `include/`, or `tests/` exceeding 900 lines. The targeted forbidden-construct search found no prohibited string functions or `.c` includes; textual `x18` matches were comments. These checks do not constitute compiler or emitted-instruction validation.

- [ ] **S64-R3-1:** Connect peer VM changes to every thread’s DBT invalidation.
- [ ] **S64-R3-2:** Preserve file contents and EOF semantics during remap growth.
- [ ] **S64-R3-3:** Stop evicting live file-mapping metadata.
- [ ] **S64-R3-4:** Wire Darwin futex helpers into guest dispatch.
- [ ] **S64-R3-5:** Unregister Darwin workers and handle table exhaustion.
- [ ] **S64-R3-6:** Preserve unread directory entries across cache pressure.
- [ ] **S64-R3-7:** Wait until the requested sleep deadline.