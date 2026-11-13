# Round-11 Static Audit: Signals, Altstack, RT Frames, Fault Recovery

Read-only audit, no files modified, no builds or tests run. Seven concrete defects below; host fault recovery (A2 sub-page / COW / guest translation) is clean.

| ID | Area | Severity | Location |
|---|---|---|---|
| I686-R11-1 | rt_sigpending | High | sys_pass.c:220 |
| I686-R11-2 | DF on entry | High | signals_i386.c:344 |
| I686-R11-3 | KILL/STOP action | Med | sys_pass.c:129 |
| I686-R11-4 | KILL/STOP mask | Med | sys_pass.c:198 |
| I686-R11-5 | Altstack limits | Med | sys_pass.c:234 |
| I686-R11-6 | AUTODISARM | Med | signals_i386.c:141 |
| I686-R11-7 | x87 FIP/FDP | Low | signals_i386.c:164 |

## I686-R11-1 (BUG): `rt_sigpending` always returns empty

[sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:220) fills the output with `zeros` and never reads `pending_signals`. Repro: block `SIGUSR1` via `rt_sigprocmask`, raise it via `tkill`, call `rt_sigpending` — kernel reports the bit, this returns 0. Fix: copy `pending_signals & sig_mask` instead of zeros.

## I686-R11-2 (BUG): `DF` not cleared on handler entry

`sigframe_build_snapshot` ([signals_i386.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:344)) sets `eip`/`esp` but never clears `I686_EF_DF` ([i686rt.h](/Users/angerman/Projects/zw3rk/i686rt/src/i686rt.h:51)). The kernel and i386 ABI guarantee `DF=0` at handler entry. Repro: guest executes `STD`, takes a signal, handler runs `MOVS` — it copies backwards. Fix: `ctx->eflags &= ~I686_EF_DF;` before `eip` is redirected (`DF` lives in `eflags`, not the lazy descriptor).

## I686-R11-3 (BUG): `rt_sigaction` accepts `SIGKILL`/`SIGSTOP` dispositions

[sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:129) checks only `sigsetsize == 8` and `1..64`, with no `9`/`19` rejection. The kernel returns `EINVAL` when `act` is non-NULL for `SIGKILL`/`SIGSTOP`. Repro: `rt_sigaction(9, {handler=c.func})` returns 0 and stores the handler; a later `oldact` query leaks it back. Fix: if `act_va != 0` and `sig` is 9 or 19, return `-EINVAL` (queries with `act == NULL` stay allowed).

## I686-R11-4 (BUG): `rt_sigprocmask` stores `SIGKILL`/`SIGSTOP` bits

[sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:198) stores the mask verbatim; the kernel silently ignores bits 9/19. Two consequences: an `oldset` query reports `KILL` as blocked, and [sys_thread_raise](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_thread.c:143) skips the futex wake for a "masked" `SIGKILL`, so a `tkill(KILL)` to a futex-blocked thread sleeps instead of dying. Delivery itself already exempts 9/19, so only the stored mask and the wake path are wrong. Fix: `m &= ~((1ULL<<8)|(1ULL<<18));` before the `SIG_BLOCK`/`SETMASK` store.

## I686-R11-5 (BUG): `sigaltstack` skips `MINSIGSTKSZ` and flag validation

[sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:234) copies `sp`/`flags`/`size` with no checks. The kernel returns `ENOMEM` for `ss_size < MINSIGSTKSZ` (2048 on i386) and `EINVAL` for unknown `ss_flags` bits. Repro: `sigaltstack({sp, 0, 1})` succeeds here, fails on hardware. Fix: reject `size < 2048` with `-ENOMEM` and `flags & ~(SS_ONSTACK|SS_DISABLE|SS_AUTODISARM)` with `-EINVAL`.

## I686-R11-6 (BUG): `SS_AUTODISARM` stored but never honored

The flag is preserved verbatim ([sys_pass.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:264)), but delivery tests only `0x2` ([signals_i386.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:141)) and `i686_sigreturn` clears `onstack` unconditionally ([signals_i386.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:390)) without setting `SS_DISABLE`. Repro: establish an `AUTODISARM` stack, handle one `SA_ONSTACK` signal, `sigreturn`, raise again — the kernel delivers on the main stack, this reuses the altstack. Fix: on `sigreturn`, if the saved flags carry `SS_AUTODISARM`, set `altstack_flags |= SS_DISABLE`.

## I686-R11-7 (DEFECT): signal `fpstate` zeroes x87 `FIP`/`FDP`/opcode

The builder ([signals_i386.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:164)) memsets the 624 B area and fills only `cwd`/`swd`/`twd`/`mxcsr`/`st`/`xmm`/magic, leaving the fsave `fip`/`fcs`/`foo`/`fos` and FXSAVE `fop`/`fpu_ip2`/`fpu_dp2` zero; restore ([signals_i386.c](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:446)) never touches `ctx->fpu_ip`/`fpu_dp`/`fop`, which the translator otherwise tracks ([h_x87_env.c](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_env.c:32)). Repro: `FLDENV` with nonzero IP, take a signal, handler reads `fpstate` — sees 0, and handler edits to `FIP` are dropped on `sigreturn`. Fix: save all three into both images on build, restore them on return.

## Verified clean (no findings)

- `pretcode`/`sig`/`pinfo`/`puc`: the `rt` struct's pre-push `pinfo`/`puc` values are overwritten by the correct `hdr` store at `frame_va+8`/`+12`; in-guest layout is right.
- `SA_RESTORER` vs vDSO: `__kernel_sigreturn` pops then `119`, `__kernel_rt_sigreturn` does not pop then `173`, matching the `esp-8`/`esp-4` math in `i686_sigreturn`.
- Handler args ride the stack (`sig` / `sig`,`pinfo`,`puc`); GPR/`EFLAGS`/segments/XMM/`mxcsr`/`TOP` restore is complete.
- Host fault recovery: A2 `safe_decode` guard, subpage-lock discipline, matched-page requirement, REP single-step with per-element checks, COW promote plus DBT invalidate on both emulate paths, and the per-loop `s_last_remap_ga` single-retry bound are all coherent.
- Legacy numbers (`signal` 48, `sigaction` 67, `sigsuspend` 72, `sigpending` 73, `sigprocmask` 126, `rt_sigtimedwait` 177, `rt_sigsuspend` 179, `time64` 421) return `-ENOSYS`; with no phase acceptance check covering them, that is out of scope rather than a defect.
