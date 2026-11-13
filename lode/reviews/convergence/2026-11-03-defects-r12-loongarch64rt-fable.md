That's just a comment, not a violation. Here's the full review.

---

## Round-12 Remediation Review — Commit `83baf28`

Three files changed, +34/−6 lines. All three items addressed.

---

### LA64-R12-1 — Darwin errno mistranslation — **VERIFIED**

**Defect**: `neg_errno()` only mapped `ENOSYS`/`EAGAIN`; Darwin errnos 62 (`ELOOP`), 63 (`ENAMETOOLONG`), 66 (`ENOTEMPTY`) reached the guest raw.

**Fix at `src/os/syscalls_priv.h:105-110`**: Three new `if` branches in the `#else` (non-Linux) path:
- `e == 62 → -40` (Darwin `ELOOP` → Linux `ELOOP`)
- `e == 63 → -36` (Darwin `ENAMETOOLONG` → Linux `ENAMETOOLONG`)
- `e == 66 → -39` (Darwin `ENOTEMPTY` → Linux `ENOTEMPTY`)

**Evidence**: Guest values confirmed against in-repo constants — `LA64_ENAMETOOLONG` is 36 (`src/os/syscalls.h:36`), `LA64_ELOOP_PROC` is 40 (`src/os/proc.c:29`). Guest `ENOTEMPTY` 39 matches Linux `asm-generic/errno.h`. Darwin host values 62/63/66 match macOS `sys/errno.h`.

**Style note**: Uses raw integer literals instead of `ELOOP`/`ENAMETOOLONG`/`ENOTEMPTY` macros (available via `<errno.h>`) on the host side and `LA64_ENAMETOOLONG`/`LA64_ELOOP_PROC` on the guest side. The existing entries use symbolic `ENOSYS`/`EAGAIN`. Not a bug, but inconsistent — the symbolic forms would be self-documenting and portable across BSD-derived hosts.

---

### LA64-R12-2 — `waitid` options passed raw to Darwin host — **VERIFIED**

**Defect**: Guest Linux `waitid` option flags were passed directly to the Darwin host call, where `WSTOPPED`, `WCONTINUED`, and `WNOWAIT` have different bit positions.

**Fix at `src/os/minsys.c:583-598`**: New `#if !defined(__linux__)` block translates guest flags to host flags before the call:

| Guest (Linux) | Host (Darwin) | Flag |
|---|---|---|
| `0x01` | `0x01` | `WNOHANG` (same) |
| `0x04` | `0x04` | `WEXITED` (same) |
| `0x02` | `0x08` | `WSTOPPED` |
| `0x08` | `0x10` | `WCONTINUED` |
| `0x1000000` | `0x20` | `WNOWAIT` |

**Evidence**: Translation applied to `host_options` (line 580), which replaces `options` in the `waitid()` call at line 611. Values match the audit's cross-reference of Linux `wait.h` vs Darwin `sys/wait.h`. Unknown guest bits are silently dropped (built from zero), which is correct — unrecognized bits would cause `EINVAL` on either platform.

No bugs introduced. The `(int)host_options` cast at line 611 is safe since the maximum translated value is `0x3D` (all five flags set).

---

### LA64-R12-3 — Synthetic `/proc` fds drop `O_CLOEXEC` — **VERIFIED**

**Defect**: `la64_proc_open` reopened the synthetic tempfile with `open(O_RDONLY)` and never applied `FD_CLOEXEC`, even when the guest passed `O_CLOEXEC`.

**Fix at `src/os/proc.c:332-333`**:
```c
if ((flags & 0x80000U) != 0U)
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
```

**Evidence**: `0x80000` matches `LA64_O_CLOEXEC` defined at `src/os/minsys.c:122`. `<fcntl.h>` is included at `src/os/proc.c:19`, providing `fcntl`, `F_SETFD`, `FD_CLOEXEC`. The call is placed after the `fd < 0` guard (line 330-331), so `fd` is always valid. `(void)` suppresses the unused-return warning; `F_SETFD` on a valid fd doesn't fail in practice.

**Style note**: Uses raw `0x80000U` instead of `LA64_O_CLOEXEC` — that constant is local to `minsys.c` and not visible in `proc.c`. Either hoisting the define to a shared header or using the raw value (as done) is acceptable; a comment referencing the constant name would help.

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| No VLAs | Pass — no variable-length arrays in diff |
| No `.c` includes | Pass — no `#include "*.c"` |
| No `sprintf`/`strcpy`/`strcat` | Pass |
| No `_Generic` / `<threads.h>` / Annex K | Pass |
| File size ≤ 900 lines | Pass — `syscalls_priv.h`: 297, `minsys.c`: 816, `proc.c`: 357 |

### Newly Introduced Bugs

None found. The three changes are all guarded by appropriate conditionals, use correct types, and don't alter control flow for any existing code path.

---

### Summary

All three items **VERIFIED**. No regressions, no C11 violations, all files within line limits. Two minor style observations (magic numbers in R12-1 and R12-3) are non-blocking.
