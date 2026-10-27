**The plan is not ready to freeze.** Its main risks are incomplete memory semantics, removal of code that remains necessary, and acceptance gates that do not establish the claimed behavior. No repository files were edited.

**Critical findings**

1. **The “5-insn Soft-TLB” neither assembles nor validates a complete memory access.**
   [UNIFICATION-PLAN.md:212](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:212):
   - `ubfx x2, x1, #8, #12` extracts address bits 8–19. It does not calculate `((gva >> 12) & 4095) << 4`.
   - `ldp x2, x3, [x20, x2]` is invalid: AArch64 `ldp` has no register-offset addressing form. The assembler rejected this exact operand.
   - The listing already contains six instructions, including the final load. A straightforward corrected lookup requires seven, before additional guards.
   - Only the starting page is checked. An access crossing into another guest page can bypass its permissions or use an unrelated host backing. This is particularly dangerous when both guest pages occupy one accessible 16 KiB Darwin page.
   - Masking the address with `bic` does not check alignment. Endian conversion, signed loads, atomics, and precise fault state are also absent.

   Existing MIPS64 lowering explicitly checks alignment and records the fault PC, then performs endian conversion: [emit_mem.c:73](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:73), [emit_mem.c:85](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:85), [emit_mem.c:171](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:171).

   **Fix:** Specify an assembled fast path for a defined subset—such as naturally aligned, single-page scalar accesses—with explicit read/write permission selection. Route cross-page, unusual alignment, atomic, and special-endian cases through validated paths. Preserve fault-PC reconstruction and guest architectural state.

2. **Class-A Darwin cannot enforce 4 KiB permissions using bookkeeping plus direct window accesses.**
   [UNIFICATION-PLAN.md:378](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:378) retains direct `[x20,wAddr,uxtw]` lowering while relying on `vm32.c` to track sub-16K permissions. Tracking cannot prevent a load from an unmapped quarter or a store into a read-only quarter of an accessible host page.

   The existing Class-A emitter directly accesses memory: [mips32rt/emit_int.c:563](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_int.c:563). The cited LoongArch implementation explicitly relies on software permission checks in `la64_mem_ptr`, rather than tracking alone: [mem_min.c:137](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:137).

   **Fix:** Choose software-checked memory lowering for standalone Darwin Class A, or define a restricted profile that rejects incompatible mappings. Test partial `mprotect`, partial `munmap`, `MAP_FIXED` replacement, cross-quarter accesses, and syscall buffer validation. Anonymous allocation plus `pread` solves ELF placement, not protection.

3. **Retiring `rvrt` family machinery after U3 removes native Linux functionality without replacing it.**
   [UNIFICATION-PLAN.md:477](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:477) retires `family_*` and `guest_memory*` while [line 32](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:32) promises native AArch64 Linux execution.

   These subsystems manage guest memory, not just APFS adaptation. `rvrt` creates software page payloads in [space.c:22](/Users/angerman/Projects/zw3rk/rvrt/src/memory/space.c:22), creates the process family in [guest_memory.c:292](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/guest_memory.c:292), and seeds canonical MM state at [guest_memory.c:306](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/guest_memory.c:306). Native Linux cannot infer guest file associations from those allocated payloads.

   Native Linux regression targets explicitly exercise this behavior: [Makefile:939](/Users/angerman/Projects/zw3rk/rvrt/Makefile:939), [Makefile:3029](/Users/angerman/Projects/zw3rk/rvrt/Makefile:3029).

   **Fix:** Separate portable, native-Linux, and negotiated `hl` memory providers. Retire each mechanism only after its replacement passes the existing native Linux and `hl` suites. Preserve family MM, scheduling, reservation epochs, and exec lifetime behavior until independently replaced.

4. **The existing `hl` shared arena is not the proposed truncation replacement.**
   [UNIFICATION-PLAN.md:253](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:253) proposes automatic EOF invalidation and `SIGBUS`. Current code deliberately provides narrower guarantees:
   - Managed family files/memfds; uncontrolled external writers excluded: [rvrt_shared.h:59](/Users/angerman/Projects/zw3rk/hyper-linux/src/rvrt_shared.h:59).
   - Retained views survive guest unmapping: [rvrt_shared.h:54](/Users/angerman/Projects/zw3rk/hyper-linux/src/rvrt_shared.h:54).
   - Shrinking retained mappings returns `EBUSY`: [syscall_fs.c:5749](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_fs.c:5749).
   - Shared `MAP_FIXED` and initial `PROT_NONE` return `EOPNOTSUPP`: [syscall.c:2291](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall.c:2291).
   - Read-only descriptors and whole mapped pages beyond EOF are rejected: [syscall.c:2314](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall.c:2314).

   **Fix:** Treat U3 as new MM functionality. Specify inode-wide mapping ownership, translator reverse mappings, pointer quiescence, cross-process invalidation, fault classification, and shrink/regrow recovery. A policy rename cannot supply these semantics or automatically support Class-A fixed windows.

**Major findings**

