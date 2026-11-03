I have all the evidence needed. Here is the full review.

---

## Round-9 Remediation Review — commit `746bb65`

### File-size & Curated C11 compliance

All 16 modified files are within limits (max 899 lines: `signals.c`, `vm.c`). No VLAs, no `.c` includes, no forbidden functions (`gets`/`sprintf`/`strcpy`/`strcat`/`atoi`), fixed-width integers used throughout.

---

### Per-item verdicts

**A32-R9-1 — `madvise` length-0 probe** → **VERIFIED**
`src/os/os_sys_fs_arm.c:522`: deleted the spurious first `madvise(…, 0U, …)`. VMA check now precedes the single remaining host call at line 531. Correct.

**A32-R9-2 — `futex` uaddr unchecked** → **VERIFIED**
`src/os/os_sys_sig_time.c:794–795`: bare `a0 < 0x1000U` threshold replaced with `a32_guest_range_ok(ctx, a0, 4U, PROT_READ | PROT_WRITE)`. Matches the existing `uaddr2` validation style. Correct.

**A32-R9-3 — `iov` entries unchecked** → **VERIFIED**
`src/os/os_sys_thread_sig.c:158–176`: new per-entry loop validates `base < 0x1000`, 32-bit address wrap (`(uint64_t)base + len > 0x100000000`), and `a32_guest_range_ok(ctx, base, len, req_prot)`. Zero-length entries safely get `NULL` base. New `req_prot` parameter threaded to all four call sites: `readv`/`preadv` pass `PROT_WRITE`, `writev`/`pwritev` pass `PROT_READ` (`:362`), `sendmsg` passes `PROT_READ`, `recvmsg` passes `PROT_WRITE` (`:611–614`). Function signature updated in `sys_priv.h:771`. Correct.

**A32-R9-4 — GDB `M` packet checks `READ` for write** → **VERIFIED**
`src/gdb.c:515`: `PROT_READ` → `PROT_WRITE`. One-line fix, correct.

**A32-R9-5 — `signals.c guest_write` skips reservation bump** → **VERIFIED**
`src/signals.c:82`: added `a32_vm32_copyout_invalidate_exec(ctx, va, len)` after the `memcpy`. The `_exec` variant subsumes the reservation bump AND adds JIT-on-EXEC invalidation (covering A32-R9-6 for this site too). Frame memset at line 275 similarly upgraded. Correct.

**A32-R9-6 — Copyout to `PROT_EXEC` pages never invalidates JIT** → **PARTIAL**

New `a32_vm32_copyout_invalidate_exec()` at `src/vm/vm32.c:535–553` performs reservation bump then scans `g_prot` for any EXEC page in the range, issuing one `a32_jit_invalidate_range` if found. New `guest_iov_invalidate()` at `src/os/sys_priv.h:712–727` handles post-readv/recvmsg iov buffers.

**Covered sites (correct):**
- `sys_priv.h:704` (`guest_write`)
- `signals.c:82` (`guest_write`)
- `interp.c:128` (`i_store_bytes`)
- `interp_a32.c:643` (SWP/SWPB)
- `os_sys_thread_sig.c:384–385` (readv/preadv → `guest_iov_invalidate`)
- `os_sys_sock.c:627–629` (recvmsg → `guest_iov_invalidate` + header)
- `os_sys_sock.c:680–681` (recvmsg cmsg)
- `os_sys_fs_arm.c:306–309` (epoll_wait)
- `os_sys_fs_arm.c:131–133` (epoll_pwait)
- `os_sys_sig_time.c:196` (getrlimit → routed through `guest_write`)
- `os_sys_thread_sig.c:473` (llseek → routed through `guest_write`)
- `os_sys_sock.c:70–71` (get_robust_list → routed through `guest_write`)

**Uncovered sites (same class of host-direct write, no invalidation):**
- `os_sys_thread_sig.c:339` — `read((int)a0, a32_guest_ptr(ctx, a1), ...)` writes directly to guest memory
- `os_sys_sock.c:81` — `pread((int)a0, a32_guest_ptr(ctx, a1), ...)` same
- `os_sys_sock.c:462` — `recvfrom((int)a0, a32_guest_ptr(ctx, a1), ...)` same
- Several `memcpy(a32_guest_ptr(...), ...)` for getsockopt/ioctl/stat results at `os_sys_thread_sig.c:497,507,518,543,560,588,658,682`

