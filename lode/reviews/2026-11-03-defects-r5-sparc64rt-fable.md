# Round-5 Post-Remediation Verification — `sparc64rt` @ `d5cac9d`

**Scope:** static read of `git show d5cac9d` plus residual greps. No builds, tests, containers, or QEMU were run. Working tree is clean at `d5cac9d` ("sparc64rt: remediate Round-5 defects (S64-R5-1..9)").

**Result:** 7 VERIFIED, 2 PARTIAL, 0 REGRESSION, 0 NOT FIXED. One new Medium defect was introduced by the S64-R5-3 rewrite (iovec re-read after validation in the write path). Requested regression tests for R5-1, R5-2, R5-3 and R5-5 were not added.

## Summary table

| Item | Severity | Status | Evidence |
|---|---|---|---|
| S64-R5-1 composite open flags | High | **VERIFIED** | `src/os/syscalls_ext.c:123-126`, `:145-158`, `:161` |
| S64-R5-2 `F_SETFL` rejects ordinary flags | Medium | **VERIFIED** | `src/os/syscalls_ext.c:414-463` |
| S64-R5-3 vectored I/O semantics | High | **PARTIAL** | `src/os/syscalls_ext.c:244-351`; new TOCTOU in write staging |
| S64-R5-4 ELF bias wrap | High | **VERIFIED** | `src/os/guest_run.c:85-92`, `:278`, `:319-330`, `:342-346`, `:380-404` |
| S64-R5-5 `statx` pre-epoch timestamps | Medium | **VERIFIED** | `src/os/syscalls_stat.c:262` |
| S64-R5-6 undersized `statx` test buffer | High | **VERIFIED** | `tests/test_h2_syscall.c:100-104`, `:188-198` |
| S64-R5-7 duplicated errno/commit | Medium | **VERIFIED** | `src/os/syscalls_min.h:63,69`; `syscalls_min.c:112,163`; `syscalls_sig.c:45-53` |
| S64-R5-8 unused `rt_sigprocmask` | Low | **PARTIAL** | removed body/decl/mask; `SP_SIG_*` defines remain at `syscalls_ext.c:93-95` |
| S64-R5-9 interp_mem.c overview | Low | **VERIFIED** | `src/interp/interp_mem.c:7-14` |

## Per-item evidence

### S64-R5-1 — VERIFIED
The match predicate changed from any-bit to full-mask equality at `src/os/syscalls_ext.c:161` (`(rest & map[i].guest) == map[i].guest`). `SP_O_TMPFILE` (0x2010000) now leads the table (`:123-125`) ahead of `SP_O_DIRECTORY`, and `SP_O_NDELAY` (0x4004) precedes `SP_O_NONBLOCK` (`:126-131`). The `SYNC`/`DSYNC` block uses full-mask tests with `SYNC` first (`:145-158`). Both reported misdecodes are closed.

