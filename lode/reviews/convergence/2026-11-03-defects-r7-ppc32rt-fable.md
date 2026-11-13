All evidence is in. Writing up the report now.

# Review of commit 5a42963 (P32-R7-1..25) against the Round-7 findings

**Verdict:** 17 items verified, 6 partial, 2 regressions. The host suite passes, but it passes partly because the two new test files encode the same wrong FPSCR bit positions as the code they test. The two regressions are a mis-shifted FPCC write that clobbers FPSCR[C] on every float compare, and an NX fetch check that faults the runtime's own on-stack sigreturn trampoline.

Method: full read of the commit diff, the post-commit sources it touches, the two new test files, and the DEFECTS.md Section 4 entries. I ran `make check-line-limits test` (all three host suites pass, exit 0) and a probe program at `/tmp/ppc32rt-r7-probe/probe.c` driving `interp_step` with inputs the committed tests do not cover. Not run: the aarch64 build, the qemu-ppc oracle, or `--difftest`.

## Item classification

| Item | Status | Note |
|---|---|---|
| R7-1 | VERIFIED | D-form, X-form, lmw/stmw, lswi/lswx, lwbrx family, dcbz, SPE loads all commit after success and hold NIP. FP loads already did. |
| R7-2 | VERIFIED | Fetch fault returns before decode. |
| R7-3 | REGRESSION | NX check is correct, but the sigreturn trampoline that signals.c writes into the RW stack frame now faults. See below. |
| R7-4 | VERIFIED | Interpreter store path holds the LL lock across write + invalidation; lock order VM then LL is respected, host-fault path releases it. DBT stores are outside the finding's scope and unchanged. |
| R7-5 | VERIFIED | CR1 at shift 24. |
| R7-6 | VERIFIED | Opposite-sign rule for add, same-sign for sub, doubles and singles. |
| R7-7 | PARTIAL | fsqrt, fdiv, fadd and FMA suppress correctly under VE/ZE. fctiw with VE=1 still commits the saturated word. |
| R7-8 | VERIFIED | Lanes normalized to 0/1, single nibble, no bleed. |
| R7-9 | VERIFIED | Both lanes masked. |
| R7-10 | PARTIAL | Per-lane products fixed, but `a`, `aa` and guarded accumulator semantics are still wrong. |
| R7-11 | VERIFIED | Dispatch tables and 2^31 scaling fixed in all three families. |
| R7-12 | VERIFIED | `>=` boundary checks before every cast. |
| R7-13 | PARTIAL | SPR 512 access, FRMC rounding and status bits work. No pmax/nmax saturation, enables ignored, classic profile also accepts SPR 512, enable-bit defines are one bit high. |
| R7-14 | VERIFIED | One 4-byte read, width validated. |
| R7-15 | VERIFIED | Profile gate before any side effect. |
| R7-16 | VERIFIED | Accumulator starts at zero. |
| R7-17 | VERIFIED | lswx/stswx implemented with XER count, wrap, clearing, fault stop. |
| R7-18 | PARTIAL | mtfsb1/mtfsfi now raise VX/FX; sticky FX is event-based. VX is never recomputed downward, and mtfsf lost the recomputation it had before. |
| R7-19 | PARTIAL | FR is set equal to FI, not "fraction incremented". |
| R7-20 | VERIFIED | Round first, then range check. |
| R7-21 | PARTIAL | VXIMZ now raised, but the NaN operand payload and VXSNAN co-setting are lost. |
| R7-22 | VERIFIED | Single results classified before expansion. |
| R7-23 | REGRESSION | FPCC written to bits 13..16 instead of 12..15, so C is overwritten and FU stale. |
| R7-24 | VERIFIED | XO 371 decoded, 1 MHz monotonic TB. Minor: any TBR value is forwarded to mfspr, so `mftb` with TBR=8 reads LR. |
| R7-25 | VERIFIED | RA!=0 for all update forms, RA!=RT for update loads, before memory access. |

## Findings needing follow-up

**R7-23 (regression).** In this codebase FPSCR value bit = 31 minus the IBM bit number, so C is bit 16 and FPCC is bits 15..12. The code's own classifier agrees: `fp_fprf64` returns 0x11 for a QNaN and it is written at shift 12, putting C at bit 16. The pre-commit compare used `ret << 12` with a mask of `0x1f << 12`, which was right for FPCC and only wrong for clearing C. The commit changed both to shift 13 at `src/interp/fp.c:398`. Probe output:

