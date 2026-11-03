# Round-5 Post-Remediation Verification: `mips64rt` @ `4fee604`

Scope: static review of commit `4fee604` ("mips64rt: remediate Round-5 defects (M64-R5-1..11)") against the 11 items in `lode/reviews/2026-11-03-defects-r5-mips64rt-astra.md`. Four tool turns used. No build, test, Docker, or QEMU run. All conclusions are from reading the diff and surrounding code.

## Summary

| Item | Title | Verdict |
|---|---|---|
| M64-R5-1 | `clock_nanosleep` argument layout | **VERIFIED** (dead wrapper residue) |
| M64-R5-2 | Failed inode refresh reported as success | **VERIFIED** |
| M64-R5-3 | `CVT.S.D` / `CVT.D.S` sNaN Invalid | **VERIFIED** |
| M64-R5-4 | `CFC1` sign extension | **VERIFIED** |
| M64-R5-5 | Leader raw `exit` kills siblings | **PARTIAL** |
| M64-R5-6 | Predictable `AT_RANDOM` | **PARTIAL** |
| M64-R5-7 | Duplicate record on left coalesce | **VERIFIED** |
| M64-R5-8 | Provider capacity preflight | **VERIFIED** (conservative, see note) |
| M64-R5-9 | Difftest certifies two failures | **PARTIAL** |
| M64-R5-10 | `clock_getres` not dispatched | **VERIFIED** |
| M64-R5-11 | FP emitter dead guard / constant / comment | **VERIFIED** |

8 VERIFIED, 3 PARTIAL, 0 REGRESSION, 0 NOT FIXED.

## Per-item evidence

### M64-R5-1 — VERIFIED
- `src/os/syscall_min.c:698-704`: both `clock_nanosleep` routes now pass `a0, a1, a2, a3` (clk, flags, req, rem) to `mips_sc_clock_nanosleep`; plain `nanosleep` at `:687-690` passes `(a0, a1)`.
- `src/os/syscalls_time.c:103-104`: `mips_sc_nanosleep` reduced to `(req_va, rem_va, is64)`; the `use_clock`/errno path is gone.
- `src/os/syscalls_extra.c:179-180`: remainder copy-out is now gated on `saved_err == EINTR && (flags & TIMER_ABSTIME) == 0`, closing the uninitialised `rm` copy after an interrupted absolute sleep.
- Residue: `src/os/syscalls_extra.c:201-212` adds two exported wrappers, `mips_sys_clock_nanosleep4` and `mips_sys_clock_getres`, with no callers anywhere in `src/`, `tests/`, or `include/`. They compile silently under `-Werror` because they are non-static, but they are YAGNI dead code introduced by a DRY fix. Recommend deleting.

### M64-R5-2 — VERIFIED
- `src/vm/vm64.c:503-518`: `pread` loop retries `EINTR`, continues short reads, treats `0` as EOF, and on a hard error restores protection and returns `-1` (`:510-513`). Only the EOF tail is zero-filled (`:519-521`).
- Caller `src/vm/vm_file.c:700-703` already sets `ok = 0` on non-zero return, and `:707-711` only advances `seen_write_seq`/`seen_resize_seq`/`min_size` when `ok != 0`. The Round-4 retry is therefore preserved on failure.
- Note: the read is still in place rather than staged. A mid-span hard error leaves the first `have` bytes refreshed and the rest stale, but the failure is now reported and retried, so the alias is not wrongly marked current.

### M64-R5-3 — VERIFIED
- `src/interp/fp_cvt.c:118-120` (`CVT.S.D`) and `:138-140` (`CVT.D.S`) classify the original source bits with `fp_issn_d`/`fp_issn_s` and call `fp_raise(ctx, FP_EXC_V)` before writing the default NaN.
- The "write destination, raise, return 0" shape matches the existing overflow paths in the same function (`:77-79`, `:88-90`), so the caller's `fp_finish_trap` destination-restoration path (declared `fp*.h:64`) applies uniformly. Trap delivery itself was not executed.

### M64-R5-4 — VERIFIED
- `src/interp/fpmove.c:183`: `interp_set_reg(ctx, rt, interp_sext32(ctx->fcsr))`.
- `src/interp/fpmove.c:187-188`: FIR read also sign-extended for consistency.

