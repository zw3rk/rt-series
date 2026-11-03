Here is the full item-by-item review of commit `997d71b`.

---

## Round-8 Remediation Review (RTS-R8-1..9)

### RTS-R8-1 — `AT_PAGESZ` contradiction on `sparc64rt` — **VERIFIED**

`docs/HOST-CONTRACT.md:36` now reads "except `sparc64rt` with `AT_PAGESZ = 8192`" and line 42 adds an explicit "On `sparc64rt`, substitute `8192` for `4096`" rule across all four syscall families. Consistent with `SPEC.md:92` D11.

### RTS-R8-2 — `A32H_CAP_FIXADE` / `A32H_CAP_SOFT_TLB_256M` undocumented — **VERIFIED**

`docs/HOST-CONTRACT.md:104` versioning text now lists bits 9–11. Lines 115–116 add the two new capability entries with `(ABI 1.1)` attribution.

**Minor**: Bits 10, 11 are listed *before* bit 9 (ordering: 0–8, 10, 11, 9). Cosmetic only — not incorrect.

### RTS-R8-3 — Stale `x20 = xG` invariant — **VERIFIED**

`SPEC.md` updated in three places — line 22 (Class A intro), line 83 (D2 table), and line 273 (MIPS32 register map). All now distinguish Regime A1 (`H == 4096`: `x20 = xG`) from Regime A2 (`H > 4096`: `x20 = &ctx->tlb[0]`, `x23 = xG`). Matches `UNIFICATION-PLAN.md:363`.

### RTS-R8-4 — IBTC direct linking without invalidation rule — **VERIFIED**

`SPEC.md:127` (L-C6b bullet) now specifies: "Direct block linking / IBTC / RAS lookup is gated on the code-cache epoch (`vm_code_epoch`): every `munmap`, `mprotect`, or SMC store bumps the epoch and invalidates overlapping blocks/IBTC/RAS entries."

### RTS-R8-5 — `ICACHE_TRAP_IALLU` vs explicit invalidation — **VERIFIED**

Two changes in `docs/UNIFICATION-PLAN.md`:
- Line 92 diagram: `IC IALLU` → `seal_rx I-cache` (both providers).
- Line 465 `rt_host_jit_seal_rx` comment: specifies Linux path (`IC IALLU`/EL2 trap only under `A32H_CAP_ICACHE_TRAP_IALLU`, else `__builtin___clear_cache`) and Darwin path (`pthread_jit_write_protect_np(1)` + `sys_icache_invalidate`).

### RTS-R8-6 — Missing `--` separator — **VERIFIED**

`tools/remote_bench_common.sh`: three `--` separators added:
- Line 36 fallback `printf`: `'%s --%s'` → `'%s --%s --'`
- Line 74: inserted `--` before `"$_rrt_guest"`
- Line 136: inserted `--` before `"$_rrh_guest"`

All three Class-B non-`rvrt` paths now match the `rvrt` pattern.

### RTS-R8-7 — Single-engine grind suites mask divergence — **VERIFIED**

New `run_dual_or_single_guest()` helper (`tools/run_grind.sh:277–314`) runs both engines, compares exit codes AND stdout (`cmp -s`), reports divergence via `grind_fail`. Integrated into: compiler-rt builtins, libc-ltp, TestFloat (new block at ~line 618), stress-ng, lmbench, and LTP.

**Minor**: lmbench and LTP inline blocks compare only exit codes (stdout is non-deterministic for benchmarks — acceptable). The `elif [ "$?" -eq 1 ]` pattern at lines ~695 and ~754 is correct per POSIX but fragile; any future insertion between `if` and `elif` would silently break exit-code routing.

### RTS-R8-8 — `gcc-torture` without independent oracle — **VERIFIED**

`tools/run_grind.sh:408–412`: new gate skips foreign-arch gcc-torture when `GRIND_QEMU` is unset, reporting "GAP without independent oracle" (SKIP, not PASS). Escape hatch `GRIND_ALLOW_NO_ORACLE=1` is intentional per the defect's "report `GAP` or `SKIP`" language.

### RTS-R8-9 — `p3_torture` lacks SMC/`clear_cache` coverage — **VERIFIED**

New `t_smc_clear_cache()` (`tests/p3_torture.c:819–874`) and `main()` call at line 888. Test flow: map RW → write "return 42" → `__builtin___clear_cache` → seal RX → call (assert 42) → unseal RW → patch to "return 99" → clear → seal RX → call (assert 99). Seven architecture codegen paths (AArch64, x86_64, RISC-V, MIPS, PowerPC, SPARC, LoongArch) plus Apple `MAP_JIT` handling. Machine code encodings verified correct for all seven ISAs.

---

## Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None in `p3_torture.c` |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| `<threads.h>` / `_Generic` | None |
| C files ≤ 900 lines | `p3_torture.c` = **900** (at limit, passes) |

---

## Newly Introduced Bugs

**None found.** Three minor observations (not bugs):

1. **HOST-CONTRACT.md cap ordering** — bits 10, 11 listed before bit 9. Cosmetic.
2. **`$?` fragility** in `run_grind.sh` — correct today, but a maintenance hazard if code is inserted between `if` and `elif`.
3. **lmbench/LTP dual-engine** — exit-code-only comparison misses divergent stdout on identical exit codes. Acceptable for non-deterministic benchmark output.

---

**Overall: 9/9 VERIFIED, 0 PARTIAL, 0 REGRESSION. No new bugs. Commit is clean.**
