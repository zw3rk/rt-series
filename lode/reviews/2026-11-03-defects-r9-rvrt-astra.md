Found 2 demonstrable defects. Other in-scope paths showed no demonstrable defect.

| ID | Area | Effect |
|---|---|---|
| RV-R9-1 | file mmap offset | accepts huge offset |
| RV-R9-2 | vm64 unmapped access | permits freed range |

### RV-R9-1: legacy file mmap misses `INT64_MAX` offset bound

Location: [memory.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/memory.c:209) checks only `size > UINT64_MAX - offset`.

Canonical [mm_view.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/mm_view.c:438) correctly rejects `size > INT64_MAX || offset > INT64_MAX - size` with `EOVERFLOW`.

Reproduction: legacy `rv_linux_mmap_source` with page-aligned `offset = 0x7FFFFFFFFFFFF000`, `size = 0x1000` succeeds instead of returning `-75`.

Fix: add the same `INT64_MAX` check before placement, matching the canonical path.

### RV-R9-2: `vm64` unmapped ranges remain accessible

Locations: [vm64.c host](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:457), [vm64.c copyin/out](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:799), [vm64.c write check](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:363), [vm64.c promote](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:690).

`rv_vm64_host` rejects only `BEYOND_EOF`, never `UNMAPPED`. `vma_write_ok` explicitly allows no-VMA ranges as writable.

Reproduction: `rv_vm64_map_anon(0x1000,0x1000)`, `rv_vm64_unmap(0x1000,0x1000)`, then `rv_vm64_host(0x1000,1)` and `rv_vm64_copyin(0x1000,...)` both succeed instead of `-EFAULT`.

Fix: check `states[page] == RV_VM64_PAGE_UNMAPPED` in `rv_vm64_host` and `rv_vm64_promote_write`, so `copyin`/`copyout` fault through `host`.

