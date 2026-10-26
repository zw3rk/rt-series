# Work Order — Pane 5 (`0:9.5`): Stage-Gate Remediation for `sparc64rt` (`RC-U12-sparc64`) & `../hyper-linux-u4` (`RC-U4`)

Read both independent stage-gate review reports:
1. `/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-26-rc-sparc64-fable-high.md` (`sparc64rt` `RC-U12-sparc64`)
2. `/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-26-rc-u4-astra-xhigh.md` (`hyper-linux-u4` `RC-U4`)
3. `/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h`

Fan out parallel worktree lanes to close every P1, P2, and P3 finding in both reports!

---

## Milestone A — `sparc64rt` Stage-Gate (`RC-U12-sparc64`) Remediation (`lode/reviews/2026-10-26-rc-sparc64-fable-high.md`)

1. **P1 — Wire the 7-Instruction Soft-TLB Emitter into Live DBT (`src/dbt/emit_int.c`, `src/dbt/emit_mem.c`, `src/dbt/mem_sites.c`)**:
   - Initialize the Soft-TLB (`sparc64_tlb_init`) on context/thread startup so `read_tag` and `write_tag` are initialized to invalid sentinels (`~0ULL`) rather than `0` (preventing false VPN 0 hits).
   - Wire `e_emit_mem` (`src/dbt/emit_int.c:718`) to emit the 7-instruction BE Soft-TLB fast path (`sparc64_mem_emit_fast`) + per-block cold stub tail (`sparc64_mem_emit_tail` / `sparc64_mem_block_alloc`).
   - In the miss helper (`src/dbt/mem_sites.c:129-159`), actually populate the Soft-TLB entry (`sparc64_tlb_fill`) when the accessed 4 KiB page is valid and permitted so subsequent accesses hit the inline 7-instruction fast path!
2. **P2 — Fix Load-Miss Continuation Contract (`src/dbt/emit_mem.c`, `src/dbt/mem_sites.c`)**:
   - Ensure the slow-path load miss continuation reloads the destination value (or writes directly to `ctx->r[rd]` before jumping past the fast-path register writeback) so `x0` (the host resume address for `br x0`) is never written into the guest destination register on a TLB miss!
3. **P2 — Wire Provider A (`src/vm/vm_file.c`, `src/vm/vm64.c`), 6-Step Quiescence, and `ftruncate`/`truncate`/`mremap` Syscalls (`src/os/syscalls_*.c`, `src/os/guest_run.c`)**:
   - Call `rt_host_install_signal_handlers` at runtime initialization so the preemption signal handler (`SIGRTMIN+1` on Linux, `SIGUSR2` on Darwin) is active and rewinds in-flight Soft-TLB sequences via `vm64_seq_rewind`.
   - Connect `vm64_txn_prepare` / `vm64_txn_host_op` / `vm64_txn_commit` and `src/vm/vm_file.c` (`vm64_cow_promote_8k`, `vm64_eof_upper_half`) to live guest `mmap`, `mprotect`, `munmap`, `mremap` (NR 250, enforcing 8 KiB `GUEST_ABI_PAGE_SIZE` alignment), and `truncate`/`ftruncate` (NRs 77, 84, 129, 130).
   - Serialize `dbt_mem_site_t[]` records in `src/dbt/aot/`.
   - Add `tests/test_rc_u2_8k_cow_eof.c` covering 8 KiB COW promotion, `[st_size, 8 KiB)` EOF tail zeroing, beyond-EOF `SIGBUS`, failed `ftruncate`/`mprotect` state preservation, and `mremap` 8 KiB alignment.
4. **P3 — Cleanup**:
   - Remove unused `SPARC64_AT_PAGESZ UINT64_C(4096)` at `src/os/mem_space.h:19-23`, remove `-Wno-error=unused-function` in `Makefile:108-112` by marking unused static helpers `__attribute__((unused))` or conditionalizing them, and document `x5` scratch clobber on 16-byte stores in `src/dbt/emit_mem.h`.
   - Merge to `sparc64rt` `master` and verify `make check`, `make build-darwin`, `tests/check_host_contract.sh`, and `tests/parity_suite.sh` all pass.

