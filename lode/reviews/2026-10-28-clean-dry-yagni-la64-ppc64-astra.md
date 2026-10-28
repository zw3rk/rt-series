The audit found **high-priority correctness and architecture defects in both repositories**. File-size gates and strict C compiler checks pass, but the current differential tests miss several of the defects below.

Reviewed clean working trees at:

- `loongarch64rt`: `ac4f0a9203dddc067b4da818b9fadcdf8a1066c6`
- `ppc64rt`: `eef6dc00cc4db0c1fafc68d740ef4b87de11908b`

Findings are source-confirmed unless marked as requiring runtime verification. No files were changed.

**CLEAN:** No source file exceeds approximately 1,000 lines. Both repositories pass their stricter `make check-line-limits` gate of 900 newline-counted lines. However, several files effectively contain one enormous function.

| Repository | Source inventory | Largest functions needing decomposition |
|---|---:|---|
| LoongArch | 89 `.c/.h/.S` files; approximately 28,000 lines | [`interp_step`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:58): approximately 804 lines; [`fp_step_scalar`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:345): 551; [`la64_emit_int`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_int.c:452): 424 |
| PPC64 | 79 `.c/.h/.S` files; approximately 28,600 lines | [`execute`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:303): approximately 580 lines; [`ppc64_fp_str_step`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:162): 433; [`syscall_mm_mmap`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_mm_map.c:164): 273 |

PPC64’s `interp.c` has 901 logical lines but 900 newline characters because its final line lacks a newline; the existing gate counts the latter.

**DRY:** The strongest duplication problems are backend plumbing, emitter lifecycle and recovery metadata, repeated errno conversion, and old execution paths alongside newer ones. Some duplication between interpreter and DBT is valuable because they should remain independent semantic implementations.

**YAGNI:** PPC64’s **`emit_int.c` remains active** through `ppc64_emit_int_one`. Its whole-block wrapper is obsolete; deleting the entire file would break mixed-block lowering. Conversely, several live compatibility shims implement incomplete behavior and require replacement before removal.

**Curated C11:** All four product C source configurations passed syntax checks with the required warnings, including `-Werror`. I found no actual production calls to `sprintf`, `strcpy`, or `strcat`, and no concrete X18/W18 use in the inspected register plans and assembly. Nevertheless, the audit found definite undefined behavior and memory-safety defects that those compiler checks do not diagnose.

The following **High-priority checklist** should precede structural cleanup.

- [ ] **H1 — PPC64: replace deterministic production entropy.**  
  [`syscalls_misc.c:77`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:77) seeds `getrandom` with a fixed xorshift state; [`:155`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:155) uses it in normal execution and ignores flags. [`load.c:35`](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:35) supplies constant `00..0f` bytes for `AT_RANDOM`. Guest keys, nonces and canaries can therefore be predictable. **Remediation:** use host entropy in production; inject or replay randomness explicitly in difftest. **Acceptance:** production runs differ, while explicit replay remains deterministic.

- [ ] **H2 — PPC64: validate ELF bounds before reading fields or program headers.**  
  [`load.c:328`](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:328) reads fields before validating the header length; [`:338`](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:338) walks the program-header table before checking its extent. The later addition-based check can wrap. **Remediation:** validate the header first, then require `phoff <= len && phnum <= (len - phoff) / 56`; validate segment and load-bias arithmetic similarly. **Acceptance:** truncated headers, huge offsets and wrapped extents fail cleanly under ASan.

- [ ] **H3 — PPC64: make emitter patching capacity-safe.**  
  [`emit_core.h:100`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:100) stops emission at capacity, but branch reservations can return `at == cap`; patchers at [`:126`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:126) and `:158` then write `o[at]` unconditionally. [`emit_mem.c:165`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mem.c:165) repeats the pattern. **Remediation:** make failed reservations explicit and bounds-check every patch operation. **Acceptance:** sweep output capacities from zero through the required size using canaries/ASan, including long FP blocks.

- [ ] **H4 — LoongArch: preserve the final executed block’s PC after chaining.**  
  [`trampoline_a64.S:59`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:59) can execute several blocks, but [`dbt.c:713`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:713) handles FALLTHROUGH using the original block’s `next_pc`. A warm A→B chain ending at a cold successor can resume at A’s sequential successor. **Remediation:** treat the PC committed by executed code as authoritative. **Acceptance:** prewarm A and a 64-instruction B, leave B’s successor cold, and verify distinct side effects and the final PC.

