# ppc64rt — Read-only static audit

**HEAD:** `f42cf1ae5f50e9b13a3d74ec5bef3de9369a2b21`

**Result:** 16 findings: **6 High, 5 Medium, 5 Low**. No Critical finding established.

The source inventory contains **83 `.c`/`.h`/`.S` files under `src/`, totaling 29,551 lines**; including tests and experiments gives 39,554 lines. Inspection covered selected interpreter/decoder, DBT/cache/TLB, VM/atomics, loader, syscall, signal, backend, and build-rule paths.

This was a bounded static audit using six batched shell inspections, plus one output retrieval. No builds, compilers, QEMU, Docker, or tests were run. Some large outputs were truncated, so this report does **not** claim exhaustive line-by-line coverage or qualification of every module. Findings below cite inspected source; suggested failure cases were not executed.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 4 | 2 | 0 | 0 | 0 | 0 | 6 |
| Medium | 4 | 0 | 1 | 0 | 0 | 0 | 5 |
| Low | 0 | 0 | 1 | 1 | 1 | 2 | 5 |
| **Total** | **8** | **2** | **2** | **1** | **1** | **2** | **16** |

## 1. Bugs & Defects

### Critical

None established.

### High

- [ ] **P64-1 — High — BUG — Guest LL/SC bypasses the atomic memory interface**
  - **Where**: `src/interp/interp.c:25-38`, `src/interp/interp.c:537-557` (`g_res_valid`, reservation instruction execution).
  - **What breaks / Why**: Load-reserve performs an ordinary `mem->read` and records a process-global address/width. Store-conditional checks those globals and performs an ordinary `mem->write`. It never invokes `mem->atomic`, despite the VM providing that interface. An intervening write through another execution path can change the reserved location without clearing this interpreter state; store-conditional then reports success and overwrites it. Separate guest contexts also share the same reservation. DBT interpreter fallback inherits this defect.
  - **Fix**: Make reservations CPU/worker-local and route reservation instructions through a coherent atomic implementation. Coordinate reservation invalidation with interpreter stores, DBT stores, syscall writes, and shared backing mutations. Do not simply wire in the existing callback without addressing P64-11.

- [ ] **P64-2 — High — DEFECT — Clone executes the child to completion before returning to the parent**
  - **Where**: `src/os/syscalls_p4.c:104-139`, `src/os/syscalls_p4.c:159-184` (`syscall_clone_child_run`, `syscall_p4_clone`); `src/os/syscalls.c:570-579` (live dispatch).
  - **What breaks / Why**: The production clone path calls an unbounded interpreter loop for the child before the parent receives its clone result. A child waiting for any action by its parent prevents that parent from running. Ordinary pthread startup and synchronization patterns therefore cannot rely on Linux scheduling semantics. Child `exit_group` is also treated as completion of this inline child rather than termination of the thread group.
  - **Fix**: Implement resumable guest tasks with scheduling at blocking operations and appropriate instruction boundaries, or properly isolated host workers. Preserve per-thread TLS, signal state, clear-TID state, and thread-group exit semantics.

- [ ] **P64-3 — High — DEFECT — Futex WAIT always returns EAGAIN and WAKE never wakes**
  - **Where**: `src/os/syscalls_p4.c:188-214` (`syscall_p4_futex`); `src/os/syscalls.c:585-590` (live dispatch).
  - **What breaks / Why**: WAIT reads the word but returns `EAGAIN` regardless of whether it equals the expected value. WAKE always returns zero. Matching waits never block, timeouts cannot complete correctly, and mutex/condition-variable implementations can spin indefinitely. This behavior is explicitly tailored to the gate test rather than general guest execution.
  - **Fix**: Implement compare-and-enqueue atomically with respect to wake operations, suspend matching waiters, and implement wake counts, timeouts, bitsets, interruption, and argument validation.

- [ ] **P64-4 — High — BUG — Querying sigaction destroys the disposition and never returns the old action**
  - **Where**: `src/run/sigdeliver.c:54-84` (`run_sig_record`).
  - **What breaks / Why**: When `act == NULL`, the function clears the disposition and returns success. A query must leave the disposition unchanged. The function never handles `args[2]`, the `oldact` pointer, so queries and replacements do not return the previous action; an invalid output pointer is silently accepted. Libraries that inspect or temporarily replace handlers lose their previous state.
  - **Fix**: Serialize the previous action to `oldact` when supplied, validate copyout, and install a replacement only when `act` is non-null. Reject attempts to change uncatchable signals.

