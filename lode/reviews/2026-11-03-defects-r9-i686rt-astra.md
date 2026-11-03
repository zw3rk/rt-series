# i686rt Round-9 static audit — VM / Soft-TLB / copy / fork / ELF-Auxv-Stack

Scope read line-by-line: `src/vm/*`, `src/rt32/rt32_vm*`, `src/rt32/rt32_elf32.c`, `src/rt32/rt32_stack32.c`, `src/rt32/rt32_host.c`, `src/rt32/rt32.h`, `src/i686rt.h`, `src/main.c`, plus in-scope helpers `src/os/marshal.*`, `src/os/syscalls.c`, `src/os/sys_misc.c`, `src/os/clone.c`, `src/os/proc.*`, `src/os/vdso.c`, `src/os/ldt.c`, `src/os/signals_subpage.c`, `src/dbt/engine_smc.c`.

## Summary

| ID | Where | Impact | Fix |
|---|---|---|---|
| I686-R9-1 | `marshal.c:205,226` | Wrap read, wrong bytes | Add wrap check |
| I686-R9-2 | `syscalls.c:196` | Bad `uname` crashes | Use checked copy |
| I686-R9-3 | `sys_misc.c:583` | `madvise` escapes window | Validate, invalidate |
| I686-R9-4 | `mmap.c:154`, `vm.c:841`, `elf32.c:118` | Hole becomes accessible | Use widen, not union |
| I686-R9-5 | `elf32.c:299` | Shared page gets `RWX` | Use current prot |
| I686-R9-6 | `vm_file.c:235,785` | `pwrite` clobbers writes | Promote on write |
| I686-R9-7 | `mmap.c:220` | Host/VMA diverge | Record before host |
| I686-R9-8 | `vm_file.c:345` | `4K mprotect` on `16K` host | Use widen cover |
| I686-R9-9 | `vm32.c:73`, `clone.c:836` | Destroy locked mutex | Reset without destroy |

## Defects

### I686-R9-1 — `i686_fetch_cstr` misses 32-bit wrap check

- File: `src/os/marshal.c:205`, `src/os/marshal.c:226`
- `i686_copy_from_guest`/`copy_to_guest` reject `va+len > 0x100000000` (`marshal.c:162,179`). `i686_fetch_cstr` has no such check.
- `s_fetch_run` does `cur_va = va + (uint32_t)i`, which wraps. `va=0xFFFFFFF0`, `buflen=0x20` wraps to low memory and can return low-memory bytes instead of `-EFAULT`.
- Fix: add the same `(uint64_t)va + buflen > 0x100000000` guard, or per-byte overflow check.

### I686-R9-2 — `sys_uname` writes guest memory unchecked

- File: `src/os/syscalls.c:196`
- Wrap is checked, but mapped/permitted is not. It does `buf = i686_guest_ptr(ctx, buf_va); memset(...)` directly.
- Unmapped/`PROT_NONE`/read-only `buf_va`, or an A2 widen-restricted page, host-faults. The outer run-loop turns it into guest `SIGSEGV`, while Linux returns `-EFAULT`.
- Fix: build into a stack buffer and `i686_copy_to_guest`.

### I686-R9-3 — `r_madvise` unchecked, escapes window, skips invalidation

- File: `src/os/sys_misc.c:583`
- Passes `EBX`/`ECX` straight to host `madvise` with no wrap, alignment, or mapped-range check. `EBX=0xFFFFFF00,ECX=0x200` advises `[G+4GiB-256,G+4GiB+256)`, past the window into host memory.
- No Soft-TLB/DBT invalidation on `DONTNEED`/`REMOVE` of a `PROT_EXEC` page, so stale translated blocks survive discarded bytes.
- Fix: reject wrap, require mapped range, `i686_dbt_invalidate_range` when discarding/removing executable pages.

### I686-R9-4 — steady state uses union instead of widen on A2

