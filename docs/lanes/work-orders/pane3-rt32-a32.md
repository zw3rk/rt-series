# Pane 3 (`%135`) Work Order — Pod 2: Class-A 32-Bit Family (`ppc32rt`, `mips32rt`, `sparc32rt`, `i686rt`, `a32rt` — Waves U0 & U3)

- **Coordinator Spec**: `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` (Rev 4, especially §4.4, §4.5, §4.6, §5.1, §6, §7 Wave U3)
- **Task Cards**: `/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-u-unification.md` (`L-U0-D`, `L-U3-PPC32`, `L-U3-MIPS32`, `L-U3-SPARC32`, `L-U3-I686`, `L-U3-A32-1..4`)
- **Exclusive Repository Ownership**: `/Users/angerman/Projects/zw3rk/{ppc32rt,mips32rt,sparc32rt,i686rt,a32rt}` (and their isolated `../<repo>-*` worktrees). Do NOT modify any 64-bit translator or `hyper-linux`.

## Mandatory Rules
1. Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and `/Users/angerman/Projects/zw3rk/rt-series/AGENTS.md`.
2. Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`), zero VLAs, zero `sprintf`/`strcpy`/`strcat`, and **every source file `<= 900` lines** (`make check-line-limits`). Host register `x18` is permanently reserved.
3. Use parallel subagent worker lanes in explicit isolated git worktrees (`git worktree add ../<repo>-<lane> -b lane/<lane> HEAD`) with disjoint file ownership, review their diffs, merge `--no-ff` to local `master`, and run bounded (`timeout --kill-after=30s`) acceptance checks.
4. Never `git push`. Commit with author `Moritz Angermann <moritz@zw3rk.com>`, `Apache-2.0`, and zero AI agent/model attribution trailers.
5. Serialize any Lima VM (`limactl`) test runs so at most one Lima command runs at a time.

## Execution Milestones

### Milestone 1: Two-Regime `src/vm/vm32.c` + `Provider A` + Dual Backends in `ppc32rt`, `mips32rt`, `sparc32rt`, `i686rt`
1. Reorganize `src/rt32/` into `src/vm/vm32*.c` + `src/vm/vm_file.c` implementing the **Two-Regime Class-A VM** (`UNIFICATION-PLAN.md` §4.6):
   - **Regime A1 (`H == 4096`: 4K Linux kernels & all `hyper-linux` `/dev/a32host` runs)**: 1-instruction `[x20, wAddr, uxtw]` over a `MAP_PRIVATE | MAP_ANONYMOUS` 4 GiB window `[G, G + 4 GiB)`.
   - **Regime A2 (`H > 4096`: 16 KiB Standalone macOS Mach-O `backend_darwin.c` & 16K/64K Linux without `/dev/a32host`)**: 7-instruction Soft-TLB (`x20 = &ctx->tlb[0]`, `mov w1, wAddr`) over a single `MAP_PRIVATE | MAP_ANONYMOUS` 4 GiB arena mapped with union host protections (`PROT_READ | PROT_WRITE`, never `PROT_EXEC`). Preserves native `fork()` COW (`fable` `C1`, `astra#xhigh` #2), keeps in-place fixed `HVA = G + gva` on `PAGE_COW_CLEAN -> PAGE_COW_DIRTY` promotion (`fable` `C2`), and eliminates RELRO+`.data` `SIGSEGV` trap storms (`fable` `M3`).
