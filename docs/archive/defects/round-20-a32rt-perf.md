# rt-series Defect Archive — Round 20: `a32rt` Backend Dispatch, Soft-TLB, VFP/NEON & AOT Audit (2026-11-15)

Audited `a32rt` `master` @ `cc3d3aa` across 6 backend subsystem deep-dives (`A32-R20-D1`..`A32-R20-D4`) plus lock-step `--difftest` verification (`A32-R20-D5`..`A32-R20-D6`), remediated across 5 isolated worker waves (`b4cee33..100af25`, ledger commit `6bf6d76`), and re-verified across 6 post-wave code-review slices (`RC-1`..`RC-4`) with `make check check-headers build-darwin build`, `./tools/run_ios_suite.sh` (`61 / 61` PASS), Regime A1 & Regime A2 `--auto-aot` warm reload (`blocks_compiled=0`), `test-m4` DBT PASS, and lock-step `--difftest` (`0` divergences). Paired with [`docs/PERF.md`](../../PERF.md) (`A32-R20-P0`..`A32-R20-P15`, `16 / 16` resolved).

| Runtime | Audited Revision | Remediated Commit | Items (Round 20) |
|---|---|---|---:|
| `a32rt` | `cc3d3aa` | `6bf6d76` (`100af25`) | `6 / 6` |

---

## 1. DBT Dispatch, Regime A2 AOT, VM32/Soft-TLB & VFP Slot Defects (`A32-R20-D1`..`D4`)

- [x] **A32-R20-D1 — High — DBT/RAS — `cur_entry->ret_entry` permanently `NULL` (`ras_hits = 0`) & missing `POP`/`LDR` return hints**
  - **Where**: `a32rt` `src/dbt/dbt_jit_run.c`, `src/core/core_emit_exit.c`, `src/core/core_emit_shared.c` @ `cc3d3aa`.
  - **What breaks / Why**: On a first `BL callee`, the return block (`LR`) is not yet compiled (`found_e == NULL`), so `set_ht_ret_slot_locked` is skipped while `try_chain_entries` chains the caller directly to `callee`; the caller never exits slow again, leaving `ret_entry == NULL` permanently (`ras_hits = 0`) while `BX LR` still runs dead inline RAS pop probes and `POP {.., pc}` / `LDR pc, [sp], #4` omit `is_return`.
  - **Fix**: Record unresolved `caller` in `ctx->ras[top]`, back-patch `caller->ret_entry` when the return block compiles on first return, gate inline 64-entry RAS pop on `b->is_return` across `BX LR` / `MOV PC, LR` / `POP {.., pc}` / `LDR PC, [SP], #4`, and record dedicated `ras_hits` / `ibtc_hits` under `--stats` (`ras_hits = 3,571,175` on `bench_suite.c --full`).

- [x] **A32-R20-D2 — High — AOT — Contended `a32_aot_site_fetch` drops fault-recovery sites & stale Regime A2 AOT lockout**
  - **Where**: `a32rt` `src/dbt/dbt_aot_cache.c`, `src/dbt/aot/aot_sites.c` @ `cc3d3aa`.
  - **What breaks / Why**: `write_block_cb` silently wrote AOT blocks without fault-recovery site records when `a32_aot_site_fetch` returned `-EAGAIN` on `trylock` contention; `compute_elf_hash` folded `ctx->guest_base` into the cache key even though emitted A64 code is parametric in `x20`; stale pre-`A32-IOS-P4` Regime A2 checks disabled `--aot` / `--auto-aot` on macOS despite position-independent Soft-TLB addressing.
  - **Fix**: Replace `trylock` drop with bounded spin-acquire (`site_lock_acquire`), drop `guest_base` from cache hashing while rebasing PIE `load_bias` on site records, verify `aot_abs64 == 0` (`MOVZ/MOVK hw>=2` fail-closed check), and serialize fault sites inline in `.bin` (`blocks_compiled=0` on Regime A2 warm reload).

- [x] **A32-R20-D3 — High — VM32/SMC — `A32_PROT_WATCH` bypassed on `tlb_fill`, 32 MiB startup BSS walk & uncoalesced `vm32` atomics/`mprotect`**
  - **Where**: `a32rt` `src/vm/vm32.c`, `src/vm/vm32.h`, `src/vm/vm_jit_mem.c` @ `cc3d3aa`.
  - **What breaks / Why**: `a32_vm32_tlb_fill` populated `write_tag` from mapping `writable` without clearing it on `A32_PROT_WATCH` translated code pages; `a32_vm32_tlb_invalidate_all()` unconditionally dirtied all 32 MiB of Soft-TLB BSS at startup; `sync_region` executed 64-entry `vm32_bump_spanned` atomics and uncoalesced `mprotect` syscalls per 4 KiB page.
  - **Fix**: Switch to 16-byte `ntag = ~page_tag` Soft-TLB entries honoring `A32_PROT_WATCH`, lazy host reservations + zero-RSS `tlb[0]` init (`ns_vm_init`: `6.23 ms -> 94–199 µs` on Darwin, `19 µs` on Linux), range-level `vm32_bump_spanned`, and coalesced `mprotect` + APRR flushes (`ns_wx_flush`: `126 µs -> 9–18 µs`).

