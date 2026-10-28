The audit found **interpreter correctness defects, undefined behavior, and test paths that can report success after failure**. Fix those before consolidating helpers: several duplicated implementations already disagree, while others share the same bug.

I reviewed all ten translators and `rt-series`. No files changed. Findings below distinguish source-confirmed defects from cleanup candidates; guest execution and sanitizer validation remain outstanding.

P1 means incorrect execution or unreliable acceptance evidence. P2 covers build reproducibility, harness maintenance, and substantial duplication. P3 covers smaller cleanup and portability debt.

- [ ] **P1 — Repair A32 Thumb ALU interpretation.**  
  [interp_thumb.c:167](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:167) implements several wrong operations: ADC ignores carry, ROR becomes a shift, NEG becomes XOR, CMP multiplies and writes its destination, and MUL adds. Flag preservation is also wrong. The DBT mapping at [interp_t16.c:470](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_t16.c:470) differs. This is reachable through `--interp`. Verify all 16 ALU opcodes against an external oracle, including carry and IT-state cases.

- [ ] **P1 — Fix A32 register-shift boundaries.**  
  [interp_thumb.c:170](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:170) evaluates shifts by 32 or `UINT_MAX` when `b=32`. Masking every count with 31 also loses the architectural zero/32/>32 behavior. Consolidate interpreter shift-with-carry handling around the existing logic at [interp_a32.c:66](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:66); test counts `0,1,31,32,33,255,256`.

- [ ] **P1 — Correct PPC64 reservations and 16-byte LR/SC.**  
  [interp.c:26](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:26) stores reservations globally. [interp.c:537](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:537) implements LR/SC through ordinary reads/writes, bypassing the atomic callback. Additionally, `lqarx/stqcx` pass width 16 into scalar helpers at [interp.h:155](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:155), producing shifts of 64–120 and transferring only one GPR. Use context-owned reservations, atomic validation, and explicit register-pair transfers. Test conflicting stores, interleaved contexts, remapping, faults, and both halves of quadword operations.

- [ ] **P1 — Preserve PPC64 oversized-shift semantics in both engines.**  
  [interp.h:557](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:557) and [emit_int.c:328](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:328) discard the count bit that distinguishes oversized shifts. `SLW` by 32 and `SLD` by 64 consequently act like shifts by zero. The interpreter’s `n < 64` checks after `n = b & 63` are tautologies. Test against QEMU, since interpreter/DBT agreement cannot expose this shared mistake.

- [ ] **P1 — Use unsigned modular accumulation for ARM/MIPS multiply-accumulate.**  
  Signed overflow occurs in A32 SMLAL at [interp_a32.c:216](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:216), MIPS32 MADD/MSUB at [interp.c:294](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:294) and line 316, and MIPS64 at [interp.c:397](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:397) and line 416. MIPS64 also ORs sign-extended `LO` into `HI:LO`, overwriting HI whenever LO’s bit 31 is set. Mask each half, compose in `uint64_t`, and accumulate modulo 2⁶⁴. The MIPS64 DBT already clears LO’s upper half at [emit_alu.c:388](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_alu.c:388).

- [ ] **P1 — Repair x87 rounding carry and signed reconstruction.**  
  [x87_80.c:663](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:663) evaluates `1ULL << 64` at normal 64-bit precision. The preceding significand increment can itself wrap, so adding a shift guard alone is insufficient: rounding needs an explicit carry result. [x87_80.c:2297](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:2297) also shifts signed `n` into its sign bit. Add full-precision rounding-carry and `F2XM1(1)` regressions.

- [ ] **P1 — Remove signed-left-shift UB from branch and dividend construction.**  
  Ordinary backward branches trigger it in A32 [interp_a32.c:320](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:320), SPARC64 [interp.c:94](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:94), and LoongArch [decode.c:385](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/decode.c:385), with repeated instances through line 456. Negative dividend construction has the same defect in SPARC32 [interp.c:275](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:275) and SPARC64 [interp_win.c:525](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:525). Use unsigned composition or representable signed multiplication, then explicit architectural wrapping.

- [ ] **P1 — Replace the duplicated LoongArch si12 sign-extension idiom.**  
  Signed `int32_t << 20` overflows for encoded negative immediates in [fp_vec.c:121](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:121), [fp_shuf.c:116](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_shuf.c:116), [emit_fp_mem.c:120](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:120), and [dbt_mem.c:217](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:217). Introduce one defined immediate-extraction helper and test `-2048,-1,0,2047` through interpretation, emitted memory access, and recovery.

