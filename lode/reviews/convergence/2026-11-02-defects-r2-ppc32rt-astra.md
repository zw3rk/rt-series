# ppc32rt — Round 2 static audit

**HEAD:** `abe6b0b70bc756eabc5956c9621444045ea3f400`  
**Commit:** `fix(ppc32rt): resolve audit defects P32-1 through P32-15`

**Result: nine findings; no Critical finding established.** Round-1 remediation remains incomplete in mapping lifetime, concurrent pointer validation, and reservation fault handling. Enabling OE-form arithmetic also exposes incorrect overflow calculations.

**Scope and limits:** The source inventory contains **23,892 physical lines** under `src/` and `include/`, and **29,647 including tests**, counting `.c`, `.h`, and `.S` files. Seven shell inspection calls were used. No builds, compilers, QEMU, Docker, or test scripts were intentionally run; no repository files were changed. Git’s macOS launcher emitted sandbox diagnostics, and large inspection outputs were truncated. Consequently, this is a bounded static audit—not exhaustive clearance of every module or the complete remediation diff. FP/SPE, AOT, signal restoration, and DBT cache concurrency remain incompletely reviewed.

**Round-1 verification:** Current source confirms the interpreter barrier, NEG carry preservation, checked atomic access, futex requeue argument correction, and common pthread wrapper’s direct error handling. File counts confirm the oversized-file pressure was reduced. Findings below explain why the mapping, pointer-validation, and reservation fixes cannot yet be considered complete. Other Round-1 fixes are not independently certified here.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 4 | 0 | 1 | 0 | 0 | 0 | 5 |
| Medium | 2 | 1 | 0 | 0 | 0 | 0 | 3 |
| Low | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| **Total** | **6** | **1** | **1** | **0** | **0** | **1** | **9** |

## 1. Bugs & Defects

### High

- [ ] **P32-R2-1 — High — BUG — Remapping relies on a borrowed file descriptor**
  - **Where**: `src/rt32/ppc32_vm_regions.c:75-103` (`vm_insert_region_raw_ex`); `src/rt32/ppc32_vm.c:671-688`, `src/rt32/ppc32_vm.c:710-718`, `src/rt32/ppc32_vm.c:752-759` (`ppc32_vm_mremap`)
  - **What breaks / Why**: The remediation stores the supplied descriptor number directly in the region and later uses that number to recreate or extend its backing. A mapping must survive closing its original descriptor. After close, remapping can fail with `EBADF`; after descriptor reuse, it can map an unrelated file. In the A1 shared-file relocation path, copying is deliberately skipped, so a reused descriptor can replace the original contents outright. Numeric descriptor equality also does not establish stable backing identity for region coalescing.
  - **Fix**: Retain an owned backing object with a private duplicated descriptor and explicit lifetime management across region splits, merges, and unmaps. Use backing identity rather than the guest descriptor number. Cover close-before-remap and descriptor-reuse cases.

