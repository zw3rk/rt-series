# a32rt — Round 2 static audit

**HEAD:** `a5f53b418d84a2e7dfa4c141d7bf85b3bf741a98`  
**Remediation commit:** `Fix A32-1 through A32-18 audit defects and enforce separate compilation`

**Inventory:** 40,457 physical lines of `.c`, `.h`, and `.S` under `src/`, `include/`, and `tests/`, plus the Makefile and provisioning tools.

Seven batched shell inspection turns were used. No builds, tests, emulators, or source modifications were performed. Inspection covered remediation changes and selected interpreter, emitter, VM, backend, JIT/AOT, signal, syscall, loader, trampoline, test, and tooling paths. Some outputs were truncated: **this report does not claim exhaustive inspection or verification of every module.**

**Round-1 verification:** The source now contains cross-page and doubleword permission checks, context-local interpreter reservation fields, an early failed-`fstat` return, separate compilation, and split test files. However, the mapping and file-shrink fixes remain incomplete, and the interpreter fault-delivery change introduces a GDB regression. The findings below also identify defects outside the Round-1 scope.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 9 | 0 | 1 | 0 | 0 | 0 | 10 |
| Medium | 3 | 0 | 2 | 0 | 0 | 0 | 5 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **12** | **0** | **3** | **1** | **1** | **1** | **18** |

## 1. Bugs & Defects

### High

- [ ] **A32-R2-1 — High — BUG — Code-cache rollover reclaims blocks still executing**
  - **Where**: `src/vm/vm_jit_mem.c:108-149`, `src/vm/vm_jit_mem.c:198-214` (`a32_jit_reset_cache_locked`, `a32_jit_allocate_code_space_locked`); `src/dbt/dbt_jit_run.c:348-355` (`a32_jit_run`).
  - **What breaks / Why**: Allocation overflow resets the entire cache, changes its protection to RW on Linux, and immediately reuses its storage. Guest execution proceeds outside the JIT lock. Another thread can therefore be executing a block when its page loses execute permission or its instructions are overwritten. Publishing epoch zero cannot stop a block already executing, or protect a code pointer selected immediately before reset.
  - **Fix**: Retire cache generations and reclaim them only after every executing thread reaches a quiescent point. Alternatively, stop guest threads before reset. Protect the interval from selecting a block through completing its execution.

- [ ] **A32-R2-2 — High — BUG — Signed loads use write permission checks**
  - **Where**: `src/core/core_emit_mem.c:167-182`, `src/core/core_emit_mem.c:224-241` (`emit_guest_mem`, `a64_emit_guest_ldrsb_w`, `a64_emit_guest_ldrsh_w`).
  - **What breaks / Why**: `is_store` is inferred solely from opcode bit 22. The signed-load opcodes `0x38A04800` and `0x78A04800` have that bit clear, so LDRSB/LDRSH consult the write tag. Valid signed loads from read-only pages fault; pages represented as writable but unreadable pass the wrong permission check. The site-recording code uses the same classification.
  - **Fix**: Pass access direction explicitly, or decode the complete load/store opcode field. Verify signed byte and halfword loads against read-only, write-only, and inaccessible guest pages.

- [ ] **A32-R2-3 — High — BUG — Darwin shared-file mapping can overwrite adjacent guest mappings**
  - **Where**: `src/vm.c:570-607` (`vm_mmap2_locked`); `src/os/backend_darwin.c:116-142` (`a32_backend_map_file`).
  - **What breaks / Why**: The remediation replaces copied shared mappings with native `MAP_FIXED` file mappings. The allocator aligns a nonfixed shared-file mapping’s start to the host page size, but reserves/checks only its guest-rounded length. A 4 KiB mapping on a 16 KiB host occupies a complete host page and can replace neighboring 4 KiB guest mappings. Fixed guest addresses and file offsets are also accepted at 4 KiB alignment even when native mapping cannot represent them.
  - **Fix**: Validate the complete host-page footprint before native replacement. Implement a coherent subpage backing strategy, or explicitly reject layouts that cannot preserve neighboring mappings and file-offset semantics.

