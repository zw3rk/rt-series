# `rt-series` Software Qualification Catalogue & Unified Benchmark Harness

This document defines the **Real-World Software Qualification Catalogue (`T1`–`T5`)** and the **Unified 4-Target Benchmark Harness** across all 10 `<arch>rt` repositories (11 guest architectures, 16 ABI variants).

It strictly separates **setup & deterministic smoke testing** (`make bench-build`, `make bench-smoke`, `make catalogue-smoke` — runnable on any host or CI in seconds) from **timed performance measurement** (`make bench-run` — gated on a calm host).

---

## 1. Architecture × Libc, Toolchain & Sysroot Matrix (10 Translators, 16 Guest ABIs)

Every translator is qualified against both static ELF binaries and dynamically linked (`ET_DYN` / `PT_INTERP`) userlands across `musl` and `glibc`:

| Translator | Guest Architecture & ABIs | `musl` Sysroot & Version | `glibc` Sysroot & Version | `PT_INTERP` Dynamic Linker Path(s) | Reference `binutils` / `gcc` |
|---|---|---|---|---|---|
| **[`a32rt`](../../a32rt)** | `EM_ARM` (`armhf` A32 & Thumb-2, EABIv5 HF) | Alpine v3.21 `armv7` (`musl 1.2.5`) | Debian 12/13 `armhf` (`glibc 2.36` / `2.40`) | `/lib/ld-musl-armhf.so.1`<br>`/lib/ld-linux-armhf.so.3` | `binutils 2.42+`, `gcc 14.2.0` (`arm-linux-musleabihf` / `arm-linux-gnueabihf`) |
| **[`i686rt`](../../i686rt)** | `EM_386` (`i686` System V x86-32) | Alpine v3.21 `x86` (`musl 1.2.5`) | Debian 12/13 `i386` (`glibc 2.36` / `2.40`) | `/lib/ld-musl-i386.so.1`<br>`/lib/ld-linux.so.2` | `binutils 2.42+`, `gcc 13.2` / `14.2` (`i686-linux-musl` / `i686-linux-gnu`) |
| **[`mips32rt`](../../mips32rt)** | `EM_MIPS` O32 Little-Endian (`mipsel`) & Big-Endian (`mips`) | `musl.cc` / Alpine `mipsel` & `mips` (`musl 1.2.5`) | Debian 12 `mipsel` / Ports `mips` (`glibc 2.36` / `2.40`) | `/lib/ld-musl-mipsel.so.1`, `/lib/ld-musl-mips.so.1`<br>`/lib/ld.so.1` | `binutils 2.40+`, `gcc 12.2` / `14.2` (`mipsel-linux-gnu` / `mips-linux-gnu`) |
| **[`ppc32rt`](../../ppc32rt)** | `EM_PPC` Classic 32-bit BE (`750`/`7400`) & NXP `e500v2` SPE | Alpine / `musl` `powerpc` & `powerpc-muslspe` (`musl 1.2.5`) | Debian Ports `powerpc` (`glibc 2.40`) | `/lib/ld-musl-powerpc.so.1`, `/lib/ld-musl-powerpcspe.so.1`<br>`/lib/ld.so.1` | `binutils 2.43+`, `gcc 14.2.0` (`powerpc-linux-gnu` / `powerpc-linux-muslspe`) |
| **[`sparc32rt`](../../sparc32rt)** | `EM_SPARC` SPARC V8 32-bit BE (`LEON3/4`) | *(upstream `musl` has no SPARC port)* | Debian Ports `sparc` / `sparc64 -m32` (`glibc 2.36` / `2.40`) | `/lib/ld-linux.so.2` | `binutils 2.40+`, `gcc 12.2` / `14.2` (`sparc-linux-gnu` / `sparc64-linux-gnu -m32`) |
| **[`rvrt`](../../rvrt)** | `EM_RISCV` `RV64GC` (`lp64d`) & `RV32GC` (`ilp32d`) | Alpine v3.21 `riscv64` & Nix `riscv32` (`musl 1.2.5`) | Debian 13 `riscv64` & Nix `riscv32` (`glibc 2.40`) | `/lib/ld-musl-riscv64.so.1`, `/lib/ld-musl-riscv32.so.1`<br>`/lib/ld-linux-riscv64-lp64d.so.1`, `/lib/ld-linux-riscv32-ilp32d.so.1` | `binutils 2.43+`, `gcc 14.2.0` (`riscv64-linux-*`, `riscv32-linux-*`) |
| **[`loongarch64rt`](../../loongarch64rt)** | `EM_LOONGARCH` `LA64` `LP64D` (`LSX` + `LASX`) | Alpine / `musl` `loongarch64` (`musl 1.2.5`) | Debian 13 `loong64` (`glibc 2.40`) | `/lib/ld-musl-loongarch64.so.1`<br>`/lib64/ld-linux-loongarch-lp64d.so.1` | `binutils 2.43+`, `gcc 14.2.0` (`loongarch64-linux-gnu`) |
| **[`ppc64rt`](../../ppc64rt)** | `EM_PPC64` `ppc64le` **ELFv2** (`VMX` + `VSX`) | Alpine v3.21 `ppc64le` (`musl 1.2.5`) | Debian 12/13 `ppc64el` (`glibc 2.36` / `2.40`) | `/lib/ld-musl-powerpc64le.so.1`<br>`/lib64/ld64.so.2` | `binutils 2.42+`, `gcc 14.2.0` (`powerpc64le-linux-gnu`) |
| **[`mips64rt`](../../mips64rt)** | `EM_MIPS` **N64** (`5000+n`) & **N32** (`6000+n`), `LE` & `BE` | `musl` `mips64el` / `mips64` (`N64` & `N32`, `musl 1.2.5`) | Debian 12/13 `mips64el` / Ports `mips64` (`glibc 2.36` / `2.40`) | `/lib/ld-musl-mips64el.so.1`, `/lib/ld-musl-mips64.so.1`<br>`/lib64/ld.so.1` (N64), `/lib32/ld.so.1` (N32) | `binutils 2.42+`, `gcc 14.2.0` (`mips64el-linux-gnuabi64` / `-gnuabin32`) |
| **[`sparc64rt`](../../sparc64rt)** | `EM_SPARCV9` SPARC V9 64-bit BE (stack bias `2047`) | *(upstream `musl` has no SPARC64 port)* | Debian Ports `sparc64` (`glibc 2.40`) | `/lib64/ld-linux.so.2` | `binutils 2.43+`, `gcc 14.2.0` (`sparc64-linux-gnu`) |

