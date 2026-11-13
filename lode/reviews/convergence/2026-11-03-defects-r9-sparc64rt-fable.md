Good — `perms` is declared at line 611. All data gathered. Here's the full review:

---

## Round-9 (S64-R9-1..8) Static Review of Commit `3754389`

### S64-R9-1: Stack 8K alignment — **VERIFIED**

**Defect**: `GUEST_STACK_TOP` was `0x7ffffffff000` (4K-aligned, not 8K-aligned).

**Fix**: `guest_stack.c:33` changed to `0x7fffffffe000` (`& 0x1fff == 0`). `threads.c:94` changed from `SPARC64_TASK_SIZE - SPARC64_PAGE_SIZE` (4096) to `SPARC64_TASK_SIZE - UINT64_C(8192)`. Both sites now produce 8K-aligned tops. Verified `SPARC64_PAGE_SIZE` is `UINT64_C(4096)` at `mem_space.h:13`, confirming the old code was wrong.

---

### S64-R9-2: brk TLB invalidation — **VERIFIED**

**Defect**: `brk` growth/shrink flushed DBT but not the Soft-TLB, leaving stale `addend` pointers.

**Fix**: `guest_run.c:211-213` adds `sparc64_tlb_invalidate_gva(cur, target - cur)` on growth; `guest_run.c:216-218` adds `sparc64_tlb_invalidate_gva(target, cur - target)` on shrink. Both calls sit immediately after the space map/unmap and before the existing DBT flush at line 222. Ranges match exactly (growth delta and shrink delta respectively). Function is declared in `dbt/mem_sites.h:83`.

---

### S64-R9-3: SMC flush on guest writes — **VERIFIED**

**Defect**: `guest_mem_write` and `sparc64_sysmem_write` didn't invalidate DBT/TLB on writes to code-bearing pages.

**Fix**: Three write paths patched:
- `guest_run_mem.c:81-87` (slow-path write): adds `sparc64_tlb_evict_writes` + conditional `sparc64_dbt_invalidate` + `vm64_code_epoch_bump`.
- `guest_run_mem.c:111-117` (atomic mutating path): same three-call sequence, correctly guarded by `request->op != SPARC64_ATOMIC_SC || result->sc_success`.
- `guest_run_sysmem.c:105-111` (syscall copyout path): same sequence.

All three functions are properly declared in `dbt/mem_sites.h` and `vm/vm64.h`. New `#include "dbt/dbt.h"`, `"dbt/mem_sites.h"`, `"vm/vm64.h"` added to `guest_run_mem.c`.

---

### S64-R9-4: mremap same-size shortcut validation — **VERIFIED**

**Defect**: `mremap(unmapped, N, N, 0)` returned success without checking the source.

**Fix**: `guest_run_sysmem.c:626-629` inserts `sysmem_span_perms(g, old_addr, old_len, &perms)` check returning `-EFAULT` on failure, before the `return (long)old_addr` shortcut. `perms` is declared at line 611. Matches the pattern of the FIXED leg at line 642.

---

### S64-R9-5: MAP_FIXED_NOREPLACE and unknown flags — **VERIFIED**

**Defect**: Unknown `MAP_*` bits were silently ignored; `MAP_FIXED_NOREPLACE` fell through as a non-fixed hint.

**Fix**:
- Lines 51-62: defines `SYSMEM_MAP_KNOWN` bitmask covering `SHARED|PRIVATE|FIXED|ANONYMOUS|NORESERVE|DENYWRITE|EXECUTABLE|POPULATE|STACK|FIXED_NOREPLACE`.
- Lines 262-264: rejects unknown bits with `-EINVAL` (`flags & ~SYSMEM_MAP_KNOWN`).
- Lines 275-289: dedicated `SYSMEM_MAP_FIXED_NOREPLACE` arm validates alignment/bounds, checks `sysmem_span_free` returning `-EEXIST` if occupied, then sets `base = addr` and promotes to `FIXED`.
- `sysmem_span_free` is defined at line 580 and forward-declared at line 168.

**Note**: SPARC Linux also defines `MAP_LOCKED` (0x100), `MAP_GROWSDOWN` (0x0200), `MAP_NONBLOCK` (0x10000), `MAP_HUGETLB` (0x40000). These are not in the whitelist and would return `-EINVAL`. This is conservative (a guest passing these flags would fail) but not a regression — they were silently ignored before, not implemented. If musl startup or allocators use `MAP_LOCKED` or `MAP_GROWSDOWN`, they'll now get `-EINVAL` instead of silent ignore. Worth tracking but not a defect in the remediation itself.

