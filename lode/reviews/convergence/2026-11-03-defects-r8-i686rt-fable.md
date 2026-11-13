Good. Here's the complete review:

---

## Round-8 Commit Review: `2e403e3`

### I686-R8-1 — MOVHLPS/MOVLHPS (emit_sse.c:173-177): **Already correct, no fix needed**

The review report's claim is a false positive. The report states MOVLHPS should do "dest low <- src high" (`V0.D[0] <- V1.D[1]`), but this inverts the Intel semantics. The name encodes "move **L**ow **t**o **H**igh":

| Opcode | reg-reg form | Intel semantics | Code emits | Correct? |
|--------|-------------|-----------------|------------|----------|
| `0F 16` (hi=1) | **MOVLHPS** | DEST[127:64] <- SRC[63:0] | `sse_ins_d_elt(b, 0, 1, 1, 0)` = INS V0.D[1], V1.D[0] | **Yes** |
| `0F 12` (hi=0) | **MOVHLPS** | DEST[63:0] <- SRC[127:64] | `sse_ins_d_elt(b, 0, 0, 1, 1)` = INS V0.D[0], V1.D[1] | **Yes** |

Verified by tracing the AArch64 INS encoding in `sse_ins_d_elt` (emit_sse_shared.h:143-148): `imm5 = 8 + 16*di` selects the D-element destination index, `imm4[3] = si` selects the source index. The encoding is correct. The decoder table confirms `0x16` -> `I686_OP_MOVHPS` -> `hi=1` and `0x12` -> `I686_OP_MOVLPS` -> `hi=0` (insn_tab.h:523,527). The report's suggested "fix" would have **introduced** the transposition bug.

The commit correctly leaves this code untouched.

### I686-R8-2 — TSO barriers in emit_branch.c: **Completely fixed**

All 5 guest memory access sites in `emit_branch.c` now have conditional TSO barriers:

| Site | Op | Access | Barrier | Line | Correct? |
|------|-----|--------|---------|------|----------|
| JMP_Ev memory | load | `ldr w10` | `dmb ishld` (`0xD50339BF`) | 333 | **Yes** |
| CALL_Jz push | store | `str w11` | `dmb ish` (`0xD5033BBF`) | 393 | **Yes** |
| CALL_Ev target load | load | `ldr w10` | `dmb ishld` (`0xD50339BF`) | 453 | **Yes** |
| CALL_Ev push | store | `str w11` | `dmb ish` (`0xD5033BBF`) | 493 | **Yes** |
| RET pop | load | `ldr w10` | `dmb ishld` (`0xD50339BF`) | 542 | **Yes** |

Verified:
- **Barrier types** match the established codebase pattern (emit_alu.c:136/152, emit_mov.c:111, emit_string.c:128/147): `dmb ishld` after loads, `dmb ish` after stores.
- **Encodings** are correct: DMB = `D503_3x_BF` where `CRm[3:0]` = 9 (ishld) or B (ish).
- **Guard** uses `if (e->tso)` (emit.h:39 — `bool tso`), matching all other emitters.
- **Placement** is after the faulting access and before `cont_insn_offset` computation, so fault-recovery site metadata correctly includes the barrier in the continuation offset.
- **No missing sites**: register-form paths (JMP_Ev reg, CALL_Ev reg) don't access guest memory, so they need no barriers. JCC/SETcc/CMOVcc are register-only or exit-only with no guest memory traffic.

### Newly introduced issues

**None found in the emitted code.** The 15 new lines are mechanically identical to the barrier pattern used in every other emitter module.

**One stale comment** (cosmetic, not a code defect): the file header at line 58 still reads *"Emitted memory accesses are plain (single-threaded, D5); TSO LDAPR/STLR classes arrive with Phase 4."* — this is now outdated since the DMB barriers have been added. The rest of the codebase also uses DMB rather than LDAPR/STLR for TSO, so the original plan was superseded.

### Curated C11 compliance

The new code uses: `bool` comparison (no implicit int-to-bool), unsigned hex literals with `U` suffix, the existing `a64_emit` API, and `if` guards with braces. No VLAs, no Annex K, no `_Generic`, no undefined behavior. Compliant.
