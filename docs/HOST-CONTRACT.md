# `rt-series` Unified Host Contract (`A32H_ABI 1.0/1.1` & `HL_MEMORY_POLICY_RVRT`)

Status: Specification v1.1 (2026-10-23; distinguishes implemented v1.0 baseline from Wave 1 v1.1 migrations)  
Owner: Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.  
Shared header: [`include/a32host.h`](../include/a32host.h)  
Companion references: [`../a32rt/docs/HOST-CONTRACT.md`](../../a32rt/docs/HOST-CONTRACT.md), [`../rvrt/docs/HOST-CONTRACT.md`](../../rvrt/docs/HOST-CONTRACT.md)

---

## 1. Purpose and Scope

Every translator in `rt-series` builds as a standalone, zero-dependency, static-PIE `aarch64-unknown-linux-musl` executable (`ET_DYN`, `DF_1_PIE`, no `PT_INTERP`, zero `DT_NEEDED`). Each runtime executes on two supported host substrates without recompilation:

1. **Native AArch64 Linux** (kernel >= 5.4 with 4 KiB page size, including `limactl` `default` / `lima-aarch64` VMs, cloud Graviton4/AmpereOne servers, and `binfmt_misc`).
2. **`hyper-linux` (`hl`) on macOS Apple Silicon** (Hypervisor.framework EL0/EL1 microVM with 4 KiB guest stage-1/stage-2 page tables in `src/guest.c:60` and direct Darwin/APFS VFS and syscall brokering in `src/vfs.c` and `src/syscall.c`).

No `rt-series` translator may `#include` headers from `hyper-linux` or link against any host library. All host coordination occurs at runtime through:
- Standard Linux `auxv` (`AT_EXECFD`, `AT_PAGESZ`),
- Environment variables (`<RT>_WINDOW`, `<RT>_SYSROOT` / `<RT>_ROOTFS`, `<RT>_CACHE`, `<RT>_ENGINE`, `<RT>_HOST`),
- CLI flags (`--window`, `--sysroot` / `--rootfs`, `--cache` / `--cache-dir`, `--engine`, `--execfn`, `--image-fd`, `--`),
- Optional `/dev/a32host` capability handshake (`A32H_ABI 1.0` / `1.1`, for Class-A 32-bit 4 GiB-window translators), and
- Class-B `HL_MEMORY_POLICY_RVRT` + separate `--cache-authority`, `--file-identity`, and `--family-authority` policies + family broker descriptors (for Class-B full-address-space translators and `rvrt`).

---

## 2. Two Runtime Classes & Three-Layer Page-Size Contract

| Class | Runtimes | Guest Ptr / Reg Width | Address Space Strategy | Host Handshake & Memory Policy |
|---|---|---|---|---|
| **Class A (`rt32`)** | `a32rt` (`EM_ARM`), `i686rt` (`EM_386`), `mips32rt` (`EM_MIPS` O32), `ppc32rt` (`EM_PPC`), `sparc32rt` (`EM_SPARC` V8) | 32-bit ptrs | Contiguous 4 GiB window `[G, G + 4 GiB)` in host VA (`G = 0` or `G = 0x1_0000_0000` under `hl`); guest address = `[x20, wAddr, uxtw]` | `/dev/a32host` (`A32H_GET_INFO = 0x81006101UL`), `window_hint = 0x100000000ULL`, CoW fork snapshot when `has_host_info` |
| **Class B (`rt64` + `rvrt`)** | `rvrt` (`EM_RISCV` RV64GC & RV32GC), `loongarch64rt` (`EM_LOONGARCH`), `ppc64rt` (`EM_PPC64`), `mips64rt` (`EM_MIPS` N64/N32), `sparc64rt` (`EM_SPARCV9`) | 64-bit (32-bit ptrs in RV32GC & MIPS N32) | Checked sparse 4 KiB software radix page table (`rv_space`) decoupled from translator VA and host GPA; family shared backing (`.<rt>-family-<pid>-<seq>`) | `HL_MEMORY_POLICY_RVRT`, 1 GiB `rvrt_shared` GPA arena, SHA-256 runtime digest, separate `--cache-authority`, `--file-identity`, `--family-authority` |

