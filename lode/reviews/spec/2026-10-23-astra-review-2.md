**The second review does not support the claim “All 48 Resolved.”** Using the original review’s numbering, I assess **28 findings as closed at the specification level, 19 as partially addressed, and one as open**. Several repairs also introduce new errors.

The architecture remains workable, but the specification and Muse Spark plan are **not ready to freeze as binding implementation instructions**. The Major findings below affect observable behavior, ABI compatibility, integration, or acceptance evidence. No Critical defect was established by this static review.

I inspected the original review and dispositions, specification, plan, goal, host contract, lane cards, lode material, header, ABI assertions, Makefile, and flake, together with relevant sibling implementations. **I made no file changes.**

| Repository | Latest inspected HEAD |
|---|---|
| `a32rt` | `d84feb311a0a` |
| `i686rt` | `f24db6ed6f0c` |
| `rvrt` | `2056cb1d6d11` |
| `hyper-linux` | `fb879f088d63` |
| `rt-series` | Working tree; no initial commit |

Closure below means the original specification or planning defect has been corrected. It does not certify that the future implementation has landed or passed runtime qualification.

**Remaining and new findings follow.**

1. **R2-01 — Major: The disposition ledger does not correspond to Review #1 and contains nonexistent resolutions.**

   [The ledger](/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-23-astra-review-1-dispositions.md:4) declares all findings resolved, but its numbered subjects differ from the original review. Original finding #1 concerns RV64 qualification overclaims; disposition #1 concerns i686 worktree topology. Original #2 concerns incorrect RVRT defect IDs; disposition #2 concerns test stubs.

   Several claimed resolutions also contradict the files:

   - Disposition #35 claims an added `W2-L7` extraction lane. That lane is absent.
   - Disposition #40 claims counter emulation. [SPEC:201](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:201) deliberately specifies `SIGILL`.
   - Disposition #26 claims sign-extended RV32 register storage, while the specification correctly requires zero-extension.
   - Disposition #31 identifies the hardware-TSO capability as bit 6; the actual header uses bit 9.

   Counts still drift: [SPEC:116](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:116) says nine syscall numbers while its list contains ten including `truncate64`; [STATE:76](/Users/angerman/Projects/zw3rk/rt-series/lode/STATE-OF-PLAY-2026-10-23.md:76) lists eighteen correctness entries under “17,” and line 96 lists thirteen comment entries under “14.”

   **Required correction:** Rebuild the disposition table against the original IDs, preserving each original subject and linking actual changed text and evidence. Separate planned work, implemented changes, and qualified behavior.

