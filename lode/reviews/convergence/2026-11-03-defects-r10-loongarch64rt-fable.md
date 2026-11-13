I have all the evidence needed. Here is the full review.

---

## Static Review: Commit `4882cbb` vs LA64-R9-5, LA64-R10-1, LA64-R10-2

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None in diff or changed files |
| `.c` includes | None in changed files |
| `sprintf`/`strcpy`/`strcat` | None in changed files |
| File size <= 900 lines | `clone.c` 898, `mem_min.c` 892, `minsys.c` 796, `vm_file.c` 899, `vm_file_sync.c` 899 — all pass |

### LA64-R10-1: `clone_lock` self-deadlock on worker thread exit — **VERIFIED**

**Defect**: `la64_sched_thread_exit(me, word, clone_store_u32)` was called while holding `clone_lock` (line 668). The callback `clone_store_u32` → `la64_clone_invalidate_ll` → `la64_clone_store_lock()` + `pthread_mutex_lock(&clone_lock)` at `clone.c:749-751`. Same thread, non-recursive mutex → self-deadlock.

**Fix**: `clone.c:682` now passes `clear_word = 0`. In `sched.c:258`, `if (clear_word != 0)` gates the callback, so the `clone_store_u32` callback is **never invoked under `clone_lock`**. The ring removal (`sched_remove` + broadcast) still happens atomically under `sched_mu`. After `clone_lock` is released at line 686:

- **Linux path** (lines 688–708): manual `dbt_smc_store` + `memcpy` zero + `la64_clone_invalidate_ll` (now safe, lock free) + **new** `la64_sched_wake` (lines 700–701) + two host `SYS_futex` wakes.
- **Non-Linux path** (lines 711–716): `clone_store_u32(ctid_va, 0)` (safe, lock free) + **new** `la64_sched_wake` (lines 714–715).

The `la64_sched_wake` calls restore the sched-queue wakeup that the old `sched_wake_locked` inside `sched_thread_exit` was providing. `sched_wake_locked` (`sched.c:91–107`) finds waiters by address match and broadcasts `sched_cv`, so post-store waiters are correctly unblocked. No lost-wakeup window: the `sched_remove` + broadcast handles already-sleeping waiters; the post-unlock `sched_wake` handles anyone who entered the wait between broadcast and store.

Comment at lines 675–678 accurately describes the contract.

### LA64-R10-2: `execve` proceeds with live clone workers — **VERIFIED**

**Defect**: `sys_execve` had no live-worker gate, unlike `sys_clone_process` at `minsys.c:216`.

**Fix**: `minsys.c:451–454` adds the identical gate:
```c
if (la64_clone_has_live_workers() != 0)
    return -(long)LA64_EAGAIN;
```

`la64_clone_has_live_workers` (`clone.c:867–879`) iterates `clone_slots[]` under `clone_lock`, returns nonzero if any slot is live. The `EAGAIN` return matches POSIX `execve` semantics (implementation-defined error when the process has threads; Linux sends `SIGKILL` to siblings, but this emulator's single-threaded-only model is documented in the contract comment at lines 432–439). The gate is placed before any `copy_guest_string` / argument marshaling, avoiding wasted work.

### LA64-R9-5: Staged `MAP_SHARED` goes private across `fork` — **PARTIAL**

**Defect**: On Darwin 16 KiB hosts, unaligned shared file maps use staged anonymous pages. Host `fork` duplicates these privately, so post-fork stores in one process never reach the other.

**What the fix does** (two sites):

1. **Fork pre-copy** (`vm_file.c:189–197`): In `vmfile_fork_reserve`, under `vmfile_take_lock`, iterates all maps and calls `vmfile_staged_writeback_locked` for every used/shared/dirty map. This flushes dirty staged bytes to the backing file before `fork`, so the child inherits current data.

2. **Write-through on store** (`vm_file_sync.c:236–238`): In `vmfile_note_store`, after marking dirty and recording the epoch, calls `vmfile_staged_writeback_locked(i, s, e)` to immediately write through to the shared file. The generation bump is visible to forked processes.

**Why PARTIAL**: The commit fixes fork-time coherence (child starts with current data) and makes post-fork stores in the **storing** process visible via the file, but the **other** process must re-read from the file to see them. The original defect notes: "back staged-shared maps with shared memory or fault them on writeback post-fork." The write-through approach is a correct mitigation that ensures stores reach the file, but the cross-process propagation relies on the generation/epoch mechanism — a reader in the forked child seeing a generation bump must re-fault from the file. If the child reads without a generation check (e.g., via cached staged pages that were CoW-duplicated at fork), it sees stale data. This is a **narrowing** of the defect window, not a complete closure. Cross-process `MAP_SHARED` coherence within the same epoch (no intervening SMC or msync) remains incomplete for staged maps.

### `mem_min.c` changes — **Comment-only, no behavioral change**

All 7 hunks in `mem_min.c` are comment rewording (shortening multi-line comments to fit style). No code changes. No review concern.

### `vm_file.c` comment changes — Same: non-behavioral shortening alongside the R9-5 code fix.

---

### Summary Table

| ID | Severity | Verdict | Evidence |
|---|---|---|---|
| LA64-R10-1 | BUG (self-deadlock) | **VERIFIED** | `clone.c:682` passes `clear_word=0`, `sched.c:258` skips callback; post-unlock paths at `clone.c:688–716` restore store + LL-invalidate + sched-wake + futex-wake without holding `clone_lock` |
| LA64-R10-2 | DEFECT (missing gate) | **VERIFIED** | `minsys.c:451–454` mirrors the `sys_clone_process` gate at `minsys.c:216` |
| LA64-R9-5 | Med (fork incoherence) | **PARTIAL** | Fork-time flush (`vm_file.c:189–197`) and write-through on store (`vm_file_sync.c:236–238`) narrow the window; full cross-process staged-shared coherence (reader-side re-fault from file on generation mismatch) not addressed in this commit |

### Newly Introduced Bugs: **None found**

The `la64_sched_wake` additions are correct (address-matched, broadcast on hit). The `UINT32_C(0xffffffff)` mask/count arguments match the "wake all" semantics. Discarded `vmfile_staged_writeback_locked` return values are acceptable (failure leaves stale data, same as pre-fix). File sizes are at 898/899 — tight but within the 900-line limit.
