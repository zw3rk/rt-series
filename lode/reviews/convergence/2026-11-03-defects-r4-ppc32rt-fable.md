# Round-4 remediation review: `9a9c211` vs `f083489`

Scope: static review of the commit diff plus the post-state of `src/vm/vm_file.c`, `src/vm/vm_file_stage.c`, `src/vm/vm_file_int.h`, `src/rt32/ppc32_vm_copy.c`, `src/interp/llsc.c`, and the touched call sites. No build, test, Docker, or QEMU run. Verdicts are code-path conclusions.

**Headline:** 10 of 13 items are fixed as described. The P32-R4-3 coherence fan-out introduces a consequential regression that silently reverts guest stores and `read()` results landing in A2 staged MAP_SHARED mappings. Two further items are partial.

## Per-item verification

**P32-R4-1 readv result depletion: VERIFIED.**
`sys_vec` keeps the count in `result` and invalidates each landed chunk immediately after the chunk's `readv` returns, partial-aware via `rem`. Error returns after progress preserve both count and invalidation. The `len == 0` iovec case is handled by the early return in `sys_read_landed`.

**P32-R4-2 staging grow source offset: VERIFIED.**
`stage_fill` now reads from `file_off + stage_off + done`. The grow call passes `(file_offset, old, need - old)`, so the extension comes from `file_offset + old`. The refresh call passes `(glo, rlo - glo, rhi - rlo)`, which resolves to file offset `rlo`. Both are correct.

**P32-R4-3 overlapping shared aliases: REGRESSION.**
The design changed from unified backing to write-through fan-out. The fan-out is ordered wrongly and destroys the data it is meant to propagate.

Mechanism, in `cohere_locked` at `src/vm/vm_file_stage.c:551`:

1. The interpreter store helpers in `src/interp/interp.h:318-364` write the bytes first, then call `store_bump`, which calls `vm_file_shared_cohere_store`. Same order in `ppc32_vm_copyout_safe` at `src/rt32/ppc32_vm_copy.c:149-154`, in `vm32_sc_attempt` after a successful CAS, and in `sys_read_landed` after `read()` lands.
2. `cohere_locked` takes `hva = ppc32_guest_ptr(ctx, lo)`, a pointer into the storing alias, which for a staged alias is a `MAP_SHARED` mapping of the group's memfd.
3. It then calls `stage_refresh_groups(dev, ino, flo, fhi)`, which unconditionally `pwrite`s the file's bytes for `[flo, fhi)` into every overlapping group of that inode, including the storing alias's own group. The memfd page cache is the alias's backing, so the bytes at `hva` now hold the file's old contents. The guest's store is gone.
4. `stage_fanout_groups` then copies those stale bytes into the groups and the file.

Consequences on A2 hosts whenever any staged group is live: every ordinary store, every `stwcx.` success, every syscall copyout, and every `read()` into a staged MAP_SHARED region is reverted to the file's prior contents. A spin lock acquired with `stwcx.` through such a mapping appears unacquired afterwards. Direct kernel-mapped aliases are unaffected because their `hva` and the file agree. The DBT includes `interp/interp.h` from `src/dbt/dbt.c`, so any slow-path store routed through those helpers inherits the problem. I did not confirm which DBT paths use them.

Fix: drop the `stage_refresh_groups` call from `cohere_locked`. The fan-out overwrites exactly `[flo, fhi)` in every group anyway, so the refresh buys nothing and only reverts the landed bytes. If a refresh of neighbouring groups is wanted, capture the landed bytes into a bounded bounce buffer before refreshing. Also note the DBT's native store path does not call the hook at all, so overlapping-alias coherence under `--difftest` is interp-only even after the fix.

**P32-R4-4 stale drain over newer file: PARTIAL.**
The acquire path now refills from the file on a size or mtime change instead of draining. That part is correct. Two blind drains remain. `vm_file_shared_drop_group` drains the whole group extent on GC, and `vm_file_shared_writeback_file_range` is still called from `src/rt32/ppc32_vm_regions.c:778` without dirty tracking. A foreign file write after the last refresh is still overwritten on munmap. The commit comment argues write-through makes staged bytes equal the file, but that only holds once R4-3 is fixed and only for bytes written through the translator.

**P32-R4-5 GC drops live group after front trim: VERIFIED.**
`staged_group_referenced_locked` now matches MAP_SHARED regions of the same inode by file-range overlap, so a trimmed VMA with a shifted offset still pins its group. `vm_file_shared_group_key` exports the length for this.

**P32-R4-6 automatic placement skips shared tails: VERIFIED.**
`vm_find_free_gap_aligned_locked` applies `ppc32_vm_a2_host_page_busy` to the cursor candidate, every gap candidate, and the tail scan. Each loop advances by `align` and is bounded by the mmap top. Cost is quadratic in region count per placement, which is acceptable at current table sizes.

**P32-R4-7 EOF trapping gaps: VERIFIED.**
Zero-length files are valid EOF. The first trap offset clamps to `max(map_offset, rounded_eof)`. The call in `vm_mmap2_locked` now fires for all A2 file mappings, not only shared ones.

**P32-R4-8 fork versus truncate lock inversion: VERIFIED.**
Truncate runs in two phases. Phase 1 holds only the inode lock and touches no TLB or guest state. Phase 2 holds the VM lock with the inode lock released. `vm_file_hook_write` now nests VM then inode. The staging TU takes neither the inode nor the TLB lock. `vm_lock_held_by_self` lets the helpers run from both locked and unlocked contexts without re-entry. I found no remaining inode-to-TLB nesting.

