# mips32rt — Round 2 Static Audit

**HEAD:** `366ca9bdc5e3743a85d833cf214e218f011e23cb`

**Scope:** Seven read-only shell inspection turns. Inventoried **24,848 lines** of `.c`, `.h`, and `.S` files across `src/`, `include/`, and `tests/`; inspected selected remediation diffs and VM, interpreter, DBT, signal, syscall, loader, and build paths.

**Result:** The remediation improves several Round-1 defects, but does not fully resolve VM synchronization, Darwin shared mappings, or signal handling. Further concrete defects appear below.

**Limits:** Several large outputs were truncated, and initial Git invocations did not return usable diffs. This is a bounded static audit, **not complete verification of every module**. No builds, compilers, QEMU, Docker, or tests were intentionally run. Git’s macOS launcher emitted Xcode/cache diagnostics. No repository files were changed.

Round-1 verification established that:

- Integer branch-likely annulment now avoids the delay-slot fetch.
- `execve` performs preliminary ELF validation and terminates on post-teardown loading failure instead of returning into the destroyed image.
- Shared SMC generations and an overflow flush epoch replace thread-local invalidation bookkeeping; full concurrent execution safety remains unverified.
- Both default compiler flag sets include `-Werror`, tests participate in the line-limit target, and every inventoried source file is at most 900 lines.
- FP delay-slot delivery, VM capacity handling, shared backing, and synchronization still have defects.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 0 | 2 | 0 | 0 | 0 | 10 |
| Medium | 2 | 1 | 0 | 0 | 0 | 0 | 3 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **10** | **1** | **2** | **1** | **1** | **1** | **16** |

## 1. Bugs & Defects

### High

- [ ] **M32-R2-1 — High — BUG — FP delay-slot fetch failure can deliver the same fault twice**
  - **Where**: `src/interp/fp.c:818-829` (`fp_bc1`); `src/os/mem.c:204-228` (`mips_fault`); `src/os/signals.c:660-665` (`mips_raise_guest_code`)
  - **What breaks / Why**: The fetch-failure branch treats `exit_reason == MIPS32_EXIT_NONE` as a reason to raise another fault. Successful guest signal delivery deliberately clears that field. A delay-slot fetch fault already delivered to a handler therefore triggers another delivery, now from the handler context with delay-slot state cleared. This creates an extra frame, or terminates if `SA_RESETHAND` removed the handler.
  - **Fix**: Propagate the fetch failure without raising it again. Preserve the context installed by the memory fault path. Add a focused case with an inaccessible FP branch delay slot and a returning signal handler.

- [ ] **M32-R2-2 — High — BUG — Darwin sub-page shared mappings remain independent snapshots**
  - **Where**: `src/rt32/vm_mmap.c:132-157` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:147-175` (`vm_writeback_darw_locked`)
  - **What breaks / Why**: The unaligned Darwin path still populates existing arena memory with `pread`. Setting `darw_sync` adds eventual writeback, not shared backing. Two mappings of the same file do not observe each other’s stores, and changes through file I/O are not reflected in existing snapshots. Writing back the entire snapshot can overwrite newer file contents with stale bytes.
  - **Fix**: Implement coherent backing and alias coordination for sub-page shared mappings. Until supported, reject such mappings explicitly rather than advertise `MAP_SHARED` semantics.

- [ ] **M32-R2-3 — High — BUG — Darwin writeback occurs after the old mapping becomes inaccessible or is replaced**
  - **Where**: `src/rt32/vm_mmap.c:304-312` (`vm_munmap_locked`), `src/rt32/vm_mmap.c:144-155` and `194-199` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:178-185` (`vm_remove_region_at`)
  - **What breaks / Why**: Unmapping first applies `PROT_NONE`, then removes metadata and attempts writeback. A sub-page-backed mapping spanning complete host pages can consequently produce `EFAULT` during `pwrite`; that error is discarded. Fixed replacement similarly installs or populates new bytes before removing the old region, so old-backing writeback can write replacement contents into the old file.
  - **Fix**: Complete checked writeback while the original bytes remain accessible, before protection changes or replacement. Propagate failures and preserve consistent mapping state.

- [ ] **M32-R2-4 — High — BUG — mprotect capacity preflight disagrees with the mutation**
  - **Where**: `src/rt32/vm.c:353-368` (`vm_can_mprotect_regions_locked`), `src/rt32/vm.c:371-405` (`vm_mprotect_regions_locked`)
  - **What breaks / Why**: Preflight skips regions whose protection already equals the requested protection. The mutation does not skip them: it still splits partial overlaps and ignores insertion failures. With a full region table, a same-protection operation on the middle of a region passes preflight, truncates the original entry, and loses the unrecorded remainder.
  - **Fix**: Apply the same unchanged-protection condition in both passes. Check insertion results and guarantee all necessary entries before modifying any region.

