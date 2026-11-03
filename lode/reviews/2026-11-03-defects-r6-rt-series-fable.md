# Verification Report: commit `958acdf` vs. Round-6 defects (rt-series-R6-1..4)

Scope: static review of `git show 958acdf` plus current file contents at `master`. No builds, tests, containers, or QEMU were run. All three touched shell scripts pass `sh -n`.

| ID | Classification | One-line verdict |
|---|---|---|
| rt-series-R6-1 | **VERIFIED** | `want_suite` gates each soak job; `--suite` is validated by allowlist. |
| rt-series-R6-2 | **VERIFIED** (alternate approach) | Suffix-aware globs now cover every `_$$.<ext>` temp file; `mktemp -d` was not adopted. |
| rt-series-R6-3 | **VERIFIED** | `PHASE` and `KIND` allowlisted (exit 2); zero-executed guard (exit 1) in both dispatchers. |
| rt-series-R6-4 | **PARTIAL** | Dead-store concern removed, but the fix uses exactly the bytewise volatile writes the card said not to use; access width is no longer cross-page. |

---

## rt-series-R6-1 — weekly `--suite` ignored for soak workloads — VERIFIED

**Suite validation** (`tools/run_grind.sh:55-61`):
```sh
case "$SUITE_FILTER" in
    all|stress-ng|gcc-torture|torture|testfloat|compiler-rt|libc-ltp|libc|ltp|lmbench|csmith|yarpgen|upstream-check|upstream) ;;
    *) echo "ERROR: Invalid --suite '$SUITE_FILTER' ..." >&2; exit 2 ;;
esac
```
Runs before backend resolution and before any job, so a typo fails fast with exit 2.

**Per-job gating** inside `run_weekly_soak` (`tools/run_grind.sh:748`, `:769`, `:827`):
```sh
if want_suite csmith; then ...          # :748
if want_suite yarpgen; then ...         # :769
if want_suite upstream-check; then ...  # :827  (wraps the 1800 s make check at :830)
```
`want_suite` (`:119-127`) returns true for `all`, exact match, or the alias groups `torture→gcc-torture`, `libc|ltp|libc-ltp→libc-ltp`, `upstream→upstream-check`. The `run_arch_job` dispatch (`:845-856`) still calls `run_weekly_soak` unconditionally when `TIER=weekly`, but because every block inside is now gated, `weekly --suite stress-ng` executes only stress-ng. Matches the card's fix exactly.

Minor observation, not a defect: the error text at `:58` omits the accepted `upstream` alias that the `case` at `:56` allows. Cosmetic.

## rt-series-R6-2 — EXIT cleanup glob misses `_<pid>.c/.out/.log` — VERIFIED

Fix taken (`tools/run_grind.sh:11`):
```sh
grind_cleanup() { rm -rf /tmp/grind_*_$$ /tmp/grind_*_$$.* "${_ydir:-}" /tmp/grind_libc_$$.log /tmp/grind_ltp_$$.log /tmp/rt_grind_*_$$ /tmp/rt_grind_*_$$.* /tmp/csmith_*_$$ /tmp/csmith_*_$$.* /tmp/yarpgen_*_$$ /tmp/yarpgen_*_$$.* 2>/dev/null; }
```
I enumerated every `/tmp/` path in the script. All are of the form `/tmp/grind_<name>_$$` or `/tmp/grind_<name>_$$.<ext>`, including the ones the card cited: `grind_builtins_*_$$.c` (`:500`), `grind_csmith_*_$$.c` (`:754`), `grind_diff_{ref,dbt}_$$.out` (`:689-690`), `grind_testfloat_$$.log` (`:414`), `grind_lm*_$$.log` (`:651`, `:666`), `grind_upstream_$$.log` (`:736`, `:830`). The added `/tmp/grind_*_$$.*` glob covers every suffixed file, so interruption via EXIT/INT/TERM traps (`:12-14`) now removes them.

The card recommended a single `mktemp -d` scratch directory. The commit did not do that (no `mktemp` in the file). The glob approach resolves the stated leak, so I classify as VERIFIED, with the note that the `rt_grind_*`, `csmith_*`, and `yarpgen_*` patterns match nothing in the script and are dead entries. A future temp file named outside the `grind_*_$$[.ext]` convention would silently reintroduce the leak, which the `mktemp -d` design would have prevented structurally.

