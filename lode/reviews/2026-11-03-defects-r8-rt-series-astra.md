# Round-8 Deep-Dive 2 — Static Audit Report

Read-only audit. No files created, modified, or deleted. No builds or tests run.

## Summary

| ID | Area | Symptom | Fix |
|---|---|---|---|
| RTS-R8-1 | Page size | `AT_PAGESZ` all-4096 | Carve out 8192 |
| RTS-R8-2 | Host caps | Bits 10-11 missing | Document both bits |
| RTS-R8-3 | Reg `x20` | `xG` only, no TLB | Add A1/A2 meaning |
| RTS-R8-4 | IBTC/RAS | Link, no flush rule | Gate on epoch |
| RTS-R8-5 | I-cache | No Darwin flush | Require `sys_icache` |
| RTS-R8-6 | Runner args | Missing `--` | Append `--` |
| RTS-R8-7 | Grind engines | Single-engine only | Run both, compare |
| RTS-R8-8 | Torture oracle | QEMU optional | Require oracle |
| RTS-R8-9 | P3 fixture | No SMC test | Add SMC test |

## Defects

### RTS-R8-1 — `AT_PAGESZ` contradiction on `sparc64rt`

- [HOST-CONTRACT.md](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:36) says every Class-A and Class-B translator reports `AT_PAGESZ = 4096`.
- [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:92) `D11` and [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:178) require `AT_PAGESZ = 8192` on `sparc64rt`, with 8 KiB alignment and paired 4 KiB Soft-TLB entries.
- A guest reading `AT_PAGESZ` gets the wrong granule, and 4 KiB-only alignment checks accept 4 KiB-aligned `sparc64rt` mappings the kernel would reject.
- Fix: amend `HOST-CONTRACT.md:36` to except `sparc64rt` with `8192`, and note 8 KiB `mmap`/`mprotect`/`munmap` alignment there.

### RTS-R8-2 — `A32H_CAP_FIXADE` and `A32H_CAP_SOFT_TLB_256M` undocumented

- [include/a32host.h](/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h:50) defines bit 10 `FIXADE` and bit 11 `SOFT_TLB_256M` as ABI 1.1.
- [HOST-CONTRACT.md](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:102) versioning and caps list at lines 106-114 stop at bit 9 `HW_TSO`.
- MIPS `FIXADE` negotiation and Regime-A2 support are undiscoverable through the contract.
- Fix: document both bits and change the minor-revision text to cover bits 9-11.

### RTS-R8-3 — Stale `x20 = guest base` invariant

- [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:22), `D2` at line 83, and `mips32` register map at line 273 state `x20 = xG` with `[x20, wAddr, uxtw]` unconditionally.
- [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:363) Regime A2 binds `x20 = &ctx->tlb[0]` with the 7-instruction Soft-TLB on `H > 4096`.
- DBT emitted for the wrong `x20` meaning mis-translates every access on 16 KiB or 64 KiB hosts.
- Fix: add the A1/A2 dual meaning to `SPEC.md`, matching `UNIFICATION-PLAN.md:167-169`.

### RTS-R8-4 — IBTC direct linking without invalidation rule

- [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:127) endorses IBTC direct block linking with no invalidation condition.
- [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:341) requires epoch bump plus preemption, and range-selective invalidation at lines 348-349.
- A chained IBTC entry survives `munmap`, `mprotect`, or SMC and executes stale code.
- Fix: permit direct linking only on epoch-gated dispatch and invalidate overlapping blocks, IBTC, and RAS on every mutation.

### RTS-R8-5 — `ICACHE_TRAP_IALLU` versus explicit invalidation

- [HOST-CONTRACT.md](/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md:109) describes EL2 `IC IVAU` trapping.
- [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:92) lists Darwin `MAP_JIT` with no I-cache step, and `rt_host_jit_seal_rx` at line 465 states no maintenance semantics.
- Darwin JIT without `sys_icache_invalidate` executes stale instructions. Native Linux without `/dev/a32host` has no EL2 trap either.
- Fix: specify that the trap applies only when the cap is set under `hyper-linux`; otherwise use `__builtin___clear_cache`, and on Darwin use `pthread_jit_write_protect_np(1)` plus `sys_icache_invalidate`.

### RTS-R8-6 — Missing `--` separator for new Class-B translators

- [remote_bench_common.sh](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:35) fallback prints `%s --%s` with no `--`; the translator branches at lines 71-77 and 128-137 also omit `--` before the guest path.
- Class-B contract requires `-- <TARGET> <ARGV0>`; the `rvrt` branch includes it. The fallback covers `loongarch64rt`, `ppc64rt`, `mips64rt`, and `sparc64rt`.
- The guest path can be parsed as a translator option and `argv[0]` is wrong.
- Fix: emit `%s --%s --` and insert `--` before `"$_rrt_guest"` and `"$_rrh_guest"`.

### RTS-R8-7 — Single-engine grind suites mask divergence

- [run_grind.sh](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:602) builtins runs interp-or-dbt; lines 630 and 691 run dbt-or-interp; lines 277 and 296 run foreign `stress-ng` under DBT only.
- TestFloat at lines 536-549 skips the missing engine and can still pass with `GRIND_ALLOW_SKIP=1`.
- A passing run may never have executed one engine.
- Fix: run both configured engines in each suite and compare, or fail when an engine is missing.

### RTS-R8-8 — `gcc-torture` passes without an independent oracle

- [run_grind.sh](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:341) requires only `INTERP` plus `DBT`; `QEMU` is optional.
- Lines 383-385 promote the first successful engine output to the reference.
- Shared `interp` and `dbt` bugs pass with no `qemu-<arch>` check, violating `SPEC.md` dual-engine plus oracle rule.
- Fix: require `GRIND_QEMU` or a committed golden oracle for foreign-arch passes; otherwise report `GAP` or `SKIP`, not `PASS`.

### RTS-R8-9 — `p3_torture` has no SMC or `clear_cache` coverage

- [p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:588) covers cross-page loads and stores, and line 709 covers `mprotect` and `munmap` immediacy.
- The file contains no `PROT_EXEC` SMC write-then-execute case, no `__builtin___clear_cache`, `cacheflush`, `synci`, or `dcbst`/`icbi` path, and `main` at lines 877-888 runs seven rows with no SMC row.
- DBT code-cache invalidation on SMC is therefore unexercised by the named P3 differential fixture.
- Fix: add `t_smc_clear_cache` that maps `RW`, writes, seals to `RX`, clears the cache, executes, rewrites, clears again, and re-checks.

## Explicit zero-bug statements

- `tools/gen_torture.py`: does not exist in `rt-series`; 0 bugs.
- `tools/run_compliance.sh`: does not exist in `rt-series`; 0 bugs.
- `include/a32host.h`: caps and layout are self-consistent for the audited dimensions; 0 bugs.
- `tests/p3_llsc.h` and `tests/sig_fault_addr.h`: reservation-probe and fault-address helpers show no concrete differential defect in this round; 0 bugs.