- [ ] **H5 — LoongArch: repair SMC marking and enforce the write gate during refill.**  
  [`dbt.c:486`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:486) passes a block-sized byte range to `vm64_mark_code`, while [`vm64.c:402`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:402) requires page-aligned ranges. Ordinary blocks therefore fail marking silently. Separately, [`dbt_mem.c:306`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:306) grants writable TLB tags from write permission alone, bypassing code-page, reservation and COW restrictions. **Remediation:** mark intersecting pages, cover high-VA region mappings, and use one authoritative refill/write-gate implementation. **Acceptance:** rewrite translated code twice, including high mappings, and verify both changes execute.

- [ ] **H6 — LoongArch: fix the actual preemption hook and FP recovery-site registration.**  
  [`dbt_mem.c:341`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:341) returns the original host PC when `dbt_block_rewind` succeeds. Also, successful FP lowering at [`dbt.c:381`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:381) skips the common recovery-site drain. FP memory at block end can lose its site; a following memory instruction can be rejected because staging remains pending. **Remediation:** correct the success branch and route all successful lowerings through common finalization. **Acceptance:** preempt at each lookup instruction, including consecutive FP accesses and FP accesses at page/block ends.

- [ ] **H7 — LoongArch: preserve the host SIMD callee-saved registers.**  
  [`emit_fp.c:41`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp.c:41) uses V8–V10 as scratch; [`trampoline_a64.S:35`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:35) preserves only GPRs. The low 64 bits of V8–V15 are callee-saved under [AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst). **Remediation:** use caller-saved vector registers or save the required D registers. **Acceptance:** seed D8–D15 around a translated LSX/LASX call and verify preservation.

- [ ] **H8 — LoongArch: preserve the LASX shift mask across both halves.**  
  [`emit_fp.c:857`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp.c:857) initializes `VT` with the count mask, then overwrites it with the first-half result. The second half consequently masks counts with data. **Remediation:** use a separate mask register or reload it per half. **Acceptance:** use zero data in the lower half, nonzero upper data, and shift counts of one; compare all 256 bits.

- [ ] **H9 — PPC64: lower `stfdu` as an eight-byte double store.**  
  [`emit_fp_vs.c:199`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:199) admits opcode 55, but its store path converts to float and emits width four. **Remediation:** implement an eight-byte raw-double store and update RA only after success. **Acceptance:** check all eight destination bytes, neighboring sentinels and page-boundary faults. The existing [`test_p3_fp_simd.c:264`](/Users/angerman/Projects/zw3rk/ppc64rt/tests/test_p3_fp_simd.c:264) checks the updated pointer, then reloads the old address, so it misses this corruption.

- [ ] **H10 — PPC64: connect reservation instructions to the VM atomic contract.**  
  [`interp.c:517`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:517) implements LARX/STCX using process-global reservation state and ordinary reads/writes. The VM atomic callback is installed but unused by execution. LQARX/STQCX additionally pass width 16 to the 64-bit helpers at [`interp.h:150`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:150), causing shifts of 64–120 bits and losing the paired GPR. **Remediation:** implement CPU-owned reservations and pair-aware atomic operations through the VM. **Acceptance:** distinct 128-bit halves, UBSan, and two contexts with an intervening store.

