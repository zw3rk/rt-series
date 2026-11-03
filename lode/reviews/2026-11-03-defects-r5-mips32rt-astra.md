**Round 5 found 11 actionable issues.** Used exactly eight shell commands for static inspection. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings below are code-based; suggested reproductions remain unexecuted.

1. **[M32-R5-1] BUG — DBT bypasses guest subpage permissions on A2 hosts. High.**

   **Evidence:** [a64_emit.c:419](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/a64_emit.c:419), [trampoline_a64.S:52](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/trampoline_a64.S:52), [dbt.c:772](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:772).

   Generated loads/stores always access `[G, wAddr, uxtw]`; the trampoline always installs `guest_base`, and DBT dispatch does not gate execution on `vm_regime`. The A2 permission validator is used by interpreter accessors, not these generated accesses.

   On Darwin, a writable 4 KiB guest page can therefore make an adjacent read-only or `PROT_NONE` guest page accessible through their shared 16 KiB host page. Existing permission probes at [test_p6_perms.c:300](/Users/angerman/Projects/zw3rk/mips32rt/tests/test_p6_perms.c:300) cover a relevant layout.

   **Fix:** Route A2 memory operations through validated helpers or interpreter fallback until generated accesses enforce guest-page permissions.

2. **[M32-R5-2] BUG — Big-endian futex comparisons use little-endian host values. High.**

   **Evidence:** [threads.c:506](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:506), [threads.c:527](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:527), [threads.c:564](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:564).

   The preliminary load decodes guest endianness, but `FUTEX_WAIT` and `WAIT_BITSET` then pass the unswapped numeric `val` to the host kernel. For a BE word containing `1`, the little-endian host observes `0x01000000`, so the kernel rejects a valid wait with `EAGAIN`. `CMP_REQUEUE` has the same comparison problem. Native `WAKE_OP` arithmetic also operates on the wrong representation.

   **Fix:** Convert comparison operands to host memory representation. Implement an endian-aware atomic path for BE `WAKE_OP`, or explicitly reject unsupported operations. Add raw BE futex tests using nonzero, non-byte-symmetric values.

3. **[M32-R5-3] BUG — Futex requeue and wake-op discard argument four. High.**

   **Evidence:** [threads.c:481](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:481), [threads.c:563](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:563), [threads.c:578](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:578).

   Argument four is decoded into `to_va`, but both requeue operations and `WAKE_OP` pass `NULL` in its place. For these operations, that argument is a count, not a timeout pointer. Consequently, requeue moves zero waiters and wake-op cannot perform the requested second-address wake count.

   **Fix:** Forward the operation-specific integer count. Add tests that require moving waiters between addresses and waking waiters on both addresses.

4. **[M32-R5-4] DEFECT — Successful guest threads permanently retain host resources. High.**

   **Evidence:** [threads.c:320](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:320), [threads.c:328](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:328), [threads.c:207](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:207), [threads.c:403](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:403).

   Each successful clone allocates a record and a 2 MiB host stack. Cleanup exists only on creation failure. Successful threads exit through raw `SYS_exit`, bypassing pthread teardown, and no implemented reaper owns the retained record or stack. Detached status does not reclaim a caller-provided stack.

   **Fix:** Establish explicit completion ownership: terminate through pthread machinery and reclaim caller-owned stacks only after host-thread termination, using a reaper or equivalent lifecycle. Include repeated create/join coverage.

5. **[M32-R5-5] BUG — Robust-list registration succeeds without owner-death processing. High.**

   **Evidence:** [syscalls_meta.c:813](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls_meta.c:813), [threads.c:207](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:207).

   `set_robust_list` records the guest head and returns success. Thread teardown only clears `clear_child_tid`; it never traverses the guest robust list, marks abandoned futexes `OWNER_DIED`, or wakes their waiters. The host kernel cannot process this guest O32 list through the host pthread’s independent robust-list registration.

   **Fix:** Implement bounded, fault-tolerant O32 robust-list teardown, including the pending-operation entry and BE conversion. Until supported, do not report successful registration. Test a thread exiting while holding a robust mutex.

6. **[M32-R5-6] BUG — Round 4 read/readv epoch updates still permit invalid SC success. High.**

   **Evidence:** [syscall_min.c:150](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:150), [syscalls.c:677](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:677), [mem.c:800](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:800).

   Host I/O writes directly into guest memory before acquiring LL/SC exclusion and advancing epochs. Another thread can perform LL, observe a same-value I/O store, and complete SC before the delayed epoch update. Both the epoch check and value comparison then pass despite an intervening write.

   **Fix:** Read into host staging storage, then validate and commit transferred bytes under the established VM/LL locking order. Preserve partial-transfer and iovec ordering semantics; do not hold the LL lock across blocking I/O.

