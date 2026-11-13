# Wave 2 — `rvrt` Milestone R8: RV32GC (`rv32imafdc` / `ILP32D`) Qualification (Muse Spark Task Cards)

Parent specification: [`../../SPEC.md`](../../SPEC.md) §3  
Parent plan: [`../../PLAN.md`](../../PLAN.md) §3.2  
Target repository: [`../../../rvrt`](../../../rvrt) (plus [`../../../hyper-linux`](../../../hyper-linux) for RV32 `hl` auto-dispatch)

---

## 1. Coordinator Freeze Before Fan-Out (Read-Only to Worker Lanes)

Before launching Stage 2.1 (`L-R8a`..`L-R8e`), the Coordinator commits the following frozen interfaces and `Makefile` test rules on `rvrt` `master`:
1. **`src/core/profile.h`**:
   - Declares `const rv_profile_t *rv_profile_for_xlen(unsigned int xlen)` returning non-NULL for both `xlen == 64` (`"rv64gc-lp64d"`, `elf_class = 2`, `elf_float_abi = 4`, `hwcap = 0x112d`) and `xlen == 32` (`"rv32gc-ilp32d"`, `elf_class = 1`, `elf_float_abi = 4`, `hwcap = 0x112d`).
2. **`src/core/compressed.h`**:
   - Updates signature to `bool rv_expand_compressed(uint16_t parcel, unsigned int xlen, rv_decoded_insn_t *out)` (or adds `rv_expand_compressed_xlen`).
