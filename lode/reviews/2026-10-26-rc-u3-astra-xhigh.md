# Stage-Gate Review `RC-U3` (`astra#xhigh`) — Wave U3 Class-A 32-Bit Family Unification

- **Date**: 2026-10-26
- **Reviewer**: `gpt-6-astra` (`xhigh` / `high` read-only audit)
- **Repositories Audited**:
  - `/Users/angerman/Projects/zw3rk/a32rt` (`HEAD 514db4c3dbd3a2997ec639a53af0b437c6d2ecf1`)
  - `/Users/angerman/Projects/zw3rk/i686rt` (`HEAD c07f38ddf750e91cf02eec0274a7d1ad9e5626df`)
  - `/Users/angerman/Projects/zw3rk/ppc32rt` (`HEAD 11a212448e10c842cf321d7b7191f905fb647acd`)
  - `/Users/angerman/Projects/zw3rk/sparc32rt` (`HEAD 2cad299c6e96402c0fb534576a713b89c8cb8ee8`)
  - `/Users/angerman/Projects/zw3rk/mips32rt` (`HEAD 260d75b70e156b773118dadef3d82ca3344b5b25`)
- **Overall Verdict**: **`ACTION_REQUIRED`** across all 5 repositories.

---

## 1. `a32rt` (`514db4c`) — `ACTION_REQUIRED`

