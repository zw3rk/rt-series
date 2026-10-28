The audit found correctness defects that should be fixed before treating either translator or the benchmark results as qualified. The most serious involve malformed ELF bounds, MIPS DBT instruction buffering, Soft-TLB invalidation, thread coordination, and FP semantics.

This was read-only. I audited `mips64rt` at `99e1e8c`, `sparc64rt` at `e6e5c84`, and `rt-series` at `49a46fd`, including the existing uncommitted benchmark-harness changes. `tools/catalogue_harness.sh` does not exist; I audited its apparent equivalent, `tools/run_catalogue.sh`.

| Dimension | Assessment |
|---|---|
| CLEAN | No inventoried C/header/assembly file exceeds 1,000 lines. Several approach 900 lines and contain 200–450-line functions. Textual inclusion and compressed formatting weaken the file-size discipline. |
| DRY | Significant duplication in backend policy, A64 encoders, decoding, syscall returns, FP primitives, and harness dispatch/parsing. Some duplicated implementations already share defects. |
| YAGNI | Confirmed unused encoder APIs, obsolete syscall handlers, write-only fields, RAS scaffolding, and production-linked abstractions used only by tests. |
| Curated C11 | Strict compilation passes much of the code, but source inspection found UB, a prohibited `strcpy`, and a Darwin warning suppression. |
| Architecture | Material gaps in cache invalidation, quiescence, blocking operations, signal ownership, and interpreter/DBT FP parity. No explicit x18 register violation was found. |

**High-priority checklist**

Each item below defines a bounded worker scope. Correctness findings are source-established unless a runtime reproduction is explicitly identified.

1. **MIPS loader — reject overflowing ELF extents.**  
   [loader.c:432](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:432) adds the load bias and rounds `p_memsz` without checking intermediate overflow. The original length reaches `memset` at line 488. For example, `p_memsz=UINT64_MAX`, page offset 2, and `p_filesz=0` produce a 4,096-byte mapping followed by an enormous clear.  
   **Action:** check every extent addition, rounding operation, and file offset before mapping. Add malformed-ELF rejection tests.

2. **MIPS DBT — reserve space for the branch delay slot.**  
   [dbt.c:443](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:443) allows instruction 64 into a 64-element array, then writes its delay slot through `insns[64]` at line 465. `--difftest` uses shorter blocks and misses this boundary.  
   **Action:** terminate before the branch or reserve another element. Test branch positions 63/64 and page boundaries under ASan using normal DBT execution.

3. **MIPS DBT — correct J/JAL target construction.**  
   [emit_int.c:216](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_int.c:216) clears `0xFFFFFF` instead of `0xFFFFFFF`, retaining incorrect PC bits. PC `0x12000000` with target field zero yields `0x12000000` instead of `0x10000000`.  
   **Action:** use a named, correct region mask and test jumps between 16 MiB subregions within one 256 MiB region.

4. **MIPS Soft-TLB — preserve the address addend for write-only pages.**  
   [backend_linux.c:251](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_linux.c:251) and [backend_darwin.c:254](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_darwin.c:254) set `addend=0` when read permission is absent, then independently install a valid write tag. Integer and FP stores consume that addend.  
   **Action:** derive the host-address addend independently of permissions. Test repeated stores into `PROT_WRITE`-only mappings on both backends.

5. **MIPS worker registry — fix capacity, publication, and retirement.**  
   [threads.c:80](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:80) permits 128 threads, but [quiesce.c:44](/Users/angerman/Projects/zw3rk/mips64rt/src/os/quiesce.c:44) protects only 16. Exhaustion silently bypasses protection. At line 89, `used` becomes visible before non-atomic metadata is initialized. Backend registrations also lack matching retirement.  
   **Action:** make registration checked and mandatory, publish initialized entries safely, and unify registry lifetimes. Test more than 16 concurrent workers and repeated create/exit cycles.

6. **MIPS fork — reinitialize child synchronization state.**  
   Fork paths at [syscall_min.c:422](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:422) and [threads.c:329](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:329) inherit registry entries for vanished threads. Quiescence subsequently waits on copied peer states and can signal saved parent PID/TID bindings.  
   **Action:** reset child worker bindings, counts, locks, and leases through an explicit fork-child protocol. Test multithreaded fork followed by child mapping changes.

7. **Both translators — repair blocking-I/O ownership.**  
   MIPS holds a memory lease across blocking calls at [syscalls_sync.c:308](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_sync.c:308), including scalar and vectored I/O. SPARC holds its guest execution lock across [syscalls_min.c:199](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:199). A reader can prevent the peer operation needed to unblock it.  
   **Action:** introduce safe release/reacquire protocols with pinned or staged buffers. Test two-thread pipe operations, including a peer that maps memory before writing. Simply unlocking around a raw guest pointer is unsafe.