- [ ] **P1 — Range-check rounded FP values before integer casts.**  
  MIPS64 [fp_cvt.c:79](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:79) and LoongArch [fp.c:313](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:313) check the original input, then cast the rounded result. `2147483647.5` can pass the check and round to unrepresentable `2147483648`. LoongArch’s lower-bound literals at [fp.c:290](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:290), 301, and 324 also round to the valid minimum integer, causing that exact minimum to raise invalid. Test values **and exception flags** for every rounding mode.

- [ ] **P1 — Preserve the sign in SPARC64 quad-to-single conversion.**  
  [fp_qconv.c:344](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:344), 348, 379, and 382 place the single-precision sign at bit 32. [fp_qconv.c:792](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:792) truncates it away. Change all four packing paths to bit 31 and cover negative normal, subnormal, underflow, and overflow results.

- [ ] **P1 — Unify A32 interpreter store bookkeeping and reservation ownership.**  
  [interp.c:120](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:120) invalidates reservation epochs, but the duplicate VFP store at [interp_vfp.c:110](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:110) and doubleword stores at [interp_a32.c:556](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:556) bypass it. [interp_a32.c:20](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:20) additionally retains unsynchronized global exclusive state. Route stores through common access helpers and keep reservations in their owning context.

- [ ] **P1 — Make MIPS32 differential mismatches fail.**  
  [run_difftest.sh:59](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:59) uses unified diff but counts `^[<>]`, the ordinary-diff format. Differing traces and registers therefore add zero divergences. Equal failures/timeouts and empty trace extraction can also pass. Make any mismatch fail, distinguish comparison errors, require expected records, and compare stdout. A read-only probe confirmed `diff -u` returned 1 while the current counter returned zero.

- [ ] **P1 — Enforce exit status and coverage in shared acceptance harnesses.**  
  [bench_harness.sh:320](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:320) discards command status before searching for `ALL_PASS`; [line 398](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:398) converts QEMU failure into successful SKIP. LoongArch [parity_suite.sh:83](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:83) compares output without checking either process status. Injected probes confirmed timeout-after-`ALL_PASS` → PASS and QEMU failure → SKIP/exit 0. Invalid architecture filters also succeed with zero tests in both shared runners. Validate filters, count executed cases, and require expected exit status plus complete output.

The next batch should make builds and measurements trustworthy.

- [ ] **P2 — Select benchmark engines explicitly.**  
  [bench_harness.sh:319](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:319) ignores the requested engine for A32/i686/RVRT; [line 345](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:345) ignores it for every `hl` run. i686 [run-coremark.sh:392](/Users/angerman/Projects/zw3rk/i686rt/tools/run-coremark.sh:392) labels the default engine “interp,” although [main.c:317](/Users/angerman/Projects/zw3rk/i686rt/src/main.c:317) defaults to DBT. Its report also hardcodes a performance conclusion at [run-coremark.sh:179](/Users/angerman/Projects/zw3rk/i686rt/tools/run-coremark.sh:179). Use explicit engine arguments and derive conclusions from validated results.

- [ ] **P2 — Add reliable header dependencies.**  
  Missing dependencies affect MIPS32 [Makefile:37](/Users/angerman/Projects/zw3rk/mips32rt/Makefile:37), i686’s x86_64 objects [Makefile:74](/Users/angerman/Projects/zw3rk/i686rt/Makefile:74), PPC64 binaries [Makefile:39](/Users/angerman/Projects/zw3rk/ppc64rt/Makefile:39), LoongArch [Makefile:98](/Users/angerman/Projects/zw3rk/loongarch64rt/Makefile:98), and MIPS64 [Makefile:110](/Users/angerman/Projects/zw3rk/mips64rt/Makefile:110). Use compiler dependency files and verify that changing an interpreter/decoder header rebuilds the affected artifact.

