# Round-5 Post-Remediation Verification — `i686rt` @ `b34568a`

**Scope and method.** Static inspection only of commit `b34568a` (`HEAD` of `/Users/angerman/Projects/zw3rk/i686rt`), 4 tool turns, no build, tests, Docker, or QEMU. Line numbers refer to the files as of `b34568a`.

**Headline.** All 11 items were addressed in code. 6 are fully VERIFIED, 5 are PARTIAL. No item is NOT FIXED. One PLAUSIBLE regression risk (R5-1 f64 path) and one residual signed-overflow (R5-9) need a follow-up. All touched files are under 900 lines.

## Summary table

| Item | Status | Residual |
|---|---|---|
| I686-R5-1 | PARTIAL | f32 path fixed; f64 `default:` branch compares against `0.0L`; no rounding tests added |
| I686-R5-2 | VERIFIED | stale header comment in `emit_sse2.c:22` |
| I686-R5-3 | PARTIAL | interpreter enforced; DBT path not evidenced in diff; deny-list, not allowlist |
| I686-R5-4 | VERIFIED | always heap-stages payloads (perf, not correctness) |
| I686-R5-5 | PARTIAL | code fixed; requested partial-rights test absent |
| I686-R5-6 | VERIFIED | — |
| I686-R5-7 | VERIFIED | poll-then-nonblocking is racy against concurrent readers (minor) |
| I686-R5-8 | PARTIAL | code fixed; requested injected-failure test absent |
| I686-R5-9 | PARTIAL | `rem_s * 1000LL` can still overflow signed |
| I686-R5-10 | VERIFIED | `lease_valid` still duplicated (trivial) |
| I686-R5-11 | VERIFIED | Darwin wrappers called with `ws=NULL` → 30 s poll ceiling on blocking ops |

## Per-item evidence

### I686-R5-1 — SSE directed rounding double-step — **PARTIAL**
- **f32 path fixed.** `src/interp/h_sse.c:82-98`: after `f = (float)d`, steps with `nextafterf` only when `(double)f` lies on the wrong side of `d` for `rc` 1/2/3. This removes the "already-correct result bumped another ULP" defect; the old unconditional bump block (old lines 94–117) is deleted. The new check runs before the `mag` overflow test, and `nextafterf(±inf, …)` correctly yields `±FLT_MAX` for RD/RZ.
- **f64 path.** `src/interp/h_sse.c:264-300`: recomputes an `exact` in `long double` for `FOP_ADD/SUB/MUL/DIV` and steps `r` with `nextafter` when on the wrong side.
- **Risk (PLAUSIBLE, unconfirmed):** `h_sse.c:272` initialises `exact = 0.0L` and `h_sse.c:283` has `default: break;`. If `fop_kind` has any member beyond ADD/SUB/MUL/DIV (e.g. SQRT/MIN/MAX) that reaches this function with `rc != 0`, then `rr != exact` is true for any non-zero result and RD will step a positive result downward. Confirm the enum; if other kinds exist, guard the block with `k <= FOP_DIV` or skip when `exact` was not computed.
- **Platform note:** on Darwin arm64 `long double == double`, so the f64 verification is a no-op there (harmless, not helpful). It is only meaningful on the musl AArch64 target (IEEE quad).
- **Tests:** the finding asked for bit-exact cases for all rounding modes. `tests/unit/test_l5b_cases.c` changes only touch MXCSR; no rounding test added.

### I686-R5-2 — LDMXCSR reserved bits — **VERIFIED**
- `src/interp/h_sse_int.c:650-654`: `if ((v & ~0xFFFFu) != 0U) return I686_EXIT_FAULT;` runs **before** `sse_set_mxcsr` and before `sse_done` advances EIP. Memory read happens first (correct fault ordering).
- `src/dbt/emit_sse2.c:384-388`: LDMXCSR now returns `-1` (bail to interpreter oracle); the masking `sse_and_ffff` path is removed. STMXCSR fast path retained.
- `tests/unit/test_l5b_cases.c:363-375`: expects `run(&in) != 0`, MXCSR unchanged (`0x1F80`), EIP unchanged; follow-up valid-load/STMXCSR round-trip at `:376-388`.
- **Nit:** `src/dbt/emit_sse2.c:22` header still says "reserved bits masked on load".

