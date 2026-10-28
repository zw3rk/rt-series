The audit found substantial correctness defects beneath the cleanup issues. The recurring problem is **multiple representations of VM state that disagree, or newer coherence helpers that the live execution path never uses**.

All ten working trees were clean. No files changed. Findings below are verified by source tracing; the runtime scenarios are proposed regressions, not claimed reproductions. **P1** means fix before broader refactoring; **P2** means bounded correctness or ownership work; **P3** means cleanup.

I would address the correctness findings in this order:

1. [ ] **P1 — Fix malformed-ELF host memory accesses.**
   - **MIPS64:** unchecked segment rounding at [loader.c:439](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:439) can allocate a small mapping before [loader.c:488](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:488) zeroes the original enormous `p_memsz`. An unsigned-arithmetic probe with `va=0x1bb8`, `memsz=0xfffffffffffffc18`, and `filesz=0` produced a **4,096-byte mapping followed by an 18,446,744,073,709,550,616-byte zero-fill request**.
   - **PPC64:** [load.c:328](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:328) reads header fields before validating header length; [load.c:338](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:338) scans program headers before validating their bounds.

   Build a validated segment plan before mapping. Check subtraction-based bounds before addition, biasing, rounding, copying, or zeroing. Regress truncated headers, wrapping offsets, and near-`UINT64_MAX` segment sizes.

2. [ ] **P1 — Correct i686 exec teardown in offset mode.**  
   [rt32_vm.c:701](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:701) unmaps an absolute low address without adding `ctx->guest_base`. The live exec caller is [syscalls.c:430](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:430). With `G=4 GiB`, teardown targets the wrong host range and leaves the old guest window mapped. Preserve the reservation and reset the intended window. Test exec with `I686RT_WINDOW=0x100000000`.

3. [ ] **P1 — Separate i686 guest permissions from SMC write trapping.**  
   [engine.c:254](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:254) handles a fault on any marked code page by making it writable, without checking guest write permission. [engine.c:209](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:209) also restores RW during invalidation after mapping operations installed more restrictive permissions.

   Restore permissions from the committed VMA. Regress stores to translated RX text, and accesses after `mprotect(PROT_NONE)` or `munmap`.

4. [ ] **P1 — Track every source page of an i686 translated block.**  
   [engine.c:552](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:552) protects only the starting page; invalidation at [engine.c:214](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:214) checks block start addresses. Translation can cross pages. Retain source intervals and invalidate overlaps. Test a block starting on one page whose later instruction is changed on the next.

5. [ ] **P1 — Complete the actual A2 memory-access paths.**

   | Repository | Verified gap |
   |---|---|
   | **a32rt** | [core_emit_alu.c:713](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_alu.c:713) checks only the starting page, then emits the access. The comment at line 693 explicitly leaves multiword operations direct-addressed. |
   | **i686rt** | [vm32.c:91](/Users/angerman/Projects/zw3rk/i686rt/src/vm/vm32.c:91) implements TLB fill without runtime callers; [trampoline.S:47](/Users/angerman/Projects/zw3rk/i686rt/src/trampoline.S:47) retains direct guest-base addressing. [engine.c:133](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:133) disables SMC page protection on larger host pages. |
   | **mips32rt** | Production startup at [main.c:272](/Users/angerman/Projects/zw3rk/mips32rt/src/main.c:272) misses the alternate VM initializer. [emit_mem.c:248](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:248) emits direct accesses, while [vm_mmap.c:193](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:193) widens partial Darwin host-page protection to RW. |

   Use one canonical permission check, including access width and boundary handling, across interpreter, DBT, and guest copy operations. Test mixed RW/R/none subpages inside one 16 KiB host page, including unaligned and multiword accesses.

6. [ ] **P1 — Make MIPS32 code invalidation shared and exhaustion-safe.**  
   The cache/version table is thread-local at [dbt.c:96](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:96); `cacheflush` reaches only the caller’s invalidator through [syscall_min.c:401](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:401). A peer can retain stale translations. Separately, [dbt.c:323](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:323) silently stops recording new pages when the 1,024-entry SMC table fills.

   Own invalidation generations at address-space scope and invalidate conservatively on exhaustion. Test peer-thread patch/flush and a new code page after table saturation.

