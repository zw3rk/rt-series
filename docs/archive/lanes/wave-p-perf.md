# Wave P Task Cards & Master Checklist: 10-Translator DBT Performance Optimization (Rev 2 — Post `astra` & `fable` Review)

**Architecture & Plan Reference:** [`docs/PERF-PLAN.md`](../PERF-PLAN.md)
**Review Transcripts:** [`lode/reviews/2026-10-28-perf-plan-astra.md`](../../lode/reviews/2026-10-28-perf-plan-astra.md) and [`lode/reviews/2026-10-28-perf-plan-fable.md`](../../lode/reviews/2026-10-28-perf-plan-fable.md)
**Coordination Model:** Coordinator (`rt-series`) + 6 Parallel `muse --yolo --parallel-tool-calls` Worker Lanes in Tmux Window `0:7` (`%132`–`%137`)

---

## Master Execution Checklist

- [x] **Phase 0 — Plan & Dual Review**
  - [x] Draft `docs/PERF-PLAN.md` and `docs/lanes/wave-p-perf.md` with exact code-level root causes across all 9 non-`a32rt` translators.
  - [x] Review `docs/PERF-PLAN.md` and `docs/lanes/wave-p-perf.md` with **`astra` (`codex exec -m gpt-6-astra`)** -> saved [`lode/reviews/2026-10-28-perf-plan-astra.md`](../../lode/reviews/2026-10-28-perf-plan-astra.md).
  - [x] Review `docs/PERF-PLAN.md` and `docs/lanes/wave-p-perf.md` with **`fable` (`claude -p --model fable`)** -> saved [`lode/reviews/2026-10-28-perf-plan-fable.md`](../../lode/reviews/2026-10-28-perf-plan-fable.md).
  - [x] Fold all `astra` and `fable` review findings (exact `results-darwin5-full.tsv` reconciliation, code-page write-gate ordering, syscall copyout invalidation, per-ISA chaining register/prologue contracts, fault-barrier-aware `skip_flags`, sticky-flag-free `FCSR`/`fcsr0`/`FSR` masks, `mips32` `w15` `$ra` clobber fix, `ppc64` arena reset retry, `loongarch64` epilogue PC & miss decoder) into `docs/PERF-PLAN.md` and `docs/lanes/wave-p-perf.md`.
