# `rt-series` Defect Ledger — Executive Summary

**Status: Rounds 1–22 plus the Post-Round-12 Fast-Path Restoration Round are
100% resolved (`0` open defects).**

Every finding filed in Rounds 1–22 across the 11 translator repositories, the
`hyper-linux` `darwin32` personality workstream, and the `rt-series` harness has
been remediated on `master`, re-verified by an independent review pass, and
checked off. Round 19 (`19 / 19` resolved in `cc3d3aa`) audited and converged
`a32rt`'s 32-bit iOS (`armv7`/`armv7s`) Mach-O & XNU personality, Round 20
(`6 / 6` resolved in `6bf6d76` / `100af25`) remediated `a32rt`'s backend
RAS/IBTC dispatch, 16-byte Soft-TLB, 22-slot VFP/NEON register cache, and
Regime A2 AOT persistence, Round 21 (`36 / 36` resolved across 5 concurrent
campaign tracks) converged standalone Class-B `s390xrt` (`8410b2c`), `ppc64rt`
big-endian ELFv1 (`09832a3`), `ppc32rt` Darwin G4 CPU & `A32H_ABI 1.2` `G02`
bridge (`a2ccdfc`), `a32rt` `G02` bridge & `a32rt-slim` decoupling (`a53ee27`),
and `hyper-linux` unified 32-bit PowerPC/ARM Darwin personality (`b8cc19a0` on
`darwin32/personality`), and Round 22 promotes `s390xrt` to a full
multi-process OS with a native AArch64 W^X block JIT (`a45d529`), upgrades
`ppc64rt` to dual-ABI 64K IBTC/Soft-TLB coverage (`b37b021`), and qualifies
`T1`–`T4` `guest-payload` across all 11 translators (`681 PASS, 0 FAIL,
0 GAP, 0 SKIP`; `T1`–`T4` `ALL_OK` on every sysroot). The full checklists live
in the archive:

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

## 1. Current Converged State (All 12 Repositories + `darwin32`)

| Repository | Converged `master` | Rounds 13–21 | Verification gates |
| --- | --- | ---: | --- |
| [a32rt](https://github.com/zw3rk/a32rt) | `5959599` | `53 / 53` | R22 `45/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, ELF32 + iOS (`61/61`) + `a32rt-slim` `A32H_ABI 1.2` HVF E2E (`rc=42`), `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [i686rt](https://github.com/zw3rk/i686rt) | `deffa5e` | `17 / 17` | R22 `41/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [mips32rt](https://github.com/zw3rk/mips32rt) | `bf9f0bc` | `18 / 18` | R22 `142/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [ppc32rt](https://github.com/zw3rk/ppc32rt) | `2dfe7d0` | `25 / 25` | R22 `106/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, G4 Altivec + `A32H_ABI 1.2` HVF E2E (`rc=37`), `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [sparc32rt](https://github.com/zw3rk/sparc32rt) | `1dd1f22` | `20 / 20` | R22 `31/0/0/0`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [rvrt](https://github.com/zw3rk/rvrt) | `b237770` | `14 / 14` | R22 `68/0/0/0` + `T1`–`T4` `28/28 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [loongarch64rt](https://github.com/zw3rk/loongarch64rt) | `a748562` | `14 / 14` | R22 `53/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [ppc64rt](https://github.com/zw3rk/ppc64rt) | `b37b021` | `27 / 27` | R22 `70/0/0/0` (ELFv2 + BE ELFv1) + `T1`–`T4` `28/28 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [mips64rt](https://github.com/zw3rk/mips64rt) | `9371083` | `15 / 15` | R22 `59/0/0/0` + `T1`–`T4` `29/29 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| [sparc64rt](https://github.com/zw3rk/sparc64rt) | `0100cc5` | `19 / 19` | R22 `32/0/0/0` + `T1`–`T4` `28/28 ALL_OK`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| `s390xrt` *(local)* | `a45d529` | `12 / 12` | R22 `34/0/0/0` + `T1`–`T4` `28/28 ALL_OK` (Alpine `s390x`), native W^X block JIT Linux DBT `37,578 µs`, `--difftest` 0 divergences, `--full` bench `ALL_PASS` |
| `hyper-linux` (`darwin32`) | `b8cc19a0` | `3 / 3` | `1,376/1,376` host unit checks, `test-darwin32-os-srv` (`92/92`), live HVF PPC32 (`rc=37`) & ARM32 slim (`rc=42`) PASS |
| [rt-series](https://github.com/zw3rk/rt-series) | umbrella harness | `17 / 17` | `make check && make check-catalogue` PASS |
| **Total, Rounds 13–21** | | **`254 / 254`** | **100% verified, `0` open** |

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

**Round 22, series-wide performance & `T1`–`T4` qualification convergence.**
Two late defects were filed and closed: `a32rt` (`5959599`) fixed 2
`grp_emit_grouped` defects in `src/core/core_emit_mem.c` — a Regime A2
cross-page cold slow-path fallthrough into `cold_emit_fault` and a hot-path
`w22` pre-indexed writeback clobber — restoring `test-m7-armhf` and
`test-m8-glibc-armhf` dynamic `PASS` and `45/0/0/0` parity; and `i686rt`
(`deffa5e`) fixed a `[MEDIUM]` `pselect6_time64` `+12` padding mask defect.
The round otherwise promotes the last two baseline-only translators to
production DBT and extends the real-world software catalogue to every sysroot. `s390xrt` moves from single-process + C-helper DBT to full
multi-process/multi-thread `fork`/`vfork`/`clone`/`execve`/`wait4` with a
native AArch64 W^X block JIT (`22.0×` Darwin DBT, `2.36×` faster than
`qemu-s390x`); `ppc64rt` gains dual-ABI (ELFv2 + BE ELFv1 `.opd`) 64K
IBTC/Soft-TLB coverage with POWER8/VMX fast paths (`2.10×` vs same-run
`qemu-ppc64`); and `run_catalogue.sh guest-payload` passes `T1`–`T4`
(`29` checks) on all 11 translators with `0 FAIL, 0 GAP, 0 SKIP` (`681`
parity rows total). The standing gates in §5 below now include the Round 22
parity + `guest-payload` counts per repository (see §1).

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

**Bottom line: Rounds 1–22 and the restoration round are fully resolved
(`1,180` round 1–12 items, `7 / 7` restored fast paths, `191 / 191` round
13–18 items, `19 / 19` round 19 `a32rt` iOS items, `6 / 6` round 20
`a32rt` backend/precision items, `36 / 36` round 21 expansion items, and the
Round 22 perf + `T1`–`T4` qualification gates green on all 11 translators).
There are `0` open defects. New work starts from this ledger; it does not
reopen it.**
