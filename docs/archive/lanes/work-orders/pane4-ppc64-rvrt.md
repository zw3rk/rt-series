# Pane 4 (`%133`) Work Order — Pod 3: `ppc64rt` (Waves U0–U2) & `rvrt` (Wave U5-A/B/C)

- **Coordinator Spec**: `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` (Rev 4)
- **Task Cards**: `/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-u-unification.md` (`L-U0-A`, `L-U12-PPC64`, `L-U5-A`, `L-U5-B`, `L-U5-C`)
- **`rvrt` Handover Baseline**: `/Users/angerman/Projects/zw3rk/rvrt/docs/HANDOVER.md` (`fd4f6e3`), `/Users/angerman/Projects/zw3rk/rvrt/DEFECTS.md`
- **Exclusive Repository Ownership**: `/Users/angerman/Projects/zw3rk/ppc64rt` and `/Users/angerman/Projects/zw3rk/rvrt` (via fresh `../rvrt-u5*` worktrees). Strictly preserve `../rvrt/_build/frozen/*` and existing `../rvrt-canonical-*` handover worktrees untouched (`HANDOVER.md:56-57`).

## Mandatory Rules
1. Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and `/Users/angerman/Projects/zw3rk/rt-series/AGENTS.md`.
2. Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`), zero VLAs, zero `sprintf`/`strcpy`/`strcat`, and **every source file `<= 900` lines** (`make check-line-limits`). Host register `x18` is permanently reserved.
3. Use parallel subagent worker lanes in explicit isolated git worktrees (`git worktree add ../<repo>-<lane> -b lane/<lane> HEAD`) with disjoint file ownership, review their diffs, merge `--no-ff` to local `master`, and run bounded (`timeout --kill-after=30s`) acceptance checks.
4. Never `git push`. Commit with author `Moritz Angermann <moritz@zw3rk.com>`, `Apache-2.0`, and zero AI agent/model attribution trailers.
5. Serialize any Lima VM (`limactl`) test runs so at most one Lima command runs at a time.

## Execution Milestones

### Milestone 1: `ppc64rt` Shipped-Binary Runner Closure (`L-U0-A`) & Unification (`L-U12-PPC64`)
1. **Wire `ppc64rt/src/main.c:99` (`L-U0-A`)**:
   - Replace the Phase-0 CLI stub (`(guest execution lands in Phase 1)`, returning 2) in `ppc64rt/src/main.c` with the real ELF64 `ppc64le` ELFv2 loader (`r12 = target_pc` global entry, `64 KiB` `p_align` onto 4 KiB pages), stack/auxv builder, `--interp`, `--dbt`, `--difftest`, `--sysroot`, `--execfn`, and `--image-fd` runner so `_build/ppc64rt` runs P1–P7 and H1–H4 guest ELFs directly.
2. **Delete `ppc64rt/src/rt64/` (`242 Files / 54,930 LOC`)**:
   - Verify zero live references into `src/rt64/` from `ppc64rt/src/`, remove `src/rt64/` from `ppc64rt/Makefile:46`, and `git rm -r src/rt64`.
3. **Migrate `ppc64rt` DBT Entry ABI & Add 7-Instruction Soft-TLB (`L-U12-PPC64`)**:
   - In `ppc64rt/src/dbt/trampoline_a64.S:10-42`: migrate from caller-saved `x0 = cpu, x1 = mem_ops, x2 = mem_ctx` to callee-saved **`x19 = cpu`** and **`x20 = &cpu->tlb[0]`**, updating `src/dbt/emit_*.c` and bumping the AOT emitter version ID.
   - Add `src/dbt/emit_mem.c` with the 7-instruction Soft-TLB (`ldp x2, x3, [x2, #0]` for loads; swapped `ldp x3, x2, [x2, #8]` for stores; both natural LE and byte-reversed `lhbrx`/`lwbrx`/`ldbrx`/`sthbrx`/`stwbrx`/`stdbrx` sequences), 2-instruction per-site stub (`mov w4, #k; b .L_block_tlb_miss_common`), and 24-byte relative `dbt_mem_site_t` serialized into `src/dbt/aot/`.
   - Add `src/vm/vm64.c` + `src/vm/vm_file.c` (`Provider A` in-place non-relocating COW, family-shared `vm_inode_shared_t`, unified `LARX`/`STCX.` reservation gate, 6-step `tgkill` quiescence) + `src/os/backend.h`, `backend_linux.c`, and `backend_darwin.c` (`MAP_JIT` APRR W^X).
   - Build `_build/ppc64rt-linux-aarch64` and `_build/ppc64rt-darwin-arm64` and pass `make check check-line-limits` + Zero-GAP `tests/parity_suite.sh` (`0 FAIL, 0 GAP`).

### Milestone 2: `rvrt` Unification, Application-First Closure (`BusyBox 1.37.0 builtin`) & `RV32GC` (`L-U5-A`, `L-U5-B`, `L-U5-C`)
1. **Worktree `../rvrt-u5a-vm` (`L-U5-A`: `vm64` + `Provider A` + Dual Backends + `DEFECTS.md` Closure)**:
   - Port `src/vm/vm64.c`, `src/vm/vm_file.c` (`Provider A`), `src/os/backend.h`, `backend_linux.c`, and `backend_darwin.c` into `rvrt`.
   - Replace the cooperative turn-scheduler / `Schema4` file-write bottleneck (`HANDOVER.md:215-225` `canonical_truncate_reenter` / `progress_turn_wait` hang and `DEFECTS.md` `D14`/`D15` at `scheduler.c:491-492`) with native OS worker threads + 6-step `Prepare -> Quiesce (tgkill) -> Host-Op -> Commit` quiescence and direct host `write`/`writev` syscalls.
   - Fix `rvrt/DEFECTS.md` items: preserve `-EBADF` on `O_PATH` `pread64`/`pwrite64` with native oracle test (`D1`), unify `rv_fault_is_runtime` `-ENOMEM` vs `-EFAULT` copyout handling (`D2`, `D9`, `D10`), validate `select` `nfds` (`D8`), and fix `isNaNBF16UI` (`D13`).
   - Verify `test-fsize-hard0-linux` (`RLIMIT_FSIZE=0` hard-zero execution) and static **`BusyBox 1.37.0 builtin`** (`HANDOVER.md:260-300`) + R4b dynamic `musl`/`glibc` and C/C++17 fixtures!
2. **Worktree `../rvrt-u5b-dbt` (`L-U5-B`: Full Series DBT & v4 AOT with `dbt_mem_site_t[]`)**:
   - Upgrade `rvrt/src/jit/a64.c` (635 LOC) into the full `src/dbt/` engine (`x19 = ctx, x20 = &ctx->tlb[0], x28 = epoch`, RV64GC + RVC + RV32GC integer/FP/atomic emission, block chaining, IBTC, RAS, 7-insn Soft-TLB, `difftest.c`, and v4 AOT format serializing relative `dbt_mem_site_t[]` records and general DSO blocks).
3. **Worktree `../rvrt-u5c-rv32` (`L-U5-C`: Milestone R8 `RV32GC` `ILP32D` Qualification)**:
   - Complete end-to-end `RV32GC` (`ELFCLASS32` `ILP32D`) runtime execution in `rvrt` (`--interp`, `--dbt`, `--difftest`, 32-bit EA wrap, ELF32 loader, Linux v6.18 RV32 syscalls & 944B `rt_sigframe`, static/dynamic `musl` & `glibc` C/C++17).
