All data collected. Here's the full per-item review.

---

## Round-11 Signal/Fault Remediation Review — commit `ed8943d`

**Files changed**: `src/os/signals_i386.c` (+59), `src/os/sys_pass.c` (+41, −6)

### Curated C11 Compliance

| Check | Result |
|---|---|
| No VLAs | Pass — all arrays are fixed-size |
| No `.c` includes | Pass — grep clean |
| `signals_i386.c` | 780 lines (< 900) |
| `sys_pass.c` | 544 lines (< 900) |

---

### I686-R11-1 — `rt_sigpending` always returns empty: **VERIFIED**

**sys_pass.c:224-241.** The zeroed buffer is replaced with `__atomic_load_n(&ctx->pending_signals, __ATOMIC_SEQ_CST) & ctx->sig_mask`, written into `out[8]` via `memcpy`. This matches kernel `do_sigpending()` which returns `(shared_pending | thread_pending) & blocked`. The `sig_mask` read on line 234 is a plain load (not `__atomic_load_n`), which is technically inconsistent with the atomic pending read, but `sigpending` is inherently a snapshot — the set can change between the read and the guest-copy. Not a bug.

---

### I686-R11-2 — DF not cleared on handler entry: **VERIFIED**

**signals_i386.c:374-376.** `ctx->eflags &= ~I686_EF_DF` is placed after `sc.eflags = i686_flags_read(ctx)` (line 233, which captures pre-delivery eflags including DF into the sigcontext for later restore) and before `ctx->eip = ga->handler` (line 380). `I686_EF_DF` = `(1U << 10)` at `i686rt.h:51`. The i386 ABI guarantee (DF=0 at entry) is met without losing the saved DF.

---

### I686-R11-3 — `rt_sigaction` accepts SIGKILL/SIGSTOP: **VERIFIED**

**sys_pass.c:137-139.** `if (act_va != 0U && (sig == 9U || sig == 19U)) return -EINVAL;` — rejects setting a disposition for SIGKILL(9)/SIGSTOP(19), but allows querying with `act_va == 0`. Returns `-EINVAL` matching kernel semantics.

---

### I686-R11-4 — `rt_sigprocmask` stores SIGKILL/SIGSTOP bits: **VERIFIED**

**sys_pass.c:204.** `m &= ~((1ULL << 8) | (1ULL << 18));` strips bits 8 and 18 (0-indexed: SIGKILL=9 → bit 8, SIGSTOP=19 → bit 18) before the SIG_BLOCK/UNBLOCK/SETMASK operation. For `SIG_UNBLOCK`, clearing these bits in `m` means `~m` has them set, so the AND preserves whatever is in `sig_mask` for those positions (already 0, so harmless). Correct for all three `how` paths.

---

### I686-R11-5 — `sigaltstack` skips MINSIGSTKSZ and flag validation: **VERIFIED**

**sys_pass.c:257-276.** Three new checks in kernel order:

1. **EPERM** (lines 264-266): rejects when already on the altstack (`altstack_onstack != 0` or stale `altstack_flags & 1U`).
2. **EINVAL** (line 270): `flags & ~(2U | 0x80000000U)` rejects everything except `SS_DISABLE`(2) and `SS_AUTODISARM`(0x80000000). This correctly rejects `SS_ONSTACK`(1) as an input flag, matching modern kernels (4.7+) where `SS_FLAG_BITS = SS_AUTODISARM` and the check is `ss_flags & ~SS_DISABLE & ~SS_FLAG_BITS`.
3. **ENOMEM** (line 273): `size < 2048U` when not `SS_DISABLE`. i386 `MINSIGSTKSZ` = 2048.

The commit block at lines 288-299 also properly handles `SS_DISABLE`: zeroes sp/size when disabling.

---

### I686-R11-6 — SS_AUTODISARM stored but never honored: **VERIFIED**

Two-part fix:

**Delivery** (signals_i386.c:147-152, 317-332): When `SA_ONSTACK` delivery hits an `SS_AUTODISARM` altstack, the pre-delivery state is saved locally, then written to `uc_stack` at `frame + 0x90 + 8` (ucontext offset 8 = `uc_stack`, verified: `uc_flags`(4) + `uc_link`(4) = 8). The write is rt-only (non-rt frames lack a ucontext, matching kernel — non-rt `sys_sigreturn` never calls `restore_altstack`). The live altstack is then set to `SS_DISABLE`.

**Sigreturn** (signals_i386.c:447-466): On rt sigreturn, reads `uc_stack` from the same frame offset. If `s_flags & 0x80000000U` (SS_AUTODISARM), restores the pre-delivery altstack. The `was_onstack` guard (captured at line 423 before clearing) conditionally strips `SS_ONSTACK` from the restored flags, matching kernel `restore_altstack()` semantics.

For non-AUTODISARM frames, `uc_stack` is zero-filled (from the `memset` in frame build), so `s_flags = 0` and the `0x80000000U` check correctly skips the restore.

---

### I686-R11-7 — signal fpstate zeroes x87 FIP/FDP/opcode: **VERIFIED**

**Build** (signals_i386.c:177-181): Saves `ctx->fpu_ip` → `fp.fip` + `fp.fpu_ip2`, `ctx->fpu_dp` → `fp.foo` + `fp.fpu_dp2`, `ctx->fop` → `fp.fop`. Both fsave-header and FXSAVE-image positions populated. Field types match: `fip/foo` are `uint32_t` (sigframe_i386.h:48), `fop` is `uint16_t` (sigframe_i386.h:54), `fpu_ip2/fpu_dp2` are `uint32_t` (sigframe_i386.h:55,57), and ctx fields are `uint32_t fpu_ip`, `uint32_t fpu_dp`, `uint16_t fop` (i686rt.h:175-177).

**Restore** (signals_i386.c:504-506): `ctx->fop = fp.fop` (direct), `ctx->fpu_ip = (fp.fpu_ip2 != 0U) ? fp.fpu_ip2 : fp.fip` (prefers FXSAVE, falls back to fsave), same for `fpu_dp`. The fallback is a pragmatic choice: handlers that only edit the legacy fsave header still round-trip, and a handler zeroing only `fpu_ip2` would get the stale fsave value — a very minor deviation from kernel FXRSTOR semantics, but not a practical concern.

**Note**: The audit mentions `fcs`/`fos` (fsave segment selectors for FIP/FDP) as zeroed; the fix addresses `fip`/`foo`/`fop`/`fpu_ip2`/`fpu_dp2` but not `fcs`/`fos`. The ctx doesn't track these selectors separately, and modern kernels zero them in FXSAVE images anyway (security). Inconsequential.

---

### Newly Introduced Bugs

None found. Specific checks:

- No TOCTOU on the `staged` buffer in `sys_sigaltstack` (local copy, re-read from same buffer at line 289).
- AUTODISARM frame offset arithmetic verified against i386 ucontext layout.
- Unconditional uc_stack read in sigreturn is safe — zero-filled frames fail the `0x80000000U` flag check.
- The `disarm_altstack` flag is properly scoped; initialized to 0, only set when AUTODISARM is active.
- No integer overflow paths in the new mask arithmetic.

### Summary

All 7 items **VERIFIED**. No regressions, no Curated C11 violations, both files under 900 lines. One very minor semantic note on FIP restore fallback (FXSAVE-preferred, fsave-fallback differs from kernel's raw FXRSTOR) and unaddressed `fcs`/`fos` fields — neither is a practical defect.