- [ ] **P64-5 — High — BUG — Signal delivery and sigprocmask maintain disconnected masks**
  - **Where**: `src/run/sigdeliver.c:33-44`, `src/run/sigdeliver.c:160-202` (`run_sig_blocked`, `run_deliver`); `src/os/syscalls_conv.c:818-845` (`x_sigprocmask`); `src/run/core.c:453-460` (sigreturn).
  - **What breaks / Why**: `rt_sigprocmask` updates `x_sigmask`, while delivery saves the separate `run_sig_blocked`, which is only reset to zero. Delivery does not apply the action mask or automatically block the delivered signal. The sigreturn path receives restored metadata in `sout` but does not restore the runtime mask. Consequently, blocked signals can be delivered immediately, frames report the wrong mask, and handler masking is ineffective.
  - **Fix**: Use one per-thread signal-state object for syscall mask operations, pending delivery, handler entry, and sigreturn. Apply action masks and `SA_NODEFER`, then restore the saved mask and reconsider pending signals.

- [ ] **P64-8 — High — BUG — Failed fixed mremap destroys the previous destination mapping**
  - **Where**: `src/os/syscalls_mm.c:777-802` (`syscall_mm_mremap`).
  - **What breaks / Why**: The destination is unmapped before insertion and copying succeed. On insertion, copy, or protection failure, cleanup unmaps the destination again and calls the quiescence abort function. This code retains no snapshot of the destination mapping or its bytes to restore. A failing `MREMAP_FIXED` can therefore destroy an unrelated live mapping, contradicting the function’s “full rollback” comment.
  - **Fix**: Prepare the move before destructive publication. Preserve destination mapping/backing metadata until commit, or implement complete rollback of all removed mappings and contents.

### Medium

- [ ] **P64-6 — Medium — BUG — kill/tgkill mishandles probes, ignored signals, and syscall return state**
  - **Where**: `src/run/core.c:428-451` (kill/tgkill interception); `src/run/sigdeliver.c:79-83`, `src/run/sigdeliver.c:195-199` (disposition storage and entry).
  - **What breaks / Why**: Signal zero is rejected instead of performing an existence/permission probe. A self-directed signal without a registered handler returns `ESRCH`, conflating process existence with disposition. `SIG_IGN` is stored as a nonzero handler and can be entered as guest address 1. Successful handler delivery advances NIP without first applying the syscall success result, so the saved frame retains the syscall’s input registers rather than its return value. The `tgkill` TID is explicitly unchecked.
  - **Fix**: Handle default, ignored, and user-handler dispositions separately; implement signal-zero probes and target validation; apply the syscall return convention before saving the interrupted context for asynchronous delivery.

- [ ] **P64-7 — Medium — BUG — Fixed mremap silently ignores the requested destination for equal-size and shrinking moves**
  - **Where**: `src/os/syscalls_mm.c:729-755` (`syscall_mm_mremap`).
  - **What breaks / Why**: Equal-size requests return `old_addr` immediately. Shrinking requests unmap the source tail and also return `old_addr`. Both paths run before the `MREMAP_FIXED` destination is processed. A valid fixed relocation therefore reports success without moving the mapping.
  - **Fix**: Process fixed relocation independently of the size comparison. Restrict the current equal-size/shrink shortcuts to requests without `MREMAP_FIXED`.

- [ ] **P64-9 — Medium — BUG — mremap copies through guest read permissions**
  - **Where**: `src/os/syscalls_mm.c:687-707`, `src/os/syscalls_mm.c:767-789` (`syscall_mremap_transfer`, `syscall_mm_mremap`).
  - **What breaks / Why**: Relocation reads the source using `PPC64_ACCESS_LOAD`. A covered mapping with `PROT_NONE` or no read permission therefore fails with `EFAULT`, although moving a mapping must not require the guest to read its contents. The destination receives temporary write permission, but the source has no corresponding internal access mechanism.
  - **Fix**: Move VM backing and mapping metadata without guest-visible reads, or use a checked internal backing-copy operation independent of guest access permissions. Preserve backing identity and final protections.

- [ ] **P64-10 — Medium — BUG — nanosleep writes remaining time through the wrong argument**
  - **Where**: `src/os/syscalls_conv.c:734-758` (`x_nanosleep`).
  - **What breaks / Why**: On `EINTR`, the function reads and writes `args[2]` as the remainder pointer. `nanosleep(req, rem)` supplies that pointer in `args[1]`. Interrupted sleeps leave the requested remainder unwritten and can instead write through an unrelated third argument register.
  - **Fix**: Use `args[1]` for the optional remainder pointer and retain checked guest copyout.

### Low

No additional low-severity BUG/DEFECT findings.

## 2. Curated C11 & UB Issues

