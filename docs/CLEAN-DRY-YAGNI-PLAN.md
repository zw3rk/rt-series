# CLEAN, DRY, YAGNI & Curated-C11 Codebase Remediation Plan

> **Authoritative Audit Reports (`gpt-6-astra`, `xhigh`)**:
> 1. [`lode/reviews/2026-10-28-clean-dry-yagni-a32-i686-ppc32-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-a32-i686-ppc32-astra.md) — `a32rt`, `i686rt`, `ppc32rt`
> 2. [`lode/reviews/2026-10-28-clean-dry-yagni-mips32-sparc32-rvrt-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-mips32-sparc32-rvrt-astra.md) — `mips32rt`, `sparc32rt`, `rvrt`
> 3. [`lode/reviews/2026-10-28-clean-dry-yagni-la64-ppc64-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-la64-ppc64-astra.md) — `loongarch64rt`, `ppc64rt`
> 4. [`lode/reviews/2026-10-28-clean-dry-yagni-mips64-sparc64-series-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-mips64-sparc64-series-astra.md) — `mips64rt`, `sparc64rt`, `rt-series`
> 5. [`lode/reviews/2026-10-28-clean-dry-yagni-dbt-subsystem-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-dbt-subsystem-astra.md) — Cross-cutting DBT Subsystem
> 6. [`lode/reviews/2026-10-28-clean-dry-yagni-os-backends-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-os-backends-astra.md) — Cross-cutting OS Backends, Syscalls & Signals
> 7. [`lode/reviews/2026-10-28-clean-dry-yagni-vm-softtlb-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-vm-softtlb-astra.md) — Cross-cutting VM, Soft-TLB, SMC, ELF & Family Coordination
> 8. [`lode/reviews/2026-10-28-clean-dry-yagni-interp-build-astra.md`](../lode/reviews/2026-10-28-clean-dry-yagni-interp-build-astra.md) — Cross-cutting Interpreters, Decoders, Makefiles & Benchmark/Test Harnesses

---

## 1. Critical DBT Bugs Already Remediated & Verified (`2026-10-28`)

The following high-priority DBT correctness and performance bugs surfaced by `astra` were fixed immediately and verified against `-O2` guest benchmarks:

- [x] **`loongarch64rt` — `LA64_OP_FPU_TRAP` site-drain leak & empty fallback mark** (`src/dbt/dbt.c:381,445`):
  - Premature `continue;` on `LA64_OP_FPU_TRAP` skipped `dbt_mem_site_take(&s, &fpc)`, leaving `stage_pending = 1` after the first FP load/store and declining all subsequent memory ops in the block.
  - Also fixed `fallback = (count == 0)` so blocks with a translated native prefix are not marked as empty fallback stubs.
- [x] **`loongarch64rt` — Chained block `ctx->pc` clobber on fallthrough/direct/indirect exits** (`src/dbt/dbt.c:713`):
  - When `trampoline_a64.S` chained `Block A -> Block B` via `dbt_chain_next` and `Block B` exited via `LA64_DBT_EXIT_FALLTHROUGH`, `dbt_run` overwrote `ctx->pc` with `b->next_pc` (from `Block A`) instead of preserving `ctx->pc` written by `Block B`'s epilogue.
- [x] **`loongarch64rt` — Enable indirect exit chaining in trampoline** (`src/dbt/trampoline_a64.S:64`):
  - Changed `cmp w0, #1` to `cmp w0, #2` so `LA64_DBT_EXIT_INDIRECT` (`2`, i.e., `JIRL` returns and indirect calls) chains in-trampoline via `dbt_chain_next`.
- [x] **`loongarch64rt` — 64 KiB page-per-block exhaustion in `dbt_code_alloc` & SMC epoch refresh** (`src/dbt/dbt_code.c:121`, `src/dbt/dbt.c:158,246,486`, `src/dbt/dbt_mem.c:341`):
  - `dbt_code_alloc` previously sealed a full 64 KiB `mmap` page on every block, exhausting `DBT_MAX_PAGES = 1024` during `coremark` and forcing `chacha20`, `vfp_simd`, and `calls_ibtc` into the interpreter (**55x regression**). Fixed `dbt_code_alloc` to re-open the active tail page RW when appending, raised `DBT_CACHE_ENTRIES` to `4096u`, refreshed `b->smc` after re-hash, page-aligned `vm64_mark_code(p0, p1)`, and fixed `dbt_rewind_hook` return polarity.
- [x] **`loongarch64rt` — Caller-saved NEON scratch registers & `v_shreg` shift mask** (`src/dbt/emit_fp.c:41,870`):
  - Moved scratch NEON registers `VJ, VK, VT` from callee-saved `v8..v10` to caller-saved `v16..v18`, and preserved `VT` across both 64-bit lanes in `v_shreg`.
- [x] **`mips64rt` — Delay-slot stack buffer overflow, `J`/`JAL` upper mask, and `ef_cmp` NaN branch polarity** (`src/dbt/dbt.c:457`, `src/dbt/emit_int.c:216`, `src/dbt/emit_fp.c:558`):
  - Prevented 1-element stack buffer overflow on `insns[64]` when the 64th instruction of a block has a branch delay slot; fixed `J`/`JAL` upper mask to `~UINT64_C(0xFFFFFFF)` (28 bits); fixed `ef_cmp` NaN fallback branch (`cbz` instead of `cbnz`).
- [x] **`ppc64rt` — `stfdu` (`po == 55`) truncating 64-bit double to 32-bit float** (`src/dbt/emit_fp_vs.c:208`):
  - Fixed `po == 55u` in `v_dform` to load the full 64-bit double from `OFF_VSR + 16u * frt` and emit an 8-byte store site (`v_site(e, 8u, ...)`).
- [x] **`rvrt` — `FCVT` `x2` clobber by `emit_accum`, `FMADD.S` `x3` clobber by `emit_unbox_s`, and `UMULH` encoding** (`src/dbt_emit_fp.c:453,580,699,705`):
  - Moved `emit_accum(b)` after storing `x2` (`FCVT` result) to `rd`; moved `emit_load_f(b, 3, rs3)` after `emit_unbox_s(b, 0/1)`; fixed `UMULH` opcode base from `0x9bb17c00u` to `0x9bc07c00u`.

---

## 2. Prioritized Remediation Backlog (Remaining Findings)

### Phase C1 — P1 Correctness, Bounds & Curated-C11 Safety

- [ ] **C1.1 — Prohibited `strcpy` elimination (Curated C11 rule)**:
  - `i686rt/src/os/syscalls.c:495`, `i686rt/src/os/sys_pass.c:585`, `i686rt/src/os/sys_stat.c:518`: Replace `strcpy` with bounded `memcpy` using known `strlen` + 1.
  - `sparc64rt/src/os/guest_proc.c:109`: Replace `strcpy(out, p)` with `snprintf(out, cap, "%s", p)` and check truncation.
- [ ] **C1.2 — Emitter branch-patch bounds checks at buffer capacity**:
  - `a32rt/src/dbt/a64_emit.c:49,54`, `i686rt/src/dbt/rt32_a64_emit.c:76,81`, `ppc32rt/src/dbt/a64_emit.c:49,54`, `sparc32rt/src/dbt/a64_emit.c:45,50`, `ppc64rt/src/dbt/emit_int.c:59`, `rvrt/src/dbt_emit_fp.c:308`: Guard `e->code[idx]` / `b->code[at]` writes with `idx < e->cap` (or `!b->overflow`).
- [ ] **C1.3 — Syscall & VM correctness bugs**:
  - `ppc32rt/src/os/syscalls.c:198`: `sys_readv` decrements `total` inside its SMC invalidation loop and returns `0` instead of the bytes read; use a separate `rem = (size_t)total` loop counter.
  - `mips32rt/src/dbt/emit_mem.c:99` vs `mips32rt/src/os/mem.c:381`: Unify LL/SC epoch table index bit-width (12-bit `(addr >> 6) & 0xFFFu` in both DBT `UBFM` and `mem.c`).
  - `mips32rt/src/vm/vm_file.c:290,328`: Fix little-endian O32 `truncate64`/`ftruncate64` 64-bit length assembly (`((uint64_t)a3 << 32) | (uint64_t)a2`).
  - `a32rt/src/interp/interp_thumb.c:167`: Fix swapped Thumb data-processing opcodes `0xA` (`CMP`), `0xB` (`CMN`), `0xC` (`ORR`), `0xD` (`MUL`).
  - `ppc64rt/src/run/load.c:105,137` & `mips64rt/src/loader.c:127,184`: Add `p_filesz > p_memsz` and overflow checks before `pread`/`memset`.
- [ ] **C1.4 — Interpreter C11 Undefined Behavior (`signed <<` & float-to-int range guards)**:
  - Cast signed operands to `uint32_t`/`uint64_t` before left-shifting in `a32rt`, `mips32rt`, `sparc32rt`, `loongarch64rt`, `mips64rt`, `sparc64rt`.
  - Round before float-to-int bounds comparisons and use exclusive upper bounds (`>= 2147483648.0`, `>= 9223372036854775808.0`) in `a32rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `loongarch64rt`, `mips64rt`, `sparc64rt`.

### Phase C2 — P2 Intra-Repo DRY Consolidation (Zero Cross-Repo Coupling)

- [ ] **C2.1 — Extract shared OS backend helpers (`os_common.c` / `backend_common.h`) per repo**:
  - Factor identical ELF loader, `/proc/self/*` synthesis, path translation, and Darwin/Linux worker-thread lifecycle code out of `backend_linux*.c` and `backend_darwin*.c` in `mips64rt` (222 duplicate lines), `ppc64rt` (326 duplicate lines), `mips32rt` (94 duplicate lines), and `ppc32rt` (47 duplicate lines).
- [ ] **C2.2 — Unify duplicate AArch64 instruction encoders within each repo**:
  - `mips64rt`: Consolidate `src/dbt/a64_emit.c` and `src/dbt/emit_enc.c` (`ei_*` vs `a64e_*`).
  - `sparc64rt`: Consolidate `src/dbt/emit_rt.c` and `src/dbt/emit_priv.h`.
  - `rvrt`: Consolidate `src/jit/emit.h` and `src/dbt_emit_fp.h` (`rv_a64_*` vs `rv_dbt_a64_*`).
- [ ] **C2.3 — Unify duplicate SPARC64 instruction fields (`interp.c` vs `decode.c`)**:
  - Have `sparc64rt/src/interp/interp.c` reuse `sparc64_decode()` from `src/interp/decode.c`.

### Phase C3 — P3 YAGNI Pruning & CLEAN File-Size Decomposition

- [ ] **C3.1 — Delete dead scaffolding and unused symbols**:
  - `ppc64rt`: Remove obsolete whole-block `ppc64_emit_int` / `ppc64_emit_fp` wrappers and weak stubs in `src/dbt/dbt_ stubs.c`.
  - `mips64rt`: Remove unused `a64e_*` emitters and unused `ef_fhalf` helper.
  - `i686rt`: Remove unused ARM donor helpers (`a64_emit_b_cond`, `a64_emit_cbz`, etc.) in `src/dbt/rt32_a64_emit.c:872-1047`.
  - `sparc32rt` / `sparc64rt` / `loongarch64rt`: Remove write-only `ras_sp`/`ras_stack` fields where RAS is not queried.
- [ ] **C3.2 — Replace textual `#include "*.c"` unity chains with proper `.c` translation units**:
  - `a32rt/src/interp/interp_arm.c` (`interp_arm_mem.c`, `interp_arm_vfp.c`), `loongarch64rt/src/os/backend_linux.c`, `mips64rt/src/os/backend_{linux,darwin}.c`.
- [ ] **C3.3 — Split oversized translation units (`> 1,000` lines)**:
  - `i686rt`: Split `src/interp/{x87_80.c,h_x87.c,h_sse.c}` and `src/dbt/emit_sse.c` into focused arithmetic/load-store/conversion units.
  - `rvrt`: Split `src/runtime_main.c` (`8,201` lines) and `src/family.c` (`4,639` lines) into cohesive sub-modules.
  - `rt-series/bench/guest_bench.c` (`1,182` lines): Split into `bench_main.c`, `bench_workloads.c`, and `bench_syscalls.h`.
