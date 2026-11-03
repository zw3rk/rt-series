Now I have everything needed. Here's the full review:

---

## Round-10 (b72db16) Static Review: P32-R10-1..7

### P32-R10-1 — `FUTEX_WAIT_BITSET` unsupported → **VERIFIED**

**threads.h:61**: `PPC32_FUTEX_WAIT_BITSET 9U` added.
**threads.c:382-384**: Gate now accepts cmd 9 alongside WAIT/WAKE/REQUEUE/CMP_REQUEUE.
**threads.c:405-406**: `val3 == 0U` → `-EINVAL` (kernel parity).
**threads.c:410-414**: Comparand byte-swapped (`ppc32_be32`), val3 passed unswapped for BITSET, 0 for plain WAIT. Correct — the mask is not a memory comparand.
**threads.c:394**: Timeout parsed for both `WAIT` and `WAIT_BITSET`.
**futex_ulock.c:73**: Darwin path accepts WAIT_BITSET.
**futex_ulock.c:79**: val3==0 → EINVAL.
**futex_ulock.c:90-118**: Absolute-to-relative conversion with `CLOCK_REALTIME`/`CLOCK_MONOTONIC` selection, underflow → `ETIMEDOUT`. Clean.
**threads.h:107-111**: Comment updated.

*Note*: The Darwin `__ulock_wait2` path ignores the actual bitset mask (no ulock equivalent), so all wake ops wake all waiters. This produces spurious wakeups but never missed wakeups — NPTL condvar loops re-check the predicate, so this is a safe approximation.

### P32-R10-2 — `execve` ignores siblings → **VERIFIED**

**proc.c:370-374**: Early `ppc32_thread_count() > 1` → `-EBUSY` before any string copy or fd open.
**proc.c:519**: `ctx->is_thread_clone = false` after register/identity reset.

The defect allowed "terminate/join siblings (or reject)"; the fix chose reject. `-EBUSY` is not a Linux-standard `execve` errno, but NPTL programs exec from the main thread after joining; this is a safe conservative choice that prevents the stale-table / unmapped-window crash described in the defect.

### P32-R10-3 — `execve` leaks `FD_CLOEXEC` fds → **VERIFIED**

**proc.c:336-356**: New `proc_close_cloexec(int skip_fd)` iterates `[0, sysconf(_SC_OPEN_MAX))`, checks `fcntl(F_GETFD) & FD_CLOEXEC`, closes matches, skips `skip_fd`.
**proc.c:482**: Called as `proc_close_cloexec(fd)` *after* `ppc32_vm_reset_for_exec` / cache invalidation and *before* `ppc32_elf_load(ctx, fd, …)` — the probe fd is protected while elf_load still reads through it.

The approach matches the standard user-space exec emulation pattern. Runtime-internal fds (if any) should not carry `FD_CLOEXEC`, so no translator-owned fd is inadvertently closed.

### P32-R10-4 — `execve` leaves stale DBT blocks → **VERIFIED**

**proc.c:481**: `ppc32_cache_invalidate_all(ctx)` inserted between `ppc32_vm_reset_for_exec(ctx)` (line 480) and `ppc32_elf_load` (line 483). This bumps the cache epoch so every prior translation is invalidated before the new image's segments are loaded at potentially-overlapping VAs.

### P32-R10-5 — `CHILD_CLEARTID` under-validated → **VERIFIED**

**threads.c:577**: `thread_range_ok(parent, child_tid_va, 4U, 2U)` — the `1U` (read prot) is now `2U` (write prot), matching `PARENT_SETTID` (line 568) and `CHILD_SETTID` (line 573). The exit path writes a BE zero to this address, so write-prot validation is correct.

### P32-R10-6 — Fork-style `clone` validates after side effect → **VERIFIED**

**syscalls.c:708-719**: Two new pre-fork blocks:
- `CLONE_PARENT_SETTID` + `a2 != 0U` → `ppc32_vm_range_prot_ok(ctx, a2, 4U, 2U)` (line 710-711)
- `CLONE_CHILD_SETTID` + `a4 != 0U` → `ppc32_vm_range_prot_ok(ctx, a4, 4U, 2U)` (line 715-716)

Both return `-EFAULT` *before* `ppc32_proc_fork(ctx)` at line 720. This mirrors the CLONE_VM path in `threads.c:567-574` and prevents the fork side-effect when the TID store would fault.

### P32-R10-7 — clone-reap vs join double-free → **VERIFIED**

**threads.h (slot struct)**: New `bool joining` field.
**thread_claim_locked** (threads.c:86-88): Reaper skips slots where `joining == true`; sets `joining = true` under lock before unlocking to join.
**thread_claim_locked** (threads.c:104-106): After re-locking, only zeroes the slot if `joining` is still set and `ctx == dead` — guards against slot re-use during the unlocked window.
**ppc32_thread_join** (threads.c:667): Rejects slots already marked `joining` (`-ESRCH`).
**ppc32_thread_join** (threads.c:675): Sets `joining = true` under lock, copies handle+ctx, then unlocks.
**ppc32_thread_join** (threads.c:679-683): On `pthread_join` failure, resets `joining = false` so the slot can be retried.
**ppc32_thread_join** (threads.c:685-690): After successful join, re-locks, confirms `ctx == child`, zeroes slot.
**thread_fork_child** (threads.c:203): Resets `joining = false` on all slots.
**New slot claim** (threads.c:112): Initializes `joining = false`.

The protocol is sound: both reaper and joiner atomically claim ownership via `joining` under the lock, preventing concurrent `pthread_join` + double `free`.

---

## Curated C11 Compliance

| Check | Result |
|-------|--------|
| VLAs | None in changed files (grep: only fixed `int fds[2]`) |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| File sizes | `futex_ulock.c` 177, `proc.c` **900**, `syscalls.c` 776, `threads.c` **899**, `threads.h` 158 — all <= 900 |

`proc.c` is at the exact 900-line limit — no headroom for future additions without a split.

## Newly Introduced Issues

**None at regression severity.** Two pedantic notes:

1. **threads.c:104** — `g_thread_table[ri].ctx == dead` compares against a freed pointer (`free(dead)` at line 102). The pointer is not dereferenced, and the `joining` flag prevents any other thread from modifying the slot, so the comparison is safe in practice. Technically indeterminate per C11 6.2.4p2, but no real compiler exploits this for bare pointer comparison. Cosmetic, not a defect.

2. **futex_ulock.c:113-117** — The `dsec * 1e9 + dnsec` subtraction path (`dnsec < 0`) can underflow `timeout_ns` if `dsec == 0` slipped past the `dsec < 0 || (dsec == 0 && dnsec <= 0)` guard. Trace: `dsec == 1, dnsec == -999999999` → `timeout_ns = 1e9 - 999999999 = 1` — correct. `dsec == 0` is excluded by the guard when `dnsec <= 0`. So the subtraction path only executes when `dsec >= 1`, ensuring `timeout_ns >= 1e9` before the subtract — no underflow possible.

## Summary

| Item | Verdict |
|------|---------|
| P32-R10-1 | **VERIFIED** |
| P32-R10-2 | **VERIFIED** |
| P32-R10-3 | **VERIFIED** |
| P32-R10-4 | **VERIFIED** |
| P32-R10-5 | **VERIFIED** |
| P32-R10-6 | **VERIFIED** |
| P32-R10-7 | **VERIFIED** |

All 7 items addressed. No regressions. C11 compliance clean. `proc.c` at exactly 900 lines — watch it on the next edit.
