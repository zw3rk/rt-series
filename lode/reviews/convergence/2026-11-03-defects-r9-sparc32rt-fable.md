All context gathered. Here's the complete review:

---

## Round-9 (0fdcb4c) Static Review: S32-R9-1..8

### S32-R9-1 — Checked-copy fail-open when prot table is NULL
**VERIFIED** | `src/os/l2a_access.h:71`

`return 0` changed to `return -EFAULT`. Exact fix as prescribed — fail closed when `sparc32_vm_prot_base()` returns NULL, preventing host SIGSEGV on unmapped pages.

### S32-R9-2 — `copy_str` 32-bit wrap returns wrong errno
**VERIFIED** | `src/os/l2a_access.h:176`

`return -ENAMETOOLONG` changed to `return -EFAULT` on 32-bit address wrap in `l2a_copy_cstring`. Exact fix as prescribed.

### S32-R9-3 — File-tracking entry leaked on VMA-record ENOMEM
**VERIFIED** | `src/rt32/vm_mmap.c:229-230`

`vm_file_unregister_range(target_va, (uint32_t)aligned_len)` inserted before the PROT_NONE teardown in the `rec_rc != 0` error path. Prevents g_inodes[] leak. Exact fix as prescribed.

### S32-R9-4 — Apple-only file tail beyond EOF made PROT_NONE instead of zero-filled
**VERIFIED** | `src/rt32/vm_mmap.c:258-271`

Tail handling rewritten: publishes with `prot` (not 0), keeps `vm_mprotect_regions_locked` with `prot & 0x7U`, and conditionally zeroes only MAP_PRIVATE writable tails. Read-only tails rely on kernel zero-fill (correct POSIX behavior). The guard `(host_flags & MAP_SHARED) == 0 && (prot & 0x2U) != 0U` prevents SIGSEGV (read-only host page) and SIGBUS (shared page past EOF).

### S32-R9-5 — madvise / msync / mincore unimplemented
**PARTIAL** | `src/os/syscalls_min.c:336-378,650-655` + `src/os/backend_darwin.c:500-545`

`sys_madvise` and `sys_msync` added with dispatch arms at lines 650-655. Validation: page-alignment, advice range, guest-range bounds check. DONTNEED(4) zeroes writable pages via `guest_range_ok_prot(addr, len, 2U)` and calls `vm_invalidate_jit`. Darwin backend translates Linux MS_SYNC(4)->Darwin MS_SYNC(0x10).

**mincore (NR 78) is named in the defect but not implemented** — still falls through to the default `ret = -ENOSYS`.

One subtle new concern: `sys_madvise` DONTNEED zeroes writable guest pages then forwards to `rt_host_madvise`. On Darwin, host `MADV_DONTNEED` is advisory-only, so for MAP_PRIVATE file-backed pages the zeroing sticks — guest sees zeros instead of file content restoration. This is a minor semantic divergence from Linux (where host MADV_DONTNEED restores file content). Not a regression from the prior ENOSYS, but worth noting for future oracle-matching.

### S32-R9-6 — Initial-stack argc/envc silently truncated at 511
**VERIFIED** | `src/rt32/stack32.c:109-111`

`if (count == 511 && strs[511] != NULL) return -1;` inserted after the counting loop. Caller at line 323 propagates as loader failure (returns -1 from `rt32_stack_setup`). The defect suggested `-E2BIG` specifically, but the return type is `int` and the caller only checks `!= 0` — the critical behavior fix (reject rather than silently truncate) is correct.

### S32-R9-7 — Missing p_offset / p_vaddr congruence check
**VERIFIED** | `src/rt32/elf32.c:383-389`

`(ph->p_offset & 0xFFFU) != (ph->p_vaddr & 0xFFFU)` → `return -ENOEXEC` added in the per-segment validation loop, with diagnostic `fprintf` in commit mode. Test coverage added in `tests/test_elf_overlap.c`:
- Case E (line 253): incongruent `p_offset=0x1, p_vaddr=0x10000` → expects `-ENOEXEC`
- Case F (line 264): congruent `p_offset=0x1001, p_vaddr=0x11001` → expects `0`

### S32-R9-8 — File shrink does not invalidate translated code
**VERIFIED** | `src/vm/vm_file.c:158`

`vm_invalidate_jit(NULL, glo, ghi)` inserted immediately after the page-revert loop in `vmf_shrink_entry`. Exact fix as prescribed, matching the invalidation pattern used by every other VMA mutation path.

---

## Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None in changed files |
| `.c` includes | None in changed files |
| `sprintf`/`strcpy`/`strcat` | None in changed files |
| File line limits (<=900) | All pass: `syscalls_min.c` 898, `elf32.c` 768, `vm_mmap.c` 740, `backend_darwin.c` 613, `stack32.c` 406, `test_elf_overlap.c` 286, `vm_file.c` 280, `l2a_access.h` 194 |

## Summary

| ID | Verdict | Notes |
|---|---|---|
| S32-R9-1 | **VERIFIED** | Exact fix |
| S32-R9-2 | **VERIFIED** | Exact fix |
| S32-R9-3 | **VERIFIED** | Exact fix |
| S32-R9-4 | **VERIFIED** | Correct semantics; read-only tails rely on kernel zero-fill |
| S32-R9-5 | **PARTIAL** | madvise + msync implemented; **mincore still ENOSYS**; minor Darwin DONTNEED semantic gap for file-backed private pages |
| S32-R9-6 | **VERIFIED** | Truncation detected; error code is generic -1 not E2BIG |
| S32-R9-7 | **VERIFIED** | Exact fix + test coverage (cases E, F) |
| S32-R9-8 | **VERIFIED** | Exact fix |

**No regressions introduced.** No new C11 violations. `syscalls_min.c` at 898 lines is close to the 900-line limit — one more dispatch arm will require a split.
