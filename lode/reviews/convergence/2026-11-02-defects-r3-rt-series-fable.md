# Round-3 Remediation Review — `rt-series` `4d36271` vs `e6a22ae`

**Verdict: one regression, one partial, four verified.** The remediation is substantively correct on all six items, but the combination of RTS-R3-3 and RTS-R3-6 breaks the uniform guest build of `tests/p3_torture.c` on every non-LL/SC target. No builds, tests, containers, or QEMU were run. Findings below are from static reading of the diff, `tools/remote_bench_common.sh`, and `tools/build_uniform_guests.sh`.

---

## RTS-R3-1 — Upstream check: target adapter vs host `make check` — **VERIFIED**

`run_weekly_soak` now branches on `CURRENT_ARCH` (`tools/run_grind.sh:803-816`). Only `host` runs unwrapped `make -C "$UPSTREAM_CHECK_DIR" check`. Foreign arches go through `run_upstream_adapter_check` (`tools/run_grind.sh:685-702`), which records `SKIP` unless `UPSTREAM_CHECK_ADAPTER` is a non-empty executable, and passes arch, dir, wrappers, compilers, `GRIND_RT_BIN`, `GRIND_HL_BIN`, and `GRIND_BACKEND` in the environment. With `--arch all` a single host result can no longer be credited ten times.

Residual notes, not blocking:
- The adapter contract hands over `GRIND_INTERP`/`GRIND_DBT` as bare translator prefixes under `BACKEND=hl` (see RTS-R3-2). An adapter that assembles its own `hl` line will repeat the exact bug RTS-R3-2 fixed. The contract comment should tell adapters to source `remote_bench_common.sh` and use `rt_run_bounded_hl`.
- `GRIND_ALLOW_SKIP` defaults to `1` (`tools/run_grind.sh:38`), so a foreign weekly job without an adapter still exits 0 overall. That matches the audit's "report SKIP" wording, but weekly qualification runs should set `GRIND_ALLOW_SKIP=0`.

## RTS-R3-2 — Grind RVRT host-policy selector — **VERIFIED** (with one consequential follow-up)

`resolve_arch_defaults` no longer composes `$_hl_bin $_interp_cmd`; under `hl` it records `GRIND_HL_BIN`/`GRIND_RT_BIN` and leaves the wrappers as plain `rt_format_cmd_prefix` output (`tools/run_grind.sh:218-233`). `grind_run_guest` (`tools/run_grind.sh:166-199`) matches the wrapper against `GRIND_DBT`/`GRIND_INTERP` by string equality and dispatches to `rt_run_bounded_hl`, which emits `--rvrt-native` for `rvrt` (`tools/remote_bench_common.sh:107-117`) and the shared `--env` set. All ten former inline `timeout … $_wrap` call sites (stress-ng, gcc-torture, compiler-rt, libc/LTP, lmbench, differential, TestFloat) now go through it. Timeouts are preserved (`run_bounded` = `timeout --kill-after=30s`). The empty-wrapper semantics when `hl` is missing are unchanged.

**Follow-up (Medium): user-supplied wrapper silently replaced.** If a user sets `GRIND_DBT` (or `GRIND_INTERP`) to a custom translator command that does not contain the `hl` path, e.g. `GRIND_BACKEND=hl GRIND_DBT="/tmp/rvrt-debug --dbt --"`, then `grind_run_guest` sees `"$_gr_wrap" = "$GRIND_DBT"`, sets `_gr_eng=dbt`, and runs the auto-discovered `GRIND_RT_BIN` instead. Results are credited to a binary the user did not select. Fix: only reroute when the wrapper equals the auto-generated `_dbt_cmd`/`_interp_cmd` (store those in `GRIND_AUTO_DBT`/`GRIND_AUTO_INTERP`), or when `USER_GRIND_DBT`/`USER_GRIND_INTERP` is empty.

## RTS-R3-3 — LL/SC reservation isolation and positive control — **PARTIAL**, and it introduces the regression below

Done correctly:
- Separated from the GPR/CAS fixture into `t_llsc_reservation` with its own signal (`SIGURG`) and a counter-only handler (`tests/p3_torture.c:213-224`). `t_sig_frame_gpr` now just raises `SIGUSR1` at step 7.
- Bounded positive control `probe_llsc_no_signal` (32 retries) runs first; an always-fail SC now fails `llsc-control` (`tests/p3_torture.c:321-335`).
- Fail-closed on missed delivery (`g_llsc_probe_seen != 1`).
- Per-arch success decoding is correct: `stxr`/`strex`/`sc.w` status 0 = stored, MIPS/LoongArch rt = 1 stored, PPC `CR0[EQ]` set = stored.

