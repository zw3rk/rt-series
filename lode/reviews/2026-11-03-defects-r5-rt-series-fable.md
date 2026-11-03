# Round-5 Post-Remediation Verification — `rt-series` @ `3544333`

Scope: the eight items in `lode/reviews/2026-11-03-defects-r5-rt-series-astra.md`, checked against the diff of commit `3544333` plus surrounding context. No builds, tests, containers, or QEMU were run; this is a static review.

## Summary

| Item | Verdict | Primary evidence |
|---|---|---|
| RTS-R5-1 | VERIFIED | `tools/bench_harness.sh:25`, `:81-84`, `:94`, `:168`, `:246` |
| RTS-R5-2 | VERIFIED | `tests/bench_suite.c:49-66`, `:129-135` |
| RTS-R5-3 | VERIFIED | `tests/p3_torture.c:629-634`, `:654`, `:683-691`, `:703`, `:732` |
| RTS-R5-4 | VERIFIED | `tests/p3_torture.c:551-609` |
| RTS-R5-5 | PARTIAL | `tools/run_grind.sh:604-606`, `:620-629` |
| RTS-R5-6 | VERIFIED | `tools/run_grind.sh:25-28`, `tools/run_catalogue.sh:303-307` |
| RTS-R5-7 | VERIFIED | `tools/remote_bench_common.sh:172-180` vs `:146-157` |
| RTS-R5-8 | VERIFIED | `wc -l`: 847 / 343; `tools/run_catalogue.sh:42-43`, `:655` |

Seven of eight items are resolved. R5-5 fixes the reported bug (LTP never executed) but the replacement selection logic is weak enough that it should stay open as a follow-up.

## Per-item findings

### RTS-R5-1 — Duplicate arch lists omit RV32 — VERIFIED
- `tools/bench_harness.sh:25` sources `remote_bench_common.sh` before use; `:81-84` builds `ALL_ARCHES` from `$ARCH_LIST` by stripping at the first colon.
- `tools/remote_bench_common.sh:10` is the single canonical list and includes `riscv32:rvrt:qemu-riscv32`.
- Every entry resolves downstream: `arch_repo` handles `riscv64|riscv32` at `:94`, the QEMU map has `riscv32` at `:168`, and the RV32 build path exists at `:246-249`. Help text updated at `:592`.
- The astra requirement that every accepted filter either selects a matrix entry or is rejected now holds: `--arch riscv32` matches a job.

### RTS-R5-2 — ops/sec millisecond truncation — VERIFIED
- `tests/bench_suite.c:49-66` adds a shift-subtract `udiv64` so freestanding 32-bit targets do not pull in `__udivdi3`; divide-by-zero returns `~0ULL`.
- `:129-135` computes `(iters * 1e6) / us` in 64-bit with `us == 0` clamped to 1 and the result saturated at `0xFFFFFFFF`. This matches the astra fix text, including the "define overflow handling" clause.
- `u32_divmod` remains used at `:85` and `:122`, so no unused-function warning under `-Wall -Wextra`.
- Propagation note from astra (recompute previously recorded `ops_sec` from `us`) is a data concern, not code; not addressed in this commit and not expected to be.

### RTS-R5-3 — VM restoration check can pass without a load — VERIFIED
- `tests/p3_torture.c:629-634` introduces `volatile uint8_t *vbase` / `vsecond`; initial writes, the PROT_NONE read (`:654`), the post-restore write-then-read (`:683-691`), the RO write (`:703`), and the unmapped read (`:732`) all go through volatile accesses.
- The post-restoration check reads into a separate `volatile uint8_t check` and compares against an independent constant, so the compiler cannot fold it.

### RTS-R5-4 — Cross-page test never changes protection — VERIFIED
- `tests/p3_torture.c:551-609`: both pages are warmed by the fill loop (`:510-512`) and the earlier straddling load/store (`:518-547`); then page 1 is `mprotect`'d to `PROT_READ` (`:562`).
- Expected-success path: cross-page load at `ps-5` must still return `0x0123456789ABCDEF` (`:568-571`), which is the pattern written at `:538`. Consistent.
- Expected-fault path: cross-page store spilling into the RO page must raise `SIGSEGV`/`SIGBUS` (`:577-595`) with `si_addr` inside the mapping (`:596-602`), then RW is restored (`:603-607`). Every early-exit path restores RW before `munmap`.
- The signal helpers (`g_segv_jmp:87`, `store/load_segv_addr:98/103`, `segv_handler:182`, `install_handler:195`) are all defined before this function, so no implicit-declaration issue.
- Byte-order checks from the original test are retained.

### RTS-R5-5 — `LTP_DIR` branch never runs LTP — PARTIAL
What is fixed:
- `tools/run_grind.sh:620-629` now discovers executables under `$LTP_DIR/testcases/kernel/syscalls`, `$LTP_DIR/bin`, `$LTP_DIR/testcases/bin` and runs them, reporting under a separate `ltp` label. `libc-ltp` and `ltp` coverage is now reported separately, as astra asked.