### I686-R5-3 — LOCK on shifts/rotates — **PARTIAL**
- `src/interp/interp.c:305-335` `interp_lock_illegal_shift()` covers all 36 ROL/ROR/RCL/RCR/SHL/SHR/SAR forms. Enforced before registry dispatch in `i686_interp_step` (`interp.c:419-424`) and in the run loop (`interp.c:598-611`, with `i686_deliver_sync` SIGILL delivery).
- `src/interp/h_shift.c:127-135` and each handler: `sh_lock_check()` runs **before** the `cnt == 0` early-out, so `F0 D1 20` with zero count faults. All `sh_lock_enter/leave`, `__atomic_*` CAS loops, and split-lock externs removed (file shrinks 381 lines).
- `src/x86/decode.c:636-637`: comment only; decode preserves `pfx_lock`.
- **Gaps:** (1) The DBT is untouched. The removed comment in old `h_shift.c` said "concurrent LOCK peers on sibling threads (DBT or interpreter)", which implies the DBT had its own LOCK-shift path. Nothing in this commit shows `src/dbt/` refusing `pfx_lock` on shift opcodes; the finding asked for enforcement in *both* engines. (2) This is a shift/rotate deny-list, not the requested memory-destination allowlist, so other illegal LOCK forms (register destination on legal ops, LOCK MOV, etc.) remain unenforced.

### I686-R5-4 — Socket marshalling via checked copies — **VERIFIED**
- `src/os/sys_sock_msg.c:167-216`: iovec array bounds-checked (`:167`), each descriptor snapshotted with `i686_copy_from_guest` (`:180`), per-iov bounds (`:190`), cleanup on failure (`:184,:193,:216`).
- `:236-238` msghdr copied; `:257-265` name staged; `:281-290` control staged; `:384-417` payload heap-staged with `i686_copy_from_guest` for send; `:430-443` `msghdr_free` central release; recvmsg copy-back via `i686_copy_to_guest` with `-EFAULT` on failure (`:516-519`, `:542-544`).
- Host `sendmsg/recvmsg` never see guest pointers now. Note: staging is unconditional, not "where A2 requires it"; acceptable for correctness, measurable cost for large iovecs. The six near-identical cleanup ladders at `:360-417` are a DRY candidate for the backlog.

### I686-R5-5 — Partial SCM_RIGHTS delivery — **PARTIAL (code VERIFIED, test missing)**
- `src/os/sys_sock_msg.c:94-140`: on non-fit, sets `MSG_CTRUNC` (`:96`), computes `fit` complete `int32` fds that fit after the 12-byte header (`:105-112`), emits header + `fit` fds (`:114-128`), closes only `fds[fit..nfds)` (`:131-134`), or all when none fit (`:136-139`). Matches the 16-byte-capacity scenario (1 of 2 fds delivered).
- No partial-rights test added in this commit.

### I686-R5-6 — `msg_len` copyout counted on failure — **VERIFIED**
- sendmmsg `src/os/sys_sock_msg.c:602-611`: `i686_copy_to_guest` checked; returns `-EFAULT` if `n == 0`, else `n`; entry not counted.
- recvmmsg `:740-752`: same, `last = -EFAULT` only when `n == 0`, `break`.

### I686-R5-7 — recvmmsg timeout without SO_RCVTIMEO — **VERIFIED**
- `src/os/sys_sock_msg.c:684-736`: per-message remaining-time computed from a `CLOCK_MONOTONIC` deadline, `poll(POLLIN, rem_ms)` then `recvmsg` with `MSG_DONTWAIT`; EINTR surfaces as `-EINTR` when `n == 0`. `MSG_WAITFORONE` handled at `:690-691`. No `setsockopt` calls remain.
- Minor: `:727-731` both branches of `prc == 0` set `MSG_DONTWAIT` (dead if/else). Poll-then-nonblocking can return `-EAGAIN` early if a concurrent reader drains the socket between poll and recvmsg.

### I686-R5-8 — munmap untrack-before-reserve — **PARTIAL (code VERIFIED, test missing)**
- `src/rt32/rt32_vm_mmap.c:267-281`: preflight `i686_vm_file_can_replace` (`:270`), then `rt32_vm_reserve_prot_none` (`:274`), then `i686_vm_file_untrack_map` (`:279`). Reservation failure now returns with tracking intact.
- Residual: if untrack fails after a successful reserve (`:279-281`), the host mapping is already PROT_NONE while metadata survives; the preflight is meant to make that unreachable but it is not a transactional commit. No injected-failure test.