3. **`src/linux/rv32_abi.h` (new frozen header, verified in `rt-series/tests/check_abi_invariants.c`)**:
   - Pinned Linux v6.18 RV32 syscall numbers (`arch/riscv/kernel/Makefile.syscalls` `syscall_abis_32 += riscv memfd_secret` — which **excludes `time32`**, so raw syscall `260` `wait4` is absent and MUST return `-ENOSYS`; process waiting uses 5-arg `waitid(95)`):
     - `RV32_SYS_fcntl64 = 25`, `RV32_SYS_truncate64 = 45`, `RV32_SYS_ftruncate64 = 46`, `RV32_SYS_fallocate = 47`, `RV32_SYS_openat = 56`, `RV32_SYS_close = 57`, `RV32_SYS_getdents64 = 61`, `RV32_SYS_llseek = 62`, `RV32_SYS_read = 63`, `RV32_SYS_write = 64`, `RV32_SYS_readv = 65`, `RV32_SYS_writev = 66`, `RV32_SYS_pread64 = 67`, `RV32_SYS_pwrite64 = 68`, `RV32_SYS_readlinkat = 78`, `RV32_SYS_exit = 93`, `RV32_SYS_exit_group = 94`, `RV32_SYS_waitid = 95`, `RV32_SYS_set_tid_address = 96`, `RV32_SYS_set_robust_list = 99`, `RV32_SYS_get_robust_list = 100`, `RV32_SYS_getitimer = 102`, `RV32_SYS_setitimer = 103`, `RV32_SYS_kill = 129`, `RV32_SYS_tkill = 130`, `RV32_SYS_tgkill = 131`, `RV32_SYS_sigaltstack = 132`, `RV32_SYS_rt_sigsuspend = 133`, `RV32_SYS_rt_sigaction = 134`, `RV32_SYS_rt_sigprocmask = 135`, `RV32_SYS_rt_sigpending = 136`, `RV32_SYS_rt_sigreturn = 139`, `RV32_SYS_uname = 160`, `RV32_SYS_getpid = 172`, `RV32_SYS_getppid = 173`, `RV32_SYS_getuid = 174`, `RV32_SYS_geteuid = 175`, `RV32_SYS_getgid = 176`, `RV32_SYS_getegid = 177`, `RV32_SYS_gettid = 178`, `RV32_SYS_sysinfo = 179`, `RV32_SYS_brk = 214`, `RV32_SYS_munmap = 215`, `RV32_SYS_mremap = 216`, `RV32_SYS_clone = 220`, `RV32_SYS_execve = 221`, `RV32_SYS_mmap2 = 222`, `RV32_SYS_fadvise64_64 = 223`, `RV32_SYS_mprotect = 226`, `RV32_SYS_msync = 227`, `RV32_SYS_riscv_hwprobe = 258`, `RV32_SYS_riscv_flush_icache = 259`, `RV32_SYS_prlimit64 = 261`, `RV32_SYS_getrandom = 278`, `RV32_SYS_memfd_create = 279`, `RV32_SYS_execveat = 281`, `RV32_SYS_statx = 291`, `RV32_SYS_clock_gettime64 = 403`, `RV32_SYS_clock_settime64 = 404`, `RV32_SYS_clock_getres_time64 = 406`, `RV32_SYS_clock_nanosleep_time64 = 407`, `RV32_SYS_timer_gettime64 = 408`, `RV32_SYS_timer_settime64 = 409`, `RV32_SYS_timerfd_gettime64 = 410`, `RV32_SYS_timerfd_settime64 = 411`, `RV32_SYS_utimensat_time64 = 412`, `RV32_SYS_pselect6_time64 = 413`, `RV32_SYS_ppoll_time64 = 414`, `RV32_SYS_futex_time64 = 422`, `RV32_SYS_clone3 = 435`.
   - **Compile-time `_Static_assert`s on Linux v6.18 RV32 UAPI wire structures**:
     - `sizeof(rv32_iovec_t) == 8` (`{uint32_t iov_base, iov_len}`),
     - `sizeof(rv32_kernel_sigaction_t) == 16` (`{uint32_t sa_handler, sa_flags; uint64_t sa_mask}` — no `sa_restorer`!),
     - `sizeof(rv32_stack_t) == 12` (`{uint32_t ss_sp; int32_t ss_flags; uint32_t ss_size}`),
     - `sizeof(rv32_d_ext_state_t) == 264` (`uint64_t f[32]` + `uint32_t fcsr` + 4B pad; no `0x44504600` magic!),
     - `sizeof(rv32_fp_state_t) == 528` and `_Alignof(rv32_fp_state_t) == 16` (`union __riscv_fp_state` reserving the Q-sized union in `sigcontext` without advertising `Q`),
     - `sizeof(rv32_sigcontext_t) == 656` (`uint32_t gregs[32]` 128B + `rv32_fp_state_t` 528B),
     - `offsetof(rv32_ucontext_t, uc_mcontext) == 160` (`0xA0`, with `uint32_t uc_sigmask[2]` 8B at offset 20 + 120B `uc_sigmask_ext` + 12B align pad),
     - `sizeof(rv32_ucontext_t) == 816`,
     - `sizeof(rv32_rt_sigframe_t) == 944` (`128B siginfo_t + 816B rv32_ucontext_t`).
4. **`Makefile`**: Pre-adds build rules for `_build/test_rv32_core`, `_build/test_rv32_loader`, `_build/test_rv32_syscalls`, `_build/test_rv32_signals`, `_build/test_rv32_jit`, and `_build/test_rv32_runtime_int`.

---

## 2. Three-Stage Wave 2 Execution Schedule