7. [ ] **P1 — Repair LoongArch code marking and TLB write eligibility.**  
   [dbt.c:488](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:488) marks a basic-block byte span, but [vm64.c:402](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:402) requires page-aligned ranges. Ordinary blocks therefore fail to acquire `VM_PAGE_HAS_CODE`; [dbt_smc.c:79](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_smc.c:79) then suppresses invalidation. [dbt_mem.c:324](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:324) separately republishes writable tags without the canonical code/COW/reservation gate.

   This affects VM-enabled production builds. Round code coverage outward, include high-address mappings, and use one write-gate implementation. Test repeated patches to both arena and high-address code.

8. [ ] **P1 — Invalidate `rvrt` executable blocks after file truncation.**  
   [darwin_main.c:228](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:228) flushes only the data TLB after file syscalls. Truncation advances `space->generation`, but cached execution at [darwin_dbt.c:780](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt.c:780) checks only the DBT-local generation.

   A warmed executable mapping truncated to zero can reuse translated code instead of taking a fetch fault. This applies to Darwin and fast Linux; [Makefile:939](/Users/angerman/Projects/zw3rk/rvrt/Makefile:939) copies the fast binary into the public runtime output. Connect backing/mapping changes to block validity and chain entry. Regress warm-code → truncate → branch, expecting guest SIGBUS.

9. [ ] **P1 — Stop PPC32 population/truncation maintenance from touching inaccessible host pages.**  
   [ppc32_vm.c:468](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:468) maps with final protection, then populates it. The failed-read branch at [vm_file.c:162](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file.c:162) writes into that destination. Truncate maintenance at [vm_file.c:276](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file.c:276) likewise touches readonly or already-beyond-EOF native pages. Regrowth does not restore the protection cleared by [vm32_tlb.c:404](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm32_tlb.c:404).

   Separate native mapping registration from anonymous staging; preserve requested protections across shrink/regrow. Test readonly mmap and two-page shrink/SIGBUS/regrow sequences.

10. [ ] **P1 — Translate LoongArch EOF offsets into mapping-relative guest addresses.**  
    [vm_file.c:384](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:384) computes a file-offset cutoff, then compares it directly with guest VA at line 394. Consequently truncating a high-address private mapping can discard dirty bytes that remain below EOF.

    Compute the affected interval using `file_off`, mapping length, and checked subtraction. Test dirty surviving pages and nonzero mapping offsets.

11. [ ] **P1 — Make MIPS64 quiescence registration fail closed.**  
    [quiesce.c:44](/Users/angerman/Projects/zw3rk/mips64rt/src/os/quiesce.c:44) permits 16 tracked workers, while [threads.c:80](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:80) permits 128 threads. When registration fails, [quiesce.c:282](/Users/angerman/Projects/zw3rk/mips64rt/src/os/quiesce.c:282) silently returns and callers continue mutation. Slot publication at line 89 also precedes initialization of fields read by scanners.

    Reserve, initialize, then publish slots; reject unsupported worker admission; synchronize retirement. Test 17 workers and forced pauses during registration.

12. [ ] **P1/P2 — Replace uninitialized or predictable `AT_RANDOM`.**

    | Repository | Evidence |
    |---|---|
    | **sparc32rt** | Darwin leaves `rand_bytes` uninitialized before copying it: [stack32.c:160](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/stack32.c:160). This exposes host stack bytes. |
    | **sparc64rt** | Darwin supplies zeros; Linux entropy failure also produces zeros: [guest_stack.c:254](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_stack.c:254). |
    | **ppc64rt** | Fixed bytes: [load.c:35](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:35). |
    | **mips64rt** | Clock/PID-seeded generator: [loader.c:248](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:248). |
    | **loongarch64rt** | Clock/PID-seeded generator: [loader.c:195](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:195). |
    | **mips32rt / ppc32rt** | Predictable failure fallbacks: [MIPS stack32.c:130](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/stack32.c:130), [PPC stack32.c:121](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_stack32.c:121). |

    Use backend OS entropy, handle short reads/interruption, and report failure explicitly. Restrict deterministic injection to test configuration.

13. [ ] **P1 — Preserve backing identity instead of substituting anonymous copies.**  
    A2 shared-file mappings become private staged copies in [i686 rt32_vm.c:173](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:173), [PPC32 ppc32_vm.c:444](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:444), and the misaligned Darwin branch of [MIPS32 vm_mmap.c:108](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:108). Separately, `mremap` forces anonymous replacement in [a32 vm.c:795](/Users/angerman/Projects/zw3rk/a32rt/src/vm.c:795) and [i686 rt32_vm.c:1068](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:1068).

    Retain backing identity and offsets through map/move/grow. Test two aliases, forked aliases, file visibility, and moving a shared mapping.

