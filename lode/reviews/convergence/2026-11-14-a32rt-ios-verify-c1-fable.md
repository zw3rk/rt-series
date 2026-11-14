Review complete. All eleven files read in full; findings below are limited to what those files prove.

## Residual defects

**1. CRITICAL (P1): the exit-flush FPCR restore clobbers the exit reason in `w16`.**
`a64_emit_fpcr_restore_scalar` (`src/a64_emit.h:350-356`) writes `w16` (TMP1) and `w17` (TMP2). `a64_emit_ret` (`src/core/core_emit_mem.c:610-614`) runs `a64_vfp_emit_exit_flush` *after* callers have already loaded `w15` = exit PC and `w16` = exit reason. When `fpcr_neon_active` is set (any NEON FP op earlier in the block at depth 0, or a hoisted loop), the emitted sequence becomes `movz w16,#reason; ldr w16,[x19,#fpscr]; …; msr fpcr,x16; ret`, so the trampoline reads `w16 = fpscr & 0x07C00000` (`src/trampoline.S:100-103,301,328`). With default FPSCR that is `0`, which falls to the `default:` case in `a32_jit_run` and aborts with `exit_reason=0`. Affected callers: Soft-TLB fault exits `core_emit_mem.c:117,147,156` (Regime A2 faults lose SIGSEGV/SIGBUS delivery), `a64_emit_exit_branch_imm` interwork `:738` (Thumb `blx` to an ARM stub after NEON), `a64_emit_exit_svc :857`, `a64_emit_exit_undef :864` (breaks the UNDEF → interpreter fallback for unimplemented NEON encodings), `a64_emit_exit_bkpt :872`. Note that `a64_vfp_emit_exit_flush` intentionally leaves the flag set, so an earlier flush does not prevent the re-emission.
Minimal fix: make the restore never touch `w15`/`w16`, e.g. in `a64_emit.h`:
```c
a64_emit_ldr_imm_w(b, 23U, A64_XCTX, offsetof(a32_ctx_t, fpscr)); /* x23: chain scratch, dead at every exit */
a64_emit_mov_imm32(b, A64_TMP2, 0x07C00000U);
a64_emit_and_reg_w(b, false, 23U, 23U, A64_TMP2, A64_SHIFT_LSL, 0U);
a64_emit(b, 0xD51B4400U | 23U);
```
and in `a64_emit_exit_branch_reg` move the `mov TMP0, target_reg` (`:747-749`) above the flush (`:746`) so a `target_reg` of TMP1/TMP2 cannot be clobbered either.

**2. MEDIUM (P1): self-loop back-edge and pass-1 `.Lbail` exit without scalar FPCR restore.**
`a64_emit_exit_branch` self-loop path (`core_emit_mem.c:660-686`) never restores scalar FPCR unless the loop was hoisted. (a) Non-hoisted (`!preheader_neon_fpcr`): the body entry at `loop_body_offset` (or offset 0 in pass-1-final code) has static state `fpcr_neon_active == false`, yet the `b loop_body_offset` at `:677-678` is taken with Standard FPSCR live. Any scalar VFP op before the first NEON op in the body runs under FZ=1/DN=1/RN from iteration 2 on, because `vfp_scalar_fpcr_sync` emits nothing when the static flag is false. Triggers only with an unconditional back-edge (a conditional `bne` is covered by the restore in `a64_emit_b_cond_placeholder :545-549`). (b) Pass-1-final (`!self_loop_vfp_active`, e.g. `vfp_preheader_ineligible` via a `VMOV Rt, Dm[x]` ctx access): `.Lbail` at `:679-685` emits `ret` with no flush, leaving Standard FPSCR in the trampoline. On a masked pending signal, `.Lcheck_signals_slow` continues to `.Lsignals_ok` and fast-chains into the next block under NEON FPCR. This violates the "every block/side exit leaves with scalar FPCR" invariant stated at `:574-577`.
Fix: at the top of the self-loop branch (before `emit_exit_sig_check`):
```c
if (b->fpcr_neon_active && !b->preheader_neon_fpcr) {
    a64_emit_fpcr_restore_scalar(b);
    b->fpcr_neon_active = false;
}
```

