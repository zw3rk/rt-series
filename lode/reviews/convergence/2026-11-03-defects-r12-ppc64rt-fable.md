All evidence collected. Here's the review:

---

## Round-12 Remediation Review — commit `ec20e87`

### P64-R12-1 — `ENOSYS` mistranslated to `EOPNOTSUPP`: **VERIFIED**

| Detail | Evidence |
|--------|----------|
| Defect | `x_errno_map` entry `{ ENOSYS, 95 }` mapped host `ENOSYS` → guest `95` (`EOPNOTSUPP`) instead of `38` (`ENOSYS`) |
| Fix | `syscalls_conv.c:52` — changed literal `95` → `38` |
| Correctness | Line 44 defines `XENOSYS = 38` and `XEOPNOTSUPP = 95`, confirming the old value was wrong and the new value matches the named constant |
| Scope | One-line constant fix; no control-flow or contract change |

### P64-R12-2 — `getdents64` error folding: **VERIFIED**

| Detail | Evidence |
|--------|----------|
| Defect | `err == EBADF ? SYSCALL_EBADF : SYSCALL_EIO` folded all non-`EBADF` errors (e.g. `ENOTDIR`, `EINVAL`, `EFAULT`) to `EIO` |
| Fix | `syscalls_misc.c:197` — replaced with `syscall_host_to_linux(err)` |
| Return contract | `syscall_host_to_linux` (line 64) returns a positive Linux errno. Caller at `syscalls.c:740` propagates nonzero `rc` to `ppc64_syscall_apply_return` (`syscalls.h:101`), which expects exactly that — `+errno` for `sc`, `-errno` for `scv`. Contract preserved. |
| Linux (production) | `#ifdef __linux__` path is identity (`return err`), so `ENOTDIR=20`, `EINVAL=22`, `EFAULT=14`, `EBADF=9` all pass through faithfully |
| EINTR safety | `EINTR` is caught by the `continue` at line 193-194 *before* reaching line 197 — never enters `syscall_host_to_linux` |
| Scope | One-line substitution; no new branches, allocations, or side effects |

### Newly introduced bugs: **None**

Both changes are single-constant or single-call substitutions with no control-flow changes. Return-value contracts are preserved.

### Pre-existing gap (not a regression)

`syscall_host_to_linux`'s non-Linux (`#else`) switch (lines 69-121) lacks cases for `ENOTDIR`, `EISDIR`, `ENFILE`, `EMFILE`, `ELOOP`, `EOVERFLOW`, etc. — all of which *are* in `x_errno_map` in `syscalls_conv.c`. On the production Linux path this is moot (identity function). On the Darwin testing path, those unmapped errnos still fold to `EIO` via the `default` case. This predates the commit and is not introduced by it.

### Curated C11 compliance

| Check | Result |
|-------|--------|
| VLAs | None in changed files |
| `.c` includes | None in changed files |
| Line counts | `syscalls_conv.c`: 778, `syscalls_misc.c`: 259 — both <= 900 |
