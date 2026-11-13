# sparc32rt — Round-2 Remediation Review

| Field | Value |
|---|---|
| Repository | `sparc32rt` (`/Users/angerman/Projects/zw3rk/sparc32rt`) |
| Commit reviewed | `a73ff143064dc5e1e84107597a3391c97ac0bd3c` (parent `dad95da`) |
| Audit input | `rt-series/lode/reviews/2026-11-02-defects-r2-sparc32rt-astra.md` |
| Reviewer | `claude-fable-5-1` |
| Date | 2026-11-02 |
| Method | Static review of the full commit diff plus targeted source greps. No compile, QEMU, Docker, or difftest run. The default `make` target is `help`, so the bounded build attempt produced no object code. |
| **Overall Verdict** | **NEEDS_FOLLOWUP** |

The commit resolves the substance of 14 of 17 findings. Three residual issues remain in the synchronization work (S32-R2-13, S32-R2-14) and one new hazard was introduced by the reader-writer VM lock (fork inheritance). None of the residuals is a functional regression on the single-threaded path.

---

## Section 1: Per-Finding Verification

| ID | Title | Status | Technical Notes |
|---|---|---|---|
| S32-R2-1 | SMC mask collisions suppress invalidation | **VERIFIED** | `g_vm32_code_mask` is now a `calloc`'d `VM32_PAGE_COUNT` array indexed by full VPN (`src/vm/vm32.c:129`). `vm32_line_mask_in_page` builds exact 64-byte line masks per page with a correct `l1 - l0 >= 63` full-mask guard. `vm32_clear_code_range` and `vm32_range_has_code` index by VPN only. No aliasing remains. Allocation failure is handled and frees prior tables. |
| S32-R2-2 | Partial-range invalidation clears tracking for surviving blocks | **VERIFIED** | `sparc32_dbt_invalidate_range` (`src/dbt/dbt_cache.c:310`) unconditionally clears page tracking over the rounded range, then re-notes every still-`valid` block in `g_blocks` overlapping `[lo, hi)`. Runs under `dbt_lock_acquire`. Not verified: whether any block source other than `g_blocks` (e.g. AOT-resident blocks) contributes code lines; if so those would lose tracking. |
| S32-R2-3 | Checked syscall copies race with guest unmapping | **VERIFIED** (with Low residual) | New reader-writer discipline in `src/rt32/vm.c:81-108`: `sparc32_vm_access_enter/leave` take a reader count; `vm_lock_acquire` raises `g_vm_writer_waiting`, takes the spin lock, then drains readers. Reentrancy via `t_vm_read_depth` and `t_vm_lock_held` is correct. `l2a_load`/`l2a_store`/`l2a_copy_cstring`, `interp_mem_rd/wr`, and the LDSTUB/SWAP/CASA helpers all pin across validate+copy. `read`/`write`/`readv`/`writev`/`getrandom` are staged through host buffers, so no blocking syscall holds a guest pointer. Residual unpinned direct accesses: `src/os/threads.c:371` (CLONE_CHILD_CLEARTID store at thread exit) and the host-futex paths in `src/os/futex.c:248-296`, `src/os/syscalls_time.c:280` (kernel-side fault-safe, acceptable). |
| S32-R2-4 | Exec permits failure after destroying the old image | **VERIFIED** | `rt32_elf_prepare` opens and retains `exec_fd`/`interp_fd`, parses both images in dry-run mode, and fixes the PIE bases. `sparc32_thr_execve` then resets dispositions and VM and calls `rt32_elf_commit_plan` from the retained descriptors; any commit or stack-setup failure after the point of no return calls `_exit(127)` instead of returning to a destroyed image. Linux would deliver `SIGSEGV`; `_exit(127)` is an acceptable explicit failure path. Descriptor hygiene: every `rt32_elf_prepare` error path, `rt32_elf_commit_plan` path, and `rt32_elf_validate` closes the plan; `rt32_elf_load` closes the caller's `exec_fd` as before. |
| S32-R2-5 | Region coalescing merges mappings of different files | **VERIFIED** | `vm_region_meta_t` gains `dev`/`ino` captured via `fstat` at insert; `same_backing` now requires matching `dev`,`ino` and contiguous `pgoff`. `flags` equality already covered sharing semantics. Minor: if `fstat` fails both fields stay 0 and two such regions could still merge. |
| S32-R2-6 | Remap loses shared-anon identity and COW history | **VERIFIED** (with Low residual) | `MAP_SHARED\|MAP_ANONYMOUS` is now backed by an unlinked `mkstemp`/memfd object recorded as the region fd, so extension and relocation (`hold_fd`, `has_shm`) reuse the same object; shared growth `ftruncate`s it. Private file relocation copies only `RT_PAGE_COW_DIRTY` pages and re-marks them dirty at the destination, replacing the byte-compare heuristic. All `hold_fd` exit paths close the dup. Residual: correctness now depends on every write path calling `vm32_note_page_write`; the direct futex `FUTEX_WAKE_OP`/atomic stores in `src/os/futex.c` do not, so a page dirtied only by those ops would be dropped on mremap (practically negligible). If the shared-mem object cannot be created, the code silently degrades to plain anonymous shared memory with the old identity loss. |
| S32-R2-7 | JMPL delay slots observe the old link register | **VERIFIED** | Interpreter (`src/interp/interp.c:590-595`) checks target alignment, faults at the JMPL, then writes `rd = pc` before the delay slot; the faulting-delay path keeps `rd` committed and resumes at `npc` with `npc = target`. DBT (`src/dbt/emit_cti.c:319-334`) emits `and w, target, 3; cbz` to a `SINGLE_STEP` exit before storing `rd`, then runs the delay slot. Both engines are now ordered identically; the delay-class singlestep list was widened to FBRANCH/PRIV/ILLEGAL/FPU for both CALL and JMPL (see Section 3 perf note). |
| S32-R2-8 | NaN propagation can return a finite operand | **VERIFIED** | `fp_f32_pick_nan`/`fp_f64_pick_nan` return the sole NaN when exactly one operand is NaN; payload arbitration applies only when both are. |
| S32-R2-9 | Nondefault rounding ignored in interpreter | **VERIFIED** | `fp_finish_f32/f64` apply `FSR.RD` from the RN host result using an exact error-sign term: TwoSum for add/sub, exact double product (f32 mul/div/sqrt) and `frexp`-scaled `fma` residuals (f64 mul/div/sqrt). Directed overflow returns max-finite per IEEE for RZ/RM(+)/RP(−); underflow-to-zero with RP/RM correctly steps to the smallest subnormal; signed-zero sums honor RM. Flag derivation (OFC/UFC/NXC) is consistent with the rounded result. |
| S32-R2-10 | Batched FPSR flags corrupt `cexc` | **VERIFIED** | `fp_emit_arith` now calls `sparc32_emit_fp_flush` then `fp_fpsr_clear` before every arithmetic op, so each commit carries exactly one instruction's flags; `aexc` accrues across flushes. Costs one FPSR read/commit per FP op. |
| S32-R2-11 | Sigsuspend overwrites handler `%o0` | **VERIFIED** | `interp_deliver_async_for_syscall` stores `%o0 = 4` (EINTR) into the frame (`frame + 0xf0 + 0x20`) with `PSR.C` set, and sets live `pc = handler`, `npc = handler + 4`, `%o0 = signo`. `sparc32_thr_rt_sigsuspend` returns 0 on delivery and `sparc32_handle_syscall` returns early, bypassing the `%o0`/`PSR.C`/`pc` commit tail. Not verified (grep found no direct caller by that name): that the interpreter/DBT trap exits resume from `ctx->pc/npc` without a further advance; difftest will expose any skew. |
| S32-R2-12 | Sigsuspend lost-wakeup window | **VERIFIED** | Host delivery of all but SIGBUS/SIGSEGV/SIGILL/SIGFPE is blocked (`sigprocmask`) before the pending scan, `sigsuspend(&empty)` atomically opens the window, and the saved host mask is restored before delivery or `-EINTR` return. |
| S32-R2-13 | Unsynchronized permission/code-state tables | **INCOMPLETE** | Readers now use acquire loads; `g_vm32_state` updates use `__atomic_fetch_or/and`; `pending_signals` uses atomic RMW. However `vm32_sync_fast_write` (`src/vm/vm32.c:76-84`) is still a non-atomic load-prot/load-state/store-prot sequence invoked from two lock domains (VM lock via `vm32_publish_page`, DBT lock via `vm32_note_code_page`/`vm32_clear_code_range`). A concurrent `mprotect` publish and code-note can lose the prot bits: the note path stores a prot byte loaded before the publish. Result: table says RW while host is `PROT_NONE`, so a subsequent `interp_range_ok` passes and the `memcpy` faults the translator. Fix: CAS loop on the prot byte, or take the VM write lock in the code-note paths. |
| S32-R2-14 | Signal handlers race on live-context state | **INCOMPLETE** | Atomic half done: `thr_live[]` loads/stores and `pending_signals` RMW are atomic; `thr_init_done` is now initialized under `thr_live_lock`. Lifetime half not done: `src/os/threads.c:381-382` runs `thr_deregister(ctx); free(ctx);` while `sparc32_thr_note_signal` may have already loaded `thr_live[i]` in the async handler and is about to `__atomic_fetch_or(&c->pending_signals, ...)` → use-after-free on a process-directed signal racing a thread exit. Fix: defer `free(ctx)` (quarantine list, or mark slot with a tombstone and block the handled signals around deregister+free). |
| S32-R2-15 | Exec validation duplicates loader policy | **VERIFIED** | `validate_elf32_fd` removed; `load_elf32_image(..., commit=false)` is the single parser, with `rt32_elf_plan_t` carrying fds, infos, and both PIE bases from prepare to commit. Interp base is now computed identically in both phases (`max(brk_base, 0x3F000000)`). |
| S32-R2-16 | Removed TLB leaves no-op hook | **VERIFIED** | `vm32_tlb_invalidate` and all five call sites removed; `rt_tlb_entry_t` and `RT_TLB_*` deleted from `mem_site.h`. No remaining references in `src/` or `include/`. |
| S32-R2-17 | Store-path comment contradicts SMC remediation | **VERIFIED** | `src/dbt/emit_fast.c:151-155` now describes the slow-helper invalidation and `SPARC32_EXIT_BRANCH` re-translation path. |

