# ppc64rt — Round 2 static audit

**HEAD:** `bd3e73fb724e83b8275e7dfe157f8d2f11d40971`  
**Result:** **15 findings: 8 High, 3 Medium, 4 Low.** No Critical finding established.

Seven batched shell inspection turns were used. No builds, compilers, QEMU, Docker, or tests were run, and no files were changed. `git status --short` reported no changes.

The source inventory totals **30,354 lines under `src/`** and **40,346 lines across `src/`, `tests/`, and `experiments/`** for `.c`/`.h`/`.S` files. Inspection covered selected remediation, interpreter/FP, DBT/cache, VM/atomic/quiescence, syscall/signal, loader, backend, and test/build paths. `include/` is absent.

**Coverage limitation:** Several batched outputs were truncated. This report does not claim exhaustive line-by-line inspection of those totals, complete AOT/backend coverage, or full verification of the mremap remediation. Findings are static conclusions; suggested triggering cases were not executed.

## Round-1 remediation verification

The inspected changes address the original sigaction-query overwrite, consolidate the main runner’s signal-mask handling, replace `atoi`, introduce a shared syscall-return helper, remove the unused conditional-store API, and expand the line-limit gate. The inventory found no first-party `.c`/`.h`/`.S` file above 900 lines; the largest inspected file is `src/interp/fp_str.c`, at 874 lines.

However, **P64-1/P64-2/P64-3 are not fully resolved**: reservation ownership remains inconsistent, cooperative children lack general scheduling, and futex deadlines are not implemented. Signal fixes also do not extend consistently to the child execution path. Width-specific atomics fix the original narrow-access problem but expose additional integration defects below.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 6 | 2 | 0 | 0 | 0 | 0 | 8 |
| Medium | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| Low | 0 | 0 | 1 | 1 | 1 | 1 | 4 |
| **Total** | **9** | **2** | **1** | **1** | **1** | **1** | **15** |

## 1. Bugs & Defects

### Critical

None established.

### High

- [ ] **P64-R2-1 — High — DEFECT — Cooperative children lack general scheduling and are killed at an instruction cap**
  - **Where**: `src/os/syscalls_p4.c:173-200`, `src/os/syscalls_p4.c:245-305`, `src/os/syscalls_p4.c:397-413` (`p4_task_step_quantum`, `p4_sched_run_ready`, clone/wake dispatch).
  - **What breaks / Why**: Clone runs a bounded batch of child quanta before returning. Ready children subsequently advance through selected clone/futex paths, rather than through a scheduler integrated into ordinary parent execution. A child waiting for a parent-written flag can remain ready after clone returns, while the parent subsequently waits for the child using ordinary memory operations; neither makes progress. Blocking child host syscalls can also prevent the parent from running. Independently, exceeding 40 million child instructions silently frees the task and returns `EFAULT`, without normal exit cleanup.
  - **Fix**: Integrate task selection into the main execution loop, with bounded quanta and suspension around blocking operations. Remove the lifetime instruction cap from normal execution; keep any diagnostic execution limit explicit and separate from guest syscall results.

- [ ] **P64-R2-2 — High — BUG — Thread exit and thread-group exit still have incorrect scope**
  - **Where**: `src/os/syscalls_p4.c:208-211` (`p4_task_step_quantum`); `src/run/core.c:382-385` (`run` exit dispatch).
  - **What breaks / Why**: A child’s `exit_group` follows exactly the same path as `exit`, finishing only that child. Conversely, the main task’s `exit` breaks the whole runner even when other guest threads remain live. Programs can continue after a requested process-wide termination or lose live workers when only their initial thread exits.
  - **Fix**: Represent individual task termination separately from group termination. Continue scheduling surviving tasks after a thread exits; propagate `exit_group` and its status to the complete guest thread group.

- [ ] **P64-R2-3 — High — DEFECT — Futex timeout validation does not implement timeout behavior**
  - **Where**: `src/os/syscalls_p4.c:333-395` (`syscall_p4_futex`).
  - **What breaks / Why**: Timeout seconds and nanoseconds are read and validated, then discarded. A waiting child records no deadline and can remain suspended indefinitely. A parent returns `ETIMEDOUT` as soon as no child is ready, regardless of the requested interval; with perpetually ready children, the loop does not enforce a deadline. An untimed matching wait can still return `EAGAIN` merely because there is nothing locally runnable.
  - **Fix**: Store deadlines in waiter state, distinguish relative WAIT from absolute WAIT_BITSET deadlines and clock selection, and suspend until wake, interruption, or actual expiry. Couple this with the scheduler rather than interpreting an empty ready queue as timeout or mismatch.

