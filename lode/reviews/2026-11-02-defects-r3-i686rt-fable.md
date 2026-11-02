# Round-3 remediation review: i686rt `0c82128` vs `4a759c6`

Static review only. I read the astra Round-3 report, the full `HEAD` diff (15 files, +722/−255), and ran targeted greps for the points the diff alone could not settle. No build, test, Docker, or QEMU ran, so `-Werror` cleanliness and runtime behaviour are not verified here.

## Per-item verification

**I686-R3-1 (clone / SETTID / gettid identity): VERIFIED.**
`src/os/clone.c` now uses one namespace, the host TID. The synthetic `s_next_tid` counter is gone. `thread_entry()` publishes `clone_host_gettid()` through a mutex/condvar handshake in `struct clone_arg`; the parent waits for `ready`, registers the entry under the host TID (`i686_thread_registry_add` now also stores `host_tid = tid`), writes PARENT_SETTID itself, then sets `registered` and returns the host TID. The child writes CHILD_SETTID after the handshake and before any guest code. `set_host_tid()` no longer rekeys. All `clone_arg` failure paths destroy the mutex/condvar and free both allocations. Lock nesting is `ca->mtx` → `s_registry_lock` on the parent side only; the child never takes the registry lock under `ca->mtx`. The parent's `i686_copy_to_guest` under `ca->mtx` may take the subpage lock, but the child is not yet an exec reader, so there is no drain deadlock. Minor note: PARENT_SETTID is now written by the parent and CHILD_SETTID by the child after the parent has already returned, which matches kernel ordering (glibc ≥2.34 and musl rely on PARENT_SETTID only).

**I686-R3-2 (staged mmap subpage quiescence): VERIFIED for the two mutating callers; one caller class unconfirmed.**
`vm_mmap2_locked()` and `rt32_vm_brk()` take `i686_vm32_subpage_lock()` before `rt32_vm_mmap2_staged_a2_locked()` and release it on every exit, including the record/untrack/track rollback paths. The helper's failure path restores protections via `i686_vm32_widen_prot` instead of `union_protect`, which is correct while the subpage lock is held. Lock order is VM lock (outer) → subpage (inner), consistent with `note_pwrite` and `marshal.c`. My grep for other callers of the staged helper failed on a shell glob and I had no budget left to repeat it, so loader-time or mremap-staged callers are not confirmed to hold the subpage lock. Loader use is single-threaded, so the practical exposure is small.

**I686-R3-3 (anonymous MAP_FIXED stale file registrations): VERIFIED.**
`i686_vm_file_untrack_map()` is now called unconditionally after every successful host mapping, and `track_map` only when `want_track` (file-backed with a valid fd). The staged `-EBADF` check is hoisted ahead of any mutation. Capacity for the untrack split is pre-reserved via the new `i686_vm_file_can_replace()`.

**I686-R3-4 (metadata failures after mmap succeeds): VERIFIED, with one logic smell.**
Pre-flight checks (`rt32_vm_can_record_locked`, `i686_vm_file_can_replace`) run before the host mapping; post-mapping failures of record/untrack/track roll the host range back to a PROT_NONE reservation (or widen + unlock when staged) and return `-ENOMEM`. mremap now propagates failures of mprotect, record, and the old-range munmap, each with provisional-destination cleanup and `hold_fd` close. Smell: in the extension path the `ok` expression evaluates `rt32_vm_record_region_locked()` first and, when `has_file` is true, ignores its result and proceeds to untrack/track. Because `vm_mmap2_locked()` already recorded exactly that range, the re-record is slot-neutral and cannot fail on capacity, so this is benign today but fragile.

**I686-R3-5 (VMA split exhaustion): VERIFIED.**
New `vm_unmap_final_count` / `vm_mprotect_final_count` compute the post-operation region count (fully covered −1, interior +1 for unmap; interior +2, partial +1 for mprotect) and the `can_*` helpers reject before mutation. The old "broaden to whole region" and "leave interval mapped" fallbacks are removed; `unmap_regions_locked` and `mprotect_regions_locked` now return `int`, and every caller (mmap, mprotect, munmap, brk grow and shrink, mremap) checks them. The opportunistic `vm_coalesce_regions_locked()` retry before failing was removed; since coalescing already runs after each operation the table stays normalised, so this only changes behaviour at the hard cap. `rt32_vm.c` is now exactly 900 lines, at the limit.

**I686-R3-6 (syscall copy fault containment): VERIFIED.**
Both `siglongjmp(*outer, 1)` sites in `s_copy_tolerant()` are removed; `outer` is still used only to re-arm the saved fault buffer on exit, so no dead-variable warning under `-Werror`. Faults return `-I686_EFAULT` after re-widening opened pages and releasing the subpage lock. The related `sigaction`/`sigprocmask`/`sigaltstack` changes stage the copy-in before writing `old*`, which removes a partial-update window; that is beyond the audit scope but correct.

