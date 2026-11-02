# Round-3 Remediation Review: `d58f57e` vs `2c2a62e` (ppc32rt)

Reviewer model: claude-fable-5-1. Static inspection only. No builds, tests, Docker, or QEMU ran. Tool budget used: 4 turns.

## Per-defect verification

**P32-R3-1, division overflow with RT == RB: VERIFIED.**
`src/interp/interp.c:378` now snapshots `da`/`db` alongside `sa`/`sb`, and `div_ov` is computed from `db` before the write to `ctx->gpr[insn.rt]`. The quotient can no longer feed the divisor test, and `xer_set_ov` still runs before `set_cr0`, so CR0.SO sees the correct XER.SO. The DBT side was already correct and is unchanged. Gap: no regression case with RT == RB and a zero quotient was added. The grep for `R3-1` or `RT == RB` in `tests/` finds nothing, so the audit's requested test is missing.

**P32-R3-2, host-page padding as guest memory: PARTIAL.**
`rec_end` is gone. Both `vm32_record_map` and `vm_record_region_ex_locked` publish only `[target_va, map_end)`, and the A2 permission sync covers only that range. The padding is now unrecorded and guest-inaccessible through the TLB. The cursor still advances by `host_map_len`, so cursor allocations skip it. What the fix did not do is "account for the backing when placing adjacent mappings," as the audit asked. `vm_can_modify_range_locked` only checks region-table capacity, not overlap, and the `tail_busy` test runs only for the shared mapping's own tail. A later `MAP_FIXED` or hint-address mapping whose extent lands inside a live shared mapping's padding sees free space and is placed on a host page that is still `MAP_SHARED` file-backed. In the A2 anonymous path the `memset` zero-fill then writes through to the file beyond the guest-visible range, and a `MAP_PRIVATE` file populate copies into the shared file page. This is listed as follow-up 1 below. The common path (cursor placement) is correct.

**P32-R3-3, unaligned shared mappings becoming private copies: PARTIAL.**
The silent private copy is gone. On A2, a host-aligned VA with a guest-aligned sub-page file offset now goes through `vm_file_shared_map_at`, which maps one memfd staging object per (dev, ino, offset) family `MAP_SHARED` at every alias. Alias and fork visibility hold, and the new test covers both plus survivor-after-peer-munmap. The remaining `is_shared` cases on A2 (non-host-aligned VA, anonymous shared below host granularity, tail past the window) return an explicit `-EINVAL`/`-ENOMEM`, which is the audit's accepted fallback. Limitations, partly documented in the code: coherence holds only within identical (offset, length) families, not between a staged range and an overlapping direct or staged range, and not with `read`/`write` on the file until write-back at munmap or GC. One new defect is in the refresh logic (follow-up 2). The `mremap` eligibility update (`staged_ok`) is consistent with the new mmap path.

**P32-R3-4, multithreaded fork coordination: VERIFIED.**
The repository has exactly six process-global spinlocks (`g_vm_lock`, `g_tlb_lock`, `g_ll_lock`, `g_inode_lock`, `g_thread_lock`, `g_sig_disp_lock`). `proc_fork_prepare` acquires all six in the documented order, `proc_fork_parent` releases them in reverse on both success and `fork` failure (errno is saved first), and `proc_fork_child` clears each inherited value plus the two thread-local held flags before rebuilding the thread table around slot 0. Greps show no thread-lock use under the VM lock and no VM entry while the disposition lock is held, so the stated order is consistent with the code I could see. Two assumptions I could not fully verify: the syscall dispatcher must not already hold the VM lock when `ppc32_proc_fork` runs (the spinlock is not recursive), and no non-spinlock shared state outside these six exists in `src/dbt/`. Other threads' `ppc32_ctx_t` allocations leak in the child, which is acceptable.

**P32-R3-5, aliased signal syscall input/output: VERIFIED.**
All three handlers now read the full input into locals before any output store. `rt_sigprocmask` also validates `how` only when a new set is supplied and computes the new mask from the snapshotted `old_mask`, matching kernel ordering. Two pre-existing, non-regressing divergences remain: `rt_sigaction` and `sigaltstack` still write the old value before the new value is validated, where Linux writes it only on success, and `rt_sigaction` performs the get and the set in two separate critical sections, so a concurrent `sigaction` from another thread can make the returned old value stale. No identical-pointer or overlapping-pointer tests were added.

