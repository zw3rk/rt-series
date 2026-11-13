# Catalogue coverage: current gates and improvement todos

> **Historical Audit Snapshot (Resolved in Wave C1 / Wave C2)**: Sections 1 and 2 below record the pre-Wave-C1 audit baseline of `tools/run_catalogue.sh` and per-repository gates. Since Wave C1/C2, `tools/run_catalogue.sh` enforces fail-closed execution (`matched > 0`, `pass > 0`, `fail == 0`, and `skip == 0` unless `CATALOGUE_ALLOW_SKIP=1`), `tests/catalogue/run_catalogue.sh` delegates to `tools/run_catalogue.sh`, and `guest-payload` implements all Tier 1–4 assertions and exits non-zero on any skipped check unless `CATALOGUE_ALLOW_SKIP=1`.

Status of `tools/run_catalogue.sh` and the per-repository qualification gates, plus the grind suites worth adding. Companion to [`SOFTWARE-CATALOGUE.md`](SOFTWARE-CATALOGUE.md). Reviewed by `astra` ([`lode/reviews/2026-10-29-catalogue-todo-astra.md`](../lode/reviews/2026-10-29-catalogue-todo-astra.md)) and `fable` ([`lode/reviews/2026-10-29-catalogue-todo-fable.md`](../lode/reviews/2026-10-29-catalogue-todo-fable.md)). The smoke command and the catalogue document disagree; the tables below are from the scripts as they stood prior to Wave C1/C2.

`make catalogue-smoke` runs `tools/run_catalogue.sh smoke`. For each of the ten repositories it executes `tests/parity_suite.sh` when that file exists, and `make check` otherwise. The whole script sits inside `timeout 360s`. An unknown `--arch` selects nothing and the command still exits 0.

`guest-payload` is a second mode of the same script. Smoke never calls it. It runs only when launched by hand inside a guest shell:

```sh
<arch>rt --sysroot <dir> /bin/sh tools/run_catalogue.sh guest-payload
```

`tests/catalogue/run_catalogue.sh`, named as the acceptance command in [`PERF-PLAN-P13.md`](PERF-PLAN-P13.md), is not in any repository.

---

## 1. What smoke runs today

| Repo | Smoke entry | What that entry executes | QEMU vs `--interp` vs `--dbt` vs `--difftest` |
|---|---|---|---|
| `a32rt` | `make check` | Line-limit, `x18`, `push`/`pop`, and banned-C scans. `test-m1`…`test-m8` and `test-all-hl` exist and are off this path. | No |
| `i686rt` | `parity_suite.sh` | Line limits, `build-darwin`, `test_u3_sites`, and a file-exists list. `test-p1`…`test-p5`, BusyBox, and the golden FPU runs are separate Make targets. | No |
| `mips32rt` | `make check` | Host `check_abi_invariants` and `test_decode`, twice. `run_p1_isa.sh`, `run_p3_fpu.sh`, `run_p4.sh`, `run_p5.sh`, `run_p6.sh`, and `difftest/run_difftest.sh` are not called. | No |
| `ppc32rt` | `make check` | `cc -fsyntax-only` of the sources. `test_p1_isa.c`, `test_p3_fp_spe.c`, `test_p4_threads_signals.c`, `test_p5_dyn.c`, `test_h1_smc.c`, and `test_h4_cxx17.cc` are not built. | No |
| `sparc32rt` | `make check` | Build, line limits, and `check_abi_invariants`. The `test_p*` / `test_h*` guests are not run. | No |
| `rvrt` | `parity_suite.sh` | Six Make targets: image expectation, image guest, loader, signal suspend, trap signal, signal exec. The header says this stands in for a ~30-minute `make check`. The `test/` tree, RV32 parity, and U5 DBT checks stay off this path. | No |
| `loongarch64rt` | `parity_suite.sh` | P1 (`p1_mini`, `test_p1_isa`), P2 (hello, printf, qsort, malloc, fileio), P3 FP/LSX/LASX, P4 threads, P5 dynamic musl, P6 sched, CoreMark CRCs, H1 SMC, H4 C++17. Each is oracle, `--interp`, `--dbt`, and `--difftest`. A missing sysroot is a GAP, and a GAP fails the script. | Yes |
| `ppc64rt` | `parity_suite.sh` | Nine rows: `p1_isa`, `p3_fp`, `p4_threads`, `p5_dyn`, `h1_smc`, `h2_libc`, `h3_compute`, `h4_cxx`, plus an AOT magic check. Stdout, stderr, and exit are compared with `qemu-ppc64le -cpu power10`. | Yes |
| `mips64rt` | `parity_suite.sh` | Host units, then one Docker run over N64/N32 × LE/BE: P1, P3, P4, P6, H1, H4, dynamic P5, five `--difftest` fixtures, and N64LE BusyBox. When Docker is absent, the script records `SKIP` and still exits 0 (`[ "$fail" -eq 0 ]`). When Docker runs, its inner timeout is 480s, so the outer 360s cuts it off. | Yes (when Docker is available) |
| `sparc64rt` | `parity_suite.sh` | `guest_p1`, `guest_p3`, `guest_p4`, dynamic `test_p5_dyn`, two BusyBox legs, and `test_p6_page_perm`, with `--difftest` on the single-threaded legs. On Darwin with no `qemu-sparc64`, the oracle rows are recorded as GAP and the script still fails closed on GAP. | Yes, when `qemu-sparc64` is on `PATH` |

