Agents are still running — waiting for all four to report back.

First agent back (SSE/DBT/vm86). Waiting for the remaining three.

Two agents back. Still waiting for the segment/stack/branch and x87 agents.

Three of four agents complete. Waiting on the x87 agent.

All four agents complete. Compiling the final report now.

---

# Round-7 Remediation Review — commit 31995d8

**Method:** Static code + diff review only (no builds, tests, or external fetches).
**Sources:** `git show 31995d8`, current tree, and the Astra defect report.

## Summary

| Verdict | Count |
|---------|-------|
| VERIFIED | 41 |
| PARTIAL | 12 |
| REGRESSION | 2 |
| **Total** | **55** |

---

## Per-finding verdicts

### VERIFIED (41)

| Finding | Sev | Summary | Notes |
|---------|-----|---------|-------|
| R7-1 | HIGH | Subpage access width | F3/F2 packed ops now classified as 16-byte. Pre-existing gap: MMX PUNPCKL* still 4 vs 8. |
| R7-2 | HIGH | LES/LDS/LSS/LFS/LGS | `mem_load` now receives bit widths; register-form #UD added. |
| R7-3 | HIGH | Far CALL/JMP 16:32 | New `far_off`/`far_sel` fields; no UB shifts. |
| R7-4 | HIGH | ModR/M DS vs SS | `ea_default_seg` selects SS from base register, not mod. |
| R7-5 | HIGH | 16-bit EA wrapping | Interpreter masks to 16 bits; DBT emits UXTH before seg base add. |
| R7-6 | MED | SIMD mandatory 66 vs CS.D | Raw `pfx_66` preserved; all SIMD handlers use it. |
| R7-7 | MED | LOCK prefix validation | Whitelist-based `x86_lock_legal()`. Minor: LOCK XCHG reg,reg still accepted. |
| R7-8 | HIGH | Null/nonexistent selectors | Null CS/SS → #GP; unknown GDT → #GP; null data faults on use. |
| R7-10 | HIGH | Expand-down limits | Type classification fixed; validates `(limit, upper_bound]` with B. |
| R7-11 | HIGH | Stack ops + SS.B | New `ctx->ss_b`; push/pop/call/ret use SP width + SS base. Minor: `h_ret_iw` doesn't wrap. |
| R7-13 | HIGH | Faulting segment pops | Peek-then-validate-then-commit ordering throughout. |
| R7-14 | MED | modify_ldt readback | S bit, G flag, and page-granular limit encoding all correct. |
| R7-15 | HIGH | Stale flags on fault | Flags committed after stores; lazy state checkpointed per instruction. |
| R7-16 | HIGH | LODSB/LODSW | `w * 8U` passed to `x86_reg_write`; SCAS/STOS also fixed. |
| R7-18 | MED | XADD same-register | Aliasing handled; single write of `old + src`. |
| R7-19 | HIGH | Signal lazy EFLAGS | Materialize before save; clear lazy state on restore. |
| R7-20 | HIGH | Sigreturn EAX clobber | Syscall 119/173 skips EAX assignment on success. |
| R7-21 | HIGH | Sigreturn x87 TOP | `x87_set_top` called from saved status word. |
| R7-22 | HIGH | Sync fault delivery | UNDEF/TRAP/FAULT all routed through delivery. Minor: trapno not set to 6 for SIGILL. |
| R7-24 | HIGH | f32 store sign | `to_ieee_bits` parameterized by sign-bit position. |
| R7-25 | HIGH | Rounding UB + carry | `eff >= 64` handled; UINT64_MAX wrap detected. |
| R7-26 | HIGH | x87 int store UB + exc | `eff < 0` branch; IE/PE reported; narrow overflow → indefinite + IE. |
| R7-27 | HIGH | FCMOV decoded as FCOM | DA /0-/3 → `FCMOV_STi`; no pop, no compare. FCMOVN* still unimplemented. |
| R7-28 | HIGH | FXSAVE/FXRSTOR tags | Polarity corrected; empty slots preserved through save/restore. |
| R7-32 | HIGH | x87 rounding mode race | `_Thread_local` RC/PC per context. |
| R7-33 | MED | Exact FRNDINT | Large values bypass int64; 0.75 rounds correctly. Minor: -0 → +0. |
| R7-34 | MED | MOVSS/MOVSD upper lanes | Memory loads zero destination before copy. |
| R7-35 | MED | PSRLQ/PSLLQ oversized | Count > 63 zeroes lanes. |
| R7-37 | MED | FXRSTOR DAZ/MXCSR | DAZ preserved; reserved bits → #GP. |
| R7-38 | MED | Trig C2 | Range failure preserves operand, sets C2; success clears C2. |
| R7-39 | MED | Directed rounding | Residual sign and toward-zero logic corrected. |
| R7-40 | MED | f64 subnormal → ext | Initial exponent corrected to −1023. |
| R7-45 | MED | FSCALE/FXTRACT UB | Special values handled before `ilogb`/int cast. |
| R7-46 | MED | FPATAN +∞ X | π/4 vs 3π/4 selected by X sign. |
| R7-47 | MED | DBT unsigned MUL | CF/OF from `upper != 0`. |
| R7-48 | HIGH | DBT MMX logical ops | MMX forms return D2 (interpreter fallback). |
| R7-49 | MED | DBT PUNPCKHDQ | Correct lanes {d2,s2,d3,s3}. |
| R7-51 | HIGH | DBT FP + MXCSR | Affected paths return D2 (interpreter fallback). |
| R7-52 | HIGH | vm86 ESP + 16-bit writes | ESP installed on entry; `r16_set` preserves upper half. |
| R7-54 | HIGH | vm86 prefix loop | 15-byte limit enforced; fault on overflow. |
| R7-55 | MED | 15-byte decode budget | Checked cursor on every fetch. Edge: 4 GiB wrap → decode fail. |

