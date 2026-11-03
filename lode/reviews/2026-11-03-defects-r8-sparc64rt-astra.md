# Round-8 Deep-Dive 2 Static Audit — AArch64 DBT/JIT

Read-only; no files modified, no builds/tests run. All `src/dbt/*`, `src/dbt/aot/*`, `trampoline_a64.S`, `safe_syscall_a64.S`, `include/a32host.h`, `src/core/cpu.h` read line-by-line.

## Summary

| ID | Where | Defect |
|---|---|---|
| S64-R8-1 | emit_cond.c:469 | TCC imm drops rs1 |
| S64-R8-2 | emit_int.c:242 | ADDXCC icc wrong |
| S64-R8-3 | emit_int.c:438 | WR ASI no mask |
| S64-R8-4 | emit_int.c:453 | ALIGNADDRL ignored |
| S64-R8-5 | emit_mem.h:92 | regasi lost |
| S64-R8-6 | dbt.c:604 | step_one chains |

## DEFECTS

### S64-R8-1 — `src/dbt/emit_cond.c:469` TCC immediate ignores rs1

```c
if (d->is_imm != 0U) {
    sb_mov_imm64(b, ES0, (uint64_t)d->imm);
```

Interp `exec_tcc` (`src/interp/interp.c:353`): `trapno=(R[rs1]+imm)&0x7F`.

Repro: `ta %g1+0` with `%g1=0x6D`. Interp sees `0x6D` → `SYSCALL`. DBT sees `0` → `UNDEF`.

Fix: mirror register path:

```c
e_ld64(b, ES0, d->rs1);
sb_mov_imm64(b, ES1, (uint64_t)d->imm);
sb_add_reg(b, true, false, ES0, ES0, ES1);
sb_ubfm(b, true, ES0, ES0, 0U, 6U);
```

### S64-R8-2 — `src/dbt/emit_int.c:242` ADDXCC/SUBXCC icc nibble from stale flags

With-carry first pass uses no-`S` `ADC`/`SBC` into `XZR`, then `e_host_to_nibble` reads the reseed `CMP` flags, not the 32-bit result.

Repro: `ADDXCC %g0,%g0,%g0` with `icc.C=0` should set `icc=Z`; DBT commits `icc=N` from `CMP 0,1`.

Fix: refuse the shape to the helper:

```c
if (with_carry) return e_emit_alu_helper(ec, d);
```

### S64-R8-3 — `src/dbt/emit_int.c:438` `WR %asi` missing `&0xFF`

```c
sb_ldst_imm(b, false, false, ES1, ECTX, E_OFF_ASI);
```

Interp (`src/interp/interp.c:121`): `asi=(a^b)&0xFF`.

Repro: `wr %g1,%g2,%asi` with `a^b=0x1FF` → interp `0xFF`, DBT `0x1FF`; later `%asi`-relative loads diverge.

Fix: `sb_ubfm(b, false, ES1, ES1, 0U, 7U);` before store.

### S64-R8-4 — `src/dbt/emit_int.c:453` `ALIGNADDRL` decoded as `ALIGNADDR`

`e_emit_align` never reads `d->opf`. Interp (`src/interp/interp.c:142`): `ALIGNADDRL` uses `(0-sum)&7`.

Repro: `alignaddrl %g1,%g2,%g3` with `sum=1` → interp `gsr=7`, DBT `gsr=1`.

Fix: branch on `d->opf==0x1A`, negate sum first for `ALIGNADDRL`.

### S64-R8-5 — `src/dbt/emit_mem.h:92` alternate-`%asi` lost, `regasi` uninit

`s64_jrt_mem` sets `d.asi` but never `d.regasi`; `e_call_mem` (`src/dbt/emit_mem.h:182`) packs only `d->asi` (`0xFF` for `i==1` form).

Repro: `lda [%g1]%asi,%g2` with `%asi=0x80` → interp resolves to `0x80` and succeeds; helper sees `asi=0xFF` → `LOAD_ACCESS` → spurious `UNDEF`.

Fix: pack `regasi`, init `d.regasi=0`, set from pack, letting `sparc64_exec_load/store/atomic` resolve via `cpu->asi`.

### S64-R8-6 — `src/dbt/dbt.c:604` `dbt_step_one` allows chaining

```c
return dbt_enter_block(ctx, mem, mc, dbt, code, false);
```

`false` selects `sparc64_dbt_enter` (live epoch, chaining on). Single-step must use `enter_step` (zero epoch). Repro: difftest step over a `BRANCH` fallthrough with the next block cached executes two guest insns; `pc` overshoots by 4/8.

Fix: pass `true`.

## Clean files

0 bugs in scope: `dbt.h`, `emit_priv.h`, `emit_int.h`, `emit_cond.h`, `emit_fast.h`, `emit_fast.c`, `emit_mem.c`, `emit_fp.h`, `emit_fp.c`, `emit_fpcmp.c`, `emit_rt.c`, `mem_sites.h`, `mem_sites.c`, `difftest.h`, `difftest.c`, `trampoline_a64.S`, `safe_syscall_a64.S`, `a32host.h`, `core/cpu.h`, `dbt/aot/*`. Strict `x18` reservation holds; no emitter emits or clobbers `x18`. `REV`, `UBFM`, branch-offset, `W^X`/I-cache, IBTC/RAS probe layouts verified against `emit_rt.c` asserts.

