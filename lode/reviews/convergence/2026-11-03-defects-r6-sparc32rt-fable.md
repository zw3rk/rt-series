# Verification report: sparc32rt commit `4477836` vs. Round-6 defects S32-R6-1..10

Scope: static review of the commit diff plus surrounding context at `4477836`. No build, test, container, or QEMU run. Line numbers refer to the post-commit tree.

## Summary

| ID | Severity | Verdict | Note |
|---|---|---|---|
| S32-R6-1 | HIGH | VERIFIED | fd-table realloc no longer leaves a dangling pointer |
| S32-R6-2 | HIGH | VERIFIED | argv/envp/exec path deep-copied into heap ownership |
| S32-R6-3 | HIGH | VERIFIED | `futex_time64` passes full `op`, matching `futex` |
| S32-R6-4 | HIGH | VERIFIED | CSPRNG with retry; hard failure instead of fixed pattern |
| S32-R6-5 | HIGH | VERIFIED | seekable unlinked temp file replaces blocking pipe |
| S32-R6-6 | HIGH | VERIFIED | guarded `l2a_copy_cstring` replaces unguarded copier |
| S32-R6-7 | MEDIUM | VERIFIED | negative seconds serialized unclamped |
| S32-R6-8 | MEDIUM | PARTIAL | reported scenario fixed; new `SP_O_ASYNC` constant is wrong for SPARC |
| S32-R6-9 | LOW | VERIFIED | `thr_ld` removed |
| S32-R6-10 | LOW | VERIFIED | `AT_PLATFORM` now published (publish option of the fix) |

9 verified, 1 partial, 0 not fixed, 0 regressions.

## Per-item evidence

**S32-R6-1 — VERIFIED.** `src/os/threads_fd.c:63-77`. The first `realloc` result is committed to `thr_fd_used` immediately (line 68) before the second `realloc` (line 69). On second-realloc failure the function returns with `thr_fd_cap` unchanged (line 71), so the published capacity still covers only the initialized prefix. The unzeroed tail of `nu` is never read because the cap did not grow. The old `free(nu)` is gone. No dangling pointer remains.

**S32-R6-2 — VERIFIED.** `src/rt32/stack32.c:170-264` adds file-static owned vectors plus `rt32_dup_strvec` and `rt32_retain_args`. `rt32_stack_setup` calls `rt32_retain_args` at line 390 and sets `ctx->guest_argv`, `ctx->host_envp`, and `ctx->exec_path` to heap copies (lines 259-262). Only pointers previously placed by this code are freed, so the initial `main.c:305-307` process-argv pointers are replaced but never freed. In `src/os/threads_exec.c:166` the staging `path` buffer is borrowed into `ctx->exec_path` only for the `rt32_stack_setup` call at line 167, and the failure path at line 171 is `_exit(127)`, so no dangling borrow survives. `src/rt32/procfs.c:176-195` and `procfs_exe_path` at lines 50-60 now read durable heap strings. The old `ctx->exec_path = NULL` clear after exec is removed, so `/proc/self/exe` no longer falls back to argv.

**S32-R6-3 — VERIFIED.** `src/os/futex.c:266`, `277`, `306`, `323` now pass `(int)op` instead of `(int)(op & 15U)`. The ordinary entry point in `src/os/syscalls_time.c` already passes `(int)op` for both wake and wait. `FUTEX_PRIVATE_FLAG` and `FUTEX_CLOCK_REALTIME` share values on the host, so both paths now derive the same host key.

**S32-R6-4 — VERIFIED.** `src/rt32/stack32.c:120-163` adds `rt32_get_rand`: `getrandom` loop with `EINTR` and short-read handling on Linux, then `/dev/urandom` with the same retry discipline on all hosts, returning failure unless 16 bytes arrive. Line 308-310 turns failure into `-EIO`. The Darwin `if (0)` and the fixed `0xA5 ^ i*17` pattern are gone. `<sys/random.h>` is included at line 28 and the `getrandom` call is inside `#ifdef __linux__`, so Darwin compiles against the fallback only.

