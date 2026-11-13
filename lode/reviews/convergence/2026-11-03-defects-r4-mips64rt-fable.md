# Round-4 Remediation Review — `mips64rt` `17713a6` vs `f7c6924`

Scope: static review of the commit diff plus targeted reads of the current tree. No builds, tests, Docker, or QEMU were run. Three tool turns used.

## Headline

The commit fixes astra items 1 through 7 to varying degrees, but **items 8, 9 and 10 are not touched at all**. The files they name (`src/os/sigact.c`, `src/os/syscalls_sync.c`, `src/os/syscalls.c`, `src/os/syscall_min.c`) are absent from the commit, and the defects are still present at `HEAD`. The commit message claims `M64-R4-1..10`, which is inaccurate.

The in-source markers also reveal that the commit answered a second, differently numbered Round-4 list: `futex.c` labels a FUTEX_WAIT deadline change "R4-5", `exec.c` labels a CLOEXEC sweep "R4-6", and `mem_table.c` labels a shared-mapping mprotect rejection "R4-7". None of these correspond to the astra items with those numbers. Two of those extra changes introduce consequential risks (see follow-ups 1 and 2).

## Per-item verification

### M64-R4-1 — File-offset to guest-VA translation before DBT invalidation — **VERIFIED**

`vm_inode_invalidate_maps()` (`src/vm/vm_file.c:646`) now treats `[lo, hi)` as a file-offset interval, intersects it with each mapping's `[file_offset, file_offset+len)`, and translates the overlap to `va + (ilo - flo)` before calling `dbt_invalidate_range`. Both callers pass file offsets: `vm_inode_apply_write_locked` passes `off, wend` (line 713), and `vm_inode_post_truncate_locked` passes the full range (line 769). The saturating `fhi` guards wrap. The `wide` early-path is preserved. Correct.

### M64-R4-2 — Shared writeback bounded by EOF, short writes handled — **VERIFIED**

`mips_vm_file_shared_sync()` (now in `src/vm/vm_file_sync.c`) skips when `foff >= in->size`, clips `n` to `in->size - foff`, loops `pwrite` on short writes with EINTR retry, and only marks COW_CLEAN, bumps `write_seq`, and calls `vm_inode_apply_write_locked` when every byte landed. A failed writeback leaves the pages dirty for the next sync. Matches the requested fix. Residual note: the function is `void`, so a persistent write failure is never surfaced to the guest syscall that triggered the sync. That is pre-existing and not in scope.

### M64-R4-3 — Refresh/zero helpers respect 16 KiB host pages — **PARTIAL** (plausible regression)

Both helpers now go through `u0_cover_rw()` (`src/vm/vm64.c:373`), which widens the enclosing host page to RW, operates on the 4 KiB subpage, and restores. Both return `int`, and all callers in `vm_file.c` keep the old `seen_write_seq`/`seen_resize_seq` on failure so reconciliation retries. That addresses the boundary bug and the silent-advance bug.

Regression risk: the restore protection is now computed as `u0_host_prot(u0_union_prot(halo, halo+hlen))`, the union of *guest* region prots over the host page. The old code restored the *tracked host* prot from `mips_vm_inode_page_host_prot()`. That function still exists at `vm64.c:318` but is no longer consulted by either helper. If the host cover is deliberately narrower than guest prot for write detection (COW-clean pages or shared-fallback dirty tracking kept read-only on the host so a guest store faults), this restore widens it to RW and the next guest store goes undetected until something else re-arms the cover. I could not confirm the dirty-tracking design within budget, so this is PLAUSIBLE, not CONFIRMED. Someone should check whether any page can legitimately have host prot narrower than the region-table union before this is accepted.

Minor: in the `eof_page` branch of `vm_inode_post_truncate_locked`, `vm_inode_internal_protect(ctx, page, 0u)` still runs when the zero failed. Harmless since the retry will redo it.

### M64-R4-4 — Preserve backing metadata on exhaustion — **PARTIAL**

Fixed as requested for split and middle-punch: `vm_inode_split_at()` returns `-1` before mutating on table-full or `fcntl` failure; `mips_vm_file_unmap_hook` reserves the dup before truncating `m->len`; protect and remap hooks set `in->wide` on split failure; `vm_inode_lookup()` recycles entries with `nmaps == 0`. The file split into `vm_file_sync.c` with a repo-local `vm_file_int.h` is clean.

Not addressed: the audit also named silent return from mapping registration when inode allocation fails. Slot recycling makes that rarer but the `mips_vm_file_map_hook` path is unchanged in the diff and still cannot report failure to the `mmap` caller.

Interaction: on table-full middle punch, the stored record now keeps the whole span including the unmapped hole. Combined with the new `mips_vm_file_has_shared()` check, a later `mprotect` on a fresh anonymous mapping placed in that hole will be rejected with `-EINVAL` (see follow-up 2).

### M64-R4-5 — Symmetric absorbed-operand correction — **VERIFIED**

`src/interp/fp.c:640` adds the `qd == sb && a != 0.0f` branch steering the residual by the sign of `a`. The `-0.0f` case correctly falls through to the exact path. The same logic is mirrored in `fp_ps.c`.

### M64-R4-6 — Paired-single honours FCSR rounding — **VERIFIED**

`fp_ps_lane()` now takes `ctx`, reads `fp_rm(ctx)`, computes the exact reference the same way as the scalar path, applies `fp_adj_f(r, q, rm)`, and accumulates bits from the new shared `fp_inexact_exc()`. MUL keeps the exact quad product. Whole-destination trap suppression is unchanged (caller still raises from the accumulated mask). `fp_inexact_exc` reads the U-enable bit for trapped tininess, so parity with scalar is complete.