- [ ] **P64-11 — Medium — C11 — Narrow VM atomics perform unaligned and out-of-range 64-bit accesses**
  - **Where**: `src/vm/vm_atomic.c:180-216`, `src/vm/vm_atomic.c:225-241` (`vm_mem_atomic`).
  - **What breaks / Why**: Alignment is checked against the requested width, but the aligned path casts the host pointer to `uint64_t *` and executes eight-byte atomic loads/CAS even for one-, two-, and four-byte requests. A four-byte operation at page offset 4092 passes validation yet accesses eight bytes, crossing the validated page boundary and violating eight-byte alignment. This is a latent callback defect: the current interpreter reservation path bypasses it, as described in P64-1.
  - **Fix**: Dispatch to width-correct atomic operations with matching alignment and bounds. If using a containing-word CAS scheme, explicitly align and validate the complete containing word and preserve neighboring bytes.

- [ ] **P64-12 — Low — C11 — Image descriptor parsing uses banned atoi**
  - **Where**: `src/main.c:91-100` (`main`, `--image-fd` parsing).
  - **What breaks / Why**: `atoi` violates the requested curated subset. It accepts malformed input such as `"abc"` as descriptor zero, accepts numeric prefixes with trailing junk, and cannot report overflow reliably.
  - **Fix**: Use `strtol` with `errno`, end-pointer, and `0..INT_MAX` checks. Reject empty input and trailing characters.

## 3. DRY — Intra-Repo Duplication

- [ ] **P64-13 — Low — DRY — Syscall return convention is implemented independently in two runners**
  - **Where**: `src/run/core.c:52-82` (`run_is_scv`, `run_apply_sc`); `src/os/syscalls_p4.c:78-101` (`syscall_child_apply`).
  - **What breaks / Why**: Both paths refetch the trapping instruction, advance NIP, and implement `sc`/`scv` return and CR0.SO rules independently. Their instruction-validation behavior already differs: the child helper rejects unrecognized words, while the main runner treats any non-`scv` result as `sc`. Fixes to architectural return behavior must be maintained twice.
  - **Fix**: Introduce a small **repository-local** helper that takes the already-decoded syscall kind and applies the return state. Keep memory fetching and scheduling outside it.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **P64-14 — Low — YAGNI — Unused conditional-store API reports success without storing**
  - **Where**: `src/vm/vm_atomic.c:281-291` (`ppc64_vm_conditional`); `src/vm/vm.h:127-128` (public declaration).
  - **What breaks / Why**: The function checks reservation identity, clears it, ignores `val`, and returns true without performing a store or checking the reservation epoch. Repository symbol search found no production caller. It leaves a misleading public alternative to the atomic callback that could be mistaken for a complete store-conditional operation.
  - **Fix**: Remove the unused declaration and implementation, or rename and narrowly document it if a reservation-consumption-only operation is actually needed.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P64-15 — Low — CLEAN — Current specifications mix obsolete paths with unrelated ISA concepts**
  - **Where**: `SPEC.md:30-36`, `SPEC.md:78`, `SPEC.md:93`; `GOAL.md:36-43`.
  - **What breaks / Why**: Authoritative instructions still direct implementation to `src/rt64/`, which is absent from the current layout. They also require delay-slot/annul and register-window coverage for this PowerPC target. These requirements obscure the actual architecture and make completed phase checkboxes misleading as a description of current coverage.
  - **Fix**: Document the current `src/vm/`, `src/os/`, and `src/run/` ownership, retain migration history separately, and replace unrelated ISA requirements with concrete PowerPC branch, prefix, and precise-exception cases.

- [ ] **P64-16 — Low — CLEAN — Repository-wide line ceiling is not enforced by the source-only gate**
  - **Where**: `Makefile:52-60` (`check-line-limits`); `vendor/softfloat/source/include/primitives.h:901-1160`; `vendor/mbedtls/include/mbedtls/check_config.h:901-1149`; `vendor/mbedtls/library/sha256.c:901-983`.
  - **What breaks / Why**: The requested rule covers every `.c`/`.h`/`.S` file, but the gate scans only `src/`. The three vendored files exceed 900 lines. Production files also have little margin: `src/interp/interp.c` and `src/interp/decode.c` are exactly 900 lines, with `src/os/syscalls_conv.c` at 893 and `src/dbt/emit_int.c` at 888.
  - **Fix**: Make the rule and gate agree. Either explicitly document a vendored-source exception or extend the gate and split affected files while preserving upstream provenance. Split near-limit production files at coherent module boundaries when changing them.

The inspected fallback path does return to `ppc64_step` when translation declines (`src/dbt/dbt.c:775-780`). The targeted source scan found no textual `.c` unity includes or explicit assembly use of `x18`; this is not proof that every emitted instruction preserves it. FP corner cases, synchronous host-fault recovery, complete AOT validation, and concurrent cache safety remain unqualified by this bounded inspection.