### PARTIAL (12)

| Finding | Sev | Summary | Residual |
|---------|-----|---------|----------|
| R7-9 | HIGH | Segment protection bypass | x87 memory ops still bypass segment checks; GDT TLS descriptor limits/types unenforced. |
| R7-12 | MED | ENTER/LEAVE operand-size | Level-0/1 correct. Level > 1 display-copy loop uses wrong size for EBP decrement. |
| R7-17 | HIGH | CMPXCHG mismatch | LOCK and CMPXCHG8B probe correctly. Non-locked 8/16/32 path skips segment write check on mismatch when host page is writable. |
| R7-23 | MED | Privileged instructions | CLI/STI/HLT → #GP. IN/OUT/MOV CR/DR/RDMSR/WRMSR still give SIGILL (not #GP) in flat 32-bit mode. |
| R7-29 | HIGH | Legacy x87 env/state | 32-bit layout correct. 16-bit layout wrong at offsets +10/+12 (opcode vs FDP sel). Register order is physical, not ST(i). |
| R7-30 | HIGH | Unmasked FP exceptions | x87 pending-ES check works, but no-wait ops (FNCLEX, FNSTSW, etc.) also trapped. SSE `sse_done` faults on sticky flags, not just newly raised. SSE dest written before fault. |
| R7-31 | HIGH | x87 stack under/overflow | Most opcodes covered. FSCALE skips ST(1); FSINCOS/FPTAN clobber ST(0) before push check; masked overflow pushes real value not indefinite. |
| R7-36 | MED | QNaN exception classify | SSE side correct. **x87 regression:** `do_fcomi` hard-codes quiet rule — FCOMI/FCOMIP no longer signal IE on QNaN. |
| R7-41 | MED | MMX x87 alias state | MMX remap uses `x87_top` offset. SDM requires TOP=0 + all tags valid on any MMX insn; not implemented. |
| R7-42 | MED | Exact FPREM1 | Quotient-bit reporting fixed (`prem_qq`). Nearest-quotient selection for exp-diff −1 appears pre-existing; unclear if the core defect is addressed. |
| R7-50 | MED | DBT byte shifts | Immediate base word fixed (0x6E000000). **Operands still swapped** — PSRLDQ emits left shift, PSLLDQ emits right shift. Still broken. |
| R7-53 | MED | vm86 EA decoding | Register table and default segment fixed. **0x67 regression:** `modrm_ea` returns 0 (== `I686_VM86_SIGNAL`), callers treat 0 as success, use uninitialized seg/off. |

