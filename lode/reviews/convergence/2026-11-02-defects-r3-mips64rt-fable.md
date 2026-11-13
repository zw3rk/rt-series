# Post-remediation review: Round-3 fixes (`385b31a` vs `45af6bf`)

Scope: static review only, five tool turns, no builds/tests/Docker/QEMU. All claims below are source-derived from the commit diff and the current tree.

## Headline

Five of six items are fixed or materially improved. One fix introduces a consequential regression: the new ADD.S/SUB.S residual logic mishandles an infinite first operand, so `+Inf + (-1.0f)` now raises Overflow and Inexact in every rounding mode and returns `FLT_MAX` instead of `+Inf` under toward-zero and toward-minus-infinity. Round-trip verification of the Inexact/Overflow path was not done by the new test, which only covers finite absorbed operands.

## Per-item findings

### M64-R3-1 — Syscall copyout vs LL/SC: PARTIAL

What was done (correct):
- New `mips_sc_copyout()` at `src/os/syscalls.c:156` stages in host memory, then takes `sc_lock`, `memcpy`s, calls `mips_llsc_note_write`, releases, then does COW-clear / code-retire / shared-file sync. Ordering is identical to the pre-existing `l2a_commit_guest_write()` in `src/os/syscalls_sync.c:201`, so the two helpers are semantically parallel.
- Lock recursion is safe: `sc_lock_acquire()` (`src/interp/unaligned.c:301`) is depth-counted via `_Thread_local g_sc_held`, so the nested acquire inside `mips_llsc_note_write` does not deadlock. Preemption is blocked for the critical section.
- Converted callers: `pipe2`, `readlinkat`, `getrandom` (all three branches), `getdents64`, `clock_getres`, `clock_nanosleep` rem, `/proc/self/exe` readlink. Error paths are clean: `pipe2` now closes both fds on copyout fault; `getdents64` saves `errno` before `free`; the `&zero` sentinel is never freed (the "free-on-stack-address" fix in the message is real and correct).
- `clock_nanosleep` no longer invalidates the reservation at `rem_va` when the sleep completes without writing; this is strictly better than before.

What remains (why PARTIAL): the audit's root cause was the `guest_range(..., write=1)` contract itself (`src/os/syscalls.c:178`): it invalidates the reservation and then hands back a raw pointer that callers write through with no lock. That primitive is unchanged and still has eleven writer call sites:

| File | Lines | Syscall |
|---|---|---|
| `src/os/syscalls_time.c` | 101 | `nanosleep` rem (the sibling of the fixed `clock_nanosleep`) |
| `src/os/syscalls_sync.c` | 157, 189, 190 | `rt_sigprocmask` oldset, `get_robust_list` |
| `src/os/syscalls_stat.c` | 116, 246 | stat/statx image copyout |
| `src/os/sigact.c` | 272, 349, 426, 547 | `sigaction` old, `sigaltstack` old, `rt_sigpending`, sigset |
| `src/os/sigframe.c` | 301 | signal frame push |

Each of these exhibits the exact interleaving the audit describes (invalidate, unlocked write, SC succeeds). The targets are small kernel-ABI structs that are unlikely LL/SC words in practice, so the residual exposure is low, but the invariant "every syscall copyout commits under `sc_lock`" is not established and the racy primitive remains exported.

Test note: `t_sc_copyout_llsc` validates that a same-value copyout clears the reservation in a single thread. It does not exercise the cross-thread interleaving the audit asked for; it is a property test, not a race regression.

### M64-R3-2 — Single-precision directed rounding: REGRESSION

The finite-operand math is sound. For two binary32 operands, the binary64 sum `qd` is either exact or loses only an absorbed small operand; because double rounding is monotonic, `sign(qd - r)` equals `sign(exact - r)` whenever `qd != r`, and I verified that `qd == r && exact != r` implies `qd == a`, so the `qd == (double)a` absorbed test is the correct discriminator. The twelve new cases (1.0f ± 2^-126 under RM 0..3, both signs) are the right coverage for the audit's complaint.

The regression is at `src/interp/fp.c:678`. The earlier special-case block (`fp.c:574-594`) returns early only for opposite-sign infinities; a single infinite operand falls through. Trace `ADD.S` with `a = +Inf`, `b = -1.0f`:

1. `r = +Inf`, `sb = -1.0`, `qd = +Inf`, so `qd == (double)a` and `sb != 0.0` is true.
2. `q = nextafterl(+Inf, -INFINITY)` = `LDBL_MAX`.
3. `fp_adj_f(+Inf, LDBL_MAX, rm)` (`fp.c:280`): RZ gives `nextafterf(Inf, 0) = FLT_MAX`; RM gives `FLT_MAX`; RN and RP give `+Inf`.
4. `fp_inexact(ctx, rf, q)` (`fp.c:196`): `isinf(rf)` or `isinf((float)q)` is true and `isinf(q)` is false, so it raises **Overflow and Inexact in all four modes**.

Mirror cases: `a = -Inf, b = +1.0f` (and `SUB.S` with the sign flipped) produce `-FLT_MAX` under RZ/RP and the same spurious flags. Before this commit `q` was `(long double)a + b = Inf == r`, so no flag was raised and the result was correct. Expected behavior is `±Inf`, no flags, in every mode. Because the default mode RN is affected via FCSR cause/flag bits, any guest that polls `fetestexcept` or has an enabled Overflow trap after an infinity-involving add will misbehave, and the `--difftest` DBT parity gate will diverge on FCSR if the DBT emits a native `FADD` for this opcode.

