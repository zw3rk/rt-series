# sparc64rt Round-9 Deep-Dive 3: VM / 8 KiB Pages / Copy / fork / ELF Loader

Read-only audit. No files created, modified, or executed.

## Summary

| ID | Area | Location | Impact |
|---|---|---|---|
| S64-R9-1 | Stack 8K align | `guest_stack.c:33` | Misaligned VMA |
| S64-R9-2 | brk TLB | `guest_run.c:205` | Stale TLB / UAF |
| S64-R9-3 | SMC flush | `guest_run_mem.c:63` | Stale DBT code |
| S64-R9-4 | mremap check | `guest_run_sysmem.c:583` | Missing EFAULT |
| S64-R9-5 | NOREPLACE | `guest_run_sysmem.c:232` | Wrong overlap |
| S64-R9-6 | madvise | `syscalls_min.c:621` | Spurious ENOSYS |
| S64-R9-7 | Prot truncation | `syscalls_min.c:625` | High bits lost |
| S64-R9-8 | fork threads | `proc.c:146` | Ghost threads |

### S64-R9-1: `GUEST_STACK_TOP` is 4 KiB-aligned, not 8 KiB-aligned

`src/os/guest_stack.c:33`:

```c
#define GUEST_STACK_TOP UINT64_C(0x7ffffffff000)
```

`0x7ffffffff000 & 0x1fff == 0x1000`. The ABI granule is 8192 (`src/os/guest_run_priv.h:48`). The stack mapping in `build_stack_core` (`src/os/guest_stack.c:243-251`) is therefore `[TOP-8M, TOP)`, whose base `0x7ffff7fff000` and top are both mid-8 KiB. The enclosing 8 KiB pages straddle mapped/unmapped 4 KiB halves. A later 8 KiB `mprotect`/`munmap`/`mremap` over either edge sees a half-hole. Same shape in `src/os/threads.c:94`:

```c
uint64_t stack_top = SPARC64_TASK_SIZE - SPARC64_PAGE_SIZE;
```

Repro: map the stack, then `mprotect(stack_base, 8192, PROT_READ)` where `stack_base` is the loader base. The 8 KiB page's lower half is unmapped, so the call fails or splits incorrectly although the stack is live.

Fix: use an 8 KiB-aligned top in both places:

```c
#define GUEST_STACK_TOP UINT64_C(0x7fffffffe000)
uint64_t stack_top = SPARC64_TASK_SIZE - UINT64_C(8192);
```

### S64-R9-2: `brk` growth/shrink never invalidates the Soft-TLB

`src/os/guest_run.c:189-219`, specifically `src/os/guest_run.c:205-217`:

```c
if (target > cur) {
    if (!sparc64_space_map(...)) ...
} else if (target < cur) {
    (void)sparc64_space_unmap(...);
}
g->brk_cur = addr;
if (g->dbt != NULL && target != cur) {
    sparc64_dbt_invalidate(g->dbt, 0U, SPARC64_TASK_SIZE);
}
```

The DBT is flushed but `sparc64_tlb_invalidate_gva` is not called. Shrink frees heap backings while live `sparc64_dbt_tlb` entries still carry `addend` pointers at the freed bytes. The next fast-path load hits the stale tag and reads freed heap instead of faulting `UNMAPPED`.

Repro: `brk` up one page, touch it to fill the TLB, `brk` down, touch the same VA. Expected fault; observed stale bytes.

Fix: invalidate the precise delta next to the DBT flush:

```c
sparc64_tlb_invalidate_gva(cur, target - cur);   /* grow */
sparc64_tlb_invalidate_gva(target, cur - target); /* shrink */
```

### S64-R9-3: Guest writes to `PROT_EXEC` pages do not invalidate cached code

`src/os/guest_run_mem.c:63-79` (`guest_mem_write`) and `src/os/guest_run_sysmem.c:79-93` (`sparc64_sysmem_write`):

```c
if (!sparc64_space_write(&g->space, va, host, (size_t)len))
    return false;
sysmem_file_note_write(g, va, len);
return true;
```

` sparc64_space_write` bumps the substrate `generation`, but the DBT consults only `dbt->epoch` plus per-page versions (`src/dbt/dbt.c:613-614`, `src/dbt/emit_rt.c:51-56`). Nothing here calls `sparc64_dbt_invalidate`, `sparc64_tlb_evict_writes`, or `vm64_code_epoch_bump`. Mapping paths do all three; the write path does none.

Repro: run a block under DBT so `page_has_code` is true, store new bytes to that page through the interpreter slow path, execute again. The DBT lookup still hits the old `page_version`/`epoch` and runs stale bytes.

Fix: after a successful write, evict and invalidate the written span:

```c
sparc64_tlb_evict_writes(va, (uint64_t)size);
if (g->dbt != NULL)
    sparc64_dbt_invalidate(g->dbt, va, (uint64_t)size);
vm64_code_epoch_bump();
```

Apply in both write bridges, including the atomic mutating path.

### S64-R9-4: `mremap` same-size shortcut skips source validation

`src/os/guest_run_sysmem.c:583-585`:

```c
if (new_len == old_len && (flags & SYSMEM_MREMAP_FIXED) == 0U) {
    return (long)old_addr;
}
```

No `sysmem_span_perms` check runs. An unmapped `old_addr` returns success instead of `-EFAULT`. Every other leg (FIXED, grow, relocate, free-tail extend) validates coverage first.