**P32-R4-9 truncate writes through inaccessible mappings: PARTIAL.**
The private path is fixed: `file_zero_private_span` widens the host pages writable, zeroes, then restores the sub-page union. Direct mappings are left to the kernel. The staged path is a no-op on shrink. `vm_file_shared_truncate_range` clamps `hi` to the current file size, which is already the new size after the host `ftruncate`, and `lo` is at least the new size, so it returns before writing. The partial tail page in a staged mapping keeps stale non-zero bytes after a shrink, and a later regrow re-exposes them as readable through `file_truncate_rerecord` instead of zeros. The clamp protects the file, but this function writes the staging object, not the file, so the clamp should be the group's extent instead. Minor nit: zeroing also hits already dirtied private COW pages, which Linux would leave alone.

**P32-R4-10 alias tracking by fd number: VERIFIED.**
`file_register` keeps one slot per `(fd, gva_base, pages, map_offset)` and refreshes only an identical range. Truncate and the write hook match by `(st_dev, st_ino)`. Slot pressure on `VM_FILE_INODES` rises since every mapping takes a slot and exhaustion fails silently. That is pre-existing behaviour, now more reachable.

**P32-R4-11 syscall access bypasses sub-page permissions: PARTIAL.**
`read`, `write`, `pread`, `readv`, `writev`, `ppc32_copyin`, and `ppc32_copyout` now check per sub-page permissions. The struct conversion helpers in `src/os/convert.c:183-493` and `ppc32_copyin_str` at line 169 still use raw `memcpy` through `ppc32_guest_ptr`. Those are the paths used for stat, termios, flock, and string arguments, so the audit's laundering case still applies there. The permission check also runs before the blocking host call with the VM lock released, so a concurrent `mprotect` or `munmap` can still change the target. That is a known residual, not a regression.

**P32-R4-12 copyout does not invalidate peer reservations: VERIFIED.**
`ppc32_vm_copyout_safe` bumps every spanned 64-byte bucket after the copy, and `sys_read_landed` does the same for landed read bytes. The write-then-bump ordering matches the interpreter's own store helpers, so the residual window is no worse than an ordinary guest store.

**P32-R4-13 unused broadcast truncate: VERIFIED.**
`vm_file_on_truncate` is gone from both the header and the TU. Only the identity form remains, now declared in `vm/vm32.h`.

## Compliance

- No `#include "*.c"` anywhere under `src/` or `include/`.
- No `sprintf`, `strcpy`, or `strcat`. The only fixed buffers are `char buf[8192]` and a `static const` zero page. No VLAs.
- Largest files after the split: `threads.c` 884, `ppc32_vm.c` 879, `proc.c` 872, `vm_file_stage.c` 746. All at or under 900. The two rt32 VM files are within 25 lines of the limit.
- New TUs `llsc.c`, `ppc32_vm_copy.c`, `vm_file_stage.c` are picked up by the Makefile wildcards and carry the required license headers.
- `vm_file_int.h` uses `st_mtim`, which needs `_POSIX_C_SOURCE 200809L`. Both including TUs define it before the include.

## Summary table

| Item | Status | Note |
|---|---|---|
| P32-R4-1 | VERIFIED | Count preserved, per-chunk invalidation |
| P32-R4-2 | VERIFIED | Source offset tracks destination bias |
| P32-R4-3 | REGRESSION | Refresh-before-fanout reverts landed stores and reads in staged aliases |
| P32-R4-4 | PARTIAL | Acquire path fixed. GC and writeback drains still blind |
| P32-R4-5 | VERIFIED | Overlap-based GC identity |
| P32-R4-6 | VERIFIED | All three placement scans guarded |
| P32-R4-7 | VERIFIED | Empty file, beyond-EOF, and A2 private covered |
| P32-R4-8 | VERIFIED | Two-phase truncate, VM then inode in write hook |
| P32-R4-9 | PARTIAL | Private path safe. Staged shrink zeroing is a no-op |
| P32-R4-10 | VERIFIED | Per-mapping slots, inode identity matching |
| P32-R4-11 | PARTIAL | Byte-stream paths fixed. Struct and string helpers still raw |
| P32-R4-12 | VERIFIED | Range bump after copyout and landed reads |
| P32-R4-13 | VERIFIED | Removed |

## Newly discovered consequential follow-ups

- **P32-R5-1 (High, from R4-3):** `cohere_locked` refreshes the storing alias's own staging group from the file before fanning out, reverting the guest's store, `stwcx.` result, copyout, or `read()` data. Remove the refresh from the store and read fan-out paths, or snapshot the landed bytes first. Add a staged-alias regression that stores through alias A and reads through alias B at both identical and overlapping offsets on a 16 KiB host page regime.
- **P32-R5-2 (High, from R4-9):** `vm_file_shared_truncate_range` clamps to the post-truncate file size and never zeroes on shrink. Clamp to the group extent instead. Test shrink, read the partial tail page through a staged alias, then regrow and re-read.
- **P32-R5-3 (Medium, from R4-3):** When any staged group is live, every interpreter store to a MAP_SHARED file region performs an `fstat` plus several `pread` and `pwrite` calls under the VM spin lock. Measure before optimising, but expect a large interpreter slowdown on shared-memory-heavy A2 workloads. The DBT's native store path performs no fan-out at all, so interp and DBT diverge in observable alias contents.
- **P32-R5-4 (Low, from R4-12):** `vm32_store_invalidate_range` iterates once per 64-byte line of the range even though the table has 1024 buckets. A large `read()` into guest memory does millions of atomic increments. Cap the loop at 1024 iterations.
- **P32-R5-5 (Low, from R4-11):** Migrate the struct conversion helpers and `ppc32_copyin_str` in `src/os/convert.c` onto the permission-aware copy helpers to close the remaining sub-page laundering paths.