```
fcmpu eq, C preset:  fpscr=0x00004000   expected 0x00012000  (C lost, EQ landed in FG)
fcmpu lt:            fpscr=0x00010000   expected 0x00008000  (LT landed in C)
fcmpo NaN:           C(bit16)=1         expected C=0          (forced-C line still present)
```

The tests in `check_p32_r7b_defects.c` assert bit 12 as C and bits 13..16 as FPCC, so they pass against the wrong layout. Every float compare now diverges from the qemu oracle in FPSCR.

**R7-3 (regression).** `vm32_page_is_exec` is recorded from the EXEC bit, the ELF loader and mmap paths preserve it, and the stack is recorded read/write only in `ppc32_stack32.c`. When a handler is installed without SA_RESTORER, `ppc32_sig_build_rt_frame` writes `li r0,172; sc` into the frame on that stack and sets LR to it. The probe confirms a fetch from a RW-only page returns `PPC32_EXIT_FAULT`, so such a handler now dies with SIGSEGV on return under the interpreter. The DBT does not check exec permission, so the two engines also disagree. The project's guest tests use musl, which always sets SA_RESTORER, so they do not hit this path. The pre-existing test file was changed to record the window RWX, which hides the issue there too. Linux on 32-bit PowerPC makes the signal stack executable for this reason; the fix is either an exec-mapped trampoline page or marking the frame's page exec when the stack trampoline is used.

**R7-10 (partial).** Per the SPE PEM, the `a` suffix means rD = product and ACC = rD, `aa` means per-lane rD = ACC + product, and guarded forms add a single sign-extended product from the low word's halfword. The committed test uses rD=ACC=0, which hides all three errors:

```
evmwhsmia  rD=5/5 ACC=7/7 -> rD=00000006:00000006 ACC=0000000800000008   expected rD=ACC=00000001:00000001
evmwhsmiaa ACC=0:ffffffff + {1,1} -> ACC=0000000200000000               expected 00000001:00000000 (64-bit carry across lanes)
evmhegsmiaa even halves 1*1 -> ACC=2                                   expected 1 (sums the high-word product too)
```

**R7-7 (partial).** `fp_fctiw_invalid` has no VE check. Probe: fctiw(NaN) with VE=1 writes 0x7fffffff over the sentinel.

**R7-13 (partial).** Overflow produces IEEE infinity, where e500 saturates to pmax with FOVF (probe: efsmul 0x7f000000² gives 0x7f800000). Enable bits are never consulted. A classic-profile `mtspr 512` succeeds instead of UNDEF. The five `SPE_*E` defines in `src/ppc32rt.h` are one bit high (FINXE is 0x40, FOVFE is 0x04, 0x80 is reserved); they are unused, and `SPE_WRITABLE` and the test's expected 0xff3eff7f happen to be correct.

**R7-18 (partial).** `fp_touch` only ever sets VX. After `mtfsb1 7; mtfsb0 7` VX stays 1, and `mtfsf` of field 1 with zero leaves VX set. The pre-commit `mtfsf` recomputed VX as the OR of its sub-bits, which matches qemu, so this is a small regression inside a partial fix.

**R7-19 (partial).** `fp_flags_arith` and `fp_fctiw` set FR whenever FI is set. FR means the fraction was incremented. Probe: fadd(1, 2^-60) and fctiw(2.5) both round down and report FR=1. Hardware reports FR=0. The qemu oracle never sets FR at all, so the previous behavior was oracle-neutral and this one diverges on every inexact result.

**R7-21 (partial).** The VXIMZ check now precedes NaN propagation but returns a default QNaN. Probe: fmadd(0, inf, QNaN 0x7ff80000deadbeef) yields 0x7ff8000000000000. ISA and qemu return the operand NaN. With an SNaN addend, VXSNAN is no longer set either.

## New regressions and verification limits

New or worsened behavior introduced by the commit, in priority order:

1. Float compares write FPCC one bit too high and clobber C (R7-23).
2. Signal return via the on-stack trampoline faults under the interpreter (R7-3).
3. `mtfsf` no longer clears a derived VX (R7-18).
4. FMA with 0*inf and a NaN operand drops the NaN payload and VXSNAN (R7-21).
5. FR now set on rounded-down results, diverging from hardware and oracle (R7-19).
6. `mftb` with an invalid TBR silently reads the matching SPR (R7-24, minor).

The R7 test files are the weak point: they share the FPSCR bit misunderstanding with the code and use zeroed accumulators for the MAC tests. Line limits and the three host suites pass; the aarch64 build, qemu oracle, and difftest were not run in this review, so the oracle divergences above are inferred from the ISA and qemu's known FPSCR layout rather than measured.
