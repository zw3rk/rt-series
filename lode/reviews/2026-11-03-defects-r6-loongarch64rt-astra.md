Found **eight remaining issues** at verified HEAD `494c134`. Used **six shell commands**; no Markdown reads, builds, tests, Docker, or QEMU. Findings are static, not runtime-confirmed. Git remediation history was checked, but without the previous audit reports, “never reported in Rounds 1–5” cannot be fully established.

1. **loongarch64rt-R6-1 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:384–404`  
   **`statx` returns timestamps in the wrong fields.** With `at = dst + 64`, modification time is written at offset 96 (`stx_ctime`), and change time at offset 80 (`stx_btime`). Actual `stx_mtime` at offset 112 remains zero, despite `stx_mask` advertising basic timestamps. Both host branches contain the error. This can break timestamp-based rebuilds and synchronization.  
   **Fix:** Write ctime at offset 96 and mtime at 112, preferably through the already layout-asserted structure instead of relative numeric offsets.

2. **loongarch64rt-R6-2 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:505–506`, `src/os/syscalls.c:653–661`  
   **`fchownat` silently discards its flags argument.** Dispatch passes only `a0`–`a3` into `sys_at2`; the handler always supplies zero flags. Consequently, `AT_SYMLINK_NOFOLLOW` requests follow the symlink and can change ownership of its target instead. `AT_EMPTY_PATH` also cannot work.  
   **Fix:** Forward `a4`, validate guest flags, and translate supported flags to host constants before calling `fchownat`.

3. **loongarch64rt-R6-3 — DEFECT — HIGH**  
   **Location:** `src/os/clone.c:555–585`, `src/os/clone.c:447–470`  
   **`CLONE_CHILD_SETTID` never stores the child TID.** The flag causes pointer validation, but `ctid_va` is retained only for `CLONE_CHILD_CLEARTID`. Worker startup begins executing instructions without writing the requested TID. A guest using CHILD_SETTID without PARENT_SETTID observes an unchanged word.  
   **Fix:** Retain the CHILD_SETTID destination separately from the clear-on-exit destination and write the child’s guest TID before its first guest instruction.

4. **loongarch64rt-R6-4 — BUG — HIGH**  
   **Location:** `src/os/clone.c:532–541`, `src/os/clone.c:560–583`  
   **Failed clone setup leaves a nonexistent thread in the scheduler.** The child enters the scheduler ring before allocation. Allocation failure and subsequent guest-memory failures free/reset the clone slot but omit `la64_sched_abort_clone`. Once scheduling reaches that entry, no worker exists to advance the turn. The `pthread_create` failure path already performs the necessary rollback.  
   **Fix:** Use one cleanup path that removes scheduler registration on every failure after registration, or defer registration until other fallible setup has completed.

5. **loongarch64rt-R6-5 — BUG — HIGH**  
   **Location:** `src/os/clone.c:284–320`, `src/os/clone.c:329–339`  
   **The two futex waiter queues violate wake and requeue semantics.** Untimed waits use the cooperative queue; timed waits use the kernel queue. WAKE applies the full requested count independently to both, so `WAKE(1)` can wake two waiters. REQUEUE returns after processing only the cooperative queue whenever scheduling is engaged, leaving timed kernel waiters at the original address.  
   **Fix:** Coordinate both queues: subtract cooperative wakes from the kernel wake allowance and implement requeue across both populations. Prefer one consistent waiter implementation if feasible.

6. **loongarch64rt-R6-6 — BUG — MEDIUM**  
   **Location:** `src/os/clone.c:380–387`  
   **Darwin treats monotonic `FUTEX_WAIT_BITSET` deadlines as relative timeouts.** The absolute-deadline branch requires both WAIT_BITSET and CLOCK_REALTIME. Without CLOCK_REALTIME, an absolute monotonic timestamp is added to the current time, extending the wait by approximately host uptime.  
   **Fix:** Treat every WAIT_BITSET timeout as absolute. Use CLOCK_REALTIME only to select the clock; add the current time only for relative FUTEX_WAIT.

7. **loongarch64rt-R6-7 — DRY — LOW**  
   **Location:** `src/os/syscalls.c:362–418`, `src/os/backend_darwin_fs.c:253–323`  
   **Two independent `statx` serializers duplicate the same guest ABI layout and have diverged.** The syscall serializer misplaces timestamps; the Darwin backend uses the correct ctime/mtime offsets and preserves nanoseconds, which the syscall’s Darwin branch discards. Maintaining separate numeric-offset implementations makes further drift likely.  
   **Fix:** Consolidate guest `statx` serialization into one helper **within `loongarch64rt`**, with host-specific field extraction and named, asserted guest fields.

8. **loongarch64rt-R6-8 — YAGNI — LOW**  
   **Location:** `src/os/syscalls_mem.c:263–266`  
   **The O_WRONLY rejection is unreachable.** The preceding condition returns for every access mode other than O_RDWR, necessarily including O_WRONLY. The second check adds no protection and obscures which validation is authoritative.  
   **Fix:** Remove the redundant O_WRONLY branch.

No separate CLEAN finding is asserted merely because files approach 900 lines. This bounded inspection does not establish that the remaining code is defect-free.