14. [ ] **P1 — Preflight VMA-table edits before changing host mappings.**  
    All five Class-A implementations can lose mapping records or widen a partial protection update when split capacity is exhausted:

    [a32 vm.c:270](/Users/angerman/Projects/zw3rk/a32rt/src/vm.c:270), [i686 rt32_vm.c:437](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:437), [MIPS32 vm.c:270](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm.c:270), [PPC32 vm_regions.c:204](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm_regions.c:204), [SPARC32 vm.c:301](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm.c:301).

    Construct the resulting interval set first, then commit mapping and metadata together. Regress full tables followed by middle-page unmap, partial mprotect, and fixed replacement.

15. [ ] **P1/P2 — Give shared address spaces one synchronized permission authority.**  
    MIPS32 and SPARC32 copy region changes into only selected contexts at [MIPS vm.c:121](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm.c:121) and [SPARC vm.c:137](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm.c:137), while peer interpreters read their context copies. Conversely, i686 allocates per-mm permission/COW arrays as `MAP_SHARED` at [vm_file.c:85](/Users/angerman/Projects/zw3rk/i686rt/src/vm/vm_file.c:85), allowing ordinary fork children to alter metadata belonging to independent address spaces.

    Separate thread state, shared-mm state, and family inode state. Test synchronized peer map/protect/unmap and child-only protection changes after fork.

The next batch should repair ownership and admission rather than introduce further abstractions:

16. [ ] **P2 — Replace misleading “family-shared” side tables with explicit ownership and consumers.**  
    Ordinary process-private statics hold the advertised family records in [a32 vm_file.c:47](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_file.c:47), [MIPS32 vm_file.c:72](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:72), [PPC32 vm_file.c:63](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file.c:63), and [SPARC32 vm_file.c:78](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:78). Atomic counters do not make that storage shared across fork.

    Concrete associated defects include PPC32 replacing an earlier mapping of the same numeric fd ([vm_file.c:104](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file.c:104)), i686 dropping an entire record on partial unmap ([vm_file.c:320](/Users/angerman/Projects/zw3rk/i686rt/src/vm/vm_file.c:320)), and SPARC32 initializing a newly registered file’s size to zero ([vm_file.c:109](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:109)). A32’s truncate hook also passes an end address of zero to invalidation ([vm_file.c:271](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_file.c:271)), which invalidates no pages.

    Use stable inode identity, separate mapping objects, retained-descriptor ownership, and complete split/unmap/remap hooks. Test dup/reopen, fd reuse, multiple aliases, and fork shrink/regrow.

17. [ ] **P2 — Separate shared inode metadata from process-local descriptors.**  
    `rvrt` stores local descriptor numbers in a shared table at [vm_file.c:177](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm_file.c:177), but destruction uses table-creator ownership at [vm_file.c:134](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm_file.c:134). A child-created entry can cause the parent to use or close an unrelated descriptor number. This is reachable through the **16 MiB shadow VM**, not the mature authoritative guest VM.

    LoongArch similarly retains numeric descriptors in shared inode rows, and [vm_file.c:54](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:54) tears down the table without closing retained duplicates. Keep descriptors in local ownership tables or acquire them through the capability broker.

18. [ ] **P2 — Make `rvrt`’s alternate arena metadata transactional before further integration.**  
    [vm64.c:143](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:143) explicitly allows dropping a surviving VMA tail when its 64-slot table is full. Mapping operations can alter host memory before `vma_add` reports exhaustion. Regrowth at [vm64.c:503](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:503) revives zeroed pages without re-establishing file backing.

    Keep these findings scoped to the alternate/shadow implementation. Either finish its backing/lifetime contract or isolate it from production hooks.

19. [ ] **P2 — Fix PPC64 VM destruction and global failure state.**  
    [vm64.c:340](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm64.c:340) resets the directory during destruction, retaining the L1 allocation; [vm_dir.c:127](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_dir.c:127) contains the actual freeing destructor. The retained pointer table is 2 MiB on a 64-bit host. [vm_dir.c:66](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_dir.c:66) also lets one allocation failure disable future arenas globally.

    Use the real destructor and per-instance failure state. Test repeated lifecycle operations and transient allocation failure.

