# A32 Round-9 Deep-Dive 3 — VM / Soft-TLB / Checked Copy / fork COW / ELF-Auxv-Stack

Static audit only. No files created, modified, or deleted. No builds or tests run.

## Summary

| ID | Location | Defect | Fix |
|---|---|---|---|
| A32-R9-1 | `os_sys_fs_arm.c:513` | `madvise` length `0` | Pass real length once |
| A32-R9-2 | `os_sys_sig_time.c:827` | `futex` uaddr unchecked | Add `range_ok` check |
| A32-R9-3 | `os_sys_thread_sig.c:157` | `iov` entries unchecked | Validate each buffer |
| A32-R9-4 | `gdb.c:515` | GDB write checks `READ` | Check `WRITE` instead |
| A32-R9-5 | `signals.c:75` | `guest_write` skips bump | Add `copyout_invalidate` |
| A32-R9-6 | copyout paths | `EXEC` writes skip SMC flush | Invalidate JIT on `EXEC` |
| A32-R9-7 | `vm32.c`, `vm_file.c` | Unmap/remap keeps reserves | Bump all spanned buckets |
| A32-R9-8 | `os_sys_fork_time.c:145` | Fork skips `PROT_NONE` | Snapshot all regions |
| A32-R9-9 | `os_sys_fork_time.c:222` | Fork raw `mprotect` on A2 | Use backend protect |
| A32-R9-10 | fork/clone paths | Exclusives survive fork | Clear reserves in child |
| A32-R9-11 | `elf32.c:114` | `e_flags` never checked | Validate EABI/float ABI |
| A32-R9-12 | `elf32.c:590` | kuser non-`EXEC` vs carve-out | Grant guest `EXEC` |
| A32-R9-13 | `stack32.c:118` | Stack clobbers without retire | Check overlap first |
| A32-R9-14 | `vm.c:209` | Split failure silent, diverges | Preflight, fail cleanly |
| A32-R9-15 | `vm.c:623` | Bad `mmap` prot accepted | Reject unknown prot bits |

## Defects

### A32-R9-1 — `madvise` probes with length `0`, then advises twice

`src/os/os_sys_fs_arm.c:513` calls `madvise(a32_guest_ptr(ctx, a0), 0U, (int)a2)`, then `src/os/os_sys_fs_arm.c:524` calls it again with `(size_t)a1`. The first call validates nothing about the range, and host advice happens before the VMA check at line 517. Repro: `madvise` with an invalid advice on an unmapped range returns `ENOMEM` instead of `EINVAL`; with a valid advice it issues two host calls. Fix: delete the first call, keep the VMA check, then issue one `madvise` with `(size_t)a1`.

### A32-R9-2 — Linux `futex` never validates the primary `uaddr`

`src/os/os_sys_sig_time.c:794` only rejects `a0 < 0x1000`. `src/os/os_sys_sig_time.c:827` then passes `a32_guest_ptr(ctx, a0)` straight to host `futex`. The `uaddr2` path at line 821 does check `range_ok`; the primary address does not. Repro: `futex(0x60000000-unmapped, FUTEX_WAIT, ...)` crashes the host instead of returning `-EFAULT`. Fix: `FAIL_EFAULT_IF(!a32_guest_range_ok(ctx, a0, 4U, PROT_READ | PROT_WRITE))` before the host call.

### A32-R9-3 — `translate_guest_iov` validates the array, not the buffers

`src/os/os_sys_thread_sig.c:147` checks the `iov` array itself, but lines 157-166 convert every `iov_base` with `a32_guest_ptr` after only a `< 0x1000` test. No per-entry `range_ok`, no `base + len` wrap check. Repro: `readv`/`writev`/`recvmsg` with an unmapped `iov_base` faults the host instead of returning `-EFAULT`. Fix: validate each entry for existence and wrap, with direction-appropriate `READ`/`WRITE` permission.

### A32-R9-4 — GDB `M` packet requires `READ` for a write

`src/gdb.c:515` gates a memory write with `PROT_READ`, then forcibly widens the host page to `RW`, writes, and invalidates JIT. A `WRITE`-only page fails the check despite being writable, and a read-only page passes it and gets written anyway. Repro: GDB write to a `PROT_WRITE`-only page is rejected; write to a read-only page succeeds. Fix: check `PROT_WRITE` at line 515.

### A32-R9-5 — `signals.c guest_write` skips reservation invalidation

`src/signals.c:75-82` checks `PROT_WRITE` and copies, unlike `src/os/sys_priv.h:695-705` which also calls `a32_vm32_copyout_invalidate`. Repro: `rt_sigaction` old-action store landing on a reserved line leaves a stale `STREX` able to succeed. Fix: bump reservations after the copy, matching the `sys_priv.h` helper.

### A32-R9-6 — Copyout to `PROT_EXEC` pages never invalidates JIT

`src/os/sys_priv.h:695 guest_write` and `src/interp/interp.c:121 i_store_bytes` bump reservations but never call `a32_jit_invalidate_range`. Direct-copy sites (for example `src/os/os_sys_thread_sig.c:448 llseek`, `src/os/os_sys_sock.c:70-71`, `src/os/os_sys_sig_time.c:196`) and host-direct writes (`readv`, `recvmsg`, `epoll_wait` result buffers) do neither. Repro: make an `EXEC` page writable, overwrite code through a syscall or interpreter store, execute again — stale translated block runs. Fix: after any emulator or syscall store, if the range is guest-`EXEC`, call `a32_jit_invalidate_range`; route direct sites through the checked helper.

