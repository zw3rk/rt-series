# Round-12 Deep-Dive 6: Syscall ABI / Marshaling / procfs / Backends

**Scope read:** `src/os/syscalls.c`, `syscalls_min.c`, `syscalls_time.c`, `syscalls_sig.c`, `syscall_nr.h`, `backend_linux.c`, `backend_darwin.c`, `backend.h`, `rt32/procfs.c`, `rt32/host.c`, plus `rt32/elf32.c` (one helper) and kernel UAPI ground truth (`errno.h`, `fcntl.h`, `ioctls.h`, `ioctl.h`, `termbits.h` from torvalds/linux; rust-libc and strace traces as second sources).

**Result: 3 defects.** No findings in: dispatch/carry mechanics, `pipe` dual-return, `O_*` values (all 13 verified against `arch/sparc` `fcntl.h`, incl. `O_SYNC=0x802000`), `stat`/`stat64`/`statx` layouts, `clock_gettime{,64}`, `FIONREAD`, F_SETFL/GETFL translation, `dirfd`/sysroot gating, `exe` synthesis, or `/dev/a32host` probing.

| ID | Where | Defect |
|---|---|---|
| S32-R12-1 | `syscalls_min.c:143-147` | 4 wrong SPARC errno numbers |
| S32-R12-2 | `syscalls_time.c:31,359` | Wrong TCGETS number, empty success |
| S32-R12-3 | `procfs.c:126,145,169,202,230` | Synthetic fds drop O_CLOEXEC |

## S32-R12-1: wrong SPARC errno values in `sparc_errno_from_host`

`sparc_errno_from_host` (`src/os/syscalls_min.c:143-147`) maps `ENOSYS→38`, `ENAMETOOLONG→36`, `ELOOP→40`, `EOVERFLOW→75`. Those are asm-generic numbers. Linux/SPARC uses SunOS numbering (`arch/sparc/include/uapi/asm/errno.h`, verified first-hand): `ENOSYS=90`, `ENAMETOOLONG=63`, `ELOOP=62`, `EOVERFLOW=92`. The comment above it ("SPARC Linux errnos are the asm-generic numbers … SPARC as 38") is factually wrong, as is the macOS example (should be "78 → 90"). This is the single choke point for every error return (commit at `syscalls_min.c:881,888`), so all error paths are affected.

Reproduction: `ta 0x10` with `%g1=236` (`_llseek`, unimplemented) yields `%o0=38, C=1`; the oracle yields 90, so guest-libc `ENOSYS` fallbacks never trigger (38 is `ENOTSOCK` on SPARC). Likewise a >4095-byte path yields 36 instead of 63, a symlink loop yields 40 instead of 62, and `lseek` past 2 GiB yields 75 instead of 92.

Fix: return `90/63/62/92` in those four arms and correct the comment.

## S32-R12-2: `TCGETS` can never match, and succeeds without a payload

`SP_TCGETS` is `0x80245408` (`syscalls_time.c:31`), but SPARC `_IOR` encodes READ as `2<<29`, so the true request is `0x40245408` (corroborated by rust-libc's sparc64 table and an strace decode of `ioctl(1, 0x40245408, …)` as `TCGETS`). A real guest request therefore always falls through to `-ENOTTY`, even on a tty. Independently, the match arm (`syscalls_time.c:359`) returns 0 on `isatty` without storing anything to `arg_va`, so success would hand the guest uninitialized `termios`.

Reproduction: guest `ioctl(tty_fd, 0x40245408, &t)` returns `ENOTTY`; oracle fills the 36-byte BE `termios`.

Fix: change the constant to `0x40245408U`; then either marshal host `termios` into the BE guest layout or return `-ENOTTY`.

## S32-R12-3: `/proc/self/{maps,cmdline,stat,auxv}` discard guest `O_CLOEXEC`

`procfs_open_maps/cmdline/stat/auxv` call `procfs_serve_bytes(…, O_RDONLY)` with a hardcoded flag (`procfs.c:163,197,227,248`), dropping the guest's `host_flags` — even though `procfs_serve_bytes` already implements `O_CLOEXEC`/`O_NONBLOCK` (`procfs.c:95-101`). The `openat` wrapper still records CLOEXEC in the fd table, so `execve` sweep is correct, but the host fd flag stays clear. (`/proc/self/exe` is fine: `rt32_open_guest_ro` always sets `O_CLOEXEC`.)

Reproduction: guest `open("/proc/self/maps", O_RDONLY\|O_CLOEXEC)` then `fcntl(F_GETFD)` returns 0; the oracle returns `FD_CLOEXEC`.

Fix: thread `host_flags` into the four helpers and pass it to `procfs_serve_bytes` instead of `O_RDONLY`.

## Explicitly checked, no defect

Unimplemented `pread64`/`pwrite64`/`truncate64`/`_llseek`/`statfs64`/`socket`/`socketcall`/`poll`/`ppoll`/`pselect6` correctly route to the default `-ENOSYS` arm (whose *number* is fixed by S32-R12-1); `/proc/self/fd/*` passthrough is correct under fd identity; `status` passthrough matches oracle behavior.