- Files: `src/rt32/rt32_vm_mmap.c:154`, `src/rt32/rt32_vm.c:841`, `src/rt32/rt32_elf32.c:118`
- `widen` is AND (correct steady state); `union` is OR (temporary single-step cover). New `mmap`, growing `brk`, and ELF segment protect all finish with `union`.
- Repro on `16K` host: one host page with sub-page `PROT_NONE`, then `MAP_FIXED` a sibling sub-page `RW`. Union makes the whole host page `RW`, so DBT `[x20,wAddr,uxtw]` accesses the `PROT_NONE` hole without faulting.
- Fix: call `i686_vm32_widen_prot` for the steady state; reserve `union` for the locked emulate window.

### I686-R9-5 — ELF shared-page prot uses OR, creates `RWX`

- File: `src/rt32/rt32_elf32.c:299`
- `merged_prot = highest_mapped_prot | guest_prot`. A shared `4K` page between `R-X` text and `RW-` data becomes `RWX` (`5|6=7`).
- Linux `MAP_FIXED` load order makes the later mapping win; OR wrongly adds `X` to data. Visible in guest `/proc/self/maps` as `rwx`.
- Fix: protect the shared prefix with the current segment prot (or the later one), not OR.

### I686-R9-6 — `CLEAN->DIRTY` promotion never runs

- Files: `src/vm/vm_file.c:235`, `src/vm/vm_file.c:785`
- `i686_vm_file_promote_cow` has no callers. Writes never flip `PAGE_COW_CLEAN` to `DIRTY`.
- The `pwrite` hook refreshes every `CLEAN` page, so after a guest write to a `MAP_PRIVATE` file page, a `pwrite` to the same file offset overwrites the guest write with file bytes.
- Fix: promote on guest writes (`copy_to_guest` store path, SMC write-fault commit, A2 emulate store commit).

### I686-R9-7 — `mprotect` changes host before VMA commit

- File: `src/rt32/rt32_vm_mmap.c:220`
- A2 path records first, then widens (safe). The `4K` path does host `mprotect` first, then `rt32_vm_mprotect_regions_locked`.
- If the region split exceeds `I686_MAX_REGIONS`, host prot is already new while the VMA/mirror still hold old prot.
- Fix: record/split first, then host `mprotect`; restore host prot if the record fails.

### I686-R9-8 — shrink prefix uses `4K mprotect` on A2 hosts

- File: `src/vm/vm_file.c:345`
- Prefix restore calls `mprotect(page, 0x1000u, ...)` per sub-page. On a `16K` host this is not host-aligned and fails `EINVAL`; the return is cast to void.
- Fix: drop the per-sub-page host call here and rely on the host-aligned cover plus final widen.

### I686-R9-9 — `fork` child destroys locked mutexes

- Files: `src/vm/vm32.c:73`, `src/os/clone.c:836`
- `fork_prepare` holds `s_futex_mtx`, `s_subpage_mtx`, and the registry lock across `fork`. The child then `pthread_mutex_destroy`s them while locked, which is undefined behaviour.
- Fix: in the child, reinitialise without destroying a locked mutex, or use a fork-safe reset that does not destroy-while-locked.

## Files with 0 bugs in this scope

- `src/vm/vm32.h` — 0 bugs.
- `src/vm/vm_file.h` — 0 bugs.
- `src/rt32/rt32_vm_internal.h` — 0 bugs.
- `src/rt32/rt32.h` — 0 bugs.
- `src/rt32/rt32_host.c` — 0 bugs.
- `src/rt32/rt32_stack32.c` — 0 bugs in the audited properties; stack is `16B`-aligned and overflow-checked.
- `src/i686rt.h` — 0 bugs.
- `src/main.c` — 0 bugs.
- `src/os/proc.h`, `src/os/proc.c` — 0 bugs; auxv order, `AT_PHENT` value from ELF, `AT_PAGESZ=4096`, `HWCAP`/`CLKTCK`/conditional `SYSINFO` handling match the stated contract.
- `src/os/vdso.c` — 0 bugs.
- `src/os/ldt.c` — 0 bugs for `modify_ldt`/`set_thread_area`/clone-TLS validation in this read.