- [ ] **P2 — Remove duplicate recipes and implicit directory ordering.**  
  MIPS32 [Makefile:80](/Users/angerman/Projects/zw3rk/mips32rt/Makefile:80) and [line 98](/Users/angerman/Projects/zw3rk/mips32rt/Makefile:98) compile the same ABI-test output through separate prerequisites, racing under `make -j check`. Standalone checks lack build-directory prerequisites in PPC64 [Makefile:62](/Users/angerman/Projects/zw3rk/ppc64rt/Makefile:62), SPARC32 [Makefile:108](/Users/angerman/Projects/zw3rk/sparc32rt/Makefile:108), and SPARC64 [Makefile:74](/Users/angerman/Projects/zw3rk/sparc64rt/Makefile:74). Define test binaries once as file targets with order-only directory prerequisites.

- [ ] **P2 — Replace successful placeholder test targets.**  
  i686 [Makefile:91](/Users/angerman/Projects/zw3rk/i686rt/Makefile:91) and PPC32 [Makefile:92](/Users/angerman/Projects/zw3rk/ppc32rt/Makefile:92) still print “phase 0: no tests yet.” MIPS32 [run_p1_isa.sh:35](/Users/angerman/Projects/zw3rk/mips32rt/tests/run_p1_isa.sh:35) absorbs required test failures, while [run_p3_fpu.sh:38](/Users/angerman/Projects/zw3rk/mips32rt/tests/run_p3_fpu.sh:38) records failures without propagating failure status. Wire meaningful interpreter/decoder checks and make required missing tests fail.

- [ ] **P2 — Repair PPC64 harnesses referencing deleted layouts.**  
  [dbt_run.sh:349](/Users/angerman/Projects/zw3rk/ppc64rt/tests/dbt_run.sh:349), [p3_run.sh:131](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p3_run.sh:131), [p4_run.sh:148](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p4_run.sh:148), and [p5_run.sh:212](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p5_run.sh:212) generate includes of deleted `rt64/memory/space.h`. [p6_run.sh:182](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_run.sh:182) also compiles deleted implementation paths. Extract one maintained runner using current interfaces; retain separate guest fixtures and oracle assertions.

- [ ] **P2 — Select MIPS64’s backend from each artifact’s actual compiler.**  
  [Makefile:39](/Users/angerman/Projects/zw3rk/mips64rt/Makefile:39) chooses the backend using `CC`, while [build-cross:114](/Users/angerman/Projects/zw3rk/mips64rt/Makefile:114) compiles that source list with `CROSS_CC`. A Darwin `CC` and Linux cross-compiler select incompatible sources. Define explicit Linux/Darwin source groups.

- [ ] **P2 — Standardize bounded execution and exact cleanup ownership.**  
  LoongArch [parity_suite.sh:90](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:90) creates names ending `---interp`/`---dbt`, but [line 116](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:116) cleans `-interp`/`-dbt`. i686 [difftest.sh:78](/Users/angerman/Projects/zw3rk/i686rt/tools/difftest.sh:78) and shared [remote_bench.sh:110](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench.sh:110) have unbounded execution paths. RVRT [parity_suite.sh:24](/Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh:24) retries arbitrary failures while overwriting first-attempt evidence. Store exact resource names, preserve attempt logs, bound commands, and trap owned-resource cleanup.

- [ ] **P2 — Make benchmark builds sensitive to their inputs.**  
  [bench_harness.sh:143](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:143) hardcodes Nix store paths; [line 147](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:147) rebuilds only when an executable is absent. Source or flag changes can silently reuse old binaries. Build paths also vary between freestanding/hosted and `-O1`/`-O2`. Track source, flags, compiler, and artifact identity; record the chosen variant with results.

- [ ] **P2 — Reject timing failures instead of manufacturing measurements.**  
  [bench_suite.c:35](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:35) and [line 297](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:297) ignore clock errors. [line 400](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:400) turns a zero interval into one microsecond. A broken clock can therefore accompany `ALL_PASS` and implausible throughput. Track timing validity separately from workload correctness.

- [ ] **P2 — Test production ABI/capability policy rather than copied declarations.**  
  The umbrella [check_abi_invariants.c:140](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:140) asserts a locally reproduced MIPS context, so changes to the real context cannot fail it. PPC64’s production-unused [core/profile.h:36](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/profile.h:36) retains RISC-V extension scaffolding and returns FULL capabilities, while [run/load.c:496](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:496) emits PHASE2 capabilities. Assert actual runtime types and loader outputs against independent expected constants.

For DRY work, share mechanical representation and validation within each repository. Preserve independently implemented execution semantics and external oracles; the standalone-repository constraint rules out a new shared runtime library.

