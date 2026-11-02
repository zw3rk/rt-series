# rvrt — Round 2 static audit

**HEAD:** `8e207fb01112b0a897132a1bcda69012aa4c5861`  
**Result:** Five findings, including a high-severity FP register corruption defect. Round-1 remediation is incomplete.

The source inventory contains **77,425 lines under `src/`, 103,306 under `test/`, and 12 under `include/`** in `.c`/`.h`/`.S` files. These are inventory totals, **not fully reviewed LOC**. Detailed inspection concentrated on the native DBT emitter, FP cache, code cache, backend APIs, and remediation structure. Interpreter, loader, signals, VM, tests, and Makefile received partial inspection or searches.

Seven shell inspection turns were used. No builds, tests, QEMU, or Docker were run; no repository files were changed. System Git/Python launchers unexpectedly invoked Xcode initialization and encountered sandbox failures. Those failures and truncated output materially reduced coverage. **This report does not establish completion of the requested all-module audit or comprehensive lock/signal-ordering verification.**

## Round-1 remediation verification

| Round-1 finding | Static assessment |
|---|---|
| RV-1: FP load miss | Pre-load/post-load cache snapshots now address the identified miss-path metadata mismatch. A separate FP destination-eviction defect remains below. |
| RV-2: pthread errors | Darwin preemption now returns the captured pthread error. Full spawn-path verification was incomplete. |
| RV-3: writable transitions | Cache publication checks `mprotect`; invalidation replaces or exhausts an unreclaimable mapping. Native DBT compilation checks write/seal results. Failure-injection behavior remains untested. |
| RV-4: stale TLB tags | Both tags are cleared before installing the replacement translation. |
| RV-5: offset overflow | The inspected Darwin implementation checks alignment and `INT64_MAX` before casting. Complete cross-backend verification was not achieved. |
| RV-6: banned parsing | The first-party search returned no `atoi`/`atol` calls. |
| RV-7: duplicated startup | A shared backend spawn module exists; complete ownership/error-path verification remains open. |
| RV-8: unused RAS | Calls were added, but the stack still does not influence dispatch: RV-R2-3. |
| RV-9: textual implementation includes | **Incomplete:** numerous prohibited `.c` includes remain: RV-R2-4. |
| RV-10: oversized files | First-party C/header/assembly inventory showed no file above 900 lines. Much of the split preserves the original large translation units through implementation headers: RV-R2-5. |

## Findings summary

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| Medium | 0 | 1 | 0 | 0 | 0 | 1 | 2 |
| Low | 0 | 0 | 0 | 0 | 1 | 1 | 2 |
| **Total** | **1** | **1** | **0** | **0** | **1** | **2** | **5** |

## 1. Bugs & Defects

### High

