I have all the evidence. Here's the review.

---

## Round-10 Remediation Review — `bb78b2d`

### S64-R10-1: `proc_clone` swaps the SPARC tls/ctid registers — **VERIFIED**

**Defect:** `sparc64_proc_clone` declared `(…, parent_tid_va, child_tid_va, tls_va)` but the call site at `syscalls_min.c:569` passes positional `(o0, o1, o2, o3, o4)` where the SPARC ABI is `o2=ptid, o3=tls, o4=ctid`. So `child_tid_va` received `o3` (tls) and `tls_va` received `o4` (ctid).

**Fix evidence:**
- `proc.h:52` and `proc.c:195–196` now declare `(…, parent_tid_va, tls_va, child_tid_va)` — matching the SPARC `o2=ptid, o3=tls, o4=ctid` order.
- `proc.c:200` casts `(void)tls_va` on `o3`, and `proc.c:208` passes `(parent_tid_va, child_tid_va, set_flags)` to `proc_do_fork` — `parent_tid_va` is `o2`, `child_tid_va` is `o4`. Correct.
- The sibling CLONE_VM path (`sparc64_thread_clone` at `threads.h:128–130` / `threads.c:542–544`) already had `(…, ptid, tls, ctid)` — both paths now agree.
- Call site `syscalls_min.c:569` passes `(o0, o1, o2, o3, o4)` unchanged; the fix is purely in the declaration, which is correct since the positional binding is now right.

### S64-R10-2: `PROC_CLONE_PARENT_SETTID` was `0x10U`, must be `0x100000U` — **VERIFIED**

**Defect:** `proc.c` had `#define PROC_CLONE_PARENT_SETTID 0x10U` — collides with low signal bits; the Linux value is `0x100000`.

**Fix evidence:**
- `proc.c:55` now reads `#define PROC_CLONE_PARENT_SETTID 0x100000U`.
- Matches `threads.h:43` `SPARC64_CLONE_PARENT_SETTID UINT64_C(0x100000)`.
- `_Static_assert` in `test_r10_threading.c:62–63` pins the public constant.
- The guard at `proc.c:171` and flag extraction at `proc.c:206` use this constant — parent-tid stores now trigger only when the guest actually sets `CLONE_PARENT_SETTID`.

### S64-R10-3: `execve` neither rejects nor tears down live threads — **VERIFIED**

**Defect:** `sparc64_proc_execve` destroyed `g->space` while sibling host threads still reference it.

**Fix evidence:**
- `proc.c:479`: `if (sparc64_threads_has_live_peers(ctx)) { return -EBUSY; }` — inserted before malloc/load, so the entire exec is rejected early.
- `threads_fork.c:68–80`: `sparc64_threads_has_live_peers` iterates `thr_table[0..THR_MAX_THREADS-1]`, counting slots that are `used && running && !done && ctx_ref != ctx`. Returns 1 if any exist. Locks `thr_table_lock` around the scan.
- The approach (refuse, return `-EBUSY`) is the conservative fix noted in the defect report ("refuse while peers are alive"). This is a safe choice; Linux kills siblings, but refusing is correct until full thread-group teardown is implemented.
- Test coverage: `test_r10_threading.c` lines 184–199 inject a running peer (detected), then mark it `done` (ignored) — both branches exercised.

### S64-R10-4: `fork()` with live threads has no lock quiescence — **VERIFIED**

**Defect:** No `pthread_atfork` handler; a child forked while a peer holds `thr_table_lock` inherits a permanently locked mutex copy.

**Fix evidence:**
- `threads_fork.c:86–101`: Three static handlers registered via `pthread_atfork`:
  - `thr_atfork_prepare` — locks `thr_table_lock` (blocks until any holder releases).
  - `thr_atfork_parent` — unlocks after fork returns in parent.
  - `thr_atfork_child` — unlocks in the child.
- `threads_fork.c:103–110`: `sparc64_threads_fork_init` registers the triple once (static `registered` guard).
- `threads.c:134`: Called from `sparc64_threads_boot` inside `thr_table_lock`, so it runs exactly once during initialization.
- Lock ordering: the forker already holds `thr_big_lock` (via `sparc64_proc_clone` → reject path or `proc_do_fork` path under guest lock); `prepare` takes `thr_table_lock` — this is `big → table`, consistent with the documented order in `threads.h:82–84`.
- Test: `test_r10_threading.c` lines 162–226 spawns a holder thread that locks `thr_table_lock` for 200ms, then forks — the child `trylock` succeeds only if the atfork handlers worked.

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None (`grep` clean) |
| `.c` includes | None found |
| `sprintf`/`strcpy`/`strcat` | None found |
| `_Generic` / `<threads.h>` / Annex K | None found |
| File sizes | `proc.c` 867, `threads.c` 895, `threads_fork.c` 112, `threads.h` 151, `test_r10_threading.c` 253 — all <= 900 |

### Newly Introduced Bug Check

1. **`thr_table_lock` moved from `threads.c` to `threads_fork.c`**: The `static` was dropped and the variable is now `extern` in `threads.h:84`. All users (`threads.c`, `threads_fork.c`, `test_r10_threading.c`) include `threads.h` — linkage is correct; no duplicate definition.

2. **`sparc64_threads_fork_init` called under `thr_table_lock`**: At `threads.c:134`, `fork_init` is called inside the `thr_table_lock` critical section. `fork_init` itself does not take `thr_table_lock` (it only calls `pthread_atfork`), so no deadlock.

3. **`sparc64_threads_fork_init` idempotency**: Uses a `static int registered` guard (`threads_fork.c:106`). The test calls it twice (`test_r10_threading.c:181–182`) to exercise this path. Safe.

4. **`-EBUSY` from execve**: This is a divergence from Linux semantics (Linux kills siblings rather than refusing). Guest programs calling `execve` in a multi-threaded process will get an unexpected error. This is documented and intentional — the comment at `proc.c:475–478` explains the rationale. Acceptable as a conservative intermediate fix.

5. **Makefile change**: `threads_fork.c` added to the `check-thr-granule` target's source list (`Makefile:88`). Required because `thr_table_lock` now lives there. Correct.

### Summary

| ID | Verdict | Evidence |
|---|---|---|
| S64-R10-1 | **VERIFIED** | `proc.h:52`, `proc.c:195–196`: param order now `(ptid, tls, ctid)` matching SPARC ABI |
| S64-R10-2 | **VERIFIED** | `proc.c:55`: `0x100000U`, matches `threads.h:43` |
| S64-R10-3 | **VERIFIED** | `proc.c:479`: early `-EBUSY` gate; `threads_fork.c:68–80`: live-peer scan |
| S64-R10-4 | **VERIFIED** | `threads_fork.c:86–110`: `pthread_atfork` triple registered at boot |

All 4 items remediated. No new bugs found. Curated C11 compliant, all files within 900-line limit.