---

## 2. Five-Tier Real-World Software Qualification Catalogue (`T1`–`T5`)

To ensure every translator exercises deep real-world control flow, dynamic relocation, file/pipe/socket semantics, floating-point/SIMD, self-modifying JITs, and multi-process compiler pipelines, the qualification catalogue is organized into five tiers (driven by [`tools/run_catalogue.sh`](../tools/run_catalogue.sh)):

### Tier 1 (`T1`): Shells, POSIX Userland & Stream Pipelines
Exercises `fork`, `vfork`, `execve`, `#!` script interpretation, `pipe2`, `dup2`, `wait4`/`waitid`, `getdents64`, `/proc/self/*`, and regex/locale engines:
- **`busybox` (`1.37.0`)**: `ash` shell arithmetic/subshells, `awk`, `sed`, `sort | uniq -c`, `tar`, `gzip`, `sha256sum`.
- **`dash` (`0.5.12`) & `bash` (`5.2`)**: Job control, pipelines, command substitution, arrays, and trap handlers.
- **GNU / uutils `coreutils`, `grep` (`3.11`), `sed` (`4.9`), `gawk` (`5.3`), `findutils` (`4.10`), `diffutils` (`3.10`), `tree`**: Floating-point `gawk` associative aggregation, recursive `find` directory traversal (`getdents64` + `fstatat64`/`statx`), unified `diff -u` exit-status and patch verification.

### Tier 2 (`T2`): Compression, Cryptography & Embedded Databases
Exercises unaligned loads/stores, vector/SIMD loops (`NEON`, `SSE2`, `VSX`, `LSX`/`LASX`, `VIS`), 64-bit integer arithmetic, `mmap`/`mremap`, and `fcntl` file locking:
- **`zlib` (`1.3.1`), `xz` (`5.6`), `zstd` (`1.5.6`), `bzip2` (`1.0.8`)**: Compress + decompress round-trip with `cmp -s` bit-exact verification.
- **`openssl` (`3.3`/`3.4`)**: `aes-256-cbc -pbkdf2 -iter 1000` encryption/decryption round-trip, `dgst -sha256`, and `pkeyutl` signature verification.
- **`jq` (`1.7.1`)**: Recursive JSON parsing, filter predicates, and array/string formatting.
- **`sqlite3` (`3.46+`)**: On-disk B-tree table creation, IEEE-754 `REAL` window functions (`AVG(score) OVER ()`), `ORDER BY`, transactions, and `PRAGMA integrity_check`.

### Tier 3 (`T3`): Scripting VMs, Language Runtimes & Nested Guest JITs
Exercises IEEE-754 NaN-boxing (`rvrt`, `mips`, `loongarch64`), custom allocators (`mmap` with `MAP_ANONYMOUS` / `mprotect`), `sigaltstack`, and **guest-side dynamic code generation (JIT-inside-DBT)**:
- **`lua5.4` (`5.4.7`)**: Coroutines (`coroutine.create`/`resume`/`yield`), closures, and incremental garbage collection.
- **`luajit` (`2.1`)** *(on architectures with a LuaJIT backend: `arm32`, `i686`, `mips32`, `ppc32`, `mips64`)*: Asserts `jit.status() == true` so LuaJIT emits native guest machine code into RW mappings and executes it — directly stressing `rt-series` W^X write-gate traps, `cacheflush`/`synci`/`icbi`, and Soft-TLB `PAGE_HAS_CODE` invalidation.
- **`python3` (`3.12+`)**: Full CPython runtime importing dynamic `.so` C extensions (`hashlib`, `json`, `math`, `re`, `zlib`, `threading`), verifying SHA-256 + zlib + floating-point serialization.

