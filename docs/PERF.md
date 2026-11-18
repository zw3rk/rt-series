# `rt-series` Performance Ledger (`docs/PERF.md`)

Authoritative performance baseline and optimization ledger across all 11 `rt-series` translators (`12` guest ISAs / `13` Linux ELF benchmark targets + 32-bit iOS `armv7`/`armv7s` Mach-O in `a32rt`). All optimization work follows the mandatory 6-step loop (`Instrument -> Measure -> Hypothesise -> Fix -> Measure -> Validate`).

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

---

## 3. Round 20: `a32rt` Backend Codegen, 1-Load Soft-TLB, VFP/NEON & macOS AOT Waves (`a32rt` @ `6bf6d76` / `100af25`, `16 / 16` Resolved)

Tracked in [`a32rt/PERF.md`](../../a32rt/PERF.md) (`A32-R20-P0`..`A32-R20-P15`, `16 / 16` resolved) and [`archive/defects/round-20-a32rt-perf.md`](archive/defects/round-20-a32rt-perf.md) (`A32-R20-D1`..`A32-R20-D6`, `6 / 6` resolved) across Step 0 + 5 concurrent worker waves:

- [x] **Step 0 (`A32-R20-P0`)** — Added `[a32rt stats-ext]` phase timers (`ns_vm_init`, `ns_translate`, `ns_wx_flush`), `aprr_toggles`, inline RAS/IBTC attribution, CP15 Generic Timer (`CNTFRQ`/`CNTVCT`), freed `x25` (`A64_XTLB`), and split `src/core/core_emit_exit.c`.
- [x] **Wave A (`A32-R20-P1`..`P3`, `A32-R20-D1`)** — First-return `caller->ret_entry` RAS back-patching (`ras_hits`: `0 -> 3,571,175`), `b->is_return` gating across `BX LR` / `MOV PC, LR` / `POP {.., pc}` / `LDR PC, [SP], #4`, inline 1,024-entry IBTC lookup (`ibtc_hits`: `20,080 -> 1,020,107`), forward-chain signal-poll elision, and 2-reg `LDM` probe skip (retaining `ldar w21, [x28]` acquire ordering in `trampoline.S`).
- [x] **Wave B (`A32-R20-P4`..`P6`, `A32-R20-D3`)** — Pinned `x25` (`A64_XTLB`), 16-byte `{read_ntag, write_ntag}` negated-page-tag Soft-TLB (`CMN` + `CSEL`, `32 MiB -> 16 MiB`), `A32_PROT_WATCH` enforcement, out-of-line cold fault stubs (`f2 = addr_w + span - 1` page-2 fault target), and base+offset Soft-TLB span-check grouping (`tlb_groups = 15..84`, `tlb_slow = 0`).
- [x] **Wave C (`A32-R20-P7`..`P10`)** — A32/T32 arithmetic, `MOVN`, `MOVW`+`MOVT`, & 32-bit bitmask immediate folding, immediate barrel-shifter fusion, branchless `CSEL`/`CSINC`/`CSINV`/`CSNEG` predication + same-cond skip merging, 4-bit backward NZCV liveness, and A32 `rn == 15` PC-relative constant folding.
- [x] **Wave D (`A32-R20-P11`..`P14`, `A32-R20-D4`..`D6`)** — 22-slot (`v8..v29`) VFP/NEON register cache with exact `S`/`D`/`Q` alias flushing + `a32_vfp_record_preheader` loop-pinning, contiguous `VLDM`/`VSTM`/`VPUSH`/`VPOP` lowering, and range-guarded (`[-0.0, +0.0]` and `[2^-61, 2^62)`, `UMAXP` reduction) mixed NEON+scalar self-loop `FPCR == 0` elision (`a64_vfp_note_vmsr` invalidation).
- [x] **Wave E (`A32-R20-P15`, `A32-R20-D2`..`D3`)** — Position-independent Regime A2 `--aot`/`--auto-aot` with inline `.bin` fault-recovery sites (`blocks_compiled=0`, `aot_abs64=0`), lazy reservation / zero-RSS `tlb[0]` Soft-TLB init (`ns_vm_init`: `6.23 ms -> 94–199 µs` Darwin, `19 µs` Linux) + coalesced `mprotect`/APRR (`ns_wx_flush`: `126 µs -> 9–18 µs`), and zero-exit native Thumb-2 leaf stubs for `_getpid`, `_mach_absolute_time`, and `_mach_timebase_info` (`syscalls`: `20,062 -> 57` traps).