- [x] **A32-R20-D4 — Medium — VFP/DBT — Block-wide `vfp_preheader_ineligible` disables all loop VFP register promotion on any width overlap**
  - **Where**: `a32rt` `src/core/core_emit_alu.c`, `src/interp/interp_vfp_cache.c` @ `cc3d3aa`.
  - **What breaks / Why**: Touching both `S_k` and `D_{k>>1}` / `Q_{k>>2}` anywhere in a block disabled loop-preheader VFP register promotion for every other non-overlapping `D8..D31` register in the loop (`armv7s` `vfp_simd`).
  - **Fix**: Implement the 22-slot (`v8..v29`) VFP/NEON register cache with exact `S`/`D`/`Q` alias invalidation and wire `a32_vfp_record_preheader` directly into `cache_src` / `cache_dst`.

---

## 2. Reference Interpreter Precision Defects Found via `--difftest` (`A32-R20-D5`..`D6`)

- [x] **A32-R20-D5 — High — INTERP/NEON — `vfp_mcr_mrc` `opc1` mask hijacks `VDUP.32 Dd/Qd, Rt` (`348b299`)**
  - **Where**: `a32rt` `src/interp/interp_vfp.c:340, 388`.
  - **What breaks / Why**: `vfp_mcr_mrc` checked `((opc1 & 2U) == 0U)` instead of `(opc1 == 0U || opc1 == 1U)`, intercepting `VDUP.32` (`opc1 == 4, 5`) as a scalar single-lane `VMOV` before `i_vfp_neon_int` could run.
  - **Fix**: Restrict the 32-bit `VMOV` lane check to `(opc1 == 0U || opc1 == 1U)`.

- [x] **A32-R20-D6 — Medium — INTERP/VFP — Host `-O2` folds `(-d + p)` to `(p - d)` in `VNMLS`, losing QNaN sign negation (`9274aff`)**
  - **Where**: `a32rt` `src/interp/interp_vfp.c:789, 820`.
  - **What breaks / Why**: ARMv7-A defines `VNMLS` as `FPAdd(FPNeg(Vd), FPMul(Vn, Vm))`, which negates the sign bit of a quiet NaN accumulator `Vd` (`0x7FC01234 -> 0xFFC01234` when `DN=0`). Host Clang `-O2` rewrote `(-d + p)` into `FSUB` (`p - d`), leaving QNaN `d`'s sign bit un-negated and diverging under `--difftest` on `test-m4`.
  - **Fix**: Materialize `volatile` `-d` prior to addition so `FNEG` + `FADD` executes as architecturally specified.

---

## 3. Pre-Merge Review Checkpoint Hardening (`RC-1`..`RC-4`, `026566a..100af25`)

Caught during the 6-slice post-wave machine-code review and remediated prior to merge sign-off:
- **Soft-TLB Cross-Page & Grouped Cold Stubs (`src/core/core_emit_mem.c`)**: Routed page-straddling wrap/page-2 misses in `queue_cold_spanN` to `f2` (`addr_w + span - 1`) instead of `f1`, bounded `cold_words` writes, scaled grouped cold-word reservation to `(n + 1U) * (42U + 2U * dirty_vfp)`, and flushed dirty VFP slots on the inline fallback path.
- **Dispatch & AOT/iOS Guards (`core_emit_exit.c`, `trampoline.S`, `aot_sites.c`, `ios_stubs_time.c`)**: Added `_Static_assert`s for all inline exit/RAS/IBTC context offsets, restored `ldar w21, [x28]` acquire ordering in `trampoline.S` `.Lrun_loop`, bounded `site_lock_acquire` spin count, and enforced `PROT_READ | PROT_WRITE` range checks on iOS timer data pointers.
- **A32/T32 Predication, Shifter & 4-Bit NZCV Liveness (`interp_pred_imm.c`, `interp_a32_dp.c`, `interp_a32_ctl.c`, `interp_t16.c`, `interp_t32_dp.c`)**: Rejected unsupported `ROR` on A64 `ADD`/`SUB` and `imm5 == 0` (`LSR/ASR #32`, `RRX`) in shifted-reg fusion, excluded `MULS`/`MLAS` from non-flag-writing skip merging, preserved `C`/`V` on unencodable `S=1` logical immediates and conditional `RRX`/`MRS`, preserved post-indexed `Rm == Rt` shifts, and tightened 4-bit NZCV liveness across `CMP.W`/`TST.W` vs. `LDRH`/`LDRD`/mid-block branches.
- **VFP Cache Eviction Ordering (`interp_neon_alu.c`)**: Acquired `rd = a64_vfp_inout_*` prior to `rn`/`rm` so clean-slot eviction cannot alias a source operand register.
