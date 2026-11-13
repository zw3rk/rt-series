Found **16 actionable issues** at `f7d73db`. The Round-3 and follow-up fixes are present, but thread retirement, signal routing, descriptor tracking, and VM publication still have incomplete paths.

Used **seven shell inspection commands**, including the requested history commands. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings below are static conclusions; commit-message test claims were not independently verified.

**S32-R4-1 — Clone startup storage can be freed before the parent finishes using it**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads.c:777`
- **Evidence & Root Cause:** The child signals `st->ready`, unlocks `st->lock` at lines 616–620, and immediately begins guest execution. A fast exit reaches `thr_thread_finish()`, which frees `st` at line 604. The parent can subsequently lock, read, unlock, or destroy synchronization objects in that freed allocation at lines 777–784. Signaling readiness does not transfer lifetime ownership safely.
- **Concrete Fix:** Separate the startup rendezvous from child-owned execution storage, or add an ownership handshake/reference count that keeps both the allocation and synchronization objects alive until both participants finish. Add a repeated immediate-child-exit regression.

**S32-R4-2 — Retired threads can modify the replacement executable’s memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads.c:489`
- **Evidence & Root Cause:** After roughly two seconds, retirement removes remaining siblings from `thr_live` without stopping their host calls. A sibling blocked in `sys_read()` can later return and execute `l2a_store()` into the reused guest address space (`src/os/syscalls_min.c:221`). Its eventual retirement also calls `thr_thread_finish()`, which clears the old `st->clear_tid_va` at lines 588–590. Sticky retirement marks protect subsequent instruction execution, but neither copyout nor cleanup. Clone admission is also not closed during the retirement snapshot.
- **Concrete Fix:** Serialize exec and clone admission; interrupt and acknowledge sibling shutdown before replacing the address space. Add an address-space generation check before syscall copyout and suppress old-image clear-TID writes. Do not treat deregistration as completed retirement.

**S32-R4-3 — VM writers release DBT quiescence before retiring stale translations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_mmap.c:298`
- **Evidence & Root Cause:** `mprotect`, `munmap`, and mapping replacement release `vm_lock` before calling `vm_invalidate_jit()`. `vm_lock_release()` also releases `g_dbt_lock`. A DBT thread can enter between these operations and execute code compiled from the old mapping. The epoch bump during quiescence does not solve this: `dbt_lookup_locked()` at `src/dbt/dbt.c:258` refreshes the epoch of an otherwise valid block without recompiling it.
- **Concrete Fix:** Retire affected blocks and chaining entries while DBT admission remains closed. Introduce a lock-held invalidation helper and publish the mapping/protection change and cache invalidation as one transaction.

**S32-R4-4 — Guest signal numbers are passed directly to incompatible host ABIs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_sig.c:93`
- **Evidence & Root Cause:** `sig_host_sync()` passes the SPARC signal number directly to host `sigaction()`. `threads_kill.c` similarly passes it to `kill`/`tgkill`, and `sparc32_thr_host_handler()` queues the host number unchanged. SPARC numbering differs from AArch64 Linux and Darwin—for example, the repository’s guest tests identify SIGUSR1 as 30. The special-case exclusion of signal 7 as SIGBUS also uses the wrong SPARC number. Self-generated tests can conceal this by using the same incorrect number in both installation and sending.
- **Concrete Fix:** Implement explicit SPARC↔host signal conversion at every host boundary, including delivery, installation, masks, and wait-status translation. Keep pending queues and guest frames exclusively in SPARC numbering.

**S32-R4-5 — Blocked default-action signals act immediately**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:164`
- **Evidence & Root Cause:** Guest mask updates only change `ctx->sig_mask` (`src/os/syscalls_time.c:46`). Default dispositions are mirrored as host `SIG_DFL`, and the default `tgkill` path immediately invokes the host kernel without checking the guest mask. Blocking guest SIGTERM and then sending it therefore terminates the host process instead of leaving it pending. Process-directed `kill()` has the same problem.
- **Concrete Fix:** Queue maskable default-action signals and apply their actions only when guest delivery permits. Integrate host reception with guest masks; keep genuinely unmaskable signals separate. Add blocked-default, pending-query, and unblock regressions.

**S32-R4-6 — Wakeup “echo” deduplication loses or duplicates real signals**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/interp_signal.c:547`
- **Evidence & Root Cause:** Thread delivery consumes any same-number process-pending bit as an assumed wakeup echo. Process delivery likewise discards a claimed bit whenever another thread has that signal pending. An independent process-directed signal is therefore lost when it coincides with a thread-directed signal. Conversely, the target can consume its thread bit before the sender executes the host wakeup at `threads_kill.c:187`; the later host handler creates a fresh process bit that can deliver again.
- **Concrete Fix:** Use a distinct internal wakeup mechanism that never enters guest pending queues. Maintain process-directed and thread-directed events independently; remove same-number echo inference.

