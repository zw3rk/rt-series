# Round-9 Deep-Dive 3 Static Audit: VM, Soft-TLB, Checked Copy, `fork()` COW, ELF/Stack/Auxv Loader

Read-only audit. No files modified, no builds or tests run. Every file in `src/vm/*`, `src/run/load.c`, `src/run/core.c`, `src/main.c`, and the related syscall/CPU/DBT headers was read line-by-line.

## Summary

| ID | Area | Where | Effect |
|---|---|---|---|
| P64-R9-1 | brk | `syscalls_mm.c:550` | Stale TLB/DBT after same-page shrink |
| P64-R9-2 | brk | `syscalls_mm.c:554` | Regrow resurrects stale heap bytes |
| P64-R9-3 | EOF | `vm/vm64.c:270` | Shared write past EOF succeeds, no SIGBUS |
| P64-R9-4 | COW shared | `vm/vm_file.c:686` | Sibling mapping keeps stale DBT code |
| P64-R9-5 | COW shared | `vm/vm_file.c:686` | Cross-mapping LR/SC alias not cleared |
| P64-R9-6 | raw fill | `syscalls_mm_map.c:95` | Fixed-map over reservation, SC wrongly OK |
| P64-R9-7 | read | `os/syscalls.c:568` | Pipe data lost on bad guest buffer |
| P64-R9-8 | getdents | `os/syscalls_misc.c:185` | Dir offset advances, then EFAULT |
| P64-R9-9 | auxv | `run/load.c:466` | No cache-block-size tags |
| P64-R9-10 | interp load | `run/load.c:247` | Bias wrap plus fixed-base clobber |
| P64-R9-11 | mremap | `os/syscalls_mm.c:560` | Mixed-prot range wrongly ENOMEM |
| P64-R9-12 | madvise | `os/syscalls_conv.c:305` | DONTNEED is a no-op, stale bytes stay |
| P64-R9-13 | exec copy | `os/proc.c:293` | Wrapped string splices, no EFAULT |

## Defects

### P64-R9-1 — Same-page `brk()` shrink skips all invalidation, TLB/DBT go stale

`src/os/syscalls_mm.c:550-553`: when the page-aligned old and new ends are equal, `syscall_mm_brk` updates `s_brk_cur` and returns with no quiesce transaction, no `pp64_vm_tlb_invalidate`, and no `has_code` DBT check. Shrinking the byte-granular break inside one page revokes bytes that a populated Soft-TLB entry (whole-page `prot_of` was valid before) and possibly translated code still cover. Repro: heap page fully below break, touch its top byte under DBT (TLB entry cached), `brk()` down 100 B staying in-page, touch again — DBT fast path hits the stale tag while the interpreter slow path faults (`--difftest` divergence). Fix: on the shrink direction, run the same `quiesce_begin`/`commit` (or at minimum `tlb_invalidate` plus a `has_code` retire) even when `new_end == old_end`.

### P64-R9-2 — `brk()` shrink never discards bytes, regrowth resurrects them

`src/os/syscalls_mm.c:554-570` with `syscall_heap_trim` at `449-497`: shrinking only edits the VMA table; live `vm_dir` bytes persist. Linux frees the tail (regrowth faults fresh zeros). Repro: write `0xAA`, shrink one page, regrow, read back `0xAA` instead of `0`. Fix: zero (or discard-and-recommit) live host pages in `[new_end, old_end)` while the shrink transaction holds the quiesce lock.

### P64-R9-3 — `MAP_SHARED` write past EOF inside the partial tail page succeeds

`src/vm/vm64.c:162-187` (`vm_validate`) and `261-287` (`vm_mem_write`): EOF rejection is per whole page (`is_beyond_eof`, i.e. class `BEYOND`). A write at file offset 200 in a 100-byte file mapped `MAP_SHARED` lands in page 0 (class `PARTIAL_TAIL`), passes validation, and commits. Linux raises `SIGBUS` for any shared write at or past EOF. The same hole exists in `vm_mem_atomic` (`src/vm/vm_atomic.c:324-327`). Repro: 100-byte file, shared map, 8-byte store at offset 200 — returns success. Fix: in write/atomic-write validation, fault when `ppc64_vm_file_eof_class(addr, size)` is `PARTIAL_TAIL` or `BEYOND` on a range whose covering map is shared (private partial-tail writes must keep succeeding).

### P64-R9-4 — Shared-write sibling propagation retires no DBT code at the alias VA

