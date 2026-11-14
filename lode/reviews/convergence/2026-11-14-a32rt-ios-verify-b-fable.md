## Round 19 Track B verification — iOS lanes

Verdict first: **4 RESIDUAL DEFECTS** (one high, one medium, two low). Everything else in scope is sound; details below.

### Residual defects

**1. HIGH — D11: timed `FUTEX_WAIT` on a Darwin host times out immediately.**
`src/os/backend_darwin.c:499-509` treats the `FUTEX_WAIT` timeout as an absolute `CLOCK_MONOTONIC` deadline. Linux semantics make it relative. For a relative timeout such as 100 ms, `d_sec = ts->tv_sec - now.tv_sec` is uptime-negative, so line 509 returns `-ETIMEDOUT` before parking. Every musl `pthread_cond_timedwait`, `sem_timedwait` and `__timedwait` on an ELF32 guest run by `a32rt-darwin` fails instantly. `FUTEX_WAIT_BITSET` (absolute) is correct.
Fix: when `basic == A32_FUTEX_WAIT`, skip the subtraction and compute `deadline = now_realtime + *ts` via `futex_add_ns`.

**2. MEDIUM — D16: `abort()` never runs an installed SIGABRT handler, and would return to its caller if it did.**
`src/ios/ios_stubs.c:853-855` calls `a32_ios_sys_pthread_kill(ctx, 0, 6)`, which for `target_id == 0` only ORs a bit into `pending_signals` (`src/ios/ios_threads.c:597-601`). Nothing in the stub path calls `a32_ios_signals_check_pending`, and `a32_ios_handle_svc` returns straight from the stub branch (`src/ios/ios_svc_bsd.c:719-720`). So `exit_reason` never becomes `A32_EXIT_BRANCH`, the check at line 854 is dead, and the process always `_exit(134)`s with the handler skipped. If delivery were added as-is, `mc.pc` would be the post-`svc` address, so the handler's `sigreturn` would run `bx lr` and `abort()` would return.
Fix: rewind `ctx->regs[15]` to the stub entry `(A32_IOS_STUB_BASE_VA + 6*8) | 1` before delivering, set a `_Thread_local bool aborting`, call `a32_ios_signals_check_pending(ctx)`, return if `exit_reason == A32_EXIT_BRANCH`; on re-entry with `aborting` set, tear down unconditionally.

**3. LOW — D15: the thread's Mach port has two different names.**
Trap 27 / stub 82 allocate names from `0x1000+` (`src/ios/ios_svc_mach.c:210-223`), while `bsdthread_create` returns `0x203 + 4*(tid & 0xFF)` in r1 (`src/ios/ios_threads.c:262`) and `a32_ios_thread_kill_target` only matches that form (`src/ios/ios_threads.c:596-608`). `__pthread_kill(mach_thread_self(), sig)` (BSD 328) therefore returns ESRCH. Real libpthread stores `mach_thread_self()` as the kernel thread port, so `pthread_kill(pthread_self(), …)` under a genuine libSystem would fail.
Fix: pass `want_name = 0x203 + ((host_tid & 0xFF) << 2)` in `mach_ensure_thread_port`, or make `a32_ios_thread_kill_target` also consult `g_ports[].owner_ctx`.

**4. LOW — D11: `FUTEX_REQUEUE` / `FUTEX_CMP_REQUEUE` use the wrong requeue limit.**
`src/os/backend_darwin.c:590` passes `val3` as `max_move`; Linux takes `nr_requeue` from `val2` (the timeout slot, which `os_sys_sig_time.c:834-835` does forward as `a3`). Line 610 requeues unbounded instead of `val2`.
Fix: use `val2` in both calls.

### VERIFIED