- [ ] **Phase 1 — Parallel Lane Execution (`muse --yolo --parallel-tool-calls` in Tmux Window `0:7`)**
  - [ ] **Lane P1 (`ppc32rt` & `ppc64rt` — Pane `%132`)**:
    - [ ] `ppc32rt`: Remove unconditional `ppc32_cache_invalidate_all(ctx)` on `PPC32_EXIT_SYSCALL` in `src/dbt/dbt.c`; add range invalidation (`ppc32_smc_store` / `ppc32_cache_invalidate_range`) to syscall copyouts (`sys_read`, `sys_pread64`, `sys_readv`, `sys_getdents64`) in `src/os/syscalls.c` when overlapping code pages.
    - [ ] `ppc32rt`: Remove the 3 redundant `isb` pipeline flushes per FP op in `src/dbt/emit_fp.c` and skip `msr fpcr` when `(fpscr & 3U) == 0U` (preserving `fp_accum` and `fp_fprf` for 100% `--difftest` accuracy).
    - [ ] `ppc32rt`: Reuse `ppc32rt`'s existing code-page occupancy bitmap to guard `dbt_emit_smc_hook` (`blr ppc32_smc_store`) inline, checking both start and end pages (`(ea >> 12)` and `((ea + size - 1) >> 12)`) for cross-page stores.
    - [ ] `ppc64rt`: Unify `ppc64_emit_int` and `ppc64_emit_fp` so mixed integer+FP basic blocks compile natively; add `lfs`/`lfd`/`stfs`/`stfd`/`lfsx`/`lfdx`/`stfsx`/`stfdx` + VSX scalar ops (`xsadd*`, `xssub*`, `xsmul*`, `xsdiv*`, `xsmadd*`, `xsmsub*`, `xscmp*`, `xscvdpsp`, `xscvspdpn`); truncate blocks using byte-accurate decoded instruction lengths (never splitting `lwarx`/`stwcx.`); cache 1-insn fallback blocks.
    - [ ] `ppc64rt`: Raise `DBT_MARKS_MAX` from `64u` to `4096u` in `src/dbt/dbt.c`, reuse tail pages in `src/dbt/cache.c` (or call `ppc64_dbt_reset()` and retry on `ppc64_cache_reserve` exhaustion), and add a bounded multi-block IBTC/cache dispatch loop in `ppc64_dbt_step` (disabled when `ppc64_difftest_enabled()`).
  - [ ] **Lane P2 (`rvrt` — `RV64GC` & `RV32GC` — Pane `%133`)**:
    - [ ] `rvrt`: Add `src/dbt_emit_fp.c` + `src/dbt_emit_fp.h` (wired into `DARWIN_RUNTIME_SOURCES` in `Makefile` so both `_build/rvrt-darwin-arm64` and `_build/rvrt-fast-linux-aarch64` include it) lowering RV32/RV64 scalar `F` and `D` ops (`FADD`, `FSUB`, `FMUL`, `FDIV`, `FSQRT`, `FMADD`, `FMSUB`, `FNMSUB`, `FNMADD`, `FSGNJ*`, `FEQ` via `fcmp`, `FLT`/`FLE` via `fcmpe`, `FCVT.*`, `FMV.*`) when `frm` is RNE (`0` or `7` with `ctx->frm == 0`), checking input NaN-boxing on `.s`, canonicalizing output NaNs, and accumulating `FPSR` into `ctx->fflags`.
    - [ ] `rvrt`: Lower `M`-extension `MULH`/`MULHSU`/`MULHU`/`DIV`/`DIVU`/`REM`/`REMU` and `DIVW`/`DIVUW`/`REMW`/`REMUW` inline in `src/dbt_emit_fp.c`.
    - [ ] `rvrt`: Add stack-balanced in-trampoline `jit_lut` chaining in `src/dbt/trampoline_a64.S` + `src/darwin_dbt.c` right after `blr x1` returns (when `exit_reason == RV_DBT_EXIT_BRANCH || RV_DBT_EXIT_INDIRECT` and budget `> 0`), avoiding stack growth and `x21` (`xCPU`) conflicts. Also wire `RVRT_RUNTIME` (`_build/rvrt-linux-aarch64`) or copy `_build/rvrt-fast-linux-aarch64` so Linux standalone benchmarks get the fast DBT.
  - [ ] **Lane P3 (`i686rt` — Pane `%134`)**:
    - [ ] `i686rt`: Lower `ROL`/`ROR` (`C0/C1/D0/D1/D2/D3 /0,/1`), `INC`/`DEC` (`0x40..0x4F`, `FE/FF /0,/1`), `CL`-shifts (`D2/D3 /4,/5,/7`), memory shifts/ALU RMWs, 1-op `MUL`/`IMUL`/`DIV`/`IDIV` (`F6/F7 /4..7`), `ADC`/`SBB`, `BSWAP` (`0F C8..CF`), `SHLD`/`SHRD` (`0F A4/A5/AC/AD`), and memory `NEG`/`NOT` in `src/dbt/emit_alu.c` (+ `src/dbt/emit_alu_ext.c`), preserving `CF` on `INC`/`DEC`, `ZF/SF/PF/AF` on `ROL`/`ROR`, and all flags when shift/rotate `count & 31 == 0`.
    - [ ] `i686rt`: Pre-scan basic-block instructions in `src/dbt/translate.c` to compute fault-barrier-safe `skip_flags[i]` (stopping at any memory access, division, helper call, partial flag writer, or flag reader) so dead `emit_lazy()` stores are eliminated in register-only ALU sequences (`chacha20`, `coremark`) without ever losing flags on a fault.
    - [ ] `i686rt`: Expand SSE2 scalar emission in `src/dbt/emit_sse.c` (`divsd`, `divss`, `sqrtsd`, `sqrtss`, `cvtsi2sd`, `cvtsi2ss`, `cvttsd2si`, `cvttss2si`, `ucomisd`, `ucomiss`, `pxor`) and add a bounded loop budget (`4096`) to `src/trampoline.S`'s existing IBTC loop.
  - [ ] **Lane P4 (`mips32rt` & `mips64rt` — Pane `%135`)**:
    - [ ] `mips32rt`: Fix the clobber of `w15` (cached `$ra`) in `src/dbt/emit_fp.c:488`, remove `if (dbt_is_fp_arith(d)) break;` in `src/dbt/dbt.c`, lower `LWC1`/`SWC1`/`LDC1`/`SDC1` in `src/dbt/emit_mem.c` / `src/dbt/emit_fp.c`, and fast-path `FCSR` in `src/dbt/emit_fp.c` using mask `0x01000F83U` (`FS | Enable | RM`, excluding sticky flags 6:2).
    - [ ] `mips32rt`: Chain blocks inside `src/dbt/trampoline_a64.S` after the block epilogue writes cached GPRs `w0`–`w15` back to `ctx->r[]`, using callee-saved `x23` (IBTC pointer) and `w24` (budget `4096`) to branch directly to the next block's entry without returning to `mips_hostfault_run` on every block.
    - [ ] `mips64rt`: Remove `is_fp_coproc(d)` blocker in `src/dbt/dbt.c`, lower `LWC1`/`LDC1`/`SWC1`/`SDC1` and `COP1X` (`LWXC1`, `LDXC1`, `SWXC1`, `SDXC1`, `MADD.S/D`, `MSUB.S/D`), and fast-path `FCSR` (`mask 0x01000F83U`) in `src/dbt/emit_fp.c`.
    - [ ] `mips64rt`: Remove per-execution `dbt_u0_prefill` (calling it only once at compile time) and duplicate `lookup_entry` in `src/dbt/dbt.c`, wire `MIPS_VM_PAGE_HAS_CODE` + Soft-TLB write-tag eviction on compiled pages so `dbt_snap_match` is only needed when `smc_epoch` advances, use a bump-allocated W^X arena, and add in-trampoline IBTC chaining (updating active block pointer for fault recovery).
  - [ ] **Lane P5 (`sparc32rt` & `sparc64rt` — Pane `%136`)**:
    - [ ] `sparc32rt`: Remove `SPARC32_OP_FPU` from `dbt_falls_through` / `dbt_block_ends` in `src/dbt/dbt.c`, fast-path `FSR` status in `src/dbt/emit_fp.c` when `TEM == 0 && RD == 0`, populate `g_chain` metadata structs `{epoch, code}` in `src/dbt/dbt.c` (clearing on invalidation), and inline aligned loads/stores (`LD`/`ST`/`LDUB`/`STB`/`LDUH`/`STH` with `rev` and code-page bitmap store check) and `SMUL`/`UMUL` in `src/dbt/emit_int.c`.
    - [ ] `sparc64rt`: Fix `fp_sync_fsr` in `src/dbt/emit_fp.c:155` so `FPSR.IXC` (Inexact, bit 4) updates `FSR.cexc` / `FSR.aexc` inline instead of exiting `SPARC64_EXIT_UNDEF` when `TEM == 0 && RD == 0`; lower `FCMPs`/`FCMPd`/`FMOVcc`/`FBfcc` and allow `SPARC64_ICLS_FPU` in delay slots.
    - [ ] `sparc64rt`: Allow Soft-TLB write fills on `PF_X` `.data`/`.bss` pages that contain no translated blocks (`src/dbt/mem_sites.c`), evicting writable TLB tags in `dbt_translate` when a block is compiled on a page; inline `UMUL`/`SMUL`/`UDIVX`/`SDIVX` and fast-path `SAVE`/`RESTORE` (`cansave > 0` / `canrestore > 0`); add epoch-safe in-trampoline IBTC chaining in `src/dbt/trampoline_a64.S` + `src/dbt/dbt.c` (bumping `dbt->epoch` or clearing IBTC on `sparc64_dbt_invalidate`).
  - [ ] **Lane P6 (`loongarch64rt` — Pane `%137`)**:
    - [ ] `loongarch64rt`: Lower all 13 branch instructions (`B`, `BL`, `JIRL`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `BEQZ`, `BNEZ`, `BCEQZ`, `BCNEZ`) in `src/dbt/emit_branch.c` + `src/dbt/emit_int.c`, and update `src/dbt/dbt.c` epilogue so dynamic branch targets in `ctx->pc` are not overwritten by static sequential `next_pc`.
    - [ ] `loongarch64rt`: Lower indexed loads/stores (`LDX_*`, `STX_*`) and FP loads/stores (`FLD_S/D`, `FST_S/D`, `FLDX_S/D`, `FSTX_S/D`) via Soft-TLB in `src/dbt/emit_int.c` / `src/dbt/emit_fp.c`, and extend `la64_dbt_mem_miss` in `src/dbt/dbt_mem.c` to decode and service all new indexed and FP memory forms.
    - [ ] `loongarch64rt`: Wire `vm64_mark_code` + Soft-TLB write-tag revocation on compiled pages and bump `region_epoch` on code-page writes so `cache_lookup` skips per-block `dbt_guest_sum` FNV-1a hashing on hot hits; track unsealed blocks so `dbt_seal_all` is O(1); fast-path `fcsr0` using mask `0x31FU` (`RM | Enables`); add in-trampoline IBTC chaining in `src/dbt/trampoline_a64.S`.
