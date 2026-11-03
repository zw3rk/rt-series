I now have complete evidence for all 13 items. Here's the full review.

---

## Round-9 Remediation Review: Commit `0231928`

### Curated C11 Compliance

| Check | Result |
|-------|--------|
| All files <= 900 lines | **PASS** — max is `vm_file.c` at 882 |
| No VLAs | **PASS** |
| No `.c` includes | **PASS** |
| No `sprintf`/`strcpy`/`strcat` | **PASS** |
| No `_Generic` | **PASS** |
| `-std=c11 -pedantic -Wall -Wextra -Werror` | Not run (static review only) |

### Per-Item Verdicts

---

**P64-R9-1 — Same-page `brk()` shrink skips invalidation** — **VERIFIED**

`src/os/syscalls_mm.c:577-595`: The `new_end == old_end` branch now detects the shrink direction (`addr < prev`), acquires the quiesce lock, zeros revoked bytes via `syscall_brk_zero`, and calls `ppc64_vm_quiesce_commit(self_vm, self_cpu, addr, prev - addr)` which retires TLB/DBT over the exact revoked range. Growth within the same page correctly takes the no-op path (line 594).

---

**P64-R9-2 — `brk()` shrink never discards bytes** — **VERIFIED**

`src/os/syscalls_mm.c:537-559`: New `syscall_brk_zero()` walks `[start, end)` page-by-page, zeroing only materialized host pages (`ppc64_vm_page_host` returns NULL for absent pages — they already read as zero). Called in both:
- Same-page shrink: line 588 `syscall_brk_zero(self_vm, addr, prev)`
- Cross-page shrink: line 611 `syscall_brk_zero(self_vm, addr, prev)`

Both run under the quiesce lock. The `quiesce_commit` range was also corrected from `[new_end, old_end)` to `[addr, prev)` (byte-granular, not page-granular), matching the actual zeroed region.

---

**P64-R9-3 — MAP_SHARED write past EOF in partial tail page succeeds** — **VERIFIED**

Three insertion points:
1. `src/vm/vm_file.c:770-808`: New `ppc64_vm_file_shared_past_eof()` — byte-precise check that tests each page's file offset against the inode size for shared mappings.
2. `src/vm/vm64.c:172-176`: `vm_validate()` now rejects writes when `ppc64_vm_file_shared_past_eof(addr, size)` is true. This covers `vm_mem_write` AND `vm_mem_atomic` (which calls `vm_validate` at `vm_atomic.c:324-327`).
3. `src/vm/vm64.c:625-630`: `ppc64_vm_tlb_miss()` also gates store TLB fills against `shared_past_eof`, so the fast path can't bypass the check.
4. `src/vm/vm_file.c:811-822`: `ppc64_vm_file_signal_for()` returns SIGBUS (7) for shared partial tails, so the fault handler reports the right signal.

Private partial-tail writes pass through (`shared` flag is checked).

---

**P64-R9-4 — Shared-write sibling propagation retires no DBT code** — **VERIFIED**

`src/vm/vm_file.c:809`: After the sibling `memcpy`, `ppc64_vm_quiesce_invalidate_all(sgva, n)` retires translated code at the alias VA. The sibling loop at line 791 correctly skips `sib == src` (the primary mapping), so only alias VAs are invalidated here. The primary mapping's DBT retirement happens in `vm_mem_write` via `ppc64_dbt_has_code` + `ppc64_dbt_reset()` at `vm64.c:298-300`.

---

**P64-R9-5 — Sibling shared write does not clear LWARX/LDARX reservations** — **VERIFIED**

`src/vm/vm_file.c:810`: `ppc64_vm_reserve_note_store(vm, sgva, n)` clears reservations at the sibling alias VA. The primary reservation is already cleared by `vm_mem_write` at `vm64.c:302` (pre-existing code: `ppc64_vm_reserve_note_store(vm, address, (uint64_t)size)`).

---

**P64-R9-6 — Raw-fill mutation paths bypass reservation epoch** — **VERIFIED**