5. **U1 classifies live SPARC64 donor code as dead.**
   [UNIFICATION-PLAN.md:20](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:20) says `src/main.c` never calls the carried tree. In fact, [sparc64rt/main.c:17](/Users/angerman/Projects/zw3rk/sparc64rt/src/main.c:17) imports its host contract and calls parsing, authority validation, image resolution, cache admission, and statistics functions. The donor implementation also invokes family creation: [host_contract_identity.c:452](/Users/angerman/Projects/zw3rk/sparc64rt/src/rt64/runtime/host_contract_identity.c:452).

   **Fix:** Inventory reachable symbols and headers separately for each repository. Migrate the complete live dependency closure before deletion, preserving CLI, authority, cache, identity, and self-test behavior.

6. **The claimed completed baseline includes a PPC64 production entry point that cannot execute guests.**
   Despite the completion claim at [UNIFICATION-PLAN.md:13](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:13), [ppc64rt/main.c:99](/Users/angerman/Projects/zw3rk/ppc64rt/src/main.c:99) prints “guest execution lands in Phase 1” and returns 2. H3 instead builds a separate harness: [h3_run.sh:292](/Users/angerman/Projects/zw3rk/ppc64rt/tests/h3_run.sh:292).

   **Fix:** Distinguish component/harness qualification from shipped-binary qualification. Require actual guest execution through each final artifact before declaring a non-regressing baseline.

7. **The Soft-TLB invalidation and publication protocol is missing.**
   [UNIFICATION-PLAN.md:220](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:220) specifies only `page_tag = ~0ULL`. With per-thread tables, this does not define:
   - How other running threads stop using revoked translations.
   - When old host backing can be reclaimed.
   - How tag/addend publication avoids mismatched observations.
   - How file truncation, alias changes, fork/exec, and writable executable guest pages interact with TLB/JIT invalidation.

   **Fix:** Freeze the ownership and synchronization protocol with the entry layout. Use owner-thread updates plus synchronized invalidation/safepoints, or another explicitly proven mechanism. Require concurrent unmap/remap/protect tests before fast-path acceptance.

8. **The proposed truncation algorithm loses existing private-COW behavior.**
   [UNIFICATION-PLAN.md:255](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:255) uniformly zeroes trailing bytes for private and shared mappings. Existing `rvrt` preserves private bytes in a partial final COW page and discards ownership only for whole removed pages: [file_backing.c:197](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_backing.c:197), [file_backing.c:246](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_backing.c:246).

   Also, the proposed `hl_open_file_t.backing_size` does not exist in [fd_object.h:112](/Users/angerman/Projects/zw3rk/hyper-linux/src/fd_object.h:112). Separate opens have separate OFDs; invalidation must follow inode/backing identity and survive descriptor closure.

   **Fix:** Define shared, clean-private, and dirty-private transitions separately. Place authoritative size/version and mapping membership on a retained backing object. Add dirty-private shrink/regrow differential tests.

9. **The frozen backend contract cannot express the advertised supported surface.**
   [UNIFICATION-PLAN.md:339](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:339) lacks networking, polling/epoll, thread lifecycle, fork/exec/wait, host signal-mask/delivery, worker interruption, and restart-safe blocking-call interfaces, despite the promises at [line 390](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:390).

   The futex interface at [line 358](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:358) also cannot represent bitsets, absolute deadlines/clocks, requeue operands, or shared identity. Existing Linux handling already passes these operands: [loongarch64rt/clone.c:279](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:279), [clone.c:311](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:311).

   **Fix:** Inventory reachable host operations before freezing the interface. Specify canonical structures, interruption/restart rules, and either complete backend primitives or an explicitly permitted portable implementation. Guest `sigaction` state can remain common; host notification and masking still need a contract.

10. **`mmap_guest` has FD/flags arguments, but leaves their meaning unresolved.**
    They are present at [UNIFICATION-PLAN.md:325](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:325). The missing decisions concern guest versus host addresses, descriptor ownership, placement, rounding, 4 KiB file offsets, `MAP_FIXED`, rollback, sharing, EOF faults, and removal of host execute permission from guest data.

    **Fix:** Separate host allocation/mapping primitives from guest VMA operations and define their ownership boundary. Query host page size; Linux does not universally imply 4096 bytes. Existing code already queries it: [mem_min.c:80](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:80).

11. **The “existing x28 context convention” is false, and the example clobbers live state in several engines.**
    [UNIFICATION-PLAN.md:498](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:498) describes a uniform convention that does not exist:
    - LoongArch pins context in `x28`: [trampoline_a64.S:35](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/trampoline_a64.S:35).
    - MIPS64 pins context in `x19`, window base in `x20`: [dbt.h:13](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.h:13).
    - PPC32 uses `x28` for the chaining epoch: [dbt.h:43](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/dbt.h:43).
    - i686 keeps guest GPRs in `w0–w7`: [emit.h:7](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit.h:7).

    The proposed sequence uses `x4` despite listing only `x2/x3` as scratch and overwrites NZCV with `cmp`.

    **Fix:** Preserve existing per-engine ABIs initially, or make register migration an explicit coordinated change covering emitters, trampolines, helpers, fault reconstruction, chaining, and cached code. Keep `x18` reserved; define scratch, flags, LR, and miss-stub preservation.

