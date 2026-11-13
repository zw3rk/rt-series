I have all the evidence. Here's the full review.

---

## Round-9 Commit Review: `7ce3b53`

### Per-Item Verdicts

#### LA64-R9-1 — `st_bytes` commit loop NULL deref: **VERIFIED**
`interp_mem.h:132-143` — NULL check added in the commit loop. Return type changed from `void` to `int`. All 10 callers in `interp.c` (ST_B/H/W/D, STX_B/H/W/D, STPTR_W/D at lines 515-600) and `stck` (`interp_mem.h:185`) now check the return and bail on fault. Correct: unlock, signal `SIGSEGV/MAPERR`, return -1.

#### LA64-R9-2 — Multi-VMA span spurious EFAULT: **VERIFIED**
New `mem_copy()` at `mem_min.c:418` iterates per-region via `find_containing()`. Public API `la64_mem_copy_to_guest`/`la64_mem_copy_from_guest` declared in `mem_min.h:48-49`. Bounce-buffer pattern applied consistently across 18 syscall sites: `sys_read`, `sys_pread64`, `sys_pwrite64`, `sys_readv`/`sys_writev`, `sys_getdents64`, `sys_write`, `sys_uname`, `sys_clock_gettime`, `sys_getrandom`, `sys_ioctl`, `sys_statx`, `sys_at2(statfs)`, `sys_wait4`, `sys_waitid`, `sys_pipe2`, `la64_proc_readlink`, `clone_store_u32`, `mmap_file_fill`.

#### LA64-R9-3 — `brk` shrink keeps stale bytes: **VERIFIED**
`mem_min.c:816-826` — when `addr < brk_cur`, zeros `[addr, brk_cur)` via `la64_mem_ptr` + `memset`, calls `dbt_clear_code` to retire translations, then sets `brk_cur`. The brk region is a single contiguous allocation so `la64_mem_ptr` should always succeed; the `if (p != NULL)` guard handles the theoretical NULL.

#### LA64-R9-4 — Copyouts skip LL invalidation: **VERIFIED**
`la64_clone_invalidate_ll(NULL, va, len)` added at every host-side copyout site: `sys_read` (`syscalls_file.c:338,347`), `sys_pread64` (:399), `sys_readv` (:244), `sys_getdents64` (:95), `sys_clock_gettime` (`syscalls.c:167`), `sys_getrandom` (:268), `sys_ioctl` (:335), `sys_statx` (:410), `sys_at2/statfs` (:464), `sys_uname` (`minsys.c:82`), `sys_wait4` (:547,:557), `sys_waitid` (:617), `sys_pipe2` (:663), `clone_store_u32` (`clone.c:191`), `la64_clone_thread_exit` (`clone.c:699`), `sf_deliver_locked` (`sigframe.c:249`), `la64_proc_readlink` (`proc.c:352`), `clone_process/parent_tid` (`minsys.c:258`).

#### LA64-R9-5 — Staged-shared fork incoherence: **NOT ADDRESSED**
No changes to `vm_file.c` or any fork-related path. The commit message claims "LA64-R9-1..11" but this item has no corresponding code change. The defect (staged anonymous pages going private across `fork` on 16 KiB Darwin hosts) remains open.

#### LA64-R9-6 — `load_elf` address overflow: **VERIFIED**
Five overflow checks added in `loader.c`:
1. `bias > UINT64_MAX - ph.p_vaddr` (line 372) — before `va = bias + p_vaddr`
2. `ph.p_memsz > UINT64_MAX - page_off - (LA64_PAGE_SIZE - 1u)` (line 388) — rounding wrap
3. `ph.p_memsz > UINT64_MAX - va` (line 394) — `va + memsz` wrap
4. `eh.e_phoff - ph.p_offset > UINT64_MAX - va` (line 462) — phdr calc
5. `bias > UINT64_MAX - eh.e_entry` (line 473) — entry point

Also the `phdr` computation was tightened from `bias + p_vaddr + delta` to `va + delta` (using the already-validated `va`).

#### LA64-R9-7 — Ignored `vmfile_unmap` failure: **VERIFIED**
`syscalls_mem.c:341` (MAP_FIXED) and `:469` (munmap) now check `vmfile_unmap(...) == -ENOMEM` and propagate the error before tearing down backing. Other return codes (e.g. `-EINVAL` when no table) preserve the old ignore-and-proceed behavior per the comment.