2. **True Atomic RMWs, `TIF_FIXADE`, Delay-Slot `RT_NPC_DYNAMIC_CTX` & Pre-Fault Rollback (`astra#xhigh` #3, #4; `fable` `C4`, `M5`)**:
   - Replace non-atomic interpreter RMWs with C11 `__atomic_*` (`__ATOMIC_SEQ_CST`) builtins on `HVA` in:
     - `ppc32rt/src/interp/interp.c:792` (`STWCX.` + `g_ll_table` reservation epoch check);
     - `sparc32rt/src/interp/interp.c:487` (`LDSTUB`, `SWAP`, `CASA`);
     - `i686rt/src/interp/h_alu.c:12,458` & `h_shift.c:37` (all `LOCK`-prefixed instructions).
   - Add 24-byte relative `dbt_mem_site_t` records with `sp_rollback_delta` recovery for `PUSH`/`POP`/`CALL` in `i686rt` (`src/dbt/emit_mov.c:390`, flushing cached `w0..w7` and lazy flags `x21` in the shared fault landing pad) and `RT_NPC_DYNAMIC_CTX` (`JMPL`) in `sparc32rt`.
   - In `mips32rt`, emulate unaligned integer loads/stores by default (`ctx->fixade_enabled = 1`, Linux MIPS `TIF_FIXADE`) and raise `SIGBUS` (`BUS_ADRALN`) when disabled via `sysmips(MIPS_FIXADE, 0)`.
3. Implement `src/os/backend.h` (§6), `backend_linux.c`, `backend_darwin.c` (`MAP_JIT` APRR W^X + per-class `kevent`/`wake_pipe_rd`/`__ulock_wait2`), and `src/dbt/aot/` across `ppc32rt`, `mips32rt`, `sparc32rt`, and `i686rt`, building both `_build/<arch>rt-linux-aarch64` and `_build/<arch>rt-darwin-arm64`.

### Milestone 2: `a32rt` 5-Module `<= 900`-Line Split, Kuser W^X Fix, Reference Interpreter & `--difftest` (`L-U3-A32-1..4`)
1. **Lane `L-U3-A32-1` (Structural Split & Kuser W^X Fix)**:
   - Split the 7 files exceeding 900 lines in `a32rt/src/` (`syscalls.c` 4,330L, `vfp_neon.c` 2,036L, `a64_emit.c` 1,946L, `decode_t32.c` 1,824L, `jit.c` 1,740L, `decode_a32.c` 1,118L, `aot.c` 939L) into `src/{core,interp,dbt,vm,os}/` so **every file is `<= 900` lines**, preserving all existing `a32rt` JIT, AOT, and GDB stub functionality.
   - Fix `a32rt/src/elf32.c:588` (`fable` `m6`): map the guest kuser helper page (`0xffff0000`) `PROT_READ` on the host (never `PROT_EXEC`) and let the DBT/interpreter execute it like any other guest code page, restoring strict W^X.
   - Pre-validate the first and last byte of `LDM`/`STM` spans (`src/a64_emit.c:1897`) before modifying architectural registers or memory (`astra#xhigh` #3).
2. **Lanes `L-U3-A32-2` & `L-U3-A32-3` (Reference Interpreter & `--difftest`)**:
   - Implement `a32rt/src/interp/` (pure C11 A32, Thumb/Thumb-2, and VFPv4/NEON reference interpreter with `__atomic_*` `LDREX`/`STREX` + `EXIT_UNDEF` single-step fallback) and `a32rt/src/dbt/difftest.c` (`--interp`, `--dbt`, `--difftest`).
3. **Lane `L-U3-A32-4` (Two-Regime `vm32.c`, Dual Backends & v2 AOT)**:
   - Integrate `vm32.c` Regime A1/A2, `backend_linux.c`, `backend_darwin.c`, and `src/dbt/aot/` with relative `dbt_mem_site_t[]` records.

### Milestone 3: Acceptance Gate (`RC-U3`)
Verify all 5 Class-A repositories (`ppc32rt`, `mips32rt`, `sparc32rt`, `i686rt`, `a32rt`) pass `make check check-line-limits` (`0` files `> 900` lines), build both `-linux-aarch64` and `-darwin-arm64` binaries, and pass Zero-GAP `tests/parity_suite.sh` (`0 FAIL, 0 GAP`), `fork()` private-COW isolation tests, RELRO+`.data` zero-trap-storm checks, `PUSH`/`LDM` fault recovery, and concurrent DBT + interpreter atomic `LOCK`/`LDSTUB`/`STWCX.` stress tests.
