# Round-3 Remediation Review: `076461d` vs `205054f` (ppc64rt)

**Result:** 8 of 9 findings are fixed as specified. P64-R3-4 is partially fixed: fabricated timeouts are gone, but the no-deadline idle case still exits or returns `EAGAIN` instead of blocking for a wake event. No regressions were found in the nine remediations. One new consequential follow-up was found outside the numbered items: the exec-time signal inheritance added in the same commit never reaches the new image.

Static review only. No builds, tests, Docker, or QEMU were run.

## Per-item verification

**P64-R3-1 — Partial mremap loses moved region's file backing: VERIFIED**
The new split phase in `src/vm/vm_file_mremap.c:737` computes the intersection of every partially overlapping record with the source range and allocates a destination record carrying the original inode index, sharing mode, protection, and `file_off + (is - gva_start)`. Capacity is reserved before any mutation by `ppc64_vm_file_space_for_mremap()` at `src/os/syscalls_mm_map.c:573`, and the mremap now returns an error code that routes through `rfail` at line 644, which reloads the file snapshot and the full VMA table. The snapshot is saved at line 612 after the preflight grows the table, so a restore never sees a smaller capacity than it rewrites. The regression test in `tests/test_vm_prova.c` moves a shared interior range and confirms the write lands at file offset 4103.

**P64-R3-2 — Inverted right-hand record: VERIFIED**
`orig_end` and `right_off` are captured at `vm_file_mremap.c:781` before `m->gva_end = old_addr`. The right survivor gets `[old_end, orig_end)`. Pointers are re-read by index after `vm_file_alloc_slot()` because growth may realloc the table. The test checks both survivors keep file coverage and that a write to the right survivor reaches offset 12299.

**P64-R3-3 — SS_AUTODISARM nested overwrite: VERIFIED, one low divergence**
`run_deliver` now snapshots the live altstack into `d.stack` before SP selection, builds the frame, and only then zeroes an autodisarm stack when the frame actually landed on it. `run_sig_restore` reinstalls the snapshot with flag validation. Nested trace checked: the second `SA_ONSTACK` delivery inside the handler sees a disabled altstack and uses the live SP, which sits inside the alt region. Returning from the inner handler reinstalls disabled, returning from the outer rearms the stack. The existing `ppc64_sigaltstack_onstack()` exclusion of autodisarm stacks is now correct rather than a bug, because an armed autodisarm stack can never be "on".
Divergence: `run_sig_restore` returns -1 on unknown flag bits or `ss_size < MINSIGSTKSZ` in the frame's `uc_stack`. Linux ignores the return of `restore_altstack`. A handler that scribbles `uc_stack` kills the guest here. Low severity.

**P64-R3-4 — Idle scheduling fabricates timeouts: PARTIAL**
Fixed: `p4_check_futex_deadlines()` expires only due deadlines. `p4_sleep_until_earliest()` compares remaining time per clock, so realtime and monotonic interleave correctly, and both the exit loop and the main futex loop sleep until a real deadline.
Not fixed: when no waiter holds a deadline, the exit loop at `src/os/syscalls_p4.c:442` still breaks and reports process completion with live futex waiters, and the main wait at `syscalls_p4_futex.c` breaks to `EAGAIN`. The only remaining legitimate wake sources in that state are asynchronous host signals (interval timers, `SIGCHLD` from a forked family member, external `kill`). Linux blocks there. This is a defensible deadlock detector for a single-host-thread scheduler, but it is not the "wait for a deadline or wake event" the audit asked for. Also, `EAGAIN` from `FUTEX_WAIT` when the value matched is not a Linux outcome.

**P64-R3-5 — Signals cannot interrupt main futex wait: VERIFIED**
`p4_main_has_deliverable()` is checked at the top of every loop pass and returns `EINTR`. Both runner paths in `src/run/core.c` now drain pending signals when any syscall returns 4, so the handler runs before the guest observes further progress. The readers are registered in `run_sig_install_p4_hook()`, and `syscall_p4_reset()` clears them.
Note: the deliverable test is `pending & ~mask` without a disposition filter. If an ignored signal can ever land in `run_sig_pending`, the main wait would return `EINTR` with no handler run. `run_sig_record` clears pending on ignore install, so this needs a stray queue-time path to trigger. Unverified, low.

**P64-R3-6 — Requeue omits main waiter and misreports count: VERIFIED**
The main waiter is moved to `uaddr2` under the `max_requeue` limit, and both `FUTEX_REQUEUE` and `FUTEX_CMP_REQUEUE` return `woken + reqd`.
Note: the main loop keeps polling the original `uaddr` against `want`. After requeue, a change to the old futex word returns 0 to the main task as a spurious wake. Spurious wakeups are permitted by the futex contract, so low severity.

