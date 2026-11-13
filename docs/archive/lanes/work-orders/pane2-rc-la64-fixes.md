# Work Order — Pane 2 (`0:9.2`): Pre-Merge Stage-Gate (`RC-U12-la64`) Remediation for `loongarch64rt` (& `mips64rt` Checklist)

Read `/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-26-rc-la64-lanes-astra.md` in full before merging `lane/u0-la64-proto` (`ae2f8fc`) and `lane/u12-la64` (`0f3f27a`) into `/Users/angerman/Projects/zw3rk/loongarch64rt` (`master`), and apply the same verification checklist to `mips64rt` before closing out:

1. **P1 — Wire 7-Instruction Soft-TLB into Live DBT Lowering (`src/dbt/emit_int.c:777`, `src/dbt/trampoline_a64.S:36`)**:
   - Connect `rt_emit_tlb_access()` into the live scalar load/store lowering in `src/dbt/emit_int.c` (and populate the Soft-TLB entry in the miss helper so subsequent loads/stores hit the inline 7-instruction fast path).
   - Ensure `x20` is loaded from `ctx->tlb` (with all entries initialized to invalid sentinel `~0ULL` on context init so VPN 0 never falsely hits an uninitialized zero tag).
2. **P1 — Wire Provider A (`src/vm/vm64.c`, `src/vm/vm_file.c`) & Mutation Transactions into Guest Syscalls (`src/os/minsys.c:181,841,863`, `src/os/syscalls.c:508`)**:
   - Connect `vm64` / `vm_file` hooks (`mmap`, `mprotect`, `munmap`, `ftruncate`, and add `pwrite64` dispatch) to the live guest syscall handlers.
   - In `src/vm/vm64.c:218,228,291,659`, fix quiescence so it checks syscall-lease holders, uses the calling thread's actual worker slot (not hard-coded `0`), installs the preemption signal handler to rewind `[pc_begin, pc_commit)` via `dbt_mem_site_t`, and fails/retries rather than silently succeeding after spin timeout.
3. **P1 — Fix Darwin `MAP_JIT` Toggle (`src/dbt/dbt.c:175,509`)**:
   - On Darwin (`__APPLE__`), call `pthread_jit_write_protect_np(0)` BEFORE writing/copying emitted A64 instructions into the code cache, and `pthread_jit_write_protect_np(1)` + `sys_icache_invalidate()` immediately after!
4. **P1 — Fix `safe_syscall_a64.S` Race-Free Window (`src/os/safe_syscall_a64.S:32`, `src/os/backend_linux_fs.c:71`, `src/os/backend_linux_sync.c:542`)**:
   - Perform the `signal_seq != expected_seq` check *inside* `safe_syscall_a64.S` between `__rt_safe_syscall_begin:` and `__rt_safe_syscall_commit:` (before `svc #0`), and in the signal handler (`backend_linux_sync.c`), if the interrupted `uc_mcontext.pc` lies in `[__rt_safe_syscall_begin, __rt_safe_syscall_commit)`, rewind `uc_mcontext.pc = (uintptr_t)__rt_safe_syscall_aborted` (`x0 = -EINTR`).
5. **P2 — 24B `dbt_mem_site_t` AOT Serialization, Dual-Backend `Makefile` Targets, & `tests/parity_suite.sh`**:
   - Persist `dbt_mem_site_t[]` records in `src/dbt/aot/` and bump `AOT_EMITTER_VERSION`.
   - Resolve the `Makefile` merge conflict between `lane/u0-la64-proto` and `lane/u12-la64`, select `backend_linux_*.c` + `safe_syscall_a64.S` vs `backend_darwin_*.c` from the compiler target triple (`$(CC) -dumpmachine`), and provide both `build-linux` (`_build/loongarch64rt-linux-aarch64`) and `build-darwin` (`_build/loongarch64rt-darwin-arm64`).
   - Fix `tests/parity_suite.sh:47,59,133`: use container-relative `/w/...` paths inside Docker, persist compiled guest binaries across container invocations, and fail if `GAP > 0` (`0 FAIL, 0 GAP`).
