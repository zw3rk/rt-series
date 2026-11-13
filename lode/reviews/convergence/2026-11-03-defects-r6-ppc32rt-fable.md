# Round-6 Remediation Verification — `ppc32rt` @ `c529e45`

**Scope:** commit `c529e45` ("remediate Round-6 defects (P32-R6-1..7)") against `rt-series/lode/reviews/2026-11-03-defects-r6-ppc32rt-astra.md` and `rt-series/DEFECTS.md` §4 (P32-R6-1..7).
**Method:** static review of the diff and surrounding code, plus native build, the host regression suite, and the musl cross build. No Docker/QEMU guest runs.

## Summary

| Item | Severity | Verdict | One-line reason |
|---|---|---|---|
| P32-R6-1 | HIGH | **PARTIAL** | Lock and retire list added, but reclaim has no quiescence guarantee, peer IBTC/RAS sync is dead code, and the new mutex is missing from the fork protocol. |
| P32-R6-2 | HIGH | **VERIFIED** | Static staging buffer replaced by a per-call stack array. |
| P32-R6-3 | HIGH | **VERIFIED** (minor gaps) | Distinct `exit` / `exit_group` paths for workers and the initial thread. |
| P32-R6-4 | MEDIUM | **VERIFIED** | Child clears `CR0.SO`; bit value is correct. |
| P32-R6-5 | MEDIUM | **VERIFIED** | `set_tid_address` and `gettid` share one backend returning the guest TID. |
| P32-R6-6 | MEDIUM | **PARTIAL** | Sibling lookup and pend work, but delivery is neither prompt nor interrupting, and the pend is a racy RMW. |
| P32-R6-7 | HIGH | **VERIFIED** (one pre-existing cap noted) | Checked `ppc32_vm_copyout_safe` copyout with partial-result handling. |

Build evidence:

```
make check            -> syntax check OK (40 files), line limits OK, check_abi_invariants: ALL OK
make test             -> check_p32_defects: ALL OK   (suite contains no R6 cases)
nix build .#ppc32rt   -> exit=0  (/nix/store/bs1n7n2y...-ppc32rt-aarch64-unknown-linux-musl-0.1.0)
```

The DEFECTS.md checkboxes for all seven items are still unticked; that matches the verdicts above only for R6-1 and R6-6.

## Per-item detail

### P32-R6-1 — thread-safe cache eviction — PARTIAL

What landed (`src/dbt/cache.c`):
- `s_cache_lock` (line 71) serializes lookup, install, record, invalidation, and the SMC hook.
- Evicted blocks go onto a retire list; `block_free_now` runs only from `reclaim_retired_locked` (line 121), which frees every node whose epoch differs from the current one.
- The epoch is bumped on every eviction and invalidation, so emitted epoch checks stop chained entry into retired code.

Why it is partial:
1. **Reclamation is "one bump later", not "after all threads left".** `reclaim_retired_locked` (lines 490, 493, 629, 726) frees anything retired under an older epoch. Two back-to-back bumps on thread B (two collisions, or an invalidation followed by an install) unmap a block that thread A entered before the first bump and is still executing, for example while preempted by the host. The window shrank from "immediately" to "until the next generation", which is not a safety guarantee. The finding explicitly asked for protection of executing blocks.
2. **Peer IBTC/RAS pointers still dangle.** `ppc32_cache_sync_ctx` (line 654) is defined and declared `extern` in `dbt.c:63` but never called. The comment claims "the dispatch loop calls this before every lookup"; it does not. `sever_ctx_range` (line 628) and `invalidate_all_locked` still clear only the calling context. The inline IBTC/RAS probe in `ppc32_a64_emit2.c:392-410` dereferences `ibtc[].entry` from JIT code, so a peer thread reads a freed block struct once the block is reclaimed. Also, even if the call were added, it would sync only at dispatcher visits, not inside chained execution.
3. **Regression: the new mutex is not fork-safe.** `proc_fork_prepare/parent/child` (`src/os/proc.c:121-150`) handle the signal, thread, VM, TLB, file, and LL locks, but not `s_cache_lock`. A fork from a threaded guest while another thread is inside `ppc32_cache_lookup` or `ppc32_cache_install` leaves the child's mutex permanently locked; the child's first DBT lookup hangs. Pre-commit there was no such lock, so this is new.
4. **Low-probability new hazard:** `snapshot_clean` (line 387) runs `memcmp` on guest memory while holding `s_cache_lock`. A concurrent guest `munmap` of that page from another thread faults; `hostfault.c` recovers via `siglongjmp` with the mutex still held, which deadlocks every subsequent lookup process-wide. Before the lock, the same fault was simply recovered.

Minor: every DBT block dispatch now takes an uncontended mutex in `ppc32_cache_lookup`; no measurement was done, so I note it only as unmeasured.

### P32-R6-2 — `getdents64` static buffer — VERIFIED