| Priority | Duplication and exact references | Refactoring boundary |
|---|---|---|
| P2 | MIPS32 [decode.c:77](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/decode.c:77), [interp.h:63](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.h:63), [emit_int.c:541](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:541) | One branch descriptor: condition, link, likely, delay slot. Existing tables disagree; [decode.h:95](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/decode.h:95) also swaps BC1FL/BC1T constants. |
| P2 | MIPS64 [interp.h:149](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.h:149), [emit_int.c:155](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:155), [decode.c:219](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.c:219) | Consolidate branch metadata while retaining distinct integer/FP dispatch and emitter-support predicates. |
| P2 | LoongArch [fp_vec.c:115](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:115), [emit_fp_mem.c:144](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:144), [dbt_mem.c:156](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:156) | Decode FP-memory width, direction, operands, and addressing form once. The repeated sign-extension bug demonstrates the maintenance cost. |
| P2 | SPARC64 [decode.c:528](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:528) versus [interp.c:68](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:68) | Resolve two decoded structures/classifiers. Runtime DBT and difftest currently consume different decoder paths. |
| P3 | PPC32 [interp.h:73](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:73) / [emit_int.h:342](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_int.h:342); PPC64 [interp.h:81](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:81) / [emit_int.c:351](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:351) | Share pure rotate-mask construction, with exhaustive mask tests. |
| P3 | i686 [h_muldiv.c:50](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_muldiv.c:50), [h_shift.c:133](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_shift.c:133), [emit_alu.c:415](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:415) | Put descriptor-to-width/mask metadata in the existing decoder interface. |
| P3 | RVRT [rv32_expand.c:9](/Users/angerman/Projects/zw3rk/rvrt/src/core/rv32_expand.c:9) versus [compressed_expand.c:11](/Users/angerman/Projects/zw3rk/rvrt/src/core/compressed_expand.c:11) | Share pure encoders and compressed-immediate unpackers; retain separate RV32C/RV64C opcode admission tables. |

The remaining CLEAN/YAGNI and style work is narrower:

- [ ] **Remove obsolete production scaffolding after reconnecting its consumers.** MIPS32’s weak failing `guest_ld32` stub remains at [decode.c:38](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/decode.c:38), despite the real implementation at [os/mem.c:589](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:589). Move link stubs into tests. MIPS64 classifiers beginning at [decode.c:170](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.c:170) have tests but no production callers while engines duplicate their logic. Wire them into the descriptor or remove the unused API.

- [ ] **Remove confirmed unused includes and investigate unreachable decode code.** A32 [interp_thumb.c:11](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:11) includes unused `<string.h>` and `<sys/mman.h>`. Its [line 591](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:591) tests a bit already forced clear by the enclosing mask at line 581. Repair the T32 branch decoding before deleting that unreachable arm. No wholly orphaned interpreter/core header was established; PPC64 `profile.h` is specifically **production-unused**, not unreferenced.

- [ ] **Replace textual `.c` splitting with meaningful module boundaries.** LoongArch [interp.c:42](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:42) includes five implementation files, composing roughly 3,967 lines before helper headers. A32 [decode_a32.c:9](/Users/angerman/Projects/zw3rk/a32rt/src/decode_a32.c:9) and [decode_t32.c:9](/Users/angerman/Projects/zw3rk/a32rt/src/decode_t32.c:9) include DBT lowering fragments stored under `src/interp/`. Correct their placement/names and expose small private interfaces.

- [ ] **Close explicit Curated-C11 deviations.** SPARC64 [fp_sd.c:347](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:347) uses `__uint128_t`; warning-clean Clang compilation does not make that portable C11. Replace it with bounded word-pair arithmetic or explicitly revise the portability requirement. Banned setup-time `strcpy` calls remain in i686 [test_l2a.c:306](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l2a.c:306) and [test_l2h.c:172](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l2h.c:172). Distinguish these from fixtures intentionally testing guest libc string functions.

- [ ] **Complete `.PHONY` declarations.** Missing action targets occur at A32 [Makefile:521](/Users/angerman/Projects/zw3rk/a32rt/Makefile:521), 523, 542, 565; i686 [Makefile:71](/Users/angerman/Projects/zw3rk/i686rt/Makefile:71); PPC64 [Makefile:62](/Users/angerman/Projects/zw3rk/ppc64rt/Makefile:62); and RVRT [Makefile:7414](/Users/angerman/Projects/zw3rk/rvrt/Makefile:7414), 7416. Same-named files can suppress those recipes.

