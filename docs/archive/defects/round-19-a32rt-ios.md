# rt-series Defect Archive — Round 19: `a32rt` 32-Bit iOS (`armv7`/`armv7s`) & Thumb-2/DBT Audit (2026-11-14)

Audited `a32rt` `master` @ `8d87576` across 6 parallel subsystem deep-dives (`lode/reviews/convergence/2026-11-14-a32rt-ios-lane{1..6}-fable.md`), remediated across isolated worker lanes (`8d87576..f5e0d35`, ledger commit `cc3d3aa`), and independently re-verified across 8 post-remediation verification tracks (`lode/reviews/convergence/2026-11-14-a32rt-ios-verify-{a1,a2a1,a2a2,a2b,b,c1,c2a,c2b}-fable.md`) with `make check check-headers test-ios` (`61 / 61` PASS), ELF32 `M1..M7` regressions PASS, and lock-step `--difftest` (`0` divergences).

| Runtime | Audited Revision | Remediated Commit | Items (Round 19) |
|---|---|---|---:|
| `a32rt` | `8d87576` | `cc3d3aa` (`f5e0d35`) | `19 / 19` |

---

## 1. Security, Memory-Safety & Concurrency (`P1`)

- [x] **A32-IOS-D1 — High — SECURITY — Host stack out-of-bounds read in synthetic `printf` / `snprintf`**
  - **Where**: `a32rt` `src/ios/ios_stubs.c:363-385, 645-694` @ `8d87576`.
  - **What breaks / Why**: `pfmt1` bounds its copy loop by `snprintf`'s untruncated return value `w` instead of clamping to `sizeof(tmp) - 1` (`255`), reading past `tmp[256]` on the host stack when a formatted `%s`/specifier exceeds 255 bytes. Likewise `snprintf`/`vsnprintf` (`ids 50–52`) clamp `cp` to guest `r1 - 1` without clamping to `sizeof(buf) - 1` (`2047`), reading past `buf[2048]` when `r1 > 2048` and `n > 2048`.
  - **Fix**: Clamp `pfmt1` copy count to `sizeof(tmp) - 1` (or stream `%s` directly from validated guest memory without fixed-stack truncation) and clamp `snprintf`/`vsnprintf` copy count to `sizeof(buf) - 1`.

- [x] **A32-IOS-D2 — High — SECURITY — Unchecked guest range in `madvise` (75) and `msync` (65) + Linux `MADV_FREE_REUSE` corruption**
  - **Where**: `a32rt` `src/ios/ios_svc_bsd.c:635-647, 685-694` @ `8d87576`.
  - **What breaks / Why**: Neither `madvise` nor `msync` checks `a32_guest_range_ok` / `[a[0], a[0] + a[1]) <= 0x100000000ULL`, allowing a guest `madvise(0xFFFFF000, 0x10000000, MADV_DONTNEED)` to discard host translator mappings above `[G, G + 4 GiB)`. On Linux hosts, Darwin `MADV_FREE_REUSE (8)` passes straight through as Linux `MADV_FREE (8)` (discarding live `malloc` pages) and `MADV_CAN_REUSE (9)` maps to `MADV_REMOVE (9)`. On 16 KiB-page macOS hosts, 4 KiB-aligned guest hints can fail host `madvise` with `EINVAL`.
  - **Fix**: Validate `[a[0], a[0] + a[1])` inside the guest window (`[a32_min_va(ctx), 0x100000000ULL)` and mapped regions), map only portable `MADV_NORMAL..MADV_DONTNEED` (`0..4`) to Linux host `madvise` (treating Darwin `5..9` hints as safe no-ops on Linux), and align/skip unaligned sub-host-page `madvise` hints on 16 KiB hosts.

- [x] **A32-IOS-D3 — High — SECURITY — Missing `st_uid == geteuid()` ownership check on `/tmp` AOT cache load**
  - **Where**: `a32rt` `src/dbt/dbt_aot_cache.c:151, 520-532` @ `8d87576`.
  - **What breaks / Why**: When `A32RT_CACHE` and `XDG_CACHE_HOME` are unset, AOT cache paths default to shared `/tmp/a32rt-cache-<hash>.bin`. `load_cache_from_path` checks `O_NOFOLLOW`, `S_ISREG`, and `(st_mode & 0022) == 0`, but omits `st.st_uid == geteuid()`, allowing another local user to pre-seed host AArch64 machine code.
  - **Fix**: Require `st.st_uid == geteuid()` in `load_cache_from_path` before accepting any AOT cache file.

