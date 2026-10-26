# Pane 3 (`0:9.3` / `%135`) — `RC-U3-r2` Verification Follow-Up Fixes (All 5 Class-A 32-Bit Repos)

## Review Artifacts
- [`lode/reviews/2026-10-26-rc-u3-r2-4repos-astra.md`](../../../lode/reviews/2026-10-26-rc-u3-r2-4repos-astra.md) (`a32rt` `21b3851`, `ppc32rt` `4c36985`, `sparc32rt` `89c4b05`, `mips32rt` `5fc0415`)
- [`lode/reviews/2026-10-26-rc-u3-r2-i686-astra.md`](../../../lode/reviews/2026-10-26-rc-u3-r2-i686-astra.md) (`i686rt` `df94bfe` / `a11acc1`)

Independent `astra` round-2 verification (`RC-U3-r2`) audited your merged round-1 remediation commits across all 5 Class-A 32-bit repositories. Many findings are cleanly resolved, while specific P1/P2 gaps remain that must be fixed so `RC-U3-r3` achieves **PASS** across all 5 repos.

Use a **5-lane parallel workflow** (one lane per repo) to fix the exact items below, commit and merge to `master` on each repo, and rebuild all 5 Linux static-PIE binaries.

---

## 1. `/Users/angerman/Projects/zw3rk/a32rt` (`21b3851`)
1. **#2 (P1) — True single-instruction lockstep in `src/dbt/difftest.c` (`:174`, `:186`, `:258`) and `src/dbt/dbt_jit_run.c:520`**:
   - Ensure difftest translates and executes **1 guest instruction per DBT block** (force single-step block length `max_insns = 1` when running under difftest) so 1 interpreter step is compared 1:1 against 1 DBT instruction, with separate memory or deterministic syscall synchronization, and return failure if 0 instructions were compared or if divergence occurred.
2. **#3 (P1) — Regime A2 Soft-TLB & host-page union `mprotect` wiring (`src/trampoline.S:30`, `src/core/core_emit_alu.c:603`, `src/vm.c:686`)**:
   - When `ctx->vm32_regime == VM32_REGIME_A2`, `mprotect` in `src/vm.c:686` must delegate to `vm32_protect` (computing the union of all 4 KiB guest page permissions within each host page before calling `rt_host_protect`), and memory emission/trampoline must respect Regime A2 (`x21` Soft-TLB pointer and 7-insn lookup when `VM32_REGIME_A2` is active while keeping Regime A1 direct `[x20, wAddr, uxtw]` on 4 KiB hosts).
3. **#5 (P2) — Provider A file population permissions & truncate/write hooks (`src/vm.c:618`, `src/vm/vm_file.c:95,137,160`)**:
   - In `vm_file_populate` / `vm.c:618`, populate file bytes via `pread` while the backing range is temporarily `PROT_READ | PROT_WRITE` (before applying a read-only final guest `prot`), propagate errors instead of ignoring them, only zero-fill within mapped host memory, and wire `sys_ftruncate` / `sys_truncate` / `sys_write` (`pwrite`) to invoke the `vm_file` hooks when overlapping tracked file mappings.
4. **#6 (P2) — Clean Darwin compilation (`src/host.c:41`, `src/vm/vm_jit_state.c:96`)**:
   - In `src/host.c:41`, guard raw `syscall(SYS_ioctl, ...)` with `#ifdef __linux__` (or use `ioctl()` on non-Linux) so `clang -fsyntax-only -Wall -Wextra -Werror` on macOS succeeds with 0 warnings/errors. Route `vm_jit_state.c:96` through the backend abstraction on Darwin.
5. **#7 (P2) — Call `a32_aot_site_track()` from the DBT emitter (`src/dbt/dbt_aot_cache.c:308,493`)**:
   - Wire the DBT memory/PC-sync emitters to call `a32_aot_site_track()` during block translation so newly translated blocks populate the site registry consumed by `a32_aot_save()`.
6. **#8 (P2) — Shift carry bit fixes in `src/interp/interp_a32.c:100,120`**:
   - Fix ordinary `LSL` (`amt in 1..31`) carry extraction to use bit `32 - amt` (`(val >> (32U - amt)) & 1U`) instead of `amt - 1`.
   - Fix register `LSR` with shift count `> 32` to produce `carry = 0` (only `amt == 32` extracts bit 31).

---

## 2. `/Users/angerman/Projects/zw3rk/i686rt` (`df94bfe` / `a11acc1`)
1. **#1 (P1) — Regime A2 `mmap(MAP_FIXED)` & file population on >4 KiB host pages (`src/rt32/rt32_vm.c:727`)**:
   - When `ctx->vm32_regime == VM32_REGIME_A2` (host page size > 4 KiB) and `addr` or `offset` is 4 KiB-aligned but not host-page-aligned, do NOT pass unaligned `addr`/`offset` directly to host `mmap(MAP_FIXED)` (which returns `EINVAL` on 16 KiB/64 KiB hosts). Instead, route through `i686_vm_file_map` / anonymous sub-page staging + `i686_vm32_protect` host-page union permissions.
