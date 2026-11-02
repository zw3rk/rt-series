# Wave C2 — Uniform 10-Class Guest Matrix, DBT Bug Closure & Qualify Wiring

**Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.**  
**SPDX-License-Identifier: Apache-2.0**

---

## 1. Objective

Wave C1 established the shared `PARITY_ROW` / `PARITY_SUMMARY` reporting contract (`tools/parity_contract.sh`) and hermetic `tests/golden/` bundles across all 10 `<arch>rt` repositories. However, the audit after Wave C1 identified three remaining gaps:

1. **Heterogeneous Guest Suites Across Repositories**: While `ppc64rt` and `loongarch64rt` run all 8 guest classes (`P1` ISA, `P2` static libc, `P3` FP/SIMD, `P4` threads/signals/fork/wait, `P5` dynamic `PT_INTERP`, `H1` SMC, `H4` C++17, and guest AOT cold-emit/warm-reload), the other 8 repositories omit several classes in `smoke`, or only run a host C unit test for AOT instead of a real guest cold-emit $\to$ warm-reload run, or lack `armel` (`a32rt`) / guest torture rows (`rvrt`).
2. **Known `i686rt` DBT Skips (`3 SKIP`)**: `i686rt/tests/parity_suite.sh` sets `PARITY_ALLOW_SKIP=1` to mask 3 real DBT bugs (`test_h1_smc` DBT SMC rewrite invalidation, and `test_p5_fpu_sse` / `test_p5_fpu_sse-x87-80` DBT SSE `FTZ`/`DAZ` + `cmpps` lane order).
3. **Unwired Shared Torture Sources (`tests/p3_torture.c`, `tests/tcg/smoke_tcg.c`) & `guest-payload` in `qualify`**: `rt-series/tools/run_catalogue.sh qualify` only checks that `tests/p3_torture.c` and `tests/tcg/smoke_tcg.c` exist on disk instead of executing them, and `bench-ppc64le` / `bench-sparc64` are missing from `rt-series/_build/bench/`.

Wave C2 closes all three gaps across 6 parallel `muse` worker lanes (`C2-1` through `C2-6`) so that **every one of the 10 translators (and all 16 ABIs) runs the same 10-category guest verification suite with `0 FAIL, 0 GAP, 0 SKIP`**.

---

## 2. Uniform 10-Category Guest Matrix (Required in Every `<repo>/tests/parity_suite.sh`)

Every `<repo>/tests/parity_suite.sh` must execute and emit `PARITY_ROW` lines (`PASS`, `0 FAIL, 0 GAP, 0 SKIP`, with `PARITY_ALLOW_SKIP=0` by default) for all 10 categories:

1. **`p1_isa`**: Integer, branch, unaligned, and trap/fault ISA torture (`--interp`, `--dbt`, `--difftest`).
2. **`p2_libc`**: Static libc (`hello`, `printf`, `qsort`, `malloc`, `fileio` or combined `p2_libc` guest) (`--interp`, `--dbt`, `--difftest`).
3. **`p3_fp`**: Architecture FP/SIMD torture (`--interp`, `--dbt`, `--difftest`).
4. **`p3_torture`**: Shared portable FP rounding/NaN/denormal/vector torture compiled from `../../rt-series/tests/p3_torture.c` (`--interp`, `--dbt`, `--difftest`).
5. **`tcg_smoke`**: Shared portable ALU/mul/div/bitfield/atomic/unaligned/branch torture compiled from `../../rt-series/tests/tcg/smoke_tcg.c` (`--interp`, `--dbt`, `--difftest`).
6. **`p4_threads`**: Threads (`clone`/futex), signals (`rt_sigframe`), pipes, `fork`/`wait4` (`--interp`, `--dbt`, and `--difftest` where single-thread/supported).
7. **`p5_dyn`**: Dynamic ELF (`PT_INTERP` / `ld.so` + shared `libc.so` + `libp5.so`) using a committed minimal `tests/sysroot/` (or prebuilt self-contained sysroot fixture in `tests/sysroot/`) (`--interp`, `--dbt`).
8. **`h1_smc`**: Self-modifying code + I-cache invalidation (`--interp`, `--dbt`, `--difftest`).
9. **`h4_cxx`**: C++17 exceptions/stack unwinding, `dynamic_cast` RTTI, and `std::thread` (`--interp`, `--dbt`, `--difftest`).
10. **`bench_smoke` + `aot_reload`**:
    - `bench_smoke`: `../../rt-series/_build/bench/bench-<arch> --smoke` (or repo CoreMark CRC) across `--interp`, `--dbt`, `--difftest`.
    - `aot_reload`: Real guest ELF cold-emit (populating AOT cache/file) followed by warm-reload execution, verifying AOT cache file creation/magic and byte-identical guest stdout.

