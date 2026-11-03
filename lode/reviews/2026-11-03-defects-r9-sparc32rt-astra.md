# Round-9 Deep-Dive 3 Static Audit: VM / Soft-TLB / Checked Copy / fork COW / ELF32-Auxv-Stack

Read-only audit. No files created, modified, or deleted. No builds or tests run. Every file below was read line-by-line.

## Summary

| ID | Location | Effect | Fix |
| --- | --- | --- | --- |
| S32-R9-1 | `l2a_access.h:70` | fail-open to host crash | return `EFAULT` |
| S32-R9-2 | `l2a_access.h:176` | wrong errno on wrap | return `EFAULT` |
| S32-R9-3 | `vm_mmap.c:228` | file-track leak on ENOMEM | unregister on failure |
| S32-R9-4 | `vm_mmap.c:256` | tail beyond EOF faults | map zero anon tail |
| S32-R9-5 | `syscalls_min.c:811` | `madvise` always ENOSYS | add dispatch arms |
| S32-R9-6 | `stack32.c:106` | args silently truncated | return `E2BIG` |
| S32-R9-7 | `elf32.c:455` | misaligned LOAD misloads | check congruence |
| S32-R9-8 | `vm_file.c:185` | shrink keeps stale code | invalidate shrunk range |

## Findings

### S32-R9-1 — Checked-copy fail-open when protection table is `NULL`

Location: [l2a_access.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:69)

```c
prot = sparc32_vm_prot_base();
if (prot == NULL) {
    return 0;
}
```

Behavior: `l2a_range_ok_prot()` reports success for any `[SPARC32_LOW_GUARD_SIZE, SPARC32_TASK_SIZE_TOP)` range when `g_vm32_prot` is `NULL`. Callers `l2a_load()` / `l2a_store()` then `memcpy()` through `sparc32_guest_ptr()`. If the host reservation at `G+va` is `PROT_NONE`, the host takes `SIGSEGV` instead of returning guest `-EFAULT`.

Contrast [interp_mem.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:39): `interp_range_ok()` falls back to the `ctx->regions` scan when the table is `NULL`. The syscall path has no fallback.

Reproduction: force `vm32_alloc_tables()` failure or call before `vm32_attach()`, then `l2a_load(ctx, 0x50000000, buf, 4)` on an unmapped page. Returns `0` and crashes host instead of `-EFAULT`.

Fix: fail closed, mirroring the interpreter:

```c
if (prot == NULL) {
    return -EFAULT;
}
```

or fall back to a region-table scan.

### S32-R9-2 — `copy_str` 32-bit wrap returns wrong errno

Location: [l2a_access.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:174)

```c
uint32_t a = va + i;
if (a < va) {
    sparc32_vm_access_leave();
    return -ENAMETOOLONG;
}
```

Behavior: a NUL-terminated string crossing `0xFFFFFFFF` wraps `a`. The range is unmapped past `SPARC32_TASK_SIZE_TOP` and must be `-EFAULT`. Returning `-ENAMETOOLONG` misleads `execve` / `openat` path handling.

Reproduction: `l2a_copy_cstring(ctx, 0xFFFFFF00, out, 512)` with no NUL before the top. Returns `-36` instead of `-14`.

Fix:

```c
if (a < va) {
    sparc32_vm_access_leave();
    return -EFAULT;
}
```

### S32-R9-3 — File-tracking entry leaked on VMA-record `ENOMEM`

Location: [vm_mmap.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:228)

Order is:

```c
vm_mmap_publish(...);
vm_mmap_note_file(fd, target_va, ...);   // line 219
rec_rc = vm_record_region_ext_locked(...); // line 225
if (rec_rc != 0) {
    (void)vm_reserve_prot_none(...);
    vm_mmap_publish(..., 0U, 0U);
    // missing vm_file_unregister_range()
    return (uint32_t)(-ENOMEM);
}
```