20. [ ] **P2 — Validate complete ELF/stack admission before destructive setup.**  
    All five Class-A stack builders silently shorten argv/envp at 511 entries: [a32:89](/Users/angerman/Projects/zw3rk/a32rt/src/stack32.c:89), [i686:53](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_stack32.c:53), [MIPS32:89](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/stack32.c:89), [PPC32:56](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_stack32.c:56), [SPARC32:103](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/stack32.c:103).

    The three newer 32-bit builders also install fixed stacks without rejecting admitted ELF overlap. MIPS32 does not verify interpreter endianness against the main image at [elf32.c:657](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/elf32.c:657). SPARC64 main/interpreter ELF admission has diverged, detailed below. Preserve valid vectors or return `E2BIG`; validate reserved ranges and execution-mode compatibility before mapping.

21. [ ] **P2 — Close remaining A32 host-policy/error-path gaps.**  
    Large-page Linux mappings still forward guest-granular fixed ranges through [backend_linux.c:84](/Users/angerman/Projects/zw3rk/a32rt/src/os/backend_linux.c:84). Guest memory can retain host execute permission through [a32rt.h:253](/Users/angerman/Projects/zw3rk/a32rt/src/a32rt.h:253), contrary to the series invariant. Finally, failed `fstat` leaves `st` uninitialized before its EOF use in [vm_file.c:168](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_file.c:168).

    Centralize guest-to-host protection translation, implement large-page staging consistently, and propagate metadata-read failures.

For CLEAN, DRY, and YAGNI, the following are repository-local changes. Intentional copies between standalone translators are excluded.

| Repository | Prioritized local cleanup |
|---|---|
| **a32rt** | **P2:** consolidate global VMA/context mirrors at [vm.c:37](/Users/angerman/Projects/zw3rk/a32rt/src/vm.c:37) and separate permission state at [vm32.c:26](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:26). **P3:** consolidate repeated host-page union walks at [vm32.c:230](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:230) and line 317. `a32_vm32_tlb_probe`, `a32_vm32_tlb_miss`, and several file hooks have no runtime callers; inode generation fields have no behavioral consumer. |
| **i686rt** | **P2:** replace global/context/file-table mirrors with owned per-mm state. **P3:** unify duplicated pread/zero-fill loops in [rt32_vm.c:116](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm.c:116) and [vm_file.c:218](/Users/angerman/Projects/zw3rk/i686rt/src/vm/vm_file.c:218); their EINTR behavior differs. Fill/invalidate/fini at [vm32.c:78](/Users/angerman/Projects/zw3rk/i686rt/src/vm/vm32.c:78) lack runtime consumers; distinguish test-only COW APIs from integrated behavior. |
| **mips32rt** | **P2:** normalize ELF decoding once: [elf32.c:165](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/elf32.c:165) and line 509 duplicate validation/swapping. Unify region checks in [mem.c:188](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:188) and [proc.c:91](/Users/angerman/Projects/zw3rk/mips32rt/src/os/proc.c:91). **P3:** remove unused `next_seq`, unconsumed retained `host_fd`, and ineffective generation/minimum-shrink bookkeeping at [vm_file.c:60](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:60), after resolving ownership. |
| **ppc32rt** | **P2:** merge reservation implementations at [vm32.c:97](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm32.c:97) and [ppc32_vm.c:85](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:85); they disagree on alignment/low-guard behavior. Centralize repeated TLB publication at [vm32_tlb.c:122](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm32_tlb.c:122). **P3:** `g_arena_len` is write-only; page flags are never set; probe and broadcast-truncate helpers have no callers. |
| **sparc32rt** | **P2:** unify mapped-memory validation: [interp_mem.c:26](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:26) checks mappings, while [l2a_access.h:50](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:50) checks only low guard/wrap. **P3:** isolate/remove dormant reserve/miss helpers at [vm32.c:118](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm32.c:118) and unused COW/shrink/generation APIs beginning at [vm_file.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:126). The live DBT uses different protection/state arrays. |
| **rvrt** | **P2:** share normalized ELF validation/mapping between [image.c:244](/Users/angerman/Projects/zw3rk/rvrt/src/loader/image.c:244) and [elf32.c:117](/Users/angerman/Projects/zw3rk/rvrt/src/loader/elf32.c:117); share stack construction policy between [stack.c:71](/Users/angerman/Projects/zw3rk/rvrt/src/loader/stack.c:71) and line 159. Extract small family codec/staging helpers from [family_mm.c:22](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_mm.c:22), [family_file_index.c:22](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_file_index.c:22), and duplicated write/truncate staging. **P3:** `rv_elf32_entry` has no callers; `vm64.pages` is write-only; shadow generations/minimum-shrink fields have no runtime consumer. Keep test-facing family APIs explicitly classified. |
| **loongarch64rt** | **P2:** merge competing TLB write policies at [dbt_mem.c:324](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:324) and [vm64.c:551](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:551). Give global arena/page/map registries explicit ownership. **P3:** inode `resize_seq`, `code_generation`, `futex_pin_count` at [vm_file.h:25](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.h:25) lack consumers or complete lifecycle; global code generation at [vm64.c:53](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:53) is write-only. |
| **ppc64rt** | **P2:** choose one active reservation/atomic contract; [vm_atomic.c:109](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_atomic.c:109) installs a callback unused by production, while [interp.c:537](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:537) implements LR/SC separately. Remove duplicated fallback blocks and global request scratch. **P3:** unused `ppc64_vm_page_t`, code-range fields, and increment-only `quiesce_epoch` start at [vm.h:36](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm.h:36); code-mark declarations lack implementations/callers. |
| **mips64rt** | **P2:** distinguish the prototype handle VM at [vm64.c:391](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:391) from production mapping at [mem_table.c:230](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem_table.c:230). Prototype tests do not qualify the live mapper. **P3:** consolidate duplicated protection implementations at [vm64.c:182](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:182) and line 274; remove unused `priv`. If retained, fix `u0_record` merging then falling through to insert another record at line 74. |
| **sparc64rt** | **P2:** unify main and interpreter segment admission: [guest_run.c:301](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:301) omits checks present in [guest_interp_map.c:222](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_interp_map.c:222), including alignment and executable-entry validation. **P3:** alternate validators/TLB publication beginning at [vm64.c:140](/Users/angerman/Projects/zw3rk/sparc64rt/src/vm/vm64.c:140) and several file helpers have no callers. Fix partial-acquisition cleanup in [host_contract_family.c:177](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/host_contract_family.c:177): failure creating the second diagnostic directory leaks the first. |

