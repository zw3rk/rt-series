# sparc64rt — Read-only static audit

**HEAD:** `71fe7a506ef4e542930fab01b31a563d84537750`

**Inventory:** 105 C/header/assembly files, **36,298 lines** under `src/` and `include/`; **44,672 lines** including `tests/` and `experiments/`.

**Result:** 14 findings: **3 High, 9 Medium, 2 Low**. No Critical finding established.

Seven shell inspection commands were used, including one rejected heredoc invocation. No builds, compilers, QEMU, Docker, or tests were intentionally run; macOS tool discovery emitted sandbox errors during Git/Python startup. No repository files were changed.

Coverage comprised repository-wide inventory and pattern searches, with focused source inspection of decoding, CPU initialization, DBT dispatch/publication, memory fast paths, VM validation, signal handling, syscall boundaries, and backends. This is **not exhaustive semantic verification of all 36,298 lines**. Several Darwin backend functions have no production callers found under `src/`; their findings concern implemented interface behavior, not demonstrated failures in the current guest execution path.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 2 | 0 | 1 | 0 | 0 | 0 | 3 |
| Medium | 1 | 6 | 1 | 1 | 0 | 0 | 9 |
| Low | 0 | 0 | 0 | 0 | 1 | 1 | 2 |
| **Total** | **3** | **6** | **2** | **1** | **1** | **1** | **14** |

## 1. Bugs & Defects

### High

- [ ] **S64-1 — High — BUG — CPU initialization leaves half the FP register file unchanged**
  - **Where**: `src/core/cpu.h:137-141,202-218` (`sparc64_ctx_init`); `src/os/guest_run.c:450-465,549-550,683-688` (initial execution and exec reset).
  - **What breaks / Why**: The FP union occupies 256 bytes, but initialization clears only `f[32]`, or 128 bytes. Consequently, `d[16..31]` remains uninitialized in the stack-allocated initial context and retains old-image state when the context is reused for exec. Extended FP register reads can expose indeterminate or previous-image values.
  - **Fix**: Initialize all 32 double-register storage elements, or clear the entire FP union. Check both initial launch and exec reset.

- [ ] **S64-2 — High — BUG — Failed RX publication does not prevent JIT execution**
  - **Where**: `src/dbt/dbt.c:228-242` (`dbt_publish`), `src/dbt/dbt.c:820-824` (`sparc64_dbt_run`).
  - **What breaks / Why**: `dbt_publish` silently returns when `a32h_wx_publish` fails. Its caller nevertheless enters `b->host_code`. A failed permission transition can therefore lead directly to execution of non-executable staging memory instead of a controlled translator error or interpreter fallback.
  - **Fix**: Return publication status and require successful publication before entering any fragment. Preserve an explicit failure state and propagate an internal error or safely fall back.

### Medium

- [ ] **S64-3 — Medium — BUG — Floating-condition MOVcc encodings become no-op barriers**
  - **Where**: `src/interp/interp.c:239-257` (`sparc64_decode_op2`); `src/dbt/emit_int.c:596-598` (`sparc64_emit_int`).
  - **What breaks / Why**: For MOVcc, bit 18 clear selects the floating-condition-code form. The execution classifier instead labels it `SPARC64_ICLS_MEMBAR`, with a comment claiming MEMBAR shares this opcode. The DBT then emits nothing. Such a conditional integer move cannot update its destination correctly. The separate decoder rejects this form instead, adding inconsistent behavior.
  - **Fix**: Decode the floating-condition MOVcc form explicitly and evaluate its selected FCC. Keep MEMBAR recognition under its RDASR encoding. Add raw-encoding cases for both integer and floating condition selectors.

- [ ] **S64-4 — Medium — DEFECT — Darwin socket wrappers omit address-layout conversion**
  - **Where**: `src/os/backend_darwin.c:529-535,543-567` (`rt_host_bind`, `rt_host_connect`, address-returning socket wrappers).
  - **What breaks / Why**: Buffers explicitly identified as Linux socket addresses are cast directly to Darwin `struct sockaddr`. Darwin’s leading length/family bytes differ from Linux’s family field; family values also require translation for some domains. Incoming addresses can be rejected or misinterpreted, while returned addresses have the wrong interface representation. No current production callers of `rt_host_bind` were found.
  - **Fix**: Convert supported Linux address structures into bounded Darwin structures and convert output addresses back, including lengths and family values. Reject unsupported families explicitly.

