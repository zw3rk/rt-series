# Multi-Agent Work Order — Wave U4 (`hyper-linux`: Provider B Generalization & 10-Translator Dispatch)

## Context & Authority
- **Master Plan**: `/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md` (Rev 4) — read **§1–§3, §4.4, §5.2, §6, §9, §10.2 (Wave U4), §11.5 (`RC-U4`), and §12** in full before spawning any lanes.
- **Host Contract**: `/Users/angerman/Projects/zw3rk/rt-series/docs/HOST-CONTRACT.md` and `/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h` (`A32H_ABI 1.1`).
- **Wave Card**: `/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/wave-u-unification.md` (`U4-A` and `U4-B`).
- **Target Repository**: `/Users/angerman/Projects/zw3rk/hyper-linux`.

---

## Execution Model (Muse Multi-Agent Workflow)
You are the **Pod Coordinator** for **Wave U4 (`hyper-linux`)**.
1. **Worktree Isolation**:
   - Create two disjoint isolated git worktrees from `hyper-linux` `master`:
     - `../hyper-linux-u4a` on branch `lane/u4a-provider-b-mmap-truncate`
     - `../hyper-linux-u4b` on branch `lane/u4b-translators-a32host`
2. **Parallel Fan-Out**:
   - Spawn `U4-A` and `U4-B` concurrently with strict disjoint file ownership.
   - Review diffs, merge `--no-ff` to `master`, and run all host/guest tests.

---

## Milestone 1 — Lane `U4-A` (`../hyper-linux-u4a`: Provider B Page-Size-Aware Shared Views & Truncation Fence)

### Owned Files in `/Users/angerman/Projects/zw3rk/hyper-linux`
- `src/rvrt_shared.h`, `src/rvrt_shared.c`
- `src/syscall_fs.c` (only `rvrt_shared_truncate_allowed` / `HL_MEMORY_POLICY_RVRT` call sites)
- `test/host/test-rvrt-shared-*.c` (or new `test/host/test-provider-b-sparc64-8k.c`)

### Required Implementation
1. **Page-Size-Aware `rvrt_shared_file_covers()` (`src/rvrt_shared.h:47-52`, `src/rvrt_shared.c:84-120, 212-238`)**:
   - Currently `rvrt_shared_file_covers(file_size, offset, length)` hardcodes `4095u` / `4096u` (`offset + length - 4096u < file_size`).
   - Add `uint64_t guest_page_size` to `guest_t` (default `4096`, set to `8192` when launching `sparc64rt` / `EM_SPARCV9`) and add `rvrt_shared_file_covers_page(uint64_t file_size, uint64_t offset, uint64_t length, uint64_t guest_page_size)`:
     - Require `(offset & (guest_page_size - 1)) == 0` and `(length & (guest_page_size - 1)) == 0`.
     - Require `offset + length - guest_page_size < file_size` so no whole guest ABI page (`4096` or `8192` on `sparc64rt`) lies beyond EOF.
   - Keep `rvrt_shared_file_covers(file_size, offset, length)` as an inline wrapper passing `4096u` for backward compatibility with existing host unit tests.
