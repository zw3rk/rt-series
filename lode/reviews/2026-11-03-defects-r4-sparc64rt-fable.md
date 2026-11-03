# Round-4 remediation review: `103433c` vs `5232650` (sparc64rt)

Scope: static review only. No build, test, Docker, or QEMU run. Evidence is the audit report, `git show 103433c`, and targeted reads of the post-fix sources.

## Global compliance checks

- **No `#include "*.c"`** anywhere under `src/`, `tests/`, `include/`.
- **Line limits**: all `.c/.h/.S` files are at or below 890 lines. Largest after the fix: `src/os/threads.c` (890), `src/vm/vm64.c` (887), `src/interp/fp_quad.c` (863), `src/dbt/emit_priv.h` (857), `src/os/proc.c` (855). The 776-line churn in `guest_run_sysmem_file.c` was absorbed by splitting into `sysmem_file_remap.c` and `sysmem_file_resize.c`.
- **`x18`**: only comment mentions in `src/dbt/`; no new assembly or emitter touched.
- **New files** `fp_commit.c/.h` are picked up by the `find src -name '*.c'` source list and the `$(wildcard src/interp/*.c)` test link line, so no Makefile source list was missed.

## Per-item verification

### S64-R4-1 — negative 32-bit int-to-float magnitude — **VERIFIED**
`src/interp/fp_conv.c:181` now computes `UINT64_C(0) - (uint64_t)(int64_t)v`. For `v == -1` this yields `1`; for `INT32_MIN` it yields `0x80000000`. The DBT path is unchanged, so difftest parity is restored rather than altered. The audit's requested FITOS/FITOD vectors (`-1`, `INT32_MIN`, boundary negatives) were not added.

### S64-R4-2 — directed rounding of exact integers — **VERIFIED**
In `cv_int_bits()` the inexact flag `*nx` is derived from the guard/round/sticky bits **before** the mode switch, and RM=2/RM=3 now gate on `(*nx != 0U)`. Exact integers no longer increment under directed modes; the post-increment carry normalisation (`sig >> p`) is untouched. The helper serves FITOS/FITOD/FXTOS/FXTOD as before. No rounding-mode vectors were added.

### S64-R4-3 — failed relocated mremap rollback — **PARTIAL**
What was done, and it is sound as far as it goes:
- A full registry snapshot (`sysmem_file_snapshot`) with refcount-bumped descriptors is taken before `vm64_stxn_prepare()`; every exit path runs exactly one of discard/restore. Refcount accounting in `restore` (release every current live slot, then install the snapshot whose refs transfer) is correct given the invariant that non-live slots carry `desc == NULL`, which `slot_release` and `grow` maintain.
- On growth-fill `-12`, the tail is dropped, the head is moved back from `dest` to `old_addr` when relocated, the snapshot is restored, both spans are TLB/DBT invalidated, and `vm64_code_epoch_bump()` is called before `vm64_stxn_abort()`. This fixes the "abort does not bump the epoch" half of the finding.
- `check-r4` arms `sysmem_file_test_fail_next_fill(1)` through the real `sparc64_sysmem_mremap` shell.

What remains open:
- The audit's second half, **"for FIXED relocation, replaced destination mappings are also lost"**, is not addressed. The forward move replaces whatever lived at `dest`; the move-back only returns the relocated head. Worse, the restored registry snapshot still contains the entries that `sysmem_file_remap_update` excised at `dest`, so after a failed MREMAP_FIXED growth the registry claims file-backed coverage at `dest` that the address space no longer maps. A later truncate on that file would drive `sparc64_space_map_bus`/`sparc64_space_replace` over an unmapped range. For MAYMOVE (free destination) the rollback is complete.
- A failed move-back deliberately keeps the relocated state and still returns `-ENOMEM` to the guest; documented in the comment, but the guest then holds an invalid old pointer in that corner.

### S64-R4-4 — retained-fd acquisition failure — **VERIFIED**
`sysmem_file_desc_t {fd, refs}` replaces per-entry fds. `note_map` returns `-errno` (test hook forces `EMFILE`) instead of recording a descriptor-less entry; `note_map_owned` closes and frees on every failure branch (invalid length, `malloc`, `reserve`, no free slot). Splits in `drop_map`, `remap_update`, and the new `protect_update` share the description via `sysmem_desc_share`, so splitting never needs a host descriptor. `fill_overlap` still returns `0` for `desc == NULL`, which is now only reachable for `fd < 0` registrations (tests), not for a degraded file mapping.

Note: the mmap shell (`guest_run_sysmem.c:377`) still calls `sysmem_file_note_map` after the legs rather than acquiring up front; correctness rests on the existing nonzero-rc rollback that Round-3 introduced for `-ENOMEM`. That rollback is not in this diff and was not re-read; the mechanism is the same one already relied on, so this is noted, not failed.

### S64-R4-5 — munmap reserve failure — **VERIFIED**
`sparc64_sysmem_munmap` now returns `-ENOMEM` before `vm64_stxn_prepare()` when `sysmem_file_reserve(sysmem_file_drop_extra(...))` fails, so the middle-excision tail can never be silently dropped. Linux `munmap` may legitimately return `ENOMEM` on VMA-split failure, so the guest-visible semantics are acceptable. `check-r4` arms `fail_next_grow(1)`.