2. **#2 (P1) — Record exact faulting store `host_insn_offset` for `CALL` (`src/dbt/emit_branch.c:405`, `src/dbt/engine.c:436`)**:
   - In `src/dbt/emit_branch.c:405`, record `host_insn_offset` **immediately before** the `STR` instruction that pushes the return address to the stack (after the return-address `MOVZ`/`MOVK` instructions), so `i686_aot_site_lookup` at `src/dbt/engine.c:436` matches the exact faulting host `STR` PC on `CALL` stack faults.
3. **#4 (P1) — Release split-lock in DBT fault catch (`src/dbt/engine.c:563,650`, `src/interp/interp.c:517`)**:
   - When DBT exits to `i686_interp_step` (`src/dbt/engine.c:650`) and a guest fault (`siglongjmp`) lands in the DBT `sigsetjmp` catch block (`src/dbt/engine.c:563`), release the global split-lock (`i686_split_lock_release_if_held(ctx)`) just as `i686_interp_run` does at `src/interp/interp.c:517`.
4. **#5 (P1) — Unified lock or cacheline-split serialization for unaligned vs aligned `LOCK` RMWs (`src/interp/h_alu.c:210`, `src/interp/h_shift.c:73`)**:
   - Currently, unaligned `LOCK` RMWs in `h_alu.c:210` and `h_shift.c:73` use bytewise loads/stores under `i686_split_lock`, while aligned `LOCK` RMWs bypass `i686_split_lock` and use `__atomic_*`. Either have all interpreter `LOCK` RMWs acquire `i686_split_lock` (or perform atomic 64-bit word CAS across the enclosing 8-byte aligned word when within a cacheline and fall back to `i686_split_lock` across all `LOCK` ops when split-lock is active) so overlapping aligned and unaligned `LOCK` operations are mutually atomic, and ensure faults release `i686_split_lock` via Fix #4.

---

## 3. `/Users/angerman/Projects/zw3rk/ppc32rt` (`4c36985`)
1. **#1 (P1) — Multi-line reservation invalidation & `vm32_sc_attempt` check (`src/interp/interp.h:172,228`, `src/interp/interp.c:36`)**:
   - When an ordinary store spans two 64-byte reservation granules (`(ea >> 6) != ((ea + size - 1) >> 6)`), bump the generation counter for **both** reservation lines in `vm32_store_inval` (and in `interp.h:172,228`), and ensure `vm32_sc_attempt()` checks both the shared per-line generation counter and `ctx->reservation_valid` / `ctx->reservation_addr`.
2. **#2 (P1) — X-form update loads/stores (`LBZUX`, `LHZUX`, `LHAUX`, `LWZUX`, `STBUX`, `STHUX`, `STWUX`) fault-before-writeback (`src/dbt/emit_int.h:623,633`)**:
   - Just as D-form update instructions were fixed to compute effective address into a scratch register, perform the memory access first, and write back `ra` only after the memory access succeeds, fix the X-form update emitters at `src/dbt/emit_int.h:623,633` so a faulting X-form update access leaves architectural `ra` unmodified!
3. **#4 (P2) — Wire `vm32_init()` & `vm_file` lifecycle (`src/vm/vm32.c:135`, `src/vm/vm_file.c:133,172,193`)**:
   - Call `vm32_init()` during VM startup; in `vm_file_cow_promote` (`src/vm/vm_file.c:172`), transition the page state to `PAGE_COW_DIRTY`; in `vm_file_truncate` (`src/vm/vm_file.c:193`), match by file identity (`fd` / `dev`+`ino`), zero the partial page tail on shrink, and mark pages beyond the new EOF as `PAGE_EOF_TRAP` (`SIGBUS`); and wire `mmap`/`mprotect`/`ftruncate` in `src/rt32/` to invoke the `vm32` / `vm_file` helpers.

---

## 4. `/Users/angerman/Projects/zw3rk/sparc32rt` (`89c4b05`)
1. **#2 (P1) — `LDD`/`STD` 8-byte alignment `SIGBUS` classification in `src/main.c:228` and `src/dbt/difftest.c:360`**:
   - In `src/main.c:228` and `src/dbt/difftest.c:360`, when classifying an alignment fault (`EXIT_ALIGN` or unaligned memory trap), do not check only `(fault_addr & 3) != 0` — a 4-byte-aligned, 8-byte-misaligned `LDD`/`STD` has `(fault_addr & 3) == 0` and `(fault_addr & 7) != 0` and MUST deliver `SIGBUS` (`BUS_ADRALN`), not `SIGSEGV`! Decode the faulting instruction (or check `EXIT_ALIGN` / `insn` `LDD`/`STD` opcode) so 8-byte-misaligned `LDD`/`STD` delivers `SIGBUS`.
