All evidence collected. Here is the review:

---

## Round-12 Remediation Review — commit `d521faf`

### M32-R12-1 — `F_GETFL` loses `O_SYNC` — **VERIFIED**

**Defect**: `host_to_mips_flags()` tested `(host & O_DSYNC) != 0`, which matched when `O_SYNC` was set (since Linux `O_SYNC` = `__O_SYNC | O_DSYNC`), so an `O_SYNC` fd incorrectly reported `MIPS_O_DSYNC (0x10)` instead of `MIPS_O_SYNC (0x4010)`.

**Fix** at `syscalls_meta.c:62-66`:
```c
if ((host & O_SYNC) == O_SYNC) {
    mips |= MIPS_O_SYNC;
} else if ((host & O_DSYNC) != 0) {
    mips |= MIPS_O_DSYNC;
}
```

- Uses exact multi-bit mask test `== O_SYNC` (not `!= 0`), so all bits of `O_SYNC` must be present before the `MIPS_O_SYNC` branch fires.
- Falls through to `O_DSYNC` only when the host has `O_DSYNC` alone (without `__O_SYNC`).
- Matches the report's prescribed fix verbatim.
- Forward direction (`syscalls.c:197,221`) was already correct — `MIPS_O_DSYNC` and `MIPS___O_SYNC` are tested independently; passing `MIPS_O_SYNC (0x4010)` sets both `O_DSYNC` and `O_SYNC` on the host, which is idempotent.

No new bugs introduced.

---

### M32-R12-2 — sysroot bypass when `dirfd != AT_FDCWD` — **VERIFIED**

**Defect**: `mips_sysroot_open()` rejected calls where `dirfd != MIPS_AT_FDCWD`, but the function already requires `path[0] == '/'` (absolute). Per `openat(2)`, `dirfd` is ignored for absolute paths, so the check was dead logic that broke absolute `openat` with a non-`AT_FDCWD` descriptor.

**Fix** at `vm_file.c:203-206`:
```c
(void)dirfd; /* openat(2): dirfd is ignored for absolute paths. */
if (ctx == NULL || path == NULL || path[0] != '/' ||
    ctx->sysroot == NULL || ctx->sysroot[0] == '\0') {
    return -1;
}
```

- Removes the `dirfd != (int)MIPS_AT_FDCWD` clause.
- `(void)dirfd` suppresses the unused-parameter warning required under `-Wall -Wextra -Werror`.
- Function signature retains `dirfd` for API stability; the single caller (`syscalls.c:323`) continues to compile unchanged.
- The `path[0] != '/'` guard remains, so only absolute paths route through sysroot — correct.

No new bugs introduced.

---

### Curated C11 & File-Size Compliance

| Check | Result |
|---|---|
| No `.c` includes | Clean (grep: no hits) |
| No VLAs, `sprintf`, `strcpy`, `strcat`, `_Generic` | Clean (0 matches in both files) |
| `syscalls_meta.c` line count | **850** (limit 900) |
| `vm_file.c` line count | **220** (limit 900) |

---

### Summary

Both items **VERIFIED** with exact-match fixes to the prescribed remediation. No regressions, no Curated C11 violations, both files within the 900-line limit.
