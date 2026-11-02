# i686rt static audit

**HEAD:** `2fa17fbb56b8d425a896af232e034ba88f653936`

**Result:** 20 findings, including guest permission bypasses, stale translations across threads, incorrect fault-state recovery, and missing memory-ordering enforcement.

The inventory contains **89 runtime `.c`/`.h`/`.S` files totaling 48,211 lines**. Including headers, tests, and experiments, the counted files total **78,809 lines**. Inspection concentrated on VM management, DBT translation/cache/fault recovery, interpreter execution, signals, and selected backend, loader, decoder, and floating-point paths.

**Limits:** Seven shell inspection commands were issued, including one rejected heredoc. Some large outputs were truncated. This is a bounded static audit, **not an exhaustive review of every module**; syscall families, x87-80 arithmetic, and individual ISA handlers remain incompletely reviewed. No builds, compilers, QEMU, Docker, or tests were invoked. No repository changes were made.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 0 | 2 | 0 | 0 | 0 | 10 |
| Medium | 2 | 1 | 1 | 0 | 0 | 1 | 5 |
| Low | 0 | 0 | 0 | 1 | 1 | 3 | 5 |
| **Total** | **10** | **1** | **3** | **1** | **1** | **4** | **20** |

Severity reflects the source-supported failure mode, not a demonstrated exploit. All proposed factoring stays **inside i686rt**.

## 1. Bugs & Defects

### High

- [ ] **I686-1 — High — BUG — A2 fault recovery permanently opens protected sub-pages**
  - **Where**: `src/os/signals_i386.c:707-754` (`i686_spurious_emulate`); `src/vm/vm32.c:148-173` (`i686_vm32_union_prot`).
  - **What breaks / Why**: After the per-host-page counter reaches 64, recovery applies the union of sub-page permissions and returns without restoring the restrictive cover. A writable 4 KiB neighbor therefore makes a `PROT_NONE` or read-only sub-page accessible through the same 16 KiB host page. Direct guest accesses subsequently succeed without entering the fault handler, so its permission checks cannot help. Before that threshold, temporarily opening the process-wide mapping also exposes the protected neighbors to other guest threads.
  - **Fix**: Remove the leave-open heuristic. Enforce guest permissions on every access through an integrated software translation/checking path, including cross-page accesses. Any temporary host-permission change must prevent concurrent threads from bypassing guest protection.

- [ ] **I686-2 — High — BUG — SMC invalidation leaves other threads executing stale code**
  - **Where**: `src/dbt/engine.c:86-116` (`s_ht`, `s_code_pages`, `s_run_ctx`); `src/dbt/engine.c:302-332` (`smc_drop_host`); `src/dbt/engine.c:403-426` (`i686_dbt_smc_write_fault`).
  - **What breaks / Why**: Translation caches are thread-local, while the code-page bitmap and host page protections are shared. A write fault clears only the faulting thread’s cache and context links, then makes the page writable process-wide. Another thread retains translations of the old bytes, and further writes need not fault.
  - **Fix**: Track code generations per shared guest page. Publish invalidations to every execution context, interrupt or synchronize active execution where necessary, and reject stale cache/IBTC entries before reuse.

- [ ] **I686-3 — High — BUG — SMC handling overrides guest memory permissions**
  - **Where**: `src/dbt/engine.c:174-207` (`smc_unprotect_host`, `smc_protect`); `src/dbt/engine.c:335-360` (`i686_dbt_invalidate_range`); `src/rt32/rt32_vm.c:974-988` (`rt32_vm_mprotect`).
  - **What breaks / Why**: SMC unprotection blindly restores `PROT_READ | PROT_WRITE`, without checking the guest mapping’s permissions. Consequently, a write to translated read-only code can be accepted as an SMC write. Separately, `rt32_vm_mprotect` applies the requested protection and then invalidates translations; invalidation can immediately replace that protection with RW on a marked page.
  - **Fix**: Keep guest permissions separate from translator-imposed write protection. Handle a fault as SMC only when the guest mapping permits the access. Restore effective host permissions from current guest metadata, and order invalidation so it cannot undo `mprotect`.