### Tier 4 (`T4`): Binary Toolchains, Compilers & Self-Hosted Builds ("The Compiler Torture Gate")
The most demanding user-mode workload: running a multi-process compiler driver (`gcc`/`g++` -> `cc1`/`cc1plus` -> `as` -> `collect2` -> `ld.bfd`), binary inspection tools, and version control **entirely inside the guest translator**:
- **`binutils` (`2.42` / `2.44`)**: `as`, `ld.bfd`, `ar`, `ranlib`, `nm -D`, `objdump -d`, `readelf -hS`, `strip`.
- **Self-Hosted `gcc` & `g++` (`12.2` / `14.2`)**:
  1. Compiles `selfhost.c` (`-O2 -lm`) inside the guest translator into a native guest ELF binary, inspects it with `readelf -h` and `nm -D`, strips it with `strip`, and executes the resulting guest binary (`GCC_SELFHOST_OK:6765:1.414`).
  2. Compiles `selfhost_cxx.cc` (`-O2 -std=c++17 -pthread`) inside the guest translator and executes it to verify zero-cost exception unwinding (`.eh_frame` / `.ARM.exidx`), cross-DSO `dynamic_cast` RTTI, STL containers, and `std::thread`.
- **`make` (`4.4.1`) & `git` (`2.47`)**: Multi-process `make -j2` jobserver build + `git init`, `git add`, `git commit`, `git log`, `git diff`, and `git gc` packfile delta compression.

### Tier 5 (`T5`): Concurrency, Signal, COW & Unwind Torture Suite
- **`libc-test` (`H2`)**: `functional/*`, `math/*`, `regression/*`, `pthread/*` (cancellation, robust mutexes, `pthread_once`, condvars).
- **LTP Syscall Conformance Subset (`H2`)**: `mmap`/`mprotect`/`mremap`, `fork`/`vfork`/`clone`/`wait4`/`waitid`, `futex`, `rt_sigaction`/`rt_sigprocmask`/`sigaltstack`, `epoll`, `socketpair` + `SCM_RIGHTS`, `statx`, `getdents64`, `EFAULT` negative bounds.
- **Wave U Torture (`P6` / `RC-U`)**: Multi-thread 6-step `tgkill`/`SIGUSR2` Soft-TLB shootdown, `Provider A` / `Provider B` in-place non-relocating `MAP_PRIVATE` COW across `fork()` + `futex`, and `MAP_SHARED` `ftruncate` EOF tracking.

### 2.6 Verified Qualification Summary across All 10 Translators (`tools/run_catalogue.sh`)

All 10 `<arch>rt` repositories pass their `tools/run_catalogue.sh smoke` gate (`10/10 PASS`, `0 FAIL`, `0 GAP`) with cross-engine `--interp` / `--dbt` / `--difftest` (`0 divergences`) parity against upstream QEMU user-mode oracles, dynamic linker (`PT_INTERP`) verification, and multi-tier userland payloads:

| Translator | `run_catalogue.sh smoke` Gate | Verified Userland, Sysroot & Torture Coverage |
|---|---|---|
| **[`a32rt`](../../a32rt)** | **`PASS`** (`parity_suite.sh`, `11/11` checks) | Full `T1`–`T5`: `M1`–`M6` + `H1` SMC (`WXORX_TRAP_OK`) + `H3` CoreMark + `H4` C++17 `.ARM.exidx` unwind; **15/15 `T1`–`T4` `guest-payload` checks `PASS`** inside Alpine `armhf` rootfs under `hl` (`busybox`, `bash`, `gawk`, `grep`, `find`, `diff`, `gzip`, `xz`, `zstd`, `bzip2`, `openssl`, `jq`, `sqlite3`, `lua5.4`, **`luajit 2.1` nested guest JIT**, `python3`, `binutils`, **self-hosted `gcc` & `g++` C++17**, `make -j2`, `git`); dynamic `busybox` under `a32rt-darwin --sysroot`. |
| **[`i686rt`](../../i686rt)** | **`PASS`** (`parity_suite.sh`, `11/11` checks) | `P1`–`P6` + `H1` SMC (`mprotect` + write-gate) + `H2` `libc-test`/LTP + `H3` CoreMark + `H4` C++17 DWARF `.eh_frame` unwind + dynamic `PT_INTERP` (`ld-musl-i386.so.1` / `ld-linux.so.2`) + `BusyBox` pipeline parity (`--interp`, `--dbt`, `--difftest 0 divergences`). |
| **[`mips32rt`](../../mips32rt)** | **`PASS`** (`make check`, `69/69` checks) | Dual-endian `mipsel` + `mips` (BE) O32: ISA/delay-slot/FPU (`FR=0`/`FR=1`), `clone`/NPTL TLS (`rdhwr $29`), signals, dynamic `ld-musl-mipsel.so.1` + `dlopen`, `H1` `synci` SMC, `H2` `libc-test`/LTP, `H3` CoreMark, `H4` C++17 unwind (`--interp`, `--dbt`, `--difftest 0 divergences`). |
| **[`ppc32rt`](../../ppc32rt)** | **`PASS`** (`make check`) | Classic 32-bit BE (`750`/`7400` + FPU) and NXP `e500v2` SPE (`ev*`/`efd*`/`efs*` 64-bit accumulator/GPR split): `P1`–`P6` + dynamic `ld.so.1` + `H1` `dcbst`/`icbi` SMC + `H2` `libc-test`/LTP + `H3` CoreMark + `H4` C++17 unwind (`--interp`, `--dbt`, `--difftest 0 divergences`). |
| **[`sparc32rt`](../../sparc32rt)** | **`PASS`** (`make check`) | SPARC V8 BE (`LEON3/4` 8-window register file, `save`/`restore` window spill/fill, `ta 0x10` syscalls, delayed control transfers `DCTI` + annulled branches): `P1`–`P6` + dynamic `glibc` `/lib/ld-linux.so.2` (`sparc32-sysroot`) + `H1` `iflush` SMC + `H2` `libc-test`/LTP + `H3` CoreMark + `H4` C++17 unwind. |
| **[`rvrt`](../../rvrt)** | **`PASS`** (`parity_suite.sh`, `9/9` suites) | Unified `RV64GC` (`lp64d`) + `RV32GC` (`ilp32d`): 73-check host unit & DBT suite + `RV32` ISA/syscall/signal/VM parity (`test_rv32_smoke`, `test_rv32_parity`) + dynamic `rv64-musl` (`ld-musl-riscv64.so.1`), dynamic `rv64-glibc` (`ld-linux-riscv64-lp64d.so.1`), and `BusyBox` userland execution. |
| **[`loongarch64rt`](../../loongarch64rt)** | **`PASS`** (`parity_suite.sh`, `41/41` checks, `0 FAIL`, `0 GAP`) | `LA64` `LP64D` (`LSX` 128-bit + `LASX` 256-bit SIMD): `P1` (`p1_mini`, `test_p1_isa`), `P2` (`hello`, `printf`, `qsort`, `malloc`, `fileio`), `P3` (`test_p3_fp_simd`), `P4` (`test_p4_threads_signals`), `P5` (`test_p5_dyn` dynamic `ld-musl-loongarch64.so.1` + `dlopen` + TLS, `29/29`), `P6` (`test_p6_sched` 6-step `tgkill` quiescence + COW), `P7`/`H3` CoreMark, `H1` (`test_h1_smc` `ibar`), `H4` (`test_h4_cxx17` C++17 unwind). |
| **[`ppc64rt`](../../ppc64rt)** | **`PASS`** (`parity_suite.sh`, `9/9` suites, `0 FAIL`) | `ppc64le` ELFv2 (`r2` TOC, `r12` global entry, `sc` + `scv 0` syscalls, `VMX` + `VSX` + Power10 `maddld`/`setb`/`setbcr`): `p1_isa`, `p2_hello`, `p3_vsx`, `p4_threads`, `p5_dyn` (dynamic `/lib64/ld64.so.2` + `BusyBox`), `h1_smc` (`dcbst`/`icbi`), `h2_libc`, `h3_compute`, `h4_cxx` (`--interp`, `--dbt`, `--difftest 0 divergences`). |
| **[`mips64rt`](../../mips64rt)** | **`PASS`** (`parity_suite.sh`, `8/8` suites, `0 FAIL`, `0 GAP`) | 4-ABI matrix (`N64` `5000+n` & `N32` `6000+n`, `LE` & `BE`): `P1`–`P4` + `P5` dynamic `/lib64/ld.so.1` & `/lib32/ld.so.1` + `BusyBox` (`1.37.0`) oracle parity + `P6` `tgkill`/COW + `H1` `synci` SMC + `H2` `libc-test`/LTP + `H3` CoreMark + `H4` C++17 unwind (`--interp`, `--dbt`, `--difftest 0 divergences`). |
| **[`sparc64rt`](../../sparc64rt)** | **`PASS`** (`parity_suite.sh`, `9/9` suites, `0 FAIL`) | SPARC V9 64-bit BE (stack bias `2047`, `save`/`restore`/`flushw`, `ta 0x6d`, V9 `%ccr`/`%asi`, `VIS`): `p1_isa`, `p2_hello`, `p3_fpu`, `p4_threads`, `p5_dyn` (dynamic `/lib64/ld-linux.so.2` in `sparc64-sysroot` + `BusyBox`), `h1_smc` (`flush`), `h2_libc`, `h3_coremark`, `h4_cxx` (`--interp`, `--dbt`, `--difftest 0 divergences`). |

---

## 3. Unified 4-Target Benchmark Harness (`bench_suite.c` + `tools/bench_harness.sh`)

### 3.1 Five Deterministic Workloads ([`tests/bench_suite.c`](../tests/bench_suite.c))
Compiled from a single Curated C11 source file across all 11 guest architectures (plus `aarch64` and `x86_64` baselines):

| Workload | Full Mode (`--full`, 1 warmup + 4 timed trials) | Smoke Mode (`--smoke`, 1 trial, fast gate) | Expected Full CRC | Expected Smoke CRC | What It Measures |
|---|---|---|---|---|---|
| **`coremark`** | `2,000` iters (4×4 `int32` matmul, 16-node list sort, 8-state tokenizer, CRC-16) | `50` iters | `0x000041dd` | `0x0000edd5` | Integer ALU, pointer chasing, branch prediction, Soft-TLB hit path |
| **`chacha20`** | `8,000` blocks (`512 KiB`) of 20-round ChaCha20 ARX cipher | `200` blocks | `0x065fe64f` | `0x5ff8eba4` | 32-bit rotate/xor/add density, register allocation, loop back-edges |
| **`vfp_simd`** | `40,000` iters of 4×4 FP32 matvec + 4-step FP64 Mandelbrot orbit | `1,000` iters | `0xfffdaf18` | `0xfffff160` | Scalar & vector FPU lowering (`VFP`/`NEON`, `SSE2`, `VSX`, `LASX`, `CP1`, `FPU`) |
| **`calls_ibtc`** | Recursive `fib(28)` (`1,028,457` calls) + `200,000` indirect vtable calls | `fib(18)` + `5,000` vtable calls | `0xed9c5a0a` | `0x5b06486e` | Direct call/return RAS, indirect branch target cache (IBTC), register windows (`sparc32`/`sparc64`) |
| **`syscalls`** | `4,000` `getpid()` syscalls | `100` `getpid()` syscalls | `0x00000fa0` | `0x00000064` | Guest syscall trap (`svc`/`int $0x80`/`ecall`/`syscall`/`sc`/`ta`) + OS backend dispatch latency |

