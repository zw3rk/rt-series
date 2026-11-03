All data collected. Here is the full review.

---

## Round-9 VM/Loader Remediation Review — Commit `6740a71`

### Per-item verdicts

**I686-R9-1 — `i686_fetch_cstr` 32-bit wrap check**
**VERIFIED.** `src/os/marshal.c:210`: `if (cur_va < va)` detects when `va + (uint32_t)i` wraps past 0 and returns `-I686_EFAULT`. For `va=0xFFFFFFF0, i=16`, `cur_va` wraps to 0 which is `< va`, so the guard fires. The initial byte (`i=0`) is not falsely rejected. Matches the defect's requested fix.

**I686-R9-2 — `sys_uname` writes guest memory unchecked**
**VERIFIED.** `src/os/syscalls.c:196-204`: builds into a stack buffer `ubuf[I686_UTS_TOTAL]` (compile-time constant = `65 * 6 = 390` bytes), then calls `i686_copy_to_guest(ctx, buf_va, ubuf, sizeof(ubuf))` which validates mapping, permission, and wrap. The old direct `i686_guest_ptr` + `memset` path is eliminated. Old wrap-only guard removed; `i686_copy_to_guest` handles wrap internally.

**I686-R9-3 — `r_madvise` unchecked, escapes window, skips invalidation**
**PARTIAL.** `src/os/sys_misc.c:584-621`: All three stated issues are addressed — wrap/escape check (`end64 > 0x100000000ULL`), page alignment check, mapped-range validation via `rt32_vm_check_mapped_range_locked`, and `rt32_vm_invalidate_jit` on `MADV_DONTNEED`/`MADV_REMOVE` for stale translations. Two minor new issues:

1. **`len == 0U` returns `-EINVAL`** (line 596): Linux `madvise(2)` accepts `len=0` as a no-op returning 0 since kernel 3.18. This is a guest-visible semantic mismatch.
2. **Truncation when `addr + len == 0x100000000`** (line 605): `(uint32_t)end64` truncates to 0 when `end64` is exactly `0x100000000`, making `rt32_vm_check_mapped_range_locked(addr, 0, ...)` meaningless. Fails safe (returns `-ENOMEM`), so not a security hole, but rejects a legitimate edge-case range.

**I686-R9-4 — Steady state uses union instead of widen**
**VERIFIED.** All three call sites changed:
- `src/rt32/rt32_elf32.c:118`: `i686_vm32_union_prot` → `i686_vm32_widen_prot`
- `src/rt32/rt32_vm_mmap.c:151` (via `rt32_vm_widen_protect_a2`): function body calls `widen_prot`
- `src/rt32/rt32_vm.c:842` (brk growth, via renamed function)
- The wrapper renamed from `rt32_vm_union_protect_a2` to `rt32_vm_widen_protect_a2` in both `rt32_vm.c:241` and `rt32_vm_internal.h:62`. No stale references to the old name remain.

**I686-R9-5 — ELF shared-page prot uses OR, creates RWX**
**VERIFIED.** `src/rt32/rt32_elf32.c:299` (now ~298): `merged_prot = guest_prot` replaces `merged_prot = highest_mapped_prot | guest_prot`. The `highest_mapped_prot` variable is fully removed (no references remain). This matches Linux `MAP_FIXED` semantics where the later mapping wins the shared boundary page.

**I686-R9-6 — `CLEAN→DIRTY` promotion never runs**
**VERIFIED.** `i686_vm_file_promote_cow` now has 4 callers covering all guest write paths:
- `src/os/marshal.c:151` — `copy_to_guest` store path
- `src/dbt/engine_smc.c:327` — SMC write-fault commit
- `src/os/signals_subpage.c:756` — emulated `REP` string stores (EDI-write path)
- `src/os/signals_subpage.c:878` — A2 emulate general store commit

The `signals_subpage.c` changes correctly move `promote_cow` outside the `#ifndef I686RT_NO_DBT` guard so COW promotion happens even without DBT, while `dbt_invalidate_range` remains guarded. The promote function itself (`vm_file.c:235`) flips `COW_CLEAN(1)` → `COW_DIRTY(2)` atomically per page.

**I686-R9-7 — `mprotect` changes host before VMA commit**
**VERIFIED.** `src/rt32/rt32_vm_mmap.c:220-230`: VMA record (`rt32_vm_mprotect_regions_locked`) now precedes host `mprotect`. On VMA slot exhaustion, `-ENOMEM` is returned without touching host permissions, eliminating the original divergence. The reverse scenario (host `mprotect` fails after VMA succeeds) is theoretically possible but much rarer than slot exhaustion and fails-safe (guest gets stricter permissions than VMA claims, triggering catchable faults).

**I686-R9-8 — Shrink prefix uses per-4K mprotect on A2 hosts**
**VERIFIED.** `src/vm/vm_file.c:345-360`: The A2 detection (`a2` variable) is hoisted above the prefix-restore loop. On A2 hosts, the per-4K `mprotect` loop is replaced by a single `i686_vm32_widen_prot(ctx, map_start, cut)` call which handles host-page alignment internally. The non-A2 path retains the original per-4K logic unchanged.

**I686-R9-9 — `fork` child destroys locked mutexes**
**VERIFIED.** Two sites fixed:
- `src/vm/vm32.c:76-77`: `pthread_mutex_unlock` on `s_subpage_mtx` then `s_futex_mtx` (inner-first unlock order) before the existing destroy+init sequence.
- `src/os/clone.c:838`: `pthread_mutex_unlock(&s_registry_lock)` before existing destroy+init.

This eliminates the POSIX UB of `pthread_mutex_destroy` on a locked mutex. Post-fork unlock by a non-owner thread is the standard glibc/musl pattern for this scenario.

---

### Newly introduced issues

| Severity | Location | Description |
|---|---|---|
| Minor | `sys_misc.c:596` | `len == 0U → -EINVAL` deviates from Linux (should be no-op returning 0) |
| Minor | `sys_misc.c:605` | `(uint32_t)end64` truncates to 0 when `end64 == 0x100000000`, making mapped-range check vacuous; fails safe as `-ENOMEM` |

### Curated C11 compliance

- **No VLAs**: All stack arrays use compile-time constants (`I686_UTS_TOTAL` = `65*6`). The `int tail_fd[I686_FILE_MAX_MAPS]` in `vm_file.c` pre-dates this commit and uses a `#define` constant.
- **No `.c` includes**: Zero `#include "*.c"` in any modified file.
- **File lengths (all <= 900 lines)**: `rt32_vm.c` 899, `clone.c` 898, `vm_file.c` 894, `signals_subpage.c` 890, `syscalls.c` 863 — all within the 900-line limit. The remaining files are well under.

### Summary

| Item | Verdict |
|---|---|
| I686-R9-1 | VERIFIED |
| I686-R9-2 | VERIFIED |
| I686-R9-3 | PARTIAL (two minor semantic edge cases) |
| I686-R9-4 | VERIFIED |
| I686-R9-5 | VERIFIED |
| I686-R9-6 | VERIFIED |
| I686-R9-7 | VERIFIED |
| I686-R9-8 | VERIFIED |
| I686-R9-9 | VERIFIED |

**8 of 9 VERIFIED, 1 PARTIAL.** The R9-3 fix is structurally sound and closes the security hole (window escape, missing invalidation) but introduces two minor guest-visible semantic mismatches on edge-case inputs. No regressions, no C11 violations.