### REGRESSION (2)

| Finding | Sev | Summary | Detail |
|---------|-----|---------|--------|
| R7-43 | MED | Aligned SIMD alignment faults | `sse_align16` added to `h_movdqa`, which also serves **MOVDQU** (F3 prefix). Any unaligned MOVDQU now faults. Guard must check `pfx_66 && pfx_rep == 0`. DBT alignment still unchecked. |
| R7-44 | MED | Default x87 exception flags | `d_div` now treats **Inf/0** as invalid (returns NaN + IE). Hardware returns ±Inf with no flags. Only finite/0 should set ZE. |

---

## New bugs introduced by the commit

### HIGH severity

| # | Area | Description |
|---|------|-------------|
| N1 | DBT | **DBT effectively disabled for all normal i386 processes.** `i686_seg_dbt_eligible` rejects null FS/GS, but Linux i386 initializes FS=0. Every standard guest falls through to the interpreter. |
| N2 | SSE | **MOVDQU faults on misaligned memory** (R7-43 regression). `sse_align16` runs unconditionally for non-MMX, non-F2 paths in `h_movdqa`, catching MOVDQU (F3). |
| N3 | x87 | **No-wait ops re-fault forever.** `fp_pending_trap` fires for FNCLEX/FNINIT/FNSTSW/FNSTCW/FNSTENV/FNSAVE/FXSAVE/FXRSTOR. A SIGFPE handler running FNCLEX faults again infinitely. |
| N4 | x87 | **`d_div` Inf/0 → NaN** (R7-44 regression). Should return ±Inf with no flags. |
| N5 | x87 | **FCOMI/FCOMIP lost IE on QNaN** (R7-36 regression). `do_fcomi` hard-codes quiet-compare; needs a `ucom` parameter. |

### MEDIUM severity

| # | Area | Description |
|---|------|-------------|
| N6 | SSE | **`sse_done` faults on old sticky MXCSR flags.** After `LDMXCSR` unmasks a previously-set flag, every subsequent SSE instruction (even MOVAPS) raises spurious #XM. |
| N7 | DBT | **PSRLDQ/PSLLDQ operands still swapped** despite base-word fix (R7-50). Directions remain reversed. |
| N8 | x87 | **FSINCOS/FPTAN clobber ST(0) before push overflow check.** Unmasked stack overflow leaves ST(0) modified. |
| N9 | seg | **POP SS applies new SS.B to ESP write.** If the popped SS has a different B bit, the ESP commit uses the wrong width. |
| N10 | vm86 | **0x67 in vm86 uses uninitialized seg/off** (R7-53 regression). `modrm_ea` returns 0 = `I686_VM86_SIGNAL`; callers treat it as a valid EA. |

### LOW severity

| # | Area | Description |
|---|------|-------------|
| N11 | decode | LOCK XCHG reg,reg accepted (should be #UD per SDM). |
| N12 | signals | SIGILL trapno is 0 or raw op-id, not 6; si_code is 0, not ILL_ILLOPN. |
| N13 | seg | SS limit violations report #GP (trap 13) instead of #SS (trap 12). |
| N14 | x87 | FSCALE doesn't validate ST(1) emptiness (no IE/SF on empty). |
| N15 | branch | `h_ret_iw` doesn't wrap SP on 16-bit stack. |
| N16 | x87 | 16-bit FNSTENV/FRSTOR layout wrong at +10/+12; register order physical not ST(i). |
| N17 | x87 | MMX instructions remap through `x87_top` instead of forcing TOP=0 + all tags valid. |
| N18 | decode | Instructions straddling 4 GiB boundary fail to decode. |

---

## Scorecard

- **41/55 (75%) fully verified** — the commit resolves the stated root causes.
- **12/55 (22%) partial** — core fix present but residual gaps remain (often edge cases or secondary paths).
- **2/55 (4%) regression** — fix introduces a new correctness defect worse than the status quo.
- **5 high-severity new bugs** (N1–N5) introduced by the commit, of which N1 (DBT disabled) and N3 (no-wait re-fault loop) are likely the most impactful in practice.
