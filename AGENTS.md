# AGENTS.md — `rt-series`

`rt-series` is the architecture, specification, host-contract, and Muse Spark coordination repository for the `zw3rk` family of foreign-Linux user-mode binary translators targeting AArch64 hosts (`aarch64-linux` and macOS on Apple Silicon via `hyper-linux`).

Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and the sibling boundary rules in `../hyper-linux/AGENTS.md` and `../hyper-linux/docs/SIBLING-REPOS.md`. Keep `CLAUDE.md` symlinked to `AGENTS.md`.

---

## 1. Authoritative Documents in This Repository

| Document | Role |
|---|---|
| [`README.md`](README.md) | Series overview: existing vs. missing guest runtimes, width/address-space classes, example CPUs, and business objectives. |
| [`SPEC.md`](SPEC.md) | Master technical specification covering all existing runtimes (`a32rt`, `i686rt`, `rvrt`, `hyper-linux` integration) and all missing/unqualified runtimes (`rv32gc`, `mips32rt`, `ppc32rt`, `sparc32rt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`). |
| [`PLAN.md`](PLAN.md) | Master implementation plan tailored to **Muse Spark** (`Coordinator + Parallel Worker-Lane Worktree DAG`, phase gates, frozen headers, exclusive file ownership, single-command acceptance checks, and Wave 1–5 execution schedule). |
| [`GOAL.md`](GOAL.md) | Executable `/goal` prompt for coordinator sessions executing the Unification & Dual-Backend Architecture Program (`docs/UNIFICATION-PLAN.md` Rev 4 + `docs/lanes/wave-u-unification.md`). |
| [`docs/UNIFICATION-PLAN.md`](docs/UNIFICATION-PLAN.md) | Master 10-translator Unification & Dual-Backend Architecture Plan (Rev 4): uniform 5-module layout, 7-instruction Soft-TLB, in-place non-relocating COW, 6-step `tgkill` quiescence, `Provider A` & `Provider B` (`hyper-linux`), and dual `backend_linux.c` / `backend_darwin.c` targets. |
| [`docs/HOST-CONTRACT.md`](docs/HOST-CONTRACT.md) | Unified host contract for Class-A 32-bit 4 GiB-window runtimes (`A32H_ABI 1.0/1.1`, `/dev/a32host`, `include/a32host.h`) and Class-B 64-bit full-address-space runtimes (`HL_MEMORY_POLICY_RVRT`, `hyper-linux-apfs-acl-v1`, `hl_translators[]` auto-dispatch). |
| [`docs/CONVERGENCE-AUDIT-PROCESS.md`](docs/CONVERGENCE-AUDIT-PROCESS.md) | Authoritative multi-agent convergence audit & remediation playbook (`gpt-6-astra` hunting $\rightarrow$ cross-runtime clustering $\rightarrow$ `muse exec` surgical remediation $\rightarrow$ `claude-fable-5-1` / fallback `claude-opus-5-5` verification), parabola oscillation model, step-size annealing, and 6-subsystem deep-dive schedule. |
| [`DEFECTS.md`](DEFECTS.md) | Master cross-repository defect, Curated-C11, and subsystem deep-dive checklist across all 11 repositories (active round + archived rounds). |
| [`docs/lanes/`](docs/lanes/) | Per-wave task cards (`wave-u-unification.md`, `wave-1-closeout.md`, `wave-2-rv32gc.md`, `wave-3-rt32-family.md`, `wave-4-rt64-family.md`). |
| [`lode/`](lode/) | Engineering lode: cross-repo state-of-play audit (`lode/STATE-OF-PLAY-2026-10-23.md`), 11-architecture ISA/syscall/signal matrix (`lode/ISA-TRAP-AND-ABI-MATRIX.md`), and `astra` (`gpt-6-astra`) review transcripts (`lode/reviews/`). |

---

## 2. Series Architectural Invariants

1. **Two Address-Space Classes**:
   - **Class A — 32-Bit Fixed 4 GiB Window (`[G, G + 4 GiB)`)**: `a32rt` (`EM_ARM`), `i686rt` (`EM_386`), `mips32rt` (`EM_MIPS` O32), `ppc32rt` (`EM_PPC` classic + e500v2 SPE), and `sparc32rt` (`EM_SPARC` V8 / LEON).
     - Copy-first reuse of the proven `rt32_` substrate (`vm.c`, `elf32.c`, `stack32.c`, `host.c`, `a64_emit.[ch]`, JIT cache/chaining/IBTC/RAS core, signal multiplexing, `/proc/self/*` synthesis). **Never extract a premature shared `librt32` library across repos**; each translator stays a standalone zero-dependency repository.
     - Parametric window base `G` held in reserved register `x20` (`xG`); all 32-bit effective addresses wrap in `W` registers before adding `xG` (`[x20, wAddr, uxtw]`). Under `hyper-linux`, `G = 0x1_0000_0000` (4 GiB offset mode).
     - Negotiates host capabilities via `/dev/a32host` (`include/a32host.h`, `A32H_ABI 1.0/1.1`).
   - **Class B — 64-Bit Full Address Space (plus RV32GC in `rvrt`)**: `rvrt` (`EM_RISCV` RV64GC & RV32GC), `loongarch64rt` (`EM_LOONGARCH` LA64), `ppc64rt` (`EM_PPC64` `ppc64le` ELFv2), `mips64rt` (`EM_MIPS` N64/N32), and `sparc64rt` (`EM_SPARCV9` SPARC V9).
     - Strict separation of Guest VA (`uint64_t`), Translator VA, and Host GPA. Never truncate 64-bit guest addresses or force a 64-bit guest into a 4 GiB window.
     - Reuses `rvrt`'s family coordination substrate (`.<rt>-family-<pid>-<seq>`, canonical `family_mm`, `family_shmem`, `family_file`, `rv_file_caps` SCM broker, deterministic FIFO turn scheduler, race-free `safe_syscall_a64.S`, and same-PID `execve` packed bootstrap).
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
   - The **Coordinator** owns `master`, the dependency DAG, frozen headers/interfaces, task cards (`docs/lanes/`), batch reviews, `--no-ff` or `--ff-only` merges, and phase-level Review Checkpoints (`RC`). The Coordinator does no repetitive table/handler/fixture grunt work.
   - **Worker Lanes** run in isolated git worktrees (`../<repo>-<lane>` on branch `lane/<phase>-<lane>` or `.muse/worktrees/subagent-v2-...`). Each lane has **exclusive file ownership**, codes against **frozen read-only headers**, and runs **one deterministic acceptance check** once.
2. **Escalation Protocol**:
   - A worker lane stops and escalates to the Coordinator when: (1) its acceptance check fails twice, (2) it needs any edit to a frozen header or unowned file, or (3) the task card or spec is ambiguous.
3. **Process & Container Lifecycle**:
   - Bound every build, container, QEMU oracle, Lima VM, and `hl` test run with an explicit wall-clock `timeout --kill-after=30s`.
   - Name every Docker/Podman container uniquely (`--name` or `--cidfile`) and verify container removal (`docker ps` / `podman ps`) on exit, error, or cancellation.
4. **Git & Attribution Hygiene**:
   - Default branch is `master`. Preserve user changes and sibling worktrees. Never `git push` without explicit user permission.
   - License: `Apache-2.0`, `Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.` Never include AI agent or model names in commit messages, trailers, or author metadata.
