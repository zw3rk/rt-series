# Round-8 Deep-Dive 2 — DBT/JIT/Code-cache/Trampoline audit

Read-only. No builds, no edits. All claims from source read.

## Summary

| ID | Where | Symptom | Fix |
|---|---|---|---|
| A32-R8-1 | `vm_jit_mem.c:84-92` | No `DC CVAU` on IALLU path | Add `DC` loop |
| A32-R8-2 | `dbt_jit_run.c:392` | RAS key wrong mode on `BLX` | Use `LR[0]` |
| A32-R8-3 | `core_emit_mem.c:104-150` | Fault drops ITSTATE in A2 | Store ITSTATE |

### A32-R8-1 — Missing `DC CVAU` in `A32H_CAP_ICACHE_TRAP_IALLU` path

`src/vm/vm_jit_mem.c:84-92` does only `IC IVAU; DSB; ISB`.

The non-trapped path at `vm_jit_mem.c:95-106` does `DC CVAU` per line, `DSB`, then `IC IVAU`, `DSB`, `ISB`.

New code in D-cache is still dirty. A trapped `IC IVAU` that only invalidates I-cache can fetch stale bytes. Repro: run under `hl` with `A32H_CAP_ICACHE_TRAP_IALLU`, compile any new block, branch to it. Fix: clean the batch range first:

```c
for (uintptr_t p = addr; p < end; p += 64U)
    __asm__ volatile("dc cvau, %0" : : "r"(p) : "memory");
__asm__ volatile("dsb ish" ::: "memory");
```

then the existing single `IC IVAU; DSB; ISB`.

### A32-R8-2 — RAS return key uses callee `T`, not caller mode

`src/dbt/dbt_jit_run.c:392`:

```c
uint32_t ret_key = a32_make_key(lr_pc, is_thumb);
```

`is_thumb` is re-read after `a32_jit_run_block`, i.e. callee mode. Repro:

- A32 `BLX label` at `interp_a32_ctl.c:284-296` sets `LR=pc+4` (ARM, even), exits `INTERWORK` to Thumb. Post `is_thumb=1`, pushed `ret_key` is Thumb-odd. Correct return is ARM-even.
- T32 `BL/BLX` at `interp_t32_dp.c:138-142` sets `LR=(pc+4)|1` (Thumb, odd), exits to ARM. Post `is_thumb=0`, pushed `ret_key` is ARM-even. Correct return is Thumb-odd.

Result is safe but wrong: RAS/IBTC miss, pollutes `ibtc[r_ibtc]` with an unhittable key. Fix:

```c
bool ret_thumb = (ctx->regs[14] & 1U) != 0U;
uint32_t ret_key = a32_make_key(lr_pc, ret_thumb);
```

### A32-R8-3 — A2 Soft-TLB fault exit loses ITSTATE

T32 blocks with entry `itstate != 0` clear `ctx->itstate` on entry at `src/interp/interp_t32_mem.c:607-610`:

```c
a64_emit_str_imm_w(b, A64_ZR, A64_XCTX, offsetof(a32_ctx_t, itstate));
```

`UNDEF`/`BKPT`/`SVC` paths restore it before exit at `interp_t32_mem.c:808-811,821-824` and `interp_t16.c:442-457`. The Soft-TLB miss paths at `src/core/core_emit_mem.c:104-150` only do:

```c
str fault_addr; mov_pc32 w15,cur_pc; movz w16,FAULT; ret
```

Repro, Regime-A2 only: Thumb IT block containing a faulting `LDR/STR` (`[rN]` unmapped). `r15` is exact via `a32_jit_last_record_pc()`, but `ctx->itstate` stays `0`. The pre-instruction IT slot is lost for signal handling / retry. Fix: store the pre-insn `itstate` on these two fault exits, same as the `UNDEF` path, or thread `itstate` into `emit_soft_tlb_check`.

## Files with 0 bugs

- `src/a64_emit.h`: 0 bugs. Reg map reserves `x18` by never emitting it; `x20` documented as `xG`; cond codes match A32/T32/A64.
- `src/core/core_emit_alu.c`: 0 bugs. `MOVZ/K`, `ADD/SUB`, `UBFM/SBFM/BFM`, `MADD/MSUB`, `UDIV/SDIV`, `CSEL/CSNEG`, `MRS/MSR NZCV` bases verified.
- `src/core/core_emit_shared.c`: 0 bugs. `Q/GE` via `BFM` lsb/width, `MRS/MSR CPSR` masks, `LDM/STM` first/last probe and `Rn`-in-list handling correct.
- `src/trampoline.S`: 0 bugs. Saves `x19-x28`, `d8-d15`; `x18` untouched; `w25/w26` mask/mode, `NZCV` merge, chain/IBTC/RAS offsets `48/56`, `2496`, `448`, `424` match `jit_priv.h` / `a32rt.h`.
- `src/dbt/jit_priv.h`, `src/dbt/dbt_jit_query.c`, `src/vm/vm_jit_state.c`, `src/vm/vm32.c`, `src/vm/vm32.h`, `src/interp/decode_priv.h`, `src/interp/interp_a32_ctl.c`, `src/interp/interp_a32_dp.c`, `src/interp/interp_t32_dp.c`, `src/interp/interp_t16.c`, `src/interp/interp_thumb.c`: 0 behavioral bugs found in this scope. `x18` never emitted; `[x20,wAddr,uxtw]` vs A2 `[x23,wAddr,uxtw]` discipline holds; `PC+8`/`PC+4`/`pc_align4`, `B.cond/CBZ` `imm19` range, `LDREX/STREXD` 64-bit `LDXR/STXR X` (never `LDXP/STXP`), no mem between paired exclusives hold.

