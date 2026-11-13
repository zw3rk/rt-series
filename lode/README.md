# `rt-series` Engineering Lode

This directory stores durable engineering research, the low-level ISA/ABI
reference, a dated baseline snapshot, and the review transcripts behind the
architecture and the convergence audit program.

## Contents

- [`ISA-TRAP-AND-ABI-MATRIX.md`](ISA-TRAP-AND-ABI-MATRIX.md) — Reference
  matrix of all 11 guest architectures (`a32`, `i686`, `rv64gc`, `rv32gc`,
  `mips32`, `ppc32`, `sparc32`, `loongarch64`, `ppc64le`, `mips64`, `sparc64`):
  ELF header fields, endianness, register conventions, condition flags, branch
  delay slots, TLS, atomics, Linux syscall ABIs, vDSO, and signal frames.
- [`STATE-OF-PLAY-2026-10-23.md`](STATE-OF-PLAY-2026-10-23.md) — **Historical
  baseline snapshot (2026-10-23, superseded).** Cross-repository audit as of
  that date: commits, working-tree state, defect ledgers, and verification
  gates. It records where the series stood before the unification and
  convergence programs; do not use its commits or counts as current.
- [`reviews/`](reviews/) — Review transcripts in 4 organized subdirectories
  (340 files total), oldest program first.

## Review Directories

### `reviews/spec/` (4 files)

The two original `SPEC.md` reviews plus point-by-point dispositions:

- [`2026-10-23-astra-review-1.md`](reviews/spec/2026-10-23-astra-review-1.md)
  and
  [`2026-10-23-astra-review-1-dispositions.md`](reviews/spec/2026-10-23-astra-review-1-dispositions.md)
  (48 findings, 1-to-1 correspondence).
- [`2026-10-23-astra-review-2.md`](reviews/spec/2026-10-23-astra-review-2.md)
  and
  [`2026-10-23-astra-review-2-dispositions.md`](reviews/spec/2026-10-23-astra-review-2-dispositions.md)
  (26 follow-up findings `R2-01`..`R2-26`).

### `reviews/unification/` (78 files)

Unification-plan reviews and per-wave stage-gate reviews:

- Architecture reviews of the unification plan with dispositions:
  [`2026-10-26-astra-unification-review.md`](reviews/unification/2026-10-26-astra-unification-review.md),
  [`2026-10-26-astra-unification-review-2.md`](reviews/unification/2026-10-26-astra-unification-review-2.md),
  [`2026-10-26-astra-xhigh-unification-review-3.md`](reviews/unification/2026-10-26-astra-xhigh-unification-review-3.md),
  [`2026-10-26-fable-unification-review.md`](reviews/unification/2026-10-26-fable-unification-review.md),
  and the combined
  [`dispositions`](reviews/unification/2026-10-26-astra-xhigh-and-fable-dispositions.md).
- Wave stage gates, including the closing passes
  [`2026-10-26-rc-u3-astra-xhigh.md`](reviews/unification/2026-10-26-rc-u3-astra-xhigh.md),
  [`2026-10-26-rc-u4-astra-xhigh.md`](reviews/unification/2026-10-26-rc-u4-astra-xhigh.md),
  and
  [`2026-10-26-rc-u5-final-astra.md`](reviews/unification/2026-10-26-rc-u5-final-astra.md).

### `reviews/perf-and-clean/` (18 files)

Performance-plan and code-health reviews:

- Plan reviews:
  [`2026-10-28-perf-plan-astra.md`](reviews/perf-and-clean/2026-10-28-perf-plan-astra.md)
  and
  [`2026-10-28-perf-plan-fable.md`](reviews/perf-and-clean/2026-10-28-perf-plan-fable.md),
  plus the P13 follow-ups
  [`2026-10-29-perf-plan-p13-astra.md`](reviews/perf-and-clean/2026-10-29-perf-plan-p13-astra.md)
  and
  [`2026-10-29-perf-plan-p13-fable.md`](reviews/perf-and-clean/2026-10-29-perf-plan-p13-fable.md).
- Eight cross-cutting codebase audits (`clean-dry-yagni-*`, one per
  translator group plus DBT, OS backends, VM/Soft-TLB, and interp/build
  subsystems) and the catalogue reviews
  [`2026-10-29-catalogue-todo-astra.md`](reviews/perf-and-clean/2026-10-29-catalogue-todo-astra.md)
  /
  [`2026-10-29-catalogue-todo-fable.md`](reviews/perf-and-clean/2026-10-29-catalogue-todo-fable.md).

### `reviews/convergence/` (240 files)

Round-by-round convergence audit transcripts (`defects-r<N>-<repo>-astra.md`
hunting reports paired with `-fable.md` verification reports):

- Rounds 1–3 (2026-11-02) whole-repository sweeps, rounds 4–9 (2026-11-03)
  verification and subsystem deep-dives, and rounds 10–12 annealed deep-dives
  with per-item `VERIFIED` verdicts.
- Final per-repository closeouts, e.g.
  [`2026-11-03-defects-r12-a32rt-fable.md`](reviews/convergence/2026-11-03-defects-r12-a32rt-fable.md)
  and
  [`2026-11-03-defects-r12-sparc64rt-fable.md`](reviews/convergence/2026-11-03-defects-r12-sparc64rt-fable.md).

The per-item checklists these transcripts feed are archived in
[`../docs/archive/defects/`](../docs/archive/defects/) and summarized in
[`../docs/DEFECTS.md`](../docs/DEFECTS.md).