- [ ] **I686-4 — High — BUG — Threaded DBT execution never enables TSO lowering**
  - **Where**: `src/dbt/emit_exit.c:38-47` (`i686_emit_begin`); `src/dbt/emit_alu.c:128-155` (guest-memory lowering); `src/dbt/emit_sse.c:786-792` (`I686_OP_SFENCE`).
  - **What breaks / Why**: Emitter initialization zeroes `e->tso`; the inspected source references contain no assignment enabling it. Memory lowering consequently retains the non-TSO path after threads exist. `SFENCE` is also emitted as nothing under an explicitly single-threaded assumption. AArch64 can therefore expose load/store orderings forbidden by x86, despite correct ordering on individual LOCK operations.
  - **Fix**: Implement the shared transition to threaded execution, invalidate existing translations, and consistently enable the required ordering for scalar, string, and SIMD accesses. Lower fences according to their architectural guarantees.

- [ ] **I686-5 — High — BUG — Flag elimination crosses faulting instructions**
  - **Where**: `src/dbt/translate.c:98-105`, `src/dbt/translate.c:160-182`, `src/dbt/translate.c:239-260` (`tr_classify`, skip analysis); `src/dbt/emit_alu.c:258-264`, `src/dbt/emit_alu.c:379-408` (flag emission).
  - **What breaks / Why**: The analysis treats memory MOV instructions as transparent and removes earlier flag updates when a later instruction overwrites flags. For `add eax,1; mov ecx,[inaccessible]; xor edx,edx`, the ADD flags are omitted even though the MOV can fault before XOR executes. The guest signal frame must contain ADD’s flags. Recovering live GPRs cannot reconstruct a flag update that was never emitted.
  - **Fix**: Treat potentially faulting instructions as flag-observation barriers, or retain sufficient per-site recovery information to reconstruct the precise flags at each fault. Do not eliminate flag computation unless every intervening exit is covered.

- [ ] **I686-6 — High — BUG — Translation pre-scan faults on instructions that will not execute**
  - **Where**: `src/dbt/translate.c:224-238` (`i686_dbt_translate` pre-scan); `src/x86/decode.c:76-80` (`fetch8`).
  - **What breaks / Why**: Pre-scan decodes up to 64 instructions without stopping at control-flow terminators. Instruction fetch directly dereferences guest memory. A branch before the end of a mapped page can therefore cause translation to decode unreachable trailing bytes, including an instruction extending into an inaccessible next page. That host fault becomes a guest fault even though execution would have branched away.
  - **Fix**: Stop pre-scan at block terminators. Make speculative decoding fault-contained, so failure beyond the executable block cannot be delivered as an architectural guest fault.

- [ ] **I686-7 — High — BUG — Moving or growing mremap loses backing-object semantics**
  - **Where**: `src/rt32/rt32_vm.c:1079-1081`, `src/rt32/rt32_vm.c:1102-1107`, `src/rt32/rt32_vm.c:1141-1162` (`rt32_vm_mremap`).
  - **What breaks / Why**: Remapping constructs anonymous mappings regardless of the original backing. Growth appends anonymous pages; relocation allocates anonymous storage and copies bytes. A moved `MAP_SHARED` mapping no longer aliases the original file or other mappings, and file-backed growth does not preserve file offsets or contents. Preserving the shared flag alone does not preserve the backing object.
  - **Fix**: Retain backing identity and offsets in mapping metadata. Move or extend the original backing with appropriate host primitives, or return an explicit unsupported error where faithful remapping is unavailable.

- [ ] **I686-8 — High — BUG — Default-action pending signals are silently discarded**
  - **Where**: `src/os/signals_i386.c:823-852` (`i686_deliver_pending`).
  - **What breaks / Why**: Unblocked signals with `handler == 0` (`SIG_DFL`) follow the same clearing path as `SIG_IGN`. A pending signal whose default action is termination or stopping is removed without performing that action.
  - **Fix**: Implement the default-action table, distinguishing ignore, terminate, core-producing termination, stop, and continue. Preserve uncatchable/unblockable signal rules and apply process-wide actions to the whole guest thread group.

### Medium

- [ ] **I686-9 — Medium — BUG — SSE double arithmetic ignores guest rounding mode**
  - **Where**: `src/interp/h_sse.c:405-458` (`sse_f64_op`).
  - **What breaks / Why**: ADD/SUB/MUL/DIV execute as host `double` operations without applying MXCSR’s rounding-control bits. The comment explicitly acknowledges the gap. Directed-rounding guest computations therefore produce incorrect results, including incorrect finite-versus-infinite overflow outcomes.
  - **Fix**: Execute with the guest rounding mode under compiler-supported floating-point environment semantics, restoring host state afterward, or use a correctly rounded implementation. Cover all four rounding modes and associated exception flags.

