# rt-series

User-mode runtimes that run foreign Linux guests on an AArch64 host, including macOS on Apple Silicon. The host runs AArch64 natively. Each other guest is either one of the translators below or Apple Rosetta.

A 32-bit guest can use a fixed 4 GiB window (`Class A`). A 64-bit guest needs a full address space (`Class B`), the way [rvrt](../rvrt) does for RV64.

The benefit column is the business reason to create or keep that guest: which software then runs on an AArch64 Mac, and what that work is for.

## Have a runtime

| Guest | Width | Fits in | Runtime | Example CPUs | Benefit and objective |
| --- | --- | --- | --- | --- | --- |
| AArch64 | 64 | Native | The host | Apple M4, AWS Graviton4, AmpereOne | Native speed on the machines this series runs on. Objective: keep AArch64 as the host, and build translators for guests those CPUs cannot execute. |
| AArch32 | 32 | 4 GiB window | [a32rt](../a32rt) ([GitHub](https://github.com/zw3rk/a32rt)) | ARM Cortex-A7 (Raspberry Pi 2), Cortex-A15 | Apple Silicon, Graviton4, and AmpereOne execute AArch64 only. Objective: run the installed armhf userspace (Raspberry Pi OS, older Debian, board SDKs) on the machines people already have. Qualified through Phase 7 (`RC-H`), Wave U3 (`RC-U3 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| i386 | 32 | 4 GiB window | [i686rt](../i686rt) | Intel Pentium III, AMD Athlon XP | Rosetta runs x86-64. Objective: run the i386 Linux binaries and i386 multiarch sysroots that are still what legacy applications and SDKs ship. Qualified through Phase 7 (`RC-H`), Wave U3 (`RC-U3 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| x86-64 | 64 | Native (Rosetta) | [Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment) | AMD Ryzen, Intel Core | Mainstream PC and server Linux. Objective: cover it on the Mac through Rosetta, and spend new translator work on the other guests. |
| RV64GC | 64 | Full address space | [rvrt](../rvrt) | SiFive U74 (VisionFive 2), T-Head C910 | The open ISA shipping on boards and moving into products. Objective: run riscv64 userspace on a Mac without that board. Qualified through Wave U5 (`RC-U5 PASS`) and Convergence Round 18 (`0 DEFECTS`). |
| RV32GC | 32 | Full address space (`va_bits=32`) | [rvrt](../rvrt) | Nuclei N300FD (`rv32imafdc`) | The embedded RISC-V profile (`ILP32D`) in `rvrt`, with static and dynamic `musl` & `glibc` sysroots in tree. Qualified through Milestone R8, Wave U5 (`RC-U5 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| MIPS32 | 32 | 4 GiB window | [mips32rt](../mips32rt) | Ingenic XBurst (JZ4770), MIPS 24Kc (MediaTek MT7620) | Installed router and IoT firmware, including OpenWrt on MIPS 24Kc parts such as the MT7620 (`mipsel` and `mips` O32). Qualified through Phase 7 (`RC-H`), Wave U3 (`RC-U3 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| SPARC V8 | 32 | 4 GiB window | [sparc32rt](../sparc32rt) | Gaisler LEON3, LEON4 | LEON is still designed into spacecraft. Runs SPARC V8 Linux userspace on a Mac for aerospace programs with a long service life. Qualified through Phase 7 (`RC-H`), Wave U3 (`RC-U3 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| PowerPC | 32 | 4 GiB window | [ppc32rt](../ppc32rt) | PowerPC 750 (G3) and RAD750, NXP e500v2 (P1021) | Avionics, defense, and industrial boards stay on 32-bit PowerPC for decades. Covers both classic 750/7400 FPU and NXP e500v2 SPE userspace. Qualified through Phase 7 (`RC-H`), Wave U3 (`RC-U3 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| MIPS64 | 64 | Full address space | [mips64rt](../mips64rt) | Loongson 3A3000, Cavium Octeon III | Older Loongson PCs and Cavium Octeon network processors (`mips64el` and `mips64`, N64 and N32 ABIs). Qualified through Phase 7 (`RC-H`), Wave U1/U2 (`RC-U12 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| LoongArch | 64 | Full address space | [loongarch64rt](../loongarch64rt) | Loongson 3A6000, 3B6000 | Current Loongson PCs and servers (`LP64D` + 128-bit LSX + 256-bit LASX). Qualified through Phase 7 (`RC-H`), Wave U1/U2 (`RC-U12 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| SPARC V9 | 64 | Full address space | [sparc64rt](../sparc64rt) | Oracle SPARC M8, Fujitsu SPARC64 XII | 64-bit SPARC V9 Linux userspace (stack bias `2047`, quad FP, VIS). Qualified through Phase 7 (`RC-H`), Wave U1/U2 (`RC-U12 PASS`), and Convergence Round 18 (`0 DEFECTS`). |
| Power ISA | 64 | Full address space | [ppc64rt](../ppc64rt) | IBM POWER9 (Raptor Talos II), Power11 | Runs `ppc64le` ELFv2 Linux (RHEL, SLES, Ubuntu on Power, 64x128-bit VSX). Qualified through Phase 7 (`RC-H`), Wave U1/U2 (`RC-U12 PASS`), and Convergence Round 18 (`0 DEFECTS`). |

Older Loongson chips speak MIPS64. Current Loongson chips speak LoongArch. Power11 is the living 64-bit Power ISA: AIX and IBM i are big-endian, and Linux on Power is little-endian (`ppc64le`). SPARC V9 servers are being wound down. SPARC V8 remains in spacecraft (LEON).

---

## Benchmarks (Apple M4 / `aarch64-darwin-5.lan`)

Every runtime is benchmarked on the unified 5-workload suite ([`tests/bench_suite.c`](tests/bench_suite.c): **CoreMark**-style integer/list/matrix/tokenizer, **ChaCha20** 20-round ARX stream cipher, **FP/SIMD** IEEE-754 + vector kernels, **Calls/IBTC** indirect call/return dispatch, and **Syscalls** `getpid`/`clock_gettime` round-trips; 1 warmup + 4 timed trials per workload, reporting minimum elapsed microseconds with deterministic CRC verification).

Raw results are recorded in [`docs/bench/results-darwin5-full.tsv`](docs/bench/results-darwin5-full.tsv).

### Total Suite Execution Time ($\mu\text{s}$, lower is better)

| Guest ISA | Translator | Darwin DBT ($\mu\text{s}$) | Linux DBT ($\mu\text{s}$) | `hyper-linux` DBT ($\mu\text{s}$) | `qemu-user` TCG ($\mu\text{s}$) | Speedup vs. `qemu-user` | Darwin Interp ($\mu\text{s}$) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **AArch64** *(baseline)* | Native host | `3,255` | `3,740` | — | — | — | — |
| **AArch32** (`armhf`) | `a32rt` | `12,689` | **`7,954`** | `15,118` | `24,914` | **3.13x** | `571,857` |
| **i386** (`i686`) | `i686rt` | `32,904` | `34,441` | **`30,815`** | `36,682` | **1.19x** | `1,174,119` |
| **MIPS32** (`mipsel` O32) | `mips32rt` | **`30,190`** | `31,057` | `40,664` | `39,533` | **1.31x** | `703,022` |
| **PowerPC 32** (`ppc32`) | `ppc32rt` | **`37,899`** | `38,205` | `47,323` | `67,799` | **1.79x** | `916,982` |
| **SPARC V8** (`sparc32`) | `sparc32rt` | **`40,138`** | `40,537` | `52,502` | `68,051` | **1.70x** | `1,477,200` |
| **RISC-V 64** (`riscv64`) | `rvrt` | `25,686` | **`24,463`** | `37,235` | `30,703` | **1.26x** | `5,213,780` |
| **RISC-V 32** (`riscv32`) | `rvrt` | `26,093` | **`25,046`** | `38,657` | `26,750` | **1.07x** | `5,073,356` |
| **LoongArch64** (`loongarch64`) | `loongarch64rt` | **`38,786`** | `39,222` | `49,558` | `43,724` | **1.13x** | `2,927,333` |
| **Power ISA 64** (`ppc64le`) | `ppc64rt` | **`35,243`** | `35,681` | `44,710` | `68,920` | **1.96x** | `4,284,855` |
| **MIPS64** (`mips64el` N64) | `mips64rt` | **`23,785`** | `25,150` | `47,080` | `42,229` | **1.78x** | `1,425,215` |
| **SPARC V9** (`sparc64`) | `sparc64rt` | **`51,386`** | `51,428` | `60,051` | `69,027` | **1.34x** | `10,651,648` |

### Per-Workload Breakdown — Darwin DBT vs. Linux DBT vs. `qemu-user` TCG ($\mu\text{s}$)

| Guest ISA (`Translator`) | Target | CoreMark ($\mu\text{s}$) | ChaCha20 ($\mu\text{s}$) | FP/SIMD ($\mu\text{s}$) | Calls/IBTC ($\mu\text{s}$) | Syscalls ($\mu\text{s}$) | Total ($\mu\text{s}$) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `armhf` (`a32rt`) | Darwin / Linux / QEMU | `3,953` / `1,554` / `2,470` | `2,994` / `1,067` / `2,398` | `953` / `950` / `7,943` | `4,607` / `3,713` / `11,159` | `182` / `670` / `944` | `12,689` / **`7,954`** / `24,914` |
| `i686` (`i686rt`) | Darwin / Linux / QEMU | `7,245` / `7,803` / `2,505` | `3,730` / `4,520` / `6,226` | `8,212` / `8,395` / `16,895` | `13,556` / `13,587` / `9,981` | `161` / `136` / `1,075` | **`32,904`** / `34,441` / `36,682` |
| `mipsel` (`mips32rt`) | Darwin / Linux / QEMU | `6,924` / `6,950` / `2,410` | `2,113` / `2,112` / `993` | `8,030` / `8,052` / `26,458` | `11,618` / `11,649` / `8,747` | `1,505` / `2,294` / `925` | **`30,190`** / `31,057` / `39,533` |
| `ppc32` (`ppc32rt`) | Darwin / Linux / QEMU | `7,292` / `7,014` / `2,278` | `2,907` / `2,907` / `981` | `16,348` / `16,409` / `55,408` | `10,826` / `10,830` / `8,254` | `526` / `1,045` / `878` | **`37,899`** / `38,205` / `67,799` |
| `sparc32` (`sparc32rt`) | Darwin / Linux / QEMU | `6,641` / `6,644` / `4,545` | `4,411` / `4,418` / `1,321` | `16,888` / `16,949` / `30,977` | `11,873` / `11,830` / `30,311` | `325` / `696` / `897` | **`40,138`** / `40,537` / `68,051` |
| `riscv64` (`rvrt`) | Darwin / Linux / QEMU | `4,812` / `4,806` / `1,624` | `2,645` / `2,658` / `1,285` | `10,299` / `8,680` / `14,545` | `7,313` / `7,317` / `12,300` | `617` / `1,002` / `949` | `25,686` / **`24,463`** / `30,703` |
| `riscv32` (`rvrt`) | Darwin / Linux / QEMU | `5,081` / `5,095` / `1,615` | `2,634` / `2,651` / `1,292` | `10,238` / `8,743` / `11,091` | `7,525` / `7,561` / `11,816` | `615` / `996` / `936` | `26,093` / **`25,046`** / `26,750` |
| `loongarch64` (`loongarch64rt`) | Darwin / Linux / QEMU | `5,993` / `5,981` / `2,527` | `1,990` / `1,984` / `1,455` | `22,089` / `22,136` / `30,639` | `8,057` / `8,019` / `7,988` | `657` / `1,102` / `1,115` | **`38,786`** / `39,222` / `43,724` |
| `ppc64le` (`ppc64rt`) | Darwin / Linux / QEMU | `10,133` / `10,064` / `3,093` | `1,799` / `1,802` / `1,180` | `8,107` / `8,104` / `50,715` | `14,631` / `14,646` / `12,940` | `573` / `1,065` / `992` | **`35,243`** / `35,681` / `68,920` |
| `mips64el` (`mips64rt`) | Darwin / Linux / QEMU | `7,184` / `7,100` / `2,544` | `2,479` / `2,481` / `1,449` | `3,378` / `3,357` / `29,290` | `10,065` / `10,066` / `8,047` | `679` / `2,146` / `899` | **`23,785`** / `25,150` / `42,229` |
| `sparc64` (`sparc64rt`) | Darwin / Linux / QEMU | `11,691` / `11,475` / `4,418` | `4,268` / `4,073` / `1,325` | `16,227` / `16,150` / `30,966` | `18,747` / `18,810` / `31,362` | `453` / `920` / `956` | **`51,386`** / `51,428` / `69,027` |

---

## Nix Flakes (`flake.nix`)

Every translator repository stays a standalone, zero-dependency repository with its own `flake.nix`, while `rt-series` provides an **Umbrella Flake** ([`flake.nix`](flake.nix)) that aggregates all 10 translators:

### Umbrella Flake (`rt-series/flake.nix`)
- **Build all 10 translators at once** (`bin/` contains both `<rt>` static-PIE Linux binaries and `<rt>-darwin` native macOS binaries on `aarch64-darwin`):
  ```sh
  nix build .#default
  ```
- **Build an individual translator via the umbrella flake**:
  ```sh
  nix build .#a32rt
  nix build .#i686rt-darwin
  nix build .#rvrt
  ```
- **Enter the unified cross-compilation & audit shell**:
  ```sh
  nix develop
  ```

### Standalone Per-Repository Flakes (`../<rt>/flake.nix`)
Each of the 10 translator repositories (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `rvrt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) exposes:
- `packages.<system>.default` and `packages.<system>.<rt>` — Static-PIE `aarch64-unknown-linux-musl` translator binary (for `aarch64-linux` and `hyper-linux`);
- `packages.aarch64-darwin.<rt>-darwin` — Native macOS Apple Silicon (`backend_darwin`) translator binary;
- `devShells.<system>.default` — Hermetic development shell with `aarch64-unknown-linux-musl-gcc` + guest cross-compiler toolchain.

---

## Repository Contents

| Path | Description |
| --- | --- |
| [`flake.nix`](flake.nix) | Umbrella Nix Flake aggregating all 10 sibling translators (`a32rt` through `sparc64rt`) plus the cross-architecture benchmark/verification `devShell`. |
| [`include/a32host.h`](include/a32host.h) | Canonical frozen `/dev/a32host` ABI header (`A32H_ABI 1.0/1.1`) shared across all Class-A 32-bit 4 GiB-window translators and `hyper-linux`. |
| [`tests/`](tests/) | Unified 11-architecture benchmark suite ([`tests/bench_suite.c`](tests/bench_suite.c), [`tests/bench_sys.h`](tests/bench_sys.h)), TCG/DBT torture tests ([`tests/p3_torture.c`](tests/p3_torture.c)), ABI invariant checks ([`tests/check_abi_invariants.c`](tests/check_abi_invariants.c)), and catalogue harness ([`tests/catalogue/run_catalogue.sh`](tests/catalogue/run_catalogue.sh)). |
| [`tools/`](tools/) | Series-wide orchestration scripts: [`tools/run_catalogue.sh`](tools/run_catalogue.sh) (multi-tier `smoke`/`quick`/`full` qualification across all 10 repos), [`tools/parity_contract.sh`](tools/parity_contract.sh) (60-row Linux/Darwin parity gate), [`tools/remote_bench.sh`](tools/remote_bench.sh) (automated remote Darwin/Lima/`hyper-linux`/`qemu-user` benchmarking), and [`tools/build_uniform_guests.sh`](tools/build_uniform_guests.sh). |
| [`DEFECTS.md`](DEFECTS.md) | Master cross-repository defect, Curated-C11, and 6-subsystem deep-dive checklist across all 11 repositories (Rounds 1–18 + Fast-Path Restoration Round, converged to `0 DEFECTS`). |
| [`docs/CONVERGENCE-AUDIT-PROCESS.md`](docs/CONVERGENCE-AUDIT-PROCESS.md) | Authoritative multi-agent convergence audit & remediation playbook (`gpt-6-astra` hunting $\rightarrow$ cross-runtime clustering $\rightarrow$ `muse exec` surgical remediation $\rightarrow$ `claude-fable-5-1` / fallback `claude-opus-5-5` verification), parabola oscillation model, step-size annealing, and 6-subsystem deep-dive schedule. |
| [`docs/UNIFICATION-PLAN.md`](docs/UNIFICATION-PLAN.md) | Series-wide 5-module unification, 7-instruction Soft-TLB, `hyper-linux` inode/truncation VFS consolidation, and dual-backend (`backend_linux.c` vs standalone macOS `backend_darwin.c`) architecture and execution plan (Waves `U0`–`U6`), hardened across two fresh-context `astra` reviews ([Review #1](lode/reviews/2026-10-26-astra-unification-review.md), [Review #2](lode/reviews/2026-10-26-astra-unification-review-2.md)). |
| [`docs/FEATURE-MATRIX.md`](docs/FEATURE-MATRIX.md) | Cross-runtime feature, execution-engine (`--interp` / `--dbt` / `--difftest` / AOT), SIMD/FP, syscall/signal/thread/process, and Phase 7 (`RC-H`) qualification matrix across all 10 translators. |
| [`docs/HOST-CONTRACT.md`](docs/HOST-CONTRACT.md) | Unified host contract (`A32H_ABI 1.0/1.1` via [`include/a32host.h`](include/a32host.h) for 32-bit 4 GiB-window runtimes, `HL_MEMORY_POLICY_RVRT` + `hl_translators[]` for 64-bit full-address-space runtimes). |
| [`SPEC.md`](SPEC.md) & [`PLAN.md`](PLAN.md) | Master technical specification and Muse Spark Coordinator + Parallel Worker-Lane Worktree DAG plan across Waves 1–5. |
| [`lode/`](lode/) | Engineering lode: cross-repository state-of-play audit ([`STATE-OF-PLAY-2026-10-23.md`](lode/STATE-OF-PLAY-2026-10-23.md)), 11-architecture ISA/syscall/signal matrix ([`ISA-TRAP-AND-ABI-MATRIX.md`](lode/ISA-TRAP-AND-ABI-MATRIX.md)), and review transcripts ([`lode/reviews/`](lode/reviews/)). |