- [ ] **P32-R2-2 — High — BUG — Futex pointer validation uses stale, unlocked region snapshots**
  - **Where**: `src/os/threads.c:58-83` (`thread_range_ok`, `thread_ld32be`); `src/os/threads.c:279-289` (`futex_get_timeout`); `src/rt32/ppc32_vm_regions.c:41-60` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`)
  - **What breaks / Why**: The new permission check reads `ctx->regions` without the VM lock. VM updates refresh the operating context and root context, not every existing child context. A child can therefore validate a timeout against stale mappings after another thread unmaps or protects that memory, then fault in the subsequent `memcpy`. Conversely, newly mapped valid memory can be rejected. Root-context readers can also race with another thread copying its region array. Even a fresh snapshot leaves a validation-to-copy race.
  - **Fix**: Validate against authoritative shared VM state and perform a fault-safe guest copy with a defined mapping-lifetime protocol. Do not use unlocked per-context snapshots as syscall memory authority.

- [ ] **P32-R2-3 — High — BUG — A fault during conditional store permanently strands the reservation lock**
  - **Where**: `src/interp/interp.c:60-84` (`vm32_sc_attempt`); `src/interp/interp.c:721-730` (`PPC32_OP_STWCX`); `src/os/hostfault.c:65-85`, `src/os/hostfault.c:106-137` (`hf_handler`, `ppc32_hostfault_run`)
  - **What breaks / Why**: STWCX validates the address before entering `vm32_sc_attempt`, which holds `g_ll_lock` across the host compare-exchange. Another thread can unmap or revoke access after validation; the reservation lock does not protect VM mappings. If the compare-exchange faults, the host handler `siglongjmp`s past the unlock. Subsequent LWARX/STWCX operations spin forever on the stranded global lock. Mapping-generation checks cannot close the interval between their comparison and the actual memory access.
  - **Fix**: Give checked atomic accesses a mapping-lifetime guard and a fault-recovery protocol that cannot abandon held locks. Establish a consistent VM/reservation lock order and ensure every exceptional exit releases acquired guards.

- [ ] **P32-R2-4 — High — BUG — Moving shared anonymous memory loses its original shared backing**
  - **Where**: `src/rt32/ppc32_vm.c:684-688`, `src/rt32/ppc32_vm.c:752-786` (`ppc32_vm_mremap`)
  - **What breaks / Why**: Anonymous mappings are moved by creating another anonymous mapping and copying bytes. For `MAP_SHARED | MAP_ANONYMOUS`, that creates a different shared object. After a fork, a parent that moves its mapping no longer shares subsequent writes with the child’s original mapping. Preserving `MAP_SHARED` in the flags does not preserve backing identity.
  - **Fix**: Move the existing backing with a supported host remap operation, or represent shared anonymous memory with an owned backing object that can be mapped again. Reject unsupported moves before mutation rather than silently breaking sharing.

### Medium

- [ ] **P32-R2-5 — Medium — BUG — Newly reachable overflow arithmetic computes incorrect XER flags**
  - **Where**: `src/interp/interp.c:214-232`, `src/interp/interp.c:239-270` (`interp_step`, ADD/SUBF families); `src/interp/interp.h:152-159` (`add_overflow`, `sub_overflow`)
  - **What breaks / Why**: The subtraction helper tests `((a ^ r) & (a ^ b))`, although its callers calculate `r = b - a`. Overflow must compare the result sign with the minuend `b`. For example, `a=0x80000000`, `b=0` produces an overflowing mathematical result but the helper clears OV. The addition path also folds carry into a truncated second operand: `addeo` with `a=0`, `b=0x7fffffff`, CA=1 produces `0x80000000` but reports no overflow. The decoder remediation makes these previously inaccessible OE paths executable.
  - **Fix**: Calculate the signed mathematical result in `int64_t`, including the original carry input and instruction-specific operands, then compare against `INT32_MIN..INT32_MAX`. Cover boundary cases with independent expected OV/SO values.

- [ ] **P32-R2-6 — Medium — BUG — Overflow-enabled division clears OV on division by zero**
  - **Where**: `src/interp/interp.c:325-348` (`interp_step`, DIVW/DIVWU)
  - **What breaks / Why**: The overflow predicate recognizes only signed `INT32_MIN / -1`. A zero divisor therefore clears OV for both `divwo` and `divwuo`; unsigned division always supplies false. Division by zero must set the overflow indication when OE is enabled, irrespective of the undefined quotient value.
  - **Fix**: Include a zero divisor in both signed and unsigned overflow predicates, retaining the signed minimum/-1 case. Check OV, sticky SO, and record-form CR0 propagation separately from quotient behavior.

- [ ] **P32-R2-7 — Medium — DEFECT — Remap commits success after ignoring protection and teardown failures**
  - **Where**: `src/rt32/ppc32_vm.c:778-795` (`ppc32_vm_mremap`)
  - **What breaks / Why**: Source-read permission changes, destination protection restoration, region recording, and source unmapping have discarded return values. A failed source permission change can lead directly to a host fault in `memcpy`. A failed destination protection change can leave the new mapping more permissive than requested while region metadata advertises the intended permissions. The function can subsequently return success despite failed bookkeeping or teardown.
  - **Fix**: Check each operation and make relocation transactional. Preserve enough original state to restore temporary source permissions and discard the destination on failure. Preflight region capacity and do not publish success until protections, metadata, and source removal agree.

### Critical / Low

No additional findings established at these severities.

## 2. Curated C11 & UB Issues

- [ ] **P32-R2-8 — High — C11 — Soft-TLB publication mixes atomic reads with ordinary concurrent writes**
  - **Where**: `src/vm/vm32_tlb.c:86-119` (`vm32_tlb_probe`); `src/vm/vm32_tlb.c:122-144` (`vm32_tlb_fill`); `src/vm/vm32_tlb.c:207-250` (invalidation)
  - **What breaks / Why**: Lock-free probes use atomic builtins to load tags, but writers assign the same tag fields normally under a lock that probes never acquire. The addend is also read and written ordinarily. Writer-only locking does not establish synchronization with readers; naturally aligned AArch64 loads do not remove C data-race UB. There is also no coherent tag/addend snapshot protocol.
  - **Fix**: Use synchronized access on both sides or a fully specified atomic publication protocol, including replacement and invalidation. If the addend is always the immutable Class-A guest base, remove it from mutable cache publication and document that invariant. Address mapping lifetime separately from metadata publication.

The textual scan found no calls to `sprintf`, `strcpy`, `strcat`, or `atoi`, and no textual `.c` includes. Literal `x18`/`w18` matches were comments. This does not certify dynamically encoded register operands or exclude every possible VLA.

## 3. DRY — Intra-Repo Duplication

No additional duplication finding established with sufficient evidence. Moving common pthread wrappers into `src/os/backend_common.c` addresses the previously identified duplication. No cross-repository library extraction is proposed.

## 4. YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding established with sufficient reference coverage. The remediation’s removal of signal scaffolding is reflected in the changed-file summary, but this inspection does not certify all remaining backend APIs as live.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P32-R2-9 — Low — CLEAN — Normal build flags omit the required general warnings-as-errors setting**
  - **Where**: `Makefile:25` (`CFLAGS`); `Makefile:72-78` (`build-darwin`)
  - **What breaks / Why**: Both normal build configurations include `-Werror=vla` but omit the project-required general `-Werror`. The separate syntax-check target supplies it, so normal builds and checks enforce different warning policies. Non-VLA diagnostics can therefore pass ordinary builds.
  - **Fix**: Add `-Werror` to both default build configurations. Keep any necessary platform-specific warning exceptions explicit and narrow.

All inventoried `.c`, `.h`, and `.S` files under `src/`, `include/`, and `tests/` are within 900 lines. The largest observed files are `src/os/threads.c` at 878 and `src/os/signals.c` at 861. These counts establish file-size compliance only; no runtime or compilation claims are made.