- [ ] **S64-5 — Medium — DEFECT — Darwin futex implementation discards essential semantics**
  - **Where**: `src/os/backend_darwin.c:684-716` (`rt_host_futex_wait_bitset`, `rt_host_futex_wake_bitset`, `rt_host_futex_requeue`).
  - **What breaks / Why**: Waiting ignores the futex key and bitset. Waking ignores the requested count and bitset and always requests wake-all. Requeue ignores the destination, requeue count, and comparison value, then performs a wake. Thus even wake-count zero can wake waiters, and compare-requeue can report success without comparing or moving any waiter. No production requeue caller was found.
  - **Fix**: Implement a keyed waiter abstraction that preserves counts, masks, comparison, and requeue behavior. Until implemented, return an explicit unsupported-operation error for operations whose contract cannot be met.

- [ ] **S64-6 — Medium — DEFECT — Darwin no-replace mapping can overwrite an existing mapping**
  - **Where**: `src/os/backend_darwin.c:202-213` (`rt_host_map_anon`).
  - **What breaks / Why**: The no-replace implementation probes with `mincore` and then uses `MAP_FIXED`. Another thread can establish a mapping between the probe and replacement. Furthermore, `fixed && noreplace` bypasses the probe entirely. The implementation can replace memory despite the caller requesting no replacement. No production caller was found.
  - **Fix**: Use an atomic platform reservation mechanism or fail closed when atomic no-replace behavior cannot be provided. Never implement this contract through an unchecked `MAP_FIXED` operation.

- [ ] **S64-7 — Medium — DEFECT — Darwin copy fallback loses partial-write accounting**
  - **Where**: `src/os/backend_darwin.c:373-390` (`darwin_copy_loop`).
  - **What breaks / Why**: `done` and `in_off` advance only after an entire read chunk has been written. If one write transfers bytes and a subsequent write fails, the function reports only previously completed chunks—or an error despite having written data—and leaves the input offset behind the bytes actually transferred. Retrying can duplicate output.
  - **Fix**: Account for each successful write immediately. On failure, return the complete transferred-byte count and advance explicit offsets by exactly that amount.

- [ ] **S64-8 — Medium — DEFECT — Darwin ppoll drops signal-mask and empty-set waiting behavior**
  - **Where**: `src/os/backend_darwin.c:578-593` (`rt_host_ppoll`).
  - **What breaks / Why**: `linux_sigmask` is explicitly discarded, so the temporary atomic signal-mask contract is absent. With no descriptors and no wake descriptor, the function returns immediately regardless of the supplied timeout. A caller using polling as a timed or signal-driven wait receives incorrect behavior. No production caller was found.
  - **Fix**: Implement the temporary-mask wait protocol and preserve timeout behavior for an empty descriptor set. Reject unsupported mask behavior rather than silently ignoring it.

- [ ] **S64-9 — Medium — DEFECT — VM validation helpers admit wrapped and out-of-range spans**
  - **Where**: `src/vm/vm64.c:125-127,161-177,182-204,210-225` (`vm64_align_up_8k`, VM argument validators).
  - **What breaks / Why**: Validation subtracts `base` or `addr` from `VM64_TASK_SIZE` without first rejecting values above that limit. The unsigned subtraction wraps and can admit an out-of-range address. Alignment also adds the page mask without checking overflow: `vm64_check_mprotect_args(8192, UINT64_MAX, ...)` rounds the size to zero and can return success. These are helper-contract defects; current syscall reachability was not established.
  - **Fix**: Check the address against `TASK_SIZE` first, validate the unrounded length using subtraction, and perform checked rounding. Reject overflow before calculating endpoints.

### Critical / Low

No additional findings established at these severities in this category.

## 2. Curated C11 & UB Issues

