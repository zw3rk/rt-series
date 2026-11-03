# Round-12 Deep-Dive 6 Audit — Syscall / Proc / Host Backends

Scope: `src/os/syscall_min.c`, `src/os/syscalls.c`, `src/os/syscalls_meta.c`, `src/os/syscalls_priv.h`, `src/os/syscall_nr.h`, `src/os/proc.c`, `src/os/backend_*.c`, `src/os/backend_posix.c`, `src/rt32/host.c`. Read-only, no builds/tests.

Verified clean: O32 dispatch (`$v0`, `$a0..$a3`, `sp+16..28`, `$a3` convention), `pipe` (`$v0`/`$v1`), `_llseek`/`truncate64` even-pair handling, `stat64` 104 B layout, `statx` 256 B layout, `clock_gettime`/`64`, `ioctl` FIONREAD/TIOCGWINSZ, `O_*` values, `MAP_ANONYMOUS 0x0800` normalize, errno `11/45/89/122/93/1133`, `/proc/self/{exe,maps,cmdline,stat,auxv}`, `/dev/a32host` handshake.

| ID | Location | Symptom | Fix |
|---|---|---|---|
| M32-R12-1 | `syscalls_meta.c:45` | `F_GETFL` drops `O_SYNC` | Map `O_SYNC` first |
| M32-R12-2 | `vm_file.c:203` | sysroot skips absolute `openat` | Drop `dirfd` check |

## M32-R12-1 — `F_GETFL` loses `O_SYNC`

`host_to_mips_flags()` in [syscalls_meta.c](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls_meta.c:45) maps `O_DSYNC` but never `O_SYNC`. On Linux `O_SYNC` contains the `O_DSYNC` bit, so an `O_SYNC` fd reports `MIPS_O_DSYNC (0x10)` instead of `MIPS_O_SYNC (0x4010)`.

Repro: `open(p, MIPS_O_SYNC)` then `fcntl(F_GETFL)` returns `0x10`, not `0x4010`.

Fix, at `syscalls_meta.c:59`:

```c
if ((host & O_SYNC) != 0) mips |= MIPS_O_SYNC;
else if ((host & O_DSYNC) != 0) mips |= MIPS_O_DSYNC;
```

## M32-R12-2 — sysroot bypass when `dirfd != AT_FDCWD`

`mips_sysroot_open()` in [vm_file.c](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:203) returns `-1` unless `dirfd == AT_FDCWD`. Linux ignores `dirfd` for absolute paths, and the function already rejects non-absolute paths, so the check is dead logic that breaks absolute `openat`.

Repro with `sysroot` set: `openat(5, "/lib/libc.so.6", O_RDONLY)` misses sysroot, opens host path.

Fix: remove the `dirfd != MIPS_AT_FDCWD` clause; absolute paths resolve via sysroot regardless of `dirfd`.

