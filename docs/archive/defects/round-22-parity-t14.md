# rt-series Defect Archive — Round 22: Native `s390x` JIT, Dual-ABI `ppc64`, & Series-Wide `T1`–`T4` Qualification (2026-11-17 to 2026-11-19)

Audited across all 11 translator repositories plus the `rt-series` harness
starting `2026-11-17 02:00:00 +0900` against the `fable_*` review logs in
`scratch/wo_r22/` (`fable_bench_sys.md`, `fable_dbt_cpu.md`,
`fable_i686_*`, `fable_la64_t14*`, `fable_mips32_*`, `fable_mips64_*`,
`fable_j1..j7b`, `wo_s390x_*`, `wo_ppc64_*`, `wo_t14_*`, `wo_rvrt_*`,
`wo_sparc64_*`), remediated on per-repository `T14` lanes, and re-verified by
independent review passes with parity suites at `0 FAIL, 0 GAP, 0 SKIP` and
`T1`–`T4` `guest-payload` `ALL_OK` on every sysroot. `s390xrt` moves from
single-process + C-helper DBT to a full multi-process OS with a native
AArch64 W^X block JIT (`ca8f0c5`); `ppc64rt` gains dual-ABI (ELFv2 + BE ELFv1
`.opd`) 64K IBTC/Soft-TLB coverage with POWER8/VMX fast paths (`b37b021`);
and the real-world software catalogue passes `T1`–`T4` on all 11 translators.

| Repository | Audited Base | Remediated Commit | Items (Round 22) |
|---|---|---|---:|
| `a32rt` | `a53ee27` | `5959599` | `3 / 3` |
| `i686rt` | `226c880`-era `master` | `deffa5e` (`7aa0489`) | `6 / 6` |
| `mips32rt` | `a0794d2`-era `master` | `bf9f0bc` (`41f325b`) | `4 / 4` |
| `ppc32rt` | `a2ccdfc` | `2dfe7d0` (`d3820c1`) | `3 / 3` |
| `rvrt` | `f978775`-era `master` | `b237770` (`6d47ff0..f875739`) | `8 / 8` |
| `loongarch64rt` | `c98e960`-era `master` | `a748562` (`a5d715f..321c0ad`) | `7 / 7` |
| `ppc64rt` | `09832a3` | `b37b021` (`3d48a85..a28980c`) | `6 / 6` |
| `mips64rt` | `71ac358`-era `master` | `9371083` (`48d47ea`) | `3 / 3` |
| `sparc64rt` | `5486608`-era `master` | `0100cc5` (`8fcf55c..0100cc5`) | `7 / 7` |
| `s390xrt` | `8410b2c` | `ca8f0c5` (`b3bc45f..558a2a5`) | `9 / 9` |
| `rt-series` | `f1a765a`-era `master` | `75ff661` | `3 / 3` |
| `sparc32rt` | `1dd1f22` | `1dd1f22` (unchanged) | `0 / 0` |
| **Total** | | | **`59 / 59`** |

`sparc32rt` had no post-`2026-11-17 02:00:00 +0900` commits: it was audited at
`1dd1f22` against the same `T1`–`T4` bar, no genuine defect was filed, and the
round records an explicit `0 / 0` rather than an omission.

---

## 1. `a32rt` (`3 / 3` in `5959599`)

- [x] **A32-R22-D1 — High — DBT — `grp_emit_grouped` Regime A2 cross-page cold slow-path fallthrough into `cold_emit_fault`**
  - **Where**: `a32rt` `src/core/core_emit_mem.c` (`grp_emit_grouped`) @ `a53ee27`.
  - **What breaks / Why**: A grouped Regime A2 emission whose span crosses a page boundary falls through to the cold path that unconditionally raises `cold_emit_fault`, so `test-m7-armhf` and `test-m8-glibc-armhf` dynamic runs abort on the first cross-page grouped access instead of handling the page-2 miss inline.
  - **Fix**: Route the cross-page cold slow-path to the page-2 miss handler instead of falling through into `cold_emit_fault`; restores `test-m7`/`test-m8` dynamic `PASS` and `45/0/0/0` parity (`5959599`).

- [x] **A32-R22-D2 — High — DBT — `grp_emit_grouped` hot-path `w22` pre-indexed writeback clobber**
  - **Where**: `a32rt` `src/core/core_emit_mem.c` (`grp_emit_grouped`) @ `a53ee27`.
  - **What breaks / Why**: The hot path reuses `w22` for the pre-indexed writeback computation while `w22` still holds the live grouped base, clobbering the address for the remaining lanes and emitting stores to a corrupted address under `--difftest`.
  - **Fix**: Spill/rename the writeback scratch so `w22` survives the pre-indexed update across all grouped lanes (`5959599`).