The runners in `loongarch64rt`, `ppc64rt`, and `mips64rt` are the template for the other seven, subject to the golden-bundle contract below so Darwin and `hl` legs do not depend on a live Linux-only `qemu-<arch>` binary.

---

## 2. What `guest-payload` checks

Tier 5 is described in the script header and in [`SOFTWARE-CATALOGUE.md`](SOFTWARE-CATALOGUE.md). The script implements tiers 1–4. The help text offers `--tier 1..4`.

| Tier | Assertions that run | Documented, and absent from the script |
|---|---|---|
| T1 | `sh` arithmetic `17+25=42`; `sort \| uniq -c \| sed \| grep`; `gawk`/`awk` sum `14.75:20.25`; `find` counts two `*.txt` files | `dash`, `bash` job control, `tar`, `gzip`, `sha256sum`, `diff -u`, `tree`, `#!`, `/proc/self` |
| T2 | `openssl enc -aes-256-cbc` round trip; `zstd -T1`; `xz -T1`; `jq` filter `b,c`; `sqlite3` window `AVG` plus `PRAGMA integrity_check` | `gzip`, `bzip2`, `openssl dgst` / `pkeyutl`, anything larger than one line |
| T3 | Lua 5.4 coroutine sum `5050`; LuaJIT bit loop golden `675631440`; Python 3 SHA-256 prefix `b5abbd2c04884798` plus zlib | `jit.status()==true` + trace-compilation proof (the LuaJIT loop can stay in the interpreter or abort trace recording); Python `threading` |
| T4 | `git init -b master` and one commit; `gcc -O2` fib(20)+`sqrt(2)` then `readelf`/`nm`/`strip` and run the ELF; `g++ -std=c++17` exception plus `dynamic_cast` | `make -j2`, `std::thread`, `objdump`, `as`/`ld` of a `.s` file |

Prior to Wave C1, a missing T2–T4 tool incremented `skip` and the script still printed `ALL_OK` and exited 0 (an empty sysroot that lacked `sh` failed T1, while a sysroot with a shell and nothing else passed). As of Wave C1/C2, `guest-payload` exits non-zero whenever `skip > 0` unless `CATALOGUE_ALLOW_SKIP=1` is explicitly set.

The suite that is already uniform is [`tests/bench_suite.c`](../tests/bench_suite.c) plus [`tools/bench_harness.sh`](../tools/bench_harness.sh): `coremark`, `chacha20`, `vfp_simd`, `calls_ibtc`, and `getpid`, with a CRC check on every guest ABI. It uses the default rounding mode, one thread, and no signals, `mmap`, `fork`, `exec`, dynamic linker, or self-modifying code. `getpid` does not exercise the vDSO. Keep it as the minute-scale smoke. It does not qualify the translator.

---

## 3. Grind suites worth adding

`stress-ng`, QEMU `tests/tcg/multiarch`, and a guest-`gcc` torture differential are the grind suites that hit this translator. CoreMark, Embench, and CoreMark-PRO are too narrow to carry that load. SPEC CPU 2017 is a licensed performance bar and a poor feature test. Phoronix wraps the suites below and adds version drift.

