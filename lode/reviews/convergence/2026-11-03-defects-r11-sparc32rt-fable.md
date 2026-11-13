I have all the evidence. Here is the complete review.

---

## Round-11 Signal/Fault Remediation Review — d9ac2db

### Files Modified (7), all <= 900 lines

| File | Lines |
|---|---|
| `src/os/threads.h` | 368 |
| `src/os/syscalls_sig.c` | 617 |
| `src/os/threads_kill.c` | 333 |
| `src/os/threads_sig.c` | 311 |
| `src/interp/interp_signal.c` | 852 |
| `src/interp/interp_priv.h` | 76 |
| `tests/check_r11_signals.c` | 78 |

No VLAs, no `.c` includes, no `sprintf`/`strcpy`/`strcat`. Curated C11 clean.

---

### S32-R11-1: SPARC 7/29 alias to host signals — **VERIFIED**

The defect was a non-bijective signal map: guest 7 (SIGEMT) and guest 10 (SIGBUS) both mapped to host 7, and guest 29 (SIGLOST) and guest 23 (SIGIO) both mapped to host 29.

The commit introduces `sparc32_sig_pure_emu()` (`threads.h:58-61`) returning true for 7 and 29, and makes `sparc32_sig_to_host()` return -1 for them (`threads.h:64-66`), breaking the collision. All host-facing paths are guarded (8 call sites total):

- **`sig_host_sync`** — `syscalls_sig.c:108`: early return prevents installing a host handler for 7/29.
- **`sparc32_thr_kill`** — `threads_kill.c:86`: skips host `kill()` for pure-emu signals; falls through to `thr_kill_self` which queues only the translator pending bit (repro #2 fixed).
- **`thr_host_tgkill`** — `threads_kill.c:110`: returns 0 early (no host tgkill/tkill/pthread wakeup).
- **`thr_kill_tid` caught path** — `threads_kill.c:268`: skips wakeup suppress token for pure-emu (no host signal would consume it).
- **`interp_poll_async`** thread queue — `interp_signal.c:661`: skips host `kill()` in default-terminate path.
- **`interp_poll_async`** process queue — `interp_signal.c:695`: same guard.
- **`rt_sigsuspend`** phase 1 — `threads_sig.c:153`: skips host `kill()` in default-terminate path.
- **`rt_sigsuspend`** phase 2 — `threads_sig.c:195`: same guard.

`from_host` is intentionally unchanged: on Linux, host 7 **is** SIGBUS and host 29 **is** SIGIO, so they correctly map to guest 10/23. All three defect repro vectors (overwrite, double-pend, wait4 status) are addressed.

---

### S32-R11-2: accepts SS_ONSTACK as new flags — **VERIFIED**

The old validation `if (in_flags != 0U && in_flags != SPARC_SS_ONSTACK) return -EINVAL` accepted SS_ONSTACK (1) as a settable value.

New validation (`syscalls_sig.c:463`):
```c
if ((in_flags & ~(SPARC_SS_DISABLE | SPARC_SS_AUTODISARM)) != 0U)
    return -EINVAL;
```
Since `1 & ~(2 | 0x80000000) = 1 != 0`, SS_ONSTACK is now correctly rejected with EINVAL. Only DISABLE (2) and AUTODISARM (0x80000000) pass.

---

### S32-R11-3: SS_DISABLE while onstack succeeds — **VERIFIED**

The old code executed DISABLE unconditionally before checking ALT_ONSTACK.

New code (`syscalls_sig.c:458-459`) checks ONSTACK **first**:
```c
if ((ctx->altstack_flags & ALT_ONSTACK) != 0U)
    return -EPERM;
```
This blocks both install and disable while ONSTACK is set, matching Linux `do_sigaltstack`. The EPERM fires before reaching the DISABLE or install paths.

---

### S32-R11-4: rejects SS_AUTODISARM — **VERIFIED**

The old flag check rejected 0x80000000 (SS_AUTODISARM).

The commit:
1. Adds `SPARC32_SS_AUTODISARM 0x80000000U` (`interp_priv.h:47`) and `ALT_AUTODISARM 4U` (`syscalls_sig.c:196`).
2. Accepts AUTODISARM in validation (`syscalls_sig.c:463`).
3. Records AUTODISARM on install (`syscalls_sig.c:482-483`): `ALT_ENABLED | ALT_AUTODISARM`.
4. Implements `sparc32_sigaltstack_auto_disarm_ctx` (`syscalls_sig.c:234-242`): clears `ALT_ENABLED` when `ALT_AUTODISARM` is set.
5. Fires on delivery (`interp_signal.c:66`): after setting ONSTACK, the disarm clears ENABLED — the frame then reports SS_DISABLE and nested signals use the main stack.
6. Fires on sigreturn (`syscalls_sig.c:559`): idempotent since ENABLED is already cleared; the stack stays disabled until the guest re-installs.
7. Preserves AUTODISARM through `set_onstack_ctx` (`syscalls_sig.c:227`): `f = ctx->altstack_flags & (ALT_ENABLED | ALT_AUTODISARM)`.

Lifecycle is correct: install → delivery disarms → frame shows SS_DISABLE → sigreturn keeps disabled → guest must re-install.

---

### Potential Issue Found (minor)

**Autodisarm + sigaltstack from handler**: After delivery on an autodisarmed stack, the translator sets `ALT_ONSTACK` (line 62) before calling `auto_disarm_ctx` (line 66), so the handler runs with flags `ALT_ONSTACK | ALT_AUTODISARM` (no `ALT_ENABLED`). If the handler then calls `sigaltstack(SS_DISABLE)` — redundant but legal on Linux — the `ALT_ONSTACK` check at `syscalls_sig.c:458` returns EPERM, while Linux's `do_sigaltstack` would not consider the process "on-stack" after autodisarm fires (because `sas_ss_reset` zeros `ss_size`, making `on_sig_stack(sp)` false). This is a very narrow edge case (calling sigaltstack from an autodisarm handler is unusual), but it's a semantic divergence from Linux for AUTODISARM stacks.

**Not a regression** — the old code rejected AUTODISARM entirely, so this is new-but-incomplete rather than a newly broken path.

---

### Summary

| Item | Verdict | Key Evidence |
|---|---|---|
| S32-R11-1 | **VERIFIED** | `sparc32_sig_pure_emu` + 8 guarded call sites, `to_host` returns -1 |
| S32-R11-2 | **VERIFIED** | Flag mask `~(DISABLE\|AUTODISARM)` rejects ONSTACK at `syscalls_sig.c:463` |
| S32-R11-3 | **VERIFIED** | EPERM check at `syscalls_sig.c:458` fires before DISABLE path |
| S32-R11-4 | **VERIFIED** | `ALT_AUTODISARM` stored, fired on delivery+sigreturn, frame reports SS_DISABLE |

All 4 items verified. One minor AUTODISARM edge-case divergence noted (not a regression). No C11 compliance violations. All files under 900 lines. No `.c` includes. Test file pins the conversion invariants and flag constants.