- [x] **A32-R22-D3 — Medium — BUILD — `Makefile` missing `-MMD -MP` header dependency tracking**
  - **Where**: `a32rt` `Makefile` @ `a53ee27`.
  - **What breaks / Why**: Without generated header dependencies, editing a shared header (e.g. the `G02` bridge or Soft-TLB headers) does not rebuild dependent objects, so stale `.o` files silently link and parity goldens drift from source.
  - **Fix**: Add `-MMD -MP` header dependency tracking to the `Makefile` (`5959599`).

---

## 2. `i686rt` (`6 / 6` in `deffa5e` / `7aa0489`)

- [x] **I686-R22-D1 — High — SMC — Sub-page SMC write-gate invalidation too coarse for nested `luajit` JIT traces**
  - **Where**: `i686rt` `src/dbt/engine_smc.c`, `src/os/signals_subpage.c` @ pre-`7aa0489`.
  - **What breaks / Why**: The SMC write gate invalidates at page granularity, so a nested `luajit` JIT trace that patches one byte discards the whole page's translations; hot traces retranslate forever and `luajit` payloads never reach steady-state parity.
  - **Fix**: Narrow the write gate to sub-page precision for nested JIT traces (`7aa0489`, `engine_smc.c`, `signals_subpage.c`).

- [x] **I686-R22-D2 — Medium — SYSCALL — `pselect6_time64` `+12` uninitialized stack-padding mask**
  - **Where**: `i686rt` `src/os/sys_misc.c` (`pselect6_time64`) @ pre-`7aa0489`.
  - **What breaks / Why**: The compat `pselect6_time64` wrapper leaves 12 bytes of stack padding uninitialized in the timeout/sigmask frame, leaking host stack bytes to the guest and diverging from the oracle under `difftest`.
  - **Fix**: Mask/zero the `+12` stack-padding region in `sys_misc.c` (`7aa0489`).

- [x] **I686-R22-D3 — Medium — SYSCALL — `F_DUPFD_CLOEXEC` / `utimensat_time64` / `statx` unimplemented**
  - **Where**: `i686rt` `src/os/sys_pass*.c`, `src/os/syscalls*.c` @ pre-`7aa0489`.
  - **What breaks / Why**: `T1`–`T4` userland (Alpine `i686`) exercises `F_DUPFD_CLOEXEC`, 64-bit `utimensat`, and `statx`; each returns `ENOSYS` and aborts package-manager and coreutils payload flows.
  - **Fix**: Implement `F_DUPFD_CLOEXEC`, `utimensat_time64`, and `statx` (`7aa0489`, `sys_pass_at.c`, `sys_pass_extra.c`, `sys_pass_fs.c`).

- [x] **I686-R22-D4 — High — SIGNALS — Missing `SA_RESTART` syscall restart**
  - **Where**: `i686rt` `src/os/signals_i386.c` @ pre-`7aa0489`.
  - **What breaks / Why**: Interrupted blocking syscalls return `-EINTR` even when the handler is installed with `SA_RESTART`, breaking `luajit` and perl-ish `T3` payloads that depend on transparent restart.
  - **Fix**: Restart eligible syscalls on `SA_RESTART` delivery (`7aa0489`, `signals_i386.c`, `decode.c`).

- [x] **I686-R22-D5 — High — PROC — Virtual-PID `kill`/`tgkill` target the wrong thread**
  - **Where**: `i686rt` `src/os/clone.c`, signal delivery @ pre-`7aa0489`.
  - **What breaks / Why**: `kill`/`tgkill` resolve virtual PIDs against host thread IDs inconsistently, so signals land on the wrong guest thread (or `ESRCH` a live one) in multi-threaded `T2` payloads.
  - **Fix**: Route virtual-PID `kill`/`tgkill` through the guest thread table (`7aa0489`, `clone.c`).

- [x] **I686-R22-D6 — Medium — ISA — x87/SSE/ALU edge-case divergences**
  - **Where**: `i686rt` `src/interp/h_x87.c`, `h_sse_ext.c`, `src/dbt/emit_*.c`, `src/x86/decode.*` @ pre-`7aa0489`.
  - **What breaks / Why**: x87 tag/precision edges, SSE extension encodings, and ALU flag corners diverge between `interp` and `dbt`, failing `41/0/0/0` parity on FP-heavy payloads.
  - **Fix**: Harden x87/SSE/ALU edges in both the interpreter and the DBT emitters (`7aa0489`, new `emit_bit.c`, `emit_mov_ext.c`, `h_sse_ext.c`).

---

## 3. `mips32rt` (`4 / 4` in `bf9f0bc` / `41f325b`)

- [x] **M32-R22-D1 — High — SYSCALL — Debian 12 `mipsel` `T1`–`T4` userland syscall gaps**
  - **Where**: `mips32rt` `src/os/syscalls_fs.c`, `syscalls_misc.c`, `syscall_min.c` @ pre-`41f325b`.
  - **What breaks / Why**: The Debian 12 `mipsel` `T1`–`T4` payload set exercises filesystem, misc, and minimal syscalls the translator leaves `ENOSYS`, aborting userland qualification before userspace initializes.
  - **Fix**: Complete the `T1`–`T4` Debian `mipsel` syscall surface (`41f325b`).