Cross-cutting item referenced in the commit (X-R2-2, split capacity): `vm_can_split_range_locked` pre-validates region-table headroom before `mprotect`/`munmap` mutate anything. Logic counts removals and splits correctly for both operations. VERIFIED.

---

## Section 2: Cross-Cutting & Hygiene Verification

| Check | Result |
|---|---|
| Unity includes (`#include "*.c"`) in `src/`, `include/`, `tests/` | None found. |
| File-size discipline | `make check-line-limits` → `line limits OK (all src/include/tests .c/.h/.S <= 900 lines)`. Independent `wc -l` scan found no file over 900. `elf32.c` lacks a trailing newline (cosmetic). |
| Curated C11 flags | `Makefile:29` `-std=c11 -Wall -Wextra -Werror -Werror=vla -pedantic`; `build-darwin` and `check-abi-invariants` carry the same set. New code uses `_Atomic`, `_Thread_local`, `__atomic_*` builtins, fixed-size arrays (no VLAs), `snprintf` with bounds. No `sprintf`/`strcpy`/`strcat`, Annex K, `<threads.h>`, or `_Generic` introduced. |
| `x18` reserved | Only textual references are comments asserting non-use in `safe_syscall_a64.S`, `thread_entry.S`, `trampoline_a64.S`, `dbt.h`, `emit_int.c`. No operand use. The new JMPL emission uses `ES0`=w15/`EKEEP`=w22. |
| Cross-repo library extraction | None; all new helpers (`l2a_copy_cstring`, plan struct, RW lock) are repo-local. `rt32/` substrate stays a copied, standalone tree. |
| Compile verification | **Not performed.** Budget-bounded `make` ran the default `help` target. `-Werror` cleanliness of the 29 touched files is therefore asserted by the commit, not by this review. |
| fd / memory leak audit of new code | `rt32_elf_plan_t` closes on every path; `hold_fd` in `rt32_vm_mremap` closed on all 7 exits; `anon_shm_fd` closed after `vm_record_region_ext_locked` dups it, and on failure. Staging buffers in `sys_read`/`sys_write`/`sys_rwvec` freed on every return including the `readv` partial-store error path. |