- [ ] **Phase 2 — Qualification & Full Re-Benchmark on `aarch64-darwin-5.lan`**
  - [ ] Verify `make check-line-limits` and `tools/run_catalogue.sh smoke` across all 10 translators (`10/10 PASS`, `0 FAIL`, `0 GAP`).
  - [ ] Rebuild all Linux static-PIE and macOS arm64 translator binaries and sync to `aarch64-darwin-5.lan`.
  - [ ] Run `tools/remote_bench.sh --full` on `aarch64-darwin-5.lan` and verify every translator beats `qemu-<arch>`.
  - [ ] Update `docs/bench/results-darwin5-full.tsv`, `docs/SOFTWARE-CATALOGUE.md`, and `docs/FEATURE-MATRIX.md`, commit cleanly on `master` across all repositories.

---

## Detailed Worker Lane Task Cards

### Lane P1 Card (`../ppc32rt` + `../ppc64rt` — Pane `%132`)
- **Workspaces**: `/Users/angerman/Projects/zw3rk/ppc32rt` and `/Users/angerman/Projects/zw3rk/ppc64rt`
- **Owned Files**: `ppc32rt/src/{dbt,os,vm}/*`, `ppc32rt/Makefile`, `ppc32rt/tests/*`; `ppc64rt/src/{dbt,run,os,vm}/*`, `ppc64rt/Makefile`, `ppc64rt/tests/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/ppc32rt check-line-limits build build-darwin && \
  make -C /Users/angerman/Projects/zw3rk/ppc64rt check-line-limits build build-darwin && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch ppc32rt && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch ppc64rt && \
  /Users/angerman/Projects/zw3rk/ppc32rt/_build/ppc32rt-darwin /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-ppc32 --full && \
  /Users/angerman/Projects/zw3rk/ppc64rt/_build/ppc64rt-darwin-arm64 --dbt /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-ppc64le --full
  ```