### S64-R4-6 — mprotect permissions tracked in the registry — **VERIFIED**
`sparc64_sysmem_mprotect` reserves `sysmem_file_protect_extra()` slots (2 per overlapping entry) before the legs and calls `sysmem_file_protect_update(g, addr, size, prot & 7U)` after invalidation. `protect_update` handles fully-covered (prot overwrite), head-stays/mid-claims/tail-claims, and no-head (mid reuses slot with shifted chunk states) cases; all source fields are snapshotted before any `claim_free` that could realloc. `sysmem_file_resize` (now in `sysmem_file_resize.c`) reads the per-split `slot->prot`, so shrink BUS and growth replace use current permissions.

### S64-R4-7 — CLOEXEC sweep on failed exec — **VERIFIED**
Host-exec path: no sweep; the host `execve` performs atomic CLOEXEC handling and a failed `execve` returns with all guest descriptors intact. Guest-image path: `proc_close_cloexec()` runs only after `sparc64_guest_exec_image` returns `0`, skips descriptors for which `sysmem_file_is_retained()` is true, and is followed by `sysmem_file_drop_all()` to release the replaced address space's registry and its retained fds. The ordering (skip-then-drop) is correct.

Unverified assumption: `drop_all` after commit presumes the image loader does not register the new image's segments through the registry. The only `sysmem_file_note_map` caller is the mmap shell; if the loader ever routes through `sparc64_sysmem_mmap`, the new image's coverage would be discarded. Worth a one-line assertion in the loader or a comment.

### S64-R4-8 — per-thread signal state — **VERIFIED**
`sync_thr[65]` keyed by `const sparc64_ctx_t *` holds `blocked`, `pending`, and `ss_sp/ss_size/ss_flags`; dispositions stay global. All public accessors take `ctx`; `guest_engines.c` setjmp/longjmp pass `ctx`. `threads.c:584` calls `sparc64_sync_sig_clone(&slot->ctx, ctx)`, which copies the parent's mask, clears pending, and disables the altstack, so a reused thread slot (same `ctx` address) is reinitialised on clone rather than inheriting a dead thread's state. Residual gaps, none of which the audit demanded: no explicit thread-exit release, `sync_resolve` aliases slot 0 on exhaustion, and process-directed signals still queue to a single thread's `pending` rather than a shared set.

### S64-R4-9 — futex relative deadline across retries — **VERIFIED**
Both backends compute one `CLOCK_MONOTONIC` deadline for relative `FUTEX_WAIT` (WAIT_BITSET is absolute, correctly excluded) and pass the remaining slice on each loop iteration, returning `-ETIMEDOUT` when the deadline has passed before re-sleeping. The Linux path does not validate `tv_nsec`/negative `tv_sec` before building the deadline, so a negative relative timeout now yields `-ETIMEDOUT` where Linux returns `-EINVAL`; minor. Whether the loop distinguishes internal preemption from guest-visible signal interruption was not re-verified within budget.

### S64-R4-10 — syscall-shell transaction tests — **VERIFIED** (statically)
New `check-r4` links `guest_run_sysmem.c` plus the split files and drives `sparc64_sysmem_mmap/munmap/mprotect/mremap` with injectable grow, dup, and fill failures; it is wired into `test`. Not executed here.

### S64-R4-11 — single FP commit helper — **VERIFIED**
`sparc64_fp_commit()` in `fp_commit.c/.h` is byte-identical in semantics to the removed `cv_commit`/`sd_commit`; all 30 call sites in `fp_conv.c` and `fp_sd.c` were converted. Result publication stays with the callers, as requested.

## Summary

| Item | Title | Status |
|---|---|---|
| S64-R4-1 | Negative int32→float magnitude | VERIFIED |
| S64-R4-2 | Directed rounding of exact integers | VERIFIED |
| S64-R4-3 | Transactional failed mremap relocation | PARTIAL |
| S64-R4-4 | Retained-descriptor acquisition failure | VERIFIED |
| S64-R4-5 | munmap metadata on reserve failure | VERIFIED |
| S64-R4-6 | Permissions preserved across truncate | VERIFIED |
| S64-R4-7 | CLOEXEC closure only at exec commit | VERIFIED |
| S64-R4-8 | Per-thread mask/pending/altstack | VERIFIED |
| S64-R4-9 | Futex deadline across retries | VERIFIED |
| S64-R4-10 | Real syscall-shell failure tests | VERIFIED (not run) |
| S64-R4-11 | Unified FP exception commit | VERIFIED |

No regressions found in the fixes themselves. Curated C11 and the 900-line limit hold.

## Newly discovered consequential follow-ups

1. **S64-R4-3 residual (Medium)**: after a failed MREMAP_FIXED growth, the registry snapshot resurrects entries for the destination range whose mappings the forward move replaced, leaving registry coverage over unmapped guest VA. Either refuse FIXED growth that would replace tracked ranges when the fill could fail, or exclude the excised destination entries from the restored snapshot and document the lost destination mappings.
2. **S64-R4-7 assumption (Low, verification item)**: `sysmem_file_drop_all()` after exec commit must stay ahead of any loader path that registers segments; add an assertion or comment in `sparc64_guest_exec_image` so a future loader change cannot silently discard the new image's tracking.
3. **S64-R4-9 minor (Low)**: validate the relative timespec on the Linux path before computing the deadline so invalid values return `-EINVAL` like Linux.
4. **S64-R4-1/2 coverage (Low)**: the audit's requested FITOS/FITOD/FXTOS vectors (`-1`, `INT32_MIN`, exact integers under all four RD modes with FSR flag checks) were not added; parity currently rests on difftest alone.
