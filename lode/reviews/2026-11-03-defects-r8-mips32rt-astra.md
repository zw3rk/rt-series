# Round-8 Deep-Dive 2 Static Audit: AArch64 DBT/JIT

Read-only audit, no builds or tests run, no files touched. Every file in scope was read line-by-line: `src/dbt/dbt.c`, `emit_int.c`, `emit_mem.c`, `emit_fp.c`, `emit_fp_cvt.c`, `trace.c`, `trampoline_a64.S`, `aot_emit.c`, `aot/aot.c`, `emit_priv.h`, `emit_fp_priv.h`, `dbt.h`, `aot_emit.h`, `aot/aot.h`, `src/rt32/a64_emit.c`, `a64_emit.h`, `safe_syscall_a64.S`, plus contract headers `src/mips32rt.h`, `src/rt32/rt32.h`, `include/a32host.h`. Oracle cross-checks against `src/interp/` were read-only and are cited as evidence, not findings.

## Summary

| ID | Location | Finding |
|---|---|---|
| M32-R8-1 | `emit_int.c:546` | TLTIU uses GT, must be CC |
| M32-R8-2 | `emit_int.c:546` | TEQI uses LE, must be EQ |
| M32-R8-3 | `emit_fp.c:830` | FP traps in delay slots commit wrong PC |
| M32-R8-4 | `emit_int.c:668` | JALR rd==rs defers link, wrong slot view |
| M32-R8-5 | `trampoline_a64.S:67` | Inline IBTC skips SMC check |
| M32-R8-6 | `trace.c:77` | Delay-slot test misses REGIMM links |
| M32-R8-7 | `emit_fp.c:557` | Batched FP skips intermediate traps |

## M32-R8-1: TLTIU traps on the wrong condition (HIGH severity)

`emit_regimm` (`src/dbt/emit_int.c:546`) maps trap immediates to AArch64 conditions with `kCond = {10U, 2U, 11U, 12U, 13U, 0U, 0U, 1U}`. Index 3 (TLTIU, `d->rt == 0x0B`, `src/dbt/emit_int.c:552`) selects `12U` (`A64_COND_GT`, signed greater-than). The oracle (`src/interp/interp.c:448-449`) is `fire = rs < (uint32_t)d->simm`, unsigned below, which is `A64_COND_CC` (3U). Repro: `TLTIU $t0,-2` with `$t0 = 0xFFFFFFFF`. Oracle: `0xFFFFFFFF < 0xFFFFFFFE` is false, no trap. DBT: `SUBS` then `B.GT` (`-1 > -2` signed) is true, `EXIT_FAULT`. Fix: change index 3 to `3U`.

## M32-R8-2: TEQI traps on the wrong condition (HIGH severity)

Same table, index 4 (TEQI, `d->rt == 0x0C`, `src/dbt/emit_int.c:554`) selects `13U` (`A64_COND_LE`, signed less-or-equal). The oracle (`src/interp/interp.c:451-452`) is `fire = (int32_t)rs == d->simm`, equality, which is `A64_COND_EQ` (0U). Repro: `TEQI $t0,1` with `$t0 = 0`. Oracle: no trap. DBT: `0 <= 1` is true, `EXIT_FAULT`. The sibling table for register traps (`src/dbt/emit_int.c:394`) is correct (`TEQ -> EQ`, `TLTU -> CC`), confirming this table is a transcription error. Fix: change index 4 to `0U`.

## M32-R8-3: FP trap exits inside delay slots commit the wrong PC (HIGH severity)

`dbt_emit_fp` (`src/dbt/emit_fp.c:827-830`) takes `fpc` but discards it with `(void)fpc`, and has no `ind_slot` parameter at all. All four trapping paths (`fp_arith_op` via `fp_finish` at `src/dbt/emit_fp.c:629`, `fp_madd_op` at `:744`, `fp_cmp_op` at `:489`, `fp_to_int_op` at `:254`) therefore emit `pc = slot`, `npc = slot + 4`. Every integer equivalent (`emit_cond_fault` at `src/dbt/emit_int.c:182`, `emit_sync_pc` at `src/dbt/emit_mem.c:51`, `emit_align_fault` at `:185`) commits `pc = branch`, `npc = delay_target` for indirect slots. Repro: enable an FCSR trap via CTC1, then `BEQ` with `ADD.s` (sNaN inputs, legacy NaN mode) in the delay slot. DBT exits `TRAP` with `pc = slot`; the fallback re-executes the slot standalone and a re-raised trap delivers `EPC = slot` with `in_delay_slot = 0`. The oracle executes the slot with `in_delay_slot = 1` (`src/interp/interp.c:798`) and delivers `EPC = branch` (`src/os/signals.c:532`). Fix: thread `ind_slot` into `dbt_emit_fp` and its four callers, and make `fp_finish` emit the `emit_cond_fault`-shaped PC recovery.

## M32-R8-4: JALR with rd==rs executes the delay slot against stale state (MEDIUM severity)