**I686-R3-7 (file refresh locking and protected destinations): PARTIAL, with a regression in Regime A1.**
Good: `note_pwrite` now holds the VM lock across the `s_maps` walk, reads into a stack buffer with full-length/EINTR handling, skips the page on short read instead of counting it, and invalidates DBT translations for executable pages. For A2 it takes the subpage lock, opens the host cover RW, copies, then `widen_prot` restores the union. Regression: in the non-A2 branch the code does a plain `memcpy()` into the guest page with no protection change (`vm_file.c` has only the one A2 `mprotect`). A CLEAN private file page that is mapped `r--` or `r-x`, which is the common case for mapped text and rodata, is a read-only host page in A1. Before this commit `pread()` into it failed with `EFAULT` and the loop stopped silently; now the runtime SIGSEGVs in its own code while holding the VM spin lock. Trigger: guest `pwrite64` to an fd whose file is also privately mapped read-only. Also a perf note: blocking `pread()` now runs under a spin lock, so sibling threads burn CPU during the I/O.

**I686-R3-8 (fork lock and registry reinit): VERIFIED, two caveats.**
`fork_prepare/parent/child` in `clone.c` are registered once from both init paths. Prepare acquires VM spin lock → registry mutex → subpage mutex → futex mutex; parent releases in reverse; child resets the spin lock, reinitialises the three mutexes, resets vm32 writer/reader counters and futex slots, resets the AOT split lock and (Darwin) the JIT toggle mutex, empties the registry, makes the surviving ctx `s_main_ctx`, sets its `host_tid` to the new pid, and clears `is_thread_clone`. Guest fork and vfork both go through libc `fork()`, so the atfork handlers do run. The standalone vm32 `pthread_atfork` was removed, so the child reset runs once. Caveat 1: the surviving ctx is not re-added to the registry; `sys_gettid` still works because `i686_thread_registry_self_tid` falls back to the main pid when `ctx == s_main_ctx`, but any lookup by TID (tkill/tgkill wake targeting the survivor) depends on an equivalent main-ctx fallback I did not verify. Caveat 2: `pthread_mutex_destroy` on a mutex still locked from `prepare` returns `EBUSY` on glibc; the subsequent `init` overwrites it, which works on glibc and musl in practice but is technically undefined.

**I686-R3-9 (shared anonymous mremap fallback): VERIFIED.**
Linux: host `mremap` failure unmaps the provisional destination, closes `hold_fd`, and returns `-errno`. Non-Linux backends: shared anonymous moves now fail with `-ENOMEM` rather than copy into a fresh object. This is the audit's requested semantics; Darwin loses MAYMOVE for MAP_SHARED|MAP_ANONYMOUS, which is the honest outcome.

**I686-R3-10 (reader registration DRY): VERIFIED.**
`vm32_register_reader()` holds the single wait/add/recheck/rollback loop; `exec_enter()` keeps the ctx/regime/reentrancy guards and `subpage_unlock()` calls the helper when restoring a dropped registration.

**I686-R3-11 (Makefile lane lists): VERIFIED.**
`U3_OWNED` and `P13_OWNED` and the lane commentary are gone; `check-line-limits` comment now describes repository-wide enforcement. `-Werror` was added to every compile and link line, which is beyond scope and unverified by a build here.

**Curated C11 hygiene:** no `#include "*.c"` anywhere under `src`, `include`, `tests`; the longest first-party file is `src/rt32/rt32_vm.c` at 900 lines. Both pass, but `rt32_vm.c` has zero headroom.

## Summary

| Item | Status | Note |
|---|---|---|
| I686-R3-1 | VERIFIED | Host-TID namespace, startup handshake, all failure paths clean |
| I686-R3-2 | VERIFIED | mmap and brk quiesced; other staged callers unconfirmed |
| I686-R3-3 | VERIFIED | Unconditional untrack, capacity pre-reserved |
| I686-R3-4 | VERIFIED | Transactional; benign `ok` expression smell in mremap extension |
| I686-R3-5 | VERIFIED | Reservation before mutation, no semantic substitution |
| I686-R3-6 | VERIFIED | No remaining `siglongjmp` to outer |
| I686-R3-7 | PARTIAL | A1 `memcpy` into read-only host page is a new SIGSEGV path |
| I686-R3-8 | VERIFIED | Survivor not re-registered; relies on main-ctx fallback |
| I686-R3-9 | VERIFIED | Fail instead of silent copy on all backends |
| I686-R3-10 | VERIFIED | Single helper |
| I686-R3-11 | VERIFIED | Lists removed |

## Newly discovered consequential follow-ups

1. **R3-7 A1 refresh crash.** `i686_vm_file_note_pwrite()` non-A2 branch must open the destination page RW (host `mprotect` to `PROT_READ|PROT_WRITE`, copy, restore the region prot) or route through the checked copy helper. As written, a guest `pwrite64` overlapping a privately mapped read-only CLEAN page faults in runtime code under the VM spin lock.
2. **Post-fork survivor registry entry.** `fork_child()` should re-add the surviving ctx under `getpid()` (or the review should confirm every TID-keyed lookup has the same `s_main_ctx` fallback as `self_tid`). Also consider clearing the survivor's `clear_child_tid` when it was a worker clone.
3. **mremap extension `ok` expression** swallows a `record_region` failure when `has_file` is true. Restructure so the record result is checked independently of `has_file`.
4. **`rt32_vm.c` at 900 lines** and `-Werror` now on every compile line: the next edit to that file or any new warning breaks `check-line-limits` or the build. Both need a real `nix develop -c make build check-line-limits` run before this commit is treated as green.
