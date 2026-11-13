Static review completed without running builds or tests. `tests/qual/` is absent from this checkout; the review included the torture suite’s two helper headers and all nine files under `tools/`.

### RTS-R7-1 — DEFECT — HIGH

- **Summary**: The TestFloat pipeline neither invokes the upstream tools correctly nor executes the guest FP operations being qualified.
- **Locations**: [tools/run_grind.sh:410](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:410), lines 410–480.
- **Evidence & Root Cause**: The generator receives `-rounds` without a type/function; upstream requires a type/function and uses `-n` for case counts. The verifier likewise receives no function argument. Beyond those invocation errors, the pipeline feeds generator output directly into the verifier. Function-mode generator results come from SoftFloat; verifying them against SoftFloat does not exercise translated guest FP instructions. Upstream explicitly requires an intervening program that executes the operation. See the [generator interface](https://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_gen.html), [verifier interface](https://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_ver.html), and [required pipeline](https://www.jhauser.us/arithmetic/TestFloat-3/doc/TestFloat-general.html).
- **Remediation**: Add a guest operation runner that produces actual results and exception flags, or use a correctly configured guest `testfloat`. Specify operations and rounding modes explicitly, use supported arguments, and require a positive verified case count.

### RTS-R7-2 — BUG — MEDIUM

- **Summary**: The FP preservation comparison invokes undefined behavior by discarding `volatile`.
- **Locations**: [tests/p3_torture.c:396](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:396); declarations at lines 371 and 392.
- **Evidence & Root Cause**: Both `b` and `ref` are defined as `volatile double`, but their addresses are cast to `const void *` and passed to `memcmp`, which reads them through nonvolatile accesses. C11 §6.7.3p6 defines this access as undefined behavior, undermining the supposedly exact comparison. See the [C11 committee draft](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).
- **Remediation**: Read both volatile values into ordinary `double` snapshots and compare those snapshots, or compare their representations through volatile-qualified character pointers.

### RTS-R7-3 — DEFECT — MEDIUM

- **Summary**: The signal-frame test never checks `siginfo_t.si_signo` and accepts a missing `siginfo_t`.
- **Locations**: [tests/p3_torture.c:108](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:108), lines 108–115 and 250–320.
- **Evidence & Root Cause**: `g_usr1_signo` captures the handler’s separate `signo` argument, yet its assertion reports `"si_signo mismatch"`. Nothing reads `info->si_signo`. When `info == NULL`, `g_usr1_code` retains its initialized zero, which the test explicitly accepts. A translator supplying the correct handler argument but corrupt or absent signal information can therefore receive the advertised `si_signo/si_code/ucontext` PASS.
- **Remediation**: Record and require a non-null `info`; independently check the handler argument, `info->si_signo`, and the supplied `si_code`.

### RTS-R7-4 — DEFECT — MEDIUM

- **Summary**: Nested alternate-stack delivery is advertised but never exercised; dropped nested signals also pass.
- **Locations**: [tests/p3_torture.c:134](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:134), lines 134–148, 170–179, 245–246, 448–458, and 794–797.
- **Evidence & Root Cause**: `usr1_handler` ignores the result of `raise(SIGUSR2)`. The nested handler only changes `g_nest_depth`, which no assertion examines. Suppressing SIGUSR2 leaves every PASS condition unchanged. These handlers also run without `SA_ONSTACK`, before the alternate stack is installed. The actual alternate-stack handler never delivers a nested signal, despite the coverage claim at line 8.
- **Remediation**: Run the nested scenario with an installed alternate stack and appropriate `SA_ONSTACK` dispositions. Assert delivery count, nesting order, and actual stack residency for both handlers.

### RTS-R7-5 — DEFECT — MEDIUM

- **Summary**: The SPARC V8 annul rule incorrectly describes branch control flow.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:37](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:37).
- **Evidence & Root Cause**: The matrix describes annul as `pc = npc + 4, npc = npc + 8` without restricting that rule to an untaken conditional branch. A taken conditional branch executes its delay instruction even with `,a`; `ba,a target` skips the delay instruction and transfers directly to `target`. Applying the documented rule universally can discard a required instruction or select the wrong PC. See the [SPARC V8 Architecture Manual](https://www.cs.utexas.edu/~novak/sparcv8.pdf).
- **Remediation**: Document taken conditional, untaken conditional, and unconditional annulled branches separately, with explicit resulting `pc`/`npc` values.

### RTS-R7-6 — DEFECT — MEDIUM

- **Summary**: The combined MIPS64/N32 signal-frame description incorrectly assigns N32 a 64-bit `ucontext`.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:58](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:58).
- **Evidence & Root Cause**: N32 retains 64-bit saved registers but uses 32-bit `uc_flags`, `uc_link`, and stack fields. Consequently, `uc_mcontext` begins at offset 24 for N32 versus 40 for N64. Treating the layouts as shared shifts saved-register accesses by 16 bytes. Both frames also have a 24-byte prefix omitted from this row. The distinction appears in [Linux’s N32 definitions](https://code.googlesource.com/linux/torvalds/linux/+/26ba1bf310f0ed43f249a93d0cf8a93675cd8ae8/arch/mips/kernel/signal_n32.c) and the sibling’s [frozen layouts](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigframe_mips64rt.h:162).
- **Remediation**: Specify N64 and N32 layouts separately, including their common prefix, pointer widths, and distinct context offsets.

### RTS-R7-7 — BUG — MEDIUM

- **Summary**: The lmbench qualification loop supplies incompatible arguments to multiple tools.
- **Locations**: [tools/run_grind.sh:641](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:641), lines 641–658.
- **Evidence & Root Cause**: Every binary receives `-P 1 null`. That operation is valid for `lat_syscall`, but `lat_proc` requires `procedure`, `fork`, `exec`, or `shell`; `lat_ctx` expects a numeric process count; and `lat_pagefault` expects an existing input file. Correct installations therefore encounter harness-induced failures instead of the intended qualification workloads. See upstream [lat_proc](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_proc.c), [lat_ctx](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_ctx.c), and [lat_pagefault](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_pagefault.c).
- **Remediation**: Dispatch arguments per tool and prepare the page-fault input file explicitly. Validate each tool’s expected completion output.

### RTS-R7-8 — DEFECT — LOW

- **Summary**: The SPARC32 signal-frame size contradicts its field offsets and the frozen implementation.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:55](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:55).
- **Evidence & Root Cause**: The stated size is **348 bytes**, but the final four-byte `rwin_save_ptr` starts at `0x154`, giving an extent of `0x158`, or **344 bytes**. That already satisfies Linux’s eight-byte alignment. The sibling [frame definition](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/sigframe_sparc32rt.h:20) explicitly records the correction to 344, consistent with the [Linux structure](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/kernel/signal_32.c).
- **Remediation**: Change the base frame size to 344 bytes and distinguish structure size from any additional stack-placement padding.