---

## Milestone B — `../hyper-linux-u4` Stage-Gate (`RC-U4`) Remediation (`lode/reviews/2026-10-26-rc-u4-astra-xhigh.md`)

All work for `hyper-linux` MUST remain strictly inside `/Users/angerman/Projects/zw3rk/hyper-linux-u4` (`branch lane/u4-integration`). Do NOT touch `/Users/angerman/Projects/zw3rk/hyper-linux`'s main working tree.

Fix every P1, P2, and P3 finding in `lode/reviews/2026-10-26-rc-u4-astra-xhigh.md`:

1. **P1 — Actual 10-Translator Dispatch (`src/hl.c`, `src/syscall_exec.c`, `src/a32.[ch]`, `src/rvrt_mode.[ch]`)**:
   - Define the unified `hl_translators[]` table (covering all 10 translators / 11 ELF targets: Class-A `a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`; Class-B `rvrt` RV64+RV32, `loongarch64rt`, `ppc64rt`, `mips64rt` N64+N32, `sparc64rt`).
   - In `src/hl.c` startup (`hl_translator_dispatch_note` / guest ELF loading) and `src/syscall_exec.c` (`sys_execve` foreign ELF binfmt dispatch): when a foreign ELF matches a Class-A or Class-B entry in `hl_translators[]` and the translator binary resolves, actually rewrite the launch/exec target to execute the resolved translator binary (`[translator_path, guest_elf_path, ...guest_argv]`), propagate `<PREFIX>_HOST_EXEC_AUTHORITY=hyper-linux-apfs-acl-v1` + `RT_HOST_EXEC_AUTHORITY=hyper-linux-apfs-acl-v1`, stamp `guest->guest_page_size` (8192 for `EM_SPARCV9`, 4096 for all others including 32-bit `EM_SPARC`), and select `HL_MEMORY_POLICY_RVRT` for all Class-B translators (including `rvrt` for `ELFCLASS32` `EM_RISCV` and `mips64rt` for `ELFCLASS32` `EM_MIPS` `EF_MIPS_ABI2`).
2. **P1 / P2 — Provider-B `rvrt_shared`, `syscall.c`, `syscall_fs.c`, and `fork_ipc.c`**:
   - **`src/syscall.c:2318`**: Replace the legacy 4096-byte `rvrt_shared_file_covers_page()` precheck call with `rvrt_shared_file_covers_guest_page(..., guest_page_size)` so `EM_SPARCV9` (`guest_page_size == 8192`) admits partial 8 KiB pages (e.g. `st_size = 1, offset = 0, len = 8192`) and zero-fills the `[st_size, 8192)` tail.
   - **`src/fork_ipc.c`**: Because fork uses `posix_spawn` (`fork_ipc.c:7858`), process-global state in the child resets to 4096 before IPC restore. Serialize `guest->guest_page_size` explicitly in the fork IPC snapshot/wire payload and restore both `guest->guest_page_size` and `hl_translator_note_guest_page_size(guest->guest_page_size)` on the child side.
   - **`src/rvrt_shared.[ch]` & `src/syscall_fs.c`**: Implement the Provider-B beyond-EOF `SIGBUS` range tracking and truncation fence across shared views: when `ftruncate` / `truncate` / `O_TRUNC` shrinks a file backing a shared mapping, zero any partial tail `[new_size, round_up(new_size, guest_page_size))`, record/invalidate stripped full pages `[round_up(new_size, guest_page_size), old_end)` as beyond-EOF `SIGBUS` ranges (instead of failing `ftruncate` with `EBUSY` on shrunk pages), and expose an invalidation epoch/counter so translators flush stale Soft-TLB entries.
