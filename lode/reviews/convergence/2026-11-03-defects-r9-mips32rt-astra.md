# Round-9 Deep-Dive 3 — VM / Soft-TLB / Checked Copy / `fork` COW / ELF32-Auxv Audit

Static, read-only. No files created, modified, or executed.

## Summary

| ID | Location | Issue | Fix |
|---|---|---|---|
| M32-R9-1 | `main.c:272`, `proc.c:371` | Regime never set | Init A1/A2 on load |
| M32-R9-2 | `vm.c:833`, `mem.c:539` | Exec write, no SMC flush | Invalidate JIT range |
| M32-R9-3 | `syscall_min.c:196` | `write`/`uname` TOCTOU | Stage via checked copy |
| M32-R9-4 | `vm_mmap.c:60` | Bad `prot` masked | Reject with `EINVAL` |
| M32-R9-5 | `elf32.c:294` | ABIFLAGS ignored | Parse `fp_abi` |

### M32-R9-1 — Production `vm_regime` stays `UNSET`, DBT bypasses sub-page guards

`mips32_vm32_init` is called only from `guest_mem_init` ([mem.c:202](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:202)), which production never calls. `run_guest` ([main.c:272](/Users/angerman/Projects/zw3rk/mips32rt/src/main.c:272)) calls `rt32_vm_init` (which never touches `vm_regime`) then `elf_load`/`stack_setup`; `vm_regime` remains `0`. `execve` ([proc.c:371](/Users/angerman/Projects/zw3rk/mips32rt/src/os/proc.c:371)) has the same omission.

Repro: boot on a 16 KiB host, inspect `ctx->vm_regime == 0`. `dbt_compile` falls back only on `== A2` ([dbt.c:657](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:657)), so it emits direct `[xG,wAddr]` accesses that bypass 4 KiB sub-page guards.

Fix: call `mips32_fixade_init` + `mips32_vm32_init` in `run_guest` after `rt32_vm_init`, and in `execve` after `rt32_vm_reset_for_exec`; or move it inside `rt32_vm_init`.

### M32-R9-2 — Guest stores to `PROT_EXEC` never invalidate translated code

`rt32_vm_copy_to` ([vm.c:833](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm.c:833)) commits via `mips_guest_store_commit` (LL bump only) with no `vm_invalidate_jit`. `mips_store_locked` ([mem.c:539](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:539)) is identical.

Repro: map `RWX`, let DBT compile a block, `read(fd, exec_va, n)` new bytes over it, re-execute. `smc_version` never bumps, stale block runs. Violates SPEC 2.2/Hardening ("guest writes to translated pages").

Fix: after a successful store, if any overlapped VMA has `PROT_EXEC`, call `vm_invalidate_jit(ctx, va, va+len)` (or the weak `mips32_dbt_invalidate_range`).

### M32-R9-3 — `write`/`uname` use unchecked `mips32_guest_ptr` after check

`sc_write` checks `range_ok(READ)` ([syscall_min.c:193](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:193)) then snapshots `host_buf = mips32_guest_ptr(...)` ([syscall_min.c:196](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:196)) and calls host `write()` lock-free. `sc_uname` ([syscall_min.c:278](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:278)) is the same shape.

Repro (threads): A `write(fd, buf, 1M)` races B `munmap(buf)`; the host read faults → translator `SIGSEGV` instead of guest `-EFAULT`. `sc_read` already stages via `malloc` + `copy_to`; `write` must mirror it (`copy_from` to staging, then host `write`).

### M32-R9-4 — `mmap` silently masks illegal `prot` bits

`vm_mmap2_ext_locked` ([vm_mmap.c:60](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:60)) never validates `prot`, recording `prot & 0x7U`. `mprotect` rejects `prot & ~0x7U` ([vm_mmap.c:313](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:313)).

Repro: `mmap(0, 0x1000, 0x8, MAP_PRIVATE|MAP_ANON, -1, 0)` succeeds instead of `-EINVAL`.

Fix: `if (prot & ~0x7U) return -EINVAL;` at function entry.

### M32-R9-5 — `PT_MIPS_ABIFLAGS` / `EF_MIPS_FP64` ignored, `FR` pinned to 0

Loader admits `e_flags` ABI/NAN2008 ([elf32.c:215](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/elf32.c:215)) but never scans `p_type == 0x70000003`, and pins `fr_mode = 0U` ([elf32.c:747](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/elf32.c:747), [proc.c:413](/Users/angerman/Projects/zw3rk/mips32rt/src/os/proc.c:413)). SPEC 2.1 requires init from `e_flags` plus `.MIPS.abiflags`.

Repro: an FP64/`FR=1` O32 binary runs with `FR=0` pair semantics → wrong `MTC1`/`MFHC1`/`LDC1` results.

Fix: parse the ABIFLAGS segment's `fp_abi`, set `fr_mode`/`nan2008` accordingly.

## Files with 0 bugs in this scope

`src/vm/vm32.h`, `src/vm/vm32.c`, `src/vm/vm_file.c` (dead helper, no live caller), `src/rt32/vm_priv.h`, `src/rt32/rt32.h`, `src/rt32/vm.c` VMA split/merge/`brk`/`mmap_cursor` logic, `src/rt32/vm_init.c`, `src/rt32/vm_darw.c`, `src/rt32/stack32.c` (16-byte alignment, `AT_*` set, `AT_RANDOM` correct), `src/rt32/host.c`, `src/mips32rt.h` (`mips32_range_ok` wrap check, `mips32_host_prot`), `src/os/fork.c` (host-`fork` COW with correct prepare/release, LL/pending/tid reset), `src/os/syscalls_priv.h`, `src/os/syscalls.c` copy helpers (lock-held, `-EFAULT`, endian-correct).

`mremap`/`madvise` have no guest syscall numbers and no dispatcher entries, so `rt32_vm_mremap` is unreachable from guests; its in-tree logic (fixed/overlap, shared/private paths, in-place extend) is sound. Not reported as a bug.