**3. MEDIUM-LOW (P1/D19): host SIGSEGV path leaves NEON FPCR live across fast-path chaining.**
`host_sig_handler` (`src/signals.c:426-539`) redirects the host `pc` to `lr` (`:531,:535`) with `x16 = A32_EXIT_INTERWORK` but does not touch the saved FPCR in the ucontext. Sigreturn restores the faulting FPCR (Standard FPSCR if the fault hit a guest LDR/STR/VSTR between coalesced NEON ops, which P1 made possible). The trampoline then takes `.Lmode_ok`/the new interwork probe and may chain into the guest handler block via chain/IBTC/RAS without ever reaching the `.Lslow_exit` reset (`trampoline.S:323-325`). `handle_guest_fault` (`dbt_jit_run.c:151-159`) covers only the `A32_EXIT_FAULT` path. Fix: before the register write-back at `:521`, set the saved FPCR to the scalar value: Darwin `uc->uc_mcontext->__ns.__fpcr = ctx->fpscr & 0x07C00000U;` Linux `((uint32_t *)uc->uc_mcontext.__reserved)[3] = …` after checking `fpctx[0] == 0x46508001U`.

**4. LOW (D19): iOS SIGBUS-vs-SIGSEGV mapping is missing on the host-signal fault path.**
`signals.c:496-503` forwards the raw host `sig` to `a32_ios_signals_deliver_sync`. Linux delivers SIGSEGV (`SEGV_ACCERR`) for a protection fault inside a valid mapping, so Regime A1 iOS guests (the "Linux DBT iOS armv7s" target in `PERF.md`) get SIGSEGV where XNU gives SIGBUS. Only `handle_guest_fault` (`dbt_jit_run.c:160-171`) implements the rule. Fix: apply the same `a32_guest_range_ok(ctx, fault_addr, 1U, 0) && fault_addr >= a32_min_va(ctx) ? SIGBUS : SIGSEGV` remap under `ctx->is_ios` before the call at `:500`.

**5. SECURITY (D3 residual): site-payload files bypass every D3 check.**
`a32_aot_site_load` (`src/dbt/aot/aot_sites.c:248-253`) opens `<dir>/a3ts-<guest_pc>.bin` with plain `O_RDONLY`, no `O_NOFOLLOW`, no `S_ISREG`/`st_uid == geteuid()`/mode check. The directory defaults to `/tmp` (`dbt_aot_cache.c:240`) and the name is fully predictable. Decoded `a32_vm32_mem_site_t` records (register indices, offsets, SP rollback deltas) go straight into the fault-recovery registry (`dbt_aot_cache.c:511-513`); the FNV-1a checksum is not authentication. `a32_aot_site_save` (`aot_sites.c:138`) opens with `O_WRONLY|O_CREAT|O_TRUNC` and no `O_NOFOLLOW`/`O_EXCL`, so a pre-planted symlink in `/tmp` makes a32rt truncate and overwrite an arbitrary file owned by the user. `copy_file` (`dbt_aot_cache.c:194`) has the same weakness on its predictable `.tmp.<pid>` name. Fix: mirror `load_cache_from_path :544-555` (`O_NOFOLLOW|O_CLOEXEC` + fstat uid/mode/regular check) in the loader; write via `O_CREAT|O_EXCL|O_NOFOLLOW` to a temp name plus `rename`, as `a32_aot_save_cache :352-353` already does.

**6. CONCURRENCY (D4 residual): the site registry is mutated from unlocked translation.**
`emit_site_record` (`core_emit_mem.c:61-63`) calls `a32_emit_sites_flush` → `a32_aot_site_track` (`aot_sites.c:171-199`) during translation, which per D4 now runs without `jit_lock` in multithreaded guests. `g_site_slots` (`:169`) is a plain global with a check-then-claim `free_slot` scan, so two threads can claim one slot and interleave `base`/`count`/`sites` writes, giving block A the site table of block B. `a32_aot_site_fetch` and the fault-recovery reader are likewise unsynchronised. Fix: guard `a32_aot_site_track/fetch/clear` with a mutex, or move the publish into the locked commit section in `dbt_jit_query.c` (after `:256`).