**S32-R4-7 — `tgkill` accepts an unrelated thread-group ID**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:117`
- **Evidence & Root Cause:** Local lookup checks only `tid`. A found target makes the signal-zero path return success without validating `tgid`. Caught and ignored dispositions also succeed locally for an incorrect `tgid`; caught delivery queues the bit before the host wakeup, whose failure is ignored.
- **Concrete Fix:** Validate the requested thread group before local lookup or queue mutation. Preserve host errors where a host operation remains necessary. Cover wrong-group signal-zero, caught, and ignored cases.

**S32-R4-8 — Darwin thread signals use thread IDs as process IDs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:94`
- **Evidence & Root Cause:** Darwin `thr_gettid()` derives an integer from `pthread_threadid_np()`. The non-Linux `thr_host_tgkill()` fallback calls `kill((pid_t)host_tid, sig)`. A Darwin thread ID is not a process ID: this can return `ESRCH` or address an unrelated process. Caught-signal wakeup errors are then ignored.
- **Concrete Fix:** Retain a valid `pthread_t` alongside the guest-visible TID and use `pthread_kill()` for live local targets, with correct lifetime protection and signal-number translation. Never reinterpret a thread ID as a PID.

**S32-R4-9 — Successful exec incorrectly clears blocked and pending signals**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_exec.c:196`
- **Evidence & Root Cause:** Exec clears `ctx->pending_signals` and `ctx->sig_mask`; it also clears the process-pending queue at line 165. Linux exec preserves the calling thread’s blocked mask and pending signals. Resetting caught dispositions and disabling the alternate stack do not authorize clearing these states.
- **Concrete Fix:** Preserve the survivor’s mask and relevant pending queues across successful exec. Continue resetting caught dispositions and alternate-stack state. Add a guest that blocks and queues a signal, execs, and queries both states.

**S32-R4-10 — FD bookkeeping races with host descriptor reuse**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:290`
- **Evidence & Root Cause:** Host `close(fd)` happens before acquiring the tracking lock in `sparc32_fd_note_close()`. Another thread can reopen the same descriptor and record it between those operations; the old closer then erases the new descriptor’s tracking. Open, dup, and flag updates similarly separate host operations from metadata commits. Fork’s FD-table lock consequently does not guarantee a consistent host-FD/table snapshot. The exec sweep also unlocks before its actual `close()`.
- **Concrete Fix:** Serialize each descriptor lifecycle operation and its metadata update under one consistent protocol, including fork snapshots and exec sweeping. Account for translator-owned descriptor allocation and reuse in that protocol.

**S32-R4-11 — Darwin anonymous `PROT_NONE` remaps retain old contents**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:243`
- **Evidence & Root Cause:** Fixed anonymous mappings use `mprotect()` rather than replacing their backing. For `PROT_NONE`, the function returns without zeroing the requested bytes, including an immediate return for a partial host page. A guest can write a pattern, replace the range with anonymous `MAP_FIXED|PROT_NONE`, then enable reading with `mprotect()`. The new anonymous mapping exposes the previous bytes.
- **Concrete Fix:** Establish fresh zero-filled anonymous contents independently of requested permissions, preserving neighboring 4 KiB pages on 16 KiB hosts. Add a patterned-page → anonymous `PROT_NONE` remap → readable-page regression.

**S32-R4-12 — Darwin copied file mappings expose zero-filled pages beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:373`
- **Evidence & Root Cause:** The unaligned private-file mapping path zeroes the entire mapping, copies until `pread()` reaches EOF, then returns success. `vm_mmap_publish()` grants the requested protection to every page. Interpreter and syscall accessors check those protections and access the backing directly, so pages wholly beyond EOF return zeros instead of producing a guest SIGBUS.
- **Concrete Fix:** Track file-valid page extents separately from permissions and enforce them in interpreter, DBT, and syscall-access paths. Preserve zero-fill only for the valid final partial page; update validity on truncate/regrow.

