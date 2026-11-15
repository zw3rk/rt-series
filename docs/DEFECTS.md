# `rt-series` Defect Ledger — Executive Summary

**Status: Rounds 1–20 plus the Post-Round-12 Fast-Path Restoration Round are
100% resolved (`0` open defects).**

Every finding filed in Rounds 1–20 across the 10 translator repositories and
the `rt-series` harness has been remediated on `master`, re-verified by an
independent review pass, and checked off. Round 19 (`19 / 19` resolved in
`cc3d3aa`) audited and converged `a32rt`'s 32-bit iOS (`armv7`/`armv7s`)
Mach-O & XNU personality (`8d87576 -> cc3d3aa`), and Round 20 (`6 / 6` resolved
in `6bf6d76` / `100af25`) remediated `a32rt`'s backend RAS/IBTC dispatch,
16-byte Soft-TLB, 22-slot VFP/NEON register cache, Regime A2 AOT persistence,
and reference-interpreter `VDUP.32`/`VNMLS` precision alongside [`PERF.md`](PERF.md)
(`A32-R20-P0`..`A32-R20-P15`, `16 / 16` resolved). The full checklists live in
the archive:

- [Rounds 1–12](archive/defects/rounds-01-12.md) — broad sweeps plus the six
  orthogonal subsystem deep-dives and the fast-path restoration sign-off.
- [Rounds 13–18](archive/defects/rounds-13-18.md) — five-lens review plus the
  16-loop multi-review, `191 / 191` resolved.
- [Round 19 (`a32rt` 32-bit iOS & DBT audit)](archive/defects/round-19-a32rt-ios.md) —
  6-subsystem audit + 8-track verification (`A32-IOS-D1`..`A32-IOS-D19`), `19 / 19` resolved.
- [Round 20 (`a32rt` backend dispatch, Soft-TLB, VFP/NEON & AOT audit)](archive/defects/round-20-a32rt-perf.md) —
  6-subsystem audit + `--difftest` precision & 6-slice RC hardening (`A32-R20-D1`..`A32-R20-D6`), `6 / 6` resolved.
- [Performance ledger (`PERF.md`)](PERF.md) — Wave P1–P13 baselines plus Rounds 19–20
  `a32rt` backend codegen, 16-byte Soft-TLB, VFP/NEON cache, and Regime A2 AOT fast paths (`25 / 25` resolved).
- [Convergence audit process](CONVERGENCE-AUDIT-PROCESS.md) — the hunting,
  clustering, remediation, and verification playbook behind every round.

## 1. Current Converged State (All 11 Repositories)