- [ ] **A32-R2-4 — High — BUG — Darwin anonymous sharing changes neighboring mappings and survives private replacement**
  - **Where**: `src/os/backend_darwin.c:69-95` (`a32_backend_map_anon`).
  - **What breaks / Why**: The replacement path applies `VM_INHERIT_SHARE` to the entire covering host-page range. A 4 KiB shared guest allocation can consequently make adjacent private guest pages shared across fork. Replacing the allocation with a private mapping only clears bytes; it never restores private inheritance. The `minherit` result is also ignored, allowing success without the requested sharing semantics.
  - **Fix**: Track backing and inheritance at host-page granularity. Preserve neighboring private mappings, restore private semantics on replacement, and propagate inheritance failures. Reject unsupported mixed-sharing layouts until they are implemented correctly.

- [ ] **A32-R2-5 — High — BUG — Thumb-2 memory interpreter decodes the wrong register and access width**
  - **Where**: `src/interp/interp_thumb.c:647-690` (`t32_step`).
  - **What breaks / Why**: These memory paths extract `Rt` from `hw2[11:8]` instead of `hw2[15:12]`, perform word accesses for byte-transfer encodings, and round effective addresses down to four-byte alignment. For example, an `F810` register-offset LDRB encoding enters the first path and executes an aligned word load into a register selected from offset/control bits. Successfully returning from this path silently corrupts state rather than invoking an unsupported-instruction fallback.
  - **Fix**: Decode each supported Thumb-2 memory format explicitly, including `Rt`, transfer width, register/immediate offset, and indexing controls. Preserve valid unaligned-access semantics; reject formats not yet implemented.

- [ ] **A32-R2-6 — High — BUG — Thumb VFP memory faults are reported as successful instructions**
  - **Where**: `src/interp/interp_thumb.c:595-605` (`t32_step`); `src/interp/interp_vfp.c:99-118`, `src/interp/interp_vfp.c:738-749` (`mem_r`, `mem_w`, `a32_interp_vfp_step`); `src/interp/interp.c:194-213` (`a32_interp_step`).
  - **What breaks / Why**: VFP memory helpers set `ctx->exit_reason = A32_EXIT_FAULT`, and the VFP dispatcher returns `true` to indicate that it recognized the instruction. The Thumb caller treats that boolean as successful execution, advances PC, and returns `A32_EXIT_NONE`. The next step clears `exit_reason`. A faulting Thumb VLDR/VSTR can therefore be skipped without delivering its fault.
  - **Fix**: Separate “recognized” from execution status, or propagate `ctx->exit_reason` before advancing PC. Preserve the faulting PC and IT state.

- [ ] **A32-R2-7 — High — BUG — Signal-frame construction bypasses guest write permissions**
  - **Where**: `src/signals.c:256-276` (`deliver_guest_signal`).
  - **What breaks / Why**: Frame construction checks only numeric address bounds, then directly clears and writes the frame. It never validates that the complete destination is mapped and writable. On A2, a guest-selected SP or alternate stack can overwrite guest read-only or inaccessible memory because the covering host page remains RW. On Linux, an invalid destination faults inside the translator’s signal-delivery path.
  - **Fix**: Validate the complete frame span through a signal-safe guest-memory mechanism before writing. Define controlled fatal-signal handling for an invalid signal stack without recursively faulting in the host handler.

- [ ] **A32-R2-8 — High — BUG — Moving shared anonymous mappings loses their backing identity**
  - **Where**: `src/vm.c:779-784`, `src/vm.c:848-870` (`a32_vm_mremap`).
  - **What breaks / Why**: Only shared file mappings receive a backing-preserving remap path. Shared anonymous mappings allocate a new anonymous mapping, copy bytes, and unmap the old range. After fork, another process still references the original shared object while the moving process references a new one. Shared-memory communication and shared futex identity break despite both mappings retaining `MAP_SHARED` flags.
  - **Fix**: Preserve the existing backing object when moving shared anonymous mappings. Use native remapping where suitable, or maintain an explicit shared backing handle and remap that same object.