---

## Section 3: Remaining or Newly Introduced Consequential Findings

1. **[Medium, new] Fork child inherits foreign reader counts and can deadlock on first VM mutation.** `g_vm_readers`, `g_vm_writer_waiting`, and `g_vm_lock` (`src/rt32/vm.c:49-51`) are process-global atomics. `sparc32_thr_fork` (`src/os/threads.c:288`) does not reset them in the child. If any sibling thread was inside `sparc32_vm_access_enter` at `fork()`, the child's first `vm_lock_acquire` (any `mmap`/`munmap`/`brk`) spins forever waiting for `g_vm_readers == 0`. The pre-existing `g_vm_lock` had the same class of hazard, but readers now cover every slow-path load/store, so the window is far wider. Fix: in the `pid == 0` branch reset the three atomics (and `t_vm_lock_held`/`t_vm_read_depth` are thread-local, so the forking thread's own values are already consistent).

2. **[Medium, residual S32-R2-13] `vm32_sync_fast_write` lost-update race across lock domains.** Detailed in the table. Needs a CAS loop or unified locking.

3. **[Medium, residual S32-R2-14] Use-after-free between `thr_host_handler` and `free(ctx)`** at `src/os/threads.c:381-382`. Detailed in the table.

4. **[Low] Darwin backend relaxes host-page alignment for shared `MAP_FIXED` mappings.** `backend_darwin.c:358` now skips the partial-page fallback whenever `shared != 0`. On the 16 KiB host, a guest `MAP_FIXED` shared mapping whose length is not a multiple of 16 KiB will have `mmap` round the length up and silently replace the neighbouring guest pages' host backing. Fresh placements are protected because `vm_find_free_gap_locked` now rounds to the host page, but explicit guest `MAP_FIXED`/`MREMAP_FIXED` addresses are not. Dev-host only; Linux 4 KiB production unaffected.

