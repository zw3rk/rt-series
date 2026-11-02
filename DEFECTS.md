# `rt-series` Master Defect, Curated-C11, DRY, YAGNI & CLEAN Checklist (Round 2 + Round 1 Archive)

**Audit Date:** 2026-11-02 (Round 1 & Round 2)  
**Reviewer:** `gpt-6-astra` (`codex exec -m gpt-6-astra --sandbox read-only`) across 11 concurrent read-only static audit lanes  
**Scope:** All 10 `<arch>rt` binary translator repositories (Class A 32-bit 4 GiB-window & Class B 64-bit full-address-space) plus the `rt-series` coordination, benchmark, and qualification harness repository.  
**Architectural Invariants Enforced:**
1. **Standalone Zero-Dependency Repositories (`AGENTS.md` §2.1):** Each `<arch>rt` repository is standalone; **DRY findings are strictly intra-repository** (never extract a shared cross-repo `librt32` or `librt64` C library).
2. **Curated C11 (`AGENTS.md` §2.2):** `-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror`, no VLAs, no banned libc functions (`strcpy`, `strcat`, `sprintf`, `atoi`), `x18` permanently reserved on AArch64, no textual `#include "*.c"` unity includes, and every `.c`/`.h`/`.S` file $\le 900$ lines.

---

## 0. Executive Summary & Per-Repository Audit Matrix

### 0.1 Round 2 Audit Matrix (Active Open Checklist — `0 / 145` Resolved)

