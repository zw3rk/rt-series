# `rt-series` — Master Technical Specification

Status: Draft rev 2, 2026-10-23 (incorporates Astra Review #1 fixes & compile-time ABI invariants)  
Owner: Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.  
License: Apache-2.0  
Repositories covered: `rt-series` (`.` — series architecture & coordination), [`../a32rt`](../a32rt), [`../i686rt`](../i686rt), [`../rvrt`](../rvrt), [`../hyper-linux`](../hyper-linux), and planned sibling translators (`../mips32rt`, `../ppc32rt`, `../sparc32rt`, `../loongarch64rt`, `../ppc64rt`, `../mips64rt`, `../sparc64rt`).  
Evidence tags (`~/.config/ai/AGENTS.md`): `[F]` verified in local source/commits/Linux UAPI (`tests/check_abi_invariants.c`); `[I]` inference; `[H]` hypothesis requiring runtime measurement; `[U]` requires Phase E experiment verification before dependent implementation phases start.

---

## 0. Reference Study & Current Baseline Across Sibling Repositories

### 0.1 Architectural Lineage (`a32rt`, `i686rt`, `rvrt`, `hyper-linux`) `[F]`

The `rt-series` program runs foreign Linux userspace binaries on AArch64 hosts (native AArch64 Linux on Apple M-series / AWS Graviton4 / AmpereOne, and macOS on Apple Silicon via `hyper-linux`). While AArch64 executes natively and `x86_64` is covered on macOS by Apple `RosettaLinux`, every other foreign Linux ISA requires a standalone, zero-dependency, static-PIE `aarch64-unknown-linux-musl` user-mode translator.

The series splits into **two architectural families** based on address-space backing strategy:

1. **Class A — 32-Bit Fixed 4 GiB Window (`[G, G + 4 GiB)` in Host VA)**:
   - Established by [`../a32rt`](../a32rt) (`d84feb311a0a`, ~15.8k LOC) and replicated via copy-first (`src/rt32/`) in [`../i686rt`](../i686rt) (`2061d1c`).
   - Reserves a contiguous 4 GiB range `[G, G + 4 GiB)` in the translator's 64-bit host virtual address space (`G = 0` when `[0x10000, 4 GiB)` is free on native Linux; `G = 0x1_0000_0000` in offset mode under `hyper-linux`).
   - Holds `G` in reserved host callee-saved register `x20` (`xG`). Every 32-bit guest effective address is computed in a 32-bit `W` register (giving exact modulo-$2^{32}$ wraparound) and indexed via `[x20, wAddr, uxtw]` or `add xTmp, x20, wAddr, uxtw`.
   - Shares the `/dev/a32host` capability handshake ([`include/a32host.h`](include/a32host.h), `A32H_ABI 1.0/1.1`), `AT_EXECFD` handoff, and `hyper-linux`'s static-PIE two-phase loader (`*_prepare` / `*_finalize`).
   - **Applies to**: `a32rt` (`EM_ARM`), `i686rt` (`EM_386`), `mips32rt` (`EM_MIPS` O32), `ppc32rt` (`EM_PPC` classic + e500v2 SPE), and `sparc32rt` (`EM_SPARC` V8 / LEON).

2. **Class B — Checked Sparse Software Radix Address Space (`rv_space`) & Family Coordination**:
   - Established by [`../rvrt`](../rvrt) (`c1f5caa`).
   - Strictly separates **Guest VA (`uint64_t`)**, **Translator VA (`uint8_t *`)**, and **Host GPA** via a 4 KiB-granularity software radix page table (`src/memory/space.c`). Never forces a 64-bit guest into a 4 GiB window; also supports 32-bit pointer profiles (`RV32GC` with `va_bits = 32`, `MIPS64 N32` with `TASK_SIZE = 0x7fff8000`) inside the same checked family-memory architecture.
   - Coordinates multi-thread and multi-process state across `fork`, `clone(CLONE_VM)`, `vfork`, and same-PID `execve` through a private `.rvrt-family-<pid>-<seq>` directory (`family_lock`, `family_state`, `family_shmem`, `family_file`, canonical `family_mm` snapshots, `rv_file_caps` SCM rights broker, deterministic FIFO turn scheduler, and `safe_syscall_a64.S`).
   - Integrates with `hyper-linux` via `HL_MEMORY_POLICY_RVRT` (1 GiB disjoint `MAP_SHARED` GPA arena, SHA-256 runtime digest across `fork`/`execve`, separate `--cache-authority`, `--file-identity`, and `--family-authority` policies, and the `build/rvrt-*` host broker suite).
   - **Applies to**: `rvrt` (`EM_RISCV` RV64GC & RV32GC), `loongarch64rt` (`EM_LOONGARCH` LA64), `ppc64rt` (`EM_PPC64` `ppc64le` ELFv2), `mips64rt` (`EM_MIPS` N64/N32), and `sparc64rt` (`EM_SPARCV9` SPARC V9).

---

### 0.2 Verified State & Open Items in Existing Repositories `[F]`

Full audit details are recorded in [`lode/STATE-OF-PLAY-2026-10-23.md`](lode/STATE-OF-PLAY-2026-10-23.md). Summary of actionable gaps in existing trees:

1. **`../a32rt` (`HEAD` `d84feb311a0a`, tag `v0.1.0`)**:
   - Milestones `M0`–`M8` (`make test-all-lima`, `make test-all-hl`) pass on Linux (`lima`) and `hyper-linux`.
   - **4 open code defects in `a32rt/DEFECTS.md`**:
     - `D16` (`src/decode_a32.c:284-289`): Conditional `MOV Rd, Rm` `CSEL` fast path masks with `0x0FE00FF0U`, ignoring bit 20 (`S` bit `0x00100000U`), so conditional `MOVS Rd, Rm` (`cond != AL`, `S=1`, shift=0) skips updating `NZCV`. Fix: mask with `0x0FF00FF0U`.
     - `D17` (`src/decode_a32.c:1014`): A32 data-processing writes to `PC` (`Rd == 15`, `S == 0`) pass `is_bx = false` to `a64_emit_exit_branch_reg`, failing to switch to Thumb mode when bit 0 is 1 (`ALUWritePC` interworking). Fix: pass `is_bx = true`.
     - `D18` (`src/main.c:205-211`): `a32rt` and `hyper-linux/src/a32.c:323` currently disagree on whether `--` is followed by `<TARGET_PATH> <GUEST_ARGV0>` or `<GUEST_ARGV0>` when `AT_EXECFD` is present. Fix via coordinated Wave 1 consumer-first protocol (§2.1 & `docs/HOST-CONTRACT.md` §3.1): first land `--execfn <PATH>` and `--image-fd <FD>` support in `a32rt/src/main.c` (`L-A32-2`) and `i686rt/src/main.c` (`L-I686-3`), detecting `AT_EXECFD` via `errno = 0; getauxval(AT_EXECFD)` so `AT_EXECFD == 0` is valid, and then update `hyper-linux/src/a32.c` and `src/i686.c` (`L-HL-1`) to pass `--execfn <PATH> -- <GUEST_ARGV0> ...`.
     - `D19` (`src/vm.c:778-779, 853-854`): `a32_vm_mremap` replaces grown/moved `MAP_SHARED` file mappings with `A32_MAP_ANONYMOUS` + `memcpy`, severing file writeback. Fix requires both: (a) `a32rt/src/vm.c` preserving file backing across in-window `mremap` (restoring `PROT_NONE` on vacated ranges and preserving `PROT_NONE` reservations on failure), and (b) `hyper-linux/src/syscall.c:3204` (`hl_sys_mremap`) supporting file-backed grow/move instead of returning `-ENOSYS`.
   - **15 doc/comment sync items (`D1`–`D15`)**: 4 comment edits are uncommitted in the working tree (`src/decode_a32.c`, `tests/test_m{3,4,5}_*.c`); `README.md`, `AGENTS.md`, and `A32RT.md` need alignment (`A32_AOT_VERSION = 8`, FNV-1a cache naming, `AT_PLATFORM = "v8l"`, remove `src/start.S` reference).

2. **`../i686rt` (`HEAD` `2061d1c`, updated from `11cc65c`)**:
   - Phases `E`, `0`–`8` (`RC5` x87/SSE2, `RC6` `hl`, `RC7`/`RC7b` `wine` under `interp`, `RC8` `vm86`), `H1` (`4f4e597`/`b30698e` SMC protection + `test_h1_smc`), `H2`, `H3`, and `H4` (`705123e`/`dae2c79` `x86_64-linux` interpreter-only build) are committed on `master`.
   - **Open Campaign Defects `C1`–`C12` (`i686rt/DEFECTS.md:1015-1165`, `GOAL-DEFECTS.md`)**:
     - `C1` (8 syscall groups / 10 syscall numbers blocking LTP `SAFE_*` setup and `libc-test`): `_llseek(140)`, `msync(144)`, `readv(145)`, `truncate64(193)` / `ftruncate64(194)`, `tkill(238)`, `sched_setaffinity(241)` / `sched_getaffinity(242)`, `set_robust_list(311)` / `get_robust_list(312)`, `statx(383)`.
     - `C2` (19 `libc-test` pthread cancel/cond/robust/once timeouts), `C3` (`wine` chain under `I686RT_ENGINE=dbt`), `C4` (`x87_80.c` `round_pack80` directed-mode deep-tiny), `C5` (`MOVDQA` alignment `#GP(0)` in DBT vs SPEC ratification), `C6` (CoreMark DBT 23 iter/s vs interp 71 iter/s — requires 6-step instrumentation-first performance loop on identical Lima substrate), `C7` (SMC dead-marked block reclamation), `C8` (upstream `hyper-linux` `guest_env` ordering before `finalize`), `C9` (`winevdm` stderr diagnosis), `C10` (formal dynamic-glibc 2.44 RC4 rerun), `C11` (`--x87-80` math measurement), `C12` (quarantine stash + `D1`–`D74` audit reconciliation).
   - **High-Impact Audit Ledger Defects (`D1`–`D74` in `i686rt/DEFECTS.md:1-1012`)**:
     - **DBT TSO & Unaligned Safety (`D5`, `D6`, `D17`)**: `i686_emit_begin` (`src/dbt/emit_exit.c:38`) leaves `e->tso = false`, and only `emit_alu.c` checks `e->tso`. Furthermore, baseline AArch64 `LDAR`/`STLR` faults (`SIGBUS`) on unaligned 16/32-bit x86 accesses, and gating `e->tso` on `num_threads > 1` leaves pre-`clone` cached blocks unordered once threads or `MAP_SHARED` mappings exist. Therefore, software TSO is enabled unconditionally by default (`e->tso = !ctx->hw_tso && !ctx->no_tso`, flushing the DBT cache on any mode transition) and emits normal unaligned-capable `LDR`/`STR` paired with `DMB ISHLD`/`DMB ISH` fences across all memory emitters (`emit_alu.c`, `emit_mov.c`, `emit_stack.c`, `emit_str.c`, `emit_branch.c`, `emit_sse.c`).
     - **Signal Frame Alignment, `_fpstate_32` Wire Layout, & Authoritative Legacy x87 Restore (`D34`, `D37` + UAPI layout bug)**:
       1. In `src/os/signals_i386.c`, align handler `sp` via `sp = ((sp + 4U) & ~15U) - 4U` (giving `sp % 16 == 12`, NOT `((sp - 4) & 15) == 0`).
       2. In `src/os/sigframe_i386.h` and `src/os/signals_i386.c`, fix `i686_fpstate_32_t` to match Linux `arch/x86/include/uapi/asm/sigcontext.h`: `0x00..0x1b` legacy FPU env (`cw, sw, tag, ipoff, cssel, dataoff, datasel`), `0x1c..0x6b` `_st[8]` (80 B, authoritative 8 × 10-byte x87 stack), `0x6c` `uint16_t status; uint16_t magic;` (`status = sw`, `magic = 0x0000` for pure FXSR), `0x70` `_fxsr_env[6]` (24 B), `0x88` `mxcsr` + `mxcsr_mask` (8 B), **`0x90` `_fxsr_st[8]` (128 B)**, **`0x110` `_xmm[8]` (128 B)**, `0x190` `padding1[44]` (176 B), `0x240` `sw_reserved[12]` (48 B, zeroed in pure FXSR mode when no XSAVE tail is appended), total `624 B`. On `sigreturn`/`rt_sigreturn`, restore x87 state (`cw`, `sw`, `tag`, `_st[0..7]`) from the **authoritative legacy 108-byte `i387_fsave_struct` region (`0x00..0x6b`)** while restoring `_xmm[0..7]` and `mxcsr` from the FXSR region (`0x88..0x18f`), matching Linux `arch/x86/kernel/fpu/signal.c`.
     - **Decoder Default Segment (`D14` in `src/x86/decode.c`)**: `ea_default_seg` must return `I686_SEG_SS` when `modrm_mod == 0` and 32-bit SIB base is `4` (`ESP`, `rm == 4`) or 16-bit `rm` is `2` or `3` (`[bp+si]`, `[bp+di]`).
     - **OS & x87/SSE Defects**: `D13` (`moffs` `A0–A3` uses `pfx_addrsize`, not `pfx_opsize`), `D23` (`AT_EXECFD` consumption + `--execfn`/`--image-fd`), `D26` (`exec_path` copy), `D27` (`fchmodat` flags), `D28` (`--x87-64` priority), `D31` (`set_tid_address` return TID), `D41` (`settimeofday`), `D43` (`getdents64` 64-bit `d_off`), `D47` (`O_DIRECTORY` in `i686_oflags_h2g`), `D52` (`openat` low-VA guard), `D53` (`statfs` `-EOVERFLOW`), and `D57`–`D72` (`h_sse.c`, `x87.c`, `h_x87.c`).

3. **`../rvrt` (`HEAD` `c1f5caa`, updated from `884ae73`)**:
   - **RV64GC Qualification Scope (`docs/SUPPORT.md`)**: `rvrt` has qualified bounded checkpoints (focused RV64 fixtures, bounded 1–2 block & `PT_INTERP` entry AOT caching `test-aot-multiblock` / `test-aot-dynamic`, single-worker `RLIMIT_FSIZE=0` SysV slice `test-fsize-hard0-linux`, and internal `runtime-file-attributed-linux` MM/clone slice). Explicit remaining RV64 work:
     1. Cut over public `rvrt-linux-aarch64` to the canonical MM/source-family path once all exclusions in `docs/SUPPORT.md` (multi-worker file `mmap`, `CLONE_SIGHAND`/`CLONE_THREAD` during pending `vfork`, `RLIMIT_FSIZE=0` process/fork/thread and `-hl` 65,536-row fragments, and normal-policy `HL_MEMORY_POLICY_RVRT` fork gate) are closed;
     2. Expand `src/jit/a64.c` and `src/aot/` to general multi-block and DSO translations;
     3. Pass the finite application suite in `docs/IMPLEMENTATION-PLAN.md` (BusyBox child-process pipelines/redirection/exec + C/C++17 helper matrix).
   - **Exact `rvrt/DEFECTS.md` Ledger (`D1`–`D35` at `25e9de64` — 18 correctness IDs, 4 doc IDs, 13 comment IDs = 35 total)**:
     - Note on **`D1` (`src/linux/file.c`)**: For nonnegative `pos >= 0`, Linux `ksys_pread64`/`ksys_pwrite64` calls `fdget(fd)` (`FMODE_PATH` filter) *before* checking `FMODE_PREAD`/`FMODE_PWRITE`, returning `-EBADF` (`9`) on `O_PATH` descriptors. `rvrt`'s existing `pos < 0 -> EINVAL`, `path_descriptor -> EBADF` order is already Linux-accurate; `D1` is closed by adding a native-Linux/QEMU oracle regression test asserting `-EBADF` for `pread64`/`pwrite64` on `O_PATH` with `pos >= 0` (do NOT change it to `-ESPIPE`!).
     - Fix the remaining 17 correctness entries (`D2` in `src/linux/file.c`; `D8` in `src/linux/poll.c`; `D9` in `src/linux/metadata.c`; `D10` in `src/linux/signal.c`; `D13` in `vendor/softfloat/source/include/internals.h` `isNaNBF16UI`; `D15` in `src/runtime/scheduler.c`; `D16` in `src/runtime/family_wait.c`; `D17` in `src/runtime/family.c`; `D20` in `test/musl_heap_tls.c`; `D21, D22` in `test/test_fork_*.py`; `D23` in `nix/rv32-glibc-target-libraries.nix`; `D24` in `src/linux/exec_args.c`; `D26` in `src/runtime/native_signal.c`; `D28` in `test/r5_exec.c`; `D34` in `src/runtime/family_file_index.c`; `D35` in `src/runtime/guest_memory.c`), 4 doc entries (`D3, D4` in `docs/HOST-CONTRACT.md`; `D5, D6` in `README.md`), and 13 comment entries (`D7, D11, D12, D14, D18, D19, D25, D27, D29–D33`).
   - **RV32GC (`Milestone R8`)**: Implement full RV32GC (`rv32imafdc` / `ILP32D`) runtime execution in `rvrt-linux-aarch64` (see §3).

4. **`../hyper-linux` (`HEAD` `fb879f088d63`)**:
   - **Rebase & Land `lane/6-l6a` (`../i686rt-l6a` @ `6352d84`)**: Merge `src/translator.h` (`hl_translators[]` with masked `e_flags` predicates) and `src/i686.c` onto `master`, fixing `D185`, `D187`–`D191`, `i686rt` `C8` (`guest_env` ordering in `src/hl.c`), and file-backed `mremap` in `src/syscall.c:3204` (`a32rt` `D19`).
   - **Audit, Fix & Merge the 43-Worktree `build/rvrt-*` Broker Stack (`build/rvrt-shm-stat-rmid` @ `67afb8a`, `hl/rvrt-m1-broker` @ `bc8b136`)**: Audit and resolve the **13 Round-17 defect IDs** (`D211–D213` and `D249–D258`, plus `D201` on `master`) against the candidate tip (`bc8b136`/`67afb8a`, noting `src/vfs.c` already updated the older FIFO read implementation cited in `D211`), and merge onto `master`.
   - **Android Slice C Dynamic Bionic32 Linker Fix**: Fix `D218` (`rseq` 32-bit signature check) and resolve the Bionic32 `/system/bin/linker` `mprotect` / `tgkill` abort.

---

## 1. Series-Wide Key Design Decisions (`D1`–`D11`)

| # | Decision | Rationale |
|---|---|---|
| **D1** | **Language, Toolchain & Binary Format**: Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic -Os -fPIE`) + minimal AArch64 `.S` assembly, linked with `aarch64-unknown-linux-musl-gcc -static-pie -Wl,-z,max-page-size=4096`. Zero dependencies beyond static musl libc. `x18` is permanently reserved on AArch64. | Proven in `a32rt`, `i686rt`, and `rvrt`; runs identically on native AArch64 Linux and `hyper-linux`. |
| **D2** | **Two Address-Space Classes & Per-Profile `TASK_SIZE`**: Class A (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`) uses a fixed 4 GiB host window `[G, G + 4 GiB)` (`[x20, wAddr, uxtw]`). Class B (`rvrt` RV64 & RV32, `loongarch64rt`, `ppc64rt`, `mips64rt` N64 & N32, `sparc64rt`) uses `rv_space` checked sparse 4 KiB radix page tables with per-profile `TASK_SIZE` (`exclusive_limit`: conservative `0x7fff8000` for MIPS O32/N32, `4 GiB` for RV32, `1 TiB` `1ULL<<40` for MIPS64 N64, `128 TiB` `1ULL<<47` for RV64/LA64/PPC64/SPARC64) and profile-specific stack/mmap/interp/sigtramp addresses below `exclusive_limit`. | Separates ISA width, user `TASK_SIZE`, and backing strategy (`lode/ISA-TRAP-AND-ABI-MATRIX.md` §1). |
| **D3** | **Copy-First Substrate Reuse (`src/rt32/` and `src/rt64/`)**: Each new Class-A repo copies `src/rt32/` from `i686rt`/`a32rt` (with D18/D19 fixes applied); each new Class-B repo copies `rvrt`'s `src/{memory,runtime,linux,aot}/` into `src/rt64/{memory,runtime,linux,aot}/` using the explicit Phase 0 copy map and adaptation seam contract in §5.0 (splitting `runtime_main.c` and `signal.c` into `< 900 LOC` modules at Phase 0). **No shared library is extracted across repositories.** | Keeps every translator repository standalone, self-contained, and independently buildable without cross-repo API churn. |
| **D4** | **Dual Engines (`interp` + `dbt`) with Single-Step Fallback & Independent QEMU Oracle**: Every new translator implements a portable C11 interpreter (`src/interp/`) and an AArch64 DBT (`src/dbt/`). Any instruction declined by the DBT emits `EXIT_UNDEF`, interprets one instruction via `interp_step(ctx)`, and resumes DBT execution. Because `interp` and `dbt` can share an ABI or semantic bug, every phase gate ALSO validates against an independent `qemu-<arch>` / Linux oracle. | Eliminates "unimplemented opcode in JIT" crashes while preventing shared-bug blind spots. |
| **D5** | **Big-Endian Guest Memory & ELF Lowering (`mips32rt` BE, `ppc32rt`, `sparc32rt`, `mips64rt` BE, `sparc64rt`)**: Guest memory bytes are stored in **guest-native (big-endian) byte order** in RAM. Byte accesses (`ldrb`/`strb`, `read`/`write` syscalls, string ops) require zero conversion. 16/32/64-bit memory accesses in the interpreter use `__builtin_bswap{16,32,64}`, and in the AArch64 DBT emit `LDR` followed by `REV16`/`REV32`/`REV64` (or `REV*` followed by `STR` on stores). | Ensures `read()`, `write()`, `mmap()`, string literals, and byte-level pointer aliasing work transparently without page-granularity endianness tracking. |
| **D6** | **Delay-Slot & Annul State Machine + Page-Boundary Progress Rule (`mips32rt`, `mips64rt`, `sparc32rt`, `sparc64rt`)**: The CPU context maintains explicit `(pc, npc)` (and internal `in_delay_slot` / `branch_taken` flags). In the interpreter, every step advances `pc = npc; npc = next_npc`, and an annulled branch (`BEQL` not taken on MIPS; `Bicc,a` not taken or `BA,a` on SPARC) skips fetching the delay-slot instruction so an unmapped page immediately after an annulled branch never faults. In the DBT, a branch and its delay-slot instruction are translated together as an indivisible pair when both lie on the same page; if a block encounters a branch at `(pc & 0xfff) == 0xffc` after prior instructions, it ends the block before `pc`, and if a block *starts* at `(pc & 0xfff) == 0xffc`, it emits `EXIT_SINGLE_STEP` (`interp_step`) to guarantee forward progress across the page boundary. On synchronous faults or signals inside a delay slot, MIPS records `sc_pc = branch_pc` (`pc - 4`, keeping `in_delay_slot` internal), while SPARC records `(pc, npc)` in `pt_regs`. | Prevents control-flow corruption, infinite re-entry loops at page-final branches, and spurious page faults on annulled delay slots. |
| **D7** | **Syscall Error Polarity Adapters**: AArch64 Linux syscalls return `-errno` in `x0` (`(uint64_t)ret >= (uint64_t)-4095LL`). Each guest OS layer translates this into the guest's exact kernel ABI: `-errno` in `a0`/`r0`/`eax` (ARM, x86, RISC-V, LoongArch, PPC64 `scv 0`); `$a3 = 1, $v0 = +errno` (MIPS O32/N32/N64); `CR0.SO = 1, r3 = +errno` (PowerPC 32/64 `sc`); `PSR.icc.C = 1, %o0 = +errno` (SPARC V8 `ta 0x10`); **both `CCR.icc.C = 1` and `CCR.xcc.C = 1`, `%o0 = +errno`** (SPARC V9 `ta 0x6d`). | Syscall error signaling is the #1 subtle ABI divergence across non-x86 Linux architectures (`lode/ISA-TRAP-AND-ABI-MATRIX.md` §3). |
| **D8** | **Guest Errno / Signal Number / Socket / Open-Flag Translation Tables & MIPS 128-Signal Namespace**: MIPS and SPARC define architecture-specific constants for `errno`, signals (`SIGEMT=7, SIGBUS=10, SIGSYS=12, SIGUSR1=16...` on MIPS — full 1..128 table with guest-owned 128-entry action/pending/RT-queue tables, never a 64-signal clamp or identity prefix!), socket types (`SOCK_STREAM=2`, `SOCK_DGRAM=1` on MIPS; `SOL_SOCKET=0xffff` on MIPS/SPARC), and `open()`/`fcntl()` flags. Every translator generates compile-time verified translation tables from pinned Linux `arch/<arch>/include/uapi/asm/{errno,signal,socket,fcntl,ioctls,stat}.h` headers. | Passing host AArch64 constants unmapped to a MIPS or SPARC guest silently breaks `wait4`, `kill`, `socket()`, `setsockopt()`, `stat64`, and `fcntl()`. |
| **D9** | **Memory Ordering & Unaligned-Safe TSO**: TSO guests (`i686rt`, `sparc32rt`, `sparc64rt`) emit software memory ordering by default (`LDR`/`STR` paired with `DMB ISHLD`/`DMB ISH` for unaligned-capable x86 accesses across all memory emitters, flushing the DBT cache on any TSO mode change; never unguarded `LDAR`/`STLR` on potentially unaligned 16/32-bit addresses!) and elide barriers only when `A32H_CAP_HW_TSO` (Class A) or `--hw-tso` (Class B) confirms hardware TSO is active and readback-verified across all vCPUs (`hl.c`, `thread.c`, `fork_ipc.c`). | Prevents AArch64 Alignment Faults (`SIGBUS`), unordered pre-`clone` cached blocks, and TSO violations across threads and forks. |
| **D10** | **Phase E Experiment & Ordering Gate (FPU/SIMD Before Dynamic Libc, Feature Advertising Tracks Implementation)**: Every new translator begins with a parallel **Phase E** (`experiments/E01..E06/FINDINGS.md`) verifying UAPI struct sizes/offsets and QEMU oracle execution. **Phase 3 implements FPU & SIMD before Phase 4 (Signals) and Phase 5 (Dynamic `PT_INTERP` `musl`/`glibc`)**, and `AT_HWCAP`/`CPUCFG` are derived from the currently implemented feature profile (integer-only in Phase 2; full FPU/SIMD from Phase 3 onward). | Prevents dynamic `glibc`/`musl` `ld.so` or static feature-probing binaries from executing unimplemented FPU/SIMD instructions. |
| **D11** | **Three-Layer Page-Size Policy (`4 KiB` Guest ABI, `4 KiB` Stage-1/Radix Page Table, `16 KiB` Darwin Backing, `64 KiB` ELF Alignment)**: All translators report `AT_PAGESZ = 4096`, enforce Linux per-syscall alignment/rounding rules (`mmap`/`mprotect`/`munmap`/`mremap` reject unaligned addresses with `-EINVAL`, `brk` keeps a byte-granular logical break), and enforce 4 KiB page permissions (`rv_space` in Class B; 4 KiB guest stage-1 page tables in `hyper-linux/src/guest.c:60` in Class A). 64 KiB-aligned `ppc64le` ELFs (`p_align = 0x10000`) load cleanly onto 4 KiB pages. | Decouples guest ABI page size from Darwin's 16 KiB host backing and IBM Power's 64 KiB linker alignment. |

