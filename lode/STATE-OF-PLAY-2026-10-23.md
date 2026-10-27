# Cross-Repository State-of-Play Audit (2026-10-23)

Audited repositories and exact commit baselines:
- `/Users/angerman/Projects/zw3rk/rt-series` (this repository)
- `/Users/angerman/Projects/zw3rk/a32rt` (`HEAD` `d84feb311a0a`, tag `v0.1.0`)
- `/Users/angerman/Projects/zw3rk/i686rt` (initial audit baseline `11cc65c`, updated `master` HEAD `2061d1c` / `f24db6ed6f0c` where `H1`, `H4`, `DEFECTS.md` `C1–C12`, and `GOAL-DEFECTS.md` landed; plus sibling worktrees `../i686rt-*`)
- `/Users/angerman/Projects/zw3rk/rvrt` (initial audit baseline `884ae73`, updated `master` HEAD `c1f5caa` / `2056cb1d6d11` where bounded two-block and `PT_INTERP` AOT entry caching landed; plus 278 sibling worktrees `../rvrt-*`)
- `/Users/angerman/Projects/zw3rk/hyper-linux` (`HEAD` `fb879f088d63`, plus 44 sibling worktrees `../hyper-linux-rvrt-*` and `../i686rt-l6a` @ `6352d84`)

Evidence tags (`~/.config/ai/AGENTS.md`): `[F]` verified repository/UAPI fact, `[I]` inference, `[H]` hypothesis requiring runtime measurement, `[U]` unverified prior to execution.

---

## 1. Executive Summary Table

| Repository | `master` HEAD | Qualified Checkpoint & Explicit Exclusions | Worktrees / Branches | Working Tree / Stashes | Open Code & Campaign Defects (`DEFECTS.md`) |
|---|---|---|---|---|---|
| **`a32rt`** | `d84feb311a0a` (`v0.1.0`) | `[F]` M0–M8 fixtures pass on `lima` and `hyper-linux` (musl, glibc 2.36, C++17 EHABI, Alpine gcc/python3/luajit, AOT v8, GDB stub) | 0 worktrees, 0 unmerged branches | 4 tracked files with comment-only fixes (`src/decode_a32.c`, `tests/test_m{3,4,5}_*.c`) + untracked `DEFECTS.md` | **4 code defects** (`D16`..`D19`) + 15 doc/comment items (`D1`..`D15`) |
| **`i686rt`** | `2061d1c` / `f24db6ed6f0c` | `[F]` Phases E, 0–8, RC7/RC7b (`wine` under `interp`), RC8 (`vm86`), H1 (`4f4e597`/`b30698e` SMC), H2, H3, and H4 (`705123e`/`dae2c79` `x86_64-linux` interp) committed on `master` | Active `lane/fix-c*` campaign branches + 8 earlier `l4a..l5e` worktrees; **`../i686rt-l6a` (`6352d84`) is a worktree of `hyper-linux`** | 2 stashes (`quarantine`, `quarantine-2`, tracked in `C12`) | **Open campaign inventory `C1`–`C12`** (`GOAL-DEFECTS.md`) + **audit ledger `D1`–`D74`** (incl. default-on unaligned-safe TSO `D5/D6/D17`, `ea_default_seg` `D14`, `_fpstate` `_fxsr_st`/`_xmm` layout & authoritative legacy `_st[8]` restore `D34/D37`, x87/SSE `D57`–`D72`) |
| **`rvrt`** | `c1f5caa` / `2056cb1d6d11` | `[F]` Bounded RV64GC checkpoint (`docs/SUPPORT.md`): focused RV64 fixtures, bounded 1–2 block & `PT_INTERP` AOT entry caching (`1e0fde1`, `b6169d2`, `c1f5caa`), internal `runtime-file-attributed-linux` MM/clone slice, and `RLIMIT_FSIZE=0` SysV single-worker slice. **Exclusions**: normal-policy `HL_MEMORY_POLICY_RVRT` fork (`ENOSYS`), full R5/H2 public source admission, general multi-worker file `mmap`, full multi-block/DSO AOT, finite application suite, and **all RV32GC (`R8`) runtime execution** | 296 branches / 278 worktrees (`for-each-ref --no-merged` lists ~278 branches due to cherry-pick/re-authored history; requires content-equivalence audit before any removal) | 12 tracked files with comment-only fixes (`D7..D33`) + untracked `DEFECTS.md` | **35 cataloged entries (`D1`..`D35` at `25e9de64`)**: **18 correctness entries** (`D1, D2, D8, D9, D10, D13, D15, D16, D17, D20, D21, D22, D23, D24, D26, D28, D34, D35` — noting `D1` is already Linux-accurate `-EBADF`), **4 doc (`other`) entries** (`D3, D4, D5, D6`), **13 comment entries** (`18 + 4 + 13 = 35`) |
| **`hyper-linux`** | `fb879f088d63` | `[F]` Native AArch64 (Linux/Android/FreeBSD/NetBSD/OpenBSD), Rosetta x86-64, `a32rt` merged on `master`, base `rvrt_mode.c` on `master` | **43 `hyper-linux-rvrt-*` worktrees** (tip `build/rvrt-shm-stat-rmid` @ `67afb8a`, +206 commits; `hl/rvrt-m1-broker` @ `bc8b136`) + **`../i686rt-l6a`** (`lane/6-l6a` @ `6352d84`, +2 commits) | Untracked probe/temp files (`p4g-*`, `p4s-*`, `g1probe-*`) | **AArch32**: `D185`, `D187`–`D191` + dynamic Bionic32 linker self-kill; **RVRT stack**: **13 Round-17 defect IDs** (`D211–D213`, `D249–D258`) + **1 additional `D201` on `master` = 14 IDs total**; **Fork/Exec**: `D151`, `D195`, `D218` |

