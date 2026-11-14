# Round 19 Post-Remediation Review — Track A2a-1 (BSD Core & Proc Syscalls, `claude-fable-5-1`)

Review complete. Findings below, assigned items first, then one extra defect observed in a file I was asked to read.

## Assigned items

**A32-IOS-D2 (`madvise`/`msync`) — NOT VERIFIABLE in the 2-file scope.** `src/ios/ios_svc_bsd.c:197-199` and `:808` show that syscalls 73/74/75/78/65 are forwarded to `a32_ios_bsd_vm_simple`, which now lives in `src/ios/ios_svc_bsd_sock.c`. The range checks and the Darwin `MADV_FREE_REUSE (8)` / `MADV_CAN_REUSE (9)` remap cannot be confirmed from `ios_svc_bsd.c`. No defect found in the dispatch itself.

**A32-IOS-D7 (`ios_try_signal`) — VERIFIED (dispatcher side).** `src/ios/ios_svc_bsd.c:695-698` skips the `r0`/carry write for 111/410/37/328 when the signal layer pushed a frame (`exit_reason == A32_EXIT_BRANCH`), `:687-689` keeps restored registers after a successful `sigreturn`, and `:816-818` suppresses the pending-signal check when a frame is already live but still runs it after `sigreturn`. Soundness depends on two cross-file invariants outside this review: the SVC entry path must leave `exit_reason` at a non-`BRANCH` value, and `ios_signals.c` must store `r0 = EINTR`/carry-set (sigsuspend) or `r0 = 0`/carry-clear (kill/pthread_kill) into the mcontext before pushing.

**A32-IOS-D10 `sysctl` — DEFECT (truncation semantics).**
- Where: `src/ios/ios_svc_bsd_proc.c:670-677` (`sysc_emit`) and `:724-729` (name2oid branch).
- Mechanism: on a short buffer the code copies `avail` bytes, writes the *required* length `need` to `*oldlenp`, and returns `ENOMEM`. XNU (`bsd/kern/kern_newsysctl.c`): `sysctl_old_user` copies what fits and returns `ENOMEM` to `userland_sysctl`, which sets `*retval = req.oldlen` (the caller's buffer length, unchanged) when `oldptr != NULL` and overflowed; then `sysctl()`/`sys_sysctlbyname()` does `if (error && error != ENOMEM) return error; if (oldlenp) error = suulong(oldlenp, oldlen); return error;`, so the `ENOMEM` is overwritten and the syscall returns **0** with silently truncated data whenever `oldlenp` is non-NULL. `ENOMEM` only surfaces when `oldlenp == NULL` (where the code at `:660` returns `EFAULT` instead).
- Guest-visible effect: a guest doing `buf[len - 1] = 0` after a short `sysctl` sees `len == need > sizeof(buf)` and writes out of bounds; a guest that treats `-1` as fatal aborts where real iOS succeeds.
- Fix: in both branches, `P_WR(olp, &avail, 4U); a32_ios_bsd_ok(ctx, 0U, 0U, false);` after the partial copy; at `:660` return `D_ENOMEM` for `op != 0 && olp == 0`.

**A32-IOS-D10 `getrlimit`/`setrlimit` — rl_host VERIFIED, DEFECT in flag handling.**
- `rl_host` (`:474-494`) is identity on Darwin and maps 5/6/7/8 to `RLIMIT_AS`/`MEMLOCK`/`NPROC`/`NOFILE` on Linux. Correct. `RLIM_INFINITY` ↔ `0x7FFFFFFFFFFFFFFF` (`:503-504`, `:516-517`) correct.
- Where: `:500` and `:518`, `rl_host((int)args[0])`.
- Mechanism: Darwin Libc `sys/getrlimit.c` and `sys/setrlimit.c` issue `__getrlimit(resource | _RLIMIT_POSIX_FLAG)` / `__setrlimit(resource | _RLIMIT_POSIX_FLAG)` with `_RLIMIT_POSIX_FLAG = 0x1000`; XNU `getrlimit()`/`dosetrlimit()` mask it off. So a real libSystem sends `r0 = 0x1008` for `RLIMIT_NOFILE`. `rl_host` falls into `default: return d;` and the Linux host rejects `4104` with `EINVAL`. Every libc `getrlimit`/`setrlimit` fails on the Linux target. The macOS host survives only because its own libc re-ORs the flag and the kernel masks it.
- Fix: `int which = (int)(args[0] & ~0x1000U);` before `rl_host` in both functions.

**A32-IOS-D10 fork kevent reset — VERIFIED.** `src/ios/ios_svc_bsd_proc.c:153` calls `a32_ios_kq_atfork_reset()` in the child with all signals blocked (`:176-182`), before the mask is restored at `:164`. XNU child dual-return `r0 = 0, r1 = 1` at `:166` is compatible with the `___fork`/`___vfork` stubs, which test `r1` and then overwrite `r0`.

**A32-IOS-D10 `SYS_exit` teardown — VERIFIED (call present).** `:249-253` routes exit(1) to `a32_ios_exit_teardown`. If that function can return, the guest resumes after the `svc` with no result set; it must be `noreturn` (out of scope to confirm).

**A32-IOS-P8 `ios_cstr` — VERIFIED.** `src/ios/ios_svc_bsd.c:158-195` validates one page remainder per `a32_guest_range_ok` call and scans with `memchr`; copy bounds are sound (`n + (hit - blk) + 1 <= cap - 1`). Boundary note, not counted: a string of exactly `cap - 1` characters is rejected with `-63` at `:187-190` although it would fit. With `cap = 4096` this is unobservable since XNU returns `ENAMETOOLONG` above `PATH_MAX = 1024` anyway. `g_cstr` at `ios_svc_bsd_proc.c:104-140` has the same shape.

## Additional defect in a reviewed file (outside the assigned sub-items)

**`openat` dirfd bypass on `..`** — `src/ios/ios_svc_bsd.c:441-448`. A relative path containing `".."` with a real `dirfd` is routed through `a32_resolve_guest_path`, so `openat(dfd, "../x")` resolves against the cwd/sysroot, not against `dfd` as XNU requires. `strstr` also matches names like `a..b`. Fix: use `openat(dirfd, tmp, ...)` for every relative path when `dirfd != -2`; if sysroot-escape protection is intended, resolve the dirfd path first (`/proc/self/fd/N` or `F_GETPATH`) and join.

Minor, uncounted: the `kSysctl` table (`ios_svc_bsd_proc.c:604-608`) mixes `kern.osrelease 19.6.0` / `kern.osversion 17G68` (iOS 13.6) with `kern.osproductversion 10.3.4` and `hw.machine iPhone5,2`, which cannot run iOS 13.

**3 RESIDUAL DEFECTS**
