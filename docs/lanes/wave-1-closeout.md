# Wave 1 — Closeout of Existing Runtimes & `hyper-linux` Unification (Muse Spark Task Cards)

Parent specification: [`../../SPEC.md`](../../SPEC.md) §2  
Parent plan: [`../../PLAN.md`](../../PLAN.md) §3.1  
Host contract: [`../HOST-CONTRACT.md`](../HOST-CONTRACT.md)

Common lane rules for all Wave 1 cards:
- Create your assigned git worktree explicitly (`git -C ../<repo> worktree add ../<repo>-<lane> -b lane/w1-<lane> <base-sha>`) and assert `pwd` and `git rev-parse --abbrev-ref HEAD` before making any edits.
- Never modify files outside your card's **Exclusive File Ownership** list.
- Follow Curated C11 (`-std=c11 -Wall -Wextra -Werror=vla -pedantic`); no VLAs, no `sprintf`/`strcpy`/`strcat`.
- Run your card's **Single Acceptance Check** once, wrapping the entire command group in `timeout --kill-after=30s <sec> bash -lc "..."`.
- Commit once with author `Moritz Angermann <moritz@zw3rk.com>` and zero AI attribution trailers.
- Escalate to the Coordinator if your acceptance check fails twice, if you need a frozen-header or `Makefile` edit, or if any requirement is ambiguous.

---

## 1. Sub-Wave W1A: `../a32rt` Defect Remediation & Consumer CLI Parser (`D1`–`D19`)
*(Runs BEFORE `W1D.1` so `a32rt` accepts `--execfn`, `--image-fd` `FD>=0`, `--rootfs`, and `--no-host` before `hyper-linux` switches its launcher to emit `--execfn`.)*

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-A32-1** | `../a32rt-w1a1` (`lane/w1-a32-decode`) | `src/decode_a32.c`, `tests/test_m1_isa_fs.c` | `timeout --kill-after=30s 180s bash -lc "make -C ../a32rt-w1a1 build tests test-m1-lima"` -> `PASS` |
| **L-A32-2** | `../a32rt-w1a2` (`lane/w1-a32-vm-main`) | `src/main.c`, `src/vm.c`, `tests/test_m5_ltp_gdb.c` | `timeout --kill-after=30s 240s bash -lc "make -C ../a32rt-w1a2 build tests test-hello-lima test-m5-lima"` -> `PASS` |
| **L-A32-3** | `../a32rt-w1a3` (`lane/w1-a32-docs`) | `include/a32host.h`, `README.md`, `AGENTS.md`, `A32RT.md`, `tests/test_m3_threads_signals.c`, `tests/test_m4_vfp_neon.c`, `DEFECTS.md` | `timeout --kill-after=30s 120s bash -lc "make -C ../a32rt-w1a3 build && cmp -s ../a32rt-w1a3/include/a32host.h ../rt-series/include/a32host.h && git -C ../a32rt-w1a3 diff --check"` -> exit 0 |

### Card L-A32-1 — Fix `D16` (Conditional `MOVS` Mask) & `D17` (`ALUWritePC` Interworking)
- **Scope**:
  1. **`D16` (`src/decode_a32.c:284-289`)**: Change `(insn & 0x0FE00FF0U) == 0x01A00000U` to `(insn & 0x0FF00FF0U) == 0x01A00000U` so `S == 1` (`MOVS`) updates `NZCV`.
  2. **`D17` (`src/decode_a32.c:1014`)**: When `rd == 15 && !s_bit`, call `a64_emit_exit_branch_reg(b, A64_TMP0, true)` (`ALUWritePC` interworking).
  3. Add regression tests in `tests/test_m1_isa_fs.c` for conditional `moveqs` and A32 `add pc, r0, #0` interworking to Thumb.
- **Acceptance check**: `timeout --kill-after=30s 180s bash -lc "make -C ../a32rt-w1a1 build tests test-m1-lima"` -> `PASS`.