**P64-R3-7 — Timeout wrap: VERIFIED**
`p4_futex_deadline()` uses `sec <= (UINT64_MAX - nsec) / 1e9` as the multiply guard, which is exact for integer `sec`, and saturates the relative-to-absolute add. A saturated deadline never satisfies `now >= deadline`, and the derived `nanosleep` duration is a valid huge `tv_sec`.

**P64-R3-8 — SIG_IGN leaves child pending bits: VERIFIED**
`syscall_p4_discard_signal()` clears the bit in every task slot. It is called from `run_sig_record()` whenever `run_sig_is_ignored()` holds, which also covers `SIG_DFL` on default-ignore signals. That matches Linux `sig_handler_ignored()`. The parallel `syscall_sigaction` table in `syscalls_access.c` discards only on an explicit `SIG_IGN` handler. Minor inconsistency, not consequential for the runner path.

**P64-R3-9 — Obsolete VMA rollback API: VERIFIED**
`syscall_vma_snapshot()` and `syscall_vma_restore()` are removed from both the source and the header. Only the full-table pair remains, with two live callers.

## Hygiene and Curated C11

- No `#include "*.c"` anywhere in `src/` or `tests/`.
- `check-line-limits` covers both `src/` and `tests/`. Largest files are `src/interp/fp.c` at 890 lines and `tests/test_vm_prova.c` at 875 lines. Both are under 900, but the test file now has 25 lines of headroom.
- New files are 424 and 315 lines. `syscalls_p4.c` shrank substantially.
- The mapping table moved from a fixed array to a heap-growable pointer. No stale `sizeof(g_maps_priv)` or `VM_FILE_MAPS_MAX` users remain. The snapshot format gained a leading capacity word and the loader regrows or truncates safely.
- No prohibited string calls, VLAs, Annex K, or `_Generic` were introduced in the diff.

## Summary table

| Item | Finding | Status | Notes |
|---|---|---|---|
| P64-R3-1 | Partial mremap loses file backing | VERIFIED | Intersection relocated with inode, share mode, and offset. Preflight plus rollback. Test present. |
| P64-R3-2 | Inverted right-hand record | VERIFIED | Original end saved before truncation. Test present. |
| P64-R3-3 | SS_AUTODISARM nested overwrite | VERIFIED | Nested trace correct. `rt_sigreturn` is stricter than Linux on a bad `uc_stack`. |
| P64-R3-4 | Fabricated timeouts, live-task exit | PARTIAL | Real deadlines honored. No-deadline idle still exits or returns `EAGAIN`. |
| P64-R3-5 | Main futex not signal-interruptible | VERIFIED | `EINTR` plus prompt drain in both runners. |
| P64-R3-6 | Requeue misses main, bad count | VERIFIED | Main requeued; both commands count requeued. Spurious wake on old word is low. |
| P64-R3-7 | Timeout wrap | VERIFIED | Checked multiply and saturating add. |
| P64-R3-8 | Stale child pending on SIG_IGN | VERIFIED | All task slots cleared, including default-ignore case. |
| P64-R3-9 | Obsolete VMA rollback API | VERIFIED | Removed, no callers remain. |

## Newly discovered consequential follow-ups

1. **Exec-time signal inheritance is inert (Medium).** `ppc64_proc_execve` publishes the mask, ignore set, and pending set with `setenv()` into the translator's own `environ` at `src/os/proc.c:419`. The host execve at line 425 receives the `envp` vector built from guest memory by `proc_read_strvec`, or an empty vector. The three words never reach the new image. `run_sig_exec_restore()` therefore only fires if the guest's own environment happens to contain those names, which makes the restored state guest-controlled rather than kernel-controlled. This is not a regression against `205054f`, but the cross-RT invariant named in the commit title is not implemented. Fix: append the three words to the constructed `envp`, and have the restore path unset them so the guest never observes them.

2. **P64-R3-4 residual (Medium).** The no-deadline idle path should block for an asynchronous wake rather than exit or return `EAGAIN`. If host-delivered timer and child signals can reach a guest in this state, the current behavior terminates a live process or returns a non-Linux errno. If they cannot, document the deadlock-exit as intentional in the scheduler comment and in the test expectations.

3. **Low items for the backlog.** `rt_sigreturn` hard failure on an ignorable `uc_stack` (R3-3). Requeued main waiter still polls the original futex word (R3-6). `tests/test_vm_prova.c` is within 25 lines of the limit and the next mremap test will need a split.