**S32-R4-13 — Mapping success ignores failure to record the VMA**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_mmap.c:199`
- **Evidence & Root Cause:** `vm_mmap2_locked()` installs host backing and publishes page permissions, then discards `vm_record_region_ext_locked()`’s result and returns the address. Region-table exhaustion or insertion failure can therefore leave accessible pages absent from the authoritative VMA records. Gap selection, overlap checks, backing retention, and later remapping then operate on incomplete state. The move path repeats this unchecked recording at line 557.
- **Concrete Fix:** Reserve all required region entries and backing resources before destructive mapping operations. Propagate failures and commit host mappings, page tables, and VMA metadata together; provide rollback where preparation cannot guarantee success.

**S32-R4-14 — Descriptors above 8191 silently escape close-on-exec handling**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/threads_fd.c:45`
- **Evidence & Root Cause:** Every tracking operation silently ignores descriptors at or above `THR_FD_TRACK_MAX`, while guest descriptor allocation is not constrained to that range. A successful high-numbered `F_DUPFD` followed by `F_SETFD(FD_CLOEXEC)` remains open after emulated exec because no real host exec performs the kernel sweep.
- **Concrete Fix:** Grow the tracking structure to cover accepted descriptors, or enforce an explicit guest descriptor limit consistently. Never return successful descriptor allocation while silently omitting required lifecycle tracking.

**S32-R4-15 — Checked big-endian guest word access is duplicated across syscall units**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/threads_fd.c:180`
- **Evidence & Root Cause:** `fd_st`, `thr_st`, `sig_st_be32`, and `l2a_st_be32` independently implement the same stack-buffer → `put_be32()` → `l2a_store()` sequence. Similar checked loads exist in the signal and exec units. These copies all depend on the same permission, copyout, and invalidation behavior.
- **Concrete Fix:** Add checked BE32 load/store helpers to the existing repo-local `os/l2a_access.h` and replace equivalent copies. Keep raw loader/stack initialization helpers separate where their contracts differ.

**S32-R4-16 — The retirement survivor global is write-only**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/threads.c:78`
- **Evidence & Root Cause:** `g_exec_survivor` is initialized, reset after fork, and assigned at retirement start. No source or test reads it. Retirement decisions now use `thr_retired_contains()`, so this atomic state no longer participates in the protocol.
- **Concrete Fix:** Remove the global and its stores; update comments that imply it controls survivor selection.

The CLEAN inspection found no oversized `.c`/`.h`/`.S` files, prohibited string-call matches, `.c` includes, or production assembly references to `x18` in the searched paths. The Makefile retains the prescribed warning flags. This was not a compiler-based compliance verification, and the bounded audit does not certify the unreported ISA/FPU paths.

- [ ] **S32-R4-1:** Fix clone startup-object ownership.
- [ ] **S32-R4-2:** Complete sibling shutdown before exec replacement.
- [ ] **S32-R4-3:** Invalidate translations before reopening DBT admission.
- [ ] **S32-R4-4:** Translate signal numbers at host boundaries.
- [ ] **S32-R4-5:** Honor guest masks for default-action signals.
- [ ] **S32-R4-6:** Separate internal wakeups from guest signal queues.
- [ ] **S32-R4-7:** Validate `tgkill` thread-group IDs.
- [ ] **S32-R4-8:** Use pthread handles for Darwin thread signals.
- [ ] **S32-R4-9:** Preserve masks and pending signals across exec.
- [ ] **S32-R4-10:** Make FD operations and bookkeeping atomic.
- [ ] **S32-R4-11:** Zero anonymous Darwin remaps regardless of initial protection.
- [ ] **S32-R4-12:** Enforce EOF faults for copied file mappings.
- [ ] **S32-R4-13:** Make VMA registration failures transactional.
- [ ] **S32-R4-14:** Track every accepted guest descriptor.
- [ ] **S32-R4-15:** Unify checked BE32 syscall access helpers locally.
- [ ] **S32-R4-16:** Remove write-only retirement state.