The mutable singleton tables above generally lack a documented performance justification and obscure ownership. Refactor them around address-space or family lifetime. Two exceptions deserve preservation: ABI padding such as `flags_reserved`, and `rvrt`’s [documented POSIX-lock ownership singleton](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_zero_control.c:42). Neither is simply dead state.

Curated-C11 cleanup also includes prohibited `strcpy` at [SPARC64 guest_proc.c:109](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_proc.c:109), unnecessary `__typeof__` at [LoongArch minsys.c:569](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/minsys.c:569), and compiler-specific atomic publication in otherwise C11-described modules. The `strcpy` has a preceding length check; this is a style-contract violation, not a demonstrated overflow.

Validation completed:

- **67 selected translation units passed native Darwin syntax checks** across the ten repositories. Checks used direct Apple Clang, the explicit SDK, `-std=c11 -Werror=vla -pedantic -Wall -Wextra`, and repository-specific includes/feature flags. SPARC64 retained its existing `-Wno-error=unused-function`.
- Exact `rvrt` check, exit **0**, no diagnostics:

  ```sh
  timeout --kill-after=30s 60s \
    /Library/Developer/CommandLineTools/usr/bin/clang \
    -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror \
    -fsyntax-only -Isrc -Iinclude \
    src/vm/vm64.c src/vm/vm_file.c \
    src/loader/elf32.c src/loader/stack.c \
    src/loader/image.c src/loader/image_transport.c \
    src/memory/space.c src/runtime/family.c \
    src/runtime/family_mm.c src/runtime/family_shmem.c
  ```

- Whole-repository symbol searches checked runtime versus test-only reachability. Arithmetic probes confirmed the MIPS64 overflow, A32 zero-page invalidation, and LoongArch coordinate error.
- **No full builds, guest/oracle tests, Linux large-page tests, concurrency executions, or benchmarks ran.** No performance improvement is claimed.

Audited heads: `a32rt d81bebbf61c5`, `i686rt 76bed20b1531`, `mips32rt 9379b3dfd14b`, `ppc32rt 04d50ceab36d`, `sparc32rt e74075e2b56b`, `rvrt 726e3d50f2fc`, `loongarch64rt ac4f0a9203dd`, `ppc64rt eef6dc00cc4d`, `mips64rt 99e1e8c20e83`, `sparc64rt e6e5c844e20f`.