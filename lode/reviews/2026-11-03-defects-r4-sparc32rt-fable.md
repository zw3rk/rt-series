# Round-4 remediation review: `8b8a259` vs `f7d73db` (sparc32rt)

Scope: static read of the audit report and the full commit diff, plus targeted greps of the current tree. No build, test, Docker, or QEMU was run. The commit message names only S32-R4-4 and S32-R4-5, but the diff addresses all sixteen items; the message under-reports its own scope.

Headline: 9 items verified, 5 partial, 2 regressions. The two regressions are consequential. Removing the wakeup-echo dedup without adding a separate wakeup path makes every thread-directed caught signal (including musl `raise()`) run the guest handler twice. The new tracked-close path grows the FD table to any guest-supplied descriptor number, so `close(INT_MAX)` allocates and zeroes two 2 GiB arrays.

## Per-item verification

**S32-R4-1 (clone startup storage) — VERIFIED.** `struct thr_start` gains `refs` (set to 2 before `thr_register`), and `thr_start_release()` decrements under `st->lock`, destroying lock/cond and freeing only on the last drop. Parent drops after reading `child_tid`; child drops in `thr_thread_finish()`. Neither party touches `st` after its own release. The `pthread_create` failure path (not in the diff) still frees directly with no child alive, which is fine.

**S32-R4-2 (retired siblings touching the new image) — PARTIAL.** Fixed: clone returns `EAGAIN` while `g_exec_retiring`; `sparc32_thr_exec_retire_done()` clears the flag after successful commit, and the failure path `_exit(127)`s so the flag cannot stick; `thr_thread_finish()` suppresses the clear-TID store for retired contexts; `sparc32_thr_is_retired()` is now purely the sticky set. Not fixed: only `sys_read` in `syscalls_min.c` checks retirement before copyout. Every other copyout path a blocked sibling can return through (`readv`, `pread64`, `recvfrom`, `recvmsg`, `wait4`, `nanosleep` remainder, `getdents`, `fstat`, `clock_gettime`, `poll`, etc.) is unguarded. The 2 s timeout still deregisters siblings without acknowledgement, which the audit explicitly asked not to treat as completion.

**S32-R4-3 (invalidate before reopening DBT admission) — VERIFIED, one unconfirmed assumption.** All `vm_invalidate_jit()` calls in `vm_mmap.c` (mmap2, mprotect, munmap, four mremap paths, reset_for_exec) now run through `vm_invalidate_jit_locked()` before `vm_lock_release()`. `dbt_lookup_locked()` no longer refreshes a stale-epoch block in place; it retires the slot (`valid=false`, `host_code=NULL`, chain cleared, `g_cached_count` decremented) and retranslates. Assumption I could not confirm within budget: `vm_lock_acquire()` holds `g_dbt_lock` via `dbt_quiesce_begin_local()`, and `vm_invalidate_jit()` was previously always called with the lock released. If `sparc32_dbt_invalidate_range()` takes `g_dbt_lock` unconditionally, every mprotect/munmap in `--dbt` mode now self-deadlocks. The conditional lock at `dbt_cache.c:106` and the "_local" depth naming suggest reentrancy is handled, but one `--difftest` run would settle it and should be done before this is called closed.

**S32-R4-4 (signal numbering) — PARTIAL.** `sparc32_sig_to_host()`/`from_host()` added in `threads.h` and applied at `sigaction`, `kill`, `tgkill`/`tkill`, `pthread_kill`, the async host handler, and the poll's deferred `kill(getpid())`. Reserved sync-fault check corrected to SPARC 10/11. Darwin identity claim is correct for all listed signals. Gaps:
- Wait-status translation is untouched. `sparc32_thr_waitpid` was not modified, so on a Linux host a child killed by host signal 10 (SIGUSR1) reports `WTERMSIG` 10, which the SPARC guest reads as SIGBUS. A guest doing `kill(child, 30)` then `wait4` sees the wrong signal.
- `to_host(29)` is identity. SPARC 29 is SIGLOST/SIGPWR; Linux AArch64 29 is SIGIO, which SPARC 23 also maps to. The mapping is not injective, so `from_host(SIGIO)` always yields 23.
- Pre-existing, now more visible: the Darwin backend uses `pthread_kill(th, SIGUSR2)` internally (`backend_darwin.c:187`). A guest `sigaction(31)` installs over that same host signal on Darwin.

**S32-R4-5 (blocked default-action signals) — PARTIAL.** Self `kill`, self `tgkill`, and cross-thread `tgkill` now queue a blocked DFL signal (excluding 9 and 17) instead of invoking host `SIG_DFL`; the poll applies termination via `kill(getpid(), to_host(s))` at unmask time, and a disposition change to CAUGHT or IGN in between is honoured correctly. Gaps: stop-default signals (TSTP/TTIN/TTOU) queued while blocked are silently discarded at unmask because `interp_dfl_terminates()` returns false and the loop `continue`s; the stop action is lost. Externally originated signals (from another process) with guest-blocked but host-`SIG_DFL` disposition still terminate the host immediately, which the audit's "integrate host reception with guest masks" item covered. No regression tests were added.

