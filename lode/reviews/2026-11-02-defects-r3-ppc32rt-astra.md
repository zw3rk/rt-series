Found **7 actionable defects** at `2c2a62e`, including two in the recent fixes. Review used **5 shell inspection turns**. No builds, tests, Docker, or QEMU ran; findings below are based on static code paths.

**P32-R3-1 — Division overflow checks read an overwritten divisor**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/interp/interp.c:380](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:380)
- **Evidence & Root Cause:** The Round-2 change writes `ctx->gpr[insn.rt]` before testing `ctx->gpr[insn.rb] == 0U`. When `RT == RB`, the test examines the quotient. For example, `divwo. r5,r4,r5` with `r4=1`, `r5=2` produces zero and incorrectly sets `XER.OV`, sticky `XER.SO`, and `CR0.SO`. The DBT retains the original divisor in `EI_B`, so the engines diverge. Existing regression cases use distinct destination and divisor registers.
- **Concrete Fix:** Test the saved divisor (`sb == 0`) or calculate overflow before writing the destination. Add signed and unsigned cases with `RT == RB`, a nonzero divisor, and a zero quotient.

**P32-R3-2 — Host-page padding becomes guest-accessible memory**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/rt32/ppc32_vm.c:443](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:443), [src/rt32/ppc32_vm.c:470](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:470)
- **Evidence & Root Cause:** The latest fix extends `rec_end` to the host-rounded mapping end, then uses that end for both `vm32_record_map` and the guest region record. On a 16-KiB host, a 4-KiB shared mapping therefore grants the requested guest permissions to an additional 12 KiB. Unmapping the requested 4 KiB leaves the padding represented as a live guest mapping. This confuses host backing allocation with the specified 4-KiB guest mapping granularity.
- **Concrete Fix:** Track host backing extent separately from guest-visible extent. Publish guest permissions and VMAs only through `map_end`; keep padding inaccessible while accounting for its backing when placing or replacing adjacent mappings. Cover a 4-KiB shared mapping, accesses immediately past its end, and unmapping its exact requested length.

**P32-R3-3 — Unaligned shared mappings silently become private copies**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/rt32/ppc32_vm.c:438](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:438), [src/rt32/ppc32_vm.c:474](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:474)
- **Evidence & Root Cause:** On A2, a shared mapping whose address or file offset is not host-page aligned fails `shared_direct`. It then enters the generic population branch: file contents are copied with `vm_file_populate_private`, or anonymous contents are zeroed. The mapping is nevertheless recorded as `VM32_PAGE_SHARED` and `MAP_SHARED`. A valid guest file offset of 4096 on a 16-KiB host reaches this path. The copied bytes do not provide coherent shared backing between aliases or processes.
- **Concrete Fix:** Implement shared backing for guest-aligned subpages, including alias and fork visibility. Until that exists, return an explicit unsupported-mapping error instead of reporting successful `MAP_SHARED` semantics. Test two mappings of the same file range and parent/child writes.

**P32-R3-4 — Multithreaded fork can inherit permanently locked runtime state**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/os/proc.c:102](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:102)
- **Evidence & Root Cause:** `ppc32_proc_fork` directly calls host `fork()`. Its child refresh changes context identity and reservation fields, but does not coordinate or repair process-global locks and thread bookkeeping. The repository contains custom VM, LL/SC, inode, and thread-table spinlocks, with no `pthread_atfork` registration found. If another host thread owns one at the fork snapshot, the child inherits the locked value without its owner and can spin forever. Resetting locks alone would also risk exposing metadata copied during a partial update.
- **Concrete Fix:** Add a coordinated fork protocol that reaches a consistent runtime state before the snapshot, releases locks in the parent, and rebuilds child lock ownership and thread bookkeeping around the sole surviving thread. Validate with a bounded child operation after forks concurrent with VM activity.

**P32-R3-5 — Signal syscalls overwrite aliased input before reading it**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/os/signals.c:605](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:605), [src/os/signals.c:635](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:635), [src/os/signals.c:704](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:704)
- **Evidence & Root Cause:** `rt_sigaction`, `rt_sigprocmask`, and `sigaltstack` write the old value to the output pointer before copying the requested input. When input and output overlap, the requested change is destroyed. For example, `rt_sigprocmask(SIG_SETMASK, p, p, 8)` rereads the old mask it just wrote and leaves the mask unchanged. Locked scalar copies prevent an unmap race but do not fix this ordering.
- **Concrete Fix:** Copy the complete input into a host-local structure before any output write. Apply validation and state changes using that snapshot. Add identical-pointer and partially overlapping-pointer cases for all three handlers.

**P32-R3-6 — Shared signal dispositions have unsynchronized readers and writers**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/os/signals.c:203](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:203), [src/os/signals.c:224](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:224), [src/os/signals.c:407](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:407)
- **Evidence & Root Cause:** Guest threads share the static `sig_actions` table. Getters copy individual fields, setters assign individual fields, and `SA_RESETHAND` clears them directly, without synchronization. Concurrent guest `sigaction` calls and delivery therefore create C data races and can combine a handler from one disposition with flags, restorer, or mask from another.
- **Concrete Fix:** Synchronize disposition snapshots and updates. Make selection and consumption of a one-shot disposition atomic with respect to other deliveries and updates. Release the disposition lock before frame construction or guest-memory access, and include it in fork coordination.

**P32-R3-7 — Successful exec clears the inherited signal mask**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/os/proc.c:428](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:428)
- **Evidence & Root Cause:** The successful guest `execve` path unconditionally assigns `ctx->sig_mask = 0ULL`. The calling thread’s blocked signal mask must survive exec. A program that blocks a signal before replacing its image consequently starts the new image with that signal unblocked. The adjacent comment incorrectly describes this reset as Linux exec semantics.
- **Concrete Fix:** Preserve the calling thread’s signal mask across image replacement and correct the comment. Add a guest that blocks a signal, execs another guest, and queries its inherited mask.

The inspected line counts stayed within 900 lines. Text searches found no prohibited string-function calls or C-source inclusions; matching `x18` references were comments. These checks do not establish full C11 compliance or validate emitted register encodings. No additional DRY/YAGNI finding was sufficiently established in this bounded review.

Checklist:

- [ ] **P32-R3-1:** Preserve the original divisor for overflow checks.
- [ ] **P32-R3-2:** Separate host padding from guest mappings.
- [ ] **P32-R3-3:** Preserve sharing for guest-aligned A2 mappings.
- [ ] **P32-R3-4:** Coordinate fork with runtime locks and thread state.
- [ ] **P32-R3-5:** Snapshot signal syscall inputs before output writes.
- [ ] **P32-R3-6:** Synchronize shared signal dispositions.
- [ ] **P32-R3-7:** Preserve the signal mask across exec.