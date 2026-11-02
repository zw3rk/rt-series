# mips64rt — Round 2 static audit

**HEAD:** `32d5c9e0d0b8c67a596d84d458536784e2109470`  
**Commit:** `Resolve M64-1..M64-18 audit defects and hygiene gates`

**Result: 10 findings, including an incomplete LL/SC remediation and concurrency hazards in quiescence and fork handling.**

The inventory contains **117 C/header/assembly files totaling 41,014 lines**, including tests and experiments. Source inspection focused on the changed interpreter, backend state, threading, memory, FP, and DBT paths, with additional inspection of syscall, signal-frame, build, and VM interfaces. `include/` and `tools/` were absent.

**Coverage limitation:** Seven batched shell inspection commands were issued. Some large outputs were truncated, and subsequent Git diff requests stalled in the macOS launcher. This report therefore does **not** certify exhaustive inspection of all 41,014 lines or complete verification of every remediation. No builds, tests, compilers, QEMU, or Docker commands were run. No repository files were changed.

Round-1 verification found the expected source changes for the write-only TLB addend, unsigned/masked MADD accumulation, DSRA32 handling, rounded FP-to-integer bounds, integer-to-FP inexact accounting, backend-state consolidation and release, worker engine selection, and arena reclamation bookkeeping. The line-count inventory found no source over 900 lines. These are static observations, not runtime validation. The LL/SC fix remains incomplete as described below.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 4 | 0 | 1 | 0 | 0 | 0 | 5 |
| Medium | 2 | 1 | 0 | 0 | 0 | 0 | 3 |
| Low | 0 | 0 | 0 | 1 | 0 | 1 | 2 |
| **Total** | **6** | **1** | **1** | **1** | **0** | **1** | **10** |

## 1. Bugs & Defects

### High

- [ ] **M64-R2-1 — High — BUG — Ordinary stores remain outside the LL/SC critical section**
  - **Where**: `src/os/mem.c:209-223`, `src/os/mem.c:302-329` (`guest_st8`, `guest_st32`); `src/interp/unaligned.c:370-377`, `src/interp/unaligned.c:442-479` (`mips_llsc_note_write`, `do_sc`).
  - **What breaks / Why**: The Round-1 fix locks reservation bookkeeping, but ordinary stores modify guest memory **before** calling the notification hook. SC holds `sc_lock` across its generation/value check and store; ordinary writers do not hold that lock while writing. Another thread can therefore modify the reserved word between SC’s comparison and commit, then wait for the lock to report its write. SC can incorrectly succeed and overwrite that intervening store. The new generation counters do not close this window.
  - **Fix**: Serialize the actual memory write and reservation invalidation with SC’s check-and-commit. Provide a shared write transaction covering scalar stores and other guest-memory writers, with explicit handling for writes already executing inside SC.

- [ ] **M64-R2-2 — High — BUG — Blocking syscalls can prevent every VM mutation from completing**
  - **Where**: `src/os/syscall_min.c:848-861` (`mips_syscall`); `src/os/quiesce.c:306-340` (`mips_qs_begin`); `src/os/quiesce.c:169-171` (`qs_preempt_handler`).
  - **What breaks / Why**: The syscall wrapper holds a memory lease across the entire syscall body, including potentially indefinite host waits. A VM mutator waits until every peer is parked with zero leases. Leased peers are deliberately excluded from preemption, and the preemption handler returns if a lease is active. A thread blocked in a read or wait can consequently prevent another thread’s `mmap`, `mprotect`, or `munmap` from completing indefinitely.
  - **Fix**: Separate guest-memory access from blocking host waits. Use staging buffers or explicit mapping pins where needed, release the quiescence lease before blocking, and reacquire and revalidate before guest-memory copyout.

- [ ] **M64-R2-3 — High — BUG — DBT compilation performs faulting speculative instruction fetches**
  - **Where**: `src/dbt/dbt.c:443-474` (`dbt_compile`); `src/interp/interp.c:794-810` (`exec_branch`).
  - **What breaks / Why**: Compilation calls the architectural `mips_fetch` on subsequent instructions and on a branch’s delay slot before executing the branch. When the delay-slot fetch fails, compilation merely removes the branch from the candidate block. Any fault or signal-delivery side effect of that fetch has already happened. In particular, a not-taken branch-likely at a page boundary must annul its inaccessible delay slot; the interpreter explicitly skips the fetch, while compilation attempts it unconditionally.
  - **Fix**: Use a side-effect-free fetch/probe for block construction. On an inaccessible speculative instruction or delay slot, end the block or fall back at the branch PC. Only execution should deliver the architectural fault.

- [ ] **M64-R2-4 — High — BUG — Fork inherits quiescence entries for threads that no longer exist**
  - **Where**: `src/os/syscall_min.c:429-439` (`sc_fork`); `src/os/quiesce.c:46-63`, `src/os/quiesce.c:314-337` (worker registry and mutation drain); `src/interp/unaligned.c:290-308` (`sc_lock`).
  - **What breaks / Why**: The fork child inherits the process-wide worker registry, including parent-process TIDs, pthread identities, and lease counts. Only the calling host thread survives. A later child VM mutation can wait forever for inherited peers that cannot park or release leases; preemption also uses the saved parent PID/TID. The newly introduced LL/SC spinlock can likewise be inherited as locked if another thread held it at fork. The inspected atfork registrations cover memory/file bookkeeping, not these registries and locks.
  - **Fix**: Add a coordinated fork lifecycle that stabilizes relevant state before fork and reconstructs child-only thread, quiescence, and reservation state afterward. Reset inherited locks safely and refresh the surviving thread’s PID/TID binding.

### Medium