`src/vm/vm_file.c:686-757`: `ppc64_vm_file_note_shared_write` copies bytes into every sibling `MAP_SHARED` mapping of the same file, but performs no `has_code` check and no invalidation for the sibling range. `vm_mem_write` (`src/vm/vm64.c:293-295`) only retires when the primary range is marked. Repro: map one library text file twice `MAP_SHARED` at A and B, execute from B (marks B only), store through A at the same file offset — B's translated block is never retired and stale code runs (the reset in `ppc64_dbt_reset` is whole-cache, so it only fires when A itself is marked). Fix: after the sibling `memcpy`, call `ppc64_vm_quiesce_invalidate_all(sgva, n)`.

### P64-R9-5 — Sibling shared write does not clear `LWARX`/`LDARX` reservations at the alias VA

Same function (`src/vm/vm_file.c:686-757`): neither the primary `reserve_note_store` (keyed to the faulting `gva`) nor anything else touches a reservation held at a sibling VA aliasing the same file bytes (different `gva` misses the overlap test in `ppc64_vm_reserve_note_store`, `src/vm/vm_atomic.c:454-473`, and usually a different epoch slot). Repro: `LDARX` at B, plain store to the same file offset via A, `STCX` at B succeeds. Fix: `ppc64_vm_reserve_note_store(vm, sgva, n)` for each updated sibling span.

### P64-R9-6 — Raw-fill mutation paths bypass the reservation epoch

`mm_fill_staged` (`src/os/syscalls_mm_map.c:84-112`, via `ppc64_vm_write_raw`), used by the anonymous zeroing (`320-345`), file population (`381-393`), and `mremap` copy (`624`); plus `vm_file_refill_span` (`src/vm/vm_file_size.c:48-76`) and `vm_file_fill_tail` (`src/vm/vm_file_mremap.c:97-110`). None bumps the LL epoch or clears reservations. Repro: `LWARX` at X (value 0), `MAP_FIXED` anonymous mapping over X (re-zeros, same bytes), `STCX` at X succeeds although hardware/Linux would fail it. Fix: `ppc64_vm_reserve_note_store(vm, at, size)` alongside every raw fill that runs under a live address space (loader-time fills before first execution are exempt).

### P64-R9-7 — `read()` consumes host bytes before validating the guest buffer

`src/os/syscalls.c:538-590`: `ppc64_host_read` runs at line 568, the checked `mem->write` at line 582. A pipe/file read into an unmapped guest buffer returns `EFAULT` but the consumed bytes are already gone. Repro: write N bytes to a pipe, `read(fd, unmapped, N)` → `EFAULT`, then `read(fd, valid, N)` blocks/returns 0 where Linux still delivers N. Fix: probe `ppc64_syscall_access_ok(buf, count, PPC64_MEM_WRITE)` before the host read (single-threaded runner, no TOCTOU).

### P64-R9-8 — `getdents64` advances the directory offset before guest validation

`src/os/syscalls_misc.c:156-199`: `mm_host_getdents` at line 185 consumes entries, `mem->write` at line 195 can then fail `EFAULT` with the offset already advanced — the entries are skipped on retry, unlike Linux. Same fix shape as P64-R9-7: validate the guest range first.

### P64-R9-9 — Initial auxv omits `AT_DCACHEBSIZE`/`AT_ICACHEBSIZE`

`src/run/load.c:466-517` with tags in `src/run/run.h:37-44`: 18 pairs cover `PHDR` through `MINSIGSTKSZ` but no cache-block-size tags (19/20, plus 21). `getauxval(AT_DCACHEBSIZE)` returns 0 instead of the Linux value (128). The repo's own oracle note (`src/os/procfs.h:156-166`) confirms the kernel/qemu layout carries them. Fix: append the three pairs (value 128); extend `need` at `load.c:520-522` accordingly. `/proc/self/auxv` (`src/os/procfs.c:290-349`) mirrors the stack image, so it stays consistent automatically.

### P64-R9-10 — Interpreter load: unchecked bias wrap, no collision check

`src/run/load.c:247` (`vaddr + bias`) and `load.c:407` (`RUN_LD_BASE + e_entry`) never check for 64-bit wrap; `load.c:402-409` maps the interpreter at fixed `RUN_LD_BASE` without checking overlap against the already-loaded main image (`[lo, hi)`). Repro: crafted `PT_INTERP` DYN with a huge `p_vaddr` wraps onto the main image and `map_fixed` silently clobbers it, or entry wraps to a wrong VA that still passes the `EXEC` check. Fix: reject when `vaddr > UINT64_MAX - bias` (and entry likewise), and fail the load if any interpreter span overlaps `[lo, hi)`.