The `read`/`pread`/`recvfrom` gaps are the most operationally relevant — runtime code loading via `read()` into an RWX page would leave stale JIT translations. The stat/ioctl gaps are extremely unlikely to hit EXEC pages in practice.

**A32-R9-7 — VMA/TLB/file mutations leave LDREX reservations live** → **VERIFIED**

New `vm32_bump_spanned()` at `src/vm/vm32.c:140–164` bumps all 64-byte LL buckets spanned by a range, with a full-stride fast path when the span covers all buckets. Called from:
- `tlb_fill` (`:181`) — was bumping only one bucket per 4 KiB page, now bumps all 64 lines
- `sync_unmap` (`:330`) — was not bumping at all
- `set_eof_cut` (`:377`) — was not bumping at all
- `vm_file.c:423,461` — zeroing/repopulation during truncate/grow now calls `a32_vm32_copyout_invalidate` which bumps spanned buckets

Correct. All four mutation paths identified in the review are now covered.

**A32-R9-8 — Fork snapshot drops `PROT_NONE` regions** → **VERIFIED**
`src/os/os_sys_fork_time.c:162–164`: condition changed from `r->end <= r->start || (r->prot & (R|W|X)) == 0` to just `r->end <= r->start`. PROT_NONE regions now included. The snapshot path at `:238` widens via `fork_protect(…, hprot | PROT_READ)` to read the zero-initialized content, and the child restore at `:293,302` correctly applies `gprot = 0U` via `a32_vm32_protect`. Correct.

**A32-R9-9 — Fork uses raw `mprotect` on 4 KiB ranges** → **VERIFIED**
New `fork_protect()` at `src/os/os_sys_fork_time.c:76–85`: rounds HVA to host page granule (`a32_backend_page_size()`), calls `a32_backend_protect`. All pre-fork quiesce (`:238,242,246`), child widen (`:270–276`), and child/parent restores (`:293,302,316–317,342`) use either `fork_protect` (temporary transitions) or `a32_vm32_protect` (final restores with host-page-union correctness). No remaining raw `mprotect` calls. Correct.

**A32-R9-10 — Fork/clone inherit exclusive state** → **VERIFIED**

