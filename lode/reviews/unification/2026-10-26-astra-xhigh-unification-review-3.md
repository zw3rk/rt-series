**Rev 3 is not ready to freeze.** The scalar Soft-TLB lookup is sound, but the surrounding contracts still permit broken aliasing, incorrect fault recovery, lost reservation invalidation, stale translated code, and deadlocks.

I did not read `lode/reviews/*` or modify files. Citations below refer to the inspected worktrees, including `rt-series` at `731638b`, `rvrt` at `a7182d5`, and `hyper-linux` at `5c72284`. The latter two have advanced beyond the plan’s pinned revisions. These are design findings against existing implementation requirements, not claims that the proposed components already exist.

1. **Critical — The universal `G + gva` / `S + gva` model cannot represent arbitrary guest file mappings.**

   [Plan:302–308](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:302) requires both windows to reference one coherent backing. Existing mappings preserve guest `MAP_SHARED`/`MAP_PRIVATE`, file descriptors, and offsets through host `mmap`, as illustrated by [mips32rt/vm_mmap.c:34](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:34) and [line 73](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:73).

   Three failures follow:

   - Replacing a range in `G` with a file mapping leaves `S` pointing at the original shared-memory object.
   - Separately mapping a file `MAP_PRIVATE` into both windows creates independent COW mappings. A write through either view can immediately make the views disagree.
   - On a 16 KiB host, mapping file offset zero at guest VA `0x11000` requires file byte zero at offset 4096 within a host page. Host-page remapping cannot express that placement. Mapping both windows does not solve this alignment problem.

   **Fix:** Represent backing identity and offset per guest page. Use direct `G` mappings only where all subpages are compatible with one host mapping. Route incompatible chunks through checked indirect accesses. Replace universal `S + gva` pointers with canonical backing spans and bounce buffers. Apply EOF/COW handling to `vm32` as well as `vm64`.

