# sparc32rt — static audit

**HEAD:** `816cc90c89294cdc827f8651c4140e8ce64fecf0`

**Inventory:** 66 C/header/assembly files under `src/` and `include/`, totaling **21,953 lines**. Including inspected test/experiment inventories: **28,530 lines**.

Six batched shell inspections covered specifications, source inventories, decoder/interpreter paths, DBT/cache management, VM/loader paths, backends, syscalls, threads, signals, futexes, and build declarations. No builds, compilers, QEMU, Docker, or test scripts were invoked. Findings are static conclusions, not runtime reproductions.

**Coverage limitation:** Some large reads were truncated. This is a bounded audit with verified locations, not exhaustive qualification of every instruction, FP operation, emitter, or test. No Critical finding was established.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 0 | 1 | 0 | 0 | 0 | 9 |
| Medium | 3 | 0 | 1 | 0 | 1 | 0 | 5 |
| Low | 0 | 0 | 0 | 1 | 0 | 3 | 4 |
| **Total** | **11** | **0** | **2** | **1** | **1** | **3** | **18** |

## 1. Bugs & Defects

### High

- [ ] **S32-1 — High — BUG — Syscall pointer checks accept inaccessible guest memory**
  - **Where**: `src/os/l2a_access.h:49-69` (`l2a_range_ok`, `l2a_store`); `src/os/futex.c:269-277` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: The shared check validates only arithmetic bounds and the low guard. It does not check mappings, guest permissions, or `TASK_SIZE`. Callers then use host `memcpy` or direct loads. An unmapped timeout pointer can fault the translator instead of returning `EFAULT`. On a 16 KiB host page, an inaccessible guest subpage can remain host-accessible, allowing forbidden reads or writes without any host fault.
  - **Fix**: Introduce checked copyin/copyout helpers that validate every guest page and required permission. Coordinate validation and access with concurrent mapping changes; arithmetic checks alone are insufficient.

- [ ] **S32-2 — High — BUG — Failed execve changes the running process**
  - **Where**: `src/os/threads_exec.c:137-161` (`sparc32_thr_execve`).
  - **What breaks / Why**: Signal dispositions are reset before even copying the pathname. An invalid pathname pointer therefore returns an error after destroying installed handlers. The VM reset also precedes opening/loading the new ELF, so later failures occur after image replacement has begun. All loader failures are additionally collapsed to `ENOENT`.
  - **Fix**: Copy arguments, open the executable, and validate/stage its image before committing process-state changes. Preserve the old image and dispositions for recoverable failures, and propagate the actual failure reason.

- [ ] **S32-3 — High — BUG — LDSTUB retains a process-wide lock across guest execution**
  - **Where**: `src/dbt/aot/aot_atomic.h:89-117` (`sparc32_atomic_ldstub`); `src/interp/interp_mem.c:109-115` (`interp_mem_wr`).
  - **What breaks / Why**: An exchange that reads zero retains `g_sparc32_ldstub_lock.owner` until a later matching guest store. Another thread executing `LDSTUB` on an unrelated address spins before performing its exchange. A thread holding lock A while waiting for work from a thread acquiring lock B can therefore deadlock despite the guest locks being independent. `LDSTUB` must complete as one atomic instruction, regardless of whether software later clears the byte.
  - **Fix**: Remove guest-critical-section ownership from the implementation. Use the atomic byte exchange itself, with the required memory ordering, and return its result immediately.

- [ ] **S32-4 — High — BUG — Guest stores do not invalidate translated code**
  - **Where**: `src/interp/interp_mem.c:96-117` (`interp_mem_wr`); `src/dbt/aot/aot_atomic.h:124-161` (`sparc32_atomic_swap`, `sparc32_atomic_casa`); `src/dbt/emit_priv.h:423-455` (`sparc32_rt_mem` store cases); `src/dbt/dbt.c:469-488` (`dbt_lookup`).
  - **What breaks / Why**: Ordinary helper stores and atomic writes modify guest memory without retiring translations. Routing a write to a code-bearing page through the slow helper does not repair this: the helper still performs only the write. `dbt_lookup` subsequently reuses the cached block without checking its source bytes. A modified RWX guest page can execute stale translated instructions.
  - **Fix**: Apply one intra-repository write-notification contract to interpreter stores, DBT slow stores, atomics, and syscall copyout. Retire affected translations and leave the current fragment safely before reclaiming executable storage.

