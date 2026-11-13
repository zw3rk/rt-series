# Round-3 Remediation Review: rvrt `b1b08af` vs `dab0b91`

Static review only. No builds, tests, containers or QEMU were run. Four inspection turns: the astra Round-3 report, the full commit diff, and the surrounding emitter, compile-block, vm64 and Makefile context in the current tree.

## Verdict

All seven items are fixed in code. Six are fully verified. RV-R3-6 is verified for the reported defect but the chosen mechanism widens a pre-existing neighbour-protection hazard on 16 KiB hosts, which I list as a consequential follow-up. The commit adds vm64 regressions but no DBT regressions for RV-R3-1, RV-R3-2 or RV-R3-3, although the audit asked for them.

## Per-item verification

### RV-R3-1: Dynamic-rounding slow path flushes uninitialized FPSR. VERIFIED

The snapshot struct in `src/dbt_emit_fp.h:353` now carries `fpsr_dirty`, `frm_checked` and `tlb_cache_kind`. The ordering in `src/dbt_emit_fp.c:489` is correct: the snapshot is taken first, then the frm guard is emitted, then `emit_clear_fpsr`. On the guard-taken path the slow tail restores the pre-instruction snapshot before emitting the helper exit. For a block's first FP instruction that snapshot has `fpsr_dirty == false`, so the helper exit emits no FPSR flush and host garbage cannot reach guest `fcsr`. When earlier FP instructions did accumulate flags, the flush runs and banks exactly what the taken path produced. The `frm_checked` rewind also means the helper exit is emitted as if no guard existed, and the post-snapshot restore re-establishes the hoisted guard for later fast-path instructions. No regression found. Note that `rv_dbt_emit_flush_fpsr` never mutates `fpsr_dirty`, so the restore sequence is self-consistent.

### RV-R3-2: Underflow correction erases earlier sticky flags. VERIFIED

`src/dbt_emit_fp.c:546` banks accumulated flags before the gated multiply: it emits the OR-into-fcsr flush, then `MSR FPSR, xzr`. I checked the encoding `0xd51b443f` against `emit_clear_fpsr`, which uses the same word. `emit_uf_fix` then only sees this instruction's UFC. `fpsr_dirty` stays true through the flush and `emit_accum` re-asserts it, so the block exit still accumulates the multiply's own flags. The tiny-product helper path is also correct: its snapshot is taken before the bank-and-clear sequence, and at that branch point host FPSR still holds the earlier flags, so the helper exit flushes them. Cost is seven extra words per static-RNE `FMUL.S` after the block's first FP op. Performance only.

### RV-R3-3: Emitter rollback retains discarded-instruction state. VERIFIED

The snapshot struct covers every mutable metadata field of `rv_dbt_emit_buf_t`: boxed mask, GPR cache, FPR cache tags and dirty bits, FPSR liveness, frm guard and Soft-TLB reuse kind. `words`, `count`, `exit_patch_count` and `overflow` are rewound separately in `src/darwin_dbt.c:314`. The exit flush after rollback therefore uses correct tags. The 96-word exit reserve at `src/darwin_dbt.c:301` is a heuristic, not a guarantee. An instruction that fits but eats into the final 96 words still leaves the exit sequence to overflow. That path returns -1 from `compile_block` via the existing overflow check, so it degrades rather than emitting wrong code. Acceptable, but the commit message's "reserve exit-emission headroom" oversells it slightly.

### RV-R3-4: VMA capacity exhaustion loses mappings. VERIFIED

`vma_reserve` runs before any mutation in `rv_vm64_map_anon`, `rv_vm64_unmap` and `rv_vm64_map_private_file`. The worst-case arithmetic holds: a range can be strictly inside at most one VMA, so at most one split needs a new slot, plus one insert. Unmap reserves one. Growth doubles via `realloc`, zeroes the new slots, and `rv_vm64_destroy` frees the table. `vma_remove_overlap` now returns `-ENOSPC` instead of dropping the tail. The 4 KiB head-offset validation moved ahead of VMA removal. Residual, outside the audit's capacity scope: a host `mmap` or `pread` failure after VMA removal still leaves partial state.

### RV-R3-5: Large-page file mapping retains bytes beyond EOF. VERIFIED

