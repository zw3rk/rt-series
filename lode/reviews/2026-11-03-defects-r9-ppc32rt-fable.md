I have all the evidence. Here's the full review.

---

## Round-9 Remediation Review — Commit `a738212`

### Per-Item Verdicts

#### P32-R9-1 — `MAP_FIXED` stale inode records — **VERIFIED**

`vm_file_untrack_range(target_va, map_end)` added at `ppc32_vm.c:393-394`, guarded by `MAP_FIXED`, placed before the host mmap call. Correctly mirrors the `vm_munmap_locked` teardown path. `MAP_FIXED_NOREPLACE` is correctly excluded (it doesn't replace existing mappings).

#### P32-R9-2 — `MAP_FIXED` stale LL/SC reservations — **VERIFIED**

`vm32_ll_note_remap()` added at `ppc32_vm.c:559-560`, on the success return path after region records are updated. Guards on `MAP_FIXED | MAP_FIXED_NOREPLACE` — the `NOREPLACE` inclusion is harmless (killing a nonexistent reservation is a no-op).

#### P32-R9-3 — `mremap` dead dispatch — **VERIFIED**

`case PPC32_NR_MREMAP:` added at `syscalls.c:628`, dispatching `ppc32_vm_mremap(ctx,a0,a1,a2,a3,a4)`. `PPC32_NR_MREMAP` defined as `163U` at `syscall_nr.h:89`. Cast chain `(long)(int32_t)` matches the convention of neighboring syscall cases.

#### P32-R9-4 — Checked copies bypass EOF trap — **VERIFIED**

Two-site fix:
1. `ppc32_vm_copy.c:62-66`: `vm_range_prot_ok_locked` now iterates page-aligned addresses through the range and rejects any page where `vm32_page_is_eof_trap` returns true.
2. `ppc32_vm.c:844-851`: mremap move path pre-scans source pages for EOF traps before the memcpy, unwinds with `vm_munmap_locked` + `-EFAULT` on hit.

Test coverage added at `check_p32_defects.c:831-838`.

#### P32-R9-5 — Unchecked direct guest accesses — **VERIFIED**

Comprehensive fix across all call sites:
- **convert.c**: All write paths (`put_stat`, `put_stat64`, `put_timespec`, `put_timeval`, `termios_to_guest`, `winsize_to_guest`, `flock_to_guest`, `flock64_to_guest`) add `ppc32_vm_range_prot_ok(ctx, va, sizeof gs, 2U)` and replace `memcpy(ppc32_guest_ptr(...))` with `ppc32_vm_copyout_safe`. All read paths (`get_timespec`, `termios_from_guest`, `winsize_from_guest`, `flock_from_guest`, `flock64_from_guest`) add `ppc32_vm_range_prot_ok(..., 1U)` + `ppc32_vm_copyin_safe`. `flock64_to_guest` (RMW) checks both read and write perms.
- **syscalls.c**: `sys_uname` composes into a stack buffer then `copyout_safe`; 64-bit `clock_gettime` serializes into `tmp[16]` then `copyout_safe`.
- **proc.c:274-277**: `proc_copy_vec` gates each `ppc32_ld32be` with `ppc32_vm_range_prot_ok`.

#### P32-R9-6 — SPE auto-detect missing on initial load — **VERIFIED**

`main.c:363-372`: `guest_load` calls `ppc32_proc_redetect_profile(ctx, info->text_start, info->text_end)` before `ppc32_stack_setup` (which publishes `AT_HWCAP`). The guard `ctx->profile != CLASSIC && != SPE` correctly skips when user forced `--profile`. The `gnu_power_spe` override inside the same block fires correctly after redetect.

#### P32-R9-7 — No attribute-based SPE detection — **PARTIAL**

**What works:**
- Opcode scan cap removed (`proc.c:219` — the `n > 65536` limiter is gone); full text segment is now scanned. Test at `check_p32_defects.c:823-827` confirms detection at instruction 100000.
- `ppc32.h:85`: `gnu_power_spe` field added to `ppc32_elf_info_t`.
- `ppc32_elf32.c:400-410`: `PT_GNU_ATTRIBUTES` handler reads payload via `pread_full` and calls `gnu_attrs_have_power_spe`.
- `main.c:369-371`: initial-load path correctly applies `gnu_power_spe` override (inside the redetect guard block).

**Two bugs:**

1. **Endianness error** in `gnu_attrs_have_power_spe` at `ppc32_elf32.c:136-137`:
   ```c
   slen = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
          ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
   ```
   This reads little-endian, but `.gnu.attributes` section data follows the ELF byte order — big-endian for PPC32. A real 20-byte subsection (`0x00000014` BE) reads as `0x14000000` LE, exceeding the buffer, and the parser bails to "not found." The PT_GNU_ATTRIBUTES path is effectively a no-op on real PPC32 binaries.

2. **Dead override in execve path** at `proc.c:549-551`:
   ```c
   if (info.gnu_power_spe != 0U &&
       ctx->profile != PPC32_PROFILE_CLASSIC &&
       ctx->profile != PPC32_PROFILE_SPE) {
   ```
   After `ppc32_proc_redetect_profile` (line 546), `ctx->profile` is always CLASSIC or SPE. The condition `!= CLASSIC && != SPE` is never true, so the `gnu_power_spe` override never fires in the execve path. Should be `ctx->profile == PPC32_PROFILE_CLASSIC` (upgrade CLASSIC when attribute says SPE).

**Net effect**: The cap removal fixes the primary defect (late-SPE misclassification). The attribute-based path is non-functional but doesn't cause regressions — it silently falls back to the (now uncapped) opcode scan.

#### P32-R9-8 — Cache-block auxv missing — **VERIFIED**

`ppc32_stack32.c:201-206`: `AT_DCACHEBSIZE` (19)=32, `AT_ICACHEBSIZE` (20)=32, `AT_UCACHEBSIZE` (21)=0. Array expanded from 40 to 48 elements (total used: 44, no overflow). Values match 750/e500v2 32-byte cache lines; `AT_UCACHEBSIZE`=0 indicates no unified cache.

#### P32-R9-9 — Silent `argv`/`envp` truncation — **VERIFIED**

`ppc32_stack32.c:61-63`: After the capped scan, `if (count == 511 && strs[511] != NULL) return -1;` detects truncation. The check is safe because `argv`/`envp` are NULL-terminated, so `strs[511]` is always a valid access. No false positive when exactly 511 entries exist (the NULL terminator makes the check pass).

#### P32-R9-10 — Over-strict segment ordering — **VERIFIED**

`ppc32_elf32.c:447-461`: Replaced sequential `prev_seg_end` tracking with pairwise overlap detection using `seg_starts[64]`/`seg_ends[64]`. The interval overlap test `seg_vaddr64 < seg_ends[s] && seg_end64 > seg_starts[s]` is the standard half-open interval intersection check. Minor note: >64 PT_LOAD segments silently lose tracking, but this never occurs in practice. `PPC32_TASK_SIZE_TOP` is `0xC0000000` (3 GiB), so `seg_end64` fits in `uint32_t` — no truncation risk.

---

### Curated C11 Compliance

| Check | Result |
|-------|--------|
| VLAs | None found (`uint8_t attrs[4096]` is a fixed-size constant) |
| `.c` includes | None |
| File sizes <= 900 lines | All pass (max: `ppc32_vm.c` at 899) |
| `sprintf`/`strcpy`/`strcat` | None in changed code |

### Newly Introduced Bugs

| Location | Issue | Severity | Impact |
|----------|-------|----------|--------|
| `ppc32_elf32.c:136-137` | Subsection length read as LE in a BE section | Medium | PT_GNU_ATTRIBUTES detection is a no-op; falls back to opcode scan (no crash) |
| `proc.c:549-551` | `gnu_power_spe` override condition always false after `redetect_profile` | Low | Dead code in execve path only; initial load path works correctly |

### Summary

| Item | Verdict |
|------|---------|
| P32-R9-1 | **VERIFIED** |
| P32-R9-2 | **VERIFIED** |
| P32-R9-3 | **VERIFIED** |
| P32-R9-4 | **VERIFIED** |
| P32-R9-5 | **VERIFIED** |
| P32-R9-6 | **VERIFIED** |
| P32-R9-7 | **PARTIAL** (opcode scan fixed; attribute parser broken by LE/BE endianness + dead execve override) |
| P32-R9-8 | **VERIFIED** |
| P32-R9-9 | **VERIFIED** |
| P32-R9-10 | **VERIFIED** |

**9/10 VERIFIED, 1 PARTIAL (P32-R9-7), 0 REGRESSIONS.** The two R9-7 bugs are non-crashing and covered by the opcode scan fallback, but the attribute-based detection path needs a follow-up: fix the subsection length to big-endian read, and change the proc.c execve guard to `ctx->profile == PPC32_PROFILE_CLASSIC`.