---

## 2. Wave 1 Specification — Closeout of Existing Runtimes & `hyper-linux` Integration

### 2.1 Workstream W1A: `../a32rt` Defect Remediation & Doc Sync
1. **Fix `D16` (`src/decode_a32.c:284-289`)**:
   - Change `if (cond != 0xEU && (insn & 0x0FE00FF0U) == 0x01A00000U)` to `if (cond != 0xEU && (insn & 0x0FF00FF0U) == 0x01A00000U)` so bit 20 (`S == 0`) is required for the branchless `CSEL` fast path.
   - Add regression test in `tests/test_m1_isa_fs.c`: verify `moveqs r0, r1` with `r1 = 0` sets `CPSR.Z = 1` when `EQ` holds and preserves flags when `EQ` is false.
2. **Fix `D17` (`src/decode_a32.c:1014`)**:
   - In `decode_a32_dp`, when `rd == 15 && !s_bit`, call `a64_emit_exit_branch_reg(b, A64_TMP0, true)` (`is_bx = true`) so bit 0 of the computed target switches between A32 and Thumb mode (`ALUWritePC`).
   - Add regression test in `tests/test_m1_isa_fs.c`: A32 `mov pc, r0` and `add pc, r0, #0` jumping to a Thumb function (`target | 1`) and returning.
