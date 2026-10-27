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

| Target ID | Execution Stack | Binary Used | Where to Run Timed Benchmarks |
|---|---|---|---|
| **`darwin`** | **macOS Standalone (`arm64-apple-darwin`)** — Native Mach-O translator (`src/os/backend_darwin.c` + `Provider A` `vm_file.c` + `MAP_JIT` APRR W^X + 7-insn Soft-TLB). **No Hypervisor.framework / VMM required.** | `_build/<arch>rt-darwin*` | Can run on **idle `aarch64-darwin-{1,3,4,5}.lan` builders** (even without nested VMM support!) **or** on a calm local Apple Silicon Mac. |
| **`hl`** | **`hyper-linux` (`hl`) on Apple Silicon** — `hl` VMM auto-dispatching `_build/<arch>rt` via `hl_translators[]` with `Provider B` (`src/inode_backing.c` Stage-1 L3 COW + `/dev/a32host` `A32H_ABI 1.1`). | `../hyper-linux-u4/_build/hl` + `_build/<arch>rt` | Requires `Hypervisor.framework` — run on a **calm local Apple Silicon host**. |
| **`linux`** | **Linux `aarch64` Standalone** — Static-PIE `aarch64-linux-musl` translator (`src/os/backend_linux.c` + `Provider A` `vm_file.c`) inside `aarch64-linux` (Lima VM or pinned `linux/arm64` container). | `_build/<arch>rt` | Run on a **calm local Apple Silicon host** (or dedicated `aarch64-linux` hardware). |
| **`qemu`** | **Linux `qemu-<arch>` User-Mode TCG Oracle** — Upstream QEMU user-mode TCG inside the same `aarch64-linux` environment for direct apple-to-apples comparison against `linux`. | `qemu-<arch>` | Run alongside `linux` on the same calm `aarch64-linux` substrate. |

### 3.3 Separating Setup & Smoke-Test from Timed Runs

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