*(Note: Apple `RosettaLinux` handles `ELFCLASS64` `EM_X86_64` via `hl`'s dedicated TTBR1 `kbuf` + high-VA alias path and is never routed through `rt-series` translators.)*

### 2.1 Three-Layer Page-Size Contract (`4 KiB` Guest ABI vs `16 KiB` Darwin Backing vs `64 KiB` ELF Alignment)
1. **Guest ABI Page Size (`AT_PAGESZ = 4096`, except `sparc64rt` with `AT_PAGESZ = 8192`)**: Every Class-A and Class-B translator except `sparc64rt` reports `AT_PAGESZ = 4096` (4 KiB) in the guest auxiliary vector; `sparc64rt` (Class-B SPARC V9, per `SPEC.md` D11) reports `AT_PAGESZ = 8192` (8 KiB) with 8 KiB guest `mmap`/`mprotect`/`munmap` alignment and paired 4 KiB Soft-TLB entries. Syscall-specific alignment, validation, and rounding rules match Linux (`rvrt/src/linux/memory.c:212`):
   - `mmap` / `mmap2`: non-zero `addr` with `MAP_FIXED` / `MAP_FIXED_NOREPLACE` and `addr % 4096 != 0` returns **`-EINVAL`**; `offset % 4096 != 0` returns **`-EINVAL`**; `len == 0` returns **`-EINVAL`**; positive `len` rounds up to a 4 KiB page multiple for the mapped VMA extent.
   - `mprotect` / `munmap`: `addr % 4096 != 0` returns **`-EINVAL`**; `munmap` with `len == 0` returns **`-EINVAL`** while `mprotect` with `len == 0` succeeds as a no-op; positive `len` rounds up to 4 KiB.
   - `mremap`: `old_address % 4096 != 0` (or `new_address % 4096 != 0` under `MREMAP_FIXED`) returns **`-EINVAL`**; `new_size == 0` returns **`-EINVAL`**; `old_size` and `new_size` round up to 4 KiB.
   - `brk`: preserves the **exact byte-granular logical program break** (`current_brk`) returned to the guest while mapping and unmapping backing memory at 4 KiB page boundaries (`align_up(brk, 4096)`).
   - On `sparc64rt`, substitute `8192` for `4096` in all four rules above (8 KiB guest `mmap`/`mprotect`/`munmap`/`mremap` alignment, rounding, and `brk` backing).
2. **Translated Page-Table & Permission Enforcement Layer (`4 KiB`)**:
   - **Class B (`rv_space`)**: `src/memory/space.c` maintains software page-table entries at **4 KiB granularity** (`RV_PAGE_SHIFT = 12`), enforcing per-4-KiB-page `PROT_READ`, `PROT_WRITE`, and `PROT_EXEC` permissions in software regardless of the host OS page size.
   - **Class A (`rt32_`)**: Native AArch64 Linux uses 4 KiB hardware pages. Under `hyper-linux`, the primary HVF stage-2 GPA mapping (`src/guest.c:312`) is coarse `RWX`, while **4 KiB per-page `PROT_READ`/`PROT_WRITE`/`PROT_EXEC` permissions (`AP`, `UXN`/`PXN`) and page splitting are enforced in the guest's 4 KiB stage-1 AArch64 page tables** (`src/guest.c:60`).
3. **Darwin 16 KiB Host Backing & 64 KiB ELF Segment Alignment (`ppc64le`)**:
   - Under `hyper-linux`, `hl`'s VMM backs guest physical memory with Darwin 16 KiB allocations while enforcing 4 KiB guest stage-1 permissions (`Class A`) or `rv_space` 4 KiB software permissions (`Class B`). Adjacent 4 KiB guest mappings with distinct permissions (e.g., `PROT_READ|PROT_EXEC` next to `PROT_READ|PROT_WRITE` or `PT_GNU_RELRO` next to `.bss`) must be qualified on both Linux and `hyper-linux`.
   - `ppc64le` ELFv2 binaries linked with `p_align = 0x10000` (64 KiB) load directly onto the 4 KiB (`AT_PAGESZ = 4096`) runtime because `0x10000` is an exact multiple of `0x1000` (`p_vaddr % 4096 == p_offset % 4096`). No 64 KiB `AT_PAGESZ` emulation is claimed unless a separate 64 KiB page profile is explicitly enabled.

---

## 3. CLI, `argv`, & Descriptor Invocation Contract

### 3.1 Implemented Baseline vs. Coordinated Wave 1 Protocol
Currently in the sibling repositories:
- **Class B (`rvrt`)** uses:
  ```text
  rvrt-linux-aarch64 [OPTIONS] -- <TARGET_PATH> <GUEST_ARGV0> [<GUEST_ARGS>...]
  ```
  where `<TARGET_PATH>` is the executable path (or `--image-fd FD` supplies the open descriptor and `--execfn PATH` overrides `AT_EXECFN`), and `<GUEST_ARGV0>` is the guest's `argv[0]`.
- **Class A (`a32rt`, `i686rt`) and `hyper-linux` (`src/a32.c:323`, `src/i686.c`)** currently emit:
  ```text
  <rt> [OPTIONS] -- <GUEST_ARGV0> [<GUEST_ARGS>...]
  ```
  without a separate `<TARGET_PATH>` token after `--`! Under `hyper-linux`, `hl` passes the target file via `AT_EXECFD` in the translator's `auxv` (or `<GUEST_ARGV0>` is opened when `AT_EXECFD` is absent).

**Coordinated Wave 1 Rules (Fixing `a32rt` D18 and `i686rt` D23 — Consumers Land Before Producer)**:
1. **Consumer-First Migration Order**: Because current `a32rt/src/main.c:123` and `i686rt/src/main.c:77` reject unknown CLI options, **consumer CLI parser updates (`L-A32-2` in `a32rt/src/main.c` and `L-I686-3` in `i686rt/src/main.c`) MUST land before `hyper-linux` (`L-HL-1` in `src/a32.c`, `src/i686.c`) begins emitting `--execfn`**!
   - When `--execfn <PATH>` is provided, `exec_path = <PATH>` and every token after `--` (`argv[i..]`) is passed verbatim as `guest_argv[0..]` (preserving custom `argv[0]` even for zero additional args).
   - When `--execfn` is NOT provided, `argv[i]` after `--` serves as both `exec_path` and `guest_argv[0]` (preserving backward compatibility with `<rt> -- ./binary arg1`).
2. **Valid `AT_EXECFD == 0` Detection & Descriptor Hygiene**:
   - Because file descriptor `0` is a valid open descriptor when stdin was closed before `execve`, runtimes MUST detect `AT_EXECFD` presence via:
     ```c
     errno = 0;
     unsigned long aux_execfd = getauxval(AT_EXECFD);
     int exec_fd = (errno == 0) ? (int)aux_execfd : -1;
     ```
     (or by scanning the raw `auxv` array on stack entry for an `AT_EXECFD` key), and NEVER treat `getauxval(AT_EXECFD) == 0` as "absent" without checking `errno` / `auxv` key presence!
   - Both `a32rt` (`L-A32-2`) and `i686rt` (`L-I686-3`) must consume `exec_fd` (or `--image-fd FD`) to load the main ELF image and `close(exec_fd)` after mapping segments. Closing the loader-private `exec_fd` leaves `0, 1, 2` **and any ordinary caller-inherited file descriptors (`>= 3`)** untouched for the guest.

### 3.2 Standard CLI Flags and Environment Variables
Each translator uses its upper-case prefix `<RT>` (without a trailing underscore: `A32RT`, `I686RT`, `RVRT`, `MIPS32RT`, `PPC32RT`, `SPARC32RT`, `LOONGARCH64RT`, `PPC64RT`, `MIPS64RT`, `SPARC64RT`):

| CLI Flag | Environment Variable | Applies To | Current Status vs. Wave 1 Alias Assignment | Semantics |
|---|---|---|---|---|
| `--window <hex>` | `<RT>_WINDOW` | Class A | Implemented in `a32rt` & `i686rt` | Override 4 GiB guest window base `G`. Unset returns `UINT64_MAX` sentinel so probe order runs. Explicit CLI flag overrides env. |
| `--sysroot <dir>` / `--rootfs <dir>` | `<RT>_SYSROOT` / `<RT>_ROOTFS` | Class A & B | `a32rt` (`src/main.c:142`) & `rvrt` implement `--sysroot`; `i686rt` implements `--rootfs` / `I686RT_ROOTFS`. Alias both spellings in `L-A32-2`, `L-I686-3`, `L-RV64-1c` | Guest sysroot prefix for `PT_INTERP` dynamic linker and absolute guest paths (path translation only, not sandboxing). |
| `--cache <dir>` / `--cache-dir <dir>` | `<RT>_CACHE` / `<RT>_CACHE_DIR` | Class A & B | `a32rt` implements `--cache` / `A32RT_CACHE`; `rvrt` implements `--cache-dir` / `RVRT_CACHE_DIR`. Alias both spellings in Wave 1 | Persistent AOT cache directory. |
| `--engine <interp\|dbt\|jit>` | `<RT>_ENGINE` | Dual-engine | Implemented in `i686rt` (`--engine` / `I686RT_ENGINE`) & `rvrt` (`--engine` / `RVRT_ENGINE`) | Select execution engine (`interp` or `dbt`/`jit`). Explicit CLI flag overrides env. |
| `--execfn <path>` | `<RT>_EXECFN` | Class A & B | Implemented in `rvrt`; added to `a32rt` (`L-A32-2`) & `i686rt` (`L-I686-3`) before `L-HL-1` | Explicit guest executable path for `AT_EXECFN` and `/proc/self/exe` decoupled from `guest_argv[0]`. |
| `--image-fd <fd>` | — | Class A & B | Implemented in `rvrt`; added to `a32rt` (`L-A32-2`) & `i686rt` (`L-I686-3`) in Wave 1 | Open file descriptor (`fd >= 0`) for the guest main ELF image. |
| `--stats` | `<RT>_STATS=1` | Class A & B | `rvrt` implements `--stats`; `i686rt` implements `I686RT_STATS=1` env var (CLI `--stats` added in `L-I686-3`) | Emit execution/dispatch counters to stderr on process exit. |
| `--gdb <port>` | `<RT>_GDB` | Class A & B | `a32rt` & `i686rt` implement `--gdb <port>` and `<RT>_GDB` | Wait for GDB Remote Serial Protocol connection on `127.0.0.1:<port>`. |
| `--no-host` | `<RT>_HOST=none` | Class A | `a32rt` (`src/host.c:27`) & `i686rt` implement `<RT>_HOST=none` env var; CLI `--no-host` flag added in `L-A32-2` & `L-I686-3` | Opt out of `/dev/a32host` probe even when `/dev/a32host` is present. (`--` is strictly the option terminator, never an alias for `HOST=none`.) |

---

## 4. Class-A Host Handshake: `/dev/a32host` (`A32H_ABI 1.0 / 1.1`)

### 4.1 Wire Layout & Versioning Rule (`include/a32host.h`)
All Class-A 32-bit translators vendor [`include/a32host.h`](../include/a32host.h):
- Device path: `/dev/a32host` (character device `major 10, minor 240` inside `hyper-linux`).
- Request ioctl: `A32H_GET_INFO = 0x81006101UL` (`_IOR('a', 0x01, struct a32h_info)`, 256 bytes).
- **Versioning & Header Sync Rule**:
  - `A32H_ABI_MAJOR` (`1U`) and `A32H_ABI_MINOR` (`0U`) define the minimum accepted wire-layout version; `A32H_ABI_MINOR_TSO` (`1U`) identifies the minor revision that defines `A32H_CAP_HW_TSO` (bit 9), `A32H_CAP_FIXADE` (bit 10), and `A32H_CAP_SOFT_TLB_256M` (bit 11).
  - Consumers require `info.abi_major == 1` (accepting any `info.abi_minor >= 0`) and test individual capability bits in `info.caps`.
  - Because `a32rt/Makefile`'s `check-headers` target enforces byte-for-byte equality between `../a32rt/include/a32host.h` and `../hyper-linux/src/a32host.h`, Wave 1 must update `../a32rt/include/a32host.h` (`L-A32-3`), **`../i686rt/include/a32host.h`** (`L-I686-3`), and `../hyper-linux/src/a32host.h` (`L-HL-1`) in lockstep from `rt-series/include/a32host.h`.
- **Capabilities (`a32h_info_t.caps`)**:
  - `A32H_CAP_PAGE4K` (`1ULL << 0`): Host `mmap`/`mprotect` granularity is 4 KiB.
  - `A32H_CAP_WX_ENFORCED` (`1ULL << 1`): Host enforces W^X.
  - `A32H_CAP_ICACHE_TRAP_IALLU` (`1ULL << 2`): Host traps `IC IVAU` at EL2 and invalidates the full guest I-cache in one VM exit.
  - `A32H_CAP_LOW4G_FREE` (`1ULL << 3`): `[mmap_min_addr, 4 GiB)` is free (`G = 0` identity mode). Not set under `hl` because `hl` owns `< 0x400000`.
  - `A32H_CAP_DIROFF32` (`1ULL << 4`): Directory cookies fit in 31 bits without remapping.
  - `A32H_CAP_AOT_SOCKET` (`1ULL << 5`): `aot_socket` path is active.
  - `A32H_CAP_COMPAT_IOCTL` (`1ULL << 6`), `A32H_CAP_ROBUST32` (`1ULL << 7`), `A32H_CAP_SET_PROC` (`1ULL << 8`).
  - `A32H_CAP_FIXADE` (`1ULL << 10`, ABI 1.1): Host emulates MIPS unaligned load/store fixup (`TIF_FIXADE` semantics).
  - `A32H_CAP_SOFT_TLB_256M` (`1ULL << 11`, ABI 1.1): Host supports the 256 MiB Regime A2 Soft-TLB over the 4 GiB window.
  - `A32H_CAP_HW_TSO` (`1ULL << 9`, ABI 1.1): Host guarantees hardware TSO (`ACTLR_EL1` / Apple Silicon TSO mode) across **all** vCPUs of the process (initial vCPU in `src/hl.c`, thread vCPUs in `src/thread.c`, and fork/exec vCPUs in `src/fork_ipc.c`). **Qualification Requirement**: Because store-buffering (`SB`) both-zero outcomes are *permitted* under TSO, `SB` cannot distinguish TSO from weak ordering! Advertising `A32H_CAP_HW_TSO` requires: (1) explicit hardware TSO configuration and register readback confirmation on initial, thread (`src/thread.c`), fork (`src/fork_ipc.c`), and exec vCPU creation paths, plus (2) discriminating **Message-Passing (`MP`: `data = 1; flag = 1` vs `r0 = flag; r1 = data`, where `r0 == 1 && r1 == 0` is strictly forbidden under TSO)** and **Load-Buffering (`LB`)** litmus tests across initial, `pthread_create`, and `fork` workers. Until both conditions are met, `hyper-linux` MUST leave `A32H_CAP_HW_TSO` clear (`0`).

### 4.2 Window Base `G` Resolution Order (Mandatory Across All Class-A Translators)
1. Explicit `--window <hex>` CLI argument (fail-hard if reservation at `G` fails).
2. Explicit `<RT>_WINDOW` environment variable (fail-hard if reservation at `G` fails; if unset/empty, pass `UINT64_MAX` sentinel).
3. `/dev/a32host` `info.window_hint` (when `has_host_info && info.window_hint != 0`, e.g., `0x100000000ULL` under `hl`).
4. Try `G = 0` (`[0x10000, 0x100000000)`).
5. Scan 4 GiB-aligned bases `0x100000000ULL .. 0xF00000000ULL`.

### 4.3 Required `hyper-linux` `/dev/a32host` & `mremap` Fixes (Defects D185, D187, D190, D191, `a32rt` D19, `i686rt` C8)
1. **D185 (No double-close)**: `a32host_destroy()` in `hyper-linux/src/device.c` must set `st->alias_fd = -1` (or own a `dup()`d fd separate from `desc->host_fd`) so closing a `/dev/a32host` guest descriptor never closes the underlying host fd twice.
2. **D187 (Accurate `fstat`)**: `a32host_fd_ops` must implement `.fstat` reporting `S_IFCHR | 0666` and `st_rdev = makedev(10, 240)` matching `stat("/dev/a32host")`.
3. **D190 & `i686rt` C8 (`<RT>_WINDOW` environment ordering)**: `hyper-linux` must inject `<RT>_WINDOW=<hint>` into `guest_env` **before** `hl_build_initial_stack()` on initial launch (fixing `C8` where `guest_env` was materialized from `environ` before `finalize`'s `setenv`) **and** merge it into the child environment on `sys_execve()`, and `a32host_ioctl(A32H_GET_INFO)` must honor `HL_<RT>_WINDOW` / `<RT>_WINDOW` if set.
4. **D191 (Restrict `A32H_GET_INFO` to `/dev/a32host` fds)**: Remove the duplicate `case A32H_GET_INFO:` from the generic fallback switch in `hyper-linux/src/syscall_io.c` so `ioctl(fd, A32H_GET_INFO, &info)` on non-`/dev/a32host` fds returns `-ENOTTY`.
5. **File-backed `mremap` (`hyper-linux/src/syscall.c:3204`, required by `a32rt` D19)**: Extend `hl_sys_mremap` so growing or moving (`MREMAP_MAYMOVE` / `MREMAP_FIXED`) a file-backed `MAP_SHARED` VMA preserves its backing host file descriptor and offset rather than failing with `-ENOSYS` or converting to private anonymous memory.

---

## 5. Class-B Host Contract (`HL_MEMORY_POLICY_RVRT` & `rvrt` Substrate)

All Class-B translators (`rvrt` for RV64GC & RV32GC, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`) adhere to the complete contract defined in [`../rvrt/docs/HOST-CONTRACT.md`](../../rvrt/docs/HOST-CONTRACT.md):

1. **Three Separate Authority Policies (Never Conflated)**:
   - **`--cache-authority=auto|hyper-linux-apfs-acl-v1`**: Controls persistent AOT cache admission. `auto` certifies local Linux `ext4`/`tmpfs` ACL absence only and declines APFS; `hyper-linux-apfs-acl-v1` requires the qualified `hyper-linux` APFS ACL xattr facade (`system.posix_acl_access` synthesis). It does **not** authorize `RLIMIT_FSIZE=0` family backing!
   - **`--file-identity=auto|hyper-linux-apfs-v1`**: Controls read-only file-backed futex identity (`st_dev`/`st_ino` stability). `auto` accepts verified Linux `tmpfs`; `hyper-linux-apfs-v1` is required on `hyper-linux` APFS.
   - **`--family-authority=auto|hyper-linux-apfs-acl-v1`**: Controls bounded hard-zero (`RLIMIT_FSIZE=0`) SysV/inode-locator family backing (`make test-family-authority-cli-hl`). Separate from `--cache-authority`.
2. **Descriptor Ownership, Validated Images, & Internal `--resume-v7`**:
   - Per [`../rvrt/docs/HOST-CONTRACT.md:338`](../../rvrt/docs/HOST-CONTRACT.md) and `rvrt/src/runtime/initial_image.c:36`, `--image-fd FD` may be **any nonnegative file descriptor (`FD >= 0`, including descriptor `0` when stdin is closed)** referencing a regular ELF file, provided `FD != runtime_fd`. The `>= 3` restriction applies strictly to the borrowed **`runtime_fd`** (`runtime_fd < 3` is rejected), and ELF loading uses position-independent `pread()` so it does not depend on the descriptor's current file offset. `rv_initial_image_prepare` consumes `owned_image_fd` except when `fd == runtime_fd`, which returns `EINVAL` without closing the borrowed `runtime_fd`.
   - Dynamic `PT_INTERP` loading pins both the main executable and interpreter descriptors and binds both file identities into dynamic AOT cache keys.
   - `--resume-v7` is a **private internal same-PID `execve` continuation vector**, NOT a public CLI option, and does not expose source-enabled family admission from the ordinary CLI.
3. **Shared Arena & Runtime Identity**:
   - Under `HL_MEMORY_POLICY_RVRT`, `hyper-linux` reserves the disjoint 1 GiB shared GPA arena `[0x80000000, 0xC0000000)` (`rvrt_shared.c`), tracks the SHA-256 digest of the translator binary across `fork`/`execve`, and provides the SCM/pipe/FIFO/dir/pidfd/signal/fsize broker services.
   - For `sparc64rt` (Class-B TSO guest), software memory ordering is the default; hardware TSO elision requires an explicit `--hw-tso` flag passed by `hyper-linux` only when all worker vCPUs have hardware TSO enabled.
4. **Explicit Exclusions Preserved Across All Class-B Runtimes**:
   - Robust and PI futexes (`set_robust_list`, `FUTEX_LOCK_PI`), `rseq`, and `ptrace` are excluded (deliberately rejected with `-ENOSYS` / `-EOPNOTSUPP`).
   - Guest threads execute under the deterministic FIFO turn scheduler (`--quantum N`, default 64), not parallel guest CPU execution.
   - Shared regular-file mappings (`MAP_SHARED` on regular files), external/native shared writers, and `O_PATH` preservation on current `hyper-linux` VFS paths are not claimed.
   - The normal `hyper-linux` `HL_MEMORY_POLICY_RVRT` native process-fork gate remains closed (`ENOSYS`) until all Round-17 broker defects (`D201`, `D211–D213`, `D249–D258`) and host lock/SCM continuity tests pass.

---

## 6. `hyper-linux` Unified Translator Dispatch Table (`src/translator.h`)

To partition architectures that share `e_machine` (specifically `EM_MIPS` across O32, N32, and N64, and `EM_RISCV` across RV32GC and RV64GC) and reject unsupported ABI variants, `hl_translator_desc_t` in `hyper-linux/src/translator.h` MUST match on `(elf_class, elf_data, e_machine, e_flags_mask, e_flags_val)` plus an optional header predicate `match_ehdr`:

```c
typedef enum {
    HL_TRANSLATOR_POLICY_CLASS_A = 1, /* 4 GiB window + /dev/a32host */
    HL_TRANSLATOR_POLICY_CLASS_B = 2, /* HL_MEMORY_POLICY_RVRT */
} hl_translator_policy_t;

typedef struct {
    const char            *name;          /* e.g. "mips32rt" */
    uint8_t                elf_class;     /* ELFCLASS32 or ELFCLASS64 */
    uint8_t                elf_data;      /* ELFDATA2LSB, ELFDATA2MSB, or 0 (either) */
    uint16_t               e_machine;     /* EM_* */
    uint32_t               e_flags_mask;  /* bits inspected in ehdr.e_flags */
    uint32_t               e_flags_val;   /* required value of (e_flags & e_flags_mask) */
    bool                 (*match_ehdr)(const uint8_t ehdr[64]); /* optional stricter check */
    hl_translator_policy_t policy;        /* CLASS_A or CLASS_B */
    const char            *cli_flag;      /* e.g. "--mips32rt" */
    const char            *env_var;       /* e.g. "HL_MIPS32RT" */
    const char            *default_rel;   /* e.g. "../mips32rt/_build/mips32rt" */
} hl_translator_desc_t;
```

| ELF Class | `e_machine` | `EI_DATA` | `e_flags` Mask & Admission Rule | Translator | CLI Flag | Env Var | Default Sibling Path | Policy |
|---|---|---|---|---|---|---|---|---|
| `ELFCLASS64` | `EM_AARCH64 (183)` | `LSB (1)` | — | *(native)* | — | — | — | Direct HVF EL0 |
| `ELFCLASS64` | `EM_X86_64 (62)` | `LSB (1)` | — | `rosetta` | — | — | `/Library/Apple/.../rosetta` | Rosetta TTBR1 |
| `ELFCLASS32` | `EM_ARM (40)` | `LSB (1)` | `(e_flags & EF_ARM_EABI_MASK) == EF_ARM_EABI_VER5` | `a32rt` | `--a32rt` | `HL_A32RT` | `../a32rt/_build/a32rt` | `CLASS_A` |
| `ELFCLASS32` | `EM_386 (3)` | `LSB (1)` | `e_flags == 0` | `i686rt` | `--i686rt` | `HL_I686RT` | `../i686rt/build/i686rt` | `CLASS_A` |
| `ELFCLASS64` | `EM_RISCV (243)` | `LSB (1)` | `(e_flags & EF_RISCV_FLOAT_ABI) == EF_RISCV_FLOAT_ABI_DOUBLE (0x4)` | `rvrt` | `--rvrt-runtime` | `HL_RVRT` | `../rvrt/_build/rvrt-linux-aarch64` | `CLASS_B` |
| `ELFCLASS32` | `EM_RISCV (243)` | `LSB (1)` | `(e_flags & EF_RISCV_FLOAT_ABI) == EF_RISCV_FLOAT_ABI_DOUBLE (0x4)` | `rvrt` | `--rvrt-runtime` | `HL_RVRT` | `../rvrt/_build/rvrt-linux-aarch64` | `CLASS_B` (RV32GC) |
| `ELFCLASS32` | `EM_MIPS (8)` | `LSB` or `MSB` | `(e_flags & EF_MIPS_ABI2) == 0` AND `(e_flags & EF_MIPS_ABI) in {0, E_MIPS_ABI_O32 (0x1000)}` (reject EABI/O64!) | `mips32rt` | `--mips32rt` | `HL_MIPS32RT` | `../mips32rt/_build/mips32rt` | `CLASS_A` |
| `ELFCLASS32` | `EM_PPC (20)` | `MSB (2)` | Classic or SPE (`.gnu.attributes` tag 4) | `ppc32rt` | `--ppc32rt` | `HL_PPC32RT` | `../ppc32rt/_build/ppc32rt` | `CLASS_A` |
| `ELFCLASS32` | `EM_SPARC (2)` | `MSB (2)` | `e_flags == 0` (**reject `EM_SPARC32PLUS (18)` and `EF_SPARC_32PLUS`!**) | `sparc32rt` | `--sparc32rt` | `HL_SPARC32RT` | `../sparc32rt/_build/sparc32rt` | `CLASS_A` |
| `ELFCLASS64` | `EM_LOONGARCH (258)` | `LSB (1)` | `(e_flags & 0x7) == EF_LOONGARCH_ABI_DOUBLE_FLOAT (0x3)` | `loongarch64rt` | `--loongarch64rt` | `HL_LOONGARCH64RT` | `../loongarch64rt/_build/loongarch64rt` | `CLASS_B` |
| `ELFCLASS64` | `EM_PPC64 (21)` | `LSB (1)` | `(e_flags & EF_PPC64_ABI) == 2` (`EF_PPC64_ABI = 3`, ELFv2) | `ppc64rt` | `--ppc64rt` | `HL_PPC64RT` | `../ppc64rt/_build/ppc64rt` | `CLASS_B` |
| `ELFCLASS32` | `EM_MIPS (8)` | `LSB` or `MSB` | `(e_flags & EF_MIPS_ABI2) == EF_MIPS_ABI2 (0x20)` (N32 ABI) | `mips64rt` | `--mips64rt` | `HL_MIPS64RT` | `../mips64rt/_build/mips64rt` | `CLASS_B` |
| `ELFCLASS64` | `EM_MIPS (8)` | `LSB` or `MSB` | `(e_flags & EF_MIPS_ABI) == 0` (N64 ABI) | `mips64rt` | `--mips64rt` | `HL_MIPS64RT` | `../mips64rt/_build/mips64rt` | `CLASS_B` |
| `ELFCLASS64` | `EM_SPARCV9 (43)` | `MSB (2)` | `(e_flags & EF_SPARCV9_MM) in {TSO (0), PSO (1), RMO (2)}` | `sparc64rt` | `--sparc64rt` | `HL_SPARC64RT` | `../sparc64rt/_build/sparc64rt` | `CLASS_B` |

### 6.1 Single-Open Pinned Preload Rule (Fixing `hyper-linux` Defects D188 & D189)
Both the guest target binary (`AT_EXECFD`) and the translator binary (`<rt>`) MUST be opened and validated **once** before `execve`'s Point of No Return (`guest_reset()`):
1. The target binary is opened with `O_RDONLY | O_CLOEXEC`, `fstat`-pinned (`dev`, `ino`, `size`, `mtime`), header-verified in memory, and that exact open host FD is wrapped via `fd_alloc(FD_REGULAR, pinned_fd)` for `AT_EXECFD` (never re-opened by path in `*_finalize`).
2. The translator binary is loaded via `elf_preload()` + `elf_load_mem()` + `elf_map_segments_mem()` from a single open descriptor (never two separate `fopen()` calls).
