**Scope note.** The four files are syscall shims; no Thumb-2/IT/NEON codegen is in them, so those categories are empty here. Findings below are ranked. Items marked "verify" rest on XNU ABI facts I could not cross-check against `ios/ios.h` or the parity fixtures within the read limit.

## P1 — correctness

1. **64-bit syscall operands read from the wrong register slots (verify).** `src/ios/ios_svc_bsd.c:814-821` (pread/pwrite use `args[3..4]`), `:843` (lseek uses `args[1..3]`), `:601` (mmap offset uses `a[5..6]`), `src/ios/ios_svc_bsd_fs.c:836-838` (truncate/ftruncate use `args[1..2]`). The dispatcher at `:779-787` builds `args[]` as the raw `r0..r6, r8` vector, which is exactly what the arm32 libsyscall wrapper hands the kernel. XNU's arm32 mungers (`munge_wl`, `munge_wlw`, `munge_wwwl`, `munge_wwwwwl`) take 64-bit operands from even-aligned slots per AAPCS, so the correct indices are: truncate/ftruncate `args[2..3]`, lseek off `args[2..3]` whence `args[4]`, pread/pwrite off `args[4..5]`, mmap off `args[6..7]`. Today lo comes from the pad word. Anonymous mmap only survives when that pad happens to be zero (the `off & 4095` test at `:602`). Reproducer: guest `lseek(fd, 4096, SEEK_SET)` followed by `read`. If it reads from offset 0 or fails with EINVAL, the fix is the index shift above.

2. **getdirentries64 emits the wrong `struct dirent` layout and misuses `basep`.** `src/ios/ios_svc_bsd_fs.c:419-424` writes `d_name` at offset 24; Darwin's 64-bit `direntry` places `d_name` at offset 21 directly after `d_type`, with `d_reclen = (21 + namlen + 1 + 7) & ~7`. Every readdir result shows an empty name. Also `:380,393` reads the guest's `basep` as an input seek position; on XNU `basep` is output-only and receives the offset *before* the read. On Linux hosts the uninitialised value seeks the directory to garbage. Fix: name at 21, reclen as above, record offset before the first readdir and write that to `basep`. Separately, the dup/fdopendir/closedir per call (`:381-429`) throws away libc DIR state every call; on macOS `telldir` tokens are per-DIR so `seekdir(prev)` is a silent no-op. Keep a small fd-to-DIR cache and release it from the close hook that already exists for kqueue.

3. **statfs64 (345/346) layout is wrong.** `src/ios/ios_svc_bsd_fs.c:226-242` defines a hybrid of the legacy and 64-bit structs. Darwin 32-bit `statfs64` is `{u32 f_bsize; i32 f_iosize; u64 blocks,bfree,bavail,files,ffree; fsid_t; uid_t owner; u32 type; u32 flags; u32 fssubtype; char fstypename[16]; char mntonname[1024]; char mntfromname[1024]; u32 reserved[8]}` (2168 bytes). The guest reads `f_bsize` at offset 0 and gets the zeroed `f_otype`. The legacy 157/158 struct is different again (32-bit `long` fields, 15/90/90-byte names). Emit the real layouts, one per syscall family.

4. **Likely `stat64` size mismatch (verify against `ios_stat64_t`).** `src/ios/ios_svc_bsd_fs.c:192,213,350` hardcode 108 bytes. On armv7, `off_t st_size` is 8-byte aligned, inserting 4 bytes of padding after `st_birthtimespec` and giving `sizeof(struct stat) == 112` with `st_size` at offset 64. 108 is the i386 size. If `ios_stat64_t` is 108 bytes packed, `st_size`, `st_blocks`, `st_blksize` are all shifted by 4. The 96-byte legacy stat needs no padding and is fine.

5. **madvise/msync have no guest-range check (host memory corruption).** `src/ios/ios_svc_bsd.c:643,689` call `madvise(a32_guest_ptr(a[0]), a[1])` with no bound on `a[0] + a[1]`. A guest `madvise(0xFFFFF000, 0x10000000, MADV_DONTNEED)` spills past the 4 GiB window into translator heap or code cache and discards it. Add the same `a32_guest_range_ok` plus wrap test used by mincore at `:649-662`. While there: on Linux hosts Darwin `MADV_FREE_REUSE` (8) passes through as Linux `MADV_FREE` and discards live malloc pages, and `MADV_CAN_REUSE` (9) becomes `MADV_REMOVE`. libmalloc issues 7/8/9 constantly. Map 7 and 9 to no-op, 8 to no-op, 5 to Linux 8 as now.

6. **rlimit renumbering applied on Apple hosts.** `src/ios/ios_svc_bsd_proc.c:460-472,478,496` remap Darwin 6/7/8 to Linux order unconditionally. On the primary macOS target, `getrlimit(RLIMIT_NOFILE)` returns the host's NPROC limit. Wrap `rl_host` in `#if !defined(__APPLE__)`.