**S32-R6-5 — VERIFIED.** `src/rt32/procfs.c:67-98` replaces the pipe with `mkstemp` plus immediate `unlink` (lines 70, 76), writes all content with `EINTR` retry, then `lseek(fd, 0, SEEK_SET)` (line 87). No reader is needed during open. Residual items, not blocking: the path is hardcoded to `/tmp` and open fails with `ENOENT` on a rootfs without it; the descriptor is `O_RDWR`, so a guest can write into its view of `/proc/self/cmdline` where the old pipe read end was read-only; on Linux `memfd_create` would avoid both. These are outside the defect's stated scenario.

**S32-R6-6 — VERIFIED.** `procfs_copy_in` is deleted. `src/rt32/procfs.c:286` calls `l2a_copy_cstring`, which takes `sparc32_vm_access_enter` before the permission check and every byte dereference (`src/os/l2a_access.h:166-175`). Return conventions match the old helper (0, `-EFAULT`, `-ENAMETOOLONG`). The header is included at `procfs.c:18`.

**S32-R6-7 — VERIFIED.** `src/os/syscalls.c:657` in `put_statx_ts` and lines 799, 802, 805 in `sparc32_l2a_statx` now emit `(uint64_t)sec` unconditionally. Pre-epoch timestamps round-trip as two's complement.

**S32-R6-8 — PARTIAL.** The reported scenario is fixed. `src/os/syscalls.c:856-858` strips the access mode and open-time bits before validation, so `fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)` now succeeds on writable descriptors. Two problems remain in the new code:

- `SP_O_ASYNC` is defined as `0x2000U` at line 50 with the comment "FASYNC shares the O_DSYNC bit". On SPARC Linux `FASYNC` is `0x0040`, and `0x2000` is `O_DSYNC`. Consequence: a guest `F_SETFL` carrying `O_DSYNC` sets host `O_ASYNC` (line 865) and also host `O_SYNC`, because the check at line 872 tests `w & SP_O_SYNC` with `SP_O_SYNC = 0x802000`, which is nonzero for `0x2000` alone. A genuine guest `FASYNC` (`0x40`) is still rejected with `-EINVAL` by the mask at line 859. Before the commit `O_DSYNC` returned `-EINVAL`; now it silently maps to the wrong host flags. Practical impact is low because no `F_SETOWN` owner is set, but the constant should be `0x0040U` and `O_DSYNC` should map to host `O_DSYNC`.
- `flags_host_to_guest` (lines 812-827) still reports only access mode, `O_APPEND`, `O_NONBLOCK`, and `O_SYNC`, so `O_ASYNC`, `O_DIRECT`, and `O_NOATIME` are settable but never read back. Pre-existing and minor.

**S32-R6-9 — VERIFIED.** `thr_ld` is deleted from `src/os/threads_exec.c`; `thr_read_vec` calls `l2a_ld_be32` at line 58. `l2a_ld_be32` (`src/os/l2a_access.h:136-150`) performs the same guarded 4-byte load, error propagation, and big-endian conversion.

**S32-R6-10 — VERIFIED.** The commit takes the "publish the entry" branch of the fix. `SPARC_AT_PLATFORM` (15) is defined at `src/rt32/stack32.c:54` and `AUXV_PUT(SPARC_AT_PLATFORM, at_platform_va)` is emitted at line 346, so the pushed `"sparc"` string and its existence check at line 316 are now meaningful. The `auxv[40]` buffer at line 283 holds the 19 pairs (38 words) now emitted, including `AT_NULL`.

## Recommended follow-up

One small fix for S32-R6-8 in `src/os/syscalls.c`: define `SP_O_ASYNC` as `0x0040U`, add it to the allowed set, and map `SP_O_DSYNC` to host `O_DSYNC` separately from `SP_O_SYNC` so the `w & SP_O_SYNC` test does not promote `O_DSYNC`. Optionally extend `flags_host_to_guest` to echo the newly settable bits.
