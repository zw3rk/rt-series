# rt-series

User-mode runtimes that run foreign Linux guests on an AArch64 host, including macOS on Apple Silicon. The host runs AArch64 natively. Each other guest is either one of the translators below, Apple Rosetta, or still missing.

A 32-bit guest can use a fixed 4 GiB window. A 64-bit guest needs a full address space, the way [rvrt](../rvrt) does for RV64.

The benefit column is the business reason to create or keep that guest: which software then runs on an AArch64 Mac, and what that work is for.

## Have a runtime

| Guest | Width | Runtime | Example CPUs | Benefit and objective |
| --- | --- | --- | --- | --- |
| AArch64 | 64 | The host | Apple M4, AWS Graviton4, AmpereOne | Native speed on the machines this series runs on. Objective: keep AArch64 as the host, and build translators for guests those CPUs cannot execute. |
| AArch32 | 32 | [a32rt](../a32rt) ([GitHub](https://github.com/zw3rk/a32rt)) | ARM Cortex-A7 (Raspberry Pi 2), Cortex-A15 | Apple Silicon, Graviton4, and AmpereOne execute AArch64 only. Objective: run the installed armhf userspace (Raspberry Pi OS, older Debian, board SDKs) on the machines people already have. |
| i386 | 32 | [i686rt](../i686rt) | Intel Pentium III, AMD Athlon XP | Rosetta runs x86-64. Objective: run the i386 Linux binaries and i386 multiarch sysroots that are still what legacy applications and SDKs ship. |
| x86-64 | 64 | [Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment) | AMD Ryzen, Intel Core | Mainstream PC and server Linux. Objective: cover it on the Mac through Rosetta, and spend new translator work on the other guests. |
| RV64GC | 64 | [rvrt](../rvrt) | SiFive U74 (VisionFive 2), T-Head C910 | The open ISA shipping on boards and moving into products. Objective: run riscv64 userspace on a Mac without that board. The tree is an early runtime. |
| RV32GC | 32 | [rvrt](../rvrt), not qualified yet | Nuclei N300FD (`rv32imafdc`) | The embedded RISC-V profile already required in rvrt, with sysroots in tree. Objective: qualify guest execution there, so embedded RV32 userspace is covered by the same project. |

`rvrt` is an early RV64 runtime, not a finished Linux claim. RV32GC is a required profile in that tree: the sysroots exist, and no RV32 guest execution is qualified yet. `i686rt` translates `EM_386`; Phases 0–7 (including x87, MMX, SSE/SSE2, `hyper-linux` integration, and `wine`) plus `H1` and `H4` are merged on `master`, with open campaign items (`C1–C12`) and audit entries (`D1–D74`) tracked in [`../i686rt/DEFECTS.md`](../i686rt/DEFECTS.md). Rosetta covers x86-64 and does not run i386.

## Missing

| Guest | Width | Fits in | Example CPUs | Benefit and objective |
| --- | --- | --- | --- | --- |
| MIPS32 | 32 | 4 GiB window | Ingenic XBurst (JZ4770), MIPS 24Kc (MediaTek MT7620) | Installed router and IoT firmware, including OpenWrt on MIPS 24Kc parts such as the MT7620. Objective: support and port that userspace on a Mac. New designs have largely left MIPS. Shares the 4 GiB window. |
| SPARC V8 | 32 | 4 GiB window | Gaisler LEON3, LEON4 | LEON is still designed into spacecraft. Objective: SPARC V8 Linux userspace on a Mac for aerospace programs with a long service life. Small market. Shares the 4 GiB window. |
| PowerPC | 32 | 4 GiB window | PowerPC 750 (G3) and RAD750, NXP e500v2 (P1021) | Avionics, defense, and industrial boards stay on 32-bit PowerPC for decades after new NXP designs moved to ARM. Objective: keep that fielded Linux userspace (QorIQ e500-class and older 750-class machines) runnable on a Mac. Shares the 4 GiB window. |
| MIPS64 | 64 | Full address space | Loongson 3A3000, Cavium Octeon III | Older Loongson PCs and Cavium Octeon network processors. Objective: run the Linux images that stay on MIPS64. Its own ISA, and a full address space. |
| LoongArch | 64 | Full address space | Loongson 3A6000, 3B6000 | Current Loongson PCs and servers. Objective: run today's LoongArch Linux for Loongson's domestic deployments. A new translator, and a full address space. |
| SPARC V9 | 64 | Full address space | Oracle SPARC M8, Fujitsu SPARC64 XII | Servers still inside a support window: last CPUs in 2017, Fujitsu UNIX on sale through 2029 and supported to 2034. The paying installed base is Solaris. The piece a Linux guest runtime can run is the smaller sparc64 Linux port, so this is the weakest build in the set. Full address space. |
| Power ISA | 64 | Full address space | IBM POWER9 (Raptor Talos II), Power11 | Power11 is in service at banks, hospitals, manufacturers, and telcos. Objective: run ppc64le Linux (RHEL, SLES, Ubuntu on Power). AIX and IBM i are the other operating systems on those servers, outside this Linux-guest series. Full address space. |

Older Loongson chips speak MIPS64. Current Loongson chips speak LoongArch. Power11 is the living 64-bit Power ISA: AIX and IBM i are big-endian, and Linux on Power is little-endian (`ppc64le`). SPARC V9 servers are being wound down. SPARC V8 remains in spacecraft (LEON).

## Specifications, Muse Spark Plan, and Engineering Lode

- [`SPEC.md`](SPEC.md) — Master technical specification across all existing (`a32rt`, `i686rt`, `rvrt`, `hyper-linux` integration) and missing/unqualified (`rv32gc`, `mips32rt`, `ppc32rt`, `sparc32rt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) guest runtimes.
- [`PLAN.md`](PLAN.md) — Master Muse Spark implementation plan (Coordinator + Parallel Worker-Lane Worktree DAG across Waves 1–5).
- [`GOAL.md`](GOAL.md) — Executable `/goal` prompt for Muse Spark coordinator sessions.
- [`docs/HOST-CONTRACT.md`](docs/HOST-CONTRACT.md) — Unified host contract (`A32H_ABI 1.0/1.1` via [`include/a32host.h`](include/a32host.h) for 32-bit 4 GiB-window runtimes, `HL_MEMORY_POLICY_RVRT` + `hl_translators[]` for 64-bit full-address-space runtimes).
- [`docs/lanes/`](docs/lanes/) — Per-wave Muse Spark task cards ([`wave-1-closeout.md`](docs/lanes/wave-1-closeout.md), [`wave-2-rv32gc.md`](docs/lanes/wave-2-rv32gc.md), [`wave-3-rt32-family.md`](docs/lanes/wave-3-rt32-family.md), [`wave-4-rt64-family.md`](docs/lanes/wave-4-rt64-family.md)).
- [`lode/`](lode/) — Cross-repository state-of-play audit ([`STATE-OF-PLAY-2026-10-23.md`](lode/STATE-OF-PLAY-2026-10-23.md)), 11-architecture ISA/syscall/signal matrix ([`ISA-TRAP-AND-ABI-MATRIX.md`](lode/ISA-TRAP-AND-ABI-MATRIX.md)), and review records ([`lode/reviews/`](lode/reviews/)).
