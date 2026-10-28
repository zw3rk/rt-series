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

| Translator | Guest Arch | `darwin` DBT (`us`) | `hl` DBT (`us`) | `linux` DBT (`us`) | `darwin` Interp (`us`) | `linux` Interp (`us`) | macOS `qemu` (`us`) | Linux `qemu` (`us`) | Speedup vs `qemu` (`darwin` / `linux`) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| **`a32rt`** | `armhf` | **10,773** | **15,348** | **8,030** | 571,857 | 570,282 | 44,581 | 22,066 | **4.14x vs macOS QEMU / 2.75x vs Linux QEMU** |
| **`i686rt`** | `i686` | **32,193** | **34,485** | **32,739** | 1,174,119 | 1,381,159 | 52,554 | 32,623 | **1.63x vs macOS QEMU / 1.01x vs Linux QEMU** |
| **`mips32rt`** | `mipsel` | **36,218** | **46,772** | **37,228** | 703,022 | 858,482 | 39,717 | 39,328 | **1.10x vs macOS QEMU / 1.09x vs Linux QEMU** |
| **`ppc32rt`** | `ppc32` | **37,903** | **47,177** | **38,626** | 916,982 | 894,084 | 73,371 | 67,692 | **1.94x vs macOS QEMU / 1.79x vs Linux QEMU** |
| **`sparc32rt`** | `sparc32` | **55,881** | **81,746** | **67,258** | 1,477,200 | 1,706,677 | 84,562 | 68,286 | **1.51x vs macOS QEMU / 1.22x vs Linux QEMU** |
| **`rvrt`** | `riscv64` | **24,090** | **37,031** | **24,548** | 5,213,780 | 3,683,344 | 67,225 | 30,816 | **2.79x vs macOS QEMU / 1.28x vs Linux QEMU** |
| **`rvrt`** | `riscv32` | **24,642** | **38,891** | **25,087** | 5,073,356 | 3,521,173 | 67,677 | 26,932 | **2.75x vs macOS QEMU / 1.09x vs Linux QEMU** |
| **`loongarch64rt`** | `loongarch64` | **32,558** | **46,346** | **33,028** | 2,927,333 | 2,386,382 | 47,646 | 42,824 | **1.46x vs macOS QEMU / 1.32x vs Linux QEMU** |
| **`ppc64rt`** | `ppc64le` | **32,958** | **47,823** | **33,258** | 4,284,855 | 7,049,949 | 83,619 | 67,990 | **2.54x vs macOS QEMU / 2.06x vs Linux QEMU** |
| **`mips64rt`** | `mips64el` | **23,908** | **55,385** | **25,425** | 1,425,215 | 1,894,759 | 45,672 | 42,720 | **1.91x vs macOS QEMU / 1.79x vs Linux QEMU** |
| **`sparc64rt`** | `sparc64` | **56,715** | **67,622** | **56,353** | 10,651,648 | 6,298,132 | 96,659 | 68,951 | **1.70x vs macOS QEMU / 1.22x vs Linux QEMU** |

#### C. Complete 68-Cell Breakdown by Workload (`--full`, microseconds `us`)