### 3.2 Four Execution Targets & Host Placement Strategy

The harness supports four distinct execution targets via `--target`:

| Target ID | Execution Stack | Binary Used | Where It Runs on `aarch64-darwin-5.lan` |
|---|---|---|---|
| **`darwin`** | **macOS Standalone (`arm64-apple-darwin`)** — Native Mach-O translator (`src/os/backend_darwin.c` + `Provider A` `vm_file.c` + `MAP_JIT` APRR W^X + 7-insn Soft-TLB). **No Hypervisor.framework / VMM required.** | `_build/<arch>rt-darwin*` | Directly in `aarch64-darwin-5.lan` macOS user space (native Darwin process). |
| **`hl`** | **`hyper-linux` (`hl`) on Apple Silicon** — `hl` VMM auto-dispatching `_build/<arch>rt` via `hl_translators[]` with `Provider B` (`src/inode_backing.c` Stage-1 L3 COW + `/dev/a32host` `A32H_ABI 1.1`). | `../hyper-linux-u4/_build/hl` + `_build/<arch>rt` | Directly on `aarch64-darwin-5.lan` macOS host via `Hypervisor.framework` (`kern.hv_support: 1`). |
| **`linux`** | **Linux `aarch64` Standalone** — Static-PIE `aarch64-linux-musl` translator (`src/os/backend_linux.c` + `Provider A` `vm_file.c`) inside an `aarch64-linux` Lima `vz` VM. | `_build/<arch>rt` | Inside the Lima `Virtualization.framework` (`--vm-type=vz`) `aarch64-linux` VM on `aarch64-darwin-5.lan`. |
| **`qemu`** | **Linux `qemu-<arch>` User-Mode TCG Oracle** — Upstream QEMU user-mode TCG inside the same `aarch64-linux` Lima `vz` VM for direct apple-to-apples comparison against `linux`. | `qemu-<arch>-static` | Inside the same Lima `--vm-type=vz` `aarch64-linux` VM on `aarch64-darwin-5.lan`. |

### 3.3 Dedicated Calm Benchmark Host (`aarch64-darwin-5.lan` + Lima `vz`)

- **Why `darwin-{1,3}` previously failed VMM checks**: `aarch64-darwin-{1,3,4,5}.lan` are bare-metal Apple M1 hosts (`kern.hv_support: 1`, macOS 26.6.2 `25G83`). On `darwin-1` and `darwin-3`, the `runner` service runs inside a `com.apple.Virtualization.VirtualMachine` guest, and Apple M1 (unlike M3+) does not support nested virtualization inside a VM.
- **Why `aarch64-darwin-5.lan` works for all 4 targets**: `aarch64-darwin-5.lan` runs directly on bare metal with no active runner VMs (~98% idle CPU, 90 GiB free disk; its ~1.14 `vm.loadavg` is caused by periodic GHC RTS timer wakeups from a niced 2% CPU `cardano-node`).
- Running `darwin` and `hl` directly on `aarch64-darwin-5.lan` macOS and `linux` + `qemu` inside a Lima `--vm-type=vz` VM on `aarch64-darwin-5.lan` ensures all four columns are measured on the exact same calm M1 silicon.

### 3.4 Separating Setup & Smoke-Test from Timed Runs

```sh
# Step 1: Build cross-architecture benchmark ELFs & verify translator binaries (any host load)
make bench-build

# Step 2: Fast deterministic smoke test (--smoke, < 1s per target, verifies CRCs & ALL_PASS)
make bench-smoke                        # Smoke-test all available targets on this machine
tools/bench_harness.sh smoke --target darwin
tools/bench_harness.sh smoke --target linux
tools/bench_harness.sh smoke --target qemu
tools/bench_harness.sh smoke --target hl

# Step 3: Run timed performance campaign ONLY when host is calm (refuses if load > BENCH_MAX_LOAD)
tools/bench_harness.sh run --target darwin   # Safe to run on calm aarch64-darwin-{1,3,4,5}.lan
tools/bench_harness.sh run --target all      # Run full 4-target matrix on calm local Apple Silicon host
```

---

### 3.5 Measured 68-Cell Full Benchmark Results on `aarch64-darwin-5.lan` (`--full`)

All 68 cells across all 4 targets (`darwin`, `hl`, `linux`, `qemu`), both engines (`dbt`, `interp`), and all 11 guest architectures (plus `native-darwin` and `native-linux` baselines) passed with `ALL_PASS` (`100%` CRC match across all 5 workloads) in both `--smoke` ([`_build/bench/results-darwin5-smoke.tsv`](../_build/bench/results-darwin5-smoke.tsv)) and `--full` ([`_build/bench/results-darwin5-full.tsv`](../_build/bench/results-darwin5-full.tsv)) modes on `aarch64-darwin-5.lan` (Apple M1, macOS `26.6.2` `25G83` + Lima `--vm-type=vz` `aarch64-linux` 6.8.0-106).