---

## 2. Detailed Findings Per Existing Repository

### 2.1 `../a32rt` (`HEAD` `d84feb311a0a`)
1. **Open Code Bugs in `DEFECTS.md` (`D16`–`D19`)** `[F]`:
   - **`D16` (`src/decode_a32.c:284-289`)**: Conditional `MOV Rd, Rm` branchless `CSEL` fast path masks `insn & 0x0FE00FF0U == 0x01A00000U`, omitting bit 20 (`S` bit `0x00100000U`). Consequently, conditional `MOVS Rd, Rm` (`cond != AL`, `S=1`, shift=0) emits `CSEL` without updating `NZCV`. Fix: mask with `0x0FF00FF0U`.
   - **`D17` (`src/decode_a32.c:1014`)**: A32 ALU writes to `PC` (`Rd == 15`, `S == 0`, e.g., `MOV pc, lr`, `ADD pc, pc, r0`) call `a64_emit_exit_branch_reg(b, A64_TMP0, false)` instead of `true` (`ALUWritePC` interworking in ARMv7-A). Fix: pass `is_bx = true`.
   - **`D18` (`src/main.c:205-211`) & Consumer-First Protocol Coordination with `hyper-linux`**: Currently `hyper-linux/src/a32.c:323` launches `a32rt -- guest_argv[0] guest_argv[1...]` without a separate `TARGET_PATH` token after `--`. Unconditionally skipping `argv[i]` after `--` in `a32rt` would drop `guest_argv[0]` under current `hl`! Therefore, `a32rt` (`W1A`) and `i686rt` (`W1B.1`) land backward-compatible CLI parsers supporting `--execfn PATH`, `--image-fd FD` (any non-negative `FD >= 0`), `--rootfs`/`--sysroot`, and `--no-host` (and detect `AT_EXECFD` via `errno = 0; getauxval(AT_EXECFD)` so `fd == 0` is valid) **before** `hyper-linux` (`W1D.1`) switches its launcher to emit `--execfn`.
   - **`D19` (`src/vm.c:778-779, 853-854`) & `hyper-linux` `mremap` Dependency**: `a32_vm_mremap` allocates replacement ranges with `A32_MAP_ANONYMOUS` and `memcpy`s old bytes, losing `MAP_SHARED` file backing on grow/move. Simply calling host `SYS_mremap` inside `a32rt` is insufficient because:
     1. In `a32rt`, the 4 GiB window `[G, G + 4 GiB)` is surrounded by `PROT_NONE` reservations; relocate/grow must allocate a target range inside `[G, G + 4 GiB)`, invoke `mremap(..., MREMAP_MAYMOVE | MREMAP_FIXED, G + new_guest_va)` (or remap from tracked `{dup_fd, offset}`), restore `PROT_NONE` on the vacated range on success, and preserve `PROT_NONE` on failure.
     2. In `hyper-linux/src/syscall.c:3204`, `hl_sys_mremap` currently rejects file-backed grow/move with `-ENOSYS` and its anonymous relocation helper uses private anonymous memory. Closing `D19` requires fixing both `a32rt/src/vm.c` and `hyper-linux/src/syscall.c` and verifying `MAP_SHARED` file writeback after `mremap` on both `test-m5-lima` and `test-m5-hl`.
