The audit found correctness defects that should be fixed before structural cleanup: out-of-bounds writes, unsafe code reclamation, stale translations, incorrect instruction encodings, and broken register preservation.

This was read-only. All ten worktrees remained clean. Findings below distinguish active defects from unused or test-only code. Proposed runtime regressions were **not executed**.

P1 means memory safety, wrong guest execution, or an active architectural invariant violation. P2 covers failure handling, bounded-resource problems, and validation defects. P3 covers maintainability.

The audited snapshots and size results were:

| Repository | HEAD | Largest directly scoped file |
|---|---|---|
| a32rt | `d81bebb` | `core_emit_mem.c`: 772 lines |
| i686rt | `76bed20` | **`emit_sse.c`: 1,977 lines** |
| mips32rt | `9379b3d` | `dbt.c`: 837 |
| ppc32rt | `04d50ce` | `emit_fp.c`: 899 |
| sparc32rt | `e74075e` | `emit_int.c`: 868 |
| rvrt | `726e3d5` | `darwin_dbt.c`: 837 |
| loongarch64rt | `ac4f0a9` | `a64_emit.c`: 882 |
| ppc64rt | `eef6dc0` | `dbt.c`: 888 |
| mips64rt | `99e1e8c` | `dbt.c`: 880 |
| sparc64rt | `e6e5c84` | `emit_int.c`: 895 |

The two directly scoped files exceeding 1,000 lines are [i686rt/emit_sse.c:1](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:1), **1,977**, and [i686rt/rt32_a64_emit.c:1](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_a64_emit.c:1), **1,235**. Its [line-limit target:251](/Users/angerman/Projects/zw3rk/i686rt/Makefile:251) checks a restricted file list that misses both.

Also flag [rvrt/runtime_main.c:3349](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:3349): **8,201 lines**, containing DBT/VM cache ownership and invalidation. This is a transitive integration monolith rather than a standalone emitter.

Fix the following before refactoring interfaces:

1. **P1 — MIPS64 delay-slot decoding overruns a stack array.**  
   [dbt.c:420](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:420) allocates 64 decoded instructions. A branch in the final slot increments `n` to 64, then [dbt.c:465](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:465) decodes its delay slot into `insns[64]`. Reserve room for the branch and delay slot before admitting either. Validate with 63 ordinary instructions followed by a branch and delay slot under ASan.

2. **P1 — Several emitters bypass their own overflow protection when patching branches.**  
   Appending saturates the cursor at capacity, but later fixups directly index the recorded cursor. An overflowed placeholder can therefore become `words[cap]`.

   | Repository | Unguarded access |
   |---|---|
   | a32rt | [core_emit_mem.c:709](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:709), additional fixups at 738–744 |
   | i686rt | [emit_alu_ext2.c:381](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu_ext2.c:381), unguarded read before choosing the patcher |
   | ppc32rt | [ppc32_a64_emit2.c:388](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:388) |
   | sparc32rt | [a64_emit_fp.c:442](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/a64_emit_fp.c:442) |
   | ppc64rt | [emit_core.h:126](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:126), also 158 |
   | rvrt | [dbt_emit_fp.c:120](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:120), also 139–140 and 607–609 |

   Introduce one checked reserve/patch API **inside each repo**, with an invalid-position sentinel and consistent failure propagation. Sweep capacities from zero through the complete sequence length using canaries/ASan. These boundary defects are source-confirmed; normal-workload reachability was not dynamically established.

3. **P1 — Shared code reclamation is unsafe across guest threads.**

   | Repository | Evidence and consequence |
   |---|---|
   | a32rt | [vm_jit_mem.c:328](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_jit_mem.c:328) changes the whole cache RW and rewinds allocation without waiting for peers. [dbt_jit_run.c:347](/Users/angerman/Projects/zw3rk/a32rt/src/dbt/dbt_jit_run.c:347) executes outside the JIT lock. Epoch invalidation does not stop already executing code. |
   | i686rt | [engine.c:502](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:502) clears only the caller’s IBTC before immediately unmapping shared code. The global graveyard is drained at one thread’s local dispatch boundary. Peers retain pointers and may still execute them. |
   | ppc32rt | [cache.c:383](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:383) frees shared blocks without execution quiescence; [cache.c:173](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:173) clears only the supplied context’s hints. |
   | ppc64rt | [dbt.c:857](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:857) clears the caller’s thread-local IBTC but resets shared storage. Peers noticing the mutation [clear only their TLB:441](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/core.c:441). |

   Establish consistent cache ownership, synchronized publication, and retirement after every relevant worker reaches a safe point. Validate with concurrent execution plus deliberate collisions, exhaustion, and SMC retirement. A mutex around allocation alone is insufficient.