3. **P2 — MIPS N32 (`EF_MIPS_ABI2`) & PPC64 ELFv2 (`(e_flags & 3) == 2`) ELF Probing**:
   - Read at least 52 bytes (full `Elf32_Ehdr` / `Elf64_Ehdr` through `e_flags`) in both probes.
   - `EM_MIPS` + `ELFCLASS32`: decode `e_flags` (respecting `ELFDATA2LSB` vs `ELFDATA2MSB` endianness!). If `(e_flags & 0x20U) != 0` (`EF_MIPS_ABI2`), reject in Class-A (`mips32rt`) and route to Class-B `mips64rt`!
   - `EM_PPC64`: require `ELFCLASS64`, `ELFDATA2LSB`, AND `(le32(e_flags) & 3U) == 2U` (ELFv2 ABI) for `ppc64rt`.
4. **P2 — `/dev/a32host` `A32H_ABI 1.1` Sync, Ioctl Encodings, Forwarding, and Effects**:
   - Copy the updated `/Users/angerman/Projects/zw3rk/rt-series/include/a32host.h` into `/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32host.h` (`cmp -s src/a32host.h /Users/angerman/Projects/zw3rk/rt-series/include/a32host.h` must pass).
   - Use the canonical ioctl numbers and structs from `src/a32host.h`:
     - `A32H_COMPAT_IOCTL = 0xc0186102UL` (`a32h_compat_ioctl_t`, 24 bytes)
     - `A32H_SET_ROBUST_LIST32 = 0x40106103UL` (`a32h_robust_list32_t`, 16 bytes)
     - `A32H_SET_PROC = 0x40406104UL` (`a32h_proc_t`, 64 bytes)
   - Report `info.abi_minor = A32H_ABI_MINOR_TSO` (`1U`) in `A32H_GET_INFO`, and advertise `A32H_CAP_FIXADE | A32H_CAP_SOFT_TLB_256M` alongside the existing caps in `hl_a32host_caps()`.
   - In `src/device.c` and `src/syscall_io.c`: allow `A32H_COMPAT_IOCTL` on `/dev/a32host` fds to reach the `syscall_io.c` forwarding implementation (and write the result into `compat.result`); wire `A32H_SET_PROC` to update the guest's `/proc/self/exe` and `/proc/self/cmdline` state when `exe_path_ptr` / `cmdline_ptr` are non-zero; wire `A32H_SET_ROBUST_LIST32` to record the 32-bit robust list head on the calling thread/guest state.
5. **P2 — Authority Token & RV32 Env Contract (`src/rvrt_mode.c`)**:
   - Default authority token must be `"hyper-linux-apfs-acl-v1"` (not `"hyper-linux"`), and both `RT_HOST_EXEC_AUTHORITY` and `<PREFIX>_HOST_EXEC_AUTHORITY` must be set to the same resolved value.
   - For RV32 (`HL_CLASSB_RV32`), share `rvrt`'s configuration contract (`HL_RVRT` env fallback and `RVRT` prefix for `RVRT_HOST_EXEC_AUTHORITY` / `RVRT_CACHE_DIR`).
6. **P2 / P3 — Real Behavioral Host Tests & Comment Cleanup**:
   - Update `test/host/test-provider-b-sparc64-8k.c` so it links and calls the real `rvrt_shared` admission, partial-page zero-fill, and truncation fence functions rather than local arithmetic copies.
   - Update `test/host/test-guest-translators.c` so the MIPS N32 fixture is a real `ELFCLASS32` + `EF_MIPS_ABI2` (`0x20`) image (testing both BE and LE), PPC64 tests reject BE and ELFv1 (`e_flags = 1`) and accept LE ELFv2 (`e_flags = 2`), and `/dev/a32host` tests exercise `0xc0186102UL`, `0x40106103UL`, `0x40406104UL`, `abi_minor == 1`, `A32H_CAP_FIXADE`, and `A32H_CAP_SOFT_TLB_256M`.
   - Fix the comments at `src/a32.h:16` and `src/a32.h:152` so they accurately state Class-A `sparc32rt` uses 4096-byte pages.

Run the host tests (`_build/test-host-provider-b-sparc64-8k` and `_build/test-host-guest-translators`), verify `cmp -s src/a32host.h /Users/angerman/Projects/zw3rk/rt-series/include/a32host.h`, and commit cleanly on `lane/u4-integration` in `/Users/angerman/Projects/zw3rk/hyper-linux-u4`.
