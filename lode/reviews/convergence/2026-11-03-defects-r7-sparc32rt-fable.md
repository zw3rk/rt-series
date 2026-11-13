# Static review of `a872464` (Round-7 remediation, S32-R7-1..23)

Scope: static read of the commit diff plus the post-commit sources it touches, cross-checked against the Round-7 report and `DEFECTS.md` Section 5 (which is a verbatim copy of the report). No builds, guest binaries, or test suites were run. Line numbers refer to the post-commit tree.

## Summary

| Verdict | Count | Items |
|---|---:|---|
| VERIFIED | 15 | R7-2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 17, 18, 20, 21, 22 |
| PARTIAL | 7 | R7-1, 6, 7, 8, 9, 16, 19 |
| REGRESSION | 1 | R7-23 |

The single hard regression is high severity: the new FPop1/FPop2 group check places FSMULD in the wrong group, so every real `fsmuld` now decodes as illegal in both engines. The PARTIAL items split into one incomplete fix (R7-1) and six where the interpreter is correct but the DBT, which is the default engine per `src/main.c:318`, keeps the old behavior, so the dual-engine parity invariant from the project rules is broken.

## Per-item classification

| Item | Verdict | Evidence |
|---|---|---|
| R7-1 SAVE/RESTORE loses `%o` | **PARTIAL** | A per-window `%o` image was added, and RESTORE records it, but SAVE reloads `%o` only when the target slot is valid (`src/interp/interp_win.c:174`). RESTORE clears the popped slot's valid bit, so in the report's own sequence (SAVE, set `%o0=0x22`, RESTORE, SAVE) the second SAVE still skips the reload and `%o0` stays `0x11`. The reload fires only on the eviction path. DBT parity holds because its fast path also requires an invalid target, so both engines are consistently wrong on the reported case. |
| R7-2 `%i6` edit forces fill | VERIFIED | The `interp_winsp[tgt] != post_sp` test is gone. Fill now depends only on `interp_win_valid[tgt]`. The DBT fast path still branches to the slow path on an sp mismatch, which lands in the same helper, so the outcome matches. |
| R7-3 delay-slot CTI re-executes itself | VERIFIED | `interp_cti` now sets `pc = npc`, `npc = npc + 4` before fetching the delay slot (`src/interp/interp.c:710`), so the inner transfer fetches its own successor. Residual: the inner CTI's delay slot is `npc + 4`, not the outer target that V8 Table 5-12 specifies for DCTI couples. That is a pre-existing deviation, now deterministic rather than divergent. |
| R7-4 delay-slot fault PC | VERIFIED (interp) | Every class now reports `pc = delay`, `npc = selected successor` on fetch or execute failure. See new regression N-2 for the DBT. |
| R7-5 Ticc in delay slot | VERIFIED | Shared `interp_trap_insn` (`src/interp/interp.c:190`) is reachable from `interp_single`. A delay-slot `ta 0x10` returns false, the CTI records `pc = delay`, `npc = target`, and the syscall owner's advance lands on the target. `tn` is a no-op and `ta 3` flushes without advancing. |
| R7-6 DIV saturation | **PARTIAL** | Interpreter is correct for all four forms including `INT64_MIN / -1` saturating positive with V set. The DBT runtime helper in `src/dbt/emit_priv.h:180-245` still truncates and still returns `0x80000000` with N set for that case. |
| R7-7 MULSCC | **PARTIAL** | Interpreter now shifts with `N xor V`, selects the addend by `Y[0]`, and derives ICC from the real add. `src/dbt/emit_priv.h:281` keeps the old algorithm. |
| R7-8 MULcc V | **PARTIAL** | Interpreter clears V and C. `src/dbt/emit_priv.h:155-178` still sets V on signed overflow. |
| R7-9 TADDccTV/TSUBccTV | **PARTIAL** | Interpreter computes the trap predicate before any ICC or rd commit. `src/dbt/emit_priv.h:259-280` still commits ICC first. |
| R7-10 CASA `i` bit | VERIFIED | Decoder accepts `i == 0` with ASI in bits 12:5 and rejects `i == 1`. Decoder is shared by both engines. The only fixture using the old `0xD5E22149` word (`tests/test_p1_isa.c:223`) compares the encoding and never executes it. Covered by the new host test. |
| R7-11 STBAR encoding | VERIFIED | RDASR with `rs1 == 15`, `rd == 0` decodes STBAR before generic dispatch; the invented op3 `0x2c` constant is removed and no stale references remain. |
| R7-12 fetch outside VM gate | VERIFIED | Fetch now holds `sparc32_vm_access_enter` across the `interp_range_ok` check and the 4-byte copy, and `interp_range_ok` consults the shared page table when present. The gate is reader-reentrant and the DBT translator already holds the writer lock, so no deadlock. |
| R7-13 doubleword all-or-nothing | VERIFIED | LDD, STD, LDDF, STDF go through one gated 8-byte `interp_mem_rd` or `interp_mem_wr` after the 8-alignment test. The alternate-space forms share the same case. |
| R7-14 JMPL misalignment class | VERIFIED (interp) | The fault leaves `pc` at the JMPL; the classifier decodes it and uses width 4 (`src/interp/interp_signal.c:785`). See N-2. |
| R7-15 traps to guest signals | VERIFIED | Both run loops map EXIT_TRAP and EXIT_UNDEF through `sparc32_trap_signo` into the synchronous delivery path. `si_addr` comes from `exit_dest`, and the SIGFPE and SIGILL `si_code` tables match Linux. See N-4 for a namespace collision. |
| R7-16 FSR.TEM | **PARTIAL** | Interpreter: `fp_raise` traps when `cexc & TEM` is nonzero, sets FTT = 1 without accrual, and `fp_take_trap` suppresses the destination or FCC write. The DBT's native FP emitters never consult TEM, so under the default engine the defect persists. See N-5 for an accrual residual. |
| R7-17 FDTOS odd rd | VERIFIED | `fpu_double_dest` now lists `0x0C8` as FiTOd; executor table already agreed. Covered by the host test. |
| R7-18 LDFSR mask, FTT lifecycle | VERIFIED | Writable mask `0xCFC00FFF` keeps RD, TEM, NS, fcc, aexc, cexc and preserves ver, FTT, QNE. Applied in both the interpreter and `src/dbt/emit_fpmem.c`. Every FPop helper clears FTT with cexc on entry. |
| R7-19 quiet compare NVA | **PARTIAL** | Interpreter raises nothing for a quiet unordered compare. The DBT still ORs the unordered flag into aexc bit 9 (`src/dbt/emit_fp.c:343-365`), so FSR diverges between engines. |
| R7-20 FSMULD zero times inf | VERIFIED | Explicit check raises NV and writes the canonical NaN. The exact double product path cannot raise otherwise. |
| R7-21 FDTOI range | VERIFIED | Early guards moved to the int64 bounds; representability is decided after rounding, so `-2147483648.5` yields INT32_MIN with NX. No UB in the int64 casts. |
| R7-22 directed FDTOS overflow | VERIFIED | After `nextafterf` in the RP and RM paths, a non-finite result raises OF and NX. |
| R7-23 FPop1/FPop2 validation | **REGRESSION** | See N-1. |