What remains:
- **Source-tree layout silently degrades.** `testcases/kernel/syscalls/` in an LTP source tree holds one subdirectory per syscall; the glob `"$_lp"/*` with `[ -f ]` skips directories, so that candidate yields zero binaries. Only the installed layout (`testcases/bin`, `bin`) works. The fallback is a skip, not a failure, so the operator gets no signal.
- **Selection is arbitrary.** The first 50 executables in glob order are run, including `.sh` wrappers that live in `testcases/bin` and will fail under `$_wrap`. Astra asked for "explicit LTP selection"; this is discovery without selection. No LTP environment (`LTPROOT`, `TMPDIR`) is provided, so many syscall tests will fail for reasons unrelated to the translator.
- **Stale `_found` logic.** `:604-606` still counts `LTP_DIR` as satisfying the libc-test branch, so `LTP_DIR` alone produces three `libc-test ... not built` skips against `/bin/functional` etc. Harmless but misleading; the skip message at `:608` still describes `LTP_DIR` as a `libc-ltp` input.
- Minor: `_ld` is a space-joined path list (`:621`), so paths containing spaces break.

Recommendation: either require an LTP manifest (mirroring the libc-test manifest path at `:588-602`) or restrict discovery to `testcases/bin` with an explicit name list. Keep as open R5-5 follow-up.

### RTS-R5-6 — Cancellation traps do not terminate — VERIFIED
- `tools/run_grind.sh:25-28`: `grind_cleanup` function; `EXIT` preserves `$?`; `INT` exits 130; `TERM` exits 143.
- `tools/run_catalogue.sh:303-307`: same pattern inside `run_guest_payload`, installed immediately after the work dir is created. No later `trap` statement in the file overrides it (the only other `trap` strings at `:361`/`:370` are inside quoted test payloads).
- Residual, not blocking: neither script explicitly terminates owned children before removing files. Guests run in the foreground under `timeout`, so a terminal `SIGINT` reaches them; a `SIGTERM` sent only to the script PID will leave the child running briefly while its inputs are removed. Low impact for these runners.

### RTS-R5-7 — Extraction accepts lines excluded by validation — VERIFIED
- `tools/remote_bench_common.sh:172-178`: each field is extracted with the same anchored grammar as `rt_validate_bench_output` (`:146-157`): `$1=="BENCH"`, exact workload name, `NF==6`, numeric `us=`/`ops_sec=`, 8-hex-digit `crc=`, literal `PASS`; summary requires `NF==3` and `ALL_PASS`.
- `:179` rejects any field that is empty or contains a non-digit, which includes the newline of a multi-match result, so the "one value per field" requirement is enforced. `:180` requires `st == ALL_PASS`.
- `:182` no longer substitutes `-` placeholders; partial rows become an explicit `FAIL` row. This is a deliberate fail-closed behaviour change, not a regression.
- Portability caveat: the awk regexes use `{8}` interval expressions. `grep -E` in the validator is fine everywhere; awk interval support is present in gawk, busybox awk, and mawk ≥ 1.3.4-20200120 (Debian 11+/Ubuntu 20.04+), but absent in mawk 1.3.3 (Debian 10). On such a host every record would fail. Worth a one-line note in the script header or replacing `{8}` with eight explicit `[0-9a-f]` atoms.

### RTS-R5-8 — Catalogue runner over size threshold — VERIFIED
- Line counts: `tools/run_catalogue.sh` 847, `tools/catalogue_payloads.sh` 343, both ≤ 900. The extracted file has the correct shebang, zw3rk copyright, and Apache-2.0 SPDX header (`:1-9`), and exposes five functions (`catalogue_emit_selfhost_c/cxx`, `catalogue_emit_mini_s`, `catalogue_emit_guest_makefile`, `catalogue_run_tier4`).
- `run_catalogue.sh:42-43` sources it unconditionally relative to `SCRIPT_DIR`; Tier 4 delegates at `:655`. Public entry points are unchanged (`:799-829`).
- Packaging caveat (astra: "keep the guest invocation self-contained or explicitly package its dependencies"): the documented guest invocation at `:16` and `:803` now implicitly requires `tools/catalogue_payloads.sh` to be present next to the runner inside the sysroot. Because it is sourced at top level, a missing file fails fast at startup, which is acceptable, but the usage text should state the dependency. Not verified here whether any host-side path copies only the single script into a sysroot; none was visible in the grep.

## Curated C11 and shell hygiene

- **File sizes**: all seven touched files ≤ 900 lines. `tools/run_grind.sh` is at 898, effectively at the limit; the next change there will need a split.
- **C11**: no VLAs, no Annex K, no `sprintf`/`strcpy`/`strcat`; `udiv64` uses `int i` with `1ULL << i` for `i ∈ [0,63]`, no UB; mixed declarations/statements in `t_mprotect_munmap` are valid C11. `volatile uint8_t` requires `<stdint.h>`, already included (used elsewhere in the file).
- **Shell**: `#!/bin/sh` scripts stay POSIX (no arrays, `case` for validation); `bench_harness.sh` is `#!/usr/bin/env bash` and legitimately uses arrays. Readability nit: `run_grind.sh:620` and `:626` are very long single-line compound statements; splitting them would not cost lines meaningfully.
- **Git hygiene**: commit message carries no agent attribution; author identity is the zw3rk identity. Untracked `lode/reviews/2026-11-03-defects-r5-rt-series-fable.md` is present in the tree and should be committed or removed before closeout.

## Recommended closeout actions

1. Keep RTS-R5-5 open: add manifest-driven or `testcases/bin`-scoped LTP selection, drop `LTP_DIR` from the `_found` libc-test check at `run_grind.sh:604-606`, and fail (not skip) when `LTP_DIR` is set but no candidate directory yields binaries.
2. Add a one-line dependency note for `catalogue_payloads.sh` to the `guest-payload` usage text in `run_catalogue.sh:799-803`.
3. Optional: replace awk `{8}` intervals in `remote_bench_common.sh:172-176` with explicit atoms for old-mawk hosts.
