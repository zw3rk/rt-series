I've confirmed the oracle semantics against QEMU v7.2 sources and have everything needed. Writing the report now.

## Review of `cfbe555` — Round-7 remediation (M32-R7-1..20)

**Headline:** the commit does not build with the production toolchain. The cross GCC with the Makefile's flags rejects `src/interp/interp.c` because the helper `fault_at` is now unused and `-Werror` is on. Beyond that, 12 items are fully fixed, 6 are partial, and 2 introduce regressions, the most serious being that FR=0 double aliasing was added to the interpreter only, so MTHC1/MTHC1 and the DBT engine now disagree with it under the default FR=0 mode.

### Verification performed

| Check | Result |
|---|---|
| `make check-line-limits` | pass (fp.c is exactly 900 lines, interp.c 899) |
| `make test` (host-native, includes new T9..T12) | 137 checks, 0 failures |
| Host clang `-fsyntax-only` on changed sources | interp.c fails: unused function `fault_at` |
| `aarch64-unknown-linux-musl-gcc -c src/interp/interp.c` with Makefile `CFLAGS` | **fails**, `-Werror=unused-function` |
| QEMU v7.2 sources (cpu_loop.c, fpu_helper.c, translate.c) | fetched to confirm oracle semantics cited below |

Not run: the cross build of the full binary, the qemu-mipsel suites, and `--difftest`. The commit message carries no evidence that any of these were run either.

### Per-item classification

| Item | Class | Notes |
|---|---|---|
| R7-1 FR=0 pair aliasing | **REGRESSION** | See below. Accessors are correct and tested, but MTHC1/MFHC1 and the DBT were not converted. |
| R7-2 delay-slot syscall | PARTIAL | Ordinary completion now applies the branch, and a handler redirect is preserved. But the frame's saved EPC is still slot+4 because `mips_sc_advance_pc_once` clears `in_delay_slot` before delivery, so a taken branch is lost after `sigreturn`. The review asked to record the post-slot destination before syscall handling. |
| R7-3 double fault on LWL/LWR/SWL/SWR | VERIFIED | `guest_ld8`/`guest_st8` deliver; merge helpers only propagate. |
| R7-4 MADD/MSUB UB | VERIFIED | Unsigned wrap, sign-extended product. |
| R7-5 SYNC ordering | VERIFIED (interp) | `atomic_thread_fence(seq_cst)`. The DBT still emits nothing for SYNC (`emit_int.c:437`), so the ordering bug remains in the production engine. |
| R7-6 alignment vs mapping | PARTIAL | `mips_fault_align` always selects SIGBUS, but routes through `mips_trap` whose `l4a_fault_code` derives `si_code` from `addr & 3`. The exact case the review named, LDC1/SDC1 at 4 mod 8, now reports `BUS_ADRERR` instead of `BUS_ADRALN`. Should call `mips_trap_code(ctx, 10, L4A_BUS_ADRALN, addr)`. |
| R7-7 SC write validation | VERIFIED | Every SC goes through `guest_sc32`, which validates PROT_WRITE before testing the reservation and never touches memory on failure. |
| R7-8 FPE si_code | VERIFIED | Integer overflow is `FPE_INTOVF`; FP cause maps V/Z/O/U/I to 7/3/4/5/6 in the same priority QEMU uses. |
| R7-9 BREAK/TRAP codes | PARTIAL, with new bugs | See below. |
| R7-10 ADD/SUB GRS | VERIFIED | Mantissas widened before alignment. The review's example now rounds to `0x3f800001`. |
| R7-11 directed overflow | VERIFIED | Exponent one below all-ones. |
| R7-12 extreme underflow | VERIFIED | Zero retained mantissa with sticky continues to rounding and still raises U and I. |
| R7-13 zero comparisons | VERIFIED | Explicit either-zero branch before the sign/exponent path. |
| R7-14 invalid unordered | VERIFIED | Condition evaluated independently; FCC written unless the trap fires. |
| R7-15 ROUND-family Inexact | VERIFIED | Suppression removed; matches QEMU softfloat behaviour. |
| R7-16 NaN format conversion | PARTIAL | Infinity can no longer be produced, but legacy sNaN now yields `0x7FF0000000000001` for CVT.D.S of `0x7fc00000`. QEMU legacy mode silences an sNaN to the default NaN (`0x7FF7FFFFFFFFFFFF`), which is also what the project's own `fp_nan2` does for arithmetic. |
| R7-17 NAN2008 int conversion | PARTIAL | NaN now converts to 0 and callers no longer clobber the helper's result. But QEMU's `*_2008_*` helpers keep softfloat's sign-dependent saturation for Inf and overflow (negative gives INT_MIN); this code still returns positive max for `-Inf` and negative overflow in NAN2008 mode. |
| R7-18 MOVF/MOVT/MOVZ/MOVN | VERIFIED | Correct cc/tf decode, GPR condition, FR-aware copy, no FCSR update. |
| R7-19 CFC1/CTC1 | VERIFIED, minor gaps | Aliases 25/26/28 match QEMU exactly. Two deviations: the writable mask is `0xFF81FFFF`, which makes Cause.E (bit 17) read-only, while the 24Kf profile the FIR value `0x00739300` identifies uses `0xFF83FFFF`; and QEMU's pending check ORs `0x20` so Cause.E always traps. The T12 test checks packing arithmetic only, not the CFC1/CTC1 code. |
| R7-20 FP_FMT_W/L | VERIFIED, with a side effect | Constants fixed; the interpreter still uses `0x14/0x15` literals, so the "share definitions" remediation was not done. Correcting the constants makes `fp_from_int_op` in `emit_fp_cvt.c` reachable for the first time (see below). |