## New bugs and regressions

- **N-1, HIGH, both engines: FSMULD now decodes illegal.** V8 lists FsMULd (opf `0x069`) under FPop1, op3 `0x34`. The new `fpop_valid` table puts it under FPop2 only (`src/interp/decode.c:67`, `decode.c:105`), and the executor check in `src/interp/fp.c:89-104` rejects it under FPop1. The repo already documents the correct encoding at `tests/test_p3_fp_simd.c:45` and executes `fsmuld %f1, %f2, %f30` at line 179, so that guest test will now die with SIGILL. GCC emits `fsmuld` for V8 targets. The DBT dispatches FSMULD under FPop1 (`src/dbt/emit_fp.c:684`) but never sees it because the shared decoder marks the word ILLEGAL. Fix: move `0x069` to the FPop1 list in both tables and add a host-test case.

- **N-2, HIGH, DBT engine: delay-slot faults are now misclassified.** `sparc32_classify_fault` was rewritten to assume the fault PC is the delay instruction. The DBT still records the CTI address for CALL, Bicc, and FBfcc delay faults (`src/dbt/emit_cti.c:85`, `:160`, `:250`, `:306`). Under the default engine, a delay-slot `ldd` at a 4-aligned, 8-misaligned address now gets SIGSEGV instead of SIGBUS, and an unmapped byte access at an odd address gets SIGBUS instead of SIGSEGV. The signal frame also still carries `pc = branch`, so R7-4 remains live under the DBT.

- **N-3, HIGH, parity: integer arithmetic diverges between engines.** The DBT's `sparc32_rt_muldiv` helper (`src/dbt/emit_priv.h:150-300`) was not updated for R7-6, 7, 8, 9. A `--difftest` run over MULSCC, UDIV, SDIV, UDIVcc, SDIVcc, UMULcc, SMULcc, TADDccTV, or TSUBccTV corner cases will report register and ICC divergences, violating the zero-divergence invariant.

- **N-4, MEDIUM: Ticc software trap numbers collide with trap-type constants.** `interp_trap_taken` stores the raw software trap number in `exit_arg`, while `sparc32_trap_signo` and the SIGFPE code table compare `exit_arg` against `0x01`, `0x07`, and `0x2A` (`src/interp/interp.c:55-58`, `src/interp/interp_signal.c:802`). So `ta 1` delivers SIGFPE with FPE_INTOVF, `ta 7` delivers SIGFPE with an FSR-derived code, and `ta 0x2a` delivers SIGFPE with FPE_INTDIV. Linux delivers SIGTRAP for `ta 1` and SIGILL for the others. Before the commit these were fatal stops, so this is a new wrong-signal path for guests with handlers installed.

- **N-5, LOW: FP trap accrual and cexc on multi-raise paths.** Helpers that raise in two calls accrue the first exception before the second call traps, and the trap path overwrites cexc. Example: `fp_to_f32` raises NX at `src/interp/fp_arith.c:326`, then OF plus NX at line 345 traps, leaving NX in aexc. The tiny path raises NX then UF, leaving cexc as UF only. V8 §4.4 keeps aexc unchanged and cexc complete on a trap.

- **N-6, LOW: new host test is not wired into `make check`.** `tests/test_r7_decode.c` carries its build line only in a comment. Its link stubs match the symbols `decode.c` now pulls in, and `sparc32_guest_ptr` is a static inline, so the documented command should link.

Checks that passed: all touched files stay under 900 lines (largest is `fp_arith.c` at 896), no assembly or JIT emitter changes touch `x18`, no W^X changes, and no stale references to the removed STBAR op3 constant.
