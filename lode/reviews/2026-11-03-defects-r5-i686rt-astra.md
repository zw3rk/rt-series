Static inspection found **11 actionable findings**. Eight shell commands were used; no Markdown files, builds, tests, Docker, or QEMU were run. These are source-derived findings, not reproduced failures. Inspection covered selected interpreter, DBT, VM, syscall, ELF/rt32, and test paths; it does not establish whole-repository correctness.

1. **[I686-R5-1] BUG — SSE directed rounding can move an already-correct result by another ULP.**

   **Evidence:** [src/interp/h_sse.c:82](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:82), especially lines 94–117.

   **Root cause:** After converting double to float, the helper adjusts every inexact normal result solely according to rounding mode and sign. It never checks which side of the exact value the initial conversion landed on.

   **Concrete consequence:** Under round-up, `ADDSS(1.0f, 3 × 2^-25)` should produce `0x3f800001`. With host round-to-nearest, the initial cast already produces that value, but the helper increments it to `0x3f800002`.

   **Fix:** Adjust only when the initial result lies on the wrong side of the exact value. Also preserve arithmetic residuals: the double intermediate at lines 185–192 can itself discard information needed for directed rounding. Add bit-exact cases for all rounding modes.

2. **[I686-R5-2] BUG — LDMXCSR accepts reserved bits, and a test requires that incorrect behavior.**

   **Evidence:** [src/interp/h_sse_int.c:642](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:642), [tests/unit/test_l5b_cases.c:363](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l5b_cases.c:363). The DBT also documents masking at [src/dbt/emit_sse2.c:388](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:388).

   **Root cause:** The interpreter commits the masked value and sets MXCSR.IE instead of generating the required general-protection fault. The test explicitly expects successful execution with bit 16 set.

   **Fix:** Validate reserved bits before changing MXCSR or advancing EIP. Deliver the guest fault with prior state intact. Apply the same validation to DBT execution and replace the test’s success expectation with fault-and-state-preservation assertions.

3. **[I686-R5-3] BUG — LOCK-prefixed shifts execute instead of faulting.**

   **Evidence:** [src/interp/h_shift.c:203](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_shift.c:203), [src/x86/decode.c:636](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:636), [src/interp/interp.c:399](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:399).

   **Root cause:** There is no common LOCK legality check before handler dispatch. Shift handlers deliberately implement locked atomic updates; zero-count shifts return success even earlier.

   **Concrete consequence:** `F0 D1 20`—LOCK SHL through `[EAX]`—modifies memory instead of raising #UD.

   **Fix:** Validate LOCK against an opcode-and-memory-destination allowlist before either engine executes the instruction. Remove the unreachable shift/rotate atomic machinery after enforcing legality. Cover both zero and nonzero counts.

4. **[I686-R5-4] BUG / DEFECT — Socket message marshalling bypasses fault-safe guest copies.**

   **Evidence:** [src/os/sys_sock_msg.c:137](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:137), lines 199–213 and 315–317; compare [src/os/marshal.c:43](/Users/angerman/Projects/zw3rk/i686rt/src/os/marshal.c:43).

   **Root cause:** Iovec descriptors and ancillary data are dereferenced directly after address-range checks. Those checks do not establish accessibility. Payload pointers are also passed directly to host `sendmsg`/`recvmsg`.

   **Consequences:** An inaccessible descriptor or control buffer can escape to the outer execution fault checkpoint, skipping local cleanup. On A2, a valid guest payload sharing a restricted host page can instead receive host `EFAULT`, because kernel copies cannot invoke the runtime’s user-space healing path.

   **Fix:** Snapshot descriptors and control data through checked copies. Stage payloads through host buffers where A2 requires it, with explicit cleanup and descriptor ownership on every failure.

5. **[I686-R5-5] BUG — Ancillary truncation discards SCM_RIGHTS descriptors that fit.**

   **Evidence:** [src/os/sys_sock_msg.c:79](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:79).

   **Root cause:** Conversion requires an entire control message to fit. Otherwise it drops the entire payload and closes every received descriptor.

   **Concrete consequence:** A two-descriptor SCM_RIGHTS message with guest control capacity of 16 bytes has room for the 12-byte header and one descriptor. The implementation delivers neither descriptor.

   **Fix:** Emit the prefix that fits, retain complete descriptor-sized units, set `MSG_CTRUNC`, and close only undelivered descriptors. Add a partial-rights test; existing tests cover whole-message fit/drop cases.

6. **[I686-R5-6] BUG — Multi-message syscalls count entries whose `msg_len` copyout failed.**

   **Evidence:** [src/os/sys_sock_msg.c:362](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:362) and [src/os/sys_sock_msg.c:468](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:468).

   **Root cause:** Both `sendmmsg` and `recvmmsg` discard `i686_copy_to_guest`’s return value and increment the completed count.

   **Concrete consequence:** Place the 28-byte message header at the end of a writable page and `msg_len` on an inaccessible next page. The syscall reports a completed entry without publishing its length.

   **Fix:** Stop on failed length copyout. Return `-EFAULT` if no previous entry completed, otherwise return the previous completed count. Preserve the distinction between an irreversible send/receive side effect and a successfully reported entry.