#### A. Native Host Baselines (`--full`, microseconds `us`, 1 warmup + 4 timed trials)

| Target | Host Arch | Engine | `coremark` (`us`) | `chacha20` (`us`) | `vfp_simd` (`us`) | `calls_ibtc` (`us`) | `syscalls` (`us`) | `total_us` (`us`) | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| `native-darwin` | `arm64-apple-darwin` | `native` (`clang -O2`) | 471 | 799 | 304 | 1,685 | 5 | 3,264 | `ALL_PASS` |
| `native-linux` | `aarch64-linux-musl` | `native` (`gcc -O2`) | 452 | 749 | 320 | 1,686 | 512 | 3,719 | `ALL_PASS` |

*(Note: on Darwin `arm64`, `getpid()` is cached in userspace `libSystem` TLS so `4,000` calls take `5 us`, whereas `musl` on Linux issues `4,000` real `svc #0` syscalls in `512 us` = `128 ns/syscall`.)*

#### B. Cross-Target DBT Comparison (`darwin` DBT × `hl` DBT × `linux` DBT × `qemu` TCG, `--full` `total_us`)

| Translator | Guest Arch | `darwin` DBT (`us`) | `hl` DBT (`us`) | `linux` DBT (`us`) | `darwin` Interp (`us`) | `linux` Interp (`us`) | `qemu` TCG (`us`) | `linux` DBT vs Interp Speedup |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **`a32rt`** | `armhf` | **10,789** | **15,262** | **8,048** | 588,487 | 571,365 | 22,088 | **71.0x** (`2.74x` faster than `qemu-arm`!) |
| **`i686rt`** | `i686` | 244,528 | 304,789 | 297,764 | 1,175,085 | 1,356,876 | 32,097 | **4.56x** |
| **`mips32rt`** | `mipsel` | 2,229,002 | 2,981,074 | 2,572,973 | 718,887 | 875,644 | 39,170 | `0.34x` (`interp` faster on `coremark` exit-per-branch) |
| **`ppc32rt`** | `ppc32` | 234,618 | 341,202 | 265,042 | 917,501 | 882,762 | 58,141 | **3.33x** (`20.7x` on `coremark`, `57.2x` on `chacha20`) |
| **`sparc32rt`** | `sparc32` | 213,414 | 272,782 | 229,206 | 1,485,998 | 1,736,457 | 68,227 | **7.58x** (`65.1x` on `chacha20`) |
| **`rvrt`** | `riscv64` | 429,657 | 334,953 | 293,948 | 5,232,573 | 3,411,619 | 30,695 | **11.61x** (`48.7x` on `coremark`, `190.7x` on `chacha20`) |
| **`rvrt`** | `riscv32` | 443,176 | 336,183 | 294,170 | 5,074,102 | 3,262,063 | 24,365 | **11.09x** (`47.5x` on `coremark`, `176.7x` on `chacha20`) |
| **`loongarch64rt`** | `loongarch64` | 4,449,659 | 3,664,783 | 3,934,807 | 3,381,983 | 3,184,206 | 47,945 | `0.81x` (`1.06x` on `calls_ibtc`) |
| **`ppc64rt`** | `ppc64le` | 5,918,512 | 6,028,788 | 5,995,024 | 4,409,892 | 7,678,629 | 80,309 | **1.28x** (**5.61x** on `coremark`, `2.80x` on `calls_ibtc`) |
| **`mips64rt`** | `mips64el` | 1,397,821 | 3,051,903 | 1,292,464 | 2,317,979 | 2,876,927 | 53,085 | **2.23x** (`4.20x` on `chacha20`, `3.69x` on `calls_ibtc`) |
| **`sparc64rt`** | `sparc64` | 14,163,234 | 7,161,717 | 6,452,166 | 11,877,305 | 6,293,332 | 69,907 | `0.98x` (**250.8x** on `chacha20`, **5.38x** on `calls_ibtc`) |

#### C. Complete 68-Cell Breakdown by Workload (`--full`, microseconds `us`)