`src/os/syscalls_dyn.c:212` replaces `static uint8_t heap[8192]` with a stack array; no remaining `static ...[]` in the file. Workers run on default-size pthread stacks (musl default is small), and 8 KiB plus the dispatcher is well within that, so no concern.

### P32-R6-3 — `exit` vs `exit_group` — VERIFIED

- Worker `exit_group` now `_exit`s with the status (`src/main.c:453`); plain `exit` returns through `thread_entry`, which marks the slot exited.
- Initial-thread `exit` records its status, then waits until `ppc32_thread_count() <= 1` (`main.c:493-499`) before returning; a worker `exit_group` during that wait still terminates the process with the worker's status. This matches Linux wait status rules for a leader that exited with `exit(2)`.

Minor gaps, not blocking: the wait is a `sched_yield` busy loop; the initial thread's own `clear_child_tid` futex wake is not performed on `exit`; a worker dying by unhandled fault returns a negative status to `thread_entry` instead of killing the group; the execve-repark path in `ppc32_run_guest_child` (line 458) still just returns from a worker.

### P32-R6-4 — child `CR0.SO` — VERIFIED

`src/os/threads.c:556` clears `PPC32_CR0_SO`, defined as `1U << 28` in `src/ppc32rt.h:42`, which is the CR0 SO bit. The parent still goes through the normal `sys_apply_ret` normalization.

### P32-R6-5 — `set_tid_address` identity — VERIFIED

`ppc32_gettid` (threads.c) returns `guest_tid` when assigned, else the cached or live host TID; `ppc32_set_tid_address` now returns it, and `ppc32_sig_pid_nr` `GETTID` uses the same backend. `CLONE_PARENT_SETTID`/`CHILD_SETTID` already stored the guest TID. The duplicate `guest_tid != 0` test in `signals.c:833` is redundant but harmless.

### P32-R6-6 — sibling `tkill`/`tgkill` — PARTIAL

What landed: `ppc32_thread_signal` (`threads.c:211`) resolves the guest TID under `thread_lock`, skips exited slots, checks group membership for `tgkill`, probes with signal 0, and sets the target's pending bit. The `tgid` mismatch in `tgkill` still returns `ESRCH` before the lookup, which is correct.

Why it is partial:
1. **No interruption and no prompt delivery.** The pend is consumed only by `ppc32_sig_pump_pending`, whose single caller is the signal-syscall branch (`src/os/syscalls.c:521`). A sibling blocked in a host futex, `read`, or `nanosleep` is not woken, and a compute-bound sibling never runs the handler until it happens to call a signal syscall. Meanwhile the JIT's `emit_exit_sig_check` bails to the dispatcher at every block exit because the pending word is non-zero, so the target crawls without ever being served. `tgkill(SIGKILL)` to a sibling is likewise deferred. The finding asked for a mechanism to interrupt blocked execution; the natural completion is `pthread_kill` on the slot's host thread so the existing host-signal path and `EINTR` handling take over, plus a pump at the generic syscall tail or dispatcher.
2. **Racy pend.** `target->pending_signals |= bit` (`threads.c:232`) is a plain RMW on a `volatile uint64_t` while the target clears bits with its own plain RMWs (`signals.c:305,770,774`). Bits can be lost in either direction. This is the same class as the i686 R6-3 atomic-pending fix recorded in the round summary.

### P32-R6-7 — unchecked `getdents64` stores — VERIFIED

`syscalls_dyn.c:221` pre-checks write permission over the whole `count` range (Linux also `access_ok`s the full count), each record is converted into a private buffer and published via `ppc32_vm_copyout_safe` (line 281), which performs the reservation invalidation and staged-file coherence under the VM lock. A failing copyout mid-stream returns the bytes already landed, matching Linux. `dyn_dents_landed` adds the code-cache eviction the safe copy does not do.

One observation, pre-existing and shared with `sys_read_landed`: `ppc32_smc_store` returns early for `len > 4096` (`cache.c:752`), so a BusyBox-sized 32 KiB `getdents64` or a large `read` into translated pages evicts nothing. Not introduced by this commit, but the new helper's comment promises eviction it cannot deliver for those sizes.

## Recommended follow-ups, in priority order

1. Add `s_cache_lock` to `proc_fork_prepare/parent/child` (or reinitialize it in the child). This is the only outright regression.
2. Replace the one-generation grace with a quiescence rule: reclaim only when every live context has left the JIT or observed a newer epoch than the retired node, e.g. a per-context epoch stamp set on dispatcher entry.
3. Either call `ppc32_cache_sync_ctx` from `dbt_run` before each lookup and from the syscall tail, or delete it; and have invalidation clear IBTC/RAS entries in all registered contexts under `thread_lock`.
4. Make `pending_signals` updates atomic, add a pump at the generic syscall tail and in the dispatcher's bail path, and forward sibling signals to the host thread with `pthread_kill`.
5. Move `snapshot_clean`'s guest `memcmp` outside the lock, or unlock on the fault path.
6. Add R6 cases to `tests/check_p32_defects.c`; the suite currently has none.
