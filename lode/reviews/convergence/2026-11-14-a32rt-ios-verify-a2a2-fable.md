# Round 19 Post-Remediation Review — Track A2a-2 (BSD Filesystem Syscalls, `claude-fable-5-1`)

Review complete. Findings below, scoped strictly to `DEFECTS.md` items `A32-IOS-D2` / `A32-IOS-D10` and `src/ios/ios_svc_bsd_fs.c`.

## Scope limits (stated first)

- **`A32-IOS-D2` is not verifiable from this file.** `madvise` (75) and `msync` (65) are not dispatched in `ios_svc_bsd_fs.c`. The ledger places them in `src/ios/ios_svc_bsd.c`, which the brief excluded from reading. No verdict.
- **Not present in this file, so unverified:** `open`/`openat` flag translation, `fcntl` `F_GETPATH`, `utimes`/`futimes`, and legacy 32-bit `getdirentries` (196). None of these syscall numbers appear in `a32_ios_dispatch_bsd_fs` (`src/ios/ios_svc_bsd_fs.c:831-894`); they must live in `ios_svc_bsd.c`.
- **`*at` dirfd honoring is conditionally sound.** Every `*at` handler resolves the guest path through `ios_resolve` → `a32_resolve_guest_path` before passing `ios_atfd(fd)` to the host. If that resolver leaves relative paths relative, `dirfd` works; if it absolutizes them against the sysroot or cwd, `dirfd` is silently ignored. The resolver is outside the permitted read set, so this stays UNVERIFIED.

## Residual defects

**1. `getfsstat64` (347) returns 0 entries after filling the buffer** (`src/ios/ios_svc_bsd_fs.c:355` → `:313`)
`ios_do_getfsstat` delegates to `ios_statfs_one`, which unconditionally ends with `a32_ios_bsd_ok(ctx, 0U, 0U, false)`. XNU returns the number of `statfs64` structs copied, so a caller with a valid buffer sees "0 mounted filesystems" and discards the filled entry. The count-only path (`buf == 0`, line 341) correctly returns 1, making the two paths inconsistent.
Fix: make `ios_statfs_one` return `bool` without setting the result, and have `ios_do_statfs` call `a32_ios_bsd_ok(ctx, 0U, ...)` while `ios_do_getfsstat` calls `a32_ios_bsd_ok(ctx, 1U, ...)`.

**2. Legacy `statfs` (157) / `fstatfs` (158) emit the 2168-byte `statfs64` layout** (`src/ios/ios_svc_bsd_fs.c:839-840`)
XNU syscalls 157/158 fill the legacy `struct statfs` (`user32_statfs`: `short f_otype/f_oflags`, `long` counters, `f_fstypename[15]`, `f_mntonname[90]`, `f_mntfromname[90]`, 272 bytes). The dispatcher routes them to `ios_do_statfs`, which writes 2168 bytes. A guest passing a 272-byte struct gets ~1.9 KB of adjacent stack or heap overwritten (host-side bounds are safe via `ios_wr_ok`, the corruption is guest-visible). Low likelihood on iOS since `__DARWIN_ONLY_64_BIT_INO_T` makes libSystem use 345/346, but raw-syscall users hit it.
Fix: drop `157U`/`158U` from the switch (fall through to the default unhandled path → `ENOSYS`), or implement the 272-byte legacy layout.

**3. Linux host: `f_flags` passed through untranslated** (`src/ios/ios_svc_bsd_fs.c:285`)
`o.f_flags = (uint32_t)hs.f_flags` copies Linux `ST_*` bits into a field the guest reads as Darwin `MNT_*`. The bit values differ: `ST_NOSUID` 2 ≠ `MNT_NOSUID` 8, `ST_NODEV` 4 ≠ `MNT_NODEV` 0x10, `ST_NOEXEC` 8 ≠ `MNT_NOEXEC` 4, and `ST_VALID` 0x20 (always set by the kernel) reads as `MNT_UNION`. Only `MNT_RDONLY` (1) coincides.
Fix: map bitwise (RDONLY→0x1, SYNCHRONOUS→0x2, NOEXEC→0x4, NOSUID→0x8, NODEV→0x10, NOATIME→0x10000000), always OR in `MNT_LOCAL` 0x1000, mask everything else.

## VERIFIED

- **`statfs64` layout** (`:242-262`): field offsets match XNU `struct statfs64` exactly (`f_bsize` u32 @0, `f_iosize` i32 @4, five u64 @8..47, `f_fsid` @48, `f_owner` @56, `f_type` @60, `f_flags` @64, `f_fssubtype` @68, names @72/88/1112, reserved @2136); `_Static_assert` of 2168 holds. `packed, aligned(4)` is correct for the APCS-GNU armv7 ABI where `uint64_t` is 4-byte aligned in structs.
- **`stat`/`lstat`/`fstat`/`stat64`/`fstat64`/`lstat64`/`fstatat64`** (`:202-238, 378-399`): 96-byte `ostat` and 108-byte `stat64` sizes are correct under APCS-GNU (4-byte `off_t` alignment). `ios_wr_ok` precedes each copyout. `fstatat64` maps Darwin `AT_SYMLINK_NOFOLLOW` 0x20 to the host constant.
- **`getdirentries64`** (`:408-482`): `d_name` at offset 21 (`d_ino` @0, `d_seekoff` @8, `d_reclen` @16, `d_namlen` @18, `d_type` @20); `d_reclen = (21 + namlen + 1 + 3) & ~3` matches XNU. `basep` is treated as output. Position handling is correct on both hosts: `telldir` returns an `lseek`-valid offset on glibc/musl and on Apple Libc (`dd_td->seekoff`). `dup` + `fdopendir` + `closedir` leaks no fd. `nbytes == 0` and buffer-overflow cases never dereference `dst` out of bounds.
- **`link`/`linkat`** (`:486-516`): Darwin `AT_SYMLINK_FOLLOW` is now `0x0040` (`:44`), closing the `0x20` vs `0x40` item in D10. `AT_FDCWD` -2 → host via `ios_atfd`. Argument order (fd1, p1, fd2, p2, flag) correct.
- **`readlink`/`readlinkat`** (`:759-780, 866-867`): write range checked before the host call; returns byte count; `readlinkat` argument shuffle (fd, path, buf, size) correct.
- **`access`/`faccessat`** (`:677-714`): `R_OK/W_OK/X_OK/F_OK` values coincide with the host; `AT_EACCESS` 0x10 and `AT_SYMLINK_NOFOLLOW` 0x20 translated.
- **`truncate`/`ftruncate`** (`:802-817, 887-891`): 64-bit `off_t` assembled from `args[1] | args[2] << 32` with no register-pair padding, which is correct for the APCS calling convention used by XNU's arm32 mungers.
- **`unlinkat` `AT_REMOVEDIR` 0x80, `renameat`, `mkdirat`, `symlinkat`** argument order and flag mapping correct.
- **`ios_cstr`** (`:58-95`): page-wise bounded copy, correct `ENAMETOOLONG` vs `EFAULT` termination, no over-read past the checked range.

**3 RESIDUAL DEFECTS**
