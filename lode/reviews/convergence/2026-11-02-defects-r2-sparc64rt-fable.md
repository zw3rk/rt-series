# sparc64rt — Round-2 Remediation Review

| | |
|---|---|
| **Repository** | `sparc64rt` (`/Users/angerman/Projects/zw3rk/sparc64rt`) |
| **Commit reviewed** | `0428b42f2dc99fb63178d8f5129f23c44fabe68b` (parent `3ead4f9`, the Round-2 audit HEAD) |
| **Audit input** | `rt-series/lode/reviews/2026-11-02-defects-r2-sparc64rt-astra.md` (12 findings) |
| **Reviewer** | `claude-fable-5-1` |
| **Date** | 2026-11-02 |
| **Overall Verdict** | **PASS** (all 12 findings functionally resolved; one comment-only residue and a few low-severity notes listed in Section 3) |

Evidence basis: full `git show HEAD` diff, targeted reads of `interp.c`, `dbt.c`, `emit_rt.c`, `syscalls_min.c`, `backend_darwin*.c`, and three executed checks: `make check-thr-granule` (host build of interp + sync_sig + threads with the curated flags, 13 sub-tests incl. `sig-y-preserved` and `cti-delay-syscall-npc`, result `THR-RESOLVE-GRANULE-PASS`), `make check-line-limits` (ok), and a `-fsyntax-only` compile of both Darwin backend files under `DARWIN_CFLAGS` (ok). Not run: the cross-compiled `make check`, Docker/QEMU oracle runs, and `--difftest` parity.

---

## Section 1 — Per-Finding Verification

| ID | Title | Status | Technical Notes |
|---|---|---|---|
| S64-R2-1 | Signal frames corrupt the Y register | **VERIFIED** | `sync_sig.c:485` now `put_u32be(&frame[0x1d8], (uint32_t)ctx->y)`; `sync_sig.c:590` reads `get_u32be`. Layout matches kernel `pt_regs` (u_regs@0x140, tstate@0x1c0, tpc, tnpc, y@0x1d8 u32, magic@0x1dc u32). Regression `sig-y-preserved` executed and passed. |
| S64-R2-2 | Delay-slot syscalls lose the pending branch destination | **VERIFIED** | `exec_cti` publishes `(cpu->pc, cpu->npc) = (delay_pc, target)` before `exec_delay` for CALL/RETURN/JMPL/branches; `exec_delay` commits `pc = npc; npc += 4` only on CONTINUE. `exec_tcc` returns SYSCALL with no pc change, and `sparc64_handle_syscall` commits `pc = npc; npc += 4` (`syscalls_min.c:693-694`), so the branch target is honored. TRAP path in `sparc64_step_with_insn` preserves the published `npc` (also gives correct TNPC for delay-slot faults). DBT: `dbt_delay_continuation` publishes `(cont_pc, cont_npc)` before replaying via `sparc64_step`; fallback loop now breaks only after stepping the CTI. `engine_setjmp_trap` uses `ctx->npc`. Regression `cti-delay-syscall-npc` passed. Side effect: nested CTI in a delay slot now runs its own delay slot at the outer target (V9 DCTI-couple semantics) — correct per ISA but not oracle-verified in this commit (see §3). |
| S64-R2-3 | Cache flush forgets a failed RX→RW transition | **VERIFIED** | `dbt_flush_all` invalidates blocks/IBTC and bumps epoch first, then on `a32h_wx_reopen` failure returns *without* clearing `arena_published` or resetting `arena_used`; no stale code can execute and bookkeeping stays truthful. `sparc64_dbt_step_one` falls back to `sparc64_step` on reopen failure instead of writing into RX memory. No fault-injection test added (audit suggested one). |
| S64-R2-4 | Futex requeue wrong count / ineffective moves | **VERIFIED** | Returns `woken + requeued`; `-EINVAL` when `requeue_count > 0` and either key is NULL; keyed move sets `w->uaddr = NULL`; `futex_match` rejects address-only matches for requeued keyed waiters. No production caller of `rt_host_futex_requeue` exists today (definition only), so the stricter contract is currently unreachable. |
| S64-R2-5 | Temporary poll masks permit lost signal wakeups | **VERIFIED** | Design chosen: complete notification protocol rather than an atomic syscall. `linux_sigmask != NULL` now requires a wake pipe (`-EINVAL` otherwise); `sig_seq` is rechecked after `darwin_sigmask_enter`; wake pipe is in the `poll` set and is `EV_ADD`ed/`EV_DELETE`d around `kevent` in `epoll_pwait`. A signal landing between the recheck and the blocking call writes a pipe byte via the async-signal-safe notifier, so the wait returns `-EINTR`. All early-return paths free `fds`/`evlist` and remove the kevent (no leaks). |
| S64-R2-6 | Darwin directory reads discard unread entries | **VERIFIED** | Per-`(fd, dev, ino)` cached `DIR*` (32 slots, mutex-guarded, CLOEXEC dup); the entry that does not fit is retained in `slot->pending` with its `telldir` cookie; first-record-too-small returns `-EINVAL` instead of false EOF; `rt_host_close`/`rt_host_dup3` invalidate; `rt_host_lseek` SEEK_SET maps to `rewinddir`/`seekdir`. Non-directory fd now returns `-ENOTDIR`. Slot eviction on overflow closes slot 0 (no fd leak). |
| S64-R2-7 | Signal notification locks a pthread mutex | **VERIFIED** | `rt_host_worker_notify_signal` is now atomic-add + `write` + errno restore only. Futex sleepers with `ws != NULL` wake every 10 ms to recheck `sig_seq` (loop head rechecks before each slice). Correct and signal-safe; costs ≤10 ms signal latency and 100 Hz wakeups per sleeping thread. |
| S64-R2-8 | Worker mutex init races between first callers | **VERIFIED** | `g_workers = { PTHREAD_MUTEX_INITIALIZER, {0}, {0} }`; `init` flag removed. Compiles under `-std=c11 -pedantic -Werror`. |
| S64-R2-9 | Futex timeout conversion overflows signed arithmetic | **VERIFIED** | Absolute: ordering check first, then unsigned difference, clamp to `INT64_MAX`; addition to `now_rt.tv_sec` guarded by `max_add`. Relative: negative `tv_sec` → `-EINVAL`. No signed overflow path remains. (Pre-existing: zero relative timeout returns `-ETIMEDOUT` before the futex-word check, whereas Linux gives `EAGAIN` precedence.) |
| S64-R2-10 | MOVcc duplicates the FP condition table | **VERIFIED** | Single `static inline uint32_t sparc64_fp_cond_mask()` in `emit_priv.h`; `emit_cond.c` and `emit_fpcmp.c` both call it; local tables removed. |
| S64-R2-11 | Obsolete runtime helpers have no callers | **INCOMPLETE (comment-only)** | `s64_rt_mem`/`s64_rt_win` definitions removed; stale includes dropped; `emit_fast.c`, `threads.h`, `mem_sites.c` header comment updated. One stale reference remains: `src/dbt/mem_sites.c:195` ("The s64_rt_mem caller is unaffected…"). No functional impact. |
| S64-R2-12 | Backend contract describes mechanisms no longer used | **VERIFIED** | `backend.h` now describes cv-based timed slices and the wake-pipe notifier; `rt_host_clock_nanosleep` honors `ws`/`expected_seq` (pre-check, wake-pipe `poll`, `-EINTR` with computed `rem` for relative sleeps). |