8. **SPARC futex/quiescence — pin backing and wait for acknowledgments.**  
   [threads.c:397](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.c:397) resolves a raw futex pointer, releases the lock, and waits without retaining its backing. Separately, [vm64.c:539](/Users/angerman/Projects/zw3rk/sparc64rt/src/vm/vm64.c:539) signals peers but never waits for their parking acknowledgments or drains leases.  
   **Action:** implement retained futex keys and acknowledged quiescence before relaxing execution serialization. Test concurrent wait/unmap/remap and interrupted waits. Darwin’s active futex path currently returns `ENOSYS`.

9. **SPARC memory — invalidate Soft-TLB entries before shrinking `brk`.**  
   [guest_run.c:204](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:204) releases heap backing but only invalidates translated blocks. Existing Soft-TLB entries retain host pointers.  
   **Action:** route `brk` changes through the mapping transaction/invalidation path. Prime a heap TLB entry, shrink the heap, then verify that accessing the old page faults.

10. **Both translators — close SMC invalidation gaps.**  
    SPARC writes at [guest_run_mem.c:63](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_mem.c:63) do not retire translated code; `FLUSH` is a no-op at [interp.c:578](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:578). MIPS `uname` copyout at [syscall_min.c:389](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:389) bypasses code retirement.  
    **Action:** centralize successful-write completion, covering stores, atomics, and syscall copyouts. Add rewrite-and-execute tests without an intervening `mprotect`; SPARC’s current SMC fixture relies on protection changes.

11. **SPARC DBT — invalidate every thread’s cache.**  
    [guest_engines.c:289](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_engines.c:289) creates per-thread DBTs, while mapping mutations such as [guest_run_sysmem.c:474](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run_sysmem.c:474) invalidate only the current instance. Resumed peers do not consume the recorded DBT epoch.  
    **Action:** check an address-space generation on every resume or invalidate all registered DBTs. Test a sleeping peer whose cached code is rewritten, unmapped, or made non-executable.

12. **SPARC JIT — propagate publication failure.**  
    [dbt.c:228](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.c:228) returns `void`; failed RX protection merely returns, while callers at lines 676 and 818 proceed into the code.  
    **Action:** return and check publication status, then fall back or report an internal error. Inject a protection failure to verify that unpublished code is never entered.

13. **MIPS native FP — repair comparison guards and FCSR accounting.**  
    [emit_fp.c:558](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:558) emits CBNZ with the opposite sense from its NaN-fallback comment: unordered comparisons remain native. Arithmetic and conversion paths at [emit_fp.c:340](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:340) commit results without the interpreter’s exception-flag/cause updates.  
    **Action:** correct the guard and implement precise FCSR handling or appropriate fallback. Assert both values and FCSR for signaling/quiet NaNs, inexact results, overflow, narrowing conversions, and COP1X operations.

14. **MIPS reference FP — fix rounding and admitted NaN modes.**  
    [fp.c:176](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:176) assumes `long double` supplies a wider reference; native Darwin has only 53-bit precision. Directed `ADD.D(1.0, 2^-54)` therefore has a concrete wrong-result case. [fp_ps.c:202](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:202) ignores COP1X rounding mode. [loader.c:350](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:350) admits NaN2008 ELFs without configuring or rejecting that mode.  
    **Action:** implement host-independent FP semantics, honor COP1X rounding, and initialize or explicitly reject unsupported ELF FP modes. Preserve frozen CPU-layout offsets.

15. **Both interpreters — remove demonstrated C undefined behavior.**  
    [fp_cvt.c:79](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:79) checks the unrounded value but casts the rounded value: `CEIL.W.D(2147483647.25)` reaches an out-of-range integer cast. SPARC shifts negative branch displacements at [interp.c:94](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:94), duplicated in [decode.c:215](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:215), and shifts negative dividends at [interp_win.c:525](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:525).  
    **Action:** check rounded conversion bounds, multiply bounded signed displacements, and assemble dividend bits unsigned. Add UBSan boundary cases.

16. **Both signal implementations — separate shared and per-thread state.**  
    MIPS copies dispositions into each thread and updates only the caller at [sigact.c:271](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:271); its exec reset at line 482 erases ignored dispositions, masks, and pending signals. SPARC stores masks, pending state, and alternate stacks globally at [sync_sig.c:74](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/sync_sig.c:74).  
    **Action:** share process dispositions, retain per-thread masks/altstacks/pending ownership, and implement required exec preservation. Test cross-thread handler changes and distinct thread masks.

