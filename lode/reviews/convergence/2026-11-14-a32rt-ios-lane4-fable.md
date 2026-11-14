## a32rt 32-bit iOS / DBT signal & thread review

Scope: `src/ios/ios_signals.c`, `src/ios/ios_threads.c`, `src/signals.c`, `src/os/os_sys_thread_sig.c`. Line refs are to the files as read. Items marked *unverified* depend on code outside these four files.

### P1

**P1-1 Self-delivered signal from `sigsuspend` / `pthread_kill(self)` corrupts r0.**
`src/ios/ios_signals.c:645` and `:693` call `a32_ios_signals_check_pending` (which runs `ios_deliver_signal` and rewrites r0..r3, sp, lr, pc) *before* returning `-IOS_EINTR` / `0` to the svc dispatcher. Two consequences: (a) the saved frame `mc.r[0]` (`:288`) holds the pre-syscall argument (the mask), not `EINTR` with carry set, so after `sigreturn` libSystem's `sigsuspend` returns garbage instead of `-1/EINTR`; (b) if the dispatcher writes the return value into r0 after these functions return (as `a32_ios_bsd_err` does elsewhere), the handler pointer passed to `_sigtramp` in r0 is overwritten. Fix: mirror `pwait_sigmask_enter` (`os_sys_thread_sig.c:115-123`): set `regs[0] = EINTR` and CPSR.C *before* `check_pending`, and have the caller skip result writeback when `ctx->exit_reason == A32_EXIT_BRANCH`.

**P1-2 psynch/ulock bucket aliasing causes lost wakeups.**
`src/ios/ios_threads.c:438,458,467,478,515` hash the guest address into 64 condvar buckets. `302/304/308/516` use `pthread_cond_signal` on the bucket; `301..307` (`:450`) do a single unconditional `cond_wait` with no predicate loop. If waiters on addresses A and B share a bucket, a wake for A can be consumed by B (which returns "success" spuriously) while A sleeps forever. Fix: always `pthread_cond_broadcast` (or chain a per-address waiter list) and loop on the predicate in 301..307 like 515 does. Also `515` (`:487-506`) re-sleeps if the word is unchanged after a wake; `__ulock_wake` with an unchanged value is legal, so track a per-bucket wake generation instead of only the word.

**P1-3 Statically initialised mutexes/condvars return EINVAL.**
`src/ios/ios_threads.c:649,655,661,673-674,685,694` call `mx_lookup(…, false)` / `cv_lookup(…, false)`. `PTHREAD_MUTEX_INITIALIZER` / `PTHREAD_COND_INITIALIZER` never go through `92`/`97`, so the first `pthread_mutex_lock` on a static mutex fails with EINVAL. Fix: use `create=true` in lock/trylock/unlock/wait/signal/broadcast; keep `false` only for destroy.

**P1-4 Darwin-host futex WAIT ignores wakes and sleeps the full timeout.**
`src/os/os_sys_thread_sig.c:259-270` emulates timed `FUTEX_WAIT`/`WAIT_BITSET` with `nanosleep` for the whole duration and always returns `-ETIMEDOUT` (`:274`), so a guest `pthread_cond_timedwait` never returns early on signal/broadcast. Untimed waits `return false` (`:250`) to an unseen fallback. Also `a0` is dereferenced at `:233/:238/:245` without a range check (host SIGSEGV outside a block → `_exit`, `signals.c:459`). Fix: reuse the bucketed condvar scheme from `ios_threads.c:354-368` for FUTEX_WAIT/WAKE/REQUEUE with `pthread_cond_timedwait`, and add `a32_guest_range_ok(ctx, a0, 4, PROT_READ)` → `-EFAULT`.

### P2

