# mips32rt — Static Audit Report

**HEAD:** `e0b10a2671f1c8fd6952a375dabff7a73a136d0c`

**Scope:** Seven batched, read-only shell inspections. Inventoried **53 production `.c`/`.h`/`.S` files totaling 20,182 lines**; including tests and experiments, the inventory totals **26,819 lines**. Examined interpreter/decoder, DBT, VM, syscall, signal, threading, loader, and backend code, plus build declarations.

No builds, compilers, QEMU, Docker, or tests were intentionally invoked. Git’s macOS launcher emitted Xcode/cache diagnostics. Some large inspection outputs were truncated, so this is a bounded static audit, **not exhaustive verification of every module or ISA operation**. Findings below cite source actually inspected; runtime reproduction remains unperformed.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 9 | 0 | 2 | 0 | 0 | 0 | 11 |
| Medium | 2 | 0 | 1 | 1 | 1 | 1 | 6 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **11** | **0** | **3** | **2** | **2** | **2** | **20** |

Severity reflects potential impact established by source analysis, not demonstrated exploitation. All consolidation recommendations are **within mips32rt**; its standalone repository architecture is preserved.

## 1. Bugs & Defects

### High

- [ ] **M32-1 — High — BUG — FP branch fault handling overwrites the delivered signal handler PC**
  - **Where**: `src/interp/fp.c:829-843` (`fp_bc1`); `src/os/signals.c:673-682` (`mips_raise_guest_code`)
  - **What breaks / Why**: A delay-slot instruction can fault and synchronously deliver a guest handler, which installs the handler PC and clears `exit_reason`. When `interp_step` returns `MIPS_FAULT`, `fp_bc1` overwrites that PC with the original branch PC. Execution retries the branch instead of entering the handler. The preliminary delay-slot fetch also occurs before delay-slot bookkeeping is installed.
  - **Fix**: Establish delay-slot state before fetching, and preserve the context produced by fault delivery. Use one branch/delay-slot execution helper for integer and FP branches.

- [ ] **M32-2 — High — BUG — Failed execve destroys the calling program**
  - **Where**: `src/os/proc.c:384-412` (`mips_proc_execve`)
  - **What breaks / Why**: Opening the pathname is the only precondition checked before `rt32_vm_reset_for_exec` destroys the old image. Invalid ELF contents, a failed interpreter load, or stack allocation failure then return an errno into an already destroyed address space. For example, executing an existing non-ELF file cannot safely return `ENOEXEC`.
  - **Fix**: Validate the executable and interpreter and prepare replacement state before committing image destruction. Failures after an irreversible commit must terminate appropriately rather than resume the old image.

- [ ] **M32-3 — High — BUG — Darwin sub-page MAP_SHARED mappings lose sharing**
  - **Where**: `src/rt32/vm_mmap.c:96-126` (`vm_mmap2_locked`)
  - **What breaks / Why**: Mappings that fail the 16 KiB alignment conditions use `mprotect`, `memset`, and `pread` into existing arena storage. This path also handles `MAP_SHARED`, but creates no shared file mapping or coherent shared backing. Guest stores therefore need not reach the file or other mappings. A negative `pread` result is also silently treated like EOF.
  - **Fix**: Implement coherent backing for sub-page shared mappings, retaining file identity and offsets. Propagate population errors and roll back failed mappings.

- [ ] **M32-4 — High — BUG — mremap replaces file-backed memory with anonymous storage**
  - **Where**: `src/rt32/vm_mmap.c:310-338` and `src/rt32/vm_mmap.c:372-393` (`rt32_vm_mremap`)
  - **What breaks / Why**: Both extension and relocation construct anonymous mappings. Growing a file mapping supplies anonymous zero pages instead of subsequent file contents; moving a shared file mapping copies its bytes into anonymous storage and disconnects future writes from the file and its aliases.
  - **Fix**: Retain backing-object and offset metadata. Preserve that backing during extension and relocation, using native remapping where possible and an equivalent backing-aware implementation otherwise.

- [ ] **M32-5 — High — BUG — Translation invalidation misses sibling threads**
  - **Where**: `src/dbt/dbt.c:100-105`, `src/dbt/dbt.c:328-394`, and `src/dbt/dbt.c:428-435` (`dbt_cache`, `dbt_smc_bump`, `mips32_dbt_invalidate_range`, `dbt_lookup_bi`)
  - **What breaks / Why**: Code caches and SMC versions are thread-local. A thread modifying or unmapping executable guest memory invalidates only its own cache. A sibling sharing the guest VM can keep accepting its unchanged cached version and execute obsolete translations, including after executable permission is removed.
  - **Fix**: Maintain shared address-space code generations and make every cache/chaining path observe them. Coordinate invalidation with running sibling threads.

