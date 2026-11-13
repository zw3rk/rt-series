## Round-11 Signal Remediation Review — Commit `a78b02b`

### S64-R11-1: **VERIFIED**

The defect reported that `sparc64_sync_sig_queue` and `sparc64_sync_sig_deliver_pending` conflated `SIG_DFL` (`handler == 0`) with `SIG_IGN` (`handler == 1`), treating both as fatal (`return -1`). The fix splits the combined check into two separate clauses in both functions:

**`sparc64_sync_sig_queue` (src/os/sync_sig.c:476-481):**
- `handler == 1` (SIG_IGN): clears the pending bit (`sync_resolve(ctx)->pending &= ~sig_mask_bit(signo)`) and returns `0` — signal silently discarded. Placed before the blocked check at line 483, so ignored signals are discarded even when blocked. This matches POSIX semantics and the defect report's prescription.
- `handler == 0` (SIG_DFL): still returns `-1` (fatal). Unchanged behavior.

**`sparc64_sync_sig_deliver_pending` (src/os/sync_sig.c:678-683):**
- `handler == 1`: clears pending bit via `st->pending &= ~sig_mask_bit(signo)` and `continue`s to the next signal. `st` is correctly loaded from `sync_resolve(ctx)` at line 669.
- `handler == 0`: still returns `-1`. Unchanged behavior.

**Fault-trap path preserved:** `sparc64_sync_sig_deliver` at line 518 still has `if (handler == UINT64_C(0) || handler == UINT64_C(1)) { return -1; }` — synchronous faults remain fatal even when ignored, which is correct Linux semantics. The defect report explicitly required this path be left alone.

**Consistency with module contract:** `sparc64_sync_sig_install_full` (line 141) accepts `handler == 1`, and `sparc64_sync_sig_exec_reset` (line 288) preserves `SIG_IGN` across `execve` — the fix now makes the queue/deliver paths consistent with these.

### Newly Introduced Bugs: **None found**

- The `deliverable` snapshot at line 670 is computed before the loop clears pending bits for SIG_IGN signals — this is correct. The loop iterates the snapshot; clearing pending during iteration only affects future `deliver_pending` calls, not the current pass.
- If all deliverable signals are SIG_IGN, the loop exhausts and returns `1` at line 688 (no signals to deliver), which is the correct "nothing pending" return.
- No double-evaluation risk: `sync_handler[(unsigned)signo]` is read from a module-static array, not a volatile or concurrent source.

### Curated C11 Compliance: **Pass**

| Check | Result |
|---|---|
| File <= 900 lines | 769 lines — pass |
| No VLAs | None — pass |
| No `.c` includes | None — pass |
| No `sprintf`/`strcpy`/`strcat` | None — pass |
| No `_Generic` / Annex K | None — pass |
| `UINT64_C()` literal style | Consistent — pass |

### Summary

**S64-R11-1: VERIFIED.** The fix is a minimal, exact match to the prescribed surgical repair. Both async paths correctly separate SIG_IGN (discard + return 0/continue) from SIG_DFL (fatal), the fault-trap path is left intact, and no new defects were introduced. File stays well within the 900-line limit at 769 lines.