### Card L-A32-2 — Fix `D18` (`--execfn`/`--image-fd`/`AT_EXECFD=0`/`--rootfs`/`--no-host`) & `D19` (`mremap` `MAP_SHARED` File Writeback)
- **Scope**:
  1. **`D18` (`src/main.c`)**: Add `--execfn <PATH>`, `--image-fd <FD>` (accepting any non-negative `FD >= 0`), `--rootfs <DIR>` (alias for `--sysroot <DIR>`), and `--no-host` CLI options; detect `AT_EXECFD` via `errno = 0; unsigned long fd = getauxval(AT_EXECFD); if (errno == 0) exec_fd = (int)fd;` (so `AT_EXECFD == 0` is valid); preserve custom `guest_argv[0]` across zero/one/multiple args and inherited descriptors `>= 3`.
  2. **`D19` (`src/vm.c`)**: Preserve file backing across `a32_vm_mremap` grow/move of `MAP_SHARED` VMAs inside `[G, G + 4 GiB)` (restoring `PROT_NONE` on vacated window pages on success and preserving `PROT_NONE` reservations on failure).
  3. Add regression tests in `tests/test_m5_ltp_gdb.c` verifying `MAP_SHARED` `mremap` writeback and `--execfn` + `--image-fd 0` + custom `argv[0]` + `argc == 0`.
- **Acceptance check**: `timeout --kill-after=30s 240s bash -lc "make -C ../a32rt-w1a2 build tests test-hello-lima test-m5-lima"` -> `PASS`.

### Card L-A32-3 — Sync `include/a32host.h`, Documentation & Comment Numbering (`D1`–`D15`)
- **Scope**: Copy `../rt-series/include/a32host.h` (`A32H_ABI 1.1`) into `include/a32host.h`, commit comment fixes in `tests/test_m{3,4}_*.c`, update `README.md`, `AGENTS.md`, `A32RT.md`, and `DEFECTS.md`.
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../a32rt-w1a3 build && cmp -s ../a32rt-w1a3/include/a32host.h ../rt-series/include/a32host.h && git -C ../a32rt-w1a3 diff --check"` -> exit 0.

---

## 2. Sub-Wave W1B: `../i686rt` Campaign (`C1`–`C12`) & Audit Defect (`D1`–`D74`) Closeout
*(Runs BEFORE `W1D.1`. Note: `H1` and `H4` are already committed on `i686rt/master` at `2061d1c`. Coordinator prerequisite `L-I686-0` runs first, followed by sequential Sub-Waves `W1B.1` and `W1B.2` so no file is owned by two concurrent lanes.)*

### Coordinator Prerequisite L-I686-0 (On `i686rt/master` Before `W1B.1`)
- **Scope**: Update `../i686rt/Makefile` to provide:
  - `build`: builds `_build/i686rt` and guest test binaries `_build/test_p0..p5`, `_build/test_h1_smc`, `_build/test_h4_aot`;
  - `check-headers`: `cmp -s include/a32host.h ../rt-series/include/a32host.h`;
  - `check`: runs `build`, `check-headers`, and executes `_build/i686rt` on `_build/test_p0..p5`.