### M64-R5-5 — PARTIAL
Fixed:
- `src/os/syscall_min.c:570-582`: raw `exit` from a non-clone context with `mips_thread_group_live() > 0` drops its quiescence lease and sleeps in 1 ms steps until the worker table empties, then `_Exit`s with the leader's status. `exit_group` still falls through to the direct `_Exit` path.
- `src/os/threads.c:466-479`: `mips_thread_group_live` counts used `l4b_slots` under `l4b_mu`.
- `src/os/threads.c:497-502`: same wait inserted in `mips_thread_exit` for a non-clone context.
- The leader context is never freed, so `l4b_leader_ctx` (`threads.c:160,180`) stays valid for signal routing. Exit status matches Linux, which reports the leader's `exit_code` when the leader exited first and the last thread exits raw; a worker `exit_group(n)` still wins with `n`.

Not addressed:
- The leader's `CLONE_CHILD_CLEARTID` word (set via `set_tid_address`) is not cleared and no `FUTEX_WAKE` is issued when the leader "exits". A worker that `pthread_join`s the main thread will block on that word forever while the leader blocks waiting for the worker: a two-way deadlock. Linux clears/wakes it for the leader exactly as for any thread.
- The wait loop exists twice (`syscall_min.c:574-576`, `threads.c:498-501`). Routing the dispatcher case through `mips_thread_exit` would remove the duplication.
- Polling rather than joining is acceptable but worth a comment on the 1 ms granularity.

### M64-R5-6 — PARTIAL
Fixed:
- `src/loader.c:256-275`: production path opens `/dev/urandom` with `O_CLOEXEC`, loops until 16 bytes, retries `EINTR`, and returns on success. Required headers (`<errno.h>`, `<fcntl.h>`, `<unistd.h>`) and `_POSIX_C_SOURCE 200809L` were already present (`loader.c:29,36-43`).

Not addressed:
- `src/loader.c:277-279`: on *any* failure (no `/dev` in a chroot or minimal container, read error, short read) it silently falls back to the same realtime-clock-xor-PID seed the finding flagged, expanded by xorshift. The finding asked that deterministic/weak generation stay confined to the explicit `MIPS64RT_RANDSEED` override. There is no `getrandom(2)` attempt (available in static musl and independent of `/dev`), no warning, and no hard failure. Recommend: try `getrandom()`, then `/dev/urandom`, and on failure either abort the load or at minimum log loudly.

### M64-R5-7 — VERIFIED
- `src/vm/vm64.c:75-88`: left merge extends the left neighbour, then checks the right neighbour; if it matches, absorbs its `end`, `memmove`s it out, decrements `region_count`, and `return 0` without falling through to insertion. Right-only merge and fresh insertion are unchanged below. Left-only, right-only, and two-sided cases are all covered.

### M64-R5-8 — VERIFIED (provider-only scope, conservative)
- `src/vm/vm64.c:154-173` `u0_can_map`: returns true if a slot is free or either neighbour will coalesce; used before `mmap` in `u0_a_map` (`:217-219`) and `mips_vmfile_map` (`:370-372`).
- `src/vm/vm64.c:174-183` `u0_unmap_splits` + `:284-287`: unmap of a straddler at capacity is rejected before the host `PROT_NONE` remap.
- `src/vm/vm64.c:243-245` and `:338-340`: anon/file protect preflight `region_count + 2 > MAX`.
- Note: the `+2` protect preflight is a worst-case bound (split + record). With `MIPS64_VM64_MAX_REGIONS` = 64 (`vm64.h:34`), re-protecting an exact existing region at 63 regions (net zero slots) now returns `MIPS_FAULT` where it previously succeeded. That is a safe-side behaviour change, not a consistency bug, but it tightens the provider's effective capacity by one or two entries. Pre-existing and out of scope: `u0_a_map` records without a prior `u0_forget`, so a `MAP_FIXED` over an existing anon region still inserts an overlapping record.