**S32-R4-6 (wakeup echo dedup) — REGRESSION.** The fix deletes both dedup steps in `interp_poll_async()` (the thread-path `sparc32_thr_claim_global(s)` and the process-path `thr_thread_has_pending(s)` skip) but does not add the distinct wakeup mechanism the audit asked for. The sender path in `thr_kill_tid()` is unchanged: for a CAUGHT target it sets the thread bit, then calls `thr_host_tgkill()`, whose host handler calls `sparc32_thr_note_signal()` and sets the process bit. Both bits now deliver independently, so the guest handler runs twice per `tgkill`. The self-target case is worse: the thread bit is set in the lookup branch and the tail `else if (tid == self_tid) return thr_kill_self()` sets the process bit too, so musl `raise()` (which is `tkill(gettid(), sig)`) invokes the handler twice. The stale comment at `threads_kill.c:248` still says "the poll dedups it against the thread bit above". The audit's loss scenario is fixed, but at the cost of systematic duplicate delivery on the common path.

**S32-R4-7 (tgkill thread-group validation) — VERIFIED.** `tgid <= 0` returns `EINVAL`; a foreign `tgid` with a locally live `tid` returns `ESRCH` before any queue mutation; a fully foreign pair delegates to the host. Signal-zero on non-Linux returns `ESRCH` for foreign groups, which is an acceptable conservative answer.

