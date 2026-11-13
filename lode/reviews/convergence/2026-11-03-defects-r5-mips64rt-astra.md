Found **11 issues** from static inspection. Used **8 shell commands**; read no Markdown files and ran no builds, tests, Docker, or QEMU. No files changed. The actual audit paths are `src/loader.c` and `tests/`; `src/elf/` and `tools/tests/` do not exist.

1. **[M64-R5-1] BUG / DRY — `clock_nanosleep` dispatch uses the wrong argument layout. High.**

   **Evidence:** [syscall_min.c:673](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:673), [syscalls_time.c:103](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_time.c:103).

   The dispatcher passes `(clock, flags, request)` into a helper expecting `(clock, request, remainder)`. A normal call with `flags == 0` therefore reads its timespec from guest address zero and ordinarily returns `EFAULT`. The N32 time64 route repeats this error. The old helper also handles `clock_nanosleep` errors through `errno`, although that host function returns the error number directly.

   **Fix:** Route both variants through the existing four-argument helper at [syscalls_extra.c:128](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_extra.c:128), passing `a0..a3`, and remove the duplicate clock path. Before enabling that helper, fix its absolute-sleep handling: it currently copies uninitialized `rm` after an interrupted `TIMER_ABSTIME` sleep, for which the host does not supply a remainder.

2. **[M64-R5-2] DEFECT — Failed file refreshes become successful zero-filled updates. High.**

   **Evidence:** [vm64.c:442](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:442), [vm_file.c:700](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:700).

   `mips_vm_inode_refresh_span` converts every negative `pread` result into zero, zero-fills the requested span, and returns success. Consequently, `vm_inode_apply_write_locked` advances `seen_write_seq` and `seen_resize_seq`. An interrupted or failed read can corrupt an alias and suppress the Round 4 reconciliation retry.

   **Fix:** Retry `EINTR`, complete short reads, distinguish EOF from errors, and return failure after restoring protection. Prefer staging the read before modifying guest bytes.

3. **[M64-R5-3] BUG — Floating-format conversions omit signaling-NaN exceptions. High.**

   **Evidence:** [fp_cvt.c:117](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:117), [fp_cvt.c:134](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:134).

   `CVT.S.D` and `CVT.D.S` canonicalize every NaN and return without checking `fp_issn_d`/`fp_issn_s` or raising Invalid. A signaling NaN therefore neither updates the required exception state nor triggers an enabled Invalid trap. DBT NaN conversions fall back to this same interpreter behavior.

   **Fix:** Classify the original source bits, raise `FP_EXC_V` for signaling NaNs, and retain the existing `fp_finish_trap` destination-restoration path.

4. **[M64-R5-4] BUG — `CFC1` zero-extends FCSR instead of sign-extending it. Medium.**

   **Evidence:** [fpmove.c:181](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:181).

   Casting `ctx->fcsr` directly to `uint64_t` produces a zero-extended result. When FCC7 sets bit 31, `CFC1` must sign-extend its 32-bit control-register result into the 64-bit GPR. For example, `0x80000000` currently becomes `0x0000000080000000`.

   **Fix:** Use `interp_sext32(ctx->fcsr)` and check other 32-bit control-register transfers for the same pattern.

5. **[M64-R5-5] BUG — Raw `exit` from the thread-group leader kills surviving threads. High.**

   **Evidence:** [syscall_min.c:550](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:550), [threads.c:480](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:480).

   Only contexts marked `is_thread_clone` receive thread-only exit handling. Raw guest `exit` from the original thread reaches host `_Exit`, terminating every worker. Linux thread-only exit semantics also apply to the leader; surviving threads must continue.

   **Fix:** Separate thread termination from `exit_group` for every context. Handle leader context ownership explicitly—the current worker cleanup unconditionally frees its context—and preserve final-process exit status when the last thread terminates.

6. **[M64-R5-6] DEFECT — Production `AT_RANDOM` uses predictable clock/PID state. High.**

   **Evidence:** [loader.c:245](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:245).

   The loader derives its seed entirely from realtime and PID, then expands it with xorshift. This is not an OS entropy source, despite the comment claiming production entropy. Guest libc can use these bytes for stack canaries and pointer guards.

   **Fix:** Obtain all 16 production bytes from the host OS random facility, handling interruptions and failures. Keep deterministic generation confined to the explicit test override.