- [ ] **P64-R2-4 — High — BUG — Child execution bypasses the repaired signal machinery**
  - **Where**: `src/os/syscalls_p4.c:193-200`, `src/os/syscalls_p4.c:223-237` (`p4_task_step_quantum`); `src/run/core.c:387-418` (main-task signal dispatch); `src/os/syscalls_access.c:209-219` (`x_sigmask`).
  - **What breaks / Why**: The child runner sends syscalls directly to `ppc64_syscall`, bypassing the main runner’s sigaction, kill/tgkill, sigreturn, and altstack interception. A child memory fault frees the task and returns `EFAULT` instead of delivering its installed guest handler. Signal masks are also held in one static variable, so one child’s mask change changes the parent’s mask. The Round-1 signal fixes therefore do not provide per-thread Linux signal behavior.
  - **Fix**: Use the same trap/syscall/signal dispatch for every guest task. Keep blocked masks, pending thread-directed signals, altstack, and return-frame state per task; share dispositions only according to clone semantics.

- [ ] **P64-R2-5 — High — BUG — VM atomics ignore the interpreter’s per-context reservation token**
  - **Where**: `src/interp/vec.c:110-149`, `src/interp/vec.c:151-180` (`ppc64_exec_larx_stcx`); `src/vm/vm_atomic.c:263-290`, `src/vm/vm_atomic.c:303-315` (`vm_mem_atomic`, `ppc64_vm_reserve`).
  - **What breaks / Why**: The interpreter saves and passes a reservation token, but the VM callback does not populate or check that token. It uses one `vm->resv_*` record shared by guest contexts. A later context’s LR can replace the record that an earlier context’s SC checks. This becomes a false-success risk when a write invalidates the VM reservation without clearing the earlier interpreter slot, followed by another context’s LR at the same address: the earlier SC can consume the newer reservation and overwrite data despite its original reservation having been lost.
  - **Fix**: Return an actual reservation identity/version from LR and validate that exact identity on SC. Keep ownership per guest context and invalidate it across all relevant writes and task lifecycle transitions.

- [ ] **P64-R2-6 — High — BUG — Successful atomic stores bypass code invalidation and shared-file write propagation**
  - **Where**: `src/vm/vm_atomic.c:271-297` (`vm_mem_atomic`); `src/vm/vm64.c:288-315` (`vm_mem_write`).
  - **What breaks / Why**: The aligned SC/RMW path modifies host backing directly and only calls `ppc64_vm_reserve_note_store`. Ordinary writes additionally retire translated code and propagate MAP_SHARED writes to the file and sibling mappings. Routing guest SC through the atomic callback makes this omission reachable: an atomic patch to translated code can leave stale executable translations, and an atomic modification to a shared file mapping can remain local.
  - **Fix**: Integrate atomic stores with the VM write protocol: perform required COW/code invalidation before publication and shared-backing propagation after successful modification. Preserve atomicity rather than replacing CAS with an ordinary copy.

- [ ] **P64-R2-7 — High — BUG — Scalar FP arithmetic ignores guest rounding and single-precision result rounding**
  - **Where**: `src/interp/fp.c:92-125` (`fp_add`, `fp_sub`, `fp_mul`, `fp_div`); `src/interp/fp.c:259-279` (`fp_po63`); `src/interp/fp.c:794-797` (`ppc64_fp_step`).
  - **What breaks / Why**: Opcodes 59 and 63 use the same host-double arithmetic path. Single-precision instructions therefore retain double-precision results instead of rounding to binary32 and representing that rounded value in the FPR. For example, single-precision addition of `1.0` and `2^-24` under nearest-even should produce `1.0`; this path retains `1.0 + 2^-24`. Arithmetic also never consults FPSCR.RN, so guest rounding-mode changes do not govern results. DBT fallback inherits these interpreter errors.
  - **Fix**: Implement format-specific arithmetic with guest rounding control, preferably through the existing established software-FP substrate or a carefully controlled host-FP layer. Add oracle cases for all rounding modes and binary32 halfway values.

- [ ] **P64-R2-8 — High — BUG — Child cleanup can clear the parent’s clear-TID address**
  - **Where**: `src/os/syscalls.c:563-579` (`SET_TID_ADDRESS`, clone dispatch); `src/os/syscalls_p4.c:156-169`, `src/os/syscalls_p4.c:297-301` (`p4_task_finish`, `syscall_p4_clone`).
  - **What breaks / Why**: `set_tid_address` updates a single global `s_clear_tid`, which is passed into clone and copied into the child’s `set_tid_addr`. Child exit clears and wakes that address in addition to its requested `CLONE_CHILD_CLEARTID` address. A parent that registered its own clear-TID word can therefore have that word zeroed when an unrelated child exits. A child calling `set_tid_address` also changes global state rather than its own task’s cleanup address.
  - **Fix**: Store clear-TID state per task. Initialize the child according to clone flags, update the current task on `set_tid_address`, and clear only the exiting task’s registered address.

### Medium