- [x] **A32-IOS-D4 — High — CONCURRENCY — Data race on non-TLS `g_site_stage` + stale SMC block commit during unlocked JIT compilation**
  - **Where**: `a32rt` `src/core/core_emit_mem.c:27-74`, `src/dbt/dbt_jit_query.c:131, 183-194` @ `8d87576`.
  - **What breaks / Why**: `dbt_jit_query.c` translates blocks with `jit_lock` released while `g_site_stage[]` and its index/flags in `core_emit_mem.c` are process-global static variables rather than `_Thread_local`, racing across threads and corrupting load/store fault-recovery metadata. Furthermore, at `dbt_jit_query.c:184`, if `cur_epoch != use_epoch` (an SMC/`mprotect` invalidation raced mid-compile) and the page remains executable, the JIT installs pre-invalidation code into the new epoch.
  - **Fix**: Mark `g_site_stage`, `g_site_stage_base`, `g_site_stage_count`, and `g_site_stage_valid` `_Thread_local`, and if `cur_epoch != use_epoch` when re-acquiring `jit_lock`, discard the stale translation and re-translate under the current epoch.

---

## 2. XNU 32-Bit iOS Functional & ABI Bugs (`P1`)

- [x] **A32-IOS-D5 — High — LOADER — Weak imports (`BIND_SYMBOL_FLAGS_WEAK_IMPORT`) abort Mach-O load instead of binding `0`**
  - **Where**: `a32rt` `src/ios/ios_bind.c:45-46, 333-339, 384-405` @ `8d87576`.
  - **What breaks / Why**: `IOS_BIND_SET_SYM_TRAILING` (`0x40`) ignores `imm & 0x1` (`BIND_SYMBOL_FLAGS_WEAK_IMPORT`), causing standard iOS SDK availability checks (`if (&newer_api != NULL)`) to fail fatally at load time; `INDIRECT_SYMBOL_LOCAL`/`ABS` are also defined as `0xFFFFFFFF`/`0xFFFFFFFE` instead of Mach-O's `0x80000000`/`0x40000000`.
  - **Fix**: Track `sym_weak = (imm & 0x1U) != 0U` across bind streams (and `N_WEAK_REF` `0x0040` on classic indirect symbols), writing `0` on unresolved weak symbols, and fix `INDIRECT_SYMBOL_LOCAL`/`ABS` bitmasks.

- [x] **A32-IOS-D6 — High — THREADS — Static `PTHREAD_MUTEX_INITIALIZER` / `PTHREAD_COND_INITIALIZER` fail with `EINVAL` + `psynch`/`ulock` bucket-aliasing lost wakeups**
  - **Where**: `a32rt` `src/ios/ios_threads.c:76, 438-518, 612, 648-700` @ `8d87576`.
  - **What breaks / Why**: Synthetic `pthread_mutex_lock/trylock/unlock` and `pthread_cond_wait/signal/broadcast` pass `create = false` to `mx_lookup`/`cv_lookup`, returning `EINVAL` on statically initialized (`0x4D555458` / `0x434F4E44`) mutexes and condvars. `psynch` (`301–308`) and `ulock` (`515–516`) hash guest VAs into 64 shared condvars and use `pthread_cond_signal` (losing wakeups on bucket collisions; `515` also re-sleeps when woken if `*uaddr == val`). `pthread_join` lacks self/main-thread guards and thread exit skips TSD key destructors.
  - **Fix**: Lazy-initialize static mutexes/condvars on first use, use per-bucket generation counters + `pthread_cond_broadcast` in `psynch`/`ulock`, guard `pthread_join` against self (`EDEADLK`) and main (`EINVAL`), and invoke TSD key destructors on thread exit.

- [x] **A32-IOS-D7 — High — SIGNALS — Self-delivered signals (`sigsuspend`, `kill(self)`, `pthread_kill(self)`) clobber `_sigtramp` `r0` + non-TLS `g_ios_pending_info`**
  - **Where**: `a32rt` `src/ios/ios_signals.c:146, 641-654, 692-696` and `src/ios/ios_svc_bsd.c:853-855` @ `8d87576`.
  - **What breaks / Why**: Synchronous pending signal delivery builds the signal frame before the syscall's return state (`r0` / `CPSR.C`) is finalized, or the caller overwrites `ctx->regs[0]` after `ios_deliver_signal` placed the guest handler address in `r0` for `_sigtramp`. Also `g_ios_pending_info[32]` is process-global instead of `_Thread_local`.
  - **Fix**: Finalize syscall `r0`/`CPSR.C` (`EINTR` + `C=1` for `sigsuspend`, `0` + `C=0` for `kill`/`pthread_kill`) before invoking `a32_ios_signals_check_pending(ctx)`, never overwrite `ctx->regs` after `sync_sig_delivered`, and make `g_ios_pending_info` `_Thread_local`.

