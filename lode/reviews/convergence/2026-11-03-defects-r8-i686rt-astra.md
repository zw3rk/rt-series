# i686rt Round-8 Deep-Dive 2 — DBT/JIT Static Audit Report

Read-only audit (no files modified, no builds/tests run). Every file below was read line-by-line in full.

## Summary

| ID | Severity | Location | Finding |
|---|---|---|---|
| I686-R8-1 | **BUG** | `src/dbt/emit_sse.c:173-177` | Register-form `MOVHLPS`/`MOVLHPS` lane moves are transposed |
| I686-R8-2 | **DEFECT** | `src/dbt/emit_branch.c:326-332, 378-389, 440-446, 472-483, 524-530` | Branch-module guest accesses emit no TSO barriers in TSO mode |

## I686-R8-1 — MOVHLPS/MOVLHPS reg-reg transposition (BUG)

In `sse_emit_movlp_hp`, the `modrm_mod == 3` arms are backwards:

```c
if (hi != 0U) {
    sse_ins_d_elt(b, 0U, 1U, 1U, 0U); /* MOVLHPS: d1 <- s0 */
} else {
    sse_ins_d_elt(b, 0U, 0U, 1U, 1U); /* MOVHLPS: d0 <- s1 */
}
```

`hi==1` is opcode `0F 16` whose reg-reg form is `MOVLHPS` (decoder confirms: `src/x86/insn_tab.h:527`), which must do `V0.D[0] ← V1.D[1]` (dest low ← src high). The code emits `V0.D[1] ← V1.D[0]` — that is `MOVHLPS` semantics, and vice versa for the `hi==0` (`0F 12`) arm. The memory load/store lanes in the same function are correct (`hi ? d1 : d0`), so only reg-reg is affected.

Reproduction: guest `movlhps xmm0,xmm1` with `xmm0={A0,A1}`, `xmm1={C0,C1}` (64-bit lanes) must yield `{C1,A1}`; the DBT yields `{A0,C0}`. Pure-register, deterministic, every execution.

Minimal fix — swap the two statements (and the comments):

```c
if (hi != 0U) {
    sse_ins_d_elt(b, 0U, 0U, 1U, 1U); /* MOVLHPS: d0 <- s1 */
} else {
    sse_ins_d_elt(b, 0U, 1U, 1U, 0U); /* MOVHLPS: d1 <- s0 */
}
```

## I686-R8-2 — Branch-module guest accesses lack TSO ordering (DEFECT)