- [ ] **M32-6 — High — BUG — Full SMC table silently drops invalidations**
  - **Where**: `src/dbt/dbt.c:328-359` (`dbt_smc_bump`); `src/dbt/dbt.c:374-394` (`mips32_dbt_invalidate_range`)
  - **What breaks / Why**: When every SMC slot is occupied and the requested page is absent, `dbt_smc_bump` returns without recording the modification. Repeated small invalidations can fill the table without triggering the large-range flush. A cached translation for a subsequent page can retain version 1 and remain valid after modification.
  - **Fix**: Flush the cache on insertion failure, or use a generation structure with explicit capacity handling. Never silently discard an invalidation.

- [ ] **M32-7 — High — BUG — Region-table exhaustion changes permissions outside the requested range**
  - **Where**: `src/rt32/vm.c:269-295` (`vm_mprotect_regions_locked`); `src/rt32/vm_mmap.c:200-210` (`vm_mprotect_locked`)
  - **What breaks / Why**: If a region cannot be split, the metadata fallback applies the new protection to the entire original region. The host protection operation covered only the requested range. Metadata and host mappings diverge; on A2, where software permissions are essential, neighboring guest pages can acquire unintended access.
  - **Fix**: Reserve all required region entries before changing host protections. Return an allocation error without mutation if the split cannot be represented.

- [ ] **M32-8 — High — BUG — Blocked signals are delivered immediately**
  - **Where**: `src/os/signals.c:386-444` (`mips_l4a_rt_sigprocmask`); `src/os/kill.c:151-178` (`mips_sc_kill`)
  - **What breaks / Why**: `rt_sigprocmask` records a mask, but self-signal delivery neither tests it nor queues blocked signals. A blocked signal with a handler enters that handler immediately. There is no corresponding pending-signal delivery step when the mask is relaxed.
  - **Fix**: Implement per-thread pending state, mask-aware delivery, and FIFO queuing for real-time signals. Deliver eligible pending signals at defined execution boundaries.

