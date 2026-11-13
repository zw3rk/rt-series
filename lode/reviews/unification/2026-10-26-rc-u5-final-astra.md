**RC-U5-final — rvrt master `4098abc`: ACTION_REQUIRED.**

Two items remain open: read-only EOF-tail handling and Section-4 runtime integration.

| RC-U5-AB-r2 item | Status and evidence |
|---|---|
| File shrink / mapping association | **STILL OPEN.** Partial EOF tails pass an unaligned address to `zero_guest_range`; its alignment guard skips protection widening, then unconditionally calls `memset`. A read-only mapping truncated to 100 bytes can therefore still fault. [vm64.c:456](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:456), [vm64.c:91](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:91). |
| In-place write invalidation | **RESOLVED.** Range merging preserves the original upper bound when extending left. [vm_file.c:259](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm_file.c:259). |
| DBT invalidation extent / full clear | **RESOLVED.** Overlap uses stored source extent; full clear reclaims slots and staging space. [cache.c:248](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/cache.c:248), [cache.c:299](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/cache.c:299). |
| AOT block-size overflow | **RESOLVED.** Both calculations promote operands to `size_t` before addition on the supported 64-bit hosts. [aot_v4.c:323](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/aot_v4.c:323), [aot_v4.c:371](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/aot_v4.c:371). |

| RC-U5-C-r2 item | Status and evidence |
|---|---|
| **2.4 — mmap2 offsets** | **RESOLVED.** Both workers scale page offsets; RV32 eligibility bypasses byte-alignment validation. [runtime_main.c:2651](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:2651), [2778](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:2778), [5683](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5683). |
| **2.9 — ppoll_time64** | **RESOLVED.** Multiworker allowlist admits 414. [runtime_main.c:6036](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:6036). |
| **2.10 — pselect6_time64** | **RESOLVED.** RV32 fd sets use four-byte words; allowlist admits 413. [poll.c:470](/Users/angerman/Projects/zw3rk/rvrt/src/linux/poll.c:470), [runtime_main.c:6036](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:6036). |
| **2.11 — utimensat_time64** | **RESOLVED.** Negative seconds are accepted; ordinary `utimensat` dispatches as 88. [metadata.c:260](/Users/angerman/Projects/zw3rk/rvrt/src/linux/metadata.c:260), [445](/Users/angerman/Projects/zw3rk/rvrt/src/linux/metadata.c:445). |
| **2.12 — statx** | **RESOLVED.** Both empty-path branches preserve synchronization flags. [metadata.c:188](/Users/angerman/Projects/zw3rk/rvrt/src/linux/metadata.c:188), [199](/Users/angerman/Projects/zw3rk/rvrt/src/linux/metadata.c:199). |

| Section-4 integration | Status and evidence |
|---|---|
| Makefile | **RESOLVED.** Required sources precede immediate object expansion; trampoline assembly is wired. Existing AOT targets and U5-B targets remain. [Makefile:553](/Users/angerman/Projects/zw3rk/rvrt/Makefile:553), [848](/Users/angerman/Projects/zw3rk/rvrt/Makefile:848), [8162](/Users/angerman/Projects/zw3rk/rvrt/Makefile:8162), [8417](/Users/angerman/Projects/zw3rk/rvrt/Makefile:8417), [8461](/Users/angerman/Projects/zw3rk/rvrt/Makefile:8461), [8593](/Users/angerman/Projects/zw3rk/rvrt/Makefile:8593). |
| `runtime_main.c` | **STILL OPEN.** No runtime calls connect `rv_vm64`, `rv_vm_file`, or `rv_dbt` modules. `--dbt` selects the existing JIT; execution still uses `rv_jit_compile_measured`/`rv_jit_run`. `--difftest` uses a separate PC/integer-register comparison. [runtime_main.c:6931](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:6931), [5129](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5129), [5205](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5205), [5231](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5231). |

Verified using `git show 4098abc` and source inspection. No Docker, builds, tests, or file modifications.