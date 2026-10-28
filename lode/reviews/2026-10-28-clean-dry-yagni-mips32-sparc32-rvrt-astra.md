The audit found **correctness defects in all three repositories that should precede structural cleanup**. The most consequential are rvrt emitter memory corruption, incorrect FP results, missing guest-memory protection checks, and unsafe shared thread state.

The trees remained unchanged and clean:

| Repository | Audited commit | Production C/H/S files | Lines |
|---|---|---:|---:|
| mips32rt | `9379b3dfd14b` | 49 | 18,784 |
| sparc32rt | `e74075e2b56b` | 62 | 19,530 |
| rvrt | `726e3d50f2fc` | 254 | 75,766 |

Findings below are verified source/data-flow findings. Proposed runtime regressions were **not executed** in this read-only environment.

The **High-priority checklist** addresses correctness, memory safety, and architectural invariants.

1. **[ ] rvrt: bound every emitter patch operation.**  
   [dbt_emit_fp.h:36](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:36) stops emission at 2,048 words, but [dbt_emit_fp.c:139](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:139) and [dbt_emit_fp.c:310](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:310) patch `words[]` without bounds checks. Long FP blocks reach these writes before the outer overflow check at [darwin_dbt.c:645](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:645). An index of 2,048 writes beyond the array into the surrounding emitter state; subsequent patching can use corrupted indices.  
   **Remediation:** introduce checked patch helpers and transactional per-instruction emission or capacity reservation. Do not merely enlarge the buffer. **Verify:** near-capacity emission and long dynamic-rounding FP blocks under ASan/UBSan.

2. **[ ] rvrt: fix two live FP register-clobber defects.**  
   At [dbt_emit_fp.c:450](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:450), FP-to-integer conversion places its result in `x2`; `emit_accum()` then overwrites `x2` with exception flags before the guest result is stored. Separately, [dbt_emit_fp.c:580](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:580) loads an FMA operand into `x3`, which `emit_unbox_s()` uses as scratch at [line 117](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:117).  
   **Remediation:** document and enforce helper input/output/clobber contracts; keep live operands and results separate from scratch registers. **Verify:** FCVT exact values, saturation and NaNs; all four single-precision fused operations with distinct operands. These paths serve native Darwin and fast-Linux.

3. **[ ] rvrt: make the advertised `--difftest` perform a comparison.**  
   [darwin_main.c:109](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:109) promises cross-checking, but [line 514](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:514) only sets a mode flag, and [line 549](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:549) executes either DBT or interpreter. It never compares their results. The separate [dbt/difftest.c:70](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/difftest.c:70) uses another engine and directly interprets RV32.  
   **Remediation:** compare independently initialized CPU/memory executions and side effects; explicitly reject the option until implemented. **Verify:** deliberately introduce a DBT divergence and prove that the mode detects it.

4. **[ ] mips32rt: enforce 4 KiB guest permissions in native Darwin DBT.**  
   [vm_mmap.c:193](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:193) widens partial 16 KiB host-page protection to RW, while [emit_mem.c:245](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:245) emits direct accesses without software permission checks. Production startup at [main.c:271](/Users/angerman/Projects/zw3rk/mips32rt/src/main.c:271) also bypasses the VM-regime initialization performed by [mem.c:177](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:177). Consequently, a protected 4 KiB subpage can remain accessible through DBT.  
   **Remediation:** initialize the regime on actual startup/exec paths and use checked accesses throughout that regime; use interpreter fallback until complete. **Verify:** adjacent RW/RO/NONE guest subpages inside one native host page.

5. **[ ] mips32rt: synchronize CLONE_VM mapping state and translation invalidation.**  
   [threads.c:301](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:301) copies mapping metadata into each child. [vm.c:121](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm.c:121) refreshes only the mutating context and root, leaving other siblings stale; readers traverse those mirrors without synchronization. Meanwhile, the cache is thread-local at [dbt.c:101](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:101), and [line 347](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:347) invalidates only the calling thread’s cache.  
   **Remediation:** establish synchronized mapping ownership and cross-thread invalidation generations with safe execution boundaries. **Verify:** three-thread mapping/protection changes and code replacement, including changes between non-root siblings.

