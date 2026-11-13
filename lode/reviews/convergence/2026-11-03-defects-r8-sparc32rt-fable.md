I have all the evidence needed. Here is the review.

---

## Round-8 DBT/JIT Remediation Review — Commit `2f8c7cc`

### Curated C11 Compliance

All 6 changed files pass:
- No VLAs, no `.c` includes, no Annex K (`*_s`), no `sprintf`/`strcpy`/`strcat`
- Line counts: `emit_cti.c` 370, `emit_fp.c` 748, `emit_fpbranch.c` 244, `emit_int.c` 597, `thread_entry.S` 150, `check_thread_entry.c` 321 — all under 900

---

### S32-R8-1 — FBO mask fix — **VERIFIED**

`emit_fpbranch.c:37`: `fp_taken_mask[15]` changed from `0x8U` to `0x7U`.
Oracle at `src/interp/fp.c:449` defines cond 15 (FBO) as `0x07U` (ordered: {0,1,2}).
All other 15 entries were already correct. Fix is exact.

---

### S32-R8-2 — Software trap `0x100` bit — **VERIFIED**

`emit_int.c:415-418`: On the non-syscall TA path (after the `B.AL` at line 406 is patched at line 414), `EKEEP` still holds the raw trap number. The fix ORs `0x100` (`SPARC32_TRAP_SW_BIT`, defined at `interp.c:61`) before the STR to `exit_arg`. Oracle at `interp.c:221` stores `num | SPARC32_TRAP_SW_BIT`. Consumer at `interp_signal.c:831` branches on `exit_arg & 0x100`. Control flow is correct: syscall path (lines 407-413) stores `g1` to `exit_arg` separately.

---

### S32-R8-3 — Delay fault address — **VERIFIED**

Three sites changed `ec->fault_pc` from `pc` to `npc`:
- `emit_cti.c:163` (`sparc32_emit_branch`)
- `emit_cti.c:264` (`sparc32_emit_call`)
- `emit_fpbranch.c:174` (`sparc32_emit_fbranch`)

Matches the JMPL pattern already correct at `emit_cti.c:363` and the oracle (`interp.c:731` sets `pc = npc` on delay failure). All three sites set `fault_pc = npc` before any delay emission or page-final exit.

---

### S32-R8-4 — Taken delay npc = target — **VERIFIED**

Nine `a64_jmpl_record` calls added across taken-path delay copies:
- `emit_cti.c`: lines 180-182, 215-217, 239-241 (branch cond 0x8, page-final conditional, general conditional); lines 271-273, 290-292 (call page-final and main)
- `emit_fpbranch.c`: lines 182-184, 204-206, 229-231 (FBA, page-final conditional, general conditional)

`dbt_commit` at `dbt.c:307-309` already checks `jmpl_delay_armed` for TRAP/FAULT exits and uses `jmpl_target`. The armed flag is cleared at each fragment entry (`dbt.c:366`). Not-taken paths correctly do not arm. Register clobbering of scratch ES0/ES1/ES2 (or FS0/FS1/FS2 in fpbranch) is safe — delay emission re-loads from the decoded instruction.

New `#define FS2 17u` at `emit_fpbranch.c:25` uses x17 (IP1, caller-saved), no conflict with callee-saved or x18.

---

### S32-R8-5 — Logic-cc C,V clearing — **REGRESSION**

`emit_int.c:285`: Range check `d->op3 >= 0x11U && d->op3 <= 0x17U` **includes `0x14` (SUBcc)**. The decoder stores the raw 6-bit op3 (`decode.c:215`), so SUBcc = `0x14`, and `d->cc = 1` (`decode.c:228`).

The logic-cc ops needing C,V cleared are: `0x11` (ANDcc), `0x12` (ORcc), `0x13` (XORcc), `0x15` (ANDNcc), `0x16` (ORNcc), `0x17` (XNORcc). SUBcc (`0x14`) is arithmetic and needs its SUBS-produced C,V preserved.

**Impact**: After clearing C=0, `commit_flags(sub_ops=true)` at line 295 inverts C to 1 (`emit_cc.c:156-157`). SUBcc always commits psr.icc.C=1 and psr.icc.V=0 regardless of actual borrow/overflow. Any subsequent `BCS`/`BCC`/`BVS`/`BVC` after SUBcc will diverge from the oracle.

**Fix**: The condition should exclude 0x14:
```c
if ((d->op3 >= 0x11U && d->op3 <= 0x13U) ||
    (d->op3 >= 0x15U && d->op3 <= 0x17U))
```

---

### S32-R8-6 — FTT clearing in FP commit — **PARTIAL**

**`fp_flags_commit`** (`emit_fp.c:356`): Mask changed from `0xFFFFFFE0` to `0xFFFE3FE0`. Clears bits 16:14 (all FTT) + bits 4:0 (cexc). **Correct** — matches oracle clearing all FTT on every FPop.

**`fp_fcc_commit`** (`emit_fp.c:392`): Mask changed from `0xFFFFF3E0` to `0xFFFEF3E0`. Clears only bit 16 of FTT, plus bits 11:10 (fcc) and 4:0 (cexc). **Bits 15:14 of FTT are not cleared.**

The implementation matches the defect report's literal recommendation ("bit 16 in the FCMP mask"), but the oracle clears *all* of FTT (bits 16:14) on every FPop including FCMP. Stale FTT values 1 (IEEE\_754\_exception, `001`), 2 (unfinished, `010`), or 3 (unimplemented, `011`) have bits 15 and/or 14 set, which survive the FCMP path. FTT=1 is the most common trap-induced stale value.

**Fix**: The FCMP mask should be `0xFFFE33E0` (clearing all of bits 16:14, 11:10, 4:0).

---

### S32-R8-7 — Thread-entry x25 installation — **VERIFIED**

`thread_entry.S:110-119`: `adrp + ldr x25` sequence with Apple/ELF conditional assembly, identical pattern to `trampoline_a64.S:44-48`. Loads `g_vm32_prot_jit` pointer value into x25.

Test updated:
- `check_thread_entry.c:63-65`: Local `g_vm32_prot_jit` symbol definition
- `check_thread_entry.c:106,120`: `tentry_rec.x25_seen` field + `_Static_assert`
- `check_thread_entry.c:150`: Assembly probe stores x25 at offset 56
- `check_thread_entry.c:212`: Verification `x25_seen == tentry_prot_table`

---

### Summary

| ID | Verdict | Evidence |
|---|---|---|
| S32-R8-1 | **VERIFIED** | `emit_fpbranch.c:37` → `0x7U`, matches `fp.c:449` |
| S32-R8-2 | **VERIFIED** | `emit_int.c:417-418` ORR `0x100`, matches `interp.c:61,221` |
| S32-R8-3 | **VERIFIED** | `emit_cti.c:163,264`, `emit_fpbranch.c:174` fault_pc = npc |
| S32-R8-4 | **VERIFIED** | 9 `a64_jmpl_record` sites, `dbt.c:307-309` consumes correctly |
| S32-R8-5 | **REGRESSION** | `emit_int.c:285` range `[0x11,0x17]` includes SUBcc (`0x14`) |
| S32-R8-6 | **PARTIAL** | `emit_fp.c:356` all FTT ✓; `emit_fp.c:392` only bit 16, not 15:14 |
| S32-R8-7 | **VERIFIED** | `thread_entry.S:113-119`, test at `check_thread_entry.c:212` |

**Newly introduced bugs**: 1 — S32-R8-5 regression breaks SUBcc carry and overflow flags.