Repro: `mremap(unmapped_8k, 8192, 8192, 0)` returns the address instead of `-EFAULT`.

Fix:

```c
if (new_len == old_len && (flags & SYSMEM_MREMAP_FIXED) == 0U) {
    if (!sysmem_span_perms(g, old_addr, old_len, &perms))
        return -EFAULT;
    return (long)old_addr;
}
```

### S64-R9-5: `MAP_FIXED_NOREPLACE` and unknown `MAP_*` bits are silently ignored

`src/os/guest_run_sysmem.c:232-236`:

```c
if (((flags & (SYSMEM_MAP_PRIVATE | SYSMEM_MAP_SHARED)) == 0U) ||
    ((flags & (SYSMEM_MAP_PRIVATE | SYSMEM_MAP_SHARED)) ==
     (SYSMEM_MAP_PRIVATE | SYSMEM_MAP_SHARED))) {
    return -EINVAL;
}
```

Only the PRIVATE/SHARED pair is checked. Any other bit passes. In particular `MAP_FIXED_NOREPLACE` (`0x100000U` on Linux, no `0x10` bit) falls into `sysmem_resolve_base` (`src/os/guest_run_sysmem.c:150-157`) as a non-fixed hint, so an overlapping NOREPLACE request succeeds at a different address instead of failing with `-EEXIST`.

Repro: map one page, then `mmap(same_addr, 8192, PROT_READ, PRIVATE|ANONYMOUS|0x100000, -1, 0)`. Expected `-EEXIST`; observed new address.

Fix: whitelist known bits and implement the overlap arm:

```c
#define SYSMEM_MAP_FIXED_NOREPLACE 0x100000U
if ((flags & ~(0x01U|0x02U|0x10U|0x20U|0x100000U)) != 0U)
    return -EINVAL;
if ((flags & SYSMEM_MAP_FIXED_NOREPLACE) != 0U) {
    if (!sysmem_span_free(g, addr, size))
        return -EEXIST;
    /* proceed as non-fixed placement at addr */
}
```

### S64-R9-6: `madvise` is unimplemented

`src/os/syscall_nr.h:100` declares `X(75, madvise)`, but `src/os/syscalls_min.c:621-638` dispatches only `brk`/`mmap`/`munmap`/`mprotect`/`mremap`/`truncate`. `madvise` falls to `default: ret = -ENOSYS` (SPARC `ENOSYS` 90). Static libc startup and allocators issue `madvise`; several benign advices must succeed.

Repro: `madvise(mapped_8k, 8192, MADV_DONTNEED)` returns `-ENOSYS` instead of `0`.

Fix: add a narrow handler that validates the 8 KiB range and accepts benign advices:

```c
case (long)SPARC64__NR_madvise:
    ret = sparc64_sysmem_madvise(mem->context, o0, o1, (unsigned)o2);
    break;
```

with `0` for `NORMAL/RANDOM/SEQUENTIAL/WILLNEED/DONTNEED/DONTFORK`, `-EINVAL` otherwise.

### S64-R9-7: `prot`/`flags` are truncated to 32 bits before validation

`src/os/syscalls_min.c:625-627,631-633,636-637`:

```c
ret = mem->do_mmap(..., (unsigned)o2, (unsigned)o3, ...);
ret = mem->do_mprotect(..., (unsigned)o2);
ret = sparc64_sysmem_mremap(..., (unsigned)o3, ...);
```

Validation happens after the cast (`src/os/guest_run_sysmem.c:223`, `442-454`). A guest `prot` such as `0x100000007ULL` truncates to `7` and passes although the full 64-bit value carries an illegal high bit.

Repro: `mmap(0, 8192, 0x100000007, PRIVATE|ANONYMOUS, -1, 0)` succeeds instead of `-EINVAL`.

Fix: validate the full register before narrowing, or widen the callee to `uint64_t`:

```c
if ((o2 & ~7ULL) != 0ULL)
    ret = -EINVAL;
else
    ret = mem->do_mmap(..., (unsigned)o2, ...);
```

Same for `mprotect` prot and `mremap` flags.

### S64-R9-8: `fork` in a threaded process leaves ghost thread slots

`src/os/proc.c:146-163` (`proc_do_fork` child leg):

```c
proc_nchildren = 0U;
sparc64_tlb_init();
```

Only the child table and TLB reset. `thr_table` in `src/os/threads.c` keeps every `used`/`running` slot from the parent although host `fork` cloned only the calling thread. `thr_futex_wait` counts `thr_live_locked()`; a ghost second thread defeats the `live < 2U` spurious-wakeup shortcut, so a lone child can sleep with no waker.

Repro: start one `CLONE_VM` thread, `fork`, in the child call `futex(WAIT)` with no timeout. Expected immediate spurious wakeup; observed hang.

Fix: reset the thread table on the child leg, keeping only the forking context, or refuse `fork` while threaded with `-EAGAIN`. Minimal child reset belongs next to `proc_nchildren = 0U`.

## Files with 0 defects

No demonstrable bugs found in `src/vm/vm64.h`, `src/main.c`, `src/core/cpu.h`, or `src/os/guest_interp_map.h`. The `vm64_check_*` 8 KiB validators, ELF header admission, bias-2047 stack synthesis body, big-endian auxv emission, and checked-copy wrap/range handling in the files above are correct as read. The paired-TLB helpers in `src/vm/vm64.c` are unreachable from the live `sparc64_dbt_tlb` but that is unused code, not a behavioral defect, so it is not reported per the brief.