Not done:
- The interval between LL and SC still contains a libc `raise()` (a `tgkill` syscall round-trip), not "architecture-specific assembly around a controlled delivery boundary". The comment at `tests/p3_torture.c:337-338` says "sigreturn must have cleared it", but the probe cannot distinguish sigreturn invalidation from syscall-entry invalidation or libc stores inside `raise`. Either document the validated boundary as "the complete `raise()` → handler → `sigreturn` round trip" or move to an inline `tgkill` syscall stub per arch. Low severity, but the audit asked explicitly for precise documentation of the boundary.

### REGRESSION (High): non-LL/SC guest builds fail under the new `-Werror`

`t_llsc_reservation` only references `llsc_probe_handler`, `llsc_pair`, `probe_llsc_no_signal`, and `probe_llsc_broken_by_signal` inside the `#if` for aarch64/arm/riscv/mips/ppc/loongarch (`tests/p3_torture.c:357-359`). The four helpers are unconditional `static` definitions. Before this commit, `probe_llsc_broken_by_signal` was called unconditionally from `t_sig_frame_gpr`, so they were always used. On `__i386__` and `__sparc__` they are now unreferenced, which `-Wall` reports as `-Wunused-function`. `tools/build_uniform_guests.sh:125` now adds `-Werror` to `COMMON_CFLAGS`, and that script compiles `p3_torture.c` for `i686` (line 203), `sparc32` (207), and `sparc64` (214). Those three guest builds fail. Because the script runs `set -eu`, the `i686` failure also aborts every ABI after it (`mipsel`, `mips`, `ppc32`, `sparc32`, `riscv64`, `riscv32`, `loongarch64`, `ppc64le`, `mips64el`, `mips64eb`, `sparc64`) unless `build_trixie_abi` swallows the error, which I did not see evidence of. The same break applies to anyone compiling `p3_torture.c` on an x86_64 host with the documented build line.

Fix: hoist the arch condition into one macro (`#define P3_HAVE_LLSC 1` under the same `#if`, else `0`) and guard `g_llsc_probe_seen` plus the four helpers with `#if P3_HAVE_LLSC`. Alternatively keep the helpers but call the control from the vacuous branch; the macro guard is cleaner.

Compile not run here, so this is a static conclusion, but the unused-static-function warning under `-Wall` is unambiguous for both gcc and clang.

## RTS-R3-4 — TestFloat dual-engine execution — **VERIFIED**

`run_testfloat_suite` (`tools/run_grind.sh:436-482`) runs the host verifier once for `host`, and for foreign arches runs `run_testfloat_one_engine` separately for `GRIND_INTERP` (`testfloat-interp`) and `GRIND_DBT` (`testfloat-dbt`), with labelled `SKIP` when an engine is missing or `GRIND_DBT` duplicates `GRIND_INTERP`. The same generated vector file feeds both. Both go through `grind_run_guest`, so RTS-R3-2 policy applies. A side improvement: a foreign job with no wrappers previously ran the verifier natively on the host and credited it to the foreign arch; it now skips. Minor: the shared `/tmp/grind_testfloat_$$.log` is overwritten by the second engine and deleted at the end, so the `see …log` hint in a first-engine failure message points at the wrong or missing content. Pre-existing pattern, not a regression.

## RTS-R3-5 — Uniform guest builder signal traps and container verification — **VERIFIED**

`tools/build_uniform_guests.sh:40-110`: INT and TERM handlers disarm traps, clean, verify, and `exit 130`/`143`. The EXIT handler captures `$?` first, then runs owned-container removal and the lingering check, and converts either failure into exit 1 while otherwise preserving the original status. `cleanup_owned_containers` now propagates `docker rm -f` failures. The duplicate end-of-script `cleanup; lingering grep` block is replaced by `cleanup_owned_containers || exit 1; verify_no_lingering_containers || exit 1`, which is redundant with the EXIT trap but harmless. Ownership filtering still uses the `-$$` name suffix. Behaviour now matches the benchmark harness trap fixed in Round 2.

## RTS-R3-6 — General `-Werror` enforcement — **VERIFIED** (scope as audited)

