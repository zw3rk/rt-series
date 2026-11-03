# Round-4 Remediation Review — `ppc64rt` `203b9a8` vs `56bec31`

**Scope and method.** Static review only: the audit report, `git show 203b9a8` (13 files, +556/−227), and five targeted inspections of callers, declarations, and lifetimes. No build, test, Docker, or QEMU run. Findings below are code-level, not runtime-confirmed.

**Headline.** Seven of eight items are fixed as specified. P64-R4-1 is substantially fixed (the premature `float` narrowing is gone and the DBT now defers all A-form arithmetic to the interpreter), but the new quad-reference path computes the reference under the host's round-to-nearest mode regardless of FPSCR.RN, which leaves a directed-rounding double-rounding gap and drops inexact flags for operands with a large exponent gap. Curated C11 and file-size discipline hold: no `#include "*.c"`, largest source file is 849 lines, new files are 315/45/22 lines.

---

## P64-R4-1 — Single-precision arithmetic rounds operands prematurely — **PARTIAL**

**What changed.** `fp_arith_exec()` was removed from `src/interp/fp.c` and replaced by `ppc64_fp_arith_exec()` in the new `src/interp/fp_single.c`. PO 59 ops now compute a `long double` reference from the full-precision `double` operands (`la+lb`, `la*lc`, `la/lb`, `fmal(...)`), then round once to `float` in `fp1_single()`. PO 63 uses a `double` path with `fma()` for the fused forms. The A-form set was widened to XO 18/20/21/25/28/29/30/31 (fused forms now handled). `src/dbt/emit_fp_vs.c` no longer emits any A-form arithmetic (confirmed: only the comment at line 403 mentions A-form; no `xo5`/FADD emitters remain), so interp/DBT parity is preserved by construction.

**Verified.** The audit's reproducer `(1+2^-24) + (-1)` now yields `2^-24`: the quad sum is exact and the single rounding is correct. Operand-conversion flag contamination is gone (flags are derived from `ref` vs. `f`, never from operand narrowing). NaN handling checks all three operands for fused forms and the correct second operand (`FRC` for `fmuls`, `FRB` otherwise) for non-fused.

**Residual defect (new).** `fp_single.c:631-646` compute `ref` *before* `fp1_single()` installs the guest rounding mode; `fesetround(rm[rn])` only brackets the final `(float)ref` cast at lines 504-508. The `fp1_double()` path, by contrast, sets the mode before the operation. Consequences:

- **Directed rounding wrong result.** `fadds` with FRA=`1.0`, FRB=`-2^-130` (both single-representable), FPSCR.RN=1 (toward zero). Exact: `1 - 2^-130`, correct binary32 RZ result `0x3F7FFFFF`. Quad under host nearest rounds `1 - 2^-130` to `1.0` (below quad half-ulp `2^-114`), then `(float)1.0L` = `1.0`. Wrong value, and because `(long double)f == ref`, **XX is not set either**. The same pattern hits `fmadds`-family with an exactly-representable product and a tiny addend. The QEMU oracle (`float64r32` ops) rounds once from the exact value and would diverge.
- **Inexact lost in nearest mode.** `1.0 + 2^-130` under RN=0 returns the right value but never records XX/FI, since the inexactness disappeared in the quad rounding.

Fix: install `rm[rn]` before computing `ref` (then both roundings are in the same direction, which is innocuous), or compute the reference with round-to-odd. Also track "quad was inexact" (e.g. `fetestexcept(FE_INEXACT)` after the quad op) and OR it into `exc`.

**Residual, lower priority.**
- `fp1_single()` line 490 flags OX whenever `|ref| > FLT_MAX` *before* rounding. IEEE/Power determine overflow after rounding with unbounded exponent, so a `ref` in `(FLT_MAX, FLT_MAX + ½ulp)` under nearest, or any `ref < 2^128` under RZ/RM toward FLT_MAX, should set only XX. The old host-flag path got this right, so this is a small flag-precision regression at the overflow boundary.
- **Darwin build:** on Apple Silicon `long double == double`, so `build-darwin` silently degrades to double-then-float double rounding and `fmal` becomes `fma`. There is no `_Static_assert(LDBL_MANT_DIG >= 113, ...)`. The shipped target is aarch64-linux-musl (binary128), so this is a dev-build divergence, not a product defect. Add the static assert or an `#if` fallback.
- Minor DRY nit: the `fesetround`/cast/canonicalize block is repeated three times in `fp1_single()`.

## P64-R4-2 — Integer conversions omit FPSCR updates — **VERIFIED**

`fp.c` now handles XO 14/15 (`fctiw[z]`) and 814/815 (`fctid[z]`). NaN input sets VXCVI (+VXSNAN for signalling), out-of-range sets VXCVI, both via `fp_cvt_invalid()` which also sets VX|FX and re-syncs summaries before any CR1 copy. Range check is now against the *rounded* value (`rd`) per the ISA, with non-`z` forms honoring FPSCR.RN via `fp_cvt_rn()` (host mode is nearest at that point, so `rint` is correct). Inexact conversions record XX|FX|FI through `ppc64_fpscr_record(cpu, 1u)`. The DBT declines all four XOs (`emit_fp_vs.c:88`), so difftest runs both engines through the interpreter.

Nit: the invalid path does not clear FI/FR (ISA clears them on invalid conversion), so a stale FI from the previous op can survive a NaN conversion. Low.

## P64-R4-3 — Growing file mappings silently accept refill failures — **VERIFIED**

