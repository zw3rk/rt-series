# ppc32rt — read-only static audit

**HEAD:** `3582753e2cf68f235bb62c40b335ac678cda154f`

**Source inventory:** 65 `.c`, `.h`, and `.S` files under `src/` and `include/`, totaling **24,132 physical lines**. Inspected specifications, interpreter/decoder, DBT emitters and cache, VM/loader, syscall/thread/signal paths, host backends, AOT code, and build declarations.

**Result:** 15 findings. No Critical finding established.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 6 | 0 | 1 | 0 | 0 | 0 | 7 |
| Medium | 2 | 1 | 1 | 0 | 0 | 0 | 4 |
| Low | 0 | 0 | 0 | 1 | 1 | 2 | 4 |
| **Total** | **8** | **1** | **2** | **1** | **1** | **2** | **15** |

Seven batched shell inspections were used. No builds, compilers, QEMU, Docker, or tests were intentionally run; no files were changed. Git’s macOS launcher emitted cache-permission diagnostics before returning HEAD. Findings are static conclusions, not reproduced failures. Large output batches were partially truncated, so this is **not an exhaustive line-by-line clearance of every module**, particularly FP/SPE, signal-frame restoration, and cache concurrency.

## 1. Bugs & Defects

### High

- [ ] **P32-1 — High — BUG — Overflow-enabled arithmetic instructions fail decoding**
  - **Where**: `src/interp/decode.c:325-335`, `src/interp/decode.c:444-446`, `src/interp/decode.c:559-561` (`ppc_decode`)
  - **What breaks / Why**: The decoder extracts a ten-bit XO containing OE and switches on that complete value. Arithmetic cases contain only their OE=0 values. For example, `addo` produces XO 778 rather than the handled 266 and falls through to UNDEF. The interpreter’s and emitter’s overflow handlers therefore cannot execute through normal decoding. Both engines share this defect, so differential agreement does not detect it.
  - **Fix**: Decode XO-form arithmetic using its nine-bit opcode and separate OE bit, while preserving full ten-bit matching for X-form instructions. Add explicit OE=0/OE=1 encoding checks for every arithmetic family.

- [ ] **P32-2 — High — BUG — DBT traps combine predicates incorrectly**
  - **Where**: `src/dbt/emit_int.c:541-579` (`ei_trap`)
  - **What breaks / Why**: Each enabled TO predicate emits a branch that skips the trap when that predicate is false. Consequently, all selected predicates must hold; PowerPC traps when **any** selected predicate holds. For TO=24, signed less-than and greater-than cannot both hold, so unequal operands fail to trap. The signed-less-than check also uses `PL`, which ignores overflow, instead of the signed comparison condition.
  - **Fix**: Branch to a shared trap exit on each satisfied predicate, then fall through when none match. Use `LT`/`GT` for signed comparisons and `CC`/`HI` for unsigned comparisons.

- [ ] **P32-3 — High — BUG — Memory barriers are discarded**
  - **Where**: `src/interp/decode.c:519-521`, `src/interp/decode.c:540-545` (`ppc_decode`); `src/interp/interp.c:844-848` (`interp_step`); `src/dbt/emit_int.c:856-858` (`ppc32_emit_int`)
  - **What breaks / Why**: `sync` and `eieio` reach `PPC32_OP_SYNC`, which both engines treat as a no-op. Ordinary translated loads and stores do not thereby acquire the ordering required by guest synchronization protocols on AArch64. Cache hints and memory-ordering instructions cannot safely share a blanket no-op implementation.
  - **Fix**: Preserve the relevant barrier distinction during decoding. Emit appropriate AArch64 barriers, using a conservative full barrier initially, and implement corresponding ordering in the interpreter.

- [ ] **P32-4 — High — BUG — Atomic accesses bypass A2 guest permissions**
  - **Where**: `src/interp/interp.c:796-815` (`interp_step`, LWARX/STWCX); `src/interp/interp.c:36-47` (`vm32_sc_attempt`); `src/dbt/emit_int.c:605-611`, `src/dbt/emit_int.c:642-659` (`ei_lwarx`, `ei_stwcx`)
  - **What breaks / Why**: Atomic paths form direct guest-window pointers and perform host atomics instead of using the checked page-access path. On A2, host permissions are the union of multiple guest subpages. A guest read-only or inaccessible 4 KiB page can therefore remain host-accessible because of a writable neighbor. These atomic operations can bypass guest permissions and write-side COW bookkeeping.
  - **Fix**: Validate the guest page’s read/write permissions and backing state before the atomic operation. Route A2 atomics through a checked helper initially, keeping mapping validation and the atomic access protected against concurrent remapping.

