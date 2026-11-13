/goal Execute the rt-series Unification & Dual-Backend Architecture Program defined in docs/UNIFICATION-PLAN.md (Rev 4) and docs/lanes/wave-u-unification.md using a maximally concurrent Coordinator + Worker-Lane Worktree DAG.

## 1. Coordinator Identity & Mission
You are the **top-level Coordinator and Integration Owner** for `rt-series`.
- You own the cross-repository dependency DAG across `rt-series` and all 11 sibling repositories (`../a32rt`, `../i686rt`, `../mips32rt`, `../ppc32rt`, `../sparc32rt`, `../rvrt`, `../loongarch64rt`, `../ppc64rt`, `../mips64rt`, `../sparc64rt`, `../hyper-linux`).
- You freeze shared headers, `Makefile` build rules, and ABI contracts (`src/os/backend.h`, `src/vm/vm32.h`, `src/vm/vm64.h`, `src/vm/vm_file.h`, `dbt_mem_site_t` with `_Static_assert`s, and `docs/lanes/wave-u-unification.md`) before every parallel fan-out.
- You delegate implementation slices to parallel Worker Lanes running in explicit isolated git worktrees (`git -C ../<repo> worktree add ../<repo>-<lane> -b lane/<lane> <base-sha>`).
- You review completed lanes in batches against `docs/UNIFICATION-PLAN.md` (Rev 4) and `docs/lanes/wave-u-unification.md`, merge accepted branches locally (`git merge --no-ff`), adjudicate escalations, and run each stage's Review Checkpoint (`RC`) acceptance check once.

## 2. Concurrency, Worktree Isolation & Outside Review Gates
- **Parallel Worker Lanes (Explicit Worktree Creation Required)**:
  - Each worker lane MUST be created in an explicit git worktree (`../<repo>-<lane>` on branch `lane/<lane>`) and assert `pwd` and `git rev-parse --abbrev-ref HEAD` before making any edits.
  - Spawn up to **12–15 concurrent worker lanes** across disjoint repositories/worktrees in Stage 1 (`Stage 1A` + `Stage 1B` + `Stage 1C`); serialize heavyweight Lima/HVF integration gates so host CPU/VM resources are not oversubscribed.
  - **Sibling Session & Artifact Preservation**:
    - Preserve all frozen artifacts in `../rvrt/_build/frozen/*` and all existing `../rvrt-*` handover worktrees (`../rvrt/docs/HANDOVER.md:56-57`).
    - Check whether `../hyper-linux` (`%92`) has active user edits before starting Stage 2 (`Wave U4`); never reset or overwrite user changes in any sibling repository.
- **Outside Reviewer Gate (`astra#xhigh` via `codex` and/or `fable#high` via `claude`)**:
  - Before any review invocation, record the pre-review working-tree snapshot (`git status --porcelain > /tmp/rt-pre-review.status && git diff | shasum -a 256 > /tmp/rt-pre-review.diffsha`).
  - At each stage gate (`RC-U0`, `RC-U12`, `RC-U3`, `RC-U4`, `RC-U5`, `RC-U6`), run a fresh-context read-only review via:
    - `codex exec -C <dir> -m gpt-6-astra -c 'model_reasoning_effort="xhigh"' -s read-only - < prompt.txt`, and/or
    - `claude -p --model claude-fable-5-1 --effort high --add-dir /Users/angerman/Projects/zw3rk --tools "Read,Glob,Grep,Bash" --permission-mode bypassPermissions < prompt.txt`.

## 3. Mandatory Reading Before Any Code Edits
1. `~/.config/ai/AGENTS.md` and `~/.config/ai/C_GUIDELINES.md`
2. `AGENTS.md`, `SPEC.md`, `docs/UNIFICATION-PLAN.md` (Rev 4), and `docs/HOST-CONTRACT.md` in `rt-series`
3. `docs/lanes/wave-u-unification.md` (exact lane cards, file ownership, and acceptance commands)
4. `../rvrt/docs/HANDOVER.md`, `../rvrt/DEFECTS.md`, and `../rvrt/docs/SUPPORT.md` (when working on `rvrt` Wave U5 lanes)