### Sub-Wave W1B.1 (Parallel, Disjoint Ownership)

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-I686-1a** | `../i686rt-w1b1a` (`lane/fix-c1a-stat`) | `src/os/sys_stat.c`, `src/os/sys_misc.c`, `src/os/syscalls.c` | `timeout --kill-after=30s 180s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b1a && make build && ./_build/i686rt ./_build/test_p2_syscalls"` -> `PASS` |
| **L-I686-1b** | `../i686rt-w1b1b` (`lane/fix-c1b-pass`) | `src/os/sys_pass.c`, `src/os/clone.c` | `timeout --kill-after=30s 180s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b1b && make build && ./_build/i686rt ./_build/test_p4_threads_signals"` -> `PASS` |
| **L-I686-2** | `../i686rt-w1b2` (`lane/fix-tso-decode`) | `src/dbt/emit_exit.c`, `src/dbt/emit_alu.c`, `src/dbt/emit_mov.c`, `src/dbt/emit_stack.c`, `src/dbt/emit_str.c`, `src/dbt/emit_branch.c`, `src/dbt/emit_sse.c`, `src/x86/decode.c`, `tests/test_p1_isa.c` | `timeout --kill-after=30s 180s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b2 && make build && tools/difftest.sh ./_build/test_p1_isa"` -> `EQUAL` |
| **L-I686-3** | `../i686rt-w1b3` (`lane/fix-sigframe-main`) | `include/a32host.h`, `src/os/sigframe_i386.h`, `src/os/signals_i386.c`, `src/main.c`, `src/i686rt.h`, `tests/test_p4_threads_signals.c` | `timeout --kill-after=30s 180s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b3 && make build check-headers && ./_build/i686rt ./_build/test_p4_threads_signals"` -> `PASS` |
| **L-I686-4** | `../i686rt-w1b4` (`lane/fix-fpu-sse`) | `src/interp/h_sse.c`, `src/interp/x87.c`, `src/interp/h_x87.c`, `src/interp/x87_80.c`, `tests/test_p5_fpu_sse.c` | `timeout --kill-after=30s 180s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b4 && make build && ./_build/i686rt ./_build/test_p5_fpu_sse && ./_build/i686rt --x87-80 ./_build/test_p5_fpu_sse"` -> `PASS` |

- **Card L-I686-1a**: Implement `statx(383)` in `src/os/sys_stat.c`, and fix `D27` (`fchmodat` 3 args), `D31` (`set_tid_address` returns `sys_gettid()`), `D41` (`settimeofday` `int[2]`), `D43` (`getdents64` 64-bit `d_off`), `D47` (`O_DIRECTORY` in `i686_oflags_h2g`), `D53` (`statfs` `-EOVERFLOW`).
- **Card L-I686-1b**: Implement `C1` (10 syscall numbers in 8 groups) in `src/os/sys_pass.c` and `src/os/clone.c`: `_llseek(140)`, `msync(144)`, `readv(145)`, `truncate64(193)`/`ftruncate64(194)`, `tkill(238)`, `sched_setaffinity(241)`/`sched_getaffinity(242)`, `set_robust_list(311)`/`get_robust_list(312)`, plus `D52` (`i686_fetch_cstr` `va < 0x1000` `-EFAULT`).
- **Card L-I686-2**:
  1. **Default-On Unaligned-Safe Software TSO (`D5`, `D6`, `D17`)**: Because cached translations compiled before `clone()` or across shared `MAP_SHARED` memory cannot safely transition from unordered to ordered without a full cache flush, enable software TSO **unconditionally by default** in `i686_emit_begin` (`src/dbt/emit_exit.c:38`): `e->tso = !ctx->no_tso && !(ctx->has_host_info && (ctx->host_info.caps & (1ULL << 9)))`, and flush the DBT cache if TSO mode ever changes. Across `emit_alu.c`, `emit_mov.c`, `emit_stack.c`, `emit_str.c`, `emit_branch.c`, and `emit_sse.c`, emit normal unaligned-capable `LDR`/`STR` paired with `DMB ISHLD` after loads and `DMB ISH` around stores when `e->tso` is true (never emit unguarded `LDAR`/`STLR` on potentially unaligned 16/32-bit x86 addresses!).
  2. **Decoder (`src/x86/decode.c`)**: Fix `D13` (`A0–A3` `moffs` displacement width uses `out->pfx_addrsize ? 2U : 4U`, not `pfx_opsize`), `D14` (`ea_default_seg` returns `I686_SEG_SS` when `addr_size == 4` and `(modrm_rm == 4 && sib_base == 4)` (`ESP`) or `(modrm_rm == 4 && sib_base == 5 && modrm_mod != 0)` or `(modrm_rm == 5 && modrm_mod != 0)`, and when `addr_size == 2` and `modrm_rm == 2 || modrm_rm == 3 || (modrm_rm == 6 && modrm_mod != 0)`), and `D51` (mask out undefined `F_AF` after shifts in `tests/test_p1_isa.c`).
