# rvrt Round-2 remediation review (commits `8e207fb..dab0b91`)

**Result:** Four of five Round-2 findings are resolved in the code as written. RV-R2-5 is only partly addressed. No regression was found in the inspected diffs. One silent semantic fix in the FMA encoder deserves a changelog note, and one slow-path assumption could not be verified within budget.

Scope: static inspection only. No build, test, QEMU or Docker was run. Five tool turns covered the audit report, `git log`, the full diff stat, the full diffs of `src/dbt_emit_fp.c`, `src/os/backend_darwin.c`, `src/os/backend_linux.c`, `src/darwin_dbt.c`, `src/darwin_dbt_emit.c`, `src/dbt/cache.h` and `Makefile`, plus targeted reads of `src/dbt_emit_fp.h`, `src/memory/test_alloc_hooks.h`, the new difftest cases, and repo-wide greps.

## Per-item verification

**RV-R2-1 (High, fused FP overwrites dirty victim): VERIFIED.**
- A new helper `rv_dbt_emit_prep_dst_fpr` at `src/dbt_emit_fp.h:331` spills slot `rd & 15` when it is dirty and holds a different guest register. It is called before the arithmetic write at `src/dbt_emit_fp.c:540` (add/sub/mul/div when the result goes to the cache slot), `:580` (sqrt) and `:852` (all four fused ops).
- The spill is a store only, so a source operand already resident in the destination slot (the "rs1 == victim" case) stays physically intact for the FMA read. Correct.
- `emit_str_d` and `emit_box_s` gained assertions that a late spill can never fire when the result already sits in the slot register. This catches any path that forgets the pre-spill.
- The `need_uf` single-precision multiply path writes to scratch `d2`, not a cache slot, so it correctly skips the pre-spill.
- Coverage: `test/u5b_difftest.c` adds `test_fused_fp_dirty_victim_collision`, iterating all four opcodes and both formats over three collision shapes (rs1 == victim, rs1 == rd with rs2 == victim, all sources == victim), checked against the interpreter.
- Bonus fix not in the audit: the opcode-to-A64 mapping at `src/dbt_emit_fp.c:809` was swapped. Previously RISC-V FMSUB (0x47) was encoded as A64 FMSUB (`Ra - Rn*Rm`), which is the sign inverse of `rs1*rs2 - rs3`, and likewise for FNMSUB. The new mapping (0x47 to A64 FNMSUB, 0x4b to A64 FMSUB) is correct. Operand placement (Rm=rs2, Ra=rs3, Rn=rs1) matches the A64 field layout.
- The repeated dynamic-rounding slow-tail block was factored into `emit_slow_tail`, which now emits the helper under the pre-fast-path cache snapshot and restores the post snapshot at the join. This is the right discipline. The join-point reconciliation inside `emit_helper_for` was not inspected (see follow-ups).

**RV-R2-2 (Medium, Darwin no-replace ignored): VERIFIED.**
- `rt_host_map_anon` at `src/os/backend_darwin.c:65` now rejects fixed or no-replace requests with a null or unaligned hint, then for no-replace reserves the range with `vm_map(VM_FLAGS_FIXED)`, which fails on any overlap. On success it commits with `mmap(MAP_FIXED)` over its own reservation and deallocates on mmap failure. Length overflow and page rounding are checked.
- A process-wide mutex serializes the reserve-then-commit pair. It is not needed for correctness against other mappers (the reservation already owns the range) but is harmless.
- `fixed=1, noreplace=0` still replaces destructively, which is the documented `MAP_FIXED` contract and is what `src/vm/vm64.c:123` relies on.
- Coverage: `test/u5a_vm_provider.c:425-440` checks occupied address returns `-EEXIST` for both fixed and non-fixed no-replace, misaligned hint returns `-EINVAL`, and placement succeeds after unmap.
- Linux backend only gained the same argument validation. The existing `MAP_FIXED_NOREPLACE` use was not re-inspected.

**RV-R2-3 (Low, RAS bookkeeping with no consumer): VERIFIED.**
- The mechanism was removed rather than completed. `RV_DBT_RAS_DEPTH`, the `ras[]` array, `ras_top`, `return_pc`, `rv_dbt_ras_push/pop`, `note_block_ras`, `check_indirect_ras` and the `call_return_pc` out-parameter of `rv_darwin_dbt_emit_insn` are all gone. A repo-wide grep over `src/` and `test/` finds zero references. The cache header comment was updated accordingly.