4. **P1 — PPC32 RAS entries can retain freed pointers even with one thread.**  
   [emit_ras_push_inline:222](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:222) writes `ras[top].entry` without its key. [sever_ctx_range:188](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:188) invalidates by that key. After collision eviction, [RAS pop:360](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:360) dereferences the stale pointer. Use one explicit RAS representation and sever references before freeing. Test eviction of a saved return target.

5. **P1 — i686 Linux code remains RWX.**  
   [engine.c:512](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:512) allocates `PROT_READ | PROT_WRITE | PROT_EXEC`, with no subsequent RX transition. The existing [backend allocation/sealing API:176](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_linux.c:176) already supports RW → RX. Route the engine through it and publish cache entries only after sealing succeeds. Darwin `MAP_JIT` plus thread write protection is a separate mechanism and is not itself this violation.

6. **P1 — SMC invalidation and writable Soft-TLB state diverge.**

   | Repository | Defect and repair |
   |---|---|
   | mips32rt | [dbt.c:96](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:96) makes cache/version state thread-local; [invalidation:304](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:304) changes only the writer’s versions. Publish shared invalidation generations and retire each worker’s affected translations. |
   | mips64rt | [dbt.c:319](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:319) arms code pages but evicts writable tags only from the compiling context. A peer’s prefilled tag bypasses the new code mark. Revoke write access across all affected contexts before publication. |
   | loongarch64rt | [dbt_mem.c:306](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:306) fills `write_tag` from ordinary writability, bypassing the [code/reservation gate:571](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:571). Even a load miss can enable later untracked stores into translated code. |
   | ppc32rt | [cache.c:481](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:481) retires blocks by start PC, while emitted chains/self-loops observe only the global epoch. Interior writes can leave old code executable. [cache.c:538](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/cache.c:538) also ignores copyouts exceeding 4096 bytes. |
   | i686rt | [translate.c:215](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/translate.c:215) admits an instruction crossing the page boundary, but [engine.c:552](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:552) protects only the block-start page. Changes to the instruction’s bytes on the next page can escape invalidation. |

   Record source intervals/pages explicitly. Test interior writes, cross-page instructions, peer-prefilled write tags, and linked self-modifying loops.

7. **P1 — MIPS32 LL/SC uses inconsistent epoch indexes.**  
   [emit_mem.c:99](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:99), 104, 114 and 568 emit `UBFM #6,#11`, extracting six bits. The [C helper:381](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:381) uses twelve bits: `(va >> 6) & 4095`. For `0x12340`, the indexes are **13 versus 1165**. A helper’s same-value store can leave a DBT reservation apparently valid. Share the shift/width constants and test mixed DBT/helper LL/SC, including ABA.

8. **P1 — LoongArch chaining can replay a completed block.**  
   The [trampoline:59](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:59) returns the last chained block’s exit reason, but [dbt.c:712](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:712) restores the original block’s `next_pc`. Warm A → B followed by B’s fallthrough to cold C can reset execution to B. Preserve the emitted final PC or return final-block metadata.

9. **P1 — LoongArch recovery misses required rewind information.**  
   [dbt_mem.c:341](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:341) treats successful `dbt_block_rewind` as failure and returns the original PC. Separately, the [FP emission path:381](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:381) continues before common recovery-site collection. Correct the return convention and collect sites through one post-emission path. Test the registered hook with FP-only and mixed memory blocks.

10. **P1 — LoongArch vector execution violates host callee-save requirements.**  
    [emit_fp.c:41](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp.c:41) assigns V8–V10 as scratch, while [trampoline_a64.S:38](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:38) preserves only integer registers. Preserve D8–D10 or use caller-saved vector registers. Validate host D8–D15 sentinels around vector execution.

11. **P1 — RV generated arithmetic contains two concrete defects.**  
    [dbt_emit_fp.c:698](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:698) and 704 use `0x9bb17c00` for UMULH; the assembler confirms `0x9bc17c00`. Also, [single-precision FMA:578](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:578) loads operand three into X3, then calls [emit_unbox_s:114](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:114), which overwrites X3. Introduce a checked UMULH encoder and explicit helper clobber contracts. Test multiply-high boundaries and fused operations with three distinct finite operands.

