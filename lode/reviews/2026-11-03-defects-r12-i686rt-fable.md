I have all the data needed for the review. Here's the analysis:

---

## Round-12 Remediation Review — commit `bfa270a`

### I686-R12-3 — `execve("/proc/self/exe")` → `exec_path` — **VERIFIED**

**Fix at `src/os/syscalls.c:551-561`:** Inserts a `/proc/self/exe` and own-pid `/proc/<pid>/exe` redirect into `i686_exec_open`, before the sysroot logic, mapping both to `ctx->exec_path`.

Evidence of correctness:
- Exact `/proc/self/exe` match at `:553` via `strcmp`.
- Own-pid form at `:555-559` mirrors `is_own_proc_exe` in `sys_pass_fs.c:247-262` identically: `strncmp(path, "/proc/", 6)`, `strtol(path+6, &end, 10)`, `strcmp(end, "/exe")`, `pid == (long)getpid()`.
- Guard `ctx != NULL && ctx->exec_path != NULL && ctx->exec_path[0] != '\0'` (`:552`) prevents NULL dereference and gracefully falls through to the old path when exec_path is unset.
- Redirected path enters the existing sysroot/plain-open flow, which is correct for guest binaries.
- `strtol` overflow produces `LONG_MAX`/`LONG_MIN`, which can never match `getpid()` — safe without `errno` check.

No issues found.

---

### I686-R12-4 — Darwin `socketpair`/`accept4` flag handling — **VERIFIED**

**Fix at `src/os/backend_darwin_net.c:108-119` (socketpair) and `:165-173` (accept4):** Applies `SOCK_CLOEXEC` (`02000000` octal = `0x80000`) and `SOCK_NONBLOCK` (`04000` octal = `0x800`) via `fcntl` after the syscall succeeds, mirroring `rt_host_socket` at `:87-100`.

Evidence of correctness:
- `socketpair`: Both `sv[0]` and `sv[1]` receive both flags — correct, both ends need them.
- `accept4`: The `(void)linux_flags;` suppressor is removed (`:152` old), `linux_flags` is now used at `:167,170` — clean removal, no dangling reference.
- `SOCK_CLOEXEC` applied via `F_SETFD, FD_CLOEXEC` (`:111-112, 168`) — correct (cloexec is a descriptor flag, not a status flag).
- `SOCK_NONBLOCK` applied via `F_GETFL` then `F_SETFL | O_NONBLOCK` (`:115-118, 171-172`) — actually more defensive than the original `rt_host_socket` at `:97` which sets `O_NONBLOCK` directly without preserving existing flags. Not a bug (freshly-created sockets have no flags), just a style note; the new code is better practice.

No issues found.

---

### I686-R12-5 — Non-canonical `/proc` path canonicalization — **PARTIAL**

**Fix at `src/os/proc.c:250-297`:** New `canon_proc_leaf` function canonicalizes the leaf returned by `skip_proc_prefix` before matching. `i686_proc_open_at` (`:299-345`) now compares against `canon` instead of raw `leaf`.

What works:
- `//` collapse: The `while (*p == '/') { p++; }` loop at `:269-271` skips all consecutive slashes.
- `/./` removal: `if (len == 1U && p[0] == '.') { ... continue; }` at `:280-283` drops `.` segments.
- Trailing `/` stripped implicitly (no trailing separator emitted).
- The old nested `strncmp(leaf, "self/", 5)` + manual `sub` skipping is replaced by flat `strcmp(canon, "self/maps")` etc. — cleaner and correct.

**Gap 1: `/../` traversal not handled.** The report explicitly recommended "reject or normalize `/../` so `"self/../self/maps"` cannot escape the virtual set." The `..` segment has `len == 2`, not `len == 1`, so it passes the `.`-only check and is kept verbatim. Trace:

- Guest opens `"/proc/self/../self/maps"`
- `skip_proc_prefix` → leaf `"self/../self/maps"`
- `canon_proc_leaf` → `"self/../self/maps"` (`..` is not `.`, so kept)
- No `strcmp` match → returns `I686_PROC_NOT_MATCHED`
- Caller at `sys_pass_fs.c:189` falls through to `open_guest(ctx, path, ...)` → host kernel resolves `..` → **host `/proc/self/maps` leaked**

This is the same class of ASLR/information-disclosure issue the report flagged.

**Gap 2: Off-by-one buffer overflow in `canon_proc_leaf`.** The bounds check at `proc.c:284` is:

```c
if ((!first && o + 1U >= cap) || o + len >= cap) {
```

For the non-first case, this checks `o + len >= cap` but the function writes a separator (1 byte) **plus** the segment (`len` bytes), then `out[o] = '\0'` after the loop. The combined space needed is `o + 1 + len + 1` (position + separator + segment + NUL), but the check only ensures `o + len < cap`.

Concrete trace with `cap = 64` (the actual call at `:302`):

| Step | Segment | len | o before | Check | o after |
|------|---------|-----|----------|-------|---------|
| 1 (first) | `"self"` | 4 | 0 | `0+4>=64` → false | 4 |
| 2 | 59-char segment | 59 | 4 | `(4+1>=64)∥(4+59>=64)` = `false∥false` | 4+1+59 = **64** |

After loop: `out[64] = '\0'` — **1-byte stack buffer overflow** (valid indices are 0–63). A guest binary can craft a `/proc/` path of the right length to trigger this. The correct check for the non-first case should be `o + 1U + len >= cap`:

```c
if ((!first && o + 1U + len >= cap) || (first && o + len >= cap)) {
```

---

### Curated C11 compliance

- **No VLAs** in any changed file.
- **No `.c` includes** in any changed file.
- **Line counts:** `syscalls.c` = 900, `backend_darwin_net.c` = 655, `proc.c` = 346 — all ≤ 900.
- Standard C11/POSIX API usage throughout (`strcmp`, `strtol`, `memcpy`, `fcntl`, etc.).

---

### Summary

| Item | Verdict | Evidence |
|------|---------|----------|
| I686-R12-3 | **VERIFIED** | `syscalls.c:551-561` — correct redirect, mirrors `is_own_proc_exe` |
| I686-R12-4 | **VERIFIED** | `backend_darwin_net.c:108-119,165-173` — correct `fcntl` flag application |
| I686-R12-5 | **PARTIAL** | `proc.c:250-345` — `//` and `/./` fixed; `/../` traversal still leaks host `/proc`; off-by-one overflow in bounds check at `:284` |

**Newly introduced bugs: 1** — `canon_proc_leaf` off-by-one at `proc.c:284` allows a 1-byte NUL write past the 64-byte stack buffer `canon`. Fix: change `o + len >= cap` to `o + 1U + len >= cap` in the non-first branch.
