# Verification Report — mips64rt `f29422b` vs. Round-6 defects M64-R6-1..7

**Scope:** static review of commit `f29422b` (`mips64rt: remediate Round-6 defects (M64-R6-1..7)`, parent `a37e353`) in `/Users/angerman/Projects/zw3rk/mips64rt`. Files changed: `src/os/futex.c` (+67/−18 net), `src/os/threads.c` (+19/−13 net). No build, test, Docker, or QEMU was run. Line numbers below refer to the post-commit tree at `f29422b`.

**Summary:** 7/7 VERIFIED. No regressions found. Two low-severity nits noted (non-blocking).

| ID | Severity | Verdict | Primary evidence |
|---|---|---|---|
| M64-R6-1 | HIGH | **VERIFIED** | `src/os/futex.c:80-86`, `:497-498`, `:514-515`, `:587-589`, `:305-310` |
| M64-R6-2 | HIGH | **VERIFIED** | `src/os/futex.c:574-578`, `:588-589`, `:597-600` |
| M64-R6-3 | MEDIUM | **VERIFIED** | `src/os/futex.c:574-577` (val3 bound removed) |
| M64-R6-4 | HIGH | **VERIFIED** | `src/os/threads.c:397-400`, `:421-426`, `:474-475` |
| M64-R6-5 | MEDIUM | **VERIFIED** | `src/os/threads.c:297-302`, `:403-408` |
| M64-R6-6 | MEDIUM | **VERIFIED** | `src/os/futex.c:89-105`, `:170-197`, `:325-336` |
| M64-R6-7 | LOW | **VERIFIED** | `src/os/threads.c:560-564`; `grep -rn l4b_ctx src/` → no hits |

---

## M64-R6-1 — Futex expected word not converted to host byte order — **VERIFIED**

New helper `l4f_host_word()` at `src/os/futex.c:80-86` byte-swaps the guest logical value when `be != 0` and passes it through otherwise.

Applied at every host comparison site:

- **Linux WAIT with timeout loop** `src/os/futex.c:497-498`: `int exp = (int)l4f_host_word((uint32_t)val, ctx->is_be != 0);` fed to `l4f_host(hp, hop, exp, &rem, NULL, (uint32_t)val3)` at `:504-505`. The bitset slot (`val3`) stays unswapped, as required.
- **Linux WAIT / WAIT_BITSET without timeout** `src/os/futex.c:514-517`: same conversion, same unswapped `val3` bitset.
- **Linux CMP_REQUEUE** `src/os/futex.c:587-589`: `cmp_exp = l4f_host_word((uint32_t)val3, ctx->is_be != 0);` passed as kernel `val3` only when `base == L4F_CMP_REQUEUE`, else `0U`.
- **Darwin CMP_REQUEUE** `src/os/futex.c:305-310`: `exp_raw = l4f_host_word(expected, be)` compared against `l4f_word_raw(uaddr)` (the raw in-memory host word). `l4f_darwin`'s `expected` parameter is `uint32_t` (`:286`), so the full 32-bit range is preserved.

Counts (`val` for WAKE/REQUEUE wake count, `timeout_va` requeue count) are not swapped. Matches the prescribed fix exactly.

## M64-R6-2 — Plain `FUTEX_REQUEUE` passes requeue count of zero — **VERIFIED**

Before: `nrq = NULL` unless `base == L4F_CMP_REQUEUE`, and plain REQUEUE used `val3` as count on Darwin.

After, `src/os/futex.c:574-578`:
```c
if (val > (uint64_t)INT_MAX ||
    timeout_va > (uint64_t)INT_MAX) {
    return l2a_ret(ctx, -(int64_t)EINVAL);
}
nrq = (const struct timespec *)(uintptr_t)timeout_va;
```
`nrq` is now set unconditionally for both REQUEUE and CMP_REQUEUE and forwarded as the 4th `futex(2)` argument at `:588`. Darwin path at `:597-600` uses `(int)(uint32_t)timeout_va` as `req_nr` for both ops. `val3` is zeroed for plain REQUEUE on Linux (`:589`) and ignored on Darwin via `check_exp = 0`. The header comment at `:16-20` and the block comment at `:562-565` were updated to document the corrected slot convention.

## M64-R6-3 — CMP_REQUEUE rejects expected words > INT_MAX — **VERIFIED**

The old guard `val3 > (uint64_t)INT_MAX` is gone. The new guard at `src/os/futex.c:574-575` applies the signed-`int` bound only to `val` (wake count) and `timeout_va` (requeue count). `val3` flows through as `(uint32_t)val3` at `:587` and `:601`, so `0x80000000` is now accepted. Comment at `:563-564` explicitly states "full uint32_t range".

## M64-R6-4 — Process clone drops `stack_va` / `tls_va` — **VERIFIED**