1. **P1 — Out-of-bounds reservation-table access in offset mode.** `a32_vm32_tlb_fill()` indexes the 1,024-entry `g_ll` with `tlb_index()`, whose range is `0..4095`. `sync_region()` reaches this whenever `G != 0` (including `hyper-linux`'s required `G = 0x1_0000_0000` window); normal mapping registration can therefore corrupt memory or crash. Use `ll_hash(guest_va)` (`(gva >> 6) & (A32_LL_SLOTS - 1)`), not `tlb_index()`. Citations: `src/vm/vm32.c:130`, `src/vm/vm32.c:182`, `src/vm/vm32.h:128`.
2. **P1 — `--difftest` runs only the interpreter and can falsely succeed.** No caller installs `a32_difftest_set_dbt_step()`. The CLI therefore always takes the interpreter-only branch, returning zero even after `UNDEF`, a fault, or step exhaustion. It neither executes DBT nor compares engine state. Wire `a32_difftest_set_dbt_step()` to execute DBT block/step and compare architectural GPR/CPSR/VFP state against `a32_interp_step()`, failing non-zero on any mismatch or unexpected fault. Citations: `src/dbt/difftest.c:21`, `src/dbt/difftest.c:107`, `src/dbt/difftest.c:154`.
3. **P1 — Regime A2 is selected on `> 4 KiB` hosts but not wired into execution/protection.** `src/trampoline.S:30` always loads `x20 = guest_base`, and `src/vm.c:685` maps/protects 4 KiB guest ranges directly without host-page permission unions (`PROT_R | PROT_W` union on 16K/64K host pages + `vm32` software sub-page protection enforcement). Citations: `src/trampoline.S:30`, `src/core/core_emit_alu.c:603`, `src/vm.c:685`.
4. **P1 — `SEQ_CST` CAS exists, but reservation invalidation on ordinary stores is missing.** Ordinary interpreter stores do not call `a32_vm32_reservation_bump()`, and reservation metadata (`g_ll`) updates are non-atomic. Citations: `src/interp/interp.c:118`, `src/vm/vm32.c:211`, `src/vm/vm32.c:248`.
5. **P2 — Provider A (`src/vm/vm_file.c`) is disconnected from runtime `mmap`/`mprotect`/`munmap`/`ftruncate`/`pwrite`.** Citations: `src/vm/vm_file.c:46`, `src/vm/vm_file.c:125`.
6. **P2 — Dual backends (`src/os/backend_{linux,darwin}.c`) are not wired to runtime callers and `build-darwin` target is missing.** Citations: `src/vm/vm_jit_state.c:96`, `src/os/backend.h:61`, `Makefile:44`.
7. **P2 — 24-byte `dbt_mem_site_t` AOT records are not persisted by `dbt_aot_cache.c`.** Citations: `src/vm/vm32.h:172`, `src/dbt/dbt_aot_cache.c:278`.
8. **P2 — Reference-interpreter shift/LDM/STM bugs.** `RRX` shifts left (`<< 1`) instead of right (`(val >> 1) | (carry << 31)`); register-controlled zero shifts can execute UB shift counts; `LDM`/`STM` mutates registers/memory incrementally before validating the full span. Citations: `src/interp/interp_a32.c:85`, `src/interp/interp_a32.c:97`, `src/interp/interp_a32.c:541`.
9. **P2 — DBT single-step fallback (`A32_EXIT_UNDEF` -> `a32_interp_step()`) is not wired.** Citation: `src/dbt/dbt_jit_run.c:458`.

---

## 2. `i686rt` (`c07f38d`) — `ACTION_REQUIRED`

1. **P1 — Production never initializes `i686_vm32_init` (`src/main.c:182` only calls `rt32_vm_init`).** Connect `i686_vm32_init` and union host-page protection in `rt32_vm.c` (`:668`, `:726`).
2. **P1 — DBT fault recovery does not consume 24-byte `dbt_mem_site_t` (`sp_rollback_delta`, `guest_pc_delta`).** `PUSH`/`POP` (`src/dbt/emit_mov.c:465,548`) leave `guest_pc_delta = I686_SITE_PC_UNKNOWN` and `CALL`/`RET` (`src/dbt/emit_branch.c:396`) emit no sites; `src/dbt/engine.c:421` delivers faults without calling `i686_aot_apply_rollback`.
3. **P1 — `LOCK BTS`/`BTR`/`BTC` are non-atomic (`src/interp/h_bit.c:73-85`).** When `pfx_lock` is set, perform atomic `__atomic_fetch_or`/`and`/`xor` (`__ATOMIC_SEQ_CST`) or CAS loop to extract old bit into `CF` atomically.
4. **P1 — Unaligned `CMPXCHG8B` (`src/interp/h_alu.c:779-839`) can strand `g_cmpxchg8b_split_lock` on fault (`siglongjmp` in `src/interp/interp.c:55`).** Pre-validate both 4-byte/page spans before acquiring the lock (and release any held lock in the `sigsetjmp` catch path).
5. **P2 — Unaligned 16/32-bit `LOCK` RMWs in `src/interp/h_alu.c:111-138` and `src/interp/h_shift.c:60-95` cast unaligned pointers directly to `__atomic_*`.** Pre-validate and handle unaligned `LOCK` RMWs safely (e.g., via aligned enclosing 64-bit word CAS or fault-safe lock).
6. **P1 — Interpreter stack instructions (`PUSH` `h_mov.c:360`, `POP` to mem `h_mov.c:423`, `ENTER` `h_mov.c:481`, `LEAVE` `h_mov.c:501`) mutate `ESP` before faultable memory accesses without rollback on fault.** Either validate/perform the memory access before committing `ESP` (like `stack_push` in `h_branch.c:89-90`) or restore `ESP` on `interp.c:274` fault.
7. **P2 — Nested `ENTER` (`src/interp/h_mov.c:474,484-485`) passes `opsz()` (`16` or `32` bits) instead of byte width (`2` or `4` bytes) to `EBP` decrement and `mem_read`.** Fix `int bytes = w / 8;` (`2` or `4`).
8. **P1 — Wire `vm_file.c` hooks into `sys_pass.c` (`pwrite`/`ftruncate`) and fix `vm_file.c:235` shrink calculation to use file offsets rather than guest VAs.**
9. **P2 — `Makefile` `check` target prints placeholder `"phase 0: no tests yet"` instead of running host/unit tests.** Wire `make check` to run the host unit tests (`test_u3_host` etc.).

---

## 3. `ppc32rt` (`11a2124`) — `ACTION_REQUIRED`

1. **P1 — Interpreter `STWCX.` (`src/interp/interp.c:801-802`) performs separate `__atomic_load_n` + `__atomic_store_n` instead of `__atomic_compare_exchange_n(..., __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)`!** Replace with a true `SEQ_CST` `__atomic_compare_exchange_n` on the 32-bit word in guest memory, and bump `reservation_epoch` on ordinary stores (`src/interp/interp.h:211`).
2. **P1 — DBT update-form loads/stores (`lwzu`, `stwu`, etc. in `src/dbt/emit_int.h:629`) write the effective address into architectural `ra` BEFORE the potentially faulting host load/store (`:637-669`).** Emit the host load/store (using `A64_ADDR` scratch) BEFORE writing the updated effective address back to architectural `ra` so a faulting access leaves `ra` unmodified!
3. **P1 — Host `SIGBUS` is delivered as guest `SIGSEGV` (`src/os/hostfault.c:76,120`, `src/main.c:437`).** Preserve `hf_signo` (`HF_SIGBUS` vs `HF_SIGSEGV`) on `ctx->fault_signo` and deliver `PPC32_SIGBUS` (`7`) in `deliver_sync()` (`src/main.c:437`) when the host fault was `SIGBUS`.
4. **P2 — Connect `vm32` / `vm_file` hooks (`vm_file_promote_cow` setting `PAGE_COW_DIRTY`, `vm_file_on_truncate` zeroing partial tail and marking beyond-EOF pages `SIGBUS`) to live `ppc32_vm.c` and `syscalls.c` paths, and fix Darwin compile errors in `src/os/backend_darwin.c`.**

---

## 4. `sparc32rt` (`2cad299`) — `ACTION_REQUIRED`

1. **P1 — DBT `CASA` (`src/dbt/emit_priv.h:338`), `SWAP` (`:353-359`), and `LDSTUB` (`:435-442`) in `sparc32_rt_mem` still use non-atomic load+store instead of calling the `SEQ_CST` atomic helpers (`aot_casa_seq_cst`, `aot_swap_seq_cst`, `aot_ldstub_seq_cst` in `src/dbt/aot/aot_atomic.h`)!** Wire `sparc32_rt_mem` in `src/dbt/emit_priv.h` to use the `SEQ_CST` atomic CAS/exchange helpers.
2. **P1 — DBT `LDD`/`STD` in `src/dbt/emit_priv.h:388,413-418` write `rd` or the first memory word before validating the second word, AND both interpreter (`src/interp/interp.c:453,471`) and DBT check `addr & 3` instead of `addr & 7` for 8-byte alignment (`SIGBUS`)!** Validate `(addr & 7U) == 0` (raising `SIGBUS` on 4-byte-aligned 8-byte-misaligned `LDD`/`STD`) and call `aot_span_ok(ctx, addr, 8, is_write)` (or read both words into temporaries before writing `rd`/`rd+1`) in both `src/dbt/emit_priv.h` and `src/interp/interp.c`.
3. **P1 — DBT `JMPL` delay-slot fault recovery (`src/dbt/emit_int.c:604`, `src/dbt/dbt.c:543`) loses the dynamic target (`w22`) and clobbers `rd` before the delay slot faults.** Save the computed `JMPL` target into `ctx` (`aot_delay_target_set` / `ctx->delay_target`) and defer writing `rd` until after the delay-slot instruction succeeds, and use the saved dynamic target in `dbt.c:543` on delay-slot fault recovery.
4. **P2 — Fix `src/vm/vm32.c:208` Soft-TLB addend (`G`, not `G - guest_page_base`), unsuffixed `rt_host_*` symbol names in `src/os/backend_darwin.c`, and connect `vm32` / `vm_file` hooks to live VM/syscall paths.**

---

## 5. `mips32rt` (`260d75b`) — `ACTION_REQUIRED`

1. **P1 — DBT ignores `TIF_FIXADE` (`ctx->fixade_enabled`) on unaligned `LH`/`LHU`/`LW`/`SH`/`SW` (`src/dbt/emit_int.c:557,564,574`, `src/dbt/dbt.c:765`).** When an alignment trap exits DBT (`MIPS32_EXIT_ALIGN` / `dbt.c:765`) and `ctx->fixade_enabled` is non-zero, invoke `mips32_interp_step(ctx)` to emulate the unaligned access (and resume DBT) instead of delivering `SIGBUS`! Also fix `mips_fault` in `src/os/mem.c:109,253` so unmapped/permission failures on unaligned addresses raise `SIGSEGV` (`11`) rather than `SIGBUS` (`10`) when `fixade_enabled` is set.
2. **P1 — DBT `JR`/`JALR` (`src/dbt/emit_int.c:761`) keeps the dynamic jump target only in `x23` without storing `ctx->delay_target` before executing the delay slot, and `JALR` writes `rd` (`$ra`) before the delay slot can fault.** Store `x23` to `ctx->delay_target` before the delay slot, defer `rd` commit if `rd == rs` or until after the delay slot, and recover `next_pc = ctx->delay_target` on a delay-slot fault.
3. **P1 — DBT `LL`/`SC` (`src/dbt/emit_int.c:655,669,677`): `SC` omits checking `ctx->lladdr == addr`, and aligned `LL`/`SC` skip `emit_sync_pc` before the host memory access.** Emit `emit_sync_pc` before the host memory access in `emit_ll`/`emit_sc`, verify `ctx->lladdr == addr` in `emit_sc`, and bump reservation epoch on stores.
4. **P2 — Guard raw `syscall(SYS_ioctl, ...)` in `src/rt32/host.c:44` with `#ifdef __linux__` (or `ioctl(fd, ...)`), implement Darwin `ucontext_t` PC extraction in `src/os/hostfault.c:74` (`uc->uc_mcontext->__ss.__pc`), and connect `vm32` / `vm_file` hooks to `src/os/mem.c` and `src/rt32/vm_mmap.c`.**