## 4. Non-Negotiable Technical & Architectural Invariants (`docs/UNIFICATION-PLAN.md` Rev 4)
1. **Curated C11 & `<= 900` Lines per File**: `-std=c11 -Wall -Wextra -Werror=vla -pedantic`. No VLAs, no Annex K (`*_s`), no `<threads.h>`, no `_Generic`, no `sprintf`/`strcpy`/`strcat`. Every source file must be `<= 900` lines.
2. **Uniform 5-Module Layout & Dual Build Artifacts**:
   - Every `<arch>rt` repository uses `src/core/`, `src/interp/`, `src/dbt/` (with `difftest.c` and `aot/`), `src/vm/`, and `src/os/` (`backend.h`, `backend_linux.c`, `backend_darwin.c`), with zero shared library extracted across repos.
   - Every `<arch>rt` repository builds both `_build/<arch>rt-linux-aarch64` (`aarch64-unknown-linux-musl-gcc -static-pie`) and `_build/<arch>rt-darwin-arm64` (native macOS `arm64` Mach-O with `MAP_JIT` APRR W^X and zero `Hypervisor.framework` dependency). Host register `x18` is permanently reserved.
3. **7-Instruction Soft-TLB, Compact 2-Insn Miss Stub & Two-Regime `vm32.c`**:
   - **Class B (`vm64.c`)** and **Class A on `H > 4096` hosts (`vm32.c` Regime A2)** use the 32-byte `rt_tlb_entry_t` (`read_tag` at `+0`, `addend` at `+8`, `write_tag` at `+16`) and the 7-instruction Soft-TLB fast path (`ldp x2, x3, [x2, #0]` for loads; swapped `ldp x3, x2, [x2, #8]` for stores) jumping on miss to a 2-instruction per-site stub (`mov w4, #k; b .L_block_tlb_miss_common`) backed by a 24-byte relative `dbt_mem_site_t` record (`seq_start_offset`, `sp_rollback_delta`, `npc_mode` supporting dynamic delay-slot `RT_NPC_DYNAMIC_CTX`) serialized into AOT payloads.
   - **Class A on `H == 4096` hosts (`vm32.c` Regime A1: 4K Linux & all `hyper-linux` runs)** keeps the 1-instruction `[x20, wAddr, uxtw]` direct `MAP_PRIVATE` 4 GiB window `[G, G+4GiB)`.
   - Never use Dual-View `MAP_SHARED` `G + S` windows (which break `fork()` private COW and cause RELRO trap storms).
4. **In-Place Non-Relocating COW & Unified Write/Atomic/SMC Protocol**:
   - All `MAP_PRIVATE` pages remain in place at their fixed canonical arena address `HVA = arena_base + gva` (`addend` never changes on `PAGE_COW_CLEAN -> PAGE_COW_DIRTY` promotion, preserving `CLONE_VM` thread coherence, `futex` wait/wake matching, contiguous syscall spans, and `fork()` COW).
   - `sparc64rt` enforces `GUEST_ABI_PAGE_SIZE = 8192` (`SPEC.md` D11) across `mmap`, whole-8-KiB-page COW promotion, and EOF tail zeroing while updating pairs of 4 KiB Soft-TLB entries (`vpn, vpn ^ 1`).
   - `mips64rt` and `mips32rt` emulate unaligned integer accesses by default (`ctx->fixade_enabled == 1`, Linux `TIF_FIXADE`) and raise `SIGBUS` (`BUS_ADRALN`) when disabled via `sysmips(MIPS_FIXADE, 0)`.
   - All interpreter RMW ops (`LOCK`, `LDSTUB`, `SWAP`, `CASA`, `STWCX.`, `AMO*`) use C11 `__atomic_*` (`__ATOMIC_SEQ_CST`) builtins on `HVA`.