- [ ] **RV-R2-1 — High — BUG — Fused FP operations overwrite a dirty cache victim before spilling it**
  - **Where**: `src/dbt_emit_fp.c:847-855` (fused-operation lowering in `rv_dbt_fp_try_emit`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: Fused operations emit their result directly into `16 + (rd & 15)`. Only afterward does `emit_str_d` check whether that cache slot contains a dirty, different guest register and emit its spill. The physical register already contains the new result, so the spill saves that result under the old guest register’s identity. For example, with dirty `f0` cached in `v16`, `fmadd.d f16,f1,f2,f3` overwrites `v16`, then spills the new `f16` result into architectural `f0`. The subsequent slot rename cannot recover the original value. This is separate from the repaired load-miss branch.
  - **Fix**: Preserve a dirty destination-slot victim before emitting the arithmetic instruction. Alternatively, compute into an uncached temporary, spill the victim, then move the result into the destination slot. Cover all four fused operations with dirty `fN`/`f(N+16)` collisions, including destination/source overlap.

### Medium

- [ ] **RV-R2-2 — Medium — DEFECT — Darwin anonymous mapping silently ignores no-replace semantics**
  - **Where**: `src/os/backend_darwin.c:61-74` (`rt_host_map_anon`).
  - **What breaks / Why**: The function explicitly discards `noreplace`, while independently enabling `MAP_FIXED` whenever `fixed` is nonzero. A caller requesting fixed placement without replacement can therefore overwrite an existing host mapping. With `fixed` zero, the address remains merely a hint. Neither behavior implements the requested exclusion guarantee. This is a backend API defect; production guest reachability was not established.
  - **Fix**: Implement collision-safe placement with the required ownership synchronization, or explicitly reject unsupported no-replace requests before calling `mmap`. Never silently downgrade them to destructive fixed mapping. Add an occupied-address case that verifies the original mapping survives.

### Critical / Low

No additional confirmed findings at these severities within the completed inspection.

## 2. Curated C11 & UB Issues

No independently confirmed new C11/UB finding emerged from the inspected material.

The Makefile includes the required C11 warning flags. Searches found no first-party calls to the specified banned string/parsing functions. The `x18` hit in `test/fixtures/signal_context.S` is a **RISC-V guest register**, not evidence of AArch64 platform-register misuse. These observations do not establish complete C11 or generated-register compliance.

## 3. DRY — Intra-Repo Duplication

No additional duplication finding was established with sufficient context to recommend consolidation. No cross-repository shared library is proposed.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RV-R2-3 — Low — YAGNI — Return-address stack integration only maintains unused bookkeeping**
  - **Where**: `src/darwin_dbt.c:378-395` (`note_block_ras`, `check_indirect_ras`); `src/darwin_dbt_emit.c:313-328` (`emit_term_pc`).
  - **What breaks / Why**: The new hooks push return PCs and pop them on indirect exits. A mismatch only resets `ras_top`; the popped address never selects a block, supplies a dispatch target, or changes fallback behavior. Generated chaining still uses the fast indirect-branch cache. Thus the Round-1 unused-feature finding was addressed by adding activity around the stack without implementing a consumer. Moreover, treating every indirect exit as a return cannot faithfully maintain call/return history.
  - **Fix**: Remove the unused mechanism, or implement an explicit return-prediction consumer with architectural-target validation, proper RISC-V call/return classification, and coverage for generated chaining. Adding push/pop calls alone does not resolve the original issue.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RV-R2-4 — Medium — CLEAN — Prohibited textual implementation includes remain throughout tests**
  - **Where**: `test/test_exec_state.c:47` (production implementation inclusion); `test/test_space_alloc.c:48` (allocator-intercepted implementation inclusion).
  - **What breaks / Why**: These tests still textually include production `.c` files. Repository-wide searches also found the pattern in tests for native signals, MM operations, family state, descriptor handling, file backing, and loader transport. This directly violates the requested no-unity-includes rule and leaves tests coupled to implementation-private declarations and macro substitution. RV-9 therefore remains open despite selected tests being converted.
  - **Fix**: Compile production implementation files separately and expose narrow private test interfaces or explicit dependency-injection seams. Convert all remaining occurrences, then add a source check rejecting textual `.c` includes.

- [ ] **RV-R2-5 — Low — CLEAN — Header slicing meets file limits without decomposing large implementation units**
  - **Where**: `src/runtime_main.c:115-125` (eleven implementation-header inclusions); `src/runtime/family.c:34-38` (five implementation-header inclusions).
  - **What breaks / Why**: The remediation moves large sequences of implementation into headers that are textually assembled into the original translation units. Physical files now meet the ceiling, but the runtime orchestration and family implementations retain their broad shared scope, include-order dependencies, and weak internal ownership boundaries. This is a maintainability gap in RV-10’s requested decomposition, **not a remaining literal violation of the 900-line limit**.
  - **Fix**: Split coherent responsibilities into separately compiled private modules with small interfaces and explicit state ownership. Keep headers for declarations, types, and justified small inline helpers. Preserve the standalone repository boundary.

All findings above are static deductions. Runtime reproduction, remediation test coverage, complete syscall/VM semantics, concurrent cache lifecycle, and comprehensive signal/fork lock ordering remain unverified.