Round 3 found **8 actionable issues** at `a86a161`, including a regression in the new VM generation fast path.

This was a static review using **7 shell inspection turns**. I inspected the five recent commits, both requested changesets, and selected VM, interpreter, DBT, syscall, signal, header, and test paths. No builds, tests, Docker, or QEMU ran. Findings below are source-based; this is not exhaustive runtime qualification.

### M32-R3-1 — `brk` marks stale VMA snapshots current

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm.c:98`, `src/rt32/vm.c:765`

**Evidence & Root Cause:** `vm_sync_brk_to_ctx()` updates only break fields but assigns the latest `vm_gen`. The new synchronization fast path treats that generation as proof that the entire context mapping table is current.

If thread A changes mappings and thread B subsequently calls `brk(0)` or changes its break within the same page, B can acquire the current generation without copying `g_vm_regions`. Subsequent synchronization skips the stale table until another VM mutation occurs.

**Concrete Fix:** Refresh the full context snapshot before assigning its generation, or track break and VMA generations separately. Add a regression covering one thread changing mappings while another queries `brk`.

### M32-R3-2 — Darwin shared-alias flushing overwrites newer data

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm_mmap.c:92`, `src/rt32/vm_mmap.c:164`

**Evidence & Root Cause:** Inode flushing visits every shadow mapping and copies its entire overlapping range into other aliases before writing it back. There is no dirty-byte tracking or authoritative shared backing.

For two shadow aliases A and B of the same file offset, a store through B leaves A stale. Flushing the inode visits A first when A has the lower guest address, copies stale bytes over B, and writes those bytes to the file. B’s subsequent flush cannot recover its update. Ordinary stores also do not provide immediate alias visibility.

**Concrete Fix:** Use coherent shared backing for aliases, or route shared-shadow reads and writes through an authoritative inode/offset representation. Whole-range copying from arbitrary aliases cannot establish which data is current.

### M32-R3-3 — Darwin protection restoration can disable adjacent guest pages

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm_mmap.c:64`, `src/rt32/vm_mmap.c:111`, `src/rt32/vm_mmap.c:707`

**Evidence & Root Cause:** `vm_host_temp_prot()` rounds a guest range to 16 KiB, but restoration applies the protection of only the selected VMA.

If a read-only 4 KiB shared mapping has a writable neighbor in the same host page, synchronization temporarily enables writes and then restores the entire host page to read-only. The neighbor remains writable in guest metadata, yet valid stores can fault on the host.

**Concrete Fix:** Compute host protections from all guest mappings overlapping each host page. Use that common protection calculation for temporary restoration, mapping changes, and unmapping.

### M32-R3-4 — Guest copyout bypasses LL/SC reservation tracking

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm.c:821`, `src/os/mem.c:464`

**Evidence & Root Cause:** `rt32_vm_copy_to()` performs a plain `memcpy` under the VM lock. Interpreter stores instead use the LL/SC lock and update reservation epochs.

A second thread can copy the same value into a reserved word through a syscall output or thread-TID write without changing its epoch. The reserving thread’s subsequent SC can therefore succeed despite the intervening write. Clearing the syscall caller’s `llbit` does not clear another thread’s reservation.

**Concrete Fix:** Route guest copyout through a common bulk-store primitive that participates in LL/SC exclusion and advances every affected reservation epoch. Establish a consistent lock order.

### M32-R3-5 — Real-time queue overflow silently loses signals

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/signals.c:277`, `src/os/kill.c:216`

**Evidence & Root Cause:** Once `sig_rt_count` reaches its capacity, `mips_signal_pend()` skips enqueueing but still sets the pending bit. Its caller returns success.

For 65 blocked occurrences of the same real-time signal, only 64 queue entries survive. Popping the last entry clears the pending bit, discarding the additional occurrence.

**Concrete Fix:** Make enqueue failure observable and implement explicit overflow handling appropriate to the originating syscall. Preserve all accepted occurrences; never report successful queueing for a discarded event.

### M32-R3-6 — `execve` incorrectly clears inherited signal state

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/signals.c:853`

**Evidence & Root Cause:** `mips32_signals_reset_for_exec()` resets every disposition, clears the blocked mask, and discards pending signals and the real-time queue.

Successful Linux `execve` preserves the signal mask and pending signals, and generally preserves ignored dispositions. The implementation can lose pending events, unblock deliberately blocked signals, and turn an inherited ignored signal into a terminating one.

**Concrete Fix:** Reset caught handlers to default while retaining ignored dispositions, the blocked mask, and pending events. Clear obsolete frame bookkeeping and disable the alternate stack.

### M32-R3-7 — Signal delivery alters the interrupted stack pointer

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/signals.c:631`

**Evidence & Root Cause:** Frame construction saves `$sp` as `ctx->gpr[i] & ~7U` instead of its original value. `rt_sigreturn()` restores that modified value.

Aligning the newly allocated signal frame is appropriate; rounding the saved interrupted register changes architectural state. A synchronous fault during an instruction sequence with a temporarily unaligned stack pointer resumes with a different `$sp`.

**Concrete Fix:** Save the exact interrupted `$sp`. Apply alignment only to the handler’s frame address.

### M32-R3-8 — New errno regression test is disconnected from verification

**Severity:** Low  
**Category:** DEFECT  
**Location:** `tests/test_errno_map.c:1`, `Makefile:78`

**Evidence & Root Cause:** The post-fable commit adds `test_errno_map.c`, but neither `make test` nor `make check` invokes it. The inspected scripts contain no reference to it. Normal verification therefore does not exercise the new errno assertions.

**Concrete Fix:** Add the test to the host-native test target, propagate failures, and exercise its Darwin-specific conditional assertions on Darwin.

The static hygiene scan found no `.c`, `.h`, or `.S` file exceeding 900 lines. The Makefile retains the required C11 warning flags, and `CLAUDE.md` remains symlinked to `AGENTS.md`. The targeted text scan found no prohibited string functions, `.c` includes, or explicit `x18` instruction operands; this does not validate encoded register operands.

- [ ] **M32-R3-1:** Keep VMA snapshots consistent with their generation.
- [ ] **M32-R3-2:** Prevent stale shared aliases from overwriting newer data.
- [ ] **M32-R3-3:** Restore host-page protections using all overlapping mappings.
- [ ] **M32-R3-4:** Include copyout writes in LL/SC reservation tracking.
- [ ] **M32-R3-5:** Handle real-time queue overflow without silent loss.
- [ ] **M32-R3-6:** Preserve required signal state across `execve`.
- [ ] **M32-R3-7:** Preserve the exact interrupted stack pointer.
- [ ] **M32-R3-8:** Wire the errno regression test into verification.