| Repository | Converged `master` | Rounds 13–20 | Verification gates |
| --- | --- | ---: | --- |
| [a32rt](https://github.com/zw3rk/a32rt) | `6bf6d76` | `44 / 44` | ELF32 + iOS (`61/61`) PASS, A1/A2 AOT (`blocks_compiled=0`), `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [i686rt](https://github.com/zw3rk/i686rt) | `226c880` | `17 / 17` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [mips32rt](https://github.com/zw3rk/mips32rt) | `a0794d2` | `18 / 18` | `make check`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [ppc32rt](https://github.com/zw3rk/ppc32rt) | `4a35f01` | `20 / 20` | `make check`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [sparc32rt](https://github.com/zw3rk/sparc32rt) | `1dd1f22` | `20 / 20` | `make check`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [rvrt](https://github.com/zw3rk/rvrt) | `f978775` | `14 / 14` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [loongarch64rt](https://github.com/zw3rk/loongarch64rt) | `c98e960` | `14 / 14` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [ppc64rt](https://github.com/zw3rk/ppc64rt) | `8ec83bc` | `18 / 18` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [mips64rt](https://github.com/zw3rk/mips64rt) | `71ac358` | `15 / 15` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [sparc64rt](https://github.com/zw3rk/sparc64rt) | `5486608` | `19 / 19` | parity PASS, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [rt-series](https://github.com/zw3rk/rt-series) | umbrella harness | `17 / 17` | `make check && make check-catalogue` PASS |
| **Total, Rounds 13–20** | | **`216 / 216`** | **100% verified, `0` open** |

## 2. How Convergence Was Reached

**Rounds 1–3, broad sweep.** Whole-repository audits across all 11
repositories cleared every critical defect first: unity `.c` includes,
over-length files, and the highest-severity correctness bugs (`187`, `145`,
and `85` items resolved).

**Rounds 4–6, verification.** Repeated whole-repository sweeps with expanded
cross-runtime sibling checks confirmed the fixes held and caught the defects
the first sweeps missed (`91`, `91`, and `87` items resolved).

**Rounds 7–12, six-subsystem step-size-annealed deep-dives.** Instead of
skimming every file, each round read one subsystem end-to-end across all
repositories: ISA interpreter and decode, AArch64 DBT and chaining, virtual
memory and Soft-TLB, threading and futex, signals and fault recovery, and
syscall ABI marshaling with both host backends. Once the easy defects were
gone the step size annealed — cosmetic churn stopped, `0`-finding rounds
became the expected outcome — and the per-round counts collapsed (`277`,
`55`, `96`, `19`, `24`, `23` items resolved).

**Post-Round-12 Fast-Path Restoration, `7 / 7`.** Correctness fixes had
conservatively disabled seven JIT fast paths. Each was restored behind an
inline boundary guard (normal-range operations stay in native AArch64
instructions; only true boundary cases fall back to the interpreter),
re-audited to `0` defects, and confirmed faster than `qemu-user` on every
guest architecture.

**Rounds 13–18, five-lens plus 16-loop multi-review, `191 / 191`.** A final
five-lens pass (security, performance, dead code, comments, correctness)
followed by sixteen focused re-review loops over integer ALU behavior, FP
narrowing, uncalled definitions, host errno mapping, and memory/atomics. Every
item was confirmed by two independent read-only checks and remediated on
`master`.

## 3. Fast-Path Restoration Results

| Guest Arch | Restored total | `qemu-user` total | Speedup |
| --- | ---: | ---: | ---: |
| `armhf` | `9,742 µs` | `22,066 µs` | **2.27x** |
| `i686` | `28,846 µs` | `32,623 µs` | **1.13x–1.34x** |
| `mipsel` | `26,524 µs` | `39,328 µs` | **1.48x–1.79x** |
| `ppc32` | `35,732 µs` | `67,692 µs` | **1.89x–2.10x** |
| `sparc32` | `40,107 µs` | `68,286 µs` | **1.70x–1.91x** |
| `riscv64` / `riscv32` | `25,258` / `25,153 µs` | `30,816` / `26,932 µs` | **1.07x–1.34x** |
| `loongarch64` | `35,065 µs` | `42,824 µs` | **1.22x** |
| `ppc64le` | `30,678 µs` | `67,990 µs` | **2.22x** |
| `mips64el` | `30,393 µs` | `42,720 µs` | **1.41x–1.77x** |
| `sparc64` | `43,653 µs` | `68,951 µs` | **1.58x–2.09x** |

## 4. Archive Index & Review Provenance

- Rounds 1–12 with the restoration sign-off:
  [archive/defects/rounds-01-12.md](archive/defects/rounds-01-12.md).
- Rounds 13–18, per-repository findings with audited revisions:
  [archive/defects/rounds-13-18.md](archive/defects/rounds-13-18.md).
- Round 19, `a32rt` 32-bit iOS (`armv7`/`armv7s`) & Thumb-2/DBT audit (`19 / 19` resolved):
  [archive/defects/round-19-a32rt-ios.md](archive/defects/round-19-a32rt-ios.md).
- Round 20, `a32rt` backend dispatch, Soft-TLB, VFP/NEON & AOT audit (`6 / 6` resolved):
  [archive/defects/round-20-a32rt-perf.md](archive/defects/round-20-a32rt-perf.md).
- Audit and remediation playbook (hunting, clustering, surgical fixes,
  independent verification, step-size annealing):
  [CONVERGENCE-AUDIT-PROCESS.md](CONVERGENCE-AUDIT-PROCESS.md).
- Round-by-round review transcripts, newest first:
  [../lode/reviews/convergence/](../lode/reviews/convergence/).

Each archived round records the audited revision, the remediation commits,
and the independent verification verdicts item by item, so any entry in the
summary tables above traces to its exact evidence.

## 5. Standing Verification Gates

A repository counts as converged only while all of these pass on `master`:

1. `tests/parity_suite.sh` (or `make check` / `make test-ios`) — `0 FAIL, 0 GAP, 0 SKIP`.
2. `--difftest` lockstep runs — `0` divergences between `interp` and `dbt`.
3. `--full` 5-workload benchmark — `ALL_PASS` with deterministic CRC match.
4. AOT cold-emit to warm-reload cycle on guest binaries (`blocks_compiled=0`).
5. `make check-line-limits` — every file within the line ceiling, no unity
   includes, strict Curated-C11 warnings clean.

**Bottom line: Rounds 1–20 and the restoration round are fully resolved
(`1,180` round 1–12 items, `7 / 7` restored fast paths, `191 / 191` round
13–18 items, `19 / 19` round 19 `a32rt` iOS items, and `6 / 6` round 20
`a32rt` backend/precision items). There are `0` open defects. New work starts
from this ledger; it does not reopen it.**