| Target | Arch | Engine | `coremark` (`us`) | `chacha20` (`us`) | `vfp_simd` (`us`) | `calls_ibtc` (`us`) | `syscalls` (`us`) | `total_us` (`us`) | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| `native-darwin` | `arm64` | `native` | 471 | 799 | 304 | 1,685 | 5 | 3,264 | `ALL_PASS` |
| `native-linux` | `aarch64` | `native` | 452 | 749 | 320 | 1,686 | 512 | 3,719 | `ALL_PASS` |
| `darwin` | `armhf` | `dbt` | 3,292 | 2,526 | 953 | 3,855 | 163 | 10,789 | `ALL_PASS` |
| `darwin` | `i686` | `dbt` | 31,031 | 164,165 | 18,457 | 30,632 | 243 | 244,528 | `ALL_PASS` |
| `darwin` | `mipsel` | `dbt` | 1,195,961 | 4,077 | 473,289 | 554,710 | 965 | 2,229,002 | `ALL_PASS` |
| `darwin` | `ppc32` | `dbt` | 7,699 | 2,617 | 136,981 | 15,190 | 72,131 | 234,618 | `ALL_PASS` |
| `darwin` | `sparc32` | `dbt` | 63,491 | 8,809 | 93,855 | 47,144 | 115 | 213,414 | `ALL_PASS` |
| `darwin` | `riscv64` | `dbt` | 12,974 | 4,976 | 387,069 | 24,116 | 522 | 429,657 | `ALL_PASS` |
| `darwin` | `riscv32` | `dbt` | 13,484 | 5,333 | 402,078 | 21,762 | 519 | 443,176 | `ALL_PASS` |
| `darwin` | `loongarch64` | `dbt` | 983,356 | 610,240 | 999,109 | 1,853,319 | 3,635 | 4,449,659 | `ALL_PASS` |
| `darwin` | `ppc64le` | `dbt` | 210,691 | 659,827 | 3,141,044 | 1,893,938 | 13,012 | 5,918,512 | `ALL_PASS` |
| `darwin` | `mips64el` | `dbt` | 303,442 | 27,615 | 498,109 | 565,022 | 3,633 | 1,397,821 | `ALL_PASS` |
| `darwin` | `sparc64` | `dbt` | 12,021,037 | 6,703 | 1,681,978 | 453,092 | 424 | 14,163,234 | `ALL_PASS` |
| `darwin` | `armhf` | `interp` | 138,428 | 197,059 | 42,072 | 210,263 | 665 | 588,487 | `ALL_PASS` |
| `darwin` | `i686` | `interp` | 235,580 | 402,350 | 172,424 | 363,695 | 1,036 | 1,175,085 | `ALL_PASS` |
| `darwin` | `mipsel` | `interp` | 128,871 | 140,249 | 121,327 | 327,731 | 709 | 718,887 | `ALL_PASS` |
| `darwin` | `ppc32` | `interp` | 142,421 | 122,383 | 214,333 | 437,674 | 690 | 917,501 | `ALL_PASS` |
| `darwin` | `sparc32` | `interp` | 357,498 | 545,121 | 252,074 | 329,771 | 1,534 | 1,485,998 | `ALL_PASS` |
| `darwin` | `riscv64` | `interp` | 1,038,425 | 1,588,489 | 691,121 | 1,909,469 | 5,069 | 5,232,573 | `ALL_PASS` |
| `darwin` | `riscv32` | `interp` | 1,054,323 | 1,564,044 | 713,504 | 1,737,603 | 4,628 | 5,074,102 | `ALL_PASS` |
| `darwin` | `loongarch64` | `interp` | 716,669 | 217,875 | 752,382 | 1,691,693 | 3,364 | 3,381,983 | `ALL_PASS` |
| `darwin` | `ppc64le` | `interp` | 769,364 | 517,049 | 438,547 | 2,672,459 | 12,473 | 4,409,892 | `ALL_PASS` |
| `darwin` | `mips64el` | `interp` | 502,451 | 234,682 | 305,072 | 1,273,419 | 2,355 | 2,317,979 | `ALL_PASS` |
| `darwin` | `sparc64` | `interp` | 3,065,222 | 3,501,104 | 1,774,510 | 3,524,463 | 12,006 | 11,877,305 | `ALL_PASS` |
| `hl` | `armhf` | `dbt` | 1,580 | 1,069 | 955 | 4,333 | 7,325 | 15,262 | `ALL_PASS` |
| `hl` | `i686` | `dbt` | 40,735 | 197,941 | 29,492 | 36,226 | 395 | 304,789 | `ALL_PASS` |
| `hl` | `mipsel` | `dbt` | 1,755,777 | 4,924 | 590,990 | 620,448 | 8,935 | 2,981,074 | `ALL_PASS` |
| `hl` | `ppc32` | `dbt` | 9,630 | 6,044 | 138,107 | 31,589 | 155,832 | 341,202 | `ALL_PASS` |
| `hl` | `sparc32` | `dbt` | 80,660 | 12,827 | 99,318 | 72,444 | 7,533 | 272,782 | `ALL_PASS` |
| `hl` | `riscv64` | `dbt` | 15,492 | 7,602 | 273,778 | 27,081 | 11,000 | 334,953 | `ALL_PASS` |
| `hl` | `riscv32` | `dbt` | 15,933 | 8,415 | 277,878 | 23,209 | 10,748 | 336,183 | `ALL_PASS` |
| `hl` | `loongarch64` | `dbt` | 905,810 | 603,199 | 590,443 | 1,552,455 | 12,876 | 3,664,783 | `ALL_PASS` |
| `hl` | `ppc64le` | `dbt` | 213,217 | 705,299 | 3,142,728 | 1,941,496 | 26,048 | 6,028,788 | `ALL_PASS` |
| `hl` | `mips64el` | `dbt` | 255,728 | 50,731 | 2,202,779 | 509,639 | 33,026 | 3,051,903 | `ALL_PASS` |
| `hl` | `sparc64` | `dbt` | 5,791,920 | 9,534 | 979,221 | 370,787 | 10,255 | 7,161,717 | `ALL_PASS` |
| `linux` | `armhf` | `dbt` | 1,592 | 1,067 | 951 | 3,801 | 637 | 8,048 | `ALL_PASS` |
| `linux` | `i686` | `dbt` | 37,254 | 199,620 | 23,425 | 37,156 | 309 | 297,764 | `ALL_PASS` |
| `linux` | `mipsel` | `dbt` | 1,363,430 | 3,731 | 591,201 | 612,903 | 1,708 | 2,572,973 | `ALL_PASS` |
| `linux` | `ppc32` | `dbt` | 7,958 | 2,629 | 137,247 | 19,248 | 97,960 | 265,042 | `ALL_PASS` |
| `linux` | `sparc32` | `dbt` | 64,462 | 9,129 | 98,234 | 56,726 | 655 | 229,206 | `ALL_PASS` |
| `linux` | `riscv64` | `dbt` | 13,877 | 4,908 | 248,456 | 25,845 | 862 | 293,948 | `ALL_PASS` |
| `linux` | `riscv32` | `dbt` | 14,135 | 5,200 | 251,774 | 22,195 | 866 | 294,170 | `ALL_PASS` |
| `linux` | `loongarch64` | `dbt` | 1,042,453 | 596,693 | 597,529 | 1,695,034 | 3,098 | 3,934,807 | `ALL_PASS` |
| `linux` | `ppc64le` | `dbt` | 197,938 | 673,113 | 3,219,845 | 1,887,665 | 16,463 | 5,995,024 | `ALL_PASS` |
| `linux` | `mips64el` | `dbt` | 227,377 | 46,864 | 548,749 | 465,132 | 4,342 | 1,292,464 | `ALL_PASS` |
| `linux` | `sparc64` | `dbt` | 5,112,028 | 6,397 | 973,938 | 358,951 | 852 | 6,452,166 | `ALL_PASS` |
| `linux` | `armhf` | `interp` | 126,917 | 193,350 | 37,948 | 212,040 | 1,110 | 571,365 | `ALL_PASS` |
| `linux` | `i686` | `interp` | 274,130 | 442,451 | 196,796 | 442,223 | 1,276 | 1,356,876 | `ALL_PASS` |
| `linux` | `mipsel` | `interp` | 164,999 | 158,101 | 147,563 | 403,598 | 1,383 | 875,644 | `ALL_PASS` |
| `linux` | `ppc32` | `interp` | 164,721 | 150,133 | 221,147 | 345,371 | 1,390 | 882,762 | `ALL_PASS` |
| `linux` | `sparc32` | `interp` | 403,976 | 594,373 | 356,469 | 379,370 | 2,269 | 1,736,457 | `ALL_PASS` |
| `linux` | `riscv64` | `interp` | 675,598 | 935,786 | 446,107 | 1,350,360 | 3,768 | 3,411,619 | `ALL_PASS` |
| `linux` | `riscv32` | `interp` | 671,568 | 919,030 | 454,068 | 1,213,936 | 3,461 | 3,262,063 | `ALL_PASS` |
| `linux` | `loongarch64` | `interp` | 614,791 | 203,808 | 574,472 | 1,788,359 | 2,776 | 3,184,206 | `ALL_PASS` |
| `linux` | `ppc64le` | `interp` | 1,110,435 | 622,946 | 630,274 | 5,291,680 | 23,294 | 7,678,629 | `ALL_PASS` |
| `linux` | `mips64el` | `interp` | 521,166 | 196,786 | 437,692 | 1,717,799 | 3,484 | 2,876,927 | `ALL_PASS` |
| `linux` | `sparc64` | `interp` | 1,721,078 | 1,604,613 | 1,029,174 | 1,931,437 | 7,030 | 6,293,332 | `ALL_PASS` |
| `qemu` | `armhf` | `tcg` | 2,450 | 2,399 | 5,208 | 11,088 | 943 | 22,088 | `ALL_PASS` |
| `qemu` | `i686` | `tcg` | 2,508 | 6,356 | 12,551 | 9,725 | 957 | 32,097 | `ALL_PASS` |
| `qemu` | `mipsel` | `tcg` | 2,336 | 960 | 26,327 | 8,737 | 810 | 39,170 | `ALL_PASS` |
| `qemu` | `ppc32` | `tcg` | 2,285 | 982 | 45,731 | 8,290 | 853 | 58,141 | `ALL_PASS` |
| `qemu` | `sparc32` | `tcg` | 4,538 | 1,321 | 30,694 | 30,854 | 820 | 68,227 | `ALL_PASS` |
| `qemu` | `riscv64` | `tcg` | 1,621 | 1,280 | 14,598 | 12,362 | 834 | 30,695 | `ALL_PASS` |
| `qemu` | `riscv32` | `tcg` | 1,619 | 1,292 | 8,814 | 11,812 | 828 | 24,365 | `ALL_PASS` |
| `qemu` | `loongarch64` | `tcg` | 2,301 | 1,411 | 30,880 | 12,308 | 1,045 | 47,945 | `ALL_PASS` |
| `qemu` | `ppc64le` | `tcg` | 3,111 | 1,178 | 62,787 | 12,296 | 937 | 80,309 | `ALL_PASS` |
| `qemu` | `mips64el` | `tcg` | 5,071 | 1,430 | 31,125 | 14,614 | 845 | 53,085 | `ALL_PASS` |
| `qemu` | `sparc64` | `tcg` | 4,649 | 1,319 | 32,085 | 30,994 | 860 | 69,907 | `ALL_PASS` |