**7. MINOR (D4): stale staged sites survive into retry attempt 0.**
`dbt_jit_query.c:148-150` resets the site stage only for `attempt > 0`. A translation of the same PC abandoned earlier in this thread (fault at `:217-226`, lookahead `queue_done` at `:202`) leaves `g_site_stage_valid && base == cur_b_pc`, so the next translation appends to the stale records (wrong `host_insn_offset` if the code changed, which is exactly the epoch-change case). Fix: call `a32_emit_sites_reset_block(cur_b_pc)` unconditionally at the top of the attempt loop.

**8. REQUIREMENT GAP (P4): no lock-free pre-check in `a32_jit_lookup_or_compile_entry`.**
`dbt_jit_query.c:45-48` still takes `jit_lock` before the first `g_ht` probe. The `dbt_jit_run.c` half of P4 (`:427-441` lock-free probe, `:451-459` lock only to publish) is implemented; the query-side half named in `PERF.md` is not.

## Verified

| Item | Evidence |
|---|---|
| Trampoline frame 176 B, 16-aligned; `[sp,#160]` spill/reload; encoding `0xF94053F5` = `ldr x21,[sp,#160]` | `trampoline.S:27,54`, `core_emit_mem.c:100` |
| `x18` never referenced in trampoline or emitted sequences | all files |
| Interwork probe: `w0..w14` untouched, `w15` masked only on hit; NZCV never written (no S-form ops) | `trampoline.S:107-194` |
| `CPSR.T` (`[x19,#64]` bit 5) written only in `.Liw_commit_mode`; miss paths reach `.Lslow_exit` with `[x19,#64]` and raw `w15` intact | `:183-194, :300` |
| Single-step/trace/itstate/pending signals force slow exit before any probe | `:113-115` |
| Host FPCR reset on `.Lslow_exit`; FPSR merge preserved | `:310-326` |
| D4: `_Thread_local` site stage and `stage_words`; epoch retry bounded (3 unlocked + 1 locked); install under the same lock that validated `cur_epoch` | `core_emit_mem.c:31-34`, `dbt_jit_query.c:91,147-234,256-294` |
| D3: block cache `O_NOFOLLOW` + `S_ISREG` + `st_uid==geteuid()` + `~0022`; is_ios/regime mixed into hash and header | `dbt_aot_cache.c:125-133,428-435,544-555` |
| D18 DBT side: block `A32_EXIT_BKPT`, interpreter re-step BKPT, and single-step BKPT all deliver SIGTRAP | `dbt_jit_run.c:494-505,555-566,643-651` |
| D19: `handle_guest_fault` FPCR reset + SIGBUS rule; `pthread_jit_write_protect_np(1)` in both run paths | `:147-181,384-386,633-635` |
| P1 pieces: install/restore bit values; `VMSR` installs scalar and clears flag; scalar DP ops synced; `b_cond` restore at depth 0 with hoist exemption; hoisted pass-2 preheader/back-edge/`.Lbail` consistent | `a64_emit.h:340-356`, `interp_vfp_core.c:85-103,274-276`, `core_emit_mem.c:536-554,592-611` |
| P6 consumer: `LC_FUNCTION_STARTS`, `LC_MAIN`, init seeds; iOS skips blind ARM sweep | `dbt_aot_scan.c:163-169,409-430` |

Not verifiable from the provided files: the depth>0 behaviour of `neon_fp_fpcr_begin`/`vfp_scalar_fpcr_sync` (`decode_priv.h`), parity of `a32_ibtc_hash` with the trampoline's `(key>>1)&1023`, and whether any decoder passes TMP1/TMP2 as `target_reg` to `a64_emit_exit_branch_reg`. Note (not counted): the Regime A2 refusal in `a32_aot_save_cache`/`load` (`dbt_aot_cache.c:328-333,571,586`) cites embedded Soft-TLB bases that P4 removed; the guard now needlessly disables P6 persistence on the primary Darwin target.

**8 RESIDUAL DEFECTS** (7 correctness/security, 1 unimplemented P4 requirement)