12. **P1 — i686’s software memory-ordering path is inactive.**  
    [emit_begin:38](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:38) zeroes `tso` and never enables it; [emit_alu.c:125](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:125) therefore always selects ordinary accesses. MOV and extended-ALU paths also use plain accessors. On hosts without established hardware TSO, this violates the intended ordering contract. Implement one memory-access policy across emitters, including alignment handling; merely setting this boolean would leave other paths inconsistent.

Additional correctness and lifecycle work follows:

| Priority | Finding | Required change |
|---|---|---|
| P1 | LoongArch [partial FCSR writes:33](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:33) overwrite preserved fields; field 2 also rebuilds groups incorrectly. | Use a mask-and-merge operation matching the interpreter; test asymmetric bit patterns. |
| P1 | LoongArch [LASX shifts:860](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp.c:860) reuse VT as both mask and result, so the upper half uses the lower-half result as its mask. | Separate mask/output registers; test differing halves. |
| P2 | MIPS64 [FP arithmetic:340](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:340) does not merge exception state into FCSR. | Compare complete FCSR against the interpreter; `ADD.S(2²⁴,1)` exposes missing Inexact. |
| P2 | SPARC64 [publication:228](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:228) hides RX failure, then execution proceeds. RV [cache reset:308](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/cache.c:308) and MIPS64 [begin-write:351](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_linux.c:351) similarly ignore permission failures. | Make permission changes fallible and transactional; inject RW/RX failures before allowing storage reuse or execution. |
| P2 | SPARC64 [step-one:676](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:676) enables chaining. Its dedicated step trampoline’s zero epoch is also bypassed by [the chain loop:69](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/trampoline_a64.S:69). | Implement a real no-chain gate; test with warm IBTC targets. |
| P2 | MIPS32 [SMC version table:304](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:304) silently drops invalidations after 1024 distinct pages. | Use conservative epoch invalidation on saturation; test page 1025. |
| P2 | MIPS64 [arena.c:44](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/arena.c:44) stops recording mappings after 64 entries but continues allocating 8 MiB chunks. | Add bounded exhaustion or safe generation reclamation. Cache-entry count does not bound lifetime allocation. |
| P2 | LoongArch [emit_fp_mem.c:120](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:120) and [dbt_mem.c:217](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:217) sign-extend through overflowing signed left shifts. | Use unsigned extraction and explicit sign extension; run UBSan boundary cases. |
| P2 | MIPS32 [byte staging:546](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:546) is written through a `uint32_t *` cast. | Declare word storage or use byte-safe writes; make alignment/type requirements explicit. |
| P2 | MIPS32 [fault dispatch:820](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:820) classifies alignment using only two address bits. | Preserve fault class/width; mapped LDC1/SDC1 at `base+4` currently selects the wrong signal. |

After those repairs, use this repo-local CLEAN/DRY/YAGNI checklist:

| Repository | Prioritized cleanup |
|---|---|
| **a32rt** | The physical split remains an order-dependent single translation unit: [a64_emit.c:9](/Users/angerman/Projects/zw3rk/a32rt/src/a64_emit.c:9), [jit.c:9](/Users/angerman/Projects/zw3rk/a32rt/src/jit.c:9). Introduce explicit internal interfaces for cache ownership and translation state. [Global site staging:616](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_alu.c:616) belongs in that state. `a32_aot_site_clear` and `a32_difftest_run_dbt` have declarations/definitions but no in-tree callers; determine whether to integrate or remove them. |
| **i686rt** | Remove unused donor exit emitters beginning at [rt32_a64_emit.c:872](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_a64_emit.c:872), plus unused ARM DSP/crypto helpers and associated buffer fields. Consolidate duplicated helper-call save/restore sequences in [emit_branch.c:184](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_branch.c:184), [emit_sse.c:734](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:734), and [emit_alu_impl.h:348](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu_impl.h:348). Replace instruction re-decoding in `site_pc`/`l3c_pc_of` with existing `insn_pc`. `insn_count` is incremented but never consumed. |
| **mips32rt** | Merge duplicated GPR maps/accessors in [emit_int.c:16](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:16) and [emit_fp.c:94](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:94). Remove uncalled `dbt_is_likely` at [dbt.c:143](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:143) and unused copied fields at [a64_emit.h:80](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/a64_emit.h:80). Replace `__thread` with `_Thread_local`. |
| **ppc32rt** | Consolidate FP context loads/stores with existing primitives: [emit_fp.c:101](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:101). Remove unused ARM-only helpers, including [ARM register loading:136](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit.h:136). Replace [semantic data hidden in padding:94](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/dbt.h:94) with named ownership/length fields while retaining layout assertions. |
| **sparc32rt** | Consolidate constant/GPR helpers duplicated between [emit_int.c:80](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:80) and [emit_fast.c:37](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fast.c:37). The seven [AOT-cache APIs:66](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/aot/aot_cache.c:66), `dbt_ibtc_tail`, `dbt_cached_count`, and `dbt_patch_chain` are disconnected from callers. Remove or explicitly integrate them. |
| **rvrt** | Consolidate encoders in [jit/emit.h:11](/Users/angerman/Projects/zw3rk/rvrt/src/jit/emit.h:11), [dbt_emit_fp.h:44](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:44), and [dbt/emit_mem.c:13](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:13). Several cache/RAS/memory APIs are test-only while production uses `darwin_dbt.c`. The test-only memory emitter has incorrect signed-byte and width-16 semantics. Separate active metadata from the [redundant arena allocation:723](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:723). |
| **loongarch64rt** | Consolidate repeated GPR load/store and immediate-materialization helpers around the central encoder. Remove uncalled functions such as [a64e_ret_reg:204](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/a64_emit.c:204), `a64e_br_reg`, `a64e_nop`, `a64e_ldr_w`, `a64e_str_w`, and unused vector helpers. Move global site staging/branch state into a translation object. Its append-only arena has bounded exhaustion and fallback, but no reclamation. |
| **ppc64rt** | Production uses `ppc64_emit_mixed`; standalone whole-block wrappers at [emit_int.c:660](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:660) and [emit_fp.c:242](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.c:242) duplicate lifecycle code without callers. Remove the [obsolete weak stub:54](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:54). Remove write-only chain hints, RAS contents, and `guest_len` after preserving any required ABI layout. |
| **mips64rt** | Two integer encoder layers coexist: [a64_emit.c:48](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/a64_emit.c:48) and [emit_enc.c:33](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_enc.c:33). Most production code uses the latter, while tests exercise the former. Consolidate and redirect tests to production primitives. Remove the [fallback type/header scaffold:22](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.h:22) and write-only arena bookkeeping. |
| **sparc64rt** | [emit_rt.c:28](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_rt.c:28) defines external runtime helpers shadowed by different static-inline implementations in [emit_priv.h:536](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_priv.h:536). Generated calls use the header-local versions. Keep one implementation and declaration. Remove unreferenced `sb_tst_mask3_32`/`s64_rt_popc`; replace GNU alignment attributes with `_Alignas` where applicable. |

For register reservations and magic constants:

- **No concrete direct X18 clobber was established in the reviewed paths.** Several encoders merely mask register numbers or have inconsistent validators, so this is not proof that every emitted word is safe. Add checks for register roles and encoding tests. `V18`/`D18` are not X18 violations.
- **Do not impose one X20/X21 meaning across all repos.** Class-A implementations commonly use X20 for the window and X21 as scratch; RV uses X20 for TLB and X21 for CPU context; MIPS64 uses X20 for TLB despite [stale guest-base documentation:52](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.h:52); LoongArch pins X21 as TLB.
- Centralize layout offsets, masks, strides, and helper clobbers. Examples include [RV context offsets:301](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:301), [PPC32 RAS layout:234](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_a64_emit2.c:234), and [LoongArch’s literal TLB offset:52](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:52). Use shared assembly-compatible constants plus `_Static_assert`.
- Documented opcode bases and guest ABI numbers are necessary constants. Prioritize duplicated semantic constants that can diverge—the MIPS32 epoch mask and RV UMULH word already demonstrate that failure.
- Distinguish host page/cache properties from guest constants. [MIPS32 publication:522](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:522) hardcodes host-page rounding; [A32 I-cache maintenance:296](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_jit_mem.c:296) assumes a 64-byte stride.

Verification used numbered source inspection, whole-tree symbol searches, `rg --files`, `wc -l`, and clean Git snapshots. Selected DBT C units in **all ten repos** passed native Darwin Clang syntax checks with:

```text
-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror -fsyntax-only
```

SDK/include paths and Darwin feature macros were supplied as required. These checks do not establish Linux runtime or assembly correctness. The independent encoding check was:

```sh
printf 'umulh x0, x0, x1\numulh x2, x0, x1\nsmulh x0, x0, x1\n' |
  /Library/Developer/CommandLineTools/usr/bin/clang -cc1as \
  -triple aarch64 -filetype asm -show-encoding -o -
```

It confirmed UMULH bytes `00 7c c1 9b` and `02 7c c1 9b`.

Implement the safety and wrong-code repairs first, then remove dead implementations, consolidate primitives within each repo, and split remaining large files by responsibility. Keep the standalone repositories; this audit does not justify a shared cross-repo runtime library.