17. **MIPS syscall ABI — correct errno and clock-sleep translation.**  
    [syscall_min.c:159](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:159) remaps only literal error 38; Darwin’s `ENOSYS=78` consequently leaks into the guest instead of MIPS 89. At line 658, `clock_nanosleep` flags are passed as the request pointer. [syscalls_time.c:113](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_time.c:113) also discards flags and mishandles the function’s direct error return.  
    **Action:** centralize symbolic errno translation and add a dedicated clock-sleep adapter covering flags, all four arguments, time widths, and interruption.

18. **MIPS ordering — implement SYNC semantics.**  
    [emit_alu.c:112](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_alu.c:112) and [interp.c:189](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:189) treat SYNC as a no-op; emitted atomics use ordinary LDXR/STXR.  
    **Action:** supply the required host barriers and validate supported SYNC variants with bounded ordering litmus tests. The missing implementation is confirmed; no runtime ordering failure was reproduced.

19. **Benchmark harness — make PASS depend on successful execution and correct selection.**  
    [bench_harness.sh:320](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:320) suppresses exit statuses and accepts an `ALL_PASS` substring. A mocked process exiting 137 after printing that marker was reported as PASS with exit status 0. QEMU failures become SKIP at line 398. Engine selection is omitted for several paths, including `hl` at line 345, despite printing `$ENGINE`.  
    **Action:** preserve exit status, validate complete result records, distinguish unavailable from failed targets, and centralize actual engine selection. Add harness-level failure/timeout/engine-selection tests.

**Medium-priority checklist**

| Scope | Exact starting points | Remediation |
|---|---|---|
| MIPS backend duplication | [backend_linux.c:28](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_linux.c:28), [backend_darwin.c:31](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_darwin.c:31) | Extract shared registry/TLB policy inside this repository. Keep OS operations separate. The write-only defect is duplicated here. |
| MIPS duplicate A64 APIs | [a64_emit.c:17](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/a64_emit.c:17), [emit_enc.c:33](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_enc.c:33) | Of 65 public `a64e_*` definitions, 64 have no caller in another production C file. Consolidate encoders and move encoding tests onto the implementation production uses. |
| SPARC duplicate decoders | [interp.c:68](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:68), [decode.c:528](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:528) | Adopt one decoding representation. Preserve independent execution/oracle tests rather than duplicate production decoding tables. |
| SPARC repeated primitives | [fp_quad.c:33](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:33), [fp_qdiv.c:26](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:26), [guest_interp_map.c:66](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_interp_map.c:66) | Consolidate two-word FP helpers and checked ELF readers; preserve intentional loading-policy differences. |
| SPARC dormant backend | [backend.h:1](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend.h:1), [backend_darwin.c:768](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_darwin.c:768) | Only five of 91 `rt_host_*` names have non-backend source references. Audit required seams before wiring them: dormant worker trampolines publish readiness before copying their stack-owned arguments. Remove obsolete wrappers afterward. |
| MIPS family-contract gap | [family_broker.c:36](/Users/angerman/Projects/zw3rk/mips64rt/src/os/family_broker.c:36), [worker_loop.c:159](/Users/angerman/Projects/zw3rk/mips64rt/src/os/worker_loop.c:159) | Directory creation does not implement the specified family-memory, SCM broker, scheduling, and safe-syscall substrate. Record the missing behavior explicitly and qualify it through real execution paths. |
| MIPS JIT lifetime | [arena.c:67](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/arena.c:67) | New chunks accumulate without reclamation. The 1,024-entry cache does not bound arena retention. Add safe generation retirement or a hard allocation limit with fallback. |
| MIPS startup entropy | [loader.c:245](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:245) | Replace time/PID-seeded xorshift for production `AT_RANDOM` with host entropy. Keep deterministic behavior confined to the explicit test knob. |
| Module boundaries | [syscalls.c:32](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:32), [mem_recover.c:34](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:34) | Compile `proc.c` independently instead of textual inclusion, which creates a roughly 1,364-line combined unit. Move weak correctness-disabling stubs into test-only files. |
| C11/build discipline | [host_contract_identity.c:142](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/host_contract_identity.c:142), [fp_sd.c:347](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:347), [emit_fp.c:784](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:784) | Guard Linux-only helpers instead of suppressing warnings; resolve the portable-C claim around `__uint128_t`; move exported-function NULL checks before dereferences. |
| Benchmark reproducibility | [bench_harness.sh:147](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:147), [bench_harness.sh:245](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:245) | Existing executables bypass rebuilding after source/flag changes. Fallback recipes also differ from fast-path recipes. Track source/compiler/flags and use one recipe per target. |
| Harness lifecycle | [bench_harness.sh:225](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:225), [remote_bench.sh:99](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench.sh:99) | Fix the EXIT trap’s reference to function-local `cname`; it becomes unbound after return. Add cleanup verification and bounded execution to remote runs and fast-path builds. |
| Harness duplication/coverage | [bench_harness.sh:56](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:56), [remote_bench.sh:15](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench.sh:15), [run_catalogue.sh:287](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:287) | Share architecture metadata, engine adapters, and result parsing. Add RV32 to the local matrix; reject invalid filters and zero selected tests. Both silent-zero-work cases were reproduced. |
| Benchmark validity | [bench_suite.c:35](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:35), [bench_suite.c:491](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:491) | Propagate clock failures instead of turning zero timestamps into a 1 µs result. Make sorting affect an order-sensitive checksum: summing sorted values cannot detect incorrect sorting. |