2. **Sub-16K Offset Bias & Truncation Fence (`src/rvrt_shared.c`)**:
   - Verify `map_host_fd()` and `map_existing_file_view()` handle `file_offset` aligned to `4096` or `8192` on a 16 KiB Darwin host (`aligned_offset = file_offset & ~(host_page - 1)`, `bias = file_offset - aligned_offset`, `guest_alias_range(g, va, va + length, ipa + bias, perms)`).
   - Verify `rvrt_shared_truncate_allowed(g, host_fd, new_size)` (`src/rvrt_shared.c`) and `O_TRUNC` / `truncate` / `ftruncate` checks in `src/syscall_fs.c:1524, 1965, 5749, 5919` work identically for all 5 Class-B translators (`rvrt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) under `HL_MEMORY_POLICY_RVRT`.
3. **Host Unit Test**:
   - Add a deterministic host test verifying 4 KiB and 8 KiB (`sparc64rt`) sub-16K offset bias (`file_offset = 4096`, `8192`, `12288`), partial-EOF zero-fill admission, and `rvrt_shared_truncate_allowed()` rejection when truncation would drop a retained view past EOF.

---

## Milestone 2 — Lane `U4-B` (`../hyper-linux-u4b`: 10-Translator Dispatch Table, `A32H_ABI 1.1`, & Authority Env)

### Owned Files in `/Users/angerman/Projects/zw3rk/hyper-linux`
- `src/a32host.h`, `src/device.c`, `src/syscall_io.c`
- `src/a32.h`, `src/a32.c`
- `src/rvrt_mode.h`, `src/rvrt_mode.c`
- `src/hl.c`, `src/syscall_proc.c`
- `test/host/test-guest-translators.c` (new host unit test)

### Required Implementation
1. **Sync `src/a32host.h` & `/dev/a32host` to `A32H_ABI 1.1`**:
   - Sync `src/a32host.h` with `/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h` (`A32H_ABI_MAJOR = 1`, `A32H_ABI_MINOR = 1`).
   - In `src/device.c` (`a32host_ioctl`) and `src/syscall_io.c`:
     - Advertise `A32H_ABI_MINOR = 1` and `A32H_CAP_PAGE4K | A32H_CAP_WX_ENFORCED | A32H_CAP_ICACHE_TRAP_IALLU | A32H_CAP_DIROFF32 | A32H_CAP_SET_PROC | A32H_CAP_COMPAT_IOCTL | A32H_CAP_ROBUST32`.
     - Handle `A32H_SET_PROC` (`0x40406104UL`: update guest `/proc/self/exe` and `/proc/self/cmdline` from `a32h_proc_t`), `A32H_SET_ROBUST_LIST32` (`0x40106103UL`), and `A32H_COMPAT_IOCTL` (`0xc0186102UL`).
2. **Generalize Class-A 32-Bit Translator Loader (`src/a32.h`, `src/a32.c`)**:
   - Extend `a32_probe_elf32()` (or add `hl_probe_rt32_elf(path, &e_type, &e_machine, &ei_data, &e_flags)`) to recognize all 5 Class-A 32-bit architectures:
     - `EM_ARM` (`40`, `ELFCLASS32`, `ELFDATA2LSB`) -> `a32rt` (`--a32rt` / `HL_A32RT` / `../a32rt/_build/a32rt`)
     - `EM_386` (`3`, `ELFCLASS32`, `ELFDATA2LSB`) -> `i686rt` (`--i686rt` / `HL_I686RT` / `../i686rt/_build/i686rt`)
     - `EM_MIPS` (`8`, `ELFCLASS32`, `ELFDATA2LSB` or `ELFDATA2MSB`, O32) -> `mips32rt` (`--mips32rt` / `HL_MIPS32RT` / `../mips32rt/_build/mips32rt`)
     - `EM_PPC` (`20`, `ELFCLASS32`, `ELFDATA2MSB`) -> `ppc32rt` (`--ppc32rt` / `HL_PPC32RT` / `../ppc32rt/_build/ppc32rt`)
     - `EM_SPARC` (`2` or `EM_SPARC32PLUS = 18`, `ELFCLASS32`, `ELFDATA2MSB`) -> `sparc32rt` (`--sparc32rt` / `HL_SPARC32RT` / `../sparc32rt/_build/sparc32rt`)
3. **Generalize Class-B 64-Bit (and RV32GC) Translator Dispatch (`src/rvrt_mode.h`, `src/rvrt_mode.c`, `src/hl.c`, `src/syscall_proc.c`)**:
   - Extend `hl_rvrt_initial_elf_kind()` and `hl_rvrt_target_open()` to recognize all Class-B foreign ELF targets under `HL_MEMORY_POLICY_RVRT`:
     - `EM_RISCV` (`243`, `ELFCLASS64` or `ELFCLASS32`, `ELFDATA2LSB`) -> `rvrt` (`--rvrt` / `HL_RVRT` / `../rvrt/_build/rvrt`)
     - `EM_LOONGARCH` (`258`, `ELFCLASS64`, `ELFDATA2LSB`) -> `loongarch64rt` (`--loongarch64rt` / `HL_LOONGARCH64RT` / `../loongarch64rt/_build/loongarch64rt`)
     - `EM_PPC64` (`21`, `ELFCLASS64`, `ELFDATA2LSB`, `e_flags & 3 == 2`) -> `ppc64rt` (`--ppc64rt` / `HL_PPC64RT` / `../ppc64rt/_build/ppc64rt`)
     - `EM_MIPS` (`8`, `ELFCLASS64` N64 or `ELFCLASS32` with `EF_MIPS_ABI2` N32) -> `mips64rt` (`--mips64rt` / `HL_MIPS64RT` / `../mips64rt/_build/mips64rt`)
     - `EM_SPARCV9` (`43`, `ELFCLASS64`, `ELFDATA2MSB`, sets `g->guest_page_size = 8192`) -> `sparc64rt` (`--sparc64rt` / `HL_SPARC64RT` / `../sparc64rt/_build/sparc64rt`)
   - Propagate both `<ARCH>RT_HOST_EXEC_AUTHORITY=hyper-linux-apfs-acl-v1` and `RT_HOST_EXEC_AUTHORITY=hyper-linux-apfs-acl-v1` (plus `<ARCH>RT_CACHE_DIR` / `RT_CACHE_DIR`).
4. **Host Unit Test (`test/host/test-guest-translators.c`)**:
   - Verify ELF probing and translator resolution for all 11 foreign guest targets (`EM_ARM`, `EM_386`, `EM_MIPS` O32 BE/LE, `EM_PPC`, `EM_SPARC`, `EM_RISCV` RV64/RV32, `EM_LOONGARCH`, `EM_PPC64`, `EM_MIPS` N64/N32, `EM_SPARCV9`) and `/dev/a32host` `A32H_ABI 1.1` ioctl handshake.

---

## Verification Gates (`RC-U4`)
1. Run host unit tests for `U4-A` (`test-provider-b-sparc64-8k`) and `U4-B` (`test-guest-translators`).
2. Verify `/Users/angerman/Projects/zw3rk/hyper-linux/src/a32host.h` is byte-identical to `/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h`:
   ```sh
   make -C /Users/angerman/Projects/zw3rk/rt-series check-headers
   ```
3. Merge both branches cleanly into `master` with `--no-ff`.
