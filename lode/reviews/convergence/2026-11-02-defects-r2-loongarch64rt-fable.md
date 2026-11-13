# Post-Remediation Review: `loongarch64rt`

| Field | Value |
|---|---|
| Repository | `loongarch64rt` (`/Users/angerman/Projects/zw3rk/loongarch64rt`) |
| Commit reviewed | `38f01b073da480545c0cc7631b1042185c530215` |
| Baseline audit | `rt-series/lode/reviews/2026-11-02-defects-r2-loongarch64rt-astra.md` (against `026e87d`) |
| Reviewer | `claude-fable-5-1` |
| Date | 2026-11-02 |
| **Overall Verdict** | **NEEDS_FOLLOWUP** (all seven Round-2 findings are addressed; one newly introduced link-order hazard in the LA64-R2-2 fix needs a one-line correction) |

Evidence used: the full `HEAD` diff, surrounding context of every changed function, hygiene scans, and a native build and run of `_build/test_p6_smc_mem` (result `P6-RESULT fails=0`, exit 0). The cross-compiled `_build/loongarch64rt` artifact predates the commit by four minutes and was not rebuilt or executed here. No Docker or `qemu-loongarch64` runs were performed.

## Section 1: Per-Finding Verification Table

| ID | Title | Status | Technical Notes |
|---|---|---|---|
| LA64-R2-1 | Read misses restore writable tags on translated code pages | **VERIFIED** | `dbt_mem_miss_fill` now computes `writable` once, page-granular (`la64_mem_ptr(tag, 4096, WRITE)`), and requires `dbt_page_has_code(tag) == 0`, for both load and store misses. `write_tag` is published only when that gate passes. `dbt_page_has_code` consults the bitmap and, under `LA64_HAVE_VM64`, `VM_PAGE_HAS_CODE`. New `dbt_clear_code` runs on `la64_mem_unmap` and `dbt_clear_code_all` on `la64_mem_init`, so stale code bits cannot pin recycled pages read-only. Regression test 10b covers translate-marked page, load fill with `write_tag == RT_TLB_INVALID_TAG`, and store miss returning 0 after an SMC bump. Unit test passes natively. |
| LA64-R2-2 | Reservation protection checks an access while granting a whole page | **VERIFIED** (with follow-up F-1) | Gate is now page-granular via `la64_clone_has_ll_in_range(ctx, tag, 4096)`, which checks self, `main_ctx`, and all live clone slots under `clone_lock`. `dbt_revoke_write` revokes across every context (`la64_clone_revoke_write`) and flushes the shared Soft-TLB (`vm64_tlb_flush_all`). `main_ctx` is registered from `dbt_run`, `dbt_step_bounded`, `la64_sys_clone`, and after each LL. Interp vector and FP stores now also clear the local reservation. Test 10c covers a different-word same-page miss. **Caveat**: the real implementation in `clone.c` is declared `LA64_WEAK_DEF` while `dbt_mem.c` also defines a weak self-only fallback. Two weak definitions resolve by link order. `BOOT_SRCS` lists `L1C_SRCS` before `DBT_SRCS`, so the production binary gets the correct one, but `AOT_TEST_SRCS` lists `DBT_SRCS` first. See F-1. |
| LA64-R2-3 | Mprotect releases the mutation transaction before updating host permissions | **VERIFIED** | Host sync (`sync_host_pages`) now runs before `vm64_commit_mutation`. On host failure the region `prot` values are rolled back from `old_prot[]`, host pages are resynced best-effort, `dbt_invalidate_all` runs, and the transaction commits with `host_ok = 0` before returning the error. All early-exit paths (`range_mapped`, `split_at`) commit with `host_ok = 0`. `la64_mem_unmap` was also reordered so `dbt_clear_code` and `dbt_invalidate_all` happen inside the transaction. Residual splits from `split_at` persist after rollback; harmless. |
| LA64-R2-4 | Fixed mmap silently rounds down invalid addresses | **VERIFIED** | Both `MAP_FIXED` and `MAP_FIXED_NOREPLACE` now reject `addr == 0`, misaligned `addr`, `addr >= LA64_TASK_SIZE`, and overflow via `size > LA64_TASK_SIZE - addr`. `va = addr` with no masking. Zero-address NOREPLACE goes through the same path. Minor Linux-fidelity nits (not regressions): Linux returns `EPERM`/`EEXIST` rather than `EINVAL` for `addr == 0`, and when both flags are set Linux lets `MAP_FIXED` win whereas this code applies NOREPLACE semantics and skips the replacing install. |
| LA64-R2-5 | Darwin directory cursors remain descriptor-local and can lose buffered entries | **VERIFIED** | Cursors are now `darwin_dir_cursor_t` with `refs`, shared across fd aliases via a separate `darwin_dir_fd_t` table. `darwin_dir_dup_fd` is wired into `sys_dup`, `sys_dup3`, `sys_fcntl` (F_DUPFD, F_DUPFD_CLOEXEC), and the Darwin host backend `dup`/`dup3`/`fcntl`. Slot exhaustion returns `EMFILE` instead of evicting slot 0. `lseek` now synchronizes via `rewinddir`/`seekdir` on `SEEK_SET` and invalidates on other whence values. `close_cloexec` drops cursors before closing. Weak non-static definitions in the header share state across TUs. Low notes: `dup` of any directory fd eagerly allocates a cursor (one extra host fd via `dup`+`fdopendir`) even if never enumerated; `SEEK_CUR`/`SEEK_END` on one alias releases only that alias's reference, leaving sibling aliases with a moved underlying offset. |
| LA64-R2-6 | C IBTC lookup API has no production caller | **VERIFIED** | `dbt_ibtc_lookup` removed from `dbt_chain.c` and `dbt.h`. No remaining references. |
| LA64-R2-7 | Chaining documentation describes removed and nonexistent state | **VERIFIED** | RAS references removed from `dbt.c`, `dbt.h`, `dbt_chain.c`. IBTC documented as process-wide and atomic; slots are now `_Atomic uint64_t guest` / `_Atomic uintptr_t host` with a 16-byte `_Static_assert`, and `chain_single_block` is `_Atomic int`. Insert ordering is guest=0, host (release), guest (release). Trampoline probe still null-checks host (`cbz x12`), so a concurrent `dbt_ibtc_clear` from an interp worker cannot dispatch to a zero target. The trampoline's two plain `ldr`s have no acquire ordering, but with a single DBT thread as the only inserter this is not weaker than the prior `memset`. |