---

### S64-R9-6: madvise handler — **VERIFIED**

**Defect**: `madvise(75)` fell to `default: -ENOSYS`.

**Fix**:
- `syscalls_min.c:650-651`: new `case SPARC64__NR_madvise` dispatches to `sparc64_sysmem_madvise(mem->context, o0, o1, o2)` — note `advice` (o2) stays 64-bit, no truncation (ties into S64-R9-7 philosophy).
- `guest_run_sysmem.c:839-899`: full handler validates 8K alignment, accepts `NORMAL/RANDOM/SEQUENTIAL/WILLNEED/DONTNEED/DONTFORK`, rejects unknown advices with `-EINVAL`, validates span mapping with `sysmem_span_perms`. `DONTNEED` on writable pages zeroes in 512-byte chunks via `sparc64_space_write` + SMC sequence. `zeros[512]` is a fixed-size array (not a VLA).
- Syscall number 75 confirmed in `syscall_nr.h:100`.

**Observation**: `MADV_DONTNEED` on a read-only anonymous page skips zeroing (the `perms & SPARC64_MEM_WRITE` guard). On Linux, DONTNEED on read-only anonymous memory still discards data (next read refaults to zero). This is a minor semantic gap — unlikely to trigger with musl allocators but theoretically observable.

---

### S64-R9-7: prot/flags 64-bit truncation — **VERIFIED**

**Defect**: `(unsigned)o2` / `(unsigned)o3` casts truncated high bits before validation.

**Fix**: `syscalls_min.c:631-638` (mmap) checks `o2` and `o3` upper 32 bits, returning `-EINVAL` if nonzero. `syscalls_min.c:644-648` (mprotect) checks `o2`. `syscalls_min.c:654-659` (mremap) checks `o3`. All three use the pattern `(oN & UINT64_C(0xffffffff00000000)) != UINT64_C(0)`. The narrowing `(unsigned)` casts occur only inside the `else` branch after validation passes.

---

### S64-R9-8: fork ghost threads — **VERIFIED**

**Defect**: `proc_do_fork` child leg didn't reset `thr_table`, leaving ghost parent threads.

**Fix**:
- `proc.c:156-159`: calls `sparc64_threads_note_fork_child(ctx, mem->context)` right after `sparc64_tlb_init()` on the child leg.
- `threads.h:75-82`: declares the function and exposes `thr_table[]` as `extern`.
- `threads.h:65-68`: moves `THR_MAX_THREADS` from `threads.c` to the shared header.
- `threads.c:68`: removes local `THR_MAX_THREADS` definition; line 71 makes `thr_table` non-static.
- `threads_fork.c` (new, 56 lines): `sparc64_threads_note_fork_child` iterates all slots, keeps only the slot whose `ctx_ref == ctx` (refreshes `tid` to `getpid()`, clears `done`), zeroes all other slots. Fallback at line 50 installs slot 0 if no match found. No locking needed — single-threaded child post-fork. Uses `memset` (not `strcpy`/`sprintf`). No VLAs.

---

## Curated C11 Compliance

| Check | Result |
|---|---|
| No VLAs | Pass — `zeros[512]` is a compile-time constant |
| No `.c` includes | Pass — `grep` found none |
| No `sprintf`/`strcpy`/`strcat` | Pass |
| No `_Generic`/`<threads.h>`/Annex K | Pass |
| All files <= 900 lines | Pass — `guest_run_sysmem.c` is exactly 900 (the limit) |

## Newly Introduced Issues

| Severity | File:Line | Description |
|---|---|---|
| Low | `guest_run_sysmem.c:879` | `MADV_DONTNEED` on read-only anonymous pages skips zeroing; Linux semantics discard data regardless of write permission. Unlikely to trigger with musl but semantically incomplete. |
| Info | `guest_run_sysmem.c:59` | SPARC `MAP_LOCKED`(0x100), `MAP_GROWSDOWN`(0x200), `MAP_NONBLOCK`(0x10000), `MAP_HUGETLB`(0x40000) not in `SYSMEM_MAP_KNOWN`; previously silently passed, now `-EINVAL`. Behavior change is stricter, not a regression, but could reject valid guest calls. |
| Info | `guest_run_sysmem.c:900` | File is at exactly 900 lines — zero headroom for future additions without a split. |

## Summary

All 8 items **VERIFIED**. No regressions found. Two minor observations (DONTNEED on read-only pages, missing SPARC MAP flags in whitelist) are semantic gaps rather than bugs introduced by this commit. C11 compliance and line-limit discipline pass.