- [x] **M32-R22-D2 — High — SIGNALS — `SIGCHLD`/queued-signal delivery races (`sigchld.c`, `sigqueue.c`)**
  - **Where**: `mips32rt` `src/os/sigchld.c`, `src/os/sigqueue.c`, `src/os/signals.c` @ pre-`41f325b`.
  - **What breaks / Why**: `SIGCHLD` and queued realtime signals race the guest signal mask, delivering-or-dropping inconsistently and hanging `wait`-family `T2` payloads.
  - **Fix**: Serialize `SIGCHLD`/queued-signal delivery against the guest mask (`41f325b`).

- [x] **M32-R22-D3 — High — SMC — DBT/SMC invalidation gaps on Debian `mipsel` payloads**
  - **Where**: `mips32rt` `src/dbt/dbt.c`, `src/rt32/vm_mmap.c` @ pre-`41f325b`.
  - **What breaks / Why**: Self-modifying `T3` payloads execute stale DBT blocks after guest writes because invalidation misses mapped-region edges, diverging from the interpreter oracle.
  - **Fix**: Close the DBT/SMC invalidation gaps (`41f325b`, `dbt.c`, `vm_mmap.c`).

- [x] **M32-R22-D4 — Medium — AUDIT — `claude-fable-5-1` audit findings + `errno` mapping holes**
  - **Where**: `mips32rt` full tree, `tests/test_errno_map.c` @ pre-`41f325b`.
  - **What breaks / Why**: The independent `claude-fable-5-1` audit files residual findings and the host-`errno` map drops Debian-specific codes, so failing syscalls report the wrong guest `errno`.
  - **Fix**: Remediate the audit findings and complete the `errno` map with its regression test (`41f325b`).

---

## 4. `ppc32rt` (`3 / 3` in `2dfe7d0` / `d3820c1`)

- [x] **P32-R22-D1 — High — PROC — `vfork` synchronization broken**
  - **Where**: `ppc32rt` `src/os/proc_fork.c`, `src/os/signals.c` @ `a2ccdfc`.
  - **What breaks / Why**: `vfork` parent/child address-space sharing is unsynchronized, so the parent resumes before the child `exec`s/`_exit`s and both observe torn memory state in `T1`–`T4` shell-spawning payloads.
  - **Fix**: Synchronize `vfork` parent resumption on child `exec`/`_exit` (`d3820c1`).

- [x] **P32-R22-D2 — High — SYSCALL — `T1`–`T4` userland syscall gaps (file, `poll`, dynamic)**
  - **Where**: `ppc32rt` `src/os/syscalls_fs.c`, `syscalls_poll*.c`, `syscalls_dyn.c`, `convert.c` @ `a2ccdfc`.
  - **What breaks / Why**: File, `poll`-family, and dynamically-dispatched syscalls needed by `T1`–`T4` userland return `ENOSYS`, failing qualification before init completes.
  - **Fix**: Complete the `T1`–`T4` userland syscalls (`d3820c1`, new `syscalls_poll.c`, `convert.c` dataclass).

- [x] **P32-R22-D3 — Medium — DBT — Code-cache reclamation is linear; needs O(1) edge reclamation**
  - **Where**: `ppc32rt` `src/dbt/cache.c` @ `a2ccdfc`.
  - **What breaks / Why**: Cache eviction scans the whole block list, so long-running `T4` payloads degrade superlinearly as the cache fills and eventually stall under translation pressure.
  - **Fix**: Reclaim via O(1) edge lists (`d3820c1`, new `cache_edge.c`/`cache_edge.h`).

---

## 5. `rvrt` (`8 / 8` in `b237770`: `6d47ff0..f875739`)

- [x] **RV-R22-D1 — High — RUNNER — Standalone runner lacks thread/fork/`execve` support**
  - **Where**: `rvrt` standalone runner @ pre-`6d47ff0`.
  - **What breaks / Why**: The standalone runner cannot spawn threads, `fork`, or `execve`, so multi-process `T1`–`T4` payloads cannot even launch outside the full-system harness.
  - **Fix**: Add standalone runner thread, `fork`/`exec`, `getcwd`, and file-syscall support (`6d47ff0`).

- [x] **RV-R22-D2 — Medium — SYSCALL — `fchmodat` takes a nonexistent flags argument**
  - **Where**: `rvrt` syscall layer @ `6d47ff0`.
  - **What breaks / Why**: The Linux `fchmodat` signature takes no flags argument, but the translator marshals a fourth argument, shifting registers and corrupting the mode on every call.
  - **Fix**: Drop the spurious argument: `fchmodat` has no flags (`a960429`, with `renameat2`/`linkat`/`symlinkat` coverage).

