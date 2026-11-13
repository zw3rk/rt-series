Round 3 found **10 remaining issues**, including incomplete concurrency fixes in the latest commits.

Reviewed `b40924b` and `a73ff14`, recent history, and selected VM, DBT, interpreter, syscall, backend, and test paths in **five shell inspection turns**. No builds, tests, Docker, or QEMU ran. These are static findings, not runtime reproductions.

### S32-R3-1 — Context teardown still permits cross-thread use-after-free

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads.c:103`, `src/os/threads.c:136`

**Evidence & Root Cause:** `thr_drop_context()` blocks signals only in the calling thread, removes the context from `thr_live`, and frees it. A handler on another thread can already have loaded that context pointer at line 136 and subsequently write `pending_signals` at line 140 after the free. Atomic publication protects the slot, not the pointed-to allocation. The new comment claiming that a handler cannot observe the freed pointer is incorrect.

**Concrete Fix:** Remove reclaimable context pointers from the asynchronous handler path. Have handlers update stable pending-signal storage and let normal execution route signals to contexts. Alternatively, introduce a signal-safe reclamation protocol that waits for all existing readers before freeing.

### S32-R3-2 — Fork resets VM counters without securing a consistent process snapshot

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads.c:313`, `src/rt32/vm.c:137`, `src/dbt/dbt_cache.c:46`

**Evidence & Root Cause:** `fork()` runs without coordinating VM or DBT mutations. The child resets only the VM reader/writer counters. It still inherits `thr_live_lock`, `g_dbt_lock`, DBT runner counts, and contexts belonging to vanished threads.

A worker can hold `thr_live_lock` when another thread forks; the child then deadlocks on its next `sparc32_threads_ensure_init()`. A child also can inherit a nonzero DBT runner count that can never drain. Resetting the VM lock after the fork does not repair metadata captured halfway through a VM mutation.

**Concrete Fix:** Establish a coordinated fork protocol: stop admission of new work, quiesce execution and VM mutations, acquire shared locks in a defined order, fork, then rebuild child-only thread registration and synchronization state. Reset counters only after obtaining a consistent snapshot.

### S32-R3-3 — VM reader protection does not cover generated memory accesses

**Severity:** High  
**Category:** BUG  
**Location:** `src/dbt/emit_fast.c:162`, `src/dbt/dbt.c:355`, `src/rt32/vm_mmap.c:294`

**Evidence & Root Cause:** Generated fast paths check the protection byte and then access the guest window directly. `dbt_exec_enter()` registers a DBT runner but does not join the VM reader protocol. Conversely, `vm_lock_acquire()` waits only for VM readers.

A worker can therefore change or remove a mapping after the main DBT thread passes its permission check but before its load/store. Mapping invalidation occurs after mutation and lock release; it cannot protect an already executing access. This permits host faults or accesses to replacement mappings.

**Concrete Fix:** Integrate VM mutation with execution quiescence. Before changing host mappings or permissions, prevent new translated execution and drain existing runners and memory helpers. Define lock ordering explicitly, including helpers invoked from generated code.

### S32-R3-4 — Exec replaces memory while sibling guest threads remain alive

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads_exec.c:155`, `src/rt32/vm.c:749`

**Evidence & Root Cause:** Successful `execve` resets dispositions and replaces the shared guest window without terminating sibling guest threads. Those threads retain old PCs, stacks, and contexts and can resume against the new image. Additionally, `rt32_vm_reset_for_exec()` releases its VM lock before the window-wide `MAP_FIXED` operation and permission-table resets.

This is independently incorrect even after protecting individual DBT memory accesses: old guest threads must not survive successful exec.

**Concrete Fix:** After preparation succeeds, stop and retire all sibling guest threads before destroying the old image. Keep the replacement transaction protected through mapping and table publication, then resume only the exec caller.

### S32-R3-5 — Signal masks and alternate stacks are incorrectly process-global

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/syscalls_time.c:36`, `src/os/syscalls_sig.c:59`, `src/interp/interp_signal.c:513`

**Evidence & Root Cause:** `l2a_blocked` is shared mutable storage, and delivery combines it with each context’s mask. Blocking a signal in one guest thread therefore blocks it in unrelated threads. Its plain loads and stores also race.

Likewise, the single `sigalt` object shares the alternate-stack address and `onstack` state across all guest threads. Concurrent handlers can use another thread’s stack or incorrectly consider themselves already on an alternate stack. Atomic accesses do not correct this ownership error.