| Target | Arch | Engine | `coremark` (`us`) | `chacha20` (`us`) | `vfp_simd` (`us`) | `calls_ibtc` (`us`) | `syscalls` (`us`) | `total_us` (`us`) | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| `native-darwin` | `arm64` | `native` | 475 | 799 | 304 | 1,683 | 5 | 3,266 | `ALL_PASS` |
| `native-linux` | `aarch64` | `native` | 452 | 749 | 320 | 1,686 | 533 | 3,740 | `ALL_PASS` |
| `rosetta2-darwin` | `x86_64` | `rosetta2` | 563 | 1,156 | 498 | 2,180 | 9 | 4,406 | `ALL_PASS` |
| `darwin` | `armhf` | `dbt` | 3,281 | 2,523 | 952 | 3,854 | 163 | 10,773 | `ALL_PASS` |
| `darwin` | `i686` | `dbt` | 7,349 | 3,955 | 8,163 | 12,658 | 68 | 32,193 | `ALL_PASS` |
| `darwin` | `mipsel` | `dbt` | 6,911 | 2,039 | 14,309 | 11,667 | 1,292 | 36,218 | `ALL_PASS` |
| `darwin` | `ppc32` | `dbt` | 7,106 | 2,909 | 16,966 | 10,754 | 168 | 37,903 | `ALL_PASS` |
| `darwin` | `sparc32` | `dbt` | 13,179 | 5,867 | 18,028 | 18,730 | 77 | 55,881 | `ALL_PASS` |
| `darwin` | `riscv64` | `dbt` | 4,813 | 2,620 | 8,732 | 7,313 | 612 | 24,090 | `ALL_PASS` |
| `darwin` | `riscv32` | `dbt` | 5,091 | 2,627 | 8,718 | 7,597 | 609 | 24,642 | `ALL_PASS` |
| `darwin` | `loongarch64` | `dbt` | 6,002 | 1,986 | 16,103 | 7,868 | 599 | 32,558 | `ALL_PASS` |
| `darwin` | `ppc64le` | `dbt` | 10,553 | 1,808 | 4,671 | 15,313 | 613 | 32,958 | `ALL_PASS` |
| `darwin` | `mips64el` | `dbt` | 7,098 | 2,479 | 3,599 | 10,065 | 667 | 23,908 | `ALL_PASS` |
| `darwin` | `sparc64` | `dbt` | 12,642 | 3,868 | 15,876 | 23,977 | 352 | 56,715 | `ALL_PASS` |
| `darwin` | `armhf` | `interp` | 134,168 | 192,217 | 39,663 | 205,168 | 641 | 571,857 | `ALL_PASS` |
| `darwin` | `i686` | `interp` | 235,024 | 402,880 | 172,174 | 363,003 | 1,038 | 1,174,119 | `ALL_PASS` |
| `darwin` | `mipsel` | `interp` | 126,514 | 140,392 | 119,947 | 315,460 | 709 | 703,022 | `ALL_PASS` |
| `darwin` | `ppc32` | `interp` | 142,461 | 121,826 | 214,446 | 437,559 | 690 | 916,982 | `ALL_PASS` |
| `darwin` | `sparc32` | `interp` | 356,524 | 542,071 | 248,845 | 328,217 | 1,543 | 1,477,200 | `ALL_PASS` |
| `darwin` | `riscv64` | `interp` | 1,039,336 | 1,571,373 | 693,546 | 1,904,446 | 5,079 | 5,213,780 | `ALL_PASS` |
| `darwin` | `riscv32` | `interp` | 1,054,626 | 1,564,778 | 714,805 | 1,734,560 | 4,587 | 5,073,356 | `ALL_PASS` |
| `darwin` | `loongarch64` | `interp` | 622,577 | 213,125 | 885,823 | 1,202,433 | 3,375 | 2,927,333 | `ALL_PASS` |
| `darwin` | `ppc64le` | `interp` | 749,814 | 490,506 | 426,649 | 2,605,827 | 12,059 | 4,284,855 | `ALL_PASS` |
| `darwin` | `mips64el` | `interp` | 314,447 | 223,409 | 293,189 | 592,464 | 1,706 | 1,425,215 | `ALL_PASS` |
| `darwin` | `sparc64` | `interp` | 2,565,507 | 3,481,434 | 1,539,639 | 3,053,034 | 12,034 | 10,651,648 | `ALL_PASS` |
| `hl` | `armhf` | `dbt` | 1,573 | 1,069 | 957 | 4,344 | 7,405 | 15,348 | `ALL_PASS` |
| `hl` | `i686` | `dbt` | 9,236 | 4,003 | 8,470 | 12,705 | 71 | 34,485 | `ALL_PASS` |
| `hl` | `mipsel` | `dbt` | 7,259 | 2,775 | 14,237 | 13,137 | 9,364 | 46,772 | `ALL_PASS` |
| `hl` | `ppc32` | `dbt` | 7,833 | 3,756 | 16,865 | 11,117 | 7,606 | 47,177 | `ALL_PASS` |
| `hl` | `sparc32` | `dbt` | 14,704 | 6,778 | 18,298 | 34,738 | 7,228 | 81,746 | `ALL_PASS` |
| `hl` | `riscv64` | `dbt` | 6,426 | 3,258 | 8,496 | 8,026 | 10,825 | 37,031 | `ALL_PASS` |
| `hl` | `riscv32` | `dbt` | 6,770 | 3,906 | 8,542 | 8,642 | 11,031 | 38,891 | `ALL_PASS` |
| `hl` | `loongarch64` | `dbt` | 7,503 | 2,793 | 16,181 | 9,144 | 10,725 | 46,346 | `ALL_PASS` |
| `hl` | `ppc64le` | `dbt` | 11,047 | 1,909 | 4,213 | 19,723 | 10,931 | 47,823 | `ALL_PASS` |
| `hl` | `mips64el` | `dbt` | 8,189 | 2,937 | 3,642 | 10,292 | 30,325 | 55,385 | `ALL_PASS` |
| `hl` | `sparc64` | `dbt` | 13,266 | 4,702 | 16,171 | 23,177 | 10,306 | 67,622 | `ALL_PASS` |
| `linux` | `armhf` | `dbt` | 1,559 | 1,066 | 952 | 3,795 | 658 | 8,030 | `ALL_PASS` |
| `linux` | `i686` | `dbt` | 7,857 | 3,855 | 8,267 | 12,690 | 70 | 32,739 | `ALL_PASS` |
| `linux` | `mipsel` | `dbt` | 6,934 | 2,038 | 14,338 | 11,698 | 2,220 | 37,228 | `ALL_PASS` |
| `linux` | `ppc32` | `dbt` | 7,256 | 2,913 | 17,000 | 10,763 | 694 | 38,626 | `ALL_PASS` |
| `linux` | `sparc32` | `dbt` | 13,623 | 5,894 | 18,009 | 29,084 | 648 | 67,258 | `ALL_PASS` |
| `linux` | `riscv64` | `dbt` | 4,820 | 2,660 | 8,744 | 7,323 | 1,001 | 24,548 | `ALL_PASS` |
| `linux` | `riscv32` | `dbt` | 5,110 | 2,651 | 8,722 | 7,608 | 996 | 25,087 | `ALL_PASS` |
| `linux` | `loongarch64` | `dbt` | 5,997 | 1,986 | 16,133 | 7,884 | 1,028 | 33,028 | `ALL_PASS` |
| `linux` | `ppc64le` | `dbt` | 10,498 | 1,791 | 4,678 | 15,193 | 1,098 | 33,258 | `ALL_PASS` |
| `linux` | `mips64el` | `dbt` | 7,134 | 2,478 | 3,569 | 10,080 | 2,164 | 25,425 | `ALL_PASS` |
| `linux` | `sparc64` | `dbt` | 12,672 | 3,869 | 15,939 | 23,071 | 802 | 56,353 | `ALL_PASS` |
| `linux` | `armhf` | `interp` | 126,870 | 192,597 | 37,909 | 211,777 | 1,129 | 570,282 | `ALL_PASS` |
| `linux` | `i686` | `interp` | 278,769 | 454,923 | 200,017 | 446,166 | 1,284 | 1,381,159 | `ALL_PASS` |
| `linux` | `mipsel` | `interp` | 158,834 | 155,169 | 150,692 | 392,400 | 1,387 | 858,482 | `ALL_PASS` |
| `linux` | `ppc32` | `interp` | 165,836 | 150,508 | 227,536 | 348,787 | 1,417 | 894,084 | `ALL_PASS` |
| `linux` | `sparc32` | `interp` | 391,537 | 586,686 | 352,034 | 374,141 | 2,279 | 1,706,677 | `ALL_PASS` |
| `linux` | `riscv64` | `interp` | 723,257 | 1,030,943 | 479,826 | 1,445,247 | 4,071 | 3,683,344 | `ALL_PASS` |
| `linux` | `riscv32` | `interp` | 723,666 | 1,002,903 | 485,718 | 1,305,146 | 3,740 | 3,521,173 | `ALL_PASS` |
| `linux` | `loongarch64` | `interp` | 502,943 | 206,609 | 502,463 | 1,171,732 | 2,635 | 2,386,382 | `ALL_PASS` |
| `linux` | `ppc64le` | `interp` | 991,790 | 538,281 | 569,539 | 4,928,836 | 21,503 | 7,049,949 | `ALL_PASS` |
| `linux` | `mips64el` | `interp` | 362,771 | 237,419 | 486,204 | 804,917 | 3,448 | 1,894,759 | `ALL_PASS` |
| `linux` | `sparc64` | `interp` | 1,721,541 | 1,604,322 | 1,030,304 | 1,934,920 | 7,045 | 6,298,132 | `ALL_PASS` |
| `qemu` | `armhf` | `tcg` | 2,447 | 2,394 | 5,198 | 11,087 | 940 | 22,066 | `ALL_PASS` |
| `qemu` | `i686` | `tcg` | 2,504 | 6,356 | 12,817 | 9,873 | 1,073 | 32,623 | `ALL_PASS` |
| `qemu` | `mipsel` | `tcg` | 2,330 | 960 | 26,369 | 8,748 | 921 | 39,328 | `ALL_PASS` |
| `qemu` | `ppc32` | `tcg` | 2,309 | 981 | 55,257 | 8,271 | 874 | 67,692 | `ALL_PASS` |
| `qemu` | `sparc32` | `tcg` | 4,553 | 1,320 | 30,784 | 30,733 | 896 | 68,286 | `ALL_PASS` |
| `qemu` | `riscv64` | `tcg` | 1,629 | 1,290 | 14,577 | 12,376 | 944 | 30,816 | `ALL_PASS` |
| `qemu` | `riscv32` | `tcg` | 1,625 | 1,293 | 11,124 | 11,948 | 942 | 26,932 | `ALL_PASS` |
| `qemu` | `loongarch64` | `tcg` | 2,171 | 1,455 | 30,123 | 7,947 | 1,128 | 42,824 | `ALL_PASS` |
| `qemu` | `ppc64le` | `tcg` | 3,073 | 1,177 | 50,430 | 12,338 | 972 | 67,990 | `ALL_PASS` |
| `qemu` | `mips64el` | `tcg` | 2,537 | 1,448 | 29,661 | 8,186 | 888 | 42,720 | `ALL_PASS` |
| `qemu` | `sparc64` | `tcg` | 4,410 | 1,355 | 30,984 | 31,251 | 951 | 68,951 | `ALL_PASS` |
