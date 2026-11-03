Review complete. Here is the report.

# Static review of fa31adf (M64-R7-1..18)

Scope: diff-only reading of the commit against the Round-7 defect report and DEFECTS.md Section 9. Nothing was built or run. Guest ELF headers under `tests/guests` were inspected with `od` only.

## Classification

| Item | Verdict | Note |
|---|---|---|
| R7-1 R6 admission | VERIFIED | Rejects arch 0x9/0xA. Also rejects pre-R2 arch levels, see new issue 3. |
| R7-2 LL/SC alias ABA | PARTIAL | Backing-identity check added, but the new map scans ignore the map's pid. |
| R7-3 BC1 slot redirect | VERIFIED | `fp_branch` keeps a redirected pc, mirrors `exec_branch`. |
| R7-4 double fault delivery | VERIFIED | `load_bytes`/`store_bytes` no longer re-raise. Callers propagate without re-raising. |
| R7-5 FCC1-7 branches | VERIFIED | `is_bc` accepts any rt, likely from `rt & 2`, constants fixed. Nit, see 5. |
| R7-6 NAN2008 | PARTIAL | Scalar, CVT, COP1X honor the mode. PS lanes still return the legacy default NaN. |
| R7-7 aliased sNaN | VERIFIED | Sources snapshotted in S/D arith and COP1X. PS reads both lanes before writeback. CVT checks before store. |
| R7-8 MADD rounding | PARTIAL | Product-then-sum in guest RM is implemented. NMSUB rounds in the wrong direction under RP/RM, and the DBT still emits fused FMA, see 1 and 6. |
| R7-9 JR/JALR alignment | VERIFIED | Link and slot commit first, fault at the target with pc = target. |
| R7-10 BREAK codes | VERIFIED | hi field preferred, 6/7 map to SIGFPE with INTOVF/INTDIV. Only SPECIAL reaches the BREAK path. |
| R7-11 LL/SC SIGBUS | VERIFIED | All four alignment checks use `mips_bus_fault`. |
| R7-12 Cause replaced per op | VERIFIED | `fp_begin_op` clears bits 17:12. Minor side effect, see 4. |
| R7-13 trapped op keeps Flags | VERIFIED | Flags accumulate in a thread-local and commit only on untrapped completion. |
| R7-14 DIV infinities | VERIFIED | inf/0 is exact signed inf, zero/inf quotients bypass the residual in both S and D. |
| R7-15 FS flush | PARTIAL | Result flushing is wired through all rounding helpers. Exception accounting and input handling deviate from R2 text, see below. |
| R7-16 PS cancellation | VERIFIED | Per-lane -0 under RM=3 for ADD.PS/SUB.PS. |
| R7-17 FCCR/FEXR/FENR | VERIFIED | Bit packing and masks are correct for all three. Write-trigger check applies. |
| R7-18 MOVF/MOVT/MOVZ/MOVN.fmt | VERIFIED | Predicate and lane copy correct. PS variants remain unimplemented, outside the finding. |

Notes on the PARTIAL items:

- **R7-2.** `mips_vm_file_backing_seq` and `mips_vm_file_bump_llsc` in `src/vm/vm_file_sync.c:185` and `:244` walk every inode map without filtering `m->pid == getpid()`. Every other VA-keyed scan in that file filters by pid. In a forked family, a child whose VA range coincides with a sibling's shared mapping of a different file can bind its reservation to the wrong inode, which misses the ABA this fix targets. The generation lives in the `MAP_SHARED` table so cross-process bumps are visible, but `llsc_seq++` is guarded only by the per-process `vm_inode_mu`, so it is a data race. A lost increment still moves the value away from the LL snapshot, so this is benign in practice but should be an atomic add.
- **R7-6.** `src/interp/fp_ps.c:119`, `:126`, `:135`, `:143` still return `FP_DEFNAN_S`. Under NAN2008 that bit pattern is a signaling NaN.
- **R7-8.** NMSUB is computed as round(fr − p) in `src/interp/fp_ps.c` for both S and D. The R2 definition is −round(p − fr). Those differ under RP and RM when the sum is inexact. MADD, MSUB and NMADD follow the spec.
- **R7-15.** The implementation flushes tiny results to signed zero in every rounding mode, reports I only, and never flushes subnormal inputs. My reading of the R2 FCSR text is that flushed results also signal U, that RP/RM flush to MinNorm for the matching sign, and that subnormal operands are flushed too. I could not open the referenced PDF here, so treat this as a spec check to do before closing the item. The new test in `tests/test_r7_fp.c:327` encodes the no-U expectation, so it would need to change with the code.

## New issues and regressions

1. **Dual-engine parity break for COP1X.** `src/dbt/emit_fp.c:674` lowers MADD/MSUB/NMADD/NMSUB to native fused FMADD and its comment says this matches the interpreter's `fmaf`/`fma`. The interpreter now rounds the product first. For any inexact product the two engines produce different `fpr` values, and the difftest hash in `src/os/mem.c:430` covers `fpr`. The RN fast path has no guard for this case, so `--difftest` will report divergences. Either the DBT must decline COP1X words or emit a two-step sequence.
2. **R7-2 pid filter omission** as described above.
3. **Admission now rejects valid pre-R2 binaries.** `classify` in `src/loader.c:332` admits only arch 0x0, 0x7 and 0x8. MIPS II through MIPS64r1 encodings are strict subsets of R2, so images built with `-march=mips64`, `mips3` and so on are now refused with ENOEXEC, including their PT_INTERP loader at `src/loader.c:832`. All prebuilt guests under `tests/guests` carry arch 0x8, so the existing gates are unaffected. The new `isa_rev` field is written and never read.
4. **DMFC1/DMTC1 clear FCSR Cause.** `fp_cop1` in `src/interp/fp.c:784` calls `fp_begin_op` before dispatching rs 0x01/0x05. Transfer instructions should not touch Cause. MFC1/MTC1/CFC1/CTC1 are unaffected because `fpmove_cop1` handles them first.
5. **Shared BC constants still reversed.** `MIPS64_BC_FL`/`MIPS64_BC_T` in `src/interp/decode.h:213` keep the old order while the COP1 constants were swapped. They are only used for COP0 branches, which are unreachable in user mode, but the "share the BC numbering" comment is now false and `is_bc_likely` for COP0 is wrong.
6. **NMSUB directed rounding** as described under R7-8.

Minor observations that are not regressions: misaligned jump targets still deliver SIGSEGV where Linux delivers SIGBUS, which predates this commit. BREAK words with both code fields nonzero differ from Linux's swap rule only in that corner. `interp.c` and `unaligned.c` are at 898 lines, two below the limit.

Not verified here: that the `make test` link sets in the Makefile resolve, and that the two new test programs pass. DEFECTS.md Section 9 still shows 0/18 resolved.