### Regressions and new bugs

1. **Build break (blocking).** `src/interp/interp.c:22` defines `fault_at`, which no longer has callers after the alignment refactor. With the Makefile's `-Wall -Werror`, both clang and the cross GCC refuse to compile the file:
   ```
   src/interp/interp.c:22:12: error: 'fault_at' defined but not used [-Werror=unused-function]
   ```
   Delete the function (or route the LH/LW/SH/SW FIXADE-off path back through it).

2. **R7-1 breaks MTHC1/MTHC1 under FR=0, which is the only mode the runtime ever uses.** `fr_mode` is set to 0 in `src/main.c:306` and `src/os/proc.c:413` and never raised. QEMU's FR=0 model (`gen_store_fpr32h`, `gen_load_fpr32h`) aliases MTHC1/MFHC1 `$fN` to the low half of `$f(N|1)`, which is exactly the half the new `mips_fpr_get_d` reads. The commit leaves MTHC1/MFHC1 (`fp.c:879-885`) writing the flat upper half of `fpr[N]`, which the paired accessors ignore. Before the commit, `mtc1 $a0,$f12; mthc1 $a1,$f12; sdc1 $f12,...` produced the right double; after it, the high word is whatever was last in `$f13`. This idiom is what gcc emits for FPXX (Debian/musl mips32r2 default), so it is a user-visible regression, not a corner case.

3. **R7-1 breaks interp/DBT parity under FR=0.** The DBT is untouched and remains flat: `emit_mem.c:551` LDC1 stores both words into `fpr[fs]`, and `fp_ld`/`fp_st` in `emit_fp.c:142-195` read whole 64-bit slots. The interpreter now writes `fpr[fs].lo` and `fpr[fs+1].lo`. Every D-format sequence now diverges between engines in the default mode. The difftest dump (`mips_dump_regs`) does not print FPRs, so the divergence shows up only through MFC1, SDC1, compares, and FCSR, which is why it could survive a shallow run. The Section 2 invariant requires 0 divergences.

4. **R7-9 raw codes used as `si_code`.** `fault_code_at(ctx, pc, 5, code)` stores the BREAK/TRAP code field as `si_code`. Linux and QEMU use `TRAP_BRKPT` (1) for BREAK and `SI_KERNEL` for register TRAP; the plain `break` instruction now reports `si_code 0` (`SI_USER`), which handlers read as "sent by kill". Before the commit it was `SI_KERNEL`.

5. **R7-9 missing the compatibility swap the review required.** gas encodes single-operand `break 7` with the code in bits 25:16, so the raw 20-bit field is `0x1C00`. Linux and QEMU apply `if (code >= 1024) code >>= 10` before the 6/7 test. Without it, the common gcc division-by-zero `break 7` still produces SIGTRAP rather than SIGFPE/`FPE_INTDIV`.

6. **R7-9 immediate traps misuse the immediate as a code.** `exec_regimm_trap` maps `simm == 6/7` to SIGFPE and otherwise stores the immediate as `si_code`. The immediate is the comparison operand, not a code; QEMU's translator passes code 0 for TEQI/TNEI/etc. and Linux's `do_tr` does the same, so `teqi $v0, 7` must stay SIGTRAP.

7. **Newly live DBT code for CVT.S.W/CVT.D.W/CVT.S.L/CVT.D.L looks wrong.** With `FP_FMT_W` corrected, `emit_fp.c:886` now dispatches these to `fp_from_int_op` (`emit_fp_cvt.c:313`). That function reads the source from `d->rt` via `fp_get`, which fetches a guest **GPR**, and its comment says "from W (single GPR)". The architectural source is FPR `fs` (`d->rd`); `ft` is zero in these encodings, so the emitter converts `$zero`. This path was unreachable before the commit; it needs either a fix or a decline (`return -1`) before the DBT is used. A `--difftest` run would catch it.

### Smaller observations

- The file header comments of `interp.c` and `fp.c` were cut to stay under the 900-line limit, removing the documented NaN/ABS semantics and the E03 reference. Consider splitting `fp.c` instead.
- `fp_fmt_sd` repeats the `(f == 0u) ? get_w : get_d` selection on every case; a two-line helper would restore readability.
- `fp_to_int` keeps the dead `no_inexact` parameter.
- R7-2 relies on `sig_depth` changing to detect a redirect; that is sound for `rt_sigprocmask` and `rt_sigreturn`, the only paths that call `mips_sc_advance_pc_once` or deliver pending signals.

### Recommended before marking Section 3 resolved

1. Remove `fault_at` and rebuild with `nix build .#mips32rt`.
2. Convert MTHC1/MFHC1 to the odd-register low half under FR=0, and either make the DBT FR-aware (`fp_ld`, `fp_st`, LDC1/SDC1, MTHC1/MFHC1 in `fp_move_op`) or have the DBT decline D-format ops when `fr_mode == 0`.
3. Fix or decline `fp_from_int_op` in the emitter.
4. Rework R7-9: apply the `>= 1024` swap, use `TRAP_BRKPT`/`SI_KERNEL` as `si_code`, treat immediate traps as code 0.
5. Use `mips_trap_code` with `BUS_ADRALN` in `mips_fault_align`.
6. Run the qemu-mipsel ISA suites and `--difftest` and record the commands and results in the commit or DEFECTS entry.
