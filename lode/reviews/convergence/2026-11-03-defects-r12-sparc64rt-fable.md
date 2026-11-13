I have all the evidence I need. Here's the complete review.

---

## Round-12 Remediation Review: `f00c8c2`

### S64-R12-1 — SPARC errno mistranslation: **VERIFIED**

**Evidence:** `syscalls_min.c:149-152`

| errno | Old (generic Linux) | New (SPARC64) | Correct? |
|---|---|---|---|
| `ENAMETOOLONG` | 36 | **63** | Yes |
| `ELOOP` | 40 | **62** | Yes |
| `EOVERFLOW` | 75 | **92** | Yes |

All three values now match the SPARC64 kernel errno table. No regressions.

---

### S64-R12-2 — `clock_gettime` NULL writes guest VA 0: **VERIFIED**

**Evidence:** `syscalls_ext.c:607-608`

Old code checked `l2a_range_ok(0, 16)` which could return 0 (in-range) and fall through to `store_timespec(mem, 0)`. New code unconditionally returns `-EFAULT` when `is_res == 0 && tp_va == 0U`.

Branch analysis confirms all four `(is_res, tp_va)` combinations are correct:
- `clock_gettime(clk, NULL)` → `-EFAULT` (line 608)
- `clock_gettime(clk, valid)` → range-checked, then written (lines 609-612)
- `clock_getres(clk, NULL)` → host call, returns 0 without writing (lines 618-620)
- `clock_getres(clk, valid)` → range-checked, host call, written

---

### S64-R12-3 — `fstatat64` drops validated flags: **VERIFIED**

**Evidence:** `syscalls_stat.c:141-142, 259-271, 284`

`sys_stat_path` signature changed from `int nofollow` to `int host_flags`. The caller `sparc64_l2a_fstatat64` now accumulates `AT_SYMLINK_NOFOLLOW` (line 260), `AT_NO_AUTOMOUNT` (line 264, `#ifdef`-guarded), and `AT_EMPTY_PATH` (line 269, `#ifdef`-guarded) into `host_flags`, and passes the full bitmask through at line 284.

For hosts without `AT_EMPTY_PATH` (macOS), a dedicated `fstat(host_dirfd)` fallback at lines 273-282 handles the empty-path case correctly.

`lstat`/`lstat64` callers now pass `AT_SYMLINK_NOFOLLOW` (lines 207, 228) instead of the old boolean `1`. `stat` passes `0` (line 197). All correct.

---

### S64-R12-4 — Darwin `faccessat2` drops `NOFOLLOW`: **VERIFIED**

**Evidence:** `backend_darwin.c:555-561`

Old code validated `AT_SYMLINK_NOFOLLOW` but passed `0` to the host `faccessat`. New code:
1. Validates that only `RT_LINUX_AT_SYMLINK_NOFOLLOW | RT_LINUX_AT_EACCESS` are set (line 558)
2. Maps both to their Darwin equivalents (`AT_SYMLINK_NOFOLLOW`, `AT_EACCESS`) (lines 559-560)
3. Passes the mapped flags to `faccessat` (line 561)

Also adds `RT_LINUX_AT_EACCESS` (`0x200`) at line 46, which is a correct bonus fix.

Note: `faccessat2` now does its own flag mapping rather than using the shared `darwin_atflag()` at line 48. This is fine — `darwin_atflag` only knows `AT_SYMLINK_NOFOLLOW`, and `faccessat` legitimately supports `AT_EACCESS` in addition.

---

### S64-R12-5 — stat family skips sysroot: **VERIFIED**

**Evidence:** `syscalls_stat.c:160-174`

For absolute paths, `sys_stat_path` now calls `sparc64_interp_resolve(path, getenv("SPARC64RT_SYSROOT"), joined, sizeof(joined))` to prepend the sysroot (line 164), tries `fstatat` on the resolved path (line 166), and falls back to the raw path on `ENOENT`/`ENOTDIR` (line 170). Other errors are returned immediately. This matches the audit's recommended pattern.

New includes for `<stdlib.h>` (for `getenv`) and `os/host_contract_interp.h` (for `sparc64_interp_resolve`) are correct. The `sa_handler`/`sa_sigaction` macro conflicts from macOS `<sys/signal.h>` (pulled by `<stdlib.h>`) are properly `#undef`'d at lines 28-33.