- [x] **A32-IOS-D8 — High — STUBS — Synthetic `fprintf` (`id 49`) drops its first format argument (`r2`)**
  - **Where**: `a32rt` `src/ios/ios_stubs.c:617-625` @ `8d87576`.
  - **What breaks / Why**: Shifts `r1 = r2; r2 = r3;` and calls `pfmt(..., start = 1U)`, where `fetch_rs(..., 1)` starts at `r2` (original `r3`), dropping original `r2`.
  - **Fix**: Pass format VA explicitly without shifting `regs[1..2]` (or pass the correct `start` index so `r2`, `r3`, `[sp+0]...` are read in order).

- [x] **A32-IOS-D9 — High — MACH — 8th Mach trap argument (`vm_map`, `mach_msg_overwrite_trap`) read from `[sp+16]` instead of `r8`**
  - **Where**: `a32rt` `src/ios/ios_svc_mach.c:440, 722` @ `8d87576`.
  - **What breaks / Why**: Per XNU `osfmk/mach/arm/syscall_sw.h` (`_kernel_trap_6to9`), 32-bit ARM Mach traps pass args `0..3` in `r0..r3` and args `4..7` in `r4, r5, r6, r8` (skipping frame pointer `r7`). Reading `[sp+16]` reads saved caller registers instead of `cur_protection` / `rcv_msg`.
  - **Fix**: Read arg 7 from `ctx->regs[8]` (`r8`) in `mach_trap_vm_map` and `mach_msg_trap` (`overw`).

- [x] **A32-IOS-D10 — High — BSD-ABI — Concrete XNU BSD struct/constant/kevent bugs (`getdirentries64`, `statfs64`, `rl_host`, `cmsghdr`, `kevent`, `MSG_DONTWAIT`, `AT_SYMLINK_FOLLOW`, `openat`)**
  - **Where**: `a32rt` `src/ios/ios_svc_bsd_fs.c:44, 226-242, 404-429`, `src/ios/ios_svc_bsd_proc.c:161, 460-472, 649`, `src/ios/ios_svc_bsd_sock.c:125-141, 325-370, 756-761, 848-868`, `src/ios/ios_svc_bsd.c:409, 527` @ `8d87576`.
  - **What breaks / Why**:
    1. `getdirentries64` writes `d_name` at offset `24` instead of Darwin's `21` and seeks to output-only `*basep`.
    2. `statfs64` places 16-bit `f_otype` at offset 0 instead of 32-bit `f_bsize`; `AT_SYMLINK_FOLLOW` is `0x20` instead of Darwin `0x40`; `openat` ignores `dirfd`; `F_GETPATH` demands 4096 writable bytes instead of `MAXPATHLEN` (`1024`).
    3. `rl_host` permutes `RLIMIT_MEMLOCK/NPROC/NOFILE` (`6/7/8 -> 8/6/7`) even on `__APPLE__` where host constants already match Darwin; `sysctl` truncation returns `0` instead of `ENOMEM`; `fork` does not coordinate `g_kq_mu`.
    4. `sk_ctl_g2h`/`sk_ctl_h2g` hand-rolls 16-byte Linux `cmsghdr` on macOS (where `cmsghdr` is 12 bytes, breaking `SCM_RIGHTS`) and socket flags drop `MSG_DONTWAIT` (`0x80`).
    5. `kevent` polls all fd knotes with `POLLIN | POLLOUT` (spinning 100% CPU on writable sockets watching `EVFILT_READ`), ignores `EVFILT_TIMER` deadlines in `wait_ms`, and aliases `kevent_qos` (`374`) to `kevent64` (`369`).
  - **Fix**: Remediate all five BSD syscall marshaling items and split `kqueue`/`kevent` cleanly into `src/ios/ios_svc_bsd_kevent.c`.