- [ ] **I686-10 — Medium — BUG — Signal frames export binary64 storage as x87 extended precision**
  - **Where**: `src/i686rt.h:144-146` (`x87_st` representation contract); `src/os/signals_i386.c:159-171` (`i686_sigframe_build`).
  - **What breaks / Why**: Default x87 mode stores a binary64 value in each slot’s low eight bytes. Signal-frame construction copies ten bytes from that slot directly into the ABI’s 80-bit x87 register image. The resulting exponent/significand encoding is not the represented guest value. Handlers inspecting or modifying floating-point context receive an invalid representation.
  - **Fix**: Convert the internal representation into architectural 80-bit register images when building frames, and perform the inverse conversion on restoration. Keep raw copying only for genuinely architectural extended-precision storage.

- [ ] **I686-11 — Medium — DEFECT — Linux JIT mappings remain writable and executable**
  - **Where**: `src/dbt/engine.c:656-704` (`dbt_get_or_compile`).
  - **What breaks / Why**: The Linux path allocates code with RWX permissions and publishes it without an RX transition. Instruction-cache synchronization does not enforce W^X. This leaves executable translator memory writable throughout its lifetime.
  - **Fix**: Generate into RW storage, perform cache synchronization, then change to RX before publication. Use controlled writable aliases only if required, with explicit synchronization and ownership.

## 2. Curated C11 & UB Issues

- [ ] **I686-12 — High — C11 — Fault recovery unlocks a mutex without proving ownership**
  - **Where**: `src/dbt/engine.c:44-51` (`s_jit_toggle_mutex`); `src/dbt/engine.c:744-762` (`i686_dbt_run` fault recovery).
  - **What breaks / Why**: Every Darwin host-fault recovery attempts to unlock the JIT mutex, including faults during ordinary generated-code execution when that thread never acquired it. The default mutex initializer does not guarantee an error-checking mutex; unlocking an unowned or unlocked mutex is not guaranteed to “fail harmlessly” as the comment claims. It can corrupt synchronization or invoke undefined behavior.
  - **Fix**: Track translation-lock ownership in thread-local state and unlock only when owned. Restore JIT write-protection state on that same cleanup path before resuming execution.

- [ ] **I686-13 — High — C11 — Global fault-site cursor races between translators**
  - **Where**: `src/dbt/emit_mov.c:91-127` (`s_pc_ctx`, `s_pc_base`, `s_pc_buf`, `s_pc_cur`, `site_pc`).
  - **What breaks / Why**: Fault-site attribution mutates four process-global variables without synchronization. Linux guest threads can translate concurrently, producing C data races and mixing the context, buffer, and PC cursor of separate translations. Incorrect site metadata can make fault recovery report or replay the wrong guest instruction.
  - **Fix**: Use the existing per-instruction `e->insn_pc` directly for site attribution. Remove the global cursor and redundant decoding; otherwise, keep all cursor state inside the per-translation emitter context.

- [ ] **I686-14 — Medium — C11 — Signal tracing dereferences byte arrays through uint32_t pointers**
  - **Where**: `src/os/signals_i386.c:293-318` (`i686_sigframe_build`, trace diagnostics).
  - **What breaks / Why**: `tcbdump` is a declared `uint8_t[16]`, but diagnostics read it through `const uint32_t *` casts. These accesses violate the declared object’s effective-type rules and lack a language-level alignment guarantee. Enabling diagnostics introduces undefined behavior.
  - **Fix**: Copy each word into a properly typed `uint32_t` local with `memcpy`, then print those locals.

The inspected Makefile includes the requested C11 warning flags. The targeted source scan found no textual `.c` includes or direct calls to `sprintf`, `strcpy`, `strcat`, or `atoi`. Those scan results do not establish complete UB freedom or prove x18 reservation throughout generated code.

## 3. DRY — Intra-Repo Duplication