3. **Fix `D18` (`src/main.c:180-215`) Before `hyper-linux/src/a32.c` (`L-HL-1`)**:
   - Add `--execfn <PATH>`, `--image-fd <FD>`, `--rootfs <DIR>` (alias for `--sysroot`), and `--no-host` options to `a32rt/src/main.c`, and detect `AT_EXECFD` via `errno = 0; unsigned long fd = getauxval(AT_EXECFD); if (errno == 0) exec_fd = (int)fd;` (so `AT_EXECFD == 0` is handled validly).
   - When `--execfn <PATH>` is supplied, use `<PATH>` as `exec_path` and treat all arguments after `--` as `guest_argv[0..]` (preserving custom `argv[0]`, zero/one/multiple args, and backward compatibility with `a32rt -- ./guest_bin arg1` when `--execfn` is omitted).
4. **Fix `D19` (`src/vm.c:770-865`) & `hyper-linux/src/syscall.c:3204`**:
   - Track `{backing_fd, file_offset, map_flags}` on VMAs in `a32rt/src/vm.c`. On `a32_vm_mremap` grow/move of a file-backed `MAP_SHARED` VMA, allocate the destination range inside `[G, G + 4 GiB)`, invoke host `mremap(..., MREMAP_MAYMOVE | MREMAP_FIXED, G + new_addr)` (or remap from the dup'd backing fd at `file_offset`), restore `PROT_NONE` on the vacated window range on success, and preserve `PROT_NONE` on failure.
   - In `hyper-linux/src/syscall.c:3204` (`L-HL-2`), implement file-backed `mremap` grow/relocation so `MAP_SHARED` file writeback works on both `make test-m5-lima` and `make test-m5-hl`.
5. **Sync `D1`–`D15` Documentation, Comments & `include/a32host.h`**:
   - Commit the 4 working-tree comment fixes (`src/decode_a32.c`, `tests/test_m{3,4,5}_*.c`), sync `include/a32host.h` (`A32H_CAP_HW_TSO`) with `../hyper-linux/src/a32host.h`, update `README.md`, `AGENTS.md`, and `A32RT.md`, and verify `make build tests check-headers test-hello-hl test-hello-lima test-m1-hl test-m1-lima test-m5-hl test-m5-lima`.

### 2.2 Workstream W1B: `../i686rt` Campaign (`C1`–`C12`) & Audit Defect (`D1`–`D74`) Closeout
*(Note: `H1` (`4f4e597`/`b30698e`) and `H4` (`705123e`/`dae2c79`) are already committed on `i686rt/master` at `2061d1c`.)*
1. **Close Open Campaign Items `C1`–`C12` (`i686rt/DEFECTS.md:1015-1165`)**:
   - **10 Syscall Numbers in 8 `C1` Groups (`L-C1a` & `L-C1b`)**:
     - `L-C1a` (`src/os/sys_pass.c`, `src/os/sys_stat.c`): `_llseek(140)`, `msync(144)`, `readv(145)`, `truncate64(193)` / `ftruncate64(194)`, `statx(383)`.
     - `L-C1b` (`src/os/sys_pass.c`, `src/os/clone.c`): `tkill(238)`, `sched_setaffinity(241)` / `sched_getaffinity(242)`, `set_robust_list(311)` / `get_robust_list(312)`.
   - **Pthread Timeouts (`L-C2`)**: After `L-C1b` merges, diagnose and fix the 19 `libc-test` pthread cancel/cond/robust/once timeouts in `src/os/sys_pass.c` (`sys_futex`), `src/os/clone.c`, and `src/os/threads.h`.
   - **DBT Wine Verification (`L-C3`), `x87_80` Deep-Tiny (`L-C4`), `MOVDQA` Alignment (`C5`), SMC Reclamation (`L-C7`), `winevdm` (`L-C9`), Dynamic Glibc 2.44 RC4 (`L-C10`), `--x87-80` Math Table (`L-C11`), Stash Reconciliation (`L-C12`)**.
   - **6-Step DBT Performance Pass (`L-C6a` / `L-C6b`)**:
     1. Add default-off (`I686RT_PERF_STATS=1`) `cntvct_el0` per-phase timing counters in `src/dbt/engine.c` and `src/trampoline.S` (translation vs IBTC dispatch vs A64 code execution vs flag sync vs helper/undef exits);
     2. Commit the instrumentation;
     3. Measure baseline on pinned `limactl` AArch64 VM (`limactl shell default`) with pinned CoreMark binary, seed, and warm-up;
     4. Record the measured bottleneck hypothesis based on the cycle split;
     5. Conditionally apply the optimizations confirmed by the profile (`L-C6a` block-local dead-flag elimination in `src/dbt/flags_dbt.c`, `src/dbt/translate.c` and/or `L-C6b` IBTC direct block linking in `src/dbt/engine.c`, `src/trampoline.S`, or whichever bottleneck the counters identify);
     6. Re-measure on the **exact same `limactl` AArch64 VM and CoreMark configuration** (never mixing Lima and Docker substrates), confirm or retract the hypothesis in `tests/hardening/h3-coremark.md`, and machine-assert `dbt_iter_s > interp_iter_s` with valid CoreMark CRCs.
2. **Fix High-Impact Audit Ledger Defects (`D5/D6/D17`, `D13`, `D14`, `D23`, `D26..D72`)**:
   - **Unaligned-Safe DBT TSO (`src/dbt/emit_exit.c`, `emit_alu.c`, `emit_mov.c`, `emit_stack.c`, `emit_str.c`, `emit_branch.c`, `emit_sse.c`)**: Enable software TSO unconditionally by default (`e->tso = !ctx->no_tso && !(ctx->has_host_info && (ctx->host_info.caps & A32H_CAP_HW_TSO))`) in `i686_emit_begin` (`src/dbt/emit_exit.c:38`), and flush the DBT code cache if `tso` mode ever changes (so pre-`clone` translations are never left unordered when sharing begins!). When `e->tso` is true, emit unaligned-capable `LDR`/`STR` paired with `DMB ISHLD` after loads and `DMB ISH` around stores across `emit_alu.c`, `emit_mov.c`, `emit_stack.c`, `emit_str.c`, `emit_branch.c`, and `emit_sse.c` (never unguarded `LDAR`/`STLR` on 16/32-bit x86 effective addresses!).
   - **Signal Frame Alignment, `_fpstate_32` Layout, & Authoritative Legacy x87 Restore (`src/os/sigframe_i386.h`, `src/os/signals_i386.c`)**:
     - Fix `D37`: Align `sp` via `sp = ((sp + 4U) & ~15U) - 4U` (`sp % 16 == 12`).
     - Fix `D34` & `_fpstate_32` UAPI layout: Add `uint16_t status; uint16_t magic;` at `0x6c` (`status = sw, magic = 0x0000`), `uint8_t _fxsr_st[128]` at `0x90`, move `xmm_space[32]` (`_xmm[8]`) to **`0x110`**, and reduce `__pad1` from `304` to `176` bytes (`padding1[44]` at `0x190..0x23f`, leaving `sw_reserved` at `0x240` zeroed in pure FXSR mode and total size `624 B`). On signal delivery, populate both the legacy 80-byte `_st[8]` (`0x1c..0x6b`) and 128-byte `_fxsr_st[8]` (`0x90..0x10f`) without clobbering `mxcsr`. On `sigreturn`/`rt_sigreturn`, restore x87 state (`cw, sw, tag, _st[0..7]`) from the **authoritative legacy `0x00..0x6b` region** and restore `_xmm[0..7]` and `mxcsr` from `0x88..0x18f` (verified by a test that modifies `_st[0]` and `_fxsr_st[0]` to different values in a handler).
   - **Decoder `moffs` (`D13`) & `ea_default_seg` (`D14` in `src/x86/decode.c`)**: Use `out->pfx_addrsize ? 2U : 4U` for `A0–A3` `moffs`; return `I686_SEG_SS` when `addr_size == 4` and `(modrm_rm == 4 && sib_base == 4)` or `(modrm_rm == 4 && sib_base == 5 && modrm_mod != 0)` or `(modrm_rm == 5 && modrm_mod != 0)`, and when `addr_size == 2` and `modrm_rm == 2 || modrm_rm == 3 || (modrm_rm == 6 && modrm_mod != 0)`.
   - **OS, Header & x87/SSE Fixes**: Sync `include/a32host.h` (`L-I686-3`), add `--execfn`, `--image-fd`, `--sysroot`, `--stats`, `--no-host` and consume `AT_EXECFD=0` (`D23`), copy `exec_path` into `ctx->exec_path_buf` (`D26`), fix `D27`, `D28`, `D31`, `D41`, `D43`, `D47`, `D52`, `D53`, and `D57`–`D72` (`h_sse.c`, `x87.c`, `h_x87.c`).

### 2.3 Workstream W1C: `../rvrt` Defect Ledger Remediation (`D1`–`D35`), Canonical MM Cutover & Multi-Block JIT
1. **Resolve Pinned `rvrt/DEFECTS.md` Entries (`D1`–`D35` at `25e9de64`)**:
   - **Linux Syscall & Signal Layer (`L-RV64-1a`: `src/linux/file.c`, `poll.c`, `metadata.c`, `signal.c`, `exec_args.c`)**:
     - `D1` (`src/linux/file.c`): Preserve `-EBADF` (`failure(9)`) for `pread64`/`pwrite64` on `O_PATH` descriptors with `pos >= 0` (matching Linux `fdget()` in `fs/read_write.c`), add an oracle regression test confirming `-EBADF` for `pos >= 0` and `-EINVAL` for `pos < 0`, and close `D1` in `DEFECTS.md` as oracle-verified.
     - `D2` (`src/linux/file.c`), `D9` (`src/linux/metadata.c`), `D10` (`src/linux/signal.c`), `D24` (`src/linux/exec_args.c`): Split failed `rv_space_write` / `rv_space_read` / `read_pointer` returns on `rv_fault_is_runtime` (`-ENOMEM` = `12` vs `-EFAULT` = `14`).
     - `D8` (`src/linux/poll.c`): Validate `nfds` against `RV_FD_TABLE_LIMIT` (`1024`) per Linux `select` rules.
   - **Runtime, Family & SoftFloat Layer (`L-RV64-1b`: `vendor/softfloat/source/include/internals.h`, `src/runtime/scheduler.c`, `family_wait.c`, `family.c`, `native_signal.c`, `family_file_index.c`, `guest_memory.c`)**:
     - `D13` (`internals.h`): Fix `isNaNBF16UI` exponent mask from `0x7FC0` to `0x7F80` (`((~(a) & 0x7F80) == 0) && ((a) & 0x007F)`) so signaling BF16 NaNs with bit 6 clear are recognized as NaN.
     - `D15` (`scheduler.c`): In `rv_scheduler_wake`, check `quiesce_owner != ticket` before `suspended_push`, matching `release_turn`.
     - `D16` (`family_wait.c`): Set `errno = EINVAL` unconditionally on bad arguments in `rv_family_wait_table_commit`/`sweep`.
     - `D17` (`family.c`): Check `key_equal(control->log_key, control->log_second_key)` in `replay_committed` for `RV_LOG_WAIT_PAIR` (`EIO`).
     - `D26` (`native_signal.c`): Verify `installed.sa_flags` in `rv_native_signal_process_reset_child_policy`.
     - `D34` (`family_file_index.c`): Split `!metadata_page(&page)` (`errno = EIO`) from `page.content_generation == UINT64_MAX` (`errno = EOVERFLOW`) in `write_slot`.
     - `D35` (`guest_memory.c`): Check both `page_factory.context` and `managed.context` in `rv_guest_memory_exec_capture_clear_tids` and `rv_guest_memory_prepare_child_frozen`.
   - **Tests, Nix & Documentation (`L-RV64-1c`: `nix/rv32-glibc-target-libraries.nix`, `test/musl_heap_tls.c`, `test/test_fork_*.py`, `test/r5_exec.c`, `docs/HOST-CONTRACT.md`, `README.md`)**:
     - Fix `D20`, `D21`, `D22`, `D23` (`ln -s "${prefix}gcc" "$out/bin/cc"`), `D28`, and update `D3, D4, D5, D6` prose in `docs/HOST-CONTRACT.md` and `README.md`, plus commit the 13 working-tree comment fixes (`D7, D11, D12, D14, D18, D19, D25, D27, D29–D33`).
2. **Expand `rvrt` AArch64 JIT (`src/jit/a64.c`)**:
   - Extend `src/jit/a64.c` beyond straight-line 32-bit integer instructions to support expanded 16-bit `RVC` parcels (`pc + 2`), shifts, compares, `M`-extension multiply/divide, and checked load/store helpers.
3. **Worktree Inventory & Safe Triage**:
   - Generate a non-destructive inventory of all 278 `../rvrt-*` worktrees (`branch`, `head_sha`, `git cherry` equivalence to `master`, dirty/untracked count) before proposing any worktree pruning to the user.

### 2.4 Workstream W1D: `../hyper-linux` Translator Table, `/dev/a32host` Fixes, `mremap` & `build/rvrt-*` Broker Merge
*(Note: `L-HL-1` runs after `L-A32-2` and `L-I686-3` land `--execfn` support in `a32rt` and `i686rt`; `L-HL-3` runs in Sub-Wave `W1D.2` after `L-HL-1` and `L-HL-2` merge to `hyper-linux/master` so `src/hl.c` and `src/fork_ipc.c` have exclusive single-lane ownership.)*
1. **Class-A Loader, `/dev/a32host`, & `guest_env` Ordering (`L-HL-1` in `W1D.1`)**:
   - Fix `D185` (`src/device.c` `alias_fd`), `D187` (`/dev/a32host` `.fstat`), `D188`/`D189` (single-open pinned preload), `D190` & `i686rt` `C8` (inject `<RT>_WINDOW` into `guest_env` in `src/hl.c` before `hl_build_initial_stack()` and on `sys_execve`), and `D191` (`src/syscall_io.c`).
   - Rebase `lane/6-l6a` (`src/translator.h`, `src/i686.c`) onto `master` with masked `e_flags` predicates (`docs/HOST-CONTRACT.md` §6), emitting `--execfn <PATH> -- <GUEST_ARGV0> ...` to the updated `a32rt` and `i686rt` consumers.
2. **File-Backed `mremap` & Round-17 RVRT Broker Merge (`L-HL-2` in `W1D.1`)**:
   - Implement file-backed `MAP_SHARED` `mremap` grow/move in `src/syscall.c:3204` (`hl_sys_mremap`, unblocking `a32rt` `D19`).
   - Audit all **13 Round-17 defect IDs** (`D211–D213`, `D249–D258`, plus `D201`) against the candidate broker tip (`bc8b136` / `67afb8a`), apply all live fixes (`fork_ipc.c`, `syscall_net.c`, `syscall_fs.c`, `syscall_signal.c`, `syscall_poll.c`, `rvrt_fifo.c`), and merge the broker stack onto `master`.
3. **Android Slice C Dynamic Bionic32 Linker Fix & Hardware-TSO Lifecycle (`L-HL-3` in `W1D.2`, after `W1D.1` merges)**:
   - Fix `D218` (`src/syscall.c` 32-bit `rseq` signature check) and resolve the Bionic32 `/system/bin/linker` `mprotect` / `tgkill` abort so `make test-android-e2e-32` passes.
   - If hardware TSO (`A32H_CAP_HW_TSO`) is enabled on Apple Silicon, configure and readback-verify it across **all** vCPU creation paths (`src/hl.c`, `src/thread.c`, `src/fork_ipc.c`, and `execve`) and qualify with discriminating **Message-Passing (`MP`: `r0 == 1 && r1 == 0` forbidden)** and **Load-Buffering (`LB`)** litmus tests across initial, `pthread_create`, and `fork` workers; otherwise leave `A32H_CAP_HW_TSO` (`1ULL << 9`) clear.

---

## 3. Wave 2 Specification — `rvrt` Milestone R8: RV32GC (`rv32imafdc` / `ILP32D`) Qualification

`rt-series/README.md` lines 18 & 20 state:
> `RV32GC | 32 | rvrt, not qualified yet | Nuclei N300FD (rv32imafdc) | The embedded RISC-V profile already required in rvrt, with sysroots in tree. Objective: qualify guest execution there, so embedded RV32 userspace is covered by the same project.`

### 3.1 Profile, Address Space & Effective-Address Wrapping (`src/core/profile.h`, `src/core/cpu.h`)
- Enable `rv_profile_for_xlen(32)` in `src/core/profile.h`:
  - `name = "rv32gc-ilp32d"`, `xlen = 32`, `elf_class = ELFCLASS32 (1)`, `elf_float_abi = EF_RISCV_FLOAT_ABI_DOUBLE (0x4)`, `hwcap = 0x112d` (`I | M | A | F | D | C`).
- **32-Bit Effective-Address Wrapping vs. Checked Syscall Buffers**:
  - In `rv_cpu_t`, when `cpu->xlen == 32`, integer registers `cpu->x[0..31]` and `cpu->pc` hold zero-extended 32-bit values (`(uint64_t)(uint32_t)val`), while `cpu->f[0..31]` are 64-bit IEEE-754 registers (`D` extension in `ILP32D`, with 32-bit `F` values NaN-boxed in bits `63:32`).
  - **Critical Address Arithmetic Rule**: Every RV32 instruction that computes a memory effective address (`rs1 + imm` for integer loads/stores, `FLW`/`FSW`/`FLD`/`FSD`, `LR.W`/`SC.W`/`AMO*.W`) or control-flow target (`JAL`, `JALR`, conditional branches, `AUIPC`) MUST wrap the effective address modulo $2^{32}$ (`uint64_t ea = (uint32_t)(base + offset);`) **before** calling `rv_space_*` or recording a fault address (`stval` / `si_addr`)! Truncating a destination register after a 64-bit lookup is insufficient.
  - Conversely, **syscall buffer range validation** (`rv_space_read` / `rv_space_write`) takes a 32-bit base pointer `(uint32_t)arg` and length `len`, and MUST reject any `[ptr32, ptr32 + len)` range that overflows `0x100000000ULL` (`exclusive_limit`) with `-EFAULT` (never wrapping around to page `0`).

### 3.2 RV32GC Decoder & Interpreter (`src/core/compressed.c`, `src/core/decode.c`, `src/core/interp.c`, `src/core/fp.c`)
1. **Compressed Extension (`src/core/compressed.c`) — Parameterize `rv_expand_compressed(uint16_t parcel, unsigned int xlen, rv_decoded_insn_t *out)`**:
   - **Quadrant 0 (`00`)**:
     - `funct3 == 011`: On `xlen == 64`, `C.LD`; on `xlen == 32`, **`C.FLW`** using the standard CL word-offset encoding: `uimm[5:3] = inst[12:10]`, `uimm[2] = inst[6]`, `uimm[6] = inst[5]` (`uimm[6|5:3|2]`, scaled by 4, range `0..124` bytes; there is NO `uimm[7]`) `[F]`.
     - `funct3 == 111`: On `xlen == 64`, `C.SD`; on `xlen == 32`, **`C.FSW`** using the same `uimm[6|5:3|2]` word-offset encoding `[F]`.
   - **Quadrant 1 (`01`)**:
     - `funct3 == 001`: On `xlen == 64`, `C.ADDIW`; on `xlen == 32`, **`C.JAL`** (`jal x1, offset[11|4|9:8|10|6|7|3:1|5]`).
     - `funct3 == 100` (`C.SRLI`, `C.SRAI`): When `xlen == 32` and `shamt[5] == 1` (bit 12 == 1), return `false` (`RV_TRAP_ILLEGAL_INSTRUCTION`).
   - **Quadrant 2 (`10`)**:
     - `funct3 == 000` (`C.SLLI`): When `xlen == 32` and `shamt[5] == 1` (bit 12 == 1), return `false` (`RV_TRAP_ILLEGAL_INSTRUCTION`).
     - `funct3 == 011`: On `xlen == 64`, `C.LDSP`; on `xlen == 32`, **`C.FLWSP`** (`uimm[5] = inst[12]`, `uimm[4:2] = inst[6:4]`, `uimm[7:6] = inst[3:2]`, range `0..252`).
     - `funct3 == 111`: On `xlen == 64`, `C.SDSP`; on `xlen == 32`, **`C.FSWSP`** (`uimm[5:2] = inst[12:9]`, `uimm[7:6] = inst[8:7]`, range `0..252`).
2. **Base & Extension Interpreter (`src/core/interp.c`, `src/core/fp.c`)**:
   - When `cpu->xlen == 32`:
     - Wrap all effective addresses `(uint32_t)(rs1 + imm)` before memory access.
     - Trap all RV64-only opcodes with `RV_TRAP_ILLEGAL_INSTRUCTION`: `OP-IMM-32` (`0x1b`), `OP-32` (`0x3b`), `LD`, `LWU`, `SD`, `LR.D`, `SC.D`, `AMO*.D`, `FCVT.L.S`, `FCVT.LU.S`, `FCVT.S.L`, `FCVT.S.LU`, `FCVT.L.D`, `FCVT.LU.D`, `FCVT.D.L`, `FCVT.D.LU`, `FMV.X.D`, `FMV.D.X`.
     - Shift amounts in `SLLI`, `SRLI`, `SRAI` with `shamt[5] == 1` trap with `RV_TRAP_ILLEGAL_INSTRUCTION`; register shifts (`SLL`, `SRL`, `SRA`) mask `rs2` with `0x1f`.
     - Signed comparisons (`SLT`, `SLTI`, `BLT`, `BGE`), signed division (`DIV`, `REM`, overflow at `INT32_MIN / -1`), and `MULH`/`MULHSU`/`MULHU` operate on 32-bit `int32_t` / `uint32_t` operands.
     - **Counter CSR Policy (`Zicntr` read via `Zicsr`)**: `rvrt` does not expose a vDSO `clock_gettime` and reports `TIME_CSR_FREQ = 0` in `riscv_hwprobe`, so `musl` and `glibc` call `SYS_clock_gettime64` (403) directly without executing `rdtime`/`rdtimeh`. Direct execution of `rdcycle[h]` (`0xc00`/`0xc80`), `rdtime[h]` (`0xc01`/`0xc81`), or `rdinstret[h]` (`0xc02`/`0xc82`) raises `SIGILL` (`ILL_ILLOPC`), matching `rvrt`'s deterministic RV64 policy.

### 3.3 ELF32 Loader & 32-Bit Stack / Auxv (`src/loader/image.c`, `src/loader/stack.c`)
- Extend `src/loader/image.c` to load both `ELFCLASS64` and `ELFCLASS32` when `e_machine == EM_RISCV` and `(e_flags & EF_RISCV_FLOAT_ABI) == EF_RISCV_FLOAT_ABI_DOUBLE`.
- Default PIE load bias for `ELFCLASS32` `ET_DYN`: `0x00400000`; `PT_INTERP` load bias: `0x3f000000`; stack top: `0x7fff0000`; VMA unhinted `mmap` top: `0x3f000000`; dedicated read-exec signal return trampoline page (`li a7, 139; ecall`): **`0x7fff1000`** (inside `< 4 GiB` user space, replacing `linux/signal.c`'s hardcoded `> 1 TiB` address when `xlen == 32`!).
- Extend `src/loader/stack.c` and `src/linux/exec_args.c` (`read_pointer` reading 4-byte pointers when `xlen == 32`): serialize `argc`, `argv[]`, `envp[]`, and `Elf32_Auxv_t` (`{uint32_t a_type, uint32_t a_val}`) as 4-byte little-endian words with 16-byte stack alignment (`SP % 16 == 0`).

### 3.4 RV32 Linux UAPI v6.18 Syscall, Compound Struct & Signal Frame ABI (`src/linux/`, `src/runtime/`)
1. **Pinned Linux v6.18 RV32 Syscall Table & Register Pairs**:
   - Pinned to Linux v6.18 `arch/riscv/kernel/Makefile.syscalls` + `scripts/syscall.tbl` + `include/uapi/asm-generic/unistd.h`.
   - RV32 omits legacy `time32`-tagged syscalls (`clock_gettime`, `futex`, `pselect6`, `ppoll`, `wait4 (260)`, `stat`/`fstat`/`newfstatat`) in favor of `clock_gettime64 (403)`, `futex_time64 (422)`, `pselect6_time64 (413)`, `ppoll_time64 (414)`, `waitid (95)`, and `statx (291)`. Raw syscall `260` (`wait4`) is NOT in the RV32 syscall table and must return **`-ENOSYS`**!
   - **Important UAPI Exception**: Absence of legacy `time32` syscalls does NOT make every time/resource struct 64-bit on RV32! Specifically:
     - `getitimer (102)` and `setitimer (103)` use `__kernel_old_itimerval` (four 32-bit `long`s = 16 bytes on RV32);
     - `waitid (95)` 5th raw-syscall argument `struct __kernel_rusage *ru` (64-bit `time64` `ru_utime`/`ru_stime` + fourteen 32-bit `long` counters) and `sysinfo (179)` `struct sysinfo` use 32-bit `long` fields;
     - `_llseek (62)` takes `(fd, offset_high, offset_low, result_ptr, whence)` with high word first!
     - `mmap2 (222)` takes `(addr, len, prot, flags, fd, pgoff_4k)` (`offset = (uint64_t)pgoff_4k * 4096ULL`).
     - `truncate64 (45)`, `ftruncate64 (46)`, `pread64 (67)`, `pwrite64 (68)`, `fcntl64 (25)`.
2. **Compound Structure Conversions in `src/linux/`**:
   - `pselect6_time64 (413)` (`src/linux/poll.c`): 6th argument `sigmask_pack` on RV32 is `{ uint32_t sigmask_ptr; uint32_t sigmask_size; }` (8 bytes, NOT two 8-byte fields!), and `fd_set` array sizing rounds `nfds` to 32-bit `unsigned long` words (`4` bytes).
   - `readv (65)` / `writev (66)` (`src/linux/file.c` & `src/linux/io.c:65`): `rv32_iovec_t` is `{ uint32_t iov_base; uint32_t iov_len; }` (8 bytes). `src/linux/io.c` must import 8-byte `rv32_iovec_t` descriptors when `xlen == 32` while preserving the shared worker-aware I/O path.
   - `sendmsg (211)` / `recvmsg (212)` (`src/linux/socket.c`): `rv32_msghdr_t` is 28 bytes (`msg_iovlen` and `msg_controllen` are 32-bit `size_t`!); `rv32_cmsghdr_t` is 12 bytes (`cmsg_len` is 32-bit `size_t` with 4-byte `CMSG_ALIGN`, vs 8-byte `CMSG_ALIGN` on RV64!).
   - `sigaltstack (132)` (`src/linux/signal.c`): `rv32_stack_t` is `{ uint32_t ss_sp; int32_t ss_flags; uint32_t ss_size; }` (12 bytes).
   - `rt_sigaction (134)` (`src/linux/signal.c`): Kernel `rv32_sigaction_t` is **16 bytes** (`uint32_t sa_handler; uint32_t sa_flags; uint64_t sa_mask;` — RISC-V `asm-generic/signal.h` has **NO `sa_restorer` slot**!) `[F]`.
   - `waitid (95)` (`src/runtime_main.c`): `siginfo_t` is 128 bytes with `_sifields` starting at offset **12** on RV32 (no 4-byte padding after `si_code`, unlike 64-bit where `_sifields` starts at offset 16) and 32-bit `si_utime`/`si_stime`, plus optional 5th raw-syscall argument `rusage_ptr`.
   - `riscv_hwprobe (258)`: `struct riscv_hwprobe` pairs remain `{ int64_t key; uint64_t value; }` (16 bytes), while `cpus` pointer, `cpu_count` (`size_t`), and cpuset word size (`4` bytes) are 32-bit.
   - **Scheduler & Multi-Worker Runtime Integration (`src/runtime_main.c:3497`, `src/runtime/exec_state.c`, `src/runtime/scheduler.c`)**:
     - `runtime_main.c` and `scheduler.c` must route both `SYS_futex (98)` (on RV64) and `SYS_futex_time64 (422)` (on RV32) through the scheduler-owned futex subsystem;
     - `runtime_main.c:3497` live-worker syscall admission must accept RV32 `403` (`clock_gettime64`), `407` (`clock_nanosleep_time64`), `413` (`pselect6_time64`), `414` (`ppoll_time64`), and `422` (`futex_time64`) alongside RV64 `72`/`73`/`98`/`113` when multiple worker threads are live;
     - `runtime/exec_state.c` and `linux/exec_args.c` must accept `xlen == 32` across `execve` and `--resume-v7`.
3. **Frozen RV32 Linux UAPI Signal Frame Layout (`src/linux/signal.c`, verified in `tests/check_abi_invariants.c`)** `[F]`:
   - Matches Linux v6.18 `arch/riscv/include/uapi/asm/{ptrace,sigcontext,ucontext}.h`:
     - `struct __riscv_d_ext_state`: `uint64_t f[32]` (256 B) + `uint32_t fcsr` (4 B) + 4 B tail pad = **264 bytes**. (There is **NO** `__riscv_ctx_hdr` magic `0x44504600` in standard RISC-V `sigcontext`!)
     - `union __riscv_fp_state`: **528 bytes, aligned to 16** (because `struct __riscv_q_ext_state` is `528` bytes and `sigcontext` embeds the full union unconditionally without advertising `Q`).
     - `struct sigcontext` (`rv32_sigcontext_t`): `uint32_t gregs[32]` (128 B) + `union __riscv_fp_state fpregs` (528 B, 16B-aligned) = **656 bytes**.
     - `struct ucontext` (`rv32_ucontext_t`): `uint32_t uc_flags` (4 B) + `uint32_t uc_link` (4 B) + `rv32_stack_t uc_stack` (12 B) + `uint32_t uc_sigmask[2]` (8 B at offset 20 — must be `uint32_t[2]` rather than `uint64_t` on 64-bit host to preserve 4-byte RV32 alignment!) + `uint8_t uc_sigmask_ext[120]` (120 B) + 12 B alignment padding (`offsetof(uc_mcontext) == 160` = `0xA0`) + `rv32_sigcontext_t uc_mcontext` (656 B) = **816 bytes**.
     - `struct rt_sigframe` (`rv32_rt_sigframe_t`): `siginfo_t info` (128 B) + `rv32_ucontext_t uc` (816 B) = **944 bytes** (16-byte aligned).

### 3.5 RV32 JIT, AOT Identity & Glibc Toolchain Completion
- In `src/jit/a64.c`: emit 32-bit `W`-register operations when `cpu->xlen == 32`.
- In `src/runtime/aot_cache.c` (line 87): parameterize `rv_aot_cache_identity` on the loaded image's `xlen` (`32` vs `64`) and `abi` (`ILP32D` vs `LP64D`) using the existing `xlen`, `abi`, and `profile_digest` fields in `src/aot/format.c` (no redundant `profile_id` field needed), and verify that persisted RV32 and RV64 cache records never cross-admit.
- In `nix/rv32-glibc-target-libraries.nix`: fix `D23` (`ln -s "${prefix}gcc" "$out/bin/cc"`), build and export `_build/rv32-glibc-target-libs-export-v1`, and qualify all 8 RV32 smoke binaries (musl & glibc, static & dynamic, C & C++17) under both `rvrt-linux-aarch64` on Linux and `hl` on macOS Apple Silicon.

---

## 4. Wave 3 Specifications — Class-A 32-Bit 4 GiB-Window Translators (`mips32rt`, `ppc32rt`, `sparc32rt`)

All three Wave 3 translators share the Class-A `[G, G + 4 GiB)` architecture (`src/rt32/` copied from `i686rt`/`a32rt` with `D18`/`D19` fixes applied), `/dev/a32host` (`include/a32host.h`), and the dual-engine (`src/interp/` + `src/dbt/`) design.

---

### 4.1 `mips32rt` (`../mips32rt`) — MIPS32r2 (`mipsel` & `mips` BE, O32 ABI)

#### 4.1.1 Target Profile & Business Objective
- **Target CPUs**: MIPS 24Kc / 24KEc (MediaTek MT7620, Qualcomm Atheros AR9331/QCA9531) and Ingenic XBurst (JZ4770).
- **Objective**: Execute installed router, OpenWrt (`mipsel_24kc` and `mips_24kc` musl), and Debian (`mipsel` glibc) userspace binaries on AArch64 Linux and macOS (`hl`).
- **ELF Identification & `TASK_SIZE`**:
  - `ELFCLASS32`, `e_machine == EM_MIPS (8)`, both `ELFDATA2LSB` (`mipsel`, primary) and `ELFDATA2MSB` (`mips` big-endian).
  - Admits `(e_flags & EF_MIPS_ABI2) == 0` AND `(e_flags & EF_MIPS_ABI) in {0, E_MIPS_ABI_O32 (0x00001000)}` (rejects N32, EABI, O64).
  - Guest user `TASK_SIZE = 0x7fff8000` (a deliberate conservative policy choice matching Linux's 64-bit kernel O32 compat limit `TASK_SIZE32 = 0x7fff8000` while also satisfying native 32-bit `CONFIG_32BIT`'s `0x80000000` `useg` limit; stack top `0x7fff0000`, vDSO/sigtramp `0x7fff7000`).

#### 4.1.2 `mips32_ctx_t` Context & Register Mapping (Verified in `tests/check_abi_invariants.c`) `[F]`
- **ABI-Locked Context (`src/mips32rt.h`, zero overlapping fields)**:
  - `0x000..0x07f`: `uint32_t gpr[32]` (`$0=zero` hardwired 0, `$1=at`, `$2..$3=v0..v1`, `$4..$7=a0..a3`, `$8..$15=t0..t7`, `$16..$23=s0..s7`, `$24..$25=t8..t9`, `$28=gp`, `$29=sp`, `$30=fp`, `$31=ra`)
  - `0x080..0x08f`: `uint32_t pc` (`0x080`), `uint32_t next_pc` (`0x084`), `uint32_t hi` (`0x088`), `uint32_t lo` (`0x08c`)
  - `0x090..0x097`: `uint32_t ulr` (`0x090`, CP0 UserLocal `$29` for TLS), `uint32_t fcsr` (`0x094`, `FCR31` with `fcc[0..7]` in bits `23, 25..31`)
  - `0x098..0x09b`: `uint8_t in_delay_slot` (`0x098`), `uint8_t fr_mode` (`0x099`, `0` = `FR=0`, `1` = `FR=1`), `uint8_t llbit` (`0x09a`), `uint8_t nan2008` (`0x09b`, `0` = Legacy NaN/ABS, `1` = 2008 NaN/ABS)
  - `0x09c..0x0a7`: `uint32_t lladdr` (`0x09c`), `uint32_t llval` (`0x0a0`), `uint32_t cp0_config1` (`0x0a4`, bit 0 `is_be` flag in software config)
  - `0x0a8..0x0bf`: `uint64_t guest_base` (`0x0a8`), `uint64_t ibtc_ptr` (`0x0b0`), `uint32_t exit_reason` (`0x0b8`), `uint32_t exit_info` (`0x0bc`)
  - `0x0c0..0x1bf`: `uint64_t fpr[32]` (256 B, 16-byte aligned at `0x0c0`).
- **AArch64 DBT Register Map (16 Guest GPRs -> 16 Host GPRs `w0..w15`)**:
  - `x19 = xCtx`, `x20 = xG` (`guest_base`), `x21..x24` scratch.
  - Because `$0` (`$zero`) is hardwired `wzr`, `w0..w15` cache exactly **16** hot guest GPRs: `$v0 ($2), $v1 ($3), $a0..$a3 ($4..$7), $t0..$t5 ($8..$13), $s0 ($16), $s1 ($17), $sp ($29), $ra ($31)`. Remaining guest GPRs (`$at, $t6..$t9, $s2..$s7, $gp, $fp`) are accessed at `[x19, #off]`.

#### 4.1.3 MIPS32r2 ISA Semantics, Delay Slots, Page-Final Progress, FP NaN Modes & Unaligned Accesses
- **Branch Delay Slots, Branch-Likely (`B*L`), & Page-Boundary Progress Rule**:
  - Every MIPS branch/jump executes the 32-bit instruction at `pc + 4` before transferring control to the branch target, with `ra = pc + 8` on link instructions.
  - For **Branch-Likely** instructions (`BEQL`, `BNEL`, `BLEZL`, `BGTZL`, `BLTZL`, `BGEZL`, `BC1FL`, `BC1TL`), if the branch is **not taken**, the delay-slot instruction at `pc + 4` is **annulled** (`pc` advances directly to `pc + 8` **without fetching or faulting on `pc + 4`** — critical when `pc + 4` lies on an unmapped page!).
  - In DBT (`src/dbt/`), a branch and its delay-slot instruction at `pc + 4` are decoded and emitted as an indivisible unit when both lie on the same 4 KiB page. If a block encounters a branch at the last word of a page (`(pc & 0xfff) == 0xffc`) after prior instructions, the block terminates *before* `pc`; if a block **starts** at `(pc & 0xfff) == 0xffc`, the DBT emits `EXIT_SINGLE_STEP` (`interp_step(ctx)`) to execute the cross-page branch+delay-slot pair once and resume DBT at the target PC.
  - On synchronous fault or signal delivery while `ctx->in_delay_slot == 1`, `ctx->in_delay_slot` (`CP0.Cause.BD`) remains translator-internal bookkeeping (modern Linux `arch/mips/include/uapi/asm/sigcontext.h` repurposed the old O32 `sc_cause` slot as `sc_hi1`, and N32/N64 have no cause field!) while `sc_pc` records `branch_pc` (`pc - 4`) so signal return re-executes the branch and its delay slot `[F]`.
- **FPU Register Mode (`FR=0` vs `FR=1`) & NaN/ABS Mode (`Legacy` vs `NAN2008`)**:
  - Initialized from ELF `e_flags` (`EF_MIPS_FP64`, `EF_MIPS_NAN2008 = 0x400`) and `.MIPS.abiflags` (`PT_MIPS_ABIFLAGS = 0x70000003`).
  - **Legacy NaN (`nan2008 == 0`)**: Quiet NaN has fraction MSB **0** (`0x7fbfffff` / `0x7ff7ffffffffffff`) and signaling NaN has fraction MSB **1** (`0x7fc00000` / `0x7ff8000000000000`); `ABS.S`/`ABS.D` and `NEG.S`/`NEG.D` are arithmetic operations that signal `Invalid Operation` on sNaN.
  - **2008 NaN (`nan2008 == 1`)**: Quiet NaN has fraction MSB **1** (matching IEEE 754-2008 and AArch64 `FPCR.DN = 1`), and `ABS.fmt`/`NEG.fmt` (`ABS2008`) are non-arithmetic sign-bit flips that never trap on sNaN.
- **Unaligned Load/Store Pairs (`LWL`/`LWR`, `SWL`/`SWR`) & `RDHWR`**:
  - `LWL`/`LWR`/`SWL`/`SWR` implemented in both `mipsel` and `mips` BE modes.
  - `rdhwr rt, $29` returns `ctx->ulr` (TLS pointer) in `gpr[rt]`.

#### 4.1.4 MIPS O32 Linux Syscall & 128-Signal Namespace ABI (`src/os/`)
- **O32 Syscall Convention (`syscall` instruction `0x0000000c`)**:
  - Syscall number in `$v0` (`gpr[2]`), offset from **`__NR_Linux = 4000`**.
  - **Arguments 1..4** in `$a0..$a3` (`gpr[4..7]`). **Arguments 5..8** are read from the guest user stack at **`(uint32_t)(gpr[29] + 16)`**, **`+20`**, **`+24`**, **`+28`**!
  - **64-bit Register-Pair Alignment**: O32 aligns 64-bit arguments to **even** argument pairs (`$a0:$a1` or `$a2:$a3`; in `mipsel`, `lo` is even and `hi` is odd; in `mips` BE, `hi` is even and `lo` is odd).
  - **Return Value & `$a3` Error Flag**:
    - Success (`ret >= 0`): **`gpr[7] ($a3) = 0`**, **`gpr[2] ($v0) = (uint32_t)ret`** (`pipe (4042)` also sets `gpr[3] ($v1) = pipefd[1]`).
    - Error (`ret < 0`): **`gpr[7] ($a3) = 1`**, **`gpr[2] ($v0) = mips_errno_from_host(-ret)`** (positive MIPS errno!).
- **Complete MIPS Constant, Struct & 128-Signal Namespace (`arch/mips/include/uapi/asm/`)**:
  - **Kernel `struct stat64` (`stat64 = 4213`, `lstat64 = 4214`, `fstat64 = 4215`, `fstatat64 = 4293`)**: **104 bytes** in Linux UAPI `arch/mips/include/uapi/asm/stat.h` (distinct from libc's public `struct stat`) `[F]`.
  - **Complete 1..128 Signal Namespace & Guest-Owned Signal Subsystem (`src/os/signals_mips32.c`)**:
    - MIPS defines `_NSIG = 128` (`16-byte` `sigset_t`): `1=SIGHUP, 2=SIGINT, 3=SIGQUIT, 4=SIGILL, 5=SIGTRAP, 6=SIGIOT/SIGABRT, 7=SIGEMT, 8=SIGFPE, 9=SIGKILL, 10=SIGBUS, 11=SIGSEGV, 12=SIGSYS, 13=SIGPIPE, 14=SIGALRM, 15=SIGTERM, 16=SIGUSR1, 17=SIGUSR2, 18=SIGCHLD, 19=SIGPWR, 20=SIGWINCH, 21=SIGURG, 22=SIGIO, 23=SIGSTOP, 24=SIGTSTP, 25=SIGCONT, 26=SIGTTIN, 27=SIGTTOU, 28=SIGVTALRM, 29=SIGPROF, 30=SIGXCPU, 31=SIGXFSZ, 32..128=RT signals` `[F]`.
    - Because host AArch64 Linux supports only 64 signals (`_NSIG = 64`) and has no native `SIGEMT` counterpart, `mips32rt` (and `mips64rt`) cannot rely on a 64-entry host signal table. Instead, `signals_mips32.c` maintains a **guest-owned 128-entry action table** (`mips_sigaction_t actions[128]`), **128-bit per-thread blocked and pending masks** (`uint64_t mask[2]`, `pending[2]`), and a bounded **FIFO real-time signal queue** (`mips_sigqueue_t`) for duplicate queued signals (`32..128`). Standard signals `1..31` (except `SIGEMT = 7`) and `32..62` map to host signals, while `SIGEMT (7)` and guest RT signals `63..128` are queued in guest/shared state and notify target threads via reserved host kick signal `SIGRTMAX (64)` across `kill`, `tkill`, `tgkill`, `rt_sigqueueinfo`, `rt_sigprocmask` (`sigsetsize == 16`), `rt_sigpending`, `rt_sigsuspend`, `rt_sigtimedwait`, `signalfd4`, and `ppoll`/`pselect6`.
  - **Socket & Open Constants**: `SOCK_DGRAM = 1`, `SOCK_STREAM = 2`, `SOL_SOCKET = 0xffff`, `O_CREAT = 0x0100`, `O_TRUNC = 0x0200`, `O_EXCL = 0x0400`, `O_NOCTTY = 0x0800`, `O_NONBLOCK = 0x0080`, `O_APPEND = 0x0008`, `O_LARGEFILE = 0x2000`.
- **O32 `rt_sigframe` (`src/os/sigframe_mips32.h`)**:
  - **24-byte prefix** (`uint32_t rs_ass[4]` 16 B + `uint32_t rs_pad[2]` 8 B), `mips_siginfo_t rs_info` (128 B, with `si_code` before `si_errno`), `mips_ucontext_t rs_uc` (`sc_regs[32]` stored as 64-bit `uint64_t` slots, `sc_fpregs[32]`, `sc_mdhi`, `sc_hi1..3`, `sc_mdlo`, `sc_lo1..3`, `sc_pc`, `sc_fpc_csr`) `[F]`.

---

### 4.2 `ppc32rt` (`../ppc32rt`) — PowerPC 32-Bit (`750`/RAD750 Classic & NXP `e500v2` SPE)

#### 4.2.1 Target Profile & Business Objective
- **Target CPUs**:
  1. **PowerPC 750 (G3) / BAE RAD750 / 7400 (`ppc32-classic`)**: Big-endian 32-bit PowerPC Book I + classic 64-bit IEEE-754 FPU (`f0..f31`).
  2. **NXP QorIQ / PowerQUICC III e500v2 (`P1021` / `MPC8548`, `ppc32-spe`)**: Big-endian 32-bit PowerPC Book E + Signal Processing Engine (SPE) APU (`ev*` 64-bit SIMD in `r0..r31`, `efs*` scalar float, `efd*` scalar double).
- **ELF Identification**: `ELFCLASS32`, `ELFDATA2MSB` (big-endian), `e_machine == EM_PPC (20)`. Profile auto-detected from ELF section **`.gnu.attributes`** (`Tag_GNU_Power_ABI_FP` / `Tag_GNU_Power_ABI_Vector`, emitted by `.gnu_attribute` directives), SPE opcode presence, or `--profile=classic|spe` (`PPC32RT_PROFILE`).

#### 4.2.2 `ppc32_ctx_t` Context & Dual-FPU/SPE Register Architecture
- **Unified Context Layout (`src/ppc32rt.h`)**:
  - `0x000`: `uint32_t gpr[32]` (low 32 bits of `r0..r31`; `r1 = sp`, `r2 = tp` TLS pointer, `r3..r10` args/return, `r13` small data)
  - `0x080`: `uint32_t gpr_hi[32]` (upper 32 bits of `r0..r31` for e500v2 SPE 64-bit `ev*`/`efd*` operations; untouched by classic 32-bit instructions)
  - `0x100`: `uint32_t nip` (`pc`), `uint32_t lr`, `uint32_t ctr`, `uint32_t cr` (8 × 4-bit fields `CR0..CR7`, each `[LT, GT, EQ, SO]`), `uint32_t xer`, `uint32_t fpscr`, `uint32_t spefscr`
  - `0x120`: `uint64_t acc` (64-bit SPE accumulator), `uint64_t fpr[32]` (classic `f0..f31` 64-bit IEEE-754 registers)
  - `0x228`: `uint64_t guest_base` (`G`), `uint32_t res_addr`, `uint32_t res_val`, `uint8_t res_valid`, `uint8_t is_spe`.

#### 4.2.3 PPC32 Linux Syscall, vDSO & Signal Frame ABI (`src/os/`)
- **PPC32 Syscall Convention (`sc` instruction `0x44000002`)**:
  - Syscall number in `r0`; arguments 1..6 in `r3, r4, r5, r6, r7, r8` (64-bit args in odd:even pairs `r3:r4`, `r5:r6`, `r7:r8`, high word first).
  - Success: **`CR0.SO = 0`**, `r3 = (uint32_t)ret`. Error: **`CR0.SO = 1`**, **`r3 = (uint32_t)(-ret)`** (positive errno).
- **PPC32 `rt_sigframe` & `mcontext_t` (`src/os/sigframe_ppc32.h`, Linux `arch/powerpc/include/uapi/asm/ucontext.h`)** `[F]`:
  - `struct mcontext` (`mcontext_t`, 992 bytes, 16-byte aligned):
    - `0x000..0x0bf`: `uint32_t mc_gregs[48]` (192 B: `r0..r31`, `nip`, `msr`, `orig_r3`, `ctr`, `link`, `xer`, `ccr`, `mq`, `trap`, `dar`, `dsisr`, `result`)
    - `0x0c0..0x1c7`: `uint64_t mc_fregs[33]` (264 B: `f0..f31` + `fpscr`)
    - `0x1c8..0x1cf`: `uint32_t mc_pad[2]` (8 B padding to align `mc_vregs` to 16 bytes at `0x1d0`)
    - `0x1d0..0x3df`: `uint8_t mc_vregs[528] __attribute__((aligned(16)))` (inline `elf_vrregset_t` = `33 * 16 = 528` B; on e500v2 SPE, Linux overlays `uint32_t evr[32]` (`128 B`, holding `gpr_hi[0..31]`), `uint64_t acc` (`8 B`), and `uint32_t spefscr` (`4 B`) at the start of `mc_vregs`!).

---

### 4.3 `sparc32rt` (`../sparc32rt`) — SPARC V8 (Gaisler LEON3 / LEON4)

#### 4.3.1 Target Profile, ELF Admission & Libc Sysroot
- **Target CPUs**: Cobham Gaisler LEON3 (`GR712RC`) and LEON4 (`GR740`) radiation-hardened SPARC V8 processors.
- **ELF Admission Policy (Strict V8)**:
  - Admits `ELFCLASS32`, `ELFDATA2MSB` (big-endian), **`e_machine == EM_SPARC (2)` with `e_flags == 0` ONLY** `[F]`.
  - **Explicitly rejects `EM_SPARC32PLUS (18)` and `EF_SPARC_32PLUS` (`ENOEXEC`)**, because V8+ permits 64-bit `%g`/`%o` registers and V9 instructions that a 32-bit V8 context cannot represent.
- **Target Sysroot (`glibc` + `nolibc`)**:
  - Upstream `musl` has no SPARC port `[F]`. `sparc32rt` therefore qualifies freestanding/`nolibc` static binaries in Phases 1–2 and **`sparc-unknown-linux-gnu` (`glibc` static and dynamic `ld-linux.so.2`)** in Phases 2–7.

#### 4.3.2 `sparc32_ctx_t` Context, Register Windows, Dual-PC & LEON `CASA`
- **Register Window Spill/Fill (`SAVE` / `RESTORE`)**:
  - Spills/fills `%l0..%l7` and `%i0..%i7` (`struct rwindow_32`, 16 × 32-bit big-endian words = 64 bytes) at `[%sp + 0 .. %sp + 60]`.
  - Before any `fork`, `clone`, or signal delivery, `flush_user_windows(ctx)` writes active `%l0..%l7`/`%i0..%i7` to `[%sp]`.
- **Dual-PC (`pc`, `npc`), Annul Bit (`,a`), & Page-Boundary Rule**:
  - Conditional `Bicc,a` / `FBfcc,a` annuls the delay slot (`pc = npc + 4; npc = npc + 8`) when **not taken**; unconditional `BA,a` / `FBA,a` **always** annuls the delay slot (`pc = target; npc = target + 4`). An annulled delay slot is never fetched, so an unmapped page immediately after a not-taken `Bicc,a` or taken `BA,a` at `0xffc` never faults.
  - Page-final non-annulled branches at `(pc & 0xfff) == 0xffc` use the same `EXIT_SINGLE_STEP` (`interp_step`) progress rule as MIPS (§1 `D6`).
- **LEON3/4 Hardware Multiply/Divide & `CASA` Privilege Policy**:
  - Implements `UMUL[cc]`, `SMUL[cc]`, `UDIV[cc]`, `SDIV[cc]`, `RDY`/`WRY`, `LDSTUB`, `SWAP`.
  - For LEON `CASA [%rs1] imm_asi, %rs2, %rd` (`op=3, op3=0x3c`): in Linux `arch/sparc/include/uapi/asm/asi.h`, `ASI_USERDATA = 0x0a` is user space whereas `ASI_KERNELDATA = 0x0b` is supervisor space `[F]`. `sparc32rt` accepts `ASI == 0x0a` unconditionally in user mode and faults `SIGILL` (`ILL_PRVOPC`) on `ASI == 0x0b` by default unless `--leon-allow-asi-0b` (`SPARC32RT_LEON_SUPERVISOR_ASI=1`) is explicitly enabled for bare-metal-compiled LEON binaries.

#### 4.3.3 SPARC32 Linux Syscall & Complete Signal Frame ABI (`src/os/`)
- **SPARC32 Syscall Convention (`ta 0x10` = `0x91d02010`)**:
  - Syscall number in `%g1` (`r[1]`); arguments 1..6 in `%o0..%o5` (`r[8..13]`).
  - Success: **`PSR.icc.C = 0`**, `%o0 = (uint32_t)ret`. Error: **`PSR.icc.C = 1`**, **`%o0 = sparc_errno_from_host(-ret)`** (positive SPARC errno). Always advances `pc = npc; npc = npc + 4`.
  - `pipe (42)` returns `fd[0]` in `%o0`, `fd[1]` in `%o1`; `fork (2)` / `vfork (66)` / `clone (217)` returns `%o1 = 0` in parent and **`%o0 = parent_pid, %o1 = 1`** in child.
- **Complete SPARC32 `rt_signal_frame32` Layout (`src/os/sigframe_sparc32.h`, verified in `tests/check_abi_invariants.c`)** `[F]`:
  - Per Linux `arch/sparc/include/uapi/asm/ptrace.h` and `arch/sparc/kernel/signal_32.c`, `rt_signal_frame32` (**348 bytes** fixed structure before optional FPU/rwin tail) has exact offsets:
    - `0x000..0x05f`: **`struct sparc_stackf ss` (96 bytes)**: `uint32_t locals[8]` (32 B) + `uint32_t ins[6]` (24 B) + `uint32_t fp` (4 B) + `uint32_t callers_pc` (4 B) + `uint32_t structptr` (4 B) + `uint32_t xargs[6]` (24 B) + `uint32_t xxargs[1]` (4 B) `[F]`,
    - `0x060..0x0df`: `siginfo_t info` (128 B),
    - `0x0e0..0x12f`: `struct pt_regs32 regs` (80 B: `uint32_t psr, pc, npc, y, u_regs[16]`),
    - `0x130..0x137`: `uint32_t mask[2]` (8 B `sigset_t`),
    - `0x138..0x13b`: `uint32_t fpu_save` (4 B guest pointer to inline `sigfpu32` tail or `0`),
    - `0x13c..0x143`: `uint32_t insns[2]` (8 B: `set __NR_rt_sigreturn, %g1; ta 0x10`),
    - `0x144..0x147`: `uint32_t extramask[1]` (4 B),
    - `0x148..0x14b`: `uint32_t extra_size` (4 B),
    - `0x14c..0x14f`: `uint32_t rwin_save` (4 B guest pointer to saved windows or `0`),
    - `0x150..0x15b`: `sparc32_stack_t stack` (12 B: `{uint32_t ss_sp; int32_t ss_flags; uint32_t ss_size;}`),
    - `0x15c..`: optional inline `sigfpu32` and `rwin_save` tails.
  - *(Note: Initial `_start` stack layout is distinct from `rt_signal_frame32`: at `_start`, `argc` sits at `%sp + 64` immediately after the 64-byte `rwindow_32` save area.)*

---

## 5. Waves 4 & 5 Specifications — Class-B 64-Bit Full-Address-Space Translators (`loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`)

### 5.0 Class-B `src/rt64/` Copy-First Substrate Map & Adaptation Contract
In each Class-B repository (`../loongarch64rt`, `../ppc64rt`, `../mips64rt`, `../sparc64rt`), **Phase 0 Lane `L0a`** copies the Wave-1/2-cleaned `../rvrt` runtime substrate into `src/rt64/` according to this frozen file map and seam contract (with zero cross-repository shared library):
1. **`../rvrt/src/memory/{space.c,space.h}` -> `src/rt64/memory/{space.c,space.h}`**:
   - Parameterize `rv_space_init` on the profile's `exclusive_limit` (`1ULL << 47` for `loongarch64rt`, `ppc64rt`, `sparc64rt`; `1ULL << 40` for `mips64rt` N64; `0x7fff8000ULL` for `mips64rt` N32).
2. **`../rvrt/src/runtime/{family.c,family_mm.c,mm_view.c,file_caps.c,mm_join.c,family_wait.c,family_file_index.c,guest_memory.c,scheduler.c,native_signal.c,safe_syscall_a64.S,exec_state.c}` (+ `.h`) -> `src/rt64/runtime/`**:
   - Parameterize `scheduler.c` futex syscall detection on `ARCH_SYS_futex` (`98` on LA64, `221` on PPC64, `5237` on MIPS64 N64, `6238` on MIPS64 N32, `142` on SPARC64);
   - Parameterize `exec_state.[ch]` and family directory prefix (`.<rt>-family-<pid>-<seq>`) on the target's `*_ctx_t`.
3. **`../rvrt/src/linux/{memory.c,file.c,io.c,poll.c,socket.c,metadata.c,exec_args.c}` (+ `.h`) -> `src/rt64/linux/`**:
   - Split `../rvrt/src/runtime_main.c` and `../rvrt/src/linux/signal.c` at Phase 0 into modular `< 900 LOC` files (`src/main.c`, `src/rt64/runtime/worker_loop.c`, `src/rt64/linux/signal_core.c`, and `src/linux/signal_frame_<arch>.c`) so `make check-line-limits` passes at `RC0`.
   - Parameterize signal trampoline placement in `signal_core.c` to allocate below the profile's `exclusive_limit` (never hardcoding `>= 1 TiB`).
4. **`../rvrt/src/aot/{format.c,reader.c,writer.c}` (+ `.h`) -> `src/rt64/aot/`**:
   - Parameterize on `e_machine`, `e_flags`, and `endianness`.

---

### 5.1 `loongarch64rt` (`../loongarch64rt`) — LoongArch 64-Bit (`LA64` / `LP64D`)

#### 5.1.1 Target Profile & Business Objective
- **Target CPUs**: Loongson 3A6000 and 3B6000 (`LA664` microarchitecture, `LA64` v1.10).
- **ELF Identification & `TASK_SIZE`**: `ELFCLASS64`, `ELFDATA2LSB`, `e_machine == EM_LOONGARCH (258)`, `(e_flags & 0x7) == EF_LOONGARCH_ABI_DOUBLE_FLOAT (0x3)` (`LP64D`). Guest `TASK_SIZE = 1ULL << 47` (`va_bits = 47`).

#### 5.1.2 `la64_ctx_t` Context, `CPUCFG`, & `RDTIME.D` Lowering
- **CPU State (`src/core/cpu.h`)**:
  - `uint64_t r[32]` (`r[0] = 0` hardwired, `r[2] = tp` TLS pointer, `r[3] = sp`), `uint64_t pc`.
  - `uint64_t vr[32][4] __attribute__((aligned(32)))` (256-bit **LASX** registers `xr0..xr31`, whose low 128 bits are **LSX** `vr0..vr31` and low 64/32 bits are scalar FP `f0..f31`), `uint32_t fcsr0`, `uint8_t fcc[8]`.
- **`CPUCFG rd, rj` & `RDTIME.D rd, rj` Contract (Linux `arch/loongarch/include/asm/loongarch.h`, `arch/loongarch/kernel/cpu-probe.c`)** `[F]`:
  - **`CPUCFG`** derives its words from the currently implemented feature profile (never advertising LBT, LVZ, CRYPTO, or COMPLEX, and advertising FP/LSX/LASX only from Phase 3 onward):
    - `word 0`: `0x0014c010` (PRID)
    - `word 1`: `ARCH = 2` (LA64, bits `1:0`), `PGMMU = 1` (bit 2), `PALEN = 47` (bits `11:4`), `VALEN = 47` (bits `19:12`), `UAL = 1` (bit 20), `CRC32 = 1` (bit 25)
    - `word 2`: **`LAM = 1` (bit 22, `CPUCFG2_LAM = 1U << 22`)**, `LLFTP = 1` (bit 14), `LLFTP_VER = 1` (bits `17:15`), `LAM_BH = 1` (bit 27), `LAMCAS = 1` (bit 28) in Phase 2 (`0x1840c000`), plus `FP = 1` (bit 0), `FP_SP = 1` (bit 1), `FP_DP = 1` (bit 2), `FP_VER = 1` (bits `5:3`), `LSX = 1` (bit 6), and `LASX = 1` (bit 7) from Phase 3 onward (`0x1840c0cf`) `[F]`.
    - `word 4`: `CC_FREQ = 1000000000U` (`1 GHz` constant timer frequency)
    - `word 5`: `CC_MUL = 1`, `CC_DIV = 1` (`0x00010001U`).
  - **`RDTIME.D rd, rj`** (and 32-bit `RDTIMEL.W` / `RDTIMEH.W`): reads `CLOCK_MONOTONIC` in nanoseconds (`1 tick = 1 ns`, matching `CC_FREQ = 1 GHz` in `CPUCFG[4]`) into `rd` and writes stable counter ID `0` into `rj` `[F]`.

#### 5.1.3 LoongArch64 Linux Syscall, Phase-Gated `AT_HWCAP` & Signal Frame ABI
- **Syscall ABI (`syscall 0` = `0x002b0000`)**:
  - Syscall number in `a7` (`r11`), arguments in `a0..a5` (`r4..r9`), return in `a0` (`r4`, `-errno` on error). Upstream Linux `arch/loongarch/include/uapi/asm/unistd.h` uses `statx (291)` and omits legacy `newfstatat (79)` and `fstat (80)` (raw syscalls `79` and `80` return `-ENOSYS`) `[F]`.
- **Symbolic Phase-Gated `AT_HWCAP` (Linux `arch/loongarch/include/uapi/asm/hwcap.h`, verified in `tests/check_abi_invariants.c`)** `[F]`:
  - Phase 2 integer bootstrap profile (before Phase 3 FP/SIMD lands): `HWCAP_LOONGARCH_CPUCFG (0x1) | HWCAP_LOONGARCH_LAM (0x2) | HWCAP_LOONGARCH_UAL (0x4) | HWCAP_LOONGARCH_CRC32 (0x40)` = **`0x0047`**.
  - Phase 3+ scalar FP + SIMD profile (adds `HWCAP_LOONGARCH_FPU (0x8) | HWCAP_LOONGARCH_LSX (0x10) | HWCAP_LOONGARCH_LASX (0x20)`): **`0x007f`** (`0x004f` if `--no-simd` is selected). Never advertise `LBT_X86/ARM/MIPS`, `LVZ`, `CRYPTO`, or `COMPLEX`!
- **Extensible `rt_sigframe` & 32-Byte LASX Payload Alignment (`arch/loongarch/include/uapi/asm/sigcontext.h`)** `[F]`:
  - `sigcontext` (`sc_pc`, `sc_regs[32]`, `sc_flags`) is followed by extensible `struct sctx_info` records (`uint32_t magic; uint32_t size; uint64_t padding;`, 16-byte aligned header):
    - `FPU_CTX_MAGIC` (`0x46505501`, payload 16-byte aligned),
    - `LSX_CTX_MAGIC` (`0x53580001`, payload 16-byte aligned),
    - **`LASX_CTX_MAGIC` (`0x41535801`, payload 32-byte aligned — `LASX_CTX_ALIGN = 32`!)** `[F]`,
    - terminated by an end-marker `sctx_info` with `magic = 0, size = 0`. Unknown `magic` values or misaligned records in `rt_sigreturn (139)` fault with `SIGSEGV`.

---

### 5.2 `ppc64rt` (`../ppc64rt`) — Power ISA 64-Bit (`ppc64le` ELFv2, POWER9 / Power10)

#### 5.2.1 Target Profile & ELFv2 Entry Semantics
- **Target CPUs**: IBM POWER9 (Power ISA v3.0B) and Power10 / Power11 (Power ISA v3.1).
- **ELF Admission & ELFv2 Entry Rules (`arch/powerpc`, LLVM `BinaryFormat/ELF.h`)** `[F]`:
  - Admits `ELFCLASS64`, `ELFDATA2LSB` (`ppc64le`), `e_machine == EM_PPC64 (21)`, and **`(ehdr.e_flags & EF_PPC64_ABI) == 2`** (`EF_PPC64_ABI = 3`). Rejects ELFv1 (`1`) or unspecified (`0`).
  - **ELFv2 Global vs. Local Entry Point Rule**: In ELFv2, a function's `st_other` field encodes the local entry offset (`0, 4, 8, 16, 32, or 64` bytes from the global entry point) for static linkers. At runtime, direct calls (`bl`) already target the linker-resolved local or PLT entry, while indirect calls (`bctr`/`bctrl`), initial `_start` (`e_entry`), and signal handlers (`sa_handler`) enter at the **global entry point** with **`r12 = target_pc`**. The translator **never** adds a fixed `+8` offset to any entry address!
- **Guest `TASK_SIZE` & 4 KiB Page Policy (`D11`)**:
  - `TASK_SIZE = 1ULL << 47` (`va_bits = 47` in `rv_space`).
  - Reports `AT_PAGESZ = 4096` (4 KiB). 64 KiB-aligned (`p_align = 0x10000`) `ppc64le` ELF segments load directly onto 4 KiB pages (`p_vaddr % 4096 == p_offset % 4096`).

#### 5.2.2 `ppc64_ctx_t` Context & Power ISA v3.0B / v3.1 Lowering
- **CPU State**:
  - `uint64_t gpr[32]` (`r1 = sp`, `r2 = toc`, `r12 = entry`, **`r13 = tp` TLS pointer**), `uint64_t nip`, `uint64_t lr`, `uint64_t ctr`.
  - `uint32_t cr`, `uint64_t xer` (with `OV32` bit 19, `CA32` bit 18), `uint64_t fpscr`, `uint32_t vscr`, `uint32_t vrsave`.
  - `uint64_t vsr[64][2]` (64 × 128-bit VSX registers `vs0..vs63`: `vs0..vs31` high 64 bits `[0]` are `f0..f31` and low 64 bits `[1]` are `vsr_low[0..31]`; `vs32..vs63` are Altivec/VMX `v0..v31`).

#### 5.2.3 `ppc64le` Linux Syscall, Phase-Gated Symbolic `AT_HWCAP` & Signal Frame ABI
- **Syscall Instructions (`sc` `0x44000002` and `scv 0` `0x44000001`)**:
  - For `sc`: success sets `CR0.SO = 0, r3 = res`; error sets **`CR0.SO = 1, r3 = +errno`**.
  - For `scv 0`: success sets `r3 = res`; error sets **`r3 = -errno`** (`CR0` untouched).
- **Symbolic Phase-Gated `AT_HWCAP` & `AT_HWCAP2` (`arch/powerpc/include/uapi/asm/cputable.h`, verified in `tests/check_abi_invariants.c`)** `[F]`:
  - In Phase 2 (before Phase 3 FPU/VMX/VSX lands), `AT_HWCAP` advertises only integer features (`PPC_FEATURE_32 | PPC_FEATURE_64 | PPC_FEATURE_HAS_MMU | PPC_FEATURE_ICACHE_SNOOP | PPC_FEATURE_ARCH_2_05 | PPC_FEATURE_ARCH_2_06 | PPC_FEATURE_TRUE_LE = 0xc4003102`) and `AT_HWCAP2` omits `VEC_CRYPTO`/`HAS_IEEE128` (`0x88b40000`).
  - From Phase 3 onward (when FPU, Altivec/VMX, and VSX land):
    - `AT_HWCAP` = `PPC_FEATURE_32 (0x80000000) | PPC_FEATURE_64 (0x40000000) | PPC_FEATURE_HAS_ALTIVEC (0x10000000) | PPC_FEATURE_HAS_FPU (0x08000000) | PPC_FEATURE_HAS_MMU (0x04000000) | PPC_FEATURE_ICACHE_SNOOP (0x00002000) | PPC_FEATURE_ARCH_2_05 (0x00001000) | PPC_FEATURE_ARCH_2_06 (0x00000100) | PPC_FEATURE_HAS_VSX (0x00000080) | PPC_FEATURE_TRUE_LE (0x00000002)` = **`0xdc003182`** (never advertising SPE, 601, 4xx MAC, or DFP!).
    - `AT_HWCAP2` = `PPC_FEATURE2_ARCH_2_07 (0x80000000) | PPC_FEATURE2_ISEL (0x08000000) | PPC_FEATURE2_VEC_CRYPTO (0x02000000) | PPC_FEATURE2_ARCH_3_00 (0x00800000) | PPC_FEATURE2_HAS_IEEE128 (0x00400000) | PPC_FEATURE2_DARN (0x00200000) | PPC_FEATURE2_SCV (0x00100000) | PPC_FEATURE2_ARCH_3_1 (0x00040000)` = **`0x8af40000`**.
- **PPC64 `rt_sigframe`, `vmx_reserve[101]`, & `VRSAVE` Preservation (`arch/powerpc/include/uapi/asm/sigcontext.h`, `arch/powerpc/kernel/signal_64.c`)** `[F]`:
  - `struct sigcontext` (`mcontext_t`) contains:
    - `uint64_t _unused[4]`, `int32_t signal`, `int32_t _pad0`, `uint64_t handler`, `uint64_t oldmask`, `uint64_t regs` (guest pointer to `pt_regs`),
    - `uint64_t gp_regs[48]` (384 B; `gp_regs[PT_MSR]` records `MSR_VEC` `1ULL << 25` and `MSR_VSX` `1ULL << 23` indicating whether vector/VSX register state was active),
    - `uint64_t fp_regs[33]` (264 B: `f0..f31` = upper 64 bits of `vs0..vs31`, plus `fpscr`),
    - **`uint64_t v_regs`** (**always** set to the 16-byte-aligned guest address inside `vmx_reserve` whenever Altivec is supported — even before the first vector instruction executes — because user code may write `VRSAVE` (`SPR 256`) prior to any vector instruction, and Linux `setup_sigcontext` unconditionally populates `v_regs` and saves/restores `vrsave` at `v_regs + 33 * 16`!),
    - **`uint64_t vmx_reserve[101]`** (`808 B` = `69 + 32` `uint64_t`s: holds 16-byte-aligned `elf_vrregset_t` (`32 × 16 B` `vr0..vr31` = `vs32..vs63` + `16 B` `vscr` + `4 B` `vrsave` + `12 B` pad = `544 B`) **immediately followed at `v_regs + 544` by `uint64_t vsr_low[32]` (`256 B`)** holding the lower 64-bit halves of `vs0..vs31` when `MSR_VSX` is set!).

---

### 5.3 `mips64rt` (`../mips64rt`) — MIPS64r2 (Loongson 3A3000 `mips64el` & Cavium Octeon III `mips64` BE, N64 & N32 ABIs)

*(Depends on both Wave 2 `rvrt` R8 and Wave 3 `mips32rt` Phase 3.)*

#### 5.3.1 Target Profile, ABIs & Profile-Specific `TASK_SIZE` / Address Layout
- **Target CPUs**: Loongson 3A3000 (`mips64el` LSB) and Cavium Octeon III (`CN78XX`/`CN73XX`, `mips64` MSB).
- **ELF Identification, `TASK_SIZE`, & Address Placement (`src/rt64/memory/space.c`, `src/rt64/linux/signal_core.c`)**:
  - **N64 ABI**: `ELFCLASS64`, `e_machine == EM_MIPS (8)`, `(e_flags & EF_MIPS_ABI) == 0`, syscall base `5000`, `TASK_SIZE = 1ULL << 40` (`0x0000010000000000`, 40-bit `xuseg`). Profile placements below `1ULL << 40`: stack top `0x000000ffffff0000`, unhinted `mmap` base `0x0000005500000000`, `PT_INTERP` bias `0x0000007f00000000`, signal return trampoline page **`0x000000fffffe0000`** (replacing `rvrt`'s `>= 1 TiB` trampoline search!).
  - **N32 ABI**: `ELFCLASS32`, `e_machine == EM_MIPS (8)`, `(e_flags & EF_MIPS_ABI2) == EF_MIPS_ABI2 (0x20)`, 64-bit GPRs/FPRs with **32-bit user pointers**, syscall base `6000`, **`TASK_SIZE = 0x7fff8000ULL` (2 GiB `useg`)** so every `mmap`/`brk`/stack address fits in a signed 32-bit pointer! Profile placements below `0x7fff8000`: stack top `0x7fff0000`, unhinted `mmap` base `0x3f000000`, `PT_INTERP` bias `0x3f800000`, signal return trampoline page **`0x7fff1000`**.

#### 5.3.2 `mips64_ctx_t` Context, Canonical 32-Bit Sign-Extension & NaN Modes
- **Canonical 32-Bit Sign-Extension Rule**: Every 32-bit MIPS64 operation (`ADDIU`, `ADDU`, `SUBU`, `SLL`, `SRL`, `SRA`, `LW`, `MULT`, `DIV`, `ROTR`, `EXT`, `INS`) writes `(uint64_t)(int64_t)(int32_t)res32` (`SXTW Xd, Wd` in A64 DBT).
- **FP NaN/ABS Mode (`Legacy` vs `NAN2008`)**: Same parameterized Legacy (`EF_MIPS_NAN2008 == 0`) vs IEEE-2008 (`EF_MIPS_NAN2008 = 0x400`) NaN/ABS semantics as `mips32rt` (§4.1.3), with 32 × 64-bit FPRs (`FR=1`).
- **N64 & N32 Syscall & 128-Signal Layers**:
  - 6 register arguments in `$a0..$a5` (`$4..$9`); `$a3 = 0, $v0 = res` on success (`$v0/$v1` for `pipe`); `$a3 = 1, $v0 = +mips_errno` on error.
  - Shares the guest-owned 1..128 MIPS signal subsystem (`SIGEMT=7, SIGBUS=10, SIGSYS=12, SIGUSR1=16, SIGCHLD=18...`, 128-entry action table, 128-bit masks, RT queue for `32..128`) and socket/open flag tables with `mips32rt` (§4.1.4). N64/N32 `sigcontext` has no `sc_cause` field; delay-slot faults record `sc_pc = branch_pc` using internal `ctx->in_delay_slot`.

---

### 5.4 `sparc64rt` (`../sparc64rt`) — SPARC V9 (`sparc64`, Oracle M8 / Fujitsu SPARC64 XII)

*(Wave 5 — depends on Wave 4 and Wave 3 `sparc32rt` Phase 3.)*

#### 5.4.1 Target Profile & Libc Sysroot
- **Target CPUs**: Oracle SPARC T8/M8 and Fujitsu SPARC64 XII (`SPARC-V9` + `VIS 1/2/3`).
- **ELF Identification & Sysroot**: `ELFCLASS64`, `ELFDATA2MSB` (big-endian), `e_machine == EM_SPARCV9 (43)`, `TASK_SIZE = 1ULL << 47`. Because upstream `musl` has no `sparc64` port `[F]`, qualifies `nolibc` freestanding binaries and **`sparc64-unknown-linux-gnu` (`glibc` static and dynamic `/lib64/ld-linux.so.2`)**.

#### 5.4.2 `sparc64_ctx_t` Context, Stack Bias `2047`, VIS & SPARC64 Syscall/Signal ABI
- **64-Bit Register Windows & Mandatory `2047` (`0x7ff`) Stack Bias**:
  - Every `SAVE` and `RESTORE` spills/fills 16 × 64-bit big-endian registers (`%l0..%l7` and `%i0..%i7`, 128 bytes = `struct rwindow_64`) at **`[%sp + 2047 + 0 .. %sp + 2047 + 120]`**.
  - Initial `_start` stack sets `%sp = actual_frame_ptr - 2047`, placing `rwindow_64` (128 B) at `[%sp + 2047]` and `argc` at `[%sp + 2047 + 128]`.
- **Dual Integer Condition Codes (`CCR.icc` and `CCR.xcc`) & VIS**:
  - `*cc` integer instructions update both `icc` (bits `31:0`) and `xcc` (bits `63:0`).
  - Supports `ASI_PRIMARY (0x80)`, `ASI_PRIMARY_NOFAULT (0x82)`, `ASI_PRIMARY_LITTLE (0x88)`, `ASI_PRIMARY_NOFAULT_LITTLE (0x8a)`, FPU `%f0..%f31` / `%d0..%d62` / `%q0..%q60`, `FSR` (`fcc0..fcc3`), and `GSR` (`alignaddr`, **`faligndata`**) `[F]`.
- **SPARC64 Linux Syscall (`ta 0x6d` = `0x91d0206d`) — Dual Carry Flag Update (`arch/sparc/kernel/syscalls.S`)** `[F]`:
  - Syscall number in `%g1`, args in `%o0..%o5`.
  - **Success (`ret >= 0`)**: Clears **BOTH `CCR.icc.C` (bit 0) AND `CCR.xcc.C` (bit 4)** (`TSTATE_ICARRY | TSTATE_XCARRY`), sets `%o0 = (uint64_t)ret`, and advances `pc = npc; npc += 4` `[F]`.
  - **Error (`ret < 0`)**: Sets **BOTH `CCR.icc.C = 1` AND `CCR.xcc.C = 1`**, sets `%o0 = sparc_errno_from_host(-ret)` (positive SPARC errno), and advances `pc = npc; npc += 4` `[F]`.
- **Complete SPARC64 `rt_signal_frame64` Layout (`src/os/sigframe_sparc64.h`, verified in `tests/check_abi_invariants.c`)** `[F]`:
  - Placed at `unbiased_sp = %sp + 2047` (16-byte aligned); handler receives biased `%sp = unbiased_sp - 2047`.
  - Per Linux `arch/sparc/include/uapi/asm/ptrace.h` and `arch/sparc/kernel/signal_64.c`, `rt_signal_frame64` (**528 bytes** fixed structure before optional FPU/rwin tail) has exact offsets:
    - `0x000..0x0bf`: **`struct sparc_stackf ss` (192 bytes)**: `uint64_t locals[8]` (64 B) + `uint64_t ins[6]` (48 B) + `uint64_t fp` (8 B) + `uint64_t callers_pc` (8 B) + `uint64_t structptr` (8 B) + `uint64_t xargs[6]` (48 B) + `uint64_t xxargs[1]` (8 B) `[F]`,
    - `0x0c0..0x13f`: `siginfo_t info` (128 B),
    - `0x140..0x1df`: `struct pt_regs regs` (160 B: `uint64_t u_regs[16], tstate, tpc, tnpc; uint32_t y, magic;`),
    - `0x1e0..0x1e7`: `uint64_t fpu_save` (8 B guest pointer to `sigfpu` tail or `0`),
    - `0x1e8..0x1ff`: `sparc64_stack_t stack` (24 B: `{uint64_t ss_sp; int32_t ss_flags; int32_t _pad; uint64_t ss_size;}`),
    - `0x200..0x207`: `uint64_t mask` (8 B `sigset_t`),
    - `0x208..0x20f`: `uint64_t rwin_save` (8 B guest pointer or `0`),
    - `0x210..`: optional inline `sigfpu` and `rwin_save` tails.

---

## 6. Nine-Phase Per-Translator Pipeline & Verification Gates

Every new translator in Waves 3–5 follows the **9-phase** progression (`Phase E` + `Phases 0–7`), ordered so **Phase 3 (FPU & SIMD)** lands *before* **Phase 4 (Signals)** and **Phase 5 (Dynamic Linking `PT_INTERP` & Ecosystem)**, and every gate validates against both the internal `interp`-vs-`dbt` differential harness AND an independent `qemu-<arch>` / Linux ground-truth oracle:

| Phase / Gate | Description | Required Independent Oracle & Acceptance Evidence |
|---|---|---|
| **Phase E (`RC-E`)** | Pre-Implementation Experiments (`E01`–`E06`) | All `experiments/E*/FINDINGS.md` committed with target compiler `offsetof`/`sizeof` verification of UAPI structs and `qemu-<arch>` oracle check. |
| **Phase 0 (`RC0`)** | Repository Scaffold, Frozen Headers & Substrate Copy | `nix build .#<rt>` produces static-PIE `aarch64-unknown-linux-musl` ELF; `make check-line-limits` and `check-abi-invariants` pass. |
| **Phase 1 (`RC1`)** | Base Integer Decoder, Interpreter (`src/interp/`) & Minimal Syscalls | `test_p1_isa` (covering ALU, shifts, branches, delay slots + annul including a not-taken `BEQL`/`Bicc,a` or `BA,a` at `page_end - 4` before an unmapped page, page-final branches, register windows, unaligned accesses, atomics) matches `qemu-<arch>` stdout/exit code under `<RT>_ENGINE=interp`. |
| **Phase 2 (`RC2`)** | Static Libc Syscalls & Base Integer AArch64 DBT (`src/dbt/`) | `difftest` reports `0` register/PC mismatches between `interp` and `dbt` on `test_p1_isa` (including page-final delay-slot progress); static `hello` passes on both engines and matches `qemu-<arch>`. |
| **Phase 3 (`RC3`)** | **Floating-Point & SIMD (`src/interp/fp.c`, `src/dbt/emit_fp.c`)** | `test_p3_fp_simd` (NaN encodings, rounding modes, exceptions, FR0/FR1 or SPE or LSX/LASX or VSX or VIS) matches `qemu-<arch>` golden output bit-for-bit on both `interp` and `dbt`. |
| **Phase 4 (`RC4`)** | **Signals, Threads (`clone`/`futex`/TLS), & Process Lifecycle (`fork`/`execve`)** | `test_p4_threads_signals` (including signal frame inspection/modification/restoration, PPC64 `VRSAVE`-before-first-vector preservation, MIPS signals `> 64`/queued RT/`SIGEMT=7`, delay-slot fault restart, window spill/fill under signal, **LL/SC reservation invalidation across helpers, signals, thread switches, and shared memory aliases**, pthreads, `fork`+`wait4`/`waitid`+`execve`) matches `qemu-<arch>` on both engines. |
| **Phase 5 (`RC5`)** | **Dynamic Linking (`PT_INTERP`), `BusyBox`, & Target `libc` Matrix** | Dynamic `glibc` (and dynamic `musl` for all non-SPARC profiles) `test_p5_dyn` and `BusyBox` (`sh -c 'ls / && echo ok | wc -c'`) match `qemu-<arch>` on both `interp` and `dbt`. |
| **Phase 6 (`RC6`)** | **`hyper-linux` (`hl`) End-to-End Integration on macOS Apple Silicon** | Both-host parity (`limactl` Linux + `hl` on macOS) for `test_p1_isa`, `test_p3_fp_simd`, `test_p4_threads_signals`, adjacent 4 KiB page permissions, and `hl ./busybox-<arch> sh -c 'echo ok'`. |
| **Phase 7 (`RC-H`)** | **Hardening (`SMC`, `libc-test`, LTP Syscall Subset, CoreMark, C++17)** | Committed `h1-smc`, `h2-report.md` (with machine-enforced pass/skip/fail assertions), `h3-coremark.md` (6-step instrumented `dbt > interp` on identical Lima substrate), and C++17 exception/RTTI/TLS smoke `PASS`. |