| Stage / Lane | Worktree / Branch | Exclusive File Ownership | Single Runnable Acceptance Check |
|---|---|---|---|
| **2.1 L-R8a** | `../rvrt-r8a` (`lane/r8-core`) | `src/core/profile.c`, `src/core/compressed.c`, `src/core/decode.c`, `src/core/interp.c`, `src/core/fp.c`, `test/test_rv32_core.c` | `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8a _build/test_rv32_core && ../rvrt-r8a/_build/test_rv32_core"` -> `RV32 CORE PASS` |
| **2.1 L-R8b** | `../rvrt-r8b` (`lane/r8-loader`) | `src/loader/image.c`, `src/loader/stack.c`, `test/test_rv32_loader.c` | `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8b _build/test_rv32_loader && ../rvrt-r8b/_build/test_rv32_loader"` -> `RV32 LOADER PASS` |
| **2.1 L-R8c** | `../rvrt-r8c` (`lane/r8-linux-sys`) | `src/linux/rv32_syscall.c`, `src/linux/rv32_structs.h`, `src/linux/file.c`, `src/linux/io.c`, `src/linux/poll.c`, `src/linux/socket.c`, `test/test_rv32_syscalls.c` | `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8c _build/test_rv32_syscalls && ../rvrt-r8c/_build/test_rv32_syscalls"` -> `RV32 SYSCALLS PASS` |
| **2.1 L-R8d** | `../rvrt-r8d` (`lane/r8-signals`) | `src/linux/rv32_signal_frame.c`, `test/test_rv32_signals.c` | `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8d _build/test_rv32_signals && ../rvrt-r8d/_build/test_rv32_signals"` -> `RV32 SIGNALS PASS` |
| **2.1 L-R8e** | `../rvrt-r8e` (`lane/r8-jit-aot`) | `src/jit/a64.c`, `src/runtime/aot_cache.c`, `test/test_rv32_jit.c` | `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8e _build/test_rv32_jit && ../rvrt-r8e/_build/test_rv32_jit"` -> `RV32 JIT PASS` |
| **2.2 L-R8-INT** | `../rvrt-r8-int` (`lane/r8-runtime-int`) | `src/runtime_main.c`, `src/linux/signal.c`, `src/linux/exec_args.c`, `src/runtime/exec_state.c`, `src/runtime/scheduler.c`, `test/test_rv32_runtime_int.c` | *(Runs after Stage 2.1 merges)* `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-r8-int runtime-linux _build/test_rv32_runtime_int && ../rvrt-r8-int/_build/test_rv32_runtime_int"` -> `RV32 RUNTIME INT PASS` |
| **2.3 L-R8f** | `../rvrt-r8f` (`lane/r8-glibc-e2e`) | `nix/rv32-glibc-target-libraries.nix`, `test/test_runtime_rv32_qualification.py`, `docs/SUPPORT.md` | *(Runs after Stage 2.2 merges)* `timeout --kill-after=30s 600s bash -lc "make -C ../rvrt-r8f test-rv32-export-oracle && python3 -m unittest test/test_runtime_rv32_qualification.py"` -> `OK` |

---

## 3. Individual Task Cards

