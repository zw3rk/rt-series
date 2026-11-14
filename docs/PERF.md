# `rt-series` Performance Ledger (`docs/PERF.md`)

Authoritative performance baseline and optimization ledger across all 10 `rt-series` translators (`11` guest architectures + 32-bit iOS `armv7`/`armv7s` Mach-O in `a32rt`). All optimization work follows the mandatory 6-step loop (`Instrument -> Measure -> Hypothesise -> Fix -> Measure -> Validate`).

---

## 1. Converged 11-Architecture Linux ELF DBT Baselines (`Waves P1–P13`, `results-darwin5-full.tsv`)

Measured on `aarch64-darwin-5.lan` (Apple M1, `5` trials `min_us`, `--full` 5-workload `bench_suite.c`):
- **Native `arm64-apple-darwin`**: `3,390 µs`
- **Native `aarch64-unknown-linux-musl` (Lima VZ)**: `3,719 µs`

| Guest Arch | Runtime | `linux` DBT (`µs`) | `darwin` DBT (`µs`) | macOS `qemu-<arch>` (`µs`) | Linux `qemu-<arch>` (`µs`) | Speedup vs. `qemu-<arch>` (macOS / Linux) |
|---|---|---:|---:|---:|---:|---|
| `armhf` | `a32rt` | **`8,024`** | **`10,770`** | `44,581` | `22,066` | **4.14× / 2.75×** |
| `ppc32` | `ppc32rt` | **`15,917`** | **`16,003`** | `72,621` | `67,692` | **4.54× / 4.25×** |
| `riscv64` | `rvrt` | **`24,456`** | **`24,019`** | `67,225` | `30,816` | **2.80× / 1.28×** |
| `riscv32` | `rvrt` | **`25,050`** | **`24,601`** | `67,677` | `26,932` | **2.75× / 1.09×** |
| `mips64el` | `mips64rt` | **`25,224`** | **`23,767`** | `45,672` | `42,720` | **1.92× / 1.80×** |
| `mipsel` | `mips32rt` | **`26,524`** | **`21,984`** | `48,912` | `39,328` | **2.22× / 1.79×** |
| `i686` | `i686rt` | **`28,846`** | **`23,932`** | `76,541` | `32,623` | **3.20× / 1.36×** |
| `ppc64le` | `ppc64rt` | **`30,678`** | **`28,112`** | `83,410` | `67,990` | **2.97× / 2.42×** |
| `loongarch64` | `loongarch64rt` | **`35,065`** | **`33,488`** | `51,204` | `42,824` | **1.53× / 1.28×** |
| `sparc32` | `sparc32rt` | **`40,107`** | **`35,712`** | `75,190` | `68,286` | **2.11× / 1.91×** |
| `sparc64` | `sparc64rt` | **`43,653`** | **`33,015`** | `77,845` | `68,951` | **2.36× / 2.09×** |

---

## 2. Round 19: `a32rt` 32-Bit iOS (`armv7`/`armv7s`) & Thumb-2/NEON DBT Optimization (`8d87576`)

### 2.1 Measured Pre-Optimization Profile (`bench_suite.c`, 5-workload `min_us`)

| Target / Guest Binary | `coremark` (`µs`) | `chacha20` (`µs`) | `vfp_simd` (`µs`) | `calls_ibtc` (`µs`) | `syscalls` (`µs`) | `total_us` (`µs`) |
|---|---:|---:|---:|---:|---:|---:|
| **Darwin DBT — ELF32 `thumb`** | `3,722` | `3,064` | `1,374` | `4,960` | `221` | **`13,341`** |
| **Darwin DBT — iOS `armv7s` (`libSystem`)** | `2,841` | `2,568` | **`49,413`** | `5,079` | **`676`** | **`61,308`** |
| **Darwin DBT — iOS `armv7s` (raw `svc #0x80`)** | `2,841` | `2,568` | **`49,413`** | `5,079` | `292` | **`60,193`** |
| **Linux DBT — ELF32 `thumb`** | `1,837` | `1,828` | `1,168` | `4,267` | `775` | **`9,875`** |
| **Linux DBT — iOS `armv7s` (`libSystem`)** | `1,669` | `1,801` | **`36,813`** | `4,476` | `1,010` | **`46,456`** |

### 2.2 Optimization Checklist (`9 / 9` Resolved in `a32rt` @ `cc3d3aa`)

