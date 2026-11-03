# Round-4 Remediation Review: `fe7e874` vs `3c0bb33`

Scope: static inspection only. No builds, tests, containers, or QEMU were run. Four tool turns were used.

**Headline:** six of seven items are verified. RTS-R4-5 is partial: a compiler that must be SIGKILLed is still reported as a "target-specific skip", and `run_grind.sh` has no interruption trap, so the commit message claim "temp artifacts always removed" is overstated. No regressions were found. Curated C11 checks pass.

## Per-item verification

### RTS-R4-1 — LL/SC guard matches implemented probes: `VERIFIED`

`tests/p3_llsc.h:26-36` now lists exactly the predicates used by the `#elif` chain at lines 61-120, including the ARMv6 and `__riscv_atomic` qualifiers and the `__ppc__` / `__loongarch__` aliases. The silent fallback that set `stored = 0` is replaced by `#error` at line 135, so guard and implementation can no longer drift apart silently. `P3_FORCE_NO_LLSC` still forces the no-LL/SC path.

Non-blocking note: `__ARM_ARCH >= 6` admits ARMv6 Thumb-1 builds where `ldrex` is not encodable. The current recipe builds armel as ARMv5TE and armhf as ARMv7 Thumb-2, so this is unreachable today.

### RTS-R4-2 — Guest invalidation on header or recipe change: `VERIFIED`

`tools/build_uniform_guests.sh:159-173` now requires both headers to exist and compares `p3_llsc.h`, `sig_fault_addr.h`, and the recipe itself against both output binaries. Compile flags live in the recipe, so a flag change also triggers a rebuild. A missing header makes `already_built` false, which leads to a loud compile failure rather than a stale skip.

Residual, out of scope: a retagged toolchain image such as `sparc32rt-oracle:latest` still does not invalidate guests.

### RTS-R4-3 — Container cleanup fails when state cannot be established: `VERIFIED`

Owned names are recorded before each `docker run` at lines 192, 219, and 238. Every `docker ps`, `inspect`, and `rm` is bounded by `timeout --kill-after=30s 30s`. A `docker ps` failure now returns nonzero from both cleanup and verification, and `on_uniform_exit` turns that into exit status 1.

Two residuals, both acceptable:

- In the owned-name loops at lines 59-67 and 98-104, a failed `docker inspect <name>` is still treated as "absent". The bounded suffix sweep that follows is the backstop, and a daemon outage makes that sweep's `docker ps` fail, so the gate cannot pass silently.
- `on_uniform_int` and `on_uniform_term` keep `|| true` and do not remove the owned-list file in `/tmp`. They exit 130 and 143 anyway, so the status is nonzero regardless.

### RTS-R4-4 — Sub-page permission fixture checks write protection: `VERIFIED`

`tests/tcg/smoke_tcg.c:252-402` now initialises all four sub-pages while RW, verifies RX and RO reads return the seeded bytes, verifies RX and RO writes fault with `SIGSEGV` or `SIGBUS`, a positive `si_code`, and an `si_addr` on the correct page, and rechecks the RW page after each fault. The handler is installed inside the test, which makes it self-contained. The handler only performs `siglongjmp` when armed, so an unexpected trap fails rather than loops.

Non-blocking sharpening suggestions:

- The post-fault RW recheck only reads `p[0]`. A write would additionally catch a host page narrowed to read-only.
- After each write fault, the target byte is not re-read, so a backend that raises the signal but also commits the store would pass.

### RTS-R4-5 — Grind generators and compilers bounded: `PARTIAL`

All six invocations are bounded: torture at line 361, builtin at 538, csmith at 753 and 756, yarpgen at 768, 785, and 801. Exit status 124 is reported as a distinct failure, and temporary artifacts are removed on every normal path, including the moved `rm -rf "$_ydir"`. The `$?` capture in the `else` branch is correct POSIX sh.

Two gaps remain:

