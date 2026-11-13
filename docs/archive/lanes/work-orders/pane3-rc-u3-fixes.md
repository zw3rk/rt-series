# Work Order — Pane 3 (`0:9.3`): Stage-Gate `RC-U3` Remediation Across All 5 Class-A 32-Bit Repositories

Read `/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-26-rc-u3-astra-xhigh.md` in full.
While the background `mips32` cross-gcc bootstrap continues in the background, fan out **5 parallel worker lanes** (one per repository: `a32rt`, `i686rt`, `ppc32rt`, `sparc32rt`, `mips32rt`) to resolve every P1 and P2 finding in `lode/reviews/2026-10-26-rc-u3-astra-xhigh.md`:

1. **`a32rt` (`/Users/angerman/Projects/zw3rk/a32rt`)**:
   - **P1**: Fix out-of-bounds `g_ll` reservation array indexing in `a32_vm32_tlb_fill()` (`src/vm/vm32.c:130`): `g_ll` has `A32_LL_SLOTS` (1024) entries while `tlb_index()` returns `0..4095`. Use `ll_hash(guest_va)` (`(guest_va >> 6) & (A32_LL_SLOTS - 1U)`).
   - **P1**: Wire `--difftest` (`src/dbt/difftest.c:21,107,154`): register `a32_difftest_set_dbt_step()` so `--difftest` runs both DBT and reference interpreter, compares GPRs/CPSR/VFP, and exits non-zero on any mismatch or unexpected `UNDEF`/fault.
   - **P1**: Wire `A32_EXIT_UNDEF` in `src/dbt/dbt_jit_run.c:458` to single-step fallback via `a32_interp_step(ctx)` before raising `SIGILL`.
   - **P1**: Call `a32_vm32_reservation_bump()` on ordinary stores in `src/interp/interp.c:118` and make `g_ll` metadata updates atomic.
   - **P2**: Fix reference interpreter `RRX` right-shift (`(val >> 1) | (carry << 31)`) and zero-shift UB in `src/interp/interp_a32.c:85,97`, pre-validate full `LDM`/`STM` address span before mutating registers/memory (`src/interp/interp_a32.c:541`), persist 24B `dbt_mem_site_t` records in `src/dbt/dbt_aot_cache.c:278`, and wire `vm32` / `vm_file` hooks into `src/vm.c`.

2. **`i686rt` (`/Users/angerman/Projects/zw3rk/i686rt`)**:
   - **P1**: Wire `i686_vm32_init` from `src/main.c:182` and union host-page protection in `src/rt32/rt32_vm.c:668,726`.
   - **P1**: Wire 24B `dbt_mem_site_t` fault recovery: record real `guest_pc_delta` and `sp_rollback_delta` in `PUSH`/`POP` (`src/dbt/emit_mov.c:465,548`) and `CALL`/`RET` (`src/dbt/emit_branch.c:396`), and invoke `i686_aot_apply_rollback` in the fault recovery path (`src/dbt/engine.c:421`).
   - **P1**: Implement atomic `LOCK BTS`/`BTR`/`BTC` in `src/interp/h_bit.c:73-85` using `__atomic_fetch_or`/`and`/`xor` (`__ATOMIC_SEQ_CST`) when `pfx_lock` is set.
   - **P1/P2**: In unaligned `CMPXCHG8B` (`src/interp/h_alu.c:779-839`) and unaligned 16/32-bit `LOCK` RMWs (`src/interp/h_alu.c:111-138`, `src/interp/h_shift.c:60-95`), pre-validate guest memory spans before taking `g_cmpxchg8b_split_lock` (and release the lock in `src/interp/interp.c:55` catch path on fault) and handle unaligned `LOCK` RMWs without triggering host alignment faults.
   - **P1/P2**: Fix interpreter `PUSH` (`h_mov.c:360`), `POP` to memory (`h_mov.c:423`), `ENTER` (`h_mov.c:481`), and `LEAVE` (`h_mov.c:501`) so `ESP` is not left mutated if the memory access faults; fix nested `ENTER` (`h_mov.c:474,484-485`) to use byte width `w / 8` (`2` or `4`) instead of bit width (`16` or `32`).
   - **P1/P2**: Connect `vm_file.c` hooks to `sys_pass.c` (`pwrite`/`ftruncate`), fix `vm_file.c:235` shrink calculation to use file offsets, and wire `Makefile` `check` to run host tests.