- [ ] **S32-5 — High — BUG — A clone thread can unmap code executing in its parent**
  - **Where**: `src/dbt/dbt.c:114-121` (`dbt_arena_reset`), `src/dbt/dbt.c:491-517` (`dbt_flush`, `sparc32_dbt_invalidate_range`); `src/rt32/vm_mmap.c:311-327` (`rt32_vm_munmap`); `src/os/threads.c:410-443` (`thr_thread_entry`).
  - **What breaks / Why**: Cache invalidation immediately clears global cache entries and unmaps the global executable arena. Clone children run the interpreter but still dispatch mapping syscalls that invoke this invalidation. A child can therefore flush the arena while the parent executes JIT code. The VM lock does not protect execution or provide a cache-reclamation handshake.
  - **Fix**: Establish execution quiescence before changing arena protections or reclaiming code. Synchronize cache metadata and defer reclamation until all executing workers have left the retired generation.

- [ ] **S32-6 — High — BUG — Timed futex waits and wakes use different queues on AArch64 Linux**
  - **Where**: `src/os/futex.c:235-300` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: Wake and untimed wait use `SYS_futex`. Timed wait uses the kernel only when `SYS_futex_time64` exists; otherwise it enters the pthread-condvar emulator. On native 64-bit Linux, the ordinary futex syscall already supports native 64-bit timespecs. The fallback can consequently place timed waiters in a queue that the kernel wake operation never visits.
  - **Fix**: Use `SYS_futex` with a checked native `struct timespec` on 64-bit Linux. Select one compatible wait/wake backend for each address and operation family.

- [ ] **S32-7 — High — BUG — mremap loses file backing and shared-map identity**
  - **Where**: `src/rt32/vm_mmap.c:372-374`, `src/rt32/vm_mmap.c:395-417`, `src/rt32/vm_mmap.c:438-463` (`rt32_vm_mremap`).
  - **What breaks / Why**: The implementation derives anonymous mapping flags from the original region. Growth appends anonymous pages; relocation allocates anonymous memory and copies bytes. A file-backed `MAP_SHARED` mapping thereby loses its relationship to the file and other mappings. File-backed growth also produces zero-filled anonymous storage rather than the corresponding file contents.
  - **Fix**: Preserve backing-object identity, file offset, and sharing semantics through extension and relocation. Use a suitable host remap or backing-aware reconstruction; reject unsupported cases rather than silently changing their semantics.

- [ ] **S32-8 — High — BUG — Darwin subpage file mappings silently discard MAP_SHARED semantics**
  - **Where**: `src/os/backend_darwin.c:307-349` (`rt_host_map_file`).
  - **What breaks / Why**: When a fixed mapping is not host-page aligned, the function makes the containing pages writable, zeroes the requested range, and copies file bytes with `pread`. This branch ignores `shared`: it returns ordinary arena memory without a shared file mapping. Stores do not update the file or another alias of that file.
  - **Fix**: Implement backing-aware shared subpages with coherent aliases and writes, or explicitly reject unsupported shared mappings. Keep private-copy handling separate from shared-map handling.

### Medium

- [ ] **S32-9 — Medium — BUG — Signal frames omit mask preservation and restoration**
  - **Where**: `src/interp/interp_signal.c:202-208`, `src/interp/interp_signal.c:337-343` (signal-frame construction); `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Delivery writes zero to both saved-mask words. `rt_sigreturn` never reads those words or restores the effective guest mask. A handler changing its mask cannot reliably return to the interrupted mask, and editing the saved mask in the guest frame has no effect.
  - **Fix**: Save the effective pre-delivery mask in the ABI frame and restore it on signal return, removing unblockable signals and updating both guest-mask representations consistently.

- [ ] **S32-10 — Medium — BUG — Signal FPU state is hidden outside the guest ABI frame**
  - **Where**: `src/interp/interp_signal.c:66-67`, `src/interp/interp_signal.c:208-210`; `src/os/syscalls_sig.c:329-330`, `src/os/syscalls_sig.c:360-361` (`interp_delivery_sp`, frame construction, `sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Delivery saves FP state in a translator-private stack while placing a null FPU pointer in the guest frame. Return rejects every nonzero FPU-save pointer and restores the private snapshot. Guest handlers cannot inspect or modify the interrupted FP state through the specified signal ABI, and valid frames with an FP tail are rejected.
  - **Fix**: Serialize the specified FP tail into guest memory, set its guest pointer, and validate/restore that tail on return. Make guest-visible saved state authoritative.

- [ ] **S32-11 — Medium — BUG — Clone threads misclassify doubleword alignment faults**
  - **Where**: `src/os/threads.c:421-428` (`thr_thread_entry`); `src/interp/interp.c:449-474` (doubleword alignment handling).
  - **What breaks / Why**: Clone-thread fault delivery selects `SIGBUS` only when `fault_addr & 3` is nonzero. A doubleword access at an address congruent to four modulo eight fails the doubleword alignment check but is classified as `SIGSEGV`.
  - **Fix**: Carry an explicit fault class from the access implementation to delivery. At minimum, reuse the instruction-aware classification already described in `src/main.c:237-244`.

## 2. Curated C11 & UB Issues