- [x] **A32-IOS-P1 (`36.0×` `vfp_simd`)** — Coalesce redundant per-instruction NEON `MSR FPCR` writes across basic blocks and hoist into VFP self-loop preheaders (`a32rt/src/interp/decode_priv.h`, `interp_neon_alu.c`, `core_emit_alu.c`, `core_emit_mem.c`, `dbt_jit_query.c`, `trampoline.S`).
- [x] **A32-IOS-P2 (`2.32×` PIC stub calls)** — Handle mode-switching `A32_EXIT_INTERWORK` (`A32 <-> T32` `__picsymbolstub4` transitions) directly inside `a32rt/src/trampoline.S` `.Lrun_loop` without bouncing to C.
- [x] **A32-IOS-P3** — Emit native guest Thumb-2 machine-code stubs in `0xFFFF2800..0xFFFF3FFF` for hot leaf `libSystem` routines (`_strlen`, `_strcmp`, `_strncmp`, `_memcpy`, `_memmove`, `_memset`, `_memcmp`, `___error`, `_pthread_self`, `_mach_absolute_time`) so calls execute in-JIT with zero `SVC` traps.
- [x] **A32-IOS-P4** — Replace 1–4 `MOVZ/MOVK x21` instructions per Regime A2 Soft-TLB access with a 1-instruction `[sp, #160]` load in `trampoline.S`/`core_emit_mem.c`, and add lock-free atomic pre-checks in `dbt_jit_query.c` and `dbt_jit_run.c`.
- [x] **A32-IOS-P5** — Cache per-image export trie and `symtab`/`strtab` blobs on `a32_ios_image_t` across `a32_ios_bind_all` (`ios_export.c`, `ios_dylib.c`).
- [x] **A32-IOS-P6** — Parse Mach-O `LC_FUNCTION_STARTS` (`0x26`) and `__TEXT,__text` bounds in `ios_macho.c` to enable `--aot` / `--auto-aot` pre-translation for 32-bit iOS binaries.
- [x] **A32-IOS-P7** — Avoid full-array `a32_vm32_copyout_invalidate_exec` per element swap in `qsort_resume` (`ios_stubs.c`).
- [x] **A32-IOS-P8** — Validate guest C strings per 4 KiB page via `memchr` in `ios_cstr` (`ios_svc_bsd.c`).
- [x] **A32-IOS-P9** — Cache `ios_thr_slot_plus1` on `a32_ctx_t` for `O(1)` lock-free `pthread_self`/TSD lookup (`ios_threads.c`).

### 2.3 Post-Optimization Re-Measurement (`a32rt` @ `cc3d3aa`, 5-trial `min_us`)

| Target / Guest Binary | `coremark` (`µs`) | `chacha20` (`µs`) | `vfp_simd` (`µs`) | `calls_ibtc` (`µs`) | `syscalls` (`µs`) | `sum(min_us)` / Best Trial (`µs`) | Speedup vs. `8d87576` |
|---|---:|---:|---:|---:|---:|---:|---|
| **Darwin DBT — ELF32 `thumb`** | `3,061` | `3,322` | `1,341` | `5,384` | `250` | **`13,358` / `14,474`** | Parity preserved (`ALL_PASS`) |
| **Darwin DBT — iOS `armv7s` (`libSystem`)** | `3,080` | `2,872` | **`10,249`** | `5,867` | **`355`** | **`22,423` / `23,923`** | **`4.82×` `vfp_simd`**, **`1.90×` `syscalls`** (`89%` PIC stub cut), **`2.56×–2.73×` total** |
| **Darwin DBT — iOS `armv7s` (raw `svc #0x80`)** | `3,170` | `2,694` | **`10,237`** | `6,896` | `314` | **`23,311` / `25,736`** | **`4.83×` `vfp_simd`**, `+41 µs` PIC delta (vs. `+384 µs`) |
| **Linux DBT — ELF32 `thumb`** | `2,074` | `1,784` | `1,418` | `5,680` | `873` | **`11,829` / `12,184`** | Parity preserved (`ALL_PASS`) |
| **Linux DBT — iOS `armv7s` (`libSystem`, Cold JIT)** | `2,315` | `1,523` | **`10,963`** | `5,753` | **`937`** | **`21,491` / `22,146`** | **`3.36×` `vfp_simd`**, **`1.00×` vs. raw `svc`**, **`2.10×–2.16×` total** |
| **Linux DBT — iOS `armv7s` (`libSystem`, Warm AOT)** | `2,217` | `1,655` | **`10,689`** | `5,727` | **`936`** | **`21,224` / `22,013`** | **`3.44×` `vfp_simd`**, **`blocks_compiled=0`**, `icache_flushes=1` |

- **Mixed `.f32`+`.f64` vs. Pure-NEON Self-Loops**: `bench_suite.c`'s `vfp_simd` interleaves `float` (compiled by Clang on `armv7s` to ARMv7 NEON `.f32`, which forces `FZ=1, DN=1, RMode=RN`) and `double` (compiled to scalar VFP `.f64`, using `ctx->fpscr` `FZ=0, DN=0`) 6 times per iteration; coalescing reduced `MSR FPCR` flushes from `44`/iter (`1.76M` total) to the architectural minimum of `12`/iter (`480K` total, `4.82×` faster), while pure-NEON self-loops hoist `MSR FPCR` into the preheader with **zero** `MSR FPCR` instructions in the loop body.