| Suite | What it hammers & portability contract | Budget |
|---|---|---|
| **QEMU `tests/tcg/multiarch`** | Written to break linux-user. `signals`, `sigbus`, `sigreturn-sigmask`, `segfault`, `prot-none`, `test-mmap`, `munmap-pthread`, `linux-madvise`, `testthread`, `float_convd` / `float_convs` / `float_madds`, `sha1`, and `tb-link` (self-modifying code across linked blocks). Vendor the per-arch `.ref` files for `float_*`, pass explicit guest page size (`4096`, or `8192` on `sparc64rt`) to `test-mmap` / `prot-none` so Darwin 16 KiB hosts exercise sub-page protection, and curate target-portable sources by revision. | Tier M (`catalogue-qualify`), both engines, against committed golden + live `qemu-<arch>` on Linux |
| **`stress-ng` (explicit stressor allowlist + `--verify --metrics-brief --yaml`)** | The load suite. Never rely on exit status alone (`stress-ng` exits 0 when stressors are skipped or return `ENOSYS`/`EOPNOTSUPP`); parse the YAML output and require `exit == 0`, `bogo_ops > 0`, and `0` verification failures for every required stressor. Split into two explicit lists:<br>• **Core CPU/VM/Thread list (all 3 backends: `linux`, `hl`, `darwin`)**: `cpu`, `opcode`, `atomic`, `futex`, `pthread`, `fp`, `matrix`, `mmap`, `mremap`, `mprotect`, `madvise`, `brk`, `stack`, `fork`, `vfork`, `clone`, `exec`, `spawn`, `signal`, `pipe`, `poll`, `socket`, `dentry`, `getdent`, `open`, `seek`, `malloc`, `icache`, `cache`, `tlb`, `fault`, `zlib`.<br>• **Linux/`hl` kernel-fd & procfs list**: `vma`, `bad-altstack`, `sigfd`, `timer`, `itimer`, `epoll`, `eventfd`, `lockf`, `procfs` (tracked separately against `backend_darwin.c`'s supported surface). | Nightly 5–10 s per stressor on Linux; rotating ABI subset on Darwin/`hl`; weekly 60 s soak |
| **`gcc.c-torture/execute` + Csmith + Yarpgen** | The DBT grind. Compile each program with `-ffp-contract=off` at `-O0` and `-O2`. Always compare `qemu-<arch>` vs `--interp` vs `--dbt` on the **exact same compiled ELF binary** (never compare `-O0` checksums against `-O2` checksums, which legitimately diverge under `i686` x87 80-bit excess precision). Record generator version, seed, compiler flags, and reduced reproducer on any mismatch. | Torture on the nightly; Csmith/Yarpgen as a weekly soak |
| **Berkeley TestFloat (`testfloat_gen \| guest testfloat_ver`)** | Rounding modes, tininess before/after rounding, sNaN and qNaN payloads, signed zero, exact underflow. Run `testfloat_gen` on the host piped into a static guest `testfloat_ver` binary (with ISA-specific NaN/tininess configuration for ARM, x86, MIPS Legacy/2008, PowerPC, SPARC, RISC-V, and LoongArch) so full verification completes in minutes rather than days. | Nightly curated seed corpus; weekly full per FPU |
| **musl `libc-test` + LTP `syscalls`** | The intended H2 gate, currently off the smoke path. `functional`, `math`, `pthread` (cancel, robust, once, condvar), plus `mmap`, `mprotect`, `mremap`, `clone`, `futex`, `rt_sigaction`, `sigaltstack`, `epoll`, `socketpair` / `SCM_RIGHTS`, `statx`, `getdents64`, `EFAULT`. Maintain explicit expected pass/exception manifests keyed by `(ABI, host_backend, provider)` rather than a single unreviewed QEMU failure set, so Darwin vs Linux kernel differences and QEMU bugs remain visible and audited. | Nightly |
| **compiler-rt builtins** | `div` / `rem` helper ABI symbols (`__divsi3`, `__modsi3`, `__divdi3`, `__udivmodti4`), overflow helpers (`__mulosi4`, `__addosi4`), and soft-float edges. Call the helper ABI symbols directly with boundary bit patterns (such as `0x80000000` / `-1`) rather than triggering C signed-division UB in the test harness. | Nightly |
| **CPython `python -m test`**, **LuaJIT `test/` with trace verification**, **SQLite `testfixture` + `speedtest1`**, **OpenSSL `make test`** | Real allocators, threads, `ctypes` into a DSO, nested guest JIT (W^X and cache flush), B-tree and file locks, and crypto. For LuaJIT (on supported targets: `arm32`, `i686`, `mips32`, `ppc32`, `mips64`), require `jit.status() == true` **and** `jit.attach` / `-jdump` confirmation that machine-code traces were compiled and executed. Exclude network and tty tests. | Nightly subset; weekly full |
| **Git `make test`**, **coreutils / gawk / grep / sed / diffutils / findutils / make `make check`**, **BusyBox or musl rebuild** | Fork, exec, pipes, `#!`, jobserver, `getdents`, and the dynamic linker, in programs people actually run. A Linux `defconfig` build and a 3-stage guest GCC bootstrap are the graduation form of this, measured in hours. | Weekly for the upstream suites; bootstrap is a release gate |
| **lmbench `lat_syscall`, `lat_ctx`, `lat_pagefault`, `lat_proc`, `bw_mmap`** | Short load on the syscall, fork, and fault paths with per-test wall-clock timeouts and output sanity checks. Timings are not an oracle; the gate is clean completion without hangs or corruption. | Nightly |
| **Per-ISA only** | `riscv-arch-test` for `rvrt`. QEMU `tests/tcg/<arch>` for delay-slot, register-window, Thumb interworking, and e500 SPE cases. OpenJDK only where a port exists (`arm`, `i686`, `ppc64le`, `riscv64`, `loongarch64`): it is the hardest nested JIT, and it is not uniform. | After the shared grind is green |

---

## 4. Improvement todos (Reviewed & Tiered)

To prevent CI timeout collapse while eliminating false-green smoke passes, the unified runner separates **three explicit execution budgets**:
- **Tier S (`make catalogue-smoke`, `< 2 min` total)**: Per-commit/PR gate across all 10 repos. Runs structural checks, `bench_suite --smoke` CRCs, and fast prebuilt static guest sentinels (`p1_isa`, `p3_fp_simd`, `p4_threads_signals`, `h1_smc`, `h4_cxx17`, AOT reload counter check) against committed golden bundles (and live `qemu-<arch>` on Linux).
- **Tier M (`make catalogue-qualify`, `< 10 min`)**: Merge / phase-gate (`RC`) qualification. Runs all 16 ABI rows, dynamic `PT_INTERP` (`musl` + `glibc` `test_p5_dyn` + `BusyBox`), `guest-payload` (`T1`–`T4` with `skip == 0`), `tests/tcg/multiarch`, and the P3 concurrency/memory/signal-frame suite across `linux`, `hl`, and `darwin`.
- **Tier N / W (`make catalogue-grind`, Nightly / Weekly)**: Runs `stress-ng --verify`, `libc-test` + LTP, `gcc.c-torture`/Csmith/Yarpgen, TestFloat, compiler-rt builtins, and application test suites.

### P0 — Unify the runner, oracle golden contract, and budgets

- [ ] Freeze a shared row contract (`tools/parity_contract.sh`) in `rt-series` emitting structured rows (`repo`, `abi`, `host`, `case`, `engine`, `status` in `{PASS, FAIL, GAP}`, `elapsed_ms`) and require every repo's `tests/parity_suite.sh` to implement it. Separate structural checks (`make check`) from guest execution parity so structural-only runs never report as guest parity.
- [ ] Fail closed when `--arch` matches nothing, when `pass < expected_cases`, or when any `GAP` or `SKIP` occurs on a required host/ABI cell (`mips64rt` must not exit 0 on `SKIP`).
- [ ] Establish the **Golden Bundle & Oracle Contract** across the 3 host backends:
  - Pin the `qemu-<arch>` version and `-cpu <model>` flags per ABI.
  - Commit deterministic golden bundles (`stdout`, normalized `stderr`, `exit_code`, `si_code`) under `tests/golden/<abi>/` generated from the Linux oracle leg.
  - On **Linux (`-linux-aarch64`)**, compare `--interp`, `--dbt`, and `--difftest` against both live `qemu-<arch>` and the committed golden bundle.
  - On **Darwin (`-darwin-arm64`)** and **`hyper-linux` (`hl`)**, compare `--interp`, `--dbt`, and `--difftest` against the committed golden bundle (with a deterministic per-host stderr normalizer for `hl: ` harness lines) so Darwin and `hl` never degrade to `GAP` due to missing host `qemu-<arch>`.
  - Where `qemu-<arch>` has a documented architectural bug (e.g. `mips64` annulled branch-likely page-end fetch fault offset, `sparc64` `STQF`), record an explicit `KNOWN_QEMU_QUIRK` entry anchored to real Linux hardware / ISA manual behavior rather than weakening the test.
- [ ] On deliberate fault cases (`SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP`), capture guest `siginfo_t` inside the fixture: compare `si_code` and `si_signo` exactly, and compare `si_addr` as a page/instruction offset relative to the guest mapping (masking Class-A window base `xG`).
- [ ] Run every ABI/mode variant as its own explicit row with declared ELF ABI, endianness, CPU/FPU profile, and `libc`:
  - `a32rt`: `armhf` A32 and `armhf` Thumb-2 (`musl` & `glibc`)
  - `i686rt`: `i686` (`musl` & `glibc`)
  - `mips32rt`: O32 `mipsel` (LE, Legacy & 2008 NaN) and O32 `mips` (BE) (`musl` & `glibc`)
  - `ppc32rt`: Classic 32-bit BE (`750`/`7400`) and NXP `e500v2` SPE (`musl`, `muslspe`, `glibc`)
  - `sparc32rt`: SPARC V8 BE (`LEON3/4`, `glibc`)
  - `rvrt`: `RV64GC` (`lp64d`) and `RV32GC` (`ilp32d`) (`musl` & `glibc`)
  - `loongarch64rt`: `LA64` `LP64D` (`LSX` + `LASX`, `musl` & `glibc`)
  - `ppc64rt`: `ppc64le` ELFv2 (`VMX` + `VSX`, `musl` & `glibc`)
  - `mips64rt`: `N64` LE, `N64` BE, `N32` LE, and `N32` BE (`musl` & `glibc`)
  - `sparc64rt`: SPARC V9 64-bit BE (`glibc`)
- [ ] Replace the fixed `360s` wrapper in `tools/run_catalogue.sh` with per-repo and per-case timeouts plus process-group cleanup and verified Docker container removal (`docker ps` check on exit), where the outer timeout is derived from the sum of per-repo budgets.
- [ ] Update [`SOFTWARE-CATALOGUE.md`](SOFTWARE-CATALOGUE.md) and [`PERF-PLAN-P13.md`](PERF-PLAN-P13.md) so command names, `parity_suite.sh` status, and `T1`–`T5` descriptions match the actual scripts.

### P1 — Wire existing guest suites and prove AOT execution

- [ ] Wire `test_p1_isa`, `test_p3` FP/SIMD, `test_p4` threads/signals, `test_p5` dynamic `PT_INTERP`, `test_p6` permissions/quiescence, `test_h1` SMC, and `test_h4` C++17 into `tests/parity_suite.sh` across all ten repos (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, and `rvrt`, matching `loongarch64rt`, `ppc64rt`, `mips64rt`, and `sparc64rt`).
- [ ] Keep `rvrt`'s existing host unit linkages (`test-image-expectation`, `test-image-guest`, `test-loader`, `test-linux-signal-suspend`, `test-linux-trap-signal`, `test-signal-exec`) **and** add `rvrt` RV64 + RV32 guest parity (`--interp`, `--dbt`, `--difftest`) to `rvrt/tests/parity_suite.sh`.
- [ ] Upgrade the AOT check in every repo:
  1. Emit the `.aot` cache file on a cold run, reload it in a fresh process, and assert both identical output **and** a runtime counter/diagnostic proving `dbt_blocks_translated == 0` (the cached AOT code actually ran instead of falling back to JIT).
  2. Verify AOT relocation at a changed PIE/DSO load bias and verify cache rejection/invalidation when the underlying ELF file is modified or truncated.

### P2 — Close the holes in `guest-payload` and run it in CI

- [ ] Pin a versioned sysroot package manifest per ABI, fail closed on any missing required tool (`skip > 0` fails the run unless an item is explicitly marked architecture-excluded such as LuaJIT on `sparc32`/`sparc64`/`loongarch64`/`riscv32`), and wire `guest-payload` into `make catalogue-qualify` under `--dbt`.
- [ ] Add the documented cases currently absent from `tools/run_catalogue.sh`:
  - **T1**: `dash` and `bash` traps/subshells, `tar` + `gzip` archive round-trip, `sha256sum -c`, `diff -u` exit codes (`0` identical, `1` different), `#!` shebang script execution, `/proc/self/exe` + `/proc/self/maps` inspection.
  - **T2**: `gzip` and `bzip2` round-trips on a >256 KiB payload at an unaligned offset, `openssl dgst -sha256` + `pkeyutl` sign/verify, SQLite transaction `ROLLBACK` + multi-table join.
  - **T3**: LuaJIT asserting both `jit.status() == true` and at least one compiled machine-code trace (`TRACE 1 mcode`), plus Python `threading` + `ctypes`.
  - **T4**: `git init -b master` (fixed in `tools/run_catalogue.sh`), `as` + `ld` assembling and linking a `.s` file, `objdump -d`, `make -j2` jobserver build, `g++ -std=c++17 -pthread` with `std::thread`, and running the guest-compiled `selfhost.elf` and `selfhost_cxx.elf` under both `--interp` and `--dbt`.
- [ ] Add negative loader/syscall checks: `ENOEXEC` on a truncated ELF, `ELIBBAD` / `ENOENT` on a missing `PT_INTERP`, and `EFAULT` / `ENOSYS` return-value parity.

### P3 — Translator-specific edge cases the catalogues miss

- [ ] **Signal frames & P12/P13 cached-register coherence**:
  - Deliver both synchronous traps (`SIGSEGV`, `SIGFPE`) and asynchronous signals (`SIGUSR1`, `SIGALRM`) mid-block while guest GPRs (`x20..x28`), scalar FPRs (`d8..d15`), or XMM registers (`v16..v23`) are live in host registers. Verify the handler reads the exact live values from `ucontext_t`, modifies both a cached GPR and a cached FPR in `ucontext_t`, and `rt_sigreturn` resumes execution with the modified register state intact.
  - Test `sigaltstack`, nested signal handlers, `SA_RESTART` vs `EINTR`, remaining-time writeback on interrupted `nanosleep`/`ppoll`, signal delivery and `sigreturn` targeting a MIPS/SPARC branch delay slot or annulled slot, and SPARC signal delivery during a `SAVE` window overflow with pending `FLUSHW`.
- [ ] **6-step `tgkill` Soft-TLB shootdown & quiescence**:
  - **Non-SMC TLB shootdown**: Thread A loops reading/writing a mapped data page (holding a hot Soft-TLB entry) while Thread B calls `mprotect(..., PROT_READ)`, `munmap`, or `mremap` on that page; verify Thread A traps immediately after the syscall returns and never writes through a stale TLB entry.
  - **SMC quiescence**: Thread A executes a hot translated loop while Thread B overwrites or `mprotect`s that code page; verify all 6 quiescence steps complete without deadlock even when a third thread is parked in blocking I/O or `futex` or exiting.
- [ ] **Provider A & Provider B COW, `fork`, and `ftruncate` races**:
  - In-place non-relocating `MAP_PRIVATE` COW across `fork()` where both parent and child hold hot Soft-TLB entries and translated blocks on the same page, then independently mutate it.
  - `MAP_PRIVATE` and `MAP_SHARED` file mappings with `ftruncate` shrinking and regrowing EOF, verifying partial-page zeroing, `SIGBUS` past EOF, and code-version invalidation.
- [ ] **Darwin 16 KiB host granule vs 4 KiB / 8 KiB guest sub-pages**:
  - Map four adjacent 4 KiB guest pages inside one 16 KiB Darwin host page with distinct permissions (`RW`, `RX`, `RO`, `PROT_NONE`), verify Soft-TLB sub-page permission enforcement on reads/writes/executes, test unaligned loads/stores straddling two 4 KiB sub-pages, and test `MADV_DONTNEED` / `brk` at 4 KiB granularity while `AT_PAGESZ` reports `4096` (`8192` on `sparc64rt`).
- [ ] **Address-space boundary invariants**:
  - **Class A (`vm32`)**: `mmap` refusal at address `0`, access to the final 4 KiB page of the 4 GiB window (`0xffffe000`), and 32-bit effective address wrap (`0xffffffff + 2 -> 0x00000001`) before adding `xG` (`x20`).
  - **Class B (`vm64`)**: mappings and pointer arithmetic above 4 GiB (`> 0x1_0000_0000`), plus MIPS64 `SXTW` 32-bit canonical sign-extension invariant across `0x7fffffff` / `0x80000000`.
- [ ] **Atomics with stolen reservations**:
  - `ldrex`/`strex`, `ll`/`sc`, `lwarx`/`stwcx.`, `ldarx`/`stdcx.`, and `lr`/`sc` interrupted between load-linked and store-conditional by (a) a signal handler and (b) a second thread writing the same cache line, verifying the store-conditional fails cleanly.
- [ ] **FP bit-exactness & ISA extension checksums**:
  - Per-ISA rounding modes (`RN`, `RZ`, `RP`, `RM`), NaN payload propagation, sticky exception flags, per-thread `fcsr`/`fpscr`/`mxcsr`/`fsr`, MIPS Legacy vs 2008 NaN, RISC-V NaN-boxing, Thumb interworking, SPARC register windows + `FLUSHW`, PPC64 ELFv2 `r12`/`r2` TOC + `sc` vs `scv 0`, PPC32 e500v2 SPE `evr` upper halves, x86 80-bit x87, LA64 LSX/LASX, and SPARC64 VIS + quad FP.
- [ ] **Dynamic linker, vDSO & multi-process lifecycle**:
  - `dlopen`/`dlsym`/`dlclose` of a TLS-bearing DSO, glibc `IFUNC`, `LD_PRELOAD`, `$ORIGIN`, `PT_GNU_RELRO`, vDSO `clock_gettime` vs raw syscall, `AT_PHDR`/`AT_HWCAP`/`AT_PAGESZ`/`AT_RANDOM`, guest `uname`, `fork` of a multithreaded parent, `CLONE_CHILD_CLEARTID`, robust mutexes, `SCM_RIGHTS` fd passing, `epoll` `EPOLLET`, and `getdents64` `lseek` cookie round-trip.
- [ ] **Architectural SMC rules**:
  - Verify flush-then-execute (`cacheflush`, `synci`, `dcbst`+`icbi`+`isync`, `flush`/`iflush`, `ibar`, `fence.i` / `riscv_flush_icache`, and coherent stores on `i686`) plus write-gate invalidation when a translated page is written via `memcpy` or `read()`.

### P4 — Land the grind in Tier M / N / W

- [ ] Vendor curated QEMU `tests/tcg/multiarch` (plus per-arch `tests/tcg/<arch>` delay-slot, window, Thumb, and SPE tests and `.ref` files) into `tests/tcg/` and wire them into `make catalogue-qualify` (Tier M).
- [ ] Add `make catalogue-grind-nightly` (Tier N):
  - `stress-ng` with `--verify --metrics-brief --yaml` against the per-backend stressor allowlists (5–10 s per stressor, asserting `bogo_ops > 0`).
  - `gcc.c-torture/execute` compiled with `-ffp-contract=off` at `-O0` and `-O2` (same-binary differential: `qemu-<arch>` vs `--interp` vs `--dbt`).
  - Host `testfloat_gen` piped into guest `testfloat_ver`, compiler-rt builtin ABI helpers, `libc-test`, LTP syscall subset, and `lmbench` completion checks.
  - Nightly subsets of CPython, LuaJIT (with trace-compilation check), SQLite `testfixture` + `speedtest1`, and OpenSSL `make test`.
- [ ] Add `make catalogue-grind-weekly` (Tier W):
  - Fixed-seed Csmith and Yarpgen soak with automatic checksum comparison and artifact retention on failure.
  - Upstream Git, coreutils, gawk, and BusyBox `make check`, plus a guest self-rebuild of BusyBox or musl.
- [ ] Keep `bench_suite` as the fast Tier S CRC smoke, and gate 3-stage guest GCC bootstrap as an explicit release qualification target.