- [x] **RV-R22-D3 — High — PROC — `exec` file-descriptor export is not transactional (`FD_CLOEXEC` leaks)**
  - **Where**: `rvrt` `exec` fd-export path @ `a960429`.
  - **What breaks / Why**: Descriptors marked `FD_CLOEXEC` leak across `exec` on partial-failure paths, so the new image inherits fds the guest explicitly closed and `T2` fd-table checks fail.
  - **Fix**: Export fds transactionally across `exec` with `FD_CLOEXEC` honored (`f875739`).

- [x] **RV-R22-D4 — High — PROC — `vfork` synchronization missing**
  - **Where**: `rvrt` `vfork` path @ `a960429`.
  - **What breaks / Why**: As in `ppc32rt`, the `vfork` parent is not parked, so parent and child race on the shared address space during `exec` setup.
  - **Fix**: Synchronize `vfork` parent/child handoff (`f875739`).

- [x] **RV-R22-D5 — Medium — SYSCALL — `waitid` unimplemented**
  - **Where**: `rvrt` wait-family layer @ `a960429`.
  - **What breaks / Why**: `waitid`-using supervisors (`T2` init-like payloads) get `ENOSYS` and cannot reap children with full `siginfo` semantics.
  - **Fix**: Implement `waitid` (`f875739`).

- [x] **RV-R22-D6 — High — ISA — `LR`/`SC` reservation survives context switch**
  - **Where**: `rvrt` atomics, scheduler @ `a960429`.
  - **What breaks / Why**: A load-reserved reservation is not cleared when its thread is descheduled, so a stale `SC` succeeds after another hart wrote the line, breaking RISC-V forward-progress and atomicity guarantees.
  - **Fix**: Clear the `LR`/`SC` reservation on context switch (`f875739`).

- [x] **RV-R22-D7 — High — DBT — Per-process DBT cache not reset across `exec`**
  - **Where**: `rvrt` DBT cache, `exec` path @ `6d47ff0`.
  - **What breaks / Why**: Translations from the pre-`exec` image survive into the new image, so the new program executes stale blocks from a different ELF at overlapping VAs.
  - **Fix**: Reset the per-process DBT cache across `exec` (with `setsid`/`getrusage`/`sysinfo`/`mknodat`/`pselect6` coverage, `623123b`).

- [x] **RV-R22-D8 — Medium — FS — Record locks use emulated state instead of direct leases**
  - **Where**: `rvrt` file-lock layer @ `623123b`.
  - **What breaks / Why**: Emulated record locks disagree with host lock visibility, so cooperating `T3` payloads (lock-gated writers) deadlock or double-write.
  - **Fix**: Issue direct record-lock leases to the host (`f875739`).

---

## 6. `loongarch64rt` (`7 / 7` in `a748562`: `a5d715f..321c0ad`)

- [x] **LA64-R22-D1 — High — PROC — Child virtual-PID collision (`vpid_self`/`vpid_parent`)**
  - **Where**: `loongarch64rt` `src/os/*pid*` @ pre-`321c0ad`.
  - **What breaks / Why**: Sibling forks can allocate the same child virtual PID, so `wait`/`kill` address the wrong child and `T2` process payloads reap-or-signal incorrectly.
  - **Fix**: Skip `vpid_self` and `vpid_parent` when allocating child virtual PIDs (`321c0ad`).

- [x] **LA64-R22-D2 — High — PROC — `FIXED_NSEC` root `ppid` asymmetric in PID translators**
  - **Where**: `loongarch64rt` PID translation @ pre-`b7e4390`.
  - **What breaks / Why**: The fixed-namespace root parent PID translates to different values on the forward and reverse paths, so `getppid` after namespaced `fork` disagrees with `/proc` state.
  - **Fix**: Make the `FIXED_NSEC` root `ppid` (`999`) symmetric in the PID translators (`b7e4390`).

- [x] **LA64-R22-D3 — High — PROC — Fork child `vpid_self` bound late; non-`vpid` host pgids swallowed**
  - **Where**: `loongarch64rt` `fork` path @ pre-`a750b32`.
  - **What breaks / Why**: The child binds `vpid_self` after it is observable, and non-`vpid` host process-group IDs are dropped instead of passed through, breaking job-control `T2` payloads.
  - **Fix**: Bind fork-child `vpid_self` before `fork` returns and pass through non-`vpid` host pgids (`a750b32`).

- [x] **LA64-R22-D4 — Medium — SYSCALL — `setsid` return value not virtualized**
  - **Where**: `loongarch64rt` `src/os/minsys_pid.c` @ pre-`3628262`.
  - **What breaks / Why**: `setsid` returns the host session ID instead of the guest-virtual one, so the guest observes a PID-namespace escape in `T1` session payloads.
  - **Fix**: Virtualize the `setsid` return value in `minsys_pid` (`3628262`).