Cleared in all four child paths:
1. `fork_with_guest_snapshot` child: `:266–268` — `ll_epoch_snap = 0`, `excl_valid = false`, `a32_vm32_ll_clear_owner(ctx)`
2. Process-clone (non-fork) child: `:387–389` — same three operations
3. Thread-clone child: `:421–422` — `ll_epoch_snap = 0`, `excl_valid = false` (no `ll_clear_owner` needed — fresh `calloc`'d context never owned g_ll entries)
4. Process-clone via `fork_with_guest_snapshot` child: `:479–481` — same three operations

New `a32_vm32_ll_clear_owner()` at `src/vm/vm32.c:558–566` bumps epoch and clears owner for all lines owned by the vanished context. Runs post-fork (single-threaded), so the non-atomic check-then-modify is safe. Correct.

**A32-R9-11 — ELF `e_flags` never validated** → **VERIFIED**
`src/elf32.c:134–142`: masks `0xFF000000U` for EABIv5 (`0x05000000`) and `0x600U` for conflicting float ABI (both hard and soft set). Allows soft-float (0x200), hard-float (0x400), and default (0x000) individually — all are safe since the translator works at instruction level, not calling-convention level. Correct.

**A32-R9-12 — kuser helpers guest-non-executable but JIT-executable** → **VERIFIED**

Two-part fix:
1. `src/elf32.c:603–604`: `a32_vm_record_region` prot changed from `PROT_READ` to `PROT_READ | PROT_EXEC`. This writes `g_prot` bits `0x5` (R|X) via `a32_vm32_sync_region` (called from `a32_vm_record_region_locked` at `vm.c:277`). Host mapping stays `PROT_READ` via the subsequent `a32_vm32_protect(…, PROT_READ)` at line 605.
2. `src/os/os_sys_fork_time.c:620–624`: `a32_guest_range_ok` bounds check now allows EXEC access within `[0xFFFF0000, 0xFFFF1000)` specifically. The subsequent `guest_range_mapped` (VMA check) and `a32_vm32_range_prot_ok` (`g_prot` check) both pass for EXEC.

Interpreter fetch path: `i_fetch_bytes` → `i_mem_ok` → `a32_guest_range_ok` → now passes for kuser. Host `memcpy` read succeeds because host mapping is `PROT_READ`. Correct.

**A32-R9-13 — Stack mapping overlap check** → **VERIFIED**
`src/stack32.c:119–125`: new overlap check using `a32_vm_range_overlaps(stack_base, A32_STACK_TOP)` and `a32_vm_munmap(ctx, stack_base, A32_STACK_SIZE)` before the `a32_backend_map_anon`. Added `#include "vm/vm_priv.h"` (`.h` include, C11 compliant). Correct.

**A32-R9-14 — VMA middle-split failure diverges file tracking** → **VERIFIED**
New `vm_unmap_preflight_locked()` at `src/vm.c:185–200`: counts strictly-containing regions (each needs one extra table entry for a middle split) and rejects with `-ENOMEM` if `g_vm_region_count + need > A32_MAX_REGIONS`. Called at `vm.c:208–210` BEFORE `a32_vmfile_preflight_unmap`, so a full table fails with both tables untouched. The middle-split path at `:232–237` removes the old fallback/retry loop and relies on the preflight guarantee. Correct.

**A32-R9-15 — `mmap` masks unknown prot bits** → **VERIFIED**
`src/vm.c:635`: added `(prot & ~0x7U) != 0U` to the early-reject condition, matching the existing `mprotect` behavior at `vm.c:775`. Correct.

---

### Summary

| ID | Verdict | Evidence |
|---|---|---|
| A32-R9-1 | **VERIFIED** | `os_sys_fs_arm.c:522` — deleted spurious call |
| A32-R9-2 | **VERIFIED** | `os_sys_sig_time.c:794` — proper `range_ok` |
| A32-R9-3 | **VERIFIED** | `os_sys_thread_sig.c:158–176` — per-entry validation |
| A32-R9-4 | **VERIFIED** | `gdb.c:515` — `PROT_READ` → `PROT_WRITE` |
| A32-R9-5 | **VERIFIED** | `signals.c:82` — `copyout_invalidate_exec` added |
| A32-R9-6 | **PARTIAL** | Listed sites fixed; `read`/`pread64`/`recvfrom` host-direct writes still skip JIT invalidation |
| A32-R9-7 | **VERIFIED** | `vm32.c:140–164,181,330,377`, `vm_file.c:423,461` |
| A32-R9-8 | **VERIFIED** | `os_sys_fork_time.c:162–164` — PROT_NONE included |
| A32-R9-9 | **VERIFIED** | `os_sys_fork_time.c:76–85` — `fork_protect` wrapper |
| A32-R9-10 | **VERIFIED** | 4 child paths clear excl state + `ll_clear_owner` |
| A32-R9-11 | **VERIFIED** | `elf32.c:134–142` — EABIv5 + float ABI check |
| A32-R9-12 | **VERIFIED** | `elf32.c:603–604` + `os_sys_fork_time.c:620–624` |
| A32-R9-13 | **VERIFIED** | `stack32.c:119–125` — overlap retire before install |
| A32-R9-14 | **VERIFIED** | `vm.c:185–200` — preflight before file retire |
| A32-R9-15 | **VERIFIED** | `vm.c:635` — `(prot & ~0x7U)` rejection |

**14 VERIFIED, 1 PARTIAL (A32-R9-6). No regressions. Curated C11 compliant.**

### Residual gap in A32-R9-6

The three host-direct-write syscall paths that bypass JIT invalidation:
- `os_sys_thread_sig.c:339` — `read(fd, a32_guest_ptr(ctx, a1), len)`
- `os_sys_sock.c:81` — `pread(fd, a32_guest_ptr(ctx, a1), len, pos)`
- `os_sys_sock.c:462` — `recvfrom(fd, a32_guest_ptr(ctx, a1), len, …)`

These also lack reservation invalidation (`copyout_invalidate`). The fix pattern is identical to what was done for readv/epoll — add `a32_vm32_copyout_invalidate_exec(ctx, a1, r > 0 ? (uint32_t)r : 0)` after a successful read. The stat/getsockopt `memcpy`-to-guest sites are extremely unlikely to hit EXEC pages and can be deferred.
