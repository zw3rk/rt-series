Read all ten files in `src/interp/` end-to-end and the CPU/FPU/trap headers present. There is no `include/` directory or separate MSA header. No builds, tests, or edits were performed. Examples below are static deductions.

### M64-R7-1 — BUG — HIGH

- **Summary**: R6 binaries are admitted but execute incompatible R2 semantics.
- **Locations**: [interp.c:755](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:755), [cpu.h:142](/Users/angerman/Projects/zw3rk/mips64rt/src/core/cpu.h:142), [loader.c:370](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:370).
- **Evidence & Root Cause**: ELF admission checks ABI without selecting an ISA revision. R6 `BGEUC` uses opcode `0x06`, which the interpreter always executes as `BLEZ`. With distinct source registers containing 2 and 1, a taken compact branch becomes an untaken delayed branch. CPU state also lacks forbidden-slot tracking, so required R6 CTI rejection cannot occur. [MIPS64 instruction reference](https://www.cipunited.com/xlx/files/document/202008/1205490289250.pdf).
- **Remediation**: Introduce revision-aware admission, decoding, and forbidden-slot state. Reject unsupported revisions until implemented.

### M64-R7-2 — BUG — HIGH

- **Summary**: LL/SC reservations survive interfering writes through shared-memory aliases.
- **Locations**: [unaligned.c:297](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:297), [unaligned.c:383](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:383), [unaligned.c:494](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:494), [vm_file.c:497](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:497).
- **Evidence & Root Cause**: Reservation generations identify guest virtual addresses, while native `MAP_SHARED` mappings can alias the same backing word. Thread A can load-linked through one mapping; thread B can change and restore the word through another mapping whose epoch bucket differs. Neither A’s generation nor its reservation changes, and the final value CAS succeeds incorrectly. Process-private generation arrays likewise miss writes from another process.
- **Remediation**: Track reservations by backing identity and offset, with invalidation shared across participating mappings/processes. Value comparison alone cannot detect ABA interference.

### M64-R7-3 — BUG — HIGH

- **Summary**: COP1 branch delay-slot faults discard the installed signal-handler PC.
- **Locations**: [fp.c:812](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:812), [interp.c:849](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:849).
- **Evidence & Root Cause**: `fp_branch()` executes its slot through `interp_step()`. That function converts handled faults and dispatcher-owned PC changes into return value zero. `fp_branch()` then overwrites the handler PC with the ordinary branch destination. For example, a handled overflow in a `BC1T` delay slot installs a signal frame but skips the handler, continuing with signal-delivery register state.
- **Remediation**: Preserve an explicit redirected-PC outcome when executing a delay slot, or share the integer branch’s slot-execution contract.

### M64-R7-4 — BUG — HIGH

- **Summary**: Unaligned merge accesses deliver memory faults twice.
- **Locations**: [unaligned.c:70](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:70), [unaligned.c:88](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:88), [mem.c:91](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem.c:91).
- **Evidence & Root Cause**: `guest_ld8()`/`guest_st8()` already deliver faults. Successful handler installation deliberately leaves `exit_reason == MIPS64_EXIT_NONE`; `load_bytes()`/`store_bytes()` interpret that as an undelivered fault and call `mips_fault()` again. Normally the first delivery blocks SIGSEGV, so the second marks execution fatal before the handler runs. `SA_NODEFER` instead permits an erroneous nested frame.
- **Remediation**: Propagate accessor failures without raising another fault.

### M64-R7-5 — BUG — HIGH

- **Summary**: FCC1–FCC7 branches lose their taken target during delay-slot memory recovery.
- **Locations**: [decode.c:126](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.c:126), [decode.h:207](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.h:207), [mem_recover.c:197](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:197).
- **Evidence & Root Cause**: `is_bc()` requires `rt <= 3`, excluding branches whose `rt` field selects FCC1–FCC7. Recovery therefore classifies a taken `bc1t $fcc1,target` as a nonbranch and resumes at `branch_pc+8`. Additionally, the header reverses the BC1T/BC1FL constants, making the likely classifier incorrect.
- **Remediation**: Accept all FCC selectors, derive likely from `rt & 2`, and correct the constants.

### M64-R7-6 — BUG — HIGH

- **Summary**: NAN2008 binaries execute legacy NaN semantics.
- **Locations**: [fp.c:86](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:86), [fp.h:39](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.h:39), [loader.c:811](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:811).
- **Evidence & Root Cause**: Admission accepts `EF_MIPS_NAN2008`, but loading never initializes the NaN mode and interpreter classification always uses legacy polarity. Consequently, NAN2008 quiet NaN `0x7fc00000` raises Invalid, signaling NaN `0x7f800001` does not, and invalid arithmetic produces `0x7fbfffff`, which is signaling under NAN2008. [GNU NaN-encoding documentation](https://sourceware.org/binutils/docs-2.24/as/MIPS-NaN-Encodings.html).
- **Remediation**: Initialize and consistently honor the selected NaN mode, including default results and conversions; otherwise reject that mode.

### M64-R7-7 — BUG — HIGH

- **Summary**: Destination/source aliasing suppresses signaling-NaN exceptions.
- **Locations**: [fp.c:341](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:341), [fp.c:381](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:381), [fp.c:505](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:505), [fp_ps.c:273](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:273).
- **Evidence & Root Cause**: Several arithmetic paths write the default quiet NaN into `fd` before rereading source registers to detect signaling NaNs. Legacy `SQRT.S $f0,$f0` with `0x7fc00000` therefore replaces its signaling operand before classification, suppressing Invalid and an enabled trap. Binary arithmetic and COP1X have the same ordering defect.
- **Remediation**: Snapshot and classify all source bits before destination writeback.

### M64-R7-8 — BUG — HIGH

- **Summary**: COP1X multiply-add uses incorrect rounding semantics and ignores guest RM.
- **Locations**: [fp_ps.c:287](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:287), [fp_ps.c:330](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:330).
- **Evidence & Root Cause**: The R2 path uses host `fma()`/`fmaf()`, although legacy MADD rounds the intermediate product and then the sum. With `fr=-1`, `fs=1+2^-23`, `ft=1-2^-23`, nearest-rounded `MADD.S` should produce zero; this code produces `-2^-46`. Neither path consults guest RM, also breaking directed rounding. [MIPS MADD specification](https://personal.denison.edu/~bressoud/cs281-s10/Supplements/ISA_Vol_2.pdf).
- **Remediation**: Implement the selected architecture’s intermediate and final rounding, using guest RM and combined exception accounting.

### M64-R7-9 — BUG — MEDIUM

- **Summary**: Misaligned JR/JALR targets fault before required link and delay-slot effects.
- **Locations**: [interp.c:787](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:787).
- **Evidence & Root Cause**: The target-alignment check returns before writing JALR’s link register or executing its slot. The architectural exception occurs when the target is subsequently fetched. A misaligned `jalr` followed by a store therefore incorrectly skips both the link update and store, and records the jump PC instead of the target. [MIPS instruction reference](https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00086-2B-MIPS32BIS-AFP-6.06.pdf).
- **Remediation**: Commit the link and slot first; raise the alignment fault during target fetch.

### M64-R7-10 — BUG — MEDIUM

- **Summary**: Traditional GNU arithmetic BREAK encodings deliver the wrong signal.
- **Locations**: [interp.c:54](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:54), [interp.c:220](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:220).
- **Evidence & Root Cause**: `trap_code()` extracts only bits 15:6, suitable for register trap instructions but insufficient for BREAK’s 20-bit code. GNU `break 7` (`0x0007000d`) and `break 6` (`0x0006000d`) become code zero and deliver SIGTRAP instead of the arithmetic SIGFPE mapping. Linux normalizes the historical BREAK encoding separately. [Linux MIPS trap handling](https://code.googlesource.com/linux/torvalds/linux/+/0d19d9e14687ff6f43d6c4806ace9ff682d7703f/arch/mips/kernel/traps.c).
- **Remediation**: Separate BREAK’s full code extraction/normalization from TEQ/TNE-family extraction.

### M64-R7-11 — BUG — MEDIUM

- **Summary**: Misaligned LL/SC/LLD/SCD report SIGSEGV instead of SIGBUS.
- **Locations**: [unaligned.c:459](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:459), [unaligned.c:490](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:490), [unaligned.c:588](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:588), [unaligned.c:620](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:620).
- **Evidence & Root Cause**: All four alignment checks call `mips_fault()`, which raises SIGSEGV. Linux MIPS rejects alignment emulation for these instructions and delivers SIGBUS, including when FIXADE is enabled. [Linux unaligned-access handling](https://codebrowser.dev/linux/linux/arch/mips/kernel/unaligned.c.html).
- **Remediation**: Use the existing `mips_bus_fault()` path for these alignment failures.

### M64-R7-12 — BUG — MEDIUM

- **Summary**: FCSR Cause bits accumulate across arithmetic instructions.
- **Locations**: [fp.c:103](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:103), [fp.c:109](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:109), [fp.c:841](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:841).
- **Evidence & Root Cause**: `fp_raise()` only ORs causes; `fp_clear_trap()` resets only thread-local trap state. Masked `DIV.S 1/0` followed by exact `ADD.S 1+1` leaves Cause.Z set. Causes must describe the latest arithmetic operation; only Flags are sticky. [MIPS64 FCSR specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Replace the Cause field per arithmetic operation while preserving cumulative Flags.

### M64-R7-13 — BUG — MEDIUM

- **Summary**: Trapped floating-point instructions incorrectly modify sticky Flags.
- **Locations**: [fp.c:109](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:109), [fp.c:144](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:144), [fp.c:207](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:207).
- **Evidence & Root Cause**: Exceptions update Flags independently. With Overflow enabled and Inexact disabled, overflowing arithmetic arms the Overflow trap and then sets Flag.I. Finalization restores the destination and FCC, but leaves that flag changed. Trapped instructions must preserve all Flags. [MIPS64 exception specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Accumulate exceptions, determine whether the instruction traps, then update Flags only on completion.

### M64-R7-14 — BUG — MEDIUM

- **Summary**: Division mishandles infinity operands.
- **Locations**: [fp.c:457](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:457), [fp.c:585](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:585).
- **Evidence & Root Cause**: For `DIV.S 1/+∞` under round-toward-positive-infinity, the residual calculation evaluates `0*∞`, obtains NaN, and incorrectly advances zero to `2^-149`, also setting Inexact. Both S and D paths additionally raise Divide-by-zero for `∞/0`, which should return signed infinity without that exception. [MIPS64 division exception rules](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Resolve zero/infinity operand combinations before residual-based rounding.

### M64-R7-15 — BUG — MEDIUM

- **Summary**: FCSR’s flush-to-zero control is accepted but ignored.
- **Locations**: [fpmove.c:192](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:192), [fp.c:159](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:159), [fp.c:194](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:194).
- **Evidence & Root Cause**: `CTC1` stores FS bit 24, but arithmetic never reads it. With FS set, `MUL.S(2^-126,0.5)` returns subnormal `2^-127` instead of flushing the result to zero. [MIPS64 FS definition](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Apply FS result handling and exception accounting consistently across scalar arithmetic, conversions, PS, and multiply-add.

### M64-R7-16 — BUG — MEDIUM

- **Summary**: Paired-single cancellation produces the wrong zero sign under round-down.
- **Locations**: [fp_ps.c:121](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:121), [fp.c:256](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:256).
- **Evidence & Root Cause**: `ADD.PS(+1,-1)` and `SUB.PS(+1,+1)` produce host-rounded positive zero. `fp_adj_f()` preserves it because numeric `r == q`, even when guest RM requires negative zero. Scalar ADD/SUB already contain a dedicated cancellation correction that PS lacks.
- **Remediation**: Apply the signed-zero cancellation rule independently to both PS lanes.

### M64-R7-17 — DEFECT — MEDIUM

- **Summary**: Required FCSR alias-register accesses raise SIGILL.
- **Locations**: [fpmove.c:181](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:181).
- **Evidence & Root Cause**: CFC1/CTC1 recognize only control registers 0 and 31. Legal FCCR register 25, FEXR register 26, and FENR register 28 accesses return `MIPS_FAULT`, which becomes SIGILL. These aliases are required when the R2 FPU is implemented. [MIPS64 control-register specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Implement alias packing, writable masks, shared FCSR updates, and applicable write-triggered exception checks.

### M64-R7-18 — DEFECT — MEDIUM

- **Summary**: Valid floating-point conditional moves are unimplemented.
- **Locations**: [fp.c:667](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:667).
- **Evidence & Root Cause**: `fp_fmt_sd()` has no handling for function codes `0x11`, `0x12`, or `0x13`: MOVF/MOVT, MOVZ, and MOVN `.S/.D`. They reach `MIPS_FAULT` and SIGILL. The integer MOVCI implementation does not cover these FPR destinations. [MIPS64 formatted-move instruction definitions](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Implement conditional FPR moves with the appropriate FCC/GPR predicate and no arithmetic exception side effects.
