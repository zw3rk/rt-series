# sparc64rt — Round 2 static audit

**HEAD:** `3ead4f98729076b08a8d13572901ba8cca2e700c`

**Result:** **12 findings: 3 High, 6 Medium, 3 Low.** No Critical finding established.

**Inventory:** 107 C/header/assembly files containing **36,316 lines** under `src/` and `include/`; **41,481 lines** including `tests/`. Also inspected `Makefile`, the Round-1 report, specifications, and selected remediation diffs.

Seven batched shell inspection turns were used. No builds, compilers, QEMU, Docker, or test scripts were intentionally run. Apple’s Git launcher emitted tool-discovery errors; subsequent Git inspection used the Nix-installed executable. Final `git status --short` was empty.

Coverage combined repository-wide inventory and searches with focused semantic inspection. **This is not exhaustive verification of every module or line.** Some large inspection outputs were truncated. FP rounding, complete VM/COW behavior, concurrent cache invalidation, and all syscall translations remain unqualified.

### Round-1 remediation verification

Source inspection confirms the full FP initialization change, publication checks before JIT entry, FCC restoration, exec window invalidation, decoder consolidation, partial-write accounting, additional VM bounds checks, and worker-start argument snapshotting.

However:

- The new futex implementation introduces signal-safety and arithmetic problems and retains incomplete requeue semantics.
- Applying a signal mask before `poll`/`kevent` does not supply atomic mask-and-wait semantics.
- JIT publication failure is checked, but another W^X transition still discards failure.
- File splitting satisfies the 900-line ceiling; the largest inspected source is 863 lines.
- No runtime correctness or test-pass claims are made.

Darwin backend findings below concern implemented interface contracts. Searches found no production callers for several affected `rt_host_*` interfaces; their reachability from current guest execution is not established.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| Medium | 0 | 3 | 3 | 0 | 0 | 0 | 6 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **3** | **3** | **3** | **1** | **1** | **1** | **12** |

## 1. Bugs & Defects

### High

- [ ] **S64-R2-1 — High — BUG — Signal frames corrupt the Y register**
  - **Where**: `src/os/sync_sig.c:482-486` (`sparc64_sync_sig_deliver`); `src/os/sync_sig.c:585-590` (`sparc64_sync_sig_return`).
  - **What breaks / Why**: The frame contains adjacent **32-bit** `y` and `magic` fields. Delivery writes `ctx->y` using `put_u64be` at `0x1d8`, then overwrites its lower four bytes with `magic` at `0x1dc`. For an ordinary 32-bit Y value, the actual frame Y becomes zero. Return reads eight bytes, incorporating the magic value into restored Y. A signal round trip therefore changes arithmetic state, affecting subsequent Y-dependent multiplication/division sequences.
  - **Fix**: Write and read Y as a big-endian 32-bit field. Keep magic separate. Add a regression that sets a nonzero Y, checks the handler-visible frame, and verifies Y after sigreturn.

- [ ] **S64-R2-2 — High — BUG — Delay-slot syscalls lose the pending branch destination**
  - **Where**: `src/interp/interp.c:254-260` (`exec_delay`); `src/interp/interp.c:312-325,339-364` (`exec_cti`); `src/os/guest_engines.c:244-257` (`run_interp`).
  - **What breaks / Why**: A taken branch executes its delay slot before publishing the delay instruction’s architectural `pc` and pending target in `npc`. If the slot contains a syscall trap, `exec_delay` returns immediately and the branch never commits its target. `run_interp` passes the unchanged CPU context into syscall handling; `step.pc` is used to identify the trap, but does not repair the pending control transfer. The syscall therefore sees the branch’s old PC/NPC pair, and ordinary syscall advancement cannot resume at the branch target.
  - **Fix**: Represent the architectural transition explicitly: before executing the delay instruction, publish its PC and the selected next PC. Preserve that pair across traps and syscalls. Test a taken branch with a returning syscall in its delay slot, including interpreter fallback from DBT.