The large-page path widens, zeroes the full length, then reads only `valid` bytes computed by `fstat`. `mark_file_states` classifies in mapping space, so nonzero file offsets behave like zero offsets. Pages wholly past the rounded-up EOF become `BEYOND_EOF`, and `rv_vm64_host` already refuses those at `src/vm/vm64.c:293`. The 4 KiB kernel path relies on MAP_PRIVATE zero fill for the partial page and on state alone for whole pages beyond EOF, which is correct. The overflow guard constant in `mark_file_states` mirrors `rv_vm64_discard_entry`; it is unreachable but harmless.

### RV-R3-6: Subpage remapping writes into read-only host backing. VERIFIED, with follow-up

`prepare_writable` now calls `protect_enclosing`, which aligns down and covers the full host-page span, and propagates failure before any `memset`. The reported fault is gone and the `r3-6` test covers each 4 KiB subpage of a read-only 16 KiB host page. See follow-up 1 for the side effect of also applying the final narrow protection over enclosing pages.

### RV-R3-7: Hygiene gate absent from `make check`. VERIFIED

`Makefile:8774` adds `check: check-line-limits`. The Makefile already uses recipe-less prerequisite lines for `check` at five other places, so the pattern is consistent. The target scans `src`, `include` and `test`. Current tree: zero textual `.c` includes, and the largest first-party file is 891 lines. `src/dbt_emit_fp.c` sits at 882 lines and will need a split on its next substantive change.

## Summary table

| Item | Status | Notes |
|---|---|---|
| RV-R3-1 | VERIFIED | Snapshot ordering and FPSR liveness restore correct. No DBT regression test added. |
| RV-R3-2 | VERIFIED | Bank-then-clear before gated FMUL.S. Tiny-helper path consistent. No regression test added. |
| RV-R3-3 | VERIFIED | Snapshot covers all mutable metadata. Exit reserve is heuristic; overflow still degrades safely. |
| RV-R3-4 | VERIFIED | Worst-case reservation precedes all mutation; table grows by doubling. Tests added. |
| RV-R3-5 | VERIFIED | Zero-init, fstat-bounded pread, BEYOND_EOF classification in mapping space. Tests added. |
| RV-R3-6 | VERIFIED | Enclosing-page widening fixes the fault. Neighbour narrowing side effect, see below. |
| RV-R3-7 | VERIFIED | Gate wired into `check`; tree currently passes it by inspection. |

## Newly discovered consequential follow-ups

1. **Final protection narrows neighbouring guest pages on large-page hosts.** Severity Medium, confidence PLAUSIBLE. `rv_vm64_map_anon` and the large-page branch of `rv_vm64_map_private_file` now end with `protect_enclosing(hva, len, prot)` even when `hva` is not host-page aligned. Before this commit an unaligned start skipped `mprotect` entirely. Scenario on a 16 KiB host: map anonymous read-write at guest 0x10000 for 4 KiB, then map a read-only file at 0x11000 for 4 KiB. The second call makes host page 0x10000 to 0x14000 read-only. `rv_vm64_copyin` at `src/vm/vm64.c:686` then writes through `memcpy` without widening and takes a host SIGSEGV. The same applied before for aligned starts with partial lengths, so this widens an existing hazard rather than creating one, but it now triggers from more layouts. I did not confirm whether any host fault handler recovers this. Suggested fix: on hosts with a granule larger than 4 KiB, apply the final protection only when the whole enclosing span is covered by VMAs of equal or stricter protection, or leave the enclosing span writable and rely on the VMA write check as the design comment already states.

2. **`rv_vm64_zero_range` widens permanently.** Severity Low. It now widens the enclosing host pages to read-write and never restores, unlike `zero_guest_range` which restores after the `memset`. This is a protection softening, not a correctness fault, since VMAs remain the authority. Restoring `linux_prot` after the zero would make the two helpers consistent.

3. **Non-capacity mapping failures still leave partial state.** Severity Low. In `rv_vm64_map_private_file`, a `rt_host_map_file` or `rt_host_pread64` error after `vma_remove_overlap` returns with VMAs dropped and page states untouched. The audit scoped RV-R3-4 to capacity, so this is residual rather than a regression.

4. **Missing DBT regressions.** The audit's concrete fixes for RV-R3-1, RV-R3-2 and RV-R3-3 each asked for a regression. The commit adds only vm64 tests. The emitter fixes are correct by inspection, but nothing in the suite now pins the first-FP-op dynamic-rounding path, the underflow-then-exact-multiply sequence, or a rollback with dirty FPRs.
