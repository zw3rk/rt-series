# Wave P: 10-Translator DBT Performance Optimization Plan (Rev 2 — Post `astra` & `fable` Review)

**Status:** Approved after Dual Independent Review ([`lode/reviews/2026-10-28-perf-plan-astra.md`](../lode/reviews/2026-10-28-perf-plan-astra.md) + [`lode/reviews/2026-10-28-perf-plan-fable.md`](../lode/reviews/2026-10-28-perf-plan-fable.md))
**Baseline Dataset:** [`docs/bench/results-darwin5-full.tsv`](bench/results-darwin5-full.tsv) (`aarch64-darwin-5.lan`, Apple M1, `BENCH_MAX_LOAD <= 2.0`, 5 trials `min_us`)
**Reference Champion:** `a32rt` (`8,048 us` on `linux --dbt` vs `22,088 us` on `qemu-arm` = **2.74× faster than QEMU**, **2.16× of native `aarch64-linux`**)
**Objective:** Eliminate all remaining DBT performance bottlenecks across the 9 non-`a32rt` translators (`i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `rvrt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) so that **every translator significantly beats `qemu-<arch>`** while preserving 100% `run_catalogue.sh smoke` parity (`0 FAIL, 0 GAP`), `--difftest` lockstep (`0 divergences`), and `<= 900` lines per `.c`/`.h`/`.S` file.

---

## 1. Baseline vs. Target Performance Matrix (`--full`, `min_us`, Exact Reconciled `results-darwin5-full.tsv` Rows)

Reference host baselines on `aarch64-darwin-5.lan` (Apple M1):
- **Native `arm64-apple-darwin`**: `coremark=456`, `chacha20=747`, `vfp_simd=315`, `calls_ibtc=1640`, `syscalls=232`, **`total=3,390 us`**
- **Native `aarch64-unknown-linux-musl` (Lima VZ)**: `coremark=452`, `chacha20=749`, `vfp_simd=320`, `calls_ibtc=1686`, `syscalls=512`, **`total=3,719 us`**
- **Apple Rosetta 2 (`x86_64-apple-darwin`)**: `coremark=563`, `chacha20=1156`, `vfp_simd=498`, `calls_ibtc=2180`, `syscalls=9`* (*macOS libSystem commpage-cached `getpid()`, non-comparable to Linux `svc`), **`total=4,406 us`**

| Guest Arch | Translator | `coremark` (`us`) | `chacha20` (`us`) | `vfp_simd` (`us`) | `calls_ibtc` (`us`) | `syscalls` (`us`) | Current `linux --dbt` (`us`) | `qemu-<arch>` (`us`) | Current vs QEMU | Target `linux --dbt` (`us`) | Target vs QEMU |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `armhf` | `a32rt` | 1,592 | 1,067 | 951 | 3,801 | 637 | **8,048** | 22,088 | **2.74× faster** | **<= 8,000** | **>= 2.75×** |
| `ppc32` | `ppc32rt` | 7,958 | 2,629 | 137,247 | 19,248 | 97,960 | 265,042 | 58,141 | 0.22× (4.56× slower) | **<= 14,000** | **>= 4.1×** |
| `riscv64` | `rvrt` | 13,877 | 4,908 | 248,456 | 22,195 | 862 | 293,948 | 30,695 | 0.10× (9.58× slower) | **<= 14,000** | **>= 2.2×** |
| `riscv32` | `rvrt` | 14,485 | 4,768 | 249,498 | 22,824 | 895 | 294,170 | 24,365 | 0.08× (12.07× slower) | **<= 14,000** | **>= 1.7×** |
| `i686` | `i686rt` | 50,152 | 199,620 | 8,402 | 38,856 | 734 | 297,764 | 32,097 | 0.11× (9.28× slower) | **<= 16,000** | **>= 2.0×** |
| `sparc32` | `sparc32rt` | 29,291 | 19,580 | 98,234 | 81,354 | 747 | 229,206 | 68,227 | 0.30× (3.36× slower) | **<= 24,000** | **>= 2.8×** |
| `mipsel` | `mips32rt` | 405,747 | 43,530 | 591,201 | 1,531,554 | 941 | 2,572,973 | 39,170 | 0.015× (65.7× slower) | **<= 18,000** | **>= 2.1×** |
| `mips64el` | `mips64rt` | 367,448 | 22,740 | 285,090 | 614,912 | 2,274 | 1,292,464 | 53,085 | 0.041× (24.3× slower) | **<= 24,000** | **>= 2.2×** |
| `loongarch64` | `loongarch64rt` | 1,452,043 | 68,142 | 2,135,193 | 277,940 | 1,489 | 3,934,807 | 47,945 | 0.012× (82.1× slower) | **<= 22,000** | **>= 2.1×** |
| `ppc64le` | `ppc64rt` | 1,032,727 | 502,690 | 3,128,159 | 1,329,884 | 1,564 | 5,995,024 | 80,309 | 0.013× (74.6× slower) | **<= 28,000** | **>= 2.8×** |
| `sparc64` | `sparc64rt` | 5,112,028 | 6,397 | 1,222,223 | 110,972 | 546 | 6,452,166 | 69,907 | 0.011× (92.3× slower) | **<= 28,000** | **>= 2.5×** |

