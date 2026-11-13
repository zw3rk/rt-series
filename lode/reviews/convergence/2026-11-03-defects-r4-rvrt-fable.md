# Round-4 remediation review: `98ebc81` vs `b1b08af`

Scope: static inspection only, five tool turns, no builds or tests run. Hygiene checks passed: no `#include "*.c"` anywhere under `src/` or `test/`, and no translation unit exceeds 900 lines. The largest changed file is `src/vm/vm64.c` at 810 lines.

## Per-item verification

**RV-R4-1, FP stores write canonicalized operand bits. PARTIAL.** The store path in `src/darwin_dbt_emit.c:212` now uses the cached FPR only when the slot is valid, holds `rs2`, and is dirty. A clean slot that holds a canonicalized unboxed operand is bypassed and the raw architectural bits are loaded from CPU state. That is the correct split, since only a dirty entry is newer than memory. Two residuals:
- The flush guard at line 205 was inverted from `==` to `!=`. It now flushes a dirty slot that holds a *different* register, which nothing in this function reads. That is a wasted store on every FP store that aliases a slot, not a correctness fault. The line should simply be deleted.
- The requested FSW/FSD regressions after reading an improperly boxed operand were not added. Test coverage for this item is zero.

**RV-R4-2, inline self-loops lose sticky FP exceptions. PARTIAL, with a possible regression that I could not rule out.** Both backedges now call `rv_dbt_emit_flush_fpsr` before `subs w22` at lines 130 and 146. For FP loops this banks flags into `fcsr` before `loop_top` re-clears FPSR, which is the fix the audit asked for. Concerns:
- Every pre-existing call site guards the helper with `if (b->fpsr_dirty)` (lines 179, 189, 246, 256 and `src/dbt_emit_fp.c:342`). The two new calls are unguarded. My search for the helper body returned nothing, so I could not confirm whether it self-guards. If it does not, every non-FP self-loop now reads host FPSR and ORs whatever the runtime's C helpers left there into guest `fcsr` on each iteration. The existing comments explicitly call that content "helper FPSR garbage". Add the same guard as the other call sites regardless.
- The comment at line 144 says the flush sits between CMP and Bcc. It actually sits after the first Bcc and before `subs`, so NZCV neutrality is not even required. Harmless, but the comment is wrong.
- No regression test for a multi-iteration loop raising a flag only in an early iteration.

**RV-R4-3, subpage protection strips neighbors. VERIFIED.** `protect_union` at `src/vm/vm64.c:158` computes a per-host-page OR over the new range and every surviving VMA, and is used in `map_anon`, the file copy path, and the restore leg of `zero_guest_range`. Ordering is right: it runs after `vma_remove_overlap` and before `vma_add`, with the new range passed explicitly. The remaining `protect_enclosing` callers (lines 194, 226, 640, 772) only widen to RW, which can never strip a sibling bit. No unmap path touches `rt_host_protect`. The new tests cover RW/RO, RO/RW and RW/NONE in both orders on a shared 16 KiB page, and check that the RW sibling stays writable through `copyin` and that the RO sibling still fails `promote_write`. See the follow-ups for the syscall-count cost this introduces.

**RV-R4-4, failed file replacement destroys VMA metadata. VERIFIED.** `fstat` now validates the descriptor before any mutation at line 587. The mmap path maps before `vma_remove_overlap`, and the copy path stages the whole file window in a `malloc` buffer, preads it, and only then widens, removes the old VMA, zeroes and copies. All failure returns free the staging buffer. `vma_reserve(vm, 2)` still precedes everything, so the one fallible call after the host mutation cannot fail for space. The test uses a closed FD and checks state, bytes, and writability survive. It does not exercise a mid-read failure, which would be the case that actually hits the staging path.

**RV-R4-5, nonzero-offset test fails on 4 KiB hosts. VERIFIED.** The mmap path now requires `(gva ^ file_offset)` to be host-page aligned; everything else goes through the copy path. Since `gva` is already guest-page aligned, on a 4 KiB host this means the head-trimming logic at lines 611 to 617 is now dead but harmless. The existing offset-8000 regression exercises the copy path on both host sizes, so backends no longer diverge.

**RV-R4-6, failed widening still reaches memset. PARTIAL.** `zero_guest_range` returns `-errno` before touching memory when widening fails, and restores via `protect_union`. In `rv_vm64_discard_entry` the regrow leg correctly leaves the page `BEYOND_EOF` on failure instead of publishing `COW_CLEAN`, and the shrink leg skips the transition if `prepare_writable` fails. The tail-zero failure is silently swallowed at line 707, and the discard callback has no error channel, so the audit's "propagate through the discard operation" is only half done. The new test proves zeroing an RO page works and restores protection, but there is no failure-injection test.

**RV-R4-7, signed byte uses unsigned load. VERIFIED.** Both the little-endian and the width-one big-endian branches select `RV_DBT_W_LDRSB_BASE` when signed. The old wrong expectation was corrected to `0x38a36820` and a new big-endian byte test covers both signedness cases.

**RV-R4-8, 16-byte access transfers 8 bytes. VERIFIED.** Width 16 is removed from the mask table, the word-count validator, and every `mem_words` branch. Tests assert rejection for all four load/store and endianness combinations. One stale remnant: the comment on `src/dbt/dbt.h:72` still advertises width 16.

**RV-R4-9, duplicated slow-path reload. VERIFIED.** `emit_reload_caches` at `src/darwin_dbt_emit.c:21` is byte-identical to both removed copies, and the load-specific `dbt_cache_restore` stays at its call site as requested.

## Summary

| Item | Status | Note |
|---|---|---|
| RV-R4-1 | PARTIAL | Fix correct; inverted guard emits a useless flush; no regression test |
| RV-R4-2 | PARTIAL | Fix correct for FP loops; unguarded flush call unverified, may bank stale host FPSR in non-FP loops; no test |
| RV-R4-3 | VERIFIED | Per-page union; both orders tested |
| RV-R4-4 | VERIFIED | Staged before commit; mid-read failure untested |
| RV-R4-5 | VERIFIED | Alignment contract consistent; dead head logic remains |
| RV-R4-6 | PARTIAL | No write-through on failure; tail-zero failure still silent |
| RV-R4-7 | VERIFIED | |
| RV-R4-8 | VERIFIED | Stale width-16 comment in `dbt.h` |
| RV-R4-9 | VERIFIED | |

## Newly discovered consequential follow-ups

1. **Per-host-page mprotect in `protect_union`.** The helper issues one `rt_host_protect` call and one full VMA-table scan per host page. A 256 MiB anonymous mapping on a 16 KiB host now costs about 16k syscalls where it previously cost one. Only the first and last host page of a range can have foreign neighbors; interior pages always resolve to `new_prot`. Coalesce the interior into one call. This is unmeasured, so instrument before optimizing, but the scaling is arithmetic, not a guess.
2. **Staging buffer doubles peak memory for file maps on large-page hosts.** The copy path now mallocs the full valid window. A large ELF segment or a big `mmap` of a data file transiently needs twice its size on the primary development host. Consider staging only until the descriptor is proven readable, or chunked staging with a rollback copy of the overwritten range.
3. **Guard the two new `rv_dbt_emit_flush_fpsr` calls** with `if (b->fpsr_dirty)` to match every other call site, independent of whether the helper turns out to self-guard.
4. **Missing regressions** for RV-R4-1 and RV-R4-2 remain the only unresolved asks from the audit's concrete-fix sections.