`-Werror` is added to `Makefile:9`, `COMMON_CFLAGS` in `tools/build_uniform_guests.sh:125`, and every first-party `bench_suite.c` recipe in `tools/bench_harness.sh` (clang freestanding, darwin, sparc32 oracle, loongarch64, ppc64le, mips64el, sparc64, and the trixie bulk recipe). The build-line comments in `p3_torture.c` and `smoke_tcg.c` were updated.

Two first-party compiles still lack it, outside the audit's named locations:
- `flake.nix:36-37` syntax checks of `include/a32host.h` and the ABI test use `-Werror=vla` only.
- The compiler-rt builtin probe in `tools/run_grind.sh:523` compiles with `-std=c11 -O1` and no warning flags at all.

Risk note: every `bench_harness.sh` recipe ends in `|| true`, so a new warning under some cross-gcc version now silently yields no binary and a skipped benchmark rather than a visible build failure. Whether `bench_suite.c` and `smoke_tcg.c` are warning-clean on all eleven toolchains is unverified.

## Curated C11 and file-size compliance

| File | Lines |
|---|---|
| `tests/p3_torture.c` | 892 |
| `tests/bench_suite.c` | 602 |
| `tests/tcg/smoke_tcg.c` | 522 |
| `tests/bench_sys.h` | 336 |
| `tests/check_abi_invariants.c` | 333 |
| `include/a32host.h` | 113 |

All C/H files are at or under 900 lines. `p3_torture.c` has 8 lines of headroom; the `P3_HAVE_LLSC` fix above adds roughly 4 to 6 lines, so a split of the LL/SC probe into `tests/p3_llsc.h` or a second translation unit should be planned now. The new code uses no VLAs, Annex K, `<threads.h>`, `_Generic`, banned string functions, or `x18`.

---

## Summary

| Item | Status | Note |
|---|---|---|
| RTS-R3-1 | VERIFIED | Foreign jobs SKIP without `UPSTREAM_CHECK_ADAPTER`; host-only unwrapped `make check`. |
| RTS-R3-2 | VERIFIED | All guest runs route through `rt_run_bounded_hl`; `--rvrt-native` preserved. Follow-up F2 below. |
| RTS-R3-3 | PARTIAL | Isolation and positive control done; boundary still a libc `raise()` and over-documented as sigreturn-only. Introduces F1. |
| RTS-R3-4 | VERIFIED | Separate `testfloat-interp` / `testfloat-dbt` with labelled single-engine skips. |
| RTS-R3-5 | VERIFIED | Terminating INT/TERM, status-preserving EXIT, cleanup failure → nonzero. |
| RTS-R3-6 | VERIFIED | `-Werror` on Makefile, uniform guests, and all bench recipes. Minor gaps in `flake.nix` and the grind builtin probe. |

## Newly Discovered Consequential Follow-Ups

1. **F1 (High, REGRESSION): `p3_torture.c` fails to build on i686, sparc32, sparc64 under `-Werror`.** Four `static` LL/SC helpers become unreferenced on non-LL/SC targets (`tests/p3_torture.c:217-352` vs guard at `357-359`); `-Wunused-function` becomes an error with the new `COMMON_CFLAGS`. With `set -eu`, the i686 failure aborts the remaining uniform guest builds. Guard the helpers and `g_llsc_probe_seen` with a single `P3_HAVE_LLSC` macro.
2. **F2 (Medium): `grind_run_guest` discards user-supplied `GRIND_DBT`/`GRIND_INTERP` under `BACKEND=hl`.** Any user wrapper not containing the `hl` path is replaced by the auto-discovered `GRIND_RT_BIN` (`tools/run_grind.sh:181-191`). Reroute only the auto-generated prefixes.
3. **F3 (Low): adapter contract re-opens RTS-R3-2 for adapters.** Document that `UPSTREAM_CHECK_ADAPTER` on `hl` must use `rt_run_bounded_hl` from `remote_bench_common.sh` rather than compose `hl` lines from `GRIND_HL_BIN` + `GRIND_DBT`.
4. **F4 (Low): LL/SC boundary wording.** Rephrase `tests/p3_torture.c:337-338` and `353-356` to state the validated boundary is the full `raise()` round trip, or replace `raise()` with a per-arch inline `tgkill` stub.
5. **F5 (Low): `p3_torture.c` at 892 lines.** Plan the split before the F1 fix pushes it past 900.
