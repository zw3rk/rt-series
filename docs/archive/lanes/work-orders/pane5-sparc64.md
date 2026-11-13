# Pane 5 (`%134`) Work Order — Pod 4: `sparc64rt` (Waves U0, U1, U2: `host_contract` Migration, 8 KiB Granule, Soft-TLB & Dual Backends)

- **Coordinator Spec**: `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` (Rev 4, especially §4.1, §4.2, §4.3, §4.5, §5.1, §6, §7 Waves U0–U2) and `/Users/angerman/Projects/zw3rk/rt-series/SPEC.md` (`D11`)
- **Task Cards**: `/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-u-unification.md` (`L-U0-D`, `L-U12-SPARC64`)
- **Exclusive Repository Ownership**: `/Users/angerman/Projects/zw3rk/sparc64rt` (and isolated `../sparc64rt-*` worktrees). Do NOT modify any other sibling repository.

## Mandatory Rules
1. Follow `~/.config/ai/AGENTS.md`, `~/.config/ai/C_GUIDELINES.md`, and `/Users/angerman/Projects/zw3rk/rt-series/AGENTS.md`.
2. Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`), zero VLAs, zero `sprintf`/`strcpy`/`strcat`, and **every source file `<= 900` lines** (`make check-line-limits`). Host register `x18` is permanently reserved.
3. Use parallel subagent worker lanes in explicit isolated git worktrees (`git worktree add ../sparc64rt-<lane> -b lane/<lane> HEAD`) with disjoint file ownership, review their diffs, merge `--no-ff` to local `master`, and run bounded (`timeout --kill-after=30s`) acceptance checks.
4. Never `git push`. Commit with author `Moritz Angermann <moritz@zw3rk.com>`, `Apache-2.0`, and zero AI agent/model attribution trailers.
5. Serialize any Lima VM (`limactl`) test runs so at most one Lima command runs at a time.

## Execution Milestones

### Milestone 1: Wave U1 Structural Migration of Live `sparc64_host_*` Closure & Deletion of `src/rt64/` (`252 Files / 57,529 LOC`)
1. Audit every symbol referenced by `sparc64rt/src/main.c:17` (`#include "runtime/host_contract.h"`) and `sparc64rt/tests/check_host_contract.sh`:
   - `sparc64_host_parse`, `sparc64_host_selftest` (`src/rt64/runtime/host_contract_identity.c:452,707`, explicitly tested by `tests/check_host_contract.sh:433`!), `sparc64_host_check_authorities`, `sparc64_host_apply_sysroot`, `sparc64_host_resolve_image`, `sparc64_host_cache_admit`, and `sparc64_host_report_stats`, plus the 7-file AOT codec/reader/writer/relocate/digest/authority closure.
2. Migrate that exact live symbol closure into clean `<= 900`-line modules under `src/os/host_contract*.c` and `src/dbt/aot/*.c` (replacing the heavy `rv_family_create` dependency inside `sparc64_host_selftest` with the lightweight `Provider A` `vm_inode_shared_t` family control check while preserving the exact `selftest: ok` diagnostic expected by `tests/check_host_contract.sh:433`).
3. `git rm -r src/rt64` (removing all 252 donor files / 57,529 LOC) and verify `test ! -d src/rt64 && ./tests/check_host_contract.sh` passes 100%.

### Milestone 2: Wave U2 8 KiB SPARC V9 Architectural Page Granule (`GUEST_ABI_PAGE_SIZE = 8192`) & `Provider A`
1. Resolve the split in `sparc64rt/src/os/guest_run_priv.h:39-43` (`GUEST_PAGE_SIZE = 4096` vs `GUEST_AT_PAGESZ_VALUE = 8192`, `fable` `M8`, `astra#xhigh` #9):
   - Unify `GUEST_ABI_PAGE_SIZE = 8192` across `AT_PAGESZ`, `mmap`/`mprotect`/`munmap`/`mremap` alignment (`-EINVAL` on 4 KiB-only offsets/addresses), ELF segment mapping, whole-8-KiB-page `PAGE_COW_CLEAN -> PAGE_COW_DIRTY` in-place promotion, and 8 KiB EOF tail zeroing (materializing an anonymous zeroed upper 4 KiB half when a file ends in the lower 4 KiB of an 8 KiB SPARC64 page on a 4 KiB host so valid accesses to the upper half never raise kernel `SIGBUS`).
   - Every 8 KiB guest page operation updates **pairs of consecutive 4 KiB Soft-TLB entries (`vpn` and `vpn ^ 1`)** together.
2. Implement `src/vm/vm64.c` + `src/vm/vm_file.c` (`Provider A` in-place non-relocating COW at fixed canonical `HVA = arena_base + gva`, lightweight `MAP_SHARED` `vm_inode_shared_t` family table, shrink+regrow dirty-page discard, pinned futex admission `vm_futex_prepare_and_pin` with BE byte-swap, and the 6-step `Prepare -> Quiesce (SIGRTMIN+1 tgkill / SIGUSR2 pthread_kill + seq_start_offset rewind) -> Host-Op -> Commit` protocol).

### Milestone 3: 7-Instruction Big-Endian Soft-TLB, `NZCV` (`CCR`) Preservation, Dynamic `JMPL` `npc` & Dual Backends
1. In `sparc64rt/src/dbt/trampoline_a64.S:12-44`: keep `x19 = ctx`, `x27 = chain`, `x28 = &dbt->epoch`, and bind unused callee-saved **`x20 = &ctx->tlb[0]`**.
2. Replace `sparc64_dbt_mem_*` C helper calls (`src/dbt/emit_rt.c:23`) with `src/dbt/emit_mem.c` emitting the 7-instruction Big-Endian Soft-TLB (`ldp x2, x3, [x2, #0]` for loads + `rev16`/`rev`/`rev64` + `sxth`/`sxtw`; swapped `ldp x3, x2, [x2, #8]` for stores + `rev*` into `x4` after step 6 `cbnz`), 2-instruction per-site stub (`mov w4, #k; b .L_block_tlb_miss_common`), and 24-byte relative `dbt_mem_site_t` (with `npc_mode = RT_NPC_DYNAMIC_CTX` for `JMPL` / `RETURN` delay slots, `src/dbt/emit_int.c:634`).
3. **Critical SPARC64 `CCR` Invariant**: Because `sparc64rt` caches guest `CCR` in host `PSTATE.NZCV` (`src/dbt/emit_priv.h:737-757`), `.L_block_tlb_miss_common` MUST save `mrs x5, nzcv` on entry and restore `msr nzcv, x5` before returning to `.L_tlb_cont_k`!
4. Implement `src/os/backend.h` (§6), `backend_linux.c`, and `backend_darwin.c` (`MAP_JIT` APRR W^X + per-class `kevent`/`wake_pipe_rd`/`__ulock_wait2`), serialize `dbt_mem_site_t[]` into `src/dbt/aot/`, build both `_build/sparc64rt-linux-aarch64` and `_build/sparc64rt-darwin-arm64`, and pass `tests/check_host_contract.sh`, `make check check-line-limits`, and Zero-GAP `tests/parity_suite.sh` (`0 FAIL, 0 GAP`).
