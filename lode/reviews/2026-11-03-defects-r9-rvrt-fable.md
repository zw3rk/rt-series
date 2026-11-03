Good — `check_range` rejects `len == 0` before `range_unmapped` is ever reached. I have everything needed for the review.

---

## Round-9 Remediation Review: commit `f644ddd`

### RV-R9-1: legacy file mmap misses `INT64_MAX` offset bound — **VERIFIED**

**Defect report:** `mmap_pages` in `memory.c` checked only `size > UINT64_MAX - offset` (unsigned wrap), missing the Linux/mm_view `INT64_MAX` bound. A page-aligned `offset = 0x7FFFFFFFFFFFF000` with `size = 0x1000` would succeed instead of returning error 75 (EOVERFLOW).

**Fix applied** (`src/linux/memory.c:212-214`):
```c
if (file_mapping && (source->space != memory->space ||
                     size > (uint64_t)INT64_MAX ||
                     offset > (uint64_t)INT64_MAX - size))
    return error(75);
```

**Verification:**
- The new check exactly matches the canonical `mm_view.c:438`: `size > INT64_MAX || offset > (uint64_t)INT64_MAX - size`. Both conditions are present and in the correct order.
- The old `size > UINT64_MAX - offset` wrap check is now subsumed: if `size <= INT64_MAX` and `offset <= INT64_MAX - size`, then `offset + size <= INT64_MAX < UINT64_MAX`, so unsigned wrap is impossible. The replacement is strictly tighter. Correct.
- The reproduction case (`offset=0x7FFFFFFFFFFFF000`, `size=0x1000`) hits `offset > INT64_MAX - size` because `INT64_MAX - 0x1000 = 0x7FFFFFFFFFFFE FFF < 0x7FFFFFFFFFFFF000`. Would now return error 75.
- Test added at `test/test_file_backing.c:507-513`: exercises exactly this reproduction case, asserts the error return and no side effects (generation/count unchanged, prior mapping intact).
- `#include <stdint.h>` added to `memory.c:6` — needed for `INT64_MAX`/`UINT64_C` portability; correct.

**No issues found.**

---

### RV-R9-2: vm64 unmapped ranges remain accessible — **VERIFIED**

**Defect report:** `rv_vm64_host` rejected only `BEYOND_EOF` pages, never `UNMAPPED`. After `rv_vm64_unmap`, the backing memory remained accessible through `host`, `copyin`, `copyout`, and `promote_write`.

**Fix applied:**

1. New helper `range_unmapped` (`src/vm/vm64.c:391-399`): iterates pages in `[gva, gva+len)`, returns 1 if any page has state `RV_VM64_PAGE_UNMAPPED` (enum value 0 per `vm64.h:30`).

2. Check inserted in `rv_vm64_host` (`vm64.c:481-482`): after `range_beyond_eof`, before the pointer write. Returns `-EFAULT`.

3. Check inserted in `rv_vm64_promote_write` (`vm64.c:712-713`): same position, same return.

4. `copyin` (line 823) and `copyout` (line 837) both call `rv_vm64_host` first — they inherit the unmapped check transitively. `copyin` additionally calls `promote_write` (line 828) which also checks. All four access paths now reject unmapped ranges.

5. Header doc updated (`vm64.h:49-50`, `vm64.h:77-78`): UNMAPPED ranges documented as returning `-EFAULT`.

6. Test reordering in `test/u5a_vm_provider.c:73-87`: the old `vm-translate` check ran before any mapping existed; with the new unmapped-faults check, it's moved after `vm-map-anon`. This is correct — page 0 starts as `UNMAPPED` (calloc → 0 = `RV_VM64_PAGE_UNMAPPED`), so the pre-mapping translate would now correctly fail.

7. Comprehensive regression test (`test/u5a_vm_provider.c:92-103`): unmap → verify all four paths return `-EFAULT` → remap → verify all paths succeed again. Exercises the full lifecycle.

**Edge case analysis:**
- `len == 0`: guarded by `check_range` (line 58) which rejects `len == 0` with `-EINVAL` before `range_unmapped` is reached. The `gva + len - 1` underflow in `range_unmapped` is unreachable.
- `range_unmapped` mirrors the existing `range_beyond_eof` structure (line 377-385), which has the same `gva + len - 1` pattern and same caller guard. Consistent.
- `RV_VM64_PAGE_UNMAPPED = 0` means `calloc`-initialized arenas start as all-unmapped. The test reordering confirms this is handled correctly.

**No issues found.**

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None found |
| `.c` includes | None found |
| File lengths | `memory.c`: 453, `vm64.c`: 848, `vm64.h`: 99, `test_file_backing.c`: 545, `u5a_vm_provider.c`: 701 — all under 900 |
| Undefined behavior | No new UB paths; all pointer arithmetic stays within arena bounds; casts are well-typed |
| Warning-flag concerns | None — no new implicit conversions, all explicit casts are narrowing-safe |

### Newly Introduced Bugs

None found. The changes are minimal and surgical. Both fixes match the canonical/existing patterns (`mm_view` for R9-1, `range_beyond_eof` for R9-2), and the test reordering in `u5a_vm_provider.c` is necessary and correct.

### Summary

| Item | Verdict | Evidence |
|---|---|---|
| RV-R9-1 | **VERIFIED** | `memory.c:212-214` matches `mm_view.c:438`; test at `test_file_backing.c:507-513` |
| RV-R9-2 | **VERIFIED** | `vm64.c:391-399,481-482,712-713`; copyin/copyout inherit via `host`; test at `u5a_vm_provider.c:92-103` |
| New bugs | None | — |
| C11 compliance | Pass | No VLAs, no `.c` includes, all files ≤ 900 lines |