- [x] **LA64-R22-D5 — High — SYSCALL — Virtual PIDs untranslated; `pselect6` sigmask unfiltered; path buffers shared**
  - **Where**: `loongarch64rt` PID paths, `pselect6`, pathname buffers @ pre-`ffaccc1`.
  - **What breaks / Why**: Virtual PIDs leak as host PIDs on translation paths, `pselect6` installs the raw guest sigmask without filtering, and shared path buffers race across threads, each corrupting multi-threaded `T3` payloads.
  - **Fix**: Translate virtual PIDs, filter the `pselect6` sigmask, and make path buffers thread-local (`ffaccc1`).

- [x] **LA64-R22-D6 — Medium — SYSCALL — POSIX userland gaps incl. `mknodat` and `pselect6` (`make -j2` jobserver)**
  - **Where**: `loongarch64rt` syscall layer @ pre-`a5d715f`.
  - **What breaks / Why**: Missing POSIX syscalls (notably `mknodat` and a correct `pselect6`) break the Alpine `T1`–`T4` userland, including the `make -j2` jobserver pipe protocol used by build payloads.
  - **Fix**: Add the POSIX userland syscalls including `mknodat` and `pselect6` (`a5d715f`).

- [x] **LA64-R22-D7 — Medium — ISA — LSX/LASX vector lowering defects**
  - **Where**: `loongarch64rt` LSX/LASX emitters @ pre-`a5d715f`.
  - **What breaks / Why**: Loongson SIMD extension lowerings mishandle lane widths, so vectorized `T4` payloads diverge from the interpreter oracle.
  - **Fix**: Repair the LSX/LASX fixes across `a5d715f..321c0ad`.

---

## 7. `ppc64rt` (`6 / 6` in `b37b021`: `3d48a85..a28980c`)

- [x] **P64-R22-D1 — High — LOADER — `ET_DYN` (PIE) main images not loadable**
  - **Where**: `ppc64rt` `src/run/*` @ `09832a3`.
  - **What breaks / Why**: Position-independent main images (`ET_DYN`) are rejected by the loader, so modern PIE-linked LE and BE binaries cannot start at all.
  - **Fix**: Load `ET_DYN` (PIE) main images (`1b04a5a`, merged in `b37b021`).

- [x] **P64-R22-D2 — Medium — PROFILE — LE `e_flags == 0` GNU `as`+`ld` images misclassified**
  - **Where**: `ppc64rt` `profile.h` @ `09832a3`.
  - **What breaks / Why**: GNU `as`+`ld` emit LE objects with `e_flags == 0`, which the ABI classifier rejects as unknown instead of defaulting to ELFv2, failing `T1` toolchain-built payloads.
  - **Fix**: Classify LE `e_flags == 0` GNU `as`+`ld` output as ELFv2 (`1b04a5a` via `profile.h`).

- [x] **P64-R22-D3 — High — DBT — `fetch.c` mid-block `ext_*` prematurely terminates the block**
  - **Where**: `ppc64rt` `src/dbt/fetch.c` @ `09832a3`.
  - **What breaks / Why**: Extended-opcode (`ext_*`) decode inside a block ends translation early, splitting hot loops into single-instruction fragments and collapsing IBTC hit rates on `cc1plus`-class payloads.
  - **Fix**: Continue the block across mid-block `ext_*` instead of terminating (`a28980c`); add `xxspltw` coverage (`1b04a5a`).

- [x] **P64-R22-D4 — High — PERF — 4K Soft-TLB/IBTC thrash on `cc1plus` (`475 MiB` `VmRSS`)**
  - **Where**: `ppc64rt` Soft-TLB/IBTC sizing @ `09832a3`.
  - **What breaks / Why**: 4 KiB-granularity Soft-TLB/IBTC entries thrash on compiler-sized working sets (`cc1plus` reaches `475 MiB` `VmRSS`), making DBT slower than the interpreter on the heaviest `T4` payload.
  - **Fix**: Scale to 64K IBTC/Soft-TLB coverage (`256 MiB`), restoring DBT margin (`a28980c`).

- [x] **P64-R22-D5 — Medium — DBT — VMX/VSX fast paths missing (`vcmpequb[.]`, `vspltis*`, `xxswapd`, `xxspltw`)**
  - **Where**: `ppc64rt` vector emitters @ `09832a3`.
  - **What breaks / Why**: Common vector idioms fall back to the interpreter on every iteration, so vectorized `T4` payloads never reach the `2.10x`-vs-`qemu-ppc64` ledger target.
  - **Fix**: Add VMX/VSX `vcmpequb[.]`/`vspltis*`/`xxswapd`/`xxspltw` fast paths (`a28980c`, `1b04a5a`).

- [x] **P64-R22-D6 — High — ELFv1 — BE `.opd`/R2 TOC/`FPSCR`/`fork` defects**
  - **Where**: `ppc64rt` BE ELFv1 `.opd` handling, R2 TOC, `FPSCR`, `fork` @ `09832a3`.
  - **What breaks / Why**: The full 10-category BE ELFv1 parity suite exposes descriptor (`.opd`), TOC-pointer (R2), floating-point status (`FPSCR`), and `fork` defects that abort BE userland before `T1` completes.
  - **Fix**: Repair BE ELFv1 `.opd`/R2 TOC/`FPSCR`/`fork` with `sysroot-be` (`3d48a85`).