6. **[ ] mips32rt: move signal masks/frame nesting into thread state and repair exec semantics.**  
   [signals.c:123](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:123) keeps `g_blocked`, `g_frame_sp`, and `g_depth` process-global despite concurrent guest threads. One thread changes another’s mask, and overlapping delivery corrupts shared frame bookkeeping. [signals.c:857](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:857) also clears ignored dispositions and the blocked mask during exec.  
   **Remediation:** make masks/frame nesting per-thread, synchronize shared dispositions, and preserve ignored dispositions and blocked masks across exec. **Verify:** distinct thread masks, simultaneous nested delivery/return, and exec preservation.

7. **[ ] mips32rt: correct little-endian O32 truncate argument decoding.**  
   [vm_file.c:290](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:290) and [line 328](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:328) always treat `a2` as the high word and `a3` as the low word. Mipsel uses the opposite order: `ftruncate64(fd, 1)` becomes a request for 4 GiB.  
   **Remediation:** use one endian-aware aligned O32 pair decoder. **Verify:** truncate/ftruncate in both endian modes with lengths `1`, `2^32+1`, and negative values.

8. **[ ] sparc32rt: replace arithmetic-only guest-pointer checks with checked copies.**  
   [l2a_access.h:50](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:50) checks only wraparound and the low guard; [line 68](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:68) then calls `memcpy`. Similar checks occur at [threads.c:197](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:197) and [threads_exec.c:38](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_exec.c:38). Unmapped syscall buffers can fault the translator; widened host permissions can allow writes into guest read-only pages.  
   **Remediation:** centralize copyin/copyout/string access with mapping, permission, and lifetime checks. **Verify:** unmapped, NONE, RO, cross-page, and wraparound syscall buffers return guest `EFAULT`.

9. **[ ] sparc32rt: fix clone-handshake lifetime.**  
   The child signals readiness at [threads.c:400](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:400), then can exit and free `st` at [line 384](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:384) before the parent accesses its mutex/condition/TID at [line 546](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:546). There is no acknowledgment or shared ownership preventing this use-after-free.  
   **Remediation:** give parent and child explicit handshake ownership; also return `pthread_create()`’s error value rather than `errno`. **Verify:** immediate child exit with delayed parent scheduling under ASan.

10. **[ ] sparc32rt: separate architectural thread state and make signal publication safe.**  
    [interp_win.c:23](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:23) stores all register windows in one global array, although parent and child can execute concurrently. [syscalls.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls.c:83) similarly shares one blocked mask. The signal handler traverses a concurrently modified context table and performs non-atomic pending-bit updates at [threads.c:99](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:99). Context removal/free can race with that traversal.  
    **Remediation:** make window images and masks per-context; define signal-safe pending publication and context lifetime. Preserve frozen context-prefix offsets. **Verify:** interleaved SAVE/RESTORE, opposing thread masks, and signals during thread exit.

11. **[ ] sparc32rt: repair native Darwin subpage and shared-mapping semantics.**  
    [backend_darwin.c:379](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/backend_darwin.c:379) rounds protection changes to the full host page and chooses `PROT_NONE` from only the requested guest subpage, disabling neighboring mappings. [line 312](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/backend_darwin.c:312) implements misaligned file mappings by copying bytes into anonymous memory, silently losing `MAP_SHARED` semantics.  
    **Remediation:** derive host protection from all constituent guest pages and enforce individual permissions in software; implement shared backing or explicitly reject unsupported shared mappings. **Verify:** four neighboring subpages plus alias/fork visibility, writeback, and truncate/regrow behavior.

12. **[ ] Both 32-bit repositories: remove signed-arithmetic UB.**  
    MIPS [interp.c:294](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:294) and [line 316](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:316) perform potentially overflowing signed MADD/MSUB accumulation. SPARC [decode.c:347](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:347), [line 364](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:364), [interp.c:275](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:275), and [emit_priv.h:175](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_priv.h:175) left-shift negative signed values.  
    **Remediation:** perform modular arithmetic/bit assembly unsigned, with explicit signed interpretation where required. **Verify:** UBSan boundary cases, backward branches, negative dividends, and interpreter/DBT/QEMU agreement.