3. **`ppc32rt` (`/Users/angerman/Projects/zw3rk/ppc32rt`)**:
   - **P1**: Replace the separate load+store in interpreter `STWCX.` (`src/interp/interp.c:801-802`) with a single `__atomic_compare_exchange_n(..., __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)` and advance `reservation_epoch` on ordinary stores (`src/interp/interp.h:211`).
   - **P1**: In `src/dbt/emit_int.h:629-669`, emit the host memory load/store BEFORE writing the updated effective address into architectural `ra` so faulting `lwzu`/`stwu` instructions leave `ra` unmodified!
   - **P1**: Preserve `hf_signo` (`SIGBUS` vs `SIGSEGV`) in `src/os/hostfault.c:76,120` onto `ctx->fault_signo` and deliver `PPC32_SIGBUS` (`7`) in `deliver_sync()` (`src/main.c:437`) when a host `SIGBUS` occurs.
   - **P2**: Fix `vm_file_promote_cow` (`src/vm/vm_file.c:112`) to transition `PAGE_COW_CLEAN -> PAGE_COW_DIRTY`, implement `vm_file_on_truncate` (`src/vm/vm_file.c:121`), connect `vm32`/`vm_file` hooks to `src/rt32/ppc32_vm.c` and `src/os/syscalls.c`, and fix the 9 Darwin compile issues in `src/os/backend_darwin.c`.

4. **`sparc32rt` (`/Users/angerman/Projects/zw3rk/sparc32rt`)**:
   - **P1**: Wire DBT `CASA`, `SWAP`, and `LDSTUB` in `sparc32_rt_mem` (`src/dbt/emit_priv.h:338,353,435`) to call the `SEQ_CST` atomic helpers (`aot_casa_seq_cst`, `aot_swap_seq_cst`, `aot_ldstub_seq_cst` in `src/dbt/aot/aot_atomic.h`).
   - **P1/P2**: Enforce 8-byte alignment (`(addr & 7U) == 0`, raising `SIGBUS` on 4-byte-aligned 8-byte-misaligned addresses) AND validate-then-commit (`aot_span_ok(ctx, addr, 8, is_write)` + read both words before mutating `rd`) for `LDD`/`STD` in both DBT (`src/dbt/emit_priv.h:388,413`) and interpreter (`src/interp/interp.c:453,471`).
   - **P1**: Fix DBT `JMPL` delay-slot fault recovery (`src/dbt/emit_int.c:604`, `src/dbt/dbt.c:543`): store the computed jump target into `ctx` (`aot_delay_target_set`) and defer committing link register `rd` until after the delay-slot instruction succeeds; recover `npc` from `aot_delay_target_get` on delay-slot fault.
   - **P2**: Fix `src/vm/vm32.c:208` Soft-TLB addend (`G`, not `G - guest_page_base`), export unsuffixed `rt_host_*` symbols in `src/os/backend_darwin.c`, and connect `vm32`/`vm_file` hooks to `src/rt32/vm_mmap.c`.

5. **`mips32rt` (`/Users/angerman/Projects/zw3rk/mips32rt`)**:
   - **P1**: Honor `ctx->fixade_enabled` (`TIF_FIXADE`) in DBT (`src/dbt/emit_int.c:557,564,574`, `src/dbt/dbt.c:765`): when an unaligned `LH`/`LHU`/`LW`/`SH`/`SW` triggers `MIPS32_EXIT_ALIGN` and `ctx->fixade_enabled != 0`, emulate the instruction via `mips32_interp_step(ctx)` and resume DBT instead of raising `SIGBUS`! Also fix `mips_fault` in `src/os/mem.c:109,253` so unmapped/permission faults on unaligned addresses raise `SIGSEGV` (`11`) when `fixade_enabled` is set.
   - **P1**: In DBT `JR`/`JALR` (`src/dbt/emit_int.c:761`), store the dynamic jump target `x23` to `ctx->delay_target` before executing the delay slot (and avoid clobbering `rs` with `JALR` link writeback before the delay slot completes), and recover `next_pc = ctx->delay_target` on delay-slot fault.
   - **P1**: In DBT `emit_ll`/`emit_sc` (`src/dbt/emit_int.c:655,669,677`), call `emit_sync_pc` before the host memory access and verify `ctx->lladdr == addr` in `emit_sc`.
   - **P2**: Guard `syscall(SYS_ioctl, ...)` in `src/rt32/host.c:44` with `ioctl(fd, ...)` / `#ifdef __linux__`, implement Darwin `ucontext_t` PC extraction in `src/os/hostfault.c:74`, and connect `vm32`/`vm_file` hooks to `src/os/mem.c` and `src/rt32/vm_mmap.c`.

Merge all 5 remediation branches cleanly to `master` (`--no-ff`), rebuild and re-verify each repository's Linux binary and test suite, and report completion.
