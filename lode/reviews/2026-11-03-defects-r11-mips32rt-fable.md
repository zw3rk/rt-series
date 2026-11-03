Good — I have all the evidence. Here is the complete review.

---

## Round-11 Remediation Review — Commit `5c8a583`

### M32-R11-1: `mips_trap`/`mips_trap_code` raise host with untranslated MIPS number

**Verdict: VERIFIED**

Both `mips_trap` (`signals.c:675`) and `mips_trap_code` (`signals.c:689`) now call `mips_signal_default_die(signo)` instead of the former inline `(void)raise(signo); _Exit(128 + (signo & 0x7F))`. `mips_signal_default_die` (`kill.c:133-144`) translates via `mips_to_host_fatal_sig` before `raise()`, falling back to `_Exit`-only when no host equivalent exists. The mapping table is correct for all 22 fatal signals (verified programmatically). The `_Exit` fallback for unmapped signals (e.g. `SIGEMT=7` on MIPS) is the right behaviour — no host equivalent exists.

No new bugs. Clean fix.

---

### M32-R11-2: `wait4`/`waitpid` passes host signal numbers through in status

**Verdict: VERIFIED**

`proc_wait_common` (`proc.c:519-533`) now decodes the `waitpid` status word and remaps the signal field:
- `WIFSIGNALED`: replaces bits 0..6 via `proc_host_to_mips_sig(WTERMSIG(status))`, preserving the core-dump bit (bit 7) in `status & ~0x7F`.
- `WIFSTOPPED`: replaces bits 8..15 via `proc_host_to_mips_sig(WSTOPSIG(status))`, preserving the low byte (`0x7F` stop marker).
- `WIFCONTINUED` (`0xFFFF`) and normal exit (`WIFEXITED`) are untouched — correct, as they carry no signal field.

The `proc_host_to_mips_sig` mapping (`proc.c:456-483`) covers all 30 standard signals with correct MIPS O32 numbers (verified programmatically against `arch/mips/include/uapi/asm/signal.h`). The `default: return host_sig` passthrough for exotic/RT signals is safe. `<signal.h>` is properly included (`proc.c:41`). The `#ifdef SIGPWR` / `#ifdef SIGPOLL` / `#elif defined(SIGIO)` guards handle portability correctly.

The comment block at `proc.c:448-454` was updated to reflect the new mapping.

**Style nit (not a bug)**: Missing blank line between `proc_host_to_mips_sig` closing brace (`proc.c:483`) and `proc_wait_common` function definition (`proc.c:484`). This is cosmetic only.

No new bugs. Clean fix.

---

### M32-R11-3: `tkill`/`tgkill` signo-0 existence check bypasses tid validation

**Verdict: VERIFIED**

The tid liveness check (`kill.c:199-203`) is now positioned *before* the `signo == 0` early return (`kill.c:204-210`). Previously, `signo == 0` with a bogus tid would return success (existence confirmed) without ever checking whether the tid was live. Now:

1. EINVAL check on signo range (`kill.c:192-193`) — unchanged, still first.
2. **New position**: tid != self_tid returns ESRCH (`kill.c:199-202`) — runs for all signo including 0.
3. signo == 0 existence probe (`kill.c:204-209`) — only reachable when tid matches self.

For plain `kill()`, `tid` is initialized to `self_tid` at `kill.c:178`, so the new check is a no-op — `kill(pid, 0)` behaviour is unchanged. For `tkill`/`tgkill`, the guest-supplied tid is checked first, matching Linux semantics where `tkill(dead_tid, 0)` returns ESRCH.

No new bugs. Clean fix.

---

### M32-R11-4: `rt_sigaction` installing a handler does not deliver already-pending signals

**Verdict: VERIFIED**

`mips_sc_rt_sigaction` (`signals.c:300`) now calls `mips_signal_deliver_pending(ctx)` after installing the new disposition, matching the existing calls in `rt_sigprocmask` (`signals.c:377`) and `rt_sigreturn` (`signals.c:663`).

The call is safe in this position because:
- It runs *after* the `g_sig_lock` is released (`signals.c:293`), so no deadlock.
- `mips_signal_deliver_pending` (`sigqueue.c:141-169`) iterates pending signals, checks `mips_signal_has_handler` (re-acquires `g_sig_lock` transiently), and delivers the first deliverable one via `mips_raise_guest_code`. It's the same codepath used by the other two callers.
- The call is inside the `if (have_in)` block, so it only fires when a new disposition was actually installed — querying `oact` alone does not trigger spurious delivery.
- The call happens before `mips_sc_ret(ctx, 0)` at line 302. `mips_signal_deliver_pending` may redirect `ctx->pc` to the handler. The subsequent `mips_sc_ret` overwrites `$v0`/`$a3` but does *not* touch `ctx->pc`, so delivery is preserved.

**One subtlety worth noting** (not a bug): Unlike `rt_sigprocmask` which calls `mips_sc_advance_pc_once(ctx)` *before* `deliver_pending` (`signals.c:376-377`), `rt_sigaction` does *not* explicitly advance PC before delivery. This is correct because `rt_sigaction` returns through `mips_sc_ret` → the caller in `syscall_min.c` or the engine loop advances PC on the syscall return path. The frame built by `mips_raise_guest_code` snapshots the current `ctx->pc` (which is the syscall trap instruction), and `rt_sigreturn` restores it — the engine then advances past the syscall. This matches `rt_sigprocmask`'s explicit advance only because `rt_sigprocmask` uses a different return convention (`return 0` without `mips_sc_ret`, line 378).

No new bugs. Clean fix.

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None. All arrays use compile-time constants (`L4A_KERN_SIGACTION_SIZE`, `sizeof(mips_rt_sigframe_t)`, `PROC_PATH_MAX`, `PROC_RUSAGE_SIZE`). |
| `.c` includes | None found in the three modified files. |
| File line counts | `kill.c`: 262, `proc.c`: **898** (2 lines under limit), `signals.c`: 824. All <= 900. |
| `sprintf`/`strcpy`/`strcat` | None. Only `snprintf` and `memcpy` used. |
| `_Generic` / Annex K / `<threads.h>` | None. |

### Summary

| Item | Classification | Notes |
|---|---|---|
| M32-R11-1 | **VERIFIED** | `mips_trap`/`mips_trap_code` now route through `mips_signal_default_die` with correct MIPS→host translation. |
| M32-R11-2 | **VERIFIED** | `wait4`/`waitpid` status signal fields remapped host→MIPS; core-dump bit, stop flag, exit codes preserved. Mapping table covers all 30 signals correctly. |
| M32-R11-3 | **VERIFIED** | tid liveness check moved before signo-0 early return; `kill()` path unaffected (tid pre-set to self). |
| M32-R11-4 | **VERIFIED** | `mips_signal_deliver_pending` called after handler install; safe w.r.t. locking, return convention, and conditional scope. |
| New bugs | **None found** | |
| C11 compliance | **Pass** | No VLAs, no `.c` includes, all files <= 900 lines. |

One cosmetic nit: `proc.c:483-484` is missing a blank line between `proc_host_to_mips_sig` and `proc_wait_common`. Not a correctness issue.