The **Medium-priority checklist** addresses DRY, incomplete abstractions, and maintainability.

| Item | Evidence and remediation |
|---|---|
| **[ ] Split rvrt’s runtime coordinator by responsibility.** | [runtime_main.c:5218](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5218) contains a 1,521-line `run_worker` with lexical brace depth 10; [main:7153](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:7153) is 1,049 lines; [fork_guest_process:4443](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:4443) is 428. Extract syscall families, worker lifecycle, and bootstrap behind existing ownership boundaries. Split [linux/file.c:618](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:618)’s 417-line `transfer` by operation/state transition. |
| **[ ] Split large 32-bit functions semantically.** | MIPS [elf32.c:165](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/elf32.c:165): 335-line loader. SPARC [elf32.c:189](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/elf32.c:189): 322-line loader; [syscalls_min.c:605](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_min.c:605): 272-line dispatcher; [vm_mmap.c:331](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:331): nested mremap logic. Separate validation, planning, mutation, and rollback. |
| **[ ] Consolidate syscall ABI/access helpers within each repository.** | MIPS duplicates range/errno/return/argument helpers in [syscall_min.c:82](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:82), [syscalls.c:80](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:80), [proc.c:72](/Users/angerman/Projects/zw3rk/mips32rt/src/os/proc.c:72), and signals. Its errno mappings translate only ENOSYS. SPARC duplicates BE/range access in [l2a_access.h:23](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:23), syscall, thread, and exec modules. Establish one checked ABI layer per repo, distinguishing syscall `EFAULT` from architectural faults. |
| **[ ] Consolidate A64 encoding and register contracts.** | MIPS repeats its GPR-cache map/accessors in [emit_int.c:16](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:16) and [emit_fp.c:94](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:94). SPARC repeats MOV64 emission at [emit_int.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:126), [emit_fast.c:37](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fast.c:37), and [emit_fp.h:67](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.h:67). rvrt duplicates encodings between [jit/emit.h:11](/Users/angerman/Projects/zw3rk/rvrt/src/jit/emit.h:11) and [dbt_emit_fp.h:44](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:44). Share checked primitives, preserving engine policy and oracle independence. |
| **[ ] Consolidate SPARC delay-slot policy.** | [emit_int.c:199](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:199) and [emit_fp.c:749](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:749) duplicate control handling and already differ on FBfcc fallback. Resolve intended behavior against the oracle, then share delay dispatch/annul infrastructure. Move implementation out of [emit_priv.h:31](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_priv.h:31), which explicitly exists to evade the per-file line limit. |
| **[ ] Reduce backend duplication after defining the active interface.** | MIPS has a 94-line identical run at [Linux:332](/Users/angerman/Projects/zw3rk/mips32rt/src/os/backend_linux.c:332)/[Darwin:322](/Users/angerman/Projects/zw3rk/mips32rt/src/os/backend_darwin.c:322). rvrt repeats its worker handshake at [Linux:271](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:271)/[Darwin:348](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:348), including incorrect `pthread_create()` error handling. Share truly common POSIX logic; retain platform constants, JIT, and blocking behavior separately. These rvrt worker APIs currently have no in-tree callers. SPARC backends differ substantially; wholesale merging is unwarranted. |
| **[ ] Resolve dormant backend/AOT implementations.** | MIPS links backend APIs without production callers; [aot.c:110](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/aot/aot.c:110) discards code/sites while `--cache` is accepted. SPARC’s [aot_cache.c:63](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/aot/aot_cache.c:63), [vm32.c:240](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm32.c:240), and Darwin blocking helpers lack consumers; [backend_darwin.c:432](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/backend_darwin.c:432) returns success without waiting. Integrate retained features through real callers and acceptance tests, or remove inactive build/CLI surfaces and correct support claims. |
| **[ ] Repair or remove incomplete family-file bookkeeping.** | MIPS [vm_file.c:55](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:55) and SPARC [vm_file.c:23](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:23) describe shared family tables implemented as ordinary static arrays. MIPS retains unused descriptors; SPARC initializes new inode size to zero at [line 109](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:109). Define actual shared ownership, initialization, and reclamation; remove write-only bookkeeping if deferred. |
| **[ ] Resolve rvrt’s duplicate VM authority.** | [runtime_main.c:3303](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:3303) creates a best-effort 16 MiB shadow VM beside the real sparse memory system, with ignored mirroring failures. Identify its concrete consumer, then integrate or isolate/remove the redundant path. This is architectural duplication, **not evidence that RV64 execution is truncated to that window**. |
| **[ ] Propagate rvrt JIT write-transition failure.** | [backend_linux.c:160](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:160) ignores `mprotect()` failure; [darwin_dbt.c:698](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:698) immediately writes afterward. Return status and stop before `memcpy`; test injected protection failure and rounding overflow. |
| **[ ] Replace rvrt’s successful futex placeholders.** | [darwin_main.c:269](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:269) reports successful `FUTEX_WAKE_OP` without performing its atomic memory operation, and returns immediately for a matching wait. Use the applicable existing implementation or explicitly reject unsupported behavior. Verify memory side effects and invalid operands. |

