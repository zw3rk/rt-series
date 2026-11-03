# Round-8 Deep-Dive 2 — DBT/JIT Static Audit

Scope: `src/dbt/*`, `src/core/cpu.h`, related headers. Read line-by-line. No files modified. No builds or tests run.

## Summary

| ID | Location | Issue | Severity |
|---|---|---|---|
| M64-R8-1 | emit_int.c | JR skips slot | High |
| M64-R8-2 | emit_alu.c | Trap loses delay state | High |
| M64-R8-3 | emit_int.c | Link deferred past slot | High |
| M64-R8-4 | emit/mem_recover | JALR clobbers recovery | High |

## M64-R8-1: JR/JALR misaligned target skips delay slot, wrong fault PC

**Files:** [emit_int.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:391) vs [interp.c](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:800)

`ei_branch` indirect emits `TBNZ` on bits 0/1 of the target **before** the slot, faulting at the branch PC via `ei_exit_fault_reg(pc)` without running the slot. The oracle defers alignment until after link plus slot (`defer_align`), then faults at the **target**.

Repro: `jr $t0` with `$t0 = 0x120000001`, slot `addiu $t1,$t1,1`. Interp runs the slot then faults at the target. DBT skips the slot and reports the branch PC.

Fix: park first, emit the slot, then check the parked `x25` after the slot and fault at the target value.

## M64-R8-2: trapping ALU in delay slot loses `in_delay_slot`

**Files:** [emit_alu.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_alu.c:261), [emit_int.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:524)

`ADD`/`DADD`/`SUB`/`DSUB`/`TGE`/`ADDI`/`DADDI`/`TGEI` emit `ei_bfault` inline even when `slot != 0`, without setting `in_delay_slot`. `SYSCALL`/`BREAK` correctly decline in slots; traps do not. Interp leaves `in_delay_slot = 1` on a delay-slot trap, so guest signal `BD` bit diverges.

Repro: `beq $0,$0,1f; add $t0,$t1,$t2` (overflowing) in the slot.

Fix: decline trapping words in delay slots (`if (slot != 0) return 1;`) so the whole branch falls back to `interp_step`.

## M64-R8-3: deferred JAL link breaks COP1 slots

**Files:** [emit_int.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:385), [emit_fpmem.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fpmem.c:367)

`fpslot` defers `RA = pc+8` past any `COP1`/`COP1X` slot. Two failures: `MFC1 $ra,$f0` in a `JAL` slot writes `RA`, then the deferred link overwrites it (interp keeps the slot value); `LWXC1` in a `JAL` slot can `TRAP`-miss, and `dbt_mem_recover` replays only the slot, never writing the missing link.

Repro: `jal tgt; mfc1 $ra,$f0`, or `jal tgt; lwxc1 $f0,$t0($t1)` with an unmapped indexed address.

Fix: decline linking branches whose `COP1`/`COP1X` slot writes the link register or can miss (or restrict `fpslot` to non-memory, non-GPR-writing words).

## M64-R8-4: JALR `rd == rs` link clobbers dynamic-target recovery

**Files:** [emit_int.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:394), [mem_recover.c](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:202)

For GPR slots, the link writes before the slot. `jalr $t,$t` with a faulting `LW` slot overwrites `ctx->gpr[rs]` with `pc+8` before the fault. Recovery reads `ctx->gpr[b.rs]` for `RT_NPC_DYNAMIC_CTX` and resumes at the wrong target.

Repro: `jalr $t0,$t0; lw $t1,0($t2)` with the load missing.

Fix: decline indirect links with `d->rd == d->rs` when the slot can fault.

## Files with 0 bugs (audited dimensions)

`a64_emit.c`, `a64_emit.h`, `arena.c`, `dbt.c`, `dbt.h`, `emit_enc.c`, `emit_fp.c`, `emit_fpmem.c` (outside M64-R8-3/4 roots), `emit_int.h`, `emit_mem.c`, `emit_mem.h`, `mem_recover.c` (outside M64-R8-4 root), `trampoline_a64.S`, `core/cpu.h`, `aot/identity.c`, `aot/identity.h`, `aot/sha256.c`, `aot/sha256.h`, `aot/sites.c`, `aot/sites.h`.

Notes: `x18` is rejected by every encoder and never appears in the trampoline or probe; W^X staging plus `__builtin___clear_cache` is correct on both backends; `RAS` is write-only and the emitter never sets `INFO_LINK`/`RETURN`, but that is a dead optimization, not a behavioral defect; R6 compact branches are out of scope (loader rejects R6).