These refactors should remain repository-local. They do not justify a shared cross-repository runtime library.

**Low-priority cleanup**

- **Remove verified dead scaffolding:** MIPS’s old futex/signal-mask implementations at [syscalls_sync.c:78](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_sync.c:78), write-only RAS state at [dbt.c:631](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:631), and obsolete `ef_fhalf` at [emit_fp.c:126](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:126). SPARC equivalents include unused `sparc64_fetch_decode` at [decode.c:579](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:579), old signal handling at [syscalls_ext.c:836](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:836), and write-only DBT fields at [dbt.h:69](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/dbt.h:69).

- **Split monster functions by responsibility:** MIPS `exec_special` at [interp.c:127](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:127) is roughly 448 lines; `fp_arith` at [fp.c:276](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:276) roughly 332; syscall dispatch at [syscall_min.c:508](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:508) roughly 330. SPARC’s ALU executor at [interp_win.c:442](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:442) is roughly 290. Extract semantic families and transaction phases.

- **Enforce the actual file policy:** [test_p1_isa.c:901](/Users/angerman/Projects/zw3rk/mips64rt/tests/test_p1_isa.c:901) reaches 902 lines, exceeding the local 900-line rule. The gate excludes tests. Expand compressed control flow rather than using formatting to stay below the limit.

- **Correct prohibited functions and naming:** [guest_proc.c:109](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_proc.c:109) uses `strcpy`. Existing bounds checks prevent a demonstrated overflow, but the function violates the rules. Replace it with checked formatting. Replace historical `l2a_`/`l4b_`/`u0_` names as affected modules are refactored. Change [run_catalogue.sh:206](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:206) to initialize `master`.

- **Repair misleading comments:** [host_compat.h:8](/Users/angerman/Projects/zw3rk/mips64rt/src/os/host_compat.h:8) says Darwin execution is unsupported; [fp.c:12](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:12) describes implemented FP behavior as absent; [sync_sig.c:72](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/sync_sig.c:72) describes single-threaded state. The benchmark header promises a report file it never writes and states a different default load threshold.

**Specific answer about `-O2` MIPS FP loops**

Yes: normal optimized loops can expose the DBT block-boundary overflow, COP1 comparison/FCSR defects, and COP1X rounding defects above. This audit did **not** establish the cause of a particular observed benchmark failure.

Guarded FP arithmetic in a delay slot is deliberately declined, and the emitter rejects the whole block for interpretation. I found no evidence that this fallback alone corrupts delay-slot execution.

The current guest parity recipe uses `-O1` at [parity_suite.sh:148](/Users/angerman/Projects/zw3rk/mips64rt/tests/parity_suite.sh:148). Difftest also changes block formation and disables chaining. Add an `-O2` suite running **normal DBT against QEMU**, covering loop-carried FP dependencies, overlapping FPR operands, COP1X, FP-memory delay slots, branch-likely annulment, and exact FCSR results. Ensure the harness actually rebuilds the guest.

**Validation and limits**

- Both `check-line-limits` targets passed using direct toolchain executables.
- MIPS audited translation units passed strict Darwin syntax checks with `-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror`.
- All 56 SPARC C translation units passed strict AArch64 Linux syntax checks.
- Strict SPARC Darwin checking failed on unused `fs_name`; the repository’s `-Wno-error=unused-function` converts that failure into a warning.
- `bench_suite.c` passed hosted and MIPS32/RV32 freestanding syntax checks. Shell syntax checks passed.
- Source inspection found no explicit x18/w18 use or active guest-data executable mappings. JIT publication and cache-coherence defects remain as listed.
- No new builds, QEMU runs, sanitizers, concurrency tests, or performance measurements were performed. The proposed regression cases are validation work for the repair lanes, not claimed passing evidence.