### M64-R4-7 — Invalid on SNaN in quiet comparisons — **PARTIAL**

`fp_fmt_sd` now raises V when either operand is a legacy SNaN for both S (`fp.c:718`) and D (`fp.c:729`). The second half of the requested fix, "preserve FCC on an enabled trap", is not done: `fp_set_cc(ctx, cc, res)` at `fp.c:775` still executes unconditionally after `fp_raise`, so an enabled V trap updates the condition code before `fp_finish_trap` delivers SIGFPE. Also, a signaling predicate with an SNaN operand now calls `fp_raise(V)` twice; this is benign only if `fp_raise` is idempotent, which it appears to be.

### M64-R4-8 — `sigaltstack` old-state snapshot — **NOT FIXED** (no change in commit)

`src/os/sigact.c:385` through `:448` is unchanged. `reported` is still computed from the old stack, then `ctx->sigalt_sp`/`sigalt_size` are overwritten, then the *new* values are serialized into `oss` with the *old* flags. Defect confirmed present at `HEAD`.

### M64-R4-9 — Duplicate copyout commit protocol — **NOT FIXED** (no change in commit)

`src/os/syscalls_sync.c` is untouched. The separate commit sequence that ends in `mips_vm_file_shared_sync(ctx, va, n)` at line 217 still exists alongside `mips_sc_copyout()` in `syscalls.c:156`.

### M64-R4-10 — Superseded scaffolding — **NOT FIXED** (no change in commit)

`l2a_sigmask` and `mips_sc_rt_sigprocmask` remain at `syscalls_sync.c:120`-`152` with an extern at `syscall_min.c:47`. The `g_sync_*` queue remains at `syscalls.c:139`-`194`, and `mips_guest_range_flush` is still called from the dispatcher at `syscall_min.c:871`.

## Curated C11 and repository invariants

- No `#include "*.c"` anywhere under `src/` or `tests/`.
- All changed files are within limit. Largest in the commit: `mem_table.c` 896, `vm_file.c` 876, `fp.c` 861. Largest in tree: `dbt.c` 897. Three files sit within 5 lines of the 900 ceiling; the next edit to any of them will need a split.
- `vm_file_sync.c` was added to `BOOT_COMMON`, `U0_SRCS`, and `tests/parity_suite.sh`. I could not check whether any other Makefile source list still names `vm_file.c` without `vm_file_sync.c`; if one does, that target fails to link. Unverified.
- No `x18` use, no banned string functions in the diff.

## Summary table

| Item | Topic | Status |
|---|---|---|
| M64-R4-1 | File-offset → VA invalidation | VERIFIED |
| M64-R4-2 | EOF-bounded shared writeback | VERIFIED |
| M64-R4-3 | 16 KiB host-page cover in refresh/zero | PARTIAL (restore prot may drop tracked host state) |
| M64-R4-4 | Metadata preserved on exhaustion | PARTIAL (map-hook registration still silent) |
| M64-R4-5 | Symmetric absorbed operand | VERIFIED |
| M64-R4-6 | PS rounding mode | VERIFIED |
| M64-R4-7 | SNaN Invalid in quiet compare | PARTIAL (FCC still written on enabled trap) |
| M64-R4-8 | `sigaltstack` snapshot | NOT FIXED |
| M64-R4-9 | Copyout commit DRY | NOT FIXED |
| M64-R4-10 | Dead mask/queue scaffolding | NOT FIXED |

## Newly discovered consequential follow-ups

1. **FUTEX_WAIT EINTR retry can swallow guest signal delivery** (`src/os/futex.c:455`-`467`, PLAUSIBLE, High). The Linux path now loops on `EINTR` for relative `FUTEX_WAIT` with a recomputed remaining span. Linux returns `EINTR` to userspace whenever a handler ran; the kernel only restarts transparently when no handler was invoked. If the translator delivers guest signals by interrupting the host syscall, this loop re-enters the wait without checking for a pending guest signal, so the guest handler is deferred until wake or timeout. The loop needs to distinguish translator-internal preemption from guest-visible signals and return `-EINTR` for the latter.

2. **`mprotect` on any shared file mapping now fails with `-EINVAL` on every host** (`src/os/mem_table.c:419`). The check runs before `mips_mem_ok` and does not consult the host page size, so it also rejects on Linux 4 KiB hosts and for native shared mappings where the host could apply the change exactly. Guests that `mprotect` `MAP_SHARED` regions will regress. It should be gated on the host page size being larger than the guest page and on the mapping being a fallback mapping.

3. **CLOEXEC sweep may close translator-owned descriptors** (`src/os/exec.c:325`). `mips_vm_file_is_retained_fd()` protects only mapping dups and the two pipes. Any other translator fd opened with `O_CLOEXEC` (AOT cache, family file, log, the target ELF fd if still needed after `exec_close_cloexec` runs) is closed. The sweep also takes `vm_lock()` and scans up to 64×128 records for each of up to 8192 fds on every `execve`, which is an avoidable O(1M) scan under a preempt-blocking lock.

4. **Commit message overstates scope.** It claims `M64-R4-1..10` while three items are untouched and the R4-5/6/7 markers in `futex.c`, `exec.c`, and `mem_table.c` refer to a different list. The next commit should either carry the remaining three astra items or correct the record.
