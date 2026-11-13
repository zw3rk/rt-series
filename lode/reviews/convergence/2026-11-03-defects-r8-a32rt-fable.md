I have all the information needed. Here's the review:

---

## Round-8 Remediation Review — `fd39abd`

### A32-R8-1 — Missing `DC CVAU` in IALLU path: **VERIFIED**

**Evidence**: `src/vm/vm_jit_mem.c:84-98`

The fix inserts a per-cacheline `DC CVAU` loop (lines 87-89) followed by `DSB ISH` (line 90) before the existing single `IC IVAU; DSB ISH; ISB` (lines 92-97) in the `A32H_CAP_ICACHE_TRAP_IALLU` branch. This matches the structure of the non-trapped path at lines 101-112 which does: DC CVAU loop → DSB → IC IVAU loop → DSB → ISB. The loop variable `p` starts from the 64-byte-aligned `addr` and iterates to `end`, same as the non-trapped path. Correct and complete.

---

### A32-R8-2 — RAS return key uses callee `T`, not caller mode: **VERIFIED**

**Evidence**: `src/dbt/dbt_jit_run.c:392-393`

The fix derives `ret_thumb` from `ctx->regs[14] & 1U` (LR bit\[0\] = return-address mode) instead of reading `is_thumb` (which is the callee's execution mode post-interwork). `a32_make_key(lr_pc, ret_thumb)` at line 393 now correctly encodes the return mode into the RAS key, so the predicted return will match.

`a32_ibtc_hash(ret_key, is_thumb)` at line 394 still passes `is_thumb` rather than `ret_thumb`. This is **functionally harmless**: `a32_ibtc_hash` (`src/a32rt.h:229`) voids the bool parameter and hashes only on `aligned_pc >> 1`. It is a cosmetic inconsistency — if mode-dependent hashing is ever added, this call would silently break. Worth a cleanup but not a defect today.

---

### A32-R8-3 — A2 Soft-TLB fault exit loses ITSTATE: **VERIFIED**

**Evidence**: `src/vm/vm_jit_state.c:19,26-29,34` + `src/core/core_emit_mem.c:12,17-24,95,119,149,158`

Plumbing: `a32_jit_record_pc_map` (line 34) now stores `itstate` into `g_last_record_itstate` alongside the existing `g_last_record_pc`. `a32_jit_last_record_itstate()` (line 26) exposes it. Both globals are protected by the JIT lock.

Emission: `emit_soft_tlb_check` retrieves `itstate` at line 95 and calls the new `emit_soft_tlb_fault_itstate` helper on all three fault-exit paths:

| Path | Location | Covered |
|---|---|---|
| Single-byte TLB miss | `core_emit_mem.c:119` | yes |
| Cross-page second-page fault | `core_emit_mem.c:149` | yes |
| Cross-page first-page fault | `core_emit_mem.c:158` | yes |

The helper (lines 17-24) conditionally emits `MOV imm32 + STR` to `ctx->itstate` only when `(itstate & 0x0FU) != 0U`, matching the project's IT-active convention (`a32rt.h:235`). When not in an IT block, zero instructions are emitted — no overhead on the fast path. Correct and complete.

---

### Newly Introduced Bugs

**None found.** Specifically checked:

- **Register clobber**: `emit_soft_tlb_fault_itstate` uses `A64_TMP0` for the MOV+STR pair. This is a scratch temp, distinct from `addr_w` (the guest address in w-register passed to the enclosing function). No conflict.
- **Thread safety**: `g_last_record_itstate` follows the same single-writer-under-JIT-lock pattern as `g_last_record_pc`. Safe.
- **IBTC hash parameter** (noted above): cosmetic inconsistency, not functional.

### Curated C11 Compliance

| Check | Result |
|---|---|
| No VLAs | Pass (enforced by `-Werror=vla`) |
| No `.c` includes | Pass (grep clean) |
| File lengths ≤ 900 lines | Pass: `core_emit_mem.c` 871, `dbt_jit_run.c` 597, `vm_jit_mem.c` 348, `vm_jit_state.c` 550 |
| Fixed-width integers | Pass — all new code uses `uint32_t`, `uintptr_t`, `bool`, `size_t` |
| No forbidden functions | Pass |

---

**Verdict**: All three items **VERIFIED**. No regressions, no new bugs. One cosmetic note: `a32_ibtc_hash(ret_key, is_thumb)` at `dbt_jit_run.c:394` should pass `ret_thumb` for consistency, even though the parameter is currently unused.
