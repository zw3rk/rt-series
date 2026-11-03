# Round-9 Deep-Dive 3 — Static Audit: VM + ELF/Stack/Auxv Loader

Read-only audit. No files modified, no builds/tests run, no subagents. Every file below was read line-by-line (`src/vm/*`, `src/os/mem.c`, `src/os/mem_table.c`, `src/loader.c/.h`, `src/main.c`, plus in-scope collaborators: `src/core/cpu.h`, `src/os/backend.h`, `src/os/backend_state.c`, `src/os/page_rules.*`, `src/os/syscalls.c`, `src/os/syscall_min.c`, `src/os/syscalls_sync.c`, `src/os/exec.c`, `src/os/threads.c`, `src/os/sigframe.c`, `src/os/quiesce.c`, `src/interp/decode.c`, `src/interp/unaligned.c`, `src/dbt/dbt.c`, `src/dbt/mem_recover.c`).

## Summary table

| ID | Severity | Location | Defect |
|---|---|---|---|
| M64-R9-1 | BUG (stale exec) | `src/os/syscall_min.c:394-425` | `uname` guest write skips SMC code retirement |
| M64-R9-2 | DEFECT (data loss) | `src/os/syscall_min.c:308-318,346` | `MAP_FIXED\|MAP_FIXED_NOREPLACE` replaces instead of `EEXIST` |
| M64-R9-3 | DEFECT (wrong admit) | `src/os/syscall_min.c:287-303` | `mmap` missing `MAP_SHARED`/`MAP_PRIVATE` type validation |
| M64-R9-4 | BUG (host crash / stale exec) | `src/os/mem_table.c:797-800` + `src/interp/decode.c:82-88` | Empty region table makes fetch host-fault instead of guest `SIGSEGV` |
| M64-R9-5 | DEFECT (deadlock) | `src/os/mem_table.c:611,639` vs `src/vm/vm_file.c:827,859` | `mem_lock`↔`vm_lock` ABBA between moving `mremap` and file `remap_hook` |
| M64-R9-6 | DEFECT (mis-exec) | `src/loader.c:832` | `PT_INTERP` endianness not validated against exe |
| M64-R9-7 | DEFECT (fork visibility) | `src/os/syscall_min.c:366-368` + `src/os/mem_table.c:246-262` | `MAP_SHARED` anon silently demoted to `MAP_PRIVATE` |

## Findings

### M64-R9-1 — `uname` bypasses the SMC write gate (`src/os/syscall_min.c:394-425`)

`sc_uname` validates with `mips_mem_ok`, then hand-rolls the commit: `memcpy` at `:407-412`, `mips_llsc_note_write` at `:420`, `mips_vm_pages_clear(COW_CLEAN)` at `:422`, `mips_vm_file_shared_sync` at `:423`. The shared commit path it mirrors, `mips_sc_copyout` (`src/os/syscalls.c:146-167`), additionally calls `mips_vm_pages_retire_code` (`:163`); every other staged-copyout site (`read`, `readv`, `getdents64`, `getrandom`, signal-frame delivery at `src/os/sigframe.c:389`, `waitid` memset paths at `src/os/exec.c:696,742`) retires code. `sc_uname` does not.

Reproduction: guest maps one page `PROT_READ|PROT_WRITE|PROT_EXEC`, executes code from it (DBT compiles and marks `HAS_CODE`), then calls `uname()` with its `buf` argument pointing into the same page. The 390-byte `memcpy` overwrites translated bytes; the old block stays epoch-valid and executes stale code.

Fix (one line after `:422`, `vm/vm_pages.h` is already included at `:16`):

```c
mips_vm_pages_retire_code(va, MIPS_UTS_SIZE);
```

### M64-R9-2 — `MAP_FIXED|MAP_FIXED_NOREPLACE` clobbers (`src/os/syscall_min.c:308-318,346`)

The `EEXIST` probe at `:313-317` runs only `if ((flags & MIPS_MAP_FIXED) == 0U`, and the replace path at `:346` runs whenever `MAP_FIXED` is set. With both bits set, the call takes the replace path and destroys the overlapped mapping. Per `mmap(2)`, "`EEXIST`: `MAP_FIXED_NOREPLACE` was specified in flags, and the range clashes" — the `NOREPLACE` bit is specified, so `EEXIST` is required regardless of `MAP_FIXED`.

Reproduction: live mapping at `addr`; `mmap(addr, size, prot, MAP_FIXED|MAP_FIXED_NOREPLACE|MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)` → mapping destroyed, success returned; Linux returns `EEXIST` with the old mapping intact.