- [ ] **M32-R2-5 — High — BUG — munmap reports success when its metadata split fails**
  - **Where**: `src/rt32/vm.c:276-302` (`vm_unmap_regions_locked`); `src/rt32/vm_mmap.c:304-316` (`vm_munmap_locked`)
  - **What breaks / Why**: Removing the middle of a region requires another entry. If insertion fails after coalescing, the original region remains recorded across the hole. The host mapping has already changed, and `munmap` returns success. On Darwin, a sub-page hole may remain host-accessible and be accepted by stale software permissions.
  - **Fix**: Reserve split capacity before changing host mappings. Make metadata removal return an error, and leave both host and guest mapping state unchanged when the split cannot be represented.

- [ ] **M32-R2-6 — High — BUG — mmap can return failure after replacing live memory**
  - **Where**: `src/rt32/vm_mmap.c:159-199` (`vm_mmap2_ext_locked`)
  - **What breaks / Why**: Host `MAP_FIXED` occurs before duplicating the backing descriptor and before ensuring region-table capacity. Descriptor exhaustion or metadata insertion failure returns an error after guest bytes or protections have already changed. The old metadata can remain associated with replacement memory.
  - **Fix**: Acquire backing descriptors and reserve metadata capacity before host mutation. Provide explicit rollback or a commit sequence that cannot fail after replacement.

- [ ] **M32-R2-7 — High — BUG — Pending delivery after sigreturn can skip an unexecuted syscall**
  - **Where**: `src/os/signals.c:295-305` (`mips_signal_deliver_pending`), `src/os/signals.c:734-751` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Pending delivery fetches the instruction at the current PC and advances past it whenever it equals `syscall`. That helper also runs after restoring a signal frame. If the restored PC points to a syscall that has not executed, delivering another pending signal saves `PC + 4`, permanently skipping that syscall.
  - **Fix**: Pass an explicit resume PC or delivery-boundary reason. Advance the PC only in the syscall completion path that knows the instruction has executed; never infer completion from instruction bytes.

- [ ] **M32-R2-8 — High — BUG — A2 private-file population writes through read-only mappings**
  - **Where**: `src/rt32/vm_mmap.c:117-128` and `180-190` (`vm_mmap2_ext_locked`); `src/vm/vm_file.c:65-78` (`mips32_file_populate_private`)
  - **What breaks / Why**: An aligned Darwin private file mapping is installed using its requested host protection, then populated again whenever the regime is A2. For `PROT_READ`, `pread` writes into read-only memory and fails with `EFAULT`. If EOF is encountered, the fallback `memset` can fault directly. Valid read-only mappings therefore fail after being installed.
  - **Fix**: Avoid repopulating an already established native file mapping. For copied backing, populate writable staging or arena memory before applying final protections, with rollback on failure.

### Medium

- [ ] **M32-R2-9 — Medium — BUG — Real-time pending signals are coalesced**
  - **Where**: `src/os/signals.c:262-271` (`mips_signal_pend`), `src/os/signals.c:281-291` (`mips_signal_deliver_pending`)
  - **What breaks / Why**: Pending state stores one bit and one code per signal number. Repeated blocked real-time signals overwrite the same slot and produce one delivery. This violates the repository’s required FIFO handling of duplicate signals in the 32–128 namespace.
  - **Fix**: Add bounded per-thread real-time queues preserving each delivery and its information. Keep bit-based coalescing for standard signals.

- [ ] **M32-R2-10 — Medium — BUG — Syscall errno translation handles only ENOSYS**
  - **Where**: `src/os/syscalls.c:81-99` (`xerrno`, `mips_sc_ret`); `src/os/proc.c:72-87` (`proc_ret`)
  - **What breaks / Why**: Every host errno except `ENOSYS` passes through unchanged. MIPS has additional differences, including overflow and unsupported-operation errors; Darwin introduces further differences. Guests can receive an unrelated error number and choose the wrong recovery path.
  - **Fix**: Use one complete host-to-MIPS errno translation table, selected for the host platform, across all syscall return helpers.

