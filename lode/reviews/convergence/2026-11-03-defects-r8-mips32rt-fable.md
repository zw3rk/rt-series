I have all the information needed. Here's the complete review.

---

## Round-8 DBT/JIT Remediation Review: Commit 1d86f82

### Curated C11 Compliance
- No VLAs, no `.c` includes, no `sprintf`/`strcpy`/`strcat`: **PASS**
- File line limits (all <= 900): `dbt.c`=900, `emit_fp.c`=899, `emit_int.c`=899, all others well within: **PASS**

---

### M32-R8-1: TLTIU traps on wrong condition — **VERIFIED**

`emit_int.c:553` — `kCond` table index 3 changed from `12U` (A64_COND_GT, signed) to `3U` (A64_COND_CC, unsigned below). This matches the SPECIAL register-traps table at `emit_int.c:399` (index 3 = `3U`) and the interp oracle's `rs < (uint32_t)d->simm`.

### M32-R8-2: TEQI traps on wrong condition — **VERIFIED**

Same table, index 4 changed from `13U` (A64_COND_LE) to `0U` (A64_COND_EQ). Matches the SPECIAL register-traps table at `emit_int.c:399` (index 4 = `0U`) and the oracle's equality test.

### M32-R8-3: FP traps in delay slots commit wrong PC — **VERIFIED** (conservative approach)

`emit_fp.c:829` — `dbt_emit_fp` now declines (`return -1`) when `cur != fpc`, i.e., whenever the instruction is in a delay slot. This forces the interpreter path, which correctly handles `in_delay_slot`, `EPC = branch`, etc. The defect report suggested threading `ind_slot` through the FP emitter; the actual fix is simpler and equivalently correct. FP memory ops (LWC1/LDC1/SWC1/SDC1 at `emit_int.c:740`) bypass `dbt_emit_fp` entirely, so they remain JIT-compiled in delay slots with proper `ind_slot` handling.

### M32-R8-4: JALR rd==rs defers link, wrong slot view — **VERIFIED**

The `defer_link` mechanism is removed. The link is now always committed before the delay slot at `emit_int.c:673-674`. When `link_rd == d->rs && rs != $zero`, the new `ind_link_restore` flag is armed (`emit_int.c:678-680`). All delay-slot fault exits (`emit_cond_fault:195`, `emit_align_fault:197`) call `emit_ind_link_restore`, which writes ctx->gpr[rs] = delay_target (the original jump source). The flag is cleared after the slot (`emit_int.c:686`) and on decline (`emit_int.c:683`). The `a64_buf_t` new fields (`ind_link_restore`, `ind_link_rs` at `a64_emit.h:100-101`) are zero-initialized via the `memset` in `a64_buf_init`. `emit_exit_indirect` (normal non-fault path) correctly does NOT restore, since it reads the target from `delay_target` directly.

### M32-R8-5: Inline IBTC skips SMC check — **PARTIAL** (double-dereference bug)

**C-side changes — correct:**
- `g_smc_ver_epoch` renamed to `dbt_smc_ver_epoch` with `extern` linkage (`dbt.c:10`, `dbt.h:97`)
- Epoch snapshot stored in `ctx->ibtc_epoch` at both C chaining transitions (`dbt_chain_next` at `dbt.c:550-551`, `dbt_main` at `dbt.c:842-843`)
- All 5 C-side references updated

**Trampoline — BUG at `trampoline_a64.S:78-84`:**
```asm
    adrp x16, dbt_smc_ver_epoch
    ldr  x16, [x16, :lo12:dbt_smc_ver_epoch]   /* loads the VALUE */
    ldr  x16, [x16]                              /* BUG: treats value as pointer */
```
The `adrp + ldr :lo12:` pair generates `R_AARCH64_ADR_PREL_PG_HI21` + `R_AARCH64_LDST64_ABS_LO12_NC` relocations, which directly load the 64-bit value at the symbol's address. The third `ldr x16, [x16]` dereferences that value (epoch counter, initially 1) as a memory address — this will SIGSEGV on every inline IBTC hit. The same double-deref exists on the Mach-O path (lines 78-79 + 84). Fix: remove line 84, since the value is already in x16 after the `adrp + ldr` pair.

**Secondary: hardcoded offset `0xa838`** (`trampoline_a64.S:85`) for `MIPS32_CTX_IBTC_EPOCH_OFFSET` is not verified by `tests/check_abi_invariants.c`. A struct layout change would silently break the assembly.

### M32-R8-6: Trace replay mis-bounds REGIMM links — **VERIFIED**

`trace.c:74-77` — `has_delay_slot` now returns `rt <= 3U || (rt >= 0x10U && rt <= 0x13U)`. This correctly identifies BLTZAL/BGEZAL/BLTZALL/BGEZALL (rt 0x10-0x13) as having delay slots, while excluding trap immediates (rt 0x08-0x0E) and undefined encodings (rt 0x04-0x07). Matches `dbt_is_control` at `dbt.c:128-135`.

### M32-R8-7: Batched FP skips intermediate traps — **VERIFIED**

`emit_fp.c:485-506` — `fp_batch_begin` now takes `cur`, loads runtime FCSR, extracts enable bits [11:7] via `UBFM` (shift 7, width 5), and branches with `CBZ` (`is_cbnz=false` per `a64_emit.h:265`): zero enables → skip to normal batch path; non-zero → fall through to `emit_flush` + SINGLE_STEP exit at `cur`. Both call sites updated (`fp_arith_op:554`, `fp_madd_op:668`). Since M32-R8-3 prevents FP ops in delay slots, the `pc = cur` exit is always correct.

---

### Summary

| Item | Status | Notes |
|------|--------|-------|
| M32-R8-1 | **VERIFIED** | kCond[3]: 12→3 (CC) |
| M32-R8-2 | **VERIFIED** | kCond[4]: 13→0 (EQ) |
| M32-R8-3 | **VERIFIED** | Conservative: decline all FP in delay slots |
| M32-R8-4 | **VERIFIED** | Link-before-slot + ind_link_restore |
| M32-R8-5 | **PARTIAL** | C-side correct; trampoline has double-deref crash |
| M32-R8-6 | **VERIFIED** | rt <= 3 \|\| rt in [0x10,0x13] |
| M32-R8-7 | **VERIFIED** | Runtime FCSR enable check at batch open |

### Newly Introduced Defects

1. **HIGH — M32-R8-5 trampoline double-dereference** (`trampoline_a64.S:84`): The `ldr x16, [x16]` after the `adrp + ldr :lo12:` pair treats the epoch counter value as a pointer. Will SIGSEGV on every inline IBTC hit in normal (non-difftest) operation. Fix: delete line 84.

2. **LOW — Unverified hardcoded offset** (`trampoline_a64.S:85`): `movz x17, #0xa838` assumes a specific `ibtc_epoch` struct offset with no compile-time or test-time assertion. Fix: add a `_Static_assert` or extend `check_abi_invariants`.