Fix: test `MAP_FIXED_NOREPLACE` before `MAP_FIXED` — route to the `:362-364` no-replace path (which correctly returns `mips_mem_map`'s `-EEXIST`) whenever `flags & MIPS_MAP_FIXED_NOREPLACE`, even with `MAP_FIXED` also set.

### M64-R9-3 — `mmap` accepts invalid map type (`src/os/syscall_min.c:287-303`)

`sc_mmap` never validates `MAP_SHARED`/`MAP_PRIVATE` presence (`MIPS_MAP_SHARED 0x01`, `MIPS_MAP_PRIVATE 0x02` at `:159-160`). Per `mmap(2)`, "`EINVAL`: flags contained none of `MAP_PRIVATE`, `MAP_SHARED`, or `MAP_SHARED_VALIDATE`" (older manpages: neither or both).

Reproduction: `mmap(NULL, 4096, PROT_READ, MAP_ANONYMOUS, -1, 0)` (type bits `0`) → translator returns a valid address; Linux returns `EINVAL`. Same for `MAP_SHARED|MAP_PRIVATE` combined.

Fix after the `len`/`prot` checks:

```c
if ((flags & (MIPS_MAP_SHARED | MIPS_MAP_PRIVATE)) == 0U ||
    (flags & (MIPS_MAP_SHARED | MIPS_MAP_PRIVATE)) ==
        (MIPS_MAP_SHARED | MIPS_MAP_PRIVATE))
    return sc_ret(ctx, -(int64_t)EINVAL);
```

### M64-R9-4 — fetch from an emptied address space crashes the host (`src/os/mem_table.c:797-800`, `src/interp/decode.c:82-88`)

`mips_mem_exec_ok` returns `ok = 1` when `g_region_count == 0`. `mips_fetch` treats that as covered and does `memcpy(b, mips64_guest_ptr(ctx, pc), 4U)` (`decode.c:88`) with only the `TASK_SIZE` bound as guard. In production the reservation is `PROT_NONE`, so this is a host `SIGSEGV` (4 KiB host) or silent execution of stale bytes (16 KiB host, where `mips_mem_unmap` deliberately leaves the cover host-RW, `mem_table.c:301-304`) — instead of a guest `SIGSEGV`.

Reproduction: guest calls `munmap(0, task_size)` (both `va = 0` and full-length pass validation at `mem_table.c:284-292`), emptying the table, then executes the next instruction at any `pc < task_size` → host fault, translator dies.

Fix: drop the empty-table special case so an empty table denies exec (guest gets `SIGSEGV`); update the unit-test scratch windows the comment cites to record one region first.

### M64-R9-5 — `mem_lock`/`vm_lock` lock-order inversion (`src/os/mem_table.c:611,639` vs `src/vm/vm_file.c:827,859`)

Order A (moving `mremap`, under `mem_lock` from `:611`): `remap_copy_span` (`:639`) → `mips_vm_file_read_page` → `vm_lock()` (`vm_file_sync.c:153`). Order B (in-place growth path, `mem_table.c:593-596` calls `mips_vm_file_remap_hook` with no `mem_lock` held): `vm_lock()` (`vm_file.c:827`) → `vm_inode_apply_region_prots` (`:859`) → `mips_mem_region_count/at` → `mem_lock()`. `vm_lock` is non-recursive, so opposite-order acquisition deadlocks.

Reproduction (multithreaded guest with a natively-shared file mapping): thread A runs `mremap` with `MAYMOVE` that must move; thread B concurrently runs size-growing `mremap` without `MAYMOVE` over the shared mapping. A holds `mem_lock` waiting in `read_page` for `vm_lock`; B holds `vm_lock` waiting in `apply_region_prots` for `mem_lock`.

Fix: single global order — e.g. in `remap_copy_span`, snapshot file-page contents before taking `mem_lock` (or take `vm_lock` before `mem_lock` consistently), and in `remap_hook` drop `vm_lock` across `vm_inode_apply_region_prots` with revalidation.

### M64-R9-6 — interpreter endianness unchecked (`src/loader.c:832`)

`if (parse_ehdr(ifd, &ieh) != 0 || classify(&ieh) != kind)` validates class/ABI/arch but `classify` never compares `ieh.be` with the exe's `eh.be`, while `ctx->is_be` was already fixed from the exe at `:780`.

Reproduction: LE exe naming a BE `ld.so` (or vice versa) loads successfully; control transfers to bytes decoded in the wrong byte order instead of clean `ENOEXEC`.

Fix: `if (parse_ehdr(ifd, &ieh) != 0 || classify(&ieh) != kind || ieh.be != eh.be)`.

### M64-R9-7 — `MAP_SHARED` anon demoted to private (`src/os/syscall_min.c:366-368`, `src/os/mem_table.c:246-262`)

`sc_mmap` records only `is_shared` for the file hook; the anon path ignores `MAP_SHARED`, and `mips_mem_map`/`mips_mem_map_replace` always use host `MAP_PRIVATE`. This falsifies `sc_fork`'s documented premise that "every guest mapping is `MAP_PRIVATE`" (`syscall_min.c:437-439`).

Reproduction: `mmap(NULL, 4096, RW, MAP_SHARED|MAP_ANONYMOUS, -1, 0)`; `fork()`; child stores; parent never observes it. Linux shares the page across fork.

Fix: plumb the shared bit into the anon path and place `MAP_SHARED` anon with host `MAP_SHARED` (keeping the per-4 KiB soft-TLB/software permission gate, which already handles shared pages), so host `fork()` preserves sharing.

## Verified clean (no defect claimed)

- **VMA split/overlap**: `split_at`/`insert_region` (`mem_table.c:107-179`) split straddlers and preserve sort; `MAP_FIXED` goes through atomic `mips_mem_map_replace` (`:333-392`, snapshot/restore on failure); `MAP_FIXED_NOREPLACE` probes full-hole (`syscall_min.c:313-317`); `brk` extension fails closed on overlap (`:240-251`); `mremap` validates flags/alignment/non-overlap for `FIXED` (`:561-602`). `TASK_SIZE` upper-bound plus `addr+size` wrap checks are present on every entry (`mmap :300-312`, `munmap :288-290`, `mprotect :414-416`, `mremap :566-571`, `mem_ok :190-191`).
- **Wrap-around**: all `va+len` additions are guarded before use; per-byte copy loops (`guest_str`, `mem_fix_ld/st`) can only wrap from a mapped `va < task_size ≤ 2^40`, where `+4096` cannot reach `2^64`. N32 high-half VAs are rejected by the same `task_size` bound.
- **Checked copy**: `mips_sc_copyout`, vectored/scalar I/O, `exec` copy helpers, and `guest_ld/st*` validate via `mips_mem_ok` before touching host memory and pair every committed write with LL/SC invalidation (`llsc_note_write`), `COW_CLEAN` clearing, SMC retirement, and shared-file sync — except M64-R9-1. Endianness is explicit everywhere (`putn/getn`, `guest_ld/st`, loader `st_word`, iovec decode).
- **`fork()` COW**: host `fork()` + `MAP_PRIVATE` gives correct COW; no stale LL reservation survives (every syscall clears `llbit` at `syscall_min.c:548` before `fork`/`clone` dispatch); `vm_inode` atfork ticket adoption (`vm_file.c:160-246`), `qs`/`threads`/`llsc` atfork resets are all wired in both `sc_fork` and `l4b_clone_fork`.
- **Loader**: `EM_MIPS`/class/endian admission, `ET_EXEC`/`ET_DYN` bias, `PT_LOAD` bounds/page-rounding math, `p_filesz < p_memsz` BSS zeroing, `PF_*`→`PROT_*` corner-correct translation, 16-byte stack alignment with in-mapping proof, N64 8-byte / N32 4-byte guest-order auxv (`AT_PHDR/PHENT/PHNUM/PAGESZ/FLAGS/ENTRY/UID/EUID/GID/EGID/CLKTCK/SECURE/RANDOM/EXECFN`, plus `AT_BASE/AT_HWCAP2` for `PT_INTERP`), and `/proc` auxv re-emission in guest order (`proc.c:388-400`) all check out. `madvise` has no handler (→ `ENOSYS`); glibc treats that as a hint failure, so no defect is claimed.

## Per-file verdicts

- 0 bugs: `src/vm/vm64.c`, `src/vm/vm64.h`, `src/vm/vm_pages.c`, `src/vm/vm_pages.h`, `src/vm/vm_file.h`, `src/vm/vm_file_int.h`, `src/os/mem.c`, `src/loader.h`, `src/main.c`.
- Findings as above: `src/vm/vm_file.c` (M64-R9-5), `src/vm/vm_file_sync.c` (M64-R9-5), `src/os/mem_table.c` (M64-R9-4, M64-R9-5), `src/loader.c` (M64-R9-6), `src/os/syscall_min.c` (M64-R9-1, M64-R9-2, M64-R9-3, M64-R9-7).