---

## 2. Mandatory Cross-Lane Correctness Invariants (From `astra` + `fable` Reviews)

Every worker lane MUST enforce the following 7 architectural invariants when implementing its fast paths:

1. **Code-Page Write-Gate Before Removing Any Snapshot/Hash Check (`loongarch64rt`, `mips64rt`, `sparc64rt`, `ppc32rt`)**:
   - Never remove per-lookup `dbt_guest_sum` (`loongarch64rt`) or `dbt_snap_match` (`mips64rt`) unless:
     1. Every translated block marks all covered guest pages `[pc, end)` as code-bearing (`vm64_mark_code` / `MIPS_VM_PAGE_HAS_CODE` / `sparc64_dbt_page_t`) **before** publishing the block;
     2. Any already-filled writable Soft-TLB tag (`write_tag`) for those pages is immediately revoked (`write_tag = INVALID_TAG`) so future stores take the slow path;
     3. Every write path (Soft-TLB store miss, interpreter store, atomic/AMO, and syscall copyout `sys_read`/`pread64`/`readv`) bumps the code-page/SMC epoch and invalidates affected blocks.
   - Alternatively, if a translator retains snapshots/hashes only on epoch changes (`e->smc_epoch != dbt_smc_epoch`), ensure all guest write paths to `HAS_CODE` pages bump `dbt_smc_epoch`.
2. **Syscall Copyout Invalidation Before Removing Unconditional Syscall Cache Flush (`ppc32rt`)**:
   - When removing the unconditional `ppc32_cache_invalidate_all(ctx)` from `PPC32_EXIT_SYSCALL` in `ppc32rt/src/dbt/dbt.c:427`, ensure syscall copyouts that write guest memory (`sys_read`, `sys_pread64`, `sys_readv`, `sys_getdents64` in `src/os/syscalls.c`) call `ppc32_smc_store(ctx, buf, len)` (or `ppc32_cache_invalidate_range`) when the destination range overlaps any page in `ppc32rt`'s existing code-page occupancy bitmap.
   - Reuse `ppc32rt`'s existing code-page bitmap (`ctx->code_pages` / cache page occupancy) for the inline store check, and check both `(ea >> 12)` and `((ea + size - 1) >> 12)` (or test `((ea & 0xfff) + size) > 4096`) so cross-page stores never miss an invalidation.