2. **Documentation & Working-Tree Sync (`D1`–`D15`)** `[F]`:
   - Commit the 4 working-tree comment fixes (`src/decode_a32.c`, `tests/test_m{3,4,5}_*.c`) and update `README.md`, `AGENTS.md`, and `A32RT.md` (`A32_AOT_VERSION = 8`, FNV-1a cache naming, `AT_PLATFORM = "v8l"`, remove nonexistent `src/start.S` reference).
   - Note that `a32rt/Makefile` targets are named `build`, `tests`, `check-headers`, `test-hello-{hl,lima}`, `test-m{1..8}-{hl,lima}`, `test-all-{hl,lima}` (there is no `make check` target in `a32rt/Makefile`).

### 2.2 `../i686rt` (`HEAD` `2061d1c` / `f24db6ed6f0c`)
1. **Committed Progress on `master`** `[F]`:
   - Phases E, 0–8, RC7/RC7b (`wine`), RC8 (`vm86`), H1 (`4f4e597`/`b30698e` SMC protection + `test_h1_smc`), H2, H3, and H4 (`705123e`/`dae2c79` `x86_64-linux` interpreter-only build) are committed on `i686rt/master`.
   - `i686rt/DEFECTS.md` and `i686rt/GOAL-DEFECTS.md` define two distinct sets of defects:
     - **Open Campaign Defects `C1`–`C12`** (`DEFECTS.md:1015-1165`):
       - `C1` (P0): **8 unimplemented syscall groups (10 syscall numbers**: `_llseek` 140, `msync` 144, `readv` 145, `truncate64` 193 / `ftruncate64` 194, `tkill` 238, `sched_setaffinity` 241 / `sched_getaffinity` 242, `set_robust_list` 311 / `get_robust_list` 312, `statx` 383), split into `L-C1a` (file-descriptor class) and `L-C1b` (thread/sched class, seam committed in `2061d1c`).
       - `C2` (P0): 19 `libc-test` pthread cancel/cond/robust/once timeouts.
       - `C3` (P1): `wine` chain verification under `I686RT_ENGINE=dbt`.
       - `C4` (P2): `x87_80.c` `round_pack80` directed-rounding deep-tiny fix.
       - `C5` (P2): `MOVDQA` alignment `#GP(0)` in DBT vs SPEC ratification.
       - `C6` (P0-perf): CoreMark DBT (23 iter/s) vs interpreter (71 iter/s) `[F]`. **Important `[H]`**: The H3 report identifies dead-flag elimination and IBTC block linking as expected optimization levers, NOT measured root causes, and current `I686RT_STATS` counts events rather than per-phase wall/cycle time. Closing `C6` requires the 6-step performance loop on the **same `limactl shell default` substrate** before and after: (1) add default-off `cntvct_el0` per-phase timing instrumentation, (2) commit instrumentation, (3) measure baseline on `limactl`, (4) state bottleneck hypothesis from measured phase split, (5) conditionally implement `L-C6a`/`L-C6b` targeting the dominant phase, (6) re-measure on the identical `limactl` substrate and machine-assert `dbt_iter_s > interp_iter_s` with intact CoreMark CRCs.
       - `C7` (P2): SMC dead-marked block reclamation (`engine.c` + `trampoline.S`).
       - `C8` (P1, upstream `hyper-linux`): `hl` `guest_env` materialization before `finalize`'s `setenv` breaks `A32RT_WINDOW`.
       - `C9` (P3): `winevdm` stderr diagnosis during `wineboot`.
       - `C10` (P1): Formal dynamic-glibc 2.44 rerun of RC4 (`test_p4_glibc`).
       - `C11` (P2): H2 math measurement under `--x87-80` (`I686RT_X87=80`).
       - `C12` (P3): Quarantine stash reconciliation + open `D1`–`D74` audit re-read.
     - **Audit Ledger Defects `D1`–`D74`** (`DEFECTS.md:1-1012`), including:
       - **Default-On Unaligned-Safe Software TSO (`D5`, `D6`, `D17`)**: Because cached translations compiled before `clone()` or across shared `MAP_SHARED` memory cannot safely transition from unordered to ordered without a full cache flush, software TSO must be enabled **unconditionally by default** (`e->tso = !ctx->no_tso && !hw_tso`, flushing the DBT cache on any TSO mode change) across `emit_exit.c`, `emit_alu.c`, `emit_mov.c`, `emit_stack.c`, `emit_str.c`, `emit_branch.c`, and `emit_sse.c` using unaligned-capable `LDR`/`STR` + `DMB ISHLD`/`DMB ISH` fences (never unguarded `LDAR`/`STLR` on potentially unaligned 16/32-bit x86 addresses).
       - **Signal Frame Alignment, `_fpstate_32` Wire Layout & Authoritative Legacy x87 Restore (`D34`, `D37` + UAPI layout bug)**:
         1. Handler entry stack alignment in Linux `arch/x86/kernel/signal.c` is `sp = ((sp + 4U) & ~15U) - 4U` (yielding `sp % 16 == 12`, NOT `((sp - 4) & 15) == 0`).
         2. In `src/os/sigframe_i386.h`, `i686_fpstate_32_t` omits the 128-byte `_fxsr_st[8]` array at offset `0x90`, placing `xmm_space[32]` at `0x90` instead of Linux UAPI's **`0x110`**. Furthermore, on `sigreturn`/`rt_sigreturn`, Linux's `__restore_fpregs_from_user` treats the **legacy 108-byte `i387_fsave_struct` (`_st[0..7]` at `0x1c..0x6b`) as authoritative for x87 state** and `_xmm[0..7]` (`0x110..0x18f`) + `mxcsr` as authoritative for SSE state, while pure FXSR frames (`magic = 0x0000`) must zero the `48 B` `sw_reserved` region (`0x240..0x26f`).
       - **Decoder Default Segment (`D14` in `src/x86/decode.c`)**: `ea_default_seg` returns `DS` instead of `SS` when `modrm_mod == 0` and 32-bit SIB base is `4` (`ESP`, `rm == 4`) or 16-bit `rm == 2 || rm == 3` (`[bp+si]`, `[bp+di]`).

