# Round-8 Deep-Dive 2 Static Audit: DBT/JIT Emitters, Code Cache, IBTC/RAS, Soft-TLB, Dispatcher

Read-only audit, no builds or tests run. Every file in `src/dbt/*`, `src/rt32/a64_emit*`, `src/rt32/thread_entry.S`, `src/rt32/safe_syscall_a64.S`, `src/dbt/trampoline_a64.S`, and related headers was read line-by-line and cross-checked against the interpreter oracle (`src/interp/*`) and signal consumers. Seven behavioral defects found. Dead code with no callers (donor crypto/DSP/exclusive/signed-pair primitives, disabled `win_fast`) was verified unreachable and is not reported.

| ID | Location | Defect |
|---|---|---|
| S32-R8-1 | [emit_fpbranch.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fpbranch.c:36) | FBO mask `0x8`, oracle `0x7` |
| S32-R8-2 | [emit_int.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:405) | TA exit_arg missing `0x100` bit |
| S32-R8-3 | [emit_cti.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_cti.c:160) + fbranch | Delay fault reports CTI, not delay |
| S32-R8-4 | [emit_cti.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_cti.c:214) + [dbt.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/dbt.c:307) | Taken delay fault npc misses target |
| S32-R8-5 | [emit_int.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_int.c:238) | Logic-cc keeps stale C,V |
| S32-R8-6 | [emit_fp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fp.c:355) | Arith keeps stale FTT bits |
| S32-R8-7 | [thread_entry.S](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/thread_entry.S:107) | `x25` prot base never installed |

## S32-R8-1 — FBfcc cond-15 mask is unordered-only, oracle says ordered

`fp_taken_mask[15]` is `0x8` (fcc==3 only). The oracle table in [fp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:449) and [fp.h](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.h:26) defines cond 15 as FBO `{0,1,2}` = `0x7`. Repro: FBO with `fcc=0` is taken under interp, falls through under DBT. Fix: change the last table entry from `0x8U` to `0x7U`. All other 15 entries match the oracle exactly.

## S32-R8-2 — Software-trap exit_arg drops the `0x100` SW bit

The taken-TA path stores raw `EKEEP` (`trapnum & 0x7F`) to `exit_arg`. The oracle stores `num | SPARC32_TRAP_SW_BIT` ([interp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:221)). The consumer [sparc32_trap_signo](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:831) branches on bit 8, so TA 1 delivers SIGFPE(8) under DBT instead of SIGTRAP(5), and TA `0x2A`/`0x07` deliver SIGFPE instead of SIGILL. Repro: guest executing TA 1 with a SIGTRAP handler installed. Fix: ORR `0x100` into `EKEEP` before the STR at `emit_int.c:405`.

## S32-R8-3 — Branch/Call/FBfcc delay faults report the CTI address, oracle reports the delay address

`ec->fault_pc` stays at the CTI pc in `sparc32_emit_branch`, `sparc32_emit_call`, and `sparc32_emit_fbranch`, so helper fault exits carry `dest` = CTI. The oracle sets `pc = npc` (delay) on delay failure ([interp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:731)). JMPL already does this correctly (`fault_pc = npc` at `emit_cti.c:341`). Repro: taken Bicc whose delay slot is a faulting load; interp commits `pc` = delay, DBT commits `pc` = branch. Fix: set `ec->fault_pc = npc` before delay emission in all three emitters, including the page-final paths.

## S32-R8-4 — Taken CTI delay faults commit `npc = dest+4` instead of the target

`dbt_commit` uses the armed `jmpl_target` only for JMPL, because only JMPL records it. The oracle sets `npc = succ` (`target` when taken) on any delay failure ([interp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:716)). Repro: taken Bicc with faulting delay; DBT commits `npc` = delay+4, interp commits `npc` = target (guest-observable: the signal frame stores `npc`). Fix: record the static target for the taken-path delay copy in branch/call/fbranch, mirroring the JMPL record; the not-taken copy stays unarmed (`dest+4` already equals `succ` there).

## S32-R8-5 — Logic-cc ops commit stale host C,V into `psr.icc`

`ANDcc/ORcc/XORcc/BICcc/ORNcc/XNORcc` end in `ANDS/TST …, LSL #0`, which leaves host C and V unchanged, and `sparc32_emit_commit_flags` copies them into `psr`. The oracle ([interp.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:63)) clears C and V for logic ops. Repro: `SUBcc` setting C=1 (borrow), then `ANDcc`, then `BCS`: interp does not take, DBT takes; `psr.icc` already diverges at the `ANDcc`. Fix: clear host C,V (or mask them from the commit nibble) on the `0x11`–`0x17` path.

## S32-R8-6 — FP arithmetic preserves stale FTT bits

`fp_flags_commit` clears only `cexc` (mask `0xFFFFFFE0`); the FCMP mask (`0xFFFFF3E0`) additionally keeps FTT bit 16. The oracle clears all of FTT on every FPop ([fp_arith.c](vscode://file/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:79)). Repro: TEM trap sets FTT, `LDFSR` clears TEM (FTT is not writable, so it persists), then an inline `FADD`: DBT keeps FTT, interp clears it (`difftest` compares full `fsr`). Fix: clear bits 16:14 in `fp_flags_commit` and bit 16 in the FCMP mask.

## S32-R8-7 — Thread-entry trampoline leaves `x25` undefined (latent)

`THREAD_CORE` installs `x19`/`x20`/`x24`/`x27`/`x28` but never loads the `g_vm32_prot` base into `x25`, which the main trampoline does and every inline prot check (`[x25, wVpn, uxtw]`) requires. Repro: attach the VM, translate a block containing a fast-path load/store, enter via `rt32_thread_enter_block`. Latent: no production caller exists yet and the unit-test probe does not touch `x25`. Fix: mirror the `adrp`/`ldr x25` sequence from `trampoline_a64.S:40-49`.

## Files with 0 behavioral bugs

`a64_emit.h`, `a64_emit.c`, `a64_emit_fp.c`, `emit_cc.c`, `emit_fast.c`, `emit_fpmem.c`, `dbt.c`, `dbt_cache.c`, `trampoline_a64.S`, `dbt_priv.h`, `dbt.h`, `emit_int.h`, `emit_cc.h`, `emit_fast.h`, `emit_fp.h`, `difftest.c`, `difftest.h`, `aot_atomic.h`, `mem_site.h`, `aot_sites.c`, `aot_cache.c`, `aot_cache.h`, `safe_syscall_a64.S`. Verified correct: Class-A `[x20, wAddr, uxtw]` formation with 32-bit wrap, big-endian `REV` placement, direct-slot/IBTC/RAS epoch and key checks, W^X stage-then-flip ordering with quiescence, trampoline callee-saved save/restore, and `x18` (no emission or use anywhere).
