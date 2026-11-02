Found **8 correctness defects and 1 unused API** in the inspected code. Two defects are in the latest `mremap` changes.

Used exactly four shell inspection turns, including `git show HEAD~1 --stat` and `git show HEAD`. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings are static; runtime behavior remains unverified.

**P64-R3-1 — Partial `mremap` loses the moved region’s file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:330`
- **Evidence & Root Cause:** The first loop truncates every partially overlapping file record to the portion outside the source range. The second loop only relocates records still inside that range. Consequently, moving a prefix, suffix, or interior portion of a file mapping creates no file record at the destination. The final sweep then drops its relocated COW slots. This path is reachable: `syscall_mm_mremap()` accepts covered subranges with uniform attributes. Untracked destination pages subsequently take the dirty/private fallback in `ppc64_vm_file_cow_get()` and can bypass shared-write tracking.
- **Concrete Fix:** Split each affected record into surviving source fragments and a relocated intersection. Preserve the intersection’s inode, sharing mode, and adjusted file offset. Reserve metadata capacity before mutation and return an error through the existing rollback path if allocation fails.

**P64-R3-2 — Interior `mremap` creates an inverted right-hand file record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:340`
- **Evidence & Root Cause:** For a record spanning both sides of the moved range, `m->gva_end` is first changed to `old_addr`. The right-hand record then copies this already-truncated record and sets its start to `old_end`, without restoring the original end. Its resulting interval is `[old_end, old_addr)`. The surviving right-hand guest mapping therefore loses valid file coverage even when a free metadata slot exists.
- **Concrete Fix:** Save the original record before modification. Construct the right fragment with its original end and adjusted offset. Preflight capacity so a full table cannot silently discard the right fragment.

**P64-R3-3 — `SS_AUTODISARM` can cause nested signals to overwrite the active frame**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:242`; `src/os/sigframe.c:480`
- **Evidence & Root Cause:** Signal delivery initializes `d.stack` to zero instead of saving the current alternate stack. It never disables an autodisarm stack after selecting it. Meanwhile, `ppc64_sigaltstack_onstack()` deliberately returns false for `SS_AUTODISARM`, so another `SA_ONSTACK` delivery selects the same stack top and can overwrite the first frame. `run_sig_restore()` also ignores the decoded `sout.stack`, preventing restoration of alternate-stack state.
- **Concrete Fix:** Save the current alternate-stack descriptor in the frame, disable autodisarm state after successful frame construction, and restore validated stack state on `rt_sigreturn`. Cover nested delivery and handler-driven stack replacement.

**P64-R3-4 — Idle scheduling fabricates timeouts and can terminate a live process**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:332`, `src/os/syscalls_p4.c:568`, `src/os/syscalls_p4.c:734`
- **Evidence & Root Cause:** `p4_check_futex_deadlines(..., true)` returns `ETIMEDOUT` to the earliest waiter without waiting for its deadline. The parent’s wait path likewise breaks when no child is schedulable and returns `ETIMEDOUT` merely because a timeout was supplied. After the main task exits, indefinitely waiting children cause the exit loop to break and report process completion despite remaining live tasks.
- **Concrete Fix:** Keep waiting tasks alive when the ready queue empties. Wait for an actual deadline or wake event, then recheck state. Compare remaining durations when selecting between realtime and monotonic deadlines; never expire a future deadline merely to make progress.

**P64-R3-5 — Signals cannot interrupt the main task’s futex wait**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:168`; `src/os/syscalls_p4.c:702`
- **Evidence & Root Cause:** Queuing a signal to the main task only sets `main_pending`. Child waiters receive an explicit READY/EINTR transition, but the main task has no equivalent. Its futex loop checks wake state, group exit, memory contents, and deadlines without checking pending signals. A child can send a handled signal to the blocked main task and continue running while the handler remains undelivered.
- **Concrete Fix:** Give the main task the same interruptible wait state as children, or explicitly check its deliverable pending signals in the wait loop and return `EINTR` before draining signal delivery.

**P64-R3-6 — Futex requeue omits the main waiter and misreports the result**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:794`
- **Evidence & Root Cause:** Requeue moves only entries in `s_tasks`; it never updates `s_parent_wait_addr`. If a child requeues the blocked main task, a subsequent wake at the destination cannot reach it. Additionally, line 813 returns `woken + reqd` only for `FUTEX_CMP_REQUEUE`; ordinary `FUTEX_REQUEUE` returns just `woken`, excluding successfully requeued waiters.
- **Concrete Fix:** Include the main waiter in requeue selection and accounting, respecting the wake and requeue limits. Return the number of awakened plus requeued waiters for both commands.

**P64-R3-7 — Valid large futex timeouts wrap into short or expired deadlines**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:675`
- **Evidence & Root Cause:** The timespec validation rejects negative seconds and invalid nanoseconds, but `sec * 1000000000 + nsec` and `now_ns + dur_ns` use unchecked `uint64_t` arithmetic. Large valid positive durations can wrap and satisfy the immediately following expiration check.
- **Concrete Fix:** Use checked multiplication and addition, saturating large valid timeouts to the maximum supported deadline. Apply equivalent handling to absolute deadlines.

**P64-R3-8 — Installing an ignored disposition leaves stale child-pending signals**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:138`
- **Evidence & Root Cause:** When a disposition becomes ignored, `run_sig_record()` clears only `run_sig_pending`. Pending bits stored in each child’s `sig_pending` remain. A blocked signal queued to a child can therefore survive a transition to `SIG_IGN`, then be delivered after a handler is reinstalled and the child unmasks it. Scheduler wake logic can also act on these stale bits.
- **Concrete Fix:** Add a scheduler helper that discards the signal from every task’s pending set and call it when installing an ignored disposition.

**P64-R3-9 — Obsolete VMA rollback API remains exposed**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/syscalls_mm.c:188`; `src/os/syscalls_mm_vma.h:58`
- **Evidence & Root Cause:** Searches across `src/` and `tests/` found no callers of `syscall_vma_snapshot()` or `syscall_vma_restore()`. Active rollback uses the full-table helpers. The obsolete restore implementation also retains the overlapping-fragment problem described by the replacement’s comment: it removes only the replacement interval before reinserting complete original spans.
- **Concrete Fix:** Remove the unused functions and declarations, retaining the full-table rollback API.

The static line-count scan found no `.c`, `.h`, or `.S` files over 900 lines in `src/` or `tests/`. The Makefile includes the requested warning flags. The targeted hygiene search found no prohibited string calls or `.c` includes; textual `x18` matches were comments. This does not establish correctness of encoded register operands or compiler acceptance.

Checklist:

- [ ] **P64-R3-1:** Preserve relocated partial file mappings.
- [ ] **P64-R3-2:** Preserve the right fragment’s original end.
- [ ] **P64-R3-3:** Implement alternate-stack save, autodisarm, and restore.
- [ ] **P64-R3-4:** Wait for real deadlines and preserve blocked live tasks.
- [ ] **P64-R3-5:** Interrupt main-task futex waits for deliverable signals.
- [ ] **P64-R3-6:** Requeue the main waiter and correct return counts.
- [ ] **P64-R3-7:** Check timeout arithmetic.
- [ ] **P64-R3-8:** Discard ignored signals from every task.
- [ ] **P64-R3-9:** Remove obsolete VMA rollback helpers.