---

## 8. `mips64rt` (`3 / 3` in `9371083` / `48d47ea`)

- [x] **M64-R22-D1 — High — PROC — `vfork` synchronization missing**
  - **Where**: `mips64rt` `vfork` path @ pre-`48d47ea`.
  - **What breaks / Why**: The `vfork` parent resumes concurrently with the child, tearing the shared address space during `exec` setup in shell-heavy `T1` payloads.
  - **Fix**: Synchronize `vfork` parent resumption on child `exec`/`_exit` (`48d47ea`).

- [x] **M64-R22-D2 — High — SIGNALS — `SA_RESTART` signal delivery incomplete**
  - **Where**: `mips64rt` `src/os/signal_core.c`, `sigframe.c`, `sigact.c` @ pre-`48d47ea`.
  - **What breaks / Why**: Signals delivered over restartable syscalls do not honor `SA_RESTART`, so blocking `T2`/`T3` payloads spuriously fail with `-EINTR`.
  - **Fix**: Complete `SA_RESTART` signal delivery (`48d47ea`).

- [x] **M64-R22-D3 — High — SYSCALL — Debian `mips64el` `T1`–`T4` userland syscall gaps**
  - **Where**: `mips64rt` `src/os/syscalls_fs.c`, `syscalls_misc.c`, `syscalls_poll.c`, `syscall_min.c`, `errno_map.h` @ pre-`48d47ea`.
  - **What breaks / Why**: Filesystem, misc, `poll`-family, and minimal syscalls needed by Debian `mips64el` userland return `ENOSYS`, failing qualification at bring-up.
  - **Fix**: Complete the Debian `mips64el` `T1`–`T4` syscall surface with its `errno` map (`48d47ea`).

---

## 9. `sparc64rt` (`7 / 7` in `0100cc5`: `8fcf55c..0100cc5`)

- [x] **S64-R22-D1 — High — DBT/W^X — Code arena left `PROT_READ|PROT_WRITE` after mid-block invalidation flush**
  - **Where**: `sparc64rt` `src/dbt/*` (arena flush) @ `09c4b05`.
  - **What breaks / Why**: A mid-block invalidation flush restores the W^X code arena as writable-but-not-executable, so the next block entry faults on the host and the translator wedges after the first SMC event.
  - **Fix**: Keep the W^X arena executable across mid-block invalidation flushes (`0100cc5`).

- [x] **S64-R22-D2 — High — PROC — `clone` stack frame misses the `+2047` SPARC V9 stack bias**
  - **Where**: `sparc64rt` `clone` path (`clone_stackframe`) @ pre-`099ad2b`.
  - **What breaks / Why**: The child stack pointer omits the mandatory 2047-byte V9 bias, so the first callee-save spill in the child writes 2047 bytes below the allocated stack and corrupts the parent frame.
  - **Fix**: Apply the `+2047` SPARC V9 stack bias in `clone_stackframe` (`099ad2b`).

- [x] **S64-R22-D3 — High — SIGNALS — SPARC signal numbering/sigmask wrong (`32..64` RT signals unmapped)**
  - **Where**: `sparc64rt` signal numbering, guest sigmask @ pre-`007ec7c`.
  - **What breaks / Why**: SPARC signal numbers map 1:1 from the host table and realtime signals `32..64` are unmapped, so `rt_sigaction`/`rt_sigprocmask` program the wrong signals and handlers never fire.
  - **Fix**: Map SPARC numbering with realtime signals `32..64` (`007ec7c`; audit remediation `099ad2b`).

- [x] **S64-R22-D4 — High — SIGNALS — `ppoll`/`pselect6` temporary mask installed in the wrong state; no synchronous `-EINTR`**
  - **Where**: `sparc64rt` `src/os/poll/*` @ pre-`25ced5e`.
  - **What breaks / Why**: The temporary signal mask for `ppoll`/`pselect6` is installed outside guest signal state (leaking across the call), and pending signals do not synchronously interrupt with `-EINTR`, hanging signal-driven `T3` payloads.
  - **Fix**: Install the temporary mask in guest signal state and deliver pending guest signals synchronously on `-EINTR` with the saved mask (`007ec7c`, `25ced5e`).

- [x] **S64-R22-D5 — Medium — LOCKS — Lock release path drops wakeups**
  - **Where**: `sparc64rt` lock release @ pre-`099ad2b`.
  - **What breaks / Why**: Releasing a guest lock without waking waiters stalls contended `T3` threading payloads until timeout.
  - **Fix**: Repair the lock release path (`099ad2b` audit remediation).

