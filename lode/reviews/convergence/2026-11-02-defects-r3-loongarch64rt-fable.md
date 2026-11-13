I have what I need for a static verdict. Three of the final greps were lost to a zsh glob error, so the caller analysis for the new `vmfile_msync`/`vmfile_flush`/`vmfile_sync` and the `darwin_dir_dup_fd` return value rests on the commit's file list: no caller file changed, and the guest `msync` case shown at `src/os/syscalls.c:500` still calls host `msync()` directly. I'm stopping at the tool budget and reporting.

# Round-3 Remediation Review: `0e3c4bd` vs `00ea803` (loongarch64rt)

Static review only. No builds, tests, Docker, or QEMU ran. Five inspection turns were used: the astra report, the full commit diff, and two targeted greps over the post-commit tree.

## Per-item verification

**LA64-R3-1 — Thread signal state is process-global. Status: REGRESSION**

The structural fix is in place. `src/os/sigstate.c` holds shared dispositions (`sf_actions`), a process-directed pending set (`sf_proc_pending`/code/addr), and a per-`la64_ctx_t` table of blocked mask, thread-directed pending, and altstack (`sf_thread_t`, 129 slots = 128 clone workers + main). `la64_sigprocmask_sys`, `la64_sigaltstack_sys`, `sf_deliver_locked`, `la64_sigreturn_sys`, and `sf_raise_self` all resolve per-thread state via `sf_state_for(ctx, 1)`. Clone inheritance (`la64_signal_clone_inherit`) copies the blocked mask, clears pending, disables the altstack, which matches Linux for `CLONE_VM` threads. Thread exit frees the slot. The fork child keeps only the survivor and clears pending, preserving the survivor's altstack, which matches Linux for non-`CLONE_VM` fork. Exec resets caught handlers to `SIG_DFL`, keeps ignored, and disables altstacks. `tkill` self-validation now uses the worker's clone tid.

The regression: `la64_signal_poll` resolves `sf_state_for(ctx, 0)` and returns `npc` unchanged when no record exists. Nothing creates the main thread's record at startup, and `la64_sigaction_sys` does not create one (`(void)ctx`). Scenario: guest installs a handler via `rt_sigaction` and never calls `rt_sigprocmask`/`sigaltstack`/`tkill`; a host-noted process signal (SIGALRM, SIGINT, SIGCHLD) lands in `sf_proc_pending` via `la64_host_signal_note`; `la64_signal_has_pending()` reports 1, but poll never delivers. Before this commit the global `sf_pending` was delivered for any ctx. Fix: use `sf_state_for(ctx, 1)` in poll (or treat a missing record as mask 0). High confidence, static.

Minor: `sf_state_for(NULL, create)` returns slot 0 even when slot 0 belongs to a real ctx. All current callers guard `ctx == NULL` first, so unreachable today.

**LA64-R3-2 — Shared mapping fallback becomes a private snapshot. Status: PARTIAL**

Done: the outside-arena `mem_min` route now fails `MAP_SHARED` explicitly with `EINVAL` (`src/os/syscalls_mem.c`, `mmap_file_install`), which is the audit's accepted alternative. The staged arena path gains `staged_writeback` (pwrite) and `staged_propagate` (memcpy across same-inode shared records), invoked from `vmfile_unmap`, `vmfile_msync`, `vmfile_flush`, and `vmfile_sync`. The unit test covers direct-overlay plus staged alias coherence on 16 KiB hosts.

Not done: the three new sync entry points have no production caller. The guest `msync` syscall at `src/os/syscalls.c:500` still calls host `msync()` on the arena pointer, which is a no-op for staged anonymous pages. `syscalls_file.c` is untouched, so `write`/`ftruncate` paths do not call `vmfile_sync`. The only live writeback is `vmfile_unmap`. A guest that writes through a staged `MAP_SHARED` mapping and exits without `munmap` still loses the data, and a guest `msync` still does nothing. The commit message's "coherent on msync/flush/sync" describes library surface, not guest behavior.

New defect in the writeback itself: `staged_writeback` (`src/vm/vm_file.c:365`) writes the full span regardless of file size and then grows the tracked `file_size`. Staged populate stops at EOF and leaves zeros; writeback of a 4096-byte record over a 100-byte file extends the file to 4096. Linux never extends a file through `MAP_SHARED` writeback. The test's `ftruncate(fd, 100)` shrink followed by later unmap would trigger exactly this path. Also, `pwrite` runs for `PROT_READ` records and for direct page-cache overlays (self-copy), so every unmap of a writable shared overlay bumps mtime even when untouched, and an `O_RDONLY`-dup'd inode fd returns `EBADF` (ignored in unmap today, but it will surface as a guest `msync` failure once wired).

**LA64-R3-3 — Failed file mapping leaves a live untracked mapping. Status: VERIFIED**

`map_bytes_in_place` now reserves a record slot via `maps_have_free()` before `vm64_map`, and unwinds with `vm64_unmap` on `pread` failure, page-state failure, and `record_map` failure. The direct overlay path checks capacity before mapping, and on `record_map` failure calls `repair_overlay` then `vm64_unmap`. On overlay placement failure it unmaps and falls through to the staged path. `la64_mem_map` reserves VMA capacity before the host `mmap` in both build variants. The inode row from `vmfile_register` is not released on failure, but the new reclaim in `vmfile_unmap` collects it later (see follow-up F-1 for why that reclaim is itself dangerous).

**LA64-R3-4 — `mmap` skips argument validation. Status: VERIFIED**

