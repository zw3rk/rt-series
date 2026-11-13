Here is the full review.

---

## Round-10 Remediation Review: commit `694e6d8`

### M64-R10-1 — VERIFIED

**Defect**: Leader `execve` with live thread group proceeds unchecked; workers survive with dangling `guest_base`.

**Fix applied** at `src/os/exec.c:401-403`:
```c
if (ctx->is_thread_clone || mips_thread_group_live() > 0) {
    return exec_ret(ctx, -(int64_t)EPERM);
}
```

The old code only checked `ctx->is_thread_clone` (worker threads). The new code adds `mips_thread_group_live() > 0`, which counts active `l4b_slots[]` entries under the thread mutex (`src/os/threads.c:479-491`). A leader with live sibling workers now gets `-EPERM` instead of proceeding to `mips_load_elf` and orphaning peers.

This takes the "refuse with `-EPERM`" approach from the defect report's two-option fix (the alternative being full Linux behavior: terminate siblings and proceed). The crash scenario — workers running on munmapped guest_base — is prevented.

The forward-declared extern at `exec.c:349` (`extern int mips_thread_group_live(void)`) matches the definition at `threads.c:479`.

### M64-R10-2 — VERIFIED

**Defect**: Two sub-issues: (a) `SIG_IGN` lost across `execve`, (b) `sig_blocked` mask cleared.

**Fix (a)** — SIG_IGN preserved, at `src/os/sigact.c:475-478`:
```c
for (i = 0U; i < 129U; i++) {
    if (ctx->sigactions[i].handler != 1U) {
        ctx->sigactions[i].handler = 0U;
    }
```

Previously every handler was unconditionally set to 0 (SIG_DFL). Now `handler == 1` (SIG_IGN) entries are skipped. The `flags`, `mask[]`, and `restorer` fields are still cleared for all entries including SIG_IGN — this matches the Linux kernel's `flush_signal_handlers()` which zeroes `sa_flags` and `sa_mask` unconditionally but preserves SIG_IGN handlers. The `l4a_handler_words[]` mirror is zeroed afterward (`sigact.c:490-491`), which is correct since SIG_IGN (value 1) is not a "handler" (handler >= 2 sets the mirror bit, per `sigact.c:262`).

**Fix (b)** — `sig_blocked` preserved. Two removal sites:
- `src/os/exec.c:357-358` (in `reset_state_for_exec`): the two `ctx->sig_blocked[0/1] = 0U` lines removed
- `src/os/sigact.c:483-484` (in `mips64_signals_reset_for_exec`): same two lines removed

After the fix, `sig_blocked` is untouched across `execve`, matching `signal(7)`.

### Curated C11 Compliance

| Check | Result |
|-------|--------|
| VLAs | None |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| `exec.c` line count | 747 (< 900) |
| `sigact.c` line count | 726 (< 900) |

### No Regressions Introduced

No new logic bugs found. Two cosmetic observations (non-blocking):

1. **Stale file-header comment** in `src/os/exec.c:35-38`: still reads "every signal action returns to SIG_DFL, sig_blocked / pend_queue / sigaltstack / clear_child_tid are cleared ... Under CLONE_THREAD the request is refused with -EPERM." Post-fix, SIG_IGN is preserved, sig_blocked is preserved, and the EPERM guard now also covers live thread groups (not just `CLONE_THREAD` workers). The functional comment above `reset_state_for_exec` (`exec.c:351-353`) was correctly updated.

2. **Redundant zero-stores**: `pend_head`, `pend_count`, `sigalt_sp`, `sigalt_size`, `sigalt_flags`, and `clear_child_tid` are cleared in both `mips64_signals_reset_for_exec` (`sigact.c:484-489`) and `reset_state_for_exec` (`exec.c:357-362`). Harmless (idempotent), but the caller's copies could be removed for clarity.