There is **no current `rvrt/dbt_a64.c`**. Its named comparison target is stale: [darwin_dbt.c:35](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:35) already uses shared emitter helpers. Further consolidation should target the remaining surfaces listed above.

The **Low-priority checklist** covers proven dead code and style debt.

- **[ ] Remove unused local helpers/constants and review write-only fields.** MIPS [dbt.c:143](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:143) contains unused `dbt_is_likely`; SPARC [aot_sites.c:25](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/aot/aot_sites.c:25) maintains an obsolete delay-target table with no reader, and [interp_win.c:169](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:169) repeats a macro definition. rvrt’s [rv32.h:20](/Users/angerman/Projects/zw3rk/rvrt/src/core/rv32.h:20) helper and [dbt_emit_fp.h:19](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:19) condition enums are unused; [darwin_main.c:164](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:164)’s clear-TID field is write-only. Preserve ABI-reserved slots and distinguish missing consumers from obsolete requirements.
- **[ ] Replace historical lane names and inaccurate comments during relevant extractions.** Examples: MIPS [main.c:259](/Users/angerman/Projects/zw3rk/mips32rt/src/main.c:259) says engines arrive later; SPARC [vm32.c:19](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm32.c:19) describes an x20 Soft-TLB role inconsistent with the active trampoline; rvrt’s Darwin-named runner also builds Linux. Prefer functional names over `l2a_*`/`L4A_*`, and move historical wave narratives out of current contracts.
- **[ ] Name structural constants and annotate raw encodings.** Replace repeated context offsets such as rvrt’s [dbt_emit_fp.c:15](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:15) with `offsetof`-derived constants/static assertions. Use existing decoded-opcode names in SPARC switches. ISA encodings and documented ABI constants are not inherently problematic magic numbers.
- **[ ] Extend MIPS line-limit coverage to tests.** [Makefile:89](/Users/angerman/Projects/zw3rk/mips32rt/Makefile:89) scans only `src/include`, although the repository’s rule covers source files generally. Split the oversized tests below by behavior.

File-size inventory confirms that MIPS and SPARC production files satisfy their **stricter 900-line limit**. That does not prevent large functions or implementation-heavy headers.

All rvrt production files exceeding approximately 1,000 lines are:

| File | Lines |
|---|---:|
| [runtime_main.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:1) | 8,201 |
| [runtime/family.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family.c:1) | 4,639 |
| [runtime/guest_memory.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/guest_memory.c:1) | 2,571 |
| [runtime/native_signal.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/native_signal.c:1) | 1,892 |
| [runtime/file_caps.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/file_caps.c:1) | 1,851 |
| [linux/file.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:1) | 1,531 |
| [memory/file_backing.c](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_backing.c:1) | 1,518 |
| [memory/space.c](/Users/angerman/Projects/zw3rk/rvrt/src/memory/space.c:1) | 1,484 |
| [runtime/mm_view.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/mm_view.c:1) | 1,372 |
| [linux/fd.c](/Users/angerman/Projects/zw3rk/rvrt/src/linux/fd.c:1) | 1,338 |
| [runtime/scheduler.c](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/scheduler.c:1) | 1,100 |

