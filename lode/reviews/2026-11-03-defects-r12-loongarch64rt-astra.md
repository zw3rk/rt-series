# Round-12 Deep-Dive 6 Audit Report — Syscall ABI, Marshaling, `/proc/self`, Host Backends

Read-only static audit. No files modified, no builds or tests run, no subagents spawned. Note: several names in the audit brief do not exist in-tree (`minsys_ext/sock/ipc/proc.c`, `procfs.c`, `family_*.c`); coverage was mapped to the actual files: `src/os/syscalls.c`, `src/os/syscalls_file.c`, `src/os/syscalls_mem.c`, `src/os/syscalls_priv.h`, `src/os/minsys.c`, `src/os/proc.c`, `src/os/backend_*.c`, `src/os/backend_*_priv.h`, `src/os/darwin_dir.h`, `src/os/family_broker.c`, plus trap entry in `src/interp/interp.c` and `src/dbt/dbt.c`.

## Verdict: 3 defects found

| ID | Location | Effect |
|---|---|---|
| LA64-R12-1 | `src/os/syscalls_priv.h:94-108` | Darwin errnos 62/63/66 reach guest raw |
| LA64-R12-2 | `src/os/minsys.c:573-591` | `waitid` flags misread on Darwin host |
| LA64-R12-3 | `src/os/proc.c:283-333` | Synthetic `/proc` fds drop `O_CLOEXEC` |

### LA64-R12-1 — Darwin errno mistranslation (`ELOOP`, `ENAMETOOLONG`, `ENOTEMPTY`)

`neg_errno()` maps only `ENOSYS` (78→38) and `EAGAIN` (35→11). Verified against the local macOS SDK (`sys/errno.h`): Darwin `ELOOP` is 62 (guest 40), `ENAMETOOLONG` is 63 (guest 36), `ENOTEMPTY` is 66 (guest 39). Guest Linux values are corroborated in-repo (`LA64_ENAMETOOLONG 36` in `src/os/syscalls.h:36`; `LA64_ELOOP_PROC 40` in `src/os/proc.c:29`). Repro on a macOS host: a guest `openat` through a symlink loop returns `-62` instead of `-40`; `unlinkat` of a non-empty directory returns `-66` instead of `-39`; over-long paths return `-63` instead of `-36`. All flow through the single `neg_errno()` site (`sys_openat`, `sys_statx`, `sys_at2`). Fix: extend the `#else` branch with `if (e == 62) return -40; if (e == 63) return -36; if (e == 66) return -39;`.

### LA64-R12-2 — `waitid` options passed raw to Darwin host

`sys_waitid` hands guest `options` straight to host `waitid`, and its comment claims option values match Linux on both hosts. That claim is false for `waitid`, verified against the local SDK (`sys/wait.h`: `WSTOPPED 0x08`, `WCONTINUED 0x10`, `WNOWAIT 0x20`) versus Linux (`WSTOPPED 0x02`, `WCONTINUED 0x08`, `WNOWAIT 0x1000000`). Repro on macOS: guest `waitid(P_PID, pid, &si, WEXITED|WCONTINUED)` sets bit `0x08`, which the host reads as `WSTOPPED`, so a continued child is never reported (`CLD_CONTINUED` lost, possible hang); guest `WNOWAIT` (`0x1000000`) is an unknown host bit. Fix: on non-Linux, translate `0x02→0x08`, `0x08→0x10`, `0x1000000→0x20` before the host call (same pattern `syscalls.c` already uses for `AT_*` flags).

### LA64-R12-3 — `/proc/self/*` synthetic fds ignore `O_CLOEXEC`

`sys_openat` forwards full guest flags to `la64_proc_open`, which checks only `O_DIRECTORY`/`O_NOFOLLOW` and materializes the fd via `mkstemp` plus `open(O_RDONLY)` with no `FD_CLOEXEC` handling. Repro: guest `openat(AT_FDCWD, "/proc/self/maps", O_RDONLY\|O_CLOEXEC)` followed by `fcntl(fd, F_GETFD)` returns `0`; Linux returns `FD_CLOEXEC`, and the leaked fd additionally survives guest `execve` (which sweeps only `FD_CLOEXEC` fds). Fix: after the reopen in `la64_proc_open`, apply `fcntl(fd, F_SETFD, FD_CLOEXEC)` when the guest `O_CLOEXEC` bit (`0x80000`) is set.

## Examined and deliberately cleared (no defect)

Trap ABI is correct: `src/interp/interp.c:700` dispatches `n=$a7`, args `$a0..$a5`, writeback to `$a0` with the `sigreturn` pc-redirect skip; DBT exits `SYSCALL` to `interp_step` (`src/dbt/dbt.c:735,809`), so parity is structural. `statx` 291, `79`/`80`→`-ENOSYS`, 128-byte `stat` via `statx`, zeroed `statfs` stub, `getdents64` (Linux passthrough; Darwin `d_off`/`d_type`/`reclen` reconstruction matches `linux_dirent64`), `ioctl` TCGETS/WINSZ, `fcntl` 0–4+1030, `clock_gettime`, and `O_*`/`MAP_*` validation all match SPEC §§2.2–2.3 and the phase-5 flag doc. Missing guest dispatch for sockets, `epoll`/`ppoll`/`pselect6`, `nanosleep`/`clock_nanosleep`, and general `readlinkat` is the specified `-ENOSYS` fallback (SPEC/GOAL scope the static-libc set to L2a; no contract requires them here). Unintercepted `/proc/self/status` and `/proc/self/fd/*` fall through to the host by documented design (`src/os/proc.h:24-25`; L5a covers exactly five names). `--sysroot` is documented loader-only (help text and `src/loader.h:28-30`). The `SOCK_*` bit-swap comments and `rt_host_pipe2` flag handling in the backend TUs have no callers outside their own definitions, so they are currently unreachable dead code, not behavioral defects; no `x18` use anywhere in the subsystem.