7. **Control messages use a hand-rolled Linux cmsghdr on both hosts.** `src/ios/ios_svc_bsd_sock.c:330-338,352-366` assume a 16-byte header with 64-bit `cmsg_len` and 8-byte alignment. On macOS `struct cmsghdr` is 12 bytes with `socklen_t cmsg_len` and 4-byte alignment, so SCM_RIGHTS fd passing produces garbage on the main target. Build and walk with the host's `CMSG_FIRSTHDR`/`CMSG_NXTHDR`/`CMSG_LEN`/`CMSG_SPACE`. Also translate `SCM_CREDS` (Darwin 3) vs `SCM_CREDENTIALS` (Linux 2) on Linux.

8. **Syscall 374 is `kevent_qos`, not `kevent64`; 369 (`kevent64`) is unhandled.** `src/ios/ios_svc_bsd_sock.c:848,866`. `kevent_qos` takes 64-byte `kevent_qos_s`, `data_out`, `data_available`, `flags`, and no timeout. `kevent64` has 7 args with `flags` at `args[5]` and timeout at `args[6]`. libdispatch on iOS 10 to 13 drives everything through 374/375, so today it reads a timespec from the `data_out` pointer and parses 48-byte records in a 64-byte array. Add 369 with the shifted timeout, and give 374 its own parser or a clean ENOSYS so libdispatch falls back.

9. **kevent wakes immediately and starves timers.** `src/ios/ios_svc_bsd_sock.c:756` polls every fd knote with `POLLIN | POLLOUT`, so any writable socket with only an EVFILT_READ knote returns `poll` instantly, `sk_knote_ready` reports nothing, and the call returns 0 events before the timeout. Run loops spin at 100 percent CPU. Timer knotes (`:761`) never shorten `wait_ms`, so a 10 ms timer waits up to 60 s. Fix: per-knote events by filter, `wait_ms = min(timeout, earliest timer deadline - now)`, and loop until deadline when nothing is ready. This is also PERF-1.

10. **Darwin `MSG_DONTWAIT` (0x80) is dropped.** `src/ios/ios_svc_bsd_sock.c:125-141` masks flags to known bits and never maps 0x80 to host `MSG_DONTWAIT`. A non-blocking recv becomes a blocking one. Add the mapping; also pass Darwin `MSG_NOSIGNAL` (0x80000) through.

## P2 — correctness

11. **`openat` ignores `dirfd`.** `src/ios/ios_svc_bsd.c:409-413`. A relative path with `dirfd != AT_FDCWD` resolves against cwd. The `*at` family in the fs file passes an already-absolute path too (`ios_svc_bsd_fs.c:359,462,495`), so `dirfd` is effectively dead everywhere. Resolve relative paths against the dirfd's `F_GETPATH` or use the host `*at` call on the raw guest string when no sysroot rewrite applies.

12. **`AT_SYMLINK_FOLLOW` constant wrong.** `src/ios/ios_svc_bsd_fs.c:44` defines it as 0x20; Darwin uses 0x40 (0x20 is `AT_SYMLINK_NOFOLLOW`). linkat follows symlinks when asked not to.

13. **`F_GETPATH` demands 4096 writable bytes.** `src/ios/ios_svc_bsd.c:527,543`. Darwin `MAXPATHLEN` is 1024 and guests pass 1024-byte buffers; the check spuriously faults near mapping ends and the Linux branch copies past the guest buffer. Use 1024. Also the returned path is a host sysroot path; strip the sysroot prefix so `getcwd`/`realpath` see guest paths. Same for `proc_info` at `ios_svc_bsd_proc.c:726`.

14. **sysctl truncation returns success.** `src/ios/ios_svc_bsd_proc.c:649-652`. When `need > avail`, XNU copies `avail` bytes, sets `*oldlenp = avail`, and returns ENOMEM. Here it returns 0 and writes `*oldlenp = need`, so callers read past their buffer.

15. **fork can deadlock on `g_kq_mu`.** `src/ios/ios_svc_bsd_proc.c:161` forks while another host thread may hold the kqueue mutex (`ios_svc_bsd_sock.c:562`). The child's first kqueue call hangs. Take `g_kq_mu` around `fork()` or register `pthread_atfork`.

16. **`terminate_with_payload` ignores its pid and both 520/521 exit instead of raising SIGABRT.** `src/ios/ios_svc_bsd_proc.c:773-780`. A parent `wait4` sees `WIFEXITED` 134 rather than `WIFSIGNALED(SIGABRT)`. Use `kill(pid, SIGABRT)` for 521 and `raise(SIGABRT)` after resetting the handler for 520.

17. **Linux host option and pathconf renumbering.** `src/ios/ios_svc_bsd_sock.c:109` passes IP/IPV6/TCP option names through unchanged; Darwin `IP_TTL` 4, `IPV6_V6ONLY` 27, `TCP_KEEPALIVE` 0x10 differ from Linux. `src/ios/ios_svc_bsd_fs.c:745,831` pass `_PC_*` names through; Darwin numbering is Linux plus one. Both need `#if !defined(__APPLE__)` tables.