### 2.3 `../rvrt` (`HEAD` `c1f5caa` / `2056cb1d6d11`)
1. **Qualification Scope & Explicit Exclusions (`docs/SUPPORT.md`)** `[F]`:
   - `rvrt` is a bounded RV64GC checkpoint, NOT a blanket completion claim for P0–P3 or R0–R7:
     - **Qualified slices**: `rvrt inspect`, `rvrt-linux-aarch64` focused RV64 fixtures (arithmetic/memory faults, ELF startup, static/dynamic musl and glibc smoke, TLS, selected pthread/signal/file/socket/poll/futex cells), opt-in bounded 1–2 block & `PT_INTERP` entry AOT caching (`make test-aot-multiblock`, `make test-aot-dynamic`), bounded single-worker `RLIMIT_FSIZE=0` SysV slice (`make test-fsize-hard0-linux`, `make test-family-authority-cli-hl`), and internal `runtime-file-attributed-linux` MM/clone/vfork slice.
     - **Explicitly unfinished / excluded**:
       1. Normal `hyper-linux` `HL_MEMORY_POLICY_RVRT` process-fork gate returns `ENOSYS` (diagnostic-HL fork runs do not open the normal gate);
       2. Public CLI admission of the source-enabled family (`--resume-v7` is an internal same-PID exec vector);
       3. General file `mmap` while multiple workers are live, shared regular-file mappings, and external/native shared writers;
       4. `RLIMIT_FSIZE=0` process/fork/thread support and the `-hl` 65,536-row fragment test (`test-family-zero-fragments-hl`);
       5. General multi-block/DSO AOT discovery, cross-load-bias hits, and cache preservation across fork/exec;
       6. Full BusyBox child-process/pipeline/redirection/exec behavior and the finite application suite in `docs/IMPLEMENTATION-PLAN.md`;
       7. **All RV32GC (`Milestone R8`) runtime execution** (only the Nix cross-toolchains, target libraries, and 4 exported fixtures under `qemu-riscv32` are qualified today).