- [ ] **M64-R2-5 — Medium — BUG — Double-precision FP emulation assumes wider long-double arithmetic**
  - **Where**: `src/interp/fp.c:202-223` (`fp_adj_d`); `src/interp/fp.c:395-396`, `src/interp/fp.c:417-447`, `src/interp/fp.c:469-473` (double arithmetic and exception accounting).
  - **What breaks / Why**: The interpreter treats `long double` calculations as an exact reference for rounding and inexact detection. Native Apple Silicon Darwin uses binary64 `long double`, so this reference can equal the already-rounded `double`. For example, adding `1.0` and `2^-54` under round-toward-positive must produce the next representable double; the comparison can instead see equality and leave `1.0` unchanged. Inexact flags are also lost. The Round-1 integer conversion fix avoids this assumption, but arithmetic still uses it.
  - **Fix**: Replace precision-dependent reference calculations with reliable rounding and exception handling on every supported host, using an established FP implementation or proven operation-specific residual calculations.

- [ ] **M64-R2-6 — Medium — BUG — Interpreter never raises underflow through its result-accounting helper**
  - **Where**: `src/interp/fp.c:176-187` (`fp_inexact`); `src/interp/fp_cvt.c:121-125` (`fp_cvt_sd`).
  - **What breaks / Why**: The helper explicitly omits underflow and raises only overflow and inexact. A tiny, inexact result—for example a sufficiently small finite double converted to single precision—therefore lacks the underflow cause/flag. With underflow enabled, the new enabled-exception mechanism cannot deliver SIGFPE because no underflow exception is recorded.
  - **Fix**: Implement tininess and inexactness accounting for narrowing and arithmetic according to the supported MIPS FP profile. Route underflow through `fp_raise` so enabled exceptions also suppress destination writeback.

- [ ] **M64-R2-7 — Medium — DEFECT — Instruction traps still collapse distinct signal codes to one**
  - **Where**: `src/os/sigframe.c:537-561` (`mips_trap`); `src/interp/interp.c:329-342` (trapping integer arithmetic); `src/interp/fp.c:161-170` (`fp_finish_trap`).
  - **What breaks / Why**: Round 1 corrected the signal number, but `mips_trap` assigns `si_code = 1` to every SIGFPE. Integer overflow and enabled FP invalid, overflow, underflow, and inexact exceptions consequently receive the same diagnostic code. Signal handlers cannot distinguish the actual architectural exception; code 1 denotes integer division rather than this collection of causes.
  - **Fix**: Carry an explicit exception kind and signal code from the instruction or FP exception source into signal-frame construction. Preserve the existing precise PC and delay-slot handling.

### Critical / Low

No additional confirmed findings at these severities in this category.

## 2. Curated C11 & UB Issues

- [ ] **M64-R2-8 — High — C11 — Quiescence slots are published before initialization**
  - **Where**: `src/os/quiesce.c:70-104` (`qs_slot_for`); `src/os/quiesce.c:163-165`, `src/os/quiesce.c:314-337` (registry readers); `src/os/quiesce.c:403-425` (`mips_qs_unregister`).
  - **What breaks / Why**: Slot creation changes atomic `used` from zero to one **before** initializing non-atomic `key`, `pthread`, `tid`, and `pid`. Other threads and the preemption handler treat nonzero `used` as a fully initialized slot and read those fields concurrently. Atomic publication cannot order writes that happen afterward. Unregistration similarly modifies `key` while the slot remains published. This creates C data races and can direct preemption at stale or uninitialized thread identifiers, preventing quiescence.
  - **Fix**: Distinguish FREE, INITIALIZING, and LIVE states. Initialize fields before release-publishing LIVE, and let readers acquire-observe only LIVE slots. Add a safe retirement/reuse protocol so readers cannot overlap teardown or reinitialization.

The inventory found no file exceeding 900 lines. The searches found no direct calls to the listed banned functions or textual `.c` includes in the searched production/test paths. This does not establish absence of all VLAs, UB, or numerically encoded `x18` use.

## 3. DRY — Intra-Repo Duplication

- [ ] **M64-R2-9 — Low — DRY — Pending signal queue insertion remains duplicated**
  - **Where**: `src/os/sigact.c:135-152` (`l4a_pend_enqueue`); `src/os/sigframe.c:130-146` (`l4b_pend_enqueue`).
  - **What breaks / Why**: Both implementations duplicate capacity checks, slot arithmetic, event-field writes, and count updates. The comments explicitly justify duplication by historical lane isolation. Changes to queue synchronization, overflow behavior, or event representation must now be applied consistently in two signal paths.
  - **Fix**: Move pending-queue operations into one separately compiled internal module within **mips64rt**, with a narrow header and explicit synchronization contract. Preserve the standalone repository boundary.

## 4. YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding was established with sufficient confidence within the inspection budget. The former write-only arena retention array now has a reclamation reader and should not be reported again as unchanged dead bookkeeping.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M64-R2-10 — Low — CLEAN — Arena lifetime comments contradict the reclamation implementation**
  - **Where**: `src/dbt/arena.c:15-18`, `src/dbt/arena.c:42-43`, `src/dbt/arena.c:58-73`; `src/dbt/dbt.c:131-134`, `src/dbt/dbt.c:150-151`.
  - **What breaks / Why**: Comments still promise that published mappings are never unmapped and remain valid until process exit, using the 1024-entry cache as the lifetime justification. The remediation now explicitly frees tracked mappings in `dbt_arena_reset`. These comments describe an obsolete pointer-lifetime guarantee precisely where maintainers need to understand reclamation safety.
  - **Fix**: Document the actual reclamation boundary, required cache/IBTC invalidation, thread ownership, and prohibition on retaining code pointers across reset. Remove the obsolete process-lifetime and cache-size justification.

**Validation status:** All findings are static source conclusions with line-numbered locations. No runtime reproduction or release qualification was performed.