1. **SIGKILL escalation is misclassified.** GNU `timeout` returns 137, not 124, when `--kill-after` has to escalate. At lines 363 and 540 a 137 falls into the `grind_skip` branch, so a hung compiler that ignores SIGTERM is reported as "did not compile (target-specific, skipped)". This is exactly the ambiguity the finding asked to remove. Fix: treat both codes as timeout.
   ```sh
   case "$_cc_rc" in 124|137) grind_fail ... ;; *) grind_skip ... ;; esac
   ```
2. **No interruption cleanup.** `run_grind.sh` contains no `trap`. On Ctrl-C or SIGTERM mid-compile, `/tmp/grind_*_$$` sources, binaries, and the yarpgen directory leak. The finding explicitly asked for cleanup on interruption, and the commit message says artifacts are "always removed".

Also note `run_grind.sh` is at 888 lines, 12 under the cap.

### RTS-R4-6 — Remote benchmark validation propagates failure: `VERIFIED`

`rt_validate_bench_output` at `tools/remote_bench_common.sh:144-160` requires exactly one anchored PASS record per workload, exactly one `ALL_PASS` summary, and no FAIL marker. `parse_and_print` emits a FAIL row and returns 1 on invalid output. `bench_harness.sh` sources the helper at line 25 and delegates at line 397, so there is no undefined-function regression. Both remote callers run under `set -eu` and invoke `parse_and_print` as a plain statement, so the nonzero return aborts the script with nonzero status.

Behavioural note: under `set -e`, the first invalid target in `remote_bench.sh` aborts all later targets, so their RESULT rows are never printed. That satisfies the finding but is worth knowing when reading partial output. The `FAIL|FAILED` grep at `bench_harness.sh:392` is now redundant with the helper and `FAILED` is subsumed by `FAIL`; harmless.

### RTS-R4-7 — Fault-address bridge unified: `VERIFIED`

`tests/sig_fault_addr.h` holds the struct, the `_Static_assert`, and `static inline` encode/decode helpers. Each fixture keeps its own instance. The store helper calls no libc and remains async-signal-safe. The relative include `../sig_fault_addr.h` resolves in every compile site: the docker recipes mount the repo root and compile `/w/tests/tcg/smoke_tcg.c`, and `Makefile:194` compiles from the repo root. Include resolution is relative to the including file, so both work.

## Curated C11 and hygiene checks

| Check | Result |
|---|---|
| `#include "*.c"` in `tests/` or `tools/` | none |
| Largest C file | `tests/p3_torture.c`, 741 lines |
| Largest shell file | `tools/run_grind.sh`, 888 lines |
| Banned string functions, VLAs, x18 in changed C | none seen in the diff |
| Untracked changes under `tests/` or `tools/` | none |

## Summary

| Item | Status | Note |
|---|---|---|
| RTS-R4-1 | VERIFIED | Guard mirrors `#elif` chain; `#error` on mismatch |
| RTS-R4-2 | VERIFIED | Headers and recipe mtimes tracked |
| RTS-R4-3 | VERIFIED | Owned names tracked, docker bounded, `ps` failure fails gate |
| RTS-R4-4 | VERIFIED | RX/RO read and write-fault checks with address match |
| RTS-R4-5 | PARTIAL | Exit 137 reported as skip; no interruption trap |
| RTS-R4-6 | VERIFIED | Shared validator, failure propagates under `set -eu` |
| RTS-R4-7 | VERIFIED | Shared header, separate instances, include paths resolve |

## Newly discovered consequential follow-ups

1. **`run_grind.sh` timeout classification misses exit 137.** When `--kill-after` escalates to SIGKILL, gcc-torture and compiler-rt report a skip instead of a timeout failure. Accept `124|137` at lines 363, 540, 754, 758, 769, 789, and 805.
2. **`run_grind.sh` has no EXIT/INT/TERM trap.** Temporary sources, binaries, and the yarpgen directory leak on interruption. Add a trap that removes the `/tmp/grind_*_$$` set and `_ydir`.

Both are small and local to `tools/run_grind.sh`. Nothing else rises to consequential.