7. **[I686-R5-7] BUG — `recvmmsg` timeout emulation changes shared socket state.**

   **Evidence:** [src/os/sys_sock_msg.c:417](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:417), lines 449–461.

   **Root cause:** A per-call deadline is implemented by temporarily replacing `SO_RCVTIMEO`. That option belongs to the socket and is shared across threads and duplicated descriptors.

   **Consequences:** Concurrent receives observe another call’s timeout. Concurrent option changes can be overwritten by restoration of the saved value. Failures from both `setsockopt` calls are ignored.

   **Fix:** Implement the deadline without changing socket options—for example, deadline-aware readiness waits followed by nonblocking receives, with signal and `MSG_WAITFORONE` handling.

8. **[I686-R5-8] DEFECT — Failed `munmap` can leave a live mapping without backing-file tracking.**

   **Evidence:** [src/rt32/rt32_vm_mmap.c:270](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm_mmap.c:270).

   **Root cause:** `i686_vm_file_untrack_map` commits removal before `rt32_vm_reserve_prot_none` performs the fallible host operation. If reservation fails, the function returns without restoring tracking.

   **Consequence:** Guest region metadata and the surviving host mapping can remain while backing-file records and owned descriptors have been removed. Later file-refresh or truncation handling no longer sees that mapping.

   **Fix:** Prepare tracking changes without committing them, perform the host operation, then commit metadata removal. Alternatively retain sufficient state for rollback. Validate with an injected reservation failure.

9. **[I686-R5-9] DEFECT / CLEAN — Guest-controlled time64 values cause signed-overflow undefined behavior.**

   **Evidence:** [src/os/sys_sock_msg.c:390](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:390) and line 410.

   **Root cause:** High words are shifted left as signed `int64_t`; values setting bit 63 exceed the signed range. Separately, adding a large positive timeout to monotonic time can overflow `time_t`, as can the nanosecond carry.

   **Fix:** Assemble raw words using `uint64_t`, then decode their signed representation safely. Validate negative values and use checked deadline addition. Add boundary cases for negative encodings and `INT64_MAX`.

10. **[I686-R5-10] DRY — Darwin readiness waiting is duplicated within this repository.**

    **Evidence:** [src/os/backend_darwin_io.c:47](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_io.c:47), [src/os/backend_darwin_net.c:86](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:86).

    **Root cause:** Both translation units contain the same lease check, wake-pipe polling, timeout handling, and readiness interpretation.

    **Fix:** Keep one private Darwin backend helper inside i686rt. This makes signal, timeout, and invalid-descriptor corrections apply consistently. No cross-repository library extraction is warranted.

11. **[I686-R5-11] YAGNI / CLEAN — Socket backend APIs have no callers while guest syscalls bypass them.**

    **Evidence:** [src/os/backend.h:152](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend.h:152), [src/os/backend_linux_sys.c:293](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_linux_sys.c:293), [src/os/backend_darwin_net.c:118](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:118), versus [src/os/sys_sock.c:123](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock.c:123).

    **Root cause:** Searches found declarations and implementations, but no callers for the inspected `rt_host_socket/socketpair/bind/connect/accept4/sendto/recvfrom` APIs. Actual syscall handlers call libc directly.

    **Consequence:** Two networking paths are maintained, but backend lease handling and platform adaptations do not govern guest socket execution.

    **Fix:** Establish one active path: wire guest handlers through the backend with proper ABI conversion, or remove unused implementations where no current contract requires them. Correct comments claiming Darwin is never a runtime host.

**Cross-runtime propagation notes**

Sibling repositories were not inspected; these are targeted follow-up checks, not confirmed sibling defects.

| Findings | Sibling checks |
|---|---|
| R5-1–3 | Check x86 execution paths in **hyper-linux**, if independently implemented. These opcode semantics do not directly transfer to ARM guest execution in **a32rt**. |
| R5-4–7, R5-9 | Check **a32rt** compat socket marshalling and **hyper-linux** syscall adapters for direct guest pointers, ancillary truncation, ignored copyouts, shared timeout mutation, and signed time assembly. |
| R5-8 | Prioritize **a32rt** VM/file-tracking transaction order; inspect corresponding **hyper-linux** mapping bookkeeping. |
| R5-10–11 | Check both siblings for duplicated Darwin wait helpers and backend APIs bypassed by active syscall paths. Keep remedies repository-local. |

No inspected source file exceeded 900 lines; the largest was `src/os/sys_stat.c` at 898. No additional ELF-loader finding met the confidence threshold within this inspection budget.