- **Card L-I686-3**:
  1. **Sync `include/a32host.h`**: Copy `../rt-series/include/a32host.h` (`A32H_ABI 1.1`) into `include/a32host.h`.
  2. **`_fpstate_32` UAPI Layout, Authoritative Legacy x87 Restore & `D34` (`src/os/sigframe_i386.h`, `src/os/signals_i386.c`)**: Add `uint16_t status; uint16_t magic;` at `0x6c`, `uint8_t _fxsr_st[128]` at `0x90`, move `xmm_space[32]` (`_xmm[8]`) to **`0x110`**, and change `__pad1` to `uint32_t padding1[44]` (`176 B` at `0x190..0x23f`, keeping `sw_reserved` at `0x240` and total `624 B`, verified with `_Static_assert`s on every `offsetof`). On signal delivery, write `magic = 0x0000` (`X86_FXSR_MAGIC`) and **zero the entire `48 B` `sw_reserved` region** (`0x240..0x26f`, never writing `FP_XSTATE_MAGIC1` without a complete trailing `FP_XSTATE_MAGIC2` XSAVE block), pack 8 × 10-byte x87 registers into `st_space` (`_st[8]` at `0x1c..0x6b`) and duplicate into `_fxsr_st` (`0x90..0x10f`), and pack 8 × 16-byte XMM registers into `xmm_space` (`0x110..0x18f`). On `sigreturn`/`rt_sigreturn`, **restore x87 state (`cw, sw, tag, _st[0..7]`) from the authoritative legacy `108 B` `i387_fsave_struct` region (`0x00..0x6b`)** (matching Linux `arch/x86/kernel/fpu/signal.c` `__restore_fpregs_from_user`) and restore `_xmm[0..7]` and `mxcsr` from `0x88..0x18f`. Add a regression test in `tests/test_p4_threads_signals.c` that modifies `_st[0]` and `_fxsr_st[0]` to different values in a signal handler and asserts `_st[0]` wins.
  3. **Stack Alignment `D37` (`src/os/signals_i386.c`)**: Align handler entry `sp` via `sp = ((sp + 4U) & ~15U) - 4U` (`sp % 16 == 12`).
  4. **CLI Parser (`--execfn`, `--image-fd` `FD>=0`, `--sysroot`, `--stats`, `--no-host`), `AT_EXECFD` (`D23`), `exec_path_buf` (`D26`), & `--x87-64` (`D28`) (`src/main.c`, `src/i686rt.h`)**: Add `--execfn <PATH>`, `--image-fd <FD>` (any non-negative `FD >= 0`), `--sysroot <DIR>`, `--stats`, and `--no-host`; detect `AT_EXECFD` via `errno = 0; getauxval(AT_EXECFD)`; copy `exec_path` into `ctx->exec_path_buf`; and honor `--x87-64` over `I686RT_X87=80`.
- **Card L-I686-4**: Fix `C4` (`x87_80.c` `round_pack80` directed-mode deep-tiny) and `D57`–`D72` in `src/interp/h_sse.c`, `src/interp/x87.c`, and `src/interp/h_x87.c`.