2. **#3 (P1) — Store `JMPL` dynamic target per-context in `sparc32_ctx_t` (`src/dbt/aot/aot_sites.c:23,48,58`)**:
   - Do NOT rely solely on an unsynchronized 64-entry global eviction table in `aot_sites.c` for live `JMPL` delay-slot dynamic targets! Store the computed `JMPL` target directly in a per-context field on `sparc32_ctx_t` (e.g., `ctx->jmpl_target` or `ctx->delay_npc`) before executing the delay slot, and read that per-context field on delay-slot fault recovery (keeping `aot_sites.c` metadata for static site properties).
3. **#4 (P2) — Fix Darwin backend symbol names & wire `vm32`/`vm_file` (`src/rt32/vm_mmap.c:90,154`, `src/os/backend_darwin.c`, `Makefile:41`)**:
   - `src/rt32/vm_mmap.c:90,154` calls `rt_host_map_file()` and `rt_host_protect()`, which must be exported with matching names in `src/os/backend_darwin.c` so `make darwin-sparc32rt` links cleanly on macOS! Also wire `vm32_reserve()` and `vm_file` hooks into the runtime VM lifecycle.

---

## 5. `/Users/angerman/Projects/zw3rk/mips32rt` (`5fc0415`)
1. **#1 (P1) — Remove pre-helper alignment rejection in `src/interp/interp.c:457,499` when `fixade_enabled` is set**:
   - In `src/interp/interp.c:457` (`LH`/`LHU`/`LW`) and `src/interp/interp.c:499` (`SH`/`SW`), the interpreter currently rejects unaligned addresses before calling the `FIXADE`-aware helpers in `src/os/mem.c`! Gate those alignment checks on `!ctx->fixade_enabled` (or delegate directly to the `mem.c` helpers) so DBT `EXIT_ALIGN` -> `mips32_interp_step(ctx)` actually emulates unaligned loads/stores when `FIXADE` is enabled.
2. **#2 (P1) — Propagate `ind_slot` into `LWL`/`LWR`/`SWL`/`SWR` (`src/dbt/emit_int.c:656`, `src/dbt/emit_mem.c:217`)**:
   - Pass `ind_slot` through `emit_int.c:656` into the `LWL`/`LWR`/`SWL`/`SWR` emitter at `src/dbt/emit_mem.c:217` and pass `ind_slot` (instead of hardcoded `0`) to `emit_sync_pc(..., ind_slot)` so a faulting `LWL`/`LWR`/`SWL`/`SWR` in a `JR`/`JALR` delay slot preserves the dynamic `next_pc`.
3. **#3 (P1) — Shared atomic reservation generation table for `LL`/`SC` and ordinary stores (`src/os/mem.c:175`, `src/dbt/emit_mem.c:107,327`)**:
   - Replace context-local-only `ctx->llbit = 0` invalidation and value-only ABA comparison with a shared atomic 64-byte line generation table (`g_ll_seq[(addr >> 6) & 4095]`):
     - `LL` records `ctx->ll_addr = addr`, `ctx->ll_val = val`, `ctx->ll_seq = __atomic_load_n(&g_ll_seq[idx], __ATOMIC_ACQUIRE)`, `ctx->llbit = 1`.
     - Every ordinary store in both interpreter (`src/os/mem.c:175`) and DBT (`src/dbt/emit_mem.c:107`) atomically increments `g_ll_seq[(addr >> 6) & 4095]` (and the second line if crossing a 64B boundary).
     - `SC` (`src/dbt/emit_mem.c:327` and interpreter `SC`) atomically verifies `ctx->llbit && ctx->ll_addr == addr && __atomic_load_n(&g_ll_seq[idx], __ATOMIC_ACQUIRE) == ctx->ll_seq` around the `__atomic_compare_exchange_n` (or under a reservation spinlock) and bumps `g_ll_seq[idx]` on success.
4. **#4 (P2) — Unify `vm_arena_base` with `ctx->guest_base` & wire `vm_file_truncate` (`src/vm/vm32.c:150`, `src/rt32/vm_mmap.c:89`, `src/vm/vm_file.c:147,224`)**:
   - Do not allocate a separate disconnected `vm_arena_base` in `src/vm/vm32.c:150`; bind `vm32` and `vm_file_populate` (`src/vm/vm_file.c:147`) to the canonical `ctx->guest_base` window (`G`), and wire `sys_ftruncate` / `sys_truncate` to call `vm_file_truncate` (`src/vm/vm_file.c:224`).