Three call sites patched:
1. `src/os/syscalls_mm_map.c:102`: `ppc64_vm_reserve_note_store(vm, at, size)` in `mm_fill_staged` after the vm-path fill loop. Covers anonymous zeroing (line 335), file population (line 389), and mremap copy (line 684) — all callers of `mm_fill_staged`.
2. `src/vm/vm_file_size.c:74-76`: `ppc64_vm_reserve_note_store(vm, ...)` in `vm_file_refill_span` after `ppc64_vm_write_raw`.
3. `src/vm/vm_file_mremap.c:109-111`: `ppc64_vm_reserve_note_store(vm, page, sizeof(buf))` in `vm_file_fill_tail` after the tail fill.

The `mem->write` fallback (non-VM path, `mm_fill_staged:107-114`) is exempt per the defect spec: "loader-time fills before first execution are exempt."

---

**P64-R9-7 — `read()` consumes host bytes before guest validation** — **VERIFIED**

`src/os/syscalls.c:562-563`: `ppc64_syscall_access_ok(buf, count, PPC64_MEM_WRITE)` now runs before the host `read` at line 572. Returns `SYSCALL_EFAULT` without consuming any pipe/socket data. Single-threaded runner → no TOCTOU.

---

**P64-R9-8 — `getdents64` advances directory offset before guest validation** — **VERIFIED**

`src/os/syscalls_misc.c:181-183`: `ppc64_syscall_access_ok(buf, count, PPC64_MEM_WRITE)` now runs before `mm_host_getdents` (line 192). Same shape as P64-R9-7. The `#include "os/syscalls.h"` was also added at line 29 to make the `ppc64_syscall_access_ok` declaration visible.

---

**P64-R9-9 — Auxv omits AT_DCACHEBSIZE/AT_ICACHEBSIZE** — **VERIFIED**

Updated in both auxv-emission paths:
- **Stack auxv** (`src/run/load.c`): `AT_DCACHEBSIZE`, `AT_ICACHEBSIZE`, `AT_UCACHEBSIZE` added to `atags[]` (line 529), values set to 128 (lines 571-573), `need` calculation updated to `21u * 16u + 8u` (line 584), loop bound to `i < 21` (line 606).
- **`/proc/self/auxv`** (`src/os/procfs.c`): Array sizes bumped to 21 (lines 289-290), keys/values for the three cache tags added (lines 330-335), NULL terminator shifted to index 20, loop bound to `i < 21` (line 339).
- **Enum definitions**: `run.h:38-39` and `procfs.c:27-29` both define the correct AT_ values (19, 20, 21).
- **Header oracle note** (`procfs.h:157-158`): Updated to document the new tags and the 336-byte total.

---

**P64-R9-10 — Interpreter load: unchecked bias wrap + collision** — **VERIFIED**

Four insertion points:
1. `src/run/load.c:260-261`: `run_map_loads` now checks `raw_va > UINT64_MAX - bias` before computing `vaddr = raw_va + bias`.
2. `src/run/load.c:326-364`: New `run_span_collides()` — walks the interpreter's PT_LOAD segments at the proposed bias and tests overlap against `[lo, hi)`, with wrap checks.
3. `src/run/load.c:449`: `run_span_collides(ldimg, ldlen, RUN_LD_BASE, lo, hi)` rejects the interpreter before mapping if any span overlaps the main image.
4. `src/run/load.c:458-462`: `ld_entry > UINT64_MAX - RUN_LD_BASE` check before computing `out->entry = RUN_LD_BASE + ld_entry`.

---

**P64-R9-11 — `mremap` over mixed-prot wrongly fails ENOMEM** — **VERIFIED**

`src/os/syscalls_mm_map.c:561-581` + `633-713`:
- Replaced `syscall_vma_uniform_attr` with `syscall_vma_cover_spans()` (new function at `syscalls_mm.c:722-749`) which collects clipped VMA spans preserving per-span `prot`/`heap`.
- Source coverage is verified by contiguity check (lines 575-580).
- Copy, insert, and protect all loop per-span (lines 633-671, 688-713), preserving each source span's attributes at the destination.
- Grown tail inherits the last source span's attributes (lines 499-505, 709-712).
- `syscall_vma_free_count()` pre-check (lines 597-600) prevents mid-transaction VMA table exhaustion.

---