- [ ] **H11 — PPC64: correct variable-shift semantics in both engines.**  
  [`interp.h:557`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:557) and [`emit_int.c:328`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:328) discard the count bit that distinguishes oversized shifts. For example, `SLD(1,64)` produces one instead of zero. [IBM specifies zero for SLD counts 64–127](https://www.ibm.com/docs/en/aix/7.2.0?topic=set-sld-shift-left-double-word-instruction). **Remediation:** preserve the architectural count width and implement zero/sign-fill and carry behavior. **Acceptance:** counts 0, 31, 32, 63, 64, 127 and 128 against QEMU.

- [ ] **H12 — PPC64: establish correct FP precision, rounding and status semantics.**  
  [`fp.c:259`](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:259) treats single arithmetic as double arithmetic; [`emit_fp_vs.c:401`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:401) deliberately mirrors it. Rounding-mode and exception handling also contain approximations, including finite division being treated as inexact. [IBM’s FADD/FADDS contract](https://www.ibm.com/docs/en/aix/7.2.0?topic=set-fadd-fa-floating-add-instruction) requires the appropriate precision and FPSCR rounding. **Remediation:** qualify the interpreter against QEMU, then repair lowering. **Acceptance:** half-ULP additions, directed rounding, exact/inexact division and record-form status updates.

- [ ] **H13 — LoongArch: make failed `execve` preserve the old process.**  
  [`minsys.c:463`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:463) leaves `environ` referring to freed/local storage after native exec failure. The guest path closes CLOEXEC descriptors before loading; [`loader.c:648`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:648) resets memory before the new image is fully validated. **Remediation:** stage the image, interpreter and arguments; commit replacement and CLOEXEC only after successful preparation; restore environment on failure. **Acceptance:** failed native exec, missing interpreter and truncated load segment leave old memory and descriptors usable.

- [ ] **H14 — LoongArch: enforce read permissions during guest copyin.**  
  [`vm64_dispatch.c:46`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64_dispatch.c:46) and [`mem_min.c:274`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:274) check write permission but omit read permission. Arena-backed `PROT_NONE` data can therefore reach syscall copyin; region-backed accesses may host-fault. **Remediation:** distinguish read, write, fetch and privileged loader access. **Acceptance:** guest loads and `write`/`writev`/pathname copyin from inaccessible mappings produce the correct guest fault or `EFAULT`.

- [ ] **H15 — LoongArch: finish host protection changes before publishing the mutation.**  
  [`mem_min.c:485`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:485) commits/unparks before the host protection sweep at `:487`; `protect_host_page` also ignores failure. **Remediation:** retain quiescence through the host operation, propagate errors, then publish metadata, invalidate and resume. **Acceptance:** concurrent permission changes and injected host `mprotect` failure preserve consistent state.

- [ ] **H16 — LoongArch: make signal masks and alternate stacks thread-owned.**  
  [`sigframe.c:45`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:45) stores blocked/pending state and altstack globally; [`:469`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:469) explicitly ignores the context during mask changes. **Remediation:** keep dispositions process-owned and move per-thread state into the guest-thread object. **Acceptance:** two threads maintain different masks and alternate stacks.

- [ ] **H17 — PPC64: replace live thread/process compatibility shims.**  
  [`syscalls_p4.c:173`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_p4.c:173) executes clone children inline; [`:198`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_p4.c:198) returns `EAGAIN` even for matching FUTEX_WAIT values. [`syscalls.c:570`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls.c:570) discards decoded clone-mode details, while [`proc.c:315`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/proc.c:315) implements vfork without sharing or parent suspension. Guest exec calls host `execve` directly. **Remediation:** connect real worker/futex and Class-B family/bootstrap behavior. **Acceptance:** child-waits-for-parent handoff, CLONE_VM visibility, vfork suspension and foreign-image exec without relying on host binfmt.

- [ ] **H18 — Both: repair differential testing before trusting “0 divergences.”**  
  LoongArch’s [`main.c:129`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/main.c:129) compares DBT stdout/exit, then compares an interpreter trace with another interpreter run; it excludes vector state. PPC64’s [`run.h:60`](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/run.h:60) allocates only half the VSR snapshot, excluding VSR32–63, and comparison omits memory effects. **Remediation:** compare actual DBT architectural state at defined boundaries, include complete vectors and memory effects, and replay external syscall effects. **Acceptance:** deliberate register-only, VSR63-only and store-only discrepancies must each fail.

The following **Medium-priority checklist** addresses UB, architecture and maintainability.

- [ ] **M1 — Remove LoongArch signed-shift and FP-conversion UB.**  
  [`emit_fp_mem.c:120`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:120), [`dbt_mem.c:217`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:217) and [`fp_vec.c:121`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:121) sign-extend through overflowing signed left shifts. Use unsigned extraction plus explicit sign subtraction. [`fp.c:311`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:311) checks bounds before rounding: `2147483647.75` passes, rounds out of range, then undergoes an undefined integer conversion. Check the rounded result before casting; cover all rounding modes and exact endpoint values.

- [ ] **M2 — Consolidate repository-local backend plumbing.**  
  Exact-line comparison found 326 matching lines in PPC64’s Linux/Darwin backends, in contiguous runs of at least eight lines; LoongArch has 83 in its primary backend pair and 164 in its sync pair. These counts include comments. Start with PPC64 errno conversion at [`backend_linux.c:69`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_linux.c:69)/[`backend_darwin.c:64`](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_darwin.c:64), identical validation and worker plumbing. Preserve host-specific syscall/JIT behavior and standalone repositories.

- [ ] **M3 — Share mechanical emitter helpers and recovery metadata.**  
  LoongArch duplicates GPR encoders and FP memory classification across [`emit_fp_mem.c:101`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:101), [`emit_ldst.c:28`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_ldst.c:28) and `dbt_mem.c`. PPC64 duplicates memory-site construction at [`emit_fp.c:29`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.c:29) and [`emit_fp_vs.c:100`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:100). Centralize encodings, decoded access metadata and capacity handling; retain independent interpreter semantics.

- [ ] **M4 — Replace textual `.c` inclusion with real module boundaries.**  
  LoongArch’s [`interp.c:42`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:42) includes decoder/FP implementation files, while [`minsys.c:23`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:23) includes a syscall implementation that includes further implementations. Compile each unit once, introduce small private interfaces, and retire weak-definition arrangements. Split the large functions listed above by opcode/syscall family, keeping dispatch shallow.

- [ ] **M5 — Give mutable runtime state explicit ownership and lifetime.**  
  LoongArch’s supposedly per-thread caches are globals at [`dbt_chain.c:26`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_chain.c:26). PPC64 has process-global cache/AOT registries alongside thread-local IBTC state at [`dbt.c:114`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:114). Document and enforce ownership, reset and invalidation rules; move state into VM/process/thread objects where appropriate. Existing historical comments do not establish a measured performance reason for global ownership.

- [ ] **M6 — Close gaps between contract parsing, primitive tests and production wiring.**  
  LoongArch parses authority settings in [`host_args.h:68`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/host_args.h:68), but `main` does not apply those settings. Its [`family_broker.c:36`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/family_broker.c:36) directory create/join helpers are test-only. Likewise, tested VM refill/rewind helpers differ from the production DBT implementations. Wire the required behavior or report unsupported options explicitly; make acceptance exercise installed production hooks.

- [ ] **M7 — Repair incremental-build and test wiring.**  
  PPC64 product prerequisites at [`Makefile:39`](/Users/angerman/Projects/zw3rk/ppc64rt/Makefile:39) omit headers, allowing header-only edits to leave stale binaries; LoongArch tracks only selected headers. Add generated dependencies or complete prerequisites. PPC64’s [`p6_host_contract.sh:81`](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_host_contract.sh:81) still references deleted `src/rt64` files. Its `make check` description says “all gates,” but the target only builds, checks sizes and checks ABI invariants. Make names/descriptions match coverage and restore the contract test against current modules.

- [ ] **M8 — Tighten API boundaries and C11 portability.**  
  [`aot_sites_save` at sites.c:327](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/aot/sites.c:327) validates `path` and counts but dereferences `blocks` without checking it. Add the missing check and a focused negative test. Replace unguarded alignment attributes in [`LA cpu.h:106`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/core/cpu.h:106) and [`PPC cpu.h:67`](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:67) with `_Alignas`; isolate genuinely platform-specific attributes. GCC/Clang acceptance alone does not establish the requested universal C11 portability.

- [ ] **M9 — Instrument JIT capacity before changing allocation policy.**  
  LoongArch’s [`dbt_code.c:31`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_code.c:31) documents a fresh sealed 64 KiB allocation per translation and a fixed 1,024-page limit; exhaustion falls back to interpretation. Add default-off allocation/exhaustion and phase counters, measure representative workloads, then choose a reclamation policy. This is a verified capacity limitation; its performance impact was not measured.

The **Low-priority checklist** contains proven cleanup candidates.

- [ ] **Remove obsolete whole-block emitters and integration stubs.**  
  PPC64’s production dispatcher uses `ppc64_emit_mixed`; retain the live integer instruction implementation and remove unused wrappers at [`emit_int.c:660`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_int.c:660) and [`emit_fp.c:242`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp.c:242), after checking supported external harnesses. Retire weak integration stubs in [`PPC dbt.c:63`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:63) and [`LA dbt.c:62`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:62).

- [ ] **Remove write-only metadata and unused constants.**  
  LoongArch: `dbt_block_t.exit` at [`dbt.c:177`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:177), uncalled `dbt_epoch()` at `:148`, and the Phase-0 [`worker_loop.c:31`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/worker_loop.c:31) execution stub. PPC64: write-only `chain_target` and RAS storage at [`dbt.c:96`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/dbt.c:96)/`:115`, plus unused FP macros at [`emit_fp_vs.c:63`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_fp_vs.c:63). Decoded clone fields belong to H17’s missing behavior and should be implemented.

- [ ] **Normalize names and replace misleading comments.**  
  Remove duplicate helper naming such as `e_put`/`put`, `e_at5`/`at5` in [`emit_core.h:100`](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_core.h:100). Correct LoongArch’s “FP still aborts pre-Phase 3” statement at [`main.c:139`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/main.c:139) and indexed-load fallback comment at [`emit_int.c:778`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_int.c:778). Replace historical lane/frozen-header prose with current contracts.

- [ ] **Name policy constants and remove unnecessary nesting.**  
  Centralize repeated capacity values such as emitter exit/site limits; retain documented instruction-encoding constants as such. Simplify the redundant nested scopes around [`LA main.c:713`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/main.c:713). Avoid mechanically extracting every numeric ISA encoding into a separate abstraction.

- [ ] **Verify handwritten-crypto approval provenance.**  
  [`LA sha256.c:35`](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/aot/sha256.c:35) contains an in-tree SHA-256 implementation. The global rules require established crypto libraries or explicit approval for handwritten crypto. I did not establish whether earlier approval exists; verify provenance and otherwise replace it with an established implementation consistent with static packaging.

For the requested **`-O2` investigation**, the strongest concrete leads are:

| Repository | Why optimized guest code can expose the defects | Discriminating next check |
|---|---|---|
| LoongArch | Longer straight-line blocks expose chained FALLTHROUGH handling; adjacent FP memory operations expose missing recovery-site finalization; LASX operations expose the overwritten mask. | Reduce the failing guest to its actual block sequence; compare normal multi-instruction execution with single-step execution, preserving page boundaries and warm-cache state. |
| PPC64 | Register-held float intermediates expose missing single rounding; optimized code may select unsupported XS*/XV* arithmetic; `stfdu` corrupts stores. | Inspect the actual guest disassembly, then compare QEMU, interpreter and DBT on the first differing instruction/state. |
| Both | Current difftest coverage can report success despite register or memory corruption. | Complete H18 and include deliberately injected discrepancies before relying on the result. |

The float recurrence in [`bench_suite.c:656`](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:656) is particularly relevant to PPC64 precision. The benchmark harness also has separate [`-O1` build paths](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:187) and an [`-O2` path](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:245), while PPC64’s parity suite compiles guests with [`-O1`](/Users/angerman/Projects/zw3rk/ppc64rt/tests/parity_suite.sh:91). Record the actual compiler, CPU flags and binary identity for any comparison. These findings identify concrete candidates; they do not establish the cause of an unprovided benchmark failure.

Validation completed:

- `make check-line-limits`: **passed in both repositories**.
- C source lists and defines from `make -Bn build-darwin`, LoongArch `make -Bn build-linux`, and PPC64 `make -Bn build` were checked using `-O2 -std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror -fsyntax-only`: **all four passed**, using direct CLT Clang and AArch64-musl GCC.
- Source inventory, call-site/reachability searches, duplication comparison and targeted control-flow review completed.

The read-only environment prevented rebuilding executable tests or running new ASan/UBSan reproducers. Assembly/linking, QEMU parity, concurrent stress, hyper-linux and native Darwin JIT execution remain unverified. Linux RW→RX publication and cache-flush paths are present; Darwin’s differing MAP_JIT lifecycles need a native execution probe. I found no basis to report MAP_JIT’s mapping flags alone as a W^X violation.