# `ppc64rt` Round-8 Deep-Dive 2 — DBT/JIT static audit

Read-only. No files created, modified, or deleted. No builds or tests run. Every file below was read line-by-line. Ground truth is the reference interpreter plus `qemu-ppc64le -with -cpu power10` oracle notes in the tree.

Scope: [emit_core.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h), [emit_int.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c), [emit_int.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.h), [emit_mem.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.c), [emit_mem.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.h), [emit_mixed.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mixed.c), [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.c), [emit_fp.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.h), [emit_fp_vs.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c), [dbt.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c), [dbt.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.h), [cache.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/cache.c), [fetch.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/fetch.c), [fetch.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/fetch.h), [reloc.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/reloc.c), [reloc.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/reloc.h), [trampoline_a64.S](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/trampoline_a64.S), [aot.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/aot/aot.c), [aot.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/aot/aot.h), [cpu.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h), plus `vm64.c` miss helper and `backend_linux.c` / `backend_darwin.c` seal paths for W^X.

## Summary

| ID | Location | Defect |
|---|---|---|
| P64-R8-1 | emit_int.c:339 | Shift count truncated |
| P64-R8-2 | emit_int.c:155 | SUBFO OV missing |
| P64-R8-3 | fetch.c:109 | Prefix boundary ignored |

### P64-R8-1: register shift count uses 5/6 bits, oracle uses 6/7

[emit_int.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:339) in `e_shift()`:

```c
e_ldg(e, R_B, d->rb); e_mov_imm(e, 1u, R_T3, is64 ? 63u : 31u);
```

Word shifts mask with `31` (5 bits), doubleword with `63` (6 bits). The interpreter in [interp.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:579) uses 6 bits for word (`b & 63`, `lim 32`) and 7 bits for doubleword (`b & 127`, `lim 64`), with `n >= lim` yielding zero or sign-fill. `SRAW` in [interp.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:629) uses 6 bits, `SRAD` 7 bits. Same file lines 589-592 and 601-629 agree.

Reproduction: `SLW r5,r6,r7` with `r7=32`. Interp gives `0`. DBT masks to `0`, emits `LSLV` by `0`, leaves `r6` unchanged. Same class for `SRW` with `32..63`, `SLD`/`SRD` with `64..127`, `SRAW` with `32..63`, `SRAD` with `64..127`.

Fix: mask word with `63`, doubleword with `127`, then emit an explicit `n >= lim` bound check that zeroes word logicals, zeroes doubleword logicals, and sign-fills arithmetic shifts, matching `interp.h:582,592,612,633`. Widening the mask alone is not enough because AArch64 `LSLV`/`ASRV` reduce the amount modulo 32 or 64.

### P64-R8-2: `SUBFO` never updates `OV`/`OV32`/`SO`

[emit_int.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:155) in `e_xo()`:

```c
if (d->id == PPC64_OP_ADD && d->oe) {
```

`ADD` with `OE` computes `OV` via `e_ov2()`. `SUBF` with `OE` falls through to `e_alu_tail()` with no `XER` update. The interpreter in [interp.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:647) does `r2 = y - x; if (oe) interp_alu_ov(y ^ x, y ^ r2)` for `XO 40`, explicitly leaving `CA` untouched.

Reproduction: `SUBFO r5,r6,r7` with an overflowing `r7 - r6` (for example `r7=0x7fffffff`, `r6=0xffffffff`). Interp sets `OV`/`OV32`/`SO`. DBT leaves `XER` unchanged, so a later `mcrxr` or `BC` on `SO`, and `CR0` parity via `difftest`, diverge.

Fix: handle `SUBF` with `OE` alongside `ADD`, using `s1 = RB ^ RA` and `s2 = RB ^ RT`:

```c
if ((d->id == PPC64_OP_ADD || d->id == PPC64_OP_SUBF) && d->oe) {
    if (d->id == PPC64_OP_ADD) { /* existing RA^RT, RB^RT */ }
    else { /* RB^RA, RB^RT */ }
    e_ov2(...);
}
```

