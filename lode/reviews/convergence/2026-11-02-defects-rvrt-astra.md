# rvrt static audit

**HEAD:** `29ce5fd2813ece83849f5b5540eecd3ffdab3e70`

**Result:** 10 findings, including a high-severity JIT FP-state corruption defect.

Seven batched shell inspections were used. No builds, tests, compilers, QEMU, or Docker were intentionally invoked. The system Git wrapper unexpectedly emitted Xcode initialization/cache errors.

The inventory contains **1,107 `.c`/`.h`/`.S` files, totaling 228,702 lines**: 76,780 under `src`, 103,124 under `test`, and 48,798 under `vendor`. Detailed inspection concentrated on interpreter semantics, DBT/TLB/cache paths, backend operations, memory syscalls, ELF loading, and signal-frame restoration. Other modules received searches or inventory coverage only. **This is a bounded audit, not an exhaustive review of all 228,702 lines.** Findings are static deductions, not executed reproductions.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| Medium | 2 | 1 | 1 | 0 | 0 | 2 | 6 |
| Low | 0 | 0 | 1 | 1 | 1 | 0 | 3 |
| **Total** | **3** | **1** | **2** | **1** | **1** | **2** | **10** |

## 1. Bugs & Defects

### High

- [ ] **RV-1 — High — BUG — FP load miss loses previously dirty guest registers**
  - **Where**: `src/darwin_dbt.c:312-346`, `src/darwin_dbt.c:364-389` (`emit_inline_load`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: The TLB-miss branch precedes the FP-cache eviction spill. During emission, the fast path changes the slot’s guest-register identity and clears its dirty bit. The subsequently emitted miss-path flush therefore uses the *post-load* cache metadata, although execution skipped the fast-path spill. For example, an FP operation leaves `f0` dirty, then `fld f16,...` misses the TLB: both registers use slot zero, and the updated `f0` value is lost. A faulting load into the same dirty destination also loses the pre-fault architectural value, violating precise exceptions.
  - **Fix**: Preserve pre-instruction cache metadata when generating the miss path. Spill the old dirty slot before the split, or generate separate spills and reconcile metadata only after both paths. Add regressions for colliding destinations and faulting loads into a dirty destination.

### Medium

- [ ] **RV-2 — Medium — BUG — pthread failures can be reported as success**
  - **Where**: `src/os/backend_linux.c:274-279`, `src/os/backend_darwin.c:351-356` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:302-309` (`rt_host_preempt_worker`).
  - **What breaks / Why**: These branches discard the error returned directly by `pthread_create` or `pthread_kill` and return `-errno`. pthread functions do not provide their failure code through `errno`. With stale zero `errno`, failed worker creation returns success without setting `out_host_tid`; failed preemption can likewise appear successful. Searches found no production callers of these wrappers, so current exposure is limited to the backend API.
  - **Fix**: Capture the pthread return value and return its negation. Preserve it across cleanup. Exercise failures with `errno` initially zero and with an unrelated stale value.

- [ ] **RV-3 — Medium — DEFECT — Failed writable transitions leave code caches reusable**
  - **Where**: `src/dbt/cache.c:299-312` (`rv_dbt_invalidate`), `src/dbt/cache.c:82-85` (`rv_dbt_publish`); `src/os/backend_linux.c:153-160` (`rt_host_jit_begin_write`).
  - **What breaks / Why**: Cache invalidation ignores `mprotect(..., PROT_READ | PROT_WRITE)` failure and resets `used` to zero. The next publication performs `memcpy` into memory that may remain RX, causing a host fault. The Linux backend’s write-transition API similarly discards the failure and cannot tell its caller that writing is unsafe.
  - **Fix**: Make writable transitions report failure. Reset allocation state only after success, or retire the failed mapping and allocate a replacement. Propagate publication failure before any write.

- [ ] **RV-4 — Medium — BUG — TLB refill can pair an old read tag with a new host address**
  - **Where**: `src/darwin_dbt.c:102-125` (`tlb_fill_page`), `src/darwin_dbt.c:296-300` (`emit_tlb_lookup`).
  - **What breaks / Why**: Refilling a slot for a writable, unreadable page updates `addend` and `write_tag` but leaves `read_tag` untouched. If readable page A and write-only page B collide in the 4,096-entry table, a later read of A can match A’s retained tag while using B’s address translation. This is a **latent sparse-memory API defect**: ordinary Linux mappings normalize write permission to include read permission (`src/linux/memory.c:22-26`), so that syscall path does not establish reachability.
  - **Fix**: Invalidate both tags before replacing a slot’s addend, then install only the permitted tags. Test colliding pages through the sparse-memory API, including write-only permissions.

## 2. Curated C11 & UB Issues

- [ ] **RV-5 — Medium — C11 — File-offset reconstruction can overflow signed `off_t`**
  - **Where**: `src/os/backend_linux.c:66-77` (`rt_host_map_file`).
  - **What breaks / Why**: The expression `(off_t)(aligned_file_offset >> 12) * (off_t)4096` performs signed multiplication without checking that the supplied `uint64_t` offset fits `off_t`. On the target’s signed 64-bit `off_t`, an aligned offset of `0x8000000000000000` overflows during multiplication, invoking undefined behavior before `mmap` can reject it. The wrapper itself provides no range check; guest reachability was not established.
  - **Fix**: Validate alignment and representability in `off_t`, then cast the original checked offset directly. Return an explicit overflow or invalid-argument error.

- [ ] **RV-6 — Low — C11 — Test argument parsing uses prohibited `atoi`**
  - **Where**: `test/test_family_leave.c:90-92` (`notify_fd` parsing); `test/test_family_backing.c:39` (`pin_sender` / `pin_receiver` parsing).
  - **What breaks / Why**: `atoi` violates the requested subset, does not distinguish malformed input from zero, and provides no reliable overflow handling. Invalid harness input can consequently select an unintended descriptor.
  - **Fix**: Use checked `strtol` parsing with end-pointer, range, and descriptor validation. Reuse an intra-repository checked parser where appropriate.

## 3. DRY — Intra-Repo Duplication

- [ ] **RV-7 — Low — DRY — Worker startup protocol is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:233-300`, `src/os/backend_darwin.c:312-377` (`spawn_context_t`, `spawn_trampoline`, `rt_host_spawn_worker`).
  - **What breaks / Why**: Both backends independently implement the same context handoff, ready-pipe transfer, detach, read loop, cleanup, and result validation. The same pthread error-handling defect appears in both copies. Host-specific differences are principally pipe creation and obtaining the worker identifier.
  - **Fix**: Consolidate the protocol into a private module **inside rvrt**, retaining small host-specific hooks. Do not introduce a cross-repository library.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **RV-8 — Low — YAGNI — Return-address stack has no production consumer**
  - **Where**: `src/dbt/cache.c:223-240` (`rv_dbt_ras_push`, `rv_dbt_ras_pop`); `src/dbt/cache.h:83-84` (public declarations).
  - **What breaks / Why**: Repository searches found calls only in `test/u5b_dbt_cache.c`. The execution paths do not use this stack to predict or dispatch returns, yet the cache retains its API and lifecycle bookkeeping. Tests demonstrate the container operations, not an implemented runtime feature.
  - **Fix**: Remove or defer the unused mechanism until a concrete execution path needs it, or integrate it with explicit invalidation and fallback behavior.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **RV-9 — Medium — CLEAN — Tests extensively use prohibited textual implementation includes**
  - **Where**: `test/test_linux_memory_alloc.c:42-54` (allocator interception); `test/test_mm_remap.c:38-47`; `test/test_runtime_file_exec_codec.c:11`.
  - **What breaks / Why**: Tests textually include production `.c` files, sometimes several in one translation unit. The allocation test explicitly renames `valid_range` to avoid a collision between otherwise file-local helpers. Another test includes a test `.c` file. This violates the explicit no-unity-includes rule and makes test compilation depend on private implementation names and macro substitution.
  - **Fix**: Compile implementation files separately. Expose narrow private test seams or allocator interfaces where needed, and place shared test helpers in separately compiled modules.

- [ ] **RV-10 — Medium — CLEAN — Twenty-nine source files exceed the 900-line ceiling**
  - **Where**: `src/runtime_main.c:1-8201` (runtime orchestration), `src/runtime/family.c:1-4641` (family runtime), and the additional translation units listed below.
  - **What breaks / Why**: The inventory establishes **17 production files, nine test files, and three vendored files** above the mandatory ceiling. The largest production files combine enough responsibilities to make ownership and failure-path review substantially harder.
  - **Fix**: Split first-party files along existing ownership boundaries, keeping separately compiled translation units and private headers. For vendored files, resolve the literal policy conflict explicitly rather than silently exempting them or casually rewriting upstream code.

  | Area | Files and line counts |
  |---|---|
  | Production | `runtime_main.c` 8,201; `runtime/family.c` 4,641; `runtime/guest_memory.c` 2,574; `runtime/native_signal.c` 1,894; `runtime/file_caps.c` 1,851; `linux/file.c` 1,531; `memory/file_backing.c` 1,518; `memory/space.c` 1,484; `runtime/mm_view.c` 1,372; `linux/fd.c` 1,338; `runtime/scheduler.c` 1,100; `darwin_dbt.c` 1,061; `runtime/family_file_recovery.c` 988; `runtime/exec_state.c` 982; `linux/futex.c` 978; `runtime/process_children.c` 938; `linux/signal.c` 909 — all under `src/` |
  | Tests | `test_linux_file.c` 1,426; `r6_inherited_children.c` 1,304; `test_family_file_attributed.c` 1,293; `r5_exec.c` 1,212; `test_linux_file_workers.c` 1,133; `test_file_caps.c` 1,022; `test_family_file_recovery.c` 984; `test_family.c` 970; `test_linux_signal.c` 954 — all under `test/` |
  | Vendored | `vendor/softfloat/source/include/primitives.h` 1,160; `vendor/mbedtls/include/mbedtls/check_config.h` 1,149; `vendor/mbedtls/library/sha256.c` 983 |

The root Makefile includes the requested C11 warning flags at lines 449–450. Searches found no explicit x18/w18 instruction use in the inspected source. These observations do not establish complete C11 compliance or generated-register safety. Full signal multiplexing, concurrent cache lifecycle, managed-family memory, syscall coverage, and vendor internals remain insufficiently reviewed to make correctness claims.