Additional oversized files:

- MIPS: [test_p3_fpu.c](/Users/angerman/Projects/zw3rk/mips32rt/tests/test_p3_fpu.c:1), 1,145 lines; [test_p1_isa.c](/Users/angerman/Projects/zw3rk/mips32rt/tests/test_p1_isa.c:1), 950, exceeding its 900-line rule.
- rvrt tests: [test_linux_file.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_linux_file.c:1), 1,426; [r6_inherited_children.c](/Users/angerman/Projects/zw3rk/rvrt/test/r6_inherited_children.c:1), 1,304; [test_family_file_attributed.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_family_file_attributed.c:1), 1,293; [r5_exec.c](/Users/angerman/Projects/zw3rk/rvrt/test/r5_exec.c:1), 1,212; [test_linux_file_workers.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_linux_file_workers.c:1), 1,133; [test_file_caps.c](/Users/angerman/Projects/zw3rk/rvrt/test/test_file_caps.c:1), 1,022.
- rvrt’s [Makefile](/Users/angerman/Projects/zw3rk/rvrt/Makefile:1) is 8,677 lines. Group existing targets into included make fragments while retaining the root driver.
- Vendor exceptions: SoftFloat [primitives.h](/Users/angerman/Projects/zw3rk/rvrt/vendor/softfloat/source/include/primitives.h:1), 1,160; mbedTLS [check_config.h](/Users/angerman/Projects/zw3rk/rvrt/vendor/mbedtls/include/mbedtls/check_config.h:1), 1,149. Avoid local style-only rewrites of vendored code.

For **Curated C11 and architecture**, the checks found:

- No production uses of banned string functions, Annex-K functions, `<threads.h>`, `_Generic`, or `alloca`.
- Inspected allocation sites check allocation failure. This is not a proof of all pointer safety.
- No actual textual `x18`/`w18` use was found in reviewed assembly/emitter paths. Numeric machine-code encodings were not exhaustively verified.
- Reviewed Class-A address generation preserves W-register wrapping and x20-based guest addressing. Reviewed rvrt execution retains sparse 64-bit guest addresses.
- Reviewed guest-protection translation strips host EXEC. Linux JIT paths use RW→RX publication. Darwin `MAP_JIT` requests are paired with write-protection toggles; the RWX literal alone is not an effective W^X violation.
- Both Class-A runtimes declare `A32H_CAP_ICACHE_TRAP_IALLU` without explicitly selecting it. Generic cache flushing remains present; this absence did not establish a stale-instruction bug.
- No additional proven strict-aliasing or unaligned-access defect emerged from the reviewed paths. The signed-arithmetic and emitter-bounds defects above remain material.

Verification completed successfully:

- In both 32-bit repositories:
  ```sh
  timeout --kill-after=30s 30s \
    /Library/Developer/CommandLineTools/usr/bin/make \
    check-line-limits \
    CC=/Library/Developer/CommandLineTools/usr/bin/clang
  ```
- Native syntax checks used this exact compiler/flag prefix:
  ```sh
  timeout --kill-after=30s 30s \
    /Library/Developer/CommandLineTools/usr/bin/clang \
    -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -std=c11 -D_DARWIN_C_SOURCE -Werror=vla \
    -pedantic -Wall -Wextra -Werror -fsyntax-only \
    -Iinclude -Isrc
  ```
  Coverage was all MIPS/SPARC runtime C translation units selecting the Darwin backend, with `-Isrc/rt32`; and 13 rvrt native/compiler/core units: `dbt_emit_fp.c`, `darwin_dbt.c`, `darwin_main.c`, `dbt/{cache,emit_mem,difftest}.c`, `os/backend_darwin.c`, `vm/{vm64,vm_file}.c`, and `core/{interp,decode,compressed_expand,rv32_expand}.c`. All passed without diagnostics.

No linked builds, Linux/HL guest suites, QEMU comparisons, sanitizer executions, or concurrency stress tests were run. Assign overlapping emitter findings to one owner per repository, and serialize VM/thread-context interface changes. Keep consolidation repository-local and preserve independent interpreter semantics; none of the cleanup recommendations establishes a performance benefit without measurement.