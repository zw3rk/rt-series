**The draft is not ready to serve as a binding implementation plan or frozen host contract.** Its overall architecture is reasonable, but several prescribed ABI layouts are wrong, important integration work has no owner, and multiple acceptance commands cannot establish the claimed results.

I read all 16 requested files and cross-referenced the relevant sibling implementations, worktrees, Git history, Linux UAPI, and architecture references. **I made no file changes.** This was a static engineering audit, not runtime qualification. No Critical defect was established under that scope; the Major findings below block acceptance.

The sibling repositories changed during the review:

| Repository | Document baseline | Latest inspected HEAD |
|---|---|---|
| `a32rt` | `d84feb3` | `d84feb311a0a` |
| `i686rt` | `11cc65c` | `071460db0a04` |
| `rvrt` | `884ae73` | `1e0fde1279b6` |
| `hyper-linux` | `fb879f0` | `fb879f088d63` |

The cited hashes are real. `a32rt`’s `v0.1.0` tag resolves correctly. `6352d84` belongs to the **hyper-linux** worktree named `i686rt-l6a`; its two commits beyond the host baseline and the broker tip’s 206 commits beyond that baseline checked out. Findings distinguish historical observations from incorrect claims and subsequent changes.

1. **Major — The RV64 milestone-completion claim exceeds the repository’s qualification evidence.**

   [STATE-OF-PLAY:18](/Users/angerman/Projects/zw3rk/rt-series/lode/STATE-OF-PLAY-2026-10-23.md:18) calls P0–P3 and R0–R7 complete. The authoritative sibling [SUPPORT.md:99](/Users/angerman/Projects/zw3rk/rvrt/docs/SUPPORT.md:99) explicitly leaves full R5/H2 behavior, process/clone cases, the finite application suite, and full AOT qualification incomplete. It also distinguishes diagnostic host runs from accepted normal-policy execution.

   Canonical MM and attributed-runtime tests establish particular capabilities, not completion of every milestone. The newer two-block AOT commit does not change that distinction.

   **Correction:** Describe accepted combinations of artifact, host, engine, libc, and process mode. Preserve the sibling’s explicit exclusions when defining Wave 1 acceptance.

2. **Major — Wave 1 assigns several RVRT defect numbers to unrelated problems.**

   [SPEC:145](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:145) and [SPEC:154](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:154) do not match the actual ledger:

   | ID | Umbrella description | Actual RVRT ledger entry |
   |---|---|---|
   | D4 | Repeated compilation | Stale host-contract fork-lifetime prose |
   | D13 | `getrandom` return check | BF16 signaling-NaN classifier |
   | D24 | `exec_import` truncation | `exec_args.c` runtime-fault/error classification |
   | D26 | `active_process` restoration | Native SIGCHLD disposition flags |
   | D23 | Broken `cc` symlink | Correctly identified |

   See [rvrt/DEFECTS.md:54](/Users/angerman/Projects/zw3rk/rvrt/DEFECTS.md:54), [:181](/Users/angerman/Projects/zw3rk/rvrt/DEFECTS.md:181), [:336](/Users/angerman/Projects/zw3rk/rvrt/DEFECTS.md:336), and [:365](/Users/angerman/Projects/zw3rk/rvrt/DEFECTS.md:365). D1/D2 are also correctness findings, not merely comment hygiene.

   **Correction:** Reconcile each ID against a pinned ledger revision before dispatching the lane. Otherwise workers can repair unrelated code while marking actual defects resolved.

3. **Major — The proposed argv/`AT_EXECFD` changes require a coordinated protocol migration.**

   [SPEC:103](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:103) assumes the existing host emits:

   ```text
   a32rt -- TARGET_PATH GUEST_ARGV0 ...
   ```

   Actual [hyper-linux/src/a32.c:323](/Users/angerman/Projects/zw3rk/hyper-linux/src/a32.c:323) emits `-- guest_argv[0] guest_argv[1...]`, without a separate target-path token. Unconditionally skipping that first token would drop the original guest argv0.

   Separately, i686rt startup does not consume `AT_EXECFD`; it reopens `ctx->exec_path`. The host lane explicitly calls its execfd “forward-compat only.” Host-side pinning therefore does not yet provide end-to-end pinned-image loading.

   **Correction:** Change both runtime parsers and both host launch/exec wrappers together. Test custom argv0, zero/one/multiple arguments, descriptor zero, and inherited descriptors. `AT_EXECFD=0` is valid; absence must be detected separately. The current W1A-before-W1D dependency does not support this migration.

4. **Major — The prescribed `mremap` repair cannot deliver the promised behavior under current hyper-linux.**

   [Wave 1:38](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:38) fixes a32rt’s loss of shared file backing by calling host `SYS_mremap`. But [hyper-linux/src/syscall.c:3204](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall.c:3204) rejects file-backed grow/move operations with `ENOSYS`; its relocation helper also creates private anonymous backing.

   Native in-place growth must additionally account for the reserved `PROT_NONE` window surrounding mappings.

   **Correction:** Assign the necessary host implementation, preserve reservations on failure and relocation, and run the file-writeback regression on both Linux and hyper-linux before closing D19.

