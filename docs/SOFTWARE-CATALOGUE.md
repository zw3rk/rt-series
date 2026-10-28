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

#### A. Native & Rosetta 2 Host Baselines (`--full`, microseconds `us`, 1 warmup + 4 timed trials)

| Target | Host / Guest Arch | Engine | `coremark` (`us`) | `chacha20` (`us`) | `vfp_simd` (`us`) | `calls_ibtc` (`us`) | `syscalls` (`us`) | `total_us` (`us`) | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| `native-darwin` | `arm64-apple-darwin` | `native` (`clang -O2`) | 471 | 799 | 304 | 1,685 | 5 | 3,264 | `ALL_PASS` |
| `native-linux` | `aarch64-linux-musl` | `native` (`gcc -O2`) | 452 | 749 | 320 | 1,686 | 512 | 3,719 | `ALL_PASS` |
| `rosetta2-darwin` | `x86_64-apple-darwin` | `rosetta2` (Apple Silicon AOT+JIT) | 563 | 1,156 | 498 | 2,180 | 9 | 4,406 | `ALL_PASS` |

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
| `rosetta2-darwin` | `x86_64` | `rosetta2` | 563 | 1,156 | 498 | 2,180 | 9 | 4,406 | `ALL_PASS` |
| `darwin` | `armhf` | `dbt` | 3,291 | 2,523 | 952 | 3,856 | 163 | 10,785 | `ALL_PASS` |
| `darwin` | `i686` | `dbt` | 10,146 | 11,000 | 8,664 | 21,100 | 72 | 50,982 | `ALL_PASS` |
| `darwin` | `mipsel` | `dbt` | 1,157,505 | 3,069 | 274,958 | 312,560 | 1,388 | 1,749,480 | `ALL_PASS` |
| `darwin` | `ppc32` | `dbt` | 6,821 | 2,566 | 42,235 | 14,076 | 165 | 65,863 | `ALL_PASS` |
| `darwin` | `sparc32` | `dbt` | 62,940 | 8,978 | 210,537 | 47,102 | 116 | 329,673 | `ALL_PASS` |
| `darwin` | `riscv64` | `dbt` | 12,448 | 4,898 | 46,652 | 25,343 | 519 | 89,860 | `ALL_PASS` |
| `darwin` | `riscv32` | `dbt` | 13,251 | 5,283 | 46,610 | 21,904 | 519 | 87,567 | `ALL_PASS` |
| `darwin` | `loongarch64` | `dbt` | 15,390 | 3,180 | 52,345 | 24,844 | 647 | 96,406 | `ALL_PASS` |
| `darwin` | `ppc64le` | `dbt` | 41,727 | 23,160 | 357,110 | 401,236 | 6,674 | 829,907 | `ALL_PASS` |
| `darwin` | `mips64el` | `dbt` | 7,409 | 2,689 | 154,349 | 10,527 | 683 | 175,657 | `ALL_PASS` |
| `darwin` | `sparc64` | `dbt` | 13,208 | 5,361 | 41,827 | 435,225 | 348 | 495,969 | `ALL_PASS` |
| `darwin` | `armhf` | `interp` | 138,820 | 198,429 | 42,226 | 211,474 | 665 | 591,614 | `ALL_PASS` |
| `darwin` | `i686` | `interp` | 235,044 | 402,089 | 172,320 | 362,753 | 1,041 | 1,173,247 | `ALL_PASS` |
| `darwin` | `mipsel` | `interp` | 129,045 | 140,147 | 121,289 | 327,624 | 710 | 718,815 | `ALL_PASS` |
| `darwin` | `ppc32` | `interp` | 142,793 | 121,762 | 214,424 | 438,639 | 690 | 918,308 | `ALL_PASS` |
| `darwin` | `sparc32` | `interp` | 358,123 | 546,035 | 254,084 | 330,369 | 1,530 | 1,490,141 | `ALL_PASS` |
| `darwin` | `riscv64` | `interp` | 1,039,994 | 1,591,383 | 699,433 | 1,907,416 | 5,074 | 5,243,300 | `ALL_PASS` |
| `darwin` | `riscv32` | `interp` | 1,053,599 | 1,573,202 | 720,369 | 1,735,448 | 4,581 | 5,087,199 | `ALL_PASS` |
| `darwin` | `loongarch64` | `interp` | 623,563 | 214,316 | 683,752 | 1,205,791 | 3,230 | 2,730,652 | `ALL_PASS` |
| `darwin` | `ppc64le` | `interp` | 741,676 | 492,150 | 427,305 | 2,606,212 | 12,079 | 4,279,422 | `ALL_PASS` |
| `darwin` | `mips64el` | `interp` | 313,462 | 223,321 | 292,125 | 578,898 | 1,691 | 1,409,497 | `ALL_PASS` |
| `darwin` | `sparc64` | `interp` | 3,059,607 | 3,499,362 | 1,764,556 | 3,522,717 | 12,012 | 11,858,254 | `ALL_PASS` |
| `hl` | `armhf` | `dbt` | 1,584 | 1,069 | 955 | 4,339 | 7,333 | 15,280 | `ALL_PASS` |
| `hl` | `i686` | `dbt` | 12,082 | 14,210 | 9,139 | 23,198 | 74 | 58,703 | `ALL_PASS` |
| `hl` | `mipsel` | `dbt` | 1,736,594 | 3,440 | 343,498 | 316,566 | 9,728 | 2,409,826 | `ALL_PASS` |
| `hl` | `ppc32` | `dbt` | 7,464 | 5,187 | 42,133 | 19,692 | 7,647 | 82,123 | `ALL_PASS` |
| `hl` | `sparc32` | `dbt` | 80,789 | 12,922 | 310,981 | 72,742 | 7,696 | 485,130 | `ALL_PASS` |
| `hl` | `riscv64` | `dbt` | 15,639 | 7,596 | 47,161 | 27,869 | 11,124 | 109,389 | `ALL_PASS` |
| `hl` | `riscv32` | `dbt` | 16,058 | 8,439 | 47,319 | 23,416 | 11,189 | 106,421 | `ALL_PASS` |
| `hl` | `loongarch64` | `dbt` | 17,190 | 5,535 | 53,057 | 27,699 | 10,835 | 114,316 | `ALL_PASS` |
| `hl` | `ppc64le` | `dbt` | 39,953 | 21,686 | 313,333 | 356,534 | 19,625 | 751,131 | `ALL_PASS` |
| `hl` | `mips64el` | `dbt` | 9,874 | 6,367 | 178,889 | 13,341 | 30,823 | 239,294 | `ALL_PASS` |
| `hl` | `sparc64` | `dbt` | 14,056 | 8,301 | 41,957 | 339,047 | 10,304 | 413,665 | `ALL_PASS` |
| `linux` | `armhf` | `dbt` | 1,551 | 1,067 | 952 | 3,800 | 658 | 8,028 | `ALL_PASS` |
| `linux` | `i686` | `dbt` | 10,533 | 14,239 | 8,792 | 23,273 | 72 | 56,909 | `ALL_PASS` |
| `linux` | `mipsel` | `dbt` | 1,358,142 | 2,847 | 340,961 | 308,365 | 2,352 | 2,012,667 | `ALL_PASS` |
| `linux` | `ppc32` | `dbt` | 6,878 | 2,568 | 42,415 | 18,179 | 696 | 70,736 | `ALL_PASS` |
| `linux` | `sparc32` | `dbt` | 64,646 | 9,214 | 305,004 | 59,594 | 677 | 439,135 | `ALL_PASS` |
| `linux` | `riscv64` | `dbt` | 13,948 | 4,940 | 46,754 | 25,853 | 946 | 92,441 | `ALL_PASS` |
| `linux` | `riscv32` | `dbt` | 14,221 | 5,203 | 46,895 | 22,082 | 947 | 89,348 | `ALL_PASS` |
| `linux` | `loongarch64` | `dbt` | 16,610 | 3,358 | 52,658 | 26,686 | 1,076 | 100,388 | `ALL_PASS` |
| `linux` | `ppc64le` | `dbt` | 37,665 | 20,672 | 312,974 | 358,026 | 9,785 | 739,122 | `ALL_PASS` |
| `linux` | `mips64el` | `dbt` | 7,145 | 2,685 | 174,496 | 9,836 | 2,184 | 196,346 | `ALL_PASS` |
| `linux` | `sparc64` | `dbt` | 13,167 | 5,434 | 41,887 | 335,211 | 804 | 396,503 | `ALL_PASS` |
| `linux` | `armhf` | `interp` | 126,870 | 192,597 | 37,909 | 211,777 | 1,129 | 570,282 | `ALL_PASS` |
| `linux` | `i686` | `interp` | 278,769 | 454,923 | 200,017 | 446,166 | 1,284 | 1,381,159 | `ALL_PASS` |
| `linux` | `mipsel` | `interp` | 158,834 | 155,169 | 150,692 | 392,400 | 1,387 | 858,482 | `ALL_PASS` |
| `linux` | `ppc32` | `interp` | 165,836 | 150,508 | 227,536 | 348,787 | 1,417 | 894,084 | `ALL_PASS` |
| `linux` | `sparc32` | `interp` | 404,585 | 596,770 | 353,727 | 380,098 | 2,268 | 1,737,448 | `ALL_PASS` |
| `linux` | `riscv64` | `interp` | 723,257 | 1,030,943 | 479,826 | 1,445,247 | 4,071 | 3,683,344 | `ALL_PASS` |
| `linux` | `riscv32` | `interp` | 723,666 | 1,002,903 | 485,718 | 1,305,146 | 3,740 | 3,521,173 | `ALL_PASS` |
| `linux` | `loongarch64` | `interp` | 502,943 | 206,609 | 502,463 | 1,171,732 | 2,635 | 2,386,382 | `ALL_PASS` |
| `linux` | `ppc64le` | `interp` | 991,790 | 538,281 | 569,539 | 4,928,836 | 21,503 | 7,049,949 | `ALL_PASS` |
| `linux` | `mips64el` | `interp` | 362,771 | 237,419 | 486,204 | 804,917 | 3,448 | 1,894,759 | `ALL_PASS` |
| `linux` | `sparc64` | `interp` | 1,721,541 | 1,604,322 | 1,030,304 | 1,934,920 | 7,045 | 6,298,132 | `ALL_PASS` |
| `qemu` | `armhf` | `tcg` | 2,435 | 2,397 | 5,198 | 11,144 | 960 | 22,134 | `ALL_PASS` |
| `qemu` | `i686` | `tcg` | 2,508 | 6,193 | 11,844 | 9,875 | 1,072 | 31,492 | `ALL_PASS` |
| `qemu` | `mipsel` | `tcg` | 2,346 | 957 | 26,500 | 8,992 | 922 | 39,717 | `ALL_PASS` |
| `qemu` | `ppc32` | `tcg` | 2,313 | 982 | 55,382 | 8,281 | 874 | 67,832 | `ALL_PASS` |
| `qemu` | `sparc32` | `tcg` | 4,535 | 1,325 | 30,811 | 30,322 | 896 | 67,889 | `ALL_PASS` |
| `qemu` | `riscv64` | `tcg` | 1,631 | 1,279 | 12,338 | 12,500 | 943 | 28,691 | `ALL_PASS` |
| `qemu` | `riscv32` | `tcg` | 1,621 | 1,292 | 8,813 | 11,805 | 940 | 24,471 | `ALL_PASS` |
| `qemu` | `loongarch64` | `tcg` | 2,160 | 1,455 | 30,863 | 7,936 | 1,124 | 43,538 | `ALL_PASS` |
| `qemu` | `ppc64le` | `tcg` | 3,099 | 1,177 | 62,873 | 12,249 | 1,013 | 80,411 | `ALL_PASS` |
| `qemu` | `mips64el` | `tcg` | 2,554 | 1,448 | 29,421 | 8,159 | 888 | 42,470 | `ALL_PASS` |
| `qemu` | `sparc64` | `tcg` | 4,406 | 1,327 | 31,106 | 31,456 | 947 | 69,242 | `ALL_PASS` |