2. **R2-02 — Major: The prescribed RVRT D1 repair introduces an errno regression.**

   [SPEC:139](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:139) requires checking positioned-I/O permission before `path_descriptor`, making `pread64`/`pwrite64` on `O_PATH` return `ESPIPE`.

   For a valid nonnegative offset, Linux first obtains the descriptor through `fdget`, which filters `FMODE_PATH`. That produces `EBADF` before the positioned-I/O mode check. The existing O_PATH-first result is correct for this case. The sibling defect ledger’s explanation is itself mistaken. See [Linux positioned I/O](https://raw.githubusercontent.com/torvalds/linux/v6.18/fs/read_write.c) and [descriptor lookup](https://codebrowser.dev/linux/linux/fs/file.c.html#fdget).

   **Required correction:** Preserve `EBADF` for this case and reconcile the ledger against a native Linux oracle before assigning a repair. Matching a ledger entry does not establish that its proposed change is correct.

3. **R2-03 — Major: The i386 signal repair restores x87 state from the wrong representation and leaves XSAVE metadata unresolved.**

   [SPEC:132](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:132) and [Wave 1:101](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:101) direct restoration from `_fxsr_st`. Linux’s i386 signal ABI instead treats the legacy x87 environment and `_st` fields as authoritative. A handler can modify that legacy image; restoring the duplicate FXSR image would discard its edits. [Linux signal restoration](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/x86/kernel/fpu/signal.c) explicitly folds in the legacy representation.

   The corrected offsets and 624-byte size are useful. However, [the assertion file](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:41) still describes `FP_XSTATE_MAGIC1` without defining the associated extended size, feature mask, state size, and trailing magic. The sibling serializer currently writes magic1 alone.

   **Required correction:** Specify authoritative x87 restoration and test deliberately different edits to the two images. Choose either a valid nonextended representation or complete extended-state metadata according to the [Linux UAPI](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/x86/include/uapi/asm/sigcontext.h).

4. **R2-04 — Major: The Class-B descriptor contract rejects valid descriptor-zero launches.**

   [HOST-CONTRACT:138](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:138) requires `--image-fd FD` to have `FD >= 3` and file offset zero.

   The authoritative [RVRT contract](/Users/angerman/Projects/zw3rk/rvrt/docs/HOST-CONTRACT.md:338) permits image descriptor zero. [initial_image.c:36](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/initial_image.c:36) applies the `>=3` restriction to the borrowed **runtime descriptor**; the supplied image descriptor may be any nonnegative descriptor. The umbrella contract confuses the two.

   The offset-zero requirement is also unsupported: position-independent reads or an explicit offset protocol provide the relevant guarantee.

   **Required correction:** Preserve descriptor presence independently of its numeric value, the distinction between image and runtime descriptors, and their exact ownership rules.

5. **R2-05 — Major: The argv protocol is corrected, but the migration DAG still qualifies the producer before its consumers.**

   [PLAN:72](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:72) and [Wave 1:17](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:17) place the host migration before the runtime parser changes. The host then emits `--execfn`, which both current parsers reject: [a32rt/main.c:123](/Users/angerman/Projects/zw3rk/a32rt/src/main.c:123) and [i686rt/main.c:77](/Users/angerman/Projects/zw3rk/i686rt/src/main.c:77).

   The i686 card additionally names image-fd/`AT_EXECFD` work without explicitly assigning `--execfn` parsing.

   **Required correction:** Land backward-compatible consumers first, or define an integrated host/runtime candidate with a joint checkpoint. Require explicit ownership of both parsers and qualify custom argv0, empty argument vectors, and descriptor zero through that integrated candidate.

6. **R2-06 — Major: Software TSO still lacks a safe transition when sharing begins.**

   [SPEC:129](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:129) chooses ordering during translation using `ctx->num_threads > 1`. There is no corresponding field or transition protocol in the inspected implementation. [clone.c:303](/Users/angerman/Projects/zw3rk/i686rt/src/os/clone.c:303) and its thread-start path do not invalidate or recompile previously unordered blocks.

   Consequently, merely setting the flag for future translations cannot make existing cached code ordered after the first clone. Thread count also cannot establish the absence of external observers of shared mappings.

   **Required correction:** Define a stable ordering policy or a promotion protocol completed before sharing starts. Cover cached translations, interpreter fallback, helpers, and all memory emitters. The specification names `emit_sse.c` without assigning it; it also names a nonexistent `emit_fpu.c`.

7. **R2-07 — Major: The hardware-TSO qualification test cannot establish the promised property.**

   [HOST-CONTRACT:111](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:111) and [SPEC:161](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:161) require a store-buffering, or SB, litmus before advertising hardware TSO.

   The both-zero SB outcome is permitted under TSO. Observing or failing to observe it cannot distinguish TSO from weaker ordering. This is a central property of the [x86-TSO model](https://www.cl.cam.ac.uk/~pes20/weakmemory/cacm.pdf).

   **Required correction:** Specify hardware configuration and readback, plus discriminating ordering tests with explicit forbidden outcomes across initial, thread, fork, and exec vCPU paths. Finite litmus runs provide supporting evidence; they do not independently prove the mode is enabled.

8. **R2-08 — Major: Corrected signal prefixes conceal incorrect complete frame descriptions.**

   Three inconsistencies remain:

   - [SPEC:361](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:361) gives SPARC32 a four-byte `extramask[1]` and omits `stack_t stack` and `extra_size`. Linux’s rt frame contains an eight-byte mask and those fields before `rwin_save`. Subsequent offsets and alternate-stack restoration therefore differ. [Linux SPARC32 frame](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/kernel/signal_32.c).
   - [Matrix:59](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:59) inserts `mc_fp` and `mc_i7` into the SPARC64 rt frame. Those belong to a separate get/setcontext structure. The master specification’s general rt-frame sequence is better. [Linux SPARC64 frame](https://codebrowser.dev/linux/linux/arch/sparc/kernel/signal_64.c.html).
   - [Matrix:53](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:53) describes a MIPS O32 prefix as 24 bytes plus eight bytes. The actual prefix is sixteen bytes of `rs_ass` plus eight bytes of `rs_pad`, **24 bytes total**, consistent with SPEC:300. [Linux MIPS frame](https://raw.githubusercontent.com/torvalds/linux/master/arch/mips/kernel/signal.c).

   **Required correction:** Freeze complete wire structures and offsets, then reconcile all three documents. Assertions for the 96/192-byte SPARC prefixes do not validate their frame tails.

9. **R2-09 — Major: PPC64’s unused-vector rule can lose VRSAVE across a signal.**

   [SPEC:435](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:435) permits `v_regs=0` when VMX/VSX has not been used.

   Linux deliberately supplies the aligned vector pointer even before the first vector instruction, because VRSAVE may already have been written. Saved MSR bits separately indicate which vector state is valid. [Linux PPC64 signal handling](https://codebrowser.dev/linux/linux/arch/powerpc/kernel/signal_64.c.html).

   **Required correction:** Distinguish unsupported facilities from unused registers. Specify VRSAVE preservation and `MSR_VEC`/`MSR_VSX` validity semantics, including a signal test that writes VRSAVE without executing a vector instruction.

10. **R2-10 — Major: Delay-slot handling still prescribes a nonexistent MIPS field and lacks a page-boundary progress rule.**

    [SPEC:277](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:277) requires writing `sc_cause`. Modern O32 UAPI repurposes that slot as `sc_hi1`; N32/N64 signal contexts have no cause field. Cause.BD bookkeeping must remain internal while saved-PC and restart behavior follow Linux. [MIPS sigcontext UAPI](https://codebrowser.dev/linux/linux/arch/mips/include/uapi/asm/sigcontext.h.html).

    Separately, [SPEC:86](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:86) requires translating a branch and delay slot together, but terminates before a branch in the last page word. Re-entering at that PC encounters the same rule; no progress path is specified.

    **Required correction:** Define the interpreter/slow path or safe cross-page translation explicitly. Include an oracle case where a not-taken branch-likely or annulled slot lies on an unmapped following page, so eager decoding does not manufacture a fault.

11. **R2-11 — Major design gap: A number-translation table cannot implement MIPS’s 128-signal namespace on a 64-signal host.**

    [SPEC:296](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:296) and [SPEC:455](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:455) promise the complete namespace using copied signal machinery and translation tables.

    The source substrates are explicitly limited: [a32rt/signals.c:571](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:571) rejects numbers above 64, while [rvrt/signal.h:25](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.h:25) uses 64 actions and a 64-bit pending mask. AArch64 also has no native SIGEMT counterpart.

    **Required correction:** Specify guest-owned 128-bit masks, actions, pending state, real-time queues, and routing through signal-generating and waiting APIs across threads and processes. Assign this work and test signals above 64, queued duplicates, and SIGEMT.

12. **R2-12 — Major: The new page policy changes syscall semantics and misidentifies the permission layer.**

    [HOST-CONTRACT:36](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:36) says `mmap`, `mprotect`, `munmap`, `mremap`, and `brk` round addresses and lengths to 4 KiB.

    That blanket rule is wrong. Applicable unaligned addresses must be rejected; lengths have syscall-specific treatment; `brk` preserves a byte-granular logical break while backing allocations are page-granular. Existing [RVRT memory handlers](/Users/angerman/Projects/zw3rk/rvrt/src/linux/memory.c:212) already distinguish these cases.

    Lines 39–41 also attribute 4-KiB permissions to stage 2. The inspected primary [HVF mapping](/Users/angerman/Projects/zw3rk/hyper-linux/src/guest.c:312) is RWX; the relevant 4-KiB permission descriptors and splitting are guest stage-1 behavior.

    **Required correction:** Specify validation, rounding, and returned values per syscall, and describe the actual permission-enforcement layer.

13. **R2-13 — Major: The MIPS64 VA limit conflicts with the copied signal initializer.**

    [SPEC:447](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:447) selects an exclusive N64 limit of `1ULL << 40`.

    The copied [RVRT signal initializer](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.c:301) rejects limits at or below that value and searches for its trampoline starting at 1 TiB. Direct reuse therefore rejects the new profile. N32 likewise needs explicit placement below its smaller limit.

    The matrix also labels `0x7fff8000` as native MIPS32’s Linux limit. Linux distinguishes native `CONFIG_32BIT`’s `0x80000000` from the MIPS64 compatibility limit. [Linux MIPS address limits](https://codebrowser.dev/linux/linux/arch/mips/include/asm/processor.h.html).

    **Required correction:** Freeze and assign profile-specific stack, mmap, interpreter, and signal-page placement. Describe any intentionally narrower synthetic limit as a policy choice.

14. **R2-14 — Major: The pinned RV32 syscall table includes a nonexistent `wait4(260)`.**

    [SPEC:214](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:214) and [Wave 2:78](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:78) prescribe RV32 `wait4(260)` and its `rusage` conversion.

    Linux v6.18 assigns that entry to `time32` and `64`, neither selected for RV32. The applicable interface is `waitid(95)`, including its optional raw-syscall `rusage` output. See the [v6.18 syscall table](https://github.com/torvalds/linux/blob/v6.18/scripts/syscall.tbl) and [RISC-V ABI selection](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/kernel/Makefile.syscalls).

    **Required correction:** Generate the frozen syscall set from the selected ABI. Qualify the actual waitid conversion path and the expected unsupported result for raw syscall 260.

15. **R2-15 — Major: Feature advertising still precedes implementation, and LoongArch’s two feature interfaces disagree.**

    [SPEC:90](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:90) prohibits advertising extensions before implementation, but the cards contradict it:

    - [Wave 4:32](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:32) advertises LoongArch FPU in Phase 2; scalar FP arrives in Phase 3.
    - [Wave 4:60](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:60) advertises PPC64 FPU/VMX/VSX/IEEE128 before their Phase 3 implementation.

    Static libc and feature probes can select those instructions too; moving dynamic linking later does not resolve this.

    Additionally, [SPEC:386](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:386) omits CPUCFG word-2 LAM bit 22 while [SPEC:395](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:395) advertises `HWCAP_LOONGARCH_LAM`. LAM_BH/LAMCAS are separate bits. See [CPUCFG definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/include/asm/loongarch.h) and [Linux feature probing](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/kernel/cpu-probe.c).

    **Required correction:** Use one implemented-feature profile to derive HWCAP, CPUCFG, admission, and test workloads. Move necessary implementation earlier or define restricted bootstrap profiles.

16. **R2-16 — Major plan ambiguity: LoongArch syscall availability contradicts its experiment card.**

    [SPEC:393](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:393) explicitly supports `fstat(80)` and `newfstatat(79)`. [Wave 4:22](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:22) explicitly says they are omitted.

    These are incompatible observable contracts. I verified the contradiction; I did not independently resolve the complete selected LoongArch syscall table in this pass.

    **Required correction:** Choose and document the pinned ABI policy, reconcile both locations, and make raw-syscall tests assert it.

17. **R2-17 — Major: RV32 integration still omits the real I/O conversion and multithread admission paths.**

    [SPEC:220](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:220) requires iovec conversion, but [Wave 2’s ownership](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:39) omits the relevant `linux/file.c`/`linux/io.c` seam. The existing [shared writer](/Users/angerman/Projects/zw3rk/rvrt/src/linux/io.c:65) imports sixteen-byte vectors with 64-bit fields.

    A wrapper is possible, but its translated-input interface must preserve the worker-aware I/O path. Passing RV32 vectors through unchanged is incompatible.

    The integration card also names futex 422 without explicitly resolving [runtime_main.c:3497](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:3497), whose live-worker admission recognizes RV64 numbers 72/73/113 rather than RV32 413/414/403.

    **Required correction:** Assign the conversion seam and normalize syscall identity before admission, or extend admission explicitly. Include multithread RV32 waits and clock calls in the integrated gate.

18. **R2-18 — Major: Several “runnable” acceptance commands still cannot execute the claimed checks.**

    [Wave 1](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:22) retains concrete blockers:

    | Prescribed command | Inspected behavior |
    |---|---|
    | hyper-linux `make build test-a32-smoke` | Both targets absent; relevant actual targets include `hl` and `test-a32-hello`. |
    | i686 bare `make` | Defaults to help. |
    | `./build/i686rt ./build/tests/...` | Actual artifacts use `_build/i686rt` and flat `_build/test_*` paths. |
    | GOAL’s `make check` in every repository | a32rt has no such target; i686rt’s remains a placeholder. |

    See [i686rt/Makefile](/Users/angerman/Projects/zw3rk/i686rt/Makefile:6), [hyper-linux/Makefile](/Users/angerman/Projects/zw3rk/hyper-linux/Makefile:680), and [GOAL:60](/Users/angerman/Projects/zw3rk/rt-series/GOAL.md:60).

    The broker lane’s hello smoke also does not exercise its FIFO, SCM, poll-copyout, and fork repairs.

    **Required correction:** Freeze commands that build the changed artifact, transport it to the specified host, and run discriminating regressions. Give missing runner work an actual prerequisite lane.

19. **R2-19 — Major: Threshold prose has improved, but executable acceptance still does not enforce it.**

    [PLAN:120](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:120) now states zero LTP framework deaths, at least 80/103 LTP passes, and at least 125/343 libc-test passes.

    [Wave 1:110](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:110) instead counts `PASS` in `build/ltp.log`; the [runner](/Users/angerman/Projects/zw3rk/i686rt/tools/run-ltp.sh:43) writes `tests/hardening/results/ltp.tap`. The command does not enforce the denominator, framework-death condition, or libc threshold.

    Line 111 still appends “+ shell assertion” for CoreMark as prose. Neither command binds results to a freshly built candidate.

    **Required correction:** Implement machine-enforced result parsing, expected totals, failure/skip policy, CRC validation, and artifact identity.

20. **R2-20 — Major: Exclusive ownership remains incomplete beyond RV32.**

    [Wave 1’s ownership lists](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:24) still leave predictable integration conflicts:

    - The host startup-environment repair needs `hl.c`, assigned concurrently to another lane.
    - The TSO lifecycle task modifies `fork_ipc.c` after the broker merge, but its ownership list does not receive that file.
    - The i686 TSO task names SSE memory changes without owning `emit_sse.c`.
    - The actual i686 host header has no assigned migration owner.

    **Required correction:** Add explicit coordinator prerequisites or sequential file-ownership transfers. These are known dependencies and should not consume repeated worker escalations.

21. **R2-21 — Major plan gap: The Class-B copy prerequisite lacks a concrete producer or adaptation contract.**

    [PLAN:165](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:165), [GOAL:29](/Users/angerman/Projects/zw3rk/rt-series/GOAL.md:29), and [Wave 4:7](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:7) depend on an `rt64` substrate copied from RVRT. There is no existing `rvrt/src/rt64/`, and the disposition’s claimed `W2-L7` extraction lane is absent.

    [SPEC:83](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:83) names source directories, but does not freeze the copy map, architecture-dependent seams, or acceptance responsibility.

    **Required correction:** Either assign and accept a preparatory extraction, or give each receiving lane a concrete source-to-destination map and adaptation contract. This can preserve the copy-first, standalone-repository policy.

22. **R2-22 — Minor: The performance sequence still predetermines the fixes and changes measurement substrate.**

    [SPEC:121](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:121) now correctly starts with default-off timers, a commit, and baseline measurement. However, line 126 still mandates dead-flag elimination and IBTC linking regardless of what that measurement finds.

    The baseline is specified on Lima, while the nominated remeasurement runner uses Docker. Comparable host, workload, warm-up, and configuration are not established.

    **Required correction:** Make optimization selection conditional on the measured split, keep before/after conditions identical, and require explicit confirmation or retraction of the hypothesis.

23. **R2-23 — Minor: Several timeout commands bound compilation but leave execution unbounded.**

    [Wave 2:37](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:37) and subsequent cards use:

    ```text
    timeout 120 make ... && _build/test_...
    ```

    The executable after `&&` is outside the timeout. Similar patterns occur in host checks, and many examples omit the required kill-after bound.

    **Required correction:** Apply `timeout --kill-after=30s` to the complete build-and-test command group, preserving its exit status.

24. **R2-24 — Minor: The mandatory line-limit gate is falsely described as existing and adds unassigned refactoring.**

    [PLAN:185](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:185) says `check-line-limits` exists in i686rt. It does not exist in the inspected translator Makefiles.

    Applying the universal limits also requires substantial work outside the assigned fixes: `a32rt/src/syscalls.c` has 4,330 lines and `rvrt/src/runtime_main.c` has 5,088.

    **Required correction:** Define the intended gate scope and owner. If whole-tree compliance is required, make its refactoring an explicit prerequisite rather than an implicit acceptance blocker.

25. **R2-25 — Minor: Header synchronization targets the wrong i686 path.**

    [HOST-CONTRACT:102](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:102) and [a32host.h:21](/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h:21) direct synchronization to `../i686rt/src/rt32/a32host.h`, which does not exist.

    The compiled header is [i686rt/include/a32host.h](/Users/angerman/Projects/zw3rk/i686rt/include/a32host.h). The repaired version semantics are sound, but the migration instructions would leave this consumer unchanged.

    **Required correction:** Fix the path and assign its update and equality check.

26. **R2-26 — Minor: The host CLI status table still labels proposed aliases as implemented.**

    [HOST-CONTRACT:82](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:82) says a32rt implements `--rootfs`; its [parser](/Users/angerman/Projects/zw3rk/a32rt/src/main.c:142) implements `--sysroot`. Line 89 marks `--no-host` implemented, whereas the inspected implementation recognizes [the environment variable](/Users/angerman/Projects/zw3rk/a32rt/src/host.c:27), and the parser rejects that flag.

    The i686 statistics/GDB rows similarly group CLI and environment support that are not interchangeable.

    **Required correction:** Record each spelling independently and assign proposed aliases explicitly.

**Verification of every original finding is recorded below.** “Closed” is scoped to the original reported defect; a newly discovered problem in the same area is identified separately.

| Original # | Status | Verification |
|---:|---|---|
| 1 | **Closed** | [SPEC:61](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:61) and STATE now preserve RVRT’s bounded qualification and explicit exclusions, consistent with sibling SUPPORT. |
| 2 | **Closed** | [SPEC:137](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:137) reconciles D4/D13/D23/D24/D26 against the pinned ledger. The ledger’s incorrect D1 prescription is a new finding, R2-02. |
| 3 | **Partial** | [HOST:61](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:61) fixes argv0, `--execfn`, and descriptor-zero semantics; migration ordering remains invalid. R2-05. |
| 4 | **Closed** | [SPEC:107](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:107) assigns host file-backed mremap, runtime backing/reservation handling, and both-host writeback qualification. |
| 5 | **Partial** | Unaligned-safe ordering and `emit_exit.c` ownership are added; ordering transitions and emitter coverage remain incomplete. R2-06. |
| 6 | **Partial** | [SPEC:130](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:130) fixes alignment and FP offsets; restoration authority and extended metadata remain wrong/incomplete. R2-03. |
| 7 | **Closed** | [ABI assertions:71](/Users/angerman/Projects/zw3rk/rt-series/tests/check_abi_invariants.c:71) encode sigaction 16, D state 264, aligned FP union 528, ucontext 816, and frame 944 bytes. |
| 8 | **Partial** | [Wave 2:96](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:96) adds runtime integration; I/O conversion and live-worker admission remain incomplete. R2-17. |
| 9 | **Closed** | [SPEC:218](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:218) now distinguishes pointer/long-dependent compound structures. Integration ownership is tracked under #8/#31. |
| 10 | **Closed** | [SPEC:180](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:180) distinguishes XLEN-wrapped instruction addresses from checked, nonwrapping syscall buffers. |
| 11 | **Closed** | [SPEC:239](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:239) uses existing XLEN/ABI/profile-digest identity and assigns `runtime/aot_cache.c`. |
| 12 | **Closed** | [SPEC:260](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:260) has nonoverlapping context offsets and sixteen cached registers; assertions corroborate the layout. |
| 13 | **Closed** | [SPEC:295](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:295), cards, and matrix consistently use the 104-byte O32 kernel `stat64`. |
| 14 | **Closed** | [SPEC:296](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:296) corrects MIPS signal numbers. Delivering the full namespace needs the additional design in R2-11. |
| 15 | **Closed** | [SPEC:337](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:337) rejects V8+ and `EM_SPARC32PLUS`. |
| 16 | **Closed** | [SPEC:474](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:474), cards, and matrix update both SPARC64 carry flags. |
| 17 | **Partial** | SPARC prefixes are corrected to 96/192 bytes; complete frame tails remain inconsistent. R2-08. |
| 18 | **Partial** | PPC32 inline storage and PPC64 reserve/pointer structure are corrected; the unused-vector pointer rule remains wrong. R2-09. |
| 19 | **Partial** | LoongArch mask arithmetic and CPUCFG word selection are repaired; LAM consistency and early FP advertising remain. R2-15. |
| 20 | **Closed** | [SPEC:428](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:428) corrects PPC64 symbolic masks and removes unintended features. Advertising order is tracked separately. |
| 21 | **Closed** | [SPEC:411](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:411) uses the ABI field and encoded local-entry semantics; fixed `+8` is removed. |
| 22 | **Closed** | [SPEC:278](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:278), MIPS64 specification, and cards explicitly distinguish legacy/NaN2008 profiles and qualification. |
| 23 | **Partial** | Per-profile limits are explicit, but MIPS native/compat attribution and signal placement remain unresolved. R2-13. |
| 24 | **Partial** | Three page-size layers are documented; syscall rounding and permission-layer descriptions introduce errors. R2-12. |
| 25 | **Closed** | [SPEC:498](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:498) and cards consistently exempt SPARC from musl and use glibc/nolibc. |
| 26 | **Closed** | [HOST:154](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:154) adds masked flags, optional predicates, launch policy, and O32 rejection rules. |
| 27 | **Closed** | [HOST:111](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:111) and line 143 define conservative lifecycle scope and Class-B opt-in. The proposed qualification test is insufficient, R2-07. |
| 28 | **Partial** | [HOST:131](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:131) restores authorities and exclusions but introduces the image-fd restriction. R2-04. |
| 29 | **Open** | Existing-repository acceptance commands still include missing targets, wrong paths, help-only builds, and inadequate smoke coverage. R2-18. |
| 30 | **Partial** | Thresholds and denominators are now stated, but the executable assertions remain incomplete or invalid. R2-19. |
| 31 | **Partial** | Several ownership omissions are fixed; RV32 I/O, host lifecycle files, SSE emitters, and header migration remain. R2-17/R2-20/R2-25. |
| 32 | **Partial** | RV32 integration and MIPS/SPARC reuse edges are added. Phase-2 feature advertising still precedes implementation. R2-15. |
| 33 | **Closed** | [GOAL:33](/Users/angerman/Projects/zw3rk/rt-series/GOAL.md:33) and STATE require nondestructive inventory, equivalence, dirty/untracked and active-state review, and approval before disposal. |
| 34 | **Partial** | Causes are relabeled hypotheses and instrumentation comes first; predetermined fixes and measurement comparability remain. R2-22. |
| 35 | **Closed** | [PLAN:29](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:29) requires explicit pinned worker worktrees, startup assertions, and protected review without reverting user changes. |
| 36 | **Partial** | [SPEC:494](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:494) adds meaningful independent oracle cases. Reservation invalidation through helpers/shared aliases is still not explicitly gated; page-final delay-slot coverage also needs R2-10. |
| 37 | **Closed** | [README:20](/Users/angerman/Projects/zw3rk/rt-series/README.md:20) and pinned STATE observations now record merged SSE/x87/H1/H4 and bounded multiblock AOT. |
| 38 | **Closed** | [STATE:101](/Users/angerman/Projects/zw3rk/rt-series/lode/STATE-OF-PLAY-2026-10-23.md:101) distinguishes thirteen Round-17 IDs, additional D201, and candidate-tip reinspection. Some shorthand still conflates the totals. |
| 39 | **Closed** | [SPEC:186](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:186) provides correct compressed-F bit mappings and ranges without the extra bit 7. |
| 40 | **Closed** | [SPEC:201](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:201) explicitly selects `SIGILL`; automatic libc fallback is no longer claimed. The disposition incorrectly describes emulation. |
| 41 | **Closed** | [SPEC:208](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:208) pins v6.18 and preserves old interval-timer layouts and `_llseek` ordering. The new wait4 table error is R2-14. |
| 42 | **Closed** | [SPEC:387](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:387) uses `RDTIME.D` and consistent 1-GHz CPUCFG frequency parameters. |
| 43 | **Closed** | [SPEC:398](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:398) distinguishes 16-byte headers from 32-byte LASX payload alignment. Cards should retain “payload” in their shorthand. |
| 44 | **Closed** | [SPEC:351](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:351) distinguishes ASI `0x0a` from privileged `0x0b` and defines the optional override. |
| 45 | **Partial** | Version/consumer semantics are repaired; the i686 synchronization path and ownership remain wrong. R2-25. |
| 46 | **Partial** | Prefixes, `--`, inherited descriptors, and Darwin/APFS wording are repaired; implemented CLI claims remain inaccurate. R2-26. |
| 47 | **Partial** | [Makefile:55](/Users/angerman/Projects/zw3rk/rt-series/Makefile:55) and flake now include useful ABI assertions and narrow the umbrella claim. Complete-frame, header-sync, and plan-structure coverage remain incomplete; the mandatory modularity gate is unassigned. |
| 48 | **Partial** | SIB, `.gnu.attributes`, `faligndata`, nine-phase counting, and `[U]` usage are corrected. Exact inventory/count inconsistencies remain, as recorded in R2-01. |

Several substantial changes are therefore valid: the RV32 base signal layout, i386 field offsets, MIPS context allocation and stat size, SPARC carry handling and stack prefixes, ELFv2 entry rules, NaN-profile distinction, conservative host capability policy, worktree protection, and explicit integration checkpoints. Those corrections should be retained while addressing the remaining defects.

**Read-only verification produced these results:**

```text
make check-docs
PASS — CHECK-DOCS OK (18 files verified)

timeout --kill-after=30s 60s \
  /Library/Developer/CommandLineTools/usr/bin/clang \
  -std=c11 -Wall -Wextra -Werror=vla -pedantic \
  -fsyntax-only include/a32host.h
PASS — exit 0

timeout --kill-after=30s 60s \
  /Library/Developer/CommandLineTools/usr/bin/clang \
  -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -std=c11 -Wall -Wextra -Werror=vla -pedantic \
  -Iinclude -fsyntax-only tests/check_abi_invariants.c
PASS — exit 0; compile-time assertions evaluated
```

The compiler wrapper initially encountered denied cache writes; direct Clang invocation completed the read-only checks. I did **not** execute the ABI test binary, `make check`, `nix flake check`, sibling builds, QEMU oracles, Lima suites, or hyper-linux qualification. The runtime stack-alignment loop therefore remains unexecuted in this review, and the passing static assertions establish only the properties they actually encode.