- Signature extended at `src/os/threads.c:397-400`: `l4b_clone_fork(ctx, flags, stack_va, parent_tid_va, tls_va, child_tid_va)`.
- Caller updated at `src/os/threads.c:474-475` (`mips_clone_full` fork branch) to pass both.
- Child-side installation at `src/os/threads.c:421-426`:
```c
if (stack_va != 0U) {
    ctx->gpr[29] = stack_va;
}
if ((flags & L4B_CLONE_SETTLS) != 0U) {
    ctx->ulr = tls_va;
}
```
`gpr[29]` is MIPS `$sp`; `ulr` is the same TLS (UserLocal) field the thread path sets at `:318-319`, so the two paths are now consistent. The installation happens after `mips_threads_atfork_child(ctx)` and before TID bookkeeping, inside the `pid == 0` branch. `stack_va` is already `l4b_trunc_va`'d by `mips_clone_full` (`:459-462` region) before dispatch. Linux semantics match: the kernel does not range-check the clone stack pointer for `fork`-style clones, so no `task_size` guard is needed here (the thread path's `:294` check is a stricter local policy, not a requirement).

## M64-R6-5 — Unconditional TID-pointer validation — **VERIFIED**

Both sites now gate validation on the applicable flags:

- Thread clone `src/os/threads.c:297-302`
- Process clone `src/os/threads.c:403-408`

```c
if (((flags & L4B_CLONE_PARENT_SETTID) != 0U &&
     l4b_check_tid(ctx, parent_tid_va) != 0) ||
    ((flags & (L4B_CLONE_CHILD_SETTID | L4B_CLONE_CHILD_CLEARTID)) != 0U &&
     l4b_check_tid(ctx, child_tid_va) != 0)) {
    return l2a_ret(ctx, -(int64_t)EFAULT);
}
```
Flag selection is correct: `parent_tid` is only consumed under `CLONE_PARENT_SETTID`; `child_tid` under `CLONE_CHILD_SETTID` or `CLONE_CHILD_CLEARTID`. The downstream uses at `:385`, `:436` (parent) and `:427-432` (child) were already flag-gated, so an unvalidated pointer can no longer be dereferenced.

## M64-R6-6 — Unchecked `time_t` deadline arithmetic — **VERIFIED**

- `l4f_time_max()` at `src/os/futex.c:89-92` derives `TIME_T_MAX` portably from `sizeof(time_t)`; `l4f_sat_add()` at `:94-105` saturates both directions with overflow-free pre-checks (`a > mx - b` only when `b > 0`; `a < mn - b` only when `b < 0`).
- **Linux relative deadline** `l4f_wait_deadline` `:325-336`: seconds via `l4f_sat_add`, nanosecond carry guarded by `if (dl->tv_sec < mx)`.
- **Darwin deadline helper** `l4f_deadline` `:170-197`: both additions (`:174` relative, `:185` abs-monotonic rebase) use `l4f_sat_add`; the positive-nsec carry loop at `:188-193` is guarded.

Residual arithmetic was checked and is safe without further changes: the timespec parser at `:415` rejects `sec < 0` and `nsec` outside `[0, 1e9)`, so the carry loop runs at most once and the abs-monotonic subtraction at `:182` is nonneg − nonneg (no overflow); the negative-nsec `tv_sec--` loops at `:194-197` and `:348-351` cannot reach `TIME_T_MIN` because inputs are nonnegative. `l4f_wait_remaining` (`:340-357`) computes `mx - now` which cannot overflow. The "equivalent checks to the Darwin helper" requirement is met.

## M64-R6-7 — Dead `l4b_ctx` thread-local — **VERIFIED**

- Declaration removed (old `src/os/threads.c:552`); both assignments and the `NULL` resets in `mips_hostfault_run` removed.
- `grep -rn l4b_ctx src/` → zero hits.
- Comment at `src/os/threads.c:560-563` now reads: "mips_hostfault_run resolves the captured host pc to the faulting guest pc via dbt_host_pc_to_guest." This matches the actual mechanism: `dbt_host_pc_to_guest` is declared at `src/dbt/dbt.h:159`, defined at `src/dbt/mem_recover.c:602`, and called at `src/os/threads.c:721`.

---

## Regression check

- `l4f_host` signature unchanged (`src/os/futex.c:365-371`); all call sites updated consistently.
- `l4f_darwin` signature unchanged (`:283-286`); the Darwin CMP_REQUEUE call still passes `check_exp = 1` only for CMP_REQUEUE.
- Thread clone path (`l4b_clone_thread`) behaviour for `stack_va`/`tls_va` is untouched.
- No other callers of `l4b_clone_fork` exist besides `mips_clone_full`.

## Nits (non-blocking, not part of R6 scope)

1. **`__builtin_bswap32`** at `src/os/futex.c:83` is the first use of that GCC/Clang builtin in `src/` (`grep -rln __builtin_bswap32 src/` → only `futex.c`). It is supported by both toolchains in use (musl-gcc, Apple clang) but is not strict C11. If the repo has an existing byte-swap helper (the timespec parser's `getn` suggests one), reusing it would keep the Curated-C11 surface uniform.
2. **Local named `exp`** at `src/os/futex.c:497` and `:514` shadows libm's `exp()` if `<math.h>` is ever included transitively; harmless today, but `-Wshadow` would flag it. Consider `exp_host` or `host_exp`.

## Unverified

- Compilation on both targets (Linux musl static-pie, Darwin) was not attempted per budget. The diff is type-consistent on inspection (`time_t` casts, `uint32_t`/`int` conversions, signature/caller arity), but a real build is the only proof.
- Runtime behaviour of BE-guest futex WAIT/CMP_REQUEUE and non-`CLONE_VM` clone with a supplied stack was not exercised; the R6 harness tests in rt-series (if any cover these) should be run on the integrated candidate.