### Lane P2 Card (`../rvrt` — Pane `%133`)
- **Workspace**: `/Users/angerman/Projects/zw3rk/rvrt`
- **Owned Files**: `rvrt/src/darwin_dbt.[ch]`, `rvrt/src/dbt_emit_fp.[ch]`, `rvrt/src/dbt/trampoline_a64.S`, `rvrt/src/darwin_main.c`, `rvrt/Makefile`, `rvrt/test/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/rvrt build-darwin _build/rvrt-fast-linux-aarch64 runtime-linux && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch rvrt && \
  /Users/angerman/Projects/zw3rk/rvrt/_build/rvrt-darwin-arm64 -- /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-riscv64 --full && \
  /Users/angerman/Projects/zw3rk/rvrt/_build/rvrt-darwin-arm64 -- /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-riscv32 --full
  ```

### Lane P3 Card (`../i686rt` — Pane `%134`)
- **Workspace**: `/Users/angerman/Projects/zw3rk/i686rt`
- **Owned Files**: `i686rt/src/dbt/*`, `i686rt/src/trampoline.S`, `i686rt/Makefile`, `i686rt/tests/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/i686rt check-line-limits build build-darwin && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch i686rt && \
  /Users/angerman/Projects/zw3rk/i686rt/_build/i686rt-darwin -- /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-i686 --full
  ```

