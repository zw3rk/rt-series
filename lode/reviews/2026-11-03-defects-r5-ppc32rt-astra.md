Found **11 issues**, including incomplete Round 4 copyout/coherence fixes. Used **eight shell commands**; no Markdown files, builds, tests, Docker, or QEMU. Findings are static conclusions, not runtime reproductions.

1. **[P32-R5-1] BUG — `clone(CLONE_VM)` blocks the parent until the child exits.**  
   **Evidence:** [syscalls.c:760](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:760), [syscalls.c:771](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:771).  
   The dispatcher creates the child without a runner, then executes it synchronously before returning the child TID. A child waiting for the parent to release a mutex or publish a flag deadlocks inside `clone`. The existing [thread counter test:613](/Users/angerman/Projects/zw3rk/ppc32rt/tests/test_p4_threads_signals.c:613) permits sequential completion and cannot detect this.  
   **Fix:** Schedule parent and child independently, including yielding on blocking operations. Add a parent/child handshake regression.

2. **[P32-R5-2] BUG — FP memory faults commit register and PC changes.**  
   **Evidence:** [fp.c:75](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:75), [fp.c:95](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:95), [interp.h:286](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:286), [emit_fp.c:260](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:260).  
   `ld32` returns zero after recording a permission fault. `fp_memop` nevertheless writes the destination FPR and advances `nip`. Update forms also overwrite RA before attempting the access; the DBT explicitly duplicates that ordering. A fault handler therefore sees partially committed instruction state, and retry can use the wrong address.  
   **Fix:** Propagate access failure explicitly. Commit FPR, RA, and `nip` only after successful access; test protected-page faults for D-form and indexed update instructions.

3. **[P32-R5-3] BUG/DEFECT — Raw syscall copyouts bypass Round 4 permission checks.**  
   **Evidence:** [syscalls_dyn.c:414](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_dyn.c:414), [syscalls_dyn.c:426](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_dyn.c:426), [syscalls.c:395](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:395).  
   `getcwd` uses raw `memcpy`; `getrandom` passes the guest pointer directly to the host. Both check address range but omit guest write permissions and landed-store bookkeeping. On A2, a writable neighboring subpage can allow writes into a guest read-only page. `getcwd` can also fault in host code instead of returning `EFAULT`.  
   **Fix:** Route output through checked copyout and common SMC, reservation, and shared-file coherence handling. Test read-only subpages sharing a writable host page.

4. **[P32-R5-4] BUG — `readv` rereads descriptors that its own output can overwrite.**  
   **Evidence:** [syscalls.c:213](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:213), [syscalls.c:239](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:239).  
   Host iovecs are captured before `readv`, but invalidation rereads `base` and `len` from guest memory afterward. A valid destination overlapping the guest iovec array changes those descriptors. Bookkeeping then targets incorrect ranges, leaving the actual destination without reservation, code-cache, or staged-alias updates. Later chunks can also consume overwritten descriptors.  
   **Fix:** Snapshot the complete descriptor array before I/O and retain its guest addresses for all post-I/O processing.

5. **[P32-R5-5] BUG — Chunking vectored I/O changes syscall semantics.**  
   **Evidence:** [syscalls.c:204](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:204), [syscalls.c:230](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:230).  
   More than 16 vectors produce multiple host syscalls. A 17-vector datagram `writev` becomes two datagrams. A small pipe write loses whole-request atomicity, and a read can block again after an earlier chunk completed. Correct partial-byte accounting does not repair these semantic changes.  
   **Fix:** Allocate a bounded host array for the accepted vector count and issue one host `readv`/`writev`.

6. **[P32-R5-6] BUG — Reading into staged `MAP_SHARED` memory does not update its backing file.**  
   **Evidence:** [syscalls.c:113](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:113), [vm_file_stage.c:633](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:633), [vm_file_stage.c:507](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:507).  
   `sys_read_landed` selects `cohere_read`, which passes `write_file=false`. Reading pipe bytes into a writable shared mapping changes destination memory just like any other store, but this path updates only staging objects. The backing file and direct file mappings retain old bytes.  
   **Fix:** Treat successful syscall output as a store to the destination mapping, including backing-file propagation. Keep refresh-from-file operations separate.