2. **Exact `rvrt/DEFECTS.md` Ledger (`D1`–`D35` at `25e9de64`)** `[F]`:
   - **18 Correctness Entries**:
     - `D1` (`src/linux/file.c:653`): `rvrt/DEFECTS.md` claimed `pread64`/`pwrite64` on `O_PATH` should return `-ESPIPE` (`failure(29)`). **Oracle verification (`R2-02`)**: On Linux `v6.18` (`fs/read_write.c` `ksys_pread64` -> `fdget()`), `fdget()` filters `FMODE_PATH` and returns **`-EBADF` (`failure(9)`)** for `pos >= 0` before checking `FMODE_PREAD`, so `rvrt`'s existing `path_descriptor` check is already Linux-accurate! Preserve `-EBADF`, add a native-Linux oracle regression test (`-EBADF` for `pos >= 0`, `-EINVAL` for `pos < 0`), and close `D1` as oracle-verified.
     - `D2` (`src/linux/file.c`): `get_status` and `ioctl_file` (`TIOCGWINSZ`) return `-EFAULT` (`failure(14)`) on failed `rv_space_write` without splitting on `rv_fault_is_runtime` for `-ENOMEM` (`failure(12)`).
     - `D8` (`src/linux/poll.c`): `select_files` silently clamps `nfds > RV_FD_TABLE_LIMIT` (1024).
     - `D9` (`src/linux/metadata.c`): `encoded_stat` returns `fail_guest(14)` (`-EFAULT`) without checking `rv_fault_is_runtime`.
     - `D10` (`src/linux/signal.c`): syscall 136 `rt_sigpending` returns `fail(14)` (`-EFAULT`) without checking `rv_fault_is_runtime`.
     - `D13` (`vendor/softfloat/source/include/internals.h`): `isNaNBF16UI` masks with `0x7FC0` (including quiet bit 6), rejecting signaling BF16 NaNs with bit 6 clear.
     - `D15` (`src/runtime/scheduler.c`): `rv_scheduler_wake` calls `suspended_push` during quiesce even when `ticket == quiesce_owner`.
     - `D16` (`src/runtime/family_wait.c`): `rv_family_wait_table_commit`/`sweep` set `errno = EINVAL` on bad arguments only when `errno == 0`.
     - `D17` (`src/runtime/family.c`): `replay_committed` omits `key_equal(control->log_key, control->log_second_key)` check for `RV_LOG_WAIT_PAIR`.
     - `D20` (`test/musl_heap_tls.c`): `zero_size = 140003` reads one byte past `calloc(70001, 2)` (140002 bytes).
     - `D21` (`test/test_fork_futex_process.py`, `test_fork_futex_wake_op.py`): unconditionally prepend `limactl` for `oracle`/`native-linux` instead of checking `platform.system() == 'Darwin'`.
     - `D22` (`test/test_fork_poll_lease.py`): non-run-only `--host linux` selects `args.a64_cc` with `-march=rv64gc -mabi=lp64d`.
     - `D23` (`nix/rv32-glibc-target-libraries.nix`): links `$out/bin/cc` to nonexistent `${prefix}cc` instead of `${prefix}gcc`.
     - `D24` (`src/linux/exec_args.c`): `read_string` and `read_vector` return `host_error(EFAULT)` without testing `rv_fault_is_runtime` for `ENOMEM`.
     - `D26` (`src/runtime/native_signal.c`): `rv_native_signal_process_reset_child_policy` accepts `installed.sa_handler == SIG_DFL` without checking `sa_flags`.
     - `D28` (`test/r5_exec.c`): `exec-sibling-read` passes `expect_old_thread_gone = false` while printing that the parked sibling retired.
     - `D34` (`src/runtime/family_file_index.c`): `write_slot` uses `errno = EOVERFLOW` for `!metadata_page(&page)` whereas read paths use `errno = EIO`.
     - `D35` (`src/runtime/guest_memory.c`): `rv_guest_memory_exec_capture_clear_tids` checks only `page_factory.context`, `rv_guest_memory_prepare_child_frozen` checks only `managed.context`, whereas `fork_child` checks both.
   - **4 Doc (`other`) Entries**: `D3`, `D4` (`docs/HOST-CONTRACT.md` stale ppoll-mask and fork-lifetime prose), `D5`, `D6` (`README.md` stale shared-mapping and 64KiB owned-writer transfer prose).
   - **13 Comment Entries**: `D7, D11, D12, D14, D18, D19, D25, D27, D29, D30, D31, D32, D33` (`18 + 4 + 13 = 35` total entries).