## rt-series-R6-3 — unvalidated `PHASE` / `KIND` selectors — VERIFIED

`tools/remote_bench.sh:26-32`: `case "$PHASE" in all|baseline|darwin|darwin-interp|hl|linux|linux-interp|qemu) ;; *) ... exit 2`. The allowlist matches the eight `if [ "$PHASE" = ... ]` blocks that follow (`:53`, `:62`, `:73`, `:84`, `:96`, `:101`, `:106`). `REMOTE_BENCH_COUNT` is incremented after each `parse_and_print` or inner-script dispatch, and `:111-114` exits 1 if it is still zero.

`tools/remote_linux_inner.sh:25-31`: `case "$KIND" in dbt|interp|qemu) ;; *) ... exit 2`. `REMOTE_INNER_COUNT` is incremented in both branches (`:45`, `:49`) and `:53-56` exits 1 on zero. This also catches the case where `ARCH_LIST` is empty or every iteration skips, which is stronger than the card asked for.

Both halves of the card's fix (allowlist + "at least one executed" guard) are present.

## rt-series-R6-4 — deliberate faulting store eliminable by optimizer — PARTIAL

Current code (`tests/p3_torture.c:581-590`):
```c
volatile unsigned char *vedge =
    (volatile unsigned char *)(base + (size_t)ps - 5);
uint64_t bad = 0xFEDCBA9876543210ULL;
unsigned char bad_bytes[sizeof(bad)];
memcpy(bad_bytes, &bad, sizeof(bad));
for (size_t k = 0; k < sizeof(bad); k++) {
    vedge[k] = bad_bytes[k];
}
atomic_signal_fence(memory_order_seq_cst);
```

**What is fixed:** the stores are now `volatile`, so the compiler must emit them; `<stdatomic.h>` is already included (`:37`) so `atomic_signal_fence` compiles. The "eliminated store" concern is closed.

**What is not fixed:** the card's Fix text explicitly says "Preserve the intended cross-page access width; substituting bytewise volatile writes would test a different operation." The commit does precisely that substitution. Consequences:

- The original intent (and the pass message at `:617`, "straddling load/store exact") is a single 8-byte store at `base+ps-5` that straddles the RW/RO page boundary. The translator's cross-page unaligned store path, including correct `si_addr` delivery for a straddling access, is what this probe exists to exercise.
- With bytewise stores, `vedge[0..4]` land on the writable page and succeed, and the first trap is a 1-byte store at exactly `base+ps`, a page-aligned address. No straddling store is ever issued to the guest ISA, so the translator path under test is never reached.
- The existing checks (`:597`, `:604-605`) only assert signal type and that `si_addr` lies within the mapping. They cannot distinguish the degraded probe from the intended one, so the test will still report PASS without exercising the target behaviour. This is a silent weakening rather than a visible failure.

Classification is PARTIAL rather than REGRESSION because the pre-commit `memcpy` was in practice unlikely to be eliminated (the buffer is later passed to `mprotect`/`munmap`, which are opaque calls), so the old code probably did emit a straddling store. The new code definitely does not. The net effect on test strength is negative for the translator's wide-store path, and I would treat it as needing a follow-up.

**Recommended follow-up:** replace the loop with an explicit 8-byte store whose address and value are compiler-visible operands and which carries a memory clobber, so the width is preserved. One portable form: `*(volatile uint64_t *)` is not usable here because it would also require alignment the probe deliberately lacks. Use a per-architecture inline-asm unaligned store (e.g. `str %x[v], [%x[p]]` on AArch64, `movq` on x86, with `"memory"` clobber) selected by `#if defined(__aarch64__)` etc., falling back to `memcpy` plus `__asm__ volatile("" :: "r"(edge) : "memory")` after the call for architectures without a hand-written variant. Since the guest tests are compiled for each foreign ISA, the fallback form with the memory clobber is the minimum change that keeps width and defeats elimination.

---

## Summary

Three of four items are fully remediated with exact file:line evidence. R6-1 and R6-3 match the card's fix text. R6-2 takes a different but adequate approach (glob extension instead of `mktemp -d`). R6-4 closes the optimizer concern but violates the card's explicit constraint on access width, leaving the `unaligned-cross-page` store probe no longer testing a straddling store. One follow-up item should be opened for R6-4.