- [x] **A32-IOS-D11 — High — OS — Darwin-host Linux `futex` (`FUTEX_WAIT`) lacks range check & ignores `FUTEX_WAKE`**
  - **Where**: `a32rt` `src/os/os_sys_thread_sig.c:233-274`, `src/os/backend_darwin.c` @ `8d87576`.
  - **What breaks / Why**: `futex_darwin_wait` dereferences `a0` without `a32_guest_range_ok` and `nanosleep`s the entire timeout returning `-ETIMEDOUT`, ignoring `FUTEX_WAKE` / `clear_child_tid` wakes.
  - **Fix**: Validate `a32_guest_range_ok` and implement a condvar-backed wait/wake table in `backend_darwin.c` supporting `FUTEX_WAIT`/`WAKE`/`BITSET`/`CMP_REQUEUE`.

---

## 3. Loader, Mach, Stubs, Interpreter & DBT Completeness (`P2`)

- [x] **A32-IOS-D12 — Medium — LOADER — `__mod_init_func` ordering, `ios_apply_prot` unaligned page rounding, dylib dedup & cross-image overlap**
  - **Where**: `a32rt` `src/ios/ios_dylib.c:116-120, 271-276, 369-370`, `src/ios/ios_macho.c:617` @ `8d87576`.
  - **What breaks / Why**: Initializers run in reverse-BFS order rather than dependency DFS post-order; `ios_apply_prot` computes `page_up(vmaddr + vmsize)` (over-protecting by 1 page when `vmaddr` is unaligned since `vmsize` is already page-rounded from `start`); dylib deduplication checks only path string rather than `(st_dev, st_ino)` / `install_name`; fixed-VA segments skip overlap validation before `MAP_FIXED`.
  - **Fix**: Traverse `dep_image_idx` in DFS post-order for initializers, use `end = start + seg->vmsize` in `ios_apply_prot`, deduplicate by `(st_dev, st_ino)` and `install_name`, and reject overlapping fixed segments.

- [x] **A32-IOS-D13 — Medium — EXPORT — Export-trie >255B edge truncation & two-level ordinal synthetic fallback**
  - **Where**: `a32rt` `src/ios/ios_export.c:125-130, 218-222, 343` @ `8d87576`.
  - **What breaks / Why**: `trie_walk` truncates prefixes >255 bytes (mis-matching long C++ mangled names), and `a32_ios_resolve_in` falls back to synthetic `libSystem` for any image ordinal even when the target image is a real non-`libSystem` dylib.
  - **Fix**: Raise trie prefix buffer to 2048 bytes (rejecting overflow instead of truncating) and restrict synthetic fallback inside `a32_ios_resolve_in` to `img->is_synthetic`.

- [x] **A32-IOS-D14 — Medium — CRT0/AOT — CRT0 skips `atexit`/`__cxa_atexit` & iOS exits skip `--stats`/`--auto-aot`**
  - **Where**: `a32rt` `src/ios/ios_commpage_stack.c:174-177`, `src/ios/ios_stubs.c:859-860`, `src/ios/ios_svc_bsd_proc.c:130`, `src/main.c:428-456` @ `8d87576`.
  - **What breaks / Why**: CRT0 invokes raw `SYS_exit` directly, skipping registered `__cxa_atexit`/`atexit` destructors, and iOS process exit calls `_exit` without printing `--stats` or saving `--auto-aot` caches.
  - **Fix**: Route CRT0 return through synthetic `exit()` (draining LIFO `__cxa_atexit`/`atexit` handlers) and run `--stats` + `--auto-aot` persistence on iOS process exit.

- [x] **A32-IOS-D15 — Medium — MACH — `task_get_special_port` MIG reply layout, `mach_port_destruct` leak, full-queue drop & `_mach_thread_self` port**
  - **Where**: `a32rt` `src/ios/ios_svc_mach.c:250-256, 692-706, 821`, `src/ios/ios_stubs.c:834` @ `8d87576`.
  - **What breaks / Why**: `task_get_special_port` reply lacks `MACH_MSGH_BITS_COMPLEX` + `mach_msg_port_descriptor_t` (`40B`); `mach_port_destruct` (trap 25) is a no-op; full Mach port queues drop the oldest message instead of returning `MACH_SEND_NO_BUFFER`; synthetic `_mach_thread_self` fabricates an untracked port integer instead of allocating the thread's Mach port.
  - **Fix**: Emit standard 40-byte complex MIG port descriptor reply, release ports in `mach_port_destruct`, return `MACH_SEND_NO_BUFFER` on full queues, and route `_mach_thread_self` through `a32_ios_mach_thread_self(ctx)`.