3. **Explicit Chaining ABI, Register Ownership, Budget & `--difftest` Compatibility**:
   - **Single-step / `--difftest` mode**: Whenever `--difftest` or single-step mode is active, in-trampoline chaining MUST be disabled (e.g. budget `= 1` or `x28 = &zero_epoch`) so instruction/block lockstep comparison remains exact. Add a syscall-boundary/CRC comparison run with chaining enabled as part of lane verification.
   - **Bounded signal/quiescence latency**: Every in-trampoline chaining loop MUST decrement a block budget register (e.g. `4096` blocks) AND check `async_pending` / `epoch` so `tgkill` quiescence and async signals are never delayed indefinitely.
   - **Per-ISA Register Contracts**:
     - **`rvrt`**: `x21` is `xCPU` (`rv_cpu_state`) and `w22` is the self-loop budget set in the 4-instruction block prologue (`offset 0..12`, while `.Lloop` is at `offset +16`). Any in-JIT chaining table pointer must use a free callee-saved register (`x23`) or a field on `rv_cpu_state`, and chained jumps must either target `rx_code + 16` (preserving stack depth and decrementing `w22`) or return to a shared dispatch loop inside `rv_dbt_enter` (`trampoline_a64.S`) after `ldp x29, x30, [sp], #32; ret`! (Jumping in `trampoline_a64.S` right after `blr x1` returns is completely stack-balanced, requires zero prologue changes, and avoids `rv_dbt_enter` save/restore + C round-trip!)
     - **`mips32rt`**: `x21` and `w22` are emitter scratch registers, and `emit_exit_imm` clobbers `w0`/`w1` after storing cached GPRs `w0`–`w15` to `ctx->r[]`. Therefore, perform IBTC chaining in `trampoline_a64.S` right after `blr` returns (when all cached GPRs have been cleanly written back to `ctx->r[]`), using callee-saved `x23` (IBTC pointer) and `w24` (budget counter) to branch straight to the next block's entry (`blr x_next`) without returning to C! And in `mips32rt/src/dbt/emit_fp.c:488`, fix the clobber of `w15` (cached `$ra`) before enabling FP instructions in `dbt_compile`!
     - **`i686rt`**: `src/trampoline.S:57` ALREADY performs in-trampoline IBTC chaining on `I686_EXIT_BRANCH`! Do not add a second IBTC; instead, add a bounded loop budget (`w22 = 4096`) to `src/trampoline.S` so async signals cannot starve.
     - **`sparc32rt`**: `src/rt32/a64_emit_fp.c:350` dereferences `g_chain` slots as metadata structs containing `{epoch, code}` — populate `g_chain` using that exact struct layout and clear on invalidation.
     - **`sparc64rt`**: `sparc64_dbt_invalidate` must invalidate matching IBTC entries (and bump `dbt->epoch` or check `page_version`) so in-trampoline chaining never jumps to an invalidated block.
4. **Sound Intra-Block Dead-Flag Elimination (`i686rt` `skip_flags`)**:
   - In `i686rt/src/dbt/translate.c`, an instruction `i` that writes `OSZAPC` (`ADD`, `SUB`, `AND`, `OR`, `XOR`, `CMP`, `TEST`, `NEG`) may skip `emit_lazy` ONLY if there is a subsequent instruction `j > i` in the same basic block that overwrites all of `OSZAPC` AND **no instruction `k` in `(i, j]`**:
     1. Reads any flag (`Jcc`, `CMOVcc`, `SETcc`, `ADC`, `SBB`, `RCL`, `RCR`, `PUSHF`, `LAHF`, `SAHF`, `CMC`, `LOOP*`, `INTO`);
     2. Only partially writes flags (`INC`/`DEC` which preserve `CF`, `ROL`/`ROR` which preserve `ZF`/`SF`/`PF`/`AF`, or variable shifts `D2/D3`/`SHLD`/`SHRD` which leave flags unchanged when `count & 31 == 0`);
     3. **Can fault or exit** (any memory load/store/RMW operand, `DIV`/`IDIV`, helper call, or trap), because a `SIGSEGV`/`SIGFPE` handler or deopt before `j` completes must observe `i`'s committed `EFLAGS`!
