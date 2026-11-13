# Round-10 Deep-Dive 4 Static Audit: Threading / Lifecycle / Futex

Scope read-only: `src/os/clone.c`, `src/os/sched.c`, `src/os/sched_priv.h`, `src/os/thread.h`, `src/os/minsys.c`, `src/os/sigstate.c`, `src/os/sigframe.c`, `src/os/syscall_nr.h`, `src/loader.c`, `src/vm/vm64.c`, `src/vm/vm_file.c`, `src/os/backend_*.c`. No files modified, no builds/tests run, no subagents.

## Summary

| ID | Severity | Location | Finding |
|----|----------|----------|---------|
| LA64-R10-1 | `BUG` (self-deadlock) | [clone.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c) (`668`, `684`), [sched.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sched.c) (`257`–`259`), [clone.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c) (`192`, `743`–`746`) | Worker thread exit re-acquires non-recursive `clone_lock` → every `CHILD_CLEARTID` thread exit hangs |
| LA64-R10-2 | `DEFECT` (missing gate) | [minsys.c](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c) (`440`–`509` vs `216`–`217`) | `execve` enforces no live-worker requirement nowhere; siblings keep stepping the replaced image |

## LA64-R10-1: `clone_lock` self-deadlock on worker thread exit

`clone_lock` is a plain non-recursive mutex ([clone.c:76](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:76)). `la64_clone_thread_exit` holds it across the scheduler exit ([clone.c:668](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:668), [clone.c:684](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:684)):

```c
pthread_mutex_lock(&clone_lock);          /* 668 */
...
la64_sched_thread_exit(me, word, clone_store_u32);  /* 684, lock held */
```

Inside, `sched_thread_exit` takes `sched_mu` and invokes the store callback ([sched.c:257-259](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sched.c:257)). `clone_store_u32` ends in `la64_clone_invalidate_ll` ([clone.c:192](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:192)), which takes `store_lock` then `clone_lock` ([clone.c:743-746](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:743)). Same thread, non-recursive mutex, already held → self-deadlock (practically a hang on NPTL default mutexes).

Reproduction: `clone(CLONE_VM|CLONE_THREAD|CLONE_SIGHAND|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID)` (standard musl `pthread_create`), then thread return/`exit`. Any nonzero `clear_word` triggers it; without `CLEARTID` the store is skipped and exit proceeds.

Minimal fix: snapshot `dead`/`ctid`/`me` under `clone_lock`, release it, then call `la64_sched_thread_exit`, then re-acquire only to clear the slot — or pass `clear_word = 0` there, since the post-unlock path ([clone.c:689-708](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:689)) already performs the lock-clean zero-store, LL invalidation, and host `FUTEX_WAKE` (plus add a `sched_wake` for queue waiters).

## LA64-R10-2: `execve` proceeds with live clone workers

`sys_clone_process` refuses process forks with live workers ([minsys.c:216-217](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:216)), but `sys_execve` ([minsys.c:440-509](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:440)) has no such gate even though its own contract states it "requires no live clone workers" ([minsys.c:435-437](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:435)). `la64_load` ([loader.c:677-742](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:677)) resets only the caller's context and memory; worker `pthread`s keep spinning in `clone_thread_main`, the sched ring keeps their turns, sibling soft-TLBs are never revoked, and sibling `sigstate` entries persist (`la64_signal_reset_for_exec` touches only dispositions/altstack).

Reproduction: main thread creates a spinning worker, then calls `execve` on a valid LA64 image. Expected Linux behavior is sibling termination; here workers execute the replacement image with stale contexts (crash or cross-image execution), and post-`exec` scheduling can hand the turn to dead slots.

Minimal fix mirroring the fork gate at `sys_execve` entry:

```c
if (la64_clone_has_live_workers() != 0)
    return -(long)LA64_EAGAIN;
```

## Verified clean (0 findings)

- `clone` creation: `$tp` set only under `SETTLS` (else inherits parent's), child `$a0 = 0`, `pc + 4`, LL cleared ([clone.c:559-566](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:559)); parent/child tid stores validated and LL-invalidated ([clone.c:573-602](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:573)); slot lifecycle cleared on every error path.
- `fork`/`wait4`/`waitid`: caller LL cleared at syscall entry ([minsys.c:717](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:717)); fork child resets clone/sched/signal/VM state with vpid table cleared; `wait4`/`waitid` translate virtual pids both directions. The check-then-`fork` window is not a live race: post-first-clone all guest steps are turn-serialized, pre-first-clone is single-threaded.
- `clone3` (nr 435): undispatched, falls through to `-ENOSYS` ([minsys.c:780-790](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:780)) so guests correctly fall back to `clone`. Cross-thread `tgkill` returning `ESRCH` is the documented self-only contract ([sigframe.h:16](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.h:16)), not a defect.
- `futex`: 32-bit compare with `(uint32_t)` truncation, `EAGAIN` on mismatch, timespec validation (`sec<0`, `nsec` range) all correct; untimed waits recheck under `sched_mu` before enqueue and `WAKE` is serialized under the same mutex, so no lost wakeup; timed waits correctly leave/rejoin the ring around the host wait; `WAKE`/`REQUEUE` budget accounting avoids double-wake.