### Lane P4 Card (`../mips32rt` + `../mips64rt` — Pane `%135`)
- **Workspaces**: `/Users/angerman/Projects/zw3rk/mips32rt` and `/Users/angerman/Projects/zw3rk/mips64rt`
- **Owned Files**: `mips32rt/src/{dbt,os,vm}/*`, `mips32rt/Makefile`, `mips32rt/tests/*`; `mips64rt/src/{dbt,os,vm}/*`, `mips64rt/Makefile`, `mips64rt/tests/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/mips32rt check-line-limits build build-darwin && \
  make -C /Users/angerman/Projects/zw3rk/mips64rt check-line-limits build build-darwin && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch mips32rt && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch mips64rt && \
  /Users/angerman/Projects/zw3rk/mips32rt/_build/mips32rt-darwin /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-mipsel --full && \
  /Users/angerman/Projects/zw3rk/mips64rt/_build/mips64rt-darwin-arm64 --dbt /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-mips64el --full
  ```

### Lane P5 Card (`../sparc32rt` + `../sparc64rt` — Pane `%136`)
- **Workspaces**: `/Users/angerman/Projects/zw3rk/sparc32rt` and `/Users/angerman/Projects/zw3rk/sparc64rt`
- **Owned Files**: `sparc32rt/src/{dbt,rt32,os,vm}/*`, `sparc32rt/Makefile`, `sparc32rt/tests/*`; `sparc64rt/src/{dbt,os,vm}/*`, `sparc64rt/Makefile`, `sparc64rt/tests/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/sparc32rt check-line-limits build build-darwin && \
  make -C /Users/angerman/Projects/zw3rk/sparc64rt check-line-limits build build-darwin && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch sparc32rt && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch sparc64rt && \
  /Users/angerman/Projects/zw3rk/sparc32rt/_build/sparc32rt-darwin /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-sparc32 --full && \
  /Users/angerman/Projects/zw3rk/sparc64rt/_build/sparc64rt-darwin-arm64 --dbt /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-sparc64 --full
  ```

### Lane P6 Card (`../loongarch64rt` — Pane `%137`)
- **Workspace**: `/Users/angerman/Projects/zw3rk/loongarch64rt`
- **Owned Files**: `loongarch64rt/src/{dbt,os,vm}/*`, `loongarch64rt/Makefile`, `loongarch64rt/tests/*`
- **Acceptance Command**:
  ```sh
  make -C /Users/angerman/Projects/zw3rk/loongarch64rt check-line-limits build build-darwin && \
  /Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh smoke --arch loongarch64rt && \
  /Users/angerman/Projects/zw3rk/loongarch64rt/_build/loongarch64rt-darwin-arm64 --dbt /Users/angerman/Projects/zw3rk/rt-series/_build/bench/bench-loongarch64 --full
  ```