- [ ] **P32-5 — High — BUG — mremap replaces file backing with anonymous memory**
  - **Where**: `src/rt32/ppc32_vm.c:678-679`, `src/rt32/ppc32_vm.c:701-706`, `src/rt32/ppc32_vm.c:740-765` (`ppc32_vm_mremap`)
  - **What breaks / Why**: Both extension and relocation force `PPC32_MAP_ANONYMOUS`. Relocation copies bytes into a new anonymous mapping and removes the original. A moved `MAP_SHARED` file mapping consequently loses file/alias coherence; growing a file mapping adds anonymous zero-filled pages instead of the corresponding file extent and EOF behavior. Preserving region flags does not preserve backing.
  - **Fix**: Preserve backing identity, file offset, sharing, and COW state during remapping. Use a host remap operation where applicable or implement backing-aware relocation. Reject unsupported cases before mutating mappings.

- [ ] **P32-6 — High — BUG — Invalid futex timeout pointers can crash the translator**
  - **Where**: `src/os/threads.c:52-85` (`thread_range_ok`, `thread_ld32be`); `src/os/threads.c:274-284` (`futex_get_timeout`); `src/main.c:437-448` (`ppc32_run_guest_child`)
  - **What breaks / Why**: `thread_range_ok` checks address bounds only. `futex_get_timeout` then reads guest memory with `memcpy`. An in-range unmapped or `PROT_NONE` timeout pointer passes validation and faults in host C code. Syscall dispatch occurs after the engine’s host-fault wrapper returns, so this is not converted into syscall `-EFAULT`. A2 also permits reads through overly permissive host-page unions.
  - **Fix**: Copy timeout structures through a permission-aware, fault-safe guest-copy API. Validate every covered guest page and return `-EFAULT` without dereferencing inaccessible backing.

### Medium

- [ ] **P32-7 — Medium — BUG — neg corrupts XER.CA in both engines**
  - **Where**: `src/interp/interp.c:246-257` (`interp_step`, NEG); `src/dbt/emit_int.c:166-170` (`ei_addsub_xo`)
  - **What breaks / Why**: Both implementations set carry to `(operand == 0)`. PowerPC `neg` preserves XER.CA. A carry-dependent arithmetic sequence containing `neg` therefore computes the wrong result. Because both engines repeat the same mistake, difftest can still agree.
  - **Fix**: Remove the carry update from NEG in both engines. Check preservation with incoming CA=0 and CA=1 for zero and nonzero operands.

- [ ] **P32-8 — Medium — BUG — Futex requeue count is passed in the wrong argument**
  - **Where**: `src/os/threads.c:255-264` (`futex_host`); `src/os/threads.c:341-346` (`ppc32_futex`)
  - **What breaks / Why**: Linux interprets futex argument four as the requeue count for REQUEUE/CMP_REQUEUE. Both branches pass `NULL` in that position, making the count zero. REQUEUE instead forwards `val3` in argument six, where it cannot supply the missing count. CMP_REQUEUE correctly byte-swaps its comparison operand but still requests no requeues.
  - **Fix**: Forward the guest fourth argument as the integer requeue count. Give the host wrapper an argument representation that distinguishes a WAIT timeout pointer from a REQUEUE count.