7. **[M32-R5-7] DEFECT — Darwin file synchronization still suppresses errors and destroys mapping contents. High.**

   **Evidence:** [vm_mmap.c:665](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:665), [vm_mmap.c:699](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:699), [vm_file.c:78](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:78).

   `rt32_vm_flush_shared_fd()` discards writeback failures. Write and truncate callers continue, then synchronization zeroes each entire shadow mapping and issues one unchecked `pread`. A failed preflush can lose dirty mapped bytes during refresh; an interrupted, failed, or short refresh can replace valid contents with zeros. Round 4 error propagation therefore does not cover these fd-based paths.

   **Fix:** Return and propagate flush errors. Populate temporary storage using checked, EINTR-aware reads, zero only the verified EOF remainder, and commit only after successful population.

8. **[M32-R5-8] BUG — Reserved FP conversion encodings consume an uninitialized result. Medium.**

   **Evidence:** [fp.c:711](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:711), [fp.c:750](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:750), [fp.c:770](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:770).

   `v` is uninitialized. Function 32 with S format and function 33 with D format execute `break`, reaching the shared result-write tail without assigning `v`. These reserved same-format conversions consequently invoke undefined C behavior and mutate guest state instead of taking the reserved-instruction path.

   **Fix:** Reject both combinations before result writeback. Add raw-instruction tests checking the trap and unchanged destination/FCSR state.

9. **[M32-R5-9] DEFECT — Differential testing can certify two failed launches. High for validation.**

   **Evidence:** [run_difftest.sh:71](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:71), [run_difftest.sh:84](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:84), [run_difftest.sh:115](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:115).

   The harness accepts equal exit statuses and permits empty trace/register files. If both launches fail before guest execution—for example, `setarch -R` is installed but denied—both empty outputs compare equal and produce `DIFFTEST: 0 divergences`. Matching timeouts can likewise pass when captured evidence matches.

   **Fix:** Reject infrastructure failures and timeouts, require evidence of guest execution and complete expected state records, and explicitly configure expected guest termination where nonzero exits are intentional.

10. **[M32-R5-10] YAGNI / CLEAN — Thread lifecycle bookkeeping has no consumer. Low.**

    **Evidence:** [threads.c:122](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:122), [threads.c:153](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:153), [threads.c:439](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:439).

    `host_stack` is assigned but never read. `mips_live_clones` is modified but never used to make a decision. Comments promise a reaper that is absent. Moreover, the counter increments after the child can already exit, and a parent-TID write failure skips that increment entirely.

    **Fix:** Integrate these fields into the real lifecycle repair in M32-R5-4, with publication and rollback ordering, or remove unused bookkeeping and obsolete claims.

11. **[M32-R5-11] DRY — Truncate variants duplicate O32 length decoding. Low.**

    **Evidence:** [vm_file.c:109](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:109), [vm_file.c:151](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:151).

    Path-based and fd-based truncate independently implement the same signed 32-bit validation, padded 64-bit argument extraction, and BE/LE assembly. This creates two maintenance points for one ABI rule.

    **Fix:** Extract a file-local length decoder returning a validated length or error; retain separate path/fd handling. This is strictly intra-repository consolidation.

**Cross-runtime propagation checks**

Sibling sources were not inspected; these are targeted checks, not confirmed sibling findings.

| Findings | Siblings/patterns to check |
|---|---|
| R5-1, R5-7 | `a32rt`, `i686rt`: copied Class-A substrate, Darwin subpage protection and shadow-file synchronization |
| R5-2, R5-3 | Any sibling with futex forwarding; endian handling especially in BE-capable runtimes |
| R5-4, R5-5, R5-10 | Siblings implementing guest clone through host pthreads and emulated robust lists |
| R5-6 | `a32rt` and other LL/SC runtimes using post-I/O reservation invalidation |
| R5-8 | Other MIPS runtimes sharing COP1 decoding or conversion logic |
| R5-9 | All siblings using this differential-harness pattern |
| R5-11 | No automatic propagation needed; local maintenance issue |

**CLEAN coverage:** The source line-count inspection found no `.c`, `.h`, or `.S` file above 900 lines; the largest inspected source was `src/dbt/emit_int.c` at 899. The FP uninitialized read and misleading lifecycle comments are concrete hygiene findings above. ELF loading was inspected, but this bounded review established no additional ELF finding.