Round 2 audited both the Round-1 remediation commits (`git show HEAD`) for incomplete fixes or regressions and the broader codebase across all 11 repositories. While Round 1 addressed 187 initial items (archived in Part II below), Round 2 identified **145 open findings** (`0 Critical`, `66 High`, `52 Medium`, `27 Low`), including incomplete Round-1 remediations in sub-page permissions, `MAP_SHARED`/`mremap` fd lifetime, SMC/TLB concurrency, cooperative thread scheduling, and qualification harness checks.

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | **R2 Open** | Raw Round-2 `astra` Transcript |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `a5f53b4` | 10 | 5 | 3 | 12 | 0 | 3 | 1 | 1 | 1 | **0 / 18** | [`2026-11-02-defects-r2-a32rt-astra.md`](lode/reviews/2026-11-02-defects-r2-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `8db8727` | 9 | 7 | 2 | 13 | 0 | 2 | 1 | 0 | 2 | **0 / 18** | [`2026-11-02-defects-r2-i686rt-astra.md`](lode/reviews/2026-11-02-defects-r2-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `366ca9b` | 10 | 3 | 3 | 10 | 1 | 2 | 1 | 1 | 1 | **0 / 16** | [`2026-11-02-defects-r2-mips32rt-astra.md`](lode/reviews/2026-11-02-defects-r2-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `abe6b0b` | 5 | 3 | 1 | 6 | 1 | 1 | 0 | 0 | 1 | **0 / 9** | [`2026-11-02-defects-r2-ppc32rt-astra.md`](lode/reviews/2026-11-02-defects-r2-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `dad95da` | 10 | 4 | 3 | 12 | 0 | 2 | 1 | 1 | 1 | **0 / 17** | [`2026-11-02-defects-r2-sparc32rt-astra.md`](lode/reviews/2026-11-02-defects-r2-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `8e207fb` | 1 | 2 | 2 | 1 | 1 | 0 | 0 | 1 | 2 | **0 / 5** | [`2026-11-02-defects-r2-rvrt-astra.md`](lode/reviews/2026-11-02-defects-r2-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `026e87d` | 3 | 2 | 2 | 5 | 0 | 0 | 0 | 1 | 1 | **0 / 7** | [`2026-11-02-defects-r2-loongarch64rt-astra.md`](lode/reviews/2026-11-02-defects-r2-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `bd3e73f` | 8 | 3 | 4 | 9 | 2 | 1 | 1 | 1 | 1 | **0 / 15** | [`2026-11-02-defects-r2-ppc64rt-astra.md`](lode/reviews/2026-11-02-defects-r2-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `32d5c9e` | 5 | 3 | 2 | 6 | 1 | 1 | 1 | 0 | 1 | **0 / 10** | [`2026-11-02-defects-r2-mips64rt-astra.md`](lode/reviews/2026-11-02-defects-r2-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `3ead4f9` | 3 | 6 | 3 | 3 | 3 | 3 | 1 | 1 | 1 | **0 / 12** | [`2026-11-02-defects-r2-sparc64rt-astra.md`](lode/reviews/2026-11-02-defects-r2-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `6fc9fbc` | 2 | 14 | 2 | 5 | 9 | 1 | 1 | 1 | 1 | **0 / 18** | [`2026-11-02-defects-r2-rt-series-astra.md`](lode/reviews/2026-11-02-defects-r2-rt-series-astra.md) |
| | **Total (Round 2)** | | | **66** | **52** | **27** | **82** | **18** | **16** | **8** | **8** | **13** | **0 / 145** | |

### 0.2 Round 2 Cross-Cutting Defect Clusters (Wave Planning Index)

- [ ] **X-R2-1 — High — Darwin A2 Sub-Page Protection, Soft-TLB Synchronization & Signed-Load Tag Classification**
  - **Linked Items**: `A32-R2-2`, `A32-R2-3`, `A32-R2-4`, `A32-R2-13`, `I686-R2-1`, `I686-R2-2`, `I686-R2-3`, `M32-R2-8`, `P32-R2-8`, `S32-R2-13`, `LA64-R2-1`, `LA64-R2-3`
  - **Summary**: `a32rt` `LDRSB`/`LDRSH` checking write tags instead of read tags (`A32-R2-2`), `i686rt` pinned/widened host pages remaining open to sibling threads (`I686-R2-1`) and `smc_protect` widening `PROT_NONE` sub-pages to `PROT_READ` (`I686-R2-2`), `loongarch64rt` read misses restoring writable tags on code pages (`LA64-R2-1`) and `mprotect` committing guest metadata before host `mprotect` (`LA64-R2-3`), and unsynchronized C/JIT reads vs writes on Soft-TLB/permission tables (`A32-R2-13`, `P32-R2-8`, `S32-R2-13`).
- [ ] **X-R2-2 — High — `MAP_SHARED`, `mremap` Owned FD Lifetime, Region Coalescing & Split Rollback**
  - **Linked Items**: `A32-R2-3`, `A32-R2-4`, `A32-R2-8`, `A32-R2-10`, `I686-R2-6`, `I686-R2-7`, `M32-R2-2`, `M32-R2-3`, `M32-R2-4`, `M32-R2-5`, `M32-R2-6`, `P32-R2-1`, `P32-R2-4`, `P32-R2-7`, `S32-R2-5`, `S32-R2-6`, `RV-R2-2`, `LA64-R2-4`
  - **Summary**: `mremap` storing borrowed guest fd numbers that break after `close()` or fd reuse (`I686-R2-6`, `P32-R2-1`), moving `MAP_SHARED | MAP_ANONYMOUS` losing shared identity across `fork()` (`A32-R2-8`, `P32-R2-4`, `S32-R2-6`), `sparc32rt` coalescing adjacent file mappings without checking backing identity (`S32-R2-5`), and `mips32rt` `mprotect`/`munmap`/`mmap` mutating host mappings before reserving region-split capacity (`M32-R2-4..6`).
- [ ] **X-R2-3 — High — Code-Cache Rollover Quiescence, SMC Collision/Tracking & W^X Reopen Failures**
  - **Linked Items**: `A32-R2-1`, `I686-R2-4`, `I686-R2-5`, `S32-R2-1`, `S32-R2-2`, `M64-R2-3`, `S64-R2-3`
  - **Summary**: `a32rt` code-cache overflow resetting RX pages while other threads execute (`A32-R2-1`), `sparc32rt` `vpn & 4095` code-mask aliasing across 16 MiB boundaries (`S32-R2-1`) and partial-page invalidation clearing tracking for surviving blocks (`S32-R2-2`), `i686rt` stamping post-compile page generations without comparing pre-compile generations (`I686-R2-4`), `mips64rt` speculative delay-slot fetches faulting during compilation (`M64-R2-3`), and `sparc64rt` `dbt_flush_all` ignoring `a32h_wx_reopen` failure (`S64-R2-3`).
- [ ] **X-R2-4 — High — Atomic / LL-SC Reservation Coherence, Lock Fault Safety & TSO Completeness**
  - **Linked Items**: `I686-R2-8`, `P32-R2-3`, `LA64-R2-2`, `P64-R2-5`, `P64-R2-6`, `M64-R2-1`
  - **Summary**: `ppc32rt` `STWCX` faulting while holding `g_ll_lock` and `siglongjmp`ing past unlock (`P32-R2-3`), `mips64rt` scalar stores modifying memory before acquiring `sc_lock` (`M64-R2-1`), `ppc64rt` ignoring per-context reservation tokens (`P64-R2-5`) and bypassing SMC/shared-file write hooks on atomic stores (`P64-R2-6`), `loongarch64rt` page-wide writable refill bypassing active reservations (`LA64-R2-2`), and `i686rt` TSO mode omitting string/SSE/interpreter fences (`I686-R2-8`).
- [ ] **X-R2-5 — High — Signal Delivery, Frame Permission Checks, `sigsuspend` / `ppoll` Wakeup Races & Async-Signal-Safety**
  - **Linked Items**: `A32-R2-7`, `A32-R2-15`, `I686-R2-14`, `I686-R2-15`, `M32-R2-1`, `M32-R2-7`, `M32-R2-9`, `M32-R2-13`, `S32-R2-11`, `S32-R2-12`, `S32-R2-14`, `P64-R2-4`, `M64-R2-7`, `S64-R2-1`, `S64-R2-5`, `S64-R2-7`
  - **Summary**: `sparc64rt` `put_u64be` at `0x1d8` clobbering the saved `Y` register with `magic` at `0x1dc` (`S64-R2-1`) and locking `g_futex_mu` inside signal notification (`S64-R2-7`), `mips32rt` `sigreturn` advancing PC past an unexecuted `syscall` (`M32-R2-7`) and double-delivering FP delay-slot fetch faults (`M32-R2-1`), `sparc32rt` `sigsuspend` lost-wakeup window (`S32-R2-12`) and `%o0` overwrite (`S32-R2-11`), and unchecked signal-frame writes (`A32-R2-7`, `M32-R2-13`).
- [ ] **X-R2-6 — High — Cooperative/Threaded Execution, Quiescence Leases, `fork` State & `execve` Staging**
  - **Linked Items**: `A32-R2-9`, `I686-R2-13`, `M32-R2-10`, `M32-R2-12`, `P32-R2-2`, `S32-R2-3`, `S32-R2-4`, `LA64-R2-5`, `P64-R2-1`, `P64-R2-2`, `P64-R2-3`, `P64-R2-8`, `P64-R2-10`, `P64-R2-11`, `M64-R2-2`, `M64-R2-4`, `M64-R2-8`, `S64-R2-4`, `S64-R2-6`, `S64-R2-8`, `S64-R2-9`
  - **Summary**: `ppc64rt` cooperative thread scheduling, `exit`/`exit_group` scope, `futex` deadlines, and per-task `clear_child_tid` (`P64-R2-1..3, 8`), `mips64rt` blocking syscalls holding quiescence leases (`M64-R2-2`), `fork` inheriting stale worker registry/locks (`M64-R2-4`), and premature slot publication (`M64-R2-8`), plus `sparc32rt` `execve` closing validated fds before teardown (`S32-R2-4`).
- [ ] **X-R2-7 — High — ISA Decode, Delay-Slot, FP Rounding / Exception & DBT Lowering Bugs**
  - **Linked Items**: `A32-R2-5`, `A32-R2-6`, `A32-R2-11`, `A32-R2-12`, `A32-R2-14`, `I686-R2-9`, `I686-R2-10`, `I686-R2-11`, `I686-R2-12`, `P32-R2-5`, `P32-R2-6`, `S32-R2-7`, `S32-R2-8`, `S32-R2-9`, `S32-R2-10`, `RV-R2-1`, `P64-R2-7`, `P64-R2-9`, `M64-R2-5`, `M64-R2-6`, `S64-R2-2`
  - **Summary**: `rvrt` fused FP (`fmadd.d` etc.) overwriting dirty cache victims in `v16..v31` before spilling (`RV-R2-1`), `a32rt` Thumb-2 memory decode (`Rt` bitfield/width) and VFP fault swallowing (`A32-R2-5`, `A32-R2-6`), `i686rt` `REP` address-size count & 16-bit index preservation (`I686-R2-9`), `LODSB`/`LODSW` zero-extending `EAX` (`I686-R2-10`), and `MOVSS`/`MOVSD` memory loads preserving upper lanes (`I686-R2-11`), `ppc32rt` `OE=1` `subf`/`add` overflow (`P32-R2-5`) and divide-by-zero `OV` (`P32-R2-6`), `sparc32rt` `JMPL` delay-slot link order (`S32-R2-7`), and `sparc64rt` delay-slot syscall losing branch target (`S64-R2-2`).
- [ ] **X-R2-8 — Low — Intra-Repo DRY & YAGNI Cleanup (Round 2)**
  - **Linked Items**: `A32-R2-16`, `A32-R2-17`, `I686-R2-16`, `M32-R2-14`, `M32-R2-15`, `S32-R2-15`, `S32-R2-16`, `RV-R2-3`, `LA64-R2-6`, `P64-R2-13`, `P64-R2-14`, `M64-R2-9`, `S64-R2-10`, `S64-R2-11`, `RTS-R2-16`, `RTS-R2-17`
- [ ] **X-R2-9 — Medium — CLEAN Hygiene, `rvrt` `test/*.c` Unity Includes & `rt-series` Harness Qualification**
  - **Linked Items**: `A32-R2-18`, `I686-R2-17`, `I686-R2-18`, `M32-R2-11`, `M32-R2-16`, `P32-R2-9`, `S32-R2-17`, `RV-R2-4`, `RV-R2-5`, `LA64-R2-7`, `P64-R2-12`, `P64-R2-15`, `M64-R2-10`, `S64-R2-12`, `RTS-R2-1..RTS-R2-15`, `RTS-R2-18`

---
## 1. `a32rt` (`a5f53b4`) — 18 Round-2 Findings (`0 / 18` Resolved)

### 1.1 Bugs & Defects

#### High

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

#### Medium

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

### 1.2 Curated C11 & UB Issues

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

### 1.3 DRY — Intra-Repo Duplication

- [ ] **A32-R2-16 — Low — DRY — Duplicate interpreter memory helpers have divergent reservation behavior**
  - **Where**: `src/interp/interp.c:108-137` (`i_load_bytes`, `i_store_bytes`); `src/interp/interp_vfp.c:99-118` (`mem_r`, `mem_w`).
  - **What breaks / Why**: Both implement guest range validation, fault recording, and copying. The integer store helper additionally invalidates exclusive reservations; the VFP helper does not. This is already semantic drift: a VFP store touching a reserved location can leave interpreter reservation bookkeeping valid.
  - **Fix**: Route VFP accesses through the existing internal interpreter memory helpers, preserving one implementation of permission checks, fault state, and reservation invalidation within a32rt.

### 1.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **A32-R2-17 — Low — YAGNI — File generation counters are maintained but never consumed**
  - **Where**: `src/vm/vm_file.c:38-59`, `src/vm/vm_file.c:100-105`, `src/vm/vm_file.c:299-307` (`resize_seq`, inode `code_generation`, `g_code_generation`).
  - **What breaks / Why**: Repository searches found initialization and updates, but no consumer of the per-inode sequence or generation fields. Incrementing them does not invalidate compiled code or make staged mappings coherent, despite comments suggesting generation-based coordination.
  - **Fix**: Remove the unused counters, or connect them to a concrete invalidation protocol as part of fixing file-backed mapping coherence. Do not retain them as apparent correctness machinery.

### 1.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **A32-R2-18 — Low — CLEAN — A2 protection documentation contradicts backend behavior**
  - **Where**: `src/vm/vm32.c:310-316` (`a32_vm32_protect` contract); `src/os/backend_darwin.c:153-165` (`a32_backend_protect`).
  - **What breaks / Why**: The VM comment promises faithful unioned permissions, including execute permission, and says sibling permissions are not widened. The Darwin backend explicitly ignores the requested protection on large-page hosts and makes the entire covering range RW. This obscures the fact that correctness depends entirely on software checks for guest permissions.
  - **Fix**: Document the actual host-backing policy and the software enforcement boundary. Keep claims about permission preservation aligned with the implemented mechanism.

**Verification limits:** These are source-supported findings, not reproduced failures. No runtime evidence establishes their frequency or confirms remediation. The seven-turn budget and truncated outputs leave additional ISA, syscall, AOT relocation, signal-state recovery, and test coverage unverified. All proposed consolidation is internal to a32rt; no cross-repository runtime library is proposed.

---

## 2. `i686rt` (`8db8727`) — 18 Round-2 Findings (`0 / 18` Resolved)

### 2.1 Bugs & Defects

#### High

- [ ] **I686-R2-1 — High — BUG — Temporary and pinned permissions remain visible to other guest threads**
  - **Where**: `src/vm/vm32.c:144-173`, `src/vm/vm32.c:176-211` (`i686_vm32_widen_prot`, `i686_vm32_pin_page`); `src/os/sys_pass.c:260-308` (`sys_futex`).
  - **What breaks / Why**: Pinning applies the union of all sub-page permissions, releases the mutex, and retains that protection throughout a potentially blocking futex operation. `widen_prot` deliberately preserves union permissions for pinned pages. Another guest thread can consequently read a `PROT_NONE` neighbor or write a read-only neighbor without faulting. Temporary emulation/copy windows have the same problem: ordinary guest accesses do not acquire the sub-page mutex. Round-1 I686-1 therefore remains unresolved.
  - **Fix**: Enforce permissions on every guest access to mixed-permission host pages, or coordinate all guest execution while permissions are widened. Use a futex design that does not expose protected neighbors for the duration of a wait.

- [ ] **I686-R2-2 — High — BUG — SMC protection grants read access to inaccessible neighbors**
  - **Where**: `src/dbt/engine_smc.c:135-152` (`smc_protect`).
  - **What breaks / Why**: Compiling code unconditionally applies `PROT_READ` to its entire host page. On A2, that host page can contain unmapped or `PROT_NONE` 4 KiB neighbors. The operation overrides the restrictive intersection established by the remediation, making those neighbors readable. This bypass exists even with one guest thread.
  - **Fix**: Derive SMC protection from current guest permissions. Remove write permission from the effective restrictive cover without adding permissions to any sub-page.

- [ ] **I686-R2-3 — High — BUG — Decode and REP recovery can escape while holding the sub-page mutex**
  - **Where**: `src/os/signals_subpage.c:137-167` (`safe_decode_eip`); `src/os/signals_subpage.c:658-680`, `src/os/signals_subpage.c:744-770` (`emulate_rep_string`, `i686_spurious_emulate`); `src/x86/decode.c:76-80` (`fetch8`).
  - **What breaks / Why**: `safe_decode_eip` locks and widens memory before calling the raw decoder without an inner fault checkpoint. Its `max_len` restriction is checked only after decoding, so an instruction requiring an inaccessible following page can fault first. The REP branch likewise executes before the cleanup checkpoint used by the non-REP branch. A host fault can jump to the outer engine checkpoint, skipping protection restoration and mutex unlock. Subsequent recovery can deadlock on the same mutex.
  - **Fix**: Install cleanup checkpoints before every fault-capable operation under the mutex, including decoding and REP stepping. Decode from a bounded validated byte buffer, and restore every opened cover on all exits.

- [ ] **I686-R2-4 — High — BUG — Translation publication accepts a generation changed during compilation**
  - **Where**: `src/dbt/engine.c:355-359`, `src/dbt/engine.c:397-441` (`dbt_get_or_compile`); `src/dbt/engine_smc.c:184-189` (`smc_drop_host`).
  - **What breaks / Why**: Compilation reads guest bytes, then reloads the page generation and stamps the completed translation with that newer value. It never compares the pre-compilation and post-compilation generations. A concurrent writer can invalidate and modify the source during translation; stale or mixed decoded bytes are then published as current. Installing SMC protection only after publication leaves another interval for an undetected write.
  - **Fix**: Establish source write tracking before decoding, retain the starting generation, and publish only if all source-page generations remain unchanged under a protocol synchronized with writers. Otherwise discard and retry.

- [ ] **I686-R2-5 — High — BUG — Fault permission lookup trusts stale thread-local mappings**
  - **Where**: `src/interp/interp.c:211-239` (`i686_fault_region_prot`); `src/dbt/engine_smc.c:305-318` (`i686_dbt_smc_write_fault`); `src/rt32/rt32_vm_mmap.c:177-192` (`rt32_vm_mprotect`).
  - **What breaks / Why**: Region lookup refreshes a cloned thread’s snapshot only when the address is absent. A snapshot containing the address with obsolete permissions returns immediately. After another thread changes an existing mapping from RW to read-only, an SMC fault can therefore consult stale RW permissions. On A1, the subsequent SMC unprotection can restore write access using that same stale snapshot.
  - **Fix**: Version mapping snapshots and refresh them before permission decisions whenever the shared VM generation changes. SMC restoration must use authoritative current permissions.

- [ ] **I686-R2-6 — High — BUG — mremap backing identity is a reusable descriptor number**
  - **Where**: `src/vm/vm_file.c:292-304`, `src/vm/vm_file.c:340-363` (`i686_vm_file_track_map`, `i686_vm_file_lookup_map`); `src/rt32/rt32_vm_mmap.c:284-290`, `src/rt32/rt32_vm_mmap.c:315-327`, `src/rt32/rt32_vm_mmap.c:359-367` (`rt32_vm_mremap`); `src/os/sys_pass_fs.c:501-504` (`i686_pass_r_close`).
  - **What breaks / Why**: Mapping metadata stores the caller’s descriptor without retaining an independent reference. Closing the descriptor leaves the mapping valid but makes later remapping use a closed descriptor—or a descriptor reused for a different file. Growth can fail incorrectly; relocation of a shared mapping can silently select another backing object. This defeats Round-1 I686-7’s backing-preservation fix.
  - **Fix**: Retain an owned backing-object reference for each mapping, with explicit lifetime management across splits and unmaps. Never reconstruct mapping identity from a guest-reusable descriptor number.

- [ ] **I686-R2-8 — High — BUG — TSO repair omits string, SIMD, and interpreter fence paths**
  - **Where**: `src/dbt/emit_string.c:175-205` (`i686_emit_string`); `src/dbt/emit_sse.c:99-154` (`sse_emit_movx`); `src/interp/h_sse_int.c:633-638` (`h_sfence`).
  - **What breaks / Why**: Enabling `e->tso` repairs selected scalar emitters, but string and SIMD memory operations still emit ordinary loads/stores without corresponding ordering barriers. For example, successive STOS stores or SIMD stores remain reorderable on AArch64. Interpreter SFENCE still only advances EIP. Mixed DBT/interpreter execution therefore does not consistently provide x86 ordering after cloning.
  - **Fix**: Apply the ordering policy to every guest-memory lowering family and the interpreter fallback. Implement interpreter fence semantics and verify ordering across transitions between engines.

- [ ] **I686-R2-9 — High — BUG — REP count uses operand size and 16-bit indices lose upper halves**
  - **Where**: `src/interp/h_string.c:104-131` (`str_bump`, `rep_count_get`, `rep_count_dec`); `src/os/signals_subpage.c:337-340`, `src/os/signals_subpage.c:595-599`, `src/os/signals_subpage.c:658-676` (REP classification and emulation).
  - **What breaks / Why**: REP selects CX versus ECX using `pfx_opsize`; the selection must follow address size. Thus `66 F3 A5` incorrectly truncates the count, while `67 F3 A4` incorrectly uses full ECX. Separately, 16-bit SI/DI updates clear the upper halves of ESI/EDI. The newly added sub-page emulator repeats the count error.
  - **Fix**: Select count width using `pfx_addrsize`, preserve upper halves when updating CX/SI/DI, and share those semantics between normal interpretation and fault recovery.

#### Medium

- [ ] **I686-R2-7 — Medium — BUG — Partial unmapping discards backing metadata for the surviving suffix**
  - **Where**: `src/vm/vm_file.c:310-336` (`i686_vm_file_untrack_map`); `src/rt32/rt32_vm_mmap.c:287-290`, `src/rt32/rt32_vm_mmap.c:315-320` (`rt32_vm_mremap`).
  - **What breaks / Why**: When an unmapped interval lies strictly inside a tracked mapping, the final branch retains only the prefix. The still-mapped suffix loses its backing record. A later mremap of that suffix fails lookup and falls back to anonymous backing, losing file/shared semantics.
  - **Fix**: Split the record into prefix and suffix, adjusting the suffix file offset. Reserve metadata capacity before committing the VM change and propagate allocation/capacity failures.

- [ ] **I686-R2-10 — Medium — BUG — DBT LODSB and LODSW clear upper EAX bits**
  - **Where**: `src/dbt/emit_string.c:208-220` (`i686_emit_string`, LODS cases).
  - **What breaks / Why**: LODSB and LODSW load directly into the AArch64 register holding EAX. LDRB/LDRH zero-extend, whereas x86 updates only AL/AX. With EAX=`0x12345678` and a source byte of `0xAA`, LODSB produces `0x000000AA` instead of `0x123456AA`.
  - **Fix**: Load into a scratch register and merge the low 8 or 16 bits into EAX. Correct the accompanying comment claiming zero-extension matches x86 register writes.

- [ ] **I686-R2-11 — Medium — BUG — Scalar SSE memory loads preserve lanes that must be cleared**
  - **Where**: `src/dbt/emit_sse.c:95-114` (`sse_emit_movx`).
  - **What breaks / Why**: MOVSS/MOVSD loads use the same upper-preserving destination helpers for register and memory sources. Legacy MOVSS from memory must clear destination bits 127:32; MOVSD from memory must clear bits 127:64. The emitted memory-load paths retain the previous upper lanes.
  - **Fix**: Distinguish memory sources from register sources when committing the destination. Use zeroing destination writes for memory loads and preserving writes for register copies.

- [ ] **I686-R2-12 — Medium — BUG — DBT string comparisons leave PF and AF unchanged**
  - **Where**: `src/dbt/emit_string.c:132-153` (`l3s_store_flags`); `src/dbt/emit_string.c:223-233` (`CMPS` lowering).
  - **What breaks / Why**: The comparison helper explicitly updates only CF, ZF, SF, and OF, leaving PF and AF unchanged. CMPS and SCAS define both flags from subtraction. Subsequent parity branches, LAHF, PUSHF, or signal-state inspection can observe incorrect flags.
  - **Fix**: Compute all defined subtraction flags, preferably through an existing i686rt-local flag implementation. Keep the eager result and lazy-flag state consistent.

- [ ] **I686-R2-13 — Medium — BUG — Guest-copy wrappers discard recoverable EFAULT results**
  - **Where**: `src/os/marshal.c:98-131` (`s_copy_tolerant`); `src/os/marshal.c:161-194` (`i686_copy_from_guest`, `i686_copy_to_guest`).
  - **What breaks / Why**: The inner copy helper returns `-EFAULT` when it catches a fault without an outer checkpoint. Both public wrappers ignore that return and report success. Callers can consume incomplete or uninitialized destination data, or believe an unsuccessful guest write completed. This matters especially for thread setup/teardown paths outside an armed engine checkpoint.
  - **Fix**: Return `s_copy_tolerant`’s status directly and audit callers that ignore copy failures.

### 2.2 Curated C11 & UB Issues

- [ ] **I686-R2-14 — Medium — C11 — Cleanup reads an indeterminate array after longjmp**
  - **Where**: `src/os/marshal.c:93-137` (`s_copy_tolerant`, `opened`).
  - **What breaks / Why**: `opened` is a non-volatile automatic array modified after `sigsetjmp`. If a retried copy faults again, its contents are indeterminate after `siglongjmp`. Cleanup subsequently reads those contents to choose pages to re-protect. Marking `tries`, `locked`, and `healed` volatile does not preserve `opened`.
  - **Fix**: Store the cleanup journal in storage with a lifetime unaffected by setjmp/longjmp rules, such as a carefully scoped thread-local recovery record, or use appropriately volatile storage.

- [ ] **I686-R2-15 — High — C11 — Synchronous signal handling can acquire an interrupted VM lock**
  - **Where**: `src/interp/interp.c:124-135` (`host_fault_handler`); `src/dbt/engine_smc.c:305-307` (`i686_dbt_smc_write_fault`); `src/interp/interp.c:233-234` (`i686_fault_region_prot`); `src/rt32/rt32_vm.c:718-726` (`rt32_vm_sync_ctx`).
  - **What breaks / Why**: The signal handler calls SMC recovery, which can refresh a cloned context by acquiring the global VM spinlock. A fault while that same thread holds the VM lock—for example during a guest-memory operation inside a VM update—can spin forever because the interrupted owner cannot resume. Signal recovery is therefore not restricted to signal-safe, nonblocking state handling.
  - **Fix**: Keep synchronous handlers to bounded state capture and redirection. Perform VM synchronization and substantive invalidation at a recovery point with explicit lock ownership and cleanup, or use an immutable signal-readable mapping snapshot.

The targeted scans found no direct banned string/number-conversion calls or textual `.c` includes in the inspected C sources. Textual x18 matches were comments; that does not prove reservation across every numeric register encoding.

### 2.3 DRY — Intra-Repo Duplication

- [ ] **I686-R2-16 — Low — DRY — Recovery duplicates private decoder opcode numbers**
  - **Where**: `src/os/signals_subpage.c:40-53` (`SUBPAGE_OP7_*`); `src/x86/decode.c:70-73` (`I686_OP7_*`).
  - **What breaks / Why**: Recovery introduces a second manually maintained numeric opcode namespace, including the same 470–473 SSE assignments used by the decoder. A decoder change can silently make permission classification interpret an instruction as a different operation, width, or access direction.
  - **Fix**: Define these identifiers once in an i686rt-local decoder interface. Reuse them in recovery; do not introduce a cross-repository library.

### 2.4 YAGNI — Dead Code & Speculative Scaffolding

No additional YAGNI finding met the evidence threshold in this bounded pass. The remaining Soft-TLB descriptor and reserved context slot alone do not establish a defect: the context slot is explicitly documented as reserved.

### 2.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **I686-R2-17 — Medium — CLEAN — Test and fixture drivers lack required lifecycle bounds**
  - **Where**: `Makefile:300-303` (`test-u3`); `tools/build_fixture.sh:54-62` (fixture container).
  - **What breaks / Why**: The default test dependency executes its test binary without an explicit wall-clock deadline. The fixture builder launches Docker without a unique container identity, timeout, resource limits, or identity-based cleanup. A hung build or cancelled client can leave an uncontrolled container running; `--rm` does not stop it.
  - **Fix**: Add bounded execution to the test target. Give fixture containers task-owned identities, suitable CPU/memory limits, and cleanup traps that stop/remove and verify termination of only those containers.

- [ ] **I686-R2-18 — Low — CLEAN — Comments retain claims contradicted by current implementations**
  - **Where**: `src/dbt/emit_atomic.c:122-125` (`em_atomic_site` comment); `src/interp/h_muldiv.c:156-166` (`h_imul3` comment).
  - **What breaks / Why**: Atomic-site documentation still says `e->tso` is never set, although the remediation enables it after cloning. IMUL documentation says `dest = dest * rm * imm`, while the implementation correctly computes `rm * imm`. These comments obscure precisely the semantics under review.
  - **Fix**: Describe the current TSO-independent atomic-site offset and the two-factor IMUL operation.

The source-file size repair is confirmed for the counted scope: **no `.c`, `.h`, or `.S` file in `src/`, `include/`, or `tests/` exceeds 900 lines**.

---

## 3. `mips32rt` (`366ca9b`) — 16 Round-2 Findings (`0 / 16` Resolved)

### 3.1 Bugs & Defects

#### High

- [ ] **M32-R2-1 — High — BUG — FP delay-slot fetch failure can deliver the same fault twice**
  - **Where**: `src/interp/fp.c:818-829` (`fp_bc1`); `src/os/mem.c:204-228` (`mips_fault`); `src/os/signals.c:660-665` (`mips_raise_guest_code`)
  - **What breaks / Why**: The fetch-failure branch treats `exit_reason == MIPS32_EXIT_NONE` as a reason to raise another fault. Successful guest signal delivery deliberately clears that field. A delay-slot fetch fault already delivered to a handler therefore triggers another delivery, now from the handler context with delay-slot state cleared. This creates an extra frame, or terminates if `SA_RESETHAND` removed the handler.
  - **Fix**: Propagate the fetch failure without raising it again. Preserve the context installed by the memory fault path. Add a focused case with an inaccessible FP branch delay slot and a returning signal handler.

- [ ] **M32-R2-2 — High — BUG — Darwin sub-page shared mappings remain independent snapshots**
  - **Where**: `src/rt32/vm_mmap.c:132-157` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:147-175` (`vm_writeback_darw_locked`)
  - **What breaks / Why**: The unaligned Darwin path still populates existing arena memory with `pread`. Setting `darw_sync` adds eventual writeback, not shared backing. Two mappings of the same file do not observe each other’s stores, and changes through file I/O are not reflected in existing snapshots. Writing back the entire snapshot can overwrite newer file contents with stale bytes.
  - **Fix**: Implement coherent backing and alias coordination for sub-page shared mappings. Until supported, reject such mappings explicitly rather than advertise `MAP_SHARED` semantics.

- [ ] **M32-R2-3 — High — BUG — Darwin writeback occurs after the old mapping becomes inaccessible or is replaced**
  - **Where**: `src/rt32/vm_mmap.c:304-312` (`vm_munmap_locked`), `src/rt32/vm_mmap.c:144-155` and `194-199` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:178-185` (`vm_remove_region_at`)
  - **What breaks / Why**: Unmapping first applies `PROT_NONE`, then removes metadata and attempts writeback. A sub-page-backed mapping spanning complete host pages can consequently produce `EFAULT` during `pwrite`; that error is discarded. Fixed replacement similarly installs or populates new bytes before removing the old region, so old-backing writeback can write replacement contents into the old file.
  - **Fix**: Complete checked writeback while the original bytes remain accessible, before protection changes or replacement. Propagate failures and preserve consistent mapping state.

- [ ] **M32-R2-4 — High — BUG — mprotect capacity preflight disagrees with the mutation**
  - **Where**: `src/rt32/vm.c:353-368` (`vm_can_mprotect_regions_locked`), `src/rt32/vm.c:371-405` (`vm_mprotect_regions_locked`)
  - **What breaks / Why**: Preflight skips regions whose protection already equals the requested protection. The mutation does not skip them: it still splits partial overlaps and ignores insertion failures. With a full region table, a same-protection operation on the middle of a region passes preflight, truncates the original entry, and loses the unrecorded remainder.
  - **Fix**: Apply the same unchanged-protection condition in both passes. Check insertion results and guarantee all necessary entries before modifying any region.

- [ ] **M32-R2-5 — High — BUG — munmap reports success when its metadata split fails**
  - **Where**: `src/rt32/vm.c:276-302` (`vm_unmap_regions_locked`); `src/rt32/vm_mmap.c:304-316` (`vm_munmap_locked`)
  - **What breaks / Why**: Removing the middle of a region requires another entry. If insertion fails after coalescing, the original region remains recorded across the hole. The host mapping has already changed, and `munmap` returns success. On Darwin, a sub-page hole may remain host-accessible and be accepted by stale software permissions.
  - **Fix**: Reserve split capacity before changing host mappings. Make metadata removal return an error, and leave both host and guest mapping state unchanged when the split cannot be represented.

- [ ] **M32-R2-6 — High — BUG — mmap can return failure after replacing live memory**
  - **Where**: `src/rt32/vm_mmap.c:159-199` (`vm_mmap2_ext_locked`)
  - **What breaks / Why**: Host `MAP_FIXED` occurs before duplicating the backing descriptor and before ensuring region-table capacity. Descriptor exhaustion or metadata insertion failure returns an error after guest bytes or protections have already changed. The old metadata can remain associated with replacement memory.
  - **Fix**: Acquire backing descriptors and reserve metadata capacity before host mutation. Provide explicit rollback or a commit sequence that cannot fail after replacement.

- [ ] **M32-R2-7 — High — BUG — Pending delivery after sigreturn can skip an unexecuted syscall**
  - **Where**: `src/os/signals.c:295-305` (`mips_signal_deliver_pending`), `src/os/signals.c:734-751` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Pending delivery fetches the instruction at the current PC and advances past it whenever it equals `syscall`. That helper also runs after restoring a signal frame. If the restored PC points to a syscall that has not executed, delivering another pending signal saves `PC + 4`, permanently skipping that syscall.
  - **Fix**: Pass an explicit resume PC or delivery-boundary reason. Advance the PC only in the syscall completion path that knows the instruction has executed; never infer completion from instruction bytes.

- [ ] **M32-R2-8 — High — BUG — A2 private-file population writes through read-only mappings**
  - **Where**: `src/rt32/vm_mmap.c:117-128` and `180-190` (`vm_mmap2_ext_locked`); `src/vm/vm_file.c:65-78` (`mips32_file_populate_private`)
  - **What breaks / Why**: An aligned Darwin private file mapping is installed using its requested host protection, then populated again whenever the regime is A2. For `PROT_READ`, `pread` writes into read-only memory and fails with `EFAULT`. If EOF is encountered, the fallback `memset` can fault directly. Valid read-only mappings therefore fail after being installed.
  - **Fix**: Avoid repopulating an already established native file mapping. For copied backing, populate writable staging or arena memory before applying final protections, with rollback on failure.

#### Medium

- [ ] **M32-R2-9 — Medium — BUG — Real-time pending signals are coalesced**
  - **Where**: `src/os/signals.c:262-271` (`mips_signal_pend`), `src/os/signals.c:281-291` (`mips_signal_deliver_pending`)
  - **What breaks / Why**: Pending state stores one bit and one code per signal number. Repeated blocked real-time signals overwrite the same slot and produce one delivery. This violates the repository’s required FIFO handling of duplicate signals in the 32–128 namespace.
  - **Fix**: Add bounded per-thread real-time queues preserving each delivery and its information. Keep bit-based coalescing for standard signals.

- [ ] **M32-R2-10 — Medium — BUG — Syscall errno translation handles only ENOSYS**
  - **Where**: `src/os/syscalls.c:81-99` (`xerrno`, `mips_sc_ret`); `src/os/proc.c:72-87` (`proc_ret`)
  - **What breaks / Why**: Every host errno except `ENOSYS` passes through unchanged. MIPS has additional differences, including overflow and unsupported-operation errors; Darwin introduces further differences. Guests can receive an unrelated error number and choose the wrong recovery path.
  - **Fix**: Use one complete host-to-MIPS errno translation table, selected for the host platform, across all syscall return helpers.

- [ ] **M32-R2-11 — Medium — DEFECT — Interpreter header edits do not trigger incremental rebuilding**
  - **Where**: `Makefile:36-37` (`SRCS`, `HDRS`), `Makefile:66-68` (object rule)
  - **What breaks / Why**: Interpreter sources enter `SRCS`, but `src/interp/*.h` is absent from `HDRS`. The object rule does not generate compiler dependency files. Editing decoder or FP declarations can leave existing interpreter and DBT objects stale.
  - **Fix**: Generate and include compiler dependency files, or at minimum include interpreter headers in the declared dependencies.

### 3.2 Curated C11 & UB Issues

- [ ] **M32-R2-12 — High — C11 — Atomic generation counters do not protect root-context snapshots**
  - **Where**: `src/rt32/vm.c:110-131` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`), `src/rt32/vm.c:763-781` (`rt32_vm_sync_ctx`); `src/mips32rt.h:303-317` (`mips32_range_ok`)
  - **What breaks / Why**: A sibling VM operation directly writes the root context’s ordinary `regions`, `region_count`, and `vm_gen` fields. The root thread reads those fields without holding the VM lock. The atomic global generation neither makes those accesses atomic nor prevents concurrent modification during the region walk. This remains a C data race with potentially inconsistent permission decisions.
  - **Fix**: Stop writing another running thread’s snapshot. Refresh owner-thread snapshots under the VM lock, and protect every authoritative-region traversal with a consistent synchronization scheme.

- [ ] **M32-R2-13 — High — C11 — Signal guest-memory access still races with VM mutation**
  - **Where**: `src/os/signals.c:352-375` (`mips_sc_rt_sigaction`), `src/os/signals.c:605-627` (`mips_raise_guest_code`), `src/os/signals.c:719-740` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Signal paths check permissions, release any synchronization used by that check, then directly read or write guest pointers. A sibling can unmap or reprotect the range between validation and access. Frame construction uses raw `memset` and stores, so the translator can fault inside C rather than report a controlled guest-memory failure. The new lock-held copy helpers do not cover these paths.
  - **Fix**: Serialize frames and syscall structures into local buffers, then use the checked lock-held copy interfaces. Ensure complete range validation and copying occur under the same VM protection.

The targeted search found no direct banned string-function calls, `_Generic`, `<threads.h>`, or textual `.c` includes in the searched scope. This does not establish absence of every VLA, UB case, or encoded use of register 18.

### 3.3 DRY — Intra-Repo Duplication

- [ ] **M32-R2-14 — Low — DRY — Guest argument and return helpers remain duplicated**
  - **Where**: `src/os/proc.c:72-118` (`proc_ret`, `proc_arg`); `src/os/signals.c:196-232` (`l4a_arg`, `l4a_ret`); `src/os/syscalls.c:89-118` and `124-145` (`mips_sc_ret`, copy helpers, `mips_sc_arg`)
  - **What breaks / Why**: Three implementations encode the same O32 access and return conventions. They have already diverged: the shared argument helper uses locked copies and endian decoding, while the process helper uses a checked-then-raw native-endian `memcpy`.
  - **Fix**: Consolidate these helpers inside `mips32rt`, retaining module-specific behavior only where required. Do not introduce a cross-repository runtime library.

### 3.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **M32-R2-15 — Low — YAGNI — COW state constants describe an unused state machine**
  - **Where**: `src/vm/vm32.h:89-93` (`MIPS32_PAGE_COW_CLEAN`, `MIPS32_PAGE_COW_DIRTY`)
  - **What breaks / Why**: The searched source contains these COW constants only as definitions; other matching mentions are comments. The population helper copies bytes, and the TLB miss helper installs tags without implementing the advertised clean-to-dirty state transition.
  - **Fix**: Remove unused state constants and speculative contracts, or implement the required state tracking with explicit consumers. Keep the documented contract aligned with the actual backing strategy.

### 3.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M32-R2-16 — Low — CLEAN — File-backing comments claim nonexistent coherence machinery**
  - **Where**: `src/vm/vm_file.c:18-27`, `src/vm/vm_file.c:47-51`, and `src/vm/vm_file.c:95-101`
  - **What breaks / Why**: Comments claim family-shared backing, inode-keyed control state, resize generations, mutation hooks, and COW promotion. The implementation shown performs population and ordinary truncation without that machinery. These claims obscure the actual limitations identified above.
  - **Fix**: Replace the comments with the implemented behavior and explicit limitations. Track future coherence work in the existing backlog.

**File-size result:** No inventoried `.c`, `.h`, or `.S` exceeds 900 lines. `emit_int.c` is at 899 lines, `emit_fp.c` at 897, and interpreter `fp.c` at 893; these comply but leave little room for focused fixes.

---

## 4. `ppc32rt` (`abe6b0b`) — 9 Round-2 Findings (`0 / 9` Resolved)

### 4.1 Bugs & Defects

#### High

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

#### Medium

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

#### Critical / Low

No additional findings established at these severities.

### 4.2 Curated C11 & UB Issues

- [ ] **P32-R2-8 — High — C11 — Soft-TLB publication mixes atomic reads with ordinary concurrent writes**
  - **Where**: `src/vm/vm32_tlb.c:86-119` (`vm32_tlb_probe`); `src/vm/vm32_tlb.c:122-144` (`vm32_tlb_fill`); `src/vm/vm32_tlb.c:207-250` (invalidation)
  - **What breaks / Why**: Lock-free probes use atomic builtins to load tags, but writers assign the same tag fields normally under a lock that probes never acquire. The addend is also read and written ordinarily. Writer-only locking does not establish synchronization with readers; naturally aligned AArch64 loads do not remove C data-race UB. There is also no coherent tag/addend snapshot protocol.
  - **Fix**: Use synchronized access on both sides or a fully specified atomic publication protocol, including replacement and invalidation. If the addend is always the immutable Class-A guest base, remove it from mutable cache publication and document that invariant. Address mapping lifetime separately from metadata publication.

The textual scan found no calls to `sprintf`, `strcpy`, `strcat`, or `atoi`, and no textual `.c` includes. Literal `x18`/`w18` matches were comments. This does not certify dynamically encoded register operands or exclude every possible VLA.

### 4.3 DRY — Intra-Repo Duplication

No additional duplication finding established with sufficient evidence. Moving common pthread wrappers into `src/os/backend_common.c` addresses the previously identified duplication. No cross-repository library extraction is proposed.

### 4.4 YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding established with sufficient reference coverage. The remediation’s removal of signal scaffolding is reflected in the changed-file summary, but this inspection does not certify all remaining backend APIs as live.

### 4.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P32-R2-9 — Low — CLEAN — Normal build flags omit the required general warnings-as-errors setting**
  - **Where**: `Makefile:25` (`CFLAGS`); `Makefile:72-78` (`build-darwin`)
  - **What breaks / Why**: Both normal build configurations include `-Werror=vla` but omit the project-required general `-Werror`. The separate syntax-check target supplies it, so normal builds and checks enforce different warning policies. Non-VLA diagnostics can therefore pass ordinary builds.
  - **Fix**: Add `-Werror` to both default build configurations. Keep any necessary platform-specific warning exceptions explicit and narrow.

All inventoried `.c`, `.h`, and `.S` files under `src/`, `include/`, and `tests/` are within 900 lines. The largest observed files are `src/os/threads.c` at 878 and `src/os/signals.c` at 861. These counts establish file-size compliance only; no runtime or compilation claims are made.

---

## 5. `sparc32rt` (`dad95da`) — 17 Round-2 Findings (`0 / 17` Resolved)

### 5.1 Bugs & Defects

#### High

- [ ] **S32-R2-1 — High — BUG — SMC mask collisions suppress required invalidation**
  - **Where**: `src/vm/vm32.c:276-292`, `src/vm/vm32.c:296-337` (`vm32_note_code_page`, `vm32_clear_code_range`, `vm32_range_has_code`)
  - **What breaks / Why**: The code-line mask indexes guest pages with `vpn & 4095`. Pages separated by 16 MiB share one mask. Clearing one page zeroes the shared mask even when another colliding page retains live translations and `RT_PAGE_HAS_CODE`. A subsequent short write to that other page returns false from `vm32_range_has_code`, leaving stale instructions cached. This is a new Round-1 remediation defect.
  - **Fix**: Use per-guest-page masks, or maintain collision-safe ownership/reference information. Clearing one page must never remove another page’s tracking bits.

- [ ] **S32-R2-2 — High — BUG — Partial-range invalidation clears tracking for surviving blocks**
  - **Where**: `src/dbt/dbt_cache.c:297-317` (`sparc32_dbt_invalidate_range`)
  - **What breaks / Why**: Blocks are retired using the exact byte range, but any range at least 4096 bytes long clears code tracking on every rounded boundary page. For example, a copyout covering `[P+128, P+4224)` leaves a block at `P+32` valid while clearing its page’s code marker and enabling fast writes. Later modifications to that block bypass SMC invalidation.
  - **Fix**: Retire all blocks on every page whose code tracking is cleared, or preserve/recompute tracking for surviving blocks. Distinguish mapping invalidation from arbitrary byte writes.

- [ ] **S32-R2-3 — High — BUG — Checked syscall copies still race with guest unmapping**
  - **Where**: `src/os/l2a_access.h:52-85`, `src/os/l2a_access.h:93-105` (`l2a_range_ok_prot`, `l2a_store`); `src/interp/interp_mem.c:76-111` (`interp_mem_rd`, `interp_mem_wr`)
  - **What breaks / Why**: Permission validation and host-memory access remain separate operations without mapping lifetime protection. Another `CLONE_VM` thread can unmap or revoke access after validation and before `memcpy`, causing a translator fault. On a large host page, the access can instead succeed against a guest subpage whose permission was revoked. Atomic permission loads do not close this gap. Round-1 S32-1 remains incomplete.
  - **Fix**: Introduce a coherent access/mapping synchronization contract: pin or lock mappings across short copies, and use suitable fault-safe or pinned handling for blocking operations.

- [ ] **S32-R2-4 — High — BUG — Exec prevalidation still permits failure after destroying the old image**
  - **Where**: `src/os/threads_exec.c:158-179` (`sparc32_thr_execve`); `src/rt32/elf32.c:624-639`, `src/rt32/elf32.c:656-697` (`rt32_elf_validate`, `rt32_elf_load`)
  - **What breaks / Why**: Validation closes the executable and interpreter descriptors. Exec then resets dispositions and destroys the old VM before reopening and loading those paths. File replacement/removal, mapping failure, interpreter failure, or stack allocation failure can therefore return an error to a destroyed process image. Prevalidation reduces failures but does not make replacement transactional.
  - **Fix**: Retain validated descriptors and stage the complete image and stack before committing. After an unavoidable point of no return, terminate through an explicit exec-failure path rather than returning to the former program.

- [ ] **S32-R2-5 — High — BUG — Region coalescing merges mappings of different files**
  - **Where**: `src/rt32/vm.c:219-240` (`vm_coalesce_regions_locked`); `src/rt32/vm_mmap.c:189-193` (`vm_mmap2_locked`)
  - **What breaks / Why**: `same_backing` checks only that both descriptors exist and their page offsets are consecutive. It never compares backing identity. File mappings also receive the same `"[mmap]"` name. Adjacent mappings of different files with matching protections and consecutive offsets can therefore merge; the second descriptor is closed and its identity lost. Subsequent remapping uses the first file for the combined region.
  - **Fix**: Track an explicit backing-object identity and coalesce only matching objects with contiguous offsets and compatible sharing semantics.

- [ ] **S32-R2-6 — High — BUG — Remap reconstruction loses shared-anonymous identity and private COW history**
  - **Where**: `src/rt32/vm_mmap.c:469-510` (`rt32_vm_mremap`)
  - **What breaks / Why**: Relocation creates a new mapping and copies anonymous data. For `MAP_SHARED | MAP_ANONYMOUS`, this creates a different shared object, breaking sharing with a forked process retaining the original mapping. For private file mappings, copying only pages whose bytes differ from a fresh mapping also loses COW history: a previously dirtied page that currently equals the file becomes file-backed again and may observe later file changes.
  - **Fix**: Preserve the original backing object and private-page state during relocation. Use a suitable host remap or explicit backing/page ownership; reject unsupported cases instead of approximating identity with byte comparison.

- [ ] **S32-R2-7 — High — BUG — JMPL delay slots observe the old link register**
  - **Where**: `src/interp/interp.c:586-592`, `src/interp/interp.c:626-630` (`interp_cti`); `src/dbt/emit_cti.c:316-332` (`sparc32_emit_jmpl`)
  - **What breaks / Why**: Both engines defer the JMPL destination-register write until after the delay instruction. JMPL writes its link before that instruction executes. A delay slot reading the destination, such as `%o7`, therefore sees the old value. A delay-slot write to that register is also overwritten by the delayed link commit. Agreement between these two implementations cannot establish correctness.
  - **Fix**: Compute and validate the target, commit the link, then execute the delay slot. Preserve the resulting architectural state on a delay-slot fault.

- [ ] **S32-R2-12 — High — BUG — Sigsuspend has a lost-wakeup window**
  - **Where**: `src/os/threads_sig.c:72-107` (`sparc32_thr_rt_sigsuspend`)
  - **What breaks / Why**: The function scans software pending bits and then calls host `sigsuspend` without first blocking the relevant host signals. A signal arriving between the last scan and the syscall can run the host handler and set a pending bit, after which `sigsuspend` sleeps waiting for another signal. A single expected notification can hang the guest indefinitely.
  - **Fix**: Block host delivery before inspecting pending state, then atomically release that block while sleeping. Restore the prior host mask and keep guest-mask selection consistent.

#### Medium

- [ ] **S32-R2-8 — Medium — BUG — NaN propagation can return a finite operand**
  - **Where**: `src/interp/fp_arith.c:136-153`, `src/interp/fp_arith.c:335-362` (`fp_f32_pick_nan`, `fp_f64_pick_nan`, `fp_f32_nan2`, `fp_f64_nan2`)
  - **What breaks / Why**: The payload-selection helper assumes both operands are NaNs, but callers invoke it when either operand is NaN. A finite operand with larger fraction bits wins. For example, single-precision inputs `0x7fc00000` and `0x3fffffff` select the finite second operand.
  - **Fix**: Return the sole NaN when exactly one operand is NaN. Apply payload arbitration only when both operands are NaNs, preserving signaling-NaN handling.

- [ ] **S32-R2-9 — Medium — BUG — Nondefault FP rounding falls back to an interpreter that ignores it**
  - **Where**: `src/dbt/emit_fp.c:48-78` (`fp_guard_fast`); `src/interp/fp_arith.c:400-444` (`fp_add_f32`, `fp_add_f64`)
  - **What breaks / Why**: The DBT rejects nonzero `FSR.RD` and replays in the interpreter. Arithmetic helpers nevertheless use ordinary host arithmetic without applying guest rounding. With round-toward-positive-infinity, single-precision `1.0 + 2^-24` should produce the next representable value; default round-to-nearest produces `1.0`.
  - **Fix**: Implement guest rounding for arithmetic and square root, including exception flags. Ensure the fallback actually implements the modes rejected by the fast path.

- [ ] **S32-R2-10 — Medium — BUG — Batched FPSR flags corrupt current-exception state**
  - **Where**: `src/dbt/emit_fp.c:320-338`, `src/dbt/emit_fp.c:385-393`, `src/dbt/emit_fp.c:447-453` (`fp_flags_commit`, `sparc32_emit_fp_flush`, `fp_emit_arith`)
  - **What breaks / Why**: Consecutive arithmetic instructions share cumulative host FPSR flags. The final commit writes that union to both accrued exceptions and current exceptions. After an inexact operation followed by an exact operation, guest `cexc` incorrectly retains inexact; only `aexc` should retain it.
  - **Fix**: Track each instruction’s current exceptions separately from accumulated exceptions. Any batching must preserve the last instruction’s `cexc`.

- [ ] **S32-R2-11 — Medium — BUG — Sigsuspend overwrites the handler’s signal-number argument**
  - **Where**: `src/interp/interp_signal.c:491-503` (`interp_deliver_async_for_syscall`); `src/os/threads_sig.c:93-105` (`sparc32_thr_rt_sigsuspend`); `src/os/syscalls_min.c:781-789` (syscall return commit)
  - **What breaks / Why**: Delivery sets `%o0` to the signal number and redirects execution to the handler. Returning `-EINTR` then runs the ordinary syscall tail, which overwrites `%o0` with errno 4 before the handler starts. The handler receives the wrong signal number.
  - **Fix**: Store the interrupted syscall’s `EINTR` result in the saved frame and bypass ordinary return-register commit when delivery has redirected execution.

### 5.2 Curated C11 & UB Issues

- [ ] **S32-R2-13 — High — C11 — Permission and code-state tables have unsynchronized accesses**
  - **Where**: `src/vm/vm32.c:74-82`, `src/vm/vm32.c:208-216`, `src/vm/vm32.c:290-313`; `src/interp/interp_mem.c:36-41`; `src/os/l2a_access.h:75-77`
  - **What breaks / Why**: VM updates and DBT code marking write ordinary bytes under different locks, while interpreter accesses read them without either lock. Some readers use atomic builtins, but writers remain non-atomic. Concurrent accesses are data races, and read-modify-write updates can lose permission or code-state changes.
  - **Fix**: Define one synchronization discipline for table publication and code-state updates. Use matching atomic operations where lock-free access is required, while separately protecting mapping lifetimes.

- [ ] **S32-R2-14 — High — C11 — Signal handlers race on live-context and pending-signal state**
  - **Where**: `src/os/threads.c:97-129` (`sparc32_thr_note_signal`, `thr_host_handler`); `src/interp/interp_signal.c:414-415`, `src/interp/interp_signal.c:518-538`
  - **What breaks / Why**: The host handler traverses the live-context table and performs plain read-modify-write operations on pending masks. Guest workers concurrently inspect and clear those masks. These operations lack a signal-safe atomic ownership protocol, allowing lost signals and cross-thread data races; live-context lifetime also needs protection during handler traversal.
  - **Fix**: Use lock-free atomic pending operations and a signal-safe context-lifetime design. Prefer recording delivery for the appropriate recipient and handling process-directed routing at safe points.

### 5.3 DRY — Intra-Repo Duplication

- [ ] **S32-R2-15 — Low — DRY — Exec validation duplicates loader policy**
  - **Where**: `src/rt32/elf32.c:513-612`, `src/rt32/elf32.c:615-644`, `src/rt32/elf32.c:679-694` (`validate_elf32_fd`, `rt32_elf_validate`, `rt32_elf_load`)
  - **What breaks / Why**: The new prevalidation pass independently parses and validates an image that the loader subsequently processes again. Policy already differs: interpreter validation uses a fixed `0x3f000000` base, while loading can choose a higher base based on the executable’s break. The duplicated decisions undermine prevalidation’s guarantee.
  - **Fix**: Parse and validate once into a repository-local load plan containing retained descriptors, segment ranges, and chosen load biases. Consume that plan during staging and commit.

### 5.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S32-R2-16 — Low — YAGNI — Removed TLB subsystem leaves a public no-op lifecycle hook**
  - **Where**: `src/vm/vm32.c:251-257` (`vm32_tlb_invalidate`); `src/rt32/vm.c:332-337` (`vm_record_region_ext_locked`)
  - **What breaks / Why**: Round-1 removed the disconnected TLB implementation but retained its public invalidation function and lifecycle calls. The function does nothing, while its name implies a coherence operation that callers may mistakenly rely on.
  - **Fix**: Remove the obsolete hook, declaration, and calls. Document the actual protection-table publication contract at the functions that implement it.

### 5.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S32-R2-17 — Low — CLEAN — Store-path comment contradicts the SMC remediation**
  - **Where**: `src/dbt/emit_fast.c:130-154`
  - **What breaks / Why**: The comment says stores to code-bearing pages run “without cache invalidation” and retain approximate semantics. The new helper path invalidates translations and introduces an early block exit. This obsolete explanation can lead future maintainers to preserve or reintroduce incorrect behavior.
  - **Fix**: Describe the current write notification, translation retirement, and block-exit behavior, including delay-slot constraints.

The source inventory stays within the 900-line ceiling; `src/os/syscalls.c` is largest at 865 lines. Targeted searches found no banned string-conversion calls or textual `.c` includes in the inspected production scope. Those searches do not establish absence of all VLAs, UB, or encoded-register violations. All proposed consolidation remains inside `sparc32rt`; no cross-repository library extraction is recommended.

---

## 6. `rvrt` (`8e207fb`) — 5 Round-2 Findings (`0 / 5` Resolved)

### 6.1 Bugs & Defects

#### High

- [ ] **RV-R2-1 — High — BUG — Fused FP operations overwrite a dirty cache victim before spilling it**
  - **Where**: `src/dbt_emit_fp.c:847-855` (fused-operation lowering in `rv_dbt_fp_try_emit`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: Fused operations emit their result directly into `16 + (rd & 15)`. Only afterward does `emit_str_d` check whether that cache slot contains a dirty, different guest register and emit its spill. The physical register already contains the new result, so the spill saves that result under the old guest register’s identity. For example, with dirty `f0` cached in `v16`, `fmadd.d f16,f1,f2,f3` overwrites `v16`, then spills the new `f16` result into architectural `f0`. The subsequent slot rename cannot recover the original value. This is separate from the repaired load-miss branch.
  - **Fix**: Preserve a dirty destination-slot victim before emitting the arithmetic instruction. Alternatively, compute into an uncached temporary, spill the victim, then move the result into the destination slot. Cover all four fused operations with dirty `fN`/`f(N+16)` collisions, including destination/source overlap.

#### Medium

- [ ] **RV-R2-2 — Medium — DEFECT — Darwin anonymous mapping silently ignores no-replace semantics**
  - **Where**: `src/os/backend_darwin.c:61-74` (`rt_host_map_anon`).
  - **What breaks / Why**: The function explicitly discards `noreplace`, while independently enabling `MAP_FIXED` whenever `fixed` is nonzero. A caller requesting fixed placement without replacement can therefore overwrite an existing host mapping. With `fixed` zero, the address remains merely a hint. Neither behavior implements the requested exclusion guarantee. This is a backend API defect; production guest reachability was not established.
  - **Fix**: Implement collision-safe placement with the required ownership synchronization, or explicitly reject unsupported no-replace requests before calling `mmap`. Never silently downgrade them to destructive fixed mapping. Add an occupied-address case that verifies the original mapping survives.

#### Critical / Low

No additional confirmed findings at these severities within the completed inspection.

### 6.2 Curated C11 & UB Issues

No independently confirmed new C11/UB finding emerged from the inspected material.

The Makefile includes the required C11 warning flags. Searches found no first-party calls to the specified banned string/parsing functions. The `x18` hit in `test/fixtures/signal_context.S` is a **RISC-V guest register**, not evidence of AArch64 platform-register misuse. These observations do not establish complete C11 or generated-register compliance.

### 6.3 DRY — Intra-Repo Duplication

No additional duplication finding was established with sufficient context to recommend consolidation. No cross-repository shared library is proposed.

### 6.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RV-R2-3 — Low — YAGNI — Return-address stack integration only maintains unused bookkeeping**
  - **Where**: `src/darwin_dbt.c:378-395` (`note_block_ras`, `check_indirect_ras`); `src/darwin_dbt_emit.c:313-328` (`emit_term_pc`).
  - **What breaks / Why**: The new hooks push return PCs and pop them on indirect exits. A mismatch only resets `ras_top`; the popped address never selects a block, supplies a dispatch target, or changes fallback behavior. Generated chaining still uses the fast indirect-branch cache. Thus the Round-1 unused-feature finding was addressed by adding activity around the stack without implementing a consumer. Moreover, treating every indirect exit as a return cannot faithfully maintain call/return history.
  - **Fix**: Remove the unused mechanism, or implement an explicit return-prediction consumer with architectural-target validation, proper RISC-V call/return classification, and coverage for generated chaining. Adding push/pop calls alone does not resolve the original issue.

### 6.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RV-R2-4 — Medium — CLEAN — Prohibited textual implementation includes remain throughout tests**
  - **Where**: `test/test_exec_state.c:47` (production implementation inclusion); `test/test_space_alloc.c:48` (allocator-intercepted implementation inclusion).
  - **What breaks / Why**: These tests still textually include production `.c` files. Repository-wide searches also found the pattern in tests for native signals, MM operations, family state, descriptor handling, file backing, and loader transport. This directly violates the requested no-unity-includes rule and leaves tests coupled to implementation-private declarations and macro substitution. RV-9 therefore remains open despite selected tests being converted.
  - **Fix**: Compile production implementation files separately and expose narrow private test interfaces or explicit dependency-injection seams. Convert all remaining occurrences, then add a source check rejecting textual `.c` includes.

- [ ] **RV-R2-5 — Low — CLEAN — Header slicing meets file limits without decomposing large implementation units**
  - **Where**: `src/runtime_main.c:115-125` (eleven implementation-header inclusions); `src/runtime/family.c:34-38` (five implementation-header inclusions).
  - **What breaks / Why**: The remediation moves large sequences of implementation into headers that are textually assembled into the original translation units. Physical files now meet the ceiling, but the runtime orchestration and family implementations retain their broad shared scope, include-order dependencies, and weak internal ownership boundaries. This is a maintainability gap in RV-10’s requested decomposition, **not a remaining literal violation of the 900-line limit**.
  - **Fix**: Split coherent responsibilities into separately compiled private modules with small interfaces and explicit state ownership. Keep headers for declarations, types, and justified small inline helpers. Preserve the standalone repository boundary.

All findings above are static deductions. Runtime reproduction, remediation test coverage, complete syscall/VM semantics, concurrent cache lifecycle, and comprehensive signal/fork lock ordering remain unverified.

---

## 7. `loongarch64rt` (`026e87d`) — 7 Round-2 Findings (`0 / 7` Resolved)

### 7.1 Bugs & Defects

#### High

- [ ] **LA64-R2-1 — High — BUG — Read misses restore writable tags on translated code pages**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/dbt/dbt.c:487-502` (`translate_block`); `src/dbt/dbt_smc.c:136-143` (`dbt_smc_store`).
  - **What breaks / Why**: Translation revokes writable tags for code pages, but a subsequent **read** miss computes `writable` solely from guest mapping permissions and publishes that page’s `write_tag`. The code-page check runs only when servicing a store miss. Consequently, loading from an RWX code page can re-enable direct stores that bypass `dbt_smc_store`. Those stores do not bump the SMC epoch, allowing cached instructions to remain stale.
  - **Fix**: Apply the code-page write gate whenever publishing a writable tag, regardless of which access caused the fill. Keep code pages readable but never directly writable through this path. Cover translate → read miss → modify instructions → execute again.

- [ ] **LA64-R2-2 — High — BUG — Reservation protection checks an access while granting permission to an entire page**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/interp/interp_amo.c:194-225` (`interp_step_amo`); `src/dbt/dbt_smc.c:151-163` (`dbt_revoke_write`).
  - **What breaks / Why**: LL revokes the page’s writable tag. The refill path refuses a store only if that particular access overlaps the current context’s reserved eight-byte range. A store elsewhere on the same page can refill the **whole page** as writable; a read miss can do so without checking the reservation at all. A later native store to the reserved address then bypasses reservation invalidation, allowing SC to succeed incorrectly. The refill check also considers only `ctx->ll_valid`, not reservations held by other contexts.
  - **Fix**: Gate writable publication at page granularity against every live reservation relevant to that mapping. Keep the page on the checked store path until reservations are cleared. Use one reservation policy across interpreter and DBT memory paths.

- [ ] **LA64-R2-3 — High — BUG — Mprotect releases the mutation transaction before updating host permissions**
  - **Where**: `src/os/mem_min.c:575-626` (`la64_mem_protect`); `src/os/mem_min.c:169-194` (`protect_host_page`).
  - **What breaks / Why**: The function updates guest protection metadata and calls `vm64_commit_mutation` before applying host-page protection changes. This puts the host synchronization outside the intended quiescent transaction. When permissions are relaxed, another worker can observe the new guest permission while the host page still denies access, producing a translator fault. If host `mprotect` fails, the function returns an error after publishing the new guest permissions, leaving inconsistent state.
  - **Fix**: Keep peers quiescent until host permissions and guest metadata agree. Stage protection changes, handle host failures with rollback or explicitly consistent partial state, then invalidate translations/TLBs and release the transaction.

#### Medium

- [ ] **LA64-R2-4 — Medium — BUG — Fixed mmap silently rounds down invalid addresses**
  - **Where**: `src/os/syscalls_mem.c:212-231` (`sys_mmap`).
  - **What breaks / Why**: Both `MAP_FIXED` and the nonzero-address `MAP_FIXED_NOREPLACE` paths mask off the low address bits instead of rejecting an unaligned address. For `MAP_FIXED`, a malformed request can therefore replace an existing mapping at the preceding page boundary instead of returning `EINVAL`. This contradicts the series’ explicit syscall-alignment contract.
  - **Fix**: Validate page alignment before modifying mappings for either fixed-address flag. Reserve hint rounding for non-fixed mappings. Validate the zero-address `MAP_FIXED_NOREPLACE` case through the same fixed-address path.

- [ ] **LA64-R2-5 — Medium — BUG — Darwin directory cursors remain descriptor-local and can lose buffered entries**
  - **Where**: `src/os/darwin_dir.h:25-40` (`darwin_dir_slot_t`); `src/os/darwin_dir.h:53-105` (`darwin_dir_acquire`); `src/os/darwin_dir.h:125-147` (`darwin_dir_getdents64`).
  - **What breaks / Why**: The new cache retains pending entries for repeated calls on one descriptor, but it keys streams by numeric fd and creates a separate `DIR *` for each descriptor. Duplicated descriptors share the underlying directory offset while their libc buffers and pending entries remain separate. Alternating enumeration through aliases can therefore skip entries. Additionally, exhausting the cache silently closes slot zero, discarding its pending entry and buffered read-ahead; recreating that stream resumes from the advanced underlying offset.
  - **Fix**: Associate one reference-counted cursor with each shared open-file description and attach descriptor aliases to it. Do not evict a live cursor without preserving its logical position and buffered state; return a resource error if safe retention is impossible.

#### Critical / Low

No additional findings established at these severities in this section.

### 7.2 Curated C11 & UB Issues

No additional standalone C11/UB finding met the evidence threshold within this inspection budget.

The inspected negative-immediate shift change moves the shift before the signed cast, addressing the previously reported signed-left-shift issue. Searches found no textual `.c` includes or calls to the listed banned string functions. Textual `x18` matches were comments and checks; this does **not** prove every generated instruction preserves the register.

The IBTC fields remain ordinary `uint64_t` and pointer fields, despite the remediation commit’s atomic-publication claim. A complete concurrency proof would require tracing scheduler serialization and signal interleavings; absence of atomics alone is not reported here as a proven data race.

### 7.3 DRY — Intra-Repo Duplication

No additional independently substantiated duplication finding is reported. The former duplicated JIT lifecycle now routes through repository-local helpers in `src/os/jit_wx.h`.

All proposed fixes remain within this standalone repository.

### 7.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **LA64-R2-6 — Low — YAGNI — C IBTC lookup API has no production caller**
  - **Where**: `src/dbt/dbt_chain.c:49-56` (`dbt_ibtc_lookup`); `src/dbt/dbt.h:149` (declaration).
  - **What breaks / Why**: Production reference searches found only the definition and declaration. The trampoline probes the table directly, while `dbt_chain_next` uses `dbt_lookup_code`. This leaves an unused public lookup interface with a separate validation policy to maintain.
  - **Fix**: Remove the unused production API, or make its specific test-only purpose explicit and restrict its exposure accordingly.

### 7.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **LA64-R2-7 — Low — CLEAN — Chaining documentation describes removed and nonexistent state**
  - **Where**: `src/dbt/dbt_chain.c:4-7`, `src/dbt/dbt_chain.c:21-22`; `src/dbt/dbt.h:136-146`.
  - **What breaks / Why**: Comments still describe a per-thread IBTC and a RAS. The IBTC is a process-global array without thread-local storage, and the RAS was removed in the remediation. These claims obscure the actual ownership and synchronization requirements during precisely the concurrency review the code needs.
  - **Fix**: Remove the RAS references and document the IBTC’s actual process-wide ownership, invalidation rules, and serialization assumptions.

The inspected file-size gate now includes `src/` and `tests/`, and static counts found no oversized source files. Complete FP/ISA semantics, file-backed alias coherence, clone/exec behavior, and asynchronous recovery remain unqualified by this bounded audit.

---

## 8. `ppc64rt` (`bd3e73f`) — 15 Round-2 Findings (`0 / 15` Resolved)

### 8.1 Bugs & Defects

#### Critical

None established.

#### High

- [ ] **P64-R2-1 — High — DEFECT — Cooperative children lack general scheduling and are killed at an instruction cap**
  - **Where**: `src/os/syscalls_p4.c:173-200`, `src/os/syscalls_p4.c:245-305`, `src/os/syscalls_p4.c:397-413` (`p4_task_step_quantum`, `p4_sched_run_ready`, clone/wake dispatch).
  - **What breaks / Why**: Clone runs a bounded batch of child quanta before returning. Ready children subsequently advance through selected clone/futex paths, rather than through a scheduler integrated into ordinary parent execution. A child waiting for a parent-written flag can remain ready after clone returns, while the parent subsequently waits for the child using ordinary memory operations; neither makes progress. Blocking child host syscalls can also prevent the parent from running. Independently, exceeding 40 million child instructions silently frees the task and returns `EFAULT`, without normal exit cleanup.
  - **Fix**: Integrate task selection into the main execution loop, with bounded quanta and suspension around blocking operations. Remove the lifetime instruction cap from normal execution; keep any diagnostic execution limit explicit and separate from guest syscall results.

- [ ] **P64-R2-2 — High — BUG — Thread exit and thread-group exit still have incorrect scope**
  - **Where**: `src/os/syscalls_p4.c:208-211` (`p4_task_step_quantum`); `src/run/core.c:382-385` (`run` exit dispatch).
  - **What breaks / Why**: A child’s `exit_group` follows exactly the same path as `exit`, finishing only that child. Conversely, the main task’s `exit` breaks the whole runner even when other guest threads remain live. Programs can continue after a requested process-wide termination or lose live workers when only their initial thread exits.
  - **Fix**: Represent individual task termination separately from group termination. Continue scheduling surviving tasks after a thread exits; propagate `exit_group` and its status to the complete guest thread group.

- [ ] **P64-R2-3 — High — DEFECT — Futex timeout validation does not implement timeout behavior**
  - **Where**: `src/os/syscalls_p4.c:333-395` (`syscall_p4_futex`).
  - **What breaks / Why**: Timeout seconds and nanoseconds are read and validated, then discarded. A waiting child records no deadline and can remain suspended indefinitely. A parent returns `ETIMEDOUT` as soon as no child is ready, regardless of the requested interval; with perpetually ready children, the loop does not enforce a deadline. An untimed matching wait can still return `EAGAIN` merely because there is nothing locally runnable.
  - **Fix**: Store deadlines in waiter state, distinguish relative WAIT from absolute WAIT_BITSET deadlines and clock selection, and suspend until wake, interruption, or actual expiry. Couple this with the scheduler rather than interpreting an empty ready queue as timeout or mismatch.

- [ ] **P64-R2-4 — High — BUG — Child execution bypasses the repaired signal machinery**
  - **Where**: `src/os/syscalls_p4.c:193-200`, `src/os/syscalls_p4.c:223-237` (`p4_task_step_quantum`); `src/run/core.c:387-418` (main-task signal dispatch); `src/os/syscalls_access.c:209-219` (`x_sigmask`).
  - **What breaks / Why**: The child runner sends syscalls directly to `ppc64_syscall`, bypassing the main runner’s sigaction, kill/tgkill, sigreturn, and altstack interception. A child memory fault frees the task and returns `EFAULT` instead of delivering its installed guest handler. Signal masks are also held in one static variable, so one child’s mask change changes the parent’s mask. The Round-1 signal fixes therefore do not provide per-thread Linux signal behavior.
  - **Fix**: Use the same trap/syscall/signal dispatch for every guest task. Keep blocked masks, pending thread-directed signals, altstack, and return-frame state per task; share dispositions only according to clone semantics.

- [ ] **P64-R2-5 — High — BUG — VM atomics ignore the interpreter’s per-context reservation token**
  - **Where**: `src/interp/vec.c:110-149`, `src/interp/vec.c:151-180` (`ppc64_exec_larx_stcx`); `src/vm/vm_atomic.c:263-290`, `src/vm/vm_atomic.c:303-315` (`vm_mem_atomic`, `ppc64_vm_reserve`).
  - **What breaks / Why**: The interpreter saves and passes a reservation token, but the VM callback does not populate or check that token. It uses one `vm->resv_*` record shared by guest contexts. A later context’s LR can replace the record that an earlier context’s SC checks. This becomes a false-success risk when a write invalidates the VM reservation without clearing the earlier interpreter slot, followed by another context’s LR at the same address: the earlier SC can consume the newer reservation and overwrite data despite its original reservation having been lost.
  - **Fix**: Return an actual reservation identity/version from LR and validate that exact identity on SC. Keep ownership per guest context and invalidate it across all relevant writes and task lifecycle transitions.

- [ ] **P64-R2-6 — High — BUG — Successful atomic stores bypass code invalidation and shared-file write propagation**
  - **Where**: `src/vm/vm_atomic.c:271-297` (`vm_mem_atomic`); `src/vm/vm64.c:288-315` (`vm_mem_write`).
  - **What breaks / Why**: The aligned SC/RMW path modifies host backing directly and only calls `ppc64_vm_reserve_note_store`. Ordinary writes additionally retire translated code and propagate MAP_SHARED writes to the file and sibling mappings. Routing guest SC through the atomic callback makes this omission reachable: an atomic patch to translated code can leave stale executable translations, and an atomic modification to a shared file mapping can remain local.
  - **Fix**: Integrate atomic stores with the VM write protocol: perform required COW/code invalidation before publication and shared-backing propagation after successful modification. Preserve atomicity rather than replacing CAS with an ordinary copy.

- [ ] **P64-R2-7 — High — BUG — Scalar FP arithmetic ignores guest rounding and single-precision result rounding**
  - **Where**: `src/interp/fp.c:92-125` (`fp_add`, `fp_sub`, `fp_mul`, `fp_div`); `src/interp/fp.c:259-279` (`fp_po63`); `src/interp/fp.c:794-797` (`ppc64_fp_step`).
  - **What breaks / Why**: Opcodes 59 and 63 use the same host-double arithmetic path. Single-precision instructions therefore retain double-precision results instead of rounding to binary32 and representing that rounded value in the FPR. For example, single-precision addition of `1.0` and `2^-24` under nearest-even should produce `1.0`; this path retains `1.0 + 2^-24`. Arithmetic also never consults FPSCR.RN, so guest rounding-mode changes do not govern results. DBT fallback inherits these interpreter errors.
  - **Fix**: Implement format-specific arithmetic with guest rounding control, preferably through the existing established software-FP substrate or a carefully controlled host-FP layer. Add oracle cases for all rounding modes and binary32 halfway values.

- [ ] **P64-R2-8 — High — BUG — Child cleanup can clear the parent’s clear-TID address**
  - **Where**: `src/os/syscalls.c:563-579` (`SET_TID_ADDRESS`, clone dispatch); `src/os/syscalls_p4.c:156-169`, `src/os/syscalls_p4.c:297-301` (`p4_task_finish`, `syscall_p4_clone`).
  - **What breaks / Why**: `set_tid_address` updates a single global `s_clear_tid`, which is passed into clone and copied into the child’s `set_tid_addr`. Child exit clears and wakes that address in addition to its requested `CLONE_CHILD_CLEARTID` address. A parent that registered its own clear-TID word can therefore have that word zeroed when an unrelated child exits. A child calling `set_tid_address` also changes global state rather than its own task’s cleanup address.
  - **Fix**: Store clear-TID state per task. Initialize the child according to clone flags, update the current task on `set_tid_address`, and clear only the exiting task’s registered address.

#### Medium

- [ ] **P64-R2-9 — Medium — BUG — FPSCR exception and record-form updates are fabricated**
  - **Where**: `src/interp/fp.c:31-41` (`ppc64_fpscr_record`); `src/interp/fp.c:280-298` (`fp_po63`).
  - **What breaks / Why**: Finite division results are treated as inexact whenever repeating the same host division produces the same bits; exact division such as `4.0 / 2.0` satisfies that condition. The exception helper places flags in an ad hoc `exc << 4` layout and sets bit 32, rather than implementing architectural FPSCR status fields. Record forms then write CR1 as zero rather than copying the required FPSCR summary. Guest exception inspection and branches on FP status are incorrect.
  - **Fix**: Collect actual operation exceptions, map them into named Power FPSCR fields, maintain summary/sticky status, and derive CR1 from the architectural fields.

- [ ] **P64-R2-10 — Medium — BUG — Access syscalls reject valid relative paths and directory descriptors**
  - **Where**: `src/os/syscalls_access.c:109-115` (`acc_guest_abs`); `src/os/syscalls_access.c:147-158` (`syscall_faccessat`); `src/os/syscalls_access.c:173-180` (`syscall_access`).
  - **What breaks / Why**: Relative paths unconditionally return `EBADF`. `faccessat` also rejects every directory descriptor except `AT_FDCWD`, even for an absolute path where the descriptor should be ignored. Ordinary `access("file", F_OK)` and descriptor-relative access checks fail despite valid files and descriptors.
  - **Fix**: Resolve relative paths against guest cwd or the translated directory descriptor. Ignore `dirfd` for absolute paths and preserve Linux error semantics.

- [ ] **P64-R2-11 — Medium — BUG — Path copy-in reads beyond a valid terminating NUL**
  - **Where**: `src/os/syscalls_access.c:98-115` (`acc_guest_abs`).
  - **What breaks / Why**: The function reads an entire 256-byte chunk before checking for a terminating NUL. A valid short pathname near the end of a readable guest page returns `EFAULT` if the chunk crosses into an inaccessible page, even though the complete string is readable.
  - **Fix**: Bound each read to the remaining bytes in the current guest page, inspect for NUL, and only access the next page when necessary. Reuse the corrected copy-string helper within this repository.

#### Low

No additional low-severity BUG/DEFECT findings.

### 8.2 Curated C11 & UB Issues

- [ ] **P64-R2-12 — Low — C11 — Generated test source still calls banned strcpy**
  - **Where**: `tests/h2_run.sh:100-106` (generated `t_string` function).
  - **What breaks / Why**: The generated first-party C source uses `strcpy`, contrary to the explicitly requested curated subset. This particular literal fits the destination, so this is a policy violation rather than an established overflow.
  - **Fix**: Initialize the array directly or use a bounded copy with a known size. Include generated C embedded in scripts in source-policy scans.

No additional definite C undefined behavior was established within the inspected excerpts. The targeted scan found no textual `.c` unity includes or explicit assembly access to `x18`; this does not verify every encoded JIT instruction.

### 8.3 DRY — Intra-Repo Duplication

- [ ] **P64-R2-13 — Low — DRY — Access and faccessat duplicate resolution and retry logic**
  - **Where**: `src/os/syscalls_access.c:159-170`, `src/os/syscalls_access.c:181-192` (`syscall_faccessat`, `syscall_access`).
  - **What breaks / Why**: Both functions repeat the initial access call, fallback buffer construction, sysroot remapping, and retry. Their path-semantics fixes must consequently be maintained twice.
  - **Fix**: Use a repository-local helper for the resolved-path access and fallback operation, with cwd/dirfd resolution handled explicitly by its caller. No cross-repository library is needed.

### 8.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **P64-R2-14 — Low — YAGNI — Guest rounding-mode accessor has no production caller**
  - **Where**: `src/interp/fp.c:24-29` (`ppc64_fpscr_rn`).
  - **What breaks / Why**: The repository symbol search finds its declaration and definition but no caller. The accessor suggests a rounding integration point while live arithmetic ignores the mode, as described in P64-R2-7.
  - **Fix**: Connect it to the corrected arithmetic implementation, or remove the unused exported API until that integration exists.

### 8.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P64-R2-15 — Low — CLEAN — Thread module documentation describes the removed execution model**
  - **Where**: `src/os/syscalls_p4.c:4-17` (file header).
  - **What breaks / Why**: The header still says clone runs a child inline to completion, unchanged-word futex WAIT is unreachable, and WAKE has no waiters. The implementation now retains runnable and waiting tasks. These claims conceal the actual scheduling and lifetime obligations precisely where maintainers need an accurate concurrency description.
  - **Fix**: Document the current cooperative task model, its scheduling entry points, task ownership, and remaining limitations. Remove assertions based solely on the old gate-test execution order.

The line-count scan found no current first-party ceiling violation. Complete mremap rollback, synchronous host-fault recovery, AOT validation, and concurrent cache/quiescence safety remain **unqualified by this bounded audit**.

---

## 9. `mips64rt` (`32d5c9e`) — 10 Round-2 Findings (`0 / 10` Resolved)

### 9.1 Bugs & Defects

#### High

- [ ] **M64-R2-1 — High — BUG — Ordinary stores remain outside the LL/SC critical section**
  - **Where**: `src/os/mem.c:209-223`, `src/os/mem.c:302-329` (`guest_st8`, `guest_st32`); `src/interp/unaligned.c:370-377`, `src/interp/unaligned.c:442-479` (`mips_llsc_note_write`, `do_sc`).
  - **What breaks / Why**: The Round-1 fix locks reservation bookkeeping, but ordinary stores modify guest memory **before** calling the notification hook. SC holds `sc_lock` across its generation/value check and store; ordinary writers do not hold that lock while writing. Another thread can therefore modify the reserved word between SC’s comparison and commit, then wait for the lock to report its write. SC can incorrectly succeed and overwrite that intervening store. The new generation counters do not close this window.
  - **Fix**: Serialize the actual memory write and reservation invalidation with SC’s check-and-commit. Provide a shared write transaction covering scalar stores and other guest-memory writers, with explicit handling for writes already executing inside SC.

- [ ] **M64-R2-2 — High — BUG — Blocking syscalls can prevent every VM mutation from completing**
  - **Where**: `src/os/syscall_min.c:848-861` (`mips_syscall`); `src/os/quiesce.c:306-340` (`mips_qs_begin`); `src/os/quiesce.c:169-171` (`qs_preempt_handler`).
  - **What breaks / Why**: The syscall wrapper holds a memory lease across the entire syscall body, including potentially indefinite host waits. A VM mutator waits until every peer is parked with zero leases. Leased peers are deliberately excluded from preemption, and the preemption handler returns if a lease is active. A thread blocked in a read or wait can consequently prevent another thread’s `mmap`, `mprotect`, or `munmap` from completing indefinitely.
  - **Fix**: Separate guest-memory access from blocking host waits. Use staging buffers or explicit mapping pins where needed, release the quiescence lease before blocking, and reacquire and revalidate before guest-memory copyout.

- [ ] **M64-R2-3 — High — BUG — DBT compilation performs faulting speculative instruction fetches**
  - **Where**: `src/dbt/dbt.c:443-474` (`dbt_compile`); `src/interp/interp.c:794-810` (`exec_branch`).
  - **What breaks / Why**: Compilation calls the architectural `mips_fetch` on subsequent instructions and on a branch’s delay slot before executing the branch. When the delay-slot fetch fails, compilation merely removes the branch from the candidate block. Any fault or signal-delivery side effect of that fetch has already happened. In particular, a not-taken branch-likely at a page boundary must annul its inaccessible delay slot; the interpreter explicitly skips the fetch, while compilation attempts it unconditionally.
  - **Fix**: Use a side-effect-free fetch/probe for block construction. On an inaccessible speculative instruction or delay slot, end the block or fall back at the branch PC. Only execution should deliver the architectural fault.

- [ ] **M64-R2-4 — High — BUG — Fork inherits quiescence entries for threads that no longer exist**
  - **Where**: `src/os/syscall_min.c:429-439` (`sc_fork`); `src/os/quiesce.c:46-63`, `src/os/quiesce.c:314-337` (worker registry and mutation drain); `src/interp/unaligned.c:290-308` (`sc_lock`).
  - **What breaks / Why**: The fork child inherits the process-wide worker registry, including parent-process TIDs, pthread identities, and lease counts. Only the calling host thread survives. A later child VM mutation can wait forever for inherited peers that cannot park or release leases; preemption also uses the saved parent PID/TID. The newly introduced LL/SC spinlock can likewise be inherited as locked if another thread held it at fork. The inspected atfork registrations cover memory/file bookkeeping, not these registries and locks.
  - **Fix**: Add a coordinated fork lifecycle that stabilizes relevant state before fork and reconstructs child-only thread, quiescence, and reservation state afterward. Reset inherited locks safely and refresh the surviving thread’s PID/TID binding.

#### Medium

- [ ] **M64-R2-5 — Medium — BUG — Double-precision FP emulation assumes wider long-double arithmetic**
  - **Where**: `src/interp/fp.c:202-223` (`fp_adj_d`); `src/interp/fp.c:395-396`, `src/interp/fp.c:417-447`, `src/interp/fp.c:469-473` (double arithmetic and exception accounting).
  - **What breaks / Why**: The interpreter treats `long double` calculations as an exact reference for rounding and inexact detection. Native Apple Silicon Darwin uses binary64 `long double`, so this reference can equal the already-rounded `double`. For example, adding `1.0` and `2^-54` under round-toward-positive must produce the next representable double; the comparison can instead see equality and leave `1.0` unchanged. Inexact flags are also lost. The Round-1 integer conversion fix avoids this assumption, but arithmetic still uses it.
  - **Fix**: Replace precision-dependent reference calculations with reliable rounding and exception handling on every supported host, using an established FP implementation or proven operation-specific residual calculations.

- [ ] **M64-R2-6 — Medium — BUG — Interpreter never raises underflow through its result-accounting helper**
  - **Where**: `src/interp/fp.c:176-187` (`fp_inexact`); `src/interp/fp_cvt.c:121-125` (`fp_cvt_sd`).
  - **What breaks / Why**: The helper explicitly omits underflow and raises only overflow and inexact. A tiny, inexact result—for example a sufficiently small finite double converted to single precision—therefore lacks the underflow cause/flag. With underflow enabled, the new enabled-exception mechanism cannot deliver SIGFPE because no underflow exception is recorded.
  - **Fix**: Implement tininess and inexactness accounting for narrowing and arithmetic according to the supported MIPS FP profile. Route underflow through `fp_raise` so enabled exceptions also suppress destination writeback.

- [ ] **M64-R2-7 — Medium — DEFECT — Instruction traps still collapse distinct signal codes to one**
  - **Where**: `src/os/sigframe.c:537-561` (`mips_trap`); `src/interp/interp.c:329-342` (trapping integer arithmetic); `src/interp/fp.c:161-170` (`fp_finish_trap`).
  - **What breaks / Why**: Round 1 corrected the signal number, but `mips_trap` assigns `si_code = 1` to every SIGFPE. Integer overflow and enabled FP invalid, overflow, underflow, and inexact exceptions consequently receive the same diagnostic code. Signal handlers cannot distinguish the actual architectural exception; code 1 denotes integer division rather than this collection of causes.
  - **Fix**: Carry an explicit exception kind and signal code from the instruction or FP exception source into signal-frame construction. Preserve the existing precise PC and delay-slot handling.

#### Critical / Low

No additional confirmed findings at these severities in this category.

### 9.2 Curated C11 & UB Issues

- [ ] **M64-R2-8 — High — C11 — Quiescence slots are published before initialization**
  - **Where**: `src/os/quiesce.c:70-104` (`qs_slot_for`); `src/os/quiesce.c:163-165`, `src/os/quiesce.c:314-337` (registry readers); `src/os/quiesce.c:403-425` (`mips_qs_unregister`).
  - **What breaks / Why**: Slot creation changes atomic `used` from zero to one **before** initializing non-atomic `key`, `pthread`, `tid`, and `pid`. Other threads and the preemption handler treat nonzero `used` as a fully initialized slot and read those fields concurrently. Atomic publication cannot order writes that happen afterward. Unregistration similarly modifies `key` while the slot remains published. This creates C data races and can direct preemption at stale or uninitialized thread identifiers, preventing quiescence.
  - **Fix**: Distinguish FREE, INITIALIZING, and LIVE states. Initialize fields before release-publishing LIVE, and let readers acquire-observe only LIVE slots. Add a safe retirement/reuse protocol so readers cannot overlap teardown or reinitialization.

The inventory found no file exceeding 900 lines. The searches found no direct calls to the listed banned functions or textual `.c` includes in the searched production/test paths. This does not establish absence of all VLAs, UB, or numerically encoded `x18` use.

### 9.3 DRY — Intra-Repo Duplication

- [ ] **M64-R2-9 — Low — DRY — Pending signal queue insertion remains duplicated**
  - **Where**: `src/os/sigact.c:135-152` (`l4a_pend_enqueue`); `src/os/sigframe.c:130-146` (`l4b_pend_enqueue`).
  - **What breaks / Why**: Both implementations duplicate capacity checks, slot arithmetic, event-field writes, and count updates. The comments explicitly justify duplication by historical lane isolation. Changes to queue synchronization, overflow behavior, or event representation must now be applied consistently in two signal paths.
  - **Fix**: Move pending-queue operations into one separately compiled internal module within **mips64rt**, with a narrow header and explicit synchronization contract. Preserve the standalone repository boundary.

### 9.4 YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding was established with sufficient confidence within the inspection budget. The former write-only arena retention array now has a reclamation reader and should not be reported again as unchanged dead bookkeeping.

### 9.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M64-R2-10 — Low — CLEAN — Arena lifetime comments contradict the reclamation implementation**
  - **Where**: `src/dbt/arena.c:15-18`, `src/dbt/arena.c:42-43`, `src/dbt/arena.c:58-73`; `src/dbt/dbt.c:131-134`, `src/dbt/dbt.c:150-151`.
  - **What breaks / Why**: Comments still promise that published mappings are never unmapped and remain valid until process exit, using the 1024-entry cache as the lifetime justification. The remediation now explicitly frees tracked mappings in `dbt_arena_reset`. These comments describe an obsolete pointer-lifetime guarantee precisely where maintainers need to understand reclamation safety.
  - **Fix**: Document the actual reclamation boundary, required cache/IBTC invalidation, thread ownership, and prohibition on retaining code pointers across reset. Remove the obsolete process-lifetime and cache-size justification.

**Validation status:** All findings are static source conclusions with line-numbered locations. No runtime reproduction or release qualification was performed.

---

## 10. `sparc64rt` (`3ead4f9`) — 12 Round-2 Findings (`0 / 12` Resolved)

### 10.1 Bugs & Defects

#### High

- [ ] **S64-R2-1 — High — BUG — Signal frames corrupt the Y register**
  - **Where**: `src/os/sync_sig.c:482-486` (`sparc64_sync_sig_deliver`); `src/os/sync_sig.c:585-590` (`sparc64_sync_sig_return`).
  - **What breaks / Why**: The frame contains adjacent **32-bit** `y` and `magic` fields. Delivery writes `ctx->y` using `put_u64be` at `0x1d8`, then overwrites its lower four bytes with `magic` at `0x1dc`. For an ordinary 32-bit Y value, the actual frame Y becomes zero. Return reads eight bytes, incorporating the magic value into restored Y. A signal round trip therefore changes arithmetic state, affecting subsequent Y-dependent multiplication/division sequences.
  - **Fix**: Write and read Y as a big-endian 32-bit field. Keep magic separate. Add a regression that sets a nonzero Y, checks the handler-visible frame, and verifies Y after sigreturn.

- [ ] **S64-R2-2 — High — BUG — Delay-slot syscalls lose the pending branch destination**
  - **Where**: `src/interp/interp.c:254-260` (`exec_delay`); `src/interp/interp.c:312-325,339-364` (`exec_cti`); `src/os/guest_engines.c:244-257` (`run_interp`).
  - **What breaks / Why**: A taken branch executes its delay slot before publishing the delay instruction’s architectural `pc` and pending target in `npc`. If the slot contains a syscall trap, `exec_delay` returns immediately and the branch never commits its target. `run_interp` passes the unchanged CPU context into syscall handling; `step.pc` is used to identify the trap, but does not repair the pending control transfer. The syscall therefore sees the branch’s old PC/NPC pair, and ordinary syscall advancement cannot resume at the branch target.
  - **Fix**: Represent the architectural transition explicitly: before executing the delay instruction, publish its PC and the selected next PC. Preserve that pair across traps and syscalls. Test a taken branch with a returning syscall in its delay slot, including interpreter fallback from DBT.

- [ ] **S64-R2-3 — High — BUG — Cache flush forgets a failed RX-to-RW transition**
  - **Where**: `src/dbt/emit_rt.c:70-93` (`dbt_flush_all`); `src/dbt/dbt.c:122-142` (`dbt_stage`).
  - **What breaks / Why**: `dbt_flush_all` ignores `a32h_wx_reopen` failure, clears `arena_published`, and resets `arena_used`. If the permission change fails, the arena remains RX while bookkeeping says it is writable. Subsequent staging skips reopening and returns that memory for code emission, causing a host write fault. The Round-1 publication fix covers entry into unpublished code but not this reverse transition.
  - **Fix**: Change arena state only after successful reopening. Propagate failure or discard the arena and fall back to interpretation. Exercise both publication and reopening failures through an injectable host-memory interface.

#### Medium

- [ ] **S64-R2-4 — Medium — DEFECT — Futex requeue reports the wrong count and permits ineffective moves**
  - **Where**: `src/os/backend_darwin_sync.c:348-387` (`rt_host_futex_requeue`); `src/os/backend_darwin_sync.c:148-157` (`futex_match`).
  - **What breaks / Why**: The implementation counts moved waiters in `requeued` but returns only `woken`. A request that moves waiters without waking any returns zero despite changing the queue. If `key2 == NULL`, it increments `requeued` without changing either the key or address. Additionally, keyed moves retain the old `uaddr`; a subsequent address-only lookup can still match the source address.
  - **Fix**: Return the total number woken and requeued. Require a valid destination identity and update the matching representation consistently. Reject unsupported keyed/address-only combinations rather than reporting an ineffective move.

- [ ] **S64-R2-5 — Medium — DEFECT — Temporary poll masks still permit lost signal wakeups**
  - **Where**: `src/os/backend_darwin.c:578-615` (`darwin_sigmask_enter`, `rt_host_ppoll`); `src/os/backend_darwin.c:680-702` (`rt_host_epoll_pwait`).
  - **What breaks / Why**: `pthread_sigmask` and the blocking operation are separate calls. A pending signal can be delivered after the mask changes but before `poll` or `kevent` starts. With no worker wake pipe, `ppoll` can then sleep for the entire timeout or indefinitely. The epoll path does not register the worker wake pipe with this wait; checking `sig_seq` after `kevent` cannot wake a wait already sleeping. Thus Round-1’s atomic-mask requirement remains unresolved.
  - **Fix**: Use a platform-supported atomic mask-and-wait mechanism or a complete signal-notification protocol with persistent readiness included in every wait. Define and enforce behavior when `ws == NULL`.

- [ ] **S64-R2-6 — Medium — DEFECT — Darwin directory reads discard unread entries**
  - **Where**: `src/os/backend_darwin.c:385-403` (`rt_host_getdents64`).
  - **What breaks / Why**: Each call creates a fresh buffered `DIR` on a duplicate of the caller’s descriptor. `readdir` can advance the shared underlying directory offset beyond the entries returned to the caller. When the output buffer fills, `closedir` discards remaining buffered entries, and the next call resumes past them. The entry that fails the size check has also already been consumed. If even the first record does not fit, the function returns zero, falsely indicating EOF.
  - **Fix**: Preserve directory stream state across calls or use an unbuffered directory-entry interface with explicit offsets. Retain the first unreturned entry and report an appropriate error when the buffer cannot hold any record.

#### Critical / Low

No additional findings established in these severity groups.

### 10.2 Curated C11 & UB Issues

- [ ] **S64-R2-7 — Medium — C11 — Signal notification now locks a pthread mutex**
  - **Where**: `src/os/backend_darwin_sync.c:135-145,160-169` (`futex_lock`, `futex_broadcast_all_signals`); `src/os/backend_darwin_sync.c:210-216` (`rt_host_worker_notify_signal`); `src/os/backend.h:45-59` (signal-wakeup contract).
  - **What breaks / Why**: The notification function now enters `g_futex_mu` and broadcasts pthread condition variables. These operations are not async-signal-safe. If invoked by a signal handler interrupting a thread that holds this mutex, notification deadlocks on that same thread. First-use notification can also initialize condition variables inside the handler. This is a regression in the intended signal-notification interface; a current production handler-to-function call chain was not found.
  - **Fix**: Keep handler notification limited to async-signal-safe operations. Arrange for normal execution context to process the persistent wake notification and signal waiters without losing wakeups.

- [ ] **S64-R2-8 — Medium — C11 — Worker mutex initialization races between first callers**
  - **Where**: `src/os/backend_darwin_sync.c:65-79` (`g_workers`, `workers_lock`); `src/os/backend_darwin_sync.c:82-115` (worker registration and lookup).
  - **What breaks / Why**: `g_workers.init` is read and written without synchronization before the mutex is acquired. Concurrent first callers can both initialize the same mutex, or one can reinitialize it while another begins using it. The flag accesses constitute a C data race, and concurrent initialization invalidates the pthread synchronization object.
  - **Fix**: Initialize the mutex statically with `PTHREAD_MUTEX_INITIALIZER`, removing the flag, or use `pthread_once` for any initialization that genuinely needs execution.

- [ ] **S64-R2-9 — Medium — C11 — Futex timeout conversion overflows signed arithmetic**
  - **Where**: `src/os/backend_darwin_sync.c:250-271` (`rt_host_futex_wait_bitset`).
  - **What breaks / Why**: Only nanoseconds are validated. Relative seconds are multiplied by one billion in `int64_t`; absolute deadlines also subtract and multiply in signed arithmetic. A large positive timeout, such as `tv_sec = INT64_MAX`, causes signed overflow and undefined behavior instead of a well-defined long wait or error. Negative relative seconds are reported as timeout expiration rather than rejected as an invalid timespec.
  - **Fix**: Validate seconds and nanoseconds, use checked arithmetic, and retain a normalized seconds/nanoseconds representation instead of collapsing unrestricted deadlines into signed nanoseconds.

### 10.3 DRY — Intra-Repo Duplication

- [ ] **S64-R2-10 — Low — DRY — MOVcc adds another copy of the FP condition table**
  - **Where**: `src/dbt/emit_cond.c:184-187,218-220` (`sparc64_emit_movcc`); `src/dbt/emit_fpcmp.c:19-33` (`fp_taken_mask`, `fp_taken_compute`).
  - **What breaks / Why**: The remediation introduces a second identical 16-entry FP condition mask inside the DBT. MOVcc and floating conditional operations now maintain the same truth table separately, creating another drift point immediately after consolidating the raw decoder.
  - **Fix**: Define one internal DBT condition table or emission helper and use it from both files. Keep independent oracle tests. No cross-repository extraction is needed.

### 10.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S64-R2-11 — Low — YAGNI — Obsolete runtime helpers have no callers**
  - **Where**: `src/dbt/emit_rt.c:182-222` (`s64_rt_mem`, `s64_rt_win`).
  - **What breaks / Why**: Repository-wide searches found definitions and historical comments but no calls or function-address references to either helper. They retain superseded memory/window execution paths and misleading claims about active call sites, adding code that must appear correct without contributing to execution.
  - **Fix**: Remove these internal helpers and update stale references, unless a concrete external consumer requires them. If such a consumer exists, declare and document that interface explicitly.

### 10.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S64-R2-12 — Low — CLEAN — Backend contract describes synchronization mechanisms the code no longer uses**
  - **Where**: `src/os/backend.h:45-59` (blocking and preemption contract); `src/os/backend_darwin_sync.c:303-319` (`rt_host_futex_wait_bitset`); `src/os/backend_darwin_sync.c:403-420` (`rt_host_clock_nanosleep`).
  - **What breaks / Why**: The public contract describes futex sleeping through `__ulock_wait2` and signal wakeup through `__ulock_wake`. The implementation now uses pthread condition variables. The same comment promises kqueue-based sleep including a worker wake descriptor, while `rt_host_clock_nanosleep` discards `ws` and `expected_seq` and calls `nanosleep`. These comments incorrectly assure reviewers that lost-wakeup protection exists.
  - **Fix**: Document the actual mechanisms and supported guarantees. Remove obsolete ulock descriptions and identify unsupported wake protocols until implemented.

**Static hygiene results:** No inventoried source exceeded 900 lines. Searches found no production banned string calls or textual `.c` includes. Banned string calls in `test_h2_string.c` exercise libc behavior. Textual `x18` matches were comments; numeric emitter encodings were not exhaustively decoded, so register reservation is not fully qualified.

---

## 11. `rt-series` (`6fc9fbc`) — 18 Round-2 Findings (`0 / 18` Resolved)

### 11.1 Bugs & Defects

#### Critical

No confirmed findings.

#### High

- [ ] **RTS-R2-1 — High — DEFECT — Qualification accepts unrelated tests as software-tier evidence**
  - **Where**: `tools/run_catalogue.sh:107-141` (`check_parity_categories`).
  - **What breaks / Why**: The RTS-6 remediation accepts `hello` as T2 evidence, ISA cases as T1 evidence, and FP/thread cases as T3 evidence. `p3-torture` itself also matches the T3 `p3-` alternative. Matching searches the entire row rather than its case field, and requires no per-ABI or per-engine coverage. A small collection of passing runtime fixtures can therefore qualify a repository without executing compression/database tools, scripting runtimes, or the full required ABI/engine matrix.
  - **Fix**: Parse tab-separated fields and require explicit category evidence for every required ABI/engine tuple. Map only tests that actually implement the category; require separate guest-payload tier results.

- [ ] **RTS-R2-2 — High — DEFECT — Grind still credits host execution to selected foreign architectures**
  - **Where**: `tools/run_grind.sh:69-72` (`resolve_arch_defaults`), `tools/run_grind.sh:442-485` (`run_libc_ltp_suite`), `tools/run_grind.sh:489-529` (`run_lmbench_suite`).
  - **What breaks / Why**: `--arch all` returns without constructing a translator matrix. Even with an explicit foreign architecture, libc/LTP and lmbench binaries execute directly, ignoring the resolved translator wrappers. Native binaries can produce PASS results under a foreign-architecture campaign heading; foreign binaries instead fail direct execution. RTS-4 is only partially fixed.
  - **Fix**: Expand `all` into explicit architecture jobs. Route every guest suite through a validated architecture/backend runner, and record native diagnostics separately from translator qualification.

#### Medium

- [ ] **RTS-R2-3 — Medium — BUG — Grind chooses executable format before resolving the backend**
  - **Where**: `tools/run_grind.sh:73-98`, `tools/run_grind.sh:115-123` (`resolve_arch_defaults`, `BACKEND`).
  - **What breaks / Why**: Discovery prefers `*-darwin-arm64`, then Linux, based only on executable permission. Backend selection happens afterward and does not influence the runner. A Linux host with both artifacts selects Mach-O; Darwin can select a Linux ELF when its native artifact is absent. `GRIND_BACKEND=hl` never adds an `hl` launcher.
  - **Fix**: Resolve and validate the backend first. Select matching binary formats and construct explicit native-Linux, Darwin, or hyper-linux commands.

- [ ] **RTS-R2-4 — Medium — DEFECT — Weekly differential checks never compare results**
  - **Where**: `tools/run_grind.sh:537-575` (`run_weekly_soak`).
  - **What breaks / Why**: Csmith and Yarpgen run one selected wrapper and accept exit zero. Csmith output is never compared; Yarpgen output is discarded. Both report “differential OK.” A translator returning incorrect generated-program checksums can pass. The new RTS-22 implementation therefore adds execution without the claimed correctness oracle.
  - **Fix**: Run the identical generated binary through an independent oracle and each required engine. Compare complete outputs and exit statuses before reporting differential success.

- [ ] **RTS-R2-5 — Medium — BUG — Yarpgen compilation passes unmatched source globs**
  - **Where**: `tools/run_grind.sh:560-574` (`run_weekly_soak`, Yarpgen branch).
  - **What breaks / Why**: The compiler receives both `"$_ydir"/*.c` and `"$_ydir"/*.cpp`. In POSIX shell, an unmatched glob remains a literal filename. A generated corpus containing only C++ or only C sources therefore supplies a nonexistent input and fails compilation. This becomes a tolerated SKIP under the default policy. The selected C compiler also does not explicitly provide C++ linkage.
  - **Fix**: Select the generator’s language explicitly, collect only existing source files, and use the matching compiler/linker. Treat compilation failure after successful prerequisite discovery as a failure.

- [ ] **RTS-R2-6 — Medium — DEFECT — Signal remediation still does not test interrupted reservations or register restoration reliably**
  - **Where**: `tests/p3_torture.c:202-240`, `tests/p3_torture.c:272-293`, `tests/p3_torture.c:313-359` (`t_sig_frame_gpr`, `t_sig_frame_fpr`).
  - **What breaks / Why**: The atomic load precedes delivery, but the compare-exchange starts afterward; no LL/SC reservation spans the signal. A value-changing handler makes the later CAS fail even if reservation invalidation is entirely broken. Ordinary C variables across `raise()` do not guarantee particular registers remain live. The FP fallback similarly invokes a normal function call while operands reside in volatile memory, and the handler neither changes rounding mode nor deliberately raises the exception flags being checked.
  - **Fix**: Use small per-ISA fixtures to establish live registers and an actual exclusive-load/store interval across controlled delivery. Explicitly alter handler FP state and verify resumed state. Keep the portable cases, but label their narrower guarantees accurately.

- [ ] **RTS-R2-7 — Medium — DEFECT — SPARC smoke binary bypasses the new freshness checks**
  - **Where**: `tools/bench_harness.sh:213-217`, `tools/bench_harness.sh:248-255`, `tools/bench_harness.sh:284-289`, `tools/bench_harness.sh:373-375`.
  - **What breaks / Why**: The fast builder refreshes `bench-sparc32`, while smoke execution prefers any existing `bench-sparc32-smoke`. The latter is rebuilt only by the broad fallback container. After a source/header change, a successful fast rebuild leaves the old smoke executable selected, so RTS-11 remains reproducible on this path.
  - **Fix**: Use one executable with `--smoke`, or apply the same dependency checks and rebuild/publication rules to both artifacts before selection.

- [ ] **RTS-R2-8 — Medium — BUG — Benchmark EXIT trap references an expired local variable**
  - **Where**: `tools/bench_harness.sh:257-301`, `tools/bench_harness.sh:532-535` (`build_guest_bins`).
  - **What breaks / Why**: The EXIT trap stores a deferred reference to local `cname`. After a successful build returns, that local no longer exists. At shell exit, `set -u` makes its expansion fail. Cleanup can emit an unbound-variable error and does not reliably address the intended container. The trap also remains installed for later execution.
  - **Fix**: Scope the trap to a subshell whose lifetime owns the local variable, or maintain explicit invocation-level container ownership. Clear traps after successful cleanup.

- [ ] **RTS-R2-9 — Medium — BUG — Linux benchmark load check selects an unsupported sysctl key**
  - **Where**: `tools/bench_harness.sh:303-319` (`check_calm_host`).
  - **What breaks / Why**: Presence of `sysctl` selects `vm.loadavg`, a Darwin/BSD key. Linux commonly has `sysctl` but exposes load through `/proc/loadavg`. The failed pipeline, combined with `set -euo pipefail`, aborts normal `run` before reaching benchmarks; the `/proc` fallback is never attempted.
  - **Fix**: Select the load source by platform or successful query, validate the numeric result, and fall back to `/proc/loadavg` when appropriate.

- [ ] **RTS-R2-10 — Medium — DEFECT — Catalogue ignores failed summary counters**
  - **Where**: `tools/run_catalogue.sh:79-104`, `tools/run_catalogue.sh:896-907` (`check_parity_no_skip`, `run_repo_gate`).
  - **What breaks / Why**: Despite its updated contract, the checker extracts only `skip`. A delegated command returning zero with `PARITY_SUMMARY ... pass=0 fail=1 gap=0 skip=0` passes this check if no matching FAIL row exists. Smoke mode also accepts an empty log because category validation is disabled there.
  - **Fix**: Validate summary presence and syntax, repository identity, positive pass count, and zero failure/gap counts. Explicitly distinguish a supported non-parity fallback from malformed parity output.

- [ ] **RTS-R2-11 — Medium — DEFECT — Benchmark success does not require complete workload records**
  - **Where**: `tools/bench_harness.sh:349-361` (`check_bench_output`).
  - **What breaks / Why**: Exit zero plus any `ALL_PASS` substring is sufficient. The five workload records, their checksums/statuses, and a valid final timing record are not required; absent timing is printed as `?`. This leaves RTS-3’s requested complete-record validation unfinished. Truncated or incorrectly forwarded output can still receive PASS.
  - **Fix**: Require exactly one valid record for each expected workload and one anchored final summary. Reject missing, duplicate, malformed, or contradictory records.

- [ ] **RTS-R2-12 — Medium — BUG — Concurrent catalogue runs overwrite each other’s evidence**
  - **Where**: `tools/run_catalogue.sh:896-930` (`run_repo_gate`).
  - **What breaks / Why**: Logs use `/tmp/cat-$CMD-$_repo.log` without an invocation identifier. Concurrent runs for the same repository truncate and write the same file. Validation can read another run’s PASS rows or a mixed log, producing false results and destroying diagnostic evidence.
  - **Fix**: Allocate a unique invocation directory and pass its log paths through execution and validation. Preserve failed logs and clean up only owned files.

- [ ] **RTS-R2-13 — Medium — DEFECT — Benchmark container cleanup remains incomplete on timeout and interruption**
  - **Where**: `tools/bench_harness.sh:213-243`, `tools/bench_harness.sh:448-457`, `tools/bench_harness.sh:468-485`.
  - **What breaks / Why**: Fast-path build containers have no cleanup trap or explicit removal after timeout. Runtime containers are removed only after command substitution completes; interrupting the harness bypasses that code. `--rm` removes a container when it exits, but terminating a Docker client does not establish that the daemon-owned workload exited. Removal failures are swallowed without verification.
  - **Fix**: Track all owned container IDs, install invocation-scoped exit/signal cleanup, and verify removal after success, failure, timeout, and interruption.

- [ ] **RTS-R2-14 — Medium — DEFECT — Golden-update failures can return success**
  - **Where**: `tools/parity_contract.sh:89-101` (`parity_check_golden`).
  - **What breaks / Why**: Update mode executes `mkdir` and `cp`, then unconditionally returns zero. When called in an `if` or other tested context, shell `errexit` does not reliably terminate on those failures. Missing input or an unwritable golden can therefore be reported as a successful update.
  - **Fix**: Explicitly propagate directory-creation and copy errors. Copy to a temporary file and atomically rename only after successful completion.

#### Low

No additional BUG/DEFECT findings.

### 11.2 Curated C11 & UB Issues

- [ ] **RTS-R2-15 — Medium — C11 — Fault handlers communicate through ordinary static address objects**
  - **Where**: `tests/p3_torture.c:84-88`, `tests/p3_torture.c:163-172`, `tests/p3_torture.c:529-545`; `tests/tcg/smoke_tcg.c:80-96`, `tests/tcg/smoke_tcg.c:160-175` (`g_segv_addr`, `g_got_addr`).
  - **What breaks / Why**: Both handlers assign ordinary static `uintptr_t` objects that normal execution subsequently reads. These objects have neither the `volatile sig_atomic_t` signal-communication guarantee nor lock-free atomic semantics. The deliberate fault probes necessarily depend on platform extensions, but that does not establish portable C11 signal communication for these address fields.
  - **Fix**: Use a demonstrably lock-free atomic address representation supported by the target, or an explicitly documented platform signal bridge. Verify lock-free support before entering the handler; do not introduce a locking atomic helper there.

No banned-function calls, textual `.c` includes, explicit `x18` references, `_Generic`, or `<threads.h>` references were returned by the source search. All inventoried `.c`/`.h` files are below 900 lines; the largest is `tests/p3_torture.c` at 658 lines. These observations are not compiler or sanitizer validation.

### 11.3 DRY — Intra-Repo Duplication

- [ ] **RTS-R2-16 — Low — DRY — Translator invocation policy is duplicated across runners**
  - **Where**: `tools/bench_harness.sh:322-347` (`build_rt_args`), `tools/run_grind.sh:83-97` (`resolve_arch_defaults`), `tools/remote_bench.sh:26-88`, `tools/remote_linux_inner.sh:36-68`.
  - **What breaks / Why**: Four paths independently encode engine flags, environment variables, separators, and backend invocation. They already differ: remote `rvrt` interpreter execution uses `--engine interp`, while benchmark/grind construction uses `--interp`; other engines alternate between environment and command-line selection. Each future CLI change requires synchronized edits.
  - **Fix**: Centralize the architecture/backend invocation contract in a repository-local helper, retaining argument boundaries. This is tooling reuse within `rt-series`, not a shared translator C library.

### 11.4 YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RTS-R2-17 — Low — YAGNI — Fault signal code is recorded but never checked**
  - **Where**: `tests/p3_torture.c:87-87`, `tests/p3_torture.c:167-169`, `tests/p3_torture.c:539-599` (`g_segv_code`, `t_mprotect_munmap`).
  - **What breaks / Why**: `g_segv_code` is write-only. The fixture collects fault provenance but never distinguishes protection faults from unmapped-address faults. Later probes also omit fresh address validation, despite the combined success message claiming fault-address checking.
  - **Fix**: Reset and validate signal number, platform-appropriate code, and fault address for each probe. Otherwise remove unused collection and narrow the advertised coverage.

### 11.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RTS-R2-18 — Medium — CLEAN — HEAD declares complete remediation despite demonstrably incomplete fixes**
  - **Where**: `DEFECTS.md:14-14`, `DEFECTS.md:28-29` (remediation status and `rt-series` verification row).
  - **What breaks / Why**: HEAD declares all findings resolved and `rt-series` fully verified. Current code still has incomplete RTS-4 architecture routing, RTS-6 qualification evidence, RTS-11 freshness handling, and RTS-16 signal coverage. Reported passing gates cannot establish those missing semantics.
  - **Fix**: Reopen the affected original findings and distinguish implemented changes, executed checks, and remaining verification gaps. Retain historical results without presenting them as proof of complete remediation.

The 900-line C/header ceiling is satisfied. The 1,059-line catalogue shell script is outside that specific ceiling; its size alone is not counted as a violation.

---
## Part II — Round-1 Audit Archive (187 Items Addressed in Round-1 Commits)

> [!NOTE]
> The 187 items below record the Round-1 `gpt-6-astra` audit and the Round-1 commits (`a5f53b4`, `8db8727`, `366ca9b`, `abe6b0b`, `dad95da`, `8e207fb`, `026e87d`, `bd3e73f`, `32d5c9e`, `3ead4f9`, `96e1fe6`). Where Round-2 static inspection found that a Round-1 fix was incomplete or introduced a follow-up edge case, the corresponding open item is tracked in **Part I (Round 2)** above (`§0.1` and `§1..§11`).

### Cross-Cutting Defect Clusters (Wave Planning Index)

- [x] **X-1 — High — Darwin A2 16 KiB Sub-Page Protection & Soft-TLB Fast-Path Integrity**
  - **Linked Items**: `A32-1`, `A32-2`, `I686-1`, `I686-16`, `M32-7`, `P32-4`, `S32-1`, `S32-15`, `RV-4`, `LA64-1`, `LA64-2`, `LA64-8`, `M64-2`
  - **Summary**: Cross-page unaligned accesses only checking the starting 4 KiB page (`A32-1`), multiword/atomic emitters bypassing Soft-TLB on A2 (`A32-2`, `P32-4`), `i686rt` spurious fault counter permanently opening 16 KiB host pages after 64 faults (`I686-1`), write-only pages leaving stale `read_tag` (`RV-4`) or zero `addend` (`M64-2`), and mixed sub-page permissions on Darwin leaving host pages inaccessible (`LA64-2`).
- [x] **X-2 — High — `MAP_SHARED` File / Anonymous Backing & `mremap` Backing Preservation**
  - **Linked Items**: `A32-3`, `A32-4`, `A32-11`, `I686-7`, `M32-3`, `M32-4`, `M32-17`, `P32-5`, `S32-7`, `S32-8`, `LA64-7`, `P64-7`, `P64-8`, `P64-9`, `M64-1`, `S64-6`, `S64-9`
  - **Summary**: Darwin sub-page `MAP_SHARED` file mappings silently falling back to private `pread` copies (`A32-4`, `M32-3`, `S32-8`), `MAP_SHARED | MAP_ANONYMOUS` forced to `MAP_PRIVATE` (`A32-3`), `mremap` replacing file/shared backing with anonymous memory (`I686-7`, `M32-4`, `P32-5`, `S32-7`) or destroying destination mappings on failed `MREMAP_FIXED` (`P64-7`, `P64-8`, `P64-9`).
- [x] **X-3 — High — Multi-Threaded SMC / Code-Cache Invalidation, W^X & Arena Lifecycle**
  - **Linked Items**: `I686-2`, `I686-3`, `I686-6`, `I686-11`, `M32-5`, `M32-6`, `S32-4`, `S32-5`, `RV-1`, `RV-3`, `M64-11`, `M64-16`, `S64-2`
  - **Summary**: Thread-local code caches missing cross-thread SMC/munmap invalidation (`I686-2`, `M32-5`), clone threads unmapping shared JIT arenas while parent threads execute (`S32-5`), ignored W^X `mprotect` errors (`RV-3`, `S64-2`), Linux RWX JIT allocation in `i686rt` (`I686-11`), and unbounded arena growth (`M64-11`).
- [x] **X-4 — High — Atomic / LL-SC Reservation Coherence, Memory Barriers & Data Races**
  - **Linked Items**: `A32-13`, `I686-4`, `P32-3`, `P32-4`, `P32-10`, `S32-3`, `P64-1`, `P64-11`, `M64-3`
  - **Summary**: Unsynchronized process-global reservation state (`A32-13`, `P32-10`, `P64-1`), ABA-vulnerable value-comparison SC without write invalidation (`M64-3`), `LDSTUB` holding a process-wide lock across guest execution (`S32-3`), no-op memory barriers (`P32-3`, `I686-4`), and narrow atomics performing 8-byte CAS across page boundaries (`P64-11`).
- [x] **X-5 — High — Signal Multiplexing, Blocked-Mask Coherence, `rt_sigaction` & `rt_sigreturn`**
  - **Linked Items**: `A32-6`, `A32-9`, `I686-5`, `I686-8`, `I686-10`, `M32-1`, `M32-8`, `M32-11`, `M32-12`, `S32-9`, `S32-10`, `S32-11`, `LA64-3`, `P64-4`, `P64-5`, `P64-6`, `M64-4`, `M64-6`
  - **Summary**: Blocked signals delivered immediately or disconnected masks between `rt_sigprocmask` and delivery/sigreturn (`M32-8`, `S32-9`, `P64-5`), `rt_sigaction(sig, NULL, oldact)` wiping dispositions (`P64-4`), `SIG_DFL` pending signals silently dropped (`I686-8`), instruction traps routed as `SIGSEGV` (`M64-4`), and unsynchronized global signal state across threads (`M32-12`).
- [x] **X-6 — High — Syscall Pointer Validation (`-EFAULT`), Transactional `execve`, `clone` & `futex`**
  - **Linked Items**: `A32-5`, `A32-10`, `M32-2`, `M32-9`, `M32-13`, `P32-6`, `P32-8`, `P32-9`, `S32-1`, `S32-2`, `S32-6`, `RV-2`, `LA64-6`, `P64-2`, `P64-3`, `P64-10`, `M64-7`, `M64-12`, `S64-4`, `S64-5`, `S64-7`, `S64-8`, `S64-11`
  - **Summary**: Unchecked guest pointers faulting in translator C/libc instead of returning `-EFAULT` (`A32-5`, `M32-13`, `P32-6`, `S32-1`), `execve` destroying the caller's VM/signals before validating the target ELF (`M32-2`, `S32-2`), inline child-to-completion `clone` (`P64-2`) or interpreter-only `clone` workers (`M64-12`), stubbed `futex` (`P64-3`, `S64-5`), and `pthread_create`/`pthread_kill` returning `-errno` instead of `-rc` (`RV-2`, `P32-9`) or reading expired parent stack (`S64-11`).
- [x] **X-7 — High — ISA Decode / Lowering Bugs & Curated C11 Undefined Behavior**
  - **Linked Items**: `A32-7`, `A32-8`, `A32-12`, `A32-14`, `I686-9`, `I686-12`, `I686-13`, `I686-14`, `M32-10`, `M32-14`, `P32-1`, `P32-2`, `P32-7`, `P32-11`, `S32-12`, `S32-13`, `RV-5`, `RV-6`, `LA64-4`, `LA64-5`, `LA64-9`, `P64-12`, `M64-5`, `M64-8`, `M64-9`, `M64-10`, `M64-13`, `M64-14`, `S64-1`, `S64-3`, `S64-10`, `RTS-1`, `RTS-18`, `RTS-19`
  - **Summary**: Thumb-2 `B.W` condition/displacement bugs (`A32-7`), PowerPC `OE=1` decode failure (`P32-1`), PowerPC `tw`/`twi` ANDing instead of ORing TO predicates (`P32-2`), MIPS64 `MADD`/`MSUB` unmasked sign-extended `LO` (`M64-5`), SPARC64 `MOVcc (fcc)` misclassified as `MEMBAR` (`S64-3`), LoongArch64 LSX failing to zero upper 128 bits of LASX (`LA64-4`) and difftest re-running interpreter instead of DBT (`LA64-5`), plus signed left-shift UB and float-to-int UB.
- [x] **X-8 — Medium — Intra-Repo DRY & YAGNI Cleanup**
  - **Linked Items**: `A32-15`, `A32-16`, `I686-15`, `I686-16`, `M32-15`, `M32-16`, `M32-17`, `M32-18`, `P32-12`, `P32-13`, `S32-14`, `S32-15`, `RV-7`, `RV-8`, `LA64-10`, `LA64-11`, `P64-13`, `P64-14`, `M64-15`, `M64-16`, `S64-12`, `S64-13`, `RTS-20`, `RTS-21`, `RTS-22`
- [x] **X-9 — Medium — CLEAN Hygiene (`#include "*.c"` Unity Includes, 900-Line Ceiling, `-Werror` & Harness Gates)**
  - **Linked Items**: `A32-17`, `A32-18`, `I686-17`, `I686-18`, `I686-19`, `I686-20`, `M32-19`, `M32-20`, `P32-14`, `P32-15`, `S32-16`, `S32-17`, `S32-18`, `RV-9`, `RV-10`, `LA64-12`, `LA64-13`, `P64-15`, `P64-16`, `M64-17`, `M64-18`, `S64-14`, `RTS-2..RTS-17`, `RTS-23..RTS-25`

---

### R1-1. `a32rt` (`55cdc5f` → `a5f53b4`) — 18 / 18 Resolved

### 1.1 Bugs & Defects

- [x] **A32-1 — High — BUG — Soft-TLB fast path checks only the starting page**
  - **Where**: `src/core/core_emit_alu.c:676-732` (`emit_guest_mem`); `src/os/backend_darwin.c:164-184` (`a32_backend_protect`).
  - **What breaks / Why**: Generated A2 accesses compare the starting virtual page’s tag and then execute the host access without checking alignment or whether the access crosses a 4 KiB boundary. A word load at page offset `4094` can read two bytes from an adjacent guest `PROT_NONE` page because Darwin keeps covering 16 KiB host pages RW.
  - **Fix**: Check the complete access span before the host instruction (or reject unaligned/cross-page offsets on the fast path) and route cross-page accesses through a checked slow path that validates both guest pages and preserves fault state.

- [x] **A32-2 — High — BUG — Doubleword transfers bypass A2 guest permissions**
  - **Where**: `src/core/core_emit_mem.c:20-40` (`a64_emit_guest_ldrd_w`, `a64_emit_guest_strd_w`); `src/interp/interp_t32_mem.c:269-305` (LDRD/STRD lowering); `src/os/backend_darwin.c:175-184` (`a32_backend_protect`).
  - **What breaks / Why**: `LDRD`/`STRD` emit a direct guest-base addition followed by host `LDP`/`STP`, bypassing the Soft-TLB. On Darwin A2, `STRD` can modify guest read-only memory and `LDRD` can read guest-inaccessible memory.
  - **Fix**: Give `a64_emit_guest_ldrd_w` / `a64_emit_guest_strd_w` (and any other multiword/vector/exclusive emitters) an A2 permission-checked implementation covering the full 8-byte span.

- [x] **A32-3 — High — BUG — Anonymous shared mappings become private**
  - **Where**: `src/vm/vm_file.c:145-147` (`a32_vmfile_map_commit`); `src/os/backend_linux.c:67-84` and `src/os/backend_darwin.c:65-95` (`a32_backend_map_anon`).
  - **What breaks / Why**: The anonymous branch discards the requested sharing mode; both backends hardcode `MAP_PRIVATE | MAP_ANONYMOUS`. A guest `MAP_SHARED | MAP_ANONYMOUS` mapping becomes private across host `fork()`, breaking shared-memory IPC and shared futexes.
  - **Fix**: Carry `shared` through `a32_backend_map_anon` and preserve it across fork and remap paths.

- [x] **A32-4 — High — BUG — Darwin MAP_SHARED file mappings are private byte copies**
  - **Where**: `src/os/backend_darwin.c:107-142` (`a32_backend_map_file`); `src/vm/vm_file.c:149-151` (`a32_vmfile_map_commit`).
  - **What breaks / Why**: The normal replacement path zeroes the arena and fills it with `pread`, returning before the actual file-backed `mmap` even when `shared` is true. Writes through the mapping do not update the underlying file or alias mappings.
  - **Fix**: Implement shared file backing that preserves file identity and alias coherence (or reject unsupported unaligned shared mappings explicitly instead of silently copying them).

- [x] **A32-5 — High — BUG — Pathname validation can fault inside the translator**
  - **Where**: `src/os/os_sys_path.c:416-430` (`resolve_guest_path_at`).
  - **What breaks / Why**: Only the first byte is checked with `a32_guest_range_ok`; `strnlen(gpath, PATH_MAX)` then reads directly across subsequent pages. A nonterminated string ending at a readable page boundary followed by an inaccessible page faults in host libc instead of returning guest `-EFAULT`.
  - **Fix**: Copy guest strings into a bounded host buffer using page-aware, fault-safe reads before resolving the path.

- [x] **A32-6 — High — BUG — Synchronous faults outside JIT blocks retry forever**
  - **Where**: `src/signals.c:392-429` (`host_sig_handler`).
  - **What breaks / Why**: A genuine synchronous fault whose host PC is outside the JIT cache is enqueued as an asynchronous signal, then the handler returns without advancing the faulting PC, causing an infinite fault loop.
  - **Fix**: Distinguish user-generated signals (`si_code <= 0`) from synchronous hardware faults outside the JIT cache; recover checked guest-memory helper accesses via fault recovery and abort on genuine translator crashes.

- [x] **A32-7 — High — BUG — Thumb-2 interpreter branch decoder ignores conditions and mixes encodings**
  - **Where**: `src/interp/interp_thumb.c:606-633` (`t32_step`).
  - **What breaks / Why**: The broad branch match includes conditional `B.W` (`T3`) and unconditional `B.W` (`T4`), never evaluates the condition for `T3`, selects displacement format using `hw1 & 0x0800` instead of `hw2` bit 12, and writes `LR` on one `B.W` path.
  - **Fix**: Decode conditional `B.W` (`T3`) and unconditional `B.W` (`T4`) separately using `hw2` bits `[15:12]`, evaluate the condition code for `T3`, reconstruct `J1`/`J2`/`S` displacements per ARMv7-A spec, and never write `LR` on non-link branches.

- [x] **A32-8 — Medium — BUG — Thumb immediate shifts produce incorrect flags and LSR results**
  - **Where**: `src/interp/interp_thumb.c:95-124` (Thumb immediate shifts).
  - **What breaks / Why**: Immediate `LSR` with `imm5 == 0` encodes `LSR #32`, but the interpreter treats `imm5 == 0` as shift-by-0 and calls `i_set_nzcv(..., false)`, clearing `V` instead of preserving `V`.
  - **Fix**: Handle `LSR #32` (`result = 0`, `C = Rm[31]`) and `ASR #32` (`result = Rm >> 31`, `C = Rm[31]`) explicitly, preserve `V`, and respect IT-block flag suppression.

- [x] **A32-9 — Medium — BUG — Interpreter memory faults bypass guest signal handlers**
  - **Where**: `src/interp/interp.c:243-268` (`a32_interp_run`).
  - **What breaks / Why**: `A32_EXIT_FAULT` immediately returns exit code `139` instead of routing through guest `SIGSEGV`/`SIGBUS` signal delivery, unlike the DBT dispatcher.
  - **Fix**: Route interpreter memory faults through the guest fault-delivery policy and resume execution when a guest handler catches the signal.

- [x] **A32-10 — Medium — BUG — Startup silently truncates arguments and environment**
  - **Where**: `src/stack32.c:84-100` (`push_string_table`); `src/stack32.c:144-150` (`a32_stack_setup`).
  - **What breaks / Why**: Collection silently stops at 511 `argv` or `envp` strings without reporting `-E2BIG`, starting the guest with truncated arguments/environment.
  - **Fix**: Dynamically size the pointer table from validated counts or return an explicit `-E2BIG` error when the limit is exceeded.

- [x] **A32-11 — Medium — BUG — File-shrink invalidation uses file offsets as guest addresses and invalidates nothing**
  - **Where**: `src/vm/vm_file.c:248-274` (`vmfile_sync_size`); `src/vm/vm32.c:176-191` (`a32_vm32_tlb_invalidate_range`).
  - **What breaks / Why**: Shrinking an inode computes `cut` as a file offset and calls `a32_vm32_tlb_invalidate_range(cut, 0U)`, which does nothing because `end <= start` and `cut` is not a guest VA.
  - **Fix**: Translate the truncated file offset range into each mapping's guest VA range and invalidate the corresponding guest pages.

### 1.2 Curated C11 & UB Issues

- [x] **A32-12 — High — C11 — Thumb shifts and branch arithmetic invoke undefined behavior**
  - **Where**: `src/interp/interp_thumb.c:54-56`, `src/interp/interp_thumb.c:114-121`, `src/interp/interp_thumb.c:556-560`, `src/interp/interp_thumb.c:620-632`.
  - **What breaks / Why**: `ASR` with `imm == 0` evaluates a 32-bit shift by 32 before overwriting the result; backward short/wide branches left-shift negative signed `int32_t` values.
  - **Fix**: Guard `imm == 0` before shifting and construct branch displacements using unsigned arithmetic before casting to signed.

- [x] **A32-13 — High — C11 — Interpreter exclusive-monitor state is process-global and unsynchronized**
  - **Where**: `src/interp/interp_a32.c:20-62` (`g_excl_valid`, `g_excl_addr`, `g_excl_size`, `do_ldrex`, `do_strex`).
  - **What breaks / Why**: Concurrent interpreter steps or DBT fallbacks read and write static globals without synchronization (C11 data race) and overwrite sibling threads' local monitor state.
  - **Fix**: Move local exclusive-monitor state into `a32_ctx_t` and synchronize shared global reservation invalidation atomically.

- [x] **A32-14 — Medium — C11 — Failed fstat leaves EOF handling reading uninitialized data**
  - **Where**: `src/vm/vm_file.c:165-203` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: `struct stat st` is uninitialized; if `fstat` fails, execution continues and reads uninitialized `st.st_size` on EOF.
  - **Fix**: Check and return the `fstat` error before entering the population loop.

### 1.3 DRY, YAGNI & CLEAN

- [x] **A32-15 — Low — DRY — File population is implemented independently in two layers**
  - **Where**: `src/os/backend_darwin.c:125-140` (`a32_backend_map_file`); `src/vm/vm_file.c:185-214` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: Both implement a `pread` loop with `EINTR` retry and EOF zero-fill with diverging error handling.
  - **Fix**: Consolidate private-file population into one helper inside `a32rt`.

- [x] **A32-16 — Low — YAGNI — Obsolete global file hooks remain publicly declared without callers**
  - **Where**: `src/vm/vm_file.c:303-340` (`a32_vmfile_on_truncate`, `a32_vmfile_hook_write`); `src/vm/vm32.h:214-215`.
  - **What breaks / Why**: Dead public functions with zero callers in `src/`, `tests/`, or `tools/`.
  - **Fix**: Remove the unused declarations and definitions.

- [x] **A32-17 — Medium — CLEAN — Source splitting relies on forbidden textual unity includes**
  - **Where**: `src/a64_emit.c:9-11`, `src/decode_a32.c:9-10`, `src/decode_t32.c:9-11`, `src/vfp_neon.c:9-11`, `src/jit.c:9-12`, `src/aot.c:9-10`, `src/syscalls.c:9-15`.
  - **What breaks / Why**: Seven top-level `.c` files textually `#include` sub-`.c` files, violating the no-unity-includes rule.
  - **Fix**: Compile each implementation `.c` file as a separate translation unit in `Makefile` with narrow internal headers.

- [x] **A32-18 — Low — CLEAN — Four test sources exceed the mandatory 900-line ceiling**
  - **Where**: `tests/test_m1_isa_fs.c:1-3702`, `tests/test_m3_threads_signals.c:1-3182`, `tests/test_m4_vfp_neon.c:1-3233`, `tests/test_m5_ltp_gdb.c:1-2587`.
  - **What breaks / Why**: Four test translation units exceed 900 lines (`2,587` to `3,702` lines); `src/vm.c` (`895`) and `src/os/os_sys_sig_time.c` (`885`) are also near the ceiling.
  - **Fix**: Split the four test suites into separately compiled `<900`-line files and extend `check-line-limits` to `tests/`.

---

### R1-2. `i686rt` (`2fa17fb` → `8db8727`) — 20 / 20 Resolved

### 2.1 Bugs & Defects

- [x] **I686-1 — High — BUG — A2 fault recovery permanently opens protected sub-pages**
  - **Where**: `src/os/signals_i386.c:707-754` (`i686_spurious_emulate`); `src/vm/vm32.c:148-173` (`i686_vm32_union_prot`).
  - **What breaks / Why**: After a 16 KiB host page's spurious-fault counter reaches 64, recovery applies the union of 4 KiB sub-page permissions and returns without restoring the restrictive cover. A writable 4 KiB neighbor permanently exposes adjacent `PROT_NONE` or read-only 4 KiB sub-pages to direct guest reads/writes.
  - **Fix**: Remove the leave-open heuristic and wire the A2 Soft-TLB fast path (`I686-16`) so sub-page permissions are enforced in software on every access.

- [x] **I686-2 — High — BUG — SMC invalidation leaves other threads executing stale code**
  - **Where**: `src/dbt/engine.c:86-116` (`s_ht`, `s_code_pages`, `s_run_ctx`); `src/dbt/engine.c:302-332` (`smc_drop_host`); `src/dbt/engine.c:403-426` (`i686_dbt_smc_write_fault`).
  - **What breaks / Why**: Code caches are thread-local (`_Thread_local`), while `s_code_pages` and host page protections are shared. An SMC write fault clears only the faulting thread's cache and unprotects the page process-wide, leaving sibling threads executing stale translations.
  - **Fix**: Maintain shared per-page code generations and validate/invalidate caches across all worker threads on SMC and `munmap`/`mprotect`.

- [x] **I686-3 — High — BUG — SMC handling overrides guest memory permissions**
  - **Where**: `src/dbt/engine.c:174-207` (`smc_unprotect_host`, `smc_protect`); `src/dbt/engine.c:335-360` (`i686_dbt_invalidate_range`); `src/rt32/rt32_vm.c:974-988` (`rt32_vm_mprotect`).
  - **What breaks / Why**: `smc_unprotect_host` blindly sets `PROT_READ | PROT_WRITE` without checking whether the guest VMA is actually writable. Calling `rt32_vm_mprotect(..., PROT_READ)` followed by `i686_dbt_invalidate_range` immediately re-applies `PROT_READ | PROT_WRITE` to pages marked in `s_code_pages`.
  - **Fix**: Treat a write fault as SMC only if the guest VMA has `PROT_WRITE`, and restore host permissions from the current guest VMA protection mask rather than hardcoded `PROT_READ | PROT_WRITE`.

- [x] **I686-4 — High — BUG — Threaded DBT execution never enables TSO lowering**
  - **Where**: `src/dbt/emit_exit.c:38-47` (`i686_emit_begin`); `src/dbt/emit_alu.c:128-155` (guest-memory lowering); `src/dbt/emit_sse.c:786-792` (`I686_OP_SFENCE`).
  - **What breaks / Why**: `i686_emit_begin` zeroes `e->tso` and nothing ever sets `e->tso = true` when threads are spawned; `SFENCE` is also emitted as a no-op. Multi-threaded guest code runs with weak AArch64 memory ordering instead of x86 TSO (`LDAR`/`STLR` / `DMB`).
  - **Fix**: Enable `e->tso` (and flush single-threaded translations) as soon as a second thread is created, and emit `dmb ishst` / `dmb ish` for `SFENCE` / `MFENCE`.

- [x] **I686-5 — High — BUG — Flag elimination crosses faulting instructions**
  - **Where**: `src/dbt/translate.c:98-105`, `src/dbt/translate.c:160-182`, `src/dbt/translate.c:239-260` (`tr_classify`, skip analysis); `src/dbt/emit_alu.c:258-264`, `src/dbt/emit_alu.c:379-408`.
  - **What breaks / Why**: Dead-flag elimination treats memory `MOV` instructions as flag-transparent and elides flag computation before a memory access if a subsequent instruction overwrites flags. If the `MOV` faults, the guest `SIGSEGV` `ucontext` receives stale `EFLAGS`.
  - **Fix**: Treat any potentially faulting memory or division instruction as a flag-observation barrier during dead-flag analysis.

- [x] **I686-6 — High — BUG — Translation pre-scan faults on instructions that will not execute**
  - **Where**: `src/dbt/translate.c:224-238` (`i686_dbt_translate` pre-scan); `src/x86/decode.c:76-80` (`fetch8`).
  - **What breaks / Why**: The pre-scan loop decodes up to 64 instructions without stopping at unconditional control-flow terminators (`RET`, `JMP`, `INT`). Decoding past a terminator at the end of a page can fault on an unmapped following page.
  - **Fix**: Stop the pre-scan loop at basic-block terminators and page boundaries.

- [x] **I686-7 — High — BUG — Moving or growing mremap loses backing-object semantics**
  - **Where**: `src/rt32/rt32_vm.c:1079-1081`, `src/rt32/rt32_vm.c:1102-1107`, `src/rt32/rt32_vm.c:1141-1162` (`rt32_vm_mremap`).
  - **What breaks / Why**: `rt32_vm_mremap` allocates anonymous mappings for extensions and moves regardless of the original file/shared backing.
  - **Fix**: Preserve file backing, offset, and `MAP_SHARED` identity across `mremap` extensions and moves.

- [x] **I686-8 — High — BUG — Default-action pending signals are silently discarded**
  - **Where**: `src/os/signals_i386.c:823-852` (`i686_deliver_pending`).
  - **What breaks / Why**: Unblocked pending signals whose handler is `SIG_DFL` (`0`) take the same bit-clearing branch as `SIG_IGN`, silently dropping fatal or stop signals.
  - **Fix**: Implement the Linux default-action table (`Term`, `Core`, `Stop`, `Ign`, `Cont`) when delivering unblocked `SIG_DFL` signals.

- [x] **I686-9 — Medium — BUG — SSE double arithmetic ignores guest rounding mode**
  - **Where**: `src/interp/h_sse.c:405-458` (`sse_f64_op`).
  - **What breaks / Why**: `ADDSD`/`SUBSD`/`MULSD`/`DIVSD`/`ADDPD` etc. execute host `double` arithmetic without applying `MXCSR.RC`.
  - **Fix**: Apply the guest `MXCSR` rounding mode (`fesetround` or FPCR rounding control) around SSE FP operations.

- [x] **I686-10 — Medium — BUG — Signal frames export binary64 storage as x87 extended precision**
  - **Where**: `src/i686rt.h:144-146` (`x87_st` representation contract); `src/os/signals_i386.c:159-171` (`i686_sigframe_build`).
  - **What breaks / Why**: In default binary64 x87 mode, `i686_sigframe_build` raw-copies 10 bytes from each slot into the 80-bit `_fpstate` register array without converting `double` to 80-bit IEEE extended precision.
  - **Fix**: Convert binary64 `x87_st` values to/from 80-bit `fp80` when constructing and restoring signal frames.

- [x] **I686-11 — Medium — DEFECT — Linux JIT mappings remain writable and executable**
  - **Where**: `src/dbt/engine.c:656-704` (`dbt_get_or_compile`).
  - **What breaks / Why**: On Linux, the JIT code buffer is mapped `PROT_READ | PROT_WRITE | PROT_EXEC` and never sealed `PROT_READ | PROT_EXEC`, violating the `AGENTS.md` §2.2 W^X invariant.
  - **Fix**: Emit into RW staging or toggle W^X (`PROT_READ | PROT_WRITE` -> `PROT_READ | PROT_EXEC`) on Linux as well as Darwin.

### 2.2 Curated C11 & UB Issues

- [x] **I686-12 — High — C11 — Fault recovery unlocks a mutex without proving ownership**
  - **Where**: `src/dbt/engine.c:44-51` (`s_jit_toggle_mutex`); `src/dbt/engine.c:744-762` (`i686_dbt_run` fault recovery).
  - **What breaks / Why**: On `sigsetjmp` recovery from any guest fault on Darwin, `i686_dbt_run` calls `pthread_mutex_unlock(&s_jit_toggle_mutex)` even when the fault occurred during normal JIT execution with the mutex unlocked. Unlocking an unowned/unlocked default mutex is C11/POSIX UB.
  - **Fix**: Track lock ownership in a `_Thread_local` flag and only unlock `s_jit_toggle_mutex` if the current thread holds it.

- [x] **I686-13 — High — C11 — Global fault-site cursor races between translators**
  - **Where**: `src/dbt/emit_mov.c:91-127` (`s_pc_ctx`, `s_pc_base`, `s_pc_buf`, `s_pc_cur`, `site_pc`).
  - **What breaks / Why**: `site_pc` mutates four static non-atomic globals during translation without a lock on Linux, racing across threads and corrupting fault-recovery PC metadata.
  - **Fix**: Use `e->insn_pc` directly from the per-translation `i686_emit_t` struct and delete the static globals.

- [x] **I686-14 — Medium — C11 — Signal tracing dereferences byte arrays through uint32_t pointers**
  - **Where**: `src/os/signals_i386.c:293-318` (`i686_sigframe_build`).
  - **What breaks / Why**: Casts `uint8_t tcbdump[16]` to `const uint32_t *`, violating strict aliasing and alignment rules.
  - **Fix**: Read words via `memcpy` into `uint32_t` locals.

### 2.3 DRY, YAGNI & CLEAN

- [x] **I686-15 — Low — DRY — Host-page-size discovery is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:71-81`; `src/os/backend_darwin.c:56-66` (`rt_host_page_size`).
  - **What breaks / Why**: Identical `sysconf(_SC_PAGESIZE)` caching helper duplicated in both backend files.
  - **Fix**: Share a single internal helper within `i686rt`.

- [x] **I686-16 — Low — YAGNI — Allocated Soft-TLB has no production fill integration**
  - **Where**: `src/vm/vm32.c:58-75` (`i686_vm32_init`); `src/vm/vm32.c:91-120` (`i686_vm32_tlb_fill`); `src/trampoline.S:47-48` (`i686_jit_run_block`).
  - **What breaks / Why**: `i686_vm32_init` allocates a Soft-TLB, but `i686_vm32_tlb_fill` has no production callers and `trampoline.S` loads `guest_base` into `x20`.
  - **Fix**: Wire the Soft-TLB into A2 memory emission and miss handling (fixing `I686-1`), or remove the dead allocation until wired.

- [x] **I686-17 — Medium — CLEAN — Twenty-three files exceed the 900-line limit**
  - **Where**: 14 runtime files (`src/interp/x87_80.c` 2971, `src/interp/h_x87.c` 2276, `src/interp/h_sse.c` 2156, `src/os/sys_pass.c` 2108, `src/os/sys_misc.c` 1249, `src/rt32/rt32_a64_emit.c` 1235, `src/os/sys_sock.c` 1216, `src/rt32/rt32_vm.c` 1182, `src/os/sys_ipc.c` 1170, `src/os/sys_time.c` 1080, `src/interp/v86.c` 975, `src/x86/insn_tab.h` 960, `src/os/syscalls_i386.h` 951, `src/dbt/engine.c` 930) and 9 test files (`tests/probe_strfuncs.c` 1473, `tests/unit/test_l5d.c` 1301, `tests/unit/test_l1d.c` 1271, `tests/unit/test_l1e.c` 1083, `tests/test_p1_isa.c` 1039, `tests/unit/test_l5c.c` 998, `tests/unit/test_l1b.c` 966, `tests/unit/test_l5b.c` 957, `tests/unit/test_l5a.c` 938); `Makefile:238-262`.
  - **What breaks / Why**: 23 files exceed the mandatory 900-line ceiling because `Makefile` only checks a subset of files.
  - **Fix**: Split all 23 files into separately compiled `<900`-line translation units and enforce a repo-wide `check-line-limits` gate.

- [x] **I686-18 — Low — CLEAN — Default test target reports obsolete phase-zero status**
  - **Where**: `Makefile:91-97` (`test`, `test-p0-lima`).
  - **What breaks / Why**: `make test` prints `"phase 0: no tests yet"` and exits 0 without running any tests.
  - **Fix**: Wire `make test` to the active unit/parity test suite.

- [x] **I686-19 — Low — CLEAN — A2 VM documentation describes a different execution path**
  - **Where**: `src/vm/vm32.c:14-21`; `src/i686rt.h:64-67`; `src/trampoline.S:47-48`.
  - **What breaks / Why**: Comments claim `x20` holds the Soft-TLB base on A2 and emits a 7-instruction probe, contradicting `trampoline.S`.
  - **Fix**: Keep comments synchronized with the actual `x20` / Soft-TLB implementation.

- [x] **I686-20 — Low — CLEAN — Pending-signal documentation contradicts its clearing behavior**
  - **Where**: `src/os/signals_i386.c:814-844` (`i686_deliver_pending`).
  - **What breaks / Why**: Comment claims `SIG_DFL`/`SIG_IGN` bits survive polling while the code clears them.
  - **Fix**: Update the comment alongside fixing `I686-8`.

---

### R1-3. `mips32rt` (`e0b10a2` → `366ca9b`) — 20 / 20 Resolved

### 3.1 Bugs & Defects

- [x] **M32-1 — High — BUG — FP branch fault handling overwrites the delivered signal handler PC**
  - **Where**: `src/interp/fp.c:829-843` (`fp_bc1`); `src/os/signals.c:673-682` (`mips_raise_guest_code`).
  - **What breaks / Why**: When a delay-slot instruction under `BC1T`/`BC1F` faults and synchronously delivers a guest signal handler (which sets `ctx->pc` to the handler), `fp_bc1` overwrites `ctx->pc` with `branch_pc`, retrying the branch instead of running the signal handler.
  - **Fix**: Set delay-slot state before fetching the slot and preserve `ctx->pc` when a guest signal handler has been delivered.

- [x] **M32-2 — High — BUG — Failed execve destroys the calling program**
  - **Where**: `src/os/proc.c:384-412` (`mips_proc_execve`).
  - **What breaks / Why**: `rt32_vm_reset_for_exec` destroys the old guest address space before validating the ELF header, loading `PT_INTERP`, or allocating the new stack. Any subsequent error returns `-errno` into an empty address space.
  - **Fix**: Validate the target ELF and `PT_INTERP` headers before resetting the caller's VM.

- [x] **M32-3 — High — BUG — Darwin sub-page MAP_SHARED mappings lose sharing**
  - **Where**: `src/rt32/vm_mmap.c:96-126` (`vm_mmap2_locked`).
  - **What breaks / Why**: Mappings not aligned to 16 KiB fall back to `mprotect` + `memset` + `pread` into anonymous arena memory even when `MAP_SHARED` is set, losing writeback and alias coherence; negative `pread` errors are also ignored.
  - **Fix**: Provide shared sub-page backing or reject unsupported unaligned `MAP_SHARED` file mappings explicitly, and propagate `pread` errors.

- [x] **M32-4 — High — BUG — mremap replaces file-backed memory with anonymous storage**
  - **Where**: `src/rt32/vm_mmap.c:310-338`, `src/rt32/vm_mmap.c:372-393` (`rt32_vm_mremap`).
  - **What breaks / Why**: Both in-place growth and relocation create anonymous mappings, losing file backing and `MAP_SHARED` coherence.
  - **Fix**: Preserve file descriptor/inode backing and offsets across `mremap`.

- [x] **M32-5 — High — BUG — Translation invalidation misses sibling threads**
  - **Where**: `src/dbt/dbt.c:100-105`, `src/dbt/dbt.c:328-394`, `src/dbt/dbt.c:428-435` (`dbt_cache`, `dbt_smc_bump`, `mips32_dbt_invalidate_range`, `dbt_lookup_bi`).
  - **What breaks / Why**: `dbt_cache` and SMC page versions are `_Thread_local`. An SMC write or `munmap`/`mprotect` in one thread never invalidates translations cached in sibling threads.
  - **Fix**: Store per-page SMC/code generation counters in shared VM state so all threads observe invalidations immediately.

- [x] **M32-6 — High — BUG — Full SMC table silently drops invalidations**
  - **Where**: `src/dbt/dbt.c:328-359` (`dbt_smc_bump`); `src/dbt/dbt.c:374-394` (`mips32_dbt_invalidate_range`).
  - **What breaks / Why**: When all slots in the fixed-size SMC table are occupied, `dbt_smc_bump` returns without bumping the version or flushing the cache, leaving stale code executable.
  - **Fix**: Flush the code cache and reset the SMC table whenever the SMC table reaches capacity.

- [x] **M32-7 — High — BUG — Region-table exhaustion changes permissions outside the requested range**
  - **Where**: `src/rt32/vm.c:269-295` (`vm_mprotect_regions_locked`); `src/rt32/vm_mmap.c:200-210` (`vm_mprotect_locked`).
  - **What breaks / Why**: If splitting a region fails due to table capacity, the fallback overwrites `prot` on the entire unsplit VMA while host `mprotect` only updated the requested sub-range.
  - **Fix**: Pre-check free VMA slots before mutating host protections and return `-ENOMEM` if the split cannot be recorded.

- [x] **M32-8 — High — BUG — Blocked signals are delivered immediately**
  - **Where**: `src/os/signals.c:386-444` (`mips_l4a_rt_sigprocmask`); `src/os/kill.c:151-178` (`mips_sc_kill`).
  - **What breaks / Why**: `mips_sc_kill` delivers self-signals immediately without checking the blocked signal mask recorded by `rt_sigprocmask`.
  - **Fix**: Record blocked signals as pending and deliver them only when unmasked.

- [x] **M32-9 — High — BUG — CLONE_VM children retain stale mapping metadata**
  - **Where**: `src/os/threads.c:315-329` (`mips_sc_clone`); `src/rt32/vm.c:107-126` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`); `src/os/syscalls.c:116-132` (`mips_sc_range_ok`).
  - **What breaks / Why**: `mips_sc_clone` copies the VMA region snapshot into `child`, and subsequent `mmap`/`munmap`/`mprotect` calls only update the calling context and `g_root_ctx`, leaving sibling threads with stale VMA tables.
  - **Fix**: Validate ranges against the authoritative shared VM table under the VM lock (or synchronize generation-stamped snapshots).

- [x] **M32-10 — Medium — BUG — Integer branch-likely fetches an annulled delay slot**
  - **Where**: `src/interp/interp.c:775-789` (`exec_branch`); `src/dbt/dbt.c:609-612` (`dbt_compile`).
  - **What breaks / Why**: A not-taken branch-likely (`BEQL`, `BNEL`, etc.) still fetches `pc + 4` before annulling it, which can fault if the annulled delay slot lies on an unmapped next page.
  - **Fix**: Advance directly to `pc + 8` when a branch-likely condition is false without fetching `pc + 4`.

- [x] **M32-11 — Medium — BUG — Default signal handling treats stop and ignore actions as process exit**
  - **Where**: `src/os/kill.c:70-80` (`kill_die`), `src/os/kill.c:147-155` (`mips_sc_kill`).
  - **What breaks / Why**: Unhandled signals (including default-ignore signals like `SIGCHLD`/`SIGURG`/`SIGWINCH`) call `kill_die`, which exits with `_Exit(128 + signo)`.
  - **Fix**: Implement the MIPS Linux default-action table (`Ign`, `Stop`, `Cont`, `Term`, `Core`).

### 3.2 Curated C11 & UB Issues

- [x] **M32-12 — High — C11 — Signal state has unsynchronized cross-thread access**
  - **Where**: `src/os/signals.c:123-129`, `src/os/signals.c:342-378`, `src/os/signals.c:655-666`, `src/os/signals.c:732-773`.
  - **What breaks / Why**: Signal masks, frame addresses, and nesting depth (`g_depth`) are unsynchronized process globals shared across threads (C11 data race and cross-thread `sigreturn` frame corruption).
  - **Fix**: Move signal mask and frame stack/depth into per-thread `mips32_ctx_t` and protect the shared `sigaction` table with a mutex.

- [x] **M32-13 — High — C11 — Guest copy helpers race VM changes and can crash the host**
  - **Where**: `src/os/syscalls.c:136-155` (`mips_sc_copy_from`, `mips_sc_copy_to`); `src/rt32/vm.c:113-125` (`vm_copy_state_to_ctx`); `src/os/hostfault.c:104-110` (`hf_handler`).
  - **What breaks / Why**: Copy helpers read unsynchronized per-context region arrays and call `memcpy` without holding the VM lock or registering fault recovery.
  - **Fix**: Synchronize VM validation/copy helpers and guard guest memory copies with fault recovery.

- [x] **M32-14 — Medium — C11 — Fault-PC range check compares unrelated pointers**
  - **Where**: `src/os/hostfault.c:106-108` (`hf_handler`).
  - **What breaks / Why**: `pc < hf_pool` uses relational `<` on pointers from unrelated mappings (C11 UB).
  - **Fix**: Cast both `pc` and `hf_pool` to `uintptr_t` before comparing.

### 3.3 DRY, YAGNI & CLEAN

- [x] **M32-15 — Medium — DRY — Guest range validation is independently copied across syscall modules**
  - **Where**: `src/os/syscalls.c:102-133` (`mips_sc_range_ok`); `src/os/proc.c:91-124` (`proc_range_ok`); `src/os/signals.c:172-205` (`l4a_range_ok`).
  - **What breaks / Why**: Three copy-pasted implementations of the VMA region walk with subtly different null/zero-length checks.
  - **Fix**: Unify into a single `mips32rt`-internal VM range validation helper.

- [x] **M32-16 — Low — DRY — Host backends duplicate identical POSIX wrappers**
  - **Where**: `src/os/backend_linux.c:348-420`; `src/os/backend_darwin.c:338-410`.
  - **What breaks / Why**: Identical `close`/`read`/`write`/`pread`/`pwrite`/`lseek`/`ftruncate` wrappers duplicated across both backend files.
  - **Fix**: Move common POSIX fd wrappers into a shared internal file within `mips32rt`.

- [x] **M32-17 — Medium — YAGNI — File-family tracking consumes resources without enforcing its advertised coherence**
  - **Where**: `src/vm/vm_file.c:55-73`, `src/vm/vm_file.c:110-129`, `src/vm/vm_file.c:175-228`.
  - **What breaks / Why**: `dup`s file descriptors into a static table without a close path and defines `mips32_file_check_truncate` with zero callers.
  - **Fix**: Wire file-truncate invalidation into the VM lifecycle and close retained fds on unmap, or remove the dead tracking code.

- [x] **M32-18 — Low — YAGNI — Unused branch classifier suppresses its own warning**
  - **Where**: `src/dbt/dbt.c:146-163` (`dbt_is_likely`).
  - **What breaks / Why**: Unused `__attribute__((unused))` static function duplicating branch-likely decoding.
  - **Fix**: Delete `dbt_is_likely`.

- [x] **M32-19 — Medium — CLEAN — Two test sources violate the line limit and evade its check**
  - **Where**: `tests/test_p1_isa.c:1-1030`; `tests/test_p3_fpu.c:1-1164`; `Makefile:89-96` (`check-line-limits`).
  - **What breaks / Why**: `test_p1_isa.c` (`1,030` lines) and `test_p3_fpu.c` (`1,164` lines) exceed 900 lines; `check-line-limits` only scans `src/` and `include/`.
  - **Fix**: Split both test files below 900 lines and include `tests/` in `check-line-limits`.

- [x] **M32-20 — Low — CLEAN — Default build flags omit required global Werror**
  - **Where**: `Makefile:21` (`CFLAGS`); `Makefile:44` (`DARWIN_CFLAGS`).
  - **What breaks / Why**: Includes `-Werror=vla` but omits `-Werror`.
  - **Fix**: Add `-Werror` to `CFLAGS` and `DARWIN_CFLAGS`.

---

### R1-4. `ppc32rt` (`3582753` → `abe6b0b`) — 15 / 15 Resolved

### 4.1 Bugs & Defects

- [x] **P32-1 — High — BUG — Overflow-enabled arithmetic instructions fail decoding**
  - **Where**: `src/interp/decode.c:325-335`, `src/interp/decode.c:444-446`, `src/interp/decode.c:559-561` (`ppc_decode`).
  - **What breaks / Why**: `ppc_decode` extracts the 10-bit `XO` (`bits 21..30`, which includes `OE` at bit 21) for opcode 31 and switches on all 10 bits, but XO-form arithmetic cases (`add`, `subf`, `neg`, `mullw`, `divw`, `divwu`) only list `OE=0` constants. Any `OE=1` instruction (`addo`, `subfo`, `nego`, `mullwo`, `divwo`, `divwuo`) falls through to `PPC32_OP_UNDEF` in both interp and DBT.
  - **Fix**: Mask out the `OE` bit (`xo & 0x1ffU`) when matching XO-form arithmetic instructions while setting `d->oe = (xo & 0x200U) != 0`.

- [x] **P32-2 — High — BUG — DBT traps combine predicates incorrectly**
  - **Where**: `src/dbt/emit_int.c:541-579` (`ei_trap`).
  - **What breaks / Why**: For each enabled `TO` bit in `tw`/`twi`, `ei_trap` emits a conditional branch that skips the trap when that single condition is false. Thus the trap only fires when **all** enabled `TO` bits hold simultaneously instead of **any** enabled bit (e.g., `twnei` with `TO=24` never traps because `<` and `>` cannot both be true), and signed `<` uses `A64_CC_PL` instead of `A64_CC_LT`.
  - **Fix**: Emit positive conditional branches (`A64_CC_LT`, `A64_CC_GT`, `A64_CC_EQ`, `A64_CC_CC`, `A64_CC_HI`) to a shared trap-taken label when any enabled `TO` bit matches.

- [x] **P32-3 — High — BUG — Memory barriers are discarded**
  - **Where**: `src/interp/decode.c:519-521`, `src/interp/decode.c:540-545` (`ppc_decode`); `src/interp/interp.c:844-848` (`interp_step`); `src/dbt/emit_int.c:856-858` (`ppc32_emit_int`).
  - **What breaks / Why**: `sync`/`lwsync` and `eieio` decode to `PPC32_OP_SYNC`, which both the interpreter and DBT treat as a no-op instead of emitting a memory barrier (`__atomic_thread_fence` / `dmb ish`).
  - **Fix**: Emit `dmb ish` in DBT and `__atomic_thread_fence(__ATOMIC_SEQ_CST)` in the interpreter for `PPC32_OP_SYNC`.

- [x] **P32-4 — High — BUG — Atomic accesses bypass A2 guest permissions**
  - **Where**: `src/interp/interp.c:36-47` (`vm32_sc_attempt`), `src/interp/interp.c:796-815` (`LWARX`/`STWCX`); `src/dbt/emit_int.c:605-611`, `src/dbt/emit_int.c:642-659` (`ei_lwarx`, `ei_stwcx`).
  - **What breaks / Why**: `LWARX`/`STWCX` form raw `guest_base + ea` pointers and execute host atomics without consulting the A2 Soft-TLB or COW page table, bypassing 4 KiB sub-page `PROT_NONE`/`PROT_READ` protections on 16 KiB Darwin hosts.
  - **Fix**: Validate guest page read/write permissions (and trigger COW if needed) before performing the host atomic operation.

- [x] **P32-5 — High — BUG — mremap replaces file backing with anonymous memory**
  - **Where**: `src/rt32/ppc32_vm.c:678-679`, `src/rt32/ppc32_vm.c:701-706`, `src/rt32/ppc32_vm.c:740-765` (`ppc32_vm_mremap`).
  - **What breaks / Why**: Both extension and relocation force `PPC32_MAP_ANONYMOUS`, severing `MAP_SHARED` and file-backed mappings from their underlying file.
  - **Fix**: Preserve file backing, offset, and sharing flags across `ppc32_vm_mremap`.

- [x] **P32-6 — High — BUG — Invalid futex timeout pointers can crash the translator**
  - **Where**: `src/os/threads.c:52-85` (`thread_range_ok`, `thread_ld32be`); `src/os/threads.c:274-284` (`futex_get_timeout`); `src/main.c:437-448` (`ppc32_run_guest_child`).
  - **What breaks / Why**: `thread_range_ok` checks only arithmetic address bounds (`< 4 GiB`), not whether the guest page is mapped and readable. Dereferencing an unmapped timeout pointer in `futex_get_timeout` crashes the translator in host C code instead of returning `-EFAULT`.
  - **Fix**: Validate timeout pointers against the VM mapping table with `PROT_READ` before reading.

- [x] **P32-7 — Medium — BUG — neg corrupts XER.CA in both engines**
  - **Where**: `src/interp/interp.c:246-257` (`interp_step`, `NEG`); `src/dbt/emit_int.c:166-170` (`ei_addsub_xo`).
  - **What breaks / Why**: Both interpreter and DBT update `XER.CA` during `neg`/`neg.`, whereas PowerPC `neg` does not affect `XER.CA`.
  - **Fix**: Remove the `XER.CA` update from `PPC32_OP_NEG` in both `interp.c` and `emit_int.c`.

- [x] **P32-8 — Medium — BUG — Futex requeue count is passed in the wrong argument**
  - **Where**: `src/os/threads.c:255-264` (`futex_host`); `src/os/threads.c:341-346` (`ppc32_futex`).
  - **What breaks / Why**: `FUTEX_REQUEUE` and `FUTEX_CMP_REQUEUE` pass `NULL` as the 4th argument (`val2` / `nr_requeue`) to `futex_host`, causing the kernel to always requeue 0 waiters.
  - **Fix**: Pass `(const struct timespec *)(uintptr_t)val2` as the 4th syscall argument for `REQUEUE` and `CMP_REQUEUE`.

- [x] **P32-9 — Medium — DEFECT — pthread failures are reported using unrelated errno**
  - **Where**: `src/os/backend_linux.c:605-609`, `src/os/backend_darwin.c:801-805` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:399-407` (`rt_host_preempt_worker`).
  - **What breaks / Why**: `pthread_create` and `pthread_kill` return their error code directly without setting `errno`, but the wrappers return `-errno` (which may be `0`).
  - **Fix**: Capture `int rc = pthread_create(...)` / `pthread_kill(...)` and return `-rc`.

### 4.2 Curated C11 & UB Issues

- [x] **P32-10 — High — C11 — Reservation metadata has unsynchronized shared accesses**
  - **Where**: `src/interp/interp.c:24-26`, `src/interp/interp.c:43-51`, `src/interp/interp.c:804-806` (`g_ll_table`, `vm32_sc_attempt`, `LWARX`).
  - **What breaks / Why**: Non-atomic fields (`owner`, `addr`, `val`, `snap`, `gensnap`) in shared `g_ll_table` are read and written concurrently by multiple threads without a lock (C11 data race).
  - **Fix**: Store per-thread reservation state in `ppc32_ctx_t` and synchronize shared cacheline generation counters atomically.

- [x] **P32-11 — Medium — C11 — Signed offset construction left-shifts negative values**
  - **Where**: `src/os/syscalls.c:710-712` (`ppc32_syscall`, `PREAD64`).
  - **What breaks / Why**: `((int64_t)(int32_t)a3 << 32)` left-shifts a negative signed value when `a3` has bit 31 set (C11 UB).
  - **Fix**: Use `(int64_t)(((uint64_t)a3 << 32) | (uint64_t)a4)`.

### 4.3 DRY, YAGNI & CLEAN

- [x] **P32-12 — Low — DRY — Worker-spawn plumbing is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:575-615`, `src/os/backend_darwin.c:771-811` (`spawn_slot_t`, `spawn_tramp`, `rt_host_spawn_worker`).
  - **What breaks / Why**: Duplicated worker-spawn trampoline and slot management in both backend files (both sharing bug `P32-9`).
  - **Fix**: Extract common worker-spawn logic into a shared internal file within `ppc32rt`.

- [x] **P32-13 — Low — YAGNI — Signal installation API is unwired scaffolding that reports success**
  - **Where**: `src/os/backend_darwin.c:875-890` (`rt_host_install_signal_handlers`).
  - **What breaks / Why**: Discards all three callback arguments, sets `SIG_IGN`, and returns `0` with no callers in `src/`.
  - **Fix**: Wire to `hostfault.c` or remove the unused stub.

- [x] **P32-14 — Low — CLEAN — Core files have effectively exhausted the line budget**
  - **Where**: `src/interp/interp.c:1-900`, `src/interp/fp.h:1-899`, `src/os/syscalls.c:1-898`, `src/os/backend_darwin.c:1-895`.
  - **What breaks / Why**: Four core files are at `895–900` lines, leaving zero headroom for bug fixes.
  - **Fix**: Split cohesive sub-units into separate `.c` files when applying the fixes above.

- [x] **P32-15 — Low — CLEAN — Execution comments contradict current behavior**
  - **Where**: `src/interp/interp.h:38-42`, `src/interp/interp.c:837-843`, `src/dbt/dbt.c:17-21`, `src/dbt/dbt.c:44-45`.
  - **What breaks / Why**: Header comments state `interp_step` advances `NIP` on `sc`, whereas `interp.c` leaves `NIP` at `sc` for the caller to advance; `dbt.c` comments still describe native emission as future work.
  - **Fix**: Update the comments to match the actual `sc` NIP convention and active DBT emitter architecture.

---

### R1-5. `sparc32rt` (`816cc90` → `dad95da`) — 18 / 18 Resolved

### 5.1 Bugs & Defects

- [x] **S32-1 — High — BUG — Syscall pointer checks accept inaccessible guest memory**
  - **Where**: `src/os/l2a_access.h:49-69` (`l2a_range_ok`, `l2a_store`); `src/os/futex.c:269-277` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: `l2a_range_ok` checks only arithmetic bounds (`addr >= 0x1000`), not whether the guest pages are mapped with required permissions. Unmapped syscall buffer/timeout pointers fault the translator in host `memcpy` instead of returning `-EFAULT`, and bypass A2 sub-page permissions on Darwin.
  - **Fix**: Validate every covered guest page against the VM permission/mapping table in `l2a_range_ok` / copyin / copyout helpers.

- [x] **S32-2 — High — BUG — Failed execve changes the running process**
  - **Where**: `src/os/threads_exec.c:137-161` (`sparc32_thr_execve`).
  - **What breaks / Why**: Signal dispositions and the VM are reset before validating the pathname pointer or opening/validating the new ELF image, and all loader errors are collapsed to `-ENOENT`.
  - **Fix**: Copy in arguments and validate/open the target ELF before resetting signal dispositions and the guest VM, and return the actual loader errno.

- [x] **S32-3 — High — BUG — LDSTUB retains a process-wide lock across guest execution**
  - **Where**: `src/dbt/aot/aot_atomic.h:89-117` (`sparc32_atomic_ldstub`); `src/interp/interp_mem.c:109-115` (`interp_mem_wr`).
  - **What breaks / Why**: When `LDSTUB` reads `0x00`, it keeps `g_sparc32_ldstub_lock.owner` held across subsequent guest instructions until the owning thread stores to that address. Any other thread executing `LDSTUB` on an **unrelated** address spins waiting for `owner` to clear, causing cross-lock deadlocks.
  - **Fix**: Execute `LDSTUB` as a single atomic byte exchange (`__atomic_exchange_n(ptr, 0xffU, __ATOMIC_SEQ_CST)`) and release any helper lock immediately before returning.

- [x] **S32-4 — High — BUG — Guest stores do not invalidate translated code**
  - **Where**: `src/interp/interp_mem.c:96-117` (`interp_mem_wr`); `src/dbt/aot/aot_atomic.h:124-161` (`sparc32_atomic_swap`, `sparc32_atomic_casa`); `src/dbt/emit_priv.h:423-455` (`sparc32_rt_mem`); `src/dbt/dbt.c:469-488` (`dbt_lookup`).
  - **What breaks / Why**: Interpreter stores, DBT slow-path stores, and atomic writes modify guest memory without invalidating cached DBT blocks covering that page (`dbt_lookup` does not verify source instruction words either).
  - **Fix**: Call `sparc32_dbt_invalidate_range` (or bump per-page SMC generation tags) on stores to pages containing translated blocks.

- [x] **S32-5 — High — BUG — A clone thread can unmap code executing in its parent**
  - **Where**: `src/dbt/dbt.c:114-121` (`dbt_arena_reset`), `src/dbt/dbt.c:491-517` (`dbt_flush`, `sparc32_dbt_invalidate_range`); `src/rt32/vm_mmap.c:311-327` (`rt32_vm_munmap`); `src/os/threads.c:410-443` (`thr_thread_entry`).
  - **What breaks / Why**: `sparc32_dbt_invalidate_range` calls `dbt_flush`, which immediately `munmap`s the global JIT code arena. If a cloned thread calls `munmap` or `mprotect` while the parent thread is executing inside the JIT code arena, the parent faults on unmapped host instructions.
  - **Fix**: Quiesce executing threads before unmapping/resetting the shared JIT arena or defer arena reclamation until no thread is inside JIT code.

- [x] **S32-6 — High — BUG — Timed futex waits and wakes use different queues on AArch64 Linux**
  - **Where**: `src/os/futex.c:235-300` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: On AArch64 Linux (`__NR_futex_time64` is not defined because 64-bit Linux `__NR_futex` already uses 64-bit `timespec`), `sparc32_l2a_futex_time64` falls back to the user-space pthread condvar emulator while `FUTEX_WAKE` uses kernel `SYS_futex`, so timed waiters are never woken by `FUTEX_WAKE`.
  - **Fix**: Use kernel `SYS_futex` with a native 64-bit `struct timespec` on 64-bit Linux hosts.

- [x] **S32-7 — High — BUG — mremap loses file backing and shared-map identity**
  - **Where**: `src/rt32/vm_mmap.c:372-374`, `src/rt32/vm_mmap.c:395-417`, `src/rt32/vm_mmap.c:438-463` (`rt32_vm_mremap`).
  - **What breaks / Why**: `rt32_vm_mremap` creates anonymous mappings for growth and relocation, losing file backing and `MAP_SHARED` alias coherence.
  - **Fix**: Preserve file backing, offset, and `MAP_SHARED` state across `rt32_vm_mremap`.

- [x] **S32-8 — High — BUG — Darwin subpage file mappings silently discard MAP_SHARED semantics**
  - **Where**: `src/os/backend_darwin.c:307-349` (`rt_host_map_file`).
  - **What breaks / Why**: Unaligned fixed file mappings on Darwin fall back to `mprotect` + `memset` + `pread` into anonymous arena memory even when `shared` is true.
  - **Fix**: Provide coherent shared sub-page backing or reject unsupported unaligned `MAP_SHARED` file mappings explicitly.

- [x] **S32-9 — Medium — BUG — Signal frames omit mask preservation and restoration**
  - **Where**: `src/interp/interp_signal.c:202-208`, `src/interp/interp_signal.c:337-343`; `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Signal delivery writes `0` to the saved mask words in the frame, and `sparc32_sys_rt_sigreturn` never restores the signal mask from the frame.
  - **Fix**: Save the pre-delivery signal mask into the signal frame and restore it in `sigreturn` / `rt_sigreturn`.

- [x] **S32-10 — Medium — BUG — Signal FPU state is hidden outside the guest ABI frame**
  - **Where**: `src/interp/interp_signal.c:66-67`, `src/interp/interp_signal.c:208-210`; `src/os/syscalls_sig.c:329-330`, `src/os/syscalls_sig.c:360-361`.
  - **What breaks / Why**: FPU state is saved in a translator-private array with `fpu_save = 0` in the guest frame, and `rt_sigreturn` rejects any non-zero `fpu_save` pointer.
  - **Fix**: Serialize the SPARC32 FPU save area onto the guest signal stack when used and restore from it on `sigreturn`.

- [x] **S32-11 — Medium — BUG — Clone threads misclassify doubleword alignment faults**
  - **Where**: `src/os/threads.c:421-428` (`thr_thread_entry`); `src/interp/interp.c:449-474`.
  - **What breaks / Why**: `thr_thread_entry` checks `(fault_addr & 3U) != 0U` for `SIGBUS`, misclassifying 4-byte-aligned (but not 8-byte-aligned) `LDD`/`STD` faults as `SIGSEGV` instead of `SIGBUS`.
  - **Fix**: Share the instruction-aware `SIGBUS`/`SIGSEGV` classifier from `src/main.c:237-244`.

### 5.2 Curated C11 & UB Issues

- [x] **S32-12 — High — C11 — Signed shifts make normal branch and division decoding undefined**
  - **Where**: `src/interp/decode.c:343-364` (`sparc32_decode_word`); `src/interp/interp.c:275`, `src/interp/interp.c:304` (signed dividend construction).
  - **What breaks / Why**: Left-shifting negative sign-extended `int32_t` branch displacements (`disp << 2`) and negative `%y` (`(int64_t)(int32_t)y << 32`) invokes C11 signed left-shift UB.
  - **Fix**: Left-shift as unsigned (`(uint32_t)` / `(uint64_t)`) before casting to signed.

- [x] **S32-13 — Medium — C11 — Futex timeout saturation still permits signed overflow**
  - **Where**: `src/os/futex.c:113-123` (`sparc32_futex_wait_emu`).
  - **What breaks / Why**: Adding `now` to a capped `int64_t` relative timeout up to `9e18` ns can overflow `INT64_MAX`.
  - **Fix**: Clamp `rel_ns` against `INT64_MAX - now_ns` before adding.

### 5.3 DRY, YAGNI & CLEAN

- [x] **S32-14 — Low — DRY — Signal-return functions duplicate register restoration**
  - **Where**: `src/os/syscalls_sig.c:263-312` (`sparc32_sys_sigreturn`); `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Both functions duplicate register window, PSR, PC/nPC, and FPU restoration logic.
  - **Fix**: Extract a common frame-restore helper inside `src/os/syscalls_sig.c`.

- [x] **S32-15 — Medium — YAGNI — Soft-TLB miss machinery is disconnected from production callers**
  - **Where**: `src/vm/vm32.c:87-101` (`t_tlb`, `vm32_tlb_reset_thread`), `src/vm/vm32.c:268-336` (`vm_tlb_miss_helper`), `src/vm/vm32.c:339-364` (`vm32_tlb_invalidate`).
  - **What breaks / Why**: `vm_tlb_miss_helper` has no callers in `src/`; active execution uses the protection table directly.
  - **Fix**: Either wire `vm_tlb_miss_helper` into the DBT fast path or remove the unused `t_tlb` scaffolding.

- [x] **S32-16 — Low — CLEAN — Memory-access comments contradict current alignment handling**
  - **Where**: `src/interp/interp_mem.c:67-72`; `src/interp/interp_signal.c:20-33`.
  - **What breaks / Why**: Comments state `LDD`/`STD` 8-byte alignment is an unimplemented Phase-3 gap, contradicting `interp.c:449-474`.
  - **Fix**: Update the stale comments to reflect current alignment trap behavior.

- [x] **S32-17 — Low — CLEAN — Default build flags omit the required general warning gate**
  - **Where**: `Makefile:29-33` (`CFLAGS`).
  - **What breaks / Why**: Includes `-Werror=vla` but omits `-Werror`.
  - **Fix**: Add `-Werror` to `CFLAGS`.

- [x] **S32-18 — Low — CLEAN — Three core files have almost no line-limit headroom**
  - **Where**: `src/dbt/dbt.c:1-888`, `src/os/threads.c:1-883`, `src/dbt/emit_int.c:1-882`.
  - **What breaks / Why**: Within 12–18 lines of the 900-line ceiling.
  - **Fix**: Extract cohesive helpers into separate `.c` files when modifying these modules.

---

### R1-6. `rvrt` (`29ce5fd` → `8e207fb`) — 10 / 10 Resolved

### 6.1 Bugs & Defects

- [x] **RV-1 — High — BUG — FP load miss loses previously dirty guest registers**
  - **Where**: `src/darwin_dbt.c:312-346`, `src/darwin_dbt.c:364-389` (`emit_inline_load`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: In `emit_inline_load`, the Soft-TLB miss branch is emitted *before* the FP register-cache eviction spill, and the fast path then updates the slot's guest FP register identity and clears its dirty bit at compile time. When the cold miss path is emitted afterward, `emit_flush_fp_cache` uses the *post-load* compile-time cache metadata even though runtime execution jumped over the fast-path spill. If `f0` was dirty in slot 0 and `fld f16, ...` misses the Soft-TLB (both map to slot `0`), the dirty value of `f0` is never written back and is silently lost.
  - **Fix**: Snapshot pre-instruction FP/GPR cache metadata before the fast path mutates it (or emit the dirty-slot eviction spill before the TLB miss branch) so the cold miss path flushes the actual live pre-load register state.

- [x] **RV-2 — Medium — BUG — pthread failures can be reported as success**
  - **Where**: `src/os/backend_linux.c:274-279`, `src/os/backend_darwin.c:351-356` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:302-309` (`rt_host_preempt_worker`).
  - **What breaks / Why**: `pthread_create` and `pthread_kill` return an error number directly without setting `errno`, but these wrappers discard the return value and return `-errno` (which is `0` if `errno` was clear).
  - **Fix**: Capture `int rc = pthread_create(...)` / `pthread_kill(...)` and return `-rc`.

- [x] **RV-3 — Medium — DEFECT — Failed writable transitions leave code caches reusable**
  - **Where**: `src/dbt/cache.c:299-312` (`rv_dbt_invalidate`), `src/dbt/cache.c:82-85` (`rv_dbt_publish`); `src/os/backend_linux.c:153-160` (`rt_host_jit_begin_write`).
  - **What breaks / Why**: `rv_dbt_invalidate` ignores `mprotect(..., PROT_READ | PROT_WRITE)` errors and resets `used = 0`. A subsequent `rv_dbt_publish` then `memcpy`s into memory that may still be `PROT_READ | PROT_EXEC`, crashing the host process.
  - **Fix**: Check and propagate `mprotect` / `rt_host_jit_begin_write` failures before resetting `used` or writing to the code arena.

- [x] **RV-4 — Medium — BUG — TLB refill can pair an old read tag with a new host address**
  - **Where**: `src/darwin_dbt.c:102-125` (`tlb_fill_page`), `src/darwin_dbt.c:296-300` (`emit_tlb_lookup`).
  - **What breaks / Why**: When refilling a Soft-TLB slot for a write-only page (`PROT_WRITE` without `PROT_READ`), `tlb_fill_page` updates `entry->addend` and `entry->write_tag` without invalidating `entry->read_tag`. If a previously cached readable page A collides with write-only page B in the 4096-entry table, a subsequent load from page A matches A's stale `read_tag` and uses B's `addend`.
  - **Fix**: Unconditionally invalidate both `read_tag` and `write_tag` (`~0ULL`) before writing `entry->addend` and installing the permitted tag(s).

### 6.2 Curated C11 & UB Issues

- [x] **RV-5 — Medium — C11 — File-offset reconstruction can overflow signed `off_t`**
  - **Where**: `src/os/backend_linux.c:66-77` (`rt_host_map_file`).
  - **What breaks / Why**: `(off_t)(aligned_file_offset >> 12) * (off_t)4096` overflows signed 64-bit `off_t` when bit 63 of `aligned_file_offset` is set.
  - **Fix**: Validate `(aligned_file_offset & 0xfffULL) == 0ULL && aligned_file_offset <= (uint64_t)INT64_MAX` and cast `(off_t)aligned_file_offset` directly.

- [x] **RV-6 — Low — C11 — Test argument parsing uses prohibited `atoi`**
  - **Where**: `test/test_family_leave.c:90-92` (`notify_fd` parsing); `test/test_family_backing.c:39` (`pin_sender` / `pin_receiver` parsing).
  - **What breaks / Why**: Uses banned `atoi` without error checking.
  - **Fix**: Replace with `strtol` and range validation.

### 6.3 DRY, YAGNI & CLEAN

- [x] **RV-7 — Low — DRY — Worker startup protocol is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:233-300`, `src/os/backend_darwin.c:312-377` (`spawn_context_t`, `spawn_trampoline`, `rt_host_spawn_worker`).
  - **What breaks / Why**: Both backends duplicate the ready-pipe handshake, thread detach, and TID read loop (both sharing bug `RV-2`).
  - **Fix**: Consolidate the worker-spawn handshake into an internal module within `rvrt`.

- [x] **RV-8 — Low — YAGNI — Return-address stack has no production consumer**
  - **Where**: `src/dbt/cache.c:223-240` (`rv_dbt_ras_push`, `rv_dbt_ras_pop`); `src/dbt/cache.h:83-84`.
  - **What breaks / Why**: Only called in `test/u5b_dbt_cache.c`; no production DBT execution path uses it.
  - **Fix**: Wire into DBT call/return dispatch or remove the unused API.

- [x] **RV-9 — Medium — CLEAN — Tests extensively use prohibited textual implementation includes**
  - **Where**: `test/test_linux_memory_alloc.c:42-54`, `test/test_mm_remap.c:38-47`, `test/test_runtime_file_exec_codec.c:11` (and other `test/*.c` files).
  - **What breaks / Why**: Tests textually `#include "../src/.../*.c"` implementation files (requiring macro renames like `#define valid_range ...` to avoid static symbol collisions).
  - **Fix**: Compile production `.c` files separately and expose narrow internal headers for unit testing.

- [x] **RV-10 — Medium — CLEAN — Twenty-nine source files exceed the 900-line ceiling**
  - **Where**: 17 production files under `src/` (`runtime_main.c` 8201, `runtime/family.c` 4641, `runtime/guest_memory.c` 2574, `runtime/native_signal.c` 1894, `runtime/file_caps.c` 1851, `linux/file.c` 1531, `memory/file_backing.c` 1518, `memory/space.c` 1484, `runtime/mm_view.c` 1372, `linux/fd.c` 1338, `runtime/scheduler.c` 1100, `darwin_dbt.c` 1061, `runtime/family_file_recovery.c` 988, `runtime/exec_state.c` 982, `linux/futex.c` 978, `runtime/process_children.c` 938, `linux/signal.c` 909), 9 test files under `test/` (`test_linux_file.c` 1426, `r6_inherited_children.c` 1304, `test_family_file_attributed.c` 1293, `r5_exec.c` 1212, `test_linux_file_workers.c` 1133, `test_file_caps.c` 1022, `test_family_file_recovery.c` 984, `test_family.c` 970, `test_linux_signal.c` 954), and 3 vendored files under `vendor/`.
  - **What breaks / Why**: 26 first-party `.c` files exceed the mandatory 900-line ceiling.
  - **Fix**: Split all 26 first-party files into separately compiled `<900`-line translation units and add a `check-line-limits` target to `Makefile` (with explicit exclusion for `vendor/`).

---

### R1-7. `loongarch64rt` (`0f57c40` → `026e87d`) — 13 / 13 Resolved

### 7.1 Bugs & Defects

- [x] **LA64-1 — High — BUG — Instruction fetch ignores guest execute permission**
  - **Where**: `src/interp/interp.c:71-79` (`interp_step`); `src/dbt/dbt.c:370-389` (`translate_block`); `src/os/mem_min.c:274-305` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:46-67` (`vm64_ptr`).
  - **What breaks / Why**: Both interpreter and DBT fetch guest instructions via `la64_mem_ptr(pc, 4, 0)`, which checks `PROT_READ` instead of `PROT_EXEC`. Non-executable `PROT_READ` data pages can be executed as code, while `PROT_EXEC`-only pages fail instruction fetch.
  - **Fix**: Add an instruction-fetch access mode that checks `PROT_EXEC` and invalidate DBT translations when `mprotect` removes `PROT_EXEC`.

- [x] **LA64-2 — High — BUG — Mixed guest protections can leave a Darwin host page inaccessible**
  - **Where**: `src/os/mem_min.c:150-173` (`protect_host_page`), `src/os/mem_min.c:478-519` (`la64_mem_protect`).
  - **What breaks / Why**: When 4 KiB guest sub-pages sharing a 16 KiB Darwin host page have differing protections, `protect_host_page` returns early without calling host `mprotect`. If a 16 KiB range was first marked `PROT_READ` (or `PROT_NONE`) and one 4 KiB sub-page is then restored to `PROT_READ | PROT_WRITE`, the host page stays `PROT_READ` (or `PROT_NONE`), causing valid guest accesses to fault in the translator.
  - **Fix**: Set the 16 KiB host page protection to the union of its live 4 KiB sub-pages while enforcing sub-page permissions in software/Soft-TLB tags.

- [x] **LA64-3 — High — BUG — Vector memory faults terminate the translator**
  - **Where**: `src/interp/interp_vec.c:83-110` (`interp_step_vec`); `src/interp/interp.c:817-848` (`interp_step`); `src/interp/interp_mem.h:29-35` (`die_at`).
  - **What breaks / Why**: Faulting LSX/LASX vector loads/stores return an error string that `interp_step` passes to `die_at`, which calls `exit(3)` instead of raising a guest `SIGSEGV`, and partial bytes are written to the destination vector register before later bytes are validated.
  - **Fix**: Stage vector load bytes into a temporary buffer, validate the entire span before committing to `vr[vd]`, and route faults through the guest `SIGSEGV` delivery path.

- [x] **LA64-4 — High — BUG — Bootstrap LSX instructions retain stale LASX upper halves**
  - **Where**: `src/interp/interp_vec.c:83-93`, `src/interp/interp_vec.c:114-188` (`interp_step_vec`); `src/interp/interp.c:817-833` (`interp_step`).
  - **What breaks / Why**: The bootstrap LSX handler in `interp_vec.c` (`VLD`, broadcasts, shuffles, `VOR.V`, shifts) writes only `vr[rd][0..1]` without zeroing `vr[rd][2..3]`, violating the LoongArch64 LSX upper-128-bit zeroing contract.
  - **Fix**: Zero `vr[rd][2]` and `vr[rd][3]` after every LSX instruction that writes a vector register.

- [x] **LA64-5 — High — DEFECT — Difftest does not compare DBT register or PC state**
  - **Where**: `src/main.c:302-382` (`diff_child_verify`); `src/main.c:579-639` (`run_difftest`).
  - **What breaks / Why**: `run_difftest` compares DBT vs interpreter only on process exit status and stdout; `diff_child_verify` then replays `interp_step` against a second `interp_step` trace instead of stepping the DBT engine, yet prints `difftest: 0 divergences`.
  - **Fix**: Step the DBT single-block/single-instruction engine against `interp_step` and compare architectural GPR/FPR/FCC/FCSR/PC state at each boundary.

- [x] **LA64-6 — Medium — BUG — Darwin directory enumeration loses unread entries**
  - **Where**: `src/os/syscalls_file.c:173-210` (`sys_getdents64`).
  - **What breaks / Why**: Each `sys_getdents64` call on Darwin `dup`s the fd, calls `fdopendir`, reads entries until the guest buffer is full, and `closedir`s the stream. Both the uncopied overflow entry and any entries pre-buffered by `fdopendir` into libc's internal buffer are lost on the next `getdents64` call.
  - **Fix**: Use `seekdir`/`telldir` with a retained `DIR *` per open directory fd (or `getdirentries` / ` lseek` to the exact offset of the last emitted entry).

- [x] **LA64-7 — Medium — BUG — Mprotect succeeds across unmapped holes**
  - **Where**: `src/os/mem_min.c:478-522` (`la64_mem_protect`); `src/os/syscalls_mem.c:424-434` (`sys_mprotect_range`).
  - **What breaks / Why**: `la64_mem_protect` sets `covered = 1` as soon as *any* sub-region overlaps `[addr, addr + len)` and returns `0` even if part of `[addr, addr + len)` is unmapped, instead of returning `-ENOMEM`.
  - **Fix**: Verify contiguous VMA coverage across the entire `[addr, addr + len)` interval before returning success.

- [x] **LA64-8 — Medium — BUG — Write validation incorrectly requires read permission**
  - **Where**: `src/os/mem_min.c:299-304` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:62-65` (`vm64_ptr`).
  - **What breaks / Why**: Both helpers check `(r->prot & PROT_READ) == 0` unconditionally even for write accesses (`write == 1`), rejecting valid guest stores into write-only (`PROT_WRITE`) mappings.
  - **Fix**: Check `PROT_WRITE` for writes, `PROT_READ` for reads, and `PROT_EXEC` for instruction fetches.

### 7.2 Curated C11 & UB Issues

- [x] **LA64-9 — Medium — C11 — Negative vector offsets invoke signed left-shift UB**
  - **Where**: `src/interp/fp_shuf.c:113-118` (`vec_mem_step`).
  - **What breaks / Why**: `((int32_t)si12 << 20) >> 20` left-shifts a signed `int32_t` into bit 31 when `si12 >= 0x800` (negative 12-bit offset), which is C11 UB.
  - **Fix**: Sign-extend via `(int64_t)(int32_t)((uint32_t)si12 << 20) >> 20`.

### 7.3 DRY, YAGNI & CLEAN

- [x] **LA64-10 — Low — DRY — JIT memory lifecycle is implemented twice**
  - **Where**: `src/dbt/dbt_code.c:55-104` (`dbt_alloc_rw`, `dbt_seal_page`); `src/os/backend_linux.c:288-326` and `src/os/backend_darwin.c:200-264` (`rt_host_jit_*`).
  - **What breaks / Why**: `dbt_code.c` duplicates platform `mmap`/`mprotect`/`pthread_jit_write_protect_np`/`sys_icache_invalidate` logic already implemented in `rt_host_jit_*`.
  - **Fix**: Route `dbt_code.c` through `rt_host_jit_*`.

- [x] **LA64-11 — Low — YAGNI — Return-address stack is populated but never consumed**
  - **Where**: `src/dbt/dbt_chain.c:23-24`, `src/dbt/dbt_chain.c:51-62` (`chain_ras`, `dbt_ras_push`, `dbt_ras_pop`); `src/dbt/dbt.c:728-735` (`dbt_run`).
  - **What breaks / Why**: `dbt_ras_push` is called on block exits, but `dbt_ras_pop` has zero callers in the repository.
  - **Fix**: Wire RAS prediction into `JR $ra` return dispatch or delete the dead RAS array/functions.

- [x] **LA64-12 — Medium — CLEAN — Textual C includes bypass module boundaries**
  - **Where**: `src/interp/interp.c:40-56`, `src/os/syscalls.c:41-100`, `src/os/minsys.c:23`, `src/os/clone.c:217-218`, `src/main.c:20`.
  - **What breaks / Why**: Production `.c` files textually `#include` other `.c` files (`decode.c`, `fp.c`, `syscalls_*.c`, etc.), violating the no-unity-includes rule.
  - **Fix**: Compile each `.c` file as an independent translation unit in `Makefile` with proper internal headers.

- [x] **LA64-13 — Low — CLEAN — File-size gate excludes an oversized test**
  - **Where**: `tests/test_p3_fp_simd.c:1-940`; `Makefile:156-163` (`check-line-limits`).
  - **What breaks / Why**: `tests/test_p3_fp_simd.c` is 940 lines (`> 900`), and four `src/` files (`emit_int.c` 899, `a64_emit.c` 898, `fp.c` 895, `emit_fp.c` 890) have almost no headroom.
  - **Fix**: Split `tests/test_p3_fp_simd.c` below 900 lines and include `tests/` in `check-line-limits`.

---

### R1-8. `ppc64rt` (`f42cf1a` → `bd3e73f`) — 16 / 16 Resolved

### 8.1 Bugs & Defects

- [x] **P64-1 — High — BUG — Guest LL/SC bypasses the atomic memory interface**
  - **Where**: `src/interp/interp.c:25-38`, `src/interp/interp.c:537-557` (`g_res_valid`, `lwarx`/`ldarx`/`stwcx.`/`stdcx.`).
  - **What breaks / Why**: `lwarx`/`ldarx` performs an ordinary `mem->read` and stores the reservation in process-global `g_res_valid`/`g_res_addr`; `stwcx.`/`stdcx.` checks those globals and calls `mem->write`, never invoking `mem->atomic` or invalidating reservations on normal stores. Concurrent threads also race on the globals.
  - **Fix**: Make reservation tracking per-thread/worker, invalidate reservations on all guest/DBT/syscall stores, and perform atomic CAS via the fixed width-accurate `vm_mem_atomic` (`P64-11`).

- [x] **P64-2 — High — DEFECT — Clone executes the child to completion before returning to the parent**
  - **Where**: `src/os/syscalls_p4.c:104-139`, `src/os/syscalls_p4.c:159-184` (`syscall_clone_child_run`, `syscall_p4_clone`); `src/os/syscalls.c:570-579`.
  - **What breaks / Why**: `syscall_p4_clone` synchronously runs the child in an inline interpreter loop to completion before returning the child TID to the parent. Any child thread that waits on the parent deadlocks immediately.
  - **Fix**: Spawn a host worker thread (or preemptive/cooperative green-thread scheduler) so parent and child execute concurrently.

- [x] **P64-3 — High — DEFECT — Futex WAIT always returns EAGAIN and WAKE never wakes**
  - **Where**: `src/os/syscalls_p4.c:188-214` (`syscall_p4_futex`); `src/os/syscalls.c:585-590`.
  - **What breaks / Why**: `FUTEX_WAIT` unconditionally returns `-EAGAIN` even when `*uaddr == val`, and `FUTEX_WAKE` unconditionally returns `0`.
  - **Fix**: Route `syscall_p4_futex` to the real futex wait/wake backend (`rt_host_futex_wait_bitset` / `rt_host_futex_wake_bitset` or waiter table).

- [x] **P64-4 — High — BUG — Querying sigaction destroys the disposition and never returns the old action**
  - **Where**: `src/run/sigdeliver.c:54-84` (`run_sig_record`).
  - **What breaks / Why**: When `act == NULL` (a query), `run_sig_record` zeroes the signal's disposition instead of preserving it, and it completely ignores `args[2]` (`oldact`), never writing back the previous `struct sigaction`.
  - **Fix**: Copy out the previous `sigaction` to `oldact` when non-NULL, and only modify the stored disposition when `act != NULL` (rejecting `SIGKILL`/`SIGSTOP`).

- [x] **P64-5 — High — BUG — Signal delivery and sigprocmask maintain disconnected masks**
  - **Where**: `src/run/sigdeliver.c:33-44`, `src/run/sigdeliver.c:160-202` (`run_sig_blocked`, `run_deliver`); `src/os/syscalls_conv.c:818-845` (`x_sigprocmask`); `src/run/core.c:453-460`.
  - **What breaks / Why**: `rt_sigprocmask` updates `x_sigmask`, while signal delivery reads/saves `run_sig_blocked` (which is always `0`), does not mask the delivered signal or `sa_mask` on handler entry, and `rt_sigreturn` fails to restore the saved mask.
  - **Fix**: Unify `x_sigmask` and `run_sig_blocked` into a single per-thread signal mask, apply `sa_mask` + the delivered signal during handler entry, and restore the saved mask on `rt_sigreturn`.

- [x] **P64-6 — Medium — BUG — kill/tgkill mishandles probes, ignored signals, and syscall return state**
  - **Where**: `src/run/core.c:428-451`; `src/run/sigdeliver.c:79-83`, `src/run/sigdeliver.c:195-199`.
  - **What breaks / Why**: `sig == 0` is rejected instead of probing existence; sending a signal with `SIG_DFL` returns `-ESRCH`; `SIG_IGN` (`1`) is treated as a function pointer at guest address `0x1`; and synchronous self-delivery saves the pre-syscall `r3` instead of the `0` syscall return value in the signal frame.
  - **Fix**: Handle `sig == 0`, `SIG_IGN`, and `SIG_DFL` properly, and commit the `0` syscall return value + `NIP += 4` before constructing the signal frame on self-signaling `kill`/`tgkill`.

- [x] **P64-7 — Medium — BUG — Fixed mremap silently ignores the requested destination for equal-size and shrinking moves**
  - **Where**: `src/os/syscalls_mm.c:729-755` (`syscall_mm_mremap`).
  - **What breaks / Why**: Equal-size (`new_len == old_len`) and shrinking (`new_len < old_len`) calls return `old_addr` before checking `MREMAP_FIXED`, ignoring the requested relocation to `new_addr`.
  - **Fix**: Bypass the in-place equal/shrink fast paths whenever `MREMAP_FIXED` is set.

- [x] **P64-8 — High — BUG — Failed fixed mremap destroys the previous destination mapping**
  - **Where**: `src/os/syscalls_mm.c:777-802` (`syscall_mm_mremap`).
  - **What breaks / Why**: `syscall_mm_mremap` unmaps `new_addr` before inserting/copying the moved mapping; if insertion or copying fails, the error path unmaps `new_addr` again without restoring whatever mapping previously lived at `new_addr`.
  - **Fix**: Validate and stage the relocation before unmapping the destination, or snapshot and restore overwritten destination mappings on failure.

- [x] **P64-9 — Medium — BUG — mremap copies through guest read permissions**
  - **Where**: `src/os/syscalls_mm.c:687-707`, `src/os/syscalls_mm.c:767-789` (`syscall_mremap_transfer`, `syscall_mm_mremap`).
  - **What breaks / Why**: `syscall_mremap_transfer` reads the source range using `PPC64_ACCESS_LOAD`, failing with `-EFAULT` if a `PROT_NONE` or write-only mapping is moved with `mremap`.
  - **Fix**: Copy backing pages using an internal VM transfer helper that does not require guest `PROT_READ`.

- [x] **P64-10 — Medium — BUG — nanosleep writes remaining time through the wrong argument**
  - **Where**: `src/os/syscalls_conv.c:734-758` (`x_nanosleep`).
  - **What breaks / Why**: On `EINTR`, `x_nanosleep` copies the remaining `timespec` to `args[2]` instead of `args[1]` (`rem`).
  - **Fix**: Copy the remainder to `args[1]`.

### 8.2 Curated C11 & UB Issues

- [x] **P64-11 — Medium — C11 — Narrow VM atomics perform unaligned and out-of-range 64-bit accesses**
  - **Where**: `src/vm/vm_atomic.c:180-216`, `src/vm/vm_atomic.c:225-241` (`vm_mem_atomic`).
  - **What breaks / Why**: Casts the host pointer to `uint64_t *` and performs 8-byte `__atomic_load_n` / `__atomic_compare_exchange_n` even when `width` is 1, 2, or 4. A 4-byte atomic at page offset `4092` is only 4-byte aligned and crosses the end of the 4 KiB page.
  - **Fix**: Dispatch width-specific (`uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`) atomic operations.

- [x] **P64-12 — Low — C11 — Image descriptor parsing uses banned atoi**
  - **Where**: `src/main.c:91-100` (`main`, `--image-fd` parsing).
  - **What breaks / Why**: Uses banned `atoi` to parse `--image-fd`.
  - **Fix**: Replace with `strtol` and range validation.

### 8.3 DRY, YAGNI & CLEAN

- [x] **P64-13 — Low — DRY — Syscall return convention is implemented independently in two runners**
  - **Where**: `src/run/core.c:52-82` (`run_is_scv`, `run_apply_sc`); `src/os/syscalls_p4.c:78-101` (`syscall_child_apply`).
  - **What breaks / Why**: Duplicated `sc`/`scv` `r3` and `CR0.SO` return-value application in `core.c` and `syscalls_p4.c`.
  - **Fix**: Share one internal helper within `ppc64rt`.

- [x] **P64-14 — Low — YAGNI — Unused conditional-store API reports success without storing**
  - **Where**: `src/vm/vm_atomic.c:281-291` (`ppc64_vm_conditional`); `src/vm/vm.h:127-128`.
  - **What breaks / Why**: `ppc64_vm_conditional` ignores `val`, performs no store, and has no callers in `src/`.
  - **Fix**: Delete `ppc64_vm_conditional`.

- [x] **P64-15 — Low — CLEAN — Current specifications mix obsolete paths with unrelated ISA concepts**
  - **Where**: `SPEC.md:30-36`, `SPEC.md:78`, `SPEC.md:93`; `GOAL.md:36-43`.
  - **What breaks / Why**: Mentions obsolete `src/rt64/` paths and SPARC/MIPS concepts (delay slots, register windows) in `ppc64rt`'s repo-local `SPEC.md`/`GOAL.md`.
  - **Fix**: Update `ppc64rt/SPEC.md` and `ppc64rt/GOAL.md` to reflect PowerPC64 ELFv2 and the current `src/vm/`, `src/os/`, `src/run/` layout.

- [x] **P64-16 — Low — CLEAN — Repository-wide line ceiling is not enforced by the source-only gate**
  - **Where**: `Makefile:52-60` (`check-line-limits`); `src/interp/interp.c` (`900`), `src/interp/decode.c` (`900`), `src/os/syscalls_conv.c` (`893`), `src/dbt/emit_int.c` (`888`).
  - **What breaks / Why**: `interp.c` and `decode.c` sit at exactly 900 lines with zero headroom; `check-line-limits` only scans `src/`.
  - **Fix**: Split `interp.c` and `decode.c` when modifying them, and extend `check-line-limits` to `tests/` (excluding `vendor/`).

---

### R1-9. `mips64rt` (`8d5950c` → `32d5c9e`) — 18 / 18 Resolved

### 9.1 Bugs & Defects

- [x] **M64-1 — High — BUG — ELF segment rounding can wrap before bounds validation**
  - **Where**: `src/loader.c:432-444`, `src/loader.c:467-488` (`PT_LOAD` mapping and initialization).
  - **What breaks / Why**: `bias + ph.vaddr` and `ph.memsz + page_off + 4095` are computed before overflow checks. If `ph.memsz + page_off + 4095` wraps `uint64_t` to a small value (e.g. `4096`), the bounds check passes on the wrapped length while `memset` uses the huge unrounded `ph.memsz - ph.filesz`, overflowing the host mapping.
  - **Fix**: Validate `ph.vaddr`, `ph.filesz`, `ph.memsz`, `bias`, and page-rounding additions against unsigned overflow before mapping or zero-filling.

- [x] **M64-2 — High — BUG — Write-only TLB entries use a zero host-address addend**
  - **Where**: `src/os/backend_linux.c:251-264`, `src/os/backend_darwin.c:254-267` (`mips_soft_tlb_fill`); `src/dbt/emit_mem.c:193-202` (`ei_probe_open`).
  - **What breaks / Why**: In `mips_soft_tlb_fill`, `addend` is only set when `mips_mem_ok(ctx, page_va, 1, 0)` (read permission) succeeds; otherwise `addend = 0`. However, `write_tag` is set whenever `mips_mem_ok(ctx, page_va, 1, 1)` (write permission) succeeds. For a write-only guest page (`PROT_WRITE`), the DBT fast-path store matches `write_tag` and adds `addend = 0`, storing to the raw guest VA in host memory!
  - **Fix**: Populate `addend = (uintptr_t)host_page - (uintptr_t)page_va` whenever either `can_read` or `can_write` is true.

- [x] **M64-3 — High — BUG — LL/SC implements value comparison instead of reservation invalidation**
  - **Where**: `src/interp/unaligned.c:269-284`, `src/interp/unaligned.c:305-337`, `src/interp/unaligned.c:342-389` (`do_ll`, `do_sc`, `do_lld`, `do_scd`).
  - **What breaks / Why**: `SC`/`SCD` succeeds whenever the current memory word equals `ctx->llval` without tracking intervening stores (classic ABA bug), and ordinary stores do not acquire `g_sc_lock` or invalidate reservations.
  - **Fix**: Maintain atomic per-cacheline reservation epochs bumped by all guest stores, and validate the epoch atomically during `SC`/`SCD`.

- [x] **M64-4 — High — BUG — Instruction exceptions are delivered as SIGSEGV**
  - **Where**: `src/interp/interp.c:22-31` (`fault_at`), `src/interp/interp.c:188-189` (`BREAK`), `src/interp/interp.c:282-295` (overflow), `src/interp/interp.c:381-382` (unrecognized instruction); `src/os/mem.c:69-85` (`mips_fault`).
  - **What breaks / Why**: `fault_at` calls `mips_fault`, which unconditionally raises signal `11` (`SIGSEGV`). Thus `BREAK` (`SIGTRAP`), `ADD`/`SUB`/`DADD` signed overflow (`SIGFPE`), and illegal instructions (`SIGILL`) all deliver `SIGSEGV` instead of their architectural signals.
  - **Fix**: Pass an explicit signal number (`SIGTRAP`, `SIGFPE`, `SIGILL`, `SIGBUS`, `SIGSEGV`) from the interpreter/DBT trap site to `mips_trap`.

- [x] **M64-5 — High — BUG — Sign-extended LO corrupts MADD/MSUB accumulation**
  - **Where**: `src/interp/interp.c:395-428` (`exec_special2`); `src/dbt/emit_alu.c:414-419` (`ei_special2`).
  - **What breaks / Why**: In the interpreter, `MADD`/`MADDU`/`MSUB`/`MSUBU` construct the 64-bit accumulator as `(hi << 32) | lo` without masking `lo` to 32 bits (`(uint32_t)lo`). Because `LO` holds a sign-extended 32-bit value in MIPS64, a negative `LO` (`0xffffffff80000000`) bitwise-ORs `0xffffffff` into the upper 32 bits (`HI`), corrupting `HI` and diverging from the DBT.
  - **Fix**: Construct the accumulator as `((uint64_t)(uint32_t)ctx->hi << 32) | (uint64_t)(uint32_t)ctx->lo` in all four `MADD`/`MADDU`/`MSUB`/`MSUBU` handlers.

- [x] **M64-6 — High — BUG — Thread-directed signals reject valid worker TIDs**
  - **Where**: `src/os/sigact.c:676-699` (`l4a_tkill`); `src/os/threads.c:180-199`, `src/os/threads.c:312-322`.
  - **What breaks / Why**: `l4a_tkill` rejects any `tid != getpid()` with `-ESRCH`, even though cloned threads publish their distinct host TID (`SYS_gettid`). Thus `pthread_kill` or `raise()` inside a worker thread fails with `-ESRCH`.
  - **Fix**: Look up `tid` in the active guest thread table and deliver/queue the signal to that thread's context.

- [x] **M64-7 — Medium — BUG — Backend context slots are never released**
  - **Where**: `src/os/backend_linux.c:28-39`, `src/os/backend_linux.c:82-109`; `src/os/backend_darwin.c:31-42`, `src/os/backend_darwin.c:85-112`; `src/os/threads.c:424-437` (`u0_slot_for`, `mips_thread_exit`).
  - **What breaks / Why**: `u0_slot_for` has only 16 fixed slots and never frees a slot when a thread exits in `mips_thread_exit`. After 16 threads, subsequent threads silently fail to allocate a backend slot.
  - **Fix**: Release the thread's backend slot in `mips_thread_exit` and increase the table size to match the 128-thread limit.

- [x] **M64-8 — Medium — BUG — A valid DSRA32 encoding is treated as a breakpoint**
  - **Where**: `src/interp/interp.c:375-379` (`exec_special`); `src/dbt/emit_alu.c:382-392` (`ei_special`).
  - **What breaks / Why**: `SPECIAL` function `0x3f` with `rt=0, rd=0, sa=0` (`0x0000003f`) is `DSRA32 $zero, $zero, 0`, a valid no-op, but both engines treat it as `SDBBP` and trap (`SDBBP` is in `SPECIAL2`, not `SPECIAL`).
  - **Fix**: Remove the `0x3f` `SDBBP` trap from `SPECIAL` (`exec_special` and `ei_special`), keeping `SDBBP` solely under `SPECIAL2`.

- [x] **M64-9 — Medium — DEFECT — Interpreter FP exception enables are ignored**
  - **Where**: `src/interp/fp.c:135-144` (`fp_raise`).
  - **What breaks / Why**: `fp_raise` sets `FCSR` cause and sticky flags without checking `FCSR` enable bits `[11:7]` or delivering `SIGFPE`.
  - **Fix**: Check `FCSR` enable bits in `fp_raise` and trigger a `SIGFPE` guest trap when an enabled FP exception fires.

- [x] **M64-10 — Medium — BUG — Integer-to-FP conversions omit inexact exceptions**
  - **Where**: `src/interp/fp_cvt.c:170-204` (`fp_cvt_wl`).
  - **What breaks / Why**: `CVT.S.W`, `CVT.S.L`, and `CVT.D.L` do not check whether the converted float/double round-trips back to the exact integer, omitting `FCSR` inexact flags.
  - **Fix**: Compare the round-tripped integer value against the source operand and call `fp_raise(ctx, FP_X_I)` when they differ.

- [x] **M64-11 — Medium — DEFECT — Code-arena allocation grows without reclamation**
  - **Where**: `src/dbt/arena.c:7-18`, `src/dbt/arena.c:42-80` (`arena_retain`, `dbt_arena_alloc`).
  - **What breaks / Why**: Exhausted JIT code chunks are retired into `arena_maps[]` and never unmapped or reused.
  - **Fix**: Reclaim retired arena chunks at a safe quiescence/flush point.

- [x] **M64-12 — Medium — DEFECT — Cloned threads always run the interpreter**
  - **Where**: `src/os/threads.c:170-205` (`l4b_entry`).
  - **What breaks / Why**: `l4b_entry` unconditionally calls `interp_run(child)` even when the process was launched in `--dbt` mode.
  - **Fix**: Dispatch `child` through the active engine (`dbt_run` when DBT is enabled, `interp_run` otherwise).

### 9.2 Curated C11 & UB Issues

- [x] **M64-13 — High — C11 — FP conversion validates the source instead of the rounded result**
  - **Where**: `src/interp/fp_cvt.c:67-84` (`fp_to_int`).
  - **What breaks / Why**: `fp_to_int` checks bounds on the unrounded input `q` (`q < 2147483648.0`) and then casts the *rounded* value `t` (`(int32_t)t`). For `CEIL.W.D` on `2147483647.5`, `q` passes the check, `t` rounds to `2147483648.0`, and `(int32_t)t` invokes C11 float-to-int overflow UB.
  - **Fix**: Check the bounds of the rounded value `t` (`t >= -2147483648.0 && t < 2147483648.0`) before casting `t` to `int32_t` / `int64_t`.

- [x] **M64-14 — High — C11 — Signed MADD/MSUB accumulation can overflow**
  - **Where**: `src/interp/interp.c:396-401`, `src/interp/interp.c:415-420` (`exec_special2`).
  - **What breaks / Why**: `MADD` and `MSUB` perform `int64_t` `+=` / `-=` which overflows signed `int64_t` (C11 UB).
  - **Fix**: Perform the 64-bit accumulator addition/subtraction in `uint64_t`.

### 9.3 DRY, YAGNI & CLEAN

- [x] **M64-15 — Low — DRY — Linux and Darwin duplicate the backend state registry**
  - **Where**: `src/os/backend_linux.c:28-328`; `src/os/backend_darwin.c:31-331` (`u0_slot_for`, FIXADE state, delay targets, soft-TLB management).
  - **What breaks / Why**: ~300 lines of host-independent slot/TLB state management are copy-pasted between `backend_linux.c` and `backend_darwin.c` (both sharing bugs `M64-2` and `M64-7`).
  - **Fix**: Extract the shared state registry and Soft-TLB fill logic into a common internal file within `mips64rt`.

- [x] **M64-16 — Low — YAGNI — Arena retention array is write-only bookkeeping**
  - **Where**: `src/dbt/arena.c:42-57`, `src/dbt/arena.c:74` (`arena_maps`, `arena_nmaps`, `arena_retain`).
  - **What breaks / Why**: `arena_maps` is written by `arena_retain` and never read anywhere in `src/`.
  - **Fix**: Use `arena_maps` to `munmap` retired chunks (`M64-11`) or remove the write-only array.

- [x] **M64-17 — Medium — CLEAN — Production and test code use textual C unity includes**
  - **Where**: `src/os/syscalls.c:32-36` (`#include "proc.c"`); `tests/check_host_contract.c:37-43`.
  - **What breaks / Why**: `src/os/syscalls.c` textually includes `proc.c`, and `tests/check_host_contract.c` textually includes seven `src/` `.c` files.
  - **Fix**: Compile `src/os/proc.c` and the test dependencies as separate `.o` files in `Makefile`.

- [x] **M64-18 — Low — CLEAN — A test exceeds 900 lines and the gate excludes tests**
  - **Where**: `tests/test_p1_isa.c:1-902`; `Makefile:215-222` (`check-line-limits`).
  - **What breaks / Why**: `tests/test_p1_isa.c` is 902 lines (`> 900`), and four `src/` files (`mem_table.c` 899, `interp.c` 897, `syscalls.c` 896, `emit_mem.c` 895) are within 5 lines of the ceiling.
  - **Fix**: Trim/split `tests/test_p1_isa.c` below 900 lines and include `tests/` in `check-line-limits`.

---

### R1-10. `sparc64rt` (`71fe7a5` → `3ead4f9`) — 14 / 14 Resolved

### 10.1 Bugs & Defects

- [x] **S64-1 — High — BUG — CPU initialization leaves half the FP register file unchanged**
  - **Where**: `src/core/cpu.h:137-141,202-218` (`sparc64_ctx_init`); `src/os/guest_run.c:450-465,549-550,683-688` (initial execution and exec reset).
  - **What breaks / Why**: The SPARC V9 FP register file union is 256 bytes (`32 × 64-bit` doubles `d[0..31]`, or `f[0..31]` covering only the first 128 bytes), but `sparc64_ctx_init` and `execve` reset only zero `f[0..31]` (`128` bytes), leaving `d[16..31]` (`%d32..%d62`) uninitialized or retaining pre-`execve` register values.
  - **Fix**: Zero all 32 double registers (`d[0..31]` / `memset(&ctx->fp, 0, sizeof(ctx->fp))`) in `sparc64_ctx_init` and `execve` reset.

- [x] **S64-2 — High — BUG — Failed RX publication does not prevent JIT execution**
  - **Where**: `src/dbt/dbt.c:228-242` (`dbt_publish`), `src/dbt/dbt.c:820-824` (`sparc64_dbt_run`).
  - **What breaks / Why**: `dbt_publish` ignores failure from `a32h_wx_publish` and returns; `sparc64_dbt_run` then jumps into `b->host_code` while the arena page is still non-executable (`PROT_READ | PROT_WRITE`).
  - **Fix**: Have `dbt_publish` return `bool` and fall back to the interpreter if RX publication fails.

- [x] **S64-3 — Medium — BUG — Floating-condition MOVcc encodings become no-op barriers**
  - **Where**: `src/interp/interp.c:239-257` (`sparc64_decode_op2`); `src/dbt/emit_int.c:596-598` (`sparc64_emit_int`).
  - **What breaks / Why**: In SPARC V9 `MOVcc` (`op3 = 0x2c`), bit 18 (`cc2`) clear selects floating-point condition codes (`%fcc0..%fcc3`), but `sparc64_decode_op2` misclassifies bit 18 clear as `SPARC64_ICLS_MEMBAR`, turning `MOVcc (%fccn)` into a no-op in both interpreter and DBT.
  - **Fix**: Decode `MOVcc` with `cc2 == 0` as floating-condition `MOVcc` reading `%fcc0..%fcc3` from `FSR`.

- [x] **S64-4 — Medium — DEFECT — Darwin socket wrappers omit address-layout conversion**
  - **Where**: `src/os/backend_darwin.c:529-535,543-567` (`rt_host_bind`, `rt_host_connect`, address-returning socket wrappers).
  - **What breaks / Why**: Casts Linux `struct sockaddr` buffers (`uint16_t sa_family` at offset 0) directly to Darwin `struct sockaddr` (`uint8_t sa_len, uint8_t sa_family` at offsets 0–1) without converting `sa_len`/`sa_family` or `AF_INET6` (`10` vs `30`).
  - **Fix**: Translate Linux `<->` Darwin `sockaddr` headers (`sa_len`, `sa_family`) in the Darwin socket backend wrappers.

- [x] **S64-5 — Medium — DEFECT — Darwin futex implementation discards essential semantics**
  - **Where**: `src/os/backend_darwin.c:684-716` (`rt_host_futex_wait_bitset`, `rt_host_futex_wake_bitset`, `rt_host_futex_requeue`).
  - **What breaks / Why**: Ignores the futex address key, bitset, wake count, and requeue comparison/target, broadcasting to a single process-wide condition variable on every wake/requeue.
  - **Fix**: Key waiters by address and bitset, honor `max_wake` and `max_requeue`, and check `*uaddr == cmpval` under the futex lock.

- [x] **S64-6 — Medium — DEFECT — Darwin no-replace mapping can overwrite an existing mapping**
  - **Where**: `src/os/backend_darwin.c:202-213` (`rt_host_map_anon`).
  - **What breaks / Why**: When `fixed && noreplace` are both set, the `if (fixed)` branch runs first and calls `mmap(..., MAP_FIXED)` without probing `mincore`.
  - **Fix**: Check `noreplace` before `fixed` and guard the probe+map under the VM lock.

- [x] **S64-7 — Medium — DEFECT — Darwin copy fallback loses partial-write accounting**
  - **Where**: `src/os/backend_darwin.c:373-390` (`darwin_copy_loop`).
  - **What breaks / Why**: Updates `done` and `*in_off` only after an entire read chunk is written; if a subsequent write fails after a partial write succeeded, the already-written bytes are not accounted for.
  - **Fix**: Advance `done` and `*in_off` immediately after each successful `write`/`pwrite`.

- [x] **S64-8 — Medium — DEFECT — Darwin ppoll drops signal-mask and empty-set waiting behavior**
  - **Where**: `src/os/backend_darwin.c:578-593` (`rt_host_ppoll`).
  - **What breaks / Why**: Ignores `linux_sigmask` and immediately returns `0` when `nfds == 0` instead of sleeping for `timeout_ns`.
  - **Fix**: Honor `timeout_ns` even when `nfds == 0` (via `poll(NULL, 0, ...)` or wake-pipe poll) and apply/restore the temporary signal mask.

- [x] **S64-9 — Medium — DEFECT — VM validation helpers admit wrapped and out-of-range spans**
  - **Where**: `src/vm/vm64.c:125-127,161-177,182-204,210-225` (`vm64_align_up_8k`, VM argument validators).
  - **What breaks / Why**: Subtracts `addr` from `VM64_TASK_SIZE` without first checking `addr <= VM64_TASK_SIZE`, and `vm64_align_up_8k(UINT64_MAX)` wraps to `0`.
  - **Fix**: Check `addr <= VM64_TASK_SIZE` and check `val <= UINT64_MAX - 0x1fffULL` before aligning up.

### 10.2 Curated C11 & UB Issues

- [x] **S64-10 — Medium — C11 — Backward branch decoding left-shifts negative signed values**
  - **Where**: `src/interp/interp.c:94,109,116,131,149` (`sparc64_classify_word`); `src/interp/decode.c:215,230,247,256,564` (`sparc64_decode_word`).
  - **What breaks / Why**: Left-shifts negative sign-extended branch displacements (`<< 2`) in both decoders (C11 signed left-shift UB).
  - **Fix**: Perform the `<< 2` shift on `uint64_t` / `uint32_t` before sign-extending, or multiply the signed `int64_t` value by `4`.

- [x] **S64-11 — High — C11 — Darwin worker startup reads a parent stack object after its lifetime**
  - **Where**: `src/os/backend_darwin.c:763-786` (`worker_tramp`, `rt_host_spawn_worker`).
  - **What breaks / Why**: In `worker_tramp`, the child thread sets `st->ready = 1`, signals the condition variable, and unlocks `st->mu` *before* reading `st->fn` and `st->arg`. The parent thread wakes up and returns from `rt_host_spawn_worker`, destroying stack-allocated `st` before the child reads `st->fn(st->arg)` (stack use-after-return UB).
  - **Fix**: Copy `fn` and `arg` into local variables in `worker_tramp` *before* setting `st->ready = 1` and unlocking `st->mu`.

### 10.3 DRY, YAGNI & CLEAN

- [x] **S64-12 — Medium — DRY — Two instruction decoders have already diverged**
  - **Where**: `src/interp/interp.c:68-170,239-257` (`sparc64_classify_word`); `src/interp/decode.c:200-258,316-327,528-577` (`sparc64_decode_word`); `src/dbt/difftest.c:224-227`.
  - **What breaks / Why**: `sparc64rt` maintains two separate instruction decoders (`sparc64_classify_word` in `interp.c` and `sparc64_decode_word` in `decode.c`) that already disagree on `MOVcc` (`S64-3`).
  - **Fix**: Consolidate raw instruction decoding in `sparc64rt` so `interp`, `dbt`, and `difftest` share one authoritative decode table.

- [x] **S64-13 — Low — YAGNI — VM syscall validators are disconnected from production callers**
  - **Where**: `src/vm/vm64.c:182-204,210-242` (`vm64_check_munmap_args`, `vm64_check_mremap_args`).
  - **What breaks / Why**: Defined in `src/vm/vm64.c` with no production callers in `src/`.
  - **Fix**: Wire into the `munmap`/`mremap` syscall handlers (after fixing `S64-9`) or remove the unused functions.

- [x] **S64-14 — Low — CLEAN — Core implementation files have almost no size headroom**
  - **Where**: `src/interp/interp.c:1-900`, `src/os/syscalls_ext.c:1-894`, `src/dbt/dbt.c:1-892`, `src/interp/fp_sd.c:1-889`.
  - **What breaks / Why**: `interp.c` is at 900 lines and three other core files are at `889–894` lines.
  - **Fix**: Extract cohesive helpers into separate `.c` files when applying fixes `S64-2`, `S64-3`, and `S64-12`.

---

### R1-11. `rt-series` (`4e4512d` → `96e1fe6`) — 25 / 25 Resolved

### 11.1 Bugs & Defects

- [x] **RTS-1 — High — BUG — Cross-page fixture rejects correct big-endian execution**
  - **Where**: `tests/p3_torture.c:361-374` (`t_unaligned_cross_page`).
  - **What breaks / Why**: `memcpy(&got, edge, sizeof(got))` loads 8 bytes in native guest endianness, but `want` always packs `edge[0]` into the least-significant byte (`want |= (uint64_t)edge[i] << (i * 8)`). On big-endian guests (`ppc32`, `sparc32`, `sparc64`, big-endian MIPS), `got` and `want` have opposite byte orders, so a correct big-endian translator fails `t_unaligned_cross_page`.
  - **Fix**: Construct `want` in native guest byte order (or compare byte-for-byte via an aligned staging buffer) so both little-endian and big-endian guests are tested accurately.

- [x] **RTS-2 — High — DEFECT — Assembler/linker test substitutes a shell script and reports PASS**
  - **Where**: `tools/run_catalogue.sh:652-691` (`run_guest_payload`, Tier 4).
  - **What breaks / Why**: In `run_guest_payload`, assembly source for `as+ld .s link + exit 42` is only provided for `aarch64` and `x86_64`; the `*)` branch writes a `#!/bin/sh\nexit 42` shell script instead of assembling and linking a guest `.s` file, yet records `PASS` for `as+ld .s link + exit 42`.
  - **Fix**: Provide minimal `_start` exit-42 assembly snippets for all 10 guest architectures (`arm`, `i686`, `mips`, `ppc`, `sparc`, `riscv`, `loongarch64`, `ppc64le`, `mips64`, `sparc64`) and require `as` + `ld` to produce an ELF binary.

- [x] **RTS-3 — High — DEFECT — Benchmark PASS ignores process failure**
  - **Where**: `tools/bench_harness.sh:318-331`, `tools/bench_harness.sh:344-353`, `tools/bench_harness.sh:364-399` (`run_one_target`).
  - **What breaks / Why**: Benchmark invocations append `|| true`, discarding non-zero exit codes or timeouts if `ALL_PASS` was printed earlier, and converting QEMU checksum failures that lack `ALL_PASS` into `SKIP` instead of `FAIL`.
  - **Fix**: Capture the command exit code, require both `rc == 0` and `ALL_PASS`, and report `FAIL` when a runnable target crashes, times out, or fails checksum verification.

- [x] **RTS-4 — High — DEFECT — Grind architecture selection does not select a translator**
  - **Where**: `tools/run_grind.sh:39-46`, `tools/run_grind.sh:116-130`, `tools/run_grind.sh:164-207`, `tools/run_grind.sh:464-482` (`ARCH_FILTER`, grind dispatch).
  - **What breaks / Why**: `--arch <repo>` sets `ARCH_FILTER`, which is printed in the banner but never used to select a cross-compiler or `<arch>rt` translator binary; `stress-ng` and `gcc-torture` run on the host unless `GRIND_INTERP`/`GRIND_DBT` env vars are manually supplied.
  - **Fix**: Map `--arch <repo>` to the repository's cross-compiler and `--interp`/`--dbt` translator binaries automatically when `GRIND_*` overrides are not set.

- [x] **RTS-5 — High — DEFECT — Grind converts executed failures into tolerated skips**
  - **Where**: `tools/run_grind.sh:262-270`, `tools/run_grind.sh:409-435`, `tools/run_grind.sh:490-498` (`run_testfloat_suite`, `run_lmbench_suite`, final gate).
  - **What breaks / Why**: Non-zero exits from executed `testfloat` or `lmbench` runs increment `skip` instead of `fail`, and `GRIND_ALLOW_SKIP` (documented in the header) is never read.
  - **Fix**: Count non-zero exits from executed `testfloat`/`lmbench` binaries as `FAIL` and honor `GRIND_ALLOW_SKIP=0`.

- [x] **RTS-6 — High — DEFECT — Qualification checks fixture presence without requiring execution evidence**
  - **Where**: `tools/run_catalogue.sh:99-118`, `tools/run_catalogue.sh:751-780`, `tools/run_catalogue.sh:832-848` (`check_uniform_guests`, `run_repo_gate`, `run_host_qualify`).
  - **What breaks / Why**: `check_uniform_guests` verifies that `p3_torture.elf`, `smoke_tcg.elf`, `dyn_pie_test.elf`, and `rootfs/bin/busybox` exist on disk, then `run_repo_gate` delegates to `tests/parity_suite.sh` without verifying that the delegated script actually emitted `PASS` rows for all 10 required catalogue categories.
  - **Fix**: Verify in `run_repo_gate` / `run_host_qualify` that the delegated parity output contains `PASS` rows covering all required catalogue categories (`p3-torture`, `tcg-smoke`, `dyn-pie`, `t1-busybox`, `t2-core`, `t3-system`, `t4-compiler`) and zero `FAIL`/`GAP`/`SKIP` rows.

- [x] **RTS-7 — Medium — BUG — Tier 4 strips the symbol it later requires**
  - **Where**: `tools/run_catalogue.sh:553-560`, `tools/run_catalogue.sh:696-700` (`run_guest_payload`).
  - **What breaks / Why**: Tier 4 runs `strip "$hello_bin"` in place during the `strip` check and later runs `objdump -d "$hello_bin" | grep -q "main"`, which fails when `strip` removes the symbol table.
  - **Fix**: Run `strip` on a copy (`${hello_bin}.stripped`) or run `objdump -d` before `strip`.

- [x] **RTS-8 — Medium — BUG — Requested benchmark engine is not consistently passed**
  - **Where**: `tools/bench_harness.sh:306-327`, `tools/bench_harness.sh:344-349`, `tools/bench_harness.sh:364-377` (`run_one_target`).
  - **What breaks / Why**: `run_one_target` passes `--$ENGINE` only for 7 of the 10 translators on Darwin/Linux (omitting engine selection for `a32rt`, `i686rt`, and `rvrt`) and omits it on `hl`, yet labels all output rows with `$ENGINE`.
  - **Fix**: Pass each translator's engine selection flag/env (`A32_INTERP=1`, `I686_NO_JIT=1`, `RVRT_ENGINE=...`, `--interp`/`--dbt`) consistently or skip unsupported engine combinations explicitly.

- [x] **RTS-9 — Medium — DEFECT — Empty benchmark matrices succeed**
  - **Where**: `tools/bench_harness.sh:301-304`, `tools/bench_harness.sh:311-401`, `tools/bench_harness.sh:404-420` (`run_one_target`, `run_matrix`).
  - **What breaks / Why**: Passing an unknown `--arch` or `--target` runs zero benchmarks and exits `0`.
  - **Fix**: Reject unknown `--arch`/`--target`/`--engine` arguments and fail if zero benchmark rows were executed.

- [x] **RTS-10 — Medium — BUG — Optional grind settings become fatal unset-variable expansions**
  - **Where**: `tools/run_grind.sh:191-193`, `tools/run_grind.sh:234-235` (`run_gcc_torture_suite`, `run_testfloat_suite`).
  - **What breaks / Why**: Under `set -u`, `eval "_cmd=\$$_runner_var"` aborts when `GRIND_QEMU` is unset, and `${TESTFLOAT_ROUNDS_WEEKLY:-$TESTFLOAT_ROUNDS}` aborts when both env vars are unset instead of falling back to `$_rounds`.
  - **Fix**: Use `eval "_cmd=\${${_runner_var}:-}"` and `${TESTFLOAT_ROUNDS_WEEKLY:-$_rounds}`.

- [x] **RTS-11 — Medium — DEFECT — Existing binaries bypass source changes**
  - **Where**: `tools/build_uniform_guests.sh:43-48`, `tools/bench_harness.sh:146-174`, `tools/bench_harness.sh:212-221` (`already_built`, `build_guest_bins`).
  - **What breaks / Why**: `already_built` checks only `[ -x "$out/p3_torture.elf" ] && [ -x "$out/smoke_tcg.elf" ]`, skipping rebuilds when `tests/p3_torture.c`, `tests/tcg/smoke_tcg.c`, or `tests/bench_suite.c` is modified.
  - **Fix**: Rebuild whenever the C source file is newer than the output binary (`[ "$src" -nt "$bin" ]`) or `FORCE_REBUILD=1` is set.

- [x] **RTS-12 — Medium — BUG — Uniform container names collide and cleanup is not guaranteed**
  - **Where**: `tools/build_uniform_guests.sh:52-83`, `tools/build_uniform_guests.sh:259-296`.
  - **What breaks / Why**: Uses a hardcoded `--name rt-u-*-23194` suffix instead of `$$` and lacks an `EXIT`/`INT`/`TERM` trap to remove containers on interruption.
  - **Fix**: Use `$$` in container names and register a `trap` that removes any lingering `rt-u-*-$$` containers and verifies `docker ps`.

- [x] **RTS-13 — Medium — DEFECT — Remote benchmark execution has no wall-clock bound**
  - **Where**: `tools/remote_bench.sh:98-145`, `tools/remote_linux_inner.sh:40-75`.
  - **What breaks / Why**: Benchmark invocations in `remote_bench.sh` and `remote_linux_inner.sh` run without `timeout --kill-after=30s`.
  - **Fix**: Wrap every remote and inner benchmark execution in `timeout --kill-after=30s`.

- [x] **RTS-14 — Medium — BUG — Failed clock reads produce valid-looking benchmark timings**
  - **Where**: `tests/bench_suite.c:32-38`, `tests/bench_suite.c:291-304`, `tests/bench_suite.c:390-400` (`get_monotonic_time`, `elapsed_us_between`).
  - **What breaks / Why**: Ignores `clock_gettime` return values and clamps `0 us` to `1 us`, reporting fabricated timings if `clock_gettime` fails.
  - **Fix**: Check the `clock_gettime` return value and fail the benchmark if the clock syscall fails.

- [x] **RTS-15 — Medium — BUG — Alternate-stack error paths free a registered stack**
  - **Where**: `tests/p3_torture.c:313-338` (`t_sigaltstack`).
  - **What breaks / Why**: If `sigaction` or `raise` fails after `sigaltstack(&ss, &old_ss)` succeeds, `free(alt)` runs without disabling the registered alternate signal stack first.
  - **Fix**: Disable the alternate stack (`SS_DISABLE`) before calling `free(alt)` on all exit paths.

- [x] **RTS-16 — Medium — DEFECT — Signal torture passes without exercising the claimed register/reservation conditions**
  - **Where**: `tests/p3_torture.c:173-235`, `tests/p3_torture.c:238-293` (`t_sig_frame_gpr`, `t_sig_frame_fpr`).
  - **What breaks / Why**: `t_sig_frame_gpr` only checks `ucontext != NULL` and runs `__sync_bool_compare_and_swap` *after* `raise(SIGUSR1)` returns; `t_sig_frame_fpr` allows the fallback `raise(SIGALRM)` after the FP loop finishes and leaves the alarm armed during the reference loop.
  - **Fix**: Cancel any pending `alarm(0)` before the reference loop and verify live volatile/callee-saved register preservation across asynchronous signal delivery.

- [x] **RTS-17 — Medium — DEFECT — Missing core fixture capabilities still produce ALL_OK**
  - **Where**: `tests/p3_torture.c:531-550`, `tests/tcg/smoke_tcg.c:443-461` (`main`).
  - **What breaks / Why**: Both fixtures print `ALL_OK` and return `0` as long as `g_fail == 0 && g_pass > 0`, even if `g_skip > 0` because `mmap`, `sigaction`, `sigaltstack`, or `pthread_create` returned `ENOSYS`.
  - **Fix**: Require `g_skip == 0` (unless an explicit allow-skip flag/env is set) before printing `ALL_OK`.

- [x] **RTS-25 — Medium — DEFECT — Stderr normalization hides input failures**
  - **Where**: `tools/parity_contract.sh:72-77` (`parity_norm_stderr`).
  - **What breaks / Why**: `grep -v -E ... "$_pns_in" > "$_pns_out" || true` masks exit code `2` (missing/unreadable input file), producing an empty output file that matches an empty golden stderr.
  - **Fix**: Check `[ -r "$_pns_in" ]` and allow only `grep` exit codes `0` and `1`.

### 11.2 Curated C11 & UB Issues

- [x] **RTS-18 — High — C11 — Thread arithmetic overflows signed long on 32-bit guests**
  - **Where**: `tests/tcg/smoke_tcg.c:265-284` (`thread_fn`, `t_testthread`).
  - **What breaks / Why**: With `n = 200000`, `sum += i` reaches `19,999,900,000` and `n * (n - 1) / 2` reaches `39,999,800,000`, overflowing 32-bit signed `long` on all five Class-A ILP32 guests (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt` + `rv32gc`), which is C11 signed integer overflow UB.
  - **Fix**: Use `int64_t` / `uint64_t` for `sum` and `(int64_t)n * (n - 1) / 2` (or reduce `n` so `n * (n - 1)` fits in `int32_t`).

- [x] **RTS-19 — Medium — C11 — Thread error path can leave a pointer to an expired stack object**
  - **Where**: `tests/tcg/smoke_tcg.c:265-267`, `tests/tcg/smoke_tcg.c:283-310` (`thread_fn`, `t_testthread`).
  - **What breaks / Why**: `pthread_create` receives `&n` (a stack local); if `munmap` fails before `pthread_join`, `t_testthread` returns while the child thread is still running and reading `&n`.
  - **Fix**: Always `pthread_join` a created thread before returning from `t_testthread`.

### 11.3 DRY, YAGNI & CLEAN

- [x] **RTS-20 — Low — DRY — Remote benchmark parser and architecture matrix are duplicated**
  - **Where**: `tools/remote_bench.sh:15-31`, `tools/remote_linux_inner.sh:14-30` (`ARCH_LIST`, `parse_and_print`).
  - **What breaks / Why**: Identical `ARCH_LIST` and 7-field output parser duplicated across both scripts.
  - **Fix**: Factor into a shared shell helper sourced by both scripts.

- [x] **RTS-21 — Low — DRY — Uniform guest builders repeat the same build procedure fourteen times**
  - **Where**: `tools/build_uniform_guests.sh:52-255`, `tools/build_uniform_guests.sh:259-277` (`build_*`).
  - **What breaks / Why**: Fourteen nearly identical `build_<abi>` functions repeat directory setup, container invocation, and compiler flags.
  - **Fix**: Drive uniform guest builds from a single parameterized helper function.

- [x] **RTS-22 — Medium — YAGNI — Weekly soak is permanently skipped scaffolding**
  - **Where**: `tools/run_grind.sh:438-452`, `tools/run_grind.sh:474-482` (`run_weekly_soak`).
  - **What breaks / Why**: Both `csmith` and `yarpgen` branches in `run_weekly_soak` unconditionally increment `skip` even when the tools are installed.
  - **Fix**: Execute bounded `csmith` / `yarpgen` generation+differential runs when installed, or remove the no-op branches.

- [x] **RTS-23 — Low — CLEAN — Catalogue status documentation contradicts current skip behavior**
  - **Where**: `docs/CATALOGUE-TODO.md:3`, `docs/CATALOGUE-TODO.md:47`; `tools/run_catalogue.sh:733-747`.
  - **What breaks / Why**: `docs/CATALOGUE-TODO.md` still describes pre-Wave-C2 behavior where missing T2–T4 tools were silently skipped.
  - **Fix**: Mark the historical audit findings in `docs/CATALOGUE-TODO.md` as resolved by Wave C1/C2.

- [x] **RTS-24 — Low — CLEAN — Benchmark implementation is seven lines below the C file ceiling**
  - **Where**: `tests/bench_suite.c:1-893`.
  - **What breaks / Why**: At 893 lines, leaving only 7 lines of headroom under the 900-line ceiling.
  - **Fix**: Split architecture syscall/startup glue (`tests/bench_sys.h`) from the benchmark kernels (`tests/bench_suite.c`) when touching `bench_suite.c`.