**Concrete Fix:** Store both mask and alternate-stack state in the guest thread context. Remove the global mask merge. Apply explicit clone inheritance and exec-reset rules to those context fields.

### S32-R3-6 — Ignored signals become default-action signals

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/syscalls_sig.c:205`, `src/os/threads.c:151`

**Evidence & Root Cause:** Installing either `SIG_DFL` or `SIG_IGN` clears `sigact[sig].installed`. `sparc32_signal_get()` subsequently reports both as absent. The host handler responds by restoring `SIG_DFL` and re-raising the signal.

For example, a guest that ignores `SIGTERM` can still be terminated. Querying the disposition also loses `SIG_IGN`, because the query path returns handler zero when `installed` is false.

**Concrete Fix:** Represent default, ignored, and caught dispositions distinctly. Preserve and return `SIG_IGN`; discard ignored signals rather than re-raising them.

### S32-R3-7 — One host signal is delivered to every guest thread

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/threads.c:125`

**Evidence & Root Cause:** `sparc32_thr_note_signal()` sets the pending bit on every live context. Each context independently consumes that bit. A single process-directed signal can consequently invoke the guest handler multiple times. Thread-directed delivery also loses its target through this broadcast path.

**Concrete Fix:** Maintain separate process-pending and thread-pending signals. Let one eligible thread atomically claim a process-directed signal, and route thread-directed signals only to their target context.

### S32-R3-8 — Signal-action updates are atomic by field but not coherent

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/syscalls_sig.c:90`, `src/os/syscalls_sig.c:212`

**Evidence & Root Cause:** Replacing an installed action writes its handler, restorer, flags, and mask independently while `installed` remains true. A concurrent reader can obtain the new handler with the old restorer or flags. The final release-store of `installed = 1` does not make earlier readers obtain a coherent snapshot.

This can construct a signal frame using incompatible action fields.

**Concrete Fix:** Serialize action updates and snapshots outside asynchronous host handlers. If asynchronous access remains necessary, publish an immutable action snapshot with safe lifetime management; avoid a retry loop that can deadlock when a signal interrupts its own writer.

### S32-R3-9 — Guest exec does not close close-on-exec descriptors

**Severity:** Medium  
**Category:** DEFECT  
**Location:** `src/os/threads_exec.c:42`, `src/os/threads_exec.c:155`

**Evidence & Root Cause:** The exec implementation explicitly leaves descriptors open. Guest open and pipe paths set host `FD_CLOEXEC`, but guest exec only reloads an image; it never performs host exec, so those flags are never acted upon.

Descriptors leak into the replacement guest image. A leaked pipe endpoint can also prevent EOF and hang another process.

**Concrete Fix:** Track guest-owned descriptors and close those marked close-on-exec when exec commits. Keep translator-owned backing and control descriptors separate from that sweep.

### S32-R3-10 — ELF overlap validation duplicates loader geometry

**Severity:** Low  
**Category:** DRY  
**Location:** `src/rt32/elf32.c:592`

**Evidence & Root Cause:** `elf_collect_spans()` reparses ELF headers and independently reproduces the program-header limit, load-bias decision, and page-span calculations already performed by `load_elf32_image()`. Its comment explicitly acknowledges that it mirrors the loader. Preparation now has multiple interpretations of the same image geometry that must remain synchronized.

**Concrete Fix:** Retain validated segment spans in `rt32_elf_plan_t`, or produce a single internal parsed-image representation used by overlap validation and commit. Keep this abstraction local to this repository.

The inspected source counts were within 900 lines, and the Makefile’s default C flags include the required strict warnings. This limited static review does not establish complete ISA/FPU correctness or runtime parity.

### Checklist

- [ ] **S32-R3-1:** Make context reclamation safe against remote signal handlers.
- [ ] **S32-R3-2:** Coordinate fork and rebuild child synchronization state.
- [ ] **S32-R3-3:** Quiesce generated accesses before VM mutations.
- [ ] **S32-R3-4:** Retire sibling threads before exec replaces memory.
- [ ] **S32-R3-5:** Make signal masks and alternate stacks per-thread.
- [ ] **S32-R3-6:** Preserve and honor ignored dispositions.
- [ ] **S32-R3-7:** Route each signal to the appropriate recipient.
- [ ] **S32-R3-8:** Publish coherent signal-action snapshots.
- [ ] **S32-R3-9:** Implement guest close-on-exec handling.
- [ ] **S32-R3-10:** Reuse validated ELF segment geometry.