- [ ] **I686-15 — Low — DRY — Host-page-size discovery is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:71-81`; `src/os/backend_darwin.c:56-66` (`rt_host_page_size`).
  - **What breaks / Why**: Both implementations duplicate cached `sysconf(_SC_PAGESIZE)` discovery; only the fallback differs. Changes to validation, initialization, or synchronization must be maintained twice.
  - **Fix**: Put the common discovery logic in an i686rt-local backend utility, passing the platform fallback explicitly. Keep platform-specific mapping behavior in its backend.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **I686-16 — Low — YAGNI — Allocated Soft-TLB has no production fill integration**
  - **Where**: `src/vm/vm32.c:58-75` (`i686_vm32_init`); `src/vm/vm32.c:91-120` (`i686_vm32_tlb_fill`); `src/trampoline.S:47-48` (`i686_jit_run_block`).
  - **What breaks / Why**: A2 allocates and initializes a Soft-TLB, but the source reference search found no production caller of its fill routine. The trampoline loads `guest_base` into x20. The allocation and API therefore do not provide the software permission enforcement claimed by the VM documentation.
  - **Fix**: Integrate the TLB into actual generated accesses and miss handling as part of repairing I686-1. If that work is deferred, remove unused allocation/API scaffolding and document the implemented execution path accurately.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **I686-17 — Medium — CLEAN — Twenty-three files exceed the 900-line limit**
  - **Where**: The following verified files exceed the ceiling; ranges identify the excess:
    - `src/rt32/rt32_a64_emit.c:901-1235`
    - `src/rt32/rt32_vm.c:901-1182`
    - `src/dbt/engine.c:901-930`
    - `src/interp/v86.c:901-975`
    - `src/interp/h_sse.c:901-2156`
    - `src/interp/x87_80.c:901-2971`
    - `src/interp/h_x87.c:901-2276`
    - `src/x86/insn_tab.h:901-960`
    - `src/os/sys_ipc.c:901-1170`
    - `src/os/sys_time.c:901-1080`
    - `src/os/sys_sock.c:901-1216`
    - `src/os/sys_misc.c:901-1249`
    - `src/os/sys_pass.c:901-2108`
    - `src/os/syscalls_i386.h:901-951`
    - `tests/unit/test_l5a.c:901-938`
    - `tests/unit/test_l1e.c:901-1083`
    - `tests/unit/test_l5b.c:901-957`
    - `tests/unit/test_l1b.c:901-966`
    - `tests/unit/test_l5c.c:901-998`
    - `tests/unit/test_l1d.c:901-1271`
    - `tests/unit/test_l5d.c:901-1301`
    - `tests/test_p1_isa.c:901-1039`
    - `tests/probe_strfuncs.c:901-1473`
  - **What breaks / Why**: Fourteen runtime files and nine test files violate the requested limit. The Makefile’s checker covers selected historical lane-owned files rather than the repository-wide rule (`Makefile:238-262`). Correction to the interim update: the runtime count is **14**, not 15.
  - **Fix**: Split by cohesive instruction families, syscall families, and test groups, using ordinary separately compiled translation units. Extend the checker to all applicable `.c`, `.h`, and `.S` files; do not use textual `.c` inclusion.

- [ ] **I686-18 — Low — CLEAN — Default test target reports obsolete phase-zero status**
  - **Where**: `Makefile:91-97` (`test`, `test-p0-lima`).
  - **What breaks / Why**: `make test` succeeds after printing “phase 0: no tests yet,” although the repository contains substantial test infrastructure. Users or automation selecting the conventional test target receive success without validation.
  - **Fix**: Connect `test` to a documented, bounded existing test aggregate, or fail explicitly with the required target selection. Update the help text.

- [ ] **I686-19 — Low — CLEAN — A2 VM documentation describes a different execution path**
  - **Where**: `src/vm/vm32.c:14-21`; `src/i686rt.h:64-67`; `src/trampoline.S:47-48`.
  - **What breaks / Why**: The comments state that A2 places the Soft-TLB pointer in x20 and emits a seven-instruction lookup. The trampoline instead loads `guest_base` unconditionally. This misleads reviewers about where permission checking occurs and obscures the fault-based behavior implicated in I686-1.
  - **Fix**: Document the currently implemented register contract and memory path. Update those comments together with any future TLB integration.

- [ ] **I686-20 — Low — CLEAN — Pending-signal documentation contradicts its clearing behavior**
  - **Where**: `src/os/signals_i386.c:814-844` (`i686_deliver_pending`).
  - **What breaks / Why**: The leading comment says unblocked `SIG_DFL`/`SIG_IGN` bits survive polling, while the implementation clears them. This directly contradicts a significant signal-policy decision.
  - **Fix**: After implementing the correct default actions in I686-8, rewrite the comment to state the actual blocked, ignored, delivered, and default-action behavior.