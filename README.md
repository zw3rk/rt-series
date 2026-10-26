# rt-series

User-mode runtimes that run foreign Linux guests on an AArch64 host, including macOS on Apple Silicon. The host runs AArch64 natively. Each other guest is either one of the translators below, Apple Rosetta, or still missing.

A 32-bit guest can use a fixed 4 GiB window. A 64-bit guest needs a full address space, the way [rvrt](../rvrt) does for RV64.

The benefit column is the business reason to create or keep that guest: which software then runs on an AArch64 Mac, and what that work is for.

## Have a runtime

| Guest | Width | Fits in | Runtime | Example CPUs | Benefit and objective |
| --- | --- | --- | --- | --- | --- |
| AArch64 | 64 | Native | The host | Apple M4, AWS Graviton4, AmpereOne | Native speed on the machines this series runs on. Objective: keep AArch64 as the host, and build translators for guests those CPUs cannot execute. |
| AArch32 | 32 | 4 GiB window | [a32rt](../a32rt) ([GitHub](https://github.com/zw3rk/a32rt)) | ARM Cortex-A7 (Raspberry Pi 2), Cortex-A15 | Apple Silicon, Graviton4, and AmpereOne execute AArch64 only. Objective: run the installed armhf userspace (Raspberry Pi OS, older Debian, board SDKs) on the machines people already have. |
| i386 | 32 | 4 GiB window | [i686rt](../i686rt) | Intel Pentium III, AMD Athlon XP | Rosetta runs x86-64. Objective: run the i386 Linux binaries and i386 multiarch sysroots that are still what legacy applications and SDKs ship. |
| x86-64 | 64 | Native (Rosetta) | [Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment) | AMD Ryzen, Intel Core | Mainstream PC and server Linux. Objective: cover it on the Mac through Rosetta, and spend new translator work on the other guests. |
| RV64GC | 64 | Full address space | [rvrt](../rvrt) | SiFive U74 (VisionFive 2), T-Head C910 | The open ISA shipping on boards and moving into products. Objective: run riscv64 userspace on a Mac without that board. |
| RV32GC | 32 | Full address space (`va_bits=32`) | [rvrt](../rvrt) | Nuclei N300FD (`rv32imafdc`) | The embedded RISC-V profile in `rvrt`, with sysroots in tree. Objective: cover embedded RV32 userspace in the same project. |
| MIPS32 | 32 | 4 GiB window | [mips32rt](../mips32rt) | Ingenic XBurst (JZ4770), MIPS 24Kc (MediaTek MT7620) | Installed router and IoT firmware, including OpenWrt on MIPS 24Kc parts such as the MT7620 (`mipsel` and `mips` O32). Qualified through Phase 7 (`Gate RC-H`). |
| SPARC V8 | 32 | 4 GiB window | [sparc32rt](../sparc32rt) | Gaisler LEON3, LEON4 | LEON is still designed into spacecraft. Runs SPARC V8 Linux userspace on a Mac for aerospace programs with a long service life. Qualified through Phase 7 (`Gate RC-H`). |
| PowerPC | 32 | 4 GiB window | [ppc32rt](../ppc32rt) | PowerPC 750 (G3) and RAD750, NXP e500v2 (P1021) | Avionics, defense, and industrial boards stay on 32-bit PowerPC for decades. Covers both classic 750/7400 FPU and NXP e500v2 SPE userspace. Qualified through Phase 7 (`Gate RC-H`). |
| MIPS64 | 64 | Full address space | [mips64rt](../mips64rt) | Loongson 3A3000, Cavium Octeon III | Older Loongson PCs and Cavium Octeon network processors (`mips64el` and `mips64`, N64 and N32 ABIs). Qualified through Phase 7 (`Gate RC-H`). |
| LoongArch | 64 | Full address space | [loongarch64rt](../loongarch64rt) | Loongson 3A6000, 3B6000 | Current Loongson PCs and servers (`LP64D` + 128-bit LSX + 256-bit LASX). Qualified through Phase 7 (`Gate RC-H`). |
| SPARC V9 | 64 | Full address space | [sparc64rt](../sparc64rt) | Oracle SPARC M8, Fujitsu SPARC64 XII | 64-bit SPARC V9 Linux userspace (stack bias `2047`, quad FP, VIS). Qualified through Phase 7 (`Gate RC-H`). |
| Power ISA | 64 | Full address space | [ppc64rt](../ppc64rt) | IBM POWER9 (Raptor Talos II), Power11 | Runs `ppc64le` ELFv2 Linux (RHEL, SLES, Ubuntu on Power, 64x128-bit VSX). Qualified through Phase 7 (`Gate RC-H`). |

Older Loongson chips speak MIPS64. Current Loongson chips speak LoongArch. Power11 is the living 64-bit Power ISA: AIX and IBM i are big-endian, and Linux on Power is little-endian (`ppc64le`). SPARC V9 servers are being wound down. SPARC V8 remains in spacecraft (LEON).

## Specifications, Feature Matrix, Muse Spark Plan, and Engineering Lode

- [`docs/UNIFICATION-PLAN.md`](docs/UNIFICATION-PLAN.md) — Series-wide 5-module unification, 7-instruction Soft-TLB, `hyper-linux` inode/truncation VFS consolidation, and dual-backend (`backend_linux.c` vs standalone macOS `backend_darwin.c`) architecture and execution plan (Waves `U0`–`U6`), hardened across two fresh-context `astra` reviews ([Review #1](lode/reviews/2026-10-26-astra-unification-review.md), [Review #2](lode/reviews/2026-10-26-astra-unification-review-2.md)).
- [`docs/FEATURE-MATRIX.md`](docs/FEATURE-MATRIX.md) — Cross-runtime feature, execution-engine (`--interp` / `--dbt` / `--difftest` / AOT), SIMD/FP, syscall/signal/thread/process, and Phase 7 (`RC-H`) qualification matrix across all 10 translators.
- [`lode/ISA-TRAP-AND-ABI-MATRIX.md`](lode/ISA-TRAP-AND-ABI-MATRIX.md) — 11-architecture ISA, register, condition-flag, delay-slot, TLS, atomic, Linux syscall, and `rt_sigframe` ABI reference matrix.
- [`SPEC.md`](SPEC.md) — Master technical specification across all guest runtimes (`a32rt`, `i686rt`, `rvrt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) and `hyper-linux` integration.
- [`PLAN.md`](PLAN.md) — Master Muse Spark implementation plan (Coordinator + Parallel Worker-Lane Worktree DAG across Waves 1–5).
- [`GOAL.md`](GOAL.md) — Executable `/goal` prompt for Muse Spark coordinator sessions.
- [`docs/HOST-CONTRACT.md`](docs/HOST-CONTRACT.md) — Unified host contract (`A32H_ABI 1.0/1.1` via [`include/a32host.h`](include/a32host.h) for 32-bit 4 GiB-window runtimes, `HL_MEMORY_POLICY_RVRT` + `hl_translators[]` for 64-bit full-address-space runtimes).
- [`docs/lanes/`](docs/lanes/) — Per-wave Muse Spark task cards ([`wave-1-closeout.md`](docs/lanes/wave-1-closeout.md), [`wave-2-rv32gc.md`](docs/lanes/wave-2-rv32gc.md), [`wave-3-rt32-family.md`](docs/lanes/wave-3-rt32-family.md), [`wave-4-rt64-family.md`](docs/lanes/wave-4-rt64-family.md)).
- [`lode/`](lode/) — Cross-repository state-of-play audit ([`STATE-OF-PLAY-2026-10-23.md`](lode/STATE-OF-PLAY-2026-10-23.md)), 11-architecture ISA/syscall/signal matrix ([`ISA-TRAP-AND-ABI-MATRIX.md`](lode/ISA-TRAP-AND-ABI-MATRIX.md)), and review records ([`lode/reviews/`](lode/reviews/)).
