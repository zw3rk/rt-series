Here is the complete review of commit `c5e5f7e` against the Round-12 defect report.

---

## A32-R12-1: Darwin `translate_open_flags` mis-maps two guest flag bits — **VERIFIED**

**Defect**: `sys_priv.h:656-657` OR'd guest `0x10000` (ARM `O_DIRECT`) into host `O_DIRECTORY` and guest `0x20000` (ARM `O_LARGEFILE`) into host `O_NOFOLLOW`, using x86 numbering.

**Fix** (`sys_priv.h:656-657`): Removed the extra `| 0x00010000U` and `| 0x00020000U` terms. Now maps only `0x4000 -> O_DIRECTORY` and `0x8000 -> O_NOFOLLOW`, matching the ARM32 ABI. `O_DIRECT` and `O_LARGEFILE` are silently dropped, which is correct — `O_DIRECT` requires aligned I/O the translator doesn't guarantee, and `O_LARGEFILE` is a no-op on 64-bit hosts. The `#else` Linux passthrough at line 661 remains untouched (arm64 kernel accepts arm32 values natively).

**No new bugs introduced.** The remaining Darwin flag map covers all common ARM32 `O_*` bits correctly.

---

## A32-R12-2: `faccessat` ignores the guest flags argument — **VERIFIED**

**Defect**: `os_sys_thread_sig.c:698` hard-coded `gflags = 0U` for `ARM_NR_faccessat`, and the non-`at2` fallback at `:715` called `faccessat(..., 0)`, dropping `AT_SYMLINK_NOFOLLOW`.

**Fix** (`os_sys_thread_sig.c:700`):
```c
uint32_t gflags = (nr == ARM_NR_faccessat2) ? a3
    : ((nr == ARM_NR_faccessat && (a3 & ~(0x100U | 0x200U)) == 0U) ? a3 : 0U);
```
For `faccessat`, forwards `a3` only when it contains exclusively recognized flag bits (`AT_SYMLINK_NOFOLLOW = 0x100`, `AT_EACCESS = 0x200`); falls back to `0U` if `a3` has other bits (which protects against stale register contents, since the kernel `faccessat` syscall is formally 3-argument). The fallback call at line 718 now passes `hflags` instead of `0`.

**No new bugs introduced.** The guard `(a3 & ~(0x100U | 0x200U)) == 0U` is appropriately defensive. The `FAIL_EINVAL_IF` validation at line 701-702 still catches invalid combinations. The `RESOLVE_AT` and `hflags` translation are consistent across both `faccessat` and `faccessat2` paths.

---

## A32-R12-3: Darwin `futex_darwin_wait` treats relative timeout as absolute — **VERIFIED**

**Defect**: `os_sys_thread_sig.c:251-270` read a guest relative timeout into `end_m`, subtracted `CLOCK_MONOTONIC` now, producing a negative delta (and instant `-ETIMEDOUT`) for any typical relative timeout against a large uptime.

**Fix** (`os_sys_thread_sig.c:228-275`): Three changes:

1. **Signature** (`os_sys_thread_sig.c:228`): Parameter renamed from `basic_op` to `op` — receives the full `a1` (raw futex op including `FUTEX_CLOCK_REALTIME` bit). The callee now extracts `basic_op = op & 0x7FU` at line 231. Call site at `os_sys_sig_time.c:832` updated to pass `a1` instead of pre-stripped `basic_op`. Header declaration at `sys_priv.h:777` matches.

2. **Timeout validation** (`os_sys_thread_sig.c:257`): Adds `end_m.tv_sec < 0 || end_m.tv_nsec < 0 || end_m.tv_nsec >= 1000000000L` check, returning `-EINVAL`. Correct — matches Linux kernel validation.

3. **Relative vs absolute dispatch** (`os_sys_thread_sig.c:258-270`):
   - `FUTEX_WAIT` (`basic_op == 0U`): Relative timeout → `nanosleep(&end_m, NULL)` directly. Correct.
   - `FUTEX_WAIT_BITSET` (`basic_op == 9U`): Absolute timeout → subtracts current clock, then sleeps the delta. Uses `op & 0x100U` (`FUTEX_CLOCK_REALTIME`) to select `CLOCK_REALTIME` vs `CLOCK_MONOTONIC`. Correct.

**No new bugs introduced.** The `now_m`, `ds`, `dn` variables declared at block scope are only used in the `else` branch — valid C11, no dead-store issue. The reuse of `end_m` for the computed delta in the absolute path (lines 266-268) is fine since the original value is no longer needed after subtraction.

---

## Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None |
| `.c` includes | None |
| File sizes | `os_sys_sig_time.c`: 843, `os_sys_thread_sig.c`: 899, `sys_priv.h`: 831 — all under 900 |
| Forbidden functions | None (`snprintf`-style used throughout) |
| Fixed-width types | All uses are `uint32_t`, `long`, `time_t` — compliant |

---

## Summary

All three items **VERIFIED**. No regressions, no newly introduced bugs, C11 compliance intact. The `futex_darwin_wait` signature change (passing full `op` instead of pre-stripped `basic_op`) is a clean improvement that lets the callee access the `FUTEX_CLOCK_REALTIME` flag for correct clock selection on `FUTEX_WAIT_BITSET`.
