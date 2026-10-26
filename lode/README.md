# `rt-series` Engineering Lode

This directory stores durable engineering research, cross-repository state audits, architectural reference tables, and independent review records for `rt-series`.

## Contents

- [`STATE-OF-PLAY-2026-10-23.md`](STATE-OF-PLAY-2026-10-23.md) — Comprehensive audit of `rt-series`, `../a32rt`, `../i686rt`, `../rvrt`, and `../hyper-linux` as of 2026-10-23 (commits, dirty files, stashes, unmerged worktrees/branches, defect ledgers, and verification gates).
- [`ISA-TRAP-AND-ABI-MATRIX.md`](ISA-TRAP-AND-ABI-MATRIX.md) — Reference matrix of all 11 guest architectures (`a32`, `i686`, `rv64gc`, `rv32gc`, `mips32`, `ppc32`, `sparc32`, `loongarch64`, `ppc64le`, `mips64`, `sparc64`): ELF header fields, endianness, register conventions, condition flags, branch delay slots, TLS, atomics, Linux syscall ABIs, vDSO, and signal frames.
- [`reviews/2026-10-23-astra-review-1.md`](reviews/2026-10-23-astra-review-1.md) — Independent Review #1 of `rt-series` by `astra` (`gpt-6-astra`) via `codex` (48 findings: 36 Major, 11 Minor, 1 Nit).
- [`reviews/2026-10-23-astra-review-1-dispositions.md`](reviews/2026-10-23-astra-review-1-dispositions.md) — Point-by-point disposition table for all 48 findings from Review #1 (1-to-1 numbered correspondence).
- [`reviews/2026-10-23-astra-review-2.md`](reviews/2026-10-23-astra-review-2.md) — Independent Review #2 of `rt-series` by `astra` (`gpt-6-astra`) via `codex` (verifying closure of Review #1 items and identifying 26 follow-up findings `R2-01`..`R2-26`).
- [`reviews/2026-10-23-astra-review-2-dispositions.md`](reviews/2026-10-23-astra-review-2-dispositions.md) — Point-by-point disposition table for all 26 findings (`R2-01`..`R2-26`) from Review #2.
- [`reviews/2026-10-26-astra-unification-review.md`](reviews/2026-10-26-astra-unification-review.md) — Critical architectural review of [`docs/UNIFICATION-PLAN.md`](../docs/UNIFICATION-PLAN.md) by `astra` via `codex` against all 11 sibling repositories (15 findings: 4 Critical, 8 Major, 3 Minor).
- [`reviews/2026-10-26-astra-unification-review-dispositions.md`](reviews/2026-10-26-astra-unification-review-dispositions.md) — Point-by-point disposition table resolving all 15 findings in `docs/UNIFICATION-PLAN.md` (Rev 2).
