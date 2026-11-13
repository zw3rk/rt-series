# Waves U0–U6 — `rt-series` Unification & Dual-Backend Architecture (Muse Spark Task Cards)

Parent specification: [`../UNIFICATION-PLAN.md`](../UNIFICATION-PLAN.md) (Rev 4)  
Master series spec: [`../../SPEC.md`](../../SPEC.md)  
Host contract: [`../HOST-CONTRACT.md`](../HOST-CONTRACT.md)  
`rvrt` handover baseline: [`../../../rvrt/docs/HANDOVER.md`](file:///Users/angerman/Projects/zw3rk/rvrt/docs/HANDOVER.md) (`fd4f6e3`)

Common lane rules for all Wave U0–U6 cards:
- Create your assigned git worktree explicitly (`git -C ../<repo> worktree add ../<repo>-<lane> -b lane/<lane> <base-sha>`) and assert `pwd` and `git rev-parse --abbrev-ref HEAD` before making any edits.
- Never modify files outside your card's **Exclusive File Ownership** list.
- Preserve all existing `../rvrt-*` handover worktrees and `../rvrt/_build/frozen/*` artifacts (`HANDOVER.md:56-57,119-128`), and never disturb unrelated user processes or `../hyper-linux` working-tree edits.
- Follow Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`); no VLAs, no Annex K (`*_s`), no `<threads.h>`, no `_Generic`, no `sprintf`/`strcpy`/`strcat`. Every source file must stay `<= 900` lines.
- Run your card's **Single Acceptance Check** once, wrapping the entire command group in `timeout --kill-after=30s <sec> bash -lc "..."`.
- Commit once with author `Moritz Angermann <moritz@zw3rk.com>` and zero AI attribution trailers.
- Escalate to the Coordinator if your acceptance check fails twice, if you need a frozen-header edit, or if any requirement is ambiguous.

---

## 1. Stage 0 (Wave U0): Pre-Unification Closure & Dual Prototype Gate (`4 Concurrent Lanes`)

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-U0-A** | `../ppc64rt-u0a` (`lane/u0-ppc64-main`) | `src/main.c`, `Makefile`, `tests/parity_suite.sh` | `timeout --kill-after=30s 300s bash -lc "make -C ../ppc64rt-u0a check && ../ppc64rt-u0a/tests/parity_suite.sh"` -> `0 FAIL, 0 GAP` |
| **L-U0-B** | `../loongarch64rt-u0b` (`lane/u0-la64-proto`) | `src/os/backend.h`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/vm/vm64.[ch]`, `src/vm/vm_file.[ch]`, `src/dbt/dbt.[ch]`, `src/dbt/emit_mem.c`, `src/dbt/emit_int.c`, `src/dbt/trampoline_a64.S`, `Makefile`, `tests/test_u0_soft_tlb.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../loongarch64rt-u0b check build-darwin && ../loongarch64rt-u0b/_build/test_u0_soft_tlb && ../loongarch64rt-u0b/tests/parity_suite.sh"` -> `0 FAIL, 0 GAP` |
| **L-U0-C** | `../mips64rt-u0c` (`lane/u0-mips64-proto`) | `src/os/backend.h`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/os/mem.c`, `src/vm/vm64.[ch]`, `src/vm/vm_file.[ch]`, `src/dbt/dbt.[ch]`, `src/dbt/emit_mem.c`, `src/dbt/trampoline_a64.S`, `Makefile`, `tests/test_u0_delay_tlb.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../mips64rt-u0c check build-darwin && ../mips64rt-u0c/_build/test_u0_delay_tlb && ../mips64rt-u0c/tests/parity_suite.sh"` -> `0 FAIL, 0 GAP` |
| **L-U0-D** | `../{mips32,ppc32,sparc32,sparc64}rt-u0d` (`lane/u0-parity-suite`) | `tests/parity_suite.sh`, `Makefile` (`parity` target) in `mips32rt`, `ppc32rt`, `sparc32rt`, `sparc64rt` | `timeout --kill-after=30s 300s bash -lc "for r in mips32rt ppc32rt sparc32rt sparc64rt; do ../\${r}-u0d/tests/parity_suite.sh || exit 1; done"` -> `0 FAIL, 0 GAP` |

- **Card L-U0-A (`ppc64rt` Shipped-Binary Runner Closure)**:
  1. Replace the Phase-0 CLI stub in `ppc64rt/src/main.c:99` (`(guest execution lands in Phase 1)`) with the real ELF64 loader, stack/auxv builder, `--interp`, `--dbt`, `--difftest`, `--sysroot`, `--execfn`, and `--image-fd` runner used by the Phase 1–7 harnesses (`tests/h3_run.sh`).
  2. Add `tests/parity_suite.sh` enforcing the Zero-GAP rule (`UNIFICATION-PLAN.md` §7 Wave U0).
- **Card L-U0-B (`loongarch64rt` Prototype Gate)**:
  1. Implement the reference `src/os/backend.h` (§6), `backend_linux.c`, and `backend_darwin.c` (including `MAP_JIT` APRR W^X in `src/dbt/dbt.c:146-189` without calling `mprotect` on `MAP_JIT` pages, and per-class `kevent`/`wake_pipe_rd`/`__ulock_wait2` blocking).
  2. Bind `x20 = &ctx->tlb[0]` in `src/dbt/trampoline_a64.S` (preserving `x28 = ctx`), add `src/dbt/emit_mem.c` with the 7-instruction Soft-TLB + 2-instruction per-site stub (`mov w4, #k; b .L_block_tlb_miss_common`) + 24-byte relative `dbt_mem_site_t`, implement the unified `LL/SC` + write-gate (`PAGE_HAS_SW_RESERVATION`, `PAGE_HAS_CODE`, `PAGE_COW_CLEAN`), and implement the 6-step `Prepare -> Quiesce (tgkill/pthread_kill + seq_start_offset rewind) -> Host-Op -> Commit` transaction in `src/vm/vm64.c` + `src/vm/vm_file.c` (`Provider A` in-place non-relocating COW).
- **Card L-U0-C (`mips64rt` Delay-Slot & `TIF_FIXADE` Prototype Gate)**:
  1. Replace the legacy `[x20 + va]` + `str pc, [ctx, #scratch]` lowering in `mips64rt/src/dbt/emit_mem.c:69-107` with the 7-instruction Soft-TLB (`x19 = ctx`, `x20 = &ctx->tlb[0]`, big-endian `rev*` sequences) and 24-byte relative `dbt_mem_site_t` supporting `npc_mode = RT_NPC_DYNAMIC_CTX` (`x25` / `ctx->delay_target`).
  2. Fix `mips64rt/src/os/mem.c:17-19,55` (`fable` `M5`): emulate unaligned integer loads/stores when `ctx->fixade_enabled == 1` (default `1`, matching Linux MIPS `TIF_FIXADE`), and deliver `SIGBUS` (`BUS_ADRALN`, not `SIGSEGV`) when disabled via `sysmips(MIPS_FIXADE, 0)`.

---

## 2. Stage 1A (Waves U1 & U2): Class-B (`rt64`) `src/rt64/` Removal, Soft-TLB & Dual Backends (`4 Concurrent Lanes`)
*(Starts immediately after `RC-U0` freezes `backend.h`, `vm64.c`, `vm_file.c`, and `dbt_mem_site_t`.)*

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-U12-LA64** | `../loongarch64rt-u12` (`lane/u12-la64`) | Entire `loongarch64rt` tree (`src/rt64/` removal, `src/{core,interp,dbt,vm,os}/`, `Makefile`, `tests/`) | `timeout --kill-after=30s 300s bash -lc "test ! -d ../loongarch64rt-u12/src/rt64 && make -C ../loongarch64rt-u12 check check-line-limits build-darwin && ../loongarch64rt-u12/tests/parity_suite.sh"` -> `PASS` |
| **L-U12-MIPS64** | `../mips64rt-u12` (`lane/u12-mips64`) | Entire `mips64rt` tree (`src/rt64/` removal, `src/{core,interp,dbt,vm,os}/`, `Makefile`, `tests/`) | `timeout --kill-after=30s 300s bash -lc "test ! -d ../mips64rt-u12/src/rt64 && make -C ../mips64rt-u12 check check-line-limits build-darwin && ../mips64rt-u12/tests/parity_suite.sh"` -> `PASS` |
| **L-U12-PPC64** | `../ppc64rt-u12` (`lane/u12-ppc64`) | Entire `ppc64rt` tree (`src/rt64/` removal, `src/{core,interp,dbt,vm,os}/`, `Makefile`, `tests/`) | `timeout --kill-after=30s 300s bash -lc "test ! -d ../ppc64rt-u12/src/rt64 && make -C ../ppc64rt-u12 check check-line-limits build-darwin && ../ppc64rt-u12/tests/parity_suite.sh"` -> `PASS` |
| **L-U12-SPARC64** | `../sparc64rt-u12` (`lane/u12-sparc64`) | Entire `sparc64rt` tree (`src/rt64/` removal, `src/{core,interp,dbt,vm,os}/`, `Makefile`, `tests/`) | `timeout --kill-after=30s 300s bash -lc "test ! -d ../sparc64rt-u12/src/rt64 && make -C ../sparc64rt-u12 check check-line-limits build-darwin && ../sparc64rt-u12/tests/check_host_contract.sh && ../sparc64rt-u12/tests/parity_suite.sh"` -> `PASS` |

- **Key Requirements Across `L-U12-*`**:
  1. Migrate all live symbols out of `src/rt64/` (including `sparc64_host_selftest` in `sparc64rt/src/main.c:17` / `tests/check_host_contract.sh:433`) into `src/os/` and `src/dbt/aot/`, then `git rm -r src/rt64` (deleting all 656 donor files / 168,783 LOC across the four repos).
  2. In `L-U12-PPC64`: migrate `ppc64rt/src/dbt/trampoline_a64.S` from caller-saved `x0 = cpu, x1 = mem_ops, x2 = mem_ctx` to callee-saved `x19 = cpu, x20 = &cpu->tlb[0]`, add `src/dbt/emit_mem.c`, and bump the AOT emitter version ID.
  3. In `L-U12-SPARC64`: unify `GUEST_ABI_PAGE_SIZE = 8192` across `AT_PAGESZ`, `mmap`/`mprotect`/`munmap`/`mremap` alignment (`EINVAL` on 4 KiB-only offsets), whole-8-KiB-page `PAGE_COW_CLEAN -> PAGE_COW_DIRTY` promotion, and 8 KiB EOF tail zeroing while updating pairs of 4 KiB Soft-TLB entries (`vpn, vpn ^ 1`), and preserve host `NZCV` (`CCR`) across `.L_block_tlb_miss_common`.
  4. Serialize the 24-byte relative `dbt_mem_site_t[]` array into `src/dbt/aot/` and verify warm-cache fault/miss recovery after process restart and PIE rebasing.

---

## 3. Stage 1B (Wave U3): Class-A (`rt32` + `a32rt`) Unification & Dual Backends (`8 Concurrent Lanes`)
*(Runs 100% in parallel with Stage 1A and Stage 1C!)*

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-U3-MIPS32** | `../mips32rt-u3` (`lane/u3-mips32`) | Entire `mips32rt` tree (`src/rt32/` -> `src/vm/`, `src/os/`, `src/interp/`, `src/dbt/`) | `timeout --kill-after=30s 300s bash -lc "make -C ../mips32rt-u3 check check-line-limits build-darwin && ../mips32rt-u3/tests/parity_suite.sh"` -> `PASS` |
| **L-U3-PPC32** | `../ppc32rt-u3` (`lane/u3-ppc32`) | Entire `ppc32rt` tree (`src/rt32/` -> `src/vm/`, `src/os/`, `src/interp/`, `src/dbt/`) | `timeout --kill-after=30s 300s bash -lc "make -C ../ppc32rt-u3 check check-line-limits build-darwin && ../ppc32rt-u3/tests/parity_suite.sh"` -> `PASS` |
| **L-U3-SPARC32** | `../sparc32rt-u3` (`lane/u3-sparc32`) | Entire `sparc32rt` tree (`src/rt32/` -> `src/vm/`, `src/os/`, `src/interp/`, `src/dbt/`) | `timeout --kill-after=30s 300s bash -lc "make -C ../sparc32rt-u3 check check-line-limits build-darwin && ../sparc32rt-u3/tests/parity_suite.sh"` -> `PASS` |
| **L-U3-I686** | `../i686rt-u3` (`lane/u3-i686`) | Entire `i686rt` tree (`src/rt32/` -> `src/vm/`, `src/os/`, `src/interp/`, `src/dbt/`) | `timeout --kill-after=30s 300s bash -lc "make -C ../i686rt-u3 check check-line-limits build-darwin && ../i686rt-u3/tests/parity_suite.sh"` -> `PASS` |
| **L-U3-A32-1** | `../a32rt-u3-split` (`lane/u3-a32-split`) | Structural split of `a32rt/src/` into `src/{core,dbt,vm,os}/` (<=900 LOC/file) + `src/elf32.c:588` kuser W^X fix | `timeout --kill-after=30s 300s bash -lc "make -C ../a32rt-u3-split build tests check-line-limits"` -> `0 files >900L, PASS` |
| **L-U3-A32-2** | `../a32rt-u3-interp-int` (`lane/u3-a32-interp-int`) | `src/interp/decode_a32.c`, `src/interp/decode_t32.c`, `src/interp/interp_int.c`, `src/interp/interp.h` | `timeout --kill-after=30s 240s bash -lc "make -C ../a32rt-u3-interp-int build test-interp-int"` -> `PASS` |
| **L-U3-A32-3** | `../a32rt-u3-interp-fp` (`lane/u3-a32-interp-fp`) | `src/interp/interp_vfp_neon.c`, `src/dbt/difftest.c` | `timeout --kill-after=30s 240s bash -lc "make -C ../a32rt-u3-interp-fp build test-difftest"` -> `PASS` |
| **L-U3-A32-4** | `../a32rt-u3-backends` (`lane/u3-a32-backends`) | `src/vm/vm32.c`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/dbt/aot/*` | `timeout --kill-after=30s 300s bash -lc "make -C ../a32rt-u3-backends check build-darwin test-aot"` -> `PASS` |

- **Key Requirements Across `L-U3-*`**:
  1. **Two-Regime `vm32.c` (`UNIFICATION-PLAN.md` §4.6)**:
     - **Regime A1 (`H == 4096`: 4K Linux & all `hyper-linux` runs)**: 1-instruction `[x20, wAddr, uxtw]` over a `MAP_PRIVATE | MAP_ANONYMOUS` 4 GiB window `[G, G+4GiB)`.
     - **Regime A2 (`H > 4096`: 16K Darwin Mach-O & 16K/64K Linux without `/dev/a32host`)**: 7-instruction Soft-TLB (`x20 = &ctx->tlb[0]`, `mov w1, wAddr`) over a `MAP_PRIVATE | MAP_ANONYMOUS` 4 GiB arena mapped with union host protections (`PROT_READ | PROT_WRITE`). Preserves native `fork()` COW (`fable` `C1`, `astra#xhigh` #2) and eliminates RELRO+`.data` `SIGSEGV` trap storms (`fable` `M3`).
  2. **True Atomic RMWs & Pre-Fault Rollback (`astra#xhigh` #3, #4; `fable` `C4`)**:
     - Implement C11 `__atomic_*` (`__ATOMIC_SEQ_CST`) builtins for all `LOCK`-prefixed instructions in `i686rt/src/interp/h_alu.c` & `h_shift.c`, `STWCX.` in `ppc32rt/src/interp/interp.c:792`, and `LDSTUB`/`SWAP`/`CASA` in `sparc32rt/src/interp/interp.c:487`.
     - Add `sp_rollback_delta` recovery for `PUSH`/`POP`/`CALL` in `i686rt` (`emit_mov.c:390`) and span pre-validation for `LDM`/`STM` in `a32rt` (`a64_emit.c:1897`).
     - In `L-U3-A32-1`, map the kuser helper page (`a32rt/src/elf32.c:588`, `0xffff0000`) `PROT_READ` on the host (never `PROT_EXEC`) and translate it via DBT (`fable` `m6`).

---

## 4. Stage 1C (Wave U5 Part 1): `rvrt` Unification, Application-First Closure & `RV32GC` (`3 Concurrent Worktree Lanes`)
*(Starts right after `RC-U0` in fresh `../rvrt-u5*` worktrees off `fd4f6e3`, strictly preserving `../rvrt/_build/frozen/*` and `../rvrt-canonical-*` worktrees per `rvrt/docs/HANDOVER.md:56-57`.)*

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-U5-A** | `../rvrt-u5a-vm` (`lane/u5-rvrt-vm-os`) | `src/vm/vm64.[ch]`, `src/vm/vm_file.[ch]`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/linux/{file,poll,metadata,signal}.c`, `vendor/softfloat/source/include/internals.h` | `timeout --kill-after=30s 300s bash -lc "make -C ../rvrt-u5a-vm runtime-linux build-darwin test-fsize-hard0-linux test-busybox-static-builtins-linux"` -> `PASS` |
| **L-U5-B** | `../rvrt-u5b-dbt` (`lane/u5-rvrt-dbt-aot`) | `src/dbt/*`, `src/jit/*`, `src/aot/*` (full RV64/RV32 DBT: chaining, IBTC, RAS, 7-insn Soft-TLB, `difftest.c`, v4 AOT with relative `dbt_mem_site_t[]` and general DSO support) | `timeout --kill-after=30s 300s bash -lc "make -C ../rvrt-u5b-dbt runtime-linux test-aot-cache-rebase test-aot-multiblock test-aot-dynamic"` -> `PASS` |
| **L-U5-C** | `../rvrt-u5c-rv32` (`lane/u5-rvrt-rv32gc`) | `src/core/rv32*`, `src/interp/rv32*`, `src/loader/elf32*`, `src/linux/rv32*` (complete R8 `RV32GC` `ILP32D` runtime execution: `--interp`, `--dbt`, `--difftest`, musl & glibc C/C++17) | `timeout --kill-after=30s 300s bash -lc "make -C ../rvrt-u5c-rv32 runtime-linux test-rv32-parity-linux"` -> `PASS` |

- **Key Requirements from `rvrt/docs/HANDOVER.md` & `rvrt/DEFECTS.md`**:
  1. **Replace Cooperative Turn-Scheduler Bottleneck with Native Worker Threads + 6-Step Quiescence**: Eliminate the `progress_turn_wait` / `canonical_truncate_reenter` deadlock (`HANDOVER.md:215-225`, `DEFECTS.md` `D14`/`D15`) and the 64 KiB / 1-unknown-page / `O_WRONLY` restrictions by routing guest `CLONE_VM` workers, `mmap`, `write`, `writev`, and `ftruncate` through `vm64.c` + `Provider A` (`vm_file.c`).
  2. **Close `rvrt/DEFECTS.md` Items**: Preserve `-EBADF` on `O_PATH` `pread64`/`pwrite64` with oracle regression test (`D1`), unify `rv_fault_is_runtime` `-ENOMEM` vs `-EFAULT` copyout handling (`D2`, `D9`, `D10`), validate `select` `nfds` (`D8`), and fix `isNaNBF16UI` (`D13`).
  3. **Application-First Acceptance (`HANDOVER.md:258-335`)**: Verify static `BusyBox 1.37.0 builtin`, R4b dynamic `musl`/`glibc` and C/C++17 fixtures, and `test-fsize-hard0-linux`.

---

## 5. Stage 2 (Wave U4 & Wave U5 Part 2): `hyper-linux` Provider B & `rvrt` `-hl` Broker Retirement (`4 Lanes`)
*(Runs once `../hyper-linux` session `%92` is idle/merged; refreshes `hyper-linux` baseline pin at wave start.)*

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-U4-A** | `../hyper-linux-u4a` (`lane/u4-hl-inode-cow`) | `src/inode_backing.[ch]`, `src/guest.c`, `src/guest.h`, `src/fork_ipc.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../hyper-linux-u4a hl test-inode-cow-fork"` -> `PASS` |
| **L-U4-B** | `../hyper-linux-u4b` (`lane/u4-hl-hooks-kick`) | `src/syscall.c`, `src/syscall_fs.c`, `src/syscall_io.c`, `src/syscall_net.c`, `src/futex.c`, `src/thread.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../hyper-linux-u4b hl test-truncate-multivcpu-kick test-copyout-cow"` -> `PASS` |
| **L-U4-C** | `../hyper-linux-u4c` (`lane/u4-hl-translators`) | `src/translator.h`, `src/translator_dispatch.c`, `src/syscall_exec.c`, `src/a32.c`, `src/i686.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../hyper-linux-u4c hl test-translator-dispatch-all"` -> `PASS` |
| **L-U5-D** | `../rvrt-u5d-retire` (`lane/u5-rvrt-broker-retire`) | `src/runtime/family_*`, `src/linux/file_caps*`, `src/runtime_main.c` (split into `<=900L` files in `src/{core,os,vm}/`), `Makefile`, `docs/SUPPORT.md` | `timeout --kill-after=30s 360s bash -lc "make -C ../rvrt-u5d-retire check check-line-limits test-busybox-static-builtins-hl test-fsize-hard0-hl test-r5-file-mmap-threads-hl test-aot-multiblock-hl"` -> `PASS` |

- **Key Requirements Across Stage 2**:
  1. **`L-U4-A` (Physical Private GPA COW & Family Coordinator Interning)**: Allocate a fresh private 4 KiB GPA from the guest slab + `memcpy` + Stage-1 L3 PTE repointing on `PTE_COW_CLEAN -> PTE_COW_DIRTY` (never flipping `AP=RW` on shared backing or calling `MAP_FIXED` over HVF GPAs, `astra#xhigh` #10); intern `hl_inode_ctrl_t` across both pre-fork and post-fork mappers with retained duplicate `host_fd` (`astra#xhigh` #12).
  2. **`L-U4-B` (Active vCPU Kick, Translator DBT Invalidation Ring & Futex Pinning)**: Use `hv_vcpus_exit` (`src/thread.c:1380`) + shared `code_inval_seq` ring to synchronize Stage-1 PTEs and translator DBT caches across `ftruncate`, `truncate`, `openat(O_TRUNC)`, `write`, `pwrite64`, `writev`, `fallocate(mode=0)`, `sendfile`, and `copy_file_range` (`astra#xhigh` #8, #12); call `hl_pin_and_promote_futex_page` *before* acquiring `futex_bucket_lock` (`src/futex.c:504`, preserving Rank-1 `mmap_lock` -> Rank-7 `futex_bucket_lock` order, `astra#xhigh` #11).
  3. **`L-U5-D` (Gate-Verified Broker Retirement)**: Only after all `-linux` and `-hl` targets (including `test-busybox-static-builtins-hl`, R4b, R6, R7, R8 `RV32GC`, and `test-fsize-hard0-hl`) pass on the merged `U4` `hyper-linux` and `U5-A/B/C` `rvrt`, retire the ~30k-LOC legacy `family_file*` / `file_caps*` / `scheduler.c` turn-ticket broker and split `runtime_main.c` so every file in `rvrt/src/` is `<= 900` lines.

---

## 6. Stage 3 (Wave U6): Series-Wide 7-File AOT Cache & 10-Repo × 3-Host Matrix Qualification

- **Scope**: Verify all 10 `<arch>rt` repositories (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `rvrt` [RV64GC + RV32GC], `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) pass `make check check-line-limits`, `tests/parity_suite.sh` (`0 FAIL, 0 GAP`), and cold/warm/rebased/fault-recovery AOT cache suites across all three host modes:
  1. `_build/<arch>rt-linux-aarch64` on Native Linux (`limactl`);
  2. `_build/<arch>rt-linux-aarch64` inside `hyper-linux` (`hl`);
  3. `_build/<arch>rt-darwin-arm64` standalone on macOS Apple Silicon (zero `Hypervisor.framework` dependency).
