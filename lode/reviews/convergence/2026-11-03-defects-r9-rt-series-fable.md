Good — line 558 confirms the second page is `PROT_READ`, so the byte-loop's first write to `vedge[7]` (which is `base + ps + 2`, on the RO page) will fault immediately. All the evidence is now assembled.

---

## Round-9 Remediation Review: `fd1fa05` (RTS-R9-1..8)

**Commit**: `fd1fa05` — 2 files changed, 82 insertions, 88 deletions.
**Files**: `SPEC.md` (533 lines), `tests/p3_torture.c` (895 lines).

### Per-Item Verdicts

**RTS-R9-1 — Named P1/P2/P4 torture files absent** — **VERIFIED**

The commit chose the "restate scope as P3-only" alternative from the astra finding. `p3_torture.c:2-5` now documents that `rt-series/tests/` hosts shared cross-ISA P3/ABI/benchmark suites, while ISA-specific P1/P2/P4 suites live in each translator repo under `tests/guest/`. No false claim of coverage.

**RTS-R9-2 — N64 placement contradiction** — **VERIFIED**

`SPEC.md:474` now reads `mmap_base = 0x000000c000000000`, `interp_bias = 0x000000f000000000`, `sigtramp = 0x000000ffffff1000`. Cross-checked against `ISA-TRAP-AND-ABI-MATRIX.md:22` (`0xc0_0000_0000`, `0xf0_0000_0000`, `0xff_ffff_1000`) — all three match the `[F]`-tagged matrix.

**RTS-R9-3 — N32 placement contradiction** — **VERIFIED**

`SPEC.md:475` now reads `mmap_base = 0x60000000`, `interp_bias = 0x70000000`. Matches `ISA-TRAP-AND-ABI-MATRIX.md:22` exactly.

**RTS-R9-4 — SPARC32 frame size and order** — **VERIFIED**

`SPEC.md:365-375`: `extramask[1]` removed, total restated as **344 bytes / `0x158`**. Layout order now: `insns[2]` at `0x13c`, `stack_t` at `0x144`, `extra_size` at `0x150`, `rwin_save` at `0x154`. Byte arithmetic: 96+128+80+8+4+8+12+4+4 = 344. Matches both `signal_32.c` and `ISA-TRAP-AND-ABI-MATRIX.md:55`.

**RTS-R9-5 — PPC64 vmx_reserve arithmetic** — **VERIFIED**

`SPEC.md:463` now reads `68 + 32 + 1` with "plus `8 B` alignment slack". 68 × 8 = 544 (vrregset) + 32 × 8 = 256 (vsr_low) + 1 × 8 = 8 (slack) = 808 B = 101 `uint64_t`s. Correct.

**RTS-R9-6 — Fault probe calls memcpy under handler** — **VERIFIED**

`p3_torture.c:582-586`: `memcpy` replaced with a `volatile unsigned char *vedge` byte loop. Loop writes `k = 8..1` (high-to-low), so `vedge[7]` (at `base + ps + 2`, on the RO second page) is written first, faulting immediately via `siglongjmp` before any first-page byte is touched. No async-signal-safety issue — only volatile stores, no library calls in the fault window.

**RTS-R9-7 — Weak si_addr acceptance, no partial-write check** — **VERIFIED**

`p3_torture.c:601-603`: `si_addr` lower bound tightened from `base` to `base + ps` (must be on the 2nd page). First-page integrity verified via `pre_first[5]` snapshot (`p3_torture.c:575-576`) compared after the fault (`memcmp` at line 603). A translator reporting a first-page address or partially mutating the RW page now fails.

**RTS-R9-8 — No brk, mremap, fork-COW, auxv, or 8K tests** — **PARTIAL**

`p3_torture.c:844-868`: New `t_vm_fork_cow()` test added — maps 2 pages, forks, child mutates, parent verifies COW isolation. Also validates `_SC_PAGESIZE >= 4096` and power-of-two (AT_PAGESZ proxy). Called from `main()` at line 883. However, **brk byte-granular**, **mremap file-backing preservation**, and **SPARC64 8K COW** probes were not added. These may be deferred to per-translator P1/P2 suites (consistent with the RTS-R9-1 scope restatement).

### New Bug Check

No newly introduced bugs found:

1. **`t_vm_fork_cow`**: child uses `_exit()` (correct, avoids atexit/stdio flush). `waitpid` return and `WIFEXITED`/`WEXITSTATUS` checked. Both paths `munmap`. `<sys/wait.h>` properly added at `p3_torture.c:32`.
2. **Byte-loop write order**: high-to-low ensures RO 2nd page is hit first (`vedge[7]` = `base + ps + 2`); first-page bytes `vedge[0..4]` are never reached before the fault. `memcmp` verification is sound.
3. **No resource leaks**: all error paths `munmap` and restore `mprotect`.

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None (`grep -E 'VLA\|#include.*\.c'` clean) |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None in diff |
| File lengths | SPEC.md: 533, p3_torture.c: 895 — both under 900 |
| Feature macros | `_POSIX_C_SOURCE 200809L`, `_DEFAULT_SOURCE` — correct |

### Summary

| Item | Verdict | Evidence |
|---|---|---|
| RTS-R9-1 | **VERIFIED** | `p3_torture.c:2-5` scope restatement |
| RTS-R9-2 | **VERIFIED** | `SPEC.md:474` matches matrix `[F]` values |
| RTS-R9-3 | **VERIFIED** | `SPEC.md:475` matches matrix `[F]` values |
| RTS-R9-4 | **VERIFIED** | `SPEC.md:365-375` — 344 B, correct field order |
| RTS-R9-5 | **VERIFIED** | `SPEC.md:463` — `68 + 32 + 1` = 101 words |
| RTS-R9-6 | **VERIFIED** | `p3_torture.c:582-586` volatile byte-loop |
| RTS-R9-7 | **VERIFIED** | `p3_torture.c:601-603` 2nd-page bound + `pre_first` check |
| RTS-R9-8 | **PARTIAL** | fork-COW added (`p3_torture.c:844-868`); brk/mremap/8K COW absent |

**7 VERIFIED, 1 PARTIAL, 0 REGRESSIONS.** No new bugs or C11 violations introduced.