Fix: guard the absorbed branch on a finite reference, for example

```c
q = (isfinite(qd) && qd == (double)a && sb != 0.0)
        ? nextafterl((long double)r, sb > 0.0 ? INFINITY : -INFINITY)
        : (long double)qd;
```

and add cases `{+Inf, -1.0f}`, `{-Inf, +1.0f}` for ADD and SUB across RM 0..3 expecting `±Inf` with `fcsr == rm`.

### M64-R3-3 — Vectored I/O single call: VERIFIED

- `mips_sc_vec` (`src/os/syscalls_sync.c:300`) rejects `iovcnt > IOV_MAX` before any allocation, so the `calloc` path is bounded to 1024 entries and `iovcnt * step` cannot overflow.
- One host `readv`/`writev`/`preadv`/`pwritev` call is issued with the complete vector; the 64-entry stack fast path is fixed-size (no VLA), and the heap path is `calloc`-zeroed so `l2a_vec_free` is NULL-safe. All allocation-failure branches free consistently.
- The aggregate cap mirrors Linux `MAX_RW_COUNT` truncation: later entries are shortened to zero rather than the request being rejected, which is what the kernel does in `import_iovec`.
- `t_vec_single_call` checks 65 iovecs produce exactly one 520-byte datagram on a `SOCK_DGRAM` socketpair and that no second datagram follows. That is the audit's precise scenario.

### M64-R3-4 — Partial readv copyout accounting: VERIFIED

`l2a_vec_copyout` (`src/os/syscalls_sync.c:242`) returns `committed` when a later destination fails revalidation and `-EFAULT` only when `committed == 0`. The unit test covers both branches plus the all-good path. One inherent limitation is unchanged and not a regression: bytes the host already produced for the faulted entries are consumed from the fd and dropped, whereas a Linux pipe read would leave them queued. That is a property of the staging design, not of this fix.

### M64-R3-5 — Remove `fp_adj_d`: VERIFIED

Definition and declaration removed; repository grep over `src` and `tests` finds no remaining reference.

### M64-R3-6 — Unaligned-access comments: VERIFIED with a wording nit

The header (`src/interp/unaligned.c:7-14`) now states the implemented endian-specific spans and matches the function-level comment at `unaligned.c:185-189` word for word, so the contradiction is gone. Nit: the sentence "the LE canonical pair does not compose a full doubleword" is only true if "canonical pair" means offsets (0,7), which the header no longer defines. Under the implemented LE rule, the LE-native pair (LDL at +7, LDR at +0 of the unaligned address) does compose a full doubleword; I traced it for k=0 and k≥1. The audit asked for the correct pair offsets to be stated explicitly, and they are not.

## Hygiene and Curated C11

- No `#include "*.c"` anywhere in `src` or `tests`.
- All `.c/.h/.S` files are ≤ 900 lines; the largest are `src/vm/vm_file.c` (898) and `src/dbt/dbt.c` (897). `syscalls.c` is below 850 after the split.
- No VLAs introduced (fixed 64-entry stack arrays plus `calloc`). `_Thread_local` is a C11 keyword and does not violate the `<threads.h>` ban. `static inline` in `host_compat.h` is the right fix for `-Wunused-function` in the new TU.
- `snprintf` with bounds throughout the test file; no banned string functions.
- The new test is wired into `tests/parity_suite.sh` T0 with a build-failure row, so a failing compile is reported rather than silently skipped.

## Summary

| Item | Status | Note |
|---|---|---|
| M64-R3-1 | PARTIAL | Correct helper and lock discipline; 11 `guest_range(write=1)` writers still commit unlocked, including `nanosleep` rem |
| M64-R3-2 | REGRESSION | Finite cases correct; `±Inf ± finite` now returns `±FLT_MAX` under RZ/RM(RP) and raises Overflow+Inexact in all modes |
| M64-R3-3 | VERIFIED | Single host call, IOV_MAX bounded, Linux-style aggregate cap |
| M64-R3-4 | VERIFIED | Committed count returned; `-EFAULT` only when nothing committed |
| M64-R3-5 | VERIFIED | No remaining references |
| M64-R3-6 | VERIFIED | Header and function comment agree; "LE canonical pair" wording undefined |

## Newly discovered consequential follow-ups

1. **`fp.c:678` infinity regression (High).** Add `isfinite(qd)` to the absorbed-operand condition and extend `t_fp_swallow` with infinite-first-operand cases for ADD and SUB under all four modes. Re-run the DBT `--difftest` parity gate afterwards, since FCSR divergence on this path is likely if the DBT uses native `FADD`.
2. **R3-1 residue (Medium, bounded).** Migrate the eleven remaining `guest_range(write=1)` writers to `mips_sc_copyout` (or `l2a_commit_guest_write`), starting with `syscalls_time.c:101` for consistency with its already-fixed sibling, then make `guest_range` read-only or drop the `write` parameter so the racy contract cannot be reintroduced.
3. **R3-6 wording (Low).** Replace "the LE canonical pair" with the explicit offsets: on LE the composing pair is LDL +7 / LDR +0 relative to the unaligned address; on BE it is LDL +0 / LDR +7.