- [ ] **S64-R2-3 — High — BUG — Cache flush forgets a failed RX-to-RW transition**
  - **Where**: `src/dbt/emit_rt.c:70-93` (`dbt_flush_all`); `src/dbt/dbt.c:122-142` (`dbt_stage`).
  - **What breaks / Why**: `dbt_flush_all` ignores `a32h_wx_reopen` failure, clears `arena_published`, and resets `arena_used`. If the permission change fails, the arena remains RX while bookkeeping says it is writable. Subsequent staging skips reopening and returns that memory for code emission, causing a host write fault. The Round-1 publication fix covers entry into unpublished code but not this reverse transition.
  - **Fix**: Change arena state only after successful reopening. Propagate failure or discard the arena and fall back to interpretation. Exercise both publication and reopening failures through an injectable host-memory interface.

### Medium

- [ ] **S64-R2-4 — Medium — DEFECT — Futex requeue reports the wrong count and permits ineffective moves**
  - **Where**: `src/os/backend_darwin_sync.c:348-387` (`rt_host_futex_requeue`); `src/os/backend_darwin_sync.c:148-157` (`futex_match`).
  - **What breaks / Why**: The implementation counts moved waiters in `requeued` but returns only `woken`. A request that moves waiters without waking any returns zero despite changing the queue. If `key2 == NULL`, it increments `requeued` without changing either the key or address. Additionally, keyed moves retain the old `uaddr`; a subsequent address-only lookup can still match the source address.
  - **Fix**: Return the total number woken and requeued. Require a valid destination identity and update the matching representation consistently. Reject unsupported keyed/address-only combinations rather than reporting an ineffective move.

- [ ] **S64-R2-5 — Medium — DEFECT — Temporary poll masks still permit lost signal wakeups**
  - **Where**: `src/os/backend_darwin.c:578-615` (`darwin_sigmask_enter`, `rt_host_ppoll`); `src/os/backend_darwin.c:680-702` (`rt_host_epoll_pwait`).
  - **What breaks / Why**: `pthread_sigmask` and the blocking operation are separate calls. A pending signal can be delivered after the mask changes but before `poll` or `kevent` starts. With no worker wake pipe, `ppoll` can then sleep for the entire timeout or indefinitely. The epoll path does not register the worker wake pipe with this wait; checking `sig_seq` after `kevent` cannot wake a wait already sleeping. Thus Round-1’s atomic-mask requirement remains unresolved.
  - **Fix**: Use a platform-supported atomic mask-and-wait mechanism or a complete signal-notification protocol with persistent readiness included in every wait. Define and enforce behavior when `ws == NULL`.

- [ ] **S64-R2-6 — Medium — DEFECT — Darwin directory reads discard unread entries**
  - **Where**: `src/os/backend_darwin.c:385-403` (`rt_host_getdents64`).
  - **What breaks / Why**: Each call creates a fresh buffered `DIR` on a duplicate of the caller’s descriptor. `readdir` can advance the shared underlying directory offset beyond the entries returned to the caller. When the output buffer fills, `closedir` discards remaining buffered entries, and the next call resumes past them. The entry that fails the size check has also already been consumed. If even the first record does not fit, the function returns zero, falsely indicating EOF.
  - **Fix**: Preserve directory stream state across calls or use an unbuffered directory-entry interface with explicit offsets. Retain the first unreturned entry and report an appropriate error when the buffer cannot hold any record.

### Critical / Low

No additional findings established in these severity groups.

## 2. Curated C11 & UB Issues

- [ ] **S64-R2-7 — Medium — C11 — Signal notification now locks a pthread mutex**
  - **Where**: `src/os/backend_darwin_sync.c:135-145,160-169` (`futex_lock`, `futex_broadcast_all_signals`); `src/os/backend_darwin_sync.c:210-216` (`rt_host_worker_notify_signal`); `src/os/backend.h:45-59` (signal-wakeup contract).
  - **What breaks / Why**: The notification function now enters `g_futex_mu` and broadcasts pthread condition variables. These operations are not async-signal-safe. If invoked by a signal handler interrupting a thread that holds this mutex, notification deadlocks on that same thread. First-use notification can also initialize condition variables inside the handler. This is a regression in the intended signal-notification interface; a current production handler-to-function call chain was not found.
  - **Fix**: Keep handler notification limited to async-signal-safe operations. Arrange for normal execution context to process the persistent wake notification and signal waiters without losing wakeups.

