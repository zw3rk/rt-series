# Verification report: rvrt commit `2b6759c` vs Round-6 defects RV-R6-1..5

Commit `2b6759c` is HEAD of `rvrt`. It touches exactly the three files the audit named. Evidence below is static diff reading only; no builds, tests, or emulation were run. All line numbers refer to the post-commit tree.

| ID | Severity | Status |
|---|---|---|
| RV-R6-1 | HIGH | **VERIFIED** |
| RV-R6-2 | HIGH | **VERIFIED** |
| RV-R6-3 | MEDIUM | **VERIFIED** |
| RV-R6-4 | LOW | **VERIFIED** |
| RV-R6-5 | LOW | **VERIFIED** |

## RV-R6-1 — Division overwrote divisor before zero check: VERIFIED

The fix reorders every affected sequence so the compare against the original divisor happens before the divide writes `mdst`. The new order in all six sites is `MOVN x3,#0` then `CMP mr2,xzr` then `UDIV/SDIV mdst,mr1,mr2` then `CSEL mdst,x3,mdst,EQ`.

- RV32 DIV/DIVU: `src/dbt_emit_m.c:65-68` and `:72-75`
- RV64 DIV/DIVU: `src/dbt_emit_m.c:111-114` and `:117-120`
- RV64 DIVW/DIVUW: `src/dbt_emit_m.c:140-143` and `:147-150`

Why this is sound. AArch64 `MOVN`, `UDIV`, and `SDIV` do not write NZCV, so flags set by the compare survive through to the `CSEL`. The `-1` sentinel lives in scratch `x3`, and guest registers map to `x10..x17` via `rv_dbt_dst_gpr` and `rv_dbt_get_gpr` at `src/dbt_emit_fp.h:418-445`, so neither `mr1`, `mr2`, nor `mdst` can alias `x2`/`x3`. The `mdst == mr2` alias case now works because the divisor is consumed by the compare before it is clobbered. REM/REMU/REMW were not in scope and were already safe since they divide into scratch `x2` first.

Not covered: no new regression test for the `div a1,a0,a1` alias case was added in this commit. That is a test-coverage gap, not a correctness gap.

## RV-R6-2 — `update_header()` used RV64 offsets for RV32: VERIFIED

`update_header` now branches on `rv_space_is32` at `src/linux/message.c:520`.

- Name length offset is `4` on RV32 and `8` on RV64 at `src/linux/message.c:521`, used for the read at `:523` and the write-back at `:529-531`. This removes the RV32 bug where the iovec pointer at `+8` was read and clobbered as a length.
- RV32 `msg_flags` written as 4 bytes at `+24` at `src/linux/message.c:535`, and `msg_controllen` as 4 bytes at `+20` at `:538`, then early return.
- RV64 path unchanged at `+48` and `+40` at `src/linux/message.c:542-546`.

These match the RV32 ILP32 `msghdr` layout of 28 bytes that `load_message` already read at `src/linux/message.c:102-113`. No other RV64-only header offset remains in the file.

## RV-R6-3 — Control-message codec hardwired to 64-bit layout: VERIFIED

Both directions are now width-aware.

- **Decode** (`parse_rights`): `header_size` 12/16, `cmsg_level` at `+4`/`+8`, `cmsg_type` at `+8`/`+12`, and alignment mask 3/7 at `src/linux/message.c:229-233`. `cmsg_len` is read as `le32` on RV32 at `:236`, which fixes the original rejection of a valid single-fd `SCM_RIGHTS` record. Minimum length, fd count, trailing-record check, and fd array base all use the selected header size at `:234-249`.
- **Encode** (`copy_control`): descriptor capacity uses `header_size` at `src/linux/message.c:445-449`, fd slots are written at `header_size + 4*i` at `:461`, and the header is emitted as 4-byte `cmsg_len` plus level/type at `+4`/`+8` on RV32 at `:486-494`, versus the unchanged 8-byte form on RV64 at `:495-504`. Padded `msg_controllen` uses the width-appropriate mask at `:508`.

The audit's second repro, zero capacity when an RV32 guest supplies the normal 16-byte `CMSG_SPACE(int)` buffer, is resolved since 16 is now greater than the 12-byte header. Multi-record control buffers remain explicitly out of scope with `EOPNOTSUPP`, as before.

## RV-R6-4 — Duplicated `/dev/urandom` sequence: VERIFIED

A file-local `fill_random` helper exists at `src/loader/stack.c:33-50` and preserves the `EINTR` retry, short-read detection, and close-error check verbatim from the old inline code. Both builders call it at `src/loader/stack.c:123` and `:197`. The helper reports through `stack_error` itself, so the callers' plain `return false` still yields a populated error buffer. The helper stays inside `rvrt`, as the card required.

## RV-R6-5 — Dead `input_flags` field: VERIFIED

The field is removed from `guest_message_t` and both initializers at `src/linux/message.c:108-119`. A tree-wide `git grep input_flags` at this commit returns no hits, so nothing else referenced it.

## Summary

All five Round-6 rvrt findings are resolved in `2b6759c` with no regressions observed in the changed code. The commit message carries no agent attribution. The only remaining item is advisory: RV-R6-1 would benefit from a DBT regression case for destination/divisor aliasing and a zero quotient, and RV-R6-2/3 from the canary-based RV32 `recvmsg` test the card suggested. Neither was requested as part of this verification.