---

## 3. Worker-Lane Ownership & Task Cards

| Lane | Owned Repositories | Scope & Deliverables |
|---|---|---|
| **Lane C2-1** | `rt-series` | Build missing ` _build/bench/bench-{ppc64le,sparc64,loongarch64,mips64el}` binaries; add `tools/build_uniform_guests.sh`; wire `run_host_qualify` in `tools/run_catalogue.sh` to execute `p3_torture`, `smoke_tcg`, and `guest-payload` (Tier 1–4); update `docs/SOFTWARE-CATALOGUE.md`. |
| **Lane C2-2** | `a32rt`, `i686rt` | **Fix `i686rt` DBT bugs** (`test_h1_smc` SMC invalidation + `test_p5_fpu_sse` SSE `FTZ`/`DAZ` & `cmpps` lane order) and remove `PARITY_ALLOW_SKIP=1`. Bring both `a32rt` (`armhf`, `thumb`, **and `armel`**) and `i686rt` (`i686`) up to the full 10-category guest matrix (`p1`, `p2`, `p3`, `p3_torture`, `tcg_smoke`, `p4`, `p5_dyn` with `tests/sysroot`, `h1_smc`, `h4_cxx`, `bench_smoke`, `aot_reload`) with committed goldens (`0 FAIL, 0 GAP, 0 SKIP`). |
| **Lane C2-3** | `mips32rt`, `ppc32rt`, `sparc32rt` | Upgrade all three Class-A 32-bit repos (`mipsel`+`mips` BE, `ppc32` classic+`e500v2` SPE, `sparcv8`) to the full 10-category guest matrix: compile & add `p2_libc`, `p3_torture`, `tcg_smoke`, `p4_threads` (for `ppc32rt`), `p5_dyn` (`tests/sysroot`), `h1_smc`, `h4_cxx`, and **real guest ELF `aot_reload`** (replacing host-only AOT check as the sole AOT row), with committed goldens (`0 FAIL, 0 GAP, 0 SKIP`). Fix any translator bugs uncovered. |
| **Lane C2-4** | `rvrt` | Upgrade `rvrt/tests/parity_suite.sh` (`rv64gc` and `rv32gc`) to the full 10-category guest matrix: add guest parity rows (`--interp`, `--dbt`, `--difftest`) for `p1_isa` (`core-checks`/`rv32`), `p2_libc`, `p3_fp` (`fp-checks`), `p3_torture`, `tcg_smoke`, `p4_threads` (`clone-futex`/`signal-context`/`fork-wait`), `p5_dyn` (`aot-cache-dynamic-main` / `tests/sysroot`), `h1_smc` (`self-modify`), `h4_cxx`, `bench_smoke`, and real guest `aot_reload` (`--cache-dir`), with committed goldens (`0 FAIL, 0 GAP, 0 SKIP`). |
| **Lane C2-5** | `loongarch64rt`, `ppc64rt` | Add `p3_torture`, `tcg_smoke`, and `bench_smoke` (`bench-loongarch64` / `bench-ppc64le`) to both `loongarch64rt` and `ppc64rt` `tests/parity_suite.sh`; add committed minimal `tests/sysroot/` for `loongarch64rt` `p5_dyn` so `p5_dyn` runs in `smoke` on Darwin (matching `ppc64rt`), achieving all 10 categories in `smoke` (`0 FAIL, 0 GAP, 0 SKIP`). |
| **Lane C2-6** | `mips64rt`, `sparc64rt` | **`mips64rt`**: Promote `p4_threads`, `p5_dyn` (with committed `tests/sysroot/`), `h1_smc`, `h4_cxx`, `p3_torture`, `tcg_smoke`, and real guest `aot_reload` into `smoke` on Darwin (`0 FAIL, 0 GAP, 0 SKIP`). **`sparc64rt`**: Fix Darwin `p4` / AOT reload if needed and wire `guest_p2libc`, `p3_torture`, `tcg_smoke`, `guest_h1_smc`, `guest_h4_cxx`, `bench-sparc64`, and real guest `aot_reload` into `sparc64rt/tests/parity_suite.sh` (`0 FAIL, 0 GAP, 0 SKIP`). |

---

## 4. Phase Gate (`RC-C2`)

```sh
timeout --kill-after=30s 600s bash -lc "
  cd /Users/angerman/Projects/zw3rk/rt-series &&
  make check-catalogue &&
  ./tools/run_catalogue.sh smoke &&
  ! grep -E '	(FAIL|GAP|SKIP)	' /tmp/cat-smoke-*.log
"
```
Every one of the 10 repositories must pass `smoke` with `0 FAIL, 0 GAP, 0 SKIP` across the uniform 10-category guest matrix.