### Card L-R8a — RV32GC (`RV32IMAFDC_Zicsr_Zifencei`) Decoder, Compressed & Interpreter
- **Scope**:
  1. In `src/core/profile.c`: return the static `RV32GC/ILP32D` descriptor when `xlen == 32`.
  2. In `src/core/compressed.c`: when `xlen == 32`:
     - Q0 `011` -> `C.FLW` (`flw rd', uimm(rs1')`) and Q0 `111` -> `C.FSW` (`fsw rs2', uimm(rs1')`) using the standard CL/CS 32-bit word-offset encoding `uimm[5:3] = inst[12:10]`, `uimm[2] = inst[6]`, `uimm[6] = inst[5]` (`uimm[6|5:3|2]`, scaled by 4, range `0..124` bytes);
     - Q1 `001` -> `C.JAL` (`jal x1, offset[11|4|9:8|10|6|7|3:1|5]`);
     - Q1 `100` (`C.SRLI`, `C.SRAI`) and Q2 `000` (`C.SLLI`) with `shamt[5] == 1` -> return `false` (`RV_TRAP_ILLEGAL_INSTRUCTION`);
     - Q2 `011` -> `C.FLWSP` (`uimm[5|4:2|7:6]`), Q2 `111` -> `C.FSWSP` (`uimm[5:2|7:6]`).
  3. In `src/core/interp.c` & `src/core/fp.c`: when `cpu->xlen == 32`:
     - **Wrap every effective address modulo $2^{32}$ (`(uint32_t)(base + offset)`) BEFORE calling `rv_space_*` or recording `stval`/`si_addr`**, for integer loads/stores, FP `FLW`/`FSW`/`FLD`/`FSD`, atomics `LR.W`/`SC.W`/`AMO*.W`, and branch/jump targets (`JAL`, `JALR`, `AUIPC`, conditional branches).
     - Zero-extend every GPR write and `cpu->pc` update to 32 bits (`(uint64_t)(uint32_t)val`).
     - Trap all RV64-only instructions (`OP-IMM-32`, `OP-32`, `LD`, `LWU`, `SD`, `LR.D`, `SC.D`, `AMO*.D`, `FCVT.L.S`, `FCVT.LU.S`, `FCVT.S.L`, `FCVT.S.LU`, `FCVT.L.D`, `FCVT.LU.D`, `FCVT.D.L`, `FCVT.D.LU`, `FMV.X.D`, `FMV.D.X`, and `SLLI`/`SRLI`/`SRAI` with `shamt[5] == 1`) and counter CSRs (`RDCYCLE[H]`, `RDTIME[H]`, `RDINSTRET[H]`) with `RV_TRAP_ILLEGAL_INSTRUCTION`.
     - Perform 32-bit signed comparisons (`(int32_t)rs1 < (int32_t)rs2`), 32-bit shifts (`shamt = rs2 & 0x1f`), and 32-bit `MUL`/`MULH`/`MULHSU`/`MULHU`/`DIV`/`DIVU`/`REM`/`REMU`.
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8a _build/test_rv32_core && ../rvrt-r8a/_build/test_rv32_core"` -> `RV32 CORE PASS`.

### Card L-R8b — ELF32 Image Loader & 32-Bit Stack / Auxv Builder
- **Scope**:
  1. In `src/loader/image.c`: parse `Elf32_Ehdr` and `Elf32_Phdr` when `EI_CLASS == ELFCLASS32`, validate `EM_RISCV` and `EF_RISCV_FLOAT_ABI_DOUBLE`, set `image->xlen = 32`, load `PT_LOAD` segments into `[0x1000, 4 GiB)` (PIE bias `0x00400000`, `PT_INTERP` bias `0x3f000000`), and resolve `/lib/ld-musl-riscv32.so.1` or `/lib/ld-linux-riscv32-ilp32d.so.1` inside `--sysroot`.
  2. In `src/loader/stack.c`: when `image->xlen == 32`, place the initial stack at `[0x7f7f0000, 0x7fff0000)`, write 4-byte `argc`, 4-byte `argv[]` pointers, 4-byte `envp[]` pointers, and 8-byte `{uint32_t a_type, uint32_t a_val}` `Elf32_Auxv` entries (`AT_PHDR`, `AT_PHENT=32`, `AT_PHNUM`, `AT_PAGESZ=4096`, `AT_BASE`, `AT_ENTRY`, `AT_HWCAP=0x112d`, `AT_RANDOM`, `AT_EXECFN`, `AT_NULL`) with 16-byte stack alignment (`sp % 16 == 0`).
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8b _build/test_rv32_loader && ../rvrt-r8b/_build/test_rv32_loader"` -> `RV32 LOADER PASS`.