**S32-R4-8 (Darwin pthread handles) — PARTIAL.** Slots now carry `pthread_t` plus `pt_valid`; set at register (parent's self, then overwritten), after `pthread_create` with `th`, and at child entry with `pthread_self()`; cleared on deregister and on the retirement sweep. `thr_host_tgkill()` uses `pthread_kill()` when the slot is found. Gaps: `thr_live_pt_for_tid()` copies `pt` and drops `thr_live_lock` before the caller issues `pthread_kill()`, so the target can finish, deregister, and exit in between (POSIX leaves `pthread_kill` on a terminated thread undefined). The `kill((pid_t)host_tid, hsig)` fallback remains for any TID not found live, which is exactly the misuse the audit flagged.

**S32-R4-9 (exec preserves mask and pending) — VERIFIED.** The three clears (`pending_signals`, `sig_mask`, `sparc32_thr_clear_process_pending()`) are removed; dispositions and altstack still reset. Matches Linux `de_thread`/`flush_signal_handlers` semantics.

**S32-R4-10 (FD bookkeeping atomicity) — PARTIAL.** `sparc32_fd_close_tracked()` holds `thr_fd_lock` across `close()` plus untrack, and `sparc32_l2a_close()` uses it; the exec sweep now closes under the lock. Open, `dup`/`dup2`/`F_DUPFD`, and `F_SETFD` still perform the host operation before taking the lock, and the fork snapshot is unchanged. Any other `close()` sites that call `sparc32_fd_note_close()` after the host close keep the original race. Comments label the lock-across-close as R4-14 and the table growth as R4-10, which is swapped.

**S32-R4-11 (Darwin anonymous PROT_NONE remaps) — VERIFIED.** The `PROT_NONE` branch now widens the covering host pages to RW, zeroes exactly `len` bytes, and narrows only the fully interior 16 KiB pages back to NONE. Partial boundary host pages are left RW at host level, consistent with the existing non-NONE path, so sub-host-page enforcement stays with the guest-level permission checks as before.

**S32-R4-12 (beyond-EOF pages in copied file maps) — PARTIAL.** `vm_mmap2_locked()` now `fstat`s file mappings and, for whole pages past EOF, publishes protection 0, zeroes the VMA protection, and host-protects NONE; the Darwin copy path also NONEs its tail. Gaps: the fault is a permission fault, so the guest sees SIGSEGV rather than the SIGBUS Linux produces. On a Linux host this is a step backwards: the host already delivered a correct SIGBUS for those pages, and now the guest-level prot-0 check fires first with the wrong signal. Because the VMA record is rewritten to 0, a guest `mprotect(PROT_READ)` on the tail re-enables access and, on Darwin, re-exposes the zero-filled copy; `/proc/self/maps` also shows `---p`. No validity tracking across `ftruncate` grow.

**S32-R4-13 (VMA registration failures) — VERIFIED.** All three previously discarded `vm_record_region_ext_locked()` results are checked. mmap2 rolls back to a PROT_NONE reservation plus prot-0 publish and returns `ENOMEM`; the mremap extend and move paths unmap the new range before the old mapping is disturbed. `rec_fd` is the caller's `fd` or `anon_shm_fd`, not a dup, so no descriptor leaks on the failure path. Rollback rather than pre-reservation, which is acceptable.

**S32-R4-14 (descriptors above 8191) — REGRESSION.** The table now grows on demand and no descriptor is silently untracked, which fixes the audit item. However `sparc32_fd_close_tracked()` calls `thr_fd_ensure_locked(fd)` before validating the descriptor against the host. `need` is `fd + 1`, so a guest `close(0x7FFFFFFF)` performs two `realloc`s of 2 GiB and `memset`s both under `thr_fd_lock`. Under the project's documented 2 GiB Docker memory cap this is an OOM kill from one syscall. The ensure call there is unnecessary: a close only needs to clear existing entries when `fd < thr_fd_cap`.

**S32-R4-15 (duplicated BE32 helpers) — PARTIAL.** `l2a_ld_be32()`/`l2a_st_be32()` added to `l2a_access.h`; `fd_st` removed. `thr_st` in `threads.c`, `thr_ld` in `threads_exec.c`, and `sig_ld_be32`/`sig_st_be32` in `syscalls_sig.c` remain.

**S32-R4-16 (write-only survivor global) — VERIFIED.** `g_exec_survivor` and both stores are gone; grep finds no references.

## Compliance and regression notes

- Curated C11 surface: no `#include "*.c"` anywhere in `src/`, `include/`, or `tests/`. No assembly or `x18` exposure in this commit. No `sprintf`/`strcpy`/`strcat` introduced.
- Line limits: all touched files are at or under 900 lines. `syscalls.c` (879) and `threads.c` (878) are within 25 lines of the cap and will not absorb the remaining R4-2 copyout guards or R4-15 consolidation without a split.
- Redundant declarations: `syscalls.c` re-declares `sparc32_fd_close_tracked()` and `threads_exec.c` adds an `extern` for `sparc32_thr_exec_retire_done()` even though both include `os/threads.h`, which already declares them. Harmless, but should go.
- Tests: the commit touches only `src/`. None of the regressions the audit requested (immediate child exit under clone, blocked-default plus pending query plus unblock, wrong-group `tgkill`, patterned-page PROT_NONE remap, beyond-EOF read) were added, and the duplicate-delivery regression in R4-6 is exactly the kind a `raise()` counting test would have caught.

## Summary table and follow-ups

| Item | Status | Note |
|---|---|---|
| S32-R4-1 | VERIFIED | Refcounted `thr_start`, last drop destroys |
| S32-R4-2 | PARTIAL | Only `sys_read` guards copyout; timeout still deregisters without ack |
| S32-R4-3 | VERIFIED | Lock-held invalidation; `g_dbt_lock` reentrancy assumed, needs one `--difftest` run |
| S32-R4-4 | PARTIAL | No wait-status translation; SPARC 29 collides with SIGIO on Linux |
| S32-R4-5 | PARTIAL | Blocked stop-signals dropped at unmask; external signals still hit host `SIG_DFL` |
| S32-R4-6 | REGRESSION | Dedup removed, no separate wakeup: caught `tgkill`/`raise()` deliver twice |
| S32-R4-7 | VERIFIED | `tgid` validated before lookup and queueing |
| S32-R4-8 | PARTIAL | `pthread_kill` after lock drop; `kill(host_tid)` fallback remains |
| S32-R4-9 | VERIFIED | Mask, thread pending, process pending preserved |
| S32-R4-10 | PARTIAL | Close and sweep serialized; open/dup/F_SETFD and fork snapshot not |
| S32-R4-11 | VERIFIED | PROT_NONE remaps zero-filled |
| S32-R4-12 | PARTIAL | SIGSEGV not SIGBUS (also on Linux); `mprotect` re-exposes tail; no regrow tracking |
| S32-R4-13 | VERIFIED | Rollback on all three record failures |
| S32-R4-14 | REGRESSION | `close(huge fd)` grows the table to `fd+1` before validation |
| S32-R4-15 | PARTIAL | `thr_st`, `thr_ld`, `sig_ld/st_be32` still duplicated |
| S32-R4-16 | VERIFIED | Global removed |

Newly discovered consequential follow-ups:

1. **Duplicate handler invocation for thread-directed caught signals** (`src/os/threads_kill.c:244-258`, `src/interp/interp_signal.c:580`). Introduce a dedicated host wakeup signal whose handler sets no guest state, use it for the sigsuspend wakeup, and keep the guest-visible handler for externally originated signals only. Add a `raise(SIGUSR1)` counting regression.
2. **Unbounded allocation from `close()`** (`src/os/threads_fd.c:107`). Drop the `thr_fd_ensure_locked(fd)` call from `sparc32_fd_close_tracked()`; clear entries only when `fd < thr_fd_cap`.
3. **Beyond-EOF fault type on Linux hosts** (`src/rt32/vm_mmap.c:222-245`). Either gate the prot-0 tail publish to the Darwin copied-file backend, or carry a per-page "file-invalid" marker so the fault path raises SIGBUS with the correct code.
4. **Wait-status signal translation** (`sparc32_thr_waitpid`). Map `WTERMSIG`/`WSTOPSIG` through `sparc32_sig_from_host()` before encoding the guest status word.
5. **Verify DBT lock reentrancy under the new lock-held invalidation** before closing R4-3. One existing `--difftest` run that exercises `mprotect` in `--dbt` mode is sufficient.
