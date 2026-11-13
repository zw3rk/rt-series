## Round-3 Remediation Review: `a8c5bfd` vs `a76285b` (a32rt)

Static inspection only. I read the audit report, the full commit diff for `Makefile`, `src/`, and the resulting HEAD sources for `vm.c`, `vm_file.c`, `vm_file_map.c`, `vm_mremap.c`, `vm_priv.h`, `vm_jit_mem.c`, `dbt_jit_query.c`, and `os_sys_fork_time.c`. No builds or tests ran, so compile cleanliness under the new `-Werror` fixture policy is unverified.

### Compliance gate

- No `#include "*.c"` anywhere in `src/` or `include/`.
- All source and header files are at or below 900 lines. `src/signals.c` is at 899 after this commit added 27 lines, so the next edit there will breach the limit.
- Lock order is consistent: JIT lock, then VM spinlock, then `g_vmfile_lock`. All `a32_vm_invalidate_jit` calls happen after the VM lock is released, and `fork_with_guest_snapshot` takes the JIT lock before `a32_vm_sync_ctx`. No inversion found.

---

### A32-R3-1 — Region registration deleted new file backing: **VERIFIED**

`a32_vm_record_region_locked` no longer calls `vm_unmap_regions_locked`. The retire step moved to `src/vm.c:627` and runs before the host mapping is installed. Full-cover shared unmap at `src/vm/vm_file.c:543` now only drops tracking and never remaps anonymous memory. The brk path now unwinds pages if the region table is full instead of leaving untracked memory.

One new failure-mode regression (see Follow-up 2): because retire now precedes install, a failed MAP_FIXED replacement leaves the old host pages mapped but unregistered. Linux leaves the previous mapping fully intact on a failed `mmap`.

Unverified: any external caller of the public `a32_vm_record_region` (ELF loader, stack builder) that relied on the old implicit replacement now gets pure insertion. Those files were not touched by this commit, so that is worth one grep.

### A32-R3-2 — Initial mappings accessible beyond EOF: **VERIFIED**

`a32_vmfile_populate_private` now stores `st.st_size` as the inode baseline at `src/vm/vm_file.c:212`, and `vmfile_enforce_eof_locked` marks pages wholly beyond rounded EOF as cut before the pread loop. `a32_vmfile_populate_if_private` commits the final protection only over the file-backed prefix at `src/vm/vm_file_map.c:76-90`. Shared file records also enforce the cut.

Not inspected: whether `vm_insert_region_raw` and `a32_vmfile_promote_range` (the guest `mprotect` path, which calls `a32_vm32_tlb_fill` for every page) honor the per-page EOF-cut flag. The shrink path in `vmfile_sync_size` already relied on this before the commit, so it is not a new exposure.

### A32-R3-3 — Private file backing lost across mremap: **PARTIAL**

Growth and relocation now carry an owned duplicate descriptor and file offset through `mremap_priv_lookup` and both `a32_vm_mmap_locked` calls in `src/vm/vm_mremap.c`. Descriptor lifetime is correct: `fmap_record_locked` duplicates again, and `mremap_priv_release` closes the carried fd on every exit path.

Two gaps keep this at PARTIAL:

- **Copy predicate regression** at `src/vm/vm_mremap.c:91`: `mremap_copy_prefix` only copies 4 KiB chunks that pass `a32_vm32_range_prot_ok(..., PROT_READ)`. The intent is to skip EOF-cut pages, but a `PROT_NONE` anonymous or private mapping also fails that check, so a MAYMOVE `mremap` of PROT_NONE memory now silently discards its contents. The old code did an unconditional `memcpy` after raising host protection to `PROT_READ`. The predicate should test "not EOF-cut", not "guest-readable".
- **Single-entry requirement** at `src/vm/vm_mremap.c:66`: backing is only carried if one `g_fmaps` entry covers the whole old range. An in-place growth creates a second entry for the extension, so the next `mremap` of the same mapping falls back to the anonymous path and loses file backing again. Entries are never merged.

Also, the move path applies the final protection over the entire new extent via `a32_vm_protect_locked` at line 246, bypassing the prefix-only commit introduced for R3-2.

### A32-R3-4 — Fork inherits JIT leases from vanished threads: **PARTIAL**

Under `hl` (`has_host_info` true) the fix is sound: `a32_jit_fork_prepare` at `src/vm/vm_jit_mem.c:116` takes the JIT lock, sets `g_jit_reset_pending`, and drains readers with all signals blocked; the parent resumes in `a32_jit_fork_parent`, and the child resets JIT, VM, and file locks. Every failure path in `fork_with_guest_snapshot` is reconciled through `fork_reconciled`. The deadlock precondition (no thread holds a lease while acquiring the JIT lock) is the same one `a32_jit_reset_cache_locked` already required.