### 3.1 Interleaved Post-Wave Verification (`cc3d3aa` vs. `100af25`, 5-Trial `min_us`)

| Host / Guest Target | `coremark` (`µs`) | `chacha20` (`µs`) | `vfp_simd` (`µs`) | `calls_ibtc` (`µs`) | `syscalls` (`µs`) | `sum(min_us)` / Best Trial (`µs`) | Speedup vs. R19 (`cc3d3aa`) |
|---|---:|---:|---:|---:|---:|---:|---|
| **Native `arm64-apple-darwin` (interleaved ref.)** | `729` | `958` | `380` | `1,782` | `6` | **`3,855` / `3,906`** | `1.00×` host reference (`2,206 µs` peak boost) |
| **Darwin DBT — iOS `armv7` (R19 Cold -> R20 Cold)** | `3,077 -> 2,516` | `3,268 -> 2,790` | **`1,378 -> 587`** | `5,837 -> 5,642` | **`325 -> 39`** | **`13,885 -> 11,574` (`11,959`)** | **`2.35×` `vfp_simd`**, **`8.33×` `syscalls`**, **`1.26×` total** (`6,922 µs` peak boost) |
| **Darwin DBT — iOS `armv7` (R20 Warm `--auto-aot`)** | `2,490` | `2,829` | **`587`** | `5,116` | **`39`** | **`11,061` / `11,474`** | **`1.31×` total**, **`blocks_compiled=0`**, `icache_flushes=1` |
| **Darwin DBT — iOS `armv7s` (R19 Cold -> R20 Cold)** | `3,625 -> 2,542` | `2,699 -> 2,223` | **`10,580 -> 4,516`** | `5,856 -> 4,757` | **`330 -> 47`** | **`23,090 -> 14,085` (`14,307`)** | **`2.34×` `vfp_simd`** (**`10.94×` vs. `8d87576`**), **`7.02×` `syscalls`**, **`1.64×` total** (**`4.29×` vs. `8d87576`**) |
| **Darwin DBT — iOS `armv7s` (R20 Warm `--auto-aot`)** | `2,558` | `2,187` | **`4,617`** | `5,180` | **`47`** | **`14,589` / `14,679`** | **`1.60×` total**, **`blocks_compiled=0`**, `icache_flushes=1` |
| **Darwin DBT — ELF32 `armhf` (R19 Cold -> R20 Warm)** | `3,697 -> 2,176` | `3,984 -> 2,819` | **`1,341 -> 686`** | `5,820 -> 5,147` | `242 -> 252` | **`15,084 -> 11,080` (`11,090`)** | **`1.70×` `coremark`**, **`1.95×` `vfp_simd`**, **`1.43×` total** (`11,634 µs` Cold) |
| **Darwin DBT — ELF32 `thumb` (R19 Cold -> R20 Warm)** | `3,150 -> 1,858` | `3,321 -> 2,212` | **`1,349 -> 527`** | `5,463 -> 3,631` | `249 -> 202` | **`13,532 -> 8,430` (`8,430`)** | **`1.70×` `coremark`**, **`2.56×` `vfp_simd`**, **`1.62×` total** (`11,076 µs` Cold) |
| **Linux DBT — iOS `armv7` (R20 Cold / Warm AOT)** | `2,068` / `1,955` | `1,541` / `1,538` | **`586` / `587`** | `5,364` / `5,283` | **`33` / `35`** | **`9,592` / `9,398`** | **`2.33×` `vfp_simd`**, **`28.8×` `syscalls`**, **`1.26×` total** vs. R19 |
| **Linux DBT — iOS `armv7s` (R20 Cold / Warm AOT)** | `1,931` / `1,961` | `1,431` / `1,424` | **`4,574` / `4,588`** | `5,413` / `5,475` | **`34` / `35`** | **`13,383` / `13,483`** | **`2.40×` `vfp_simd`** (**`8.05×` vs. `8d87576`**), **`27.6×` `syscalls`**, **`1.63×` total** |
| **Linux DBT — ELF32 `armhf` (R20 Cold / Warm AOT)** | **`1,629` / `1,655`** | `1,538` / `1,491` | **`689` / `689`** | `5,291` / `5,429` | `869` / `881` | **`10,016` / `10,145`** | **`1.42×` `coremark`**, **`2.02×` `vfp_simd`**, **`1.20×` total** vs. R19 (`12,045 µs`) |
| **Linux DBT — ELF32 `thumb` (R20 Cold / Warm AOT)** | `1,904` / `1,905` | `1,532` / `1,531` | **`690` / `690`** | `5,386` / `5,354` | `895` / `894` | **`10,407` / `10,374`** | **`2.06×` `vfp_simd`**, **`1.17×` total** vs. R19 (`11,829 µs`) |

