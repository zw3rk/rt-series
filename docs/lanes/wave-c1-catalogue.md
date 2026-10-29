# Wave C1 — Unified Catalogue Runner, Golden Parity Suites & P0–P4 Qualification Wave

This task card coordinates the 6 parallel `muse` worker lanes implementing [`docs/CATALOGUE-TODO.md`](../CATALOGUE-TODO.md) across `rt-series` and all 10 `<arch>rt` repositories.

---

## 1. Frozen Shared Contract (`tools/parity_contract.sh`)

[`tools/parity_contract.sh`](../../tools/parity_contract.sh) is frozen and owned by the Coordinator. Every `<repo>/tests/parity_suite.sh` sources it:

```sh
CONTRACT="$(cd "$(dirname "$0")/../../rt-series/tools" && pwd)/parity_contract.sh"
. "$CONTRACT"
parity_init "<repo>"
```

Each executed check emits a structured row via `parity_row <abi> <host> <case> <engine> <status> <elapsed_ms> [detail]` and finishes with `parity_summary`, which prints `0 FAIL, 0 GAP` and exits non-zero if `fail > 0`, `gap > 0`, `skip > 0` (when `PARITY_ALLOW_SKIP=0`), or `pass == 0`.

---

## 2. Parallel Worker-Lane Matrix & Exclusive File Ownership

| Lane | Tmux Pane | Target Repository / Scope | Exclusive File Ownership | Single-Command Acceptance Gate |
|---|---|---|---|---|
| **Lane C1-1** | `0:7.2` | `rt-series` | `tools/run_catalogue.sh`, `tools/run_grind.sh`, `tests/catalogue/run_catalogue.sh`, `tests/p3_torture.c`, `tests/tcg/**`, `Makefile`, `docs/SOFTWARE-CATALOGUE.md`, `docs/PERF-PLAN-P13.md` | `timeout --kill-after=30s 180s bash -lc "cd /Users/angerman/Projects/zw3rk/rt-series && sh -n tools/run_catalogue.sh && sh -n tools/run_grind.sh && test -x tests/catalogue/run_catalogue.sh && (! tools/run_catalogue.sh smoke --arch nonexistent_arch)"` |
| **Lane C1-2** | `0:7.3` | `a32rt`, `i686rt` | `a32rt/tests/**`, `a32rt/Makefile`, `i686rt/tests/**`, `i686rt/Makefile` | `timeout --kill-after=30s 240s bash -lc "sh /Users/angerman/Projects/zw3rk/a32rt/tests/parity_suite.sh && sh /Users/angerman/Projects/zw3rk/i686rt/tests/parity_suite.sh"` |
| **Lane C1-3** | `0:7.4` | `mips32rt`, `ppc32rt`, `sparc32rt` | `mips32rt/tests/**`, `mips32rt/Makefile`, `ppc32rt/tests/**`, `ppc32rt/Makefile`, `sparc32rt/tests/**`, `sparc32rt/Makefile` | `timeout --kill-after=30s 240s bash -lc "sh /Users/angerman/Projects/zw3rk/mips32rt/tests/parity_suite.sh && sh /Users/angerman/Projects/zw3rk/ppc32rt/tests/parity_suite.sh && sh /Users/angerman/Projects/zw3rk/sparc32rt/tests/parity_suite.sh"` |
| **Lane C1-4** | `0:7.5` | `rvrt` | `rvrt/tests/**` | `timeout --kill-after=30s 240s bash -lc "sh /Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh"` |
| **Lane C1-5** | `0:7.6` | `loongarch64rt`, `ppc64rt` | `loongarch64rt/tests/**`, `ppc64rt/tests/**` | `timeout --kill-after=30s 240s bash -lc "sh /Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh && sh /Users/angerman/Projects/zw3rk/ppc64rt/tests/parity_suite.sh"` |
| **Lane C1-6** | `0:7.7` | `mips64rt`, `sparc64rt` | `mips64rt/tests/**`, `sparc64rt/tests/**` | `timeout --kill-after=30s 240s bash -lc "sh /Users/angerman/Projects/zw3rk/mips64rt/tests/parity_suite.sh && sh /Users/angerman/Projects/zw3rk/sparc64rt/tests/parity_suite.sh"` |
