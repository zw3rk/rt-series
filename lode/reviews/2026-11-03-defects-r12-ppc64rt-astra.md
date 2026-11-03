# Round-12 Deep-Dive 6: Syscall ABI / Marshaling / `/proc/self` / Backends — Static Audit

## Summary

| ID | File:line | Defect | Severity |
|----|-----------|--------|----------|
| P64-R12-1 | `src/os/syscalls_conv.c:52` | `x_errno_map` maps host `ENOSYS` to `95` (`EOPNOTSUPP`) instead of `38` | BUG — wrong guest errno |
| P64-R12-2 | `src/os/syscalls_misc.c:197` | `getdents64` folds every non-`EBADF` host error to `EIO`, losing `ENOTDIR`/`EINVAL`/`EFAULT` | BUG — wrong guest errno |

Verified clean (0 findings): `CR0.SO`/return convention, PowerPC `O_*` mapping, `stat`/`statx` layouts, `procfs` builders, backend errno translators, `EDEADLK` reachability.

## P64-R12-1 — `ENOSYS` mistranslated to `EOPNOTSUPP`

- Location: [syscalls_conv.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_conv.c:52), table entry `{ ENOSYS, 95 }`.
- The same TU defines `XENOSYS = 38` ([syscalls_conv.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_conv.c:44)); `95` is `XEOPNOTSUPP`.
- Reproduction: any conv-path call (`open`/`stat`/`dup`/`lseek`/`pipe`/`mkdir` via `x_host_to_linux`) whose host call fails with `ENOSYS` (38 on Linux, 78 on Darwin) reports `95` to the guest instead of `38`.
- Fix (one constant):
```c
{ ELOOP, 40 }, { EOVERFLOW, 75 }, { ENOSYS, 38 }
```

## P64-R12-2 — `getdents64` error folding

- Location: [syscalls_misc.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:197):
```c
return err == EBADF ? SYSCALL_EBADF : SYSCALL_EIO;
```
- Reproduction: `open` a regular file, call `getdents64` on it. Host returns `ENOTDIR` (20); guest observes `EIO` (5) instead of `ENOTDIR` (20). Same loss for `EINVAL`/`EFAULT`.
- Fix (use the TU's own translator, declared at line 64):
```c
return syscall_host_to_linux(err);
```
On Linux this is identity (preserves `ENOTDIR`); on Darwin it maps to the curated table.

## Verified clean (no defect reported)

- `CR0.SO` convention: [syscalls.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls.h:101) `ppc64_syscall_apply_return` sets `gpr[3]=+errno` + `CR0.SO` on `sc` error, clears it on success, and uses `r3=-errno` untouched-CR on `scv`. All `ppc64_syscall` dispatch paths return `0`/`+errno`/`PPC64_SYSCALL_EXITED` consistently.
- `O_*` flags: guest `XO_DIRECTORY=0x4000`, `XO_NOFOLLOW=0x8000`, `XO_DIRECT_PPC=0x20000` ([syscalls_conv.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_conv.c:80)) map to asm-generic `0200000`/`0400000`/`040000`, matching [backend_fs.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_fs.c:53). Initial DIRECTORY/NOFOLLOW-swap suspicion was wrong; the pair is self-consistent and numerically correct for PPC→generic.
- `stat` (144 B, `st_nlink` at +16, `st_mode` at +24) and `statx` (256 B) layouts and `static_assert`s ([sigframe_ppc64rt.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe_ppc64rt.h:219), [syscalls_conv.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_conv.c:61)); fill paths assign every field.
- `EDEADLK`: no guest-reachable path in the implemented set (`open`/`stat`/`read`/`write`/`futex`/etc.) can surface it; translators' defaults are unreachable. No defect.
- `procfs` builders (`exe`/`maps`/`cmdline`/`stat`/`auxv`, [procfs.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/procfs.c:67)) are byte-correct; `status`/`fd/*` returning `PPC64_PROCFS_NONE` matches the documented lane scope ([procfs.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/procfs.h:6)). Unimplemented `statfs`/`readv`/`ioctl`/`rlimit` correctly report `ENOSYS`.

