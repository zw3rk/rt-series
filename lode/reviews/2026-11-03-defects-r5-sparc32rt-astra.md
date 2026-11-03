**Round 5 found 12 actionable issues.** These are static findings, not runtime reproductions. I used eight shell commands; read no Markdown; ran no builds, tests, Docker, or QEMU; and changed no files. Inspection covered selected interpreter, DBT, VM, syscall, ELF, and test paths. This checkout has no `src/rt32/family/` directory; related bookkeeping resides in `src/vm/vm_file.c`.

1. **[S32-R5-1] BUG — FP doubleword alignment differs between engines.**  
   **Evidence:** [interp/fp.c:230](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:230), [dbt/emit_fpmem.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fpmem.c:83).  
   The interpreter executes `LDDF`/`STDF` as two four-byte accesses, accepting an address congruent to four modulo eight. The DBT explicitly faults that address. Additionally, [interp_signal.c:643](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:643) excludes FP doublewords from alignment-fault classification, so the DBT fault becomes SIGSEGV.  
   **Fix:** Make alignment checks and fault classification consistent across both engines. Add mapped `base+4` load/store cases alongside the existing [FP round-trip test:311](/Users/angerman/Projects/zw3rk/sparc32rt/tests/test_p3_fp_simd.c:311).

2. **[S32-R5-2] BUG — Byte and halfword mapping faults can become SIGBUS.**  
   **Evidence:** [interp_signal.c:654](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:654), [interp_mem.c:74](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:74).  
   Classification immediately returns SIGBUS whenever `fault_addr & 3` is nonzero. An unmapped byte load at `page+1`, or an aligned halfword load at `page+2`, therefore gets classified as an alignment fault despite satisfying its instruction’s alignment requirement.  
   **Fix:** Record the fault cause at the access site, or determine the instruction’s required alignment before classifying it.

3. **[S32-R5-3] DEFECT — Fault classification bypasses VM reader protection.**  
   **Evidence:** [interp_signal.c:621](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:621), [main.c:259](/Users/angerman/Projects/zw3rk/sparc32rt/src/main.c:259).  
   `sparc32_fault_insn_word()` checks permissions and directly dereferences guest memory without `sparc32_vm_access_enter()`. A sibling can unmap or revoke access between those operations, causing a host fault while the runtime is classifying a guest fault. Ordinary accessors already protect this interval.  
   **Fix:** Hold the VM reader guard across validation and instruction copying, preserving the original guest fault state.

4. **[S32-R5-4] BUG — Signal queues still consume each other’s pending bits.**  
   **Evidence:** [threads_sig.c:107](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:107), [threads_sig.c:123](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:123), [interp_signal.c:418](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:418).  
   `rt_sigsuspend` consumes a process bit while delivering a thread bit. Its process loop also claims and discards a process signal if any thread has that number pending. Separately, the common async commit always clears the current thread’s bit—even when invoked for a process delivery—so a thread signal arriving during frame construction can disappear.  
   **Fix:** Carry queue ownership through selection and delivery; consume only the selected queue. Remove the remaining cross-queue deduplication. Extend the [single-signal suspend test:125](/Users/angerman/Projects/zw3rk/sparc32rt/tests/test_p4_async.c:125) with simultaneous process/thread pending cases.

5. **[S32-R5-5] BUG — `rt_sigsuspend` discards queued default-fatal signals.**  
   **Evidence:** [threads_sig.c:100](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:100), [threads_sig.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:126).  
   Both loops treat “no installed handler” as permission to discard the signal. Round 4 explicitly queues default-disposition signals while blocked at [threads_kill.c:197](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_kill.c:197). If `sigsuspend` unmasks one, it can consume the pending fatal signal and sleep instead of applying its default action.  
   **Fix:** Share disposition handling with normal polling, distinguishing ignored, caught, and default-action signals.

6. **[S32-R5-6] DEFECT — Concurrent disposition changes expose uninitialized handler addresses.**  
   **Evidence:** [interp_signal.c:296](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:296), [interp_signal.c:410](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:410), [syscalls_sig.c:162](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_sig.c:162).  
   Frame construction snapshots one action, then commit fetches it again. If another thread changes the disposition to DFL or IGN between those calls, `sparc32_signal_get_action()` fails without initializing `handler` or `restorer`. Commit ignores that failure and uses both locals. The syscall-delivery path repeats this pattern.  
   **Fix:** Pass one validated action snapshot through construction and commit, with an explicit policy for disposition changes.