5. **Deadlock-Free 6-Step `Prepare -> Quiesce -> Host-Op -> Commit` with `tgkill` Preemption**:
   - Mutators transition to `RT_WORKER_PARKED` *before* acquiring `g_vm_mutation_lock`.
   - Step 2 preempts active `RT_WORKER_RUNNING_DBT` peers via `rt_host_preempt_worker()` (`SIGRTMIN+1` / `SIGUSR2`), rewinding `ucontext->pc` to `block_base + site->seq_start_offset` if interrupted inside instructions 1–6.
   - Step 3 executes the host `mmap`/`mprotect`/`munmap`/`ftruncate` *before* Step 4 commits VMA/inode state.
6. **Git, Process & Attribution Hygiene**:
   - Bound every build/test/VM command with `timeout --kill-after=30s <sec> bash -lc "..."`.
   - Never `git push`. Author: `Moritz Angermann <moritz@zw3rk.com>`, `Apache-2.0`. Zero AI model/agent names in commits or comments.

---

## 5. Authoritative Execution Checklist (`docs/lanes/wave-u-unification.md`)

### Stage 0 (Wave U0) — Pre-Unification Closure & Dual Prototype Gate (`4 Parallel Lanes`)
1. **[`L-U0-A`: `../ppc64rt-u0a`]** Wire `ppc64rt/src/main.c` (replacing the Phase-0 stub at line 99) to the real ELF64 loader, interpreter, DBT, and `--difftest` runner; add Zero-GAP `tests/parity_suite.sh`.
2. **[`L-U0-B`: `../loongarch64rt-u0b`]** Implement and validate reference `src/os/backend.h` (§6), `backend_linux.c`, `backend_darwin.c` (`MAP_JIT` APRR W^X without `mprotect`, per-class `kevent`/`wake_pipe_rd`/`__ulock_wait2`), `vm64.c` + `vm_file.c` (`Provider A` in-place COW + family shm inode table + 6-step `tgkill` quiescence), and `src/dbt/emit_mem.c` (7-insn Soft-TLB + 2-insn stub + 24B relative `dbt_mem_site_t`).
3. **[`L-U0-C`: `../mips64rt-u0c`]** Implement and validate delay-slot `RT_NPC_DYNAMIC_CTX` recovery, Linux MIPS `TIF_FIXADE` unaligned emulation + `SIGBUS`, `LL/SC` warm-store reservation trapping, and removal of the legacy `ctx->scratch` store in `mips64rt`.
4. **[`L-U0-D`: `../{mips32,ppc32,sparc32,sparc64}rt-u0d`]** Roll out uniform Zero-GAP `tests/parity_suite.sh` scripts across the remaining Wave-3/4 repos.
5. **[Gate `RC-U0`]** Verify all 4 Stage-0 lanes pass (`0 FAIL, 0 GAP`), merge to local `master`, and freeze `backend.h`, `vm{32,64}.h`, `vm_file.h`, and `dbt_mem_site_t`.