After `clone(CLONE_VM)`, `e->tso` is set and every other lane orders its guest accesses (`emit_alu.c`/`emit_alu_impl.h` load/store add `dmb ishld`/`dmb ish`; `emit_mov.c:110-113` likewise; `emit_string.c:127-129,146-148` likewise; SSE gets `translate.c:363-365`'s trailing `dmb ish`). `emit_branch.c` contains zero barriers: `CALL_Jz` pushes the return address with a plain `STR` (`:386/:388`), `CALL_Ev` loads the indirect target (`:443/:445`) and pushes (`:480/:482`) plain, `RET` pops with a plain `LDR` (`:526/:528`), and `JMP_Ev` loads its target plain (`:329/:331`). TSO-mode CALL/RET/indirect-jump memory traffic is therefore ordered exactly as in single-threaded mode, contrary to D5.

Reproduction: two-thread guest sharing the stack page (or racing an indirect-call pointer), one thread executing `CALL`/`RET`/indirect-`JMP` while another observes the slot — AArch64 may make the barrier-free access visible out of x86-TSO order. Rare in practice (stacks are normally thread-private), hence DEFECT rather than BUG.

Minimal fix — mirror `l3s_guest_load/store`: after each cited access, `if (e->tso) a64_emit(b, 0xD50339BFU)` (loads) / `0xD5033BBFU` (stores); alternatively extend `translate.c:360-366`'s post-emit trailing barrier to branch-module memory ops.

## Per-file verdicts

- `src/rt32/rt32_a64_emit.h` — 0 bugs (reg map, cond codes, offsets verified).
- `src/rt32/rt32_a64_emit.c` — 0 bugs (all integer/logical/shift/bitfield/guest-mem encodings verified; `ldrd` alias path has no callers).
- `src/rt32/rt32_a64_emit_exit.c` — 0 live bugs. All five exit functions are unreachable (no callers repo-wide; the trampoline passes epoch in `x26`, not the `x28` these stubs assume). Encodings spot-checked correct.
- `src/trampoline.S` — 0 bugs (GPR/epoch/IBTC hash `(dest>>2)&1023`, 32-byte stride, per-link epoch check, 4096-block budget, `.Lexit` spill verified against `i686rt.h` offsets).
- `src/dbt/emit.h`, `engine_internal.h` — 0 bugs.
- `src/dbt/translate.c` — 0 bugs (pre-scan barrier model sound: memory ops are always barriers so skipped flag stores can't straddle a fault; `R7-7` illegal-LOCK guard precedes all emitters; fallback sites cover site-less string/SSE insns).
- `src/dbt/emit_exit.c` — 0 bugs (EA wraps in `W` before seg add; 16-bit path wraps at 64 KiB first; epilogue stores full 32-bit arg/dest).
- `src/dbt/emit_alu.c`, `emit_alu_impl.h`, `emit_alu_ext.c`, `emit_alu_ext2.c` — 0 bugs (SUBS-polarity `C=!CF` image used consistently by fuse/carry-in/materialize paths; 8/16-bit shift-trick, `BFI` partial writes, DIV/IDIV fault-stub shapes, CL-count early-outs verified).
- `src/dbt/emit_mov.c` — 0 bugs (high-byte/16-bit preservation, PUSH-ESP pre-value, POP-ESP wins, 16-bit LEA masking verified).
- `src/dbt/emit_atomic.c` — 0 bugs (LSE mapping, CMPXCHG unconditional-AL writeback, lazy descriptors, decline-to-interp chain verified).
- `src/dbt/emit_string.c` — 0 bugs (seg defaults, DF-from-`eflags` always current since lazy never covers DF, post-access bumps, full six-flag materialization verified).
- `src/dbt/emit_sse_shared.h` — 0 bugs (XMM write-through cache keeps `ctx` coherent; encodings match cited assembler forms).
- `src/dbt/emit_sse2.c` — 0 bugs (`COMIS` ZF/PF/CF composition, `CVTTSS2SI/SD2SI` boundary guards with NZCV save/restore, `CVTPD2PS` upper-zeroing verified).
- `src/dbt/engine.c` — 0 bugs (RW→translate→flush→RX flip order, pre/post `page_gen` race sampling, IBTC/RAS sever-on-evict, per-link epoch validation, UNDEF/TRAP/FAULT `eip` discipline verified).
- `src/dbt/engine_smc.c` — 0 bugs (write-protect→fault→bump/invalidate/restore; read-only-page check before treating as SMC).
- `src/dbt/flags_dbt.c` — 0 bugs (rebuild clobbers only `w8/w9/w11`, dead at all use sites).
- `src/dbt/aot/aot.c`, `aot.h` — 0 live bugs (ring generation checks sound; serializer/find/patch helpers have no callers).

## Invariant notes (all hold)

- `x18` is never emitted or clobbered anywhere (only AAPCS-range comments); `x24`/`x25` likewise (matches are offsets/immediates).
- Class-A `[x20, wAddr, uxtw]` with 32-bit `W` wrap holds on every live guest access; `FS:`/`GS:` bases load at runtime, flat-segment folding is gated by `i686_seg_dbt_eligible`.
- No Soft-TLB inline emission exists (direct window on both Regime A1/A2; `vm_tlb` permanently `NULL`) — nothing to defect-report.
- I-cache discipline is correct on both OS paths; `A32H_CAP_ICACHE_TRAP_IALLU` is defined but unused (harmless — unconditional invalidate is correct everywhere).
- Live `EXIT_UNDEF` carries `(len, pc)` for exact D2 single-step; `EXIT_TRAP` lands past the insn; GPRs commit inline or via trampoline `.Lexit` before `interp_step`/signal delivery.