- [ ] **S64-R2-8 — Medium — C11 — Worker mutex initialization races between first callers**
  - **Where**: `src/os/backend_darwin_sync.c:65-79` (`g_workers`, `workers_lock`); `src/os/backend_darwin_sync.c:82-115` (worker registration and lookup).
  - **What breaks / Why**: `g_workers.init` is read and written without synchronization before the mutex is acquired. Concurrent first callers can both initialize the same mutex, or one can reinitialize it while another begins using it. The flag accesses constitute a C data race, and concurrent initialization invalidates the pthread synchronization object.
  - **Fix**: Initialize the mutex statically with `PTHREAD_MUTEX_INITIALIZER`, removing the flag, or use `pthread_once` for any initialization that genuinely needs execution.

- [ ] **S64-R2-9 — Medium — C11 — Futex timeout conversion overflows signed arithmetic**
  - **Where**: `src/os/backend_darwin_sync.c:250-271` (`rt_host_futex_wait_bitset`).
  - **What breaks / Why**: Only nanoseconds are validated. Relative seconds are multiplied by one billion in `int64_t`; absolute deadlines also subtract and multiply in signed arithmetic. A large positive timeout, such as `tv_sec = INT64_MAX`, causes signed overflow and undefined behavior instead of a well-defined long wait or error. Negative relative seconds are reported as timeout expiration rather than rejected as an invalid timespec.
  - **Fix**: Validate seconds and nanoseconds, use checked arithmetic, and retain a normalized seconds/nanoseconds representation instead of collapsing unrestricted deadlines into signed nanoseconds.

## 3. DRY — Intra-Repo Duplication

- [ ] **S64-R2-10 — Low — DRY — MOVcc adds another copy of the FP condition table**
  - **Where**: `src/dbt/emit_cond.c:184-187,218-220` (`sparc64_emit_movcc`); `src/dbt/emit_fpcmp.c:19-33` (`fp_taken_mask`, `fp_taken_compute`).
  - **What breaks / Why**: The remediation introduces a second identical 16-entry FP condition mask inside the DBT. MOVcc and floating conditional operations now maintain the same truth table separately, creating another drift point immediately after consolidating the raw decoder.
  - **Fix**: Define one internal DBT condition table or emission helper and use it from both files. Keep independent oracle tests. No cross-repository extraction is needed.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S64-R2-11 — Low — YAGNI — Obsolete runtime helpers have no callers**
  - **Where**: `src/dbt/emit_rt.c:182-222` (`s64_rt_mem`, `s64_rt_win`).
  - **What breaks / Why**: Repository-wide searches found definitions and historical comments but no calls or function-address references to either helper. They retain superseded memory/window execution paths and misleading claims about active call sites, adding code that must appear correct without contributing to execution.
  - **Fix**: Remove these internal helpers and update stale references, unless a concrete external consumer requires them. If such a consumer exists, declare and document that interface explicitly.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S64-R2-12 — Low — CLEAN — Backend contract describes synchronization mechanisms the code no longer uses**
  - **Where**: `src/os/backend.h:45-59` (blocking and preemption contract); `src/os/backend_darwin_sync.c:303-319` (`rt_host_futex_wait_bitset`); `src/os/backend_darwin_sync.c:403-420` (`rt_host_clock_nanosleep`).
  - **What breaks / Why**: The public contract describes futex sleeping through `__ulock_wait2` and signal wakeup through `__ulock_wake`. The implementation now uses pthread condition variables. The same comment promises kqueue-based sleep including a worker wake descriptor, while `rt_host_clock_nanosleep` discards `ws` and `expected_seq` and calls `nanosleep`. These comments incorrectly assure reviewers that lost-wakeup protection exists.
  - **Fix**: Document the actual mechanisms and supported guarantees. Remove obsolete ulock descriptions and identify unsupported wake protocols until implemented.

**Static hygiene results:** No inventoried source exceeded 900 lines. Searches found no production banned string calls or textual `.c` includes. Banned string calls in `test_h2_string.c` exercise libc behavior. Textual `x18` matches were comments; numeric emitter encodings were not exhaustively decoded, so register reservation is not fully qualified.