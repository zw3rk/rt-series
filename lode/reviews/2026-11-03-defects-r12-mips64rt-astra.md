# `mips64rt` Round-12 Deep-Dive 6 audit

Read-only static audit. No subagents, no file modifications, no builds or tests. Scope only: `src/os/syscall_min.c`, `src/os/syscalls.c`, `src/os/syscalls_*.c`, `src/os/proc.c`, `src/os/backend_*.c`, `src/os/family_broker.c`, plus `src/os/errno_map.h`, `src/os/syscall_nr.h` as ABI oracles.

## Summary

| ID | Where | Defect | Fix |
| --- | --- | --- | --- |
| M64-R12-1 | `errno_map.h:57` | Linux errnos untranslated | Add MIPS map |

## M64-R12-1 — `BUG`: Linux host errnos returned verbatim instead of MIPS numbers

Location: [errno_map.h](/Users/angerman/Projects/zw3rk/mips64rt/src/os/errno_map.h:57) (`#else` branch):

```c
return (host_errno == 38) ? 89 : (int32_t)host_errno;
```

The header comment at [errno_map.h](/Users/angerman/Projects/zw3rk/mips64rt/src/os/errno_map.h:8) claims MIPS matches `asm-generic` except `ENOSYS`. That assumption is false. Every `l2a_ret`/`sc_ret` call site ([syscalls.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:112), [syscall_min.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:184)) therefore reports wrong `$v0` for at least seven reachable errnos.

Corroborated kernel ABI values, both sides:

- Host `AArch64` `asm-generic`: `EDEADLK 35`, `ENAMETOOLONG 36`, `ENOTEMPTY 39`, `ELOOP 40`, `EOVERFLOW 75`, `EOPNOTSUPP 95`, `EDQUOT 122`, `ENOSYS 38`.
- Guest `MIPS` `arch/mips/include/uapi/asm/errno.h`: `EDEADLK 45`, `ENAMETOOLONG 78`, `ENOTEMPTY 93`, `ELOOP 90`, `EOVERFLOW 79`, `EOPNOTSUPP 122`, `EDQUOT 1133`, `ENOSYS 89`.

Reproduction conditions (all currently return the host number with `$a3=1` instead of the MIPS number):

- `ENAMETOOLONG`: guest `openat` with a `>4096`-byte path. [syscalls.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:200) returns host `-36`; guest expects `$v0=78`.
- `ENOTEMPTY`: guest `unlinkat` on a non-empty directory without `AT_REMOVEDIR` handling change; host returns `39`, guest expects `93`.
- `ELOOP`: guest `openat` through a symlink loop, or `open("/proc/self/exe", O_NOFOLLOW)` via [proc.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/proc.c:427); host `40`, guest expects `90`.
- `EOVERFLOW` (`75` vs `79`), `EDQUOT` (`122` vs `1133`), `EOPNOTSUPP` via [sigact.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:661) (`95` vs `122`), and `EDEADLK` (`35` vs `45`) follow the same path.

The Darwin branch has the same class of error: cases `11`, `62`, `63`, `66`, `69`, `84` map to generic numbers (`35`, `40`, `36`, `39`, `122`, `75`) instead of MIPS numbers (`45`, `90`, `78`, `93`, `1133`, `79`).

Minimal surgical fix in `l2a_errno_from_host`: keep the `ENOSYS` row, add a Linux `switch` mapping `35→45`, `36→78`, `39→93`, `40→90`, `75→79`, `95→122`, `122→1133`, and correct the six Darwin targets listed above to the same MIPS values.

## Coverage with no further defects

- Dispatch (`$v0` nr, `$a0..$a5`, `$v0`+`$a3`, `pipe2` staging, `N32 time64` companions), `O_*` values, `fcntl` `GETFL`/`SETFL`, `stat`/`statx` LE/BE fills, `getdents64` BE fixup, `clock_gettime`/`nanosleep`/`clock_nanosleep` layouts and lease handling, `iovec` word widths, `/proc/self/{exe,maps,cmdline,stat,auxv}` synthesis, sysroot joins, `family_broker`, and `backend_linux`/`backend_darwin` `W^X` handling were inspected against the Phase 2/4/5 contracts. No additional concrete behavioral bugs found.
- Deliberately not reported: legacy `pipe` (`5021`/`6021`), `statfs`, sockets, `epoll`/`poll`/`pselect6` (all `ENOSYS` by Phase 2 scope), and `/proc/self/status` or `/proc/self/fd/*` (outside the Phase 5 five-file contract). `MIPS_MAP_ANONYMOUS 0x20` in [syscall_min.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:163) is correct per MIPS `mman.h` (`0x0800` is `MAP_DENYWRITE`); the `0x800` alias is accepted as configured.