- [ ] **M32-R2-11 — Medium — DEFECT — Interpreter header edits do not trigger incremental rebuilding**
  - **Where**: `Makefile:36-37` (`SRCS`, `HDRS`), `Makefile:66-68` (object rule)
  - **What breaks / Why**: Interpreter sources enter `SRCS`, but `src/interp/*.h` is absent from `HDRS`. The object rule does not generate compiler dependency files. Editing decoder or FP declarations can leave existing interpreter and DBT objects stale.
  - **Fix**: Generate and include compiler dependency files, or at minimum include interpreter headers in the declared dependencies.

## 2. Curated C11 & UB Issues

- [ ] **M32-R2-12 — High — C11 — Atomic generation counters do not protect root-context snapshots**
  - **Where**: `src/rt32/vm.c:110-131` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`), `src/rt32/vm.c:763-781` (`rt32_vm_sync_ctx`); `src/mips32rt.h:303-317` (`mips32_range_ok`)
  - **What breaks / Why**: A sibling VM operation directly writes the root context’s ordinary `regions`, `region_count`, and `vm_gen` fields. The root thread reads those fields without holding the VM lock. The atomic global generation neither makes those accesses atomic nor prevents concurrent modification during the region walk. This remains a C data race with potentially inconsistent permission decisions.
  - **Fix**: Stop writing another running thread’s snapshot. Refresh owner-thread snapshots under the VM lock, and protect every authoritative-region traversal with a consistent synchronization scheme.

- [ ] **M32-R2-13 — High — C11 — Signal guest-memory access still races with VM mutation**
  - **Where**: `src/os/signals.c:352-375` (`mips_sc_rt_sigaction`), `src/os/signals.c:605-627` (`mips_raise_guest_code`), `src/os/signals.c:719-740` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Signal paths check permissions, release any synchronization used by that check, then directly read or write guest pointers. A sibling can unmap or reprotect the range between validation and access. Frame construction uses raw `memset` and stores, so the translator can fault inside C rather than report a controlled guest-memory failure. The new lock-held copy helpers do not cover these paths.
  - **Fix**: Serialize frames and syscall structures into local buffers, then use the checked lock-held copy interfaces. Ensure complete range validation and copying occur under the same VM protection.

The targeted search found no direct banned string-function calls, `_Generic`, `<threads.h>`, or textual `.c` includes in the searched scope. This does not establish absence of every VLA, UB case, or encoded use of register 18.

## 3. DRY — Intra-Repo Duplication

- [ ] **M32-R2-14 — Low — DRY — Guest argument and return helpers remain duplicated**
  - **Where**: `src/os/proc.c:72-118` (`proc_ret`, `proc_arg`); `src/os/signals.c:196-232` (`l4a_arg`, `l4a_ret`); `src/os/syscalls.c:89-118` and `124-145` (`mips_sc_ret`, copy helpers, `mips_sc_arg`)
  - **What breaks / Why**: Three implementations encode the same O32 access and return conventions. They have already diverged: the shared argument helper uses locked copies and endian decoding, while the process helper uses a checked-then-raw native-endian `memcpy`.
  - **Fix**: Consolidate these helpers inside `mips32rt`, retaining module-specific behavior only where required. Do not introduce a cross-repository runtime library.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **M32-R2-15 — Low — YAGNI — COW state constants describe an unused state machine**
  - **Where**: `src/vm/vm32.h:89-93` (`MIPS32_PAGE_COW_CLEAN`, `MIPS32_PAGE_COW_DIRTY`)
  - **What breaks / Why**: The searched source contains these COW constants only as definitions; other matching mentions are comments. The population helper copies bytes, and the TLB miss helper installs tags without implementing the advertised clean-to-dirty state transition.
  - **Fix**: Remove unused state constants and speculative contracts, or implement the required state tracking with explicit consumers. Keep the documented contract aligned with the actual backing strategy.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M32-R2-16 — Low — CLEAN — File-backing comments claim nonexistent coherence machinery**
  - **Where**: `src/vm/vm_file.c:18-27`, `src/vm/vm_file.c:47-51`, and `src/vm/vm_file.c:95-101`
  - **What breaks / Why**: Comments claim family-shared backing, inode-keyed control state, resize generations, mutation hooks, and COW promotion. The implementation shown performs population and ordinary truncation without that machinery. These claims obscure the actual limitations identified above.
  - **Fix**: Replace the comments with the implemented behavior and explicit limitations. Track future coherence work in the existing backlog.

**File-size result:** No inventoried `.c`, `.h`, or `.S` exceeds 900 lines. `emit_int.c` is at 899 lines, `emit_fp.c` at 897, and interpreter `fp.c` at 893; these comply but leave little room for focused fixes.