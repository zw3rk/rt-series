# mips64rt — Static Audit Report

**HEAD:** `8d5950cd631fe2efa5d138c4bdf60f3280e8867a`

**Source inventory:** 73 `.c`/`.h`/`.S` files under `src/`, totaling **27,657 physical lines**. Repository-wide counting, excluding `.git` and `_build`, found **40,891 lines** in those extensions.

Seven batched shell inspections covered source inventory, targeted interpreter/DBT/backend/runtime paths, loader arithmetic, signals, atomics, build declarations, and test hygiene. **18 findings** are reported below. This was a bounded static audit, not an exhaustive line-by-line verification of every module; some large inspection outputs were truncated. Findings include only locations visible in the inspected source.

No files were edited. No make targets, compilers, QEMU, Docker, or tests were intentionally executed. The system Git launcher itself emitted Xcode/cache initialization diagnostics.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 6 | 0 | 2 | 0 | 0 | 0 | 8 |
| Medium | 3 | 3 | 0 | 0 | 0 | 1 | 7 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **9** | **3** | **2** | **1** | **1** | **2** | **18** |

## 1. Bugs & Defects

### High

- [ ] **M64-1 — High — BUG — ELF segment rounding can wrap before bounds validation**
  - **Where**: `src/loader.c:432-444`, `src/loader.c:467-488` (`PT_LOAD` mapping and initialization).
  - **What breaks / Why**: `bias + ph.vaddr` and `ph.memsz + page_off + 4095` are evaluated before overflow checks. The later check validates the already-wrapped mapping length, while file copying and zeroing still use the original sizes. For example, `memsz = 2^64 - 2048`, `page_off = 4095`, and `filesz = 0` produce a rounded mapping length of 4096, followed by an enormous `memset`. A malformed ELF can therefore cause host memory access outside the admitted mapping.
  - **Fix**: Validate bias addition and the complete unrounded segment extent using subtraction-based bounds checks. Check alignment addition separately, and prove both copy and zero-fill spans fit the mapped region before obtaining `dst`.

- [ ] **M64-2 — High — BUG — Write-only TLB entries use a zero host-address addend**
  - **Where**: `src/os/backend_linux.c:251-264`, `src/os/backend_darwin.c:254-267` (`mips_soft_tlb_fill`); `src/dbt/emit_mem.c:193-202` (`ei_probe_open`).
  - **What breaks / Why**: When a page lacks guest read permission, the fill sets `addend = 0`. It can independently publish a valid `write_tag` for the same page. The DBT store probe loads that tag together with the zero addend, causing a successful fast-path store to address the raw guest VA instead of `guest_base + VA`. This can crash the translator or target an unrelated host mapping. `mips_mem_ok` checks requested permissions literally, so write-only guest mappings reach this case.
  - **Fix**: Populate the host addend whenever either access tag is valid. Keep read and write permission tags independent from address translation.

- [ ] **M64-3 — High — BUG — LL/SC implements value comparison instead of reservation invalidation**
  - **Where**: `src/interp/unaligned.c:269-284`, `src/interp/unaligned.c:305-337`, `src/interp/unaligned.c:342-389` (`do_ll`, `do_sc`, `do_lld`, `do_scd`).
  - **What breaks / Why**: SC succeeds when the current value equals `llval`; intervening writes are not tracked. A second thread can change a word from A to B and back to A, after which SC incorrectly succeeds. The SC lock only serializes SC implementations: ordinary guest stores do not participate in this lock, so they can also intervene between the comparison and store. The comment declaring foreign same-value writes benign is incorrect for reservation semantics.
  - **Fix**: Track reservation generations for the chosen reservation granule and invalidate them on every relevant write. Make the generation check and SC commit indivisible relative to other writers, including DBT stores and shared backing updates.

- [ ] **M64-4 — High — BUG — Instruction exceptions are delivered as SIGSEGV**
  - **Where**: `src/interp/interp.c:22-31` (`fault_at`), `src/interp/interp.c:188-189` (`BREAK`), `src/interp/interp.c:282-295` (overflow), `src/interp/interp.c:381-382` (unrecognized instruction); `src/os/mem.c:69-85` (`mips_fault`).
  - **What breaks / Why**: `fault_at` routes instruction exceptions through `mips_fault`, which always calls `mips_trap(ctx, 11, addr)`. BREAK, integer overflow, and invalid instructions therefore enter the memory-fault path instead of delivering their appropriate SIGTRAP, SIGFPE, or SIGILL exceptions. Programs handling these signals receive the wrong signal and diagnostic information.
  - **Fix**: Separate instruction exceptions from memory faults. Pass an explicit exception kind and signal code through interpreter and DBT exits, preserving delay-slot PC semantics.