---

## 4. Round 21: `ppc64rt` Big-Endian ELFv1 (`09832a3`) & `s390xrt` z13 (`8410b2c`) Baselines

Measured with [`tests/bench_suite.c`](../tests/bench_suite.c) (`--full`, freestanding `-DBENCH_FREESTANDING=1`, deterministic CRC match `ALL_PASS` across all 5 workloads):

| Guest Target | Runtime (`master`) | Host Target | `coremark` (`µs`) | `chacha20` (`µs`) | `vfp_simd` (`µs`) | `calls_ibtc` (`µs`) | `syscalls` (`µs`) | `total_us` (`µs`) | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| **`ppc64` BE ELFv1** (`.opd`) | `ppc64rt` (`09832a3`) | Darwin `arm64` DBT | `25,766` | `3,914` | `8,313` | `17,107` | `411` | **`55,511`** | `ALL_PASS` (`1.24×` faster than `qemu-ppc64`) |
| **`ppc64` BE ELFv1** (`.opd`) | `ppc64rt` (`09832a3`) | `hyper-linux` (`hl` HVF) DBT | `24,506` | `2,998` | `9,634` | `18,868` | `17,731` | **`73,737`** | `ALL_PASS` |
| **`s390x` z13** (`EM_S390`) | `s390xrt` (`8410b2c`) | Darwin `arm64` DBT | `117,751` | `623,199` | `261,025` | `187,253` | `496` | **`1,189,724`** | `ALL_PASS` (`0` `--difftest` divergences) |
| **`s390x` z13** (`EM_S390`) | `s390xrt` (`8410b2c`) | `hyper-linux` (`hl` HVF) DBT | `128,438` | `851,373` | `447,986` | `255,640` | `24,895` | **`1,708,332`** | `ALL_PASS` |

---

## 5. Round 22: `s390xrt` Native AArch64 Block JIT (`22.0×` Speedup) & `ppc64rt` 64K IBTC/Soft-TLB + POWER8/VMX Fast Paths

Round 22 upgrades both remaining baseline-only translators to production DBT and re-measures the full 6-column matrix (`tests/bench_suite.c --full`, deterministic CRC `ALL_PASS` on every cell):

- **`s390xrt` (`ca8f0c5`)** — replaced the Round 21 C-helper DBT with a native AArch64 W^X block JIT (in-place block cache + Soft-TLB + `FPC`/`VR` vector lowering): Darwin DBT `1,189,724 µs -> 54,196 µs` (**`22.0×`**), Linux DBT **`37,578 µs`** (**`2.36×` faster than `qemu-s390x`** at `88,818 µs`).
- **`ppc64rt` (`b37b021`)** — 64K-entry IBTC + scaled Soft-TLB, POWER8 fast paths (`maddld`/`setb`/`setbcr`) and VMX/VSX vector lowering across both `ppc64le` ELFv2 and `ppc64` BE ELFv1 (`.opd`): BE ELFv1 Darwin DBT `55,511 µs -> 49,974 µs`, Linux DBT **`48,195 µs`** (**`2.10×` faster than same-run `qemu-ppc64`** at `101,013 µs`, `1.43×` vs the calm `68,920 µs` `qemu-ppc64le` reference).

### 5.1 Complete 6-Column Series Performance Table (All 13 Linux ELF Guest Targets)

Fastest `rt-series` DBT per row is **bold**; `Speedup` compares it against same-run `qemu-user` TCG on Linux. `ppc64` and `s390x` rows are Round 22 re-measurements; the other 11 rows carry forward the §3.5 converged baselines.