- [ ] **A32-R2-9 — High — BUG — PR_SET_NAME retains the unchecked guest-string overread**
  - **Where**: `src/os/os_sys_fs_arm.c:423-434` (`ARM_NR_prctl`, `PR_SET_NAME`).
  - **What breaks / Why**: Only one byte is validated before `strnlen(src, 15)` and `memcpy` read the guest string. A nonterminated name at the end of a readable page crosses into unchecked memory. On Linux this can terminate the translator through the newly fatal outside-JIT fault path; on A2 it can read guest-inaccessible bytes.
  - **Fix**: Copy the bounded name through the checked guest-string helper and pass the resulting host buffer to `prctl`.

### Medium

- [ ] **A32-R2-10 — Medium — BUG — File-shrink invalidation does not establish durable EOF semantics**
  - **Where**: `src/vm/vm_file.c:294-334` (`vmfile_sync_size`); `src/vm/vm32.c:176-202`, `src/vm/vm32.c:205-227` (TLB invalidation/refill); `src/interp/interp.c:108-115` (`i_load_bytes`).
  - **What breaks / Why**: The remediation now translates file offsets into guest ranges, but only invalidates TLB tags. It leaves mapping permissions and staged bytes intact. Interpreter reads still pass region validation and access the stale anonymous storage; the C miss helper can refill from unchanged `g_prot`. Conversely, invalidating at least 512 pages clears **all** TLB tags, while emitted checks treat misses as guest faults, so unrelated valid DBT accesses can fault. Regrowth does not repopulate the discarded file tail.
  - **Fix**: Represent EOF validity independently of mapping permissions and enforce it consistently in interpreter and DBT accesses. Invalidate only affected translations, preserve unrelated full-coverage entries, and define backing refresh on regrowth.

- [ ] **A32-R2-11 — Medium — BUG — Interpreter exits after successful GDB fault recovery**
  - **Where**: `src/interp/interp.c:255-260` (`a32_interp_run`); `src/gdb.c:585-613`, `src/gdb.c:662` (`a32_gdb_handle_stop`).
  - **What breaks / Why**: The new fault branch returns `128 + SIGSEGV` when `a32_gdb_handle_stop` returns zero. Zero is its normal result after continue or step. Thus a debugger can repair state and request continuation, only for the interpreter to exit. The adjacent BKPT path uses the opposite success test.
  - **Fix**: Continue execution on zero and terminate on a failed debugger interaction. Apply the same return convention to the existing UNDEF branch.

- [ ] **A32-R2-12 — Medium — BUG — Interpreter floating-point operations ignore guest FPSCR control and exceptions**
  - **Where**: `src/interp/interp_vfp.c:201-204`, `src/interp/interp_vfp.c:489-519`, `src/interp/interp_vfp.c:525-559` (`vfp_mcr_mrc`, `vfp_cdp`).
  - **What breaks / Why**: VMSR updates only `ctx->fpscr`. Arithmetic and `nearbyint` use the host floating-point environment without applying the guest rounding mode, and arithmetic does not collect exception flags into guest FPSCR. For example, changing guest rounding before VCVTR does not control `nearbyint`, and floating-point division by zero does not update the guest cumulative divide-by-zero flag.
  - **Fix**: Implement explicit guest floating-point environment handling, including rounding and cumulative exceptions, with host state saved/restored. Ensure compiler floating-point settings preserve the required semantics.

## 2. Curated C11 & UB Issues

- [ ] **A32-R2-13 — High — C11 — Shared Soft-TLB state has unsynchronized readers and writers**
  - **Where**: `src/vm/vm32.c:21-26`, `src/vm/vm32.c:145-170`, `src/vm/vm32.c:186-224`, `src/vm/vm32.c:268-302` (`g_tlb`, `g_prot`, probe/fill/invalidation/sync).
  - **What breaks / Why**: Global tags, addends, and permission bytes are ordinary objects. Mapping changes write them while other guest threads can read them through C helpers or emitted loads. Writer-side VM locking does not synchronize those readers. C helper accesses can race, and generated accesses have no coherent publication protocol for a tag/addend pair or permission revocation.
  - **Fix**: Define a reader/writer protocol covering both C and generated code. Use appropriate atomic publication and access ordering, together with a mechanism that prevents guest execution from racing backing replacement or revocation.

