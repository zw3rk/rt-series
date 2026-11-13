Found **seven concrete remaining defects** at `540bf78`. Used exactly seven shell commands; no Markdown reads, builds, tests, Docker, or QEMU. Findings are static-analysis conclusions. Novelty was checked against remediation history and source diffs; excluding the earlier audit documents limits certainty that none was previously reported.

1. **ppc32rt-R6-1 — BUG — HIGH**  
   **Location:** `src/dbt/cache.c:383–391,483–523`; `src/dbt/dbt.c:629–638`  
   Concurrent guest threads share the translation cache, but eviction immediately unmaps code and frees its block. One thread can execute a block while another evicts it through a cache collision or invalidation. Invalidation also clears only the calling context’s IBTC/RAS pointers, leaving peer pointers dangling.  
   **Fix:** Synchronize cache mutation and protect executing blocks with deferred reclamation. Invalidate cached references across all participating contexts. A mutation lock alone does not protect ongoing JIT execution.

2. **ppc32rt-R6-2 — BUG — HIGH**  
   **Location:** `src/os/syscalls_dyn.c:197–201,220–255`  
   `dyn_getdents64()` uses one process-wide mutable `static` buffer. Concurrent directory reads overwrite that buffer while another thread parses it, mixing names, inode numbers, offsets, and record lengths between calls.  
   **Fix:** Allocate the fixed-size staging buffer per invocation or per thread.

3. **ppc32rt-R6-3 — DEFECT — HIGH**  
   **Location:** `src/main.c:441–446,472–479,519–524`  
   Guest `exit` and `exit_group` have the same termination path. A worker’s `exit_group` merely returns from that worker, leaving peers running. Conversely, the initial guest thread’s ordinary `exit` returns through `main`, terminating the host process and all remaining guest threads.  
   **Fix:** Implement distinct thread-exit and group-exit paths. Keep the process alive after initial-thread exit while guest peers remain; group exit must stop all peers and preserve the group status.

4. **ppc32rt-R6-4 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:391,533–536`  
   Clone copies the parent’s CR and sets the child’s `r3` to zero without clearing `CR0.SO`. If SO was set before `sc`, the child sees a successful clone return marked as an error. The parent receives normal return normalization; the child bypasses it.  
   **Fix:** Clear `PPC32_CR0_SO` when constructing the child’s successful syscall-return state.

5. **ppc32rt-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:254–268,465`; `src/os/signals.c:831–833`  
   `set_tid_address()` returns the native host TID, whereas `gettid()` returns the allocated guest TID. These can differ for cloned threads, exposing two identities for the same guest thread.  
   **Fix:** Return `ctx->guest_tid` from `set_tid_address()` and retain `host_tid` solely for host operations.

6. **ppc32rt-R6-6 — DEFECT — MEDIUM**  
   **Location:** `src/os/signals.c:842–864`  
   `tkill` and `tgkill` reject every target except the calling thread. With concurrent clones now enabled, targeting a live sibling—including an existence probe with signal zero—incorrectly returns `ESRCH`. This breaks inter-thread signaling and cancellation mechanisms.  
   **Fix:** Resolve guest TIDs through the synchronized thread registry, validate group membership, and queue delivery to the target with a mechanism to interrupt blocked execution.

7. **ppc32rt-R6-7 — DEFECT — HIGH**  
   **Location:** `src/os/syscalls_dyn.c:207–209,245–255`  
   `getdents64()` validates only numerical address bounds, then writes directly through unchecked scalar stores and `memcpy`. An unmapped destination can fault in the translator instead of returning `EFAULT`; on a shared host page, a guest read-only subpage can be overwritten. These writes also bypass the safe-copy path’s reservation invalidation and staged-file coherence.  
   **Fix:** Convert records in the invocation-local buffer, then use permission-checked `ppc32_vm_copyout_safe()` with explicit error/partial-result handling and appropriate code-cache invalidation.