- [ ] **M32-9 — High — BUG — CLONE_VM children retain stale mapping metadata**
  - **Where**: `src/os/threads.c:315-329` (`mips_sc_clone`); `src/rt32/vm.c:107-126` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`); `src/os/syscalls.c:116-132` (`mips_sc_range_ok`)
  - **What breaks / Why**: Clone copies the region table into the child context. Subsequent VM operations synchronize only the calling context and the root context, not every existing child. A child can reject a newly mapped valid pointer or accept an unmapped/reprotected pointer using stale metadata.
  - **Fix**: Share authoritative VM metadata across contexts, or version snapshots and refresh them under synchronization before access validation.

### Medium

- [ ] **M32-10 — Medium — BUG — Integer branch-likely fetches an annulled delay slot**
  - **Where**: `src/interp/interp.c:775-789` (`exec_branch`); `src/dbt/dbt.c:609-612` (`dbt_compile`)
  - **What breaks / Why**: A not-taken branch-likely explicitly fetches `pc + 4`. At a page boundary this can fault on an unmapped annulled slot, contrary to the repository’s explicit no-fetch contract. DBT page-final fallback reaches the same interpreter behavior.
  - **Fix**: Advance directly to `pc + 8` without fetching the annulled slot. Reconcile the contradictory implementation comment and associated oracle expectations with the authoritative contract.

- [ ] **M32-11 — Medium — BUG — Default signal handling treats stop and ignore actions as process exit**
  - **Where**: `src/os/kill.c:70-80` (`kill_die`), `src/os/kill.c:147-155` (`mips_sc_kill`)
  - **What breaks / Why**: `SIGSTOP` explicitly calls `kill_die`, which exits instead of stopping. Other unhandled signals also follow the death path without distinguishing default-ignore, continue, and terminate actions. `_Exit(128 + signo)` additionally produces a normal exit status rather than signal termination.
  - **Fix**: Implement the MIPS default-action table and preserve stop/continue/termination semantics in guest-visible wait status.

## 2. Curated C11 & UB Issues

- [ ] **M32-12 — High — C11 — Signal state has unsynchronized cross-thread access**
  - **Where**: `src/os/signals.c:123-129`, `src/os/signals.c:342-378`, `src/os/signals.c:655-666`, and `src/os/signals.c:732-773`
  - **What breaks / Why**: Dispositions, blocked masks, frame addresses, and nesting depth are ordinary process-global objects accessed by guest threads without synchronization. Concurrent access causes C data races. Independently of UB, one thread’s `sigreturn` can truncate another thread’s frame bookkeeping through the shared `g_depth`.
  - **Fix**: Move masks and frame bookkeeping into per-thread contexts. Protect process-wide dispositions with a defined synchronization protocol and take consistent snapshots for delivery.

- [ ] **M32-13 — High — C11 — Guest copy helpers race VM changes and can crash the host**
  - **Where**: `src/os/syscalls.c:136-155` (`mips_sc_copy_from`, `mips_sc_copy_to`); `src/rt32/vm.c:113-125` (`vm_copy_state_to_ctx`); `src/os/hostfault.c:104-110` (`hf_handler`)
  - **What breaks / Why**: Helpers inspect ordinary region metadata and then perform unguarded `memcpy`. Concurrent VM operations can rewrite that metadata or remove access between validation and copying. Metadata access races are UB; an ensuing fault in libc/C code is outside the JIT pool and is not converted to guest `EFAULT`.
  - **Fix**: Introduce synchronized, fault-safe guest copy operations. Pin or otherwise stabilize mappings for the copy duration, with a recovery mechanism covering helper faults.

- [ ] **M32-14 — Medium — C11 — Fault-PC range check compares unrelated pointers**
  - **Where**: `src/os/hostfault.c:106-108` (`hf_handler`)
  - **What breaks / Why**: `pc < hf_pool` performs a relational pointer comparison even when the fault PC belongs to an unrelated object or mapping. This is outside portable C’s defined pointer-ordering rules. The other bound already uses integer addresses.
  - **Fix**: Convert both endpoints to `uintptr_t` and perform an overflow-safe integer range test consistently.

## 3. DRY — Intra-Repo Duplication

- [ ] **M32-15 — Medium — DRY — Guest range validation is independently copied across syscall modules**
  - **Where**: `src/os/syscalls.c:102-133` (`mips_sc_range_ok`); `src/os/proc.c:91-124` (`proc_range_ok`); `src/os/signals.c:172-205` (`l4a_range_ok`)
  - **What breaks / Why**: Three implementations repeat the sorted-region walk and permission checks, with differing null/zero-length behavior. Fixes for shared metadata, overflow handling, and mapping lifetime must be applied independently.
  - **Fix**: Provide one repository-local VM validation/copy interface with explicit zero-length semantics. Keep module-specific argument marshaling separate.

- [ ] **M32-16 — Low — DRY — Host backends duplicate identical POSIX wrappers**
  - **Where**: `src/os/backend_linux.c:348-420`; `src/os/backend_darwin.c:338-410` (`mips32_host_close`, read/write, positional I/O, seek, truncate)
  - **What breaks / Why**: These wrappers repeat effectively identical bodies, including ignored worker-synchronization parameters. Future cancellation or error-handling changes can drift between backends.
  - **Fix**: Place genuinely identical POSIX implementations in a common module inside mips32rt. Retain platform-specific flag and ABI conversion in each backend.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **M32-17 — Medium — YAGNI — File-family tracking consumes resources without enforcing its advertised coherence**
  - **Where**: `src/vm/vm_file.c:55-73`, `src/vm/vm_file.c:110-129`, and `src/vm/vm_file.c:175-228`
  - **What breaks / Why**: The “shared across fork” table is actually static process storage. Retained duplicated descriptors have no release path in this module, while resize/code-generation updates have no VM consumers in the inspected source references. `mips32_file_check_truncate` has no source caller. The tracking therefore does not implement the documented cross-process shrink/regrow behavior.
  - **Fix**: Either connect this state to actual mapping lifecycle and coherence enforcement, with shared allocation and descriptor cleanup, or remove inactive tracking and narrow the claimed behavior.

- [ ] **M32-18 — Low — YAGNI — Unused branch classifier suppresses its own warning**
  - **Where**: `src/dbt/dbt.c:146-163` (`dbt_is_likely`)
  - **What breaks / Why**: This static helper has no caller and is explicitly marked `unused`. It duplicates branch-likely classification already performed elsewhere, adding another definition that can drift.
  - **Fix**: Remove it or make one complete decoder classifier authoritative for active callers.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M32-19 — Medium — CLEAN — Two test sources violate the line limit and evade its check**
  - **Where**: `tests/test_p1_isa.c:1-1030`; `tests/test_p3_fpu.c:1-1164`; `Makefile:89-96` (`check-line-limits`)
  - **What breaks / Why**: The files contain 1,030 and 1,164 lines respectively, exceeding the required 900-line maximum. The check searches only `src` and `include`, yet prints that every source satisfies the limit. Production files `emit_int.c` and `emit_fp.c` already sit exactly at 900 lines.
  - **Fix**: Split the oversized tests into ordinary translation units and extend the check to all applicable repository sources. Do not use textual `.c` inclusion.

- [ ] **M32-20 — Low — CLEAN — Default build flags omit required global Werror**
  - **Where**: `Makefile:21` (`CFLAGS`); `Makefile:44` (`DARWIN_CFLAGS`)
  - **What breaks / Why**: Both defaults include `-Werror=vla` but omit `-Werror`, despite the project’s explicit strict-warning invariant. Other enabled warnings can therefore pass the default build.
  - **Fix**: Add `-Werror` to both default flag sets and keep target-specific exceptions explicit.

The highest-priority repairs are signal-state ownership, VM metadata/copy synchronization, cross-thread translation invalidation, and transactional `execve`. No Critical finding was established within this inspection budget.