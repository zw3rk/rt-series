Found **8 actionable issues** at `56bec31`. The Round-3 and follow-up commits are present; the `munmap` preflight now precedes table mutation, but exec inheritance and remap error handling still have gaps.

Used seven shell inspection calls. No Markdown documents, builds, tests, containers, or QEMU were read or run. Findings are static, not runtime-confirmed. `include/` and `tools/` are absent.

**P64-R4-1 — Single-precision arithmetic rounds operands prematurely**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp.c:202`
- **Evidence & Root Cause:** PO59 arithmetic reaches `fp_arith_exec()`, which casts both FPR operands to `float` before calculating. This discards input precision before the instruction’s result rounding. For `fadds` with operands `1 + 2^-24` and `-1`, nearest-even input conversion makes the first operand `1`, producing zero instead of the representable result `2^-24`. Operand conversions also contaminate the collected exception flags.
- **Concrete Fix:** Implement the instruction’s operand precision and final binary32 rounding explicitly. Avoid premature operand conversion and account for double-rounding cases. Add oracle regressions for cancellation, rounding boundaries, and FPSCR flags.

**P64-R4-2 — Integer conversions omit FPSCR updates**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:424`
- **Evidence & Root Cause:** The `fctiwz` and `fctidz` branches select integer results for fractional, NaN, and out-of-range inputs but never record conversion exceptions. Their record forms then copy the unchanged FPSCR summary into CR1. For example, converting a NaN leaves `VXCVI` unset; fractional conversion leaves inexact state unchanged.
- **Concrete Fix:** Implement conversion-specific invalid and inexact handling, including applicable signaling-NaN flags and FPSCR summary updates, before updating CR1. Test fractional, boundary, infinity, and NaN inputs.

**P64-R4-3 — Growing file mappings silently accepts refill failures**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file_mremap.c:101`
- **Evidence & Root Cause:** `vm_file_fill_tail()` retries interrupted `pread()` calls but ignores other read errors, accepts short reads without completing them, and discards `ppc64_vm_write_raw()` failure. It still returns success after marking the page CLEAN or SHARED. Because `syscall_mm_mremap()` initially stages a zero-filled extension, a failed refill can produce a successful remap exposing zeros instead of file bytes.
- **Concrete Fix:** Complete reads until the requested span or actual EOF, propagate read and raw-write failures, and let the existing remap rollback restore state. Handle unavailable backing descriptors explicitly. Add injected read/write-failure regressions.

**P64-R4-4 — Worker exec inherits the wrong pending-signal set**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:120`
- **Evidence & Root Cause:** `run_sig_exec_snapshot()` obtains the current task’s mask through `ppc64_syscall_sigmask_get()`, but copies pending signals directly from `run_sig_pending`, the main-task storage. Worker pending signals live in `s_cur_task->sig_pending`, selected by `syscall_p4_sigpending_ptr()` at `src/os/syscalls_p4.c:115`. A worker exec therefore loses its own pending signals and can inherit another task’s pending signals.
- **Concrete Fix:** Snapshot the executing task’s pending set through the task-aware accessor. If process-directed pending signals are represented separately, combine only those with the caller’s thread-directed set. Test exec from a worker with distinct blocked pending signals on worker and main task.

**P64-R4-5 — Exec converts default dispositions into explicit ignore**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:112`
- **Evidence & Root Cause:** The snapshot uses `run_sig_is_ignored()`, which includes default dispositions for signals 17, 18, 23, and 28. Restore installs every resulting bit as `handler = 1`, meaning explicit `SIG_IGN`. Consequently, a default disposition becomes observably different after exec when queried through `rt_sigaction`.
- **Concrete Fix:** Serialize only explicitly installed `SIG_IGN` dispositions (`handler == 1`). Leave default dispositions default. Test disposition queries before and after exec, covering both `SIG_DFL` and explicit `SIG_IGN`.

**P64-R4-6 — Internal exec variables reach the guest before removal**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/core.c:551`
- **Evidence & Root Cause:** `run_build()` constructs the guest stack before invoking `run_sig_exec_restore()` at line 576. `run_build_stack()` copies host `environ` into guest memory at `src/run/load.c:479`. The later `unsetenv()` calls remove only host entries; the guest already holds copies of `PPC64RT_EXEC_SIGMASK`, `PPC64RT_EXEC_SIGIGN`, and `PPC64RT_EXEC_SIGPEND`.
- **Concrete Fix:** Capture and remove the handoff variables before building the guest environment, then apply the captured state after signal initialization. Test that inheritance works while the guest environment contains none of these internal entries.

**P64-R4-7 — Expanded exec environment exceeds cleanup’s bound**

- **Severity:** Low
- **Category:** DEFECT
- **Location:** `src/os/proc.c:443`
- **Evidence & Root Cause:** `proc_envp_inject_sig()` can grow a valid 256-entry environment to 259 entries. After host exec fails, `proc_free_strvec()` frees only indices `0..PROC_MAX_ARGS` inclusive, then frees the vector. Entries 257 and 258 leak on this path. Repeated failed exec calls repeat the leak.
- **Concrete Fix:** Carry the owned element count with each vector, or free validated host-owned vectors through their guaranteed NULL terminator. Make cleanup independent of the guest-input cap. Add a failed-exec regression with a maximum-length environment.

**P64-R4-8 — File staging duplicates logic and error policy**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/syscalls_mm_map.c:42`
- **Evidence & Root Cause:** `mm_stage_file()` and `ppc64_vm_file_fill()` at `src/vm/vm_file.c:767` independently implement allocation, bounded `pread`, EINTR retry, offset checks, short-read termination, and zero-filling. Their error handling already differs: the former preserves `EBADF`, while the latter converts every read error to `EIO`. The new remap-tail reader introduces a third, less complete variant.
- **Concrete Fix:** Introduce one repository-local staged file-read helper with explicit short-read, EOF, offset, and error semantics. Reuse it in mapping and remap population while retaining their separate publication and rollback responsibilities.

The CLEAN scan found no source files above 900 lines—the largest was 890—and no prohibited string-function calls or `.c` includes in the searched trees. Literal `x18` matches were comments; that scan does not establish correctness of encoded JIT register operands. No sufficiently supported YAGNI finding emerged from this bounded inspection.

- [ ] **P64-R4-1:** Correct single-precision operand and result rounding.
- [ ] **P64-R4-2:** Record integer-conversion FPSCR exceptions.
- [ ] **P64-R4-3:** Propagate file-remap refill failures.
- [ ] **P64-R4-4:** Preserve the executing task’s pending signals.
- [ ] **P64-R4-5:** Preserve the distinction between default and ignored dispositions.
- [ ] **P64-R4-6:** Remove internal handoff variables before guest-stack construction.
- [ ] **P64-R4-7:** Free every injected environment entry after failed exec.
- [ ] **P64-R4-8:** Unify staged file reads in a repository-local helper.