`emit_branch` (`src/dbt/emit_int.c:668-669`) defers the link write past the delay slot when `link_rd == rs`, and writes it after (`:676-678`). Both the architecture and the oracle write the link first (`interp_set_reg(ctx, link_rd, pc + 8u)` at `src/interp/interp.c:784-786`, before the slot at `:816`). Two divergences follow. Repro 1: `JALR $5,$5` at `0x400` with `$5 = 0x1000`, slot `ADDU $6,$5,$0`. Oracle: `$6 = 0x408`. DBT: slot reads pre-branch `$5`, `$6 = 0x1000`. Repro 2: slot `ADDIU $5,$0,7`. Oracle: `$5 = 7`. DBT: deferred link overwrites it, `$5 = 0x408`. Fix: write the link before the slot (drop `defer_link`); the `delay_target` spill already preserves the jump target, but the `ind_slot` fault exits must then also restore `ctx->r[rs]` from `delay_target` so fallback re-execution reads the original target (the rationale that motivated deferral).

## M32-R8-5: Inline IBTC probe validates PC but not the SMC version (MEDIUM, threads-gated)

The trampoline probe (`src/dbt/trampoline_a64.S:60-73`) matches `entry.guest_pc` and non-`NULL` code, but never loads or compares `entry.smc_version` (offset 16), unlike every C lookup (`src/dbt/dbt.c:490`, `:509`, `:568`). Single-threaded execution is safe: every bump zeroes `ctx->ibtc_ptr` (`src/dbt/dbt.c:356`) and the nonzero `used_count` keeps it zeroed (`:472-475`, `:833-838`). With a second thread, a bump by thread A leaves thread B mid-chain with a nonzero `ibtc_ptr` and stale entries, and B's next inline probe executes the stale translation. Fix: snapshot the global SMC version epoch on each C transition and have the probe compare it (any bump advances `g_smc_ver_epoch`, `src/dbt/dbt.c:368,381,394`), falling to `.Lchain_slow` on mismatch.

## M32-R8-6: Trace replay mis-bounds faults in REGIMM-link delay slots (LOW severity)

`has_delay_slot` (`src/dbt/trace.c:76-78`) treats REGIMM words with `rt < 8` as branched. `BLTZAL/BGEZAL/BLTZALL/BGEZALL` (`rt` `0x10-0x13`) have delay slots but return 0, so `replay_bound` (`src/dbt/trace.c:108-116`) stops after the branch instead of including the slot. Repro under `--trace`: `BLTZAL` with a faulting `LW` in the delay slot. Oracle prints branch and slot fetches; DBT prints the branch only. The DBT's own classifier gets this right (`dbt_is_control`, `src/dbt/dbt.c:128-136`, covers `0x10-0x13`). Fix: accept `rt <= 3U || (rt >= 0x10U && rt <= 0x13U)`.

## M32-R8-7: Deferred FP batches miss intermediate enabled-exception traps (LOW, conditionally reachable)

A batch opens on translation-time FCSR with no enables (`src/dbt/emit_fp.c:839-841`). Deferred ops (`:557-587`, `:672-705`) merge flags into `W24` without checking enables, and `fp_batch_flush` (`:509-522`) merges flags only. Only the batch-final op runs the trap check in `fp_finish`. If `CTC1` enables traps after this block was compiled and the block re-executes with an exception raised solely by a non-final op, DBT merges flags and continues while the oracle traps. Repro: block `{ADD.s (overflows), MUL.s (exact)}` compiled with enables clear; `CTC1` sets Overflow-enable; re-execute. Oracle traps on the `ADD.s`; DBT silently continues. Fix: revalidate enables at `fp_batch_begin` time (runtime FCSR) and take the non-deferred path when any enable is set.

## Audited with 0 bugs

- `src/rt32/a64_emit.c`, `src/rt32/a64_emit.h`: all integer/logic/shift/bitfield/multiply/divide/select/flag/guest-window/ctx-imm/FP-convert/exclusive/barrier/branch encodings verify against ARM field layouts, including the `BFM #31,#0` carry/V merge, `EXTR`-alias `ROR`, `RRX` synthesis, and `CBZ`/`B.cond` 19-bit patching (staging-bounded, no overflow). `A64_TMP0` is defined but never emitted, so the `w15`/`$ra` alias is dead. `x18` never appears as a register operand anywhere.
- `src/dbt/emit_mem.c`: EA wraps in `W22` before `[xG, wAddr, uxtw]`; `emit_sync_pc` flushes and records `pc`/`delay_target`-recovered `npc`; alignment masks (`0/1/2` = half/word/double) with `FIXADE`-gated `SINGLE_STEP`; LL/SC lock discipline preserves `X21`-held data and unlocks on all four fail paths; unaligned `lo/hi` ranges and `merge_pos` match the E05 oracle tables in `src/interp/unaligned.c` exactly.
- `src/dbt/dbt.c`: block formation, page-crossing, `A2`-regime fallback (there is no Soft-TLB inline emission by design; `dbt_compile:654` single-steps), IBTC/RAS `smc_version` validation on all C paths, `W^X` stage/flip, and `__builtin___clear_cache` publication are sound.
- `src/dbt/emit_fp_cvt.c`, `emit_priv.h`, `emit_fp_priv.h`, `aot/*`, `aot_emit.*`, `safe_syscall_a64.S`, `mips32rt.h`, `rt32.h`, `a32host.h`: no defects; trampoline `x19`/`x20` setup and ctx offsets (`0x080`/`0x0a8`/`0x0b0`/`0x0b8`/`0x0bc`) match the ABI-locked layout.

Two judgment calls, deliberately not filed: DBT reads only the faulting bytes for `LWL/LWR` while the oracle loads the whole word (DBT is the architecturally precise one; changing it would be wrong), and the inline-IBTC `x27` hit counter is write-only dead state (cosmetic, non-behavioral).