### Card L-R8c — Linux v6.18 RV32 Syscall, `iovec32` Worker-Aware I/O & Compound Structure Conversion Layer
- **Scope**:
  1. Implement `src/linux/rv32_syscall.c` and extend `src/linux/file.c`, `src/linux/io.c`, `src/linux/poll.c`, and `src/linux/socket.c` for `xlen == 32`:
     - Validate syscall buffer ranges `[ptr32, ptr32 + len)` against `exclusive_limit = 0x100000000ULL` without wrapping (returning `-EFAULT` on page-end overflow).
     - Reconstruct 64-bit register pairs: `_llseek(62)` takes `(fd, offset_high, offset_low, result_ptr, whence)` (high word first!); `truncate64(45)`, `ftruncate64(46)`, `pread64(67)`, `pwrite64(68)`, `fallocate(47)`, `fadvise64_64(223)` take `(lo, hi)`.
     - Scale `mmap2(222)` page offset by `4096ULL`.
     - **Worker-aware `rv32_iovec_t` conversion (`src/linux/file.c`, `src/linux/io.c`)**: For `readv(65)`, `writev(66)`, `preadv(69)`, `pwritev(70)`, `preadv2(286)`, and `pwritev2(287)`, convert guest 8-byte `rv32_iovec_t` arrays (`{uint32_t iov_base, uint32_t iov_len}`) into validated 64-bit `struct iovec` arrays inside `src/linux/io.c` / `src/linux/file.c` so the existing worker-aware blocking I/O path is preserved without passing 8-byte vectors to `src/linux/io.c:65`.
     - In `src/linux/poll.c`: for `pselect6_time64(413)` on RV32, decode the 6th argument `sigmask_pack` as `{ uint32_t sigmask_ptr; uint32_t sigmask_size; }` (8 bytes, NOT two 8-byte fields!), and round `fd_set` word count by 32-bit `unsigned long` (`4` bytes).
     - In `src/linux/socket.c`: marshal 28-byte `rv32_msghdr_t` (`32-bit` `msg_iovlen` and `msg_controllen`) and 12-byte `rv32_cmsghdr_t` (`32-bit` `cmsg_len` with **4-byte `CMSG_ALIGN`**).
     - Marshal `getitimer(102)` / `setitimer(103)` using 16-byte `__kernel_old_itimerval` (four 32-bit `long`s), `waitid(95)` 5-arg `siginfo32` + optional 5th-arg `rusage32` (`__kernel_old_timeval` 8B + `int32_t` fields = 72B, while verifying raw syscall `260` returns `-ENOSYS`), `sysinfo(179)` 64-byte `rv32_sysinfo_t`, `riscv_hwprobe(258)` 4-byte cpuset words, and `statx(291)`.
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8c _build/test_rv32_syscalls && ../rvrt-r8c/_build/test_rv32_syscalls"` -> `RV32 SYSCALLS PASS`.

### Card L-R8d — RV32 Linux UAPI Signal Frame Codec (`944 B` `rt_sigframe`)
- **Scope**:
  1. Implement `src/linux/rv32_signal_frame.c` matching the frozen layouts in `src/linux/rv32_abi.h`:
     - 16-byte kernel `sigaction` (`sa_handler`, `sa_flags`, `sa_mask`; no `sa_restorer`),
     - 12-byte `rv32_stack_t`,
     - 944-byte `rv32_rt_sigframe_t` (`128 B` `siginfo_t` with `_sifields` at offset 12 + `816 B` `rv32_ucontext_t` with `uc_mcontext` at offset 160 holding `uint32_t gregs[32]` + 16-byte-aligned 528-byte `union __riscv_fp_state` `f[32]` + `fcsr`).
  2. Restore `gregs[1..31]`, `pc = gregs[0]`, `f[0..31]`, `fcsr`, `uc_stack`, and `uc_sigmask` on `RV32_SYS_rt_sigreturn (139)`.
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8d _build/test_rv32_signals && ../rvrt-r8d/_build/test_rv32_signals"` -> `RV32 SIGNALS PASS`.

### Card L-R8e — RV32 32-Bit AArch64 JIT & `aot_cache.c` Identity Isolation
- **Scope**:
  1. In `src/jit/a64.c`: support `cpu->xlen == 32` by emitting 32-bit `W`-register operations (`ADD Wd, Wn, Wm`, `SUB Wd, Wn, Wm`, etc.) which automatically zero-extend into `cpu->x[rd]`.
  2. In `src/runtime/aot_cache.c` (around line 87): parameterize `rv_aot_cache_identity` on the loaded image's `xlen` (`RV_XLEN_32` vs `RV_XLEN_64`) and `abi` (`ILP32D` vs `LP64D`) using the existing `xlen`, `abi`, and `profile_digest` fields in `src/aot/format.c`, and test that persisted RV32 and RV64 cache snapshots cannot cross-admit.
