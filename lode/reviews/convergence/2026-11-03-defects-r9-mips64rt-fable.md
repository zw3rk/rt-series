I have all the evidence. Here's the complete static review of commit `1b7808e` against the Round-9 defect list.

---

## Round-9 Remediation Review — commit `1b7808e`

### Per-item verdicts

**M64-R9-1 — `uname` bypasses SMC code retirement: VERIFIED**
- `src/os/syscall_min.c:427`: added `mips_vm_pages_retire_code(va, MIPS_UTS_SIZE);` immediately after `mips_vm_pages_clear`, matching the prescribed one-line fix exactly. The call now aligns with every other staged-copyout site (`read`, `readv`, `getdents64`, `getrandom`, `sigframe`, `waitid`).

**M64-R9-2 — `MAP_FIXED|MAP_FIXED_NOREPLACE` replaces instead of `EEXIST`: VERIFIED**
- `src/os/syscall_min.c:321`: EEXIST probe guard changed from `(flags & MIPS_MAP_FIXED) == 0U` to `(flags & MIPS_MAP_FIXED_NOREPLACE) != 0U`. Now fires whenever NOREPLACE is set, regardless of FIXED.
- `src/os/syscall_min.c:354-357`: dispatch reordered — NOREPLACE tested before FIXED. With both flags set, the EEXIST probe runs and the non-replace path is taken. FIXED-only still routes to `replace_inner`. Correct per `mmap(2)`.

**M64-R9-3 — `mmap` accepts invalid map type: VERIFIED**
- `src/os/syscall_min.c:302-306`: added `EINVAL` for missing or conflicting SHARED/PRIVATE bits, matching the exact prescribed check.

**M64-R9-4 — empty region table makes fetch host-fault: VERIFIED**
- `src/os/mem_table.c:794-800`: removed the `g_region_count == 0` → `ok = 1` special case. Empty table now returns `ok = 0`, delivering guest `SIGSEGV` instead of a host fault.
- `tests/test_decode.c:39-49`: `use_scratch_window` now records a `[0, 0x3000)` EXEC region via `mips_mem_restore` so fetch tests work with the corrected exec_ok.
- `tests/test_decode.c:470-475`: new test verifies that an emptied table (`mips_mem_reset()`) causes `mips_fetch` to return `MIPS_FAULT`.

**M64-R9-5 — `mem_lock`↔`vm_lock` ABBA deadlock: VERIFIED**
- Two snapshot-before-lock mechanisms break both inversion paths:
  - **Moving mremap** (`mem_table.c:597-598`): `mips_vm_file_snapshot_spans` takes `vm_lock`, snapshots file pages, releases `vm_lock` — all before `mem_lock`. The copy (`mips_vm_file_copy_span` at `vm_file_sync.c:503-544`) consults the snapshot with no lock.
  - **Remap hook** (`vm_file.c:811`): `mips_vm_prot_snapshot` calls `mips_mem_region_count`/`region_at` (each acquires and releases `mem_lock`) before `vm_lock`. `mips_vm_prot_apply` (`vm_file_sync.c:571-587`) is a pure `mprotect` loop over the snapshot, no `mem_lock`.
- Old `vm_inode_apply_region_prots` (the vm_lock→mem_lock path) deleted from `vm_file.c`.
- `vm_file_int.h:53-62`: new `mips_vm_prot_t` type and snapshot/apply prototypes.
- `copy_host_prot` in `vm_file_sync.c` matches `u0f_host_prot` semantics exactly (R+W only, EXEC stripped per W^X invariant).

**M64-R9-6 — PT_INTERP endianness unchecked: VERIFIED**
- `src/loader.c:831`: added `|| ieh.be != eh.be` to the interpreter ELF validation. Mismatched-endian `ld.so` now gets `ENOEXEC`.

**M64-R9-7 — `MAP_SHARED` anon demoted to private: VERIFIED**
- `src/os/syscall_min.c:312`: `shared` variable set for anon + SHARED.
- `src/os/mem_table.c:264,394`: `map_inner`/`replace_inner` pass `MAP_SHARED` (not `MAP_PRIVATE`) to host `mmap` when `shared != 0`.
- All three `sc_mmap` dispatch paths (NOREPLACE :356, FIXED :359, hole :372) use `_shared` variants when applicable.
- `src/os/syscall_min.c:442-445`: fork comment updated to reflect preserved sharing.
- `mark_shared` at `mem_table.c:226-232` sets `MIPS_REGION_SHARED` on covered regions (metadata only — flag is write-only in this commit).

---

### Newly introduced issues

| Severity | Location | Issue |
|---|---|---|
| Minor | `mem_table.c:226-232` | `mark_shared` fails to mark a region when `insert_region` merges it with an adjacent region (same prot+tag "map") because the merged region's `start < va` or `end > va+len`. Currently benign since `MIPS_REGION_SHARED` is write-only, but will be wrong if the flag gains readers. |
| Minor | `vm_file_sync.c:552-568` | `mips_vm_prot_snapshot` calls `mips_mem_region_count()` then N individual `mips_mem_region_at()` calls, each taking/releasing `mem_lock` independently. A concurrent table change yields a partial or stale snapshot. Acceptable for best-effort host-page prot restore. |
| Style | `syscall_min.c:356,367,372` | Nested ternary expressions on single lines exceed 100 chars. Readability only. |

No regressions, no security issues, no ABBA lock paths remain.

### Curated C11 compliance

- No VLAs, no `.c` includes, no `sprintf`/`strcpy`/`strcat`, no `_Generic`, no Annex K — **pass**
- Stack arrays `mips_vm_prot_t snap[512]` in `vm_file.c:775,806` are ~10 KB; within standard stack limits

### File size discipline (all <= 900 lines)

| File | Lines |
|---|---|
| `src/os/syscall_min.c` | **899** (just under the 900 limit) |
| `src/os/mem_table.c` | 893 |
| `src/loader.c` | 870 |
| `src/vm/vm_file.c` | 867 |
| `src/vm/vm_file_sync.c` | 587 |
| `tests/test_decode.c` | 564 |
| `src/vm/vm_file_int.h` | 73 |

**All 7 items: VERIFIED.** The `mark_shared` merge-safety issue is the only concrete finding worth tracking for a future commit if `MIPS_REGION_SHARED` becomes load-bearing.
