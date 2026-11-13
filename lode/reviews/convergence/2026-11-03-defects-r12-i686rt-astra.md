# i686rt Round-12 Deep-Dive 6 Audit Report — Syscall ABI, Marshaling, `/proc`, Host Backends

Scope covered: `src/os/syscalls.c`, `src/os/sys_pass.c`, `src/os/sys_pass_fs.c`, `src/os/sys_sock.c` (+ `sys_sock_msg.c`; note: no file named `sys_pass_sock.c` exists), `src/os/sys_pass_io.c`, `src/os/proc.c`, `src/os/backend_*.c` (note: no `src/host.c` exists; host logic lives in `src/rt32/rt32_host.c`, `src/main.c`, `src/os/backend_linux.c`). Read-only; no builds, no tests, no subagents.

## Summary

| ID | Severity | Location | Finding |
|----|----------|----------|---------|
| I686-R12-1 | High | `src/os/sys_pass_internal.h:139,144,145`, `src/os/sys_pass_fs.c:10-47` | `O_DIRECT`/`O_DIRECTORY`/`O_NOFOLLOW` mistranslated to Linux host: `open(O_DIRECT)` fails `ENOTDIR`, `open(O_NOFOLLOW)` follows symlinks |
| I686-R12-2 | Medium | `src/os/sys_misc_conv.c:138-139,144-169` | Same wrong model inverted in `fcntl`: `F_SETFL(O_DIRECT)` sets host `O_DIRECTORY`; `F_GETFL` reports `O_DIRECT` for directories |
| I686-R12-3 | High | `src/os/syscalls.c:548-566,691` | `execve("/proc/self/exe")` not resolved to `ctx->exec_path` → `-ENOEXEC`, contradicting the documented busybox applet path |
| I686-R12-4 | Medium | `src/os/backend_darwin_net.c:102-109,136-158` | Darwin `socketpair`/`accept4` silently drop `SOCK_CLOEXEC`/`SOCK_NONBLOCK` |
| I686-R12-5 | Low | `src/os/proc.c:231-248,251-296` | Non-canonical `/proc` spellings (`//`, `/./`) bypass synthesis and leak host `/proc/self/maps` or spuriously fail |

## Defects

### I686-R12-1 — `O_DIRECT`/`O_DIRECTORY`/`O_NOFOLLOW` swapped on the Linux `open` path

Guest i386 and host aarch64 Linux use **identical** bits here: `O_DIRECT=040000 oct (0x4000)`, `O_DIRECTORY=0200000 oct (0x10000)`, `O_NOFOLLOW=0400000 oct (0x20000)` — confirmed against upstream `include/uapi/asm-generic/fcntl.h` (`O_DIRECT 00040000`, `O_DIRECTORY 00200000`, `O_NOFOLLOW 00400000`; arm64 includes it verbatim) and against the repo's own guest octal literals in `sys_pass_internal.h:122-124` plus the "bit-identical" note in `sys_misc_internal.h:57-58`. The swap model copied from a32rt's ARM32 guest is wrong for i386: ARM32 differs from both, i386 does not.

Yet `sys_pass_internal.h` hardcodes `HOST_O_DIRECT 0x10000`, `HOST_O_DIRECTORY 0x4000`, `HOST_O_NOFOLLOW 0x8000`, applied by the map in `sys_pass_fs.c:12-42`. Reproduction conditions (all static, Linux host):

- Guest `open(f, O_RDONLY|O_DIRECT)` (`0x4000`) → host `open(..., 0x10000 = O_DIRECTORY)` on a regular file → **`-ENOTDIR`** instead of a direct-I/O fd.
- Guest `open(f, O_RDONLY|O_DIRECTORY)` (`0x10000`) → host `open(..., 0x4000 = O_DIRECT)` → `ENOTDIR` check lost (succeeds on non-directories).
- Guest `open(l, O_RDONLY|O_NOFOLLOW)` (`0x20000`) → host `0x8000` (`O_LARGEFILE`, inert on 64-bit) → **symlink followed despite `O_NOFOLLOW`** (security-relevant).

Minimal fix: set `HOST_O_DIRECT 0x4000`, `HOST_O_DIRECTORY 0x10000`, `HOST_O_NOFOLLOW 0x20000` (identity — or drop the three rows and let the access-mode-style passthrough cover them). Caution: `tests/unit/test_l2f.c:114-117,134-136,156` and `docs/lanes/fix-c12-dseries.md:29` (D47) pin the swapped values and must be updated with the fix.

### I686-R12-2 — `fcntl` `F_SETFL`/`F_GETFL` carry the same inverted swap

`sys_misc_conv.c:138-139` defines `I686_HO_DIRECT_ 0x10000` / `I686_HO_NOFOLLOW_ 0x8000`; `i686_setfl_to_host` (`:161-169`) remaps guest `O_DIRECT (0x4000)` → `0x10000`, so guest `fcntl(fd, F_SETFL, O_DIRECT|O_NONBLOCK)` asks the host to set `O_DIRECTORY` (outside the `SETFL` mask) instead of `O_DIRECT` — the file never enters direct-I/O mode. Conversely `i686_oflags_h2g` (`:144-157`) rewrites host `O_DIRECTORY (0x10000)` → guest `O_DIRECT`, i.e. `F_GETFL` on any directory fd reports `O_DIRECT` (the already-tracked D47 symptom — D47 is a symptom of this root cause, shared with R12-1). Fix with R12-1: delete both swap blocks (identity mapping); `i686_setfl_to_host` then only strips `O_LARGEFILE`.