`NEG` with `OE` already declines, which is safe.

### P64-R8-3: prefixed instruction at `PC % 64 == 60` not rejected

[fetch.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/fetch.c:109) checks `(pc & 3) != 0` but never checks the Power10 64-byte prefix boundary. The interpreter in [interp.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:99) traps `INST_MISALIGNED` with length 8 before fetching the suffix when `(pc & 63) == 60`.

Reproduction: place any `PO 1` prefix at `0x...3C` mod `0x40` (for example `paddi`). Interp reports `PPC64_TRAP_INST_MISALIGNED`. DBT fetches both words, decodes, translates, and executes them.

Fix in `ppc64_dbt_fetch()`, after reading `w0` and before fetching `w1`:

```c
if ((w0 >> 26u) == 1u && (pc & UINT64_C(63)) == UINT64_C(60))
    return false;
```

This forces fallback to `ppc64_step()`, which raises the architected trap.

## Coverage verdicts

1. A64 encoding: `movw`/`mov_imm`, `add_imm`/`add_reg`, logical, `2src`, `sbfm`/`ubfx`, `madd`, `cset`, `mem1`/`fmem1`, `bcond`/`tb`, `b26` patching, `ldp`/`stp`, `rev`/`movz`/`movk`, and miss-stub encodings match the clang-verified templates. No defect beyond P64-R8-1 and P64-R8-2, which are semantic, not word-builder, errors.
2. Registers and `x18`: guest-to-host plan (`x19` CPU, `x20` TLB, `x9..x15` temps, `x0..x7` sites, `x21..x28` GPR cache, `d8..d15` FPR cache, `d16..d18` scratch) is respected. No emitter, site, stub, trampoline, or cache path reads or writes GPR `x18`. Zero `x18` defects.
3. PPC64 emission: `CR0..7` nibble plus `SO`, `XER[SO,OV,OV32,CA,CA32]`, `CTR`/`LR` decrement and sense, `AA`/`LK`, `RLDICL`/`RLDICR`/`RLDIC`/`RLDIMI`/`RLWINM`/`RLWIMI`/`RLWNM` masks, `R=1` PC-relative `paddi`/`pld`/`pstd`, and VSX lane order with scalar-cache invalidation all match the interpreter. Zero defects beyond P64-R8-1 through P64-R8-3.
4. Soft-TLB: index, tag versus `VPN` plus alignment mask, swapped `LDP` for loads versus stores, `ADD` of `addend`, `CBNZ` bailout, miss-stub spill layout, helper six-register call, `W0`-only test, resume at `cont_insn_offset`, and update-form writeback only on the non-fault path are correct. Zero defects.
5. Chaining, IBTC, RAS, W^X, I-cache: `dbt_hash` matches the trampoline `((nip>>2)^(nip>>14))&4095` probe, budget accounting is sound, guest pages stay `PROT_READ|PROT_WRITE` while JIT staging flips `RW` to `RX` with `__builtin___clear_cache` on both backends. Zero defects.
6. Exit and `nip` discipline: normal exit advances `nip`, `SC` parks at the `SC` address, fault paths reconstruct `nip` from the site record in the helper, update-form `RA` is skipped on faults, and SMC retire commits raw then re-executes at `pc+4` after a reset. Zero defects.

Per-file zero-bug statement: [emit_core.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h), [emit_int.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.h), [emit_mem.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.c), [emit_mem.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.h), [emit_mixed.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mixed.c), [emit_fp.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.c), [emit_fp.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.h), [emit_fp_vs.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c), [dbt.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c), [dbt.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.h), [cache.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/cache.c), [fetch.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/fetch.h), [reloc.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/reloc.c), [reloc.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/reloc.h), [trampoline_a64.S](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/trampoline_a64.S), [aot.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/aot/aot.c), [aot.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/aot/aot.h), and [cpu.h](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h) have 0 demonstrable behavioral bugs in this audit. [emit_int.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c) has P64-R8-1 and P64-R8-2. [fetch.c](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/fetch.c) has P64-R8-3.