- [ ] **A32-R2-14 — Medium — C11 — Thumb effective-address arithmetic still overflows signed integers**
  - **Where**: `src/interp/interp_thumb.c:651-656`, `src/interp/interp_thumb.c:669-677` (`t32_step`).
  - **What breaks / Why**: Effective addresses use `(int32_t)base + off`. A base near `INT32_MAX` plus a positive offset overflows signed `int32_t`; casting the result to `uint32_t` afterward does not repair the UB. Guest address arithmetic requires modulo-32-bit behavior.
  - **Fix**: Construct offsets as unsigned bit patterns and perform the addition in `uint32_t`, alongside correcting the memory decoder.

- [ ] **A32-R2-15 — Medium — C11 — Synchronous signal handler calls async-signal-unsafe stdio**
  - **Where**: `src/signals.c:460-463` (`host_sig_handler`).
  - **What breaks / Why**: The host signal handler calls `fprintf` before `_exit`. Stdio is not async-signal-safe and can access interrupted or concurrently locked libc state. The fatal path therefore cannot reliably guarantee termination.
  - **Fix**: Use a fixed diagnostic through an async-signal-safe operation, or defer formatting to normal execution after safely escaping the translated block.

## 3. DRY — Intra-Repo Duplication

- [ ] **A32-R2-16 — Low — DRY — Duplicate interpreter memory helpers have divergent reservation behavior**
  - **Where**: `src/interp/interp.c:108-137` (`i_load_bytes`, `i_store_bytes`); `src/interp/interp_vfp.c:99-118` (`mem_r`, `mem_w`).
  - **What breaks / Why**: Both implement guest range validation, fault recording, and copying. The integer store helper additionally invalidates exclusive reservations; the VFP helper does not. This is already semantic drift: a VFP store touching a reserved location can leave interpreter reservation bookkeeping valid.
  - **Fix**: Route VFP accesses through the existing internal interpreter memory helpers, preserving one implementation of permission checks, fault state, and reservation invalidation within a32rt.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **A32-R2-17 — Low — YAGNI — File generation counters are maintained but never consumed**
  - **Where**: `src/vm/vm_file.c:38-59`, `src/vm/vm_file.c:100-105`, `src/vm/vm_file.c:299-307` (`resize_seq`, inode `code_generation`, `g_code_generation`).
  - **What breaks / Why**: Repository searches found initialization and updates, but no consumer of the per-inode sequence or generation fields. Incrementing them does not invalidate compiled code or make staged mappings coherent, despite comments suggesting generation-based coordination.
  - **Fix**: Remove the unused counters, or connect them to a concrete invalidation protocol as part of fixing file-backed mapping coherence. Do not retain them as apparent correctness machinery.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **A32-R2-18 — Low — CLEAN — A2 protection documentation contradicts backend behavior**
  - **Where**: `src/vm/vm32.c:310-316` (`a32_vm32_protect` contract); `src/os/backend_darwin.c:153-165` (`a32_backend_protect`).
  - **What breaks / Why**: The VM comment promises faithful unioned permissions, including execute permission, and says sibling permissions are not widened. The Darwin backend explicitly ignores the requested protection on large-page hosts and makes the entire covering range RW. This obscures the fact that correctness depends entirely on software checks for guest permissions.
  - **Fix**: Document the actual host-backing policy and the software enforcement boundary. Keep claims about permission preservation aligned with the implemented mechanism.

**Verification limits:** These are source-supported findings, not reproduced failures. No runtime evidence establishes their frequency or confirms remediation. The seven-turn budget and truncated outputs leave additional ISA, syscall, AOT relocation, signal-state recovery, and test coverage unverified. All proposed consolidation is internal to a32rt; no cross-repository runtime library is proposed.