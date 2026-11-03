# Round-10 Static Audit: Threading / Lifecycle / Futex

Scope read in full: [threads.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.c), [threads_fork.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads_fork.c), [threads.h](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.h), [proc.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.c), [proc.h](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.h), plus [syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c) dispatch, [guest_engines.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_engines.c) thread entry, [guest_run.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c) exec commit, [sync_sig.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/sync_sig.c) exec reset, and the Darwin futex backend. No files modified, nothing built or run. Four defects found; the futex value-revalidation, `%g7`/stack/`%o0` handling on the CLONE_VM path, ctid store-plus-WAKE on thread exit, child slot/TLB reset, and signal-disposition reset on exec were verified correct and are not reported.

| ID | Where | What | Fix |
|---|---|---|---|
| S64-R10-1 | proc chain | Child-tid stored to tls addr | Reorder params |
| S64-R10-2 | proc.c:55 | Wrong SETTID constant | Use 0x100000 |
| S64-R10-3 | execve path | No thread teardown | Gate or reap peers |
| S64-R10-4 | fork path | No lock quiescence | Add atfork triple |

## S64-R10-1: `proc_clone` swaps the SPARC tls/ctid registers

`sparc64_proc_clone` declares `(flags, stack_va, parent_tid_va, child_tid_va, tls_va)` ([proc.h](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.h:53)) and is called positionally with `(o0..o4)` ([syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:569)). The documented SPARC order is `o2=ptid, o3=tls, o4=ctid` ([threads.h](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.h:15)), which the sibling CLONE_VM path follows (`thread_clone(..., o2=ptid, o3=tls, o4=ctid)` at [syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:567)). So the noVM path binds `child_tid_va=o3` (actually tls) and `tls_va=o4` (actually ctid). Reproduction: guest `clone(CLONE_CHILD_SETTID|SIGCHLD, stack, NULL, tls, ctid)` without `CLONE_VM` writes the child pid to the tls address (guest memory corruption) and never writes ctid (waiters hang). Fix: reorder the parameters to `(flags, stack_va, parent_tid_va, tls_va, child_tid_va)` and adjust the `proc_do_fork` call accordingly.

## S64-R10-2: `PROC_CLONE_PARENT_SETTID` is `0x10U`, must be `0x100000U`

[proc.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.c:55) defines `0x10U`; the correct Linux value is `0x100000` (cf. [threads.h](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.h:43)). Two failures follow in `proc_do_fork`: genuine `PARENT_SETTID` requests are silently dropped (parent_tid word never stored), and bit `0x10` is a low exit-signal bit, so any fork-like clone whose signal includes it (e.g. `SIGCHLD=20=0x14`) with nonzero `o2` performs a spurious parent_tid store. Reproduction: `clone(SIGCHLD, stack, ptid=X, 0, 0)` stores the pid to `X` though no `SETTID` was requested. Fix: one-line constant change to `0x100000U`.

## S64-R10-3: `execve` neither rejects nor tears down live threads

`sparc64_proc_execve` ([proc.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.c:455)) never consults thread state, and `sparc64_guest_exec_image` ([guest_run.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:637)) destroys `g->space` (lines 713–716) while sibling host threads share that same `guest_state_t` via `space_ctx`. Peers blocked in futex WAIT (big lock dropped) wake into replaced or destroyed mappings — `thr_resolve` fails with `EFAULT` or, worse, the old uaddr aliases new-image bytes — and running peers keep stale PCs into unmapped space. Linux kills all other threads at exec. Fix: at execve entry, count live peers and either refuse or park/reap them before the load-segments commit.

## S64-R10-4: `fork()` with live threads has no lock quiescence

`proc_do_fork` calls `fork()` directly ([proc.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.c:142); the multithreaded-fork combination is in scope per [threads_fork.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads_fork.c:9)), and no `pthread_atfork` handler exists anywhere in `src/`. `threads_fork.c` clears ghost slot bits but cannot reset a mutex word: if a peer holds `thr_table_lock` at the fork instant (clone scan at [threads.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.c:560), `entry_done` at line 760, futex live-count at line 367, robust-list paths), the child's copy stays locked forever and its first clone/futex/gettid deadlocks. Reproduction: one thread looping clone/exit or futex WAIT/WAKE while another loops fork; the child then calls gettid or futex and hangs. Fix: register an atfork triple in `sparc64_threads_boot` — prepare takes `thr_table_lock` (consistent with the global big→table order, since the forker already holds big), parent and child release it.

Verified clean: futex revalidation is atomic in-kernel on Linux (original-value compare at sleep) and under `g_futex_mu` on Darwin ([backend_darwin_futex.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_darwin_futex.c:158)); relative-WAIT deadline slicing and WAIT_BITSET absolute-timeout passthrough are correct; CLONE_VM `%g7`, stack, `%o0=0`, and ctid clear-plus-WAKE are correct; fork-child slot/TLB/`proc_nchildren` reset is correct; exec signal reset preserves `IGN` and the blocked mask correctly.