**P64-R9-12 — `MADV_DONTNEED` is a no-op** — **VERIFIED**

`src/os/syscalls_access.c:306-199` (rewritten `syscall_madvise`):
- Signature expanded to include `cpu`, `mem`, `ctx` — forwarded through `syscall_extra_dispatch` (`syscalls_conv.c:762`, `syscalls.c:101-103`).
- Non-DONTNEED advice returns success at line 169-172 (validated no-op).
- For advice 4: acquires quiesce lock (line 174), calls `ppc64_vm_file_dontneed()` (line 177) or zeros via `mem->write` for non-VM paths (lines 182-194), then `ppc64_vm_quiesce_commit(vm, cpu, addr, len)` (line 196) retires TLB/DBT.
- New `ppc64_vm_file_dontneed()` (`src/vm/vm_file_size.c:532-611`): anonymous pages are zeroed; file-backed pages are refilled from the retained host descriptor via `pread`; full-page private refills reset COW from `DIRTY` to `CLEAN`. Shared pages are refilled from the same file data they already hold (effectively a no-op for content, but COW state stays consistent).

---

**P64-R9-13 — `proc_read_string` wrap-around splice** — **VERIFIED**

`src/os/proc.c:307-308`: `if (max_len > UINT64_MAX - addr) return PROC_EFAULT;` immediately after the `max_len == 0` check. This prevents the byte-wise fallback (which reads `addr + off + i`) from wrapping around 2^64 and splicing bytes from low mapped memory.

---

### Newly Introduced Bugs

**None found.** Specific checks:

1. `syscall_brk_zero` page loop handles the last-page wrap correctly: when `base + SYSCALL_PAGE_SIZE` wraps to 0, the `hi < lo` guard sets `hi = end` and the break condition triggers.

2. `ppc64_vm_file_shared_past_eof` correctly handles the `fo >= size` (at EOF) and `fo + span > size` (crossing EOF) cases. Private mappings are correctly excluded by `map->shared` check.

3. The mremap per-span insert/protect paths maintain the `done < copy_bytes` invariant. When `nspans == 0` the function returns `ENOMEM` before reaching the span loops. The `spans[nspans - 1u]` access for the grown tail is safe.

4. `ppc64_vm_quiesce_abort(NULL)` is called in the `syscall_madvise` non-VM fallback error path — this is safe since `quiesce_begin(NULL)` returns 0 (no-op), and `quiesce_abort(NULL)` is similarly a no-op.

5. Two `SYSCALL_VMA_SNAP_MAX`-sized stack arrays in `syscall_mm_mremap` total ~6 KB — within normal stack limits.

### Summary

| Item | Verdict |
|------|---------|
| P64-R9-1 | **VERIFIED** — `syscalls_mm.c:577-595` |
| P64-R9-2 | **VERIFIED** — `syscalls_mm.c:537-559,588,611` |
| P64-R9-3 | **VERIFIED** — `vm_file.c:770-808`, `vm64.c:172-176,625-630` |
| P64-R9-4 | **VERIFIED** — `vm_file.c:809` |
| P64-R9-5 | **VERIFIED** — `vm_file.c:810` |
| P64-R9-6 | **VERIFIED** — `syscalls_mm_map.c:102`, `vm_file_size.c:74`, `vm_file_mremap.c:109` |
| P64-R9-7 | **VERIFIED** — `syscalls.c:562-563` |
| P64-R9-8 | **VERIFIED** — `syscalls_misc.c:181-183` |
| P64-R9-9 | **VERIFIED** — `load.c:529,571-573`, `procfs.c:330-335`, `run.h:38-39` |
| P64-R9-10 | **VERIFIED** — `load.c:260-261,326-364,449,458-462` |
| P64-R9-11 | **VERIFIED** — `syscalls_mm.c:722-749`, `syscalls_mm_map.c:561-713` |
| P64-R9-12 | **VERIFIED** — `syscalls_access.c:306-199`, `vm_file_size.c:532-611` |
| P64-R9-13 | **VERIFIED** — `proc.c:307-308` |

**13/13 VERIFIED. 0 PARTIAL. 0 REGRESSION. 0 newly introduced bugs. Curated C11 compliant.**