### Sub-Wave W1B.2 (Runs After W1B.1 Merges to `i686rt/master`)

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-I686-5** | `../i686rt-w1b5` (`lane/fix-c2-pthreads`) | `src/os/sys_pass.c` (`sys_futex`), `src/os/clone.c`, `src/os/threads.h`, `tools/run-ltp.sh`, `tools/run-libctest.sh`, `tests/hardening/h2-report.md` | `timeout --kill-after=30s 300s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b5 && make build && tools/run-ltp.sh && tools/run-libctest.sh && python3 -c 'import re; ltp=open(\"tests/hardening/results/ltp.tap\").read(); lc=open(\"tests/hardening/results/libctest.tap\").read(); assert len(re.findall(r\"^(?:not )?ok \", ltp, re.M))==103 and len(re.findall(r\"^ok \", ltp, re.M))>=80 and \"TBROK\" not in ltp; assert len(re.findall(r\"^(?:not )?ok \", lc, re.M))==343 and len(re.findall(r\"^ok \", lc, re.M))>=125'"` -> exit 0 |
| **L-I686-6** | `../i686rt-w1b6` (`lane/fix-c6-c7-dbt`) | `src/dbt/flags_dbt.c`, `src/dbt/flags_dbt.h`, `src/dbt/translate.c`, `src/dbt/engine.c`, `src/trampoline.S`, `tools/run-coremark.sh`, `tests/hardening/h3-coremark.md` | `timeout --kill-after=30s 300s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b6 && make build && tools/run-coremark.sh"` (where `tools/run-coremark.sh` runs on `limactl` before and after, validates all 4 CoreMark CRCs, and machine-asserts `dbt_iter_s > interp_iter_s`) -> exit 0 |
| **L-I686-7** | `../i686rt-w1b7` (`lane/fix-c3-c9-c12`) | `DEFECTS.md`, `SPEC.md` | `timeout --kill-after=30s 240s limactl shell default -- bash -lc "cd /Users/angerman/Projects/zw3rk/i686rt-w1b7 && make build && ./_build/i686rt ./_build/test_p4_glibc"` -> `PASS` |

---

## 3. Sub-Wave W1C: `../rvrt` Defect Ledger (`D1`–`D35` at `25e9de64`) & Multi-Block JIT

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-RV64-1a** | `../rvrt-w1c1a` (`lane/w1-rv64-linux-defects`) | `src/linux/file.c`, `src/linux/poll.c`, `src/linux/metadata.c`, `src/linux/signal.c`, `src/linux/exec_args.c` | `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-w1c1a build runtime-linux test-aot-reader"` -> `PASS` |
| **L-RV64-1b** | `../rvrt-w1c1b` (`lane/w1-rv64-runtime-defects`) | `vendor/softfloat/source/include/internals.h`, `src/runtime/scheduler.c`, `src/runtime/family_wait.c`, `src/runtime/family.c`, `src/runtime/native_signal.c`, `src/runtime/family_file_index.c`, `src/runtime/guest_memory.c` | `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-w1c1b build runtime-linux test-fsize-hard0-linux"` -> `PASS` |
| **L-RV64-1c** | `../rvrt-w1c1c` (`lane/w1-rv64-tests-docs`) | `nix/rv32-glibc-target-libraries.nix`, `test/musl_heap_tls.c`, `test/test_fork_futex_process.py`, `test/test_fork_futex_wake_op.py`, `test/test_fork_poll_lease.py`, `test/r5_exec.c`, `docs/HOST-CONTRACT.md`, `README.md`, `DEFECTS.md` | `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-w1c1c build test-aot-format && git -C ../rvrt-w1c1c diff --check"` -> `PASS` |
| **L-RV64-2** | `../rvrt-w1c2` (`lane/w1-rv64-jit-expand`) | `src/jit/a64.c`, `src/jit/emit.h` | `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-w1c2 build runtime-linux test-aot-multiblock test-aot-dynamic"` -> `PASS` |

- **Card L-RV64-1a Note on `D1` (`src/linux/file.c:653`)**: Preserve the existing `path_descriptor` (`O_PATH`) check returning `-EBADF` for `pos >= 0` (matching Linux `fs/read_write.c` `ksys_pread64` -> `fdget()`, which filters `FMODE_PATH` and returns `-EBADF` before checking `FMODE_PREAD`); add a native-Linux oracle regression test verifying `-EBADF` for `pos >= 0` and `-EINVAL` for `pos < 0` on an `O_PATH` descriptor, and close `D1` in `DEFECTS.md` as oracle-verified (do NOT change to `-ESPIPE`). Fix `D2, D8, D9, D10, D24`.

---

