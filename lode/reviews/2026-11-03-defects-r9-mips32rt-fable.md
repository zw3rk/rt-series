I have all the evidence. Here's the complete review.

---

## Round-9 Remediation Review — Commit `e95314c`

### M32-R9-1 — Production `vm_regime` stays `UNSET` — **VERIFIED**

**Defect**: `mips32_fixade_init` + `mips32_vm32_init` only called from `guest_mem_init` (dead on the production path). `run_guest` → `rt32_vm_init` never touched `vm_regime`; `execve` identical.

**Fix evidence**:
- `src/os/mem.c:199-200` — removed the duplicate `mips32_fixade_init` + `mips32_vm32_init` calls (would leak the A2 Soft-TLB if both paths ran).
- `src/rt32/vm_init.c:142-145` — `mips32_fixade_init(ctx)` + `mips32_vm32_init(ctx)` now execute inside `rt32_vm_init`, which is the production entry point. Placed before `vm_lock_acquire()` at line 147 (correct: no concurrent threads exist at init time).
- `src/rt32/vm.c:643-647` — `rt32_vm_reset_for_exec` (execve path) calls `mips32_vm32_fini(ctx)` to drop stale TLB tags, then re-runs `mips32_fixade_init` + `mips32_vm32_init`. The `vm/vm32.h` include added at line 15 provides the declarations.
- `tests/test_r3_regress.c:210-213` — stub `mips32_vm32_fini` added for test linkage.

**Note**: `mips32_vm32_fini(ctx)` at `vm.c:643` is called unconditionally while the subsequent `mips32_fixade_init`/`mips32_vm32_init` are guarded by `if (ctx != NULL)` at line 644. This is cosmetically inconsistent, but not a real bug — `ctx` is guaranteed non-NULL at this point (the function dereferences `ctx` extensively in lines 600-638 before reaching here).

---

### M32-R9-2 — Guest stores to `PROT_EXEC` never invalidate JIT — **VERIFIED**

**Defect**: `rt32_vm_copy_to` and `mips_store_locked` performed stores without calling `vm_invalidate_jit` when the target range overlapped executable VMAs.

**Fix evidence**:
- `src/rt32/vm.c:843-859` — In `rt32_vm_copy_to`, scans `g_vm_regions` under the VM lock for `PROT_EXEC` overlap, then calls `vm_invalidate_jit(ctx, va, (uint32_t)end64)` after `vm_lock_release()`. Uses the authoritative global table (correct: lock is held during the scan).
- `src/os/mem.c:501-523` — New `store_overlaps_exec` helper scans the ctx-local region mirror. Correct: `mips_store_locked` doesn't hold the VM lock, so using the (conservatively stale) mirror is the right approach — false positives cause harmless extra invalidations, false negatives can't happen for regions that were already PROT_EXEC before the store.
- `src/os/mem.c:536,541,554-556,566-567` — `exec_hit` captured before the store; invalidation fires after both the fast path (no LL active, line 554) and the locked path (line 566).

**Minor edge note**: `vm_invalidate_jit(ctx, va, (uint32_t)end64)` at `vm.c:859` — if `va + len == 0x100000000`, `(uint32_t)end64` wraps to 0, producing `end < start`. Practically unreachable due to guard pages at the address space ceiling, and the same truncation pattern (`va + len` in `uint32_t`) exists in the mem.c path at line 555.

---

### M32-R9-3 — `write`/`uname` TOCTOU via unchecked `guest_ptr` — **VERIFIED**

**Defect**: `sc_write` and `sc_uname` called `range_ok` then `mips32_guest_ptr` without holding the VM lock, creating a race window with concurrent `munmap`.

**Fix evidence**:
- `sc_write` (`syscall_min.c:178-235`): Now mallocs a staging buffer (`tmp`), copies guest data via `rt32_vm_copy_from` (which does its own locked check), passes the host-local buffer to `write()`. Every error path frees `tmp` correctly. Errno is captured at line 220 before `free` (avoiding potential errno clobbering). The `count == 0U` early return at line 193 avoids a zero-byte malloc.
- `sc_uname` (`syscall_min.c:279-317`): Composes all 6 UTS fields into a stack-local `staged[MIPS_UTS_SIZE]` (390 bytes — safe stack size), then commits with a single `rt32_vm_copy_to`. Clean pattern, no heap allocation needed.