- **Leaf stubs, bit-by-bit** (`src/ios/ios_stubs_ext.c:375-515`). All 81 words decode as commented: `MRC p15,0,r0,c13,c0,3` (`0xEE1D0F70`), post-indexed `LDRB`/`STRB` (`0xE4Dx/0xE4Cx`), register-offset `LDRB/STRB [rN, r2]` (`0xE7D1C002/0xE7C0C002`), `SUBS/CMP/SUB/MOV/BX` encodings all correct. Branch offsets use `target - (idx + 2)` with 24-bit masking for both backward (`le_b`) and patched forward (`le_patch`) branches. Only r0–r3 and r12 are written, lr untouched, no stack. `LDRB` zero-extends and the result is `SUB rd, a, b`, so sign matches C `strcmp`/`memcmp`. `n == 0` returns 0 (`SUBS` then `BCC`) for `strncmp`/`memcmp` and is a no-op for `memset`/`memcpy`/`memmove`. `memmove` copies backward when `dst > src` (`CMP r0,r1; BLS fwd`, index-down loop) and forward otherwise. `memcpy`/`memmove`/`memset` return the original r0 via r3. 324 bytes fit the 6 KiB window; 11 symbols fit `LEAF_N`. If emission fails, `ios_setup_tramp` aborts the load before any binding (`src/ios/ios_commpage_stack.c:217`).
- **D1** `pfmt1`: `w` clamped to `sizeof(tmp)-1`, `hfmt` growth bounded, every `out[]` write guarded by `*o + 1 < ocap`; `sn_direct` passes the guest `cap` straight through with the range checked.
- **D8** `fprintf` uses `fetch_rs2` (r2, r3, then stack) with `start = 0`.
- **D9** `vm_map` and `mach_msg_overwrite` read the 8th word from r8, matching `_kernel_trap_6to9`.
- **D15** remainder: 40-byte complex reply with correct descriptor layout, `mach_port_destruct` refcount/queue cleanup, `MACH_SEND_NO_BUFFER` on a full ring.
- **D16** remainder: `strtol`/`strtoul` `endptr` and ERANGE, `sysctl` errno sign, `nanosleep` EINTR + remainder, FILE init, compiler_rt ids 120–129 with `INT64_MIN/-1`, `INT32_MIN/-1` and `/0` handled; `libSystem.tbd` exports all eight division helpers.
- **D6** static `_PTHREAD_MUTEX_SIG_init`/`_PTHREAD_COND_SIG_init` and zero words accepted; self/main join guards; TSD destructor loop bounded at `4*KEY_N` with value cleared before each call; waiter-table wakeups never consumed by colliding keys; lock order `g_thr_mu → g_key_mu` is consistent. The ledger's `0x4D555458`/`0x434F4E44` values match neither code nor fixture; the code uses the genuine Darwin signatures.
- **D7** r0/CPSR.C saved after `bsd_ok`/`bsd_err` for `kill`, `pthread_kill`, `sigsuspend` (stub and BSD paths); `exit_reason` is freshly `A32_EXIT_SVC` in both run loops so the `A32_EXIT_BRANCH` test cannot misfire; VFP d0–d31 + FPSCR saved and restored; `sigsuspend` restores the saved mask through `uc_sigmask`; pending siginfo is `_Thread_local`.
- **atexit / `__cxa_atexit`** LIFO continuation: snapshot under lock, registrations during exit never run, recursive `exit()` tears down.
- **Darwin futex** otherwise: `a32_guest_range_ok` on both addresses, negative Linux errnos, wake counts returned, single `g_futex_mu` never nested with the VM lock.
- **P7** `qsort` invalidates once at the end, only when the range is executable.

### Partially met performance items

- **P3**: `___error` and `_mach_absolute_time` are listed in PERF.md but still trap via `svc #0x81`.
- **P9**: lookup is O(1) via `ios_thr_slot_plus1`, but stubs 104/105 still take `g_thr_mu` around it, so it is not lock-free.

### Not verifiable here

`ios_mc_t` is 372 bytes (`vfp` + 8 pad words). My recollection of XNU's `_STRUCT_MCONTEXT32` is 340 bytes. The fixture header agrees with the code, the siginfo pointer is passed explicitly, and es/ss/fs offsets are unaffected, so this is benign either way. I could not check against an SDK header in this session.

**4 RESIDUAL DEFECTS**
