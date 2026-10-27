**RC-U12-mips64-r3: remediation remains incomplete at `21e0f25` on `master`.** The following dispositions preserve the previous review’s numbering. Remaining blockers are based on source inspection; I did not reproduce them in Docker.

1. **FAIL — Memory-site recovery still leaves merge stores exposed.** The new instruction markers and requested branch decoders are present. However, `ei_unaligned` marks the initial load, while the eventual merge store occurs later. Preemption between those accesses falls outside the rewind interval. A concurrent `MAP_FIXED` can therefore replace the mapping before execution resumes and stores bytes merged from the old mapping. See [emit_mem.c:519](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:519), [emit_mem.c:551](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:551), and [mem_recover.c:557](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:557). **P1.**

2. **FAIL — Concurrent mutating syscalls can deadlock.** `mips_syscall` holds a lease throughout dispatch, but `mips_qs_begin` acquires `qs_mu` without first dropping that lease and parking. If two leased workers enter mutations, A can hold `qs_mu` while waiting for B’s lease; B blocks on that mutex and cannot reach lease exit. Skipping leased workers during preemption makes this permanent. This violates Rev 4 §4.5’s explicit first step. See [syscall_min.c:841](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:841) and [quiesce.c:282](/Users/angerman/Projects/zw3rk/mips64rt/src/os/quiesce.c:282). **P1.**

3. **FAIL — Mapping lifecycle and rollback remain incomplete.** Pre-staging file contents fixes the previous invalid-fd/failed-`pread` replacement case. However, the new unmap hook does not split an interior removal. Map three pages of file A, replace the middle with file B, then write A’s middle page: A’s stale mapping record can refresh B’s clean page with A’s bytes. See [vm_file.c:574](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:574).

   Separately, `mremap` commits the destination before the final source unmap. If that host operation fails, it returns an error with the destination already replaced; temporary `mprotect` errors are also ignored. See [mem_table.c:675](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem_table.c:675) and [mem_table.c:701](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem_table.c:701). **P1.**

4. **FAIL — Provider A still loses required file semantics.** Beyond-EOF revocation remains inside `shared || COW_CLEAN`, so wholly removed dirty private pages remain accessible and survive shrink/regrow. See [vm_file.c:761](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:761).

   Syscall copyout only clears `COW_CLEAN`; neither `guest_range(write=1)` nor `mips_sc_read` performs shared write-through. DBT recovery also installs a writable TLB entry before the interpreter store; subsequently re-marking `COW_CLEAN` does not invalidate that entry, allowing later stores to bypass synchronization. See [syscalls.c:160](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:160), [syscalls_sync.c:306](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_sync.c:306), [mem_recover.c:470](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:470), and [vm_file.c:625](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:625).

   PID filtering also excludes inherited parent-owned mapping records after fork, without child registration or reconciliation. Shared metadata alone still does not establish family mapping coherence. **P1.**

5. **FAIL — Loaded AOT sites do not participate in live recovery.** The loader now has a production caller, but loaded records only suppress duplicate cache appends. Every block is re-emitted, and its live site table comes from fresh `ei_mem_take_sites` output. Thus the missing-caller edit does not satisfy the Rev 4 cold/warm recovery requirement. See [dbt.c:233](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:233), [dbt.c:463](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:463), and [dbt.c:498](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/dbt.c:498). **P1.**

6. **PASS on inspection — Reported Darwin defects are corrected.** JIT writes use `(0)` and sealing uses `(1)`. Futex slot lookup, initialization, and publication are protected by `l4f_dslots_mu`. See [backend_darwin.c:410](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_darwin.c:410) and [futex.c:107](/Users/angerman/Projects/zw3rk/mips64rt/src/os/futex.c:107).

7. **PARTIAL — Interpreter FIXADE is repaired; DBT delay-slot FIXADE remains wrong.** The redundant decoder checks are removed, and the fault fixture disables FIXADE. But recovery handles misalignment before inspecting the delay-slot flag. A taken branch with a misaligned `LW` in its slot executes that load and resumes at fall-through, bypassing branch-target restoration. See [mem_recover.c:413](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:413). **P1.**

8. **PARTIAL — Register checking and the exit predicate improve, but verification remains incomplete.** `R` checkpoints are emitted and compared, and the final predicate rejects both GAP and SKIP. However, the register hash omits all 32 FPRs. The parity suite exercises P1 and H1/H4, without invoking `--difftest` or completing the previously required matrix. Consequently, `pass=10 fail=0 skip=0 gap=0` does not establish full register or stage-gate parity. See [mem.c:379](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem.c:379) and [parity_suite.sh:204](/Users/angerman/Projects/zw3rk/mips64rt/tests/parity_suite.sh:204).

I reviewed the authoritative sibling [UNIFICATION-PLAN.md, Rev 4](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md); no local copy exists. `CLAUDE.md` correctly links to `AGENTS.md`, and all 70 source files meet the 900-line limit.

Validation performed:

- `./_build/test_u0_fill_retry`: **28 passed, 0 failed**.
- `sh -n tests/parity_suite.sh`: **passed**.
- `check-line-limits`, using the direct Command Line Tools `make` and compiler paths: **passed**.
- Other requested host binaries encountered temporary-file/cache creation failures under the read-only sandbox; those results are **inconclusive**.
- Accepted your supplied build/parity results for this commit; no heavy containers rerun and no files changed.

**Verdict: FAIL**