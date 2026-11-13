Now I have the complete picture. Here's my review.

---

## Round-12 Remediation Review — Commit `04cfaab`

### P32-R12-1: `statx` reserved holes not zeroed — **VERIFIED**

Both paths are fixed with an upfront `memset`:

- **`dyn_put_statx`** (`src/os/syscalls_dyn.c:123`): `memset(ppc32_guest_ptr(ctx, va), 0, DYN_STATX_SIZE)` zeroes all 256 bytes before the field-by-field `ppc32_st*be` writes. All spare/reserved holes (`__spare0` at 30-31, `__reserved` at 76-79/92-95/108-111/124-127, `__spare2+` at 152-255) are now guaranteed zero.
- **`dyn_put_stat_fallback`** (`src/os/syscalls_dyn.c:327`): Identical treatment. The fallback synthesizes statx from `struct stat`, same zeroing.
- Both are gated by a prior `ppc32_range_ok(va, DYN_STATX_SIZE)` check (lines 120-122 and 324-326), so the `ppc32_guest_ptr` dereference is safe.

The approach differs from the report's suggested local-buffer+`ppc32_vm_copyout_safe` but is functionally correct — the guest is blocked during syscall emulation, so there's no torn-read risk.

### P32-R12-2: `EDEADLK` not translated PPC 58 vs host 35 — **VERIFIED**

Both lock arms are patched:

- **F_GETLK/F_SETLK/F_SETLKW** (`src/os/syscalls_file.c:194`): `return (errno == EDEADLK) ? -58L : -(long)errno;`
- **F_GETLK64/F_SETLK64/F_SETLKW64** (`src/os/syscalls_file.c:233`): Same translation.

Both arms are inside `#ifdef __linux__` guards (the non-Linux paths return `-ENOSYS`), which is correct since the host `EDEADLK=35` vs PPC `EDEADLK=58` divergence only exists on Linux/aarch64. The hardcoded `58L` is the PPC `EDEADLK` from `asm-powerpc/errno.h`.

### P32-R11-6: DBT/hostfault store-fault DSISR direction — **VERIFIED**

Two independent detection paths, appropriate for their different execution contexts:

**Interpreter faults** — `src/os/hostfault.c:131-153`: Manual opcode decode in the `sigsetjmp` return path (normal C context, not signal context). Covers:
- D-form stores: opcd 36-39 (stw/stwu/stb/stbu), 44-45 (sth/sthu), 47 (stmw), 52-55 (stfs/stfsu/stfd/stfdu)
- X-form stores (opcd=31): XO 150 (stwcx.), 151 (stwx), 183 (stwux), 215 (stbx), 247 (stbux), 407 (sthx), 439 (sthux), 661 (stswx), 662 (stwbrx), 663 (stfsx), 695 (stfsux), 725 (stswi), 727 (stfdx), 759 (stfdux), 918 (sthbrx), 983 (stfiwx), 1014 (dcbz)
- SPE stores (opcd=4): sub-opcodes 800 (evstdd), 802 (evstdh)

Guard `fault_addr != nip` (line 134) prevents decoding at the faulting address (instruction-fetch fault). `ppc32_range_ok(rc->nip, 4U)` bounds-checks before the read.

**DBT JIT-exit faults** — `src/dbt/dbt.c:707-724`: Uses `ppc_decode` + `dbt_store_shape` + explicit `PPC32_OP_STWCX` check. Guard `ctx->fault_addr != ctx->nip && ctx->nip >= 0x1000U && ctx->nip <= 0xFFFFFFFCU`.

The `#include "os/convert.h"` addition to hostfault.c (line 25) is required: it declares `ppc32_ld32be` and `ppc32_range_ok` used at lines 135-136.

### Newly introduced issues

**None critical.** One latent inconsistency and one theoretical edge:

1. **`dbt_store_shape` missing `PPC32_OP_STSWX`** (latent, not reachable): `dbt_store_shape` handles `STSWI` (XO 725) but not `STSWX` (XO 661), while hostfault.c's manual table covers both. However, `STSWX` is never JIT-emitted — the DBT falls back to `interp_step`, whose faults go through the hostfault.c signal path (which does cover 661). Not a practical bug today, but if the DBT ever adds native emission for `stswx`, the dbt.c fault path would misclassify it as a load.

2. **`ppc32_ld32be` after longjmp with `hf_armed=0`** (theoretical): At hostfault.c:136, `ppc32_ld32be(rc, rc->nip)` reads guest memory. If the instruction page at NIP were unmapped (despite the `ppc32_range_ok` bounds check passing), a nested SIGSEGV with `hf_armed=0` would `_Exit`. The `fault_addr != nip` guard prevents the instruction-fetch-fault case, and for data-access faults the PC page is mapped (the CPU just executed from it). Not practically reachable.

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None in changed files |
| `.c` includes | None |
| File line counts | `syscalls_dyn.c` 547, `syscalls_file.c` 406, `hostfault.c` 171, `dbt.c` 739 — all <= 900 |
| Banned functions | No `sprintf`/`strcpy`/`strcat`/Annex K |

### Summary

| Item | Verdict |
|---|---|
| P32-R12-1 (statx reserved holes) | **VERIFIED** — `memset` zeroes all 256 B before field writes, both paths |
| P32-R12-2 (EDEADLK 35→58) | **VERIFIED** — both fcntl lock arms translate, `#ifdef __linux__` scoped |
| P32-R11-6 (store-fault direction) | **VERIFIED** — hostfault.c covers interpreter path, dbt.c covers JIT exit path |
| New regressions | **None** |
| C11 compliance | **Clean** |