18. **Timer units.** `src/ios/ios_svc_bsd_sock.c:644` treats everything except `NOTE_SECONDS` as milliseconds; `NOTE_USECONDS` (2), `NOTE_NSECONDS` (4), `NOTE_ABSOLUTE` (8) and `NOTE_MACHTIME` (0x100) all come out 1000 to 1e6 times too long.

19. **Apple host page size.** `madvise`, `msync`, `mincore` (`ios_svc_bsd.c:643,663,689`) go straight to the host, whose page is 16 KiB. 4 KiB-aligned guest addresses get EINVAL, and the mincore vector is one byte per 16 KiB. Route through the vm layer that already handles 4K-to-16K for mmap/mprotect.

20. **`getgroups` unbounded malloc.** `src/ios/ios_svc_bsd_proc.c:408` allocates `n * 4` for any positive `n`. Clamp to `NGROUPS_MAX` (16).

## PERF (hypotheses, unmeasured)

- **PERF-1.** Item 9 above. After the wake fix, `sk_knote_ready` (`:649-666`) still re-polls each knote and issues `FIONREAD` per ready read knote, so one kevent costs 1 + N + R syscalls. Index `pfds` by knote and read `revents` directly.
- **PERF-2.** `ios_cstr` and `g_cstr` (`ios_svc_bsd.c:156-177`, `ios_svc_bsd_fs.c:58-79`, `ios_svc_bsd_proc.c:104-124`) perform one `a32_guest_range_ok` per byte, up to 4096 per path. Check a page at a time and `memchr` within it. Confirm with `--stats` on an open-heavy workload before changing.
- **PERF-2.** `a32_vm32_copyout_invalidate_exec` is called on every `read`/`readv`/`recvmsg` buffer (`ios_svc_bsd.c:260,330`, `ios_svc_bsd_sock.c:497`). If it is not an O(pages) bit test with an early exit when no executable page intersects, read-heavy workloads will show it. Measure first.

## POLISH — missing ABI surface

- fcntl: `F_SETLK`/`F_GETLK`/`F_SETLKW` (7/8/9), `F_NOCACHE` (48), `F_FULLFSYNC` (51), `F_SETNOSIGPIPE` (73), `F_PREALLOCATE` (42). SQLite needs the first three and 51. (`ios_svc_bsd.c:566`)
- ioctl: `TIOCGETA` (0x40487413) so `isatty` works and stdio line-buffers; `TIOCGPGRP`, `TIOCSETA`. (`ios_svc_bsd.c:462`)
- BSD syscalls: `utimes` 138, `futimes` 139, `flock` 131, `setitimer` 83, `getitimer` 86, `getxattr`/`setxattr`/`listxattr` 234-240, `getattrlist` 220 (Darwin `realpath` uses it), `getfsstat` 18/347, `fsgetpath` 427, `pselect` 394, `connectx` 447 (CFNetwork path), `sendfile` 337, `guarded_open_np` 441.
- Socket options: `SO_RCVTIMEO`/`SO_SNDTIMEO` (0x1006/0x1005, need 8-byte guest timeval to host timeval), `SO_NREAD` 0x1020, `SO_OOBINLINE`, `SO_DONTROUTE`. recvmsg should write back `msg_flags` at offset 24 (`ios_svc_bsd_sock.c:499-513`).
- kevent: `EV_RECEIPT` (0x40) must echo one `EV_ERROR` record per change, and bad fds should surface as `EV_ERROR` with `data = errno` rather than silently vanishing. (`:603-647`)
- sysctl table (`ios_svc_bsd_proc.c:581-593`) is internally inconsistent: `osrelease` 19.6.0 and `osversion` 17G68 are iOS 13.6, but `osproductversion` says 10.3.4 and `hw.machine` iPhone5,2 is armv7s capped at iOS 10.3.4. Pick one device/OS pair. Add `kern.boottime` (1,21), `kern.maxproc` (1,6), `kern.maxfilesperproc` (1,27), `hw.tbfrequency`, `hw.physmem`, `hw.l1icachesize`, `hw.optional.*`.
- `gettimeofday` has a third `mach_time` pointer on iOS 10 and later (`:501`); write `mach_absolute_time` there when non-zero.
- `proc_info` (`:729`) only answers `PROC_PIDPATHINFO`; libdispatch and Foundation also query `PROC_PIDTBSDINFO` (3), `PROC_PIDT_SHORTBSDINFO` (13), and `PROC_INFO_CALL_SETCONTROL` (5).
- Observability: `trace_enabled` prints raw numbers only; a name table for the BSD numbers in the trace line (`ios_svc_bsd.c:790`) and a counter of ENOSYS hits per number would make the missing-surface list self-maintaining.