- [ ] **S64-10 — Medium — C11 — Backward branch decoding left-shifts negative signed values**
  - **Where**: `src/interp/interp.c:94,109,116,131,149` (`sparc64_classify_word`); `src/interp/decode.c:215,230,247,256,564` (parallel decoder).
  - **What breaks / Why**: Sign extension produces a negative signed value for backward displacements, then the decoder shifts that value left by two. Left-shifting a negative signed integer is undefined behavior in C11. This affects routine backward branches and calls in both decoder implementations.
  - **Fix**: Multiply the sign-extended displacement by four in a sufficiently wide signed type; these displacement widths fit in `int64_t`. Alternatively, shift the unsigned encoded field before sign-extending the enlarged width.

- [ ] **S64-11 — High — C11 — Darwin worker startup reads a parent stack object after its lifetime**
  - **Where**: `src/os/backend_darwin.c:763-786` (`worker_tramp`, `rt_host_spawn_worker`).
  - **What breaks / Why**: The child publishes `ready` and unlocks the startup mutex before copying `st->fn` and `st->arg`. The parent can observe readiness, destroy synchronization objects, and return, ending the lifetime of stack-local `st`. The child then reads function and argument fields from expired stack storage, potentially calling a corrupted pointer.
  - **Fix**: Copy every child-required field before publishing readiness. After unlocking, the child must never access `st` again; alternatively, transfer ownership of a heap-allocated startup record.

## 3. DRY — Intra-Repo Duplication

- [ ] **S64-12 — Medium — DRY — Two instruction decoders have already diverged**
  - **Where**: `src/interp/interp.c:68-170,239-257` (`sparc64_classify_word`); `src/interp/decode.c:200-258,316-327,528-577` (`sparc64_decode_word`); `src/dbt/difftest.c:224-227` (consumer).
  - **What breaks / Why**: The repository maintains two raw-word decoders with separate decoded structures and opcode rules. Their MOVcc classification already differs: the execution classifier returns MEMBAR for bit 18 clear, while the other returns ILLEGAL. Difftest consumes the second decoder, so its instruction metadata can drift from execution semantics.
  - **Fix**: Consolidate raw encoding classification within this repository, using adapters where callers need different metadata. Preserve independent semantic/oracle checks; do not introduce a cross-repository library.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **S64-13 — Low — YAGNI — VM syscall validators are disconnected from production callers**
  - **Where**: `src/vm/vm64.c:182-204,210-242` (`vm64_check_munmap_args`, `vm64_check_mremap_args`).
  - **What breaks / Why**: Symbol searches under `src/` found definitions but no production calls for these validators. Their comments present guest-visible validation behavior, but these functions cannot enforce that behavior on the actual syscall path. Maintaining disconnected validation duplicates policy and can create false confidence.
  - **Fix**: Connect the helpers to the actual syscall path if they are intended to own validation. Otherwise remove them or clearly restrict them to an explicitly named experimental/test interface.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **S64-14 — Low — CLEAN — Core implementation files have almost no size headroom**
  - **Where**: `src/interp/interp.c:1-900`; `src/os/syscalls_ext.c:1-894`; `src/dbt/dbt.c:1-892`; `src/interp/fp_sd.c:1-889`.
  - **What breaks / Why**: These files satisfy the 900-line limit, but one is exactly at the ceiling and three are within eleven lines. Small correctness fixes or explanatory comments will exceed the limit, encouraging compressed code or arbitrary splits.
  - **Fix**: When addressing nearby defects, extract coherent internal units—such as raw decoding or JIT arena publication—into ordinary separately compiled files. Do not use textual `.c` inclusion.

**Static checks:** No source file exceeded 900 lines. Searches found no textual `.c` includes, banned string calls in `src/` or `include/`, `<threads.h>`, or `_Generic`. Banned string names occurred in the libc string-test fixture; they were not treated as production safety defects. Textual `x18` matches were comments, but this does not prove that all numeric instruction encodings avoid the register.

**Unverified limits:** FP arithmetic/rounding, complete signal-frame restoration, atomic ordering, register-cache recovery, concurrent cache recycling, AOT validation, and 16 KiB host sub-page behavior remain unqualified by this bounded static audit. No runtime or test-pass claims are made.