# Round-12 Deep-Dive 6 Static Audit: Syscall / Marshaling / `/proc` / Host Backends

Scope (read-only; no edits, builds, or tests run): `src/os/os_sys_path.c`, `src/os/os_sys_fs_arm.c`, `src/os/os_sys_sock.c`, `src/os/os_sys_thread_sig.c`, `src/os/os_sys_sig_time.c`, `src/os/os_sys_fork_time.c`, `src/os/sys_priv.h`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/host.c`, `include/a32host.h`. Cross-checked dispatch chain (`thread_sig` → `sig_time` → `sock` → `fs_arm`), register-pair conventions, and test coverage in `tests/`.

## Summary

| ID | Location | Defect |
|---|---|---|
| A32-R12-1 | `sys_priv.h:656-657` | Darwin maps O_DIRECT/LARGEFILE to DIRECTORY/NOFOLLOW |
| A32-R12-2 | `os_sys_thread_sig.c:698` | `faccessat` drops `AT_SYMLINK_NOFOLLOW` |
| A32-R12-3 | `os_sys_thread_sig.c:251-271` | Darwin futex reads relative timeout as absolute |

### A32-R12-1: Darwin `translate_open_flags` mis-maps two guest flag bits

`src/os/sys_priv.h:656-657` ORs guest `0x10000` into host `O_DIRECTORY` and guest `0x20000` into host `O_NOFOLLOW`. The correct ARM32 values are `O_DIRECTORY = 040000 (0x4000)`, `O_NOFOLLOW = 0100000 (0x8000)`, `O_DIRECT = 0200000 (0x10000)`, `O_LARGEFILE = 0400000 (0x20000)`. The extra terms match x86 numbering, not ARM. (Linux passthrough at `sys_priv.h:661` is correct: arm64 kernels run ARM32 compat binaries with untranslated `O_*`, so host and guest values coincide.) Repro on the Darwin build: guest `open(f, O_RDONLY\|O_DIRECT)` on a regular file fails with `ENOTDIR`; any libc `open()` (glibc/musl always OR `O_LARGEFILE`) targeting a final-component symlink fails with `ELOOP`. Fix: map only `0x4000 → O_DIRECTORY` and `0x8000 → O_NOFOLLOW`; drop the other two bits.

### A32-R12-2: `faccessat` ignores the guest flags argument

`src/os/os_sys_thread_sig.c:698` sets `gflags = 0` for `ARM_NR_faccessat` (only `faccessat2` uses `a3`), and the fallback at `:715-717` calls `faccessat(..., 0)`. ARM `faccessat` takes `(dirfd, path, mode, flags)` with `AT_SYMLINK_NOFOLLOW = 0x100` in `a3`. Repro: guest `faccessat(AT_FDCWD, "/dangling-link", R_OK, AT_SYMLINK_NOFOLLOW)` should return 0 but returns `-ENOENT`, because resolution follows the link and the host call gets flags 0. The adjacent `faccessat2` path handles flags correctly, confirming oversight. Fix: `uint32_t gflags = is_at ? a3 : 0U;` and pass `hflags` in the non-`at2` branch.

### A32-R12-3: Darwin `futex_darwin_wait` treats a relative timeout as absolute

`src/os/os_sys_thread_sig.c:251-270` reads the guest relative timeout into `end_m`, then subtracts `CLOCK_MONOTONIC` now. For a typical relative timeout (e.g. 5 s) against a large uptime clock, `ds` is negative, so no sleep happens and the function returns `-ETIMEDOUT` immediately. Repro: guest `FUTEX_WAIT` with `uaddr == val` and a 5 s relative timeout returns `-110` instantly instead of blocking up to 5 s; `pthread_mutex_timedlock` spuriously times out on the Darwin backend. (The `a3 == 0` infinite-wait path spin-returns 0, which is benign: glibc re-checks the condition.) Fix: validate the relative `timespec` and `nanosleep()` it directly, removing the `clock_gettime` subtraction.

## Audited clean (no defect)

Register-pair orderings (`pread64`/`pwrite64` `a4:a5`, `truncate64`/`ftruncate64` `a2:a3`, `_llseek` lo `a2`/hi `a1`, `fallocate`/`sync_file_range2`, `statx` uid/gid words `[5]/[6]`, Darwin `statx` field offsets), `set_tls`/`get_tls`/`cacheflush` (start/end convention matches `a32_jit_invalidate_range`), `clone` TLS/parent-settid ordering, `statfs64` 84/88 sizes, `getcwd` length return, `rt_sigpending`/`waitid` layouts, `futex_time64` plumbing, `getdents` cookie mapping, `epoll_out_ok` full-extent check, `pselect6`/`ppoll` timeout writeback, `A32H_ABI` major-only check in `src/host.c:46`, and the `/proc` virtual set (`exe`, `maps`, `cmdline`, `auxv`, `cpuinfo`). `/proc/self/stat`, `status`, and `fd/*` are unvirtualized passthrough and uncovered by tests (`tests/test_m1_isa_fs.c:120-138`, `tests/test_m5_ltp_gdb.c:492-539` cover only `exe`/`maps`); that is a known coverage gap, not a demonstrated defect, so per the annealing rule it is not filed.