The tracked-file inventory found **27 files above 1,000 logical lines** in the requested surfaces and compared DBT code. Split by responsibility, rather than moving arbitrary chunks into included files.

| Repository | Files and logical line counts |
|---|---|
| a32rt | [tests/test_m1_isa_fs.c](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m1_isa_fs.c:1) 3,702; [test_m3_threads_signals.c](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m3_threads_signals.c:1) 3,182; [test_m4_vfp_neon.c](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m4_vfp_neon.c:1) 3,233; [test_m5_ltp_gdb.c](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m5_ltp_gdb.c:1) 2,587 |
| i686rt | [src/interp/h_sse.c](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:1) 2,156; [h_x87.c](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87.c:1) 2,276; [x87_80.c](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:1) 2,971; [src/dbt/emit_sse.c](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:1) 1,977 |
| i686rt tests/tools | [tests/probe_strfuncs.c](/Users/angerman/Projects/zw3rk/i686rt/tests/probe_strfuncs.c:1) 1,473; [test_p1_isa.c](/Users/angerman/Projects/zw3rk/i686rt/tests/test_p1_isa.c:1) 1,039; [unit/test_l1d.c](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l1d.c:1) 1,271; [test_l1e.c](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l1e.c:1) 1,083; [test_l5d.c](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l5d.c:1) 1,301; [tools/gen_insn_tab.py](/Users/angerman/Projects/zw3rk/i686rt/tools/gen_insn_tab.py:1) 1,039 |
| mips32rt | [tests/test_p3_fpu.c](/Users/angerman/Projects/zw3rk/mips32rt/tests/test_p3_fpu.c:1) 1,145 |
| rvrt | [Makefile](/Users/angerman/Projects/zw3rk/rvrt/Makefile:1) 8,677; [test/rv32_linux_nix.py](/Users/angerman/Projects/zw3rk/rvrt/test/rv32_linux_nix.py:1) 1,661; [test_linux_file.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_linux_file.c:1) 1,426; [r6_inherited_children.c](/Users/angerman/Projects/zw3rk/rvrt/test/r6_inherited_children.c:1) 1,304; [test_family_file_attributed.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_family_file_attributed.c:1) 1,293; [r5_exec.c](/Users/angerman/Projects/zw3rk/rvrt/test/r5_exec.c:1) 1,212; [test_linux_file_workers.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_linux_file_workers.c:1) 1,133; [test_file_caps.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_file_caps.c:1) 1,022 |
| ppc64rt | [tests/p5_run.sh](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p5_run.sh:1) 2,100; [p4_run.sh](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p4_run.sh:1) 1,602; [dbt_run.sh](/Users/angerman/Projects/zw3rk/ppc64rt/tests/dbt_run.sh:1) 1,413; [p3_run.sh](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p3_run.sh:1) 1,093 |

No additional files exceeded that threshold in the inventoried PPC32, SPARC32, LoongArch64, MIPS64, SPARC64, or `rt-series` surfaces. The PPC64 `dbt_run.sh` logical count includes its final unterminated line.

Validation completed:

- Native syntax-only checks passed without diagnostics for the inspected interpreter/decoder/core translation units across all ten translators, using `-std=c11 -Werror=vla -pedantic -Wall -Wextra`, repository include paths, and an explicit macOS SDK.
- The exact umbrella check below passed:
  ```sh
  timeout --kill-after=30s 30s \
    /Library/Developer/CommandLineTools/usr/bin/clang \
    -std=c11 -Wall -Wextra -Werror=vla -pedantic \
    -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -Iinclude -fsyntax-only \
    include/a32host.h tests/check_abi_invariants.c tests/bench_suite.c
  ```
- `/Library/Developer/CommandLineTools/usr/bin/make check-docs` passed: 34 required files verified. Shell syntax checks and tracked-file/reference scans completed.
- Injected harness probes confirmed the false-green outcomes described above.

The filesystem was read-only, so no full builds, UBSan executables, QEMU matrices, or benchmarks ran. The arithmetic findings are established from operand types and reachable values; their repair should be verified with focused boundary tests and an independent oracle.