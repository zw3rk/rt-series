# Round-9 Deep-Dive 3: VM + ELF/Stack/Auxv Loader Static Audit

Read-only audit. No files modified, nothing built or run. Every file below was read line-by-line.

## Summary

| ID | Area | Severity |
|---|---|---|
| LA64-R9-1 | interp store commit NULL deref | High |
| LA64-R9-2 | Multi-VMA span spurious EFAULT | Med |
| LA64-R9-3 | brk shrink keeps stale bytes | Med |
| LA64-R9-4 | Copyouts skip LL invalidation | Med |
| LA64-R9-5 | Staged-shared fork incoherence | Med |
| LA64-R9-6 | load_elf address overflow | Med |
| LA64-R9-7 | Ignored vmfile_unmap failure | Low |
| LA64-R9-8 | File-layer writes skip SMC | Low |
| LA64-R9-9 | execve keeps arena/file state | Low |
| LA64-R9-10 | munmap at VA 0 wrong error | Low |
| LA64-R9-11 | Wrong errno for O_WRONLY mmap | Low |

### LA64-R9-1: `st_bytes` commit loop dereferences unchecked NULL

[interp_mem.h](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:132) re-resolves each byte with `la64_mem_ptr` and stores without a NULL check. The pre-check loop above it holds `store_lock`, but `munmap`/`mprotect` take a different lock (`g_vm_mutation_lock`), so a concurrent guest thread unmapping the page between the two loops turns the commit store into a host NULL deref (crash), where `ld_bytes` and `amo_st` in the same subsystem fail cleanly with guest `SIGSEGV`.

Repro: thread 1 loops a multi-byte store to page P; thread 2 loops `munmap(P)`/`mmap(P)`.

Fix: mirror the pre-check — on NULL, unlock, deliver `SIGSEGV`/`MAPERR`, return.

### LA64-R9-2: Single-pointer lookup fails across adjacent VMAs

[mem_min.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:420) requires contiguous host backing for multi-region spans (`h != prev_end` returns NULL). Separate `mmap` calls get unrelated host addresses, so any syscall buffer spanning two adjacent guest VMAs (e.g. `write(fd, base+2048, 4096)` across two 4 KiB maps, or a buffer ending at the stack top crossing into the trampoline page) returns spurious `-EFAULT`. Linux copies across VMAs.

Fix: chunk host-side I/O per containing region instead of demanding one pointer.

### LA64-R9-3: `brk` shrink does not discard bytes

[mem_min.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:778): shrinking only lowers `brk_cur`; the heap region and bytes persist, and regrowth `memcpy`s the stale tail back. Write at P, shrink below P, grow above P: guest reads the old byte where Linux yields zero.

Fix: on shrink, zero `[addr, brk_cur)` and invalidate translations.

### LA64-R9-4: Host-side copyouts never invalidate LL reservations

Every guest-store path in `interp`/`dbt` calls `la64_clone_invalidate_ll`, but none of the ~15 host-side copyout sites do: `sys_read`/`pread`/`readv`/`getrandom`/`getdents64`/`uname`/`ioctl`/`statx`/`clock_gettime`/`wait4`/`waitid`/`pipe2`/clone tid stores ([syscalls_file.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_file.c:234), [syscalls.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls.c:136), [minsys.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:184), [clone.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:181)), nor signal-frame setup ([sigframe.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:200)) or [proc.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/proc.c:349). Thread 1 `LL`s address A; thread 2 `read(fd, A, 4)`; thread 1 `SC` succeeds though a write intervened.

Fix: call `la64_clone_invalidate_ll(NULL, va, len)` after each copyout commits.

### LA64-R9-5: Staged `MAP_SHARED` goes private across `fork`

Unaligned (on 16 KiB Darwin hosts: 4 KiB-aligned but not 16 KiB-aligned) shared file maps fall to the staged anonymous path ([vm_file.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:515)). Host `fork` duplicates anonymous pages privately, and propagation tables are process-private, so post-fork stores in one process never reach the other. Linux keeps `MAP_SHARED` shared across fork. Aligned direct overlays are unaffected, so this bites on Darwin/16 KiB hosts, not Linux/4 KiB.

Fix: back staged-shared maps with shared memory or fault them on writeback post-fork.

### LA64-R9-6: `load_elf` has no address-overflow checks

[loader.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:365): `va = bias + p_vaddr`, `map_len` rounding (line 376), and `va + memsz` (line 429) can wrap. A crafted ELF with `p_vaddr` near `2^64 - LA64_INTERP_BIAS` wraps to a low VA and loads where Linux refuses, instead of failing cleanly. `read_at` already checks `off + done` wrap; these three sites do not.