The gap: the early return at `src/os/os_sys_fork_time.c:89` for `!ctx->has_host_info` calls plain `fork()` with no quiesce, then only `fork_child_reset()` in the child. That is exactly the "resetting counters alone is insufficient" case the audit called out. This branch is the plain-Linux path, which is the project's ground-truth oracle under lima. A sibling thread mid-compile holding the JIT lock at fork time leaves the child with a half-mutated cache and a zeroed lock. The quiesce should wrap every `fork()` call, with the snapshot logic remaining hl-only.

Minor: `a32_vmfile_fork_child_reset` destroys a possibly-locked mutex, which is undefined per POSIX but works on glibc and musl.

### A32-R3-5 — Tracking exhaustion silently disables semantics: **VERIFIED, with consequential behavior change**

Records are now transactional: slots are reserved and descriptors duplicated before mutation in `fmap_record_locked` and `a32_vmfile_record_shared`, splits secure their slot first at `src/vm/vm_file.c:556` and `:593`, and inode entries are reclaimed at `:621-636` when the last mapping disappears. Pre-flight `a32_vmfile_check_record` fails the `mmap` with `-ENOMEM` before any host change.

The audit offered two remedies: grow the tables, or reject operations. The commit chose reject while keeping `A32_VMFILE_SLOTS` at 64. See Follow-up 1 for why that is a likely hard regression for dynamically linked guests.

Low: when a middle-range split cannot be tracked, the whole stale entry is kept, so a later private file mapping placed in that hole can produce two overlapping entries and `a32_vmfile_lookup_private` may return the wrong file identity. Requires an exhausted table first.

### A32-R3-6 — Single-step lease acquired after compile unlock: **VERIFIED**

`a32_jit_compile_block_leased` routes through `compile_block_internal(..., flush_now = true)`, and `a32_jit_lookup_or_compile_entry` takes the reader lease inside the lock on both the hit path (`dbt_jit_query.c:60`) and the compile path (`:249`). The separate lock, seal, increment sequence in `a32_dbt_single_step` is gone, and the unchanged tail still pairs with `a32_jit_exec_leave`.

### A32-R3-7 — Inconsistent fixture warning flags: **VERIFIED (static)**

`A32RT_WARN_C` and `A32RT_WARN_CXX` are defined once and used by the runtime, darwin, freestanding, musl, glibc, C++ and bench recipes. A `test` gate was added and `.PHONY` updated. Whether every fixture compiles clean under the newly added `-Werror` was not verified.

---

### Newly discovered consequential follow-ups

1. **High: 64-slot file table now hard-fails dynamic loading** (`src/vm/vm_file.c:42`, `src/vm.c:631`). Before this commit, exhausting `g_fmaps` silently dropped tracking and the program ran. Now the 65th live private file mapping returns `-ENOMEM` from `mmap2`. A guest dynamic loader maps each library once, then MAP_FIXED per segment; each fixed remap splits the original entry, so one library costs roughly 4 to 5 slots. Around 12 to 15 shared libraries exhausts the table and `ld.so` aborts. This likely affects the M7 ecosystem and M8 glibc suites. Grow the tables or make them heap-allocated; rejection alone is not a safe default.

2. **Medium: failed MAP_FIXED replacement leaves old pages mapped but untracked** (`src/vm.c:627-645`). Retire runs before `a32_vmfile_check_record` and `a32_vmfile_map_commit`. If either fails, the regions, Soft-TLB entries, and file descriptors for the old range are gone while the host mapping remains. Either run the capacity check before retiring (accounting for slots the retire would free) or re-register the old region on failure.

3. **Medium: `mremap` MAYMOVE discards contents of PROT_NONE mappings** (`src/vm/vm_mremap.c:91`). Covered under R3-3; one-line predicate fix.

4. **Medium: plain-Linux fork skips the JIT quiesce** (`src/os/os_sys_fork_time.c:89`). Covered under R3-4.

5. **Low: execve carry pollutes the guest environment and caps it.** The re-exec path appends three `A32RT_EXEC_SIG*` variables that the guest can observe after exec and nothing unsets them in `main.c`. The fixed `re_envp[520]` array silently drops environment entries past 516.

6. **Low: `src/signals.c` is at 899 lines**, one line below the limit.

---

### Summary

| Item | Status | Note |
|---|---|---|
| A32-R3-1 | VERIFIED | New failure-mode gap on failed MAP_FIXED (Follow-up 2) |
| A32-R3-2 | VERIFIED | Cut survival through `mprotect` promote path not inspected |
| A32-R3-3 | PARTIAL | PROT_NONE copy loss; multi-entry mappings fall back to anonymous |
| A32-R3-4 | PARTIAL | Quiesce only under `hl`; plain-Linux fork unprotected |
| A32-R3-5 | VERIFIED | Reject-without-grow likely breaks dynamic loading (Follow-up 1) |
| A32-R3-6 | VERIFIED | |
| A32-R3-7 | VERIFIED | Static only; `-Werror` fixture builds not run |

Recommended order: Follow-up 1 first since it can turn passing M7/M8 runs into startup failures, then the plain-Linux fork quiesce, then the two `mremap` and MAP_FIXED fixes.