- [ ] **P64-R2-9 — Medium — BUG — FPSCR exception and record-form updates are fabricated**
  - **Where**: `src/interp/fp.c:31-41` (`ppc64_fpscr_record`); `src/interp/fp.c:280-298` (`fp_po63`).
  - **What breaks / Why**: Finite division results are treated as inexact whenever repeating the same host division produces the same bits; exact division such as `4.0 / 2.0` satisfies that condition. The exception helper places flags in an ad hoc `exc << 4` layout and sets bit 32, rather than implementing architectural FPSCR status fields. Record forms then write CR1 as zero rather than copying the required FPSCR summary. Guest exception inspection and branches on FP status are incorrect.
  - **Fix**: Collect actual operation exceptions, map them into named Power FPSCR fields, maintain summary/sticky status, and derive CR1 from the architectural fields.

- [ ] **P64-R2-10 — Medium — BUG — Access syscalls reject valid relative paths and directory descriptors**
  - **Where**: `src/os/syscalls_access.c:109-115` (`acc_guest_abs`); `src/os/syscalls_access.c:147-158` (`syscall_faccessat`); `src/os/syscalls_access.c:173-180` (`syscall_access`).
  - **What breaks / Why**: Relative paths unconditionally return `EBADF`. `faccessat` also rejects every directory descriptor except `AT_FDCWD`, even for an absolute path where the descriptor should be ignored. Ordinary `access("file", F_OK)` and descriptor-relative access checks fail despite valid files and descriptors.
  - **Fix**: Resolve relative paths against guest cwd or the translated directory descriptor. Ignore `dirfd` for absolute paths and preserve Linux error semantics.

- [ ] **P64-R2-11 — Medium — BUG — Path copy-in reads beyond a valid terminating NUL**
  - **Where**: `src/os/syscalls_access.c:98-115` (`acc_guest_abs`).
  - **What breaks / Why**: The function reads an entire 256-byte chunk before checking for a terminating NUL. A valid short pathname near the end of a readable guest page returns `EFAULT` if the chunk crosses into an inaccessible page, even though the complete string is readable.
  - **Fix**: Bound each read to the remaining bytes in the current guest page, inspect for NUL, and only access the next page when necessary. Reuse the corrected copy-string helper within this repository.

### Low

No additional low-severity BUG/DEFECT findings.

## 2. Curated C11 & UB Issues

- [ ] **P64-R2-12 — Low — C11 — Generated test source still calls banned strcpy**
  - **Where**: `tests/h2_run.sh:100-106` (generated `t_string` function).
  - **What breaks / Why**: The generated first-party C source uses `strcpy`, contrary to the explicitly requested curated subset. This particular literal fits the destination, so this is a policy violation rather than an established overflow.
  - **Fix**: Initialize the array directly or use a bounded copy with a known size. Include generated C embedded in scripts in source-policy scans.

No additional definite C undefined behavior was established within the inspected excerpts. The targeted scan found no textual `.c` unity includes or explicit assembly access to `x18`; this does not verify every encoded JIT instruction.

## 3. DRY — Intra-Repo Duplication

- [ ] **P64-R2-13 — Low — DRY — Access and faccessat duplicate resolution and retry logic**
  - **Where**: `src/os/syscalls_access.c:159-170`, `src/os/syscalls_access.c:181-192` (`syscall_faccessat`, `syscall_access`).
  - **What breaks / Why**: Both functions repeat the initial access call, fallback buffer construction, sysroot remapping, and retry. Their path-semantics fixes must consequently be maintained twice.
  - **Fix**: Use a repository-local helper for the resolved-path access and fallback operation, with cwd/dirfd resolution handled explicitly by its caller. No cross-repository library is needed.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **P64-R2-14 — Low — YAGNI — Guest rounding-mode accessor has no production caller**
  - **Where**: `src/interp/fp.c:24-29` (`ppc64_fpscr_rn`).
  - **What breaks / Why**: The repository symbol search finds its declaration and definition but no caller. The accessor suggests a rounding integration point while live arithmetic ignores the mode, as described in P64-R2-7.
  - **Fix**: Connect it to the corrected arithmetic implementation, or remove the unused exported API until that integration exists.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P64-R2-15 — Low — CLEAN — Thread module documentation describes the removed execution model**
  - **Where**: `src/os/syscalls_p4.c:4-17` (file header).
  - **What breaks / Why**: The header still says clone runs a child inline to completion, unchanged-word futex WAIT is unreachable, and WAKE has no waiters. The implementation now retains runnable and waiting tasks. These claims conceal the actual scheduling and lifetime obligations precisely where maintainers need an accurate concurrency description.
  - **Fix**: Document the current cooperative task model, its scheduling entry points, task ownership, and remaining limitations. Remove assertions based solely on the old gate-test execution order.

The line-count scan found no current first-party ceiling violation. Complete mremap rollback, synchronous host-fault recovery, AOT validation, and concurrent cache/quiescence safety remain **unqualified by this bounded audit**.