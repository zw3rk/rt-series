# Round-5 Post-Remediation Verification — `rvrt` @ `8b57344`

**Result: 7/7 items VERIFIED. No regressions found. Hygiene clean.** Three residual nits are listed at the end; none reopens an item.

Scope: static read of commit `8b57344` ("rvrt: remediate Round-5 defects RV-R5-1 through RV-R5-7") plus surrounding context. No builds, tests, containers, or QEMU were run. Four read-only tool turns.

## Item-by-item

| ID | Verdict | Evidence |
|---|---|---|
| RV-R5-1 | **VERIFIED** | `src/dbt/emit_mem.c:16-20` now rejects `{1,2,3,4,18,19,20,21}` and `>30`. Header contract updated at `src/dbt/emit_mem.h:7-12`. Negative cases: `test/test_u0_soft_tlb.c:28-41` (unit guard incl. 31/32/64/0xffffffff) and `:45-57` (emitter rejects each bad register for load and store, LE and BE). Old positive assertion `rv_dbt_reg_usable(20u)` removed from `test/u5b_dbt_mem.c` and replaced by `:173-184`. No production caller of `rv_dbt_emit_mem`/`rv_dbt_reg_usable` exists under `src/` outside the emitter itself, so the stricter guard cannot regress a live path. |
| RV-R5-2 | **VERIFIED** | `src/dbt/emit_mem.c:148-156`: 4-alignment of `base_offset`/`stub_offset`, both `<= UINT16_MAX`, and `base_offset + (6+mem_count)*4 <= UINT16_MAX`. The sum cannot overflow because the preceding `base_offset > UINT16_MAX` test short-circuits first and `mem_count <= 3`. Consequently `seq_start_offset`, `host_insn_offset`, `cont_insn_offset` (`:167-169`) are representable without truncation. Boundary tests at `test/test_u0_soft_tlb.c:75-97` cover the 65536 base, overflowing continuation (65508/65532), unaligned offsets (`:60-72`), and the largest exactly-fitting 3-word BE sequence with exact site-field assertions (`:88-97`). Wired into `test-u5b-multiblock` via `Makefile:8722`. |
| RV-R5-3 | **VERIFIED** (no regression test) | `src/vm/vm64.c:621-626`: direct `MAP_FIXED` only when `head == 0` **and** `len` is a whole multiple of the 4 KiB granule. Combined with the existing `(gva ^ file_offset)` low-bit check at `:609-610`, `head == 0` implies `gva` is page-aligned, so the replacement covers complete host pages only. Partial pages fall through to the staged `pread` copy path at `:641+`, which preserves neighbour bytes. The sentinel test requested in the card was not added (`test/u5a_vm_provider.c` is unchanged in this commit). |
| RV-R5-4 | **VERIFIED** | `src/vm/vm64.c:547-554` introduces `round_up_page()` with a true overflow guard (`size > UINT64_MAX - (PAGE-1)`), replacing both dead `0xffffffffffffff` quotient comparisons (`mark_file_states` `:568`, `rv_vm64_discard_entry` `:711`). `UINT64_MAX` no longer rounds to zero. See nit 2 on the saturation value. |
| RV-R5-5 | **VERIFIED** | `tests/parity_suite.sh:56-72`: `timeout` → `gtimeout` → perl `alarm(30)` wrapper → python3 `signal.alarm(30)` wrapper → empty. Every guest invocation (`:222`, `:275`, `:297`) now runs only through `$GUEST_TIMEOUT`; the unbounded `else` branches are gone. Empty `GUEST_TIMEOUT` yields explicit `GAP` rows at `:214-218` (parity) and `:261-267` (both AOT cases). Function-name-in-variable dispatch is valid POSIX `sh` (`#!/bin/sh`). |
| RV-R5-6 | **VERIFIED** | New `src/runtime/family_file_internal.h:19-26` `rv_family_file_same_identity_snapshot()` compares provider/device/format/length/`mapped_key_eligible`/full digest bytes, i.e. the exact snapshot semantics, and correctly does **not** substitute `rv_file_identity_equal()`. Both static copies deleted; call sites at `src/runtime/family_file_pwrite.c:120-121` and `src/runtime/family_file_truncate.c:362-363`. No `same_identity` over `rv_file_identity_t` remains under `src/` (the one in `src/memory/mm_fork.c:281` is a different type, `rv_family_identity_t`, out of scope). |
| RV-R5-7 | **VERIFIED** | Field removed from `src/os/backend.h:63` struct; comment at `:59-61` no longer claims a commit guard. Zero-inits removed from `src/os/backend_linux.c:204` and `src/os/backend_darwin.c:317`. Repo-wide grep for `in_commit_window` across `*.c/*.h/*.S/*.md` returns nothing. Struct is internal; no ABI/layout consumer was found. |

## Hygiene

- **Curated C11:** No VLAs, Annex K, `<threads.h>`, `_Generic`, `sprintf`/`strcpy`/`strcat` introduced. New helper is `static inline` in a header with include guard and license header. New test uses `fprintf`/`exit` only.
- **Line limits (≤ 900):** all touched C sources/headers and the shell runner are within limit. Largest is `src/vm/vm64.c` at 830 lines; `tests/parity_suite.sh` 484; `src/runtime/family_file_truncate.c` 480; `src/os/backend_darwin.c` 481. `Makefile` (~8700 lines) is pre-existing and not a C source.
- **Attribution:** commit message and new file headers carry zw3rk copyright, Apache-2.0, no agent names.

## Residual nits (non-blocking, for backlog)

1. **Dead arithmetic after RV-R5-3** — `src/vm/vm64.c:622-624` still computes `file_offset - head`, `gva - head`, `len + head` inside a branch where `head == 0`; the `head > gva` check at `:613` is likewise unreachable. Pure cleanup.
2. **Saturation direction in `round_up_page`** — for `size` within 4095 of `UINT64_MAX` it returns `0xFFFF_FFFF_FFFF_F000`, which is *below* `size`, so `mark_file_states` (`:572`) would park the final 64-bit page as BEYOND_EOF. The old code saturated to `UINT64_MAX`. Unreachable for any signed `off_t` file size, but saturating upward would be strictly safer.
3. **Alarm fallback has no kill escalation** — the perl/python wrappers send only `SIGALRM`; a guest that installs a `SIGALRM` handler (rvrt forwards guest `rt_sigaction`) could absorb it, unlike `timeout --kill-after`. Only affects hosts lacking both `timeout` and `gtimeout`. The card's "test timeout-tool absence" case was not added.
4. **Test-side duplicate** — `test/test_family_file_recovery_helpers.h:112` still carries a fourth `same_identity()` copy over `rv_file_identity_t`; could reuse the new header.
5. **Redundant guard** — `src/dbt/emit_mem.c:153` (`base_offset > UINT16_MAX - 28u`) is subsumed by `:154` since `mem_count >= 1`; harmless.

## Cross-runtime propagation (from the card, unverified here)

RV-R5-1/2 register-and-offset guards and RV-R5-3/4 page-rounding patterns should be checked in sibling Soft-TLB emitters and arena providers; RV-R5-5 in sibling `parity_suite.sh` runners; RV-R5-7 in copied `rt_worker_sync_t` structures.