## Section 2: Cross-Cutting & Hygiene Verification

**Sister-repo cross-cutting fixes carried in HEAD (M64-R2-4, M64-R2-8, S64-R2-3)**

- **vm64 worker publication**: `workers[i].used` is now `_Atomic int`; fields are initialized before `used` is stored with release ordering, and every reader uses acquire loads. Sound.
- **Worker unregister on thread exit**: `vm64_worker_unregister(vm64_self())` is called in `la64_clone_thread_exit` before detaching the slot. Slot 0 is refused. Sound.
- **Fork child reset**: `la64_clone_fork_child_reset` reinitializes `clone_lock`, reruns `store_init`, zeroes slots, clears the TSD slot, and sets `main_ctx`. `vm64_fork_child_reset` reassigns the mutation mutex by struct assignment, clears `g_vm_mutating`, resets the worker table, and re-registers the child's TLB context. Struct assignment of a `pthread_mutex_t` and re-initializing a possibly-locked mutex in the post-fork child are the usual pragmatic approach; acceptable, not strictly portable.
- **W^X reopen check**: `dbt_code_alloc` only reopens a sealed page if `la64_jit_begin_write_checked` returns 0; otherwise it falls through to allocate a fresh page. Correct. It then also calls the unchecked `rt_host_jit_begin_write` on the same page, which is redundant (see F-4).

