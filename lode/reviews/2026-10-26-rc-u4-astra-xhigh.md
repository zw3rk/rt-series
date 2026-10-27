**ACTION_REQUIRED — RC-U4 does not pass at `993e37c`.** The checkout is clean on `lane/u4-integration`. The review found two P1 blockers plus the following P2/P3 issues.

The supplied Rev-4 plan ends at Section 8; it has no Section 12. I used its Section 5.2 and Section 7 Wave-U4 requirements alongside the work order.

1. **P1 — The new translator dispatch does not launch translators.**
   `hl_translator_dispatch_note()` sets environment/page-size state and prints discovery results, then startup passes the original foreign ELF to the native loader. It never loads the resolved translator or selects the required Class-B memory policy. Exec dispatch also retains the ARM/RV64 paths. Consequently, descriptor entries and CLI flags do not provide ten-translator execution. See [hl.c:265](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/hl.c:265), [hl.c:1416](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/hl.c:1416), [hl.c:1447](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/hl.c:1447), and [syscall_exec.c:630](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/syscall_exec.c:630). No `hl_translators[]` implementation exists.

2. **P1 — The Rev-4 Provider-B stage gate remains unimplemented.**
   The fence examines only one VM’s retained views. A sibling that independently maps an inode after fork is invisible to another VM’s truncate check. Locally, removing a mapped page returns `EBUSY`; beyond-EOF mappings return `EINVAL`, rather than establishing the required guest `SIGBUS` ranges. The required family inode coordinator, physical file-COW promotion, acknowledged vCPU kicks, and translator invalidation ring are absent. See [rvrt_shared.c:78](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_shared.c:78), [rvrt_shared.c:325](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_shared.c:325), and [syscall_fs.c:5749](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/syscall_fs.c:5749). These are existing limitations left unresolved against the explicit [RC-U4 gate](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:721), not newly introduced regressions.

3. **P2 — The mmap precheck still rejects valid SPARC64 partial pages.**
   [syscall.c:2318](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/syscall.c:2318) calls the legacy 4096-byte wrapper before reaching the new page-aware implementation. For `st_size=1`, offset `0`, length `8192`, the 8 KiB predicate admits the partial page, but this precheck returns `EINVAL`. Thus the valid zero-filled upper half cannot be reached through the actual syscall path.

4. **P2 — Fork loses the selected 8 KiB page size.**
   [fork_ipc.c:4629](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/fork_ipc.c:4629) restores the size from supposedly inherited process-global state. However, fork uses [posix_spawn at fork_ipc.c:7858](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/fork_ipc.c:7858), resetting that global to 4096; the child returns into IPC restoration before translator detection. Admission, fences, and GET_INFO therefore revert to 4 KiB. Transfer the selected size through IPC.

5. **P2 — MIPS N32 is classified as O32.**
   The Class-A probe reads only 20 bytes and assigns every ELF32 `EM_MIPS` image to `mips32rt`; the Class-B probe accepts MIPS only when ELFCLASS64. Neither decodes `EF_MIPS_ABI2`. Real N32 images consequently select the wrong runtime. See [a32.c:66](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32.c:66), [a32.c:90](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32.c:90), and [rvrt_mode.c:576](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_mode.c:576).

6. **P2 — PPC64 routing ignores the required endian and ELF ABI checks.**
   [rvrt_mode.c:572](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_mode.c:572) accepts any ELF64 `EM_PPC64`, including big-endian and ELFv1 images. The required target is little-endian ELFv2, with `(e_flags & 3) == 2`. The probe never decodes `e_flags`.

7. **P2 — All three new ioctl encodings disagree with the work order.**
   [a32.h:184](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32.h:184) defines SET_PROC/ROBUST_LIST32/COMPAT_IOCTL as `0x400c6102`, `0x40086103`, and `0x40106104`; the [required values](/Users/angerman/Projects/zw3rk/rt-series/docs/lanes/work-orders/pane-hl-u4.md:59) are `0x40406104`, `0x40106103`, and `0xc0186102`. Payload sizes and SET_PROC semantics also differ. Callers using the specified ABI receive `ENOTTY`.