- **Acceptance check**: `timeout --kill-after=30s 120s bash -lc "make -C ../rvrt-r8e _build/test_rv32_jit && ../rvrt-r8e/_build/test_rv32_jit"` -> `RV32 JIT PASS`.

### Card L-R8-INT (Stage 2.2) — RV32 Runtime, Live-Worker Admission, Signal Trampoline, Exec & Scheduler Integration
- **Scope** *(runs after `L-R8a..e` merge to `master`)*:
  1. `src/runtime_main.c`:
     - Admit `xlen == 32` images (`rv_space_init(..., 32)`), dispatch `xlen == 32` syscalls to `rv32_syscall.c`, marshal RV32 `waitid(95)` `siginfo32` + optional 5th-arg `rusage32`, and route `RV32_SYS_futex_time64 (422)` to the futex/scheduler engine.
     - **Normalize/extend live-worker syscall admission (`src/runtime_main.c:3497`)**: Extend the multithreaded live-worker syscall admission table so `xlen == 32` recognizes `RV32_SYS_clock_gettime64 (403)`, `RV32_SYS_clock_nanosleep_time64 (407)`, `RV32_SYS_pselect6_time64 (413)`, `RV32_SYS_ppoll_time64 (414)`, and `RV32_SYS_futex_time64 (422)` alongside RV64 `72`/`73`/`98`/`113`/`115`.
  2. `src/linux/signal.c`: admit `xlen == 32`, map the 2-instruction sigreturn trampoline page (`addi a7, x0, 139; ecall`) at `0x7fff1000` (inside `< 4 GiB` user space instead of `> 1 TiB`), and dispatch frame setup/restore to `rv32_signal_frame.c`.
  3. `src/linux/exec_args.c` & `src/runtime/exec_state.c`: read 4-byte `argv`/`envp` pointers when `xlen == 32` and admit `xlen == 32` across `execve` and `--resume-v7`.
  4. `src/runtime/scheduler.c`: recognize RV32 `SYS_futex_time64 = 422` alongside RV64 `SYS_futex = 98`.
  5. `test/test_rv32_runtime_int.c`: test multithreaded (`CLONE_VM`) RV32 `futex_time64(422)`, `ppoll_time64(414)`, `pselect6_time64(413)`, `clock_gettime64(403)`, `waitid(95)`, `readv`/`writev` under live workers, and signal delivery/return.
- **Acceptance check**: `timeout --kill-after=30s 180s bash -lc "make -C ../rvrt-r8-int runtime-linux _build/test_rv32_runtime_int && ../rvrt-r8-int/_build/test_rv32_runtime_int"` -> `RV32 RUNTIME INT PASS`.

### Card L-R8f (Stage 2.3) — RV32 Glibc Target Libraries & End-to-End Qualification on Linux and `hyper-linux`
- **Scope** *(runs after `L-R8-INT` merges to `master`)*:
  1. Build and export `_build/rv32-glibc-target-libs-export-v1` via `nix/rv32-glibc-target-libraries.nix`.
  2. Write `test/test_runtime_rv32_qualification.py` running all 4 musl RV32GC smoke binaries and all 4 glibc RV32GC smoke binaries (plus pthread/futex/signal/fork/exec fixtures) under `_build/rvrt-linux-aarch64` (`interp` and `jit`) on AArch64 Linux and `../hyper-linux/_build/hl`, comparing output against `qemu-riscv32`.
- **Acceptance check**: `timeout --kill-after=30s 600s bash -lc "make -C ../rvrt-r8f test-rv32-export-oracle && python3 -m unittest test/test_runtime_rv32_qualification.py"` -> `OK`.