#### LA64-R9-8 — File-layer byte mutations bypass SMC: **VERIFIED**
`vm_file_sync.c` adds weak `dbt_smc_store` stub (line 20) and calls it in all four paths:
1. `vmfile_staged_propagate_locked` (line 204) — propagation `memcpy`
2. `vmfile_refresh_clean_locked` (line 308) — clean-map refresh
3. `vmfile_discard_above_locked` (line 381) — discard refill
4. `vmfile_msync` (line 459) — `pwrite`-triggered refresh

#### LA64-R9-9 — `execve` keeps arena/file state: **VERIFIED**
`loader.c:698-709` — under `LA64_HAVE_VM64`, `la64_load` now unmaps the full arena via `vm64_unmap(0, vm64_arena_len())`, calls `vmfile_fini()` + `vmfile_init()` to rebuild file tables. Placed after `la64_mem_init()` and before `load_elf()`. Functions are declared in `vm64.h:100` and `vm_file.h:65-66`.

#### LA64-R9-10 — `munmap(0, len)` wrong error: **VERIFIED**
`mem_min.c:244-247` — `split_at` now returns 0 for `va == 0` (valid no-op) instead of falling through to the `-EINVAL` path. The original `va == 0 || unaligned` compound check is split into two separate checks.

#### LA64-R9-11 — Wrong errno for O_WRONLY mmap: **VERIFIED**
`syscalls_mem.c:289-298` — new check: if `file_backed && (prot & LA64_PROT_READ) != 0` and the fd is `O_WRONLY`, returns `-EACCES`. This runs after the existing shared-write check, so both read and write access are now validated.

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None found |
| `.c` includes | None found |
| `sprintf`/`strcpy`/`strcat` | None found |
| `<threads.h>` / Annex K / `_Generic` | None (one comment mentions `<threads.h>` explaining its absence) |
| File sizes <= 900 lines | All pass. `mem_min.c` is exactly 900 (at limit). `clone.c` at 893, `vm_file_sync.c` at 896 |

---

### Newly Introduced Concerns

1. **`mem_min.c` at 900 lines exactly** — any future change will exceed the limit. This file absorbed `mem_copy` + two public wrappers (+53 lines net). Consider splitting before the next phase.

2. **`la64_mem_copy_to_guest` casts away `const`** (`mem_min.c:461`): `(uint8_t *)src` drops `const` for the generic `mem_copy` internal. Safe in practice (the `to_guest=1` path only reads from `host`), but a cleaner internal signature would avoid the cast.

3. **`sys_pipe2` weakened early-fault check** (`syscalls_file.c:630`): Changed from `la64_mem_ptr(fds_va, 8, 1) == NULL` (checks write permission) to `!la64_mem_range_mapped(fds_va, 8)` (checks existence only). If the target page is read-only, the pipe fds are created before the `la64_mem_copy_to_guest` write-permission check catches the fault. The fds ARE correctly closed on the failure path (line 658-660), so no fd leak — but this is extra work for the error case vs. failing early.

4. **Double `fcntl` for shared-writable-readable maps** (`syscalls_mem.c:282,293`): A `MAP_SHARED|PROT_READ|PROT_WRITE` mapping calls `fcntl(fd, F_GETFL)` twice. Minor inefficiency, not a bug.

5. **`brk` shrink: silent skip on NULL `la64_mem_ptr`** (`mem_min.c:822`): If `la64_mem_ptr(addr, tail, 1)` ever returns NULL for the brk region (shouldn't happen in practice since it's a single allocation), the zeroing is silently skipped and stale bytes survive. The `dbt_clear_code` still runs regardless. This is a defense-in-depth gap, not a live bug.

---

### Summary

| Item | Verdict |
|---|---|
| LA64-R9-1 | **VERIFIED** |
| LA64-R9-2 | **VERIFIED** |
| LA64-R9-3 | **VERIFIED** |
| LA64-R9-4 | **VERIFIED** |
| LA64-R9-5 | **NOT ADDRESSED** — no code change in commit |
| LA64-R9-6 | **VERIFIED** |
| LA64-R9-7 | **VERIFIED** |
| LA64-R9-8 | **VERIFIED** |
| LA64-R9-9 | **VERIFIED** |
| LA64-R9-10 | **VERIFIED** |
| LA64-R9-11 | **VERIFIED** |

**10 of 11 items verified.** R9-5 (staged-shared fork incoherence on Darwin 16 KiB hosts) is absent from the commit despite the "R9-1..11" claim. No regressions or C11 violations found. `mem_min.c` at exactly 900 lines is the most pressing housekeeping item.