7. **[P32-R5-7] BUG — Staged write-through can select a read-only descriptor.**  
   **Evidence:** [vm_file_stage.c:303](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:303), [vm_file_stage.c:510](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:510), [vm_file_stage.c:531](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:531).  
   Groups retain a duplicate of their original descriptor. Write-through chooses the first same-inode group without checking access mode. If a read-only mapping was created first, a later writable mapping can send its writeback through that read-only descriptor. `pwrite` fails, and the failure is silently discarded.  
   **Fix:** Retain or select a writable descriptor from an authorized writable mapping. Handle writeback failure explicitly. Add mixed `O_RDONLY`/`O_RDWR` alias coverage.

8. **[P32-R5-8] BUG — Self-directed signals ignore the blocked mask.**  
   **Evidence:** [signals.c:720](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:720), [signals.c:451](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:451), [signals.c:616](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:616).  
   `kill` immediately enters an installed handler through `ppc32_sig_deliver_sync`, without testing `ctx->sig_mask` or queuing a pending signal. Blocking `SIGUSR1` and sending it to self therefore runs the handler immediately instead of making it pending.  
   **Fix:** Separate asynchronous signal enqueueing from synchronous fault delivery. Deliver queued signals at eligible execution boundaries after unmasking.

9. **[P32-R5-9] DEFECT — Callback thread exit races handle publication and destroys joinability.**  
   **Evidence:** [threads.c:582](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:582), [threads.c:615](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:615), [threads.c:654](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:654).  
   In the callback-backed pthread path, the child can exit before the parent records its handle. Exit clears the slot and frees the context; subsequent join returns `ESRCH`, and the joinable pthread resources remain unreaped. The embedded test also dereferences that potentially freed context at [threads.c:790](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:790). This is distinct from the currently synchronous syscall path.  
   **Fix:** Publish the handle before releasing a child startup barrier; retain completed-thread records until reaping. Give returned contexts explicit ownership.

10. **[P32-R5-10] DRY/YAGNI/CLEAN — The unused minimal syscall implementation duplicates obsolete behavior.**  
    **Evidence:** [syscalls_min.c:50](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_min.c:50), [syscalls_min.c:161](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_min.c:161), [main.c:481](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:481).  
    Repository reference searches found declarations and definitions but no callers of `ppc32_syscall_min`. It duplicates dispatch, return conversion, and memory handling while retaining a different low-address guard (`0x1000`) and unchecked direct buffers. This is an existing source of implementation drift.  
    **Fix:** Remove the unused implementation/header, or make any required compatibility entry points delegate to the maintained dispatcher. Keep consolidation within this repository.

11. **[P32-R5-11] YAGNI — `sig_installed` is write-only state.**  
    **Evidence:** [signals.c:48](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:48), [signals.c:115](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:115), [signals.c:141](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:141), [signals.c:162](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:162).  
    All references initialize or assign the array; none reads it. It adds a second apparent disposition state without influencing behavior.  
    **Fix:** Remove the array and its assignments.

**Cross-runtime propagation notes**

| Patterns | Sibling runtimes to inspect |
|---|---|
| Copyout permissions, vectored I/O, staged-file coherence | `a32rt`, `i686rt`, especially copied Class-A VM and syscall code |
| Clone scheduling, pthread lifecycle, blocked-signal delivery | `a32rt`, `i686rt` wherever equivalent guest-thread/signal layers exist |
| FP fault commit ordering | Sibling interpreter/JIT memory handlers, translated to each ISA’s precise exception rules |
| Legacy dispatchers and write-only state | Sibling repositories containing copied phase-era implementations |

These are propagation targets, **not confirmed sibling findings**; sibling source was not inspected.

**CLEAN check:** Static line counts found no `.c`, `.h`, or `.S` file above 900 lines under `src`, `include`, or `tests`; the largest was `src/os/threads.c` at 884. ELF loading was inspected, but no additional ELF finding met the evidence threshold within this budget.