# Round-12 Deep-Dive 6 — Syscall ABI / Marshaling / `/proc/self` / Host Backends

**Scope:** `src/linux/io.c`, `src/linux/file.c`, `src/linux/file_transfer_internal.h`, `src/linux/file_open_internal.h`, `src/linux/metadata.c`, `src/linux/poll.c`, `src/linux/socket.c`, `src/linux/message.c`, `src/linux/sleep.c`, `src/linux/misc.c`, `src/linux/path.c`, `src/linux/resolve.c`, `src/linux/directory.c`, `src/linux/pipe.c`, `src/linux/codec.c`, `src/linux/error.c`, `src/linux/rv32_abi.h`, `src/linux/rv32_frame.c`, `src/linux/memory.c`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/runtime/runtime_main_syscall.c`, `src/runtime/runtime_main_syscall_leaf.c`, `src/runtime/proc_inventory.c`; cross-checked against `docs/SUPPORT.md` and `docs/HOST-CONTRACT.md`.

**Method:** read-only static review. No subagents, no edits, no builds/tests.

## Verdict

**0 defects found.** No `BUG` / `DEFECT` to report.

## What was checked

- **RV32 64-bit pairs:** `pread64`/`pwrite64` low-first in `a3:a4` ([file_transfer_internal.h](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file_transfer_internal.h)), `ftruncate64` low-first in `a1:a2` ([file.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:356)), `_llseek` high-first in `a1:a2` ([file.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:73)) — each matches its Linux ABI.
- **time64:** `clock_gettime` 113/403, `clock_nanosleep` 115/407, `pselect6` 72/413, `ppoll` 73/414, `utimensat` 88/412, `futex` 98/422 share one 16-byte `timespec` codec with correct RV32 gating. `nanosleep`/`gettimeofday`/RV32 guards match the stated RV64-only inventory.
- **`statx`/`newfstatat`:** `AT_SYMLINK_NOFOLLOW`/`NO_AUTOMOUNT`/`EMPTY_PATH` (+`0x6000`) handling, empty-path/`AT_FDCWD` paths, trailing-slash and symlink-race checks in [metadata.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/metadata.c) match the support table.
- **`ioctl`/sockets/poll:** `TIOCGWINSZ` ([file.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:446)) plus owned-pipe/FIFO `FIONREAD` ([pipe.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/pipe.c:166)), other ioctls `ENOTTY`; socket option/message Rivest-Shamir-Adleman-correct per the bounded subset; `poll`/`pselect6` RV32 `fd_set` stride and `msghdr`/`iovec` strides correct.
- **Flags/errno:** `O_*` mapping ([path.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/path.c:101)), `F_DUPFD_CLOEXEC` 1030, `AT_EMPTY_PATH`/`AT_SYMLINK_NOFOLLOW`, and `EAGAIN`/`EWOULDBLOCK`→11, `ENOSYS`→38, `EOPNOTSUPP`→95, `ENOTEMPTY`→39, `EDEADLK`→35 in [error.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/error.c) all correct.
- **`/proc/self`/sysroot:** no guest procfs view by design; `resolve.c` denies `PROC_SUPER_MAGIC` and pinned `/proc`+`/dev/fd` identities, `path_join` + leaf walk implement the documented sysroot-prefix (not sandbox) semantics. Unlisted calls (`fallocate`, `statfs`, `clock_getres`, `TCGETS`, `epoll`) returning `ENOSYS`/`ENOTTY` is the documented contract, not a bug.

No surgical fixes required; subsystem has converged.

