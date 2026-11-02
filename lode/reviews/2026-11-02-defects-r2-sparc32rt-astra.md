# sparc32rt — Round 2 static audit

**HEAD:** `dad95daaa03755766b4497cc2af1d5664873569a`  
**Remediation commit:** `Resolve S32-1..S32-18 audit defects across VM, DBT, interp, and OS layers`

**Result:** 17 findings. The Round-1 remediation is incomplete and introduces new SMC and mapping-metadata defects.

Seven batched shell inspections covered the remediation diff, specifications, and selected source paths across interpreter, DBT, VM, loader, syscall, signal, thread, backend, build, and test modules. The C/header/assembly inventory under `src/`, `include/`, and `tests/` totals **27,084 lines**.

This was strictly a static audit: no builds, compilers, QEMU, Docker, or test scripts were invoked. Several large outputs were truncated; this report does **not** claim exhaustive line-by-line coverage or runtime verification.

Round-1 changes visibly remove the LDSTUB ownership lock, replace the problematic signed shifts, add the native timed-futex path and saturating deadline addition, consolidate signal restoration, introduce guest-visible mask/FPU state, add `-Werror`, and split oversized units. However, pointer-access synchronization, transactional exec, SMC correctness, and backing preservation remain unresolved. No inventoried source file exceeds 900 lines.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 0 | 2 | 0 | 0 | 0 | 10 |
| Medium | 4 | 0 | 0 | 0 | 0 | 0 | 4 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **12** | **0** | **2** | **1** | **1** | **1** | **17** |

## 1. Bugs & Defects

### High

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

### Medium

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

## 2. Curated C11 & UB Issues

- [ ] **S32-R2-13 — High — C11 — Permission and code-state tables have unsynchronized accesses**
  - **Where**: `src/vm/vm32.c:74-82`, `src/vm/vm32.c:208-216`, `src/vm/vm32.c:290-313`; `src/interp/interp_mem.c:36-41`; `src/os/l2a_access.h:75-77`
  - **What breaks / Why**: VM updates and DBT code marking write ordinary bytes under different locks, while interpreter accesses read them without either lock. Some readers use atomic builtins, but writers remain non-atomic. Concurrent accesses are data races, and read-modify-write updates can lose permission or code-state changes.
  - **Fix**: Define one synchronization discipline for table publication and code-state updates. Use matching atomic operations where lock-free access is required, while separately protecting mapping lifetimes.

- [ ] **S32-R2-14 — High — C11 — Signal handlers race on live-context and pending-signal state**
  - **Where**: `src/os/threads.c:97-129` (`sparc32_thr_note_signal`, `thr_host_handler`); `src/interp/interp_signal.c:414-415`, `src/interp/interp_signal.c:518-538`
  - **What breaks / Why**: The host handler traverses the live-context table and performs plain read-modify-write operations on pending masks. Guest workers concurrently inspect and clear those masks. These operations lack a signal-safe atomic ownership protocol, allowing lost signals and cross-thread data races; live-context lifetime also needs protection during handler traversal.
  - **Fix**: Use lock-free atomic pending operations and a signal-safe context-lifetime design. Prefer recording delivery for the appropriate recipient and handling process-directed routing at safe points.

## 3. DRY — Intra-Repo Duplication

- [ ] **S32-R2-15 — Low — DRY — Exec validation duplicates loader policy**
  - **Where**: `src/rt32/elf32.c:513-612`, `src/rt32/elf32.c:615-644`, `src/rt32/elf32.c:679-694` (`validate_elf32_fd`, `rt32_elf_validate`, `rt32_elf_load`)
  - **What breaks / Why**: The new prevalidation pass independently parses and validates an image that the loader subsequently processes again. Policy already differs: interpreter validation uses a fixed `0x3f000000` base, while loading can choose a higher base based on the executable’s break. The duplicated decisions undermine prevalidation’s guarantee.
  - **Fix**: Parse and validate once into a repository-local load plan containing retained descriptors, segment ranges, and chosen load biases. Consume that plan during staging and commit.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S32-R2-16 — Low — YAGNI — Removed TLB subsystem leaves a public no-op lifecycle hook**
  - **Where**: `src/vm/vm32.c:251-257` (`vm32_tlb_invalidate`); `src/rt32/vm.c:332-337` (`vm_record_region_ext_locked`)
  - **What breaks / Why**: Round-1 removed the disconnected TLB implementation but retained its public invalidation function and lifecycle calls. The function does nothing, while its name implies a coherence operation that callers may mistakenly rely on.
  - **Fix**: Remove the obsolete hook, declaration, and calls. Document the actual protection-table publication contract at the functions that implement it.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S32-R2-17 — Low — CLEAN — Store-path comment contradicts the SMC remediation**
  - **Where**: `src/dbt/emit_fast.c:130-154`
  - **What breaks / Why**: The comment says stores to code-bearing pages run “without cache invalidation” and retain approximate semantics. The new helper path invalidates translations and introduces an early block exit. This obsolete explanation can lead future maintainers to preserve or reintroduce incorrect behavior.
  - **Fix**: Describe the current write notification, translation retirement, and block-exit behavior, including delay-slot constraints.

The source inventory stays within the 900-line ceiling; `src/os/syscalls.c` is largest at 865 lines. Targeted searches found no banned string-conversion calls or textual `.c` includes in the inspected production scope. Those searches do not establish absence of all VLAs, UB, or encoded-register violations. All proposed consolidation remains inside `sparc32rt`; no cross-repository library extraction is recommended.