## 4. Sub-Wave W1D (`W1D.1 -> W1D.2`): `../hyper-linux` Translator Table, `/dev/a32host`, `mremap` & `build/rvrt-*` Broker Merge
*(Runs AFTER `W1A` and `W1B.1` land backward-compatible `--execfn`/`--image-fd` consumer CLI parsers. Split into sequential Sub-Waves `W1D.1` and `W1D.2` so `src/hl.c` and `src/fork_ipc.c` have strictly exclusive ownership.)*

### Sub-Wave W1D.1 (Parallel, Disjoint Ownership)

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-HL-1** | `../hyper-linux-w1d1` (`lane/w1-hl-translators`) | `src/device.c`, `src/syscall_io.c`, `src/a32host.h`, `src/translator.h`, `src/a32.c`, `src/i686.c`, `src/hl.c` | `timeout --kill-after=30s 180s bash -lc "make -C ../hyper-linux-w1d1 hl test-a32-hello && cmp -s ../hyper-linux-w1d1/src/a32host.h ../rt-series/include/a32host.h"` -> `PASS` |
| **L-HL-2** | `../hyper-linux-w1d2` (`lane/w1-hl-rvrt-fixes`, from `bc8b136`/`67afb8a`) | `src/syscall.c` (`hl_sys_mremap` lines 3180–3260), `src/rvrt_fifo.c`, `src/fork_ipc.c`, `src/syscall_net.c`, `src/syscall_fs.c`, `src/syscall_signal.c`, `src/syscall_poll.c` | `timeout --kill-after=30s 300s bash -lc "make -C ../hyper-linux-w1d2 hl && ../hyper-linux-w1d2/hl ../rvrt/_build/rvrt-linux-aarch64 -- ../rvrt/_build/smoke-rv64-static-c /bin/smoke && python3 ../rvrt/test/test_fork_poll_lease.py && python3 ../rvrt/test/test_fork_futex_process.py"` -> `PASS` |

### Sub-Wave W1D.2 (Runs After `W1D.1` Merges to `hyper-linux/master`)

| Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **L-HL-3** | `../hyper-linux-w1d3` (`lane/w1-hl-android32-tso`) | `src/guest_android.c`, `src/hl.c`, `src/thread.c`, `src/fork_ipc.c`, `test/android/run-e2e-32.sh` | `timeout --kill-after=30s 240s bash -lc "make -C ../hyper-linux-w1d3 hl && ../hyper-linux-w1d3/test/android/run-e2e-32.sh"` -> both static and dynamic Bionic32 gates pass |

### Card L-HL-1 — Fix `/dev/a32host` (`D185`, `D187`–`D191`), `C8` `guest_env` Ordering & Masked `hl_translators[]`
- **Scope**:
  1. Sync `src/a32host.h` with `../rt-series/include/a32host.h` (`A32H_ABI_MINOR_TSO = 1`, `A32H_CAP_HW_TSO = 1ULL << 9`, left clear until `L-HL-3` verifies TSO across all vCPUs).
  2. Fix `D185` (`a32host_destroy` in `src/device.c` setting `st->alias_fd = -1` so the underlying fd is never double-closed), `D187` (`.fstat` on `/dev/a32host` reporting `S_IFCHR | 0666` and `makedev(10, 240)`), `D188`/`D189` (single-open pinned `AT_EXECFD` and single-open `elf_preload`), `D190` & `i686rt` `C8` (in `src/hl.c`, inject `<RT>_WINDOW=<hint>` into `guest_env` **before** `hl_build_initial_stack()` and on `sys_execve`), and `D191` (remove duplicate `A32H_GET_INFO` from `src/syscall_io.c`).
  3. Pass `--execfn <RESOLVED_TARGET_PATH> -- <GUEST_ARGV0> [<GUEST_ARGS>...]` in `src/a32.c` and `src/i686.c` so `guest_argv[0]` is preserved verbatim while `exec_path` is explicitly provided.
  4. Extend `hl_translator_desc_t` in `src/translator.h` with `e_flags_mask` and `e_flags_val` per `docs/HOST-CONTRACT.md` §6 (partitioning `EM_MIPS` O32 vs N32 vs N64, admitting `EM_SPARC (2)` only and rejecting `EM_SPARC32PLUS (18)`, and auto-dispatching `EM_RISCV` ELF32/ELF64).