`vm_file_fill_tail()` now: returns 9 (EBADF) when bytes are needed but `held_fd < 0`; propagates `ppc64_vm_file_stage()` errors (9/5); returns 14 on `ppc64_vm_write_raw()` failure. Short reads are completed by the shared helper. Both call sites (`vm_file_mremap.c:239`, `:296`) return `rc` upward. `held_fd` is a retained dup (`vm_file_priv.h:26`) that only drops to −1 on inode-key mismatch or family release, so EBADF is the right explicit outcome there rather than a zero-filled "success".

Not re-verified in this budget: the syscall-level rollback in `syscall_mm_mremap()` that must discard COW slots allocated for pages filled before the failing page (the early return skips the sweep at `vm_file_mremap.c:306`). The commit message and Round-3 history assert that rollback exists; I did not re-read it.

## P64-R4-4 — Worker exec inherits the wrong pending-signal set — **VERIFIED**

`run_sig_exec_snapshot()` now reads `*syscall_p4_sigpending_ptr(&run_sig_pending)`, the same accessor the delivery paths at `sigdeliver.c:444` and `:511` already use. The prototype at line 38 predates this change. There is no separate process-shared pending set in `syscalls_p4.c` (kill routes to a specific task's `sig_pending`, line 172), so the audit's "combine process-directed signals" clause does not apply to this representation. Residual, by design: signals pending on *other* tasks are dropped by exec, which Linux would keep for process-directed ones.

## P64-R4-5 — Exec converts default dispositions into explicit ignore — **VERIFIED**

Snapshot serializes only `run_sigacts[sig].handler == 1u` (explicit `SIG_IGN`); restore at line 216 reinstalls `handler = 1u` for those bits only. SIGCHLD/SIGURG/SIGWINCH defaults remain `SIG_DFL` after exec.

## P64-R4-6 — Internal exec variables reach the guest before removal — **VERIFIED**

`run_sig_exec_capture()` is called at `core.c:553`, immediately before `run_build_stack()` at line 554, and it `unsetenv`s all three handoff words after parsing them into file-scope statics. `run_sig_exec_restore()` at line 579 consumes the captured values and clears them. Both `run_build()` callers (`main.c:178`, `difftest.c:81`) go through this path. The `getenv` fallback in restore is only reachable if capture was skipped, which no current caller does.

## P64-R4-7 — Expanded exec environment exceeds cleanup's bound — **VERIFIED**

`proc_free_strvec()` now walks to the NULL terminator. I checked that every vector it receives is terminated: `proc_read_strvec()` pre-NULLs all 257 slots and only returns success with `count ≤ 256` (a 257th entry trips `E2BIG` on the next iteration and that path frees locally); `proc_envp_inject_sig()` writes `nvec[count] = NULL`. No out-of-bounds read introduced.

## P64-R4-8 — File staging duplicates logic and error policy — **VERIFIED**

New `src/vm/vm_file_stage.{c,h}` provides `ppc64_vm_file_stage()` (EINTR retry, loop to `n == 0`, zero past EOF or wrapped offset, EBADF→9, other→5, NULL buf→22). All three sites use it: `mm_stage_file()`, `ppc64_vm_file_fill()`, `vm_file_fill_tail()`. Intended behavior change: `ppc64_vm_file_fill()` now preserves EBADF instead of folding it into EIO, and short reads are completed rather than treated as EOF.

---

## Curated C11 / hygiene

- No `#include "*.c"` anywhere in `src/`.
- Max source file 849 lines (`src/interp/fp.c`); `fp_single.c` 315, `vm_file_stage.c` 45. `make check-line-limits` should pass.
- `unsigned char buf[PPC64_VM_PAGE_SIZE]` is a constant-size array, not a VLA. No banned string functions. Only C11 `<fenv.h>`/`<math.h>` facilities used.
- No `x18` touched; no new assembly.
- Makefile picks up the new `.c` files via `find`, so no build wiring was needed.

## Summary

| Item | Status | Note |
|---|---|---|
| P64-R4-1 | **PARTIAL** | Premature narrowing fixed; DBT defers. Reference computed under host nearest mode: directed-rounding results and XX flags can diverge for large exponent gaps; OX flagged pre-rounding; no `LDBL_MANT_DIG` guard for Darwin. |
| P64-R4-2 | VERIFIED | FI/FR not cleared on invalid conversion (low). |
| P64-R4-3 | VERIFIED | Syscall-level COW-slot rollback on early return not re-read. |
| P64-R4-4 | VERIFIED | Other tasks' pending signals dropped by exec (representation limit, not in scope). |
| P64-R4-5 | VERIFIED | |
| P64-R4-6 | VERIFIED | |
| P64-R4-7 | VERIFIED | All freed vectors confirmed NULL-terminated. |
| P64-R4-8 | VERIFIED | EBADF now preserved in `ppc64_vm_file_fill()` (intended). |

## Newly Discovered Consequential Follow-Ups

1. **P64-R5-1 (Medium, BUG) `src/interp/fp_single.c:631-646, 504-508`** — PO 59 reference is computed under host round-to-nearest; the guest rounding mode is applied only to the final cast. `fadds 1.0, -2^-130` with RN=toward-zero returns `1.0` instead of `0x3F7FFFFF` and sets no XX. Set the mode before computing `ref` and OR quad-inexact into `exc`.
2. **P64-R5-2 (Low, BUG) `src/interp/fp_single.c:490`** — OX asserted for `|ref| > FLT_MAX` before rounding; should be determined after rounding with unbounded exponent (nearest within ½ ulp of FLT_MAX, or RZ/RM toward FLT_MAX, is XX only).
3. **P64-R5-3 (Low, DEFECT) `src/interp/fp_single.c`** — No compile-time guard that `long double` is binary128; `build-darwin` silently double-rounds. Add `_Static_assert(LDBL_MANT_DIG >= 113, ...)` or a guarded fallback.