- [x] **S64-R22-D6 — Medium — SYSCALL — `rusage` fields unpopulated**
  - **Where**: `sparc64rt` `rusage` marshaling @ pre-`099ad2b`.
  - **What breaks / Why**: `wait4`/`getrusage` return zeroed fields, so resource-accounting `T2` payloads (and the `make -j2` jobserver) mis-schedule.
  - **Fix**: Populate `rusage` (`099ad2b` audit remediation).

- [x] **S64-R22-D7 — Medium — SYSCALL — SPARC BSD-derived `flock`/`errno` marshaling wrong**
  - **Where**: `sparc64rt` `flock`, `errno` map, FP/window paths @ pre-`8fcf55c`.
  - **What breaks / Why**: SPARC's BSD-derived `flock` opcodes and several `errno` values marshal to the wrong host constants, so lock-gated `T3` payloads and error-path tests fail on Debian `sparc64` userland.
  - **Fix**: Correct the SPARC BSD-derived `flock`/`errno` marshaling with FP/window fixes (`8fcf55c`, Debian `T1`–`T4` userland syscalls).

---

## 10. `s390xrt` (`9 / 9` in `ca8f0c5`: `b3bc45f..558a2a5`)

- [x] **S390-R22-D1 — High — ISA — `IIHH`/`LDEB`/BFP condition-code and `CONVERT TO FIXED` rounding wrong**
  - **Where**: `s390xrt` `src/interp/*` @ `8410b2c`.
  - **What breaks / Why**: `IIHH` (insert immediate high-high) mis-merges, `LDEB` (lengthen short-to-long BFP) mishandles NaN payloads, BFP condition codes misreport, and `CONVERT TO FIXED` rounds instead of truncating toward zero, each diverging from the `s390x` oracle under `difftest`.
  - **Fix**: Repair `IIHH`, `LDEB`, BFP CC, and `CONVERT TO FIXED` rounding (`b3bc45f`).

- [x] **S390-R22-D2 — High — ISA — `RXY-a` long-displacement ops undecoded**
  - **Where**: `s390xrt` decoder/interpreter @ `b3bc45f`.
  - **What breaks / Why**: The `RXY-a` long-displacement family (`CHY`/`AHY`/`SHY`/`MHY`/`ALY`/`SLY`/`ALC`/`SLB`/`ALCG`/`SLBG`) traps to `EXIT_UNDEF`, aborting any `z13` userland binary that uses 20-bit displacements.
  - **Fix**: Decode and execute the `RXY-a` family (`7e801e7`).

- [x] **S390-R22-D3 — High — ISA — `fpenv` BFP rounding/flags and `LM`/`STM` wrap mishandled**
  - **Where**: `s390xrt` FP environment, `LM`/`STM` @ `b3bc45f`.
  - **What breaks / Why**: The floating-point environment ignores rounding-mode/flag updates and `LM`/`STM` mishandle register-wrap and address wrap, corrupting FP control state across calls.
  - **Fix**: Wire `fpenv` BFP rounding/flags and `LM`/`STM` wrap with AOT hooks (`eafb781`).

- [x] **S390-R22-D4 — High — DBT — Single global JIT arena/cache shared across threads**
  - **Where**: `s390xrt` `src/dbt/*` @ `b3bc45f`.
  - **What breaks / Why**: All threads share one JIT arena and cache state plus global Soft-TLB stubs, so concurrent translation corrupts emitted code and cross-thread invalidation misses.
  - **Fix**: Move to per-thread JIT arena/cache state with per-thread Soft-TLB stub binding (`62750c6`).

- [x] **S390-R22-D5 — High — ISA/INTERP — `z13` userland opcode gaps; no portable binary128 BFP; `vm_protect` whole-range only**
  - **Where**: `s390xrt` `src/interp/*`, `src/vm/*` @ `62750c6`.
  - **What breaks / Why**: Missing `z13` userland opcodes abort `T4` payloads, quad-precision BFP has no portable software fallback on hosts without it, and `vm_protect` can only change whole mappings, breaking partial `mprotect` userland flows.
  - **Fix**: Add the `z13` userland opcodes with portable binary128 BFP and sub-range `vm_protect` (`526bf35`).

- [x] **S390-R22-D6 — High — DBT — No native AArch64 W^X block JIT (C-helper DBT only)**
  - **Where**: `s390xrt` `src/dbt/*` @ `526bf35`.
  - **What breaks / Why**: DBT lowers through C helpers instead of emitting native AArch64 blocks, leaving the `22.0x` Darwin DBT ledger target unreachable and `T4` throughput below `qemu-s390x`.
  - **Fix**: Add the native AArch64 W^X block JIT with inline Soft-TLB/NEON and IBTC/chaining (`7665c49`, in `lane/s390x-jit` merged via `71a92cf`).