Behavior: `vm_file_note_mapping()` inserts a live `g_inodes[]` entry. If the region table is full (`512` entries), the host mapping is torn down but the file entry remains with `map_gva == target_va`. It is never retired because the guest received an error and will not `munmap()` it. After 128 such failures `VMF_MAX_INODES` fills and later `vmf_intern()` silently drops tracking, so subsequent `ftruncate` shrinks miss pages.

Fix, before reserve:

```c
vm_file_unregister_range(target_va, (uint32_t)aligned_len);
```

### S32-R9-4 — Apple-only file tail beyond EOF made `PROT_NONE` instead of zero-filled

Location: [vm_mmap.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:256)

```c
vm_mmap_publish(ctx, tail_start, tail_end, 0U, 0U);
vm_mprotect_regions_locked(tail_start, tail_end, 0U);
(void)rt_host_protect(..., PROT_NONE);
```

Behavior: Linux file `mmap` zero-fills `[avail, aligned_len)`: full pages beyond EOF are readable zeros. This path downgrades the whole tail to guest `PROT_NONE`. A guest read of tail bytes that Linux serves as `0` faults here.

Reproduction: 100-byte file, `mmap2(0, 8192, PROT_READ, MAP_PRIVATE, fd, 0)`, read `va+4096`. Linux returns `0`; this build faults.

Fix: keep the tail mapped with the requested `prot`, publish it, and explicitly zero it, instead of publishing `0` and protecting `NONE`.

### S32-R9-5 — `madvise` / `msync` / `mincore` unimplemented

Locations: [syscalls_min.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_min.c:810) default `ret = -ENOSYS`; numbers defined in [syscall_nr.h](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscall_nr.h:88) (`65 msync`, `75 madvise`, `78 mincore`) have no case arms. Backends already export `rt_host_madvise()` / `rt_host_msync()`.

Behavior: guest `madvise(0x40000000, 4096, 0)` returns `-38` where `qemu-sparc -cpu LEON3` returns `0`. `glibc` `malloc` / `free` `MADV_DONTNEED` paths observe spurious failure.

Fix: add minimal dispatch with range validation and `MADV_DONTNEED` invalidation:

```c
case (long)SPARC32__NR_madvise:
    ret = sys_madvise(ctx, o0, o1, o2);
    break;
```

with `l2a_range_ok_prot()` pre-check and `vm_invalidate_jit()` on `DONTNEED`.

### S32-R9-6 — Initial-stack `argc` / `envc` silently truncated at 511

Location: [stack32.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/stack32.c:106)

```c
while (count < max_count && count < 511 && strs[count] != NULL) {
    count++;
}
```

Behavior: extra arguments are dropped without error. `argv[511..]` vanish; guest sees `argc == 511`. The `execve` staging path in `threads_exec.c` correctly returns `-E2BIG` when `n+1 >= cap`. Initial stack should match.

Reproduction: launch with 600 guest args. Guest observes `argc == 511` instead of loader failure.

Fix: detect truncation:

```c
if (count == 511 && strs[511] != NULL) {
    return -1;
}
```

and propagate as `-E2BIG`.

### S32-R9-7 — Missing `p_offset` / `p_vaddr` congruence check

Location: [elf32.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/elf32.c:455)

The page-offset adjustment:

```c
if (page_start == map_start && page_off != 0U && ph->p_offset >= page_off) {
    read_file_off = ph->p_offset - page_off;
    read_file_len = ph->p_filesz + page_off;
}
```

assumes `(p_offset & 0xFFF) == (p_vaddr & 0xFFF)` but never checks it. With a mismatch the padding byte at `map_start` is loaded from `file[page_down(p_offset)]` instead of zero.

Reproduction: `PT_LOAD` with `p_vaddr == 0x10001`, `p_offset == 0x1002`. Byte at `0x10000` loads `0x1001` file content; Linux rejects or zero-fills.

Fix, in the per-segment validation loop:

```c
if ((ph->p_offset & 0xFFFU) != (ph->p_vaddr & 0xFFFU)) {
    return -ENOEXEC;
}
```

### S32-R9-8 — File shrink does not invalidate translated code

Locations: [vm_file.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:185) and [backend_linux.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/backend_linux.c:51)

`vmf_shrink_entry()` calls only `vm32_page_revert_clean()`. `vm_file_note_mutation()` bumps `code_generation` but never calls `vm_invalidate_jit()`. Every other VMA mutation (`mmap` with `FIXED`/`EXEC` in [vm_mmap.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:291), `mprotect` in [vm_mmap.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:365), `munmap` in [vm_mmap.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:426), `mremap`, `brk` shrink, `mprotect`/`munmap` in [vm.c](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm.c:188)) invalidates.

Reproduction: translate `RX` file-backed page, `ftruncate()` it shorter, grow it with new code. Old translation for the shrunk tail remains in `dbt_cache` with `RT_PAGE_HAS_CODE` still set on CLEAN pages.

Fix: after `vmf_shrink_entry()` invalidate exactly the shrunk span:

```c
vm_invalidate_jit(NULL, glo, ghi);
```

or route the shrunk `[glo, ghi)` through `sparc32_dbt_invalidate_range()`.

## Files with 0 bugs

The following in-scope files were read fully and exhibit no concrete behavioral defect for the audited dimensions:

- `src/vm/vm32.c` — 4 GiB window, Regime A1/A2 selection, per-4K publish, `FAST_WRITE` CAS, line masks, `vm32_clear_code_range` + re-note in `dbt_cache`, wrap-safe 64-bit range math.
- `src/rt32/vm.c` — window reservation, region insert/coalesce/split, `brk` limit/overlap/host-granule handling, shrink `PROT_NONE` + publish + invalidate.
- `src/rt32/vm_int.h`, `src/rt32/rt32.h`, `src/sparc32rt.h`, `include/a32host.h` — constants, frozen layout, `sparc32_host_prot()` (`EXEC` never host-`EXEC`).
- `src/rt32/host.c` — `SPARC32RT_HOST=none` opt-out, `EACCES` read-only fallback, ABI-major gate.
- `src/main.c` — window reserve + `vm32_attach` ordering, ELF + stack sequencing, entry `pc`/`npc`, `cwp` reset.
- `src/interp/interp_mem.c` — 64-bit `end`, low-guard via table, alignment faults, `vm32_note_page_write` + `vm32_range_has_code` + post-unlock invalidate, BE assembly.
- `src/dbt/aot/mem_site.h`, `src/dbt/aot/aot_sites.c` — `rt_write_tag_allowed()`, `aot_span_ok()` validate-before-commit with 8-byte callers.
- `src/dbt/emit_fast.c`, `src/dbt/dbt_cache.c` — `x25` prot probe, `FAST_WRITE` slow-path on code pages, range-selective retire + `vm32_clear_code_range` + re-note.
- `src/os/backend.h`, `src/os/backend_linux.c`, `src/os/backend_darwin.c` — host-page rounding inward for `NONE`, outward union for data, no host-`EXEC` for guest data.
- `src/os/l2a_access.h` big-endian helpers, `src/interp/decode.c` fetch `READ|EXEC` gate, `src/os/threads.c` native `fork()` COW with quiesced `dbt`/`VM` locks, `src/os/threads_exec.c` plan-then-retire ordering — no additional defect beyond the IDs above.
- `src/rt32/elf32.c` admission (`EM_SPARC` + `e_flags ∈ {0,0x300}` per `SPEC.md`), `p_filesz <= p_memsz`, BSS zeroing, `AT_PHDR`/`ENTRY`/`BASE`/`PAGESZ`/`HWCAP` BE `auxv`, and `src/rt32/stack32.c` 8-byte alignment, `%sp+64` `argc`, `AT_RANDOM`/`PLATFORM`/`EXECFN` — correct except `S32-R9-6` and `S32-R9-7`.