7. **[S32-R5-7] BUG — Suspend delivery corrupts `SA_SIGINFO` fields.**  
   **Evidence:** [interp_signal.c:365](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:365), [interp_signal.c:471](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:471).  
   Normal async construction writes legacy PC/NPC mirrors only without `SA_SIGINFO`, because offsets 100 and 104 overlap `si_errno` and `si_code`. `interp_deliver_async_for_syscall()` overwrites those offsets unconditionally. An `SA_SIGINFO` handler entered through `sigsuspend` receives instruction addresses as signal metadata.  
   **Fix:** Apply the same flag guard using the action snapshot; update the real saved PC/NPC independently.

8. **[S32-R5-8] DEFECT — New file mappings start with the wrong tracked size.**  
   **Evidence:** [vm_mmap.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:83), [vm_file.c:109](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:109), [vm_file.c:232](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:232).  
   Mapping registration publishes the file’s size **before** interning the new mapping. The new entry subsequently initializes `file_size` to zero. Its first truncation therefore compares the new size against zero and skips shrink handling.  
   **Fix:** Initialize the mapping entry with the `fstat` size during registration. Test the first shrink immediately after mapping, without an intervening write or second mmap.

9. **[S32-R5-9] DEFECT — File-mapping records outlive their mappings.**  
   **Evidence:** [vm_file.c:90](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:90), [vm_file.c:202](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:202), [vm_mmap.c:357](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:357).  
   Entries become permanently live; unmap and exec reset do not retire them. After file A is unmapped and file B occupies its address, shrinking A can clear B’s dirty-page state through the stale range. Moved private mappings copy only pages marked dirty, making this capable of losing B’s private modifications. After 128 distinct records, registration also silently stops.  
   **Fix:** Implement range retirement/splitting for unmap, replacement, remap, and exec. Recycle entries and report registration failure rather than silently dropping tracking.

10. **[S32-R5-10] DEFECT — Futex emulation exhausts slots permanently.**  
    **Evidence:** [futex.c:61](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:61), [futex.c:147](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:147), [futex.c:160](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:160).  
    The emulation table has 64 slots. Allocation sets `in_use`, but completion only decrements `waiters`; nothing releases a slot. After waits on 64 distinct addresses, waits on new addresses return EAGAIN even when the value matches and all earlier waiters have finished.  
    **Fix:** Recycle zero-waiter slots under `futex_emu_lock`, preserving safe condition-variable lifetime. Add a sequential test over more than 64 addresses.

11. **[S32-R5-11] DRY — Difftest duplicates production fault classification.**  
    **Evidence:** [difftest.c:159](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/difftest.c:159), [interp_signal.c:617](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:617), [difftest.c:433](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/difftest.c:433).  
    Difftest contains another instruction fetch and classifier, including the same erroneous address heuristic. It then delivers that single classification to both contexts. This adds maintenance drift without providing an independent signal oracle.  
    **Fix:** Reuse the repository’s production classifier and validate expected signal numbers in focused guest tests.

12. **[S32-R5-12] YAGNI / CLEAN — Unused file-state machinery overstates implemented behavior.**  
    **Evidence:** [vm_file.c:48](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:48), [vm_file.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:126), [vm_file.c:248](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:248).  
    Repository searches found no callers for `vm_file_promote_cow`, `vm_file_apply_shrink`, `vm_file_generation`, or `vm_file_shared_direct_ok`. The descriptor type supports only these unused helpers; `resize_seq` and `min_shrunk` have no readers. Meanwhile, the opening comment describes family-shared storage surviving fork, but `g_inodes` is an ordinary static array.  
    **Fix:** Remove unused alternate machinery or connect it to a concrete required path. Correct the comments to distinguish implemented behavior from intended behavior.

**Cross-runtime propagation**

| Findings | Sibling checks |
|---|---|
| 1–2 | Any SPARC sibling: FP alignment, access-width-aware fault causes. |
| 3–7 | `a32rt`, `i686rt`, and siblings with copied signal/VM helpers: reader guards, queue ownership, disposition snapshots, suspend-frame updates. |
| 8–9, 12 | `a32rt`, `i686rt`, and runtimes carrying Provider-A file tracking: registration order, mapping lifetime, generation consumers, actual fork sharing. |
| 10 | Darwin-capable siblings using the same condition-variable futex table. |
| 11 | Siblings with duplicated difftest fault-delivery logic. |

These are propagation candidates; sibling repositories were not inspected. No inspected `.c`, `.h`, or `.S` file exceeded 900 lines—the largest was `src/rt32/vm.c` at 883. No additional concrete ELF-loader finding was established within this inspection budget.