Fix: reject on `bias > UINT64_MAX - p_vaddr` (and the two analogous checks).

### LA64-R9-7: `munmap`/`MAP_FIXED` ignore `vmfile_unmap` `-ENOMEM`

[syscalls_mem.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:308) and `sys_munmap_range` (line 430) discard the return value. On middle-split slot exhaustion ([vm_file_sync.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:808)), the record survives while its backing is freed; a later truncate/msync then touches freed host memory.

Fix: propagate the error and skip the backing teardown on failure.

### LA64-R9-8: File-layer byte mutations bypass the SMC epoch

Staged propagation `memcpy` ([vm_file_sync.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:206)), clean-map refresh (line 302), discard refill (line 378), and `pwrite`-triggered refresh write guest bytes without `dbt_smc_store`. The originating store reports only its own range, so an executable alias at a different GVA keeps stale translations.

Fix: `dbt_smc_store` the destination range in each of the four paths (it self-gates on code pages).

### LA64-R9-9: `execve` does not reset arena/file state

`sys_execve` → `la64_load` calls only `la64_mem_init`; `vm64` pages and `vmfile` records from pre-execve low `MAP_FIXED`/file maps survive. Since `la64_mem_ptr` probes the arena first, stale ownership shadows later mappings (`MAP_FIXED_NOREPLACE` spuriously reports `EEXIST`).

Fix: unmap the full arena window and reset the file tables in `la64_load` before mapping the new image.

### LA64-R9-10: `munmap(0, len)` returns `EINVAL`, Linux returns 0

`split_at` rejects `va == 0` ([mem_min.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:262)), and `la64_mem_unmap` propagates it. Address 0 is always a region boundary and no region can start below it, so the split is a valid no-op.

Fix: `if (va == 0) return 0;` at the top of `split_at`.

### LA64-R9-11: Private read map of O_WRONLY fd yields `EBADF`, Linux yields `EACCES`

`sys_mmap` checks writability only for `MAP_SHARED|PROT_WRITE`; a `MAP_PRIVATE|PROT_READ` map of an O_WRONLY fd proceeds into `map_bytes_in_place`, where `pread` fails with `EBADF`.

Fix: in `sys_mmap`, return `-EACCES` when the map needs read rights and the fd lacks them.

## Files with 0 bugs (explicit)

`vm64.h`, `vm64_dispatch.c`, `vm_file.h`, `vm_file_int.h`, `loader.h`, `core/cpu.h`, `os/mem_min.h`, `os/page_rules.c`, `os/page_rules.h`, `os/syscalls_priv.h`, `dbt/dbt_smc.c`, `dbt/dbt_mem.c`, `interp/interp_amo.c`, `os/syscalls_file.c`, `main.c`, `os/clone.c`, `src/vm/vm64.c` (live paths; see notes).

## Scope notes (not bugs)

- `mremap` (nr 216) and `madvise` (nr 233) dispatch to `-ENOSYS`. SPEC/GOAL require only `brk`/`mmap`/`munmap`/`mprotect`; musl tolerates both as non-fatal. No ID.
- `copy_from_guest`/`copy_to_guest`/`copy_str_from_guest` do not exist under those names. Equivalents (`la64_mem_ptr` + `range_ok`, `copy_guest_string`, `copy_guest_dup`/`vec`) all check `-EFAULT` and wrap (`va+i < va`, `len > TASK_SIZE - va`, guarded `count*16`). Per-byte interp loops fault on the first byte, so wrap is unreachable there. No ID.
- `family_mm`/`family_shmem` and MAP_PRIVATE downgrade machinery do not exist. The analogs — host-`fork` COW (correct for private, correct for direct shared overlays), `vmfile` refcounts, in-place COW promotion — are sound; gaps are R9-5/R9-9. `vmfile_fork_reserve`/`parent_done` have no callers; the single-threaded fork gate makes the child fallback path correct, just unoptimized.
- Dead code, not behavioral: `vm_tlb_miss_helper`, `vm64_ll_record`, `vm64_ll_check` have no callers (live LL/SC is the `clone.c` invalidation protocol, verified correct under `store_lock`). `vm64_unmap`'s manual tag loop is redundant with its commit flush, harmless.
- Loader admission verified correct: `EM_LOONGARCH == 258`, `(e_flags & 7) == 3` LP64D, BSS zeroing, 16-byte `sp` alignment, `AT_PHDR/PHENT/PHNUM/PAGESZ/ENTRY/BASE/HWCAP/RANDOM/EXECFN` with exact 16/18-row auxv accounting.