---

### M32-R9-4 — `mmap` silently masks illegal `prot` bits — **VERIFIED**

**Defect**: `vm_mmap2_ext_locked` accepted any `prot` value, silently masking to `prot & 0x7U`, while `mprotect` correctly rejected unknown bits.

**Fix evidence**: `src/rt32/vm_mmap.c:67-71` — `if ((prot & ~0x7U) != 0U) return (uint32_t)(-EINVAL);` added immediately after existing `flags` validation. Matches the `mprotect` validation. `~0x7U` on uint32 is `0xFFFFFFF8U`, rejecting anything above R|W|X. Minimal and correct.

---

### M32-R9-5 — `PT_MIPS_ABIFLAGS` / `EF_MIPS_FP64` ignored, FR pinned to 0 — **VERIFIED**

**Defect**: Loader pinned `fr_mode = 0U` at three sites; never parsed `.MIPS.abiflags` or `EF_MIPS_FP64`.

**Fix evidence**:
- `src/rt32/elf32.c:44,50-55` — Adds `EF_MIPS_FP64 (0x200)`, `PT_MIPS_ABIFLAGS (0x70000003)`, `MIPS_FP_ABI_64 (6)`, `MIPS_FP_ABI_64A (7)`. All values match the MIPS ABI supplement.
- `src/rt32/elf32.c:309-323` — Scans phdrs for `PT_MIPS_ABIFLAGS` with `p_filesz >= 8U` guard, reads 8 bytes via `pread_full`, extracts `fp_abi = abiflags[7]` (byte 7 is indeed the `fp_abi` field per the ABI supplement structure layout). Sets `fr_mode = 1` for `FP_64 (6)` or `FP_64A (7)`, falls back to `EF_MIPS_FP64` e_flags bit when the segment is absent (sentinel `0xFFFFFFFF`).
- `src/rt32/rt32.h:74` — `uint32_t fr_mode` field added to `rt32_elf_info_t`.
- Propagation at all three sites:
  - `src/rt32/elf32.c:772` — `ctx->fr_mode = out_info->fr_mode != 0U ? 1U : 0U;`
  - `src/main.c:306` — `ctx->fr_mode = info.fr_mode != 0U ? 1U : 0U;`
  - `src/os/proc.c:413` — `ctx->fr_mode = info.fr_mode != 0U ? 1U : 0U;`

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None found |
| `.c` includes | None found |
| `sprintf`/`strcpy`/`strcat` | None found |
| `_Generic` / Annex K (`*_s`) | None found |
| `bool`/`true`/`false` in vm.c | Valid — `stdbool.h` included via `vm_priv.h:16` |
| File size <= 900 lines | All pass (largest: `mem.c` at 877) |

### Newly Introduced Bugs

No regressions found. One **plausible** edge-case noted:

- **`(uint32_t)end64` truncation** at `vm.c:859` and implicit `va + len` uint32 wrap at `mem.c:555`: if a store lands at the very top of the 32-bit address space such that `va + len == 0x100000000`, the end argument wraps to 0, and `vm_invalidate_jit` would receive `(start=high, end=0)` which likely no-ops instead of invalidating. This is practically unreachable (guard pages prevent mappings at the ceiling), and the same arithmetic is used throughout the codebase, so it's a pre-existing pattern rather than a regression.

### Summary

| Item | Verdict |
|---|---|
| M32-R9-1 | **VERIFIED** — regime init moved to `rt32_vm_init`; execve path tears down + reinits |
| M32-R9-2 | **VERIFIED** — both store paths now check PROT_EXEC overlap and invalidate JIT |
| M32-R9-3 | **VERIFIED** — `write` stages via malloc+copy_from; `uname` stages on stack+copy_to |
| M32-R9-4 | **VERIFIED** — `(prot & ~0x7U)` rejection added to `vm_mmap2_ext_locked` |
| M32-R9-5 | **VERIFIED** — PT_MIPS_ABIFLAGS parsed, EF_MIPS_FP64 fallback, fr_mode propagated to all 3 sites |
| C11 compliance | **PASS** — no violations; all files <= 900 lines |
| New bugs | **None** (one plausible but unreachable uint32 truncation edge case noted) |