12. **Waves and gates do not establish the promised qualification.**
    [UNIFICATION-PLAN.md:450](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:450) assumes a universal `tests/parity_suite.sh`; it is absent in LoongArch64, MIPS64, and PPC64. SPARC64’s script permits `GAP` outcomes and documents macOS execution through `hl`, not standalone Darwin: [parity_suite.sh:13](/Users/angerman/Projects/zw3rk/sparc64rt/tests/parity_suite.sh:13), [parity_suite.sh:32](/Users/angerman/Projects/zw3rk/sparc64rt/tests/parity_suite.sh:32).

    Existing checks are largely structural: [ppc64rt/Makefile:62](/Users/angerman/Projects/zw3rk/ppc64rt/Makefile:62), [rt-series/Makefile:65](/Users/angerman/Projects/zw3rk/rt-series/Makefile:65). U3 requires runnable RV32 dispatch before U4 qualifies RV32 execution: [plan:471](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:471), [plan:479](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:479).

    **Fix:** Add a contract/prototype gate before freezing U1; separate structural migration from memory changes. Define explicit native-Linux, Linux-under-`hl`, and standalone-Darwin semantic matrices. Move runnable RV32 acceptance after U4. Gate retirement on provider parity, and test AOT preservation throughout migration rather than waiting until U5.

**Minor findings and baseline corrections**

13. **The numerical baseline is not reproducible as labeled.**
    [UNIFICATION-PLAN.md:118](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:118) says `src/ + include/`, but several rows omit `include/`. Counting tracked `.c/.h/.S` blobs under both directories at the **cited commits**, with LOC counted as newline bytes, gives:

    | Repository | Cited commit | Files | LOC |
    |---|---|---:|---:|
    | a32rt | d84feb3 | 18 | 18,369 |
    | i686rt | f40d6e3 | 73 | 38,696 |
    | rvrt | 33385fc | 224 | 66,452 |
    | mips32rt | aeaeeeb | 37 | 14,352 |
    | ppc32rt | cab7ae6 | 50 | 19,224 |
    | sparc32rt | 83b1f63 | 51 | 16,093 |
    | loongarch64rt | 2064710 | 124 | 44,046 |
    | ppc64rt | 70498a0 | 280 | 68,135 |
    | mips64rt | 3ea43a7 | 123 | 46,765 |
    | sparc64rt | 2bcf6d4 | 304 | 78,868 |
    | hyper-linux | be7721f | 182 | 141,338 |

    `rvrt` HEAD had advanced to `ebba2ed`; the other inspected heads matched. The four donor trees total **168,783 source LOC**, including live code, rather than a verified ~155k dead-code deletion.

    The a32 baseline also misses existing AOT linkage and execution: [Makefile:56](/Users/angerman/Projects/zw3rk/a32rt/Makefile:56), [main.c:256](/Users/angerman/Projects/zw3rk/a32rt/src/main.c:256). Its oversized-file list uses incorrect names and omits oversized files.

    **Fix:** Publish the counting command, suffix exclusions, pinned commits, and dirty-tree status; regenerate the inventory.

14. **Existing Darwin handling needs a per-repository description.**
    The LoongArch `MAP_JIT`/`mprotect`/write-mode problem is accurately identified: [dbt.c:146](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:146), [dbt.c:171](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:171), [dbt.c:184](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt.c:184). The other three active caches use ordinary mmap/mprotect and already account for host page size: [mips64rt/dbt.c:97](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:97), [ppc64rt/cache.c:33](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/cache.c:33), [sparc64rt/a32host.h:86](/Users/angerman/Projects/zw3rk/sparc64rt/include/a32host.h:86).

    **Fix:** Distinguish existing host-page rounding, guest sub-page enforcement, and MAP_JIT publication; they are separate capabilities.

15. **Several terminology and evidence claims are too strong.**
    - `fd_object`, exact-descriptor APFS identity, and ACL subsystems do exist. However, ACL synthesis is deliberately conservative and rejects native ACLs; it is not general ACL translation: [hl_posix_acl.h:18](/Users/angerman/Projects/zw3rk/hyper-linux/src/hl_posix_acl.h:18).
    - The implemented 4 KiB permission tables are guest Stage-1 tables; the primary Stage-2 mapping is RWX: [guest.c:27](/Users/angerman/Projects/zw3rk/hyper-linux/src/guest.c:27), [guest.c:325](/Users/angerman/Projects/zw3rk/hyper-linux/src/guest.c:325).
    - SPARC64 advertises an 8 KiB Linux guest page size, distinct from its internal mapping granule: [guest_run_priv.h:39](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_priv.h:39).
    - The >98% hit rate, 2–3-cycle access, >70% build reduction, and ≥10× performance target lack supporting measurements.

    **Fix:** Separate guest ABI page size, software translation granule, and host page size. Preserve conservative authority boundaries. Instrument and measure before setting performance acceptance thresholds.

Validation used read-only source inspection, pinned Git-object counts, and an assembler probe of the proposed sequence. No full builds, semantic suites, or performance measurements were run.