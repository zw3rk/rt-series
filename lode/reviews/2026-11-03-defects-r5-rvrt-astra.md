**Round 5 found seven actionable issues.** The strongest are incorrect accepted inputs in the Soft-TLB emitter and byte-range corruption in the VM mapping helper. Their integration limits are noted below.

Used exactly **8 shell invocations**, all read-only. No Markdown files, builds, tests, Docker, or QEMU were run. Inspected selected interpreter/FP, DBT, VM, OS, ELF32, signal, family, and test paths; this is a bounded static audit, not whole-repository qualification.

1. **[RV-R5-1] BUG — Soft-TLB stores accept registers that the lookup destroys**

   **Location:** [src/dbt/emit_mem.c:137](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:137), [src/dbt/emit_mem.h:19](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.h:19).

   `rv_dbt_reg_usable()` accepts x2, x3, and x4 as store-value registers. The emitted lookup overwrites all three before executing the store. For example, `is_store=true, val_reg=2` passes validation but stores lookup state instead of the incoming value. Loads into x20 can also destroy the pinned TLB base.

   **Fix:** Enforce the documented x0 value/destination convention, or define operation-specific register exclusions. Add negative cases for scratch registers and x20. Existing shape tests exercise `val_reg=0`.

   **Impact limit:** Repository searches found test callers of this emitter, not a production call path.

2. **[RV-R5-2] DEFECT — Emitter silently truncates site offsets**

   **Location:** [src/dbt/emit_mem.c:135](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:135), [src/dbt/emit_mem.c:152](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:152).

   Validation bounds `guest_pc_delta`, but not the host offsets subsequently cast to `uint16_t`. For example, `base_offset=65536, stub_offset=65568` is accepted, yet `seq_start_offset` becomes zero. A sequence starting below 65536 can also overflow its continuation offset. Unaligned offsets are accepted even though branch encoding divides the displacement by four.

   **Fix:** Before emitting anything, validate alignment, checked offset addition, and representability of every stored offset. Add boundary tests around the last representable continuation.

   **Impact limit:** This is a demonstrated API defect; current production reachability was not established.

3. **[RV-R5-3] BUG — Partial-page file replacement overwrites surviving bytes**

   **Location:** [src/vm/vm64.c:603](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:603), [src/vm/vm64.c:618](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:618).

   On a 4 KiB host, matching low address/offset bits select `MAP_FIXED`, even when the requested range covers only part of a host page. The code expands backward by `head`; the kernel also rounds the mapped length upward. VMA removal, however, covers only the original byte range.

   For example, replacing `[4097,4098)` with file offset 1 remaps the whole page beginning at 4096. Bytes outside the requested range change while their surviving VMA metadata remains.

   **Fix:** Use direct file mapping only when the replacement covers complete host pages. Otherwise preserve surrounding bytes through the staged-copy path, or explicitly reject unsupported alignment. Test sentinels before and after a one-byte replacement.

   **Impact limit:** Runtime integration labels this VM a **best-effort shadow** at [src/runtime/runtime_main_exec_wait.c:20](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_exec_wait.c:20); this finding does not establish corruption of authoritative guest memory.

4. **[RV-R5-4] DEFECT / CLEAN — EOF rounding guard uses an impossible threshold**

   **Location:** [src/vm/vm64.c:703](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:703).

   The overflow guard compares `new_size / 4096` with `0xffffffffffffff`. That quotient cannot exceed `0xfffffffffffff`. Consequently, `new_size=UINT64_MAX` bypasses the guard and rounds to zero, making ordinary mapped pages appear beyond EOF.

   **Fix:** Replace the literal with checked rounding based on `UINT64_MAX` and `RV_VM64_GUEST_PAGE_SIZE`, or reject sizes outside the supported signed file-offset range.

   **Impact limit:** Normal signed host file sizes do not reach this case; the exposed `uint64_t` callback accepts it.

5. **[RV-R5-5] DEFECT — “Bounded” parity execution becomes unbounded without `timeout`**

   **Location:** [tests/parity_suite.sh:56](/Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh:56), [tests/parity_suite.sh:202](/Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh:202).

   When `timeout` is unavailable, the runner sets an empty prefix and executes guests directly. A looping guest hangs the suite indefinitely. The AOT cold/warm paths use the same fallback.

   **Fix:** Require a supported timeout implementation and report GAP when unavailable, or provide a bounded watchdog that terminates and reaps the child. Test timeout-tool absence and a deliberately nonterminating fixture.

6. **[RV-R5-6] DRY — Family mutation paths duplicate exact identity comparison**

   **Location:** [src/runtime/family_file_pwrite.c:17](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_file_pwrite.c:17), [src/runtime/family_file_truncate.c:269](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_file_truncate.c:269).

   Both define identical `same_identity()` implementations for validating staged mutation records. Future identity-field changes can update one validation path without the other.

   **Fix:** Extract one repository-local helper named for exact snapshot equality. **Do not substitute `rv_file_identity_equal()` unchanged:** it validates identities, compares only `length` bytes, and omits `mapped_key_eligible`, so its semantics differ.

7. **[RV-R5-7] YAGNI / CLEAN — Dormant commit-window field claims synchronization it never performs**

   **Location:** [src/os/backend.h:59](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend.h:59), [src/os/backend_linux.c:204](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:204), [src/os/backend_darwin.c:317](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:317).

   The comment says `in_commit_window` guards the commit step. Searches across `src/`, `test/`, and `tests/` found only its declaration and zero initialization—no reads or transitions. It supplies no protection and misstates the implemented protocol.

   **Fix:** Remove the unused field and claim, or explicitly document it as reserved if layout compatibility requires retention. Do not infer a working commit guard from this structure.

**Cross-runtime propagation checks**

| Findings | Sibling checks |
|---|---|
| RV-R5-1–2 | Check a32rt and other rt-series runtimes carrying equivalent Soft-TLB emitters for scratch-register acceptance and narrow site offsets. |
| RV-R5-3–4 | Check corresponding arena/COW providers, especially 4 KiB direct-mapping paths and EOF rounding. |
| RV-R5-5 | Check sibling `tests/parity_suite.sh` runners and the rt-series catalogue’s timeout assumptions. |
| RV-R5-6 | Check equivalent family write/truncate validation pairs; consolidate only within each repository. |
| RV-R5-7 | Check copied Darwin/Linux backend structures and their protocol comments. |

These are propagation targets, not verified sibling defects. No inspected C source/header under `src/` or `tests/` exceeded 900 lines. No additional interpreter, FP, ELF32, or signal finding met the evidence threshold within this budget.