- [ ] **M64-5 — High — BUG — Sign-extended LO corrupts MADD/MSUB accumulation**
  - **Where**: `src/interp/interp.c:395-428` (`exec_special2`); `src/dbt/emit_alu.c:414-419` (`ei_special2`).
  - **What breaks / Why**: The interpreter constructs HI:LO using `(hi << 32) | lo` without masking LO to 32 bits. LO is normally sign-extended, so a negative low word overwrites the entire high half. With HI=0 and LO=`0xffffffff80000000`, adding a zero product should preserve HI=0; the interpreter instead produces HI=-1. The DBT explicitly clears LO’s upper half, creating an engine divergence.
  - **Fix**: Assemble the accumulator as `((uint64_t)(uint32_t)hi << 32) | (uint32_t)lo` in all four accumulate/subtract operations.

- [ ] **M64-6 — High — BUG — Thread-directed signals reject valid worker TIDs**
  - **Where**: `src/os/sigact.c:676-699` (`l4a_tkill`); `src/os/threads.c:180-199`, `src/os/threads.c:312-322` (worker TID publication).
  - **What breaks / Why**: Clone publishes the worker’s host TID, but `tkill`/`tgkill` accepts a target only when `tid == getpid()`. On Linux, worker TIDs differ from the process leader’s PID. Valid signals to guest pthreads—including a worker signaling itself—therefore return ESRCH. Successful delivery also targets the caller through `l4a_raise_self`, rather than resolving the requested thread.
  - **Fix**: Resolve target TIDs through the live guest-thread registry, validate thread-group membership, and queue/wake the target context.

### Medium

- [ ] **M64-7 — Medium — BUG — Backend context slots are never released**
  - **Where**: `src/os/backend_linux.c:28-39`, `src/os/backend_linux.c:82-109`, `src/os/backend_linux.c:124-141`; `src/os/backend_darwin.c:31-42`, `src/os/backend_darwin.c:85-112`; `src/os/threads.c:424-437` (`u0_slot_for`, `mips_fixade_ctl`, `mips_thread_exit`).
  - **What breaks / Why**: Each backend has only 16 slots, permanently keyed by context address. Thread exit frees the context without releasing its backend slot. Once exhausted, setters silently do nothing while `mips_fixade_ctl` reports success. Reused context addresses can inherit stale state. This conflicts with the thread layer’s 128-live-thread capacity.
  - **Fix**: Add explicit context registration and destruction, release slots before freeing contexts, initialize reused state, and propagate allocation failure. Size or allocate backend state consistently with supported concurrency.

- [ ] **M64-8 — Medium — BUG — A valid DSRA32 encoding is treated as a breakpoint**
  - **Where**: `src/interp/interp.c:375-379` (`exec_special`); `src/dbt/emit_alu.c:382-392` (`ei_special`).
  - **What breaks / Why**: SPECIAL function `0x3f` with zero operand fields is `DSRA32 $zero,$zero,0`, a harmless operation. Both engines special-case it as SDBBP and fault. SDBBP belongs to SPECIAL2; the DBT already handles it separately at `src/dbt/emit_alu.c:463-468`.
  - **Fix**: Remove the breakpoint special case from SPECIAL/DSRA32 and retain SDBBP decoding exclusively under SPECIAL2.

- [ ] **M64-9 — Medium — DEFECT — Interpreter FP exception enables are ignored**
  - **Where**: `src/interp/fp.c:135-144` (`fp_raise`).
  - **What breaks / Why**: `fp_raise` unconditionally sets cause and sticky bits without checking FCSR exception enables or delivering a trap. Its comment explicitly defers traps until Phase 4, although signal support is present. Enabled FP exceptions therefore continue execution instead of entering the guest SIGFPE handler.
  - **Fix**: Implement enabled-exception delivery and instruction completion rules, including suppressing destination writeback where required. Route the result through the normal precise-exception path.

- [ ] **M64-10 — Medium — BUG — Integer-to-FP conversions omit inexact exceptions**
  - **Where**: `src/interp/fp_cvt.c:170-204` (`fp_cvt_wl`).
  - **What breaks / Why**: CVT.S.W, CVT.S.L, and CVT.D.L write rounded results and return without recording inexactness. For example, converting integer 16,777,217 to single precision loses information but leaves the FCSR inexact cause/flag unset.
  - **Fix**: Detect discarded integer bits and update FP exception state for each conversion. Use a method that remains exact on Darwin, where `long double` does not provide extra precision over `double`.

- [ ] **M64-11 — Medium — DEFECT — Code-arena allocation grows without reclamation**
  - **Where**: `src/dbt/arena.c:7-18`, `src/dbt/arena.c:42-80` (`arena_retain`, `dbt_arena_alloc`).
  - **What breaks / Why**: Every exhausted chunk creates another mapping, and mappings are never reclaimed. The 64-entry retention array does not cap allocation. The comment’s 1024-entry cache bound limits live cache entries, not cumulative code publication: cache churn or repeated SMC can allocate indefinitely.
  - **Fix**: Introduce a bounded arena lifecycle. At a safe dispatcher boundary, invalidate affected block/IBTC references and reclaim obsolete generations. Track mapping sizes for reclamation and enforce an explicit allocation budget.

