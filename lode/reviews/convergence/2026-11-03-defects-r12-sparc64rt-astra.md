# sparc64rt Round-12 Deep-Dive 6 audit

Scope: `src/os/syscalls_min.c`, `src/os/syscalls_ext.c`, `src/os/syscalls_stat.c`, `src/os/syscalls_dirent.c`, `src/os/proc.c`, `src/os/guest_proc.c`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/os/backend_darwin_sync.c`, `src/os/backend_darwin_futex.c`, `src/os/host_contract_family.c`, `src/os/guest_interp_map.c`, `src/os/host_contract_interp.c`.
Note: `syscalls_fs.c`, `syscalls_sock.c`, `procfs.c`, `family_*.c` as named do not exist; audited their actual counterparts above. Socket/epoll/poll/ppoll/pselect6/nanosleep/statfs have no guest dispatch and correctly return `ENOSYS` → guest `90`; not reported.

## Summary

| ID | Location | Effect |
|---|---|---|
| S64-R12-1 | `syscalls_min.c:149-152` | Wrong SPARC errnos |
| S64-R12-2 | `syscalls_ext.c:602-618` | NULL time writes VA 0 |
| S64-R12-3 | `syscalls_stat.c:226-228` | Drops EMPTY/AUTOMOUNT |
| S64-R12-4 | `backend_darwin.c:554-558` | Drops NOFOLLOW |
| S64-R12-5 | `syscalls_stat.c:147-195` | stat skips sysroot |
| S64-R12-6 | `syscalls_ext.c:203-214` | /proc leaks to host |
| S64-R12-7 | `proc.c:849-854` | dup3 self-dup diverges |

### S64-R12-1 — SPARC errno mistranslation

[syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:149) returns `36` for `ENAMETOOLONG` (SPARC `63`), [syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:151) returns `40` for `ELOOP` (SPARC `62`), [syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:152) returns `75` for `EOVERFLOW` (SPARC `92`). Each passes the host generic value through unchanged. Repro: overlong `openat`/`stat` reports `36` (`EINPROGRESS` on SPARC); symlink loop reports `40` (`EMSGSIZE`); oversized `stat` reports `75` (`ENOMSG`). Fix: return `63U`, `62U`, `92U` respectively.

### S64-R12-2 — `clock_gettime` NULL writes guest VA 0

[syscalls_ext.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:602) treats `tp_va==0` with `is_res==0` as in-range (`l2a_range_ok(0,16)==0`), runs the host call, then `store_timespec(mem,0)`. Repro: `clock_gettime(REALTIME,0)` corrupts VA `0` instead of `-EFAULT`. Fix: `if (!is_res && tp_va==0) return -EFAULT;` before the host call.

### S64-R12-3 — `fstatat64` drops validated flags

[syscalls_stat.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:226) validates `EMPTY_PATH`/`NO_AUTOMOUNT` then calls `sys_stat_path` with only the `NOFOLLOW` bit. Repro: `fstatat64(fd,"",buf,EMPTY_PATH)` gets `ENOENT` instead of the `fd` stat. Fix: forward full `host_flags` to `fstatat`.

### S64-R12-4 — Darwin `faccessat2` drops `NOFOLLOW`

[backend_darwin.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_darwin.c:554) validates `AT_SYMLINK_NOFOLLOW` then calls `faccessat(...,0)`. Repro: dangling-symlink check with `NOFOLLOW` wrongly returns `ENOENT`. Fix: pass the mapped `at` flag through.

### S64-R12-5 — stat family skips sysroot

[syscalls_stat.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:147) does raw `fstatat(AT_FDCWD,...)` with no `sparc64_sysroot_try_open`/`sparc64_interp_resolve`, unlike `openat` and `faccessat`. Repro: with `SPARC64RT_SYSROOT=/r`, `stat("/etc/passwd")` stats host `/etc/passwd`. Fix: resolve absolute paths via sysroot first, fall back on `ENOENT`/`ENOTDIR`.

### S64-R12-6 — non-synthetic `/proc/self/*` falls to host

[syscalls_ext.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:203) only intercepts five synthetic names; `/proc/self/status`, `/proc/self/fd/*` fall to host `openat`/`readlinkat`, and stat has no synthetic check at all. Repro: guest `open("/proc/self/status")` reads the translator's status. Fix: reject any `/proc/self/*` outside the synthetic set with `-ENOENT` before host fallback; stat `exe` against `load_path`.

### S64-R12-7 — Darwin `dup3` self-dup diverges

[proc.c](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/proc.c:849) returns success for `oldfd==newfd` on Darwin while Linux `dup3` returns `EINVAL`. Repro: `dup3(5,5,0)` succeeds on Darwin, fails on Linux. Fix: `if (oldfd==newfd) return -EINVAL;` on both paths.