### P64-R9-11 — `mremap` over mixed-prot/heap ranges wrongly fails `ENOMEM`

`src/os/syscalls_mm.c:560-562` via `syscall_vma_uniform_attr` (`672-695`): any prot or heap-flag heterogeneity in the source range fails, where Linux moves the whole range preserving per-VMA attributes. Repro: two adjacent mappings with different prot, one `mremap` over both with `MAYMOVE` → `ENOMEM`. Fix: relocate per-VMA attributes instead of requiring uniformity.

### P64-R9-12 — `MADV_DONTNEED` returns success without discarding anything

`src/os/syscalls_conv.c:305-322`: advice 4 passes validation and reports 0, but pages keep stale bytes (Linux faults zeros afterwards) and TLB/DBT entries survive. Repro: write pattern, `madvise(DONTNEED)`, read back pattern instead of zeros. Fix: for advice 4, zero covered pages and invalidate TLB/DBT over the range under quiesce; keep the other advices as no-ops.

### P64-R9-13 — `proc_read_string` can return a wrap-around-spliced string

`src/os/proc.c:293-362`: no upfront `addr + max_len` wrap check. The 128-byte chunk read fails on wrap and the byte-wise fallback (`322-337`) reads `addr + off + i`, which wraps to low mapped memory and can find a NUL there — returning success with bytes spliced from two ends of the address space where the kernel returns `EFAULT`. Repro: unterminated string ending `2^64-8` plus a NUL mapped at low VA. Fix: `if (max_len > UINT64_MAX - addr) return PROC_EFAULT;` at entry (same shape as the existing upfront checks in `syscall_guest_str`, `x_put`, `acc_get`/`acc_put`).

## Explicit 0-bug areas

- `src/vm/vm_dir.c` / `vm_dir.h` (`commit_page`, lookup/ensure/discard): 16 KiB-host `mprotect` widening commits `READ|WRITE` only, exactly the 4 KiB guest page is zeroed, guest pages are never `PROT_EXEC` on the host — W^X holds; `VM_DIR_SPLIT` spill never truncates 64-bit addresses. 0 bugs.
- Soft-TLB fill/invalidate/audit (`src/vm/vm64.c:392-515`): direct-mapped index math, `+1` page-cover heuristic, 512-page full-clear threshold, and `write_tag` gating on code/reservation/COW are correct. 0 bugs.
- `LARX`/`STCX` slow/fast paths (`src/vm/vm_atomic.c`, `src/vm/vm64.c:559-722`): width validation, cross-page/unaligned/16-byte slow paths, epoch-plus-value SC checks are correct. 0 bugs (alias gaps reported as P64-R9-5/6).
- `fork()` COW isolation (`src/os/proc.c:423-453`, `src/vm/vm_file.c:33-54`): host `fork()` COW-clones the arena, `vm_dir` chunks, and the private map/COW tables; MAP_SHARED inode sizes stay correctly shared. The empty `vm_file_atfork_child` hook is benign (per-process-private tables make the stale ASID self-consistent; no guest-reachable staleness found). 0 demonstrable bugs.
- Loader admission/BSS/stack core (`run_check_ehdr`, `run_map_loads` bounds, `run_build_stack` alignment and bounds checks): magic/class/data/type/machine/ABIv2 checks, `filesz/memsz` and wrap checks, explicit BSS zeroing, 16-byte-aligned `sp`, ascending table build with `sbase`/`top` containment — correct. 0 bugs outside P64-R9-9/10.
- `r2`/`r12` setup (`src/run/core.c:567-572`): `r2 = 0`, `r12 = entry` matches ELFv2 kernel convention (TOC derived by startup/linker). 0 bugs.
- `mmap` `MAP_FIXED`/`NOREPLACE` overlap, rollback snapshots, `munmap` hole/middle-split handling, `mprotect` coverage, `TASK_SIZE` bounds: correct (modulo P64-R9-11).

## Method note

Findings rest on paired evidence (implementation plus an independent check: Linux semantics, the repo's own oracle note, or an interp-vs-DBT behavioral split). Items that were merely incomplete without a demonstrable divergence (e.g. `mremap` with zero `new_size`, `AT_PHDR`-outside-`PT_LOAD` fallback) were excluded.