---

## Section 2 — Cross-Cutting & Hygiene Verification

| Check | Result |
|---|---|
| Unity includes (`#include "*.c"`) in `src/`, `include/`, `tests/` | None |
| File size ≤ 900 lines | `make check-line-limits` → ok. Largest: `interp/fp_quad.c` 863, `dbt/emit_priv.h` 857, `os/threads.c` 850 |
| Curated C11 flags | `CFLAGS` (Makefile:21) and `DARWIN_CFLAGS` (Makefile:112) both carry `-std=c11 -Werror -Werror=vla -pedantic -Wall -Wextra`. Host build of interp/sync_sig/threads and `-fsyntax-only` of both Darwin backend files compiled clean under these flags |
| Banned string calls (`sprintf`/`strcpy`/`strcat`/`gets`) in `src/`, `include/` | None |
| `x18`/`w18` on AArch64 | No code references; all 26 textual hits are comments. Numeric register encodings in emitters not exhaustively decoded (same limit as the audit) |
| Cross-repo shared library extraction | None. `Makefile`/`flake.nix` reference no sibling `rt` repos; `rt64` substrate remains copied, not linked |
| Sister-repo fixes in HEAD | None — HEAD touches only `sparc64rt` files (16 files, +447/−202) |
| Working tree | `git status --short` clean |
| Memory/fd leaks in changed code | All new early-return paths free heap buffers, remove kevents, and close `DIR*`/dup fds; no leak found |

---

## Section 3 — Remaining or Newly Introduced Findings

No consequential (High/Medium) defects found. Low-severity items for the backlog:

1. **Low / CLEAN — stale comment** `src/dbt/mem_sites.c:195` still names the removed `s64_rt_mem` helper (S64-R2-11 residue).
2. **Low / DEFECT (plausible, pre-existing scope widened)** — spurious `-EINTR` from an undrained wake-pipe byte. `rt_host_futex_wait_bitset` returns `-4` on `sig_seq` change without reading the pipe; a later `ppoll`/`epoll_pwait`/`clock_nanosleep` for the same worker sees `POLLIN` immediately and returns `-EINTR` even when `sig_seq == expected_seq`. Whether the worker's signal-commit path drains the pipe was not verified within budget. If it does not, drain in the futex `-4` path or compare `sig_seq` before honoring a pipe wake.
3. **Low / DEFECT (pre-existing)** — `rt_host_ppoll` maps negative `tv_sec` to a 0 ms timeout; Linux returns `-EINVAL`. Futex relative zero timeout returns `-ETIMEDOUT` before the futex-word check (Linux: `EAGAIN` precedence).
4. **Info / test gap** — the S64-R2-2 interpreter change alters nested-CTI (DCTI-couple) semantics to V9-correct behavior; no `qemu-sparc64` oracle or `--difftest` evidence is in this commit. Add a DCTI-couple parity case before the next RC.
5. **Info / test gap** — S64-R2-3 has no injectable `a32h_wx_reopen` failure test; both failure branches are only inspected, not exercised.
6. **Info / design note** — 10 ms futex slice polling (S64-R2-7) trades signal latency and idle wakeups for signal safety; document the bound in `backend.h` and revisit if idle CPU on sleeping guests becomes measurable. `rt_host_futex_requeue` has no callers; a future private-futex `FUTEX_REQUEUE` path (used by musl `pthread_cond_broadcast`) must supply keys or an address-only move will hit the new `-EINVAL`.