8. **P2 — COMPAT_IOCTL cannot reach its implementation through `/dev/a32host`.**
   [syscall_io.c:3173](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/syscall_io.c:3173) immediately returns the device handler’s result. That handler returns `ENOTTY` for COMPAT_IOCTL at [device.c:1152](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/device.c:1152), preventing execution of the generic forwarding case—even with the implementation’s own request number. The capability is nevertheless advertised.

9. **P2 — SET_PROC and ROBUST32 acknowledge operations without implementing their effects.**
   [device.c:1131](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/device.c:1131) and [device.c:1142](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/device.c:1142) only save structures in per-descriptor state. Production code never consumes them. SET_PROC does not update `/proc/self/exe` or `/proc/self/cmdline`; ROBUST32 does not install thread-exit cleanup. Advertising these capabilities can make translators rely on behavior that never occurs.

10. **P2 — The requested ABI extension is absent.**
    `A32H_CAP_FIXADE` and `A32H_CAP_SOFT_TLB_256M` are neither defined nor advertised. GET_INFO still reports minor zero through [a32host.h:32](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32host.h:32) and [device.c:1117](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/device.c:1117). The header *is* byte-identical to the canonical rt-series copy, which has the same omissions: this requires reconciling the shared contract, not merely resynchronizing files.

11. **P2 — Authority propagation exports the wrong token.**
    [rvrt_mode.c:670](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_mode.c:670) defaults to `"hyper-linux"` instead of `"hyper-linux-apfs-acl-v1"`. It can also leave generic and architecture-specific authority values different. This does not establish the specified cache-authority contract.

12. **P2 — RV32 does not share RVRT’s configuration contract.**
    [rvrt_mode.c:507](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/rvrt_mode.c:507) uses `HL_RV32RT` and the `RV32RT` prefix despite selecting the `rvrt` binary. Configuring the required `HL_RVRT` therefore does not configure RV32 discovery, and propagation targets different environment names.

13. **P2 — The new tests cannot establish the claimed acceptance results.**
    The Provider-B test duplicates bias arithmetic and checks only the inline coverage predicate; it never calls the real truncate fence or inspects mapped zero-filled bytes. The dispatch test omits startup/device handlers and labels an ELFCLASS64 fixture as N32, concealing the routing defect. See [test-provider-b-sparc64-8k.c:27](/Users/angerman/Projects/zw3rk/hyper-linux-u4/test/host/test-provider-b-sparc64-8k.c:27), [test-provider-b-sparc64-8k.c:85](/Users/angerman/Projects/zw3rk/hyper-linux-u4/test/host/test-provider-b-sparc64-8k.c:85), [Makefile:1611](/Users/angerman/Projects/zw3rk/hyper-linux-u4/Makefile:1611), and [test-guest-translators.c:398](/Users/angerman/Projects/zw3rk/hyper-linux-u4/test/host/test-guest-translators.c:398).

14. **P3 — Public comments still claim SPARC32 uses 8192-byte pages.**
    [a32.h:16](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32.h:16) and [a32.h:152](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/a32.h:152) contradict the corrected implementation and the contract.

Verified portions:

- Class-A SPARC returns **4096**; only SPARCV9 returns **8192** in the page-size selectors.
- The aligned coverage predicate is equivalent to checking the rounded file end, while avoiding rounding overflow.
- Local `O_TRUNC`, `ftruncate`, and `truncate` paths check the fence before shrinking under `HL_MEMORY_POLICY_RVRT`.
- `fallocate(PUNCH_HOLE)` returns `EOPNOTSUPP` before mutation at [syscall_io.c:3613](/Users/angerman/Projects/zw3rk/hyper-linux-u4/src/syscall_io.c:3613); it is unsupported, not an unfenced implemented path.

Read-only checks passed: `git diff --check 5c72284..993e37c` and `cmp src/a32host.h /Users/angerman/Projects/zw3rk/rt-series/include/a32host.h`. No files or Git state were modified. Builds and runtime tests were not run because they create binaries or fixtures.