- **P2-1 Shared siginfo table across threads.** `ios_signals.c:146` `g_ios_pending_info[32]` is process-global but `pending_signals` is per-ctx; writes from `:384` (host handler, any thread) and `:438` race with another thread's `ios_fill_siginfo`. Linux path correctly uses `_Thread_local` (`signals.c:182`). Make it `__thread` or move into `a32_ctx_t`.
- **P2-2 Async signals landing on a ctx-less host thread are dropped.** `signals.c:428-434` returns silently when `g_tls_ctx == NULL` (helper/exiting threads, window between `set_thread_ctx(NULL)` and `pthread_exit`). Forward with `pthread_kill(main_thread, sig)` or keep a process-level pending set drained by the main ctx.
- **P2-3 iOS host handlers always `SA_RESTART`.** `ios_signals.c:477` → `signals.c:582`. Darwin default is no-restart, so a guest handler without `SA_RESTART` never sees `EINTR` from blocking `read`/`wait4`. Pass the guest flag through like `a32_sys_rt_sigaction` does (`signals.c:691-694`).
- **P2-4 `pthread_join` on main or self.** `ios_threads.c:612-618`: `thr_by_pthread(0xFFFF5400)` yields slot 0 with `ht == 0` → `pthread_join(0)` UB; self-join blocks forever. Return `EINVAL` for slot 0, `EDEADLK` when `t->ch == ctx`.
- **P2-5 TSD destructors never run.** `g_key_dtor` (`:76`) is stored but `tsd_clear` (`:79`) only NULLs slots at `:251/:419/:818`. CF/objc autorelease-pool and `errno`-per-thread code depends on destructors. Run up to `PTHREAD_DESTRUCTOR_ITERATIONS` passes of guest calls before freeing the ctx (reuse the `ONCE_RESUME` trampoline mechanism).
- **P2-6 `sigsuspend` returns spuriously.** `ios_signals.c:636-653`: a host signal mapped to an ignored/default-ignored Darwin signal wakes `sigsuspend` with nothing pending, yet the function returns `-EINTR`. Loop until `pending & ~mask` is non-zero and deliverable.
- **P2-7 Blocking stubs are not signal-interruptible.** `93`, `98`, `90`, `301..307`, `515` block in host pthread calls; a `pthread_kill` only sets a pending bit (`:561`) and the signal is delayed until the wait ends. Darwin's `psynch_cvwait` returns `EINTR`. Use timed waits with a periodic `pending_signals` check, or `pthread_cond_broadcast` the target's bucket from `a32_ios_thread_kill_target`.
- **P2-8 Thread-port aliasing.** `ios_threads.c:235,547,558` derive the Mach port from `host_tid & 0xFF`; with >256 live-or-recycled tids two threads alias and `pthread_kill` hits the wrong one. Allocate ports from the slot index (`0x203 + 4*idx`) instead.
- **P2-9 (candidate, unverified) Lazy flags vs. sync trap.** `signals.c:478` takes NZCV from host PSTATE. If `flags_elided` means dead-flag elimination, a fault inside such a block exposes stale CPSR to the guest handler. Needs a side-table bit; verify in `jit.c`.

### PERF (hypotheses, unmeasured)

- **PERF-1 Guest mutex/cond ops take a global host mutex plus O(64) linear scan.** `ios_threads.c:92-115,134-157`, hit on every `93/95/98/99`. Also hard cap of 64 live mutexes/condvars (`MX_N`) → `ENOMEM` for real apps. Replace with an open-addressed hash keyed by gva, per-bucket locks, growable.
- **PERF-2 `pthread_self` / `getspecific` / `setspecific` scan the thread table under `g_thr_mu`.** `ios_threads.c:584-586,774,781` (`thr_by_ctx` is O(64) per call; objc/CF call `pthread_getspecific` constantly). Cache the slot index in `a32_ctx_t` at spawn.
- **PERF-3 `sigprocmask` re-walks 31 signals calling `ensure_host_handler`** (`ios_signals.c:517-524`) on every call; `pthread_sigmask` is hot in libdispatch. Only act on newly set bits (`new & ~old`).
- **PERF-4** signalfd read polls at 5 ms (`os_sys_thread_sig.c:325`); `spawn_child` spins on `sched_yield` (`ios_threads.c:351`). Minor.

### POLISH

- `ios_mc_t` is 372 bytes with `pad[8]`; real `__darwin_mcontext32` (es 12 + ss 68 + fs 260) is 340. `uc_mcsize` (`:311`) should report 340 for byte-exact ABI; the pad is harmless otherwise.
- `IOS_UC_TRADITIONAL 30U` is actually `UC_FLAVOR`; `UC_TRAD` is 1. Rename, and pass `UC_TRAD` when `SA_SIGINFO` is clear for faithful `_sigtramp` dispatch.
- Default-terminate path `ios_signals.c:415,274` exits silently; reuse `write_unhandled_sig_msg` from `signals.c:408`.
- Two main-thread pthread VA conventions: `0xFFFF5400` (`ios_threads.c:318`) vs `A32_IOS_RUNTIME_DATA_VA + A32_IOS_MAIN_PTHREAD_OFF` (`:549`). Unify behind one constant.
- Linux frame: `trap_no` should be 6 for SIGILL (`signals.c:319`); `error_code` 0 ok.
- `mxe_t.waiters` (`ios_threads.c:89,103`) is never incremented; dead field. Dead statement `ios_threads.c:825` after `pthread_exit`.
- signalfd `ssi` only fills `ssi_signo` (`os_sys_thread_sig.c:335`); add `ssi_code/pid/uid` from `g_pending_siginfo`.
- Each thread exit `free(ctx)` (4 sites) with no `a32_jit_fini`; if `a32_jit_init(ch)` (`ios_threads.c:336`) allocates per-thread cache, this leaks per thread. *Unverified.*

Highest-value order: P1-3 and P1-2 (break ordinary pthread code), P1-1 (breaks `sigsuspend`/`raise` paths), P1-4 (Darwin-host perf cliff), then P2-1/P2-5.