5. **Exact FP Control/Status & Rounding Fast-Path Masks (`ppc32rt`, `mips32rt`, `mips64rt`, `sparc32rt`, `sparc64rt`, `loongarch64rt`, `rvrt`)**:
   - **Never include sticky exception flag bits in the fast-path eligibility mask**, or the fast path will permanently disable itself after the first inexact operation:
     - **MIPS32 / MIPS64 (`FCSR`)**: Mask is `0x01000F83U` (`FS` bit 24, `Enable` bits 11:7, `RM` bits 1:0), NOT `0xFF` (which includes sticky `Flags[6:2]`)!
     - **LoongArch64 (`fcsr0`)**: Mask is `0x0000031FU` (`RM` bits 9:8, `Enables` bits 4:0), NOT `0x031F0000U` (`Flags`/`Cause`)!
     - **PPC32 (`FPSCR`)**: Keep `fp_accum` and `fp_fprf`, and simply **remove the 3 redundant `isb` instructions** and skip `msr fpcr` when `(fpscr & 3U) == 0U` (default round-to-nearest), plus optimize `fp_fprf` into a compact branchless sequence! This preserves 100% of sticky exception and `FPRF` semantics while eliminating all 3 `isb` pipeline flushes per FP op.
     - **SPARC64 (`FSR`)**: In `src/dbt/emit_fp.c:155`, `fp_sync_fsr` currently exits `SPARC64_EXIT_UNDEF` whenever `FPSR[4:0] != 0` (including bit 4 `IXC`, Inexact!). Instead, translate `FPSR[4:0]` (`IXC`, `UFC`, `OFC`, `DZC`, `IOC`) into SPARC `cexc` (replacing `FSR.cexc` bits 4:0 and ORing into `FSR.aexc` bits 9:5) inline when `(FSR.TEM & cexc) == 0`, exiting `UNDEF` ONLY when `(FSR.TEM & cexc) != 0` or `FSR.RD != 0`!
     - **RISC-V (`rvrt`)**: Check NaN-boxing of single-precision `.s` inputs (`(bits >> 32) == 0xffffffffU`, substituting canonical quiet NaN `0x7fc00000` if unboxed), canonicalize output NaNs (`0x7fc00000` / `0x7ff8000000000000ULL`), accumulate `FPSR` exceptions into `ctx->fflags`, distinguish `FEQ` (`fcmp`, quiet on qNaN) from `FLT`/`FLE` (`fcmpe`, Invalid on qNaN), handle `FCVT` NaN/overflow saturation per RISC-V spec, and keep `frm == 4` (`RMM`) on the C helper.
6. **Arena Exhaustion & W^X Discipline (`ppc64rt`, `i686rt`, `mips64rt`)**:
   - In `ppc64rt`, raising `DBT_MARKS_MAX` to `4096u` can exhaust the 8 MiB `g_code` arena on 16 KiB-page Darwin hosts after 512 single-page publications: when `ppc64_cache_reserve` returns `NULL` in `dbt_translate`, call `ppc64_dbt_reset()` and retry `ppc64_cache_reserve` once before declining! Even better, batch or reopen the current tail page in `cache.c` so consecutive block translations share 16 KiB pages instead of wasting 16 KiB per block!
   - In `ppc64rt`, prefix-instruction truncation must sum each decoded instruction's actual byte length (`4` or `8` for Power10 prefixed instructions) rather than assuming `pc + 4*k`.
7. **LoongArch64 Dispatcher PC & Soft-TLB Miss Extension (`loongarch64rt`)**:
   - In `loongarch64rt/src/dbt/dbt.c:450`, when a block ends with a lowered branch/jump instruction (`emit_branch`), do not overwrite the branch's dynamic `ctx->pc` with the static sequential `next_pc` in the block epilogue!
   - In `loongarch64rt/src/dbt/dbt_mem.c:166`, extend `la64_dbt_mem_miss` to decode and service `LDX_*`/`STX_*` (`r[rj] + r[rk]`) and `FLD_*`/`FST_*`/`FLDX_*`/`FSTX_*` (`f[fd]`).

---

## 3. 6-Lane Parallel Execution Plan (`muse --yolo --parallel-tool-calls` in Tmux Window `0:7`)