**RV-R2-4 (Medium, textual `.c` includes in tests): VERIFIED, with a residual.**
- Zero `#include "*.c"` remain under `src/`, `include/` and `test/`. Fifty-plus tests now compile the production unit separately and link it.
- Private seams are implemented as per-translation-unit macro hooks in `src/memory/test_alloc_hooks.h`, each gated on both a `-DRV_TEST_*` flag and an `RV_IN_<UNIT>_C` guard. Every guard the header references is defined in exactly one production `.c`, always on the line immediately before the hook include, and always after the system headers it shadows. So prototypes are never rewritten and other units in the same link see plain libc. Cross-TU visibility is sound.
- The `sigaction` hook is function-like, so `struct sigaction` is unaffected. The `fstat` hook is object-like but follows `<sys/stat.h>`.
- Residual: defining macros named `malloc`, `calloc`, `free`, `fstat`, `pwrite`, `fcntl` after including the standard header is formally undefined under C11 7.1.3. This is test-only configuration and pre-dates this round, but it is the "macro substitution" coupling the audit called out, and it now spans 22 guarded units.
- A new `check-line-limits` target enforces both rules. Whether it is a prerequisite of `check` was not confirmed (the `check:` prerequisite line at `Makefile:7788` is continued and was truncated in my output).

**RV-R2-5 (Low, header slicing instead of decomposition): PARTIAL.**
- The two cited sites are fixed. `src/runtime_main.c` now includes one types header instead of eleven implementation headers, and the former `runtime_main_*_internal.h` slices, `family_{commit,enter,lifecycle,replay}_internal.h` and `scheduler_internal.h` are separately compiled `.c` units.
- Twenty `*_internal.h` headers still contain function bodies, several with 20 to 39 definitions each (`file_backing_internal.h`, `file_caps_wire_internal.h`, `space_internal.h`, `guest_memory_{freeze,start}_internal.h`, `family_types_internal.h`, `runtime_main_types_internal.h`). I did not confirm whether these are small `static inline` helpers or implementation slices.
- The same pattern was newly applied in the DBT: `src/dbt_emit_fp.h` now hosts `rv_dbt_emit_flush_fpr_slot`, `rv_dbt_emit_prep_dst_fpr` and the cache snapshot code as `static inline` so that `dbt_emit_fp.c` stays at 867 lines.

Curated C11 and limits: no `.c` includes; the largest first-party files are 891 lines (`src/linux/signal.c`, `test/r6_exec_peer.c`, `test/test_family_file_pwrite_recovery.c`). Several files sit within 40 lines of the ceiling.

## Summary

| Item | Severity | Status | Note |
|---|---|---|---|
| RV-R2-1 | High | VERIFIED | Pre-spill helper on all slot-writing FP paths, asserted, difftest-covered. FMA opcode sign mapping also corrected. |
| RV-R2-2 | Medium | VERIFIED | Darwin reserve-then-commit with `-EEXIST`/`-EINVAL`, test-covered. |
| RV-R2-3 | Low | VERIFIED | RAS fully removed, zero leftovers. |
| RV-R2-4 | Medium | VERIFIED | Zero `.c` includes, enforced by `check-line-limits`. Macro seams remain (C11 7.1.3). |
| RV-R2-5 | Low | PARTIAL | Cited units decomposed; ~20 internal headers still carry bodies, and `dbt_emit_fp.h` adds a new one. |

## Newly discovered consequential follow-ups

1. **Undocumented semantic fix.** The FMSUB/FNMSUB sign inversion in the DBT fast path (`src/dbt_emit_fp.c:809`) was a real guest-visible bug before this commit. The commit message does not mention it. Record it in `docs/IMPLEMENTATION-PLAN.md` so the fixture history explains why fused-op outputs changed.
2. **Slow-path join reconciliation, unverified.** `emit_slow_tail` restores the pre-snapshot before emitting `emit_helper_for` and the post-snapshot afterwards. This is only correct if the helper tail ends by reloading every slot that the post state marks valid (or by invalidating and reloading per post state). If it reloads per the pre state, then after a dynamic-rounding slow exit the fast-path join assumes `v(16+rd&15)` holds `rd` while the register holds stale data. Concrete probe: block with `fadd.d f1,f2,f3` under `rm=dyn` with frm != RNE, followed by `fmv.x.d x5,f1` in the same block. I could not read `emit_helper_for` within budget.
3. **`check-line-limits` wiring.** Confirm it is a prerequisite of `check` so the enforcement actually runs in the integrated gate.
4. **Linux `MAP_FIXED_NOREPLACE` fallback.** Kernels before 4.17 ignore the flag and return a different address. Confirm the Linux backend compares the returned address to the hint and unmaps on mismatch. Not in the diff, so possibly pre-existing.
5. **Macro seams are formally UB.** Consider replacing the `#define malloc`-style hooks with explicit function-pointer or weak-symbol seams in a later refinement pass. Test-only, low urgency.