### A32-R9-7 — VMA/TLB/file mutations leave LDREX reservations live

`src/vm/vm32.c:279-300 sync_unmap` drops TLB/`g_prot` without bumping any bucket. `src/vm/vm32.c:136-152 tlb_fill` bumps one 64-byte bucket per 4 KiB page instead of all 64. `src/vm/vm32.c:333-369 set_eof_cut` and `src/vm/vm_file.c:422,457` truncate/grow zeroing and repopulation also skip bumping. Repro: `LDREX` an address, `munmap`/`mprotect`/truncate it, map new data at the same address, `STREX` — succeeds without an intervening `LDREX`. Fix: bump every reservation bucket spanned by the affected range on unmap, remap, protection change, and EOF-cut transitions.

### A32-R9-8 — Fork snapshot drops `PROT_NONE` regions

`src/os/os_sys_fork_time.c:145` skips regions with no `R`/`W`/`X` bit. The child rebuilds clusters as `RW` and only restores per-region protections for snapshotted regions. Repro: `mmap(PROT_NONE)` then `fork` — the child mapping is writable. Fix: include `PROT_NONE` ranges in the snapshot and restore them as `PROT_NONE`.

### A32-R9-9 — Fork uses raw `mprotect` with 4 KiB ranges on A2

`src/os/os_sys_fork_time.c:222,229-236,248-281,295-320` call raw `mprotect` on 4 KiB guest ranges. On a 16 KiB host these addresses and lengths are not host-aligned, so widening and the `PROT_NONE` quiesce silently fail. Repro on Darwin/16K: fork with a write-only page faults the snapshot copy with signals blocked, or siblings observe a torn snapshot. Fix: use `a32_backend_protect`/`a32_vm32_protect` for all fork-time widening and quiesce.

### A32-R9-10 — Fork and process-`clone` inherit exclusive state

Neither `fork_with_guest_snapshot` nor the non-thread `clone` path clears `ctx->ll_epoch_snap`, `ctx->excl_*`, or the shared `g_ll` owner record. The thread-`clone` path copies the whole `ctx` including them. Repro: parent `LDREX`, then `fork` — child `STREX` succeeds although ARM clears monitors across fork. Fix: in every child path (fork, process clone, thread-clone child context) clear `ll_epoch_snap` and `excl_valid`, and release the shared reservation owner.

### A32-R9-11 — ELF loader never validates `e_flags`

`src/elf32.c:114-192` checks class, endianness, and `EM_ARM` but ignores `e_flags`. No `EF_ARM_EABI_VER5` or float-ABI admission check exists. Repro: a soft-float or non-EABIv5 ARM binary loads and runs with mismatched VFP/NEON assumptions. Fix: reject `e_flags` outside the supported EABI version and float ABI before mapping segments.

### A32-R9-12 — kuser helpers are guest-non-executable but JIT-executable

`src/elf32.c:590-594` records the kuser page as guest `PROT_READ` only, and `src/os/os_sys_fork_time.c:584-603 range_ok` caps `EXEC` checks below `0xFFFF0000`, so the interpreter fetch path at `src/interp/interp.c:133` faults on kuser helpers. `src/vm/vm_jit_state.c:527` separately carves kuser out as executable for the JIT. Repro: branch to `0xFFFF0FC0` under the interpreter faults; under DBT it runs. Fix: record kuser as guest `PROT_READ | PROT_EXEC` (keeping the host mapping non-`EXEC`) and let `range_ok` cover the kuser page for `EXEC`.

### A32-R9-13 — Stack mapping never checks for overlap or retires

`src/stack32.c:118-126` installs `[0xD8000000, 0xE0000000)` with `MAP_FIXED` semantics and pure-inserts the VMA. No `range_overlaps` check and no retire of the old range occur, unlike the `MAP_FIXED` path in `src/vm.c`. Repro: an ELF image with a `PT_LOAD` covering the stack area ends up with two overlapping VMA entries after stack setup. Fix: reject overlap before mapping, or retire the range first.

### A32-R9-14 — VMA middle-split failure leaves file tracking and VMA diverged

`src/vm/vm_file_map.c` and `src/vm/vm_file.c` retire first, transactionally. `src/vm.c:209-226` then attempts the VMA middle split with only opportunistic coalescing; on insert failure it advances past the intact region and still returns success. The file identity is already retired while the VMA still claims the range. Repro: with a full 512-entry table, `munmap` the middle of a tracked mapping — file tracking splits but the VMA does not. Fix: preflight VMA split capacity before file retire, and return `-ENOMEM` with both tables untouched on failure.

### A32-R9-15 — `mmap` silently masks unknown protection bits

`src/vm.c:623` accepts any `prot` and records `prot & 0x7`, while `src/vm.c:775 mprotect` rejects `prot & ~0x7` with `EINVAL`. Repro: `mmap2(..., prot=0xFF, ...)` succeeds instead of returning `-EINVAL`. Fix: add the same `prot & ~0x7` rejection to the mmap path.

## Files with no defects in scope

No behavioral defects found in `src/host.c`, `src/main.c`, `src/vm/vm_priv.h`, `src/vm/vm32.h`, `src/vm/vm_file_map.c`, `src/vm/vm_mremap.c`, `src/vm/vm_jit_mem.c`, `src/vm/vm_jit_state.c`, or the Linux/Darwin backends for the 4 KiB/16 KiB regimes audited.