- [x] **A32-IOS-D16 — Medium — STUBS — `strtol` `endptr`, `sysctl` errno sign, `nanosleep` `EINTR`, `abort` `SIGABRT`, `FILE*` flags & `compiler_rt` 64-bit div/mod**
  - **Where**: `a32rt` `src/ios/ios_stubs.c:297, 418, 788, 806, 857`, `tests/ios/libSystem.tbd` @ `8d87576`.
  - **What breaks / Why**: `strtol`/`strtoul` ignores `endptr` (`r1`); `sysctl` stub negates already-positive Darwin `errno`; `nanosleep` returns `0` on `EINTR`; `abort` calls `_exit(134)` without raising `SIGABRT`; synthetic `FILE*` (`0xFFFF5600+`) needs clean initialized `sbuf`/`_flags`/`_file` fields for inline `<stdio.h>` macros; `libSystem` lacks `___divdi3`/`___udivdi3`/`___moddi3`/`___umoddi3` emitted by Clang on 64-bit ARM32 division.
  - **Fix**: Fix all five `libSystem` stub edge cases and export `___divdi3`, `___udivdi3`, `___moddi3`, `___umoddi3` (plus 32-bit `___divsi3`/`___udivsi3`/`___modsi3`/`___umodsi3`) in synthetic `libSystem` and `tests/ios/libSystem.tbd`.

- [x] **A32-IOS-D17 — High — INTERP — Missing NEON integer multiply / `.F32` / `VLD2..4` / `VREV` in reference interpreter + `VLDn` pre-flight check**
  - **Where**: `a32rt` `src/interp/interp_vfp_neon.c:21-52, 60-185` @ `8d87576`.
  - **What breaks / Why**: Running `bench_ios_v7s --smoke` under `--interp` aborts with `SIGILL` at `0x0000a882` (`vmul.i32`) because `interp_vfp_neon.c` only implements `VLD1/VST1`, `VMOV` imm, `VREV64`, and basic `VADD/VSUB/bitwise`; `VLDn` also mutates `vfp_d[]` before checking the full transfer span.
  - **Fix**: Add full ARMv7/VFPv4 NEON integer multiply/MAC/long/wide/shift, `.F32`/`.F16`/fixed-point vector & scalar ops (with cumulative `FPSCR` flags under Standard FPSCR `FZ=1, DN=1, RN`), `VLD2..4`/`VST2..4`, `VREV16/32`, `VDUP`/`VEXT`/`VTBL`/`VTRN`/`VUZP`/`VZIP`, and pre-flight memory range checks across `interp_vfp_neon*.c`.

- [x] **A32-IOS-D18 — Medium — INTERP/DBT — Darwin `__builtin_trap()` (`0xDEFE` / `0xE7FFDEFE`) raises `SIGILL` instead of `SIGTRAP`**
  - **Where**: `a32rt` `src/interp/interp_thumb.c:82`, `src/interp/interp_a32.c`, `src/interp/interp_t16.c`, `src/interp/interp_a32_ctl.c` @ `8d87576`.
  - **What breaks / Why**: Clang targeting 32-bit iOS emits Thumb `0xDEFE` (`UDF #254`) and ARM `0xE7FFDEFE` for `__builtin_trap()`, which XNU `osfmk/arm/trap.c` translates to `EXC_BREAKPOINT` (`SIGTRAP`), whereas `a32rt` currently raises `SIGILL`.
  - **Fix**: When `ctx->is_ios`, decode `0xDEFE` (Thumb) and `0xE7FFDEFE` (ARM) as `A32_EXIT_BKPT` (`SIGTRAP`) in both interpreter and DBT.

- [x] **A32-IOS-D19 — Medium — DBT — iOS protection-fault `SIGBUS`, UNDEF-fallback `A32_EXIT_BKPT` `SIGTRAP` & `a32_dbt_single_step` APRR**
  - **Where**: `a32rt` `src/dbt/dbt_jit_run.c:147, 502-532, 592` @ `8d87576`.
  - **What breaks / Why**: On iOS, faults on mapped regions with insufficient permissions deliver `SIGBUS` (`KERN_PROTECTION_FAILURE`) rather than `SIGSEGV`; `case A32_EXIT_UNDEF:` falls through to `SIGILL` when `a32_interp_step` returns `A32_EXIT_BKPT`; `a32_dbt_single_step` calls `a32_jit_run_block` on macOS without `pthread_jit_write_protect_np(1)`.
  - **Fix**: Distinguish `SIGBUS` vs `SIGSEGV` via `ctx->regions` when `ctx->is_ios`, handle `step_rc == A32_EXIT_BKPT` as `SIGTRAP`/GDB stop, reset host `fpcr` on guest fault recovery, and guard `a32_dbt_single_step` with `pthread_jit_write_protect_np(1)`.