3. **Worktree Inventory Fact (`278` Worktrees / `296` Branches)** `[F]`:
   - `git -C ../rvrt for-each-ref --no-merged=master refs/heads` lists ~278 branches not ancestry-merged into `master` (because many waves landed via cherry-pick or re-authored commits, while some worktrees may contain unique unmerged work or active state). Worktrees must **never** be bulk-deleted without a per-worktree content-equivalence (`git cherry` / `git diff`), dirty/untracked file, and active-process audit plus explicit user approval.

### 2.4 `../hyper-linux` (`HEAD` `fb879f088d63`)
1. **Unmerged `build/rvrt-*` Stack (43 Worktrees, Tip `build/rvrt-shm-stat-rmid` @ `67afb8a`, Broker Tip `hl/rvrt-m1-broker` @ `bc8b136`)** `[F]`:
   - Implements the RVRT host broker architecture (`rvrt_shared`, `rvrt_scm_broker`, `rvrt_pipe`, `rvrt_fifo`, `rvrt_dir_broker`, `rvrt_fsize_helper`, `rvrt_pidfd`, `rvrt_signal_channel`, `safe_syscall`).
   - Has **13 Round-17 defect IDs** (`D211–D213` and `D249–D258`) in `hyper-linux/DEFECTS.md` plus **1 additional `D201` on `master` (14 IDs total)**. Note that `D211–D213` were recorded against an older revision (`74f7e75b`) and `src/vfs.c` on `bc8b136`/`67afb8a` has a newer bounded FIFO read implementation; each of the 13 Round-17 IDs + `D201` must be audited against the candidate branch tip before applying fixes.
2. **Unmerged `lane/6-l6a` Worktree (`../i686rt-l6a` @ `6352d84`, +2 commits over `fb879f0`)** `[F]`:
   - Implements `src/translator.h` (`hl_translators[]`) and `src/i686.c` for `EM_386`. Needs rebase onto `master`, deduplication with `src/a32.c`, fixes for `D185`, `D187`–`D191` and `C8` (`guest_env` ordering in `src/hl.c` before `finalize`), file-backed `mremap` support in `src/syscall.c:3204` (required by `a32rt` `D19`), and extension of `hl_translators[]` with masked `e_flags` predicates to partition `EM_MIPS` O32 vs N32/N64 and dispatch all `rt-series` translators.
3. **Android Slice C Dynamic Bionic32 Linker Self-Kill** `[F]`:
   - Dynamic 32-bit Android binaries (`PT_INTERP = /system/bin/linker`) under `hl --profile android --sysroot $SYS32 --a32rt ...` spin in `mprotect` HVCs and self-kill with `SIGKILL` (exit 137); requires root-cause diagnosis (`prctl`/`rseq`/`AT_RANDOM`/TLS/linker `mprotect` semantics) and fix.

---

## 3. Post-Unification Update (2026-10-27 — Waves `U0`–`U6` Complete)

All 10 `<arch>rt` translator repositories and `hyper-linux` (`Wave U4`) have completed the Unification & Dual-Backend Architecture Program ([`../docs/UNIFICATION-PLAN.md`](../docs/UNIFICATION-PLAN.md) Rev 4, [`../docs/lanes/wave-u-unification.md`](../docs/lanes/wave-u-unification.md)) and passed independent `astra` (`gpt-6-astra`) stage-gate reviews:

| Repository | Qualified Branch / Commit | Stage Gate & Review Transcript | Key Verified Milestones |
|---|---|---|---|
| `a32rt` | `master` @ `47f105e` | `RC-U3 PASS` ([`2026-10-26-rc-u3-r5-a32-astra.md`](reviews/2026-10-26-rc-u3-r5-a32-astra.md)) | 5-module `<= 900` lines/file split, A32/Thumb-2/VFP/NEON interpreter + `--difftest`, `vm32` Regime A1/A2, kuser `0xffff0000` `PROT_READ` + DBT, `-linux-aarch64` & `-darwin-arm64` |
| `i686rt` | `master` @ `db832b7` | `RC-U3 PASS` ([`2026-10-26-rc-u3-r5-i686-sparc32-astra.md`](reviews/2026-10-26-rc-u3-r5-i686-sparc32-astra.md)) | `vm32` Regime A1/A2, C11 `__atomic_*` `LOCK` RMWs, `sp_rollback_delta` recovery for `PUSH`/`POP`/`CALL`, v2 AOT, `-linux-aarch64` & `-darwin-arm64` |
| `mips32rt` | `master` @ `5f7f285` | `RC-U3 PASS` ([`2026-10-26-rc-u3-r7-mips32-astra.md`](reviews/2026-10-26-rc-u3-r7-mips32-astra.md)) | `vm32` Regime A1/A2, `TIF_FIXADE` unaligned emulation + `SIGBUS`, delay-slot `RT_NPC_DYNAMIC_CTX`, AOT, `-linux-aarch64` & `-darwin-arm64` |
| `ppc32rt` | `master` @ `3296803` | `RC-U3 PASS` ([`2026-10-26-rc-u3-r6-ppc32-astra.md`](reviews/2026-10-26-rc-u3-r6-ppc32-astra.md)) | `vm32` Regime A1/A2, C11 `__atomic_compare_exchange_n` `STWCX.`, `MWI` byte/halfword/word recovery, AOT, `-linux-aarch64` & `-darwin-arm64` |
| `sparc32rt` | `master` @ `26f4923` | `RC-U3 PASS` ([`2026-10-26-rc-u3-r6-sparc32-astra.md`](reviews/2026-10-26-rc-u3-r6-sparc32-astra.md)) | `vm32` Regime A1/A2, C11 `__atomic_*` `LDSTUB`/`SWAP`/`CASA`, delay-slot & window recovery, AOT, `-linux-aarch64` & `-darwin-arm64` |
| `loongarch64rt` | `master` @ `893637b` | `RC-U12 PASS` ([`2026-10-26-rc-la64-r6-astra.md`](reviews/2026-10-26-rc-la64-r6-astra.md)) | `src/rt64` removed (81 files), `vm64` + `Provider A`, 7-insn Soft-TLB + 24B `dbt_mem_site_t[]`, 6-step `tgkill` quiescence, `-linux-aarch64` & `-darwin-arm64` |
| `ppc64rt` | `master` @ `fe79c9a` | `RC-U12 PASS` ([`2026-10-26-rc-ppc64-r13-astra.md`](reviews/2026-10-26-rc-ppc64-r13-astra.md)) | `src/rt64` removed (242 files), real `src/main.c` wired, `x19 = cpu, x20 = &cpu->tlb[0]`, 7-insn Soft-TLB + 24B `dbt_mem_site_t[]`, `-linux-aarch64` & `-darwin-arm64` |
| `mips64rt` | `master` @ `91fc2d4` | `RC-U12 PASS` ([`2026-10-26-rc-mips64-r13-astra.md`](reviews/2026-10-26-rc-mips64-r13-astra.md)) | `src/rt64` removed (81 files), `vm64` + `Provider A`, delay-slot `RT_NPC_DYNAMIC_CTX`, `TIF_FIXADE`, 7-insn Soft-TLB, 4-ABI (`n64le`/`n64be`/`n32le`/`n32be`) parity, `-linux-aarch64` & `-darwin-arm64` |
| `sparc64rt` | `master` @ `2f2ce13` | `RC-U12 PASS` ([`2026-10-26-rc-sparc64-r5-astra.md`](reviews/2026-10-26-rc-sparc64-r5-astra.md)) | `src/rt64` removed (252 files), `GUEST_ABI_PAGE_SIZE = 8192` (`vpn, vpn ^ 1`), 7-insn Soft-TLB preserving `NZCV`, `-linux-aarch64` & `-darwin-arm64` |
| `rvrt` | `master` @ `b5c25c5` | `RC-U5 PASS` ([`2026-10-26-rc-u5-r6-astra.md`](reviews/2026-10-26-rc-u5-r6-astra.md)) | `vm64` + `Provider A`, full series DBT + v4 AOT, Milestone R8 `RV32GC` (`ILP32D`) qualified, BusyBox 1.37.0 builtins, ~30k-LOC legacy SCM socket broker retired, all `src/` files `<= 900` lines |
| `hyper-linux` | `lane/u4-integration` @ `cd86f55` | `RC-U4 PASS` ([`2026-10-26-rc-u4-r6-astra.md`](reviews/2026-10-26-rc-u4-r6-astra.md)) | `Provider B` (`src/inode_backing.c`), Stage-1 L3 PTE COW repointing, `hv_vcpus_exit` preemption + shared DBT invalidation ring, pre-bucket-lock futex pinning, `hl_translators[]` 11-architecture auto-dispatch |