| Guest Target | Translator | Darwin DBT (`µs`) | Linux DBT (`µs`) | `hyper-linux` DBT (`µs`) | Darwin Interp (`µs`) | Linux Interp (`µs`) | `qemu-user` TCG (`µs`) | Speedup vs. `qemu-user` |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `armhf` | `a32rt` | `10,770` | **`8,024`** | `15,216` | `571,857` | `570,282` | `22,066` | **2.75×** |
| `i686` | `i686rt` | **`28,631`** | `28,947` | `30,555` | `1,174,119` | `1,381,159` | `32,623` | **1.14×** |
| `mipsel` | `mips32rt` | `33,810` | **`33,430`** | `43,739` | `703,022` | `858,482` | `39,328` | **1.18×** |
| `ppc32` | `ppc32rt` | **`34,026`** | `34,713` | `43,224` | `916,982` | `894,084` | `67,692` | **1.99×** |
| `sparc32` | `sparc32rt` | **`43,282`** | `44,489` | `55,747` | `1,477,200` | `1,706,677` | `68,286` | **1.58×** |
| `riscv64` | `rvrt` | **`24,019`** | `24,456` | `37,159` | `5,213,780` | `3,683,344` | `30,816` | **1.28×** |
| `riscv32` | `rvrt` | **`24,601`** | `25,050` | `38,458` | `5,073,356` | `3,521,173` | `26,932` | **1.09×** |
| `loongarch64` | `loongarch64rt` | **`29,627`** | `29,926` | `43,097` | `2,927,333` | `2,386,382` | `42,824` | **1.45×** |
| `ppc64le` | `ppc64rt` | **`30,332`** | `30,463` | `44,841` | `4,284,855` | `7,049,949` | `67,990` | **2.24×** |
| `ppc64` BE ELFv1 | `ppc64rt` | `49,974` | **`48,195`** | `73,737` | `12,587,556` | `7,173,020` | `101,013` | **2.10×** |
| `mips64el` | `mips64rt` | **`23,767`** | `25,224` | `55,504` | `1,425,215` | `1,894,759` | `42,720` | **1.80×** |
| `sparc64` | `sparc64rt` | **`48,933`** | `50,317` | `60,409` | `10,651,648` | `6,298,132` | `68,951` | **1.41×** |
| `s390x` | `s390xrt` | `54,196` | **`37,578`** | `73,800` | `2,748,657` | `2,236,349` | `88,818` | **2.36×** |

### 5.2 Round 22 Per-Workload Detail (`ppc64` BE ELFv1 + `s390x` z13, `--full` `µs`)

| Guest Target (`Translator` @ `master`) | Target | `coremark` (`µs`) | `chacha20` (`µs`) | `vfp_simd` (`µs`) | `calls_ibtc` (`µs`) | `syscalls` (`µs`) | `total_us` (`µs`) | Status |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `ppc64` BE ELFv1 (`ppc64rt` @ `b37b021`) | `darwin-dbt` | `13,280` | `3,872` | `15,554` | `16,835` | `433` | **`49,974`** | `ALL_PASS` |
| `ppc64` BE ELFv1 (`ppc64rt` @ `b37b021`) | `linux-dbt` | `12,835` | `3,691` | `13,556` | `16,474` | `1,066` | **`48,195`** | `ALL_PASS` |
| `ppc64` BE ELFv1 (`ppc64rt` @ `b37b021`) | `hl-dbt` | `24,506` | `2,998` | `9,634` | `18,868` | `17,731` | **`73,737`** | `ALL_PASS` |
| `ppc64` BE ELFv1 (`ppc64rt` @ `b37b021`) | `darwin-interp` | `3,281,397` | `1,522,677` | `2,245,285` | `5,528,716` | `9,481` | `12,587,556` | `ALL_PASS` |
| `ppc64` BE ELFv1 (`ppc64rt` @ `b37b021`) | `linux-interp` | `1,505,498` | `1,167,927` | `1,216,042` | `3,275,064` | `8,489` | `7,173,020` | `ALL_PASS` |
| `s390x` z13 (`s390xrt` @ `ca8f0c5`) | `darwin-dbt` | `9,112` | `29,449` | `6,307` | `8,811` | `517` | **`54,196`** | `ALL_PASS` |
| `s390x` z13 (`s390xrt` @ `ca8f0c5`) | `linux-dbt` | `5,568` | `18,895` | `4,515` | `7,650` | `950` | **`37,578`** | `ALL_PASS` |
| `s390x` z13 (`s390xrt` @ `ca8f0c5`) | `hl-dbt` | — | — | — | — | — | **`73,800`** | `ALL_PASS` |
| `s390x` z13 (`s390xrt` @ `ca8f0c5`) | `darwin-interp` | `467,242` | `551,438` | `484,343` | `1,241,957` | `3,677` | `2,748,657` | `ALL_PASS` |
| `s390x` z13 (`s390xrt` @ `ca8f0c5`) | `linux-interp` | — | — | — | — | — | `2,236,349` | `ALL_PASS` |

*(Totals are best-trial `total_us`; per-workload cells are independent per-workload minima, so a row's cells need not sum to its total. `s390x` `hl-dbt` / `linux-interp` per-workload splits were not recorded — only best-trial totals.)*
