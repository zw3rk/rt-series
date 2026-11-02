# i686rt — Round 2 static audit

**HEAD:** `8db8727989e5dd96c06f1ff3bee46aa4a37c1ff0`

**Result:** 18 findings: **9 High, 7 Medium, 2 Low**. Round-1 remediation remains incomplete, particularly for sub-page permissions, SMC synchronization, threaded memory ordering, and file-backed remapping.

**Scope:** Seven batched shell inspections. The inventory contains **198 `.c`/`.h`/`.S` files and 72,293 lines** across `src/`, `include/`, and `tests/`. Detailed inspection concentrated on remediation changes, VM/backing management, DBT caching and lowering, fault recovery, interpreter strings, signal delivery, and selected syscall, floating-point, loader, test, and build paths.

**Limits:** This was a bounded static audit, not a complete line-by-line review of all 72,293 lines. Some outputs were truncated; individual syscall families, x87-80 arithmetic, and remaining instruction handlers remain incompletely reviewed. No builds, test scripts, QEMU, or Docker were run. No files were changed. Git’s macOS launcher emitted sandbox/cache warnings.

**Round-1 verification:** The inspected changes introduce Linux RW→RX publication, thread-local Darwin JIT-lock ownership, direct instruction-PC attribution, memory barriers in flag-elimination analysis, x87 signal-frame conversions, and actual `test`/`check` wiring. All counted source/header/assembly files satisfy the 900-line ceiling; the largest is 898 lines. These are source-level observations, not runtime validation. Findings below identify incomplete fixes and additional defects.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 0 | 1 | 0 | 0 | 0 | 9 |
| Medium | 5 | 0 | 1 | 0 | 0 | 1 | 7 |
| Low | 0 | 0 | 0 | 1 | 0 | 1 | 2 |
| **Total** | **13** | **0** | **2** | **1** | **0** | **2** | **18** |

## 1. Bugs & Defects

### High

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

### Medium

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

## 2. Curated C11 & UB Issues

- [ ] **I686-R2-14 — Medium — C11 — Cleanup reads an indeterminate array after longjmp**
  - **Where**: `src/os/marshal.c:93-137` (`s_copy_tolerant`, `opened`).
  - **What breaks / Why**: `opened` is a non-volatile automatic array modified after `sigsetjmp`. If a retried copy faults again, its contents are indeterminate after `siglongjmp`. Cleanup subsequently reads those contents to choose pages to re-protect. Marking `tries`, `locked`, and `healed` volatile does not preserve `opened`.
  - **Fix**: Store the cleanup journal in storage with a lifetime unaffected by setjmp/longjmp rules, such as a carefully scoped thread-local recovery record, or use appropriately volatile storage.

- [ ] **I686-R2-15 — High — C11 — Synchronous signal handling can acquire an interrupted VM lock**
  - **Where**: `src/interp/interp.c:124-135` (`host_fault_handler`); `src/dbt/engine_smc.c:305-307` (`i686_dbt_smc_write_fault`); `src/interp/interp.c:233-234` (`i686_fault_region_prot`); `src/rt32/rt32_vm.c:718-726` (`rt32_vm_sync_ctx`).
  - **What breaks / Why**: The signal handler calls SMC recovery, which can refresh a cloned context by acquiring the global VM spinlock. A fault while that same thread holds the VM lock—for example during a guest-memory operation inside a VM update—can spin forever because the interrupted owner cannot resume. Signal recovery is therefore not restricted to signal-safe, nonblocking state handling.
  - **Fix**: Keep synchronous handlers to bounded state capture and redirection. Perform VM synchronization and substantive invalidation at a recovery point with explicit lock ownership and cleanup, or use an immutable signal-readable mapping snapshot.

The targeted scans found no direct banned string/number-conversion calls or textual `.c` includes in the inspected C sources. Textual x18 matches were comments; that does not prove reservation across every numeric register encoding.

## 3. DRY — Intra-Repo Duplication

- [ ] **I686-R2-16 — Low — DRY — Recovery duplicates private decoder opcode numbers**
  - **Where**: `src/os/signals_subpage.c:40-53` (`SUBPAGE_OP7_*`); `src/x86/decode.c:70-73` (`I686_OP7_*`).
  - **What breaks / Why**: Recovery introduces a second manually maintained numeric opcode namespace, including the same 470–473 SSE assignments used by the decoder. A decoder change can silently make permission classification interpret an instruction as a different operation, width, or access direction.
  - **Fix**: Define these identifiers once in an i686rt-local decoder interface. Reuse them in recovery; do not introduce a cross-repository library.

## 4. YAGNI — Dead Code & Speculative Scaffolding

No additional YAGNI finding met the evidence threshold in this bounded pass. The remaining Soft-TLB descriptor and reserved context slot alone do not establish a defect: the context slot is explicitly documented as reserved.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **I686-R2-17 — Medium — CLEAN — Test and fixture drivers lack required lifecycle bounds**
  - **Where**: `Makefile:300-303` (`test-u3`); `tools/build_fixture.sh:54-62` (fixture container).
  - **What breaks / Why**: The default test dependency executes its test binary without an explicit wall-clock deadline. The fixture builder launches Docker without a unique container identity, timeout, resource limits, or identity-based cleanup. A hung build or cancelled client can leave an uncontrolled container running; `--rm` does not stop it.
  - **Fix**: Add bounded execution to the test target. Give fixture containers task-owned identities, suitable CPU/memory limits, and cleanup traps that stop/remove and verify termination of only those containers.

- [ ] **I686-R2-18 — Low — CLEAN — Comments retain claims contradicted by current implementations**
  - **Where**: `src/dbt/emit_atomic.c:122-125` (`em_atomic_site` comment); `src/interp/h_muldiv.c:156-166` (`h_imul3` comment).
  - **What breaks / Why**: Atomic-site documentation still says `e->tso` is never set, although the remediation enables it after cloning. IMUL documentation says `dest = dest * rm * imm`, while the implementation correctly computes `rm * imm`. These comments obscure precisely the semantics under review.
  - **Fix**: Describe the current TSO-independent atomic-site offset and the two-factor IMUL operation.

The source-file size repair is confirmed for the counted scope: **no `.c`, `.h`, or `.S` file in `src/`, `include/`, or `tests/` exceeds 900 lines**.