**Minor note:** After `/proc/self/exe` path rewrite (line 153), the exe path (already a host-absolute path) still runs through sysroot resolution. This is harmless — the sysroot-prefixed version will almost certainly ENOENT and fall back — but it's a wasted `fstatat` call per `/proc/self/exe` stat.

---

### S64-R12-6 — non-synthetic `/proc/self/*` falls to host: **PARTIAL**

**Evidence:** `syscalls_ext.c:204-211`, `syscalls_stat.c:145-158`, `guest_proc.c:651-672`

**What's fixed (openat path):** `syscalls_ext.c:208-211` rejects any `/proc/self` or `/proc/self/*` that isn't in the synthetic set with `-ENOENT`. Synthetic paths (exe/maps/cmdline/stat/auxv) are routed to `sparc64_guest_proc_openat`. Correct.

**What's fixed (stat path):** `syscalls_stat.c:148-153` rewrites `/proc/self/exe` to the guest load path. Lines 154-158 reject non-synthetic `/proc/self/*` with `-ENOENT`. Correct for non-synthetic paths.

**Residual gap 1 — stat of synthetic paths leaks host metadata:** For recognized synthetic paths other than `exe` (maps, cmdline, stat, auxv), `sparc64_guest_proc_handles` returns true at line 156, and the code falls through to host `fstatat`. On Linux this stats the host translator's `/proc/self/maps` etc., leaking host file metadata (size, timestamps, inode). On macOS this returns ENOENT (no procfs). Low severity (metadata only, not content) and pragmatically useful (stat+open sequences work), but technically a leak on the Linux target.

**Residual gap 2 — readlinkat not blocked:** `guest_proc.c:651-672` (unchanged by this commit) — `readlinkat` for paths not in the synthetic set (e.g. `/proc/self/fd/3`) falls through to host `readlinkat` at line 660. The `openat` path now blocks these, but `readlinkat` has no equivalent guard. A guest calling `readlink("/proc/self/fd/3")` gets the host translator's fd target, not `-ENOENT`. This is the same class of leak the audit identified.

---

### S64-R12-7 — Darwin `dup3` self-dup diverges: **VERIFIED**

**Evidence:** `proc.c:844-846`

`if (oldfd == newfd) return -EINVAL;` is now placed before the `#if defined(__linux__)` / `#else` split, applying to both platforms. The old Darwin-specific handling (success with `fcntl(F_GETFD)` check) is removed. Linux `dup3` already returns EINVAL for self-dup, but the early check is a correct optimization that saves a syscall.

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None. `joined[L2A_PATH_MAX]` is a compile-time constant. |
| `.c` includes | None found in any changed file. |
| `sprintf`/`strcpy`/`strcat` | None. |
| `_Generic` / Annex K | None. |
| File line counts | `backend_darwin.c` 837, `proc.c` 864, `syscalls_ext.c` 861, `syscalls_min.c` 732, `syscalls_stat.c` 390 — all <= 900. |

---

### Summary

| ID | Verdict | Notes |
|---|---|---|
| S64-R12-1 | **VERIFIED** | All three SPARC64 errno values correct |
| S64-R12-2 | **VERIFIED** | All `(is_res, tp_va)` branches correct |
| S64-R12-3 | **VERIFIED** | Full `host_flags` forwarded; `AT_EMPTY_PATH` fallback on macOS |
| S64-R12-4 | **VERIFIED** | `NOFOLLOW` + `EACCESS` properly mapped and passed |
| S64-R12-5 | **VERIFIED** | Sysroot resolution with ENOENT/ENOTDIR fallback |
| S64-R12-6 | **PARTIAL** | `openat` blocked; stat `exe` rewritten; readlinkat for `/proc/self/fd/*` etc. still leaks to host |
| S64-R12-7 | **VERIFIED** | Early EINVAL on both platforms |

**No regressions or new bugs introduced.** One residual concern: S64-R12-6's `readlinkat` path in `guest_proc.c` (unchanged by this commit) still passes non-synthetic `/proc/self/*` to the host, which should be blocked to match the `openat` and `stat` guards.
