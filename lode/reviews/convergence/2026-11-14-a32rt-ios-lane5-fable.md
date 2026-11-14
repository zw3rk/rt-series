## a32rt Thumb-2 interpreter review (4 files)

No P1 found in the four files; the decode tables are tight and the IT/flag model is right. Findings below are ranked P2, then perf hypotheses, then polish.

### P2

**P2-1. Thumb `trap` (0xDEFE) must be SIGTRAP on XNU, not SIGILL.** `src/interp/interp_thumb.c:82` routes every `0xDExx` to `i_undef`. XNU's `sleh_undef` special-cases `IS_THUMB_GDB_TRAP` (`0xDEFE`, the clang `trap`/`__builtin_trap()` encoding on armv7 Darwin) and the ARM twin `0xE7FFDEFE` as `EXC_BREAKPOINT` → SIGTRAP. Crash reporters, `abort()` paths, and Swift runtime traps on 32-bit iOS depend on this. Fix: before line 82, `if (hw == 0xDEFEU) { ctx->regs[15] = pc; ctx->exit_reason = A32_EXIT_BKPT; return A32_EXIT_BKPT; }` (mirror line 53), and add the ARM `0xE7FFDEFE` case in the A32 stepper.

**P2-2. Inconsistent faulting-PC convention for UNDEF.** `interp_thumb.c:82-84` and `:299-300` call `i_undef` with `regs[15]` still at `pc`, while `:454`, `:527`, `:636`, `:660` and both `t32_undef` helpers set `regs[15] = next` first. Whichever `i_undef`/outer stepper assumes, one group reports the SIGILL frame PC and `si_addr` off by 2 (or 4). Fix: pick one convention (recommend `regs[15] = pc`, since the trap_ret comment says the outer stepper restores it anyway) and make `t32_undef` match.

**P2-3. VFP/NEON delegation loses Thumb PC semantics.** `src/interp/interp_t32_step.c:342` calls `a32_interp_vfp_step(ctx, word)` with no Thumb hint. `VLDR d0, [pc, #imm]` literal-pool loads (ubiquitous in clang armv7 output for FP constants) need `Align(pc+4, 4)`, not ARM `pc+8`. Verify the callee reads `cpsr.T`; if not, pass `pc_align4` or pre-substitute. The `regs[15] == pc` back-patch at `:346` is a heuristic and should become an explicit "callee advanced" return flag.

**P2-4. NEON interpreter coverage gap → spurious SIGILL.** `src/interp/interp_vfp_neon.c:27-31` accepts only VLD1/VST1 multi-register types (`0x7/0xA/0x6/0x2`). VLD2/VLD3/VLD4 (types `0x8/0x9/0x3`, `0x4/0x5`, `0x0/0x1`), all single-element/all-lanes forms (bit 23 = 1), and VREV32/VREV16 (`:91` mask fixes op=00) return `false` → UNDEF. Any iOS image/audio code that drops into the interpreter (SMC region, fault retry, `--interp`) dies. Fix: add the interleaved load/store loop (stride `nregs`, element size `insn[7:6]`), the lane forms, and widen the VREV mask to `0xFFB30E50`.

**P2-5. VLDn partial commit on fault.** `interp_vfp_neon.c:33-46` writes `vfp_d[d]` register-by-register with no span pre-check, unlike the LDM paths (`interp_t32_mem_step.c:124`, `interp_thumb.c:465`). A fault on register 2 leaves d0 modified, then the instruction is retried after the signal handler. Fix: `i_mem_ok(addr, nregs*8, prot)` first, then transfer.

**P2-6. LDM/STM silently drops SP from the list.** `interp_t32_mem_step.c:108` masks `hw2 & 0xDFFF`, which changes `n` and therefore the writeback value relative to hardware (UNPREDICTABLE, but Cortex-A loads SP). Prefer `t32_undef` when bit 13 is set, so divergence is loud.

### PERF (unmeasured hypotheses; instrument via `--stats` per the AGENTS loop)

**PERF-1. T32 dispatch order inverts frequency.** `i_t32_step_ext` evaluates the 8-term `is_vfp` predicate (`interp_t32_step.c:323-330`), then ~45 sequential mask compares, before loads/stores (`F8xx-F9xx`, the most common T32 class) reach `i_t32_mem_step` at `:817`. Hypothesis: a `switch (hw1 >> 9)` on the 7-bit major opcode at the top, with mem/LDM first, removes most compares per instruction.

**PERF-2. Double fetch per 16-bit instruction.** `interp_thumb.c:700` fetches `hw1`, then `t16_step` refetches the same halfword at `:29`. Pass `hw1` as a parameter. Also replace the popcount loops at `interp_t32_mem_step.c:114`, `interp_thumb.c:459/:549/:591` with `__builtin_popcount`.

### POLISH

- `interp_t32_step.c:355` UDF.W test `hw1 == 0xF7F0` only matches imm4 = 0; use `(hw1 & 0xFFF0U) == 0xF7F0U` (it falls through to undef today, so correct but opaque).
- `interp_t32_step.c:418` MRS returns raw `ctx->cpsr`; user-mode XNU code expects T (bit 5) set and mode `0x10`. Confirm the ctx layout matches APSR+T.
- `interp_thumb.c:635` CBZ/CBNZ inside IT → UNDEF. UNPREDICTABLE on paper, but hardware executes; compilers don't emit it, so low value.
- No per-encoding UNDEF counters: add a `--stats` histogram keyed on `(hw1 & 0xFFF0, hw2 >> 12)` at the `t32_undef` sites so coverage gaps like P2-4 surface from real iOS binaries instead of review.

Next step if you want these fixed: P2-1 and P2-2 are one-line each and testable with a `__builtin_trap()` armv7 fixture under the parity suite; P2-4 is the largest piece of work.