2. **Critical — Shared dual-window backing breaks private-memory semantics across `fork`.**

   The backing specified at [plan:302](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:302) is host `MAP_SHARED`. Inheriting that backing across host `fork` makes guest-private heaps and stacks shared between parent and child. Current i686 process cloning explicitly relies on the window being private COW: [clone.c:528](/Users/angerman/Projects/zw3rk/i686rt/src/os/clone.c:528). Linux preserves mapping attributes across fork. [Linux `mmap` documentation](https://man7.org/linux/man-pages/man2/mmap.2.html)

   Mapping each alias privately is not a repair: it causes the intra-process alias divergence described above.

   **Fix:** Separate *sharing between aliases* from *sharing between guest processes*. Fork must create independent ownership for private mappings while retaining genuinely shared objects, then rebuild coherent aliases in each process. Define mixed shared/private subpage handling and private-futex `mm_id` renewal before freezing [`rt_host_fork()`](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:532).

3. **Critical — PC recovery followed by whole-instruction replay can execute architectural effects twice.**

   [Plan:310–313](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:310) already provides a mixed-page recovery mechanism; its state-recovery contract is insufficient.

   i686 PUSH decrements live ESP before the faultable store: [emit_mov.c:390](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_mov.c:390). On a writable quarter whose enclosing host page is read-only, the store faults after ESP changes. Replaying PUSH from those registers decrements ESP again. Using the old `ctx` instead loses earlier instructions’ live changes in the same block. A32 also emits multiple host accesses for one LDM/STM: [a64_emit.c:1897](/Users/angerman/Projects/zw3rk/a32rt/src/a64_emit.c:1897).

   The proposed immutable `guest_npc` is also insufficient. SPARC JMPL computes and saves its target dynamically before executing the delay slot: [emit_int.c:634](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/emit_int.c:634). MIPS retains its indirect target in `x25`: [emit_int.c:311](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:311). One static site record cannot contain every execution’s next PC.

   **Fix:** Define complete per-site recovery recipes: architectural registers, flags, cached FP/vector state, dynamic branch targets, and completed suboperations. Either reconstruct instruction-entry state for safe replay or complete only the faulting suboperation. Enter general recovery code through a safe landing trampoline. Include PUSH/CALL, multi-transfer, and indirect delay-slot fault/sigreturn cases.

4. **Critical — The new direct-write paths bypass reservation, atomicity, and SMC protocols.**

   The [write-tag predicate](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:193) and [bare `str` hit path](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:226) do not participate in existing reservation protocols.

   LoongArch ordinary stores hold a lock across reservation invalidation and mutation: [interp_mem.h:78](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:78). SC subsequently trusts `ll_valid` under that lock: [interp_amo.c:234](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:234). An intervening warm-TLB store can therefore leave SC incorrectly successful. Keeping AMOs in helpers does not help when inline stores bypass their synchronization. RVRT likewise requires every write to update reservation epochs: [space.c:889](/Users/angerman/Projects/zw3rk/rvrt/src/memory/space.c:889).

   Shadow writes introduce a second bypass. i686 protects translated source pages through `G` and invalidates on a `G` write fault: [engine.c:110](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:110), [engine.c:226](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:226). Writing new instructions through `S` avoids that fault.

   Nor is interpreter fallback automatically atomic: PPC32 STWCX performs a software reservation check followed by a plain store, and SPARC32 LDSTUB performs separate load/store operations. [PPC32 implementation](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:792), [SPARC32 implementation](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:487)

   **Fix:** Establish one backing-aware write protocol covering DBT, interpreter, syscall copyout, aliases, debugger writes, and signal frames. It must handle reservations, atomic synchronization, COW, code generations, and current-block retirement. Direct write tags require explicit eligibility under that protocol.

5. **Major — Quiescence lacks the admission and progress rules needed to prevent deadlock.**

   [Plan:272–287](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:272) correctly excludes blocking I/O from guest-pointer leases, but leaves these cases unresolved:

   - A owns `g_vm_mutation_lock`; B blocks acquiring it while still classified RUNNING. A waits for B to become PARKED.
   - A worker checks `g_vm_mutating == 0`, then publishes a lease after the mutator has completed its drain check.
   - A DBT loop keeps hitting cached translations and never enters the three named admission points. Merely setting `yield_requested` does not guarantee acknowledgement.
   - The mutation initiator itself still holds a lease or runtime lock needed by a sibling.

   Existing SPARC execution can repeatedly enter translated blocks inside its dispatcher loop: [dbt.c:654](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:654). RVRT’s current scheduler instead documents explicit owner, checkpoint, and lock-release rules: [scheduler.h:72](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/scheduler.h:72).

   **Fix:** Freeze a state machine with atomic reader admission, mutation-owner exclusion, parked mutation contenders, synchronized worker registration, and bounded safepoints on every dispatch/chaining path. Include `mmap(MAP_FIXED)` and other mapping replacements explicitly. Preserve the existing serialized execution contract unless parallel execution is separately qualified.

6. **Major — The mutation transaction publishes state before knowing whether the host operation succeeded.**

   Step 3 updates VMA/inode state; Step 4 performs the potentially failing `mprotect`, `munmap`, or `ftruncate`. [Plan:282–287](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:282)

   If truncation fails because of permissions, seals, or limits, the prescribed sequence can leave the software EOF and COW state describing a shrink that never happened. Destructive zeroing cannot simply be undone.

   Existing RVRT uses prepare → host operation → commit: [file.c:1366](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:1366).

   **Fix:** Stage allocations and proposed metadata without publishing destructive changes. While workers remain quiescent, execute the host operation, reconcile its actual result, then commit. Specify abort and partial-success behavior, including failures after irreversible host effects.

7. **Major — Provider A cannot replace native family coordination with an in-process inode table.**

   [Plan:328–330](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:328) combines process-local inode metadata with detached anonymous private copies. After fork, a child’s truncation cannot update the parent’s cached EOF, revoke its detached copies, or invalidate its translated code.

   Native kernel truncation only handles the mappings it knows about. It does not update translator metadata or unrelated generated-code pages. Existing RVRT explicitly requires canonical source-mutation notification, including shrink/regrow between accesses: [family_file.h:60](/Users/angerman/Projects/zw3rk/rvrt/src/memory/family_file.h:60).

   **Fix:** Retain a minimal family-wide mutation authority for Provider A, including membership, ordered events, backing lifetime, and DBT invalidation. Broker retirement in [U5:658](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:658) must follow replacement of these semantics, not merely replacement of file mapping calls.

8. **Major — Provider B needs acknowledged remote invalidation and a translator notification ABI.**

   [Plan:343](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:343) allows reconciliation before the next vCPU entry. A sibling already running guest code may continue using old mappings without another entry boundary. Hyper-linux already has explicit mechanisms to force active vCPUs out: [thread.c:1380](/Users/angerman/Projects/zw3rk/hyper-linux/src/thread.c:1380).

   Furthermore, updating Stage-1 PTEs and performing TLBI does not invalidate A64 translations generated from the changed file and stored elsewhere. `code_generation` has no specified connection to each translator’s DBT dependency index, direct chains, IBTC, or RAS.

   **Fix:** Define a prepare/stop/acknowledge/commit/resume protocol across affected VMs. Add a negotiated host-to-translator mutation interface, with identities, affected ranges, sequence numbers, and acknowledgements. Block resumption until both mapping translations and generated guest-code translations have been reconciled.

9. **Major — COW and EOF rules still confuse translation granularity with guest page semantics.**

   The plan correctly identifies SPARC64’s 8 KiB guest page size, but [Provider A:330–331](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:330) always promotes 4 KiB and rounds tail zeroing to 4096.

   For an 8 KiB private guest page, modifying its lower half must establish the appropriate private-page snapshot for the whole guest page. Subsequent truncation must preserve the partial final private page consistently. Independently tracking the two halves as dirty and clean gives different behavior.

   On a 4 KiB host, an otherwise valid 8 KiB guest EOF page can also contain a whole host page beyond EOF. The software guard permits access, but the direct host mapping still SIGBUSes.

   Finally, flushing TLB entries is insufficient for wholly removed dirty pages. RVRT explicitly discards full-page COW ownership on shrink; its regression expects old private bytes to disappear after regrowth. [file_backing.c:197](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_backing.c:197), [test_file_backing.c:205](/Users/angerman/Projects/zw3rk/rvrt/test/test_file_backing.c:205)

   **Fix:** Separate host allocation, translation, and guest semantic/COW granules. Materialize safe guest EOF tails, discard removed private pages, and retain ordered resize history. Current size plus a generation counter cannot reconstruct a shrink followed by regrowth that a sibling observes together.

10. **Major — Provider B’s stated COW promotion changes permissions without establishing private ownership.**

    [Plan:347](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:347) specifies marking DIRTY and installing a writable PTE. Neither operation creates a private copy. If the clean page shares inode backing, subsequent writes modify shared data.

    Existing shared backing really is mapped `MAP_SHARED`: [rvrt_shared.c:126](/Users/angerman/Projects/zw3rk/hyper-linux/src/rvrt_shared.c:126). Remapping an existing HVF-backed host address is also unsafe under the current implementation’s documented VA→PA caching assumptions: [fork_ipc.c:7933](/Users/angerman/Projects/zw3rk/hyper-linux/src/fork_ipc.c:7933).

    **Fix:** Specify allocation, copying, per-view ownership, GPA/PTE retargeting, and publication order. Keep file-COW state distinct from fork-sharing state. Publish write permission only after the correct private backing exists.

11. **Major — Futex handling needs its own lifetime and atomic admission contract.**

    The “no raw guest pointer across blocking calls” rule at [plan:277](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:277) is not reconciled with the raw-pointer futex API at [plan:512](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:512). A bounce copy cannot replace the futex word: comparison and enqueue must remain atomic with respect to wake operations. [Linux futex contract](https://man7.org/linux/man-pages/man2/futex.2.html)

    Canonical keys alone do not provide queue synchronization or backing lifetime. RVRT retains backing ownership when enqueueing: [futex.c:786](/Users/angerman/Projects/zw3rk/rvrt/src/linux/futex.c:786).

    There is also a concrete lock-order integration hazard. Hyper-linux accesses the word under its futex bucket lock: [futex.c:504](/Users/angerman/Projects/zw3rk/hyper-linux/src/futex.c:504). Inserting a COW helper that acquires `mmap_lock` there reverses the documented rank-1 → rank-7 order. [syscall_internal.h:10](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_internal.h:10)

    **Fix:** Prepare/promote/pin the backing before bucket acquisition; compare and enqueue under the queue’s synchronization; park using a retained wait object without holding a global VM reader lease. Define locked/unlocked COW-helper variants and the inode-control lock’s rank. Preserve endian conversion and private-file key transitions.

12. **Major — Mutation coverage and inode lifetime are incomplete.**

    The proposed provider must cover existing mutation paths beyond the named truncate calls. Hyper-linux’s `fallocate(mode=0)` independently extends files; `sendfile` and `copy_file_range` directly write destination files. [syscall_io.c:3601](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_io.c:3601), [line 3680](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_io.c:3680), [line 3778](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_io.c:3778)

    Without common publication, file growth leaves cached EOF state stale, and copied instructions leave generated blocks stale.

    Exporting existing controller descriptors at fork also does not specify how siblings independently mapping the same inode *after* fork obtain one controller. Unlink/reopen correctness requires retained inode ownership, not path-based rediscovery; RVRT already requires exact descriptors to outlive identity uses. [file_identity.h:27](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_identity.h:27)

    **Fix:** Centralize actual-result publication for every admitted mutation, including partial writes and shared-mapping stores. Define family-wide controller interning, descriptor lifetime, split/unmap/remap ownership, and biased `msync`.

    Current unsupported operations should remain explicit exclusions: hyper-linux rejects hole-punch/collapse modes and file-backed moving/growing `mremap`; I found no `remap_file_pages` handler. Their absence alone is not a new regression. [fallocate restrictions](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_io.c:3576), [mremap restriction](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall.c:3885)

13. **Major — The Darwin signal-atomic blocking contract is not complete.**

    [Plan:409–410](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:409) proposes a wakeup pipe/kqueue token plus a state check. That can wake a multiplexed wait; it does not automatically interrupt a subsequent blocking libc `read`, `write`, or `open`.

    The supposedly complete interface also omits `ws + expected_seq` from potentially blocking operations such as [`rt_host_openat`](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:423). Existing RVRT explicitly puts `openat` through its safe syscall gate: [runtime_main.c:1328](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:1328).

    **Fix:** Specify a commitment mechanism per syscall class. Use nonblocking operations plus multiplexed wakeups where valid, and a proven interruption/commit protocol elsewhere. Define partial-result and restart handling. Apply it to FIFO open, blocking descriptor operations, and cancellation—not only read/write.

14. **Major — AOT migration omits recovery-table persistence and rebinding.**

    Miss stubs reference `&block->sites[k]`, and faults depend on that table. [Plan:262–266](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:262) An emitter-version bump alone does not restore this metadata after a warm-cache load.

    RVRT’s serialized block contains source, text, and relocations, but no site table; its current relocation applicator declines non-guest relocations. [format.h:63](/Users/angerman/Projects/zw3rk/rvrt/src/aot/format.h:63), [relocate.c:73](/Users/angerman/Projects/zw3rk/rvrt/src/aot/relocate.c:73) A32’s existing format does preserve its PC map. [aot.c:41](/Users/angerman/Projects/zw3rk/a32rt/src/aot.c:41)

    **Fix:** Define validated relative metadata or deterministic reconstruction, helper/site relocation, guest-PC rebasing, and metadata lifetime tied to executable-code lifetime. Warm-cache tests must actually exercise misses and faults after process restart and rebasing.

15. **Minor — Correct the baseline and qualify the frozen scalar listing.**

    The statement that all four Class-B DBTs call a helper on every load/store is inaccurate. MIPS64 already emits direct aligned accesses: [emit_mem.c:107](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:107). The other three trees do not currently have the named `src/dbt/emit_mem.c`.

    The BE store table also omits the byte-store case, and the comment “after step 5” conflicts with the table’s correct placement after `cbnz`. [Plan:226](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:226), [line 241](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:241)

    **Fix:** Refresh the source inventory and state explicitly that the seven-instruction template covers eligible scalar accesses. Paired, vector, atomic, ASI, and merge operations require their own lowering contracts or retained checked fallback paths.

The requested assembly checks produced these results:

- **The swapped `ldp` operands are correct.** Loads obtain `read_tag/addend`; stores obtain `addend/write_tag`. These are non-writeback forms.
- **The lookup preserves NZCV.** It uses `sub`, not `subs`, and `cbnz` does not alter flags. Rev 3 explicitly saves/restores NZCV around the miss helper. The scalar signed/BE load sequences are correct.
- **PPC64 needs the documented ABI migration before using this scratch convention.** Its current entry ABI retains `cpu`, `mem_ops`, and `mem_ctx` in `x0..x2`. [trampoline_a64.S:10](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/trampoline_a64.S:10)
- **I found no demonstrated current Class-B scalar-helper SIMD-clobber regression.** Existing FP emitters generally commit results between instructions. Preserve that invariant or explicitly save live Q/FPCR/FPSR state when extending the design.
- **`CBNZ` has signed imm19 reach: −1,048,576 through +1,048,572 bytes.** `B` has signed imm26 reach. Rev 3 branches on `x4` and places stubs at each block’s end, so a 16–64 MiB aggregate cache does not itself cause overflow. Cache-end placement would. Require checked relocation bounds and branch islands/veneers when necessary. [Arm instruction documentation](https://support.arm.com/documentation/dui0801/l/A64-General-Instructions/CBNZ--A64-?lang=en)

The migration gates should change accordingly:

| Wave | Required addition |
|---|---|
| **U0** | Validate reservation interference, concurrent mutators, and precise recovery before freezing interfaces. Add a delay-slot architecture probe; LoongArch alone cannot qualify that contract. |
| **U1** | Preserve the complete reachable runtime and AOT metadata closure. |
| **U2** | Qualify guest-semantic COW granules, mutation failure paths, futex admission, and all write hooks. |
| **U3** | Test incongruent file aliases, private/shared fork behavior, PUSH/CALL recovery, SMC through `S`, and mixed-page atomics on **16 KiB and 64 KiB** hosts. |
| **U4** | Require acknowledged cross-VM invalidation, physical COW separation, post-fork inode interning, and translator DBT notification. |
| **U5–U6** | Retire family machinery only after native and `hl` replacement semantics pass; exercise recovery from warm AOT caches. |

Read-only verification included source tracing and a Python model of the scalar predicate: **688,128 cases passed**, and all four logical-immediate masks were encodable. No assembler, runtime conformance suite, or builds were run.

<details>
<summary>Exact scalar verification command</summary>

```sh
python3 -c 'MASK=(1<<64)-1
pages=[0,0x1000,0x12345000,0x100001000,0xffff000000001000,0xfffffffffffff000]
checks=0
for n in (1,2,4,8):
    mask=MASK ^ (0xfff-(n-1))
    enc=[]
    for size in (2,4,8,16,32,64):
        for ones in range(1,size):
            base=(1<<ones)-1
            for rot in range(size):
                part=((base>>rot)|(base<<(size-rot)))&((1<<size)-1)
                value=sum(part<<off for off in range(0,64,size))
                if value==mask:
                    enc.append((size,ones,rot))
    assert enc, hex(mask)
    for p in pages:
        for tag in pages+[MASK]:
            for off in range(4096):
                gva=p+off
                hit=(((gva&mask)-tag)&MASK)==0
                expected=(tag==p and (off&(n-1))==0)
                assert hit==expected,(n,p,tag,off)
                if hit: assert off+n<=4096
                checks+=1
    print("width",n,"logical-immediate",hex(mask),"encoding",enc)
print("tag/alignment/no-cross-page checks:",checks,"PASS")'
```

Exited zero. This checks the predicate and logical-immediate construction, not assembled machine code or concurrent execution.

</details>