**P32-R3-6, shared disposition synchronization: VERIFIED.**
`sig_actions` is accessed only in `src/os/signals.c`, and every access (reset, exec reset, get, set, delivery) is under `g_sig_disp_lock`. Whole-struct copies replace the field-wise ones. `SA_RESETHAND` consumption moved from `ppc32_sig_build_frame` into `ppc32_sig_deliver_sync`, where it is atomic with selection and happens before any guest-memory access. I checked for a bypass: `ppc32_sig_deliver_sync` is the only delivery entry point (two callers in `src/main.c`), and no other file calls `ppc32_sig_build_frame` or `ppc32_sigaction_get`, so one-shot semantics are not lost. The lock is spin-with-`sched_yield` and is never held across guest memory, so no new deadlock surface. The `pid` for fork is included in the protocol.

**P32-R3-7, execve clearing the signal mask: VERIFIED.**
`ctx->sig_mask` and `ctx->pending_signals` are no longer written on the success path. `ppc32_sig_reset_exec` resets caught dispositions to `SIG_DFL`, leaves `SIG_IGN` alone, and runs under the disposition lock. The altstack is still cleared, which matches Linux. The misleading comment was corrected. No guest test for inherited mask across exec was added.

## Curated C11 and repository invariants

| Check | Result |
|---|---|
| `#include "*.c"` in `src/` or `tests/` | none |
| Files over 900 lines | none; `src/rt32/ppc32_vm.c` is at 897 and `src/vm/vm_file.c` at 896 |
| `sprintf`/`strcpy`/`strcat` | none |
| `x18` references | only the constants `0x18` in `fp.h` and `convert.h` |
| VLAs, Annex K, `_Generic`, `<threads.h>` in the diff | none seen |

One style concern: `src/os/signals_priv.h` defines non-inline `static` functions in a header and cites a `signals_dispatch.c` that does not exist. Today only `signals.c` includes it and uses every helper, so it compiles. A second includer that uses a subset would fail under `-Werror` for unused functions.

## Summary

| Defect | Status | Note |
|---|---|---|
| P32-R3-1 | VERIFIED | Fix correct; requested RT == RB regression test missing |
| P32-R3-2 | PARTIAL | Padding no longer guest-visible, but adjacent placement into padding is not blocked (follow-up 1) |
| P32-R3-3 | PARTIAL | Alias and fork coherence for identical ranges; explicit error for the rest; refill clobbers live stores (follow-up 2) |
| P32-R3-4 | VERIFIED | All six global spinlocks covered; dispatcher-holds-VM-lock and DBT-state assumptions unverified |
| P32-R3-5 | VERIFIED | Inputs snapshotted first; no aliasing tests added |
| P32-R3-6 | VERIFIED | No bypass of the new one-shot consumption path |
| P32-R3-7 | VERIFIED | Mask and pending set preserved; dispositions reset correctly |

**Newly discovered consequential follow-ups**

1. **Medium, `src/rt32/ppc32_vm.c:397`.** A `MAP_FIXED` or hint mapping into the unrecorded host padding of a live A2 shared mapping is placed on a file-backed shared host page. The anonymous path's `memset` writes zeros into the file past the guest-visible range. Fix by recording the padding as an internal, non-accessible reservation that blocks placement, or by rejecting placement on host pages partially owned by a shared mapping.
2. **Medium, `src/vm/vm_file.c`, `vm_file_shared_acquire`.** When a new alias is acquired and the file's size or mtime differs from the recorded value, the whole staging object is re-filled from the file. Any stores made through existing live aliases since the last write-back are discarded. A guest `write` to the file, or a forked child's write-back on its own munmap, triggers this. Fix by draining before refilling, or by refusing to refill while any live region references the group.
3. **Low.** Test coverage requested by the audit for R3-1, R3-5, and R3-7 was not added.
4. **Low, `src/rt32/ppc32_vm_regions.c`, `staged_group_referenced_locked`.** Every munmap performs one `fstat` per (region, staged group) pair. Measure before changing, per project policy, but note the cost scales with region count.
5. **Low, `src/os/signals_priv.h`.** Static non-inline helpers in a header plus a stale reference to a nonexistent file; mark `static inline` or move them back.
