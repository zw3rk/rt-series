# loongarch64rt Round-6 verification — HEAD `24c2a73`

**Scope:** `loongarch64rt: remediate Round-6 defects (LA64-R6-1..8)` (4 files, +125/−79) against `lode/reviews/2026-11-03-defects-r6-loongarch64rt-astra.md`. Static read only: 4 shell turns, no build, tests, Docker, or QEMU.

**Result:** 6 VERIFIED, 2 PARTIAL, 0 NOT FIXED, 0 REGRESSION.

| ID | Sev | Verdict | Evidence |
|---|---|---|---|
| LA64-R6-1 statx timestamp fields | HIGH | **VERIFIED** | `src/os/syscalls.c:392-400` |
| LA64-R6-2 fchownat drops flags | HIGH | **VERIFIED** | `src/os/syscalls.c:526-545`, `:701` |
| LA64-R6-3 CHILD_SETTID never stored | HIGH | **VERIFIED** | `src/os/clone.c:575-578` |
| LA64-R6-4 failed clone leaves ring entry | HIGH | **VERIFIED** | `src/os/clone.c:542`, `:568`, `:584`, `:597` |
| LA64-R6-5 dual futex queue wake/requeue | HIGH | **PARTIAL** | `src/os/clone.c:293-317` fixed; `:327-345` vs `src/os/sched.c:147` |
| LA64-R6-6 Darwin WAIT_BITSET monotonic deadline | MED | **VERIFIED** | `src/os/clone.c:389-392`, `:405-408` |
| LA64-R6-7 duplicate statx serializers | LOW | **PARTIAL** | `src/os/syscalls.c:364`, `src/os/backend_darwin_fs.c:253-323` |
| LA64-R6-8 unreachable O_WRONLY check | LOW | **VERIFIED** | `src/os/syscalls_mem.c:263-264` |

## Per-item detail

**LA64-R6-1 — VERIFIED.** With `at = dst + 64`, the Linux branch now writes `st_ctim` at `at + 32/40` (guest offset 96) and `st_mtim` at `at + 48/56` (offset 112), `src/os/syscalls.c:392-400`. A new `__APPLE__` branch (`:402-419`) writes atime/btime/ctime/mtime at 64/80/96/112 with nanoseconds preserved. The generic fallback (`:420-426`) puts ctime at `at + 32` and mtime at `at + 48`. Layout matches `la64_statx_t` asserts at `:345-348`.

**LA64-R6-2 — VERIFIED.** `sys_at2` gains an `a4` parameter (`:508-509`); dispatch forwards it at `:701`. Case 54 (`:526-545`) rejects flags outside `AT_SYMLINK_NOFOLLOW | AT_EMPTY_PATH` with `-EINVAL`, maps `LA64_AT_SYMLINK_NOFOLLOW` (`syscalls_priv.h:40`, 0x100) to the host constant, and services `AT_EMPTY_PATH` with an empty path via `fchown(host_dirfd(dfd))`. `copy_guest_string` returns 0 for an empty guest string (`syscalls_priv.h:134-135`), so the empty-path branch is reachable.
Minor, not blocking: `AT_EMPTY_PATH` with `dfd = AT_FDCWD` yields `fchown(-100)` → `-EBADF`; Linux returns `-ENOENT`.

**LA64-R6-3 — VERIFIED.** `src/os/clone.c:575-576` stores the child TID at `child_tid_va` when `CLONE_CHILD_SETTID` is set, before `pthread_create` (`:595`). `CLONE_CHILD_CLEARTID` without SETTID still only validates (`:577-578`). `slot->ctid_va` remains the clear-on-exit destination only (`:564`), as the fix text requested.

**LA64-R6-4 — VERIFIED.** `la64_sched_abort_clone` is now called on every failure after `la64_sched_register_clone` (`:538-539`): malloc failure (`:542`), `PARENT_SETTID` store failure (`:568`), child-TID store/validate failure (`:584`), and the pre-existing `pthread_create` path (`:597`). No fallible step exists between registration and malloc; `clone_alloc_tid` and `la64_signal_clone_inherit` do not return errors.

**LA64-R6-5 — PARTIAL.**
- WAKE is fixed: cooperative wakes are subtracted from the budget (`rem`) and the host futex is only called for the remainder (`:293-317`). `WAKE(1)` can no longer wake two waiters.
- REQUEUE is improved but the accounting is wrong. `la64_sched_requeue` returns `got + moved`, i.e. woken **plus** requeued (`src/os/sched.c:147`). The new code treats that sum as the wake count and subtracts it from `rwake` (`clone.c:334-336`). Example: cooperative queue holds 2 waiters, kernel queue holds 1, `val = 1`. Cooperative wakes 1 and moves 1, `sgot = 2`, `rwake = 0`; the kernel waiter is requeued but the requested wake budget is already treated as spent. Conversely with `val = 1` and only cooperative requeues (`got = 0`, `moved = 1`) the kernel wake is suppressed entirely.
- The requeue count `tmo_va` is passed unreduced to the kernel (`:340`), so up to `2 × val2` waiters can be requeued across both queues.
- Pre-existing, not R6: plain `FUTEX_REQUEUE` should return woken only; the scheduler includes `moved`.
**Fix:** have `la64_sched_requeue` return woken and moved separately (or via an out-parameter), subtract each from its own budget before the kernel call.

**LA64-R6-6 — VERIFIED.** The `CLOCK_REALTIME` test was removed; every `FUTEX_WAIT_BITSET` timeout is treated as absolute (`:390-392`) and plain `FUTEX_WAIT` stays relative (`:393-397`). The polling loop reads the same `cid` selection (`:405-408`) so monotonic absolute deadlines compare against `CLOCK_MONOTONIC`.

**LA64-R6-7 — PARTIAL.** The divergence is gone: both serializers now emit the same offsets and both preserve nanoseconds (`backend_darwin_fs.c:307-327`, `syscalls.c:402-419`). The requested consolidation into one helper did not happen; two independent `fill_statx` functions remain (`syscalls.c:364`, `backend_darwin_fs.c:~253`), both still using relative numeric offsets rather than the asserted `la64_statx_t` fields. The comment at `syscalls.c:385-387` documents the layout but does not enforce it. Drift risk persists.

**LA64-R6-8 — VERIFIED.** The unreachable `O_WRONLY` branch was deleted; `src/os/syscalls_mem.c:263-264` keeps the single authoritative `!= O_RDWR` check.

## Out-of-scope changes in the same commit

- `rt_host_msync` in `syscalls.c:36-73` is now wrapped in `#if !defined(LA64_HAVE_BACKEND)`. `syscalls_priv.h:23` includes `os/backend.h`, and both `Makefile:84-85` targets define `LA64_HAVE_BACKEND=1`, so the backend's `int rt_host_msync` is the one linked. Callers at `:604` and `:611` assign to `long`, which is compatible. Not a regression, but unverified without a build.
- Comment-trimming churn throughout `clone.c` (section banners shortened). No behavior change.

## Recommendation

Accept R6-1, 2, 3, 4, 6, 8. Reopen R6-5 as a follow-up (requeue budget conflates woken and moved). Record R6-7 as drift-fixed, consolidation deferred to the backlog unless the Coordinator wants it closed in this round.