5. **[Low] Private-file COW tracking now semantically load-bearing.** `rt32_vm_mremap` drops any `MAP_PRIVATE` file page that is not `RT_PAGE_COW_DIRTY`. Every write path must call `vm32_note_page_write`; the remaining direct writers (`futex.c` `FUTEX_WAKE_OP`/atomic-op stores, `threads.c:371` clear-tid) do not. Worth a one-line note at each or routing them through `l2a_store`.

6. **[Low] Memory amplification in staged I/O.** `sys_write`/`sys_read` `malloc` the full `count` (up to 4 GiB as a `uint32_t`), and `sys_rwvec` stages the whole batch `want`. Linux caps a single transfer at `0x7ffff000`; consider the same cap and a chunked loop to bound transient host memory.

7. **[Low, perf] FPU instruction in a CALL/JMPL delay slot now forces a `SINGLE_STEP` exit** (`emit_cti.c:259-266`, `317-324`). Compiled SPARC code frequently schedules `fmovs`/`fitos` into call delay slots; this will show up as interpreter fallbacks in hot loops. Not a correctness issue.

8. **[Low] `rt32_elf_prepare` interp/exec overlap check** (`elf32.c:759-763`) rejects any interpreter whose `load_bias` is below `brk_base` and whose image end exceeds the exec `load_bias`. For a non-rebased interpreter (ET_EXEC, or ET_DYN with `min_vaddr >= 0x10000`) and an ET_EXEC executable this compares against `load_bias == 0` and returns `-ENOEXEC` even when the ranges do not actually overlap. Replace with a true interval-overlap test against the exec's `[min_vaddr, max_vaddr)`.

9. **[Info] Build/test evidence absent.** This review is static. Before closing the round, run `make check` on the cross target and the `--difftest` parity sweep (JMPL ordering, FP rounding, and sigsuspend return path all changed engine-visible state in both interpreter and DBT).