- [ ] **M64-12 — Medium — DEFECT — Cloned threads always run the interpreter**
  - **Where**: `src/os/threads.c:170-205` (`l4b_entry`).
  - **What breaks / Why**: Worker startup unconditionally invokes `interp_run(child)`, regardless of the selected engine. A `--dbt` workload therefore executes pthread bodies in the interpreter. Threaded parity runs cannot establish DBT correctness for those worker bodies.
  - **Fix**: Dispatch worker execution using the selected engine through a common runtime entry point. Preserve thread registration, signal handling, and teardown around both engines.

## 2. Curated C11 & UB Issues

- [ ] **M64-13 — High — C11 — FP conversion validates the source instead of the rounded result**
  - **Where**: `src/interp/fp_cvt.c:67-84` (`fp_to_int`).
  - **What breaks / Why**: Bounds checks examine `q`, but casts consume rounded `t`. For `CEIL.W.D` with `q = 2147483647.5`, the source passes `q < 2^31`, while `t` becomes 2147483648. Casting that value to `int32_t` is undefined behavior. The lower-bound check also rejects some inputs whose rounded result is representable.
  - **Fix**: Validate the rounded value against the destination’s exact representable interval before casting. Handle NaN/infinity separately and generate the architectural invalid-conversion result when the rounded value is out of range.

- [ ] **M64-14 — High — C11 — Signed MADD/MSUB accumulation can overflow**
  - **Where**: `src/interp/interp.c:396-401`, `src/interp/interp.c:415-420` (`exec_special2`).
  - **What breaks / Why**: Signed `int64_t` accumulation uses `+=` and `-=` even though the guest operation wraps modulo 64 bits. For example, accumulator `0x7fffffff00000000` plus signed product `INT32_MIN * INT32_MIN` overflows `int64_t`. This is UB independently of the LO-masking defect.
  - **Fix**: Keep the accumulator unsigned. Compute the signed 32×32 product in `int64_t`, where it fits, convert its representation to `uint64_t`, and perform unsigned addition/subtraction before extracting HI and LO.

## 3. DRY — Intra-Repo Duplication

- [ ] **M64-15 — Low — DRY — Linux and Darwin duplicate the backend state registry**
  - **Where**: `src/os/backend_linux.c:28-328`; `src/os/backend_darwin.c:31-331` (`u0_slot_for`, FIXADE state, delay targets, soft-TLB management).
  - **What breaks / Why**: Approximately 300 lines of host-independent state management are duplicated, including locking, allocation, permission tags, and invalidation. The write-only addend defect and slot-lifetime defect exist in both copies, illustrating the maintenance risk.
  - **Fix**: Move the common implementation into a normal, separately compiled module **inside mips64rt**. Keep host page/JIT operations in the platform backends. Preserve the standalone repository boundary.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **M64-16 — Low — YAGNI — Arena retention array is write-only bookkeeping**
  - **Where**: `src/dbt/arena.c:42-57`, `src/dbt/arena.c:74` (`arena_maps`, `arena_nmaps`, `arena_retain`).
  - **What breaks / Why**: `arena_maps` receives pointers but has no read/reclamation path anywhere in `src/`. Keeping a pointer in this array does not keep an mmap alive; mappings remain allocated until explicitly unmapped. After 64 entries, even this bookkeeping silently stops.
  - **Fix**: Replace it with the actual bounded ownership/reclamation structure from M64-11, including sizes, or remove the unused array if lifetime retention remains an explicit temporary policy.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **M64-17 — Medium — CLEAN — Production and test code use textual C unity includes**
  - **Where**: `src/os/syscalls.c:32-36`; `tests/check_host_contract.c:37-43` (`#include "*.c"`).
  - **What breaks / Why**: Production textually includes `os/proc.c`; the host-contract test includes seven implementation files. This directly violates the requested build discipline, hides declaration boundaries, and makes test translation units differ from normal separately compiled units. The production justification that the Makefile is “frozen” is a historical workflow constraint embedded in current architecture.
  - **Fix**: Declare the required interfaces in headers and compile each implementation separately. Update production and test source lists; expose narrow test interfaces where necessary.

- [ ] **M64-18 — Low — CLEAN — A test exceeds 900 lines and the gate excludes tests**
  - **Where**: `tests/test_p1_isa.c:1-902`; `Makefile:215-222` (`check-line-limits`).
  - **What breaks / Why**: `test_p1_isa.c` contains 902 lines. The gate searches only `src`, so it cannot enforce the requested repository-wide ceiling. Production files are within the limit, but several have little room: `mem_table.c` 899, `interp.c` 897, `syscalls.c` 896, and `emit_mem.c` 895.
  - **Fix**: Split the ISA tests by coherent instruction groups and extend the gate to maintained test/experiment sources, with explicit exclusions for generated or vendored files.

The inspected Makefile contains the required C11 warning flags, and `CLAUDE.md` correctly links to `AGENTS.md`. The searches found no direct calls to the listed banned string functions in `src/`; inspected trampoline code did not use `x18`. These observations do not establish full UB freedom, complete emitter register safety, or correctness of the unreviewed VM, signal-frame, and syscall paths.