- [ ] **S32-12 — High — C11 — Signed shifts make normal branch and division decoding undefined**
  - **Where**: `src/interp/decode.c:343-364` (`sparc32_decode_word`); `src/interp/interp.c:275`, `src/interp/interp.c:304` (signed-dividend construction).
  - **What breaks / Why**: Branch/call displacements are sign-extended to `int32_t` and then left-shifted. Shifting a negative value is undefined in C11, affecting backward transfers. Signed division similarly shifts a negative sign-extended `%y` left by 32. These are ordinary guest inputs, not merely malformed instructions.
  - **Fix**: Shift unsigned bit patterns and perform explicit signed interpretation afterward. For dividend construction, multiplying the signed high word by `INT64_C(4294967296)` and adding the unsigned low word avoids shifting a negative value.

- [ ] **S32-13 — Medium — C11 — Futex timeout saturation still permits signed overflow**
  - **Where**: `src/os/futex.c:113-123` (`sparc32_futex_wait_emu`).
  - **What breaks / Why**: Relative durations are capped at approximately `9 × 10^18` nanoseconds, but current epoch time is then added without checking remaining `INT64_MAX` headroom. A very large valid timeout overflows the signed deadline calculation.
  - **Fix**: Use checked or saturating addition against `INT64_MAX - now`, and check representability when converting to the host `time_t`.

No over-900-line file was found in the inspected inventory. The targeted production-source search found no banned `sprintf`/`strcpy`/`strcat`/`atoi` calls or textual `.c` includes. Visible `x18` matches were comments; this does not constitute exhaustive verification of encoded register operands.

## 3. DRY — Intra-Repo Duplication

- [ ] **S32-14 — Low — DRY — Signal-return functions duplicate register restoration**
  - **Where**: `src/os/syscalls_sig.c:263-312` (`sparc32_sys_sigreturn`); `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Both functions duplicate frame reads, register loops, zero-register restoration, stack-state cleanup, and FP restoration. Their differing PC offsets are legitimate, but the repeated commit logic makes fixes to mask handling, validation, and nested delivery easy to apply inconsistently.
  - **Fix**: Keep ABI-specific parsing separate, then pass validated state to one internal restore routine. Keep this helper inside `sparc32rt`.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S32-15 — Medium — YAGNI — Soft-TLB miss machinery is disconnected from production callers**
  - **Where**: `src/vm/vm32.c:87-101` (`t_tlb`, `vm32_tlb_reset_thread`), `src/vm/vm32.c:268-336` (`vm_tlb_miss_helper`), `src/vm/vm32.c:339-364` (`vm32_tlb_invalidate`).
  - **What breaks / Why**: The production-source reference search found the miss helper only at its definition. The thread-local TLB is private to this file, while active access paths use the published protection table and G-window accesses. The unused miss/fill subsystem nevertheless carries invalidation work and comments describing an active Soft-TLB/quiescence design.
  - **Fix**: Either connect and verify the intended TLB path, or remove the disconnected machinery and document the protection-table implementation actually used. Do not retain an unconnected subsystem as evidence that A2 access handling is complete.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S32-16 — Low — CLEAN — Memory-access comments contradict current alignment handling**
  - **Where**: `src/interp/interp_mem.c:67-72`; `src/interp/interp_signal.c:20-33`.
  - **What breaks / Why**: Comments describe doubleword alignment as an unresolved Phase-3 gap and claim misaligned data accesses are emulated rather than delivered as signals. Current integer paths explicitly check doubleword alignment, and ordinary memory helpers reject misalignment. These comments misdirect future fault-handling work.
  - **Fix**: Describe the present split between instruction-specific alignment checks, generic access helpers, and signal classification. Move historical phase notes out of active contracts.

- [ ] **S32-17 — Low — CLEAN — Default build flags omit the required general warning gate**
  - **Where**: `Makefile:29-33` (`CFLAGS`).
  - **What breaks / Why**: Defaults include `-Werror=vla` but omit general `-Werror`, contrary to the project’s non-negotiable warning policy. Other enabled diagnostics can therefore leave the default build successful.
  - **Fix**: Include `-Werror` in the project’s default compilation flags and keep the Darwin build configuration consistent.

- [ ] **S32-18 — Low — CLEAN — Three core files have almost no line-limit headroom**
  - **Where**: `src/dbt/dbt.c:1-888`; `src/os/threads.c:1-883`; `src/dbt/emit_int.c:1-882`.
  - **What breaks / Why**: These files remain compliant but have only 12, 17, and 18 lines of headroom respectively. Correctness fixes identified above will likely exceed the ceiling if added directly.
  - **Fix**: When addressing those fixes, extract coherent private units—for example arena lifecycle or thread fault delivery—rather than compressing code or introducing textual `.c` includes.