Notes, not blockers:
- Lone bit 0x0004 is mapped to host `O_NONBLOCK` (`:127`). On a real Linux/sparc kernel that `FNDELAY` bit is stored but has no VFS effect. This is a conservative divergence, not the reported defect.
- A lone `__O_SYNC` bit (0x800000 without 0x2000) now falls to the table and returns `-EINVAL`; the kernel accepts it as `O_SYNC`. Edge case only.
- No valid-composite or partial-mask rejection test was added (astra's fix asked for both).

### S64-R5-2 — VERIFIED
`src/os/syscalls_ext.c:414-424` strips the access mode and all creation/immutable status bits before translation, so `fcntl(fd, F_SETFL, F_GETFL|O_NONBLOCK)` on an `O_RDWR` descriptor no longer fails. `APPEND`, `NDELAY`/`NONBLOCK`, `ASYNC`, `DIRECT`, `NOATIME` are translated (`:425-459`); `flags_host_to_guest` gained the matching reverse mappings (`:380-394`).

Residual: unknown leftover bits still return `-EINVAL` (`:460-462`), whereas Linux silently masks to `SETFL_MASK`. An `F_GETFL` result on an `O_PATH` descriptor fed back to `F_SETFL` could still fail. The `NONBLOCK` condition at `:429-431` is over-parenthesised but reduces correctly to "0x4000 or 0x0004 set". No round-trip test added; the only coverage is `F_GETFL >= 0` at `tests/test_h2_syscall.c:265`.

### S64-R5-3 — PARTIAL
The reported semantics are fixed: all iovecs are validated up front with aggregate overflow checks (`src/os/syscalls_ext.c:262-281`), a single `write()` (`:311`) or `read()` (`:319`) is issued over one staged buffer, and short reads scatter back with the result equal to bytes delivered (`:328-350`). Pipe atomicity and no-block-on-partial-prefix are restored.

**New Medium defect introduced.** The write staging loop re-reads each iovec entry from guest memory after validation and ignores the read result:

```
src/os/syscalls_ext.c:292-305
    (void)mem->read(mem->context, iov_va + i * 16U, e, sizeof(e));
    base = l2a_get_be64(e);
    len  = l2a_get_be64(e + 8);
    ...
    if (!mem->read(mem->context, base, buf + off, len)) { ... }
    off += len;
```

`buf` was sized from the first pass's `total`. A second guest thread (threads are supported, `src/os/threads.c` has `clone`/`CLONE_VM` paths) can enlarge `len` between validation and staging, so `off + len` exceeds `total` and `mem->read` writes past the heap allocation. If the ignored `mem->read` fails, `e` is used uninitialised. The read-side scatter is safe because `want` is clamped to `got - off` (`:342-344`). Fix: capture the validated `(base, len)` pairs once (1024 × 16 bytes, static array or the same malloc) and reuse them for staging and scatter, as the kernel does with `import_iovec`.

Minor: `malloc(total)` is bounded only by per-entry `l2a_range_ok` and `L2A_IOV_MAX`, so a large `writev` now allocates the full aggregate rather than chunking; `-ENOMEM` replaces a partial transfer in the extreme. The check at `:255-257` is dead given `iovcnt <= 1024`. No multi-vector pipe test was added; `tests/test_h2_syscall.c:145,160` still use a single vector.

### S64-R5-4 — VERIFIED
`add_u64_checked` (`src/os/guest_run.c:85-92`) guards `e_entry + bias` (`:278`), `phoff + phnum*phentsize` (`:319-330`), each per-header `phoff + i*size` (`:342-346`), `p_vaddr + bias`, `p_offset + p_filesz`, `p_vaddr + p_filesz`, `p_vaddr + p_memsz`, and the PHDR-VA derivation (`:380-404`). All failures return `-LOAD_BAD` before any mapping. The `table_bytes / phnum` multiply check is redundant for a 16-bit `e_phnum` but harmless; the `(void)` discards are intentional overflow-only probes.

### S64-R5-5 — VERIFIED
`src/os/syscalls_stat.c:262` now serialises `(uint64_t)sec` directly, preserving two's-complement negative seconds; nanoseconds unchanged at `:263`. No negative-timestamp test added.

### S64-R5-6 — VERIFIED
`tests/test_h2_syscall.c:100-104` declares a 256-byte destination between two u64 canaries; `:188-198` checks return value, both canaries, the `STATX_SIZE` mask bit at offset 0, and `stx_size` at offset 40 against the payload length. Offsets match the Linux `struct statx` layout. The explicit big-endian decode is correct for the BE guest build; if this file is ever compiled as a native LE host oracle the decode would need an endian switch.

### S64-R5-7 — VERIFIED
`sparc64_host_errno_to_guest` and `sparc64_commit_sysret` are declared in `src/os/syscalls_min.h:63,69`, defined in `syscalls_min.c:112,163`, and `syscalls_sig.c` dropped its private 40-line `sig_commit` in favour of the shared helper (`:45-53`). The shared table is a strict superset of the removed one: every code the signal switch had (`EIO`..`EOVERFLOW`, `ENOSYS=90`) is present at `syscalls_min.c:115-147`, plus `ENXIO`, `E2BIG`, `ENOEXEC`, `ECHILD`, `EBUSY`, `EISDIR`, `ELOOP`.

### S64-R5-8 — PARTIAL
Function body, header declaration, header prose, and the `l2a_blocked` static are gone (grep finds no residual). `l2a_put_be64`/`l2a_store_buf` remain in use elsewhere (`:479-481`, `:539-541`, `:667`) so no unused-function warning. However `SP_SIG_BLOCK`/`SP_SIG_UNBLOCK`/`SP_SIG_SETMASK` at `src/os/syscalls_ext.c:93-95` now have zero uses in the file; astra's fix asked for constants used only by this path to be removed. Three dead macros, Low.

### S64-R5-9 — VERIFIED
`src/interp/interp_mem.c:7-14` now distinguishes raw byte transport (`sparc64_mem_read/write`, never trap) from ISA helpers (`sparc64_ld_int/st_int`, FP lanes) that raise V9 alignment traps. The cited names exist at `:88`, `:122`, `:156`, `:196` and the trap sites at `:173`, `:208` match the text.

## Hygiene

**Line limits:** all nine touched files are under 900 lines (largest touched: `guest_run.c` 741, `syscalls_min.c` 698, `syscalls_ext.c` 671). Repository maximum is unchanged at `src/os/threads.c` 895, untouched by this commit.

**Curated C11:** no VLAs (fixed `uint8_t e[16]`, `uint8_t phdr[GUEST_PHDR_SIZE]`), no Annex K, no `sprintf`/`strcpy`/`strcat`, no `_Generic`/`<threads.h>`. `<stdlib.h>` was added for `malloc`/`free`; `SIZE_MAX` comes from the already-included `<stdint.h>`. All `free()` paths are balanced on every exit of `sys_rwvec`. No `x18` or W^X surfaces were touched.

## Follow-ups for the Round-5 closeout

1. **Medium:** cache validated iovec entries in `sys_rwvec` write path (`syscalls_ext.c:292-305`) to close the heap-overflow TOCTOU.
2. **Low:** delete dead `SP_SIG_*` defines at `syscalls_ext.c:93-95`.
3. **Test debt:** add the regression cases astra requested for R5-1 (composite/partial masks), R5-2 (`F_GETFL`→`F_SETFL` round trip on `O_RDWR`), R5-3 (multi-vector pipe `readv`/`writev`), and R5-5 (negative `statx` seconds).