`file_backed` now derives solely from `MAP_ANONYMOUS`; `fd == -1` on a file map returns `EBADF`; exactly one of `MAP_SHARED`/`MAP_PRIVATE` is required; file offset must be guest-page aligned. All checks precede the `MAP_FIXED` replacement block. Low-severity divergence: `MAP_SHARED_VALIDATE` (both bits set, value 3) returns `EINVAL`, whereas Linux ≥ 4.15 accepts it. Also Linux rejects an unaligned offset for anonymous maps too; here only file maps are checked.

**LA64-R3-5 — Directory cursor identity across early dup. Status: PARTIAL**

Alias groups (`grp`) are now tracked independently of lazy `DIR *` allocation. `darwin_dir_dup_fd` records a pending alias (`cursor_idx == -1`) for an unread directory, and `darwin_dir_acquire` creates one cursor on first enumeration and attaches later group members to it with dev/ino verification. Trace of `open; dup; getdents(fd); getdents(dup)` yields a single shared cursor. Table size grew to 256, and `lseek` preserves pending aliases.

Gaps: `darwin_dir_dup_fd` now returns `-12` on exhaustion, but no caller file is in the commit, so the error is dropped and exhaustion is still silent to the guest. Unverified: `darwin_dir_release_cursor` is now reached with `cidx == -1` from `darwin_dir_acquire` and the close path for pending aliases; its body was not inspected and must bounds-check before indexing `g_darwin_dir_cursors`. Pre-commit code never passed a negative index there.

**LA64-R3-6 — Signal syscalls overwrite aliased input. Status: VERIFIED**

`la64_sigaction_sys`, `la64_sigprocmask_sys`, and `la64_sigaltstack_sys` snapshot the full input into locals before any copyout, and `sigprocmask` validates both pointers and `how` before mutating. Exact-alias and partial-overlap cases are correct. Minor divergence: old state is copied out before new-state validation errors (`EPERM`/`EINVAL`/`ENOMEM`), whereas Linux writes old state only on success. Harmless since the copied value is the true old state.

**LA64-R3-7 — Altstack disable and sigreturn lifecycle. Status: VERIFIED**

The on-stack `EPERM` check now precedes both enable and disable. `la64_sigreturn_sys` restores `uc_stack` from frame offsets 144/152/160: `SS_DISABLE` disables; `0`/`SS_ONSTACK` with non-zero sp and size ≥ `MINSIGSTKSZ` re-enables. Low-severity divergence: Linux's `restore_altstack` ignores invalid saved values; here a malformed `uc_stack` raises `SIGSEGV` after GPRs and PC are already restored but before FP/extension records, so the fault frame captures a half-restored context. Legitimate guests cannot produce `SS_AUTODISARM` here because `sigaltstack` rejects it, so this is reachable only via a handler scribbling on `uc_stack`.

**Curated C11 and line limits**

No `#include "*.c"` in `src/` or `tests/`. Largest files: `src/os/clone.c` 899, `src/vm/vm64.c` 869, `src/interp/interp.c` 861, `src/vm/vm_file.c` 858, all ≤ 900. New `sigstate.c`/`sigstate.h` use `static inline` and `extern` tables only, no VLA/Annex K/`_Generic`. `sigstate.c` is in the Makefile object list and `sigstate.h` in `L1C_DEPS`. No `x18` touched; no assembly changed.

## Summary

| Item | Status | Note |
|---|---|---|
| LA64-R3-1 | REGRESSION | Per-thread split correct; `la64_signal_poll` with `create=0` drops process-directed delivery for threads with no record yet |
| LA64-R3-2 | PARTIAL | Explicit `EINVAL` outside arena done; staged writeback only on `munmap`; guest `msync` not wired; writeback extends files past EOF |
| LA64-R3-3 | VERIFIED | Capacity reserved first, every failure unwinds |
| LA64-R3-4 | VERIFIED | `MAP_SHARED_VALIDATE` rejected (low) |
| LA64-R3-5 | PARTIAL | Cursor identity fixed; `-12` return not consumed by callers; `release_cursor(-1)` tolerance unverified |
| LA64-R3-6 | VERIFIED | Minor copyout-before-validate ordering |
| LA64-R3-7 | VERIFIED | Malformed `uc_stack` faults where Linux ignores (low) |

## Newly discovered consequential follow-ups

- **F-1 (High) Shared inode table reclaimed from per-process view.** `src/vm/vm_file.c` header states `itable` is a `MAP_SHARED` anonymous object inherited across `fork()`, but the new reclaim loop in `vmfile_unmap` (~lines 498–524) zeroes any row that has no record in the *calling process's* private `maps[]`. After a fork, any `munmap` in the child destroys rows the parent still uses (and vice versa), breaking `staged_writeback`, truncate hooks, and `RT_FUTEX_KEY_SHARED_FILE` identity, and allowing row reuse under the other process. Reclaim needs a cross-process refcount in the row, or must be restricted to rows created by this process.
- **F-2 (Medium) `staged_writeback` grows files.** See R3-2. Clamp the span to the inode's tracked `file_size` and drop the size bump; skip writeback for `PROT_READ` records and untouched direct overlays.
- **F-3 (Medium) Fork from a multi-threaded guest now returns `EAGAIN`.** `sys_clone_process` gates on `la64_clone_has_live_workers()`. Linux permits `fork()` from a threaded process; if `posix_spawn`/`system()` from a threaded guest routes through this path, they now fail. Outside the R3 scope but introduced here; document or narrow.
- **F-4 (Low) `la64_signal_poll` fix also needed for `sf_state_for` slot accounting.** When creating in poll, the 129-slot table is exactly main + 128 workers, so exhaustion would surface only if a dead worker's slot were not freed; `la64_signal_thread_exit` runs before slot detach, which looks correct.