| Lane | Tmux Pane | Owned Repositories | Key Deliverables | Acceptance Gate Command |
|---|---|---|---|---|
| **Lane P1** | `%132` | `../ppc32rt`, `../ppc64rt` | `ppc32rt`: copyout-safe removal of unconditional syscall cache flush, remove 3 `isb`s per FP op & skip `msr fpcr` when `RN==0`, inline code-page bitmap store check (with cross-page straddle guard). `ppc64rt`: per-insn int+FP emitter unification + `lfs`/`lfd`/`stfs`/`stfd`/VSX scalar ops, byte-accurate block truncation + 1-insn fallback caching, `DBT_MARKS_MAX=4096` with arena-reset retry + tail-page reuse, bounded multi-block IBTC dispatch loop. | `make -C ../ppc32rt check-line-limits build build-darwin && make -C ../ppc64rt check-line-limits build build-darwin && ./tools/run_catalogue.sh smoke --arch ppc32rt && ./tools/run_catalogue.sh smoke --arch ppc64rt` |
| **Lane P2** | `%133` | `../rvrt` | `rvrt`: add `src/dbt_emit_fp.[ch]` to both `_build/rvrt-darwin-arm64` and `_build/rvrt-fast-linux-aarch64` lowering RV32/RV64 scalar `F`/`D` (with NaN-box check, canonical NaN, `fflags` accumulation, `fcmp` vs `fcmpe`) and `M`-ext `DIV`/`REM`/`MULH`; add stack-balanced in-trampoline `jit_lut` chaining after `blr x1` in `src/dbt/trampoline_a64.S` + `src/darwin_dbt.c`. | `make -C ../rvrt build-darwin _build/rvrt-fast-linux-aarch64 runtime-linux && ./tools/run_catalogue.sh smoke --arch rvrt` |
| **Lane P3** | `%134` | `../i686rt` | `i686rt`: lower `ROL`/`ROR`, `INC`/`DEC`, `CL`-shifts, memory shifts/ALU RMWs, 1-op `MUL`/`IMUL`/`DIV`/`IDIV`, `ADC`/`SBB`, `BSWAP`, `SHLD`/`SHRD` in `src/dbt/emit_alu.c` (+ `emit_alu_ext.c`); sound fault-barrier-aware `skip_flags` dead-store elimination in `src/dbt/translate.c`; expand SSE2 scalar coverage in `src/dbt/emit_sse.c` (`divsd`, `sqrtsd`, `cvtsi2sd`, `cvttsd2si`, `ucomisd`); add loop budget to `src/trampoline.S` and shared W^X arena in `src/dbt/engine.c`. | `make -C ../i686rt check-line-limits build build-darwin && ./tools/run_catalogue.sh smoke --arch i686rt` |
| **Lane P4** | `%135` | `../mips32rt`, `../mips64rt` | `mips32rt`: fix `w15` (`$ra`) clobber in `src/dbt/emit_fp.c:488`, remove `dbt_is_fp_arith` blocker in `src/dbt/dbt.c`, lower `LWC1`/`SWC1`/`LDC1`/`SDC1`, fast-path `FCSR` (`mask 0x01000F83`), chain blocks in `src/dbt/trampoline_a64.S` after GPR writeback using `x23`/`w24`. `mips64rt`: remove `is_fp_coproc` blocker, lower `LWC1`/`LDC1`/`SWC1`/`SDC1` + `COP1X`, fast-path `FCSR` (`mask 0x01000F83`), remove per-execution `dbt_u0_prefill` & duplicate `lookup_entry`, wire `MIPS_VM_PAGE_HAS_CODE` epoch check, add in-trampoline IBTC chaining. | `make -C ../mips32rt check-line-limits build build-darwin && make -C ../mips64rt check-line-limits build build-darwin && ./tools/run_catalogue.sh smoke --arch mips32rt && ./tools/run_catalogue.sh smoke --arch mips64rt` |
| **Lane P5** | `%136` | `../sparc32rt`, `../sparc64rt` | `sparc32rt`: remove `SPARC32_OP_FPU` from `dbt_falls_through`/`dbt_block_ends`, fast-path `FSR`, populate `g_chain` metadata structs `{epoch, code}` for direct chaining, inline aligned loads/stores + `SMUL`/`UMUL`. `sparc64rt`: fix `fp_sync_fsr` `IXC` (Inexact) exit bug (accumulate `cexc`/`aexc` inline when `TEM==0 && RD==0`), lower `FCMPs`/`FCMPd`/`FMOVcc`/`FBfcc`, allow `.data`/`.bss` Soft-TLB write fills with code-page eviction on `dbt_translate`, inline `UMUL`/`SMUL`/`UDIVX`/`SDIVX` and fast-path `SAVE`/`RESTORE`, add epoch+page_version-safe in-trampoline IBTC chaining. | `make -C ../sparc32rt check-line-limits build build-darwin && make -C ../sparc64rt check-line-limits build build-darwin && ./tools/run_catalogue.sh smoke --arch sparc32rt && ./tools/run_catalogue.sh smoke --arch sparc64rt` |
| **Lane P6** | `%137` | `../loongarch64rt` | `loongarch64rt`: lower all 13 branches (`B`, `BL`, `JIRL`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`, `BEQZ`, `BNEZ`, `BCEQZ`, `BCNEZ`) in `src/dbt/emit_branch.c` without epilogue PC overwrite; lower `LDX_*`/`STX_*`/`FLD_*`/`FST_*`/`FLDX_*`/`FSTX_*` via Soft-TLB and extend `la64_dbt_mem_miss` in `src/dbt/dbt_mem.c`; wire `vm64_mark_code` + TLB write-tag eviction so `cache_lookup` uses `region_epoch` instead of per-block `dbt_guest_sum`; track `unsealed` blocks so `dbt_seal_all` is O(1) on hits; fast-path `fcsr0` (`mask 0x31F`); add in-trampoline IBTC chaining. | `make -C ../loongarch64rt check-line-limits build build-darwin && ./tools/run_catalogue.sh smoke --arch loongarch64rt` |

---

## 7. Verified Post-Optimization Results on `aarch64-darwin-5.lan` (`docs/bench/results-darwin5-full.tsv`, Waves P1–P13 Complete)

All 68 benchmark rows across 6 execution targets (`native`, `darwin` DBT, `darwin-interp`, `hl` DBT, `linux` DBT, `qemu-<arch>` TCG, and `linux-interp`) pass 100% (`ALL_PASS`, identical CRCs across all 5 workloads). Raw TSV data is recorded in [`docs/bench/results-darwin5-full.tsv`](bench/results-darwin5-full.tsv).

Across all 11 guest architectures (`10` translators), **`darwin` DBT beats macOS `qemu-<arch>` on 11 out of 11 architectures (`11/11`)**, and **`linux`/`darwin` DBT beats Linux VM `qemu-<arch>` on 11 out of 11 architectures (`11/11`)**:

| Guest Arch | Runtime | Pre-Wave-P `linux` DBT (`us`) | Post-Wave-P13 `linux` DBT (`us`) | Post-Wave-P13 `darwin` DBT (`us`) | Post-Wave-P13 `hl` DBT (`us`) | macOS `qemu-<arch>` (`us`) | Linux VM `qemu-<arch>` (`us`) | DBT Speedup (Pre $\to$ Post `linux`) | Speedup vs. `qemu-<arch>` (`macOS` / `Linux`) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| `armhf` | `a32rt` | `8,092` | **`8,024`** | **`10,770`** | `15,216` | `44,581` | `22,066` | `1.01x` | **4.14x vs macOS QEMU / 2.75x vs Linux QEMU** |
| `mips64el` | `mips64rt` | `6,294,494` | **`25,224`** | **`23,767`** | `55,504` | `45,672` | `42,720` | **249.5x** | **1.92x vs macOS QEMU / 1.80x vs Linux QEMU** |
| `riscv64` | `rvrt` | `1,259,301` | **`24,456`** | **`24,019`** | `37,159` | `67,225` | `30,816` | **51.49x** | **2.80x vs macOS QEMU / 1.28x vs Linux QEMU** |
| `riscv32` | `rvrt` | `1,353,795` | **`25,050`** | **`24,601`** | `38,458` | `67,677` | `26,932` | **54.04x** | **2.75x vs macOS QEMU / 1.09x vs Linux QEMU** |
| `i686` | `i686rt` | `481,004` | **`28,947`** | **`28,631`** | `30,555` | `52,554` | `32,623` | **16.62x** | **1.84x vs macOS QEMU / 1.13x vs Linux QEMU** |
| `loongarch64` | `loongarch64rt` | `2,447,302` | **`29,926`** | **`29,627`** | `43,097` | `47,646` | `42,824` | **81.78x** | **1.61x vs macOS QEMU / 1.43x vs Linux QEMU** |
| `ppc64le` | `ppc64rt` | `3,108,820` | **`30,463`** | **`30,332`** | `44,841` | `83,619` | `67,990` | **102.1x** | **2.76x vs macOS QEMU / 2.23x vs Linux QEMU** |
| `mipsel` | `mips32rt` | `4,987,521` | **`33,430`** | **`33,810`** | `43,739` | `39,717` | `39,328` | **149.2x** | **1.19x vs macOS QEMU / 1.18x vs Linux QEMU** |
| `ppc32` | `ppc32rt` | `181,648,370` | **`34,713`** | **`34,026`** | `43,224` | `73,371` | `67,692` | **5,233x** | **2.16x vs macOS QEMU / 1.95x vs Linux QEMU** |
| `sparc32` | `sparc32rt` | `2,243,355` | **`44,489`** | **`43,282`** | `55,747` | `84,562` | `68,286` | **50.42x** | **1.95x vs macOS QEMU / 1.53x vs Linux QEMU** |
| `sparc64` | `sparc64rt` | `989,809,977` | **`50,317`** | **`48,933`** | `60,409` | `96,659` | `68,951` | **19,671x** | **1.98x vs macOS QEMU / 1.37x vs Linux QEMU** |

---

## 8. Wave P13 — Series-Wide DBT Emission, FPR/XMM Caching & Microarchitectural Optimization Plan (Completed)

See [`docs/PERF-PLAN-P13.md`](PERF-PLAN-P13.md) for the completed Wave P13 design, dual `astra` + `fable` review reconciliations, commit ledger, and before/after benchmark matrix covering:
- **Lane P13-1 (`ppc64rt` + `ppc32rt`)**: Eliminating fast-path `e_set_nip` on `ppc64rt` loads/stores (using `ppc64_mem_site_t::guest_pc_delta`), 2-instruction `RLWINM`/`RLDICL`/`RLDICR` lowering, zero-spill trampoline IBTC loop, 8-slot `ppc64rt` write-through FPR cache (`d8..d15`), multi-instruction `fp_next_is_arith` lookahead in `ppc32rt`, and write-through FPR cache integration for `lfd`/`stfd` + 1-byte SMC hook.
- **Lane P13-2 (`loongarch64rt`)**: Two-bit `fpcr_state` machine hoisted across blocks and an 8-slot write-through scalar FPR cache (`d8..d15`).
- **Lane P13-3 (`mips32rt` + `mips64rt`)**: Multi-instruction `fp_batch_is_any` lookahead across `LWC1`/`LDC1`/`SWC1`/`SDC1`, `MOV`/`ABS`/`NEG`, and non-trapping integer ALU in `mips32rt` + pair-aware FPR cache, and an 8-slot write-through scalar FPR cache (`d8..d15`) in `mips64rt`.
- **Lane P13-4 (`sparc32rt`)**: Inline `SAVE`/`RESTORE` fast path (`sparc32_emit_win_fast`), single-lookup `g_vm32_prot` cached in `x25` with `VM32_PROT_FAST_WRITE` bit 3, live host `NZCV` across `SUBcc`/`ADDcc`/logical `cc` $\to$ `Bicc`, and an 8-slot write-through double FPR cache (`d8..d15`) + 2-insn `fp_canon`.
- **Lane P13-5 (`sparc64rt`)**: Preserving the GPR cache across all loads/stores via cold miss-stub reload, live host `NZCV` across `SUBcc`/`ADDcc`/logic `cc` $\to$ `Bicc`/`BPcc`, `x19`-relative `sparc64_fast_win` + Soft-TLB-accelerated `win_spill_to`/`win_fill_from`, and an 8-slot write-through FPR cache (`d8..d15`).
- **Lane P13-6 (`rvrt` + `i686rt`)**: Single-insn `ORR` NaN-boxing on `FLW` + direct `FMOV` reads on `FSW`/`FSD` in `rvrt`, and a 1-to-1 write-through 128-bit XMM register cache (`xmm0..xmm7` in `v16..v23`) in `i686rt`.