### M64-R5-9 — PARTIAL
Fixed:
- `tests/difftest/run_difftest.sh:128-135`: exit code ≥ 124 on either side is reported as infrastructure/timeout failure and exits 1.
- `:153-158`: empty `I` trace or `REGS` capture on either side is a divergence.
- `:159-163`: `cmp -s a.out b.out` compares captured stdout (captured at `:65`, `:89-92`).
- `:147-148`: instruction trace order is preserved (no `sort`); `REGS` dumps remain sorted.

Not addressed:
- The finding asked for per-process identification when fork traces need separation. The sort was removed without adding a process tag, and the deleted comment explicitly documented that fork children interleave nondeterministically. No fork/clone test exists in `tests/difftest/` today (grep empty), so this is latent, but the first forking difftest will be order-flaky by construction.
- `rc >= 124` conflates legitimate guest exit codes 124..255 with `timeout` statuses. Acceptable for a test harness if documented; not documented in the script.

### M64-R5-10 — VERIFIED
- `src/os/syscall_nr.h:171-172` (existing N64 5223 / N32 6227) and `:325` (new N32 time64 6406).
- `src/os/syscall_min.c:691-697`: all three routes dispatch to `mips_sc_clock_getres`.
- `src/os/syscalls_extra.c:112-114`: null result pointer returns 0 without copy-out, checked after `clock_getres` so an invalid clock still returns `EINVAL`.

### M64-R5-11 — VERIFIED
- `src/dbt/emit_fp.c`: `ef_fhalf` and its `(void)ef_fhalf` suppression removed; `ef_fs_guard` removed; `ef_cvt_to_int` uses `ef_mode_guard` unconditionally (`:387`); guard comment updated (`:188-191`); rounding selector comment now says "4 FRINTN ties-to-even (MIPS ROUND/RINT)" (`:348-349`), which matches MIPS `ROUND.{W,L}` semantics.

## Curated C11 and line-limit hygiene

| File | Lines |
|---|---|
| `src/os/syscall_min.c` | 896 |
| `src/loader.c` | 895 |
| `src/dbt/emit_fp.c` | 793 |
| `src/os/threads.c` | 743 |
| `src/vm/vm64.c` | 593 |
| `src/os/syscall_nr.h` | 337 |
| `src/interp/fp_cvt.c` | 263 |
| `src/interp/fpmove.c` | 242 |
| `src/os/syscalls_extra.c` | 213 |
| `src/os/syscalls_time.c` | 138 |

All touched `.c`/`.h` files are ≤ 900 lines. Whole-tree scan found no `.c`/`.h`/`.S` above 900 (`src/os/mem_table.c` remains exactly 900, untouched). `syscall_min.c` and `loader.c` are within 5 lines of the limit; the next dispatcher addition should split `syscall_min.c`.

C11 checks (static):
- `src/os/syscall_min.c:11` adds `#define _POSIX_C_SOURCE 200809L` ahead of all includes, needed for `nanosleep`/`struct timespec` under `-std=c11 -pedantic`. `Makefile:22` does not define a conflicting feature macro, so no redefinition warning. `threads.c` already has `_GNU_SOURCE`; `syscalls_extra.c` has `_GNU_SOURCE` for `TIMER_ABSTIME`.
- No VLAs, Annex K, `<threads.h>`, `_Generic`, `sprintf`/`strcpy`/`strcat` introduced.
- Style only: `src/loader.c:277-279` crams a compound block onto one line and `:285` puts three statements on one line; `src/vm/vm64.c:174` lacks a blank line between `u0_can_map` and `u0_unmap_splits`. Not blocking.

## Recommended follow-ups (in priority order)

1. **R5-5**: clear the leader's `clear_child_tid` word and `FUTEX_WAKE` it before entering the wait loop; collapse the duplicated loop into `mips_thread_exit`.
2. **R5-6**: add a `getrandom()` first attempt and make the clock/PID fallback either fatal or loudly logged; do not let production silently degrade.
3. **R5-9**: either tag `I` lines with a process id in the runtime trace and compare per-process streams, or document that forking guests must not be run under the difftest until that lands.
4. **R5-1**: delete the two unused `mips_sys_clock_*` wrappers in `syscalls_extra.c:201-212`.
5. **R5-8** (optional): compute the exact slot delta for protect instead of the flat `+2` to avoid spurious faults near capacity.

Unverified: no compile or runtime evidence was collected for this review. Items marked VERIFIED are verified by code inspection only.