- **Acceptance check**: `timeout --kill-after=30s 180s bash -lc "make -C ../hyper-linux-w1d1 hl test-a32-hello && cmp -s ../hyper-linux-w1d1/src/a32host.h ../rt-series/include/a32host.h"` -> `PASS`.

### Card L-HL-2 — File-Backed `mremap` (`a32rt` `D19`) & Round-17 RVRT Broker Audit (`D201`, `D211–D213`, `D249–D258`)
- **Scope**:
  1. In `src/syscall.c:3204` (`hl_sys_mremap`), implement file-backed `MAP_SHARED` VMA grow and `MREMAP_MAYMOVE` / `MREMAP_FIXED` relocation preserving the host file descriptor and file offset (unblocking `a32rt` `D19` on `hyper-linux`).
  2. Audit each of the **13 Round-17 defect IDs** (`D211–D213` and `D249–D258`) plus `D201` (14 IDs total) against the candidate broker tip (`bc8b136` / `67afb8a`, noting `src/vfs.c` already updated the older FIFO read implementation cited in `D211`):
     - Fix `D249` (`src/fork_ipc.c`: free 6 `calloc(FD_TABLE_SIZE)` buffers on early reservation error);
     - Fix `D250`, `D254–D256` (`src/syscall_net.c`: RVRT `AF_UNIX` `recvmsg` `SOCK_DGRAM` `msg_name`, `MSG_TRUNC`/`MSG_CTRUNC` peek-before-consume, `SOCK_STREAM` non-empty control buffer, `MSG_PEEK` with control buffer);
     - Fix `D251–D252` (`src/syscall_fs.c`: `name_to_handle_at` 4-byte `int mount_id` write; `/proc/self/fd/N` `truncate()` inode permission check);
     - Fix `D253` (`src/syscall_signal.c`: stamp `getuid()` instead of `1000` on sender-less signals);
     - Fix `D257–D258` (`src/syscall_poll.c`: do not set `POLLWRBAND` on normal SCM writability; use `guest_write_checked` for `ppoll` `pollfd` copyout);
     - Verify `D211–D213` in `src/rvrt_fifo.c` / `src/vfs.c`.
- **Acceptance check**: `timeout --kill-after=30s 300s bash -lc "make -C ../hyper-linux-w1d2 hl && ../hyper-linux-w1d2/hl ../rvrt/_build/rvrt-linux-aarch64 -- ../rvrt/_build/smoke-rv64-static-c /bin/smoke && python3 ../rvrt/test/test_fork_poll_lease.py && python3 ../rvrt/test/test_fork_futex_process.py"` -> `PASS`.

### Card L-HL-3 — Android Slice C Dynamic Bionic32 Linker Fix (`D218`) & vCPU TSO Lifecycle
- **Scope**:
  1. Fix `D218` (`rseq` 32-bit signature check) and trace Bionic32 `/system/bin/linker` startup under `hl --profile android --sysroot $SYS32 --a32rt ../a32rt/_build/a32rt` to resolve the `mprotect` / `tgkill` abort.
  2. If enabling Apple Silicon hardware TSO (`A32H_CAP_HW_TSO`), apply it across initial vCPU (`src/hl.c`), thread vCPUs (`src/thread.c`), and fork vCPUs (`src/fork_ipc.c` after `W1D.1` merges), verify `ACTLR_EL1` readback on every vCPU creation path, and run message-passing (`MP`), `CLONE_VM` thread, `fork` (`MAP_SHARED`), `exec` vCPU, and 4-thread `IRIW`/Dekker litmus tests; otherwise keep `A32H_CAP_HW_TSO` clear (`0`).
- **Acceptance check**: `timeout --kill-after=30s 240s bash -lc "make -C ../hyper-linux-w1d3 hl && ../hyper-linux-w1d3/test/android/run-e2e-32.sh"` -> both static and dynamic Bionic32 gates pass.
