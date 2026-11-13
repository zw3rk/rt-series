## Review: Commit ea01633 — RTS-R11-1 Remediation

### Classification: **VERIFIED**

---

### Defect RTS-R11-1: SPARC32 `rt_signal_frame` size and field order

**What the astra review found**: `sparc32_rt_signal_frame_t` in `check_abi_invariants.c` contained a spurious `extramask[1]` field, wrong field order (`stack` after `rwin_save`), and wrong size (348 vs frozen 344).

**What the commit does** (single file changed: `tests/check_abi_invariants.c`, +7 −6):
1. Removes `extramask[1]` (4 B word not in the kernel's `rt_signal_frame32`)
2. Moves `sparc32_stack_t stack` to immediately after `insns[2]` (offset 0x144)
3. Places `extra_size` at 0x150, `rwin_save` at 0x154
4. Updates `sizeof` assertion from 348 to 344
5. Adds two new offset assertions for `extra_size` and `rwin_save`

**Offset arithmetic cross-check** against SPEC.md:364–374 and ISA-TRAP-AND-ABI-MATRIX.md:55:

| Field | Post-commit offset | SPEC.md | ISA Matrix | Match |
|---|---|---|---|---|
| `stack` | 96+128+80+8+4+8 = 324 = **0x144** | 0x144 | 0x144 | Yes |
| `extra_size` | 324+12 = 336 = **0x150** | 0x150 | 0x150 | Yes |
| `rwin_save` | 336+4 = 340 = **0x154** | 0x154 | 0x154 | Yes |
| Total size | 340+4 = **344** (0x158) | 344 / 0x158 | 344 / 0x158 | Yes |

All pre-existing assertions (`regs` at 0xe0, `mask` at 0x130, `fpu_save` at 0x138) remain unchanged and still correct.

---

### Newly introduced bugs: **None**

- The removed `extramask[1]` is absent from the Linux kernel's `arch/sparc/kernel/signal_32.c` `rt_signal_frame32` and from both frozen SPEC references. Removal is correct.
- The reorder matches the kernel field order exactly.
- No other struct, assertion, or logic was touched.

### Curated C11 compliance

| Check | Result |
|---|---|
| VLAs | None |
| `.c` includes | None (only `<stddef.h>`, `<stdint.h>`, `<stdio.h>`, `"a32host.h"`) |
| File length | 334 lines (limit 900) |
| `sprintf`/`strcpy`/`strcat` | None (`fprintf`/`printf` only) |
| Annex K / `<threads.h>` / `_Generic` | None |

All checks pass.

---

**Summary**: RTS-R11-1 is **VERIFIED** — the commit aligns `sparc32_rt_signal_frame_t` exactly with the frozen layouts in both SPEC.md and ISA-TRAP-AND-ABI-MATRIX.md, adds stronger offset coverage, introduces no regressions, and is clean Curated C11.
