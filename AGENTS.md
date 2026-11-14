# AGENTS.md — `rt-series`

`rt-series` is the architecture, specification, host-contract, and Muse Spark coordination repository for the `zw3rk` family of foreign-Linux user-mode binary translators targeting AArch64 hosts (`aarch64-linux` and macOS on Apple Silicon via `hyper-linux`).

Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and the sibling boundary rules in `../hyper-linux/AGENTS.md` and `../hyper-linux/docs/SIBLING-REPOS.md`. Keep `CLAUDE.md` symlinked to `AGENTS.md`.

---

## 1. Authoritative Documents in This Repository

| Document | Role |
|---|---|
| [`README.md`](README.md) | Series overview: 10 translators, 11 guest ISAs in 17 ABI/OS variants, address-space classes, benchmarks, and documentation map. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Technical architecture manual: address-space classes, uniform 5-module layout, 7-instruction Soft-TLB, in-place non-relocating COW, dual host backends, and cross-ISA design decisions. |
| [`docs/HOST-CONTRACT.md`](docs/HOST-CONTRACT.md) | Unified host contract for Class-A 32-bit 4 GiB-window runtimes (`A32H_ABI 1.0/1.1`, `/dev/a32host`, `include/a32host.h`) and Class-B 64-bit full-address-space runtimes (`HL_MEMORY_POLICY_RVRT`, `hyper-linux-apfs-acl-v1`, `hl_translators[]` auto-dispatch). |
| [`docs/FEATURE-MATRIX.md`](docs/FEATURE-MATRIX.md) | Cross-runtime feature, execution-engine, SIMD/FPU, syscall/signal/thread, and qualification matrix across all 10 translators. |
| [`docs/SOFTWARE-CATALOGUE.md`](docs/SOFTWARE-CATALOGUE.md) | Real-world software qualification catalogue (`T1`–`T5`) and unified 4-target benchmark harness. |
| [`docs/CONVERGENCE-AUDIT-PROCESS.md`](docs/CONVERGENCE-AUDIT-PROCESS.md) | Authoritative multi-agent convergence audit & remediation playbook (`gpt-6-astra` hunting $\rightarrow$ cross-runtime clustering $\rightarrow$ `muse exec` surgical remediation $\rightarrow$ `claude-fable-5-1` / fallback `claude-opus-5-5` verification), parabola oscillation model, step-size annealing, and 6-subsystem deep-dive schedule. |
| [`docs/DEFECTS.md`](docs/DEFECTS.md) | Defect ledger executive summary: Rounds 1–18 plus the Post-Round-12 Fast-Path Restoration Round, `0` open defects; full checklists in `docs/archive/defects/`. |
| [`lode/ISA-TRAP-AND-ABI-MATRIX.md`](lode/ISA-TRAP-AND-ABI-MATRIX.md) | 11-architecture ISA, trap, and ABI reference matrix (ELF, endianness, registers, delay slots, TLS, atomics, syscalls, vDSO, signal frames). |
| [`docs/archive/`](docs/archive/) | Historical campaign plans (`plans/`), per-wave task cards (`lanes/`), and archived defect rounds (`defects/`). |
| [`lode/`](lode/) | Engineering lode: historical baseline snapshot (`lode/STATE-OF-PLAY-2026-10-23.md`), the ISA matrix above, and review transcripts (`lode/reviews/` in 4 organized subdirectories). |

---

## 2. Series Architectural Invariants

