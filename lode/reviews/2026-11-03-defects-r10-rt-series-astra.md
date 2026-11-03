# Round-10 Deep-Dive 4 Static Audit — Threading / `clone` / `fork` / `execve` / `atfork` / `tgkill` / Futex

Read-only audit. No files modified, no builds or tests run.

## Verdict

**0 defects found.** Subsystem has converged. No `BUG` / `DEFECT` to report.

## Defects

| ID | File:Line | Description | Fix |
|----|-----------|-------------|-----|
| — | — | No concrete behavioral bug or direct specification contradiction found in scope. | — |

## Coverage checked

| Area | Evidence | Result |
|------|----------|--------|
| `t_atomic_race` race / leak | [p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c) `755-787`: `iters` written before `pthread_create`, read-only in worker; joined at `778`; `_Atomic long` `fetch_add` exact `2*200000` check | No UB, race, or leak. |
| `t_vm_fork_cow` COW / leak | [p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c) `844-868`: `MAP_PRIVATE` + `fork` + child-only `_exit` + parent `waitpid` + both-path `munmap`; `_exit` avoids stdio flush duplication | COW isolation correct, no leak. |
| LL/SC reservation clearing | [p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c) `176-199` and [p3_llsc.h](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_llsc.h) `40-52`, `57-140`, `144-175`: single-thread `raise(SIGURG)` between LL/SC, `sig_atomic_t` flag only, saved/restored `SIGURG` disposition, initialized outputs, correct per-arch success predicates | No UB or race. |
| TLS registers | [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md) `31-41` vs [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md) `267-288`, `319`, `405`, `444`: `ULR`/`rdhwr $29`, PPC32 `r2`, LA64 `r2`, PPC64 `r13` all match; no conflicting TLS assignment elsewhere | Consistent. |
| `clone` order `ptid` / `tls` / `ctid` | [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md) `51`: `clone(flags, newsp, ptid, tls, ctid)` matches Linux raw order; [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md) `622`: `rt_host_tgkill(tgid, tid, sig)` correct; no competing order in `SPEC.md` | Consistent. |
| `tgkill` 6-step quiescence | [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md) `337-350`, `341-342`, `753`: park-self before `g_vm_mutation_lock`, `SIGRTMIN+1` via `tgkill` / `SIGUSR2` via `pthread_kill`, PC-rewind, host-op-before-commit, `<512`-page selective invalidate, release + wake; `SPEC.md` `302` kick-signal use does not contradict | Internally consistent. |
| `atfork` lock ordering | No `atfork` / `pthread_atfork` specification in any of the five in-scope files; futex ordering is `Rank-1 mmap_lock` → `Rank-7 futex_bucket_lock` with pre-bucket pinning in [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md) `575-580` | No contradiction to report; absence is not a defect. |
| Futex / `fork` / `execve` lifecycle | [SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md) `29`, `351`, `363`, `387`; [UNIFICATION-PLAN.md](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md) `575-603` | Consistent; no test-level `futex` / `execve` / `vfork` implementation in `p3_torture.c` to audit. |