7. **[M64-R5-7] BUG — Provider region coalescing inserts duplicate overlapping records. Medium.**

   **Evidence:** [vm64.c:74](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:74).

   After extending the left neighbor, `u0_record` decrements `i` but falls through to insertion. Mapping adjacent equal-protection regions `[A,B)` and `[B,C)` creates two records covering `[A,C)`. Repeated adjacent mappings consume the bounded table despite being coalescible.

   **Fix:** Finish the left merge without inserting another record; if the right neighbor also matches, absorb and remove it. Cover left-only and two-sided merges.

   **Scope:** References inspected show this provider interface exercised by unit tests, rather than the live `mips_mem_*` mapping path.

8. **[M64-R5-8] DEFECT — Provider capacity failures leave host mappings and metadata inconsistent. Medium.**

   **Evidence:** [vm64.c:173](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:173), [vm64.c:113](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:113), [vm64.c:234](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:234).

   Mapping changes host memory before `u0_record` can reject table exhaustion. Conversely, unmapping a straddling region at capacity changes host memory to `PROT_NONE`, then `u0_forget` silently returns without updating metadata; the caller reports success.

   **Fix:** Preflight the resulting region table before host mutation. Make bookkeeping operations return errors and commit metadata only after the corresponding host operation succeeds. This has the same provider-only scope as finding 7.

9. **[M64-R5-9] BUG — Differential-test script can certify two failed executions. High for validation.**

   **Evidence:** [run_difftest.sh:128](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:128), [run_difftest.sh:142](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:142), [run_difftest.sh:153](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:153).

   The script requires only equal exit codes. Two loader failures with no instruction or register records produce equal empty streams and print `DIFFTEST: 0 divergences`. Sorting also discards instruction order, and captured stdout is never compared.

   **Fix:** Reject infrastructure failures/timeouts, require expected completion evidence and nonempty captures, and compare stdout. Preserve instruction order per process; use explicit process identification when forked traces need separation.

10. **[M64-R5-10] BUG — Implemented `clock_getres` has no syscall dispatch route. Medium.**

    **Evidence:** [syscalls_extra.c:101](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_extra.c:101), [syscall_nr.h:171](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_nr.h:171), [syscall_min.c:853](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:853).

    The repository defines the syscall numbers and implementation, but no dispatcher calls the helper. Guest calls fall through to `ENOSYS`.

    **Fix:** Wire the ABI-specific dispatch entries. Also fix the helper’s unconditional copyout: a valid clock query with a null result pointer must succeed without writing memory.

11. **[M64-R5-11] DRY / YAGNI / CLEAN — FP emitter retains duplicate guards and obsolete rounding machinery. Low.**

    **Evidence:** [emit_fp.c:200](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:200), [emit_fp.c:215](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:215), [emit_fp.c:130](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:130), [emit_fp.c:371](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:371).

    `ef_mode_guard` and `ef_fs_guard` emit identical sequences using the same mask. `ef_fhalf` has no call sites; `(void)ef_fhalf` merely suppresses the unused-function warning. Comments still describe ties-away rounding although mode 4 now emits ties-to-even `FRINTN`.

    **Fix:** Consolidate the identical guard implementation, remove the unused half-constant emitter and suppression, and correct the rounding comments. Keep this consolidation within the repository.

**Cross-runtime propagation checks**

These are suggested inspection targets, not confirmed sibling defects.

| Findings | Sibling runtimes to check |
|---|---|
| 1, 5, 10 | `mips32rt` first; then `rvrt`, `a32rt`, `i686rt`, and other runtimes with copied syscall/thread dispatch |
| 2, 7, 8 | `rvrt` and runtimes carrying the same file-alias reconciliation or provider region code |
| 3, 4 | `mips32rt` first; inspect other FP engines for conversion exception handling |
| 6 | All sibling ELF loaders supplying `AT_RANDOM` |
| 9 | Sibling differential-test scripts, especially copied sorting and exit-comparison logic |
| 11 | `mips32rt` and sibling AArch64 FP emitters with matching helpers |

The source line-count scan found **no `.c`, `.h`, or `.S` file above 900 lines**; `src/os/mem_table.c` is exactly 900. Findings remain statically established paths and failure scenarios, without execution-based confirmation.