### I686-R12-3 — `execve("/proc/self/exe")` bypasses `exec_path` virtualization

`r_execve` (`syscalls.c:691`) resolves exclusively via `i686_exec_open` (`syscalls.c:548-566`), which tries sysroot-prefixed then plain `open` — it has no `/proc/self/exe` handling. So guest `execve("/proc/self/exe", argv, envp)` opens the **host translator binary** (aarch64 ELF / Mach-O, never `EM_386`), `rt32_elf_load` rejects it, and the call fails `-ENOEXEC`. This directly contradicts the contract comment at `syscalls.c:412-417` ("what busybox's applet dispatch `execve("/proc/self/exe", …)` rides on, with `/proc/self/exe` virtualized to `ctx->exec_path`"), and is inconsistent with the same path working for `open` (`proc.c:283-294`) and `readlink` (`sys_pass_fs.c:283-301`). Fix: in `i686_exec_open`, before the sysroot logic, map `"/proc/self/exe"` (and own-pid `"/proc/<pid>/exe"`, mirroring `is_own_proc_exe`) to `ctx->exec_path`.

### I686-R12-4 — Darwin backend drops `SOCK_CLOEXEC`/`SOCK_NONBLOCK` in `socketpair`/`accept4`

`rt_host_socket` (`backend_darwin_net.c:87-100`) masks `type & 0xff` then applies both flags via `fcntl`, but `rt_host_socketpair` (`:102-109`) stops at the mask, and `rt_host_accept4` (`:136-158`) takes `linux_flags` then `(void)`-discards it. Repro (macOS host): guest `socketpair(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0, sv)` or `accept4(…, SOCK_CLOEXEC)` → fds lack `FD_CLOEXEC`, so `exec_close_cloexec_fds` (`syscalls.c:511-540`) does not close them and they leak into the new image; dropped `SOCK_NONBLOCK` likewise changes readiness semantics. Linux is unaffected (flags pass natively to `SYS_socketpair`/`SYS_accept4`). Fix: apply the same two `fcntl` calls as `rt_host_socket`.

### I686-R12-5 — `/proc/self/*` synthesis bypassed by non-canonical spellings

`skip_proc_prefix` (`proc.c:231-248`) collapses only `/` runs, and `i686_proc_open_at` (`:251-296`) uses exact `strcmp`. Repro: guest `open("/proc/self//maps")` → leaf `"self//maps"` → no match → falls through to host open (which collapses slashes) → guest reads the **host** process maps (host addresses/paths — wrong content and an ASLR disclosure). `open("/proc/self/maps/")` → host `ENOTDIR` for a valid virtual file; `"/proc/./self/maps"` leaks host content the same way. Fix: canonicalize duplicate `/` (done) plus `/.​/` segments before matching, and reject or normalize `/../` so `"self/../self/maps"` cannot escape the virtual set.

## Verified clean (no defect)

- Dispatch (`marshal.c:257-263`, `syscalls.c:808-837`): `EBX..EBP` order, `EAX=(u32)ret` truncation, `-errno`/`-ENOSYS(38)` convention, `sigreturn` EAX-restore guard.
- `set_thread_area(243)`/`get_thread_area(244)`/`modify_ldt(123)`: `ldt.c` full implementation supersedes the `syscalls.c:215-225` delegating stub order-independently; funcs `0/1/0x11/2`, `-1` allocation, `-ESRCH`, 16 B `user_desc`, entry-range checks all kernel-faithful.
- 64-bit pairs: `_llseek` `ECX=hi/EDX=lo` (`sys_pass_fs.c:519-541`); `pread64`/`pwrite64` `ESI=lo/EDI=hi` and `ftruncate64` `ECX=lo/EDX=hi` (`sys_pass_io.c:446-553`) — consistent low-first sequential layout.
- `stat64` (96 B), `statfs` (64 B), `statfs64` (84 B + `sz==84` gate), `statx` (256 B + static asserts) layouts match kernel uapi; `statx` AT_/mask passthrough is correct.
- `clock_gettime`/`clock_gettime64` (+`getres`/`settime`/`nanosleep`/`adjtime64`), saturation-vs-truncation policy per comments; `ioctl` sizes (`K_TERMIOS_SZ 36`, `K_TERMIO_SZ 17`) and int-arg passthrough; `socketcall` nargs table and subcall mapping; `fcntl`/`fcntl64` compat split; `O_*` values themselves match the brief.
- `/dev/a32host` + `I686RT_HOST=none` (`rt32_host.c:30-33`, `main.c:151-153`, `backend_linux.c:65-69`); `I686RT_SYSROOT`/`--sysroot` resolution in `open`/`openat`/`readlink`/`access`/`stat`/`statx`/`exec`.
- `socketcall` out-of-range → `-ENOSYS` is a documented intentional deviation, not a bug.

## Coverage notes (not defects)

No guest dispatch exists for `truncate(92)`, `ftruncate(93)`, `truncate64(193)`, `fallocate(324)`, `pselect6(308)`, `ppoll(309)` (+ time64 `413/414`); they correctly return `-ENOSYS`. `rt_host_ppoll`/`rt_host_fallocate` backends are implemented but unwired. `/proc/self/stat`, `/status`, `/fd/*` fall through to the host — unvirtualized passthrough, not wrong-code.