- [x] **S390-R22-D7 — High — OS/VM — OS/VM audit findings: signals, futex, `vfork`, `exec`, `vm64`, memory**
  - **Where**: `s390xrt` `src/os/*`, `src/vm/*` @ `7665c49`.
  - **What breaks / Why**: The OS/VM audit files defects across signal handling, futex, `vfork`, `exec`, `vm64`, and memory management, each fatal to the multi-process promotion.
  - **Fix**: Remediate the OS/VM audit findings (`ed9492e`, in `lane/s390x-os` merged via `cb83b2f`; thread/fork/`exec`/futex/UAPI-signal completeness `88ada38`; multi-thread substrate `20b1afa`).

- [x] **S390-R22-D8 — High — OS — 64-bit UAPI `rt_sigframe` offsets, `siginfo`, leader mask, `rt_sigqueueinfo` wrong**
  - **Where**: `s390xrt` `src/os/*signal*` @ `ed9492e`.
  - **What breaks / Why**: The 64-bit `rt_sigframe` layout offsets disagree with the UAPI, `siginfo` fields marshal wrong, the thread-group leader mask is miscomputed, and self-`rt_sigqueueinfo` codes are rejected, so signaled `T2`/`T3` payloads crash on delivery.
  - **Fix**: Fix the 64-bit sigframe offsets, wake-credit check, leader signal mask, and high baud rates (`17a0085`); close the remaining audit mediums — sigframe, `siginfo`, wake credits, `exec` paths, termios, shared `mmap` (`14e5e7a`); thread-gate portable `difftest`, tighten wake credits, sysroot-aware `/proc/self/exe`, allow self `rt_sigqueueinfo` codes, guard AOT save (`ebc0dff`); close `difftest` parity (`34/34`) and the `musl` `proc.c` build (`503c48a`).

- [x] **S390-R22-D9 — Medium — OS — Guest `iovec` unsegmented; `getdents64` cursors fd-local and `dup`-unsafe**
  - **Where**: `s390xrt` `src/os/*` (vectored I/O, `getdents64`) @ `17a0085`.
  - **What breaks / Why**: Unsegmented guest `iovec` arrays over-read across mappings on large vectored I/O, and `getdents64` cursors are keyed per-fd without device/inode tags, so cursors alias across `dup*` and directory reads repeat or skip entries on Darwin hosts.
  - **Fix**: Segment guest I/O vectors with resumable `getdents64` plus `mknod`/`mknodat` (`3c33522`); tag Darwin `getdents64` cursors with `(dev, ino)` for any fd, kept across `dup*` (`558a2a5`).

---

## 11. `rt-series` (`3 / 3` in `75ff661`)

- [x] **RTS-R22-D1 — High — TESTS — `bench_sys.h` cannot emit `ppc64` BE ELFv1 `.opd` or freestanding `s390x` guests**
  - **Where**: `rt-series` `tests/bench_sys.h` @ pre-`75ff661`.
  - **What breaks / Why**: The shared guest-syscall header has no `ppc64` big-endian ELFv1 `.opd` function-descriptor glue and no freestanding `s390x` `_start`/`write`/`getpid`/`exit_group` inline asm, so uniform benchmark guests cannot build for the two newly qualified targets.
  - **Fix**: Add the `ppc64` BE ELFv1 `.opd` and `s390x` freestanding inline-asm glue to `bench_sys.h` (`75ff661`).

- [x] **RTS-R22-D2 — Medium — CATALOGUE — `is_luajit_expected_missing` misdetects absent JIT payloads**
  - **Where**: `rt-series` catalogue payload scripts @ pre-`75ff661`.
  - **What breaks / Why**: The expected-missing detector for `luajit` payloads does not consult `CATALOGUE_ARCH`, so architectures where the payload is legitimately absent report `GAP` instead of the expected-missing pass.
  - **Fix**: Detect `is_luajit_expected_missing` via `CATALOGUE_ARCH` (`75ff661`).

- [x] **RTS-R22-D3 — Medium — CATALOGUE — `docker_ids()` matches unrelated shared-host containers**
  - **Where**: `rt-series` `tools/run_catalogue.sh` (`docker_ids()`) @ pre-`75ff661`.
  - **What breaks / Why**: The container-ID filter matches by loose substring, so unrelated shared-host containers (`redeye-*`, `gym-*`, `browser-vpn-*`) are flagged or touched during catalogue runs.
  - **Fix**: Scope `docker_ids()` so unrelated shared-host containers are never flagged or touched (`75ff661`).

---

## 12. Pre-Merge Review Provenance

Round 22 findings were hunted with the `fable_*`/`wo_*` review logs in
`scratch/wo_r22/` (DBT/CPU, per-ISA `T14` lanes, `s390x` JIT/OS, `ppc64`
BE-parity, `T1`–`T4` qualification sweeps), remediated on the per-repository
lanes above, and re-verified by independent post-lane review passes with
`tests/parity_suite.sh` (`0 FAIL, 0 GAP, 0 SKIP` per repository),
`--difftest` (`0` divergences), and `run_catalogue.sh guest-payload` `T1`–`T4`
`ALL_OK` on every sysroot. `docs/DEFECTS.md` §1 records the converged
revisions with `59 / 59` resolved and `0` open.
