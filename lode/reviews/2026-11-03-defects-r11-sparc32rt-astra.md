# Round-11 static audit: signals / sigaltstack / frames / safe-syscall

Scope note: `src/os/signals.c`, `signals_rt.c`, `signals_frame.c` do not exist. Audited the real owners: [syscalls_sig.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_sig.c), [threads_sig.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c), [threads_kill.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_kill.c), [sigframe_sparc32rt.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/sigframe_sparc32rt.h), [interp_signal.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c), [safe_syscall_a64.S](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/safe_syscall_a64.S), plus [threads.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.h), [threads.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c).

| ID | Where | Symptom |
|---|---|---|
| S32-R11-1 | threads.h conv | 7/29 alias |
| S32-R11-2 | syscalls_sig.c altstack | wrong ONSTACK |
| S32-R11-3 | syscalls_sig.c altstack | missing EPERM |
| S32-R11-4 | syscalls_sig.c altstack | rejects AUTODISARM |

## S32-R11-1: SPARC 7 / 29 alias to host signals

`src/os/threads.h:48-88` (`sparc32_sig_to_host`) has no case for 7 and no case for 29; default returns identity. `src/os/threads.h:90-144` (`sparc32_sig_from_host`) maps host `SIGBUS(7)->10` and host `SIGIO(29)->23`.

Result is non-bijective on Linux:

- guest `7 (SIGEMT)->host 7`, guest `10 (SIGBUS)->host 7`. Both install the same host handler via `src/os/syscalls_sig.c:98-104`.
- guest `23 (SIGIO)->host 29`, guest `29 (SIGLOST)->host 29`. Both install the same host handler.
- `from_host(7)->10`, never `7`; `from_host(29)->23`, never `29`.

Repro:

1. `rt_sigaction(7, handlerA)` then `rt_sigaction(10, handlerB)`: second `sigaction(host SIGBUS)` overwrites the first. Host `SIGBUS` always pends `10` via `src/os/threads.c:267-275`. Handler A starves.
2. `kill(getpid(),7)`: `src/os/threads_kill.c:83-90` does host `kill(SIGBUS)` plus `thr_kill_self(7)`; async handler then pends `10`. One guest kill pends two signals.
3. Same for `23` vs `29`, and `wait4` status via `src/os/threads.c:591-596` can never report `7` or `29`.

Fix: treat `7`/`29` as pure-emulation (no host delegate): exclude them in `sig_host_sync`, skip the host `kill`/`tgkill` for them, keep only the translator pending bit, and make `to_host`/`from_host` inverses.

## S32-R11-2: accepts `SS_ONSTACK` as new flags

`src/os/syscalls_sig.c:443-444`:

```c
if (in_flags !=0U && in_flags != SPARC_SS_ONSTACK) return -EINVAL;
```

`SS_ONSTACK(1)` is a query result, not a settable value. Linux rejects it with `EINVAL`.

Repro: `sigaltstack({sp, flags=1, size>=4096})` returns `0`; oracle returns `EINVAL`.

Fix: reject `1`:

```c
if (in_flags != 0U) return -EINVAL;
```

plus explicit `SS_DISABLE` / `SS_AUTODISARM` handling below.

## S32-R11-3: `SS_DISABLE` while onstack succeeds

`src/os/syscalls_sig.c:437-442` disables unconditionally without checking `ALT_ONSTACK`. Linux returns `EPERM` when executing on the altstack.

Repro: install altstack, deliver `SA_ONSTACK` signal (sets `ALT_ONSTACK` in `src/interp/interp_signal.c:60-63`), call `sigaltstack(SS_DISABLE)` from the handler. Returns `0` and clears; oracle returns `EPERM`.

Fix: check first:

```c
if (in_flags == SPARC_SS_DISABLE) {
    if ((ctx->altstack_flags & ALT_ONSTACK) != 0U) return -EPERM;
    ...
}
```

## S32-R11-4: rejects `SS_AUTODISARM`

Same check at `src/os/syscalls_sig.c:443-444` rejects `0x80000000`. Linux accepts `SS_AUTODISARM` (alone and with `SS_DISABLE`).

Repro: `sigaltstack({sp, flags=SS_AUTODISARM, size>=4096})` returns `EINVAL`; oracle returns `0`.

Fix: accept and store the bit, and clear `ALT_ENABLED` in `sigreturn_restore_common` when it was set.

## Clean (0 defects)

- Frame geometry: 344 B, `ss/info/regs/mask/fpu_save/insns/stack/extra_size/rwin_save` offsets in [sigframe_sparc32rt.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/sigframe_sparc32rt.h:54-63) match delivery in [interp_signal.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:219-303) and restore in [syscalls_sig.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_sig.c:464-532). BE helpers consistent; window spill covers `L0..L7/I0..I7` correctly; `pc`/`npc` alignment and `rwin_save==0` checks present.
- `rt_sigprocmask` how `1/2/4`, `sigsetsize==8`, alias-safe snapshot: no defect.
- `safe_syscall_a64.S:45-54`: single `svc`, only `x0-x8`, no `x18`. Sync faults excluded from host handlers in `syscalls_sig.c:101-103`. No defect found.

