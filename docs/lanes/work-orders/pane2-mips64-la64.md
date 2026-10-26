# Pane 2 (`%132`) Work Order — Pod 1: `mips64rt` & `loongarch64rt` (Waves U0, U1, U2)

- **Coordinator Spec**: `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` (Rev 4)
- **Task Cards**: `/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-u-unification.md` (`L-U0-B`, `L-U0-C`, `L-U12-LA64`, `L-U12-MIPS64`)
- **Exclusive Repository Ownership**: `/Users/angerman/Projects/zw3rk/mips64rt` and `/Users/angerman/Projects/zw3rk/loongarch64rt` (plus isolated worktrees `../mips64rt-*` and `../loongarch64rt-*`). Do NOT modify any other sibling repository.

## Mandatory Rules
1. Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and `/Users/angerman/Projects/zw3rk/rt-series/AGENTS.md`.
2. Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`), zero VLAs, zero `sprintf`/`strcpy`/`strcat`, and **every source file `<= 900` lines** (`make check-line-limits`). Host register `x18` is permanently reserved.
3. Use parallel subagent worker lanes in explicit isolated git worktrees (`git worktree add ../<repo>-<lane> -b lane/<lane> HEAD`) with disjoint file ownership, review their diffs, merge `--no-ff` to local `master`, and run bounded (`timeout --kill-after=30s`) acceptance checks.
4. Never `git push`. Commit with author `Moritz Angermann <moritz@zw3rk.com>`, `Apache-2.0`, and zero AI agent/model attribution trailers.
5. serialize any Lima VM (`limactl`) test runs so at most one Lima command runs at a time.

## Execution Milestones

### Milestone 1: Wave U0 Dual Prototype (`L-U0-B` in `loongarch64rt` + `L-U0-C` in `mips64rt`)
1. **Frozen Host Backend Interface (`src/os/backend.h`, `backend_linux.c`, `backend_darwin.c`)**:
   - Implement the exact `src/os/backend.h` contract from `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` §6 in both `loongarch64rt` and `mips64rt`.
   - Fix `loongarch64rt/src/dbt/dbt.c:146-189` on Darwin: use `MAP_JIT` with `pthread_jit_write_protect_np(0/1)` + `sys_icache_invalidate()`, never call `mprotect(..., PROT_READ | PROT_EXEC)` on `MAP_JIT` pages, and leave write protection enabled (`pthread_jit_write_protect_np(1)`) when sealing.
   - Implement per-syscall-class race-free blocking in `backend_darwin.c` (`kevent`/`poll` on `{target_fd, ws->wake_pipe_rd}` + `O_NONBLOCK` I/O for FDs/FIFOs; `__ulock_wait2`/`__ulock_wake` for futex; `kqueue` `EVFILT_PROC`/`EVFILT_TIMER` for `wait4`/`clock_nanosleep`) and `safe_syscall_a64.S` in `backend_linux.c`.
2. **In-Place Non-Relocating `vm64.c` + `Provider A` (`src/vm/vm_file.c`) + 6-Step `tgkill` Quiescence**:
   - Implement the 32-byte `rt_tlb_entry_t` (`read_tag` at `+0`, `addend` at `+8`, `write_tag` at `+16`, `flags_reserved` at `+24`).
   - Keep every guest page in-place at its fixed canonical arena address `HVA = arena_base + gva` (`addend = arena_base` is constant across the arena; `PAGE_COW_CLEAN -> PAGE_COW_DIRTY` promotion never relocates `H1 -> H2`, preserving `CLONE_VM` thread coherence, `futex` wait/wake matching, contiguous syscall buffers, and `fork()` COW).
   - Maintain the lightweight `MAP_SHARED` `vm_inode_shared_t` family inode table across `fork()` (tracking `file_size`, `resize_seq`, `code_generation`, and discarding wholly-removed `PAGE_COW_DIRTY` pages on shrink so shrink+regrow observes clean file bytes).
   - Implement the unified write gate (`write_tag` populated iff `PROT_WRITE && !PAGE_COW_CLEAN && !PAGE_HAS_CODE && !PAGE_HAS_SW_RESERVATION`), `g_ll_table[hash].seq_epoch` `LL/SC` synchronization across DBT and interpreter, and `vm_futex_prepare_and_pin()`.
   - Implement the 6-step `Prepare (park self before locking g_vm_mutation_lock) -> Quiesce (SIGRTMIN+1 tgkill / SIGUSR2 pthread_kill + rewind ucontext->pc to site->seq_start_offset if inside steps 1..6) -> Host-Op -> Commit & Invalidate -> Selective TLB Flush -> Resume` protocol (§4.5).
3. **7-Instruction Soft-TLB, 2-Insn Miss Stub, Delay-Slot `RT_NPC_DYNAMIC_CTX` & `TIF_FIXADE`**:
   - In `loongarch64rt`: keep `x28 = ctx`, bind `x20 = &ctx->tlb[0]` in `src/dbt/trampoline_a64.S`, and add `src/dbt/emit_mem.c` lowering scalar 1/2/4/8-byte loads (`ldp x2, x3, [x2, #0]`) and stores (swapped `ldp x3, x2, [x2, #8]`) + 2-insn per-site stub (`mov w4, #k; b .L_block_tlb_miss_common`) + 24-byte relative `dbt_mem_site_t`.
   - In `mips64rt`: keep `x19 = ctx`, bind `x20 = &ctx->tlb[0]` in `src/dbt/trampoline_a64.S`, replace the legacy `[x20 + va]` + `ctx->scratch` store in `src/dbt/emit_mem.c:69-107` with the 7-insn BE Soft-TLB (`rev16`/`rev`/`rev64`; for BE stores, `rev*` into `x4` after step 6 `cbnz`), and support `npc_mode = RT_NPC_DYNAMIC_CTX` (`x25` / `ctx->delay_target`) in `dbt_mem_site_t`.
   - Fix `mips64rt/src/os/mem.c:17-19,55`: emulate unaligned integer loads/stores when `ctx->fixade_enabled == 1` (default `1`, matching Linux MIPS `TIF_FIXADE`), and deliver `SIGBUS` (`BUS_ADRALN`, never `SIGSEGV`) when disabled via `sysmips(MIPS_FIXADE, 0)`.

### Milestone 2: Wave U1 `src/rt64/` Migration & Deletion (`162 Files / 56,324 LOC Removed`)
1. In `loongarch64rt`: migrate the 2 linked `src/rt64/` TUs (`worker_loop.c`, `signal_core.c`, `Makefile:51-54`) into `src/os/`, then `git rm -r src/rt64` (81 files).
2. In `mips64rt`: migrate the 5 linked `src/rt64/` TUs (`sha256.c`, `identity.c`, `family_broker.c`, `worker_loop.c`, `signal_core.c`, `Makefile:36-40`) into `src/os/` and `src/dbt/aot/`, then `git rm -r src/rt64` (81 files).
3. Verify `test ! -d src/rt64` in both repos and that Phase 6 host-contract and AOT tests (`loongarch64rt/tests/test_p6_smoke.sh`, `mips64rt/tests/test_p6_host.sh`) pass 100%.

### Milestone 3: Wave U2 AOT `dbt_mem_site_t[]` Serialization, Dual Binaries & Zero-GAP Parity Suite
1. Serialize the 24-byte relative `dbt_mem_site_t[]` array into `src/dbt/aot/` in both `loongarch64rt` and `mips64rt` (bumping emitter version ID) and verify warm-cache fault/miss recovery after process restart and PIE rebasing.
2. Build both `_build/<arch>rt-linux-aarch64` and `_build/<arch>rt-darwin-arm64` in both repositories.
3. Add/update `tests/parity_suite.sh` (`0 FAIL, 0 GAP` across P1–P7 and H1–H4 under `--interp`, `--dbt`, `--difftest`).
4. Run full verification gates (`make check check-line-limits`, `tests/parity_suite.sh`, Phase 6 AOT/host-contract, and Soft-TLB/quiescence/COW/LL-SC/delay-slot torture tests) and commit cleanly on `master` in both `loongarch64rt` and `mips64rt`.