1. **Two Address-Space Classes**:
   - **Class A — 32-Bit Fixed 4 GiB Window (`[G, G + 4 GiB)`)**: `a32rt` (`EM_ARM` Linux + 32-bit iOS `MH_MAGIC`/`FAT_MAGIC` `armv7`/`armv7s`), `i686rt` (`EM_386`), `mips32rt` (`EM_MIPS` O32), `ppc32rt` (`EM_PPC` classic + e500v2 SPE), and `sparc32rt` (`EM_SPARC` V8 / LEON).
     - Copy-first reuse of the proven `rt32_` substrate (`vm.c`, `elf32.c`, `stack32.c`, `host.c`, `a64_emit.[ch]`, JIT cache/chaining/IBTC/RAS core, signal multiplexing, `/proc/self/*` synthesis). **Never extract a premature shared `librt32` library across repos**; each translator stays a standalone zero-dependency repository.
     - Parametric window base `G` held in reserved register `x20` (`xG`); all 32-bit effective addresses wrap in `W` registers before adding `xG` (`[x20, wAddr, uxtw]`). Under `hyper-linux`, `G = 0x1_0000_0000` (4 GiB offset mode).
     - Negotiates host capabilities via `/dev/a32host` (`include/a32host.h`, `A32H_ABI 1.0/1.1`).
   - **Class B — 64-Bit Full Address Space (plus RV32GC in `rvrt`)**: `rvrt` (`EM_RISCV` RV64GC & RV32GC), `loongarch64rt` (`EM_LOONGARCH` LA64), `ppc64rt` (`EM_PPC64` `ppc64le` ELFv2), `mips64rt` (`EM_MIPS` N64/N32), and `sparc64rt` (`EM_SPARCV9` SPARC V9).
     - Strict separation of Guest VA (`uint64_t`), Translator VA, and Host GPA. Never truncate 64-bit guest addresses or force a 64-bit guest into a 4 GiB window.
     - Shares the unified Class-B `vm64` substrate (`src/vm/vm64.c`, `Provider A` / `Provider B` in-place non-relocating COW, family shared-memory inode/EOF table, 6-step `tgkill` / `SIGUSR2` quiescence, race-free `safe_syscall`, and same-PID `execve` bootstrap).
     - Integrates with `hyper-linux` via `HL_MEMORY_POLICY_RVRT`, the 1 GiB disjoint shared arena (`rvrt_shared`), `hyper-linux-apfs-acl-v1` AOT cache authority, and the `hl_translators[]` dispatch table.
2. **Language, Toolchain & Artifact Discipline**:
   - **Curated C11** (`-std=c11 -Werror=vla -pedantic -Wall -Wextra`) + minimal AArch64 assembly. No VLAs, no Annex K (`*_s`), no `<threads.h>`, no `_Generic`, no `sprintf`/`strcpy`/`strcat`.
   - Zero external runtime dependencies beyond static `musl` libc (`aarch64-unknown-linux-musl-gcc -static-pie -fPIE`).
   - **Register `x18` is permanently reserved** on AArch64 across all JIT emitters and assembly trampolines.
   - **W^X & I-Cache Coherence**: Never map guest data pages `PROT_EXEC` on the host; emit A64 code into RW staging/pages, flip to `PROT_READ | PROT_EXEC`, and honor `A32H_CAP_ICACHE_TRAP_IALLU` when running under `hyper-linux`.
3. **Dual-Engine Pattern (`interp` + `dbt`) for New Translators**:
   - Every new translator (`mips32rt`, `ppc32rt`, `sparc32rt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) implements:
     1. A portable Curated C11 **interpreter** (`src/interp/`) as the correctness oracle, differential reference, and fallback for rare/complex/unaligned/system instructions;
     2. An **AArch64 DBT/JIT** (`src/dbt/`) with D2-style single-instruction interpreter fallback (`EXIT_UNDEF` -> `interp_step` -> resume DBT) so unknown instructions never abort execution.

---

## 3. Muse Spark Workflow & Concurrency Rules

1. **Coordinator + Worker-Lane Split**:
   - The **Coordinator** owns `master`, the dependency DAG, frozen headers/interfaces, task cards (`docs/archive/lanes/`), batch reviews, `--no-ff` or `--ff-only` merges, and phase-level Review Checkpoints (`RC`). The Coordinator does no repetitive table/handler/fixture grunt work.
   - **Worker Lanes** run in isolated git worktrees (`../<repo>-<lane>` on branch `lane/<phase>-<lane>` or `.muse/worktrees/subagent-v2-...`). Each lane has **exclusive file ownership**, codes against **frozen read-only headers**, and runs **one deterministic acceptance check** once.
2. **Escalation Protocol**:
   - A worker lane stops and escalates to the Coordinator when: (1) its acceptance check fails twice, (2) it needs any edit to a frozen header or unowned file, or (3) the task card or spec is ambiguous.
3. **Process & Container Lifecycle**:
   - Bound every build, container, QEMU oracle, Lima VM, and `hl` test run with an explicit wall-clock `timeout --kill-after=30s`.
   - Name every Docker/Podman container uniquely (`--name` or `--cidfile`) and verify container removal (`docker ps` / `podman ps`) on exit, error, or cancellation.
4. **Git & Attribution Hygiene**:
   - Default branch is `master`. Preserve user changes and sibling worktrees. Never `git push` without explicit user permission.
   - License: `Apache-2.0`, `Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.` Never include AI agent or model names in commit messages, trailers, or author metadata.
