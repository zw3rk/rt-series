I now have complete evidence for the review. Here is the analysis:

---

## Round-8 DBT/JIT Remediation Review — Commit `9590c4b`

### M64-R8-1: JR/JALR misaligned target skips delay slot — **VERIFIED**

**Defect**: DBT emitted `TBNZ` alignment checks on the target *before* the delay slot, faulting at the branch PC. The oracle defers alignment until after link + slot and faults at the *target*.

**Fix** (`emit_int.c:416-448`):
1. Target is loaded into `EI_A` (x21) then parked in `EI_S` (x25) *before* the slot (line 418-419)
2. Link writes next if linking (line 420-422)
3. Delay slot runs via `ei_one()` (line 428)
4. `TBNZ` alignment checks now test `EI_S` (x25) *after* the slot (lines 436-437)
5. Fault epilogue uses new `ei_exit_fault_dyn(e, EI_S)` (line 446), which sets `ctx->pc` to the *target value* (not the branch PC)

**Evidence**: The old code had `s1 = ei_tbz(...)` before `ei_one(slot)` and `ei_exit_fault_reg(e, pc, EI_A)` (faulting at branch PC). The new code moves both TBNZ checks after the slot and faults at the dynamic target in x25. `ei_exit_fault_dyn` (lines 196-206) correctly stores the 64-bit target in `ctx->pc` and `scratch`, matching `mips_fault` semantics. Test `test_r8_jr_order` (test_u0_delay_tlb.c:776-845) verifies emission order: park < slot-store < TBNZ checks, and the fault epilogue reads x25.

### M64-R8-2: Trapping ALU in delay slot loses `in_delay_slot` — **VERIFIED**

**Defect**: Trapping instructions (`ADD`/`DADD`/`SUB`/`DSUB`/`TGE`..`TNE`/`ADDI`/`DADDI`/`TGEI`..`TNEI`) emitted `ei_bfault` inline even when `slot != 0`, without setting `in_delay_slot`. The oracle preserves `in_delay_slot = 1` for guest `BD` bit parity.

**Fix**: Six decline guards inserted, all following the pattern `if (slot != 0) return 1;`:

| Location | Instructions | Guard |
|---|---|---|
| `emit_alu.c:270-272` | ADD/SUB/DADD/DSUB (trapping variants) | `trapping != 0 && slot != 0` |
| `emit_alu.c:335-337` | TGE/TGEU/TLT/TLTU/TEQ/TNE | `slot != 0` |
| `emit_alu.c:601-603` | ADDI | `slot != 0` |
| `emit_alu.c:654-656` | DADDI | `slot != 0` |
| `emit_alu.c:685-687` | TGEI/TGEIU/TLTI/TLTIU/TEQI/TNEI | `slot != 0 && d->rt != 0x1Fu` |

**Evidence**: Non-trapping variants (`ADDU`, `SUBU`, `ADDIU`, `DADDIU`) are unguarded and still emit in slots. The SYNCI carve-out (`d->rt != 0x1Fu`) in `ei_regimm_trap` is correct — SYNCI is a cache maintenance op with no trap. `ei_one` (lines 543, 558, 572) propagates `slot` to all emitters. Test `test_r8_trapping_slots` (lines 652-718) exhaustively covers every trapping funct/opcode declining and every non-trapping neighbour emitting.

### M64-R8-3: Deferred JAL link breaks COP1 slots — **VERIFIED**

**Defect**: The old `fpslot` mechanism deferred `RA = pc+8` past COP1/COP1X delay slots. Two failures: `MFC1 $ra,$f0` in a JAL slot — the deferred link overwrites the slot's RA write; and a faulting `LWXC1` — `dbt_mem_recover` replays only the slot, never writing the missing link.

**Fix** (`emit_int.c:398-404`): Blanket decline — any linking branch with a COP1 (op 0x11) or COP1X (op 0x13) slot returns 1, falling back to `interp_step`. The entire `fpslot` variable and all 6 deferred-link sites (lines that had `fpslot != 0 → ei_link(...)`) are removed. The link is now always written before the slot (line 466-468 for direct, line 420-422 for indirect), matching the oracle.

**Evidence**: The diff removes the `fpslot` variable declaration (old line 282), removes all 6 `if (fpslot != 0) { ei_link(...); }` blocks, and adds the COP1/COP1X decline guard. Test `test_r8_branch_declines` (lines 799-837) verifies JAL+COP1, JAL+COP1X, and BGEZAL+COP1 all decline, while JAL+ADDIU emits.

### M64-R8-4: JALR `rd == rs` link clobbers dynamic-target recovery — **VERIFIED**

**Defect**: For `JALR $t0,$t0`, the link write (`ctx->gpr[rd] = pc+8`) overwrites the source register before a faulting slot. Recovery reads `ctx->gpr[rs]` for `RT_NPC_DYNAMIC_CTX` and gets the wrong target.

**Fix** (`emit_int.c:410-414`):
```c
if (link != 0 && d->rd != 0u && d->rd == d->rs) {
    return 1;
}
```

**Evidence**: The `d->rd != 0u` exclusion is correct: JR encodes as `JALR rd=0` (funct 0x08 at line 375-378) and writes to `$zero` (no-op via `ei_gst` returning early for r==0), so no clobber. JALR with `rd != rs` and `rd == 0` (JR) continue to emit. Test `test_r8_branch_declines` (lines 825-831) verifies `rd==rs` declines while `rd!=rs` and `rd==0` emit.

---

### Additional Changes (not M64-R8-1..4)

- **`test_decode.c`**: bc1t and bc1fl had swapped encodings in test vectors (rt=2 for bc1t, rt=1 for bc1fl). Fixed to rt=1 (BC1T) and rt=2 (BC1FL) per the MIPS COP1 branch encoding. Correct and unrelated to R8 defects.
- **`loader.c`**: Added `#define _DEFAULT_SOURCE` for musl compatibility. Harmless housekeeping.

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None found |
| `.c` includes | None found |
| `sprintf`/`strcpy`/`strcat` | None found |
| `_Generic` / Annex K | None found |
| File line limits (<=900) | `emit_alu.c`: 736, `emit_int.c`: 766, `loader.c`: 869, `test_decode.c`: 547, `test_u0_delay_tlb.c`: 857 — all pass |

### Newly Introduced Bugs

**None found.** The `ei_exit_fault_dyn` function follows the same structure as `ei_exit_fault_reg` (stores 64-bit PC, 32-bit exit_info, clears llbit). The decline guards are conservative (fall back to interp_step, which is always correct). The `EI_S` (x25) register is documented as trampoline-preserved and emitter-unused, with no conflicts in the delay-slot register window (x21-x24).