5. **Major — The proposed i686 TSO fix is incomplete and can regress unaligned accesses.**

   [SPEC:118](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:118) makes setting `e->tso` the repair. However:

   - `i686_emit_begin` lives in [emit_exit.c:38](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:38), outside the lane’s ownership.
   - The flag affects the local ALU helpers; MOV, stack, string, and branch-stack accesses still use ordinary loads/stores.
   - The ordered ALU path emits unguarded LDAR/STLR variants for arbitrary x86 addresses. Its own comment acknowledges alignment requirements.

   **Correction:** Cover every relevant memory emitter and provide an ordered unaligned path. Do not assume newer AArch64 alignment features across all supported hosts. [Arm’s ordering guide](https://documentation-service.arm.com/static/62a304f231ea212bb662321d?token=) documents the baseline acquire/release alignment constraint.

6. **Major — The i386 signal repair contains a wrong alignment formula and leaves the FP wire layout incorrect.**

   [SPEC:121](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:121) specifies `((sp - 4) & 15) == 0`, which gives `sp % 16 == 4`, not 12. Linux’s final handler-entry frame calculation is equivalent to:

   ```c
   sp = ((sp + 4) & -16) - 4;
   ```

   Also, [sigframe_i386.h:61](/Users/angerman/Projects/zw3rk/i686rt/src/os/sigframe_i386.h:61) places XMM storage at `0x90`. Linux places `_fxsr_st[8]` there and `_xmm[8]` at **`0x110`**. Padding conceals the missing 128-byte region from the total-size assertion. Fixing only the legacy 80-byte x87 copy leaves XMM state wrong.

   **Correction:** Repair the header and serializer together, validate extended-state magic/metadata, and assert offsets as well as sizes. Test guest inspection, modification, and restoration of the frame. [Linux frame alignment](https://github.com/torvalds/linux/blob/v6.12/arch/x86/kernel/signal.c), [Linux FP context layout](https://raw.githubusercontent.com/torvalds/linux/v6.12/arch/x86/include/uapi/asm/sigcontext.h).

7. **Major — The frozen RV32 signal ABI is wrong in several independent ways.**

   [Wave 2:19](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:19) freezes incorrect sizes; [SPEC:231](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:231) invents a D-state magic record.

   For the inspected Linux RV32 MMU ABI without additional vector state:

   | Object | Draft | Correct base layout |
   |---|---:|---:|
   | Kernel `sigaction` | 20 bytes | **16 bytes** |
   | D FP state | 268-byte record | **264-byte structure** |
   | Reserved FP union | Effectively D-sized | **528 bytes, aligned to 16** |
   | `ucontext` | 584 bytes | **816 bytes** |
   | `rt_sigframe` | 720 bytes | **944 bytes** |

   RISC-V kernel `sigaction` has no `sa_restorer` slot. Signal context reserves the Q-capable FP union even for D-only execution; that does not advertise Q support. There is no D-state context magic `0x44504600`. The kernel signal mask is eight bytes, followed by reserved padding—not a 128-byte kernel `sigset_t`.

   **Correction:** Replace the frozen definitions with independently derived UAPI layouts. An RV32 Clang layout probe corroborated these sizes. [FP state](https://raw.githubusercontent.com/torvalds/linux/master/arch/riscv/include/uapi/asm/ptrace.h), [sigcontext](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/include/uapi/asm/sigcontext.h), [ucontext](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/include/uapi/asm/ucontext.h), [kernel sigaction](https://raw.githubusercontent.com/torvalds/linux/master/include/uapi/asm-generic/signal.h).

8. **Major — The Wave 2 ownership lists omit the integration required to run RV32.**

   [PLAN:110](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:110) assigns a hook in `src/linux/syscall.c`, which does not exist in rvrt. Relevant behavior resides in unowned files:

   - `runtime_main.c` selects 64-bit startup, memory configuration, syscall dispatch, and thread admission.
   - `linux/signal.c` rejects RV32 and allocates its trampoline above 1 TiB.
   - `linux/exec_args.c` reads eight-byte argv/envp pointers.
   - `runtime/exec_state.c` explicitly rejects XLEN other than 64.
   - Scheduler-owned futex dispatch recognizes RV64 syscall 98, not RV32 422.

   **Correction:** Assign startup/profile propagation, signal delivery, exec/resume, syscall normalization, clone/TLS/clear-TID, and multithread time64 admission. Codec tests alone cannot qualify the real runtime path.

9. **Major — Reusing time64 handlers does not make RV32 compound structures compatible.**

   [Wave 2:66](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:66) understates the conversion work. Existing [rvrt/src/linux/poll.c:390](/Users/angerman/Projects/zw3rk/rvrt/src/linux/poll.c:390) interprets the `pselect6` wrapper as two eight-byte fields; RV32 supplies pointer32 and size32. Its fd-set sizing also assumes eight-byte words.

   The time64 timespec can be shared, but embedded pointers, longs, fd sets, message headers, and associated dispatch paths cannot be reused unchanged.

   **Correction:** Define each syscall’s conversion boundary. Cover page-end buffers, interrupted waits, and multithread futex/time64 routing.

10. **Major — RV32 address wrapping is not covered by truncating register writes.**

    [SPEC:185](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:185) and the R8a card require truncating GPR/PC results. Existing interpreter memory operations form a 64-bit register-plus-immediate address before calling memory helpers.

    RV32 requires XLEN-width effective-address arithmetic before lookup; truncating a destination register afterward cannot repair an incorrectly calculated load/store address.

    **Correction:** Explicitly mask effective addresses for integer and FP accesses and control-flow targets, preserving guest-width fault addresses. Keep checked syscall pointer-plus-length validation separate: those buffer ranges must not silently wrap. `rv_space_init(...,32)` supplies bounds, not address arithmetic.

11. **Major — The RV32 AOT task targets the wrong identity mechanism.**

    [Wave 2:79](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-2-rv32gc.md:79) proposes `profile_id=1/2` in `format.c`. The actual format already contains `xlen`, `abi`, and `profile_digest`, including ILP32D and LP64D identifiers.

    The real obstacle is [runtime/aot_cache.c:87](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/aot_cache.c:87): its identity constructor selects RV64 and LP64D. That file is outside R8e’s ownership.

    **Correction:** Extend the existing identity and admission path rather than inventing a redundant discriminator. Verify that persisted RV32 and RV64 records cannot cross-admit.

12. **Major — The MIPS32 frozen context overlaps, and its proposed register allocation does not fit.**

    [SPEC:256](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:256) places two `uint32_t` fields and four bytes at `0x090`, then starts `lladdr` at `0x098`, overlapping those fields.

    Sequential natural layout requires `lladdr=0x09c`, `llval=0x0a0`, and `guest_base=0x0a8`; the subsequent fields can then end at the stated `fpr=0x0c0`.

    Line 261 also assigns **17 guest registers to 16 host registers**, `w0..w15`.

    **Correction:** Resolve both contradictions before freezing the context and trampoline interface.

13. **Major — MIPS O32 `stat64` is 104 bytes, not 160.**

    [Wave 3:19](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-3-rt32-family.md:19) prejudges the experiment with 160 bytes; the implementation lane repeats it. Linux’s O32 kernel `struct stat64` is **104 bytes**. Libc’s public `struct stat` is a different object.

    **Correction:** Generate kernel-wire offsets from a pinned target UAPI and keep libc types separate. [Linux MIPS stat definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/mips/include/uapi/asm/stat.h).

14. **Major — The MIPS signal-number identity prefix is false.**

    [SPEC:287](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:287) says signals 1–14 match the host. MIPS has `SIGEMT=7`, `SIGBUS=10`, and `SIGSYS=12`, unlike AArch64/x86.

    The later listed MIPS values and 128-signal kernel namespace are substantially correct, but an identity prefix would still misdeliver signals.

    **Correction:** Freeze a complete bidirectional mapping rather than an identity prefix plus later exceptions. [Linux MIPS signal definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/mips/include/uapi/asm/signal.h).

15. **Major — The V8 runtime accepts V8+ executables its state cannot represent.**

    [SPEC:341](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:341) accepts `EM_SPARC32PLUS` using the proposed 32-bit V8 register state. V8+ permits 64-bit global/out registers and V9 instructions while retaining a 32-bit ABI; its ELF flags also include `EF_SPARC_32PLUS`.

    **Correction:** Initially reject V8+, or define a separate profile with the required state and instruction semantics. It is not merely another identifier for LEON/V8. [GCC SPARC profile distinctions](https://gcc.gnu.org/onlinedocs/gcc-4.1.1/gcc/SPARC-Options.html).

16. **Major — SPARC64 syscall completion must update both carry flags.**

    [SPEC:498](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:498), the lane cards, and matrix specify only `CCR.icc.C`. Linux sets or clears **both `TSTATE_XCARRY` and `TSTATE_ICARRY`**.

    **Correction:** Update both `%xcc` and `%icc` carry state on success/error and test wrappers using either condition-code domain. [Linux SPARC syscall return assembly](https://github.com/torvalds/linux/blob/master/arch/sparc/kernel/syscalls.S).

17. **Major — The SPARC signal descriptions omit part of the mandatory stack prefix.**

    [Wave 4:106](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:106) and matrix rows describe a register-window payload followed immediately by signal data. Linux starts with `struct sparc_stackf`: **96 bytes for SPARC32 and 192 for SPARC64**, not merely the 64/128-byte register window.

    **Correction:** Freeze the complete signal frame, including its stack prefix and FPU/window pointers and tails. Do not confuse this with the initial process stack, where the stated SPARC64 `argc` offset of `%sp+2047+128` is correct. [Stack definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/include/uapi/asm/ptrace.h), [SPARC32 signals](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/kernel/signal_32.c), [SPARC64 signals](https://codebrowser.dev/linux/linux/arch/sparc/kernel/signal_64.c.html).

18. **Major — The PPC32 and PPC64 signal-storage descriptions are not valid frozen layouts.**

    [SPEC:332](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:332) describes PPC32 `mc_vregs` as a `uint32_t`. Linux has padding followed by inline, 16-byte-aligned vector storage; SPE overlays EVR high halves, ACC, and SPEFSCR there.

    For PPC64, [Wave 4:50](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-4-rt64-family.md:50) describes a simple `vsx_reserve[32]`. The ABI instead includes a guest `v_regs` pointer into `vmx_reserve[101]`, accommodating alignment, VMX state, VSCR/VRSAVE, and additional VSX halves.

    **Correction:** Specify actual offsets, guest-pointer values, and register aliasing. [PPC ucontext](https://codebrowser.dev/linux/linux/arch/powerpc/include/uapi/asm/ucontext.h.html), [PPC64 sigcontext](https://codebrowser.dev/linux/linux/arch/powerpc/include/uapi/asm/sigcontext.h.html).

19. **Major — LoongArch HWCAP and CPUCFG advertise the wrong features.**

    [SPEC:420](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:420) gives `0x1adf`; the named OR evaluates to **`0x47d`**. The literal omits LASX and LBT_X86 while advertising unrelated LAM, COMPLEX, LVZ, LBT_ARM, and LBT_MIPS capabilities. No lane implements the advertised LBT state.

    Line 409 also puts FP/LSX/LASX feature fields in CPUCFG word 1 rather than word 2.

    **Correction:** Derive HWCAP and CPUCFG from one supported-feature profile. Advertising an unsupported extension can cause libc to select unusable code. [Linux HWCAP bits](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/include/uapi/asm/hwcap.h), [CPUCFG definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/include/asm/loongarch.h).

20. **Major — PPC64’s HWCAP literal also contradicts its named features.**

    [SPEC:452](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:452) gives `0xef803fb2`; the six named flags OR to **`0x5c000180`**. The literal omits Altivec while advertising capabilities including 601 instructions, SPE, 4xx MAC, and decimal FP.

    **Correction:** Use symbolic, profile-derived masks. Define whether the runtime exposes one synthetic ISA superset or distinct POWER9/Power10 profiles, and make HWCAP2 and CPU identification consistent with that choice. [Linux PowerPC feature definitions](https://raw.githubusercontent.com/torvalds/linux/master/arch/powerpc/include/uapi/asm/cputable.h).

21. **Major — ELFv2 local entry is not universally global entry plus eight bytes.**

    [SPEC:430](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:430) and the PPC64 experiment hard-code `+8`. ELFv2 encodes local-entry information in `st_other`; entries may coincide or use other encoded offsets.

    `EF_PPC64_ABI` is also a two-bit field. Exact `e_flags == 2` is a stricter admission policy than testing the ABI field and should be intentional.

    **Correction:** Respect encoded entry semantics and document ABI-unspecified/rejected cases. Never synthesize a fixed `+8` call adjustment. [LLVM ELF definitions](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/BinaryFormat/ELF.h).

22. **Major — MIPS FP qualification omits a required NaN-format dimension.**

    [SPEC:250](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:250) and the FP cards address FR0/FR1 but do not define `EF_MIPS_NAN2008`, legacy versus IEEE-2008 NaN handling, or ABS2008 behavior. Legacy MIPS reverses the quiet/signaling NaN convention relative to IEEE-2008/AArch64.

    **Correction:** Specify admission and execution profiles for NaN encoding, FR mode, rounding, exceptions, denormals, and signal restoration. Include invalid-operation and ABS/NEG boundary vectors. Generic “IEEE-754” or a SoftFloat dependency does not choose these policies. [GNU assembler NaN modes](https://sourceware.org/binutils/docs-2.43/as/MIPS-NaN-Encodings.html), [GCC MIPS FP options](https://gcc.gnu.org/onlinedocs/gcc-4.9.2/gcc/MIPS-Options.html).

23. **Major — Guest VA limits are mixed with ISA width and backing strategy.**

    The [address-space matrix:15](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:15) combines several different concepts:

    - Native MIPS32’s 2-GiB limit differs from MIPS64’s O32 compatibility limit.
    - N32 retains a 32-bit address limit despite 64-bit GPRs.
    - LoongArch and MIPS64 limits depend on CPU/kernel configuration.
    - PPC64 limits depend on page-table configuration.
    - The copied RVRT implementation currently selects **`1 << 47`** for every non-RV32 space in [space.c:136](/Users/angerman/Projects/zw3rk/rvrt/src/memory/space.c:136), which does not implement the matrix’s PPC64 `1 << 48` limit.

    **Correction:** Freeze per-profile exclusive VA limits, holes, stack/mmap placement, and pointer canonicalization independently of translator VA and GPA allocation. [MIPS limits](https://codebrowser.dev/linux/linux/arch/mips/include/asm/processor.h.html), [LoongArch limits](https://codebrowser.dev/linux/linux/arch/loongarch/include/asm/processor.h.html), [PPC64 limits](https://codebrowser.dev/linux/linux/arch/powerpc/include/asm/task_size_64.h.html).

24. **Major design gap — The page-size policy is incomplete, although 64-KiB ELF alignment is not itself a blocker.**

    [SPEC:438](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:438) correctly observes that 64-KiB-aligned ELF segments can load on a 4-KiB runtime. Darwin’s 16-KiB backing does not automatically become the translated Linux page size: [hyper-linux/src/guest.c:60](/Users/angerman/Projects/zw3rk/hyper-linux/src/guest.c:60) explicitly uses 4-KiB guest pages.

    What remains unspecified is the relationship among guest ABI page size, translated page-table granularity, and Darwin backing granularity.

    **Correction:** Define `AT_PAGESZ`, mmap/mprotect/munmap rounding, file offsets, BSS/RELRO overlap, and shared backing behavior. Qualify adjacent 4-KiB mappings with different permissions on the 16-KiB host. If 64-KiB guest-page semantics are promised, that is additional work beyond honoring `p_align`.

25. **Major — The blanket musl acceptance requirement cannot be met for SPARC without a libc port.**

    [SPEC:513](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:513) requires dynamic musl and glibc for every new translator; the SPARC32 card promises a musl sysroot. Upstream musl has no SPARC port. Wave 5’s glibc-only card already conflicts with the blanket gate.

    **Correction:** Make libc requirements profile-specific and pin obtainable sysroots. A new musl port would need explicit scope and ownership. [musl supported platforms](https://wiki.musl-libc.org/supported-platforms).

26. **Major — The proposed host descriptor cannot express the required MIPS dispatch partition.**

    [SPEC:161](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:161) lists class/data/machine fields but no explicit flags matcher or launch-policy discriminator. Existing `i686rt-l6a/src/translator.h` selects by machine alone.

    O32 and N32 can both be ELF32, `EM_MIPS`, and either endianness, yet require different runtimes and memory policies.

    **Correction:** Freeze a parsed-ELF predicate with masked ABI flags, rejection rules, and launch policy. `!EF_MIPS_ABI2` must not implicitly admit every other ELF32 MIPS ABI as supported O32.

27. **Major — Hardware-TSO negotiation does not cover runtime class or vCPU lifecycle.**

    [HOST-CONTRACT:82](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:82) expects SPARC64 to consume a capability otherwise specified only for Class A. Existing sibling headers do not provide the new bit, and current hyper-linux does not establish the promised mode.

    Moreover, a capability used to remove barriers must remain true after thread creation, fork, and exec. Relevant vCPU paths span `hl.c`, `thread.c`, and `fork_ipc.c`, outside L-HL-1’s ownership.

    **Correction:** Define capability scope, negotiation, and lifecycle; establish the mode on every executing vCPU before advertising it. Give Class B a valid negotiation path or retain software ordering.

28. **Major — The “frozen” Class-B host contract omits material upstream requirements and exclusions.**

    [HOST-CONTRACT:31](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:31) largely reduces integration to an arena, digest, memory-policy name, and cache-authority string.

    The sibling contract additionally defines descriptor ownership/presence, validated-image semantics, startup stacks, sparse translation, and cache-maintenance distinctions. It excludes robust/PI mutexes, parallel guest CPU execution, and external/native shared writers. The bounded hard-zero path also uses **family authority separately from cache authority**.

    **Correction:** Preserve these requirements and limits explicitly. `--cache-authority` must not be treated as authorization or qualification for family backing. See [rvrt’s host contract](/Users/angerman/Projects/zw3rk/rvrt/docs/HOST-CONTRACT.md:338).

29. **Major — Several acceptance commands do not exist or only print instructions.**

    The [Wave 1 commands](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:19) contain concrete blockers:

    | Prescribed check | Actual behavior |
    |---|---|
    | a32rt `make check`, `check-m0`, `check-m1`, `check-m5` | Targets absent |
    | i686rt `make test-h1-smc` | Target absent |
    | i686rt `make test-p1-lima` | Prints execution instructions |
    | i686rt `make check` | Prints “phase 0: no tests yet” |
    | rvrt `make test-runtime` | Target absent |
    | rvrt `check-line-limits`, `_build/test_jit_a64` | Exact targets absent |
    | “Run Round-17 regression suite” | No executable command specified |

    The a32rt targets are named `test-hello-*`, `test-m1-*`, `test-m5-*`, and `test-all-*`. Direct execution of AArch64 Linux artifacts also needs an actual Linux or hyper-linux transport.

    **Correction:** Freeze runnable commands that build and execute the changed artifact on the specified substrate.

30. **Major — Report generation is confused with acceptance assertions.**

    [Wave 1:61](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:61) and line 64 use `h2-report`/`h3-coremark` as if they enforce thresholds. These assemble or print results; they do not necessarily fail when the required threshold is unmet.

    The LTP requirement also alternates between `>=80` and `>80`, while “reaches real test bodies” is a different condition.

    **Correction:** Specify one assertion, denominator, skip/failure policy, and fresh-artifact identity. Preserve the detailed results for the remaining cases instead of treating a pass count as complete compatibility.

31. **Major — Lane ownership is neither complete nor consistently disjoint.**

    Besides the RV32 omissions:

    - L-I686-2 needs unowned `emit_exit.c`.
    - L-I686-3 needs the signal-frame header and context storage for `exec_path_buf`.
    - L-I686-6 needs `engine.c`, already assigned to the SMC lane.
    - H4 required source guards beyond its assigned Makefile/flake files; the actual completed implementation demonstrates this.
    - L-A32-2’s specified argv test requires files outside its card.
    - The host dispatcher lane needs a table assigned to another lane.
    - New tests generally require build-rule changes without assigned Makefile ownership.

    See [Wave 1 ownership](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-1-closeout.md:57) and [PLAN:101](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:101).

    **Correction:** Create explicit coordinator-owned prerequisites and serialize shared files. Predictable integration work should not be left to repeated escalation.

32. **Major — The dependency DAG omits real dependencies and orders some qualification before required implementations.**

    [PLAN:62](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:62) permits Wave 4 after Wave 2 without requiring Wave 3, although MIPS64 explicitly reuses MIPS32. SPARC64 similarly depends on SPARC32.

    R8f cannot qualify a real runtime in parallel with unmerged implementation lanes. It can prepare fixtures in parallel, but its execution gate belongs after integration.

    The generic pipeline also requires dynamic hard-float libc and feature-advertised vector paths before Phase 5 implements FP/SIMD.

    **Correction:** Add architecture-specific reuse edges, a Wave 2 integration checkpoint, and early FP/SIMD prerequisites or explicitly restricted bootstrap profiles. Feature advertising must follow implementation.

33. **Major — The worktree cleanup instructions are not supported by the inventory.**

    [STATE-OF-PLAY:18](/Users/angerman/Projects/zw3rk/rt-series/lode/STATE-OF-PLAY-2026-10-23.md:18) says only two RVRT branches are unmerged. Against its own baseline, `for-each-ref --no-merged=884ae73 refs/heads` returned **278 branch names**, versus 18 merged.

    Cherry-picks or squash merges may explain substantial equivalence; ancestry alone does not prove unique work. But the document likewise cannot infer that all 278 worktrees are disposable. Active worktree counts changed during this review.

    **Correction:** Require a pinned per-worktree inventory, content-equivalence assessment, dirty/untracked/ignored artifact review, and ownership check before removal. Preserve active worktrees.

34. **Major — The performance plan promotes an unmeasured cause to a finding.**

    [STATE-OF-PLAY:49](/Users/angerman/Projects/zw3rk/rt-series/lode/STATE-OF-PLAY-2026-10-23.md:49) attributes 23 versus 71 CoreMark iterations/s to missing chaining and flag-sync elimination. The underlying report establishes those scores, but identifies the proposed optimizations as expected levers, not measured causes.

    Current `I686RT_STATS` exposes counts, not the required per-phase timing split. The three-step recipe in [SPEC:138](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:138) does not implement the stated six-step rule.

    **Correction:** Assign default-off timing instrumentation, commit it, measure, formulate the hypothesis, then choose and validate a fix. The absolute 100-iterations/s threshold also needs an identified machine and benchmark configuration.

35. **Major — Muse isolation and reviewer write protection are overstated.**

    [PLAN:29](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:29) presents the isolation flag as an alternative to explicit worktree creation. The installed Muse help says that flag enables a capability; **each child still needs an affirmative isolation request, and omission stays shared**.

    Likewise, `--trust-workspace` loads rules; it does not make the reviewer read-only. [GOAL:21](/Users/angerman/Projects/zw3rk/rt-series/GOAL.md:21) then says to revert stray edits without specifying a pre-review dirty baseline.

    **Correction:** Specify per-child repository/worktree/base selection and assert it before work. Run reviewers with enforced write restrictions or isolated checkouts. Compare against the recorded starting state and never revert unrelated user changes.

36. **Major design gap — The gates do not yet qualify several consequential architectural contracts.**

    [SPEC:510](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:510) relies heavily on hello/BusyBox, interpreter-versus-DBT equality, and unspecified FP golden vectors. Those checks can pass while both engines share an ABI or semantic mistake.

    Required discriminating coverage includes delay-slot/annul faults and restart state, SPARC window flushing and signal edits, reservation invalidation across helpers/signals/shared aliases, FP NaN/rounding/exception modes, and both-host thread/signal/mapping behavior. “LSX maps 1:1 to NEON” and splitting LASX into halves are implementation sketches, not general semantic proofs.

    **Correction:** Tie each promised profile to explicit independent oracle cases. Preserve the interpreter as a reference, but do not make agreement with it the sole correctness criterion.

37. **Minor — Several “current” observations became stale, and README already contradicted the original audit.**

    [README:20](/Users/angerman/Projects/zw3rk/rt-series/README.md:20) still says SSE/x87 are unmerged, although the lode itself records their merge.

    During this review, H1 and H4 were committed in i686rt, and RVRT gained a bounded two-block AOT/pretranslation path. “H1 uncommitted,” “H4 remaining,” and “only the initial entry block” are therefore no longer current.

    **Correction:** Keep the historical snapshot immutable and dated to exact commits, then derive executable closeout work from the selected candidate. H4/H1 acceptance records were inspected, not independently rerun.

38. **Minor — The host defect count and historical applicability need correction.**

    [SPEC:71](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:71) calls `D211–D213` plus `D249–D258` eleven defects; that names thirteen IDs.

    More materially, D211’s ledger description concerns an older FIFO implementation. The selected broker tip contains a later limited-read implementation, so the historical repair description should not be applied mechanically.

    **Correction:** Map every defect to the candidate revision and current function before assigning it.

39. **Minor — The RV32 compressed floating-point immediate formula contains an extra bit.**

    [SPEC:190](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:190) gives `offset[7:6|2|5:3]`. C.FLW/C.FSW use the C.LW/C.SW word-offset layout: `uimm[6]`, `uimm[5:3]`, and `uimm[2]`; there is no `uimm[7]`.

    **Correction:** Pin the actual extraction expression. The stated RV32/RV64 opcode substitutions themselves are correct. [Official RV32 compressed-F encodings](https://raw.githubusercontent.com/riscv/riscv-opcodes/master/extensions/rv32_c_f).

40. **Minor — Trapping a counter instruction does not automatically produce a libc fallback.**

    [SPEC:209](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:209) says illegal `rdtime[h]` makes libc fall back to `clock_gettime64`. Direct execution instead raises an illegal-instruction trap unless an explicit fallback mechanism handles it.

    Counter CSRs belong to Zicntr/Zihpm; Zicsr supplies CSR-access instructions.

    **Correction:** State the unsupported-counter policy directly and qualify the selected libc/vDSO path separately. [RISC-V ISA reference](https://docs.riscv.org/reference/isa/v20260120/unpriv/d-st-ext.html).

41. **Minor — “Time64-only” needs a narrower definition and a pinned source version.**

    [SPEC:218](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:218) describes older header-selection machinery as current. Modern Linux selects generated RISC-V syscall headers.

    More importantly, absence of the legacy clock/futex interfaces does not make every time-related wire structure 64-bit: `getitimer`/`setitimer` remain with their old interval-timer structure.

    **Correction:** Pin the Linux UAPI revision and specify availability and structure layout per syscall. Keep `_llseek`’s high-word-first ordering as its explicit exception. [RISC-V syscall selection](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/kernel/Makefile.syscalls), [interval timer ABI](https://raw.githubusercontent.com/torvalds/linux/v6.18/kernel/time/itimer.c).

42. **Minor — LoongArch’s counter mnemonic and units are wrong.**

    [SPEC:409](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:409) names `RDTIMED.D`; the instruction is **`RDTIME.D`**. It returns stable-counter ticks and an ID, not intrinsically nanoseconds.

    **Correction:** If the synthetic counter uses nanoseconds, expose a consistent 1-GHz frequency through CPUCFG/vDSO behavior. [LoongArch architecture manual](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html).

43. **Minor — LoongArch signal alignment is underspecified for LASX.**

    [SPEC:421](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:421) gives the correct magic constants but only mentions 16-byte alignment. LASX payloads require **32-byte alignment**. Linux selects the appropriate active FP/vector record, includes applicable extension state, and terminates the chain.

    **Correction:** Freeze record and payload alignment separately, including unsupported-extension rejection. [Signal UAPI](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/include/uapi/asm/sigcontext.h), [frame construction](https://raw.githubusercontent.com/torvalds/linux/master/arch/loongarch/kernel/signal.c).

44. **Minor — LEON ASI `0x0b` is not simply another user-data ASI.**

    [SPEC:371](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:371) groups `0x0a` and `0x0b` as user ASIs. Linux identifies them as user-data and kernel-data spaces respectively.

    **Correction:** Define the selected LEON CASA privilege behavior rather than accepting both as equivalent user data. [SPARC ASI definitions](https://codebrowser.dev/linux/linux/arch/sparc/include/uapi/asm/asi.h.html).

45. **Minor — The version narrative and exported header disagree.**

    [HOST-CONTRACT:3](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:3) declares frozen v1.1, while [include/a32host.h:22](/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h:22) defines minor zero.

    Capability-only extension can be backward compatible, but minimum accepted version and producer-advertised version need distinct meanings. Updating the vendor copy must also account for a32rt’s exact header-comparison gate.

    **Correction:** State the versioning rule and synchronize producers/consumers. The existing 256-byte layout and `0x81006101` ioctl value are correct.

46. **Minor — Several unified-host descriptions are inaccurate or unimplemented requirements.**

    In [HOST-CONTRACT:55](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:55):

    - Prefixes already contain `_`, while the table adds another.
    - `--` is an argument separator, not an equivalent of `HOST=none`.
    - Mandatory CLI aliases/options need migration tasks and tests in existing runtimes.
    - Closing the loader-private fd does not imply the guest has only descriptors 0–2; ordinary inherited descriptors remain meaningful.

    Line 15 also describes “virtiofs over APFS,” whereas the inspected hyper-linux VFS/syscall path directly accesses Darwin files.

    **Correction:** Distinguish implemented protocol, proposed additions, and illustrative architecture descriptions.

47. **Minor — Makefile/flake checks do not validate the plan’s claimed invariants.**

    [Makefile:52](/Users/angerman/Projects/zw3rk/rt-series/Makefile:52) checks one header’s syntax and document presence. [flake.nix:33](/Users/angerman/Projects/zw3rk/rt-series/flake.nix:33) does similarly, with a smaller document list. Neither establishes ABI offsets, sibling equality, runnable lane commands, ownership disjointness, or line limits.

    [PLAN:164](/Users/angerman/Projects/zw3rk/rt-series/PLAN.md:164) nevertheless says every repository already enforces the prescribed gates, which the sibling Makefiles contradict.

    **Correction:** Describe these as umbrella syntax/presence checks. Assign missing structural checks explicitly; do not interpret `rt-series: all checks passed` as specification validation.

48. **Nit — Correct identifiers, counts, and evidence notation before freezing generated interfaces.**

    - `SPEC:58`: SIB base encoding ESP is **4**, not 5.
    - `SPEC:303`: ELF section is **`.gnu.attributes`**; assembly directive is `.gnu_attribute`.
    - `SPEC:495` and the SPARC64 card: **`faligndata`**, not `falignadata`.
    - The D1–D20 heading contains only D1–D10.
    - The “8 syscalls” lane body lists ten after its additions.
    - “8-phase” omits Phase E from the count.
    - `[U]` is defined but not used to distinguish uncertain architectural prescriptions.

    These are small individually, but exact identifiers matter to generated tables, source searches, and task execution.

Several important choices and constants **did check out**:

- Keeping RV32 in rvrt’s sparse, checked family-memory implementation is sound. Class B describes an implementation strategy; it does not require 64-bit guest pointers. No performance advantage over Class A has been established.
- ILP32D correctly combines 32-bit GPRs/pointers with 64-bit FP registers. The NaN-boxing requirement, `EM_RISCV=243`, float-ABI value 4, HWCAP `0x112d`, `tp=x4`, and 16-byte stack alignment are correct.
- The inspected central RV32 and explicit MIPS O32/N32/N64 syscall numbers match upstream tables. O32 stack arguments starting at `sp+16`, N32/N64 register arguments, and MIPS dual-register `pipe` returns are sound.
- PPC32 `r2`, PPC64 `r13`, LoongArch `r2`, SPARC `%g7`, and MIPS ULR/RDHWR `$29` TLS conventions are correct. PPC `sc` versus `scv` error conventions are also correct.
- SPARC traditional fork/clone’s child `%o0=parent_pid`, `%o1=1` is correct; so are stack bias 2047 and the stated initial `argc` placement. Initial-stack layout must remain distinct from signal-frame layout.
- The ELF machine numbers, LoongArch signal magic constants, `/dev/a32host` device numbers, existing capability bits, Class-A window scan, and broker’s 1-GiB shared GPA arena checked out.

Read-only verification included:

```text
make check-docs
  PASS: 15 required files present and nonempty

clang -target aarch64-none-elf -ffreestanding -std=c11 \
  -Wall -Wextra -Werror -Werror=vla -pedantic \
  -fsyntax-only include/a32host.h
  PASS

make -n -C ../a32rt check
  FAIL: No rule to make target 'check'

make -n -C ../i686rt check test-p1-lima
  Only echo commands; no tests executed

make -n -C ../rvrt test-runtime
  FAIL: No rule to make target 'test-runtime'
```

GNU Make and unwrapped Clang were used directly from installed Nix packages to avoid toolchain cache writes. No full builds, runtime suites, ISA oracle execution, or worktree content-equivalence audit were performed. The remaining qualification obligations should stay explicit; neither this review nor the existing smoke evidence establishes production readiness.