### Stage 1A (Waves U1 & U2) — Class-B (`rt64`) `src/rt64/` Removal, Soft-TLB & Dual Backends (`4 Parallel Lanes`, Concurrent with Stages 1B & 1C)
6. **[`L-U12-LA64`: `../loongarch64rt-u12`]** Migrate 2 live TUs out of `src/rt64/`, `git rm -r src/rt64` (81 files), finalize `vm64` + `Provider A` + AOT `dbt_mem_site_t[]` serialization + `-linux-aarch64` & `-darwin-arm64` binaries.
7. **[`L-U12-MIPS64`: `../mips64rt-u12`]** Migrate 5 live TUs out of `src/rt64/`, `git rm -r src/rt64` (81 files), finalize `vm64` + `TIF_FIXADE` + AOT `dbt_mem_site_t[]` serialization + dual binaries.
8. **[`L-U12-PPC64`: `../ppc64rt-u12`]** Verify zero live `src/rt64/` refs, `git rm -r src/rt64` (242 files), migrate `trampoline_a64.S` from caller-saved `x0..x2` to `x19 = cpu, x20 = &cpu->tlb[0]`, add `emit_mem.c` + AOT site table + dual binaries.
9. **[`L-U12-SPARC64`: `../sparc64rt-u12`]** Migrate `sparc64_host_*` + `sparc64_host_selftest` (`tests/check_host_contract.sh:433`) to `src/os/` & `src/dbt/aot/`, `git rm -r src/rt64` (252 files), enforce 8 KiB `GUEST_ABI_PAGE_SIZE`, add 7-insn Soft-TLB preserving `NZCV` (`CCR`) + dual binaries.
10. **[Gate `RC-U12`]** Verify `test ! -d src/rt64` across all 4 repos (168,783 donor LOC removed) and pass `make check check-line-limits`, `parity_suite.sh`, Phase 6 AOT/host-contract tests, and Darwin Mach-O execution.

### Stage 1B (Wave U3) — Class-A (`rt32` + `a32rt`) Two-Regime `vm32`, Atomic RMWs & 5-Module Split (`8 Parallel Lanes`, Concurrent with Stages 1A & 1C)
11. **[`L-U3-MIPS32`, `L-U3-PPC32`, `L-U3-SPARC32`, `L-U3-I686`]** Reorganize `src/rt32/` into `src/vm/vm32*.c` (Regime A1 direct `[x20, wAddr, uxtw]` on `H == 4096`; Regime A2 7-insn Soft-TLB over `MAP_PRIVATE` arena on `H > 4096`), implement C11 `__atomic_*` RMWs for `i686` `LOCK` (`h_alu.c:12`), `ppc32` `STWCX.` (`interp.c:792`), and `sparc32` `LDSTUB`/`SWAP`/`CASA` (`interp.c:487`), add `sp_rollback_delta` recovery for `PUSH`/`POP`/`CALL`, add `src/dbt/aot/`, and build `-linux-aarch64` & `-darwin-arm64` binaries.
12. **[`L-U3-A32-1..4`: `../a32rt-u3-*`]** Split the 7 files `> 900` lines in `a32rt/src/` into `src/{core,interp,dbt,vm,os}/` (`<= 900` lines/file), fix `a32rt/src/elf32.c:588` so the kuser helper page (`0xffff0000`) is mapped `PROT_READ` on the host and translated via DBT, implement the A32/Thumb-2/VFPv4/NEON reference interpreter (`src/interp/`) and `src/dbt/difftest.c`, and add `vm32.c` Regime A1/A2 + `backend_{linux,darwin}.c` + v2 AOT.
13. **[Gate `RC-U3`]** Verify all 5 Class-A repos pass `make check check-line-limits` (`0` files `> 900` lines), `fork()` private-COW tests, RELRO+`.data` zero-trap-storm checks, `PUSH`/`LDM` fault recovery, and `--interp`/`--dbt`/`--difftest` parity on Linux and Darwin.

### Stage 1C (Wave U5 Part 1) — `rvrt` Unification, Application-First Closure & `RV32GC` (`3 Parallel Worktree Lanes`, Concurrent with Stages 1A & 1B)
14. **[`L-U5-A`: `../rvrt-u5a-vm`]** Port `vm64.c` + `Provider A` (`vm_file.c`) + `backend_{linux,darwin}.c` into `rvrt`, replacing the cooperative turn-scheduler / `Schema4` file-write bottleneck (`HANDOVER.md:215-225`, `DEFECTS.md` `D14`/`D15`) with native worker threads + 6-step quiescence; fix `DEFECTS.md` `D1, D2, D8, D9, D10, D13`; verify `test-fsize-hard0-linux` and static `BusyBox 1.37.0 builtin` (`HANDOVER.md:260`).
15. **[`L-U5-B`: `../rvrt-u5b-dbt`]** Upgrade `rvrt`'s 635-LOC `src/jit/a64.c` to the full series DBT (`x19 = ctx, x20 = tlb, x28 = epoch`, block chaining, IBTC, RAS, 7-insn Soft-TLB, `difftest.c`, and v4 AOT with serialized `dbt_mem_site_t[]` and general DSO discovery).
16. **[`L-U5-C`: `../rvrt-u5c-rv32`]** Implement and qualify Milestone R8 `RV32GC` (`ELFCLASS32` `ILP32D`) runtime execution (`--interp`, `--dbt`, `--difftest`, ELF32 loader, Linux32 syscalls/sigframes, static/dynamic `musl` & `glibc` C/C++17).

### Stage 2 (Wave U4 & Wave U5 Part 2) — `hyper-linux` Provider B & `rvrt` `-hl` Broker Retirement (`4 Lanes`)
17. **[`L-U4-A`, `L-U4-B`, `L-U4-C`: `../hyper-linux-u4*`]** Implement `src/inode_backing.[ch]` (`hl_inode_backing_t`, physical private 4 KiB GPA allocation + `memcpy` + Stage-1 L3 PTE repointing on `PTE_COW_CLEAN -> PTE_COW_DIRTY`, pre- & post-fork family coordinator interning with retained FD), `hv_vcpus_exit` active vCPU preemption + shared translator DBT invalidation ring across `ftruncate`/`truncate`/`openat(O_TRUNC)`/`write`/`pwrite64`/`writev`/`fallocate`/`sendfile`/`copy_file_range`, pre-bucket-lock futex pinning (`src/futex.c:504`, Rank-1 `mmap_lock` -> Rank-7 `futex_bucket_lock`), and `src/translator.h` (`hl_translators[]` 11-architecture auto-dispatch). Pass `RC-U4`.
18. **[`L-U5-D`: `../rvrt-u5d-retire`]** Verify all `rvrt` `-linux` and `-hl` Make targets (`test-busybox-static-builtins-{linux,hl}`, R4b musl/glibc/C++, R6, R7, R8 `RV32GC`, `test-fsize-hard0-{linux,hl}`, `test-r5-file-mmap-threads-{linux,hl}`, `test-aot-*-{linux,hl}`) pass on merged `U4` `hyper-linux` + `U5-A/B/C` `rvrt`; then retire the ~30k-LOC legacy SCM socket broker (`family_file*`/`file_caps*`/`scheduler.c`) and split `runtime_main.c` so every file in `rvrt/src/` is `<= 900` lines. Pass `RC-U5`.

### Stage 3 (Wave U6) — Series-Wide AOT Cache & 10-Repo × 3-Host Matrix Qualification
19. **[Wave U6]** Verify all 10 `<arch>rt` repositories (`11` guest ABIs) pass `make check check-line-limits` (`0` files `> 900` lines), `tests/parity_suite.sh` (`0 FAIL, 0 GAP`), and cold/warm/rebased/fault-recovery AOT tests across **Native Linux**, **`hyper-linux` (`hl`)**, and **Standalone macOS (`_build/<arch>rt-darwin-arm64`)**, and update `docs/FEATURE-MATRIX.md` and `README.md`. Pass `RC-U6`.

## 6. Done When
Every checklist item 1–19 has passed its `RC` acceptance gate with committed evidence, all 10 `<arch>rt` repositories conform to the 5-module `<= 900`-line layout and build both `-linux-aarch64` and `-darwin-arm64` artifacts, `src/rt64/` is removed from all 4 `rt64` repositories, `rvrt` passes `BusyBox 1.37.0 builtin` + R4b + R6 + R7 + R8 `RV32GC` on all three host backends with its legacy socket broker retired, and `make -C /Users/angerman/Projects/zw3rk/rt-series check` succeeds.