### I686-R5-9 — time64 signed-shift UB — **PARTIAL**
- `src/os/sys_sock_msg.c:629-642`: words assembled as `uint64_t` then cast; `:651-654` rejects negative `tv_sec`; `:656-679` nanosecond carry guarded (`INT64_MAX` check) and deadline addition saturated.
- **Residual overflow:** `:711` `rem_ms = rem_s * 1000LL + rem_ns / 1000000LL;`. With a saturated deadline (`tv_sec = INT64_MAX`), `rem_s ≈ 9.2e18` and the multiply overflows `int64_t` (UB) before the `INT_MAX` clamp at `:712`. Clamp `rem_s` (e.g. `if (rem_s > INT_MAX / 1000) rem_ms = INT_MAX; else …`) before multiplying. Boundary tests for `INT64_MAX`/negative encodings were requested and not added.

### I686-R5-10 — Darwin wait helper duplication — **VERIFIED**
- `src/os/backend.h:274-279` declares `i686_darwin_wait_fd` under `__APPLE__`; defined at `src/os/backend_darwin_io.c:48`; the duplicate in `backend_darwin_net.c` is removed (`:84-85` comment) and all 4 net callers use the shared helper (`:119,:140,:164,` recvfrom). Repository-local, no cross-repo extraction. `lease_valid` remains duplicated in both TUs (trivial).

### I686-R5-11 — Socket backend bypass — **VERIFIED**
- `src/os/sys_sock.c:112,131,146,178,180,228,250,279` route socket/bind/connect/accept4/socketpair/sendto/recvfrom through `rt_host_*`; getpeername/getsockname/shutdown/setsockopt/getsockopt likewise. The `hs_accept4` ENOSYS shim and the "darwin is never a runtime host" comment are deleted (`:99-103`).
- **Behavior change to watch (Darwin only):** handlers pass `NULL, 0U` for `ws/expected_seq`, so `i686_darwin_wait_fd(fd, …, NULL, 0, 30000)` imposes a 30 s poll ceiling on blocking `connect/accept/sendto/recvfrom`; a guest `accept()` idle for >30 s now returns whatever the wrapper maps `w == 0` to, instead of blocking. Also Darwin `rt_host_accept4` ignores `linux_flags` (`backend_darwin_net.c:140` region, `(void)linux_flags;`), so `SOCK_NONBLOCK/CLOEXEC` are silently dropped where previously `ENOSYS` was returned. Not a Linux-host regression.

## Hygiene

**Line limits (≤ 900):** all 13 touched files pass. Largest: `src/interp/h_sse.c` 855, `src/interp/interp.c` 802, `src/interp/h_sse_int.c` 790, `src/os/sys_sock_msg.c` 767. (`sys_stat.c` at 898 is untouched and remains the repo high-water mark.)

**Curated C11:** no `sprintf/strcpy/strcat`, `_Generic`, `<threads.h>`, `alloca`, or VLAs introduced (grep hits for `threads.h` are the project's own `os/threads.h`). Block-scope `extern int i686_deliver_sync(...)` at `interp.c:603` is legal but should move to a header. `nextafterf/fabsl/offsetof/INT_MAX` require `<math.h>/<stddef.h>/<limits.h>`; includes not verified since no build was run.

## Recommended follow-ups (priority order)
1. **R5-1:** confirm `fop_kind` membership; guard the `long double` verification so it never compares against an uncomputed `exact = 0.0L`.
2. **R5-9:** clamp `rem_s` before `* 1000LL` at `sys_sock_msg.c:711`.
3. **R5-3:** show DBT refusal of `pfx_lock` on shift/rotate opcodes (or confirm the DBT already bails on `pfx_lock` for those forms).
4. **Tests:** add the requested cases for R5-1 (rounding modes), R5-5 (partial SCM_RIGHTS), R5-8 (injected reserve failure), R5-9 (`INT64_MAX`/negative).
5. **Nits:** `emit_sse2.c:22` comment; dead if/else at `sys_sock_msg.c:727-731`; Darwin 30 s ceiling and dropped `accept4` flags under R5-11.