**Hygiene gates**

| Check | Result |
|---|---|
| `#include "*.c"` unity includes in `src/`, `tests/` | None found |
| First-party `.c`/`.h`/`.S` files <= 900 lines | All pass; `make check-line-limits` reports "all files <= 900 lines". Largest: `src/os/clone.c` at 878, `src/vm/vm64.c` at 869 |
| Compiler flags | `CFLAGS := -O2 -std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror -pthread` |
| `x18` / `w18` in `.S`, `.c`, `.h` | Only comment and guard text; no non-comment register use |
| Cross-repo shared-library extraction | No `../rvrt`, `../rt-series`, or sibling paths in `Makefile`, `flake.nix`, or sources; all substrate is vendored in-repo |
| Native unit test | `_build/test_p6_smc_mem` builds under the above flags and passes (`fails=0`) including new cases 10b and 10c |

Banned string functions and Annex K were not re-scanned this round; the Round-2 audit found none and the diff introduces only `memset`/`memcpy`.

## Section 3: Remaining or Newly Introduced Consequential Findings

- **F-1 — Medium — Newly introduced — Two weak definitions of `la64_clone_has_ll_in_range`.** `src/dbt/dbt_mem.c:244` defines a `__attribute__((weak))` self-only fallback, and `src/os/clone.c:763` defines the real cross-context implementation also under `LA64_WEAK_DEF`. With two weak definitions the linker keeps whichever object it sees first. `BOOT_SRCS` happens to place `clone.c` before `dbt_mem.c`, so the shipped binary is correct today, but `AOT_TEST_SRCS` places `DBT_SRCS` before `L1C_SRCS` and will silently bind the self-only fallback, and any future reordering of `BOOT_SRCS` or the Darwin link line would silently reopen LA64-R2-2. Every other new hook follows the correct pattern (strong definition in `clone.c`, weak stub elsewhere). **Fix**: drop `LA64_WEAK_DEF` from `la64_clone_has_ll_in_range` in `clone.c` so the strong symbol always overrides the stub.

- **F-2 — Low — Unverified race window — Soft-TLB fill is not under the store lock.** `dbt_mem_miss_fill` evaluates `la64_clone_has_ll_in_range` under `clone_lock` only, then publishes `write_tag` later. A concurrently executing LL on another context takes `la64_clone_store_lock`, sets `ll_valid`, and revokes write tags; if that sequence lands between the gate check and the publish, the stale `write_tag` survives. Whether this can happen depends on the turn scheduler strictly serializing guest execution between the DBT thread and interp workers, which this review did not trace. If it does, no action is needed; otherwise take `la64_clone_store_lock` around the gate-and-publish or recheck the gate after publish.

- **F-3 — Low — Fidelity — `sys_mmap` flag precedence.** When both `MAP_FIXED` and `MAP_FIXED_NOREPLACE` are set, the code applies NOREPLACE semantics and skips the replacing install path; Linux lets `MAP_FIXED` win. `addr == 0` yields `EINVAL` where Linux yields `EPERM` (FIXED) or `EEXIST` (NOREPLACE). Not a regression against the Round-2 baseline.

- **F-4 — Low — CLEAN — Redundant JIT write-enable in `dbt_code_alloc`.** After `la64_jit_begin_write_checked` succeeds, the code still calls `rt_host_jit_begin_write` on the same page. On Darwin this toggles `pthread_jit_write_protect_np(0)` twice and on Linux issues a second `mprotect`. Remove the unchecked call.

- **F-5 — Low — Resource use — Eager Darwin directory cursors on `dup`.** `darwin_dir_dup_fd` creates a cursor (one `dup` host fd plus a `DIR *`) for any directory fd that is duplicated, even if neither alias ever calls `getdents64`. With 64 slots this can produce spurious `EMFILE` for programs that dup many directory fds without reading them. Consider attaching only when the source fd already has a cursor.