- [ ] **P32-9 — Medium — DEFECT — pthread failures are reported using unrelated errno**
  - **Where**: `src/os/backend_linux.c:605-609`, `src/os/backend_darwin.c:801-805` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:399-407` (`rt_host_preempt_worker`)
  - **What breaks / Why**: `pthread_create` and `pthread_kill` return their error number directly. These wrappers discard that result and return `-errno`. If errno is zero or stale, failure can become apparent success or the wrong error. The spawn wrappers can report success without producing a worker.
  - **Fix**: Save the pthread return value and return its negation. Keep output parameters unset on failure.

## 2. Curated C11 & UB Issues

- [ ] **P32-10 — High — C11 — Reservation metadata has unsynchronized shared accesses**
  - **Where**: `src/interp/interp.c:24-26`, `src/interp/interp.c:43-51`, `src/interp/interp.c:804-806` (`g_ll_table`, `vm32_sc_attempt`, LWARX)
  - **What breaks / Why**: `owner`, `addr`, `val`, `snap`, and `gensnap` are shared ordinary fields. Concurrent interpreter contexts accessing the same hashed reservation slot read and write them without a lock. Atomic epoch operations do not make these other accesses race-free or publish a coherent reservation record. This is C data-race UB when those contexts execute concurrently.
  - **Fix**: Keep reservation snapshots per context and synchronize shared reservation-line state. Make reservation validation and the conditional store a coherent protocol; independently atomizing each field is insufficient.

- [ ] **P32-11 — Medium — C11 — Signed offset construction left-shifts negative values**
  - **Where**: `src/os/syscalls.c:710-712` (`ppc32_syscall`, PREAD64)
  - **What breaks / Why**: `((int64_t)(int32_t)a3 << 32)` left-shifts a negative signed value when the offset’s high word has its sign bit set. That is undefined behavior in C11. Even an invalid negative guest offset must reach deterministic syscall validation rather than invoke host UB.
  - **Fix**: Assemble the bit pattern using `uint64_t`, then convert it to the intended signed value with an explicit, well-defined conversion strategy.

The repository-wide textual scan found no banned `sprintf`/`strcpy`/`strcat`/`atoi` calls or textual `.c` includes in the scanned source files. Matches for literal `x18`/`w18` were comments; this does **not** certify every hand-encoded instruction word.

## 3. DRY — Intra-Repo Duplication

- [ ] **P32-12 — Low — DRY — Worker-spawn plumbing is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:575-615`, `src/os/backend_darwin.c:771-811` (`spawn_slot_t`, `spawn_tramp`, `rt_host_spawn_worker`)
  - **What breaks / Why**: Both backends repeat allocation, trampoline cleanup, pthread creation, detach, and handle publication. The same incorrect pthread error handling appears in both copies, demonstrating maintenance drift risk in otherwise platform-neutral code.
  - **Fix**: Move the common pthread worker implementation into an internal module **within ppc32rt**, leaving genuinely host-specific handle operations in each backend. Preserve the standalone repository boundary.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **P32-13 — Low — YAGNI — Signal installation API is unwired scaffolding that reports success**
  - **Where**: `src/os/backend_darwin.c:875-890` (`rt_host_install_signal_handlers`)
  - **What breaks / Why**: The function discards all three supplied callbacks, installs `SIG_IGN` for the proposed preemption signal, and returns success. Source-reference inspection found no production caller for this API; active fault handling uses `hostfault.c`. Its interface promises functionality the implementation does not provide.
  - **Fix**: Remove or explicitly mark the API unsupported until needed. If retained for integration, wire the callbacks and preemption behavior before returning success.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **P32-14 — Low — CLEAN — Core files have effectively exhausted the line budget**
  - **Where**: `src/interp/interp.c:1-900` (`interp_step` and helpers); `src/interp/fp.h:1-899`; `src/os/syscalls.c:1-898`; `src/os/backend_darwin.c:1-895`
  - **What breaks / Why**: These files have zero, one, two, and five lines of remaining capacity respectively. They comply today, but even small corrective patches risk breaching the mandatory 900-line ceiling or encouraging compressed, harder-to-review code.
  - **Fix**: Split coherent internal units as affected fixes land—for example reservation handling, FP conversion helpers, or syscall families. Avoid textual unity includes and preserve independent compilation.

- [ ] **P32-15 — Low — CLEAN — Execution comments contradict current behavior**
  - **Where**: `src/interp/interp.h:38-42` (`interp_step` contract); `src/interp/interp.c:837-843` (SC implementation); `src/dbt/dbt.c:17-21`, `src/dbt/dbt.c:44-45` (emitter documentation)
  - **What breaks / Why**: The interpreter header says SC advances NIP, while the implementation deliberately leaves NIP at SC for syscall dispatch. DBT documentation still describes native emission as a future lane and the fallback emitter as temporary. These comments misstate the current control-flow contract and can cause double advancement or incorrect maintenance decisions.
  - **Fix**: Document the actual stopped-at-SC convention and describe fallback as the current configurable fallback path. Remove completed-phase predictions from active API documentation.