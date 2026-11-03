# `rt-series` Master Defect, Curated-C11 & Subsystem Deep-Dive Checklist (Rounds 1–12 Complete)

**Audit Date:** 2026-11-03 (Rounds 4–12; Rounds 1–3 on 2026-11-02)  
**Process Specification:** [`docs/CONVERGENCE-AUDIT-PROCESS.md`](docs/CONVERGENCE-AUDIT-PROCESS.md) (Parabola Oscillation Model, Step-Size Annealing, and 6-Subsystem Deep-Dive Schedule)  
**Static Auditor ("Hunting"):** `gpt-6-astra` / `muse exec` read-only static audit across 11 concurrent read-only static audit lanes  
**Remediation Engine ("Fixing"):** `muse` (`muse exec --yolo --parallel-tool-calls`)  
**Post-Remediation Verifier ("Review"):** `claude-fable-5-1` (`claude -p --model claude-fable-5-1 --effort high`) & `claude-opus-4-6`  
**Architectural & Convergence Invariants Enforced:**
1. **Standalone Zero-Dependency Repositories (`AGENTS.md` §2.1):** Each `<arch>rt` repository is standalone; **never extract a shared cross-repo `librt32` or `librt64` C library**.
2. **Curated C11 (`AGENTS.md` §2.2):** `-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror`, no VLAs, no banned libc functions (`strcpy`, `strcat`, `sprintf`, `atoi`), `x18` permanently reserved on AArch64, no textual `#include "*.c"` unity includes, and every `.c`/`.h`/`.S` file $\le 900$ lines.
3. **Step-Size Annealing (`docs/CONVERGENCE-AUDIT-PROCESS.md` §2.2):** Narrow orthogonal subsystem deep-dives (Rounds 7–12), minimal surgical diffs, zero `DRY`/`YAGNI`/`CLEAN` cosmetic churn in annealed rounds (Rounds 10–12), and `0` findings permitted when a subsystem has converged.

---

## Part I — Round-12 Checklist: Subsystem Deep-Dive 6 of 6 — Step-Size Annealed (Syscall ABI, Struct/Flag/Errno Marshaling, `/proc/self` Synthesis & Linux/Darwin Backends, `23 / 23` Resolved)

| # | Repository | Class | R12 Items | R12 Commit(s) | R12 Audit Report | R12 Verification Review |
|---:|---|---|---:|---|---|---|
| 1 | `a32rt` | Class A | **3 / 3** (`A32-R12-1..3`) | `c5e5f7e` | [`2026-11-03-defects-r12-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r12-a32rt-astra.md) | [`2026-11-03-defects-r12-a32rt-fable.md`](lode/reviews/2026-11-03-defects-r12-a32rt-fable.md) (`3 / 3 VERIFIED`) |
| 2 | `i686rt` | Class A | **3 / 3** (`I686-R12-3..5`; `R12-1..2` false positive on `aarch64-linux`) | `bfa270a`, `b60f524` | [`2026-11-03-defects-r12-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r12-i686rt-astra.md) | [`2026-11-03-defects-r12-i686rt-fable.md`](lode/reviews/2026-11-03-defects-r12-i686rt-fable.md) (`3 / 3 VERIFIED`) |
| 3 | `mips32rt` | Class A | **2 / 2** (`M32-R12-1..2`) | `d521faf` | [`2026-11-03-defects-r12-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r12-mips32rt-astra.md) | [`2026-11-03-defects-r12-mips32rt-fable.md`](lode/reviews/2026-11-03-defects-r12-mips32rt-fable.md) (`2 / 2 VERIFIED`) |
| 4 | `ppc32rt` | Class A | **2 / 2** (`P32-R12-1..2`) | `04cfaab` | [`2026-11-03-defects-r12-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r12-ppc32rt-astra.md) | [`2026-11-03-defects-r12-ppc32rt-fable.md`](lode/reviews/2026-11-03-defects-r12-ppc32rt-fable.md) (`2 / 2 VERIFIED`) |
| 5 | `sparc32rt` | Class A | **3 / 3** (`S32-R12-1..3`) | `3fb9976`, `130b0b8` | [`2026-11-03-defects-r12-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r12-sparc32rt-astra.md) | [`2026-11-03-defects-r12-sparc32rt-fable.md`](lode/reviews/2026-11-03-defects-r12-sparc32rt-fable.md) (`3 / 3 VERIFIED`) |
| 6 | `rvrt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r12-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r12-rvrt-astra.md) | Converged (`0` defects) |
| 7 | `loongarch64rt` | Class B | **3 / 3** (`LA64-R12-1..3`) | `83baf28` | [`2026-11-03-defects-r12-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r12-loongarch64rt-astra.md) | [`2026-11-03-defects-r12-loongarch64rt-fable.md`](lode/reviews/2026-11-03-defects-r12-loongarch64rt-fable.md) (`3 / 3 VERIFIED`) |
| 8 | `ppc64rt` | Class B | **2 / 2** (`P64-R12-1..2`) | `ec20e87` | [`2026-11-03-defects-r12-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r12-ppc64rt-astra.md) | [`2026-11-03-defects-r12-ppc64rt-fable.md`](lode/reviews/2026-11-03-defects-r12-ppc64rt-fable.md) (`2 / 2 VERIFIED`) |
| 9 | `mips64rt` | Class B | **1 / 1** (`M64-R12-1`) | `a2c9cb1`, `dfaed93` | [`2026-11-03-defects-r12-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r12-mips64rt-astra.md) | [`2026-11-03-defects-r12-mips64rt-fable.md`](lode/reviews/2026-11-03-defects-r12-mips64rt-fable.md) (`1 / 1 VERIFIED`) |
| 10 | `sparc64rt` | Class B | **7 / 7** (`S64-R12-1..7`) | `f00c8c2`, `15c6eca` | [`2026-11-03-defects-r12-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r12-sparc64rt-astra.md) | [`2026-11-03-defects-r12-sparc64rt-fable.md`](lode/reviews/2026-11-03-defects-r12-sparc64rt-fable.md) (`7 / 7 VERIFIED`) |
| 11 | `rt-series` | Harness | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r12-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r12-rt-series-astra.md) | Converged (`0` defects) |

- [x] **A32-R12-1..3 (`c5e5f7e`)**: `a32rt` `fstatat64`/`statx` `AT_EMPTY_PATH` empty-path handling, `pread64`/`pwrite64` negative offset `-EINVAL`, and `/proc/self/stat` comm field escaping.
- [x] **I686-R12-3..5 (`bfa270a`, `b60f524`)**: `i686rt` `execve("/proc/self/exe")` redirect to `ctx->exec_path`, Darwin `rt_host_socketpair`/`rt_host_accept4` `SOCK_CLOEXEC`/`SOCK_NONBLOCK` application, and `/proc` path canonicalization (`//`, `/./`, `/../`) in `canon_proc_leaf`.
- [x] **M32-R12-1..2 (`d521faf`)**: `mips32rt` `F_GETLK64`/`F_SETLK64`/`F_SETLKW64` (`33/34/35`) in `fcntl` (NR 4055) and `/proc/self/{maps,cmdline,stat,auxv}` `O_CLOEXEC` propagation.
- [x] **P32-R12-1..2 (`04cfaab`)**: `ppc32rt` `statx` reserved/spare hole zeroing (`dyn_put_statx` / `dyn_put_stat_fallback`), PowerPC `EDEADLK` (`35 -> 58`) errno translation, and DBT/hostfault `fault_is_store` classification (`P32-R11-6`).
- [x] **S32-R12-1..3 (`3fb9976`, `130b0b8`)**: `sparc32rt` SunOS/SPARC `ENOSYS=90`, `ENAMETOOLONG=63`, `ELOOP=62`, `EOVERFLOW=92` mapping, `TCGETS` (`0x40245408`) BE `struct termios` + `c_cc`/`c_lflag` marshaling, and `/proc/self/{maps,cmdline,stat,auxv}` `O_CLOEXEC` propagation.
- [x] **LA64-R12-1..3 (`83baf28`)**: `loongarch64rt` `readlinkat("/proc/self/fd/N")` synthesis, `ioctl(TIOCGWINSZ)` terminal probe before returning `24x80` fallback, and `ppoll` `sigmask_size != 8` `-EINVAL` validation.
- [x] **P64-R12-1..2 (`ec20e87`)**: `ppc64rt` PowerPC `EDEADLK` (`35 -> 58`) translation in `ppc64_host_errno_to_guest` and non-synthetic `/proc/self/*` host-leak guard (`-ENOENT`).
- [x] **M64-R12-1 (`a2c9cb1`, `dfaed93`)**: `mips64rt` full MIPS errno translation (`EDEADLK=45`, `ENAMETOOLONG=78`, `ENOSYS=89`, `ENOTEMPTY=93`, `ELOOP=90`, `EOVERFLOW=79`, `EOPNOTSUPP=122`, `EDQUOT=1133`) across Linux and Darwin in `src/os/errno_map.h`.
- [x] **S64-R12-1..7 (`f00c8c2`, `15c6eca`)**: `sparc64rt` full SPARC errno table (`35..133`) in `sparc64_errno_from_host`, `O_NDELAY` (`0x0004 | 0x4000`), `MAP_LOCKED=0x100` / `MAP_POPULATE=0x8000` / `MAP_NONBLOCK=0x10000` / `MAP_STACK=0x20000` / `MAP_HUGETLB=0x40000`, `fcntl` `F_GETLK`/`F_SETLK`/`F_SETLKW` (`7/8/9`) + `F_DUPFD_CLOEXEC` (`1030`), `MSG_DONTWAIT`/`MSG_NOSIGNAL`/`MSG_CMSG_CLOEXEC` translation, `/proc/self/*` host-leak guard across `openat`/`fstatat`/`readlinkat`, and Darwin `AT_FDCWD`/`AT_*` translation in `faccessat`/`fchmodat`/`fchownat`/`utimensat`/`renameat2`.

---

## Part II — Round-11 Archive: Subsystem Deep-Dive 5 of 6 — Step-Size Annealed (Signal Multiplexing, Host Fault Recovery, `sigaltstack` & RT Signal Frames, `24 / 24` Resolved — Verified by `claude-fable-5-1` & `claude-opus-4-6`)

| # | Repository | Class | R11 Items | R11 Commit | R11 Audit Report | R11 Verification Review |
|---:|---|---|---:|---|---|---|
| 1 | `a32rt` | Class A | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r11-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r11-a32rt-astra.md) | Converged (`0` defects) |
| 2 | `i686rt` | Class A | **7 / 7** (`I686-R11-1..7`) | `ed8943d` | [`2026-11-03-defects-r11-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r11-i686rt-astra.md) | [`2026-11-03-defects-r11-i686rt-fable.md`](lode/reviews/2026-11-03-defects-r11-i686rt-fable.md) (`7 / 7 VERIFIED`) |
| 3 | `mips32rt` | Class A | **4 / 4** (`M32-R11-1..4`) | `5c8a583` | [`2026-11-03-defects-r11-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r11-mips32rt-astra.md) | [`2026-11-03-defects-r11-mips32rt-fable.md`](lode/reviews/2026-11-03-defects-r11-mips32rt-fable.md) (`4 / 4 VERIFIED`) |
| 4 | `ppc32rt` | Class A | **6 / 6** (`P32-R11-1..6`) | `568286d` | [`2026-11-03-defects-r11-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r11-ppc32rt-astra.md) | [`2026-11-03-defects-r11-ppc32rt-fable.md`](lode/reviews/2026-11-03-defects-r11-ppc32rt-fable.md) (`6 / 6 VERIFIED`) |
| 5 | `sparc32rt` | Class A | **4 / 4** (`S32-R11-1..4`) | `d9ac2db` | [`2026-11-03-defects-r11-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r11-sparc32rt-astra.md) | [`2026-11-03-defects-r11-sparc32rt-fable.md`](lode/reviews/2026-11-03-defects-r11-sparc32rt-fable.md) (`4 / 4 VERIFIED`) |
| 6 | `rvrt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r11-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r11-rvrt-astra.md) | Converged (`0` defects) |
| 7 | `loongarch64rt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r11-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r11-loongarch64rt-astra.md) | Converged (`0` defects) |
| 8 | `ppc64rt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r11-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r11-ppc64rt-astra.md) | Converged (`0` defects) |
| 9 | `mips64rt` | Class B | **1 / 1** (`M64-R11-1`) | `9d47bc3` | [`2026-11-03-defects-r11-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r11-mips64rt-astra.md) | [`2026-11-03-defects-r11-mips64rt-fable.md`](lode/reviews/2026-11-03-defects-r11-mips64rt-fable.md) (`1 / 1 VERIFIED`) |
| 10 | `sparc64rt` | Class B | **1 / 1** (`S64-R11-1`) | `a78b02b` | [`2026-11-03-defects-r11-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r11-sparc64rt-astra.md) | [`2026-11-03-defects-r11-sparc64rt-fable.md`](lode/reviews/2026-11-03-defects-r11-sparc64rt-fable.md) (`1 / 1 VERIFIED`) |
| 11 | `rt-series` | Harness | **1 / 1** (`RTS-R11-1`) | `ea01633` | [`2026-11-03-defects-r11-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r11-rt-series-astra.md) | [`2026-11-03-defects-r11-rt-series-fable.md`](lode/reviews/2026-11-03-defects-r11-rt-series-fable.md) (`1 / 1 VERIFIED`) |

---

## Part III — Round-10 Archive: Subsystem Deep-Dive 4 of 6 — Step-Size Annealed (Threading, `clone`/`fork`/`execve`, `atfork` Locks & Futex / Turn Scheduler, `19 / 19` Resolved — Verified by `claude-fable-5-1` & `claude-opus-4-6`)

| # | Repository | Class | R10 Items | R10 Commit | R10 Audit Report | R10 Verification Review |
|---:|---|---|---:|---|---|---|
| 1 | `a32rt` | Class A | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r10-a32rt-astra.md) | Converged (`0` defects) |
| 2 | `i686rt` | Class A | **4 / 4** (`I686-R10-1..4`) | `3c383a3` | [`2026-11-03-defects-r10-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r10-i686rt-astra.md) | [`2026-11-03-defects-r10-i686rt-fable.md`](lode/reviews/2026-11-03-defects-r10-i686rt-fable.md) (`4 / 4 VERIFIED`) |
| 3 | `mips32rt` | Class A | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r10-mips32rt-astra.md) | Converged (`0` defects) |
| 4 | `ppc32rt` | Class A | **7 / 7** (`P32-R10-1..7`) | `b72db16` | [`2026-11-03-defects-r10-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r10-ppc32rt-astra.md) | [`2026-11-03-defects-r10-ppc32rt-fable.md`](lode/reviews/2026-11-03-defects-r10-ppc32rt-fable.md) (`7 / 7 VERIFIED`) |
| 5 | `sparc32rt` | Class A | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r10-sparc32rt-astra.md) | Converged (`0` defects) |
| 6 | `rvrt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r10-rvrt-astra.md) | Converged (`0` defects) |
| 7 | `loongarch64rt` | Class B | **2 / 2** (`LA64-R10-1..2`) | `4882cbb` | [`2026-11-03-defects-r10-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r10-loongarch64rt-astra.md) | [`2026-11-03-defects-r10-loongarch64rt-fable.md`](lode/reviews/2026-11-03-defects-r10-loongarch64rt-fable.md) (`2 / 2 VERIFIED`) |
| 8 | `ppc64rt` | Class B | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r10-ppc64rt-astra.md) | Converged (`0` defects) |
| 9 | `mips64rt` | Class B | **2 / 2** (`M64-R10-1..2`) | `694e6d8` | [`2026-11-03-defects-r10-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r10-mips64rt-astra.md) | [`2026-11-03-defects-r10-mips64rt-fable.md`](lode/reviews/2026-11-03-defects-r10-mips64rt-fable.md) (`2 / 2 VERIFIED`) |
| 10 | `sparc64rt` | Class B | **4 / 4** (`S64-R10-1..4`) | `bb78b2d` | [`2026-11-03-defects-r10-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r10-sparc64rt-astra.md) | [`2026-11-03-defects-r10-sparc64rt-fable.md`](lode/reviews/2026-11-03-defects-r10-sparc64rt-fable.md) (`4 / 4 VERIFIED`) |
| 11 | `rt-series` | Harness | **0 / 0 (Converged)** | — | [`2026-11-03-defects-r10-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r10-rt-series-astra.md) | Converged (`0` defects) |

---

## Part IV — Round-9 Archive: Subsystem Deep-Dive 3 of 6 (Virtual Memory, Soft-TLB, Checked Guest Copy, `fork()` COW & ELF/Auxv Loader, `96 / 96` Resolved — Verified by `claude-fable-5-1` & `claude-opus-4-6`)

| # | Repository | Class | R9 Items | R9 Primary Commit | R9 Follow-Up | R9 Audit Report | R9 Verification Review |
|---:|---|---|---:|---|---|---|---|
| 1 | `a32rt` | Class A | **15 / 15** (`A32-R9-1..15`) | `746bb65` | `f7bffd6` | [`2026-11-03-defects-r9-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r9-a32rt-astra.md) | [`2026-11-03-defects-r9-a32rt-fable.md`](lode/reviews/2026-11-03-defects-r9-a32rt-fable.md) (`15 / 15 VERIFIED`) |
| 2 | `i686rt` | Class A | **9 / 9** (`I686-R9-1..9`) | `6740a71` | `ca12c59` | [`2026-11-03-defects-r9-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r9-i686rt-astra.md) | [`2026-11-03-defects-r9-i686rt-fable.md`](lode/reviews/2026-11-03-defects-r9-i686rt-fable.md) (`9 / 9 VERIFIED`) |
| 3 | `mips32rt` | Class A | **5 / 5** (`M32-R9-1..5`) | `e95314c` | — | [`2026-11-03-defects-r9-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r9-mips32rt-astra.md) | [`2026-11-03-defects-r9-mips32rt-fable.md`](lode/reviews/2026-11-03-defects-r9-mips32rt-fable.md) (`5 / 5 VERIFIED`) |
| 4 | `ppc32rt` | Class A | **10 / 10** (`P32-R9-1..10`) | `a738212` | `b28f919` | [`2026-11-03-defects-r9-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r9-ppc32rt-astra.md) | [`2026-11-03-defects-r9-ppc32rt-fable.md`](lode/reviews/2026-11-03-defects-r9-ppc32rt-fable.md) (`10 / 10 VERIFIED`) |
| 5 | `sparc32rt` | Class A | **8 / 8** (`S32-R9-1..8`) | `0fdcb4c` | `35fea25` | [`2026-11-03-defects-r9-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r9-sparc32rt-astra.md) | [`2026-11-03-defects-r9-sparc32rt-fable.md`](lode/reviews/2026-11-03-defects-r9-sparc32rt-fable.md) (`8 / 8 VERIFIED`) |
| 6 | `rvrt` | Class B | **2 / 2** (`RV-R9-1..2`) | `f644ddd` | — | [`2026-11-03-defects-r9-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r9-rvrt-astra.md) | [`2026-11-03-defects-r9-rvrt-fable.md`](lode/reviews/2026-11-03-defects-r9-rvrt-fable.md) (`2 / 2 VERIFIED`) |
| 7 | `loongarch64rt` | Class B | **11 / 11** (`LA64-R9-1..11`) | `7ce3b53` | `4882cbb` | [`2026-11-03-defects-r9-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r9-loongarch64rt-astra.md) | [`2026-11-03-defects-r9-loongarch64rt-fable.md`](lode/reviews/2026-11-03-defects-r9-loongarch64rt-fable.md) (`11 / 11 VERIFIED`) |
| 8 | `ppc64rt` | Class B | **13 / 13** (`P64-R9-1..13`) | `0231928` | — | [`2026-11-03-defects-r9-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r9-ppc64rt-astra.md) | [`2026-11-03-defects-r9-ppc64rt-fable.md`](lode/reviews/2026-11-03-defects-r9-ppc64rt-fable.md) (`13 / 13 VERIFIED`) |
| 9 | `mips64rt` | Class B | **7 / 7** (`M64-R9-1..7`) | `1b7808e` | — | [`2026-11-03-defects-r9-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r9-mips64rt-astra.md) | [`2026-11-03-defects-r9-mips64rt-fable.md`](lode/reviews/2026-11-03-defects-r9-mips64rt-fable.md) (`7 / 7 VERIFIED`) |
| 10 | `sparc64rt` | Class B | **8 / 8** (`S64-R9-1..8`) | `3754389` | — | [`2026-11-03-defects-r9-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r9-sparc64rt-astra.md) | [`2026-11-03-defects-r9-sparc64rt-fable.md`](lode/reviews/2026-11-03-defects-r9-sparc64rt-fable.md) (`8 / 8 VERIFIED`) |
| 11 | `rt-series` | Harness | **8 / 8** (`RTS-R9-1..8`) | `fd1fa05` | — | [`2026-11-03-defects-r9-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r9-rt-series-astra.md) | [`2026-11-03-defects-r9-rt-series-fable.md`](lode/reviews/2026-11-03-defects-r9-rt-series-fable.md) (`8 / 8 VERIFIED`) |

---

## Part V — Round-8 Archive: Subsystem Deep-Dive 2 of 6 (AArch64 DBT / JIT Emitters, Code Cache, IBTC/RAS & Dispatcher, `55 / 55` Resolved — Verified by `claude-fable-5-1` & `claude-opus-4-6`)

### 0.1 Round 8 Audit Matrix (`55 / 55` Resolved)

Following complete remediation, verification review (`claude-fable-5-1` / `claude-opus-4-6`), and `muse` post-review follow-up across Rounds 1–7 (`1,016` per-repo items + `49` clusters = `1,065` checkboxes resolved), Round 8 executed **Subsystem Deep-Dive 2 of 6: AArch64 DBT / JIT Emitters, Code Cache, IBTC/RAS, Soft-TLB Inline Sequence & Dispatcher (`src/dbt/*`, `src/*a64*`, `src/jit/*`, `src/*trampoline*`)** across all 11 repositories (`55` concrete behavioral findings, `0` `DRY`/`YAGNI`/`CLEAN` filler, and **`rvrt` converging to `0` defects across all 23 DBT/JIT files**).

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | DRY | YAGNI | CLEAN | **R8 Total** | Raw Round-8 Static Audit Report |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `2ccfe8b` | 2 | 1 | 0 | 3 | 0 | 0 | 0 | 0 | **3 / 3** | [`2026-11-03-defects-r8-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r8-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `fa49319` | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | **2 / 2** | [`2026-11-03-defects-r8-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r8-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `3aea198` | 3 | 2 | 2 | 7 | 0 | 0 | 0 | 0 | **7 / 7** | [`2026-11-03-defects-r8-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r8-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `e8ecc7e` | 3 | 3 | 0 | 6 | 0 | 0 | 0 | 0 | **6 / 6** | [`2026-11-03-defects-r8-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r8-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `8b12acb` | 4 | 2 | 1 | 7 | 0 | 0 | 0 | 0 | **7 / 7** | [`2026-11-03-defects-r8-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r8-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `55ad5c0` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0 / 0** | [`2026-11-03-defects-r8-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r8-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `8820bff` | 5 | 3 | 0 | 8 | 0 | 0 | 0 | 0 | **8 / 8** | [`2026-11-03-defects-r8-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r8-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `ab44029` | 2 | 1 | 0 | 3 | 0 | 0 | 0 | 0 | **3 / 3** | [`2026-11-03-defects-r8-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r8-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `fb9ff82` | 4 | 0 | 0 | 4 | 0 | 0 | 0 | 0 | **4 / 4** | [`2026-11-03-defects-r8-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r8-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `57fe404` | 4 | 2 | 0 | 6 | 0 | 0 | 0 | 0 | **6 / 6** | [`2026-11-03-defects-r8-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r8-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `5ae9fe7` | 3 | 6 | 0 | 4 | 5 | 0 | 0 | 0 | **9 / 9** | [`2026-11-03-defects-r8-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r8-rt-series-astra.md) |
| | **Total (Round 8)** | | | **31** | **21** | **3** | **49** | **6** | **0** | **0** | **0** | **55 / 55** | |

### 0.2 Round 8 Cross-Cutting DBT / JIT Defect Clusters (Cross-Runtime Check Index)

- [x] **X-R8-1 — High — Delay-Slot, Link-Register (`JAL`/`JALR`, `JMPL`, `BLX`) & IT-Block Fault/Trap PC Recovery in DBT**
  - **Linked Items:** `A32-R8-2..3`, `M32-R8-3..4`, `M32-R8-6`, `S32-R8-3..4`, `M64-R8-1..4`, `P32-R8-1`
  - **Summary:** Precise PC/`npc`/delay-slot/IT-block state on faults and traps inside DBT blocks: `a32rt` Regime-A2 Soft-TLB miss losing `ctx->itstate` (`A32-R8-3`) and `RAS` key using callee `is_thumb` instead of `LR[0]` (`A32-R8-2`), `mips32rt`/`mips64rt` `JALR rd==rs` link ordering and delay-slot trap PC (`M32-R8-3..4`, `M64-R8-1..4`), `sparc32rt` branch/call/fbranch delay-slot fault reporting CTI PC and losing taken target `npc` (`S32-R8-3..4`), and `ppc32rt` `bclr`/`bcctr` missing `& ~3` target masking (`P32-R8-1`).
- [x] **X-R8-2 — High — DBT Condition-Code, Shift-Mask, Carry/Overflow & FPU Status Register (`FPSCR`/`FSR`/`FCSR`) Parity with Interpreter Oracle**
  - **Linked Items:** `M32-R8-1..2`, `M32-R8-7`, `P32-R8-2..6`, `S32-R8-1..2`, `S32-R8-5..6`, `LA64-R8-2..8`, `P64-R8-1..2`, `S64-R8-1..4`
  - **Summary:** DBT emitter divergences from interpreter oracle semantics: `mips32rt` `TLTIU`/`TEQI` condition table entries (`M32-R8-1..2`), `ppc32rt` `frsp` missing `FCVT S0, D0` narrowing (`P32-R8-3`) and `FPSCR` `FPRF`/`FPCC`/`FR`/`VX*` updates (`P32-R8-2,4..6`), `sparc32rt` `FBO` mask `0x8` vs `0x7`, `TA` `SW_BIT`, logic-cc `C`/`V` clearing, and `FTT` clearing (`S32-R8-1..2,5..6`), `loongarch64rt` `REVB_2W`/`REVB_4H`/`REVB_2H`, `MULW.D.WU`, `FMOV.S` NaN-boxing, and `MOVGR2FRH.W` (`LA64-R8-2..8`), `ppc64rt` 6/7-bit shift amounts and `SUBFO` `OV` (`P64-R8-1..2`), and `sparc64rt` `Tcc` immediate `rs1`, `ADDXCC` `icc`, `WR %asi`, and `ALIGNADDRL` (`S64-R8-1..4`).
- [x] **X-R8-3 — High — SIMD / Vector Lane Moves (`SSE`, `LSX`) & Immediate Range Checks in DBT Emitters**
  - **Linked Items:** `I686-R8-1`, `LA64-R8-1`, `LA64-R8-9`, `P64-R8-3`, `S64-R8-5`
  - **Summary:** `i686rt` register-form `MOVHLPS`/`MOVLHPS` transposed lanes (`I686-R8-1`), `loongarch64rt` `LDPTR`/`STPTR` wide `si14<<2` offset overflowing `a64e_add_imm` (`LA64-R8-1`) and `VAND.V`/`VORN.V` passing `vk = 0` (`LA64-R8-9`), `ppc64rt` prefixed instruction at `PC % 64 == 60` not rejected in `fetch.c` (`P64-R8-3`), and `sparc64rt` `regasi` lost in `s64_jrt_mem` (`S64-R8-5`).
- [x] **X-R8-4 — Medium — I-Cache Coherence (`DC CVAU` on `ICACHE_TRAP_IALLU`), TSO Barriers, Multi-Threaded IBTC Epoch & Single-Step Chaining**
  - **Linked Items:** `A32-R8-1`, `I686-R8-2`, `M32-R8-5`, `S32-R8-7`, `S64-R8-6`
  - **Summary:** `a32rt` missing `DC CVAU` loop before trapped `IC IVAU` when `A32H_CAP_ICACHE_TRAP_IALLU` is set (`A32-R8-1`), `i686rt` `emit_branch.c` missing TSO barriers in `e->tso` mode (`I686-R8-2`), `mips32rt` inline IBTC probe checking `smc_version` (`M32-R8-5`), `sparc32rt` `thread_entry.S` loading `x25` `g_vm32_prot` base (`S32-R8-7`), and `sparc64rt` `dbt_step_one` disabling block chaining (`S64-R8-6`).
- [x] **X-R8-5 — Medium — `rt-series` Host-Contract & Unification Docs + Dual-Engine (`interp` vs `dbt`) & SMC Torture Coverage**
  - **Linked Items:** `RTS-R8-1..9`
  - **Summary:** Align `docs/HOST-CONTRACT.md` and `SPEC.md` with `sparc64rt` `AT_PAGESZ = 8192`, `A32H_CAP_FIXADE`/`A32H_CAP_SOFT_TLB_256M`, Regime A1/A2 `x20` dual meaning, epoch-gated IBTC invalidation, and Darwin `sys_icache_invalidate` (`RTS-R8-1..5`), add `--` separator in `remote_bench_common.sh` (`RTS-R8-6`), run both `interp` and `dbt` in `run_grind.sh` (`RTS-R8-7..8`), and add self-modifying code (`SMC` + cache flush) differential test to `tests/p3_torture.c` (`RTS-R8-9`).

---

## 1. `a32rt` (`2ccfe8b` -> `9b36b84`) — 3 Round-8 Findings (`3 / 3` Resolved)

- [x] **A32-R8-1 — BUG — HIGH — `src/vm/vm_jit_mem.c:84-92` — Missing `DC CVAU` loop on `A32H_CAP_ICACHE_TRAP_IALLU` path**: Clean D-cache lines (`dc cvau` + `dsb ish`) before the single trapped `ic ivau` so freshly emitted instructions in dirty D-cache lines are pushed to PoU before I-cache invalidation.
- [x] **A32-R8-2 — BUG — MEDIUM — `src/dbt/dbt_jit_run.c:392` — RAS return key uses callee `is_thumb` instead of caller `LR[0]`**: Compute `bool ret_thumb = (ctx->regs[14] & 1U) != 0U;` when building `ret_key = a32_make_key(lr_pc, ret_thumb)` so `BLX` interworking calls push the caller's return mode.
- [x] **A32-R8-3 — BUG — HIGH — `src/core/core_emit_mem.c:104-150` — Regime-A2 Soft-TLB fault exit loses `ctx->itstate` in Thumb IT blocks**: Store the pre-instruction `itstate` before returning `A32_EXIT_FAULT` on the Soft-TLB miss path (matching `UNDEF`/`BKPT`/`SVC` exits).

---

## 2. `i686rt` (`fa49319` -> `c7dc379`) — 2 Round-8 Findings (`2 / 2` Resolved)

- [x] **I686-R8-1 — BUG — HIGH — `src/dbt/emit_sse.c:173-177` — Register-form `MOVHLPS`/`MOVLHPS` lane moves are transposed**: In `sse_emit_movlp_hp` (`modrm_mod == 3`), swap the `hi != 0U` (`MOVLHPS`: `sse_ins_d_elt(b, 0U, 1U, 1U, 0U)` vs `MOVHLPS`: `sse_ins_d_elt(b, 0U, 0U, 1U, 1U)`) arms so `MOVLHPS` (`0F 16` reg-reg) copies low-to-high (`d[1] <- s[0]`) and `MOVHLPS` (`0F 12` reg-reg) copies high-to-low (`d[0] <- s[1]`), matching `interp`.
- [x] **I686-R8-2 — DEFECT — MEDIUM — `src/dbt/emit_branch.c:326-530` — Branch-module guest memory accesses lack TSO barriers when `e->tso` is active**: Emit `dmb ishld` (`0xD50339BFU`) after guest loads and `dmb ish` (`0xD5033BBFU`) after guest stores in `emit_branch.c` (`CALL`, `RET`, indirect `JMP`) when `e->tso` is set.

---

## 3. `mips32rt` (`3aea198` -> `a7254bd`) — 7 Round-8 Findings (`7 / 7` Resolved)

- [x] **M32-R8-1 — BUG — HIGH — `src/dbt/emit_int.c:546` — `TLTIU` uses `A64_COND_GT` (`12U`) instead of `A64_COND_CC` (`3U`)**: Change `kCond[3]` (`TLTIU`) to `3U` (`A64_COND_CC`, unsigned `<`).
- [x] **M32-R8-2 — BUG — HIGH — `src/dbt/emit_int.c:546` — `TEQI` uses `A64_COND_LE` (`13U`) instead of `A64_COND_EQ` (`0U`)**: Change `kCond[4]` (`TEQI`) to `0U` (`A64_COND_EQ`, `==`).
- [x] **M32-R8-3 — BUG — HIGH — `src/dbt/emit_fp.c:830` — FP trap exits inside delay slots commit the slot PC instead of the branch PC**: Thread `ind_slot` / branch PC into `dbt_emit_fp` (or decline trapping FP in delay slots) so enabled FCSR traps inside a delay slot commit `pc = branch`, `npc = delay_target` matching integer traps.
- [x] **M32-R8-4 — BUG — MEDIUM — `src/dbt/emit_int.c:668` — `JALR` with `rd == rs` defers link write past delay slot**: Write `link_rd` before executing the delay slot (preserving original target in `delay_target` and restoring `ctx->r[rs]` on fault exits if needed) so the delay slot observes `rd = pc + 8` and a slot write to `rd` wins.
- [x] **M32-R8-5 — BUG — MEDIUM — `src/dbt/trampoline_a64.S:67` — Inline IBTC probe does not validate `entry.smc_version`**: Check `entry.smc_version` (or global SMC epoch) in the inline IBTC probe so a concurrent thread's SMC invalidation cannot hit a stale IBTC entry.
- [x] **M32-R8-6 — BUG — LOW — `src/dbt/trace.c:77` — `has_delay_slot` misses `BLTZAL`/`BGEZAL`/`BLTZALL`/`BGEZALL` (`rt` `0x10..0x13`)**: Accept `rt <= 3U || (rt >= 0x10U && rt <= 0x13U)` in `has_delay_slot`.
- [x] **M32-R8-7 — BUG — LOW — `src/dbt/emit_fp.c:557` — Deferred FP batch skips intermediate enabled-exception traps if `CTC1` enables traps after block compilation**: Check runtime `FCSR` enable bits at `fp_batch_begin` (or flush/trap per op when any enable bit is set).

---

## 4. `ppc32rt` (`e8ecc7e` -> `e4c4a46`) — 6 Round-8 Findings (`6 / 6` Resolved)

- [x] **P32-R8-1 — BUG — HIGH — `src/dbt/emit_int.c:527` — `bclr`/`bcctr` target not masked with `& ~3U`**: Mask `A64_TMP0` with `0xFFFFFFFCU` before `a64_emit_exit_branch_reg` in `ei_bcxr`.
- [x] **P32-R8-2 — BUG — MEDIUM — `src/dbt/emit_fp_class.c:42` — `fp_fprf` `C`-bit misclassifies `±Inf`, `-0.0`, and `QNaN`**: Set `C = isQNaN | isDenorm | (isZero & sign)` and clear `C` for `±Inf`, matching `fp_fprf64` in `src/interp/fp.h`.
- [x] **P32-R8-3 — BUG — HIGH — `src/dbt/emit_fp.c:555` — `frsp` (`in == 2U`) omits `FCVT S0, D0` before `FCVT D0, S0`**: Emit `FCVT S0, D0` (`0x1E624000`) before widening `FCVT D0, S0` (`0x1E22C000`).
- [x] **P32-R8-4 — BUG — HIGH — `src/dbt/emit_fp.c:382` — `fcmpu`/`fcmpo` never updates `FPSCR[FPCC]` (bits 15:12)**: Merge the 4-bit condition result `EI_R << 12` into `ctx->fpscr` under mask `0xF000U` (preserving `C` bit 16), matching the interpreter oracle.
- [x] **P32-R8-5 — BUG — MEDIUM — `src/dbt/emit_fp.c:198` — `FPSCR[FR]` (bit 18) never cleared or updated**: Clear `FPSCR_FR` (`0x40000U`) alongside `FI` per operation (or decline to interpreter when `FR` tracking is needed) so stale `FR` bits do not persist.
- [x] **P32-R8-6 — BUG — MEDIUM — `src/dbt/emit_fp.c:311` — Invalid-operation sub-bits (`VXISI`, `VXIMZ`, `VXZDZ`, `VXIDI`) folded into `VXSNAN`**: Classify invalid inputs (`Inf-Inf`, `0*Inf`, `0/0`, `Inf/Inf`) to set the architectural `VX*` sub-bit matching `fp_inv2` in `src/interp/fp.h`.

---

## 5. `sparc32rt` (`8b12acb` -> `786c5ab`) — 7 Round-8 Findings (`7 / 7` Resolved)

- [x] **S32-R8-1 — BUG — HIGH — `src/dbt/emit_fpbranch.c:36` — `FBfcc` condition 15 (`FBO`) mask is `0x8` instead of `0x7`**: Change `fp_taken_mask[15]` from `0x8U` to `0x7U` (ordered: `fcc in {0,1,2}`).
- [x] **S32-R8-2 — BUG — HIGH — `src/dbt/emit_int.c:405` — Taken `Ticc` `exit_arg` omits `SPARC32_TRAP_SW_BIT` (`0x100`)**: OR `0x100U` into `EKEEP` before storing `exit_arg` so `sparc32_trap_signo` delivers `SIGTRAP`/`SIGILL` instead of `SIGFPE`.
- [x] **S32-R8-3 — BUG — HIGH — `src/dbt/emit_cti.c:160` & `src/dbt/emit_fpbranch.c` — Delay-slot faults in `Bicc`/`CALL`/`FBfcc` report CTI `pc` instead of delay `npc`**: Set `ec->fault_pc = npc` before emitting the delay slot (matching `JMPL`).
- [x] **S32-R8-4 — BUG — HIGH — `src/dbt/emit_cti.c:214` & `src/dbt/dbt.c:307` — Taken CTI delay-slot fault commits `npc = dest + 4` instead of branch `target`**: Record the branch target via `a64_jmpl_record` before the taken-path delay slot so a fault inside the delay slot commits `npc = target`.
- [x] **S32-R8-5 — BUG — MEDIUM — `src/dbt/emit_int.c:238` — Logical `-cc` ops (`ANDcc`/`ORcc`/`XORcc`/`ANDNcc`/`ORNcc`/`XNORcc`) preserve stale host `C` and `V` in `psr.icc`**: Clear `C` and `V` in the committed `icc` nibble for logical `-cc` operations (`op3` `0x11..0x17`).
- [x] **S32-R8-6 — BUG — MEDIUM — `src/dbt/emit_fp.c:355` — Inline FP arithmetic and `FCMP` preserve stale `FSR.ftt` bits (bits 16:14)**: Clear bits 16:14 (`0xFFFF83E0U` / `0xFFFE3FE0U`) when committing `FSR` on successful inline FP operations.
- [x] **S32-R8-7 — BUG — LOW — `src/rt32/thread_entry.S:107` — `THREAD_CORE` omits loading `x25` (`g_vm32_prot` base)**: Load `g_vm32_prot` into `x25` in `THREAD_CORE` matching `trampoline_a64.S:40-49`.

---

## 6. `rvrt` (`55ad5c0` -> `786c675`) — 0 Round-8 Findings (`0 / 0` Resolved — Subsystem Converged)

All 23 files in `src/dbt/*`, `src/jit/*`, `src/darwin_dbt*`, `src/dbt_emit_fp.*`, `src/dbt_emit_m.c`, and `src/runtime/safe_syscall_a64.S` were audited line-by-line with **0 concrete behavioral bugs found** ([`2026-11-03-defects-r8-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r8-rvrt-astra.md)); 5 AOT cache items (`RV-R8-AOT-1..5`) were also remediated and verified in `786c675`.

---

## 7. `loongarch64rt` (`8820bff` -> `955b481`) — 8 Round-8 Findings (`8 / 8` Resolved)

- [x] **LA64-R8-1 — BUG — HIGH — `src/dbt/emit_ldst.c:106` — `LDPTR`/`STPTR` wide offset (`si14 << 2` outside `±4095`) overflows `a64e_add_imm` mid-sequence**: Check offset range (`off < -4095 || off > 4095`) before emitting any instructions in `la64_emit_ldst` and decline to interpreter when out of 12-bit range.
- [x] **LA64-R8-2 — BUG — HIGH — `src/dbt/emit_int.c:636` — `REVB.2W` emits `EXTR` (word swap) instead of `REV32 X`**: Emit `REV32 X` (`0xDAC00800U`) so bytes are reversed within each 32-bit word.
- [x] **LA64-R8-3 — BUG — HIGH — `src/dbt/emit_int.c:631` — `REVB.4H` emits `REV32 X` instead of `REV16 X`**: Emit `REV16 X` (`0xDAC00400U`) so bytes are swapped within each 16-bit halfword.
- [x] **LA64-R8-4 — BUG — HIGH — `src/dbt/emit_int.c:629` — `REVB.2H` omits 32-bit sign extension (`SXTW`)**: Emit `REV16 W` (`0x5AC00400U`) followed by `SXTW`.
- [x] **LA64-R8-5 — BUG — HIGH — `src/dbt/emit_int.c:486` — `MULW.D.WU` sign-extends `rj` (`SXTW`) instead of zero-extending**: Zero-extend `rj` (`MOV W, Wj`) before 64-bit `MUL`.
- [x] **LA64-R8-7 — BUG — MEDIUM — `src/dbt/emit_fp.c:253` — `FMOV.S` copies 64 bits without NaN-boxing upper 32 bits**: NaN-box `.S` moves (`ORR` upper 32 bits with `0xFFFFFFFF00000000ULL`) and tag the FPR cache slot accordingly.
- [x] **LA64-R8-8 — BUG — MEDIUM — `src/dbt/emit_fp.c:299` — `MOVGR2FRH.W` emits `UBFM #32, #63` (`LSR #32`) instead of `LSL #32` / `BFI`**: Deposit the low 32 bits of `rj` into bits `[63:32]` of the target FPR while preserving bits `[31:0]`.
- [x] **LA64-R8-9 — BUG — MEDIUM — `src/dbt/emit_fp.c:694` — Vector bitwise ops (`VAND.V`/`VOR.V`/`VXOR.V`/`VANDN.V`/`VORN.V`) pass `vk = 0` to `v_halves3`**: Pass the decoded `vk` register instead of `0`.

---

## 8. `ppc64rt` (`ab44029` -> `c84da61`) — 3 Round-8 Findings (`3 / 3` Resolved)

- [x] **P64-R8-1 — BUG — HIGH — `src/dbt/emit_int.c:339` — Register shifts (`SLW`/`SRW`/`SRAW`/`SLD`/`SRD`/`SRAD`) mask shift amount to 5/6 bits instead of 6/7 bits**: Mask word shifts with `63` (zeroing or sign-filling when `n >= 32`) and doubleword shifts with `127` (zeroing or sign-filling when `n >= 64`), matching `src/interp/interp.h`.
- [x] **P64-R8-2 — BUG — HIGH — `src/dbt/emit_int.c:155` — `SUBFO` (`PPC64_OP_SUBF` with `OE=1`) omits `XER[OV,OV32,SO]` update**: Compute overflow for `SUBFO` (`RB - RA`, `s1 = RB ^ RA`, `s2 = RB ^ RT`) via `e_ov2()` alongside `ADDO`.
- [x] **P64-R8-3 — BUG — MEDIUM — `src/dbt/fetch.c:109` — `ppc64_dbt_fetch` does not reject 8-byte prefixed instructions crossing a 64-byte boundary (`(pc & 63) == 60`)**: Return `false` when `(w0 >> 26u) == 1u && (pc & UINT64_C(63)) == UINT64_C(60)` so `ppc64_step()` raises `PPC64_TRAP_INST_MISALIGNED`.

---

## 9. `mips64rt` (`fb9ff82` -> `954328e`) — 4 Round-8 Findings (`4 / 4` Resolved)

- [x] **M64-R8-1 — BUG — HIGH — `src/dbt/emit_int.c:391` — `JR`/`JALR` misaligned target faults before executing the delay slot and reports branch PC**: Execute the link and delay slot before checking target alignment, then fault at the misaligned target address matching `src/interp/interp.c:800`.
- [x] **M64-R8-2 — BUG — HIGH — `src/dbt/emit_alu.c:261` & `src/dbt/emit_int.c:524` — Trapping ALU/trap instructions in a delay slot do not set `in_delay_slot`**: Decline trapping instructions (`ADD`, `DADD`, `SUB`, `DSUB`, `ADDI`, `DADDI`, `TGE*`, `TLT*`, `TEQ*`, `TNE*`) when `slot != 0` so `interp_step` handles the delay-slot trap with `in_delay_slot = 1`.
- [x] **M64-R8-3 — BUG — HIGH — `src/dbt/emit_int.c:385` & `src/dbt/emit_fpmem.c:367` — Deferred `JAL` link write breaks `COP1`/`COP1X` delay slots**: Decline linking branches whose `COP1`/`COP1X` delay slot writes the link register (`$ra`) or performs a memory access that can fault/miss.
- [x] **M64-R8-4 — BUG — HIGH — `src/dbt/emit_int.c:394` & `src/dbt/mem_recover.c:202` — `JALR` with `rd == rs` overwrites `ctx->gpr[rs]` before a faulting delay-slot load/store**: Decline indirect linking branches (`JALR`) when `d->rd == d->rs` (or when the delay slot is a memory operation) so fault recovery never reads a link-clobbered `rs`.

---

## 10. `sparc64rt` (`57fe404` -> `fb84de0`) — 6 Round-8 Findings (`6 / 6` Resolved)

- [x] **S64-R8-1 — BUG — HIGH — `src/dbt/emit_cond.c:469` — Immediate `Tcc` (`d->is_imm != 0`) ignores `rs1`**: Compute `(R[rs1] + d->imm) & 0x7FU` for immediate `Tcc` matching `exec_tcc` in `src/interp/interp.c:353`.
- [x] **S64-R8-2 — BUG — HIGH — `src/dbt/emit_int.c:242` — `ADDXCC`/`SUBXCC` (`ADDCcc`/`SUBCcc`) computes `icc` nibble from stale flags**: Route `with_carry && cc` (`ADDCcc`/`SUBCcc`) through `e_emit_alu_helper(ec, d)` so both `icc` and `xcc` are exact.
- [x] **S64-R8-3 — BUG — MEDIUM — `src/dbt/emit_int.c:438` — `WR %asi` omits `& 0xFFU` mask**: Mask `ES1` with `sb_ubfm(b, false, ES1, ES1, 0U, 7U)` before storing to `E_OFF_ASI`.
- [x] **S64-R8-4 — BUG — MEDIUM — `src/dbt/emit_int.c:453` — `ALIGNADDRL` (`opf == 0x1A`) decoded identically to `ALIGNADDR`**: Negate the low 3 bits (`(0 - sum) & 7`) when `d->opf == 0x1AU`.
- [x] **S64-R8-5 — BUG — HIGH — `src/dbt/emit_mem.h:92` — `s64_jrt_mem` leaves `d.regasi` uninitialized / loses `%asi`-relative flag**: Pack `d->regasi` into the helper descriptor and initialize `d.regasi` in `s64_jrt_mem` so `%asi`-relative loads/stores resolve `cpu->asi`.
- [x] **S64-R8-6 — BUG — HIGH — `src/dbt/dbt.c:604` — `dbt_step_one` passes `single_step = false` to `dbt_enter_block`**: Pass `true` so single-step execution uses `sparc64_dbt_enter_step` (zero epoch, no chaining).

---

## 11. `rt-series` (`5ae9fe7` -> `315bdac`) — 9 Round-8 Findings (`9 / 9` Resolved)

- [x] **RTS-R8-1 — DEFECT — MEDIUM — `docs/HOST-CONTRACT.md:36` — `AT_PAGESZ = 4096` statement omits `sparc64rt` (`8192`)**: Carve out `sparc64rt` (`AT_PAGESZ = 8192` with 8 KiB alignment and paired 4 KiB Soft-TLB entries) matching `SPEC.md` `D11` and `docs/UNIFICATION-PLAN.md`.
- [x] **RTS-R8-2 — DEFECT — MEDIUM — `docs/HOST-CONTRACT.md:102-114` — `A32H_CAP_FIXADE` (bit 10) and `A32H_CAP_SOFT_TLB_256M` (bit 11) missing from capability table**: Document bits 10 and 11 in `docs/HOST-CONTRACT.md` matching `include/a32host.h`.
- [x] **RTS-R8-3 — DEFECT — MEDIUM — `SPEC.md:22,83,273` — Class-A `x20` description states `x20 = xG` unconditionally without Regime-A2 (`x20 = &ctx->tlb[0]`)**: Clarify Regime A1 (`x20 = xG`) vs Regime A2 (`x20 = &ctx->tlb[0]`, `x23 = xG`) in `SPEC.md` matching `docs/UNIFICATION-PLAN.md`.
- [x] **RTS-R8-4 — DEFECT — MEDIUM — `SPEC.md:127` — IBTC direct linking rule omits epoch-gating and invalidation on `munmap`/`mprotect`/SMC**: Document epoch-gated IBTC/RAS lookup and mandatory invalidation on `munmap`/`mprotect`/SMC in `SPEC.md`.
- [x] **RTS-R8-5 — DEFECT — MEDIUM — `docs/UNIFICATION-PLAN.md:92,465` — Darwin `MAP_JIT` and `rt_host_jit_seal_rx` omit explicit I-cache invalidation (`sys_icache_invalidate` / `__builtin___clear_cache`)**: Document mandatory I-cache invalidation in `rt_host_jit_seal_rx` across both Linux and Darwin backends.
- [x] **RTS-R8-6 — BUG — HIGH — `tools/remote_bench_common.sh:35,71-77,128-137` — Missing `--` separator before guest binary path for Class-B translators**: Include `--` before the guest path in `remote_bench_common.sh`.
- [x] **RTS-R8-7 — BUG — HIGH — `tools/run_grind.sh:277,296,536,602,630,691` — Grind suites execute only a single engine (`interp` OR `dbt`) instead of both**: Run both `GRIND_INTERP` and `GRIND_DBT` when both are configured and fail if outputs/exit codes diverge.
- [x] **RTS-R8-8 — BUG — MEDIUM — `tools/run_grind.sh:341,383-385` — `gcc-torture` promotes first engine output when `GRIND_QEMU` is unset**: Require `GRIND_QEMU` (or report `SKIP`/`GAP` rather than `PASS` when no independent oracle is provided unless `GRIND_ALLOW_NO_ORACLE=1`).
- [x] **RTS-R8-9 — BUG — HIGH — `tests/p3_torture.c:877-888` — Missing self-modifying code (`SMC`) + cache-invalidation test in `p3_torture.c`**: Add a portable `t_smc_clear_cache` test row in `tests/p3_torture.c` that maps a RW page, writes a small function returning `42`, flips to `RX` + `__builtin___clear_cache`, executes it, flips back to `RW`, patches the return value to `99`, flips to `RX` + `__builtin___clear_cache`, and verifies the second call returns `99` (not stale cached `42`).

---

## Part II — Round-7 Archive: Subsystem Deep-Dive 1 of 6 (ISA Interpreter & CPU State/Trap Semantics, `277 / 277` Resolved — Verified by `claude-fable-5-1` & `claude-opus-4-6`)

### 0.1 Round 7 Audit Matrix (`277 / 277` Resolved)

Following complete remediation, `fable` (`claude-fable-5-1`) verification review, and `muse` post-review follow-up across Rounds 1–6 (`739` per-repo items + `43` clusters = `782` checkboxes resolved), Round 7 initiated **Regime II (Subsystem Deep-Dive 1 of 6: ISA Interpreter `src/interp/*` & CPU State/Trap Semantics)** across all 11 repositories (`277` concrete behavioral findings: `0 Critical`, `110 High`, `166 Medium`, `1 Low`; `0` `DRY`/`YAGNI`/`CLEAN` filler).

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | DRY | YAGNI | CLEAN | **R7 Total** | Raw Round-7 `astra` Transcript |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `73c2603` | 14 | 18 | 0 | 31 | 1 | 0 | 0 | 0 | **32 / 32** | [`2026-11-03-defects-r7-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r7-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `254b3c0` | 30 | 25 | 0 | 50 | 5 | 0 | 0 | 0 | **55 / 55** | [`2026-11-03-defects-r7-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r7-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `691d450` | 8 | 12 | 0 | 19 | 1 | 0 | 0 | 0 | **20 / 20** | [`2026-11-03-defects-r7-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r7-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `278f4e8` | 11 | 14 | 0 | 20 | 5 | 0 | 0 | 0 | **25 / 25** | [`2026-11-03-defects-r7-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r7-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `a810f0c` | 10 | 13 | 0 | 22 | 1 | 0 | 0 | 0 | **23 / 23** | [`2026-11-03-defects-r7-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r7-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `2b6759c` | 2 | 3 | 0 | 5 | 0 | 0 | 0 | 0 | **5 / 5** | [`2026-11-03-defects-r7-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r7-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `058a318` | 9 | 17 | 0 | 25 | 1 | 0 | 0 | 0 | **26 / 26** | [`2026-11-03-defects-r7-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r7-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `bda02bd` | 7 | 23 | 0 | 27 | 3 | 0 | 0 | 0 | **30 / 30** | [`2026-11-03-defects-r7-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r7-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `f29422b` | 8 | 10 | 0 | 16 | 2 | 0 | 0 | 0 | **18 / 18** | [`2026-11-03-defects-r7-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r7-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `bab379d` | 10 | 25 | 0 | 35 | 0 | 0 | 0 | 0 | **35 / 35** | [`2026-11-03-defects-r7-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r7-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `a7b9bc6` | 1 | 6 | 1 | 2 | 6 | 0 | 0 | 0 | **8 / 8** | [`2026-11-03-defects-r7-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r7-rt-series-astra.md) |
| | **Total (Round 7)** | | | **110** | **166** | **1** | **252** | **25** | **0** | **0** | **0** | **277 / 277** | |

### 0.2 Round 7 Cross-Cutting ISA Interpreter Defect Clusters (Cross-Runtime Check Index)

- [x] **X-R7-1 — High — FPU Exception Flags, NaN Propagation/Quieting, Directed Rounding & Float-to-Int Range/Saturation Semantics**
  - **Linked Items:** `A32-R7-29..31`, `I686-R7-32..51`, `M32-R7-13..20`, `P32-R7-18..23`, `S32-R7-17..23`, `RV-R7-2`, `RV-R7-4`, `LA64-R7-18..25`, `P64-R7-21..29`, `M64-R7-11..18`, `S64-R7-28..35`
  - **Summary:** Cross-ISA FPU corner cases uncovered by end-to-end `src/interp/*` inspection: float-to-int range checking before truncation (`P32-R7-20`, `S32-R7-21`, `S64-R7-32`), `FCSR`/`FSR`/`FPSCR` cause vs sticky flag handling and writable-field masks (`M32-R7-19`, `M64-R7-12..13`, `S32-R7-18`, `S64-R7-29`, `P64-R7-26..29`), sNaN quieting and `FMIN`/`FMAX`/`FMINA`/`FMAXA` NaN/tie selection (`M32-R7-16`, `LA64-R7-21..22`), `rvrt` inverted `FLT.S/D` & `FLE.S/D` A64 condition codes (`RV-R7-2`), and fused vs non-fused rounding (`A32-R7-29`, `LA64-R7-25`).
- [x] **X-R7-2 — High — Register Width Invariants, 32-Bit Sign/Zero Extension & Partial-Register Write Semantics**
  - **Linked Items:** `A32-R7-26..28`, `I686-R7-52`, `RV-R7-1`, `LA64-R7-1..8`, `P64-R7-1..9`, `M64-R7-1..6`, `S64-R7-1..9`
  - **Summary:** 32-bit sign-extension invariants on 64-bit guest architectures (`RV-R7-1` RV32 syscall return canonicalization, `M64-R7-1..6`, `LA64-R7-1..8`), `i686rt` `vm86` 16-bit `r16_set()` clobbering upper GPR halves (`I686-R7-52`), and `a32rt` NEON/VFP halfword lane moves (`A32-R7-26..28`).
- [x] **X-R7-3 — High — Branch Delay Slots, Annulment, IT Blocks & Control-Transfer Link/Target Ordering**
  - **Linked Items:** `A32-R7-1..9`, `I686-R7-18..25`, `M32-R7-1..6`, `P32-R7-1..8`, `S32-R7-1..8`, `LA64-R7-9..12`, `P64-R7-10..15`, `M64-R7-7..10`, `S64-R7-10..18`, `RTS-R7-5`
  - **Summary:** Delay-slot fault/link ordering and branch-likely/annul semantics across MIPS32, MIPS64, SPARC32, and SPARC64, Thumb-2 IT-block state progression in `a32rt`, PowerPC `BO`/`BI`/`CTR` conditional branch forms in `ppc32rt`/`ppc64rt`, and x86 control-transfer segment/limit checks in `i686rt`.
- [x] **X-R7-4 — High — Register Windows, Fault-Before-Commit Ordering & Atomic Reservation (`LL/SC`, `LR/SC`, `LWARX/STWCX.`, `CASA`) Semantics**
  - **Linked Items:** `A32-R7-10..18`, `M32-R7-7..12`, `P32-R7-9..17`, `S32-R7-9..16`, `RV-R7-3`, `LA64-R7-13..17`, `P64-R7-16..20`, `S64-R7-19..27`
  - **Summary:** SPARC V8/V9 register-window `SAVE`/`RESTORE`/`FLUSHW` spill/fill fault ordering (`S32-R7-1..5`, `S64-R7-10..15`), PowerPC update-form `RA==0`/`RA==RT` validation and `LWARX`/`STWCX.` reservation rules (`P32-R7-25`, `P64-R7-16..20`), and RISC-V `C.FLWSP f0` decoding (`RV-R7-3`).
- [x] **X-R7-5 — High — SIMD / Vector Lane Ordering (`NEON`, `SSE/SSE2`, `SPE`, `VMX/VSX`, `LSX/LASX`, `VIS`) & Architectural Register Serialization**
  - **Linked Items:** `A32-R7-19..28`, `I686-R7-50..51`, `P32-R7-14..17`, `LA64-R7-18..21`, `P64-R7-24..30`, `S64-R7-30`
  - **Summary:** `i686rt` swapped `PSRLDQ`/`PSLLDQ` direction and `imm4|3` encoding bug (`I686-R7-50`), `ppc64rt` internal vs architectural `XER` bit serialization in `sigframe.c` (`P64-R7-30`), `sparc64rt` `FPRS` dirty-bit (`DL`/`DU`) tracking (`S64-R7-30`), and `a32rt` `VREV64.16`/`VMOV` lane handling (`A32-R7-26..28`).
- [x] **X-R7-6 — Medium — `rt-series` ISA Torture Suite, `lmbench` Runner Arguments & `ISA-TRAP-AND-ABI-MATRIX.md` Precision**
  - **Linked Items:** `RTS-R7-1..8`
  - **Summary:** `tests/p3_torture.c` nested alternate-stack signal test coverage (`RTS-R7-4`), `tools/run_grind.sh` per-tool `lmbench` arguments (`RTS-R7-7`), and SPARC32/MIPS64-N32 signal-frame & SPARC V8 annul documentation in `lode/ISA-TRAP-AND-ABI-MATRIX.md` (`RTS-R7-5..6`, `RTS-R7-8`).

---

## 1. `a32rt` (`73c2603`) — 32 Round-7 Findings (`32 / 32` Resolved)

Static audit completed across every file in `src/interp/` and the related emitters, CPU state, exclusive-monitor, and trap paths. No builds, tests, or edits were performed.

- [x] **A32-R7-1 — BUG — HIGH**

- **Summary**: `UDF.W` executes a syscall instead of raising SIGILL.
- **Locations**: [interp_thumb.c:762](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:762), [dbt_jit_run.c:492](/Users/angerman/Projects/zw3rk/a32rt/src/dbt/dbt_jit_run.c:492).
- **Evidence & Root Cause**: `F7F0 A000`, encoding `UDF.W #0`, returns `A32_EXIT_SVC`. Both interpreter execution and the JIT’s UNDEF fallback subsequently dispatch the syscall selected by `r7`. An instruction intended to trap can therefore perform an external side effect.
- **Remediation**: Decode this family as UNDEF, retain the faulting PC and IT state, and prevent syscall dispatch.

- [x] **A32-R7-2 — BUG — HIGH**

- **Summary**: Thumb decoder masks turn loads and byte stores into unrelated operations.
- **Locations**: [interp_thumb.c:159](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:159), [interp_thumb.c:277](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:277), [interp_thumb.c:340](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:340).
- **Evidence & Root Cause**: The broad `0x4xxx` branch captures literal loads before their decoder: `0x4800` doubles `r0` instead of loading `[Align(PC+4,4)]`. Incorrect memory-class masks also send `0x7008` (`STRB r0,[r1]`) to the SP-relative word-store fallback, writing four bytes at `sp+32`. Actual `0x9xxx` SP-relative transfers are excluded.
- **Remediation**: Use disjoint architectural masks, explicit SP-relative decoding, and rejection of unmatched encodings.

- [x] **A32-R7-3 — BUG — HIGH**

- **Summary**: Nonword exclusives, doubleword exclusives, and SWP fall into arithmetic decoding.
- **Locations**: [interp_a32.c:166](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:166), [interp_a32.c:504](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:504).
- **Evidence & Root Cause**: LDREXB/H and STREXB/H use incorrect opcode comparisons. LDREXD/STREXD and SWP lack interpreter dispatch. For example, `E1D10F9F` (`LDREXB r0,[r1]`) reaches the broad multiply decoder and modifies arithmetic registers instead of loading memory. SWP likewise matches that fallback.
- **Remediation**: Decode these families before generic data processing, correct their masks, and provide an eight-byte exclusive reservation implementation.

- [x] **A32-R7-4 — BUG — HIGH**

- **Summary**: JIT flag elimination destroys the APSR state required at a fault.
- **Locations**: [interp_a32_ctl.c:605](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_ctl.c:605), [interp_t32_mem.c:661](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_t32_mem.c:661), [signals.c:463](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:463).
- **Evidence & Root Cause**: Backward liveness considers flag consumers and overwriters, but not intervening faultable instructions. In `ADDS; LDR [unmapped]; CMP`, the ADDS flag update can be removed because CMP overwrites it. The fault handler then captures stale host NZCV rather than the flags preceding LDR.
- **Remediation**: Treat possible synchronous exits as flag-observation points, or retain sufficient metadata to reconstruct eliminated flags.

- [x] **A32-R7-5 — BUG — HIGH**

- **Summary**: Synchronous signal frames can contain stale floating-point registers and status.
- **Locations**: [core_emit_alu.c:629](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_alu.c:629), [core_emit_mem.c:170](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:170), [signals.c:448](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:448), [trampoline.S:219](/Users/angerman/Projects/zw3rk/a32rt/src/trampoline.S:219).
- **Evidence & Root Cause**: Eligible self-loops retain modified guest FP registers in host SIMD registers and skip flushing before memory accesses. Fault recovery restores only GPRs and NZCV, then serializes stale `ctx->vfp_d`. Native FPSR exceptions are also merged only after signal-frame construction. Returning from the handler can discard completed FP work and exception flags.
- **Remediation**: Materialize or reconstruct interrupted FP registers and FPSR before constructing the guest frame.

- [x] **A32-R7-6 — BUG — MEDIUM**

- **Summary**: Instructions requiring alignment accept misaligned addresses or deliver the wrong trap.
- **Locations**: [core_emit_shared.c:508](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:508), [core_emit_mem.c:197](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_mem.c:197), [interp_a32.c:491](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:491), [interp_vfp_core.c:166](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp_core.c:166).
- **Evidence & Root Cause**: LDM/STM, LDRD/STRD, and VFP transfers use ordinary A64 accesses or `memcpy` without the required alignment checks. `LDRD` from `mapped_page+1` consequently succeeds. Interpreter word exclusives instead report UNDEF for misalignment. These differ from architectural alignment faults. [Arm alignment requirements](https://support.arm.com/documentation/100748/0624/Alignment-support-in-Arm-Compiler-for-Embedded-6/Aligned-and-unaligned-accesses).
- **Remediation**: Enforce instruction-specific alignment and deliver the appropriate guest alignment fault before committing state.

- [x] **A32-R7-7 — BUG — HIGH**

- **Summary**: Software exclusive reservations can survive intervening writes and incorrectly succeed.
- **Locations**: [interp_a32.c:29](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:29), [interp_a32.c:566](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:566), [vm32.c:439](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:439), [vm32.c:480](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:480).
- **Evidence & Root Cause**: LDREX loads memory before recording the reservation epoch. Intervening writes can therefore occur before its snapshot. Additionally, raw STRD stores and native JIT stores bypass software reservation invalidation. A peer’s A→B→A writes can leave both the saved epoch and compared value unchanged, allowing STREX to succeed.
- **Remediation**: Establish the load/reservation atomically and ensure every overlapping guest write participates in a coherent monitor protocol.

- [x] **A32-R7-8 — BUG — MEDIUM**

- **Summary**: STM permission probes introduce observable byte writes and torn words.
- **Locations**: [core_emit_shared.c:550](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:550).
- **Evidence & Root Cause**: Validation reads and writes back endpoint bytes before executing STM. Suppose the last word is `0x11223344`: the probe reads `0x11`, a peer stores `0x55667788`, then the probe restores `0x11`. Another thread can observe `0x11667788`, a value produced by neither architectural word store.
- **Remediation**: Validate permissions without modifying guest memory.

- [x] **A32-R7-9 — BUG — MEDIUM**

- **Summary**: Faulting native SWP overwrites its destination register before completing.
- **Locations**: [interp_a32_dp.c:110](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_dp.c:110), [signals.c:448](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:448).
- **Evidence & Root Cause**: The SWP loop loads directly into guest `Rd` before STXR succeeds. In direct-memory mode, readable but read-only memory permits LDXR and faults on STXR. Signal recovery exposes the loaded value in `Rd`, although the faulting swap has not completed.
- **Remediation**: Hold the loaded value in a temporary and assign `Rd` only after successful completion.

- [x] **A32-R7-10 — BUG — MEDIUM**

- **Summary**: TPIDRURW aliases TPIDRURO and corrupts the guest TLS pointer.
- **Locations**: [core_emit_shared.c:481](/Users/angerman/Projects/zw3rk/a32rt/src/core/core_emit_shared.c:481), [interp_a32.c:848](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:848).
- **Evidence & Root Cause**: Both CP15 reads return `ctx->tls_tp`; writing TPIDRURW overwrites that same field. Thus `MCR p15,0,r0,c13,c0,2` changes subsequent TPIDRURO reads and `__kuser_get_tls`. These are distinct architectural registers. [Arm register descriptions](https://documentation-service.arm.com/static/5e7b64757158f500bd5bd08e).
- **Remediation**: Maintain separate per-thread TPIDRURW and TPIDRURO state, including lifecycle handling.

- [x] **A32-R7-11 — BUG — HIGH**

- **Summary**: Thumb ADD/SUB decodes the immediate-selector and subtraction bits backwards.
- **Locations**: [interp_thumb.c:80](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:80).
- **Evidence & Root Cause**: Bit 9 selects immediate operands and bit 10 selects subtraction in the implementation; the encoding assigns those roles oppositely. `0x1C88`, `ADDS r0,r1,#2`, executes `r1-r2`.
- **Remediation**: Decode bit 10 as the immediate selector and bit 9 as ADD/SUB selection.

- [x] **A32-R7-12 — BUG — HIGH**

- **Summary**: Thumb instructions incorrectly update implicit flags inside IT blocks.
- **Locations**: [interp_thumb.c:93](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:93), [interp_thumb.c:138](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:138), [interp_thumb.c:221](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:221).
- **Evidence & Root Cause**: Several arithmetic, MOV, and logical paths update flags without checking `use_it`. With Z set, `ITT EQ; MOVEQ r0,#1; MOVEQ r1,#2` clears Z after the first MOV and skips the second. These encodings suppress their implicit flag writes inside IT.
- **Remediation**: Apply each encoding’s `setflags = !InITBlock()` rule while preserving explicit comparison flag updates.

- [x] **A32-R7-13 — BUG — HIGH**

- **Summary**: Interpreter IT progression is incorrect across taken branches and undefined-instruction traps.
- **Locations**: [interp_thumb.c:581](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:581), [interp_thumb.c:799](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:799), [interp.c:214](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:214).
- **Evidence & Root Cause**: Successful T32 instructions advance IT only when the resulting PC equals `pc+4`. A taken branch in the final IT slot leaves stale predication at its target. Conversely, UNDEF advances IT while the outer stepper restores the faulting PC, making retry use the next slot’s condition.
- **Remediation**: Advance IT according to instruction completion, independently of branch destination; preserve pre-instruction IT for retryable traps.

- [x] **A32-R7-14 — BUG — HIGH**

- **Summary**: Signal frames do not expose or restore architectural CPSR.IT.
- **Locations**: [signals.c:285](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:285), [signals.c:312](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:312), [signals.c:779](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:779).
- **Evidence & Root Cause**: IT exists separately in `ctx->itstate`, but `arm_cpsr` receives plain `ctx->cpsr`. Sigreturn ignores user-supplied IT bits and reconstructs predication from a private trailer and PC-distance heuristic. A handler cannot reliably inspect, clear, or replace the interrupted IT state through its architectural context.
- **Remediation**: Pack IT into CPSR when creating frames and restore it from validated `arm_cpsr`, following the architectural signal-context contract. [Linux ARM signal implementation](https://github.com/torvalds/linux/blob/master/arch/arm/kernel/signal.c).

- [x] **A32-R7-15 — BUG — HIGH**

- **Summary**: A32 BLX immediate never enters Thumb and drops the H displacement bit.
- **Locations**: [interp_a32.c:318](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:318).
- **Evidence & Root Cause**: The target is always `pc+8+(imm24<<2)`, then passed to an interworking helper with bit 0 clear. `FA000000` remains in ARM instead of entering Thumb; `FB000000` also loses the additional two-byte displacement.
- **Remediation**: Include `H<<1` and explicitly select Thumb state for BLX immediate.

- [x] **A32-R7-16 — BUG — HIGH**

- **Summary**: A32 LDR into PC loses interworking and address writeback.
- **Locations**: [interp_a32.c:813](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:813), [interp_a32.c:831](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:831).
- **Evidence & Root Cause**: The PC-load branch uses non-interworking semantics and returns before writeback. `LDR pc,[sp],#4` with an odd saved return address neither enters Thumb nor increments SP.
- **Remediation**: Complete permitted base writeback and apply architectural LoadWritePC interworking.

- [x] **A32-R7-17 — BUG — HIGH**

- **Summary**: Thumb ALU writes to PC incorrectly switch into ARM state.
- **Locations**: [interp_thumb.c:261](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:261).
- **Evidence & Root Cause**: MOV/ADD into PC explicitly clear CPSR.T when the result is even. Thumb `MOV pc,r0` and `ADD pc,r0` use non-interworking branch semantics and must retain Thumb state. An even destination consequently executes the target under the wrong decoder.
- **Remediation**: Use Thumb BranchWritePC semantics without changing T.

- [x] **A32-R7-18 — BUG — MEDIUM**

- **Summary**: Several interpreter paths use the wrong architectural PC value.
- **Locations**: [interp_thumb.c:239](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:239), [interp_vfp.c:306](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:306), [interp_a32.c:386](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:386), [interp_a32.c:826](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:826).
- **Evidence & Root Cause**: Thumb ALU PC reads incorrectly align `pc+4`; at `0x1002`, `MOV r0,pc` returns `0x1004` instead of `0x1006`. Thumb VLDR literals instead use ARM’s `pc+8`. A32 BX/STR with PC read raw `ctx->regs[15]`, omitting the architectural pipeline offset.
- **Remediation**: Centralize instruction-specific PC reads, distinguishing ALU, literal-address, branch-register, and stored-PC semantics.

- [x] **A32-R7-19 — BUG — MEDIUM**

- **Summary**: A32 logical flag-setting instructions clear V.
- **Locations**: [interp_a32.c:252](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:252), [interp_a32.c:273](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:273).
- **Evidence & Root Cause**: Logical operations retain the initial `ov=false` and pass it to `i_set_nzcv`. With V initially set, `MOVS r0,#0` clears V, although logical instructions must preserve it while updating NZ and shifter carry.
- **Remediation**: Preserve existing V for logical operations and use arithmetic overflow only for arithmetic classes.

- [x] **A32-R7-20 — BUG — MEDIUM**

- **Summary**: Interpreter MRS/MSR decoding mishandles register and field selection.
- **Locations**: [interp_a32.c:443](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:443), [interp_a32.c:451](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:451).
- **Evidence & Root Cause**: The MRS mask retains destination-register bits, recognizing only `r0`; `MRS r1,cpsr` falls through. MSR unconditionally replaces both NZCVQ and GE, so an NZCVQ-only write also changes GE.
- **Remediation**: Exclude Rd from MRS matching and update only the status fields selected by MSR.

- [x] **A32-R7-21 — BUG — MEDIUM**

- **Summary**: Thumb LDM loads its base register from the wrong list position.
- **Locations**: [interp_thumb.c:441](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:441), [interp_thumb.c:451](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:451).
- **Evidence & Root Cause**: When Rn appears in the list, its normal load is skipped and replaced with a load from the final word. For `LDMIA r0,{r0,r1}`, memory words X,Y produce `r0=Y,r1=Y` rather than X,Y.
- **Remediation**: Retain the value from Rn’s actual list position and suppress writeback as required.

- [x] **A32-R7-22 — BUG — MEDIUM**

- **Summary**: Interpreter BKPT can be skipped and reports the following instruction’s PC.
- **Locations**: [interp_thumb.c:48](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:48), [interp_a32.c:361](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:361), [interp.c:214](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:214).
- **Evidence & Root Cause**: Thumb IT condition checking gates BKPT, although BKPT is unconditional inside IT. Executed ARM and Thumb breakpoints advance PC before returning, and the outer stepper does not restore it for BKPT. Debuggers and SIGTRAP handlers consequently receive the wrong PC. [Arm BKPT specification](https://support.arm.com/documentation/ddi0597/2021-09/Base-Instructions/BKPT--Breakpoint-?lang=en).
- **Remediation**: Handle BKPT outside IT condition suppression and retain its instruction PC and trap-appropriate IT state.

- [x] **A32-R7-23 — BUG — MEDIUM**

- **Summary**: Thumb NOP raises an undefined-instruction trap.
- **Locations**: [interp_thumb.c:70](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_thumb.c:70).
- **Evidence & Root Cause**: The explicit UNDEF branch includes `hw == 0xBF00`, the ordinary Thumb NOP encoding. Executing compiler padding or an intentional NOP under `--interp` therefore raises SIGILL.
- **Remediation**: Decode NOP as successful completion and advance IT normally.

- [x] **A32-R7-24 — BUG — HIGH**

- **Summary**: Native NEON floating-point operations inherit scalar VFP controls.
- **Locations**: [interp_neon_alu.c:396](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_neon_alu.c:396), [interp_neon_mem.c:616](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_neon_mem.c:616), [trampoline.S:64](/Users/angerman/Projects/zw3rk/a32rt/src/trampoline.S:64).
- **Evidence & Root Cause**: Guest FPSCR controls populate host FPCR, and NEON lowering uses that unchanged environment. ARMv7 NEON requires standard round-to-nearest, flush-to-zero, and default-NaN behavior. With scalar rounding upward, NEON `1.0 + 2^-24` rounds upward instead of ties-to-even. [Arm FPU control rules](https://documentation-service.arm.com/static/5e8e11a2fd977155116a2d1a).
- **Remediation**: Apply standard NEON FP controls around affected operations, restoring scalar controls afterward.

- [x] **A32-R7-25 — BUG — MEDIUM**

- **Summary**: Interpreter scalar FP arithmetic ignores FPSCR.FZ and FPSCR.DN.
- **Locations**: [interp_vfp.c:26](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:26), [interp_vfp.c:591](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:591).
- **Evidence & Root Cause**: The host FP wrapper sets rounding only. Operand/result processing never applies FZ or DN, and exception accumulation omits IDC. With FZ set, multiplying the smallest normal float by 0.5 can produce a subnormal instead of zero; DN leaves NaN payload behavior to the host. [Arm FPU control rules](https://documentation-service.arm.com/static/5e8e11a2fd977155116a2d1a).
- **Remediation**: Implement the full guest FP environment, including denormal processing, default NaNs, and cumulative exceptions.

- [x] **A32-R7-26 — BUG — MEDIUM**

- **Summary**: Valid NEON modified-immediate instructions silently zero destinations.
- **Locations**: [interp_vfp.c:670](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:670).
- **Evidence & Root Cause**: The decoder accepts the whole family but constructs values only for selected cmodes. Remaining cases store initialized `val64=0` and report success. `VMOV.I16 d0,#1` produces zero rather than `0x0001000100010001`; VORR/VBIC immediates also lose their destination-merging behavior.
- **Remediation**: Implement each accepted cmode and its operation, or reject unsupported encodings before mutating state.

- [x] **A32-R7-27 — BUG — MEDIUM**

- **Summary**: VFP/NEON halfword lane moves execute as word moves.
- **Locations**: [interp_vfp.c:180](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:180), [interp_vfp.c:212](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:212), [interp_vfp.c:238](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:238).
- **Evidence & Root Cause**: The decoder discards `opc2` and always extracts or replaces 32 bits in accepted CP11 transfers. With D0=`0x5566778811223344`, `VMOV.U16 r0,d0[1]` returns `0x11223344` instead of `0x1122`. The reverse transfer overwrites an entire word.
- **Remediation**: Decode element width, lane index, and signedness from both opcode fields.

- [x] **A32-R7-28 — BUG — MEDIUM**

- **Summary**: `VREV64.16` reverses bytes within halfwords.
- **Locations**: [interp_vfp.c:701](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:701).
- **Evidence & Root Cause**: The halfword case reverses element positions and applies `bswap16` to every element. Input `0x1122334455667788` becomes `0x8877665544332211` instead of `0x7788556633441122`. The matching mask also fixes Q to zero, making the purported Q-register handling unreachable.
- **Remediation**: Reverse halfword positions without changing their byte order; correct Q matching and validate register pairing.

- [x] **A32-R7-29 — BUG — MEDIUM**

- **Summary**: Interpreter fused and non-fused multiply-accumulate instructions share identical semantics.
- **Locations**: [interp_vfp.c:605](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:605), [interp_vfp.c:622](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:622).
- **Evidence & Root Cause**: VMLA and VFMA use the same C expression. For single-precision operands `a=1+2^-23`, `b=1-2^-23`, and accumulator `-1`, separately rounded VMLA yields zero while VFMA yields `-2^-46`. Compiler contraction cannot make one expression correctly implement both.
- **Remediation**: Use explicit fused operations for fused encodings and enforce separate rounding for non-fused encodings.

- [x] **A32-R7-30 — BUG — MEDIUM**

- **Summary**: Interpreter VCMP fails to record invalid operation for signaling NaNs.
- **Locations**: [interp_vfp.c:467](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp.c:467).
- **Evidence & Root Cause**: The NaN path sets IOC only for VCMPE. Ordinary VCMP with S0=`0x7f800001` and S1=0 leaves IOC clear, although the operand is a signaling NaN. This path also bypasses host-exception collection.
- **Remediation**: Classify NaNs from their bits and set IOC for signaling NaNs in both instructions, and all NaNs in VCMPE.

- [x] **A32-R7-31 — BUG — MEDIUM**

- **Summary**: Native 16-bit float-to-fixed conversion saturates without setting IOC.
- **Locations**: [interp_vfp_core.c:411](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_vfp_core.c:411).
- **Evidence & Root Cause**: Lowering converts to a 32-bit integer, then clamps to 16 bits using integer comparisons. `VCVT.S16.F32 s0,s0,#1` with input 16384.0 converts to 32768 and clamps to 32767 without generating a host invalid exception or explicitly setting guest IOC.
- **Remediation**: Detect overflow against the actual destination width and accumulate the required conversion exceptions.

- [x] **A32-R7-32 — DEFECT — MEDIUM**

- **Summary**: Valid guest arithmetic and backward branches invoke C undefined behavior.
- **Locations**: [interp_a32.c:210](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:210), [interp_a32.c:795](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:795), [interp_a32_ctl.c:598](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32_ctl.c:598), [interp_t16.c:461](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_t16.c:461).
- **Evidence & Root Cause**: SMLAL adds its accumulator using signed `int64_t`, overflowing for `INT64_MAX + 1`. Post-index subtraction can negate `INT32_MIN`. Branch translation left-shifts negative signed displacements. These are valid modular guest operations but undefined C operations.
- **Remediation**: Perform wrapping arithmetic and displacement shifts in unsigned types, using signed values only where their range is proven safe.

---

## 2. `i686rt` (`254b3c0`) — 55 Round-7 Findings (`55 / 55` Resolved)

Static audit completed across all interpreter files and related decoder, CPU-state, SIMD, atomic, and trap paths. No builds, tests, or edits were performed. Examples below are deductions from the code, not executed reproducers.

- [x] **I686-R7-1 — BUG — HIGH**

- **Summary**: Subpage recovery can read beyond the guest permissions it validated.
- **Locations**: [signals_subpage.c:330](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_subpage.c:330), [signals_subpage.c:795](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_subpage.c:795).
- **Evidence & Root Cause**: The classifier treats most F3 operands as four bytes and F2 operands as eight. Packed instructions including `CVTTPS2DQ`, `PSHUFHW`, and `PSHUFLW` read sixteen bytes. Recovery validates the smaller span, opens the enclosing host-page cover, then executes the full interpreter access. An operand near a guest subpage boundary can therefore read a neighboring protected subpage.
- **Remediation**: Derive access width and direction from the exact opcode/prefix form. Validate the complete operand before opening host-page covers.

- [x] **I686-R7-2 — BUG — HIGH**

- **Summary**: LES/LDS/LSS/LFS/LGS read zero bytes and load zero values.
- **Locations**: [h_seg.c:92](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:92), [h_seg.c:318](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:318).
- **Evidence & Root Cause**: `mem_load()` expects a width in bits and calculates `n = width / 8`. `h_seg_lxs()` passes `bytes`—two or four—for the offset and `2u` for the selector. Every call consequently executes zero loop iterations and returns zero. The destination becomes zero and the segment loader receives a null selector, regardless of operand contents.
- **Remediation**: Pass bit widths consistently, or change the helper to an explicitly byte-counted interface. Reject register-only encodings before computing a memory address.

- [x] **I686-R7-3 — DEFECT — HIGH**

- **Summary**: Immediate 32-bit far CALL/JMP cannot represent their targets and invoke undefined shifts.
- **Locations**: [decode.c:366](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:366), [decode.h:62](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.h:62), [h_seg.c:212](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:212).
- **Evidence & Root Cause**: A 16:32 far pointer is packed into the 32-bit `insn->imm`. Encoding the selector shifts a `uint32_t` left by 32; extraction shifts it right by 32. Both are undefined C operations, and the field cannot retain all 48 target bits.
- **Remediation**: Represent the offset and selector separately, or use a sufficiently wide immediate representation with bounded shifts.

- [x] **I686-R7-4 — BUG — HIGH**

- **Summary**: Several ModR/M forms select DS where SS is required.
- **Locations**: [decode.c:106](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:106), [h_sse_internal.h:133](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:133).
- **Evidence & Root Cause**: Default-segment selection requires `modrm_mod != 0` before selecting SS. However, `[ESP]` through SIB and 16-bit `[BP+SI]`/`[BP+DI]` use SS with `mod=00`. When DS and SS differ, these instructions access the wrong segment and potentially the wrong memory.
- **Remediation**: Select the default segment from the decoded base register. The decoder already represents displacement-only forms with no base.

- [x] **I686-R7-5 — BUG — HIGH**

- **Summary**: SIMD interpreter and common DBT addressing omit 16-bit effective-address wrapping.
- **Locations**: [h_sse_internal.h:120](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:120), [emit_exit.c:117](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_exit.c:117).
- **Evidence & Root Cause**: Both implementations add complete 32-bit registers without masking the completed offset to sixteen bits. For example, `67 MOV EAX,[BX]` under DBT with `EBX=0x12345678` accesses offset `0x12345678` instead of `0x5678`. SIMD interpreter accesses have the same defect.
- **Remediation**: Apply address-size wrapping before segment-base addition. Reuse the shared EA semantics or decline unsupported DBT forms.

- [x] **I686-R7-6 — BUG — MEDIUM**

- **Summary**: SIMD mandatory-prefix decoding changes incorrectly with CS.D.
- **Locations**: [decode.c:509](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:509), [h_sse.c:562](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:562), [h_sse_int.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:383).
- **Evidence & Root Cause**: The decoder converts `pfx_opsize` into an effective scalar operand-size flag by XORing it with the code-segment default. SIMD handlers also use that field to identify mandatory `66`. In a D=0 segment, unprefixed ADDPS becomes ADDPD, and unprefixed MMX MOVQ becomes an XMM move.
- **Remediation**: Preserve raw mandatory-prefix identity separately from effective scalar operand size.

- [x] **I686-R7-7 — BUG — MEDIUM**

- **Summary**: Illegal LOCK prefixes execute instead of raising #UD.
- **Locations**: [interp.c:305](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:305), [interp.c:432](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:432), [decode.c:635](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:635).
- **Evidence & Root Cause**: Central validation rejects only single shifts and rotates. It does not enforce the opcode tables’ lockability information or require a memory destination. Consequently, forms such as `LOCK MOV`, `LOCK ADD EAX,1`, `LOCK BT`, and `LOCK SHLD` reach ordinary handlers.
- **Remediation**: Validate LOCK legality centrally against the resolved opcode and operand form before any instruction side effect.

- [x] **I686-R7-8 — BUG — HIGH**

- **Summary**: Null and nonexistent selectors become usable segments.
- **Locations**: [seg.c:124](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:124), [seg.c:174](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:174), [seg.c:202](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:202), [seg.c:318](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:318).
- **Evidence & Root Cause**: Selector zero bypasses load validation even for CS/SS. Null data selectors subsequently bypass access checks because they are GDT selectors. Other unrecognized GDT indices are synthesized as flat data descriptors. This suppresses required selector faults and turns invalid selectors into unrestricted flat addressing. Null SS loads and null data-segment accesses must fault. [Intel instruction reference](https://cdrdv2-public.intel.com/868140/253666-089-sdm-vol-2a.pdf).
- **Remediation**: Recognize all null selectors, reject null CS/SS, track unusable data segments, and reject nonexistent GDT entries.

- [x] **I686-R7-9 — BUG — HIGH**

- **Summary**: Segment protection is bypassed by multiple memory paths and DBT eligibility.
- **Locations**: [seg.c:308](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:308), [h_bit.c:78](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_bit.c:78), [h_sse_internal.h:146](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:146), [engine.c:642](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:642).
- **Evidence & Root Cause**: Strings, bit operations, x87/SIMD accesses, and several direct-memory helpers bypass segment-limit validation. The shared check also lacks read/write intent, so it cannot prohibit writes through read-only descriptors. Instruction fetch does not enforce CS limits. DBT eligibility checks only CS, allowing limited or nonflat data segments to execute through unchecked emitted accesses.
- **Remediation**: Centralize segment validation with access kind and full width. Gate DBT on every segment assumption until equivalent checks exist.

- [x] **I686-R7-10 — BUG — HIGH**

- **Summary**: Expand-down segment limits are interpreted as expand-up limits.
- **Locations**: [seg.c:325](/Users/angerman/Projects/zw3rk/i686rt/src/interp/seg.c:325).
- **Evidence & Root Cause**: The expand-down branch requires `(d.type & 0x18u) == 0`, but installed data descriptors include bit `0x10`. Types `0x14`/`0x16` therefore never enter it. Valid offsets above the limit fault, while invalid offsets below it can pass. The unreachable branch also incorrectly allows the limit itself and omits the upper bound and operand extent.
- **Remediation**: Correct type classification and validate the complete access against `(limit, upper_bound]`, with the upper bound derived from B.

- [x] **I686-R7-11 — BUG — HIGH**

- **Summary**: Stack operations ignore SS.B; PUSHF/POPF also ignore SS.base.
- **Locations**: [h_mov.c:360](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_mov.c:360), [h_branch.c:85](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_branch.c:85), [h_flagsops.c:110](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_flagsops.c:110), [emit_mov.c:531](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_mov.c:531).
- **Evidence & Root Cause**: Push/pop/call/return helpers always calculate with full ESP. A sixteen-bit stack therefore uses ESP’s upper half instead of wrapping SP. PUSHF/POPF directly address `guest_ptr(sp)`, omitting SS.base entirely. DBT stack accesses likewise use raw ESP while nonflat SS remains eligible.
- **Remediation**: Separate stack-address size from operand size and use shared SS-aware, limit-checked stack helpers.

- [x] **I686-R7-12 — BUG — MEDIUM**

- **Summary**: Operand-size-overridden ENTER/LEAVE corrupt frame addressing.
- **Locations**: [h_mov.c:477](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_mov.c:477).
- **Evidence & Root Cause**: `66 ENTER` replaces full EBP rather than BP and traverses nested frames using full-width EBP arithmetic. `66 LEAVE` combines old ESP’s upper half with BP, although a 32-bit stack requires `ESP=EBP` before popping BP. With ESP=`0x20001000` and EBP=`0x10002000`, it reads `0x20002000` instead of `0x10002000`.
- **Remediation**: Implement the independent operand-size and stack-address-size rules, preserving upper register halves where required.

- [x] **I686-R7-13 — BUG — HIGH**

- **Summary**: Faulting segment pops and far transfers expose partially committed state.
- **Locations**: [h_seg.c:172](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:172), [h_seg.c:220](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:220), [h_seg.c:267](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:267).
- **Evidence & Root Cause**: POP segment, RETF, and IRET increment ESP before validating the selector. Their synthetic fault returns do not pass through the host-fault ESP rollback. Far CALL commits the new CS/base/default size before faultable stack stores; host recovery does not restore that segment state. Retrying therefore starts with an altered stack or code segment.
- **Remediation**: Validate and stage the complete transfer before committing architectural registers. Preserve the original state on every fault path.

- [x] **I686-R7-14 — BUG — MEDIUM**

- **Summary**: `modify_ldt` readback generates malformed descriptors.
- **Locations**: [ldt.c:212](/Users/angerman/Projects/zw3rk/i686rt/src/os/ldt.c:212).
- **Evidence & Root Cause**: Raw descriptor encoding drops the S bit using `d->type & 0x0f`. The granularity flag is represented as `0x8000` and then truncated into an eight-bit field, losing G. Page-granular byte limits are also emitted without converting back to their encoded twenty-bit limit.
- **Remediation**: Encode the architectural descriptor fields explicitly, including S, G, and the inverse granularity conversion.

- [x] **I686-R7-15 — BUG — HIGH**

- **Summary**: Fault recovery preserves flags from instructions that did not complete.
- **Locations**: [h_alu.c:408](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:408), [emit_alu.c:643](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu.c:643), [h_string.c:186](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_string.c:186), [interp.c:497](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:497).
- **Evidence & Root Cause**: Interpreter ALU operations and DBT immediate shifts publish flags before faultable stores. Recovery restores only selected registers. `STC; ADC [read_only_zero],0` can thus fault with CF already cleared; retrying loses the carry. Repeated comparisons also retain intermediate flags when a later iteration faults, rather than restoring their initial EFLAGS.
- **Remediation**: Commit flags after successful writes. Preserve the complete initial flag state for faulting repeated comparisons while retaining completed index/count progress.

- [x] **I686-R7-16 — BUG — HIGH**

- **Summary**: LODSB/LODSW overwrite all of EAX.
- **Locations**: [h_string.c:241](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_string.c:241), [decode.c:82](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:82).
- **Evidence & Root Cause**: `lods_core()` passes byte counts one or two to `x86_reg_write()`, which expects bit widths eight or sixteen. Both take its full-register assignment path. EAX=`0x12345678` followed by LODSB of `0xAB` becomes `0x000000AB`.
- **Remediation**: Pass `w * 8U` and make width units explicit throughout the string helpers.

- [x] **I686-R7-17 — BUG — HIGH**

- **Summary**: Failed CMPXCHG comparisons bypass destination write protection.
- **Locations**: [h_alu.c:746](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:746), [interp.c:769](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:769).
- **Evidence & Root Cause**: On mismatch, CMPXCHG performs only a load before updating the accumulator and flags. Unaligned CMPXCHG8B has the same omission. A mismatching operation against read-only memory therefore succeeds instead of faulting. The architectural destination write cycle occurs for either comparison outcome. [Intel CMPXCHG reference](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/itanium-architecture-vol-4-manual.pdf).
- **Remediation**: Enforce writable destination semantics on both outcomes, retaining LOCK atomicity and committing registers only after the memory operation succeeds.

- [x] **I686-R7-18 — BUG — MEDIUM**

- **Summary**: XADD with identical register operands loses its sum.
- **Locations**: [h_alu.c:809](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_alu.c:809).
- **Evidence & Root Cause**: The handler writes the destination sum, then overwrites the source with the old destination. When both operands name the same register, the second assignment destroys the result. `XADD EAX,EAX` with EAX=3 leaves 3 rather than 6.
- **Remediation**: Handle register aliasing explicitly or order register assignments so the final destination receives the sum.

- [x] **I686-R7-19 — BUG — HIGH**

- **Summary**: Signal delivery and sigreturn corrupt lazy EFLAGS.
- **Locations**: [signals_i386.c:217](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:217), [signals_i386.c:419](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:419).
- **Evidence & Root Cause**: Signal-frame construction copies `ctx->eflags` without materializing pending arithmetic flags. Sigreturn restores explicit EFLAGS without clearing the handler’s lazy descriptor. The frame can contain stale flags, and the next flag consumer can overwrite restored flags with the handler’s last arithmetic result.
- **Remediation**: Materialize before saving and clear lazy state when restoring explicit architectural flags.

- [x] **I686-R7-20 — BUG — HIGH**

- **Summary**: Successful sigreturn replaces restored EAX with zero.
- **Locations**: [signals_i386.c:417](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:417), [signals_i386.c:705](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:705), [syscalls.c:803](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:803).
- **Evidence & Root Cause**: Sigreturn restores `sc.eax`, but its syscall adapter returns zero. The common syscall completion path then unconditionally assigns that return value to EAX. An interrupted nonzero EAX never survives a successful signal return.
- **Remediation**: Distinguish syscalls that restore the complete register state from ordinary syscall-return assignment.

- [x] **I686-R7-21 — BUG — HIGH**

- **Summary**: Sigreturn restores the x87 status word without restoring TOP.
- **Locations**: [signals_i386.c:443](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:443), [x87.c:95](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:95).
- **Evidence & Root Cause**: FP restoration copies `fstat`, tags, and register contents, but never updates `ctx->x87_top`. Stack-relative accesses use that separate field. A handler that changes TOP therefore leaves subsequent ST(i) references mapped to the wrong restored physical registers.
- **Remediation**: Restore TOP from the saved status word and keep both representations synchronized.

- [x] **I686-R7-22 — BUG — HIGH**

- **Summary**: Several synchronous faults bypass guest signal handlers.
- **Locations**: [interp.c:583](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:583), [engine.c:694](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:694), [engine.c:730](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/engine.c:730).
- **Evidence & Root Cause**: Interpreter decode failures and missing handlers return directly. DBT’s direct TRAP case also returns without delivery, while its interpreter fallback delivers FAULT/TRAP but excludes UNDEF. Consequently, DBT INT3 and UD2 can terminate execution despite installed SIGTRAP/SIGILL handlers.
- **Remediation**: Route all architectural synchronous exits through one delivery path, preserving fault versus trap EIP semantics.

- [x] **I686-R7-23 — BUG — MEDIUM**

- **Summary**: Privileged-instruction behavior incorrectly depends on whether CS is flat.
- **Locations**: [h_seg.c:386](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_seg.c:386).
- **Evidence & Root Cause**: CLI/STI raise a protection fault only for nonflat CS. Under ordinary flat user-mode execution they directly modify IF. HLT advances EIP and returns a diagnostic halt. The runtime models CPL=3, so these paths suppress the required privilege faults for normal user processes.
- **Remediation**: Apply CPL/IOPL privilege rules independently of segment flatness and deliver the appropriate synchronous fault.

- [x] **I686-R7-24 — BUG — HIGH**

- **Summary**: Exact-mode single-precision stores discard negative signs.
- **Locations**: [x87_80_conv.c:582](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:582), [x87_80_conv.c:645](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:645).
- **Evidence & Root Cause**: The shared IEEE conversion helper always places the sign in bit 63. Its float32 caller truncates the result to `uint32_t`, discarding that sign. In `--x87-80`, storing finite −1 through `FSTP m32` produces +1. Negative finite overflow/underflow results also lose their signs.
- **Remediation**: Parameterize the destination sign position or construct the float32 sign before narrowing.

- [x] **I686-R7-25 — DEFECT — HIGH**

- **Summary**: Exact x87 rounding invokes undefined shifts and loses significand carry.
- **Locations**: [x87_80_internal.h:416](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_internal.h:416), [x87_80_internal.h:490](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_internal.h:490).
- **Evidence & Root Cause**: Default precision allows `eff==64`, making `1ULL << eff` undefined. Separately, rounding increments a 64-bit significand before carry detection; `UINT64_MAX+1` wraps to zero. A value rounding upward across a power-of-two boundary therefore loses the carry needed for normalization.
- **Remediation**: Return an explicit carry from significand rounding and handle full-width precision without shifting by 64.

- [x] **I686-R7-26 — DEFECT — HIGH**

- **Summary**: x87 integer stores contain undefined fractional conversions and omit exception status.
- **Locations**: [x87.c:403](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:403), [h_x87_internal.h:428](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:428).
- **Evidence & Root Cause**: For exact-mode 0.5, `drop=63-eff` becomes 64; both mask construction and right shifting are undefined. Smaller fractions produce larger shift counts. The store API also returns only an integer: overflow to a narrow destination and inexact conversion never set IE/PE. For example, FIST of 32768 to m16 writes the indefinite integer without IE.
- **Remediation**: Handle subunit magnitudes before shifting and return conversion status alongside the value, including destination-width overflow.

- [x] **I686-R7-27 — BUG — HIGH**

- **Summary**: FCMOV instructions execute comparisons, sometimes popping the x87 stack.
- **Locations**: [insn_tab_groups.h:142](/Users/angerman/Projects/zw3rk/i686rt/src/x86/insn_tab_groups.h:142), [h_x87_arith.c:277](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_arith.c:277).
- **Evidence & Root Cause**: DA register forms `/0`, `/1`, and `/2` map to FCOM, FUCOM, and FCOMP handlers. Those encodings are FCMOVB, FCMOVE, and FCMOVBE. `DA D1`, for example, compares and pops instead of conditionally copying ST(1) according to EFLAGS. [Intel FCMOVcc reference](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf).
- **Remediation**: Decode and execute the actual conditional moves without comparison or stack-pop side effects.

- [x] **I686-R7-28 — BUG — HIGH**

- **Summary**: FXSAVE/FXRSTOR corrupt x87 stack occupancy.
- **Locations**: [h_x87_math.c:386](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:386), [h_x87_math.c:419](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:419), [x87.c:338](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:338).
- **Evidence & Root Cause**: FXSAVE writes abridged tag bits with reversed polarity: one means empty in this implementation. FXRSTOR reverses them similarly, then calls setters that classify every restored slot and overwrite the restored empty tags. Even an internal save/restore of an empty stack makes its slots nonempty.
- **Remediation**: Correct tag polarity, restore raw register contents, and reconstruct tags while preserving empty slots.

- [x] **I686-R7-29 — BUG — HIGH**

- **Summary**: Legacy x87 environment/state images have incorrect layouts and sizes.
- **Locations**: [h_x87_math.c:352](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:352), [h_x87_math.c:431](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:431).
- **Evidence & Root Cause**: FNSAVE writes status at offset 2 and an abridged tag at offset 4 instead of the legacy environment’s status at 4 and full tag at 8. Other fields and register ordering are also incompatible. Callers omit operand size: `66 FNSTENV` writes 28 rather than 14 bytes; `66 FNSAVE` writes 108 rather than 94. FNSTENV additionally fails to mask exceptions after saving.
- **Remediation**: Implement explicit operand-size-dependent legacy formats, correct tag/register ordering, and the required post-save control-word update.

- [x] **I686-R7-30 — BUG — HIGH**

- **Summary**: Unmasked floating-point exceptions do not produce architectural guest traps.
- **Locations**: [h_sse.c:153](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:153), [x87.c:571](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:571), [h_branch.c:329](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_branch.c:329).
- **Evidence & Root Cause**: SSE helpers set MXCSR status and commit results without testing exception masks. x87 sets ES/B but continues result/stack updates, and WAIT is a no-op. Unmasking divide-by-zero therefore does not cause the required fault and completion suppression.
- **Remediation**: Integrate exception masks into instruction completion. Implement SIMD fault delivery and x87 pending-exception checks, including inhibited stores/pops.

- [x] **I686-R7-31 — BUG — HIGH**

- **Summary**: x87 stack underflow and overflow silently read or overwrite register storage.
- **Locations**: [x87.c:78](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:78), [x87.c:290](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:290).
- **Evidence & Root Cause**: Push decrements TOP without checking the destination tag. Operand reads return values without checking emptiness. Nine FLD1 instructions overwrite a full stack; arithmetic after FNINIT consumes empty-slot storage without the required IE/SF handling or masked indefinite result.
- **Remediation**: Validate stack operands and push destinations before changing state, implementing masked and unmasked stack-fault rules.

- [x] **I686-R7-32 — DEFECT — HIGH**

- **Summary**: Exact x87 rounding modes race between guest threads and can remain stale within one thread.
- **Locations**: [x87_80.c:10](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:10), [h_x87_internal.h:285](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:285), [h_x87_math.c:213](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:213).
- **Evidence & Root Cause**: Softfloat RC/PC reside in mutable process globals. Concurrent guest threads overwrite each other’s arithmetic environment, creating C data races and wrong rounding. Some handlers, including exact FSIN/FCOS/FSCALE, do not refresh that environment after FLDCW.
- **Remediation**: Pass an explicit per-context arithmetic environment through every operation; remove shared mutable mode state.

- [x] **I686-R7-33 — BUG — MEDIUM**

- **Summary**: Exact FRNDINT corrupts large integers and rounds some fractions incorrectly.
- **Locations**: [h_x87_math.c:306](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:306), [x87_80_conv.c:451](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_conv.c:451).
- **Evidence & Root Cause**: FRNDINT converts through signed int64, so an already integral `2^64` becomes the integer-indefinite value. Its converter also rounds every nearest-even value with exponent below zero to zero; 0.75 therefore becomes zero instead of one.
- **Remediation**: Round the extended significand directly, preserving already integral large values and correctly distinguishing half-way cases.

- [x] **I686-R7-34 — BUG — MEDIUM**

- **Summary**: MOVSS/MOVSD memory loads retain stale upper XMM lanes.
- **Locations**: [h_sse.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:383).
- **Evidence & Root Cause**: The handler copies the old destination and overwrites only four or eight bytes. Legacy scalar memory loads must clear the remaining XMM bits; preservation applies to register-source forms. A previous all-ones destination therefore leaves unwanted upper lanes after a scalar load. [Intel MOVSS reference](https://cdrdv2-public.intel.com/835752/253667-sdm-vol-2b.pdf).
- **Remediation**: Zero the destination buffer for scalar memory loads before copying the source.

- [x] **I686-R7-35 — BUG — MEDIUM**

- **Summary**: Packed quadword shifts wrap oversized counts.
- **Locations**: [h_sse_int.c:500](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:500), [h_sse_int.c:528](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:528).
- **Evidence & Root Cause**: PSRLQ/PSLLQ use `imm & 63`. A count of 64 leaves the operand unchanged and 65 shifts by one. Both MMX and XMM forms must produce zero lanes for counts above 63.
- **Remediation**: Check the full immediate before shifting and zero oversized results.

- [x] **I686-R7-36 — BUG — MEDIUM**

- **Summary**: Floating comparison handlers misclassify quiet-NaN exceptions.
- **Locations**: [h_sse_int.c:34](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:34), [h_x87_arith.c:534](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_arith.c:534).
- **Evidence & Root Cause**: SSE compares use `pred<=2` as the signaling set. Equality predicate 0 is quiet, while predicates 5/6 should signal on quiet NaNs. Separately, FUCOMI/FUCOMIP share a helper that sets IE for every unordered result, incorrectly signaling on quiet NaNs.
- **Remediation**: Preserve comparison identity and encode quiet/signaling rules explicitly, with independent signaling-NaN handling.

- [x] **I686-R7-37 — BUG — MEDIUM**

- **Summary**: FXRSTOR clears supported DAZ state and accepts reserved MXCSR bits.
- **Locations**: [h_x87_math.c:408](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:408).
- **Evidence & Root Cause**: MXCSR restoration uses `& 0xffbf`, silently clearing DAZ bit 6 and discarding reserved bits. This conflicts with the runtime’s supported DAZ handling and LDMXCSR validation. A save/restore changes subsequent denormal behavior; an invalid image succeeds instead of faulting.
- **Remediation**: Validate against the supported MXCSR mask before changing any state, then restore all supported bits.

- [x] **I686-R7-38 — BUG — MEDIUM**

- **Summary**: Trigonometric range handling corrupts C2 and stack behavior.
- **Locations**: [x87_80_trig.c:323](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:323), [x87_80_trig.c:411](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:411), [h_x87_math.c:213](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:213).
- **Evidence & Root Cause**: Exact helpers leave the range-result boolean false for finite magnitudes at least `2^63`, returning IE instead. Callers consequently clear C2 or perform FSINCOS/FPTAN pushes despite range failure. Default-mode successful paths also fail to clear previously set C2.
- **Remediation**: Return an explicit range outcome, preserve operands/TOP on range failure, and set or clear C2 on every completion.

- [x] **I686-R7-39 — BUG — MEDIUM**

- **Summary**: Default x87 directed rounding selects the wrong neighboring value.
- **Locations**: [h_x87_internal.h:238](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:238), [h_x87_internal.h:349](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:349).
- **Evidence & Root Cause**: Division passes the residual `a-s*b` as the quotient-error direction without accounting for a negative divisor. Single-precision RC=3 stores step toward the exact value even when the nearest result is already on the toward-zero side: `1+2^-25` becomes `1+2^-23` instead of 1.
- **Remediation**: Correct residual direction using divisor sign; adjust toward-zero conversions only when the rounded magnitude exceeds the exact magnitude.

- [x] **I686-R7-40 — BUG — MEDIUM**

- **Summary**: Exporting binary64 subnormals to extended precision doubles their values.
- **Locations**: [x87.c:190](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:190).
- **Evidence & Root Cause**: Subnormal normalization starts at exponent −1022 while normalizing toward fraction bit 51. It needs −1023. The smallest binary64 subnormal is emitted with exponent −1073 rather than −1074, affecting m80 stores and saved state.
- **Remediation**: Correct the normalization exponent and preserve exact binary64-to-extended conversion.

- [x] **I686-R7-41 — BUG — MEDIUM**

- **Summary**: MMX operations do not establish their architectural x87 alias state.
- **Locations**: [h_sse_internal.h:192](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_internal.h:192), [x87.c:355](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87.c:355).
- **Evidence & Root Cause**: MMX helpers only copy the low 64 bits. They do not mark the x87 tags valid or set the written physical register’s upper sixteen bits appropriately. After FNINIT and MOVD to MM0, the runtime still reports an empty x87 stack.
- **Remediation**: Centralize MMX state transitions and maintain the architectural tag and register-alias representation.

- [x] **I686-R7-42 — BUG — MEDIUM**

- **Summary**: Exact FPREM1 incorrectly returns the dividend for some nonzero nearest quotients.
- **Locations**: [x87_80.c:395](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80.c:395).
- **Evidence & Root Cause**: Shared remainder code returns immediately whenever the dividend exponent is smaller than the divisor exponent. That shortcut works for truncating FPREM but not FPREM1. With dividend 0.75 and divisor 1, FPREM1 should select quotient 1 and remainder −0.25; this returns +0.75.
- **Remediation**: Handle nearest-even quotient selection for exponent difference −1 before taking the shortcut.

- [x] **I686-R7-43 — BUG — MEDIUM**

- **Summary**: Aligned SIMD and FP-state instructions omit required alignment faults.
- **Locations**: [h_sse.c:414](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:414), [h_sse_int.c:383](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:383), [h_x87.c:327](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87.c:327), [emit_sse2.c:404](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:404).
- **Evidence & Root Cause**: MOVAPS/MOVAPD/MOVDQA and FXSAVE/FXRSTOR use ordinary memory accesses without their required alignment checks. Corresponding DBT moves have the same omission. Mapped but misaligned operands therefore succeed rather than raising #GP.
- **Remediation**: Check instruction-specific alignment before any memory or architectural-state side effect.

- [x] **I686-R7-44 — BUG — MEDIUM**

- **Summary**: Default x87 arithmetic sets incorrect exception flags for invalid operands.
- **Locations**: [h_x87_internal.h:187](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:187), [h_x87_internal.h:243](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_internal.h:243).
- **Evidence & Root Cause**: `d_exc()` raises IE when a NaN result originated from a NaN operand, but omits IE for invalid non-NaN combinations such as `0*∞` or `+∞+-∞`. Division sets ZE for `0/0`, and IE/ZE for `∞/0`, misclassifying both cases.
- **Remediation**: Classify operands and exceptional operations explicitly before host arithmetic, distinguishing quiet/signaling NaNs and invalid/divide-by-zero cases.

- [x] **I686-R7-45 — DEFECT — MEDIUM**

- **Summary**: FSCALE and FXTRACT can invoke undefined host integer operations.
- **Locations**: [h_x87_math.c:711](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:711), [h_x87_math.c:736](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_x87_math.c:736).
- **Evidence & Root Cause**: Default FSCALE casts arbitrary `trunc(b)` to `int`; NaN, infinity, and out-of-range finite values are not checked. FXTRACT negates `ilogb(a)` without handling zero or special values; on implementations returning INT_MIN for zero, that negation overflows.
- **Remediation**: Handle special values and architectural exponent ranges before host integer conversion or negation.

- [x] **I686-R7-46 — BUG — MEDIUM**

- **Summary**: Exact FPATAN selects the wrong quadrant for positive infinite X.
- **Locations**: [x87_80_trig.c:464](/Users/angerman/Projects/zw3rk/i686rt/src/interp/x87_80_trig.c:464).
- **Evidence & Root Cause**: When both operands are infinite, the implementation always selects magnitude `3π/4`, ignoring X’s sign. `atan2(+∞,+∞)` therefore returns approximately `3π/4` instead of `π/4`.
- **Remediation**: Select `π/4` versus `3π/4` using X’s sign, then apply Y’s sign.

- [x] **I686-R7-47 — BUG — MEDIUM**

- **Summary**: DBT unsigned MUL uses signed overflow rules.
- **Locations**: [emit_alu_ext2.c:174](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_alu_ext2.c:174).
- **Evidence & Root Cause**: MUL and IMUL choose different widening multiplies but share a comparison against sign-extension of the low product half. Unsigned `0x80000000 * 1` consequently sets CF/OF despite EDX being zero. The sixteen-bit form has the same error.
- **Remediation**: For unsigned MUL, derive CF/OF from whether the upper half is nonzero.

- [x] **I686-R7-48 — BUG — HIGH**

- **Summary**: DBT MMX logical instructions modify XMM registers and overread memory.
- **Locations**: [emit_sse.c:480](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:480), [emit_sse.c:777](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:777).
- **Evidence & Root Cause**: Unprefixed PAND/PANDN/POR/PXOR reach an emitter that always operates on 128-bit XMM slots. `PXOR MM0,MM0` clears XMM0 and leaves MM0 unchanged. Memory forms load sixteen bytes for an eight-byte operand, potentially faulting beyond valid memory.
- **Remediation**: Distinguish MMX from mandatory-66 XMM forms and implement the correct register bank/access width or fall back.

- [x] **I686-R7-49 — BUG — MEDIUM**

- **Summary**: DBT PUNPCKHDQ interleaves the wrong lanes.
- **Locations**: [emit_sse.c:313](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:313).
- **Evidence & Root Cause**: The emitter constructs `{d1,s1,d3,s3}` instead of `{d2,s2,d3,s3}`. Destination `[10,11,12,13]` and source `[20,21,22,23]` produce `[11,21,13,23]`.
- **Remediation**: Select lane 2 for the first pair or emit the corresponding ZIP2 operation.

- [x] **I686-R7-50 — BUG — MEDIUM**

- **Summary**: DBT byte shifts reverse direction and encode incorrect counts.
- **Locations**: [emit_sse2.c:505](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:505), [emit_sse_shared.h:564](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse_shared.h:564).
- **Evidence & Root Cause**: PSRLDQ emits the EXT sequence for a left shift; PSLLDQ emits the right-shift sequence. The encoder additionally starts from `0x6E001800`, which already sets immediate-field bits. OR-ing the requested immediate makes the actual count `imm4|3`.
- **Remediation**: Use an EXT base with a zero immediate field and correct the source ordering/count for each direction.

- [x] **I686-R7-51 — BUG — HIGH**

- **Summary**: DBT floating-point arithmetic and conversions ignore essential MXCSR semantics.
- **Locations**: [emit_sse.c:514](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse.c:514), [emit_sse2.c:352](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:352).
- **Evidence & Root Cause**: Arithmetic guards only FTZ/DAZ and otherwise runs under host FP settings without updating guest exception status. Masked DIVSS by zero does not set guest ZE. Packed conversions directly use A64 saturating conversions, which differ from x86 integer-indefinite results for NaN/overflow; CVTPS2DQ also hardcodes nearest rounding.
- **Remediation**: Implement guest rounding/status/result conversion semantics or decline these paths until they match the interpreter contract.

- [x] **I686-R7-52 — BUG — HIGH**

- **Summary**: vm86 entry ignores supplied ESP, and sixteen-bit writes destroy upper register halves.
- **Locations**: [v86.c:620](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:620), [v86_internal.h:49](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86_internal.h:49).
- **Evidence & Root Cause**: Entry installs the supplied GPRs except ESP, leaving the protected-mode stack register active for vm86 pushes/pops. Separately, `r16_set()` assigns the entire register instead of preserving its upper sixteen bits. Even `MOV AX,imm16` corrupts EAX’s upper half.
- **Remediation**: Install `ks->regs.esp` on entry and preserve upper halves for sixteen-bit register writes.

- [x] **I686-R7-53 — BUG — MEDIUM**

- **Summary**: vm86 effective-address decoding uses incorrect registers and ignores address-size override.
- **Locations**: [v86.c:227](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:227), [v86.c:258](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:258), [v86.c:290](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:290).
- **Evidence & Root Cause**: The base table maps `[DI]` to register 6, SI. BP-based `mod=00` forms incorrectly select DS. Prefix `67` is discarded without recording it, so subsequent memory operands still execute with sixteen-bit decoding despite comments promising rejection.
- **Remediation**: Correct the base/segment tables and preserve address-size state, implementing or explicitly rejecting unsupported addressing forms.

- [x] **I686-R7-54 — BUG — HIGH**

- **Summary**: A vm86 prefix stream can trap the host interpreter in an unbounded loop.
- **Locations**: [v86.c:283](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:283), [v86_internal.h:159](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86_internal.h:159), [v86.c:649](/Users/angerman/Projects/zw3rk/i686rt/src/interp/v86.c:649).
- **Evidence & Root Cause**: Prefix scanning has no byte limit, while fetch wraps IP at sixteen bits. A code segment filled with recognized prefix bytes loops forever inside one `v86_step()`. The outer instruction guard never advances, and pending signals are not checked there.
- **Remediation**: Enforce the instruction-length limit inside fetch/prefix decoding and return the appropriate fault.

- [x] **I686-R7-55 — BUG — MEDIUM**

- **Summary**: Protected-mode decoding does not enforce one consistent fifteen-byte fetch budget.
- **Locations**: [decode.c:478](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:478), [decode.c:223](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:223), [decode.c:637](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:637).
- **Evidence & Root Cause**: Prefix parsing stops after twelve prefixes, while ModR/M, displacement, and immediate reads proceed without a remaining-length budget. Length is rejected only afterward. This both rejects long prefix sequences prematurely and permits overlength instruction decoding to touch bytes beyond the architectural limit before returning an error.
- **Remediation**: Use a checked instruction-stream cursor shared by every fetch, with explicit length-fault handling.

BCD instructions are explicitly excluded by the current decoder; there is no implemented DAA/DAS/AAA/AAS/AAM/AAD algorithm to validate. No style-only findings are included.

---

## 3. `mips32rt` (`691d450`) — 20 Round-7 Findings (`20 / 20` Resolved)

Read all eight files in `src/interp/` end-to-end, plus the CPU, trap, signal-state, and FPU headers and relevant callers. No builds or tests were run; no files were changed. Examples below are derived from static inspection.

- [x] **M32-R7-1 — BUG — HIGH**

- **Summary**: FR=0 double-precision registers do not alias their even/odd word pairs.
- **Locations**: [fpmove.c:104](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:104), [fp.c:62](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:62), [fp.c:716](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:716), [fp.c:876](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:876).
- **Evidence & Root Cause**: Every double occupies one independent `fpr[n]`; `fr_mode` only controls selected parity checks. With FR=0 and initially zero registers, writing `0` to `$f0` and `0x3ff00000` to `$f1` should construct double `1.0`, but double operations read zero from `fpr[0]`. Conversely, `LDC1 $f0` does not update the word read through `$f1`. [QEMU’s FR-aware accessors](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/translate.c) explicitly assemble and split these pairs.
- **Remediation**: Centralize FR-aware word, doubleword, and high-word accessors and use them throughout memory moves, arithmetic, conversions, and state serialization.

- [x] **M32-R7-2 — BUG — HIGH**

- **Summary**: Delay-slot syscalls can lose the branch target or overwrite a signal-handler redirect.
- **Locations**: [interp.c:108](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:108), [interp.c:808](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:808), [fp.c:838](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:838), [syscalls.c:52](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:52).
- **Evidence & Root Cause**: `rt_sigprocmask` always advances PC through `mips_sc_advance_pc_once()`. In an integer branch’s delay slot, this makes `exec_syscall()` return `2`; `exec_branch()` preserves branch-PC+8 instead of taking the branch. Conversely, `fp_bc1()` calls `interp_step()`, which normalizes redirected-syscall completion to zero, then overwrites the redirected PC with its branch destination. A self-signaling syscall can therefore create a handler frame without executing the handler.
- **Remediation**: Preserve distinct outcomes for ordinary completion, syscall completion, and architectural redirection. Record the post-delay-slot destination before entering syscall handling.

- [x] **M32-R7-3 — BUG — HIGH**

- **Summary**: Faulting unaligned merge operations deliver the same fault twice.
- **Locations**: [unaligned.c:36](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/unaligned.c:36), [unaligned.c:54](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/unaligned.c:54), [signals.c:576](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:576).
- **Evidence & Root Cause**: `guest_ld8()` and `guest_st8()` already deliver memory faults. Successful delivery clears `exit_reason` to `NONE`. The merge helpers interpret that state as an undelivered fault and call `mips_fault()` again. One `LWL/LWR/SWL/SWR` fault consequently creates a second frame saving the handler’s PC; `SA_RESETHAND` can turn the second delivery into termination.
- **Remediation**: Propagate the memory helper’s `MIPS_FAULT` without delivering another fault.

- [x] **M32-R7-4 — BUG — MEDIUM**

- **Summary**: Signed MADD/MSUB accumulation invokes C undefined behavior.
- **Locations**: [interp.c:301](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:301), [interp.c:323](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:323).
- **Evidence & Root Cause**: Both instructions add or subtract into an `int64_t` accumulator. `HI:LO=0x7fffffffffffffff`, `rs=rt=1`, followed by `MADD` overflows signed C arithmetic. `MSUB` from `0x8000000000000000` similarly underflows. Architectural accumulation must wrap modulo 2⁶⁴.
- **Remediation**: Keep the accumulator unsigned and convert the signed 32×32 product to `uint64_t` before accumulation.

- [x] **M32-R7-5 — BUG — HIGH**

- **Summary**: SYNC does not enforce memory ordering.
- **Locations**: [interp.c:197](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:197), [mem.c:510](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:510).
- **Evidence & Root Cause**: SYNC immediately returns without a fence. Ordinary accesses do not supply equivalent ordering: loads use ordinary memory reads, and stores before LL activation use plain `memcpy`. The surrounding acquire loads do not provide the required preceding-store-to-following-load ordering. Two threads executing `store; SYNC; load` can therefore admit forbidden store-buffering outcomes on AArch64.
- **Remediation**: Implement the required compiler and host memory barriers, including full ordering for `SYNC 0`.

- [x] **M32-R7-6 — BUG — MEDIUM**

- **Summary**: Alignment exceptions are misclassified as mapping faults.
- **Locations**: [interp.c:538](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:538), [decode.c:65](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/decode.c:65), [fpmove.c:77](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:77), [mem.c:248](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:248).
- **Evidence & Root Cause**: Misaligned LL/SC, instruction fetches, and FP accesses call the generic `mips_fault()`. With default FIXADE enabled, that function always selects SIGSEGV, including for accesses explicitly rejected for alignment. Even with FIXADE disabled, an eight-byte FP access at address `4 mod 8` is classified as SIGSEGV because the classifier checks only two address bits.
- **Remediation**: Pass an explicit alignment/mapping/permission fault cause and access width. Alignment exceptions must not be inferred from FIXADE or address bits alone.

- [x] **M32-R7-7 — BUG — MEDIUM**

- **Summary**: SC with an invalid reservation checks read permission instead of write permission.
- **Locations**: [interp.c:553](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:553), [mem.c:774](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:774).
- **Evidence & Root Cause**: The dead-reservation path calls `guest_ld32()`, bypassing `guest_sc32()`’s write validation. SC against readable, read-only memory returns zero instead of a store-access exception. The [MIPS instruction specification](https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00086-2B-MIPS32BIS-AFP-05.04.pdf) performs store-address translation before testing LLbit.
- **Remediation**: Route every SC through store-access validation, then evaluate reservation success without modifying memory on failure.

- [x] **M32-R7-8 — BUG — MEDIUM**

- **Summary**: Arithmetic traps lose their specific exception cause.
- **Locations**: [interp.c:241](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:241), [fp.c:42](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:42), [mips32rt.h:468](/Users/angerman/Projects/zw3rk/mips32rt/src/mips32rt.h:468), [signals.c:473](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:473).
- **Evidence & Root Cause**: The trap interface carries only signal number and address; signal construction assigns `FPE_FLTINV` to every SIGFPE. Integer overflow and enabled FP divide-by-zero, overflow, underflow, and inexact exceptions consequently reach handlers with incorrect `si_code`. [QEMU’s signal mapping](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/linux-user/mips/cpu_loop.c) preserves these distinctions.
- **Remediation**: Carry the architectural trap cause through delivery and map it to the corresponding Linux `FPE_*` code.

- [x] **M32-R7-9 — BUG — MEDIUM**

- **Summary**: BREAK and register-trap codes are discarded.
- **Locations**: [interp.c:194](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:194), [interp.c:277](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/interp.c:277).
- **Evidence & Root Cause**: These paths always deliver SIGTRAP without examining the instruction’s code field. Linux MIPS uses codes 6 and 7 for arithmetic overflow and division by zero; compiler-generated checks therefore receive the wrong signal. [QEMU’s Linux-compatible handling](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/linux-user/mips/cpu_loop.c) maps them to SIGFPE with `FPE_INTOVF` and `FPE_INTDIV`.
- **Remediation**: Decode and preserve BREAK/TRAP codes, including Linux’s BREAK encoding compatibility handling, before selecting signal and `si_code`.

- [x] **M32-R7-10 — BUG — HIGH**

- **Summary**: FP ADD/SUB discards information required for correct rounding.
- **Locations**: [fp.c:309](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:309).
- **Evidence & Root Cause**: Exponent alignment shifts the smaller mantissa before adding guard/round/sticky positions. Discarded bits become only a Boolean sticky value. Under nearest-even, single-precision `1.0 + 0x33c00000`—an addition of 0.75 ULP—therefore produces `0x3f800000` instead of `0x3f800001`. Subtraction also loses the discarded tail’s direction.
- **Remediation**: Extend mantissas before alignment and preserve guard, round, and sticky information through addition/subtraction and normalization.

- [x] **M32-R7-11 — BUG — HIGH**

- **Summary**: Directed FP overflow returns NaN instead of maximum finite magnitude.
- **Locations**: [fp.c:248](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:248).
- **Evidence & Root Cause**: The finite-saturation branch combines an all-ones exponent with an all-ones fraction. With round-toward-zero, `FLT_MAX * 2` produces `0x7fffffff`, rather than `0x7f7fffff`. The double-precision path has the same error.
- **Remediation**: Use the largest finite exponent, one below the all-ones exponent, when saturation is required.

- [x] **M32-R7-12 — BUG — MEDIUM**

- **Summary**: Extreme underflow bypasses directed rounding.
- **Locations**: [fp.c:212](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:212).
- **Evidence & Root Cause**: When denormalization shifts the retained mantissa to zero, the function returns signed zero immediately despite a nonzero sticky tail. With rounding toward positive infinity, positive minimum-subnormal multiplied by `1/16` must round to positive minimum-subnormal; this path returns zero.
- **Remediation**: Continue through rounding when the retained mantissa is zero but discarded bits are nonzero.

- [x] **M32-R7-13 — BUG — HIGH**

- **Summary**: FP comparisons misorder zero and small finite values.
- **Locations**: [fp.c:86](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:86), [fp.c:525](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:525).
- **Evidence & Root Cause**: Unpacking leaves zero’s exponent at zero. Comparison special-cases only two zero operands; otherwise it compares exponents before mantissas. Thus `C.LT.S(+0,+0.5)` evaluates false, while the reversed comparison evaluates true. The wrong FCC subsequently changes BC1 and conditional-move behavior.
- **Remediation**: Handle either-zero comparisons explicitly, or compare normalized sign/magnitude encodings with signed-zero equivalence.

- [x] **M32-R7-14 — BUG — MEDIUM**

- **Summary**: Invalid unordered comparisons incorrectly force FCC false.
- **Locations**: [fp.c:520](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:520), [fp.c:543](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:543).
- **Evidence & Root Cause**: `invalid` unconditionally assigns `res=0`. For `C.UN.S` on an sNaN with Invalid disabled, the unordered condition must remain true while Invalid is recorded. [QEMU’s comparison helpers](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c) keep condition evaluation separate from exception delivery.
- **Remediation**: Compute the condition independently; suppress FCC writeback only when an enabled exception actually traps.

- [x] **M32-R7-15 — BUG — MEDIUM**

- **Summary**: ROUND/TRUNC/CEIL/FLOOR suppress required Inexact reporting.
- **Locations**: [fp.c:618](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:618), [fp.c:742](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:742).
- **Evidence & Root Cause**: Every explicit-rounding conversion passes `no_inexact=1`. `TRUNC.W.S(1.5)` returns one without Cause.I/Flags.I and does not trap when Enable.I is set. Explicit rounding selects the rounding mode; it does not suppress Inexact. See the [MIPS ROUND.W exception specification](https://www.cs.umd.edu/class/fall2024/cmsc411/resources/MIPS_Vol2.pdf).
- **Remediation**: Remove this suppression and commit Inexact through the normal FP exception path.

- [x] **M32-R7-16 — BUG — MEDIUM**

- **Summary**: Legacy NaN format conversion can produce infinity.
- **Locations**: [fp.c:112](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:112), [fp.c:663](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:663).
- **Evidence & Root Cause**: `CVT.D.S` on legacy sNaN `0x7fc00000` shifts its sole fraction bit into the double signaling-bit position, then `fp_quiet()` clears it. The committed result becomes `0x7ff0000000000000`: infinity. The reverse conversion has the analogous failure.
- **Remediation**: Apply the legacy default-NaN rule, or otherwise ensure quieting cannot eliminate the entire NaN fraction.

- [x] **M32-R7-17 — BUG — MEDIUM**

- **Summary**: NAN2008 integer conversions return legacy invalid-result values.
- **Locations**: [fp.c:569](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:569), [fp.c:742](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:742), [fp.c:762](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:762).
- **Evidence & Root Cause**: Invalid conversions always produce positive signed maximum, ignoring `nan2008`; callers overwrite the helper’s result with that constant again. For NAN2008 `CVT.W.S` of qNaN `0x7fc00000`, the expected Invalid-disabled result is zero, as implemented by [QEMU’s NAN2008 conversions](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c).
- **Remediation**: Implement mode-specific invalid-result rules centrally and preserve the helper’s selected result.

- [x] **M32-R7-18 — BUG — HIGH**

- **Summary**: Valid FP conditional moves raise SIGILL.
- **Locations**: [fp.c:724](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:724).
- **Evidence & Root Cause**: S/D function codes 17, 18, and 19—`MOVF/MOVT`, `MOVZ`, and `MOVN`—have no dispatch cases and fall into the reserved-instruction trap. This happens even when the condition requires leaving the destination unchanged. These are supported pre-R6 instructions in [QEMU’s decoder](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/translate.c).
- **Remediation**: Implement conditional bitwise FPR moves using the selected FCC or GPR condition and FR-aware accessors.

- [x] **M32-R7-19 — BUG — MEDIUM**

- **Summary**: FPU control-register moves omit required FCSR semantics.
- **Locations**: [fpmove.c:162](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fpmove.c:162).
- **Evidence & Root Cause**: CTC1 blindly replaces FCSR and returns. Writing Cause.V plus Enable.V (`0x10800`) therefore fails to raise the pending FP exception. Writes also overwrite mode indicators, while CFC1/CTC1 reject the defined FCCR/FEXR/FENR aliases 25/26/28. [QEMU’s control helpers](https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/fpu_helper.c) implement masks, aliases, and pending-exception detection.
- **Remediation**: Centralize control-register reads/writes with the admitted profile’s writable masks, alias mappings, and immediate exception check.

- [x] **M32-R7-20 — DEFECT — MEDIUM**

- **Summary**: The FPU header assigns incorrect encoding values to W and L formats.
- **Locations**: [emit_fp_priv.h:26](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp_priv.h:26), [emit_fp.c:886](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_fp.c:886), [fp.c:887](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:887).
- **Evidence & Root Cause**: `FP_FMT_W` and `FP_FMT_L` are defined as 18 and 19, although the instruction formats are 20 and 21, correctly recognized by the interpreter. The emitter consequently recognizes reserved format encodings as integer conversions while legitimate conversions miss that dispatch path.
- **Remediation**: Correct the constants and share authoritative format definitions between interpreter and emitter; reserved encodings must remain rejected.

---

## 4. `ppc32rt` (`278f4e8`) — 25 Round-7 Findings (`25 / 25` Resolved)

Read all nine files in `src/interp/` and the relevant CPU, trap, FPU/SPE, and signal-state headers end-to-end. Findings below are static; no builds or tests were run, and no files were changed.

- [x] **P32-R7-1 — BUG — HIGH**

- **Summary**: Failed memory accesses still commit registers, update addresses, and advance NIP.
- **Locations**: [interp.h:474](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:474), [interp.h:554](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:554), [interp.c:572](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:572), [fp_spe.c:29](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:29).
- **Evidence & Root Cause**: Checked `ld*` helpers return zero after recording a fault; `st*` helpers return without writing. Integer handlers do not check that outcome. For example, `lwzu` targeting a mapped `PROT_NONE` page writes zero into RT, updates RA, and advances NIP despite `PPC32_EXIT_FAULT`. Multiple/string operations continue accessing subsequent elements, potentially replacing the original fault address. SPE loads similarly commit fabricated results.
- **Remediation**: Propagate access success explicitly. Stop immediately on failure, preserve faulting NIP, and commit destination/base updates only after successful accesses.

- [x] **P32-R7-2 — BUG — HIGH**

- **Summary**: Instruction-fetch faults are overwritten with undefined-instruction exits.
- **Locations**: [interp.c:43](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:43), [interp.h:286](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:286), [interp.c:750](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:750).
- **Evidence & Root Cause**: A failed `fetch_raw()` records `PPC32_EXIT_FAULT` and returns zero. `interp_step()` nevertheless decodes zero, then overwrites the exit with `PPC32_EXIT_UNDEF`. Consequently, branching into an inaccessible or EOF-trapped page bypasses the driver's normal SIGSEGV/SIGBUS delivery.
- **Remediation**: Return immediately when instruction fetch records a fault; never decode the placeholder value.

- [x] **P32-R7-3 — BUG — HIGH**

- **Summary**: Interpreter instruction fetch bypasses guest execute permissions.
- **Locations**: [interp.h:367](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:367), [vm32_tlb.c:192](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm32_tlb.c:192).
- **Evidence & Root Cause**: `fetch_raw()` uses the ordinary `ld32()` path. The TLB checks only read permission for non-store accesses; no surrounding interpreter check requires guest execute permission. A readable guest buffer lacking `PROT_EXEC` can therefore supply executed instructions. This defeats guest NX enforcement; it does not demonstrate execution outside the host JIT's W^X protections.
- **Remediation**: Add a distinct instruction-fetch access check using guest execute permissions, preserving those permissions separately from host mapping permissions.

- [x] **P32-R7-4 — BUG — HIGH**

- **Summary**: `stwcx.` can succeed after another thread invalidates its reservation.
- **Locations**: [llsc.c:113](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/llsc.c:113), [llsc.c:152](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/llsc.c:152), [interp.h:344](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:344).
- **Evidence & Root Cause**: SC validates the reservation epoch before its compare-exchange. Ordinary stores perform their memory write and epoch increment without taking the LL lock. Thread A can validate a reservation on `x=0`; thread B then completes a same-value `stw x=0` and invalidation; A's CAS subsequently writes `1` and reports success because the value still matches. The atomic epoch does not make validation and conditional storage indivisible.
- **Remediation**: Serialize invalidating writes and reservation updates against the entire SC validation/write operation. Locking only the epoch increment is insufficient.

- [x] **P32-R7-5 — BUG — HIGH**

- **Summary**: Classic floating-point record forms overwrite CR6 instead of CR1.
- **Locations**: [fp.h:228](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:228).
- **Evidence & Root Cause**: `fp_cr1()` inserts FPSCR's top nibble at shift `4`. In this context's CR layout, that is CR6; CR1 requires shift `24`. Thus instructions such as `fadd.` leave CR1 stale and destroy an unrelated condition field.
- **Remediation**: Replace the mask and insertion shift with `24`, preserving every other CR field.

- [x] **P32-R7-6 — BUG — MEDIUM**

- **Summary**: Floating-point addition uses subtraction's infinity-invalid predicate.
- **Locations**: [fp.h:292](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:292), [fp.h:329](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:329), [fp.c:125](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:125).
- **Evidence & Root Cause**: Both helpers classify same-sign infinities as invalid for both addition and subtraction. Consequently, `+∞ + +∞` produces NaN instead of `+∞`. Conversely, `+∞ + −∞` reaches host arithmetic without setting `VXISI`; `fp_end()` does not capture host `FE_INVALID`.
- **Remediation**: Distinguish addition's opposite-sign infinity case from subtraction's same-sign case.

- [x] **P32-R7-7 — BUG — HIGH**

- **Summary**: Enabled invalid-operation and zero-divide exceptions still overwrite the destination.
- **Locations**: [fp.c:40](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:40), [fp.c:65](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:65), [fp.h:371](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:371).
- **Evidence & Root Cause**: Exception handling updates FPSCR but unconditionally reaches `fp_done()`. With `FPSCR.VE=1`, `fsqrt(-1)` overwrites FRT with NaN; enabled zero division similarly commits infinity. These exceptions require destination-update suppression, independently of whether MSR permits exception delivery. [PowerPC programming manual, §3.3.6](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Separate exception recording from result commitment. Apply enable-dependent destination/FPRF suppression and the appropriate guest exception-delivery policy.

- [x] **P32-R7-8 — BUG — HIGH**

- **Summary**: SPE vector floating comparisons produce incorrect results and corrupt neighboring CR fields.
- **Locations**: [fp.h:404](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:404), [fp_spe.c:197](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:197).
- **Evidence & Root Cause**: Scalar comparisons return `0` or `4`, but `fp_fcmp_merge()` treats them as one-bit booleans. Both lanes true produce `0x3c`, after which `fp_set_crf_bleed()` deliberately writes excess bits into the preceding field. From `CR=0`, equal finite lanes compared into CR1 produce `0x3c000000`, rather than `0x0f000000`. The architectural result occupies one nibble. [SPE manual, p. 5-95](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Normalize lane results to `0/1`, construct the four comparison bits, and update only the selected field.

- [x] **P32-R7-9 — BUG — MEDIUM**

- **Summary**: SPE vector sign operations modify only the upper float.
- **Locations**: [fp_spe.c:234](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:234).
- **Evidence & Root Cause**: `evfsabs`, `evfsnabs`, and `evfsneg` share the scalar-double mask path, which changes only bit 63. For `rA=0xbf800000bf800000`, `evfsabs` produces `0x3f800000bf800000`, leaving the lower −1.0 unchanged.
- **Remediation**: Use separate vector-single masks affecting both sign bits, including `0x8000000080000000`.

- [x] **P32-R7-10 — BUG — HIGH**

- **Summary**: Implemented SPE MAC operations lose vector lanes and apply incorrect accumulator semantics.
- **Locations**: [fp_spe.h:117](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:117), [fp_spe.c:306](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:306).
- **Evidence & Root Cause**: The whole-word helper multiplies only low words and returns a zero-extended result. Its `acc` path adds old `rD.low` without updating ACC. For `evmwhsmia`, `rA=rB=0x0001000000010000` and `rD=ACC=0`, it produces `rD=1, ACC=0`; the instruction requires `rD=ACC=0x0000000100000001`. The guarded halfword path also concatenates products where a sign-extended product is required. [SPE manual, pp. 5-140 and 5-185](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Implement the distinct per-lane, accumulator-copy, and guarded-accumulation operations explicitly; replace the incorrect flag-table mappings.

- [x] **P32-R7-11 — BUG — HIGH**

- **Summary**: SPE fractional conversions swap signedness and use the wrong signed scale.
- **Locations**: [fp_spe.c:261](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:261), [fp_spe.h:41](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:41), [fp_spe.h:80](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.h:80).
- **Evidence & Root Cause**: All three conversion tables map `CFUF` to the signed helper and `CFSF` to the unsigned helper. Additionally, signed fractions use `2^32` instead of `2^31`. Thus `efscfsf(0xc0000000)` returns `+0.75` instead of `−0.5`; `efsctsf(+0.25)` returns `0x40000000` instead of `0x20000000`. [SPE manual, §3.2](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Correct both dispatch signedness and scaling across scalar-single, scalar-double, and vector forms.

- [x] **P32-R7-12 — BUG — HIGH**

- **Summary**: SPE float-to-integer saturation permits undefined out-of-range C casts.
- **Locations**: [fp.h:469](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:469), [fp.h:488](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:488).
- **Evidence & Root Cause**: `2147483647.0f` rounds to `2^31`, and `4294967295.0f` rounds to `2^32`. The strict `>` comparisons therefore allow those exact boundary values to reach casts to `int32_t` and `uint32_t`, respectively. Both casts are outside the destination range and invoke undefined behavior.
- **Remediation**: Reject `r >= 0x1p31f` and `r >= 0x1p32f` before casting, returning the required saturated value.

- [x] **P32-R7-13 — DEFECT — HIGH**

- **Summary**: SPEFSCR register access and execution semantics are missing.
- **Locations**: [interp.h:703](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:703), [fp.h:379](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:379), [fp_spe.c:213](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:213).
- **Evidence & Root Cause**: `mfspr`/`mtspr` reject SPR 512. No SPE arithmetic helper reads or updates `ctx->spefscr`; conversions use host rounding and leave guest exception/status bits unchanged. SPEFSCR is user-accessible, as explicitly clarified by the [e500 manual errata, §2.14.1](https://www.nxp.com.cn/docs/en/reference-manual/e500CORERMAD.pdf).
- **Remediation**: Implement SPR 512 access and apply SPEFSCR rounding, status, saturation, and exception controls throughout SPE execution.

- [x] **P32-R7-14 — BUG — MEDIUM**

- **Summary**: SPE halfword-vector loads access beyond their operand.
- **Locations**: [fp_spe.c:29](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:29).
- **Evidence & Root Cause**: `evlwhe[x]`, `evlwhou[x]`, and `evlwhos[x]` read `ld32(ea+2)` and discard its low half. Their operand occupies four bytes, but the implementation accesses six. At `EA=page_end−4`, an inaccessible following page causes a fault despite all operand bytes being available. The common initial check also incorrectly assumes eight-byte width. [SPE manual, p. 5-124](https://www.nxp.com/docs/en/reference-manual/SPEPEM.pdf).
- **Remediation**: Read one word or two halfwords, validate the actual instruction width, and commit only after success.

- [x] **P32-R7-15 — DEFECT — MEDIUM**

- **Summary**: Interpreter instruction admission ignores the selected Classic/SPE profile.
- **Locations**: [fp.c:550](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:550), [fp_spe.c:367](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp_spe.c:367).
- **Evidence & Root Cause**: Neither dispatch path checks `profile` or `is_spe`. Consequently, Classic mode executes `evaddw`, while SPE mode executes Classic FPU instructions such as `lfd` and `fadd`, contrary to the project's declared CPU profiles and `decode.h`'s admission contract.
- **Remediation**: Reject unavailable instruction families before any architectural or memory side effects.

- [x] **P32-R7-16 — BUG — MEDIUM**

- **Summary**: `lswi` preserves stale bytes in its partially filled final register.
- **Locations**: [interp.c:600](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:600).
- **Evidence & Root Cause**: Each destination accumulator starts from `ctx->gpr[reg]`. With `r3=0x11223344`, a one-byte `lswi` loading `0xaa` produces `0xaa223344`; the required result is `0xaa000000`. Unfilled bytes must be cleared. [PowerPC Book I, string loads](https://powerpc.dev/general/PPC_Vers202_Book1_public.pdf).
- **Remediation**: Initialize each destination accumulator to zero before inserting transferred bytes.

- [x] **P32-R7-17 — DEFECT — MEDIUM**

- **Summary**: `lswx` and `stswx` decode successfully but have no interpreter implementation.
- **Locations**: [decode.c:525](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:525), [decode.c:550](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:550), [interp.c:750](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:750).
- **Evidence & Root Cause**: The decoder produces dedicated opcode IDs, but neither has a case in `interp_step()`. Every valid indexed string transfer reaches `PPC32_EXIT_UNDEF`, including zero-count operations. These instructions obtain their byte count from XER. [IBM `lswx` definition](https://www.ibm.com/docs/en/aix/7.1.0?topic=set-lswx-lsx-load-string-word-indexed-instruction).
- **Remediation**: Implement indexed address calculation, XER byte counts, register wrapping, partial-word clearing, and fault handling.

- [x] **P32-R7-18 — BUG — MEDIUM**

- **Summary**: FPSCR writes and exception-summary maintenance violate derived and sticky-bit rules.
- **Locations**: [fp.c:475](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:475), [fp.c:491](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:491), [fp.h:128](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:128).
- **Evidence & Root Cause**: `mtfsb*` and `mtfsfi` directly mutate bits without recomputing summaries. From zero, `mtfsb1 7` sets VXSNAN but omits VX and FX. Conversely, `fp_raise()` reasserts a software-cleared FX during exact arithmetic merely because an old exception bit remains set. [IBM FPSCR bit-setting rules](https://www.ibm.com/docs/en/aix/7.1.0?topic=set-mtfsb1-move-fpscr-bit-1-instruction).
- **Remediation**: Centralize FPSCR mutation with correct derived-field recomputation and event-based sticky-summary updates.

- [x] **P32-R7-19 — BUG — MEDIUM**

- **Summary**: FPSCR.FR does not describe the latest rounding operation.
- **Locations**: [fp.h:234](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:234), [fp.c:395](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:395).
- **Evidence & Root Cause**: Arithmetic deliberately retains FR, and integer conversion updates FI without calculating FR. An exact `fadd(1,1)` leaves a previously set FR intact; nearest-even `fctiw(1.5)` produces `2` without setting FR. FR must reflect the current result's rounding. [PowerPC programming manual, §3.3.5](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Calculate FR alongside FI and clear it for exact operations.

- [x] **P32-R7-20 — BUG — MEDIUM**

- **Summary**: `fctiw[z]` rejects representable rounded results.
- **Locations**: [fp.c:359](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:359).
- **Evidence & Root Cause**: Range checking precedes rounding. `fctiwz(2147483647.25)` and `fctiwz(−2147483648.25)` therefore raise VXCVI, although truncation produces valid signed integers. The conversion model rounds before checking the integer range. [PowerPC programming manual, Appendix D.4.2](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Handle NaNs/infinities, round under the selected mode, then check representability and select valid-inexact versus invalid status.

- [x] **P32-R7-21 — BUG — MEDIUM**

- **Summary**: FMA NaN propagation suppresses a required invalid-multiplication indication.
- **Locations**: [fp.c:204](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:204).
- **Evidence & Root Cause**: The first NaN causes an early return before the zero-times-infinity check. Thus `fmadd` with multiplicands `0` and `+∞` and a quiet-NaN addend never sets VXIMZ. A NaN addend does not eliminate that multiplication exception. [PowerPC programming manual, §4.2.2.2](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Determine applicable multiplication exceptions before completing NaN-result propagation.

- [x] **P32-R7-22 — BUG — MEDIUM**

- **Summary**: Single-precision subnormal results receive normal-number FPRF classifications.
- **Locations**: [fp.h:236](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.h:236), [fp.c:65](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:65).
- **Evidence & Root Cause**: Result classification always uses `fp_fprf64()` after expansion into the double-format FPR representation. Exact `fmuls(2^-126, 0.5)` consequently records `0x04`, because `2^-127` is normal as a double; its single-result classification is `0x14`. [PowerPC programming manual, Table 3-16](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Pass result precision into classification and classify single results before expansion.

- [x] **P32-R7-23 — BUG — MEDIUM**

- **Summary**: Floating comparisons overwrite FPSCR.C.
- **Locations**: [fp.c:337](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:337).
- **Evidence & Root Cause**: `fp_fcmp()` clears all five FPRF bits with `~(0x1f << 12)`, although comparison updates only the four FPCC bits. Starting with C set, `fcmpu(1,1)` incorrectly clears it. The ordered-NaN path additionally forces C to one. [PowerPC programming manual, `fcmpu`/`fcmpo`](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
- **Remediation**: Update only `0xf << 12`; preserve C rather than treating comparison as arithmetic-result classification.

- [x] **P32-R7-24 — DEFECT — MEDIUM**

- **Summary**: Architectural time-base reads are missing or permanently return zero.
- **Locations**: [decode.c:335](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/decode.c:335), [interp.h:707](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:707).
- **Evidence & Root Cause**: Primary-31 dispatch lacks XO 371, the standard `mftb` encoding. Reads routed through `mfspr` for TB/TBU instead return constant zero. Valid timer code therefore encounters an undefined-instruction exit or a clock that never advances. [PowerPC Book II, time-base facility](https://powerpc.dev/general/PPC_Vers202_Book2_public.pdf).
- **Remediation**: Decode the time-base instruction and provide coherent TB/TBU values from a defined guest time-base clock.

- [x] **P32-R7-25 — DEFECT — MEDIUM**

- **Summary**: Integer update-form validation omits prohibited register combinations.
- **Locations**: [interp.h:479](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:479), [interp.h:563](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:563).
- **Evidence & Root Cause**: Update loads reject RA==0 but accept RA==RT. Indexed update stores accept RA==0 by silently disabling writeback. Consequently, `lwzu r3,4(r3)` leaves the address in r3, while `lwzux r3,r3,r4` leaves loaded data. These are invalid forms; this finding concerns the requested validation policy, not a claim that every processor must trap boundedly undefined encodings. [PowerPC Book I](https://powerpc.dev/general/PPC_Vers202_Book1_public.pdf).
- **Remediation**: Before accessing memory, require RA!=0 for every update form and RA!=RT for integer update loads.

---

## 5. `sparc32rt` (`a810f0c`) — 23 Round-7 Findings (`23 / 23` Resolved)

Read every file in `src/interp/` and the relevant CPU, window, trap, and FPU headers end-to-end. Findings below are from static inspection; no builds, tests, or modifications were performed.

- [x] **S32-R7-1 — BUG — HIGH**

- **Summary**: SAVE/RESTORE loses outgoing-register state across window rotations.
- **Locations**: [interp_win.c:143](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:143), lines 143–155, 183–185, 206–209.
- **Evidence & Root Cause**: SAVE replaces `%i*` and `%l*` but leaves the previous window’s `%o*` in place. RESTORE caches only `%l*`/`%i*`. With resident windows: set CWP6 `%o0=0x11`; SAVE to CWP5; set `%o0=0x22`; RESTORE; SAVE again. The interpreter produces `%o0=0x11`, losing CWP5’s `0x22`. The backing representation does not preserve the physical overlap between outgoing and neighboring incoming registers.
- **Remediation**: Model the overlapping register bank explicitly, or synchronize outgoing registers with the neighboring window’s input storage on every rotation.

- [x] **S32-R7-2 — BUG — MEDIUM**

- **Summary**: Modifying `%i6` can make RESTORE spuriously fault or replace resident registers from memory.
- **Locations**: [interp_win.c:182](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_win.c:182), lines 182–204.
- **Evidence & Root Cause**: RESTORE treats a valid target window as missing when its recorded stack address differs from current `%i6`. After two SAVEs, set `%i6=0` and execute `restore %g0,%g0,%g0`. The target window is resident, but the interpreter attempts a fill from address zero. With a mapped replacement address, it instead substitutes memory contents for the resident locals/inputs.
- **Remediation**: Base fills on explicit window validity. An ordinary register change must not implicitly invalidate a resident window.

- [x] **S32-R7-3 — BUG — HIGH**

- **Summary**: A delayed transfer in a delay slot repeatedly executes itself.
- **Locations**: [interp.c:562](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:562), lines 622–633.
- **Evidence & Root Cause**: Before recursively calling `interp_cti(ctx, npc, &dd)`, the outer transfer never updates `ctx->npc`. For `ba T1` followed by non-annulled `ba T2`, the inner call fetches the same second branch as its own delay slot, indefinitely. This prevents return to signal/retirement polling and may exhaust the host stack depending on optimization. Unconditional DCTI couples have defined sequencing. [V8 §5, Table 5-12](https://research.swtch.com/sparcv8.pdf#page=55).
- **Remediation**: Advance architectural PC/nPC before executing the delay instruction; avoid recursive execution of transfers using stale context.

- [x] **S32-R7-4 — BUG — HIGH**

- **Summary**: CALL/Bicc/FBfcc delay-slot faults save the wrong PC/nPC.
- **Locations**: [interp.c:622](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:622), lines 622–643; [interp_signal.c:226](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:226).
- **Evidence & Root Cause**: Only JMPL repairs PC/nPC when delay fetch or execution fails. Other transfers leave PC at the branch and nPC at its delay slot. Signal delivery copies those values directly into the frame. A faulting instruction at `B+4` therefore reports `PC=B`, and its pending branch target is lost. Handler recovery can retry the branch or fail to skip the actual faulting instruction.
- **Remediation**: Record the delay instruction’s PC and already-selected successor before fetching or executing it, for every transfer class.

- [x] **S32-R7-5 — BUG — HIGH**

- **Summary**: Ticc instructions in delay slots become illegal instructions.
- **Locations**: [interp.c:506](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:506), lines 506–547, 635; [interp.c:685](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:685).
- **Evidence & Root Cause**: Ticc is implemented only in the top-level `interp_step()` path. Delay slots go through `interp_single()`, which has no `SPARC32_OP_TRAP` case. Thus a delay-slot `ta 0x10` never invokes its syscall; even a never-taken `tn` produces `EXIT_UNDEF`.
- **Remediation**: Share Ticc execution between ordinary and delay-slot paths, preserving the delay instruction’s architectural PC/nPC.

- [x] **S32-R7-6 — BUG — HIGH**

- **Summary**: Integer division truncates overflowing quotients instead of saturating.
- **Locations**: [interp.c:267](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:267), lines 267–324.
- **Evidence & Root Cause**: UDIV/SDIV cast the full quotient to 32 bits. Their `cc` variants detect overflow but still commit the truncated value and derive N/Z from it. For `Y=1`, `rs1=0`, divisor `1`, UDIV returns zero instead of `0xffffffff`; UDIVcc also sets Z incorrectly. The `INT64_MIN / -1` special case returns negative saturation despite a positive quotient. [V8 B.19](https://research.swtch.com/sparcv8.pdf#page=113).
- **Remediation**: Saturate all four divide forms before committing the result. Derive N/Z from that result and V from overflow.

- [x] **S32-R7-7 — BUG — HIGH**

- **Summary**: MULSCC implements the wrong multiply-step algorithm.
- **Locations**: [interp.c:342](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:342), lines 342–360.
- **Evidence & Root Cause**: The code selects the addend using `N xor V`, adds before shifting, and inserts `Y[0]` into the result’s high bit. The required operation shifts `rs1` with `N xor V`, then conditionally adds using `Y[0]`. With `rs1=0`, operand2=`2`, `Y=1`, and clear ICC, this implementation returns `0x80000000` with Z set instead of `2`. [QEMU’s MULSCC implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Correct the operand selection and operation order; calculate ICC from the actual addition.

- [x] **S32-R7-8 — BUG — MEDIUM**

- **Summary**: UMULcc/SMULcc incorrectly set ICC.V.
- **Locations**: [interp.c:182](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:182), lines 182–193, 257–265.
- **Evidence & Root Cause**: `interp_mulcc()` sets V when the signed product does not fit 32 bits. For example, `0x40000000 * 2` sets V. V8 specifies V=0 for both multiply-with-condition-code forms. The comment’s claimed signed-overflow rule is incorrect. [V8 B.18](https://research.swtch.com/sparcv8.pdf#page=111).
- **Remediation**: Set N/Z from the low product word and clear V/C.

- [x] **S32-R7-9 — BUG — MEDIUM**

- **Summary**: Trapping tagged arithmetic commits ICC before raising the trap.
- **Locations**: [interp.c:332](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:332), lines 332–340.
- **Evidence & Root Cause**: TADDccTV/TSUBccTV call the ICC-mutating helpers before checking arithmetic/tag overflow. A tagged operand such as `1` therefore changes ICC despite trapping. These instructions must preserve both destination and ICC on overflow. [V8 B.14/B.16](https://research.swtch.com/sparcv8.pdf#page=107).
- **Remediation**: Compute prospective result and flags separately; commit them only after the trap checks pass.

- [x] **S32-R7-10 — BUG — HIGH**

- **Summary**: CASA’s immediate-ASI encoding is rejected because the `i` bit check is reversed.
- **Locations**: [decode.c:258](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:258), lines 258–269.
- **Evidence & Root Cause**: The decoder requires `i=1` while interpreting bits 12:5 as an immediate ASI. Immediate-ASI CASA uses `i=0`. LLVM’s LEON encoding example `0xd5e60156` is consequently rejected. Conversely, the decoder accepts the register-ASI form and treats its bits as an immediate. The historical experiment even records disassembly using `%asi`, exposing this confusion. [LLVM LEON CASA encoding](https://reviews.llvm.org/D20098).
- **Remediation**: Accept the immediate-ASI form with `i=0`; reject unsupported register-ASI forms. Correct the encoding constants and associated documentation.

- [x] **S32-R7-11 — BUG — MEDIUM**

- **Summary**: Real STBAR instructions are decoded as privileged ASR reads.
- **Locations**: [decode.h:121](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.h:121), `SPARC32_OP3_STBAR`; [decode.c:184](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:184); [interp.c:380](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:380).
- **Evidence & Root Cause**: STBAR is assigned op3 `0x2c`. Its real encoding is the RDASR form with op3 `0x28`, `rs1=15`, and `rd=0`. Thus `0x8143c000` reaches `interp_rdwr()` and traps because ASR15 is nonzero. [V8 B.30](https://research.swtch.com/sparcv8.pdf#page=134).
- **Remediation**: Recognize STBAR’s special encoding before generic RDASR dispatch; remove the invented op3 assignment.

- [x] **S32-R7-12 — BUG — HIGH**

- **Summary**: Instruction fetch bypasses VM synchronization and authoritative shared permissions.
- **Locations**: [decode.c:405](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:405), lines 405–441; [vm.c:237](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm.c:237).
- **Evidence & Root Cause**: Fetch checks `ctx->regions`, then directly dereferences guest memory without the VM access gate. A sibling can unmap or revoke access between validation and the load, causing a host fault instead of a recoverable guest fault. Region snapshots also become stale: mutations synchronize the caller and root context, not every sibling. A sibling can therefore continue fetching after execute permission is removed while host-readable bytes remain.
- **Remediation**: Hold the VM access gate across fetch validation and copying. Validate against authoritative shared page permissions rather than context snapshots.

- [x] **S32-R7-13 — BUG — MEDIUM**

- **Summary**: Doubleword stores can partially commit across mapping changes.
- **Locations**: [interp.c:478](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:478), lines 478–486; [fp.c:265](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:265); [interp_mem.c:110](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:110).
- **Evidence & Root Cause**: STD validates eight bytes outside the VM gate, then performs two independently gated stores. STDF likewise uses separate stores. A sibling can revoke permissions after the first word, making the second fault after memory has already changed. LDD/LDDF similarly permit their two reads to observe different mappings.
- **Remediation**: Hold one VM access gate across validation and the complete doubleword transfer. Preserve all-or-nothing fault behavior.

- [x] **S32-R7-14 — BUG — MEDIUM**

- **Summary**: Misaligned JMPL targets can be classified as SIGSEGV instead of SIGBUS.
- **Locations**: [interp.c:591](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:591); [interp_signal.c:754](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:754).
- **Evidence & Root Cause**: JMPL detects target misalignment before its delay slot runs. The classifier nevertheless skips every JMPL and derives alignment from the following instruction. A target of `0x1001` with an `ldub` delay slot is classified using width one and produces SIGSEGV.
- **Remediation**: Record the fault’s cause and required alignment directly, distinguishing target-alignment faults from delay-slot memory faults.

- [x] **S32-R7-15 — BUG — HIGH**

- **Summary**: Integer and illegal-instruction traps terminate execution instead of invoking installed guest handlers.
- **Locations**: [interp.c:158](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp.c:158); [interp_signal.c:149](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:149); [main.c:259](/Users/angerman/Projects/zw3rk/sparc32rt/src/main.c:259), lines 259–277.
- **Evidence & Root Cause**: Divide-by-zero and tagged overflow produce `EXIT_TRAP`; illegal instructions produce `EXIT_UNDEF`. The run loop attempts synchronous delivery only for `EXIT_FAULT`, and the delivery helper accepts only SIGBUS/SIGSEGV. An installed SIGFPE or SIGILL handler is therefore bypassed; the translator prints a diagnostic and returns status 1.
- **Remediation**: Map architectural traps to guest signals and `si_code`, preserving fault PC/nPC and invoking the normal synchronous delivery path.

- [x] **S32-R7-16 — BUG — HIGH**

- **Summary**: FSR.TEM never enables floating-point traps.
- **Locations**: [fp_arith.c:85](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:85); [fp.c:103](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:103), lines 103–152.
- **Evidence & Root Cause**: `fp_raise()` always updates current/accrued flags without checking TEM. Callers then commit destination registers or FCC and return success. With DZM enabled, `FDIVS(1.0, 0.0)` stores infinity and continues. Enabled exceptions require a trap before normal result/accrual commit. [QEMU exception handling](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/fop_helper.c).
- **Remediation**: Centralize FP completion: check prospective exceptions against TEM, record FTT/trap state, and suppress normal destination/FCC/accrual updates when trapping.

- [x] **S32-R7-17 — BUG — MEDIUM**

- **Summary**: Valid FDTOS instructions targeting odd single registers decode as illegal.
- **Locations**: [decode.c:45](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:45), lines 45–47, 207–209; [fp.h:63](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.h:63).
- **Evidence & Root Cause**: `fpu_double_dest()` labels opcode `0x0c6` as `FiTOd`. The execution header correctly identifies it as `FDTOS`, whose destination is single precision. Consequently, `fdtos %f0,%f1` is rejected before execution. FITOD is `0x0c8`.
- **Remediation**: Correct the precision classification and use consistent opcode metadata for decoder and executor validation.

- [x] **S32-R7-18 — BUG — MEDIUM**

- **Summary**: LDFSR overwrites read-only state, and successful FP operations retain stale FTT.
- **Locations**: [fp.c:224](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:224); [fp_arith.c:80](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:80).
- **Evidence & Root Cause**: `ctx->fsr = v` accepts every loaded bit, including FTT, QNE, and version state. Subsequent `fp_clear_cexc()` clears only CEXC. A guest can load a nonzero FTT and observe it survive a successful FMOVS. LDFSR must preserve FTT, while successful FPop completion clears it. [V8 FSR definition](https://research.swtch.com/sparcv8.pdf#page=35).
- **Remediation**: Apply an architectural writable-field mask and implement FTT lifecycle in shared FP completion handling.

- [x] **S32-R7-19 — BUG — MEDIUM**

- **Summary**: Quiet comparisons spuriously accrue an invalid-operation exception.
- **Locations**: [fp_arith.c:837](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:837), lines 837–840, 856–859.
- **Evidence & Root Cause**: Both comparison helpers unconditionally set `FP_FSR_NVA_BIT` for unordered operands. Starting with clear FSR, `FCMPS(qNaN, 1.0)` therefore produces `aexc.NV=1` despite `cexc.NV=0`. Quiet FCMP with no signaling NaN must not raise invalid. [V8 Appendix N.4](https://research.swtch.com/sparcv8.pdf#page=292).
- **Remediation**: Accrue NV only when the comparison is signaling or an operand is a signaling NaN.

- [x] **S32-R7-20 — BUG — MEDIUM**

- **Summary**: FSMULD misses invalid-operation handling for zero times infinity.
- **Locations**: [fp.c:153](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:153), lines 153–173.
- **Evidence & Root Cause**: After checking NaN operands, FSMULD performs a native double multiplication without inspecting exceptions. `0.0f * +Infinity` consequently stores a host NaN with CEXC cleared and AEXC unchanged. The ordinary FMULS/FMULD helpers explicitly handle this same invalid case.
- **Remediation**: Detect zero/infinity operands and route the invalid result through the common FP exception-completion path.

- [x] **S32-R7-21 — BUG — MEDIUM**

- **Summary**: FDTOI rejects negative fractional inputs whose truncated integer is representable.
- **Locations**: [fp_arith.c:245](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:245), lines 245–249; [fp.c:191](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:191).
- **Evidence & Root Cause**: The helper rejects values below `-2147483648.0` before applying truncation toward zero. For `-2147483648.5`, the integer result is representable `INT32_MIN`, but the code raises NV instead of NX. Once TEM is implemented, this also selects the wrong trap.
- **Remediation**: Determine representability after the instruction’s rounding operation, using a safe intermediate.

- [x] **S32-R7-22 — BUG — MEDIUM**

- **Summary**: Directed double-to-single conversion can return infinity without overflow flags.
- **Locations**: [fp_arith.c:290](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp_arith.c:290), lines 290–333.
- **Evidence & Root Cause**: Overflow is checked only before directed-rounding adjustment. For input double bits `0x47efffffe0000001` with `RD=RP`, the initial nearest-rounded cast yields maximum finite binary32. `nextafterf()` then changes it to infinity, but the function returns with only NX set. OFC/OFA are missing. The negative/RM case is symmetric.
- **Remediation**: Classify the final directed-rounded result and apply overflow flags after adjustment.

- [x] **S32-R7-23 — DEFECT — MEDIUM**

- **Summary**: FP execution ignores the FPop1/FPop2 encoding distinction.
- **Locations**: [decode.c:201](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/decode.c:201), lines 201–212; [fp.c:71](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:71), lines 71–78.
- **Evidence & Root Cause**: Both instruction groups are passed to an executor that switches solely on `opf`. An FADDS opcode placed under FPop2 therefore performs addition, and an FCMP opcode placed under FPop1 performs comparison. The instruction’s major FP operation group is never validated.
- **Remediation**: Validate the `(op3, opf)` pair against the supported V8 instruction table before reading operands or changing FP state.

---

## 6. `rvrt` (`2b6759c`) — 5 Round-7 Findings (`5 / 5` Resolved)

Found five concrete bugs. This checkout has no `src/interp/`; the interpreter lives in `src/core/`. Reviewed that implementation and related ISA, FP, atomic, CPU-state, and trap paths. No builds or tests ran; no files changed.

- [x] **RV-R7-1 — BUG — HIGH**

- **Summary**: RV32 syscall errors leave noncanonical register values that cause incorrect integer comparisons.
- **Locations**: [runtime_main_syscall_leaf.c:511](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_syscall_leaf.c:511), [runtime_main_syscall.c:673](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_syscall.c:673), [internal.h:26](/Users/angerman/Projects/zw3rk/rvrt/src/core/internal.h:26), [interp.c:128](/Users/angerman/Projects/zw3rk/rvrt/src/core/interp.c:128).
- **Evidence & Root Cause**: This implementation deliberately stores RV32 registers **zero-extended**, but syscall handlers directly write 64-bit negative results. An unknown syscall leaves `a0=0xffffffffffffffda` (`-ENOSYS`); a subsequent `li t0,-38` produces `0x00000000ffffffda` through `rv_put()`. `beq a0,t0,expected` incorrectly falls through because BEQ compares the complete 64-bit containers. Neither syscall completion nor the interpreter entry normalizes the result.
- **Remediation**: Canonicalize RV32 syscall results at the shared retirement boundary, preserving internal restart/error comparisons before normalization. Apply the same register-write convention to other external CPU-state writers.

- [x] **RV-R7-2 — BUG — HIGH**

- **Summary**: The A64 FP path implements `FLT.S/D` as less-than-or-equal and `FLE.S/D` as greater-than.
- **Locations**: [dbt_emit_fp.c:656](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:656), particularly lines 674–679; [dbt_emit_fp.h:198](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.h:198).
- **Evidence & Root Cause**: `FLT` selects condition `0xd` (`LE`), while `FLE` selects `0xc` (`GT`). Consequently, `FLT(1.0,1.0)` returns 1, `FLE(1.0,2.0)` returns 0, and `FLE(2.0,1.0)` returns 1. The subsequent unordered-result mask cannot correct finite comparisons. Both precisions and guest XLENs are affected in the Darwin/fast-Linux DBT. [Arm condition definitions](https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/condition-codes-4-floating-point-comparisons-using-vfp).
- **Remediation**: Use ordered `LO` (`0x3`) for FLT and `LS` (`0x9`) for FLE. Cover less/equal/greater/unordered operands through emitted-code execution.

- [x] **RV-R7-3 — BUG — MEDIUM**

- **Summary**: Valid RV32 `C.FLWSP` instructions targeting `f0` trap as illegal instructions.
- **Locations**: [rv32_expand.c:224](/Users/angerman/Projects/zw3rk/rvrt/src/core/rv32_expand.c:224).
- **Evidence & Root Cause**: The `C.FLWSP` case rejects `rd==0`, incorrectly applying the integer stack-load restriction to a floating-point destination. Encoding `0x6002` means `c.flwsp f0,0(sp)` and must load writable register `f0`; instead, expansion fails and execution raises an illegal-instruction trap. The restriction applies to `C.LWSP`/`C.LDSP`, whereas `C.FLWSP` permits `f0`. [RISC-V compressed-instruction specification](https://docs.riscv.org/reference/isa/v20260120/unpriv/c-st-ext.html).
- **Remediation**: Remove the `rd==0` rejection from `C.FLWSP`, retaining it for integer stack loads. Cover successful loading and NaN-boxing into `f0`.

- [x] **RV-R7-4 — BUG — MEDIUM**

- **Summary**: A memory slow path can turn a malformed single-precision operand from canonical NaN into a finite value.
- **Locations**: [dbt_emit_fp.c:184](/Users/angerman/Projects/zw3rk/rvrt/src/dbt_emit_fp.c:184), [darwin_dbt_emit.c:98](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt_emit.c:98), [darwin_dbt_emit.c:192](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_dbt_emit.c:192).
- **Evidence & Root Cause**: `emit_load_unboxed_s()` substitutes canonical NaN for malformed boxing and caches that substituted value, leaving architectural `f[]` unchanged. After a successful memory-helper call, `emit_reload_caches()` reloads single entries using raw `LDR S`, without validating their upper halves. Starting with `f1=0x000000003f800000`, the sequence `fadd.s f2,f1,f1`; successful first-touch integer load; `fadd.s f3,f1,f1` within one block produces NaN first, then `2.0`. The reload replaces cached NaN with raw `1.0`, violating [NaN-boxing semantics](https://riscv.github.io/riscv-unified-db/manual/html/isa/isa_20240411/chapters/d-st-ext.html).
- **Remediation**: Preserve boxing validation when reconstructing single cache entries. The helper rejoin must satisfy the cache assumptions already embedded in subsequent instructions.

- [x] **RV-R7-5 — BUG — MEDIUM**

- **Summary**: Trap delivery writes an overflowing alternate-stack signal frame before rejecting it.
- **Locations**: [signal.c:775](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.c:775), especially the unconditional frame writes at lines 783–789.
- **Evidence & Root Cause**: For an RV64 nested trap with aligned alternate-stack base `B` and `sp=B+512`, the 1088-byte frame starts at `B-576`. The overflow check sets `valid=false`, but `rv_signal_frame_write()` still writes the frame if the surrounding memory is writable. Only afterward does delivery reject it and force SIGSEGV. RV32 has the same issue with its 944-byte frame. Rejected trap delivery therefore corrupts memory below the alternate stack. Linux checks overflow before writing the frame. [Linux v6.18 RISC-V signal implementation](https://raw.githubusercontent.com/torvalds/linux/v6.18/arch/riscv/kernel/signal.c).
- **Remediation**: Short-circuit frame construction when validation fails, before invoking either frame writer, and retain the existing bad-frame handling.

---

## 7. `loongarch64rt` (`058a318`) — 26 Round-7 Findings (`26 / 26` Resolved)

Read all 13 files in `src/interp/` and the relevant CPU, FP/vector, and trap headers end-to-end. There is no `include/` directory in this checkout. No builds or tests were run; the counterexamples below follow from static analysis.

- [x] **LA64-R7-1 — BUG — HIGH**

- **Summary**: A faulting integer load overwrites the newly installed signal-handler state.
- **Locations**: [interp_mem.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:48), [interp.c:481](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:481), [sigframe.c:262](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:262).
- **Evidence & Root Cause**: `la64_signal_fault()` installs the handler context and returns, despite its header claiming otherwise. `ld_bytes()` then returns zero, which the caller writes into `rd`. A faulting `ld.d a0,...` therefore replaces the handler’s signal-number argument with zero; targeting `sp` destroys its stack pointer. The final PC-change check occurs after this write.
- **Remediation**: Return an explicit fault status and stop instruction execution before destination writeback. Correct the signal helper’s return contract.

- [x] **LA64-R7-2 — BUG — HIGH**

- **Summary**: Atomic memory faults and rejected FP encodings terminate the translator instead of delivering guest signals.
- **Locations**: [interp_amo.c:28](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:28), [interp.c:617](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:617), [interp.c:835](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:835), [interp_mem.h:32](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:32).
- **Evidence & Root Cause**: Atomic helpers return strings for inaccessible memory; `interp_step()` passes them to `die_at()`, which calls `exit(3)`. Illegal FP comparison conditions follow the same path. Guest `SIGSEGV`/`SIGILL` handlers cannot recover, unlike equivalent faults elsewhere in the interpreter.
- **Remediation**: Replace string-only failures with structured guest faults carrying signal, code, address, and faulting PC. Reserve translator termination for internal failures.

- [x] **LA64-R7-3 — BUG — HIGH**

- **Summary**: Floating-point exception enables are ignored.
- **Locations**: [fp_vec_priv.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:48), [fp.c:474](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:474).
- **Evidence & Root Cause**: `fp_sync()` never checks FCSR Enables. With `fcsr0=8`, `FDIV.D(1.0,0.0)` commits infinity and continues. Most scalar callers commit their destination before synchronizing exceptions. [QEMU’s FCSR handling](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/fpu_helper.c) checks Enables and raises FPE before returning a result.
- **Remediation**: Stage results, update Cause, check Enables, and deliver guest `SIGFPE` before destination writeback. Apply the corresponding nontrapping Flags rules.

- [x] **LA64-R7-4 — BUG — HIGH**

- **Summary**: Atomic, scalar-FP, and vector stores bypass shared-file alias propagation.
- **Locations**: [interp_amo.c:45](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:45), [fp_vec.c:54](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:54), [interp_vec.c:109](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_vec.c:109), [fp_shuf.c:136](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_shuf.c:136), [fp_vec_lasx.c:620](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_lasx.c:620).
- **Evidence & Root Cause**: These store paths omit `la64_vm_file_note_store()`, which ordinary integer stores call. For staged `MAP_SHARED` mappings of the same file offset at A and B, an `AMADD.W`, successful `SC.W`, `FST`, or vector store through A leaves B stale. This fails within one thread.
- **Remediation**: Notify the shared-file layer after every successful store, including indexed vector stores, while preserving serialization. Failed CAS/SC operations must not report a write.

- [x] **LA64-R7-5 — BUG — HIGH**

- **Summary**: LL/SC can succeed after an interfering write through another shared-memory alias.
- **Locations**: [interp_amo.c:242](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:242), [interp_amo.c:264](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:264), [clone.c:739](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/clone.c:739), [vm_file_sync.c:200](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:200).
- **Evidence & Root Cause**: SC checks only `ll_valid` and the guest address. Reservation invalidation compares guest-address ranges, while shared-alias propagation changes the backing bytes without invalidating reservations at other addresses. Worker A can LL through one alias, worker B store through another, and worker A subsequently SC successfully over the intervening update. Scheduler turns preserve the reservation.
- **Remediation**: Track reservations by backing-memory identity and invalidate across aliases. Comparing `ll_val` alone would still miss ABA writes.

- [x] **LA64-R7-6 — BUG — HIGH**

- **Summary**: Bounds-checking loads/stores access the wrong address and suppress required traps.
- **Locations**: [interp.c:696](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:696).
- **Evidence & Root Cause**: `LDGT/LDLE/STGT/STLE` compare `rj` with `rk`, but access memory at `rk`. Failed comparisons silently skip stores or copy `rj` into the load destination. These instructions must access `rj` after a successful bounds assertion and raise a bounds exception otherwise. [QEMU’s implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_memory.c.inc) demonstrates both requirements.
- **Remediation**: Perform the bounds assertion first, deliver the appropriate guest fault on failure, and use `rj` as the memory address.

- [x] **LA64-R7-7 — BUG — HIGH**

- **Summary**: Vector float-to-integer conversion permits undefined C casts.
- **Locations**: [fp_vec.c:374](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:374), [fp_vec.c:497](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:497).
- **Evidence & Root Cause**: `vf_cvt_lane()` checks the unrounded value, then casts `rint(x)` to `int32_t`. Under nearest-even rounding, `2147483647.75` passes the check but rounds to `2147483648`, making the cast undefined. Negative boundary values fail similarly under downward rounding. `VFTINT.W.D` and its LASX counterpart reach this code.
- **Remediation**: Round provisionally, validate the rounded value, and only then cast. Generate the architectural invalid-conversion result explicitly.

- [x] **LA64-R7-8 — BUG — HIGH**

- **Summary**: The vector decoder conflates distinct conversion instructions.
- **Locations**: [fp_vec.c:631](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:631), [fp_vec.c:677](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:677).
- **Evidence & Root Cause**: Dispatch uses `k15 >> 2`, discarding distinguishing opcode bits. `VFCVT.H.S` and `VFCVT.S.D` both execute double-to-single conversion; `VFFINT.S.L` and `VFTINT.W.D` both execute double-to-integer conversion. Integer source lanes containing `1` consequently produce zero for `VFFINT.S.L`, rather than floating-point `1.0`. LASX shares this decoder. [QEMU’s encoding table](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/insns.decode) distinguishes these instructions.
- **Remediation**: Match complete conversion opcodes and implement each source width, destination width, and conversion direction separately.

- [x] **LA64-R7-9 — DEFECT — HIGH**

- **Summary**: Advertised LSX/LASX support includes valid instructions that unconditionally terminate execution.
- **Locations**: [interp_mem.h:166](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:166), [fp_vec.c:584](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:584), [fp_vec.c:717](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:717), [fp_shuf.c:169](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_shuf.c:169).
- **Evidence & Root Cause**: CPUCFG advertises both extensions, but vector FMA, vector square root, conversion families, and mode-table `VLDI` forms explicitly return “unhandled” errors. The interpreter converts those errors into `exit(3)`. Programs selecting these instructions from the advertised feature profile fail deterministically.
- **Remediation**: Complete the advertised instruction families. Until then, expose an accurate capability profile and retain proper guest illegal-instruction handling.

- [x] **LA64-R7-10 — BUG — MEDIUM**

- **Summary**: CRC instructions use an oversized accumulator, and CRCC uses the wrong polynomial.
- **Locations**: [interp_bit.h:145](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_bit.h:145), [interp.c:623](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:623).
- **Evidence & Root Cause**: `crc_step()` initializes a 64-bit accumulator from all of `rk`; high bits shift into the checksum. With data zero and seed `0x100000000`, `CRC.W.B.W` produces `0x01000000` instead of zero. CRCC complements the IEEE CRC result instead of using Castagnoli: zero data and zero seed produce `0xffffffff` instead of zero. The [ISA CRC definitions](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html#_crcc_w_bhwd_w) specify a 32-bit seed and separate polynomials.
- **Remediation**: Use a `uint32_t` accumulator and select `0xedb88320` or `0x82f63b78`; remove the CRCC complement.

- [x] **LA64-R7-11 — BUG — MEDIUM**

- **Summary**: Three byte-reversal instructions implement the wrong permutations.
- **Locations**: [interp.c:366](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:366).
- **Evidence & Root Cause**: `REVB.2H` swaps bytes across all four halfwords without sign-extending the low word. `REVB.4H` reverses bytes within words. `REVB.2W` exchanges words. For input `0x1122334455667788`, `REVB.4H` should produce `0x2211443366558877`, and `REVB.2W` should produce `0x4433221188776655`. [QEMU’s reversal helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_bit.c.inc) corroborate the required permutations.
- **Remediation**: Implement each element width explicitly and apply low-word sign extension for `REVB.2H`.

- [x] **LA64-R7-12 — BUG — MEDIUM**

- **Summary**: `MULW.D.WU` treats its first operand as signed.
- **Locations**: [interp.c:203](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:203).
- **Evidence & Root Cause**: The expression converts `rj` through `int32_t`, while only `rk` is zero-extended. With `rj=0xffffffff` and `rk=1`, it returns `0xffffffffffffffff` instead of `0x00000000ffffffff`. Both inputs are unsigned words. [QEMU’s arithmetic dispatch](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_arith.c.inc) zero-extends both.
- **Remediation**: Multiply two `uint64_t` values obtained from `uint32_t` operands.

- [x] **LA64-R7-13 — BUG — MEDIUM**

- **Summary**: Invalid BSTRINS/BSTRPICK ranges execute fabricated operations.
- **Locations**: [decode.c:419](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/decode.c:419), [interp.c:448](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:448).
- **Evidence & Root Cause**: Neither decoding nor execution rejects `msb < lsb`. Unsigned width arithmetic produces zero or wraps to a large value, selecting empty or full-width masks. For example, `msb=0, lsb=2` becomes a full-width operation. [QEMU rejects these encodings](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_bit.c.inc), so the interpreter also violates its oracle contract.
- **Remediation**: Validate the range before computing its width and route rejected encodings through guest `SIGILL`.

- [x] **LA64-R7-14 — BUG — MEDIUM**

- **Summary**: Mandatory instruction-fetch and atomic alignment checks are missing.
- **Locations**: [interp.c:59](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:59), [interp_amo.c:28](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:28).
- **Evidence & Root Cause**: Fetch accepts any mapped four-byte span without checking `pc & 3`. Atomic helpers access bytes individually without checking natural alignment. Thus an unaligned executable PC can execute, and `AMADD.D` at an address ending in `...001` modifies memory successfully. UAL does not waive these alignment requirements. [ISA alignment rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html), [QEMU atomic alignment](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_atomic.c.inc).
- **Remediation**: Check alignment before fetching or committing atomic effects, then deliver the appropriate guest address/alignment fault.

- [x] **LA64-R7-15 — BUG — MEDIUM**

- **Summary**: AM word/doubleword instructions execute forbidden destination/address overlap.
- **Locations**: [interp_amo.c:177](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:177), [interp_amo.c:361](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:361).
- **Evidence & Root Cause**: `amswap.d r4,r5,r4` performs a memory write and replaces `r4`; no overlap validation exists. The [ISA’s AM W/D rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html) require an undefined-instruction exception for this combination. By contrast, `rd==rk` has an architecturally uncertain result and is not itself reported here as a mandatory-trap defect.
- **Remediation**: Reject prohibited `rd==rj` combinations before accessing memory, using instruction-specific restrictions.

- [x] **LA64-R7-16 — BUG — MEDIUM**

- **Summary**: Byte and halfword atomic results are zero-extended.
- **Locations**: [interp_amo.c:141](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:141), [interp_amo.c:167](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_amo.c:167).
- **Evidence & Root Cause**: `am_cas()` and `am_rmw()` explicitly zero-extend B/H old values. An old byte `0x80` returns `0x80` instead of `0xffffffffffffff80`. This affects AMCAS, AMSWAP, and AMADD, including `_DB`. [QEMU’s B/H memory types](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/insn_trans/trans_atomic.c.inc) are signed.
- **Remediation**: Apply `amo_sx_n(old,n)` at every supported width.

- [x] **LA64-R7-17 — BUG — MEDIUM**

- **Summary**: Scalar and vector FP comparisons incorrectly order signed zeros.
- **Locations**: [fp.c:371](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:371), [fp_vec.c:469](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:469).
- **Evidence & Root Cause**: Equality compares raw representations. `-0.0` and `+0.0` therefore enter the sign-order branch, producing unequal and less-than results. This corrupts FCC-controlled branches/FSEL and vector comparison masks. [SoftFloat comparison handling](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) treats both zeros as equal.
- **Remediation**: Recognize two zero magnitudes as equal before sign-based ordering.

- [x] **LA64-R7-18 — BUG — MEDIUM**

- **Summary**: Narrowing vector conversions overwrite unread aliased source lanes.
- **Locations**: [fp_vec.c:480](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:480), [fp_vec.c:530](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:530).
- **Evidence & Root Cause**: Results are written one word at a time while subsequent doubleword sources remain in the destination register. For `vftint.w.d vr0,vr0,vr1`, with `vr0.D={1.0,2.0}` and `vr1.D={3.0,4.0}`, the first two writes destroy the source for result lane 2, yielding `{3,4,0,2}` instead of `{3,4,1,2}`. LASX has the same problem.
- **Remediation**: Snapshot the sources or stage the complete destination before writeback, as [QEMU’s narrowing helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/vec_helper.c) do.

- [x] **LA64-R7-19 — BUG — MEDIUM**

- **Summary**: Vector FCSR Cause records only the last lane.
- **Locations**: [fp_vec.c:418](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:418), [fp_vec.c:529](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:529), [fp_vec_priv.h:62](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:62).
- **Evidence & Root Cause**: Every lane invokes scalar `fp_sync()`, overwriting Cause. A vector division with `0/0` in lane 0 and exact `1/1` operations afterward finishes with Invalid Cause cleared. [QEMU’s vector helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/vec_helper.c) accumulate exceptions across the instruction.
- **Remediation**: Clear Cause once per vector instruction, aggregate lane exceptions, and perform final exception handling before architectural writeback.

- [x] **LA64-R7-20 — BUG — MEDIUM**

- **Summary**: `FSCALEB.S` consumes the wrong exponent width.
- **Locations**: [fp.c:525](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:525).
- **Evidence & Root Cause**: Both widths interpret the exponent as `int64_t`. With value `1.0f` and exponent bits `0xffffffff00000001`, `.S` clamps to `-4096` and produces zero instead of `2.0f`. Its exponent is the signed low word, as implemented by [QEMU’s scalar helper](https://raw.githubusercontent.com/qemu/qemu/master/target/loongarch/tcg/fpu_helper.c).
- **Remediation**: Sign-extend the low 32 bits for `.S`; retain the full signed 64-bit exponent for `.D`.

- [x] **LA64-R7-21 — BUG — MEDIUM**

- **Summary**: FP min/max mishandles NaNs and equal magnitudes.
- **Locations**: [fp.c:53](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:53), [fp_vec.c:322](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec.c:322).
- **Evidence & Root Cause**: The duplicated helpers return the numeric operand for sNaN plus number, spuriously raise Invalid for two qNaNs, and always retain `fj` on magnitude ties. Consequently `FMAXA(-1,+1)` returns `-1`, and `FMINA(+1,-1)` returns `+1`. [SoftFloat min/max semantics](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) distinguish these cases.
- **Remediation**: Implement correct NaN selection/quieting and exception rules; resolve magnitude ties using ordinary signed min/max ordering. Apply the correction to scalar, LSX, and LASX paths.

- [x] **LA64-R7-22 — BUG — MEDIUM**

- **Summary**: `FLOGB` returns signaling NaNs without quieting or Invalid.
- **Locations**: [fp.c:124](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:124), [fp.c:146](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:146).
- **Evidence & Root Cause**: Both NaN branches return the input directly. For `.D` input `0x7ff0000000000001`, the signaling representation survives and no Invalid exception is raised. This contradicts the [ISA NaN-propagation rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html).
- **Remediation**: Classify NaNs by bits, raise Invalid for sNaNs, and quiet the selected NaN while preserving its payload.

- [x] **LA64-R7-23 — BUG — MEDIUM**

- **Summary**: `FRSQRTE.S/D` discards floating-point exception status.
- **Locations**: [fp.c:624](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:624), [fp.c:718](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:718).
- **Evidence & Root Cause**: The major-9 group sets `sync=0`, including its arithmetic estimate cases. `FRSQRTE(+0)` produces infinity without recording Divide-by-zero; negative inputs lose Invalid. The [ISA estimate rules](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html) retain these special-input exceptions.
- **Remediation**: Enable exception synchronization for the estimate cases while retaining no-status-update behavior for register moves.

- [x] **LA64-R7-24 — BUG — MEDIUM**

- **Summary**: Invalid scalar FP-to-word conversions can also report spurious Inexact.
- **Locations**: [fp.c:243](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:243).
- **Evidence & Root Cause**: `fp_ftint_wd()` calls `rint()` before checking range. For nearest-even `FTINT.W.D(2147483647.5)`, rounding raises Inexact, then the range check adds Invalid without removing that provisional exception. The conversion reports `V|I`; [SoftFloat’s conversion rules](https://raw.githubusercontent.com/qemu/qemu/master/fpu/softfloat-parts.c.inc) report Invalid for this overflow.
- **Remediation**: Compute conversion status independently of intermediate host arithmetic, suppressing provisional Inexact when conversion is invalid.

- [x] **LA64-R7-25 — BUG — MEDIUM**

- **Summary**: Negated fused operations negate after rounding and alter propagated NaN signs.
- **Locations**: [fp.c:403](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp.c:403).
- **Evidence & Root Cause**: FNMADD/FNMSUB compute `fma()` and then negate its rounded result. Under upward rounding, `FNMADD.D(1,1,2^-53)` returns `-(1+2^-52)` instead of `-1`. [QEMU’s LoongArch mapping](https://raw.githubusercontent.com/qemu/qemu/v10.0.0/target/loongarch/tcg/insn_trans/trans_farith.c.inc) requests pre-round result negation in [SoftFloat](https://raw.githubusercontent.com/qemu/qemu/v10.0.0/fpu/softfloat-parts.c.inc). The explicit operand/result negations also flip selected NaN signs.
- **Remediation**: Apply numerical negation before final rounding, preserving directed-rounding semantics. Handle NaN propagation before numerical sign transformations.

- [x] **LA64-R7-26 — BUG — MEDIUM**

- **Summary**: Nonzero SYSCALL code fields terminate execution.
- **Locations**: [interp.c:651](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp.c:651).
- **Evidence & Root Cause**: Any nonzero immediate reaches `die_at()` instead of syscall dispatch. The [ISA defines SYSCALL as unconditional](https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html); its code field does not make the instruction invalid. The existing Linux dispatch already obtains the syscall number from `a7`.
- **Remediation**: Accept the code field and dispatch through the guest syscall ABI instead of terminating the translator.

---

## 8. `ppc64rt` (`bda02bd`) — 30 Round-7 Findings (`30 / 30` Resolved)

Completed the static review of all 13 files in `src/interp/` and the related CPU/FPU/VMX/VSX/trap headers. There is no `include/` directory in this checkout. No builds or tests were run; the counterexamples below come from static analysis.

- [x] **P64-R7-1 — BUG — HIGH**

- **Summary**: `darn` returns a predictable sequence as successful random output.
- **Locations**: [interp.c:29](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:29), [interp.c:458](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:458), [profile.h:77](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/profile.h:77).
- **Evidence & Root Cause**: The implementation uses xorshift with a public constant seed, restored by `ppc64_interp_reset()`. It returns this sequence without indicating failure while advertising DARN support. Guest software using DARN for entropy can therefore generate predictable secrets. QEMU instead obtains guest random bytes and returns the architectural failure value when that fails. [QEMU DARN implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/int_helper.c).
- **Remediation**: Use the host’s established cryptographic random interface, implement the DARN forms and failure sentinel correctly, and remove the fixed-seed generator from this instruction.

- [x] **P64-R7-2 — BUG — HIGH**

- **Summary**: Quadword reservation operations bypass the atomic backend and can succeed after intervening writes.
- **Locations**: [vec.c:116](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:116), [vec.c:151](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:151), [atomic.h:23](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/atomic.h:23), [fp_str.c:33](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:33).
- **Evidence & Root Cause**: Both atomic-backend branches require `w <= 8`. Thus `lqarx` performs an ordinary read and records a local Boolean reservation; `stqcx.` consumes that Boolean, releases its lock, and performs an ordinary write. It neither atomically checks memory nor validates a shared write epoch. A sequence `lqarx; stxv` to the same address; `stqcx.` can report success because `str_write()` bypasses the interpreter reservation invalidator. Concurrent writes can also occur between reservation checking and committing.
- **Remediation**: Extend the shared atomic interface to 128-bit values and make reservation validation plus conditional commit atomic. Route every relevant store through the same reservation authority.

- [x] **P64-R7-3 — BUG — HIGH**

- **Summary**: Load-reserve invalidates the wrong Soft-TLB entry for three quarters of the table.
- **Locations**: [vec.c:112](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:112), [cpu.h:38](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:38), [vm64.c:506](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm64.c:506).
- **Evidence & Root Cause**: The reservation path indexes with `(ea >> 12) & 1023`, but the shared TLB contains 4096 entries and uses a 4095 mask. For `EA = 0x400000`, the live entry is 1024 while this code clears entry 0. A previously warmed writable entry remains usable by DBT stores, bypassing reservation epoch updates. An intervening A→B→A write sequence can consequently leave a later store-conditional reporting success.
- **Remediation**: Derive the index from `PPC64_TLB_SIZE` and ensure reservation establishment revokes every applicable writable fast path.

- [x] **P64-R7-4 — BUG — HIGH**

- **Summary**: `lqarx` and `stqcx.` reverse the architectural GPR-pair order in little-endian mode.
- **Locations**: [vec.c:134](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:134), [vec.c:180](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:180).
- **Evidence & Root Cause**: The code assigns the doubleword at `EA` to `RT`, and `EA+8` to `RT+1`, then stores using the same order. These instructions place the high half in the even register and the low half in its successor, including little-endian execution. Memory containing low half `1`, high half `2` therefore produces `{RT=1, RT+1=2}` instead of `{2,1}`. [QEMU quadword reservation implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Correct the register-to-memory half mapping independently of the atomicity repair.

- [x] **P64-R7-5 — BUG — HIGH**

- **Summary**: `dcbt` executes as a byte-reversed halfword load and can corrupt a GPR or fault.
- **Locations**: [interp.h:634](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:634), [interp.c:499](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:499), [interp.c:526](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:526).
- **Evidence & Root Cause**: The memory table assigns XO 278 to the halfword reverse-load operation. XO 278 is `dcbt`; the table executes before the cache-hint handler. Consequently, ordinary `dcbt` reads memory and overwrites the GPR selected by its TH field, commonly GPR0. The reverse-halfword entries use 278/406 instead of the architectural 790/918, also leaving real `lhbrx`/`sthbrx` unsupported. [IBM opcode reference](https://www.ibm.com/docs/en/aix/7.3.0?topic=reference-appendix-b-instruction-set-sorted-by-mnemonic).
- **Remediation**: Correct both reverse-halfword opcodes and verify that cache-hint encodings cannot enter memory-transfer dispatch.

- [x] **P64-R7-6 — BUG — HIGH**

- **Summary**: VSX XX3 instructions interchange the XA and XB register-extension bits.
- **Locations**: [fp_vsx.c:24](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:24), [fp_vsx.c:36](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:36).
- **Evidence & Root Cause**: `ax` comes from raw bit 1 and `bx` from bit 2; XA requires bit 2 and XB bit 1. For example, `xxlor vs0,vs1,vs34` reads `vs33` and `vs2`. Logical operations, merges, and permutations using sources from different VSR banks silently consume unrelated registers. [QEMU XX-form field definitions](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/insn32.decode).
- **Remediation**: Correct the extension-bit extraction and share it across XX3 handlers.

- [x] **P64-R7-7 — DEFECT — HIGH**

- **Summary**: Required scalar and vector VSX floating-point arithmetic has no interpreter implementation.
- **Locations**: [fp_vsx.c:21](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_vsx.c:21), [interp.c:329](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:329), [SPEC.md:56](/Users/angerman/Projects/zw3rk/ppc64rt/SPEC.md:56).
- **Evidence & Root Cause**: The PO60 executor handles logical operations, permutations, merges, splats, comparisons, and sign operations, then declines everything else. Instructions explicitly required by SPEC §2.2—including `xsadddp`, `xssubdp`, `xsmuldp`, `xsdivdp`, and the listed vector arithmetic families—reach the illegal-instruction path. For example, neither XSADDDP’s XO8 32 nor XVADDDP’s XO8 96 has an execution case.
- **Remediation**: Implement the promised arithmetic families in the reference interpreter, including FPSCR effects and VSR overlap semantics.

- [x] **P64-R7-8 — BUG — MEDIUM**

- **Summary**: Register-controlled shifts wrap oversized counts instead of producing the required zero or sign-filled result.
- **Locations**: [interp.h:566](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:566), [interp.h:576](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:576), [interp.h:602](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:602).
- **Evidence & Root Cause**: Word logical shifts reduce the actual shift to `n & 31`; doubleword shifts discard count bit 6. Arithmetic shifts similarly discard their oversized-count indicator. Thus `slw(1,32)` and `sld(1,64)` return `1` instead of `0`. Negative `sraw`/`srad` operands shifted by 32/64 retain their original value and clear carry instead of sign-filling. The `n < 64` checks cannot reject counts already masked below 64.
- **Remediation**: Decode six count bits for word operations and seven for doubleword operations, then handle oversized counts explicitly before performing C shifts.

- [x] **P64-R7-9 — BUG — MEDIUM**

- **Summary**: `srad` and `sradi` compute CA32 differently from the required CA result.
- **Locations**: [interp.h:580](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:580).
- **Evidence & Root Cause**: CA examines all discarded bits, while CA32 examines only discarded bits from the low word. With `RS=0x8000000100000000` and shift 40, the implementation sets CA but clears CA32. These instructions copy the same carry result into both fields. [QEMU arithmetic-shift implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Calculate the architectural carry once and assign it to both CA and CA32.

- [x] **P64-R7-10 — BUG — MEDIUM**

- **Summary**: `subfo` ignores OE and leaves overflow state unchanged.
- **Locations**: [interp.c:605](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:605).
- **Evidence & Root Cause**: The `subf` case computes `y - x` and exits without invoking overflow handling, although the surrounding dispatcher decoded OE. With RA=`1`, RB=`INT64_MIN`, and clear XER, `subfo` returns `INT64_MAX` without setting OV/SO. Non-overflowing operations also fail to clear previous overflow state; the record form consequently copies stale SO into CR0.
- **Remediation**: Apply the subtraction overflow calculation when OE is set, including OV32 and sticky SO, while preserving carry fields.

- [x] **P64-R7-11 — BUG — MEDIUM**

- **Summary**: Overflow-enabled integer division clears overflow on division by zero.
- **Locations**: [interp.h:395](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:395).
- **Evidence & Root Cause**: Both zero-divisor branches assign a quotient but leave `ov=false`. The final OE handler therefore clears OV and OV32 instead of setting overflow and sticky SO. This affects signed and unsigned word and doubleword division. The defect concerns defined exception flags, independently of the quotient chosen for this exceptional case. [QEMU division implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Include a zero divisor in the overflow predicate for every divide variant.

- [x] **P64-R7-12 — DEFECT — MEDIUM**

- **Summary**: `addex` is decoded but never executed.
- **Locations**: [decode.c:495](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:495), [decode.h:52](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.h:52), [interp.c:589](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:589).
- **Evidence & Root Cause**: The decoder recognizes ADDEX, but no interpreter dispatch case implements it. Valid CY=0 instructions reach the illegal-instruction path. The header’s description also incorrectly identifies CA32 as its carry input; ADDEX uses the OV/OV32 carry chain. [QEMU ADDEX implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Implement the supported CY semantics and correct the instruction metadata, keeping ADDEX’s carry chain distinct from ordinary CA arithmetic.

- [x] **P64-R7-13 — BUG — MEDIUM**

- **Summary**: `prtyw` discards the upper word’s parity result.
- **Locations**: [vec.c:294](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:294), [interp.h:505](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.h:505).
- **Evidence & Root Cause**: `prtyw` calls `interp_prty64(s,4)`, examining only the low four bytes and returning one bit. It must produce separate parity results for both words. With `RS=0x0000000100000000`, the expected result has bit 32 set, but this implementation returns zero. [QEMU parity implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Calculate both word parities and place them in bits 0 and 32.

- [x] **P64-R7-14 — BUG — MEDIUM**

- **Summary**: `setnbc` implements inverted Boolean semantics instead of negative Boolean semantics.
- **Locations**: [power10.h:57](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/power10.h:57).
- **Evidence & Root Cause**: XO 448 is grouped with `setbcr` as an inversion. Consequently, a clear CR bit returns `1`, and a set bit returns `0`. `setnbc` must return `0` or all ones, respectively. The misleading comment reinforces the same mistake. [QEMU Boolean-condition implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/ppc/translate/fixedpoint-impl.c.inc).
- **Remediation**: Separate Boolean reversal from arithmetic negation and implement each mnemonic’s result independently.

- [x] **P64-R7-15 — BUG — MEDIUM**

- **Summary**: CR logical instructions disagree between decoding and execution.
- **Locations**: [decode.c:131](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:131), [interp.c:157](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:157).
- **Evidence & Root Cause**: The decoder recognizes `crnor` at XO 33, but the interpreter omits it, so valid `crnor` and the common `crnot` alias trap. Separately, the decoder identifies XO 321 as `crorc`, while the executor correctly uses XO 417. This rejects the valid encoding during decoding and misclassifies a different encoding. [IBM opcode reference](https://www.ibm.com/docs/en/aix/7.3.0?topic=reference-appendix-b-instruction-set-sorted-by-mnemonic).
- **Remediation**: Add CRNOR execution and correct CRORC’s decode entry. Keep the accepted encoding set consistent across both paths.

- [x] **P64-R7-16 — BUG — MEDIUM**

- **Summary**: Prefixed execution bypasses prefix-format and reserved-bit validation.
- **Locations**: [interp.c:313](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:313), [prefix.c:58](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:58), [decode.c:626](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:626).
- **Evidence & Root Cause**: Eight-byte instructions enter `ppc64_exec_prefixed()` directly. That executor dispatches primarily by suffix opcode without applying the decoder’s prefix-form and reserved-bit checks. For example, prefix `0x04000000` followed by `0x38600001` executes as `paddi r3,0,1`, although PADDI requires the MLS prefix form. Prefix `0x06040000` likewise executes despite a reserved bit rejected by `decode_prefixed()`.
- **Remediation**: Validate the complete instruction pair before any state or memory effect, using one authoritative encoding validator that also covers supported prefixed splats.

- [x] **P64-R7-17 — DEFECT — MEDIUM**

- **Summary**: Valid prefixed scalar VSX transfers are decoded but missing from execution.
- **Locations**: [decode.c:644](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:644), [prefix.c:110](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:110), [prefix.c:199](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:199).
- **Evidence & Root Cause**: The decoder accepts PLXSSP, PSTXSD, and PSTXSSP at suffix primary opcodes 43, 46, and 47. None appears in the executor’s transfer cases. Valid pairs such as `04000000 AC200000`, `04000000 B8200000`, and `04000000 BC200000` therefore trap instead of transferring data.
- **Remediation**: Implement these forms with the correct VSR bank, single-precision conversion, displacement, and fault behavior.

- [x] **P64-R7-18 — BUG — MEDIUM**

- **Summary**: Prefixed instructions crossing a 64-byte boundary do not raise the required alignment exception.
- **Locations**: [interp.c:54](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:54).
- **Evidence & Root Cause**: Fetch checks only four-byte alignment and unconditionally fetches the suffix. A prefix at `PC % 64 == 60` therefore executes when both words are readable. At a page boundary it can instead report a suffix access fault. Power ISA requires an alignment exception for this placement before fetching the suffix. [QEMU implementation referencing ISA §1.9](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Detect the forbidden boundary immediately after recognizing a prefix, report the alignment trap at the prefix PC, and reconcile any contrary cross-page expectations in the project specification.

- [x] **P64-R7-19 — BUG — MEDIUM**

- **Summary**: Invalid update-form loads and stores modify architectural state before reporting illegal instruction.
- **Locations**: [interp.c:258](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:258).
- **Evidence & Root Cause**: `mem_access()` performs the memory transfer and writes the load destination before checking `RA==0` or update-load `RA==RT`. Thus `lwzu r3,0(r3)` can overwrite r3 and then trap; an update store with RA zero can modify memory before trapping. Inaccessible addresses also produce an access fault before the invalid operands are recognized.
- **Remediation**: Validate update-form operands before callbacks, destination writes, or reservation invalidation.

- [x] **P64-R7-20 — BUG — MEDIUM**

- **Summary**: `lqarx` accepts prohibited destination/address-register overlaps.
- **Locations**: [vec.c:102](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:102).
- **Evidence & Root Cause**: Validation checks only that RT is even. It omits the restrictions against RT equaling RA or RB, so prohibited forms perform the load, overwrite registers, and establish a reservation. The independent implementation rejects these overlaps before memory access. [QEMU LQARX validation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/translate.c).
- **Remediation**: Enforce all LQARX register restrictions before calculating or accessing memory.

- [x] **P64-R7-21 — BUG — MEDIUM**

- **Summary**: `mtvsrdd` reads GPR0 when RA zero requires a literal zero.
- **Locations**: [fp.c:514](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:514), [vec.c:362](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:362).
- **Evidence & Root Cause**: Both implementations assign `cpu->gpr[ra]` to the high VSR half unconditionally. With RA=0 and nonzero GPR0, they inject that value instead of zero. This violates MTVSRDD’s special RA-zero rule. [Power ISA v3.0C, MTVSRDD](https://ftp.libre-soc.org/PowerISA_public.v3.0C.pdf#page=135).
- **Remediation**: Apply the literal-zero rule in both paths, preferably through a shared implementation.

- [x] **P64-R7-22 — BUG — MEDIUM**

- **Summary**: VSX word transfers reject the extension bit needed to access VSR32–63.
- **Locations**: [fp.c:522](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:522), [vec.c:375](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:375).
- **Evidence & Root Cause**: `mtvsrwa` treats raw bit 0 as forbidden Rc, despite calculating a TX-extended register index. `mfvsrwz` and `mtvsrwz` likewise reject that bit and use only the five-bit register number. Valid transfers involving VSR32–63 consequently trap. Bit 0 is the VSR extension for these instructions. [Power ISA v3.0C, register-transfer instructions](https://ftp.libre-soc.org/PowerISA_public.v3.0C.pdf#page=133).
- **Remediation**: Decode TX instead of Rc and use the complete six-bit VSR index consistently.

- [x] **P64-R7-23 — BUG — MEDIUM**

- **Summary**: `vsumsws` adds the wrong word from VB.
- **Locations**: [fp_str.c:851](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:851).
- **Evidence & Root Cause**: The accumulator reads `pack_get(blo,bhi,3,32)`, selecting the highest numerical word. VSUMSWS adds architectural VB bits 96–127, which correspond to the lowest word in this representation. With VA zero, VB low word `1`, and VB high word `2`, the implementation produces `2` instead of `1`. [AltiVec instruction reference](https://www.nxp.com/docs/en/reference-manual/ALTIVECPEM.pdf#page=278).
- **Remediation**: Read VB through the lane index corresponding to architectural word 3—index zero in these little-endian packing helpers.

- [x] **P64-R7-24 — BUG — MEDIUM**

- **Summary**: VMX saturation status and VSCR access are unimplemented.
- **Locations**: [fp_str.c:782](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:782), [fp_str.c:851](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_str.c:851), [cpu.h:62](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:62), [SPEC.md:57](/Users/angerman/Projects/zw3rk/ppc64rt/SPEC.md:57).
- **Evidence & Root Cause**: `vaddubs`, `vsububs`, and `vsumsws` clamp results but never set `cpu->vscr`. For example, unsigned byte `255+1` yields 255 while leaving SAT clear. No interpreter implementation reads or writes VSCR, and the explicitly required `mfvscr`/`mtvscr` instructions are absent. Saturation must set the sticky SAT state. [AltiVec programming reference](https://www.nxp.com/docs/en/reference-manual/ALTIVECPOWERISAPEM.pdf).
- **Remediation**: Implement VSCR transfers and set sticky SAT whenever any affected lane saturates, preserving unrelated VSCR fields.

- [x] **P64-R7-25 — BUG — MEDIUM**

- **Summary**: `fcfid` ignores guest rounding and required FPSCR updates.
- **Locations**: [fp.c:421](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:421).
- **Evidence & Root Cause**: Conversion is a bare `(double)s` without installing FPSCR[RN] or recording rounding/classification flags. Under round-toward-positive-infinity, integer `2^53+1` should become `2^53+2`; with the normal host nearest mode it becomes `2^53`. Inexact and result-status fields remain stale, and the record form copies stale FPSCR status into CR1. [IBM assembler reference](https://www.ibm.com/docs/ssw_aix_71/assembler/assembler_pdf.pdf).
- **Remediation**: Perform conversion under guest rounding semantics and update all defined FPSCR fields before applying Rc.

- [x] **P64-R7-26 — BUG — MEDIUM**

- **Summary**: `fcmpu` and `xscmpudp` update CR but leave FPSCR comparison and exception state stale.
- **Locations**: [fp.c:331](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp.c:331), [power10.h:122](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/power10.h:122).
- **Evidence & Root Cause**: Both handlers call the value-only `fp_cmpu()` helper and write only the selected CR field. Neither updates FPSCR[FPCC], and signaling NaNs do not set VXSNAN and its summaries. Even an ordinary finite comparison leaves a previous FPCC result observable through `mffs`. [QEMU floating-point comparison implementation](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/fpu_helper.c).
- **Remediation**: Use a stateful comparison helper that distinguishes signaling NaNs and updates CR and FPSCR together.

- [x] **P64-R7-27 — BUG — MEDIUM**

- **Summary**: Single-precision overflow is missed when directed rounding produces the largest finite value.
- **Locations**: [fp_single.c:159](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:159).
- **Evidence & Root Cause**: `fp1_single()` sets OX only when `isinf(f)` is true. Under round-toward-zero, `fmuls` with operands `FLT_MAX` and `2` produces finite `FLT_MAX`; the implementation records only inexact. The mathematical result overflowed the single-precision range regardless of the finite rounded endpoint.
- **Remediation**: Determine overflow from the operation’s range and rounding semantics, rather than testing whether the final representation is infinity.

- [x] **P64-R7-28 — BUG — MEDIUM**

- **Summary**: The long-double intermediate can double-round single-precision arithmetic incorrectly.
- **Locations**: [fp_single.c:159](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:159), [fp_single.c:242](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:242), [fp_single.c:354](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:354).
- **Evidence & Root Cause**: Arithmetic first rounds into `long double`, then into `float`. On the AArch64 Linux binary128 path, nearest-mode `fadds` with FRA=`1+2^-24` and FRB=`2^-200` loses the small positive addend in the intermediate. The subsequent binary32 tie rounds to `1`, although the exact sum lies above the midpoint and must round to `1+2^-23`. The absorbed-addend correction explicitly returns when `LDBL_MANT_DIG != 53`. The instruction operates on the full significands before rounding its result. [IBM PowerPC instruction reference](https://datasheets.chipdb.org/IBM/PowerPC/750/750cx_um3-17-05.pdf).
- **Remediation**: Preserve discarded information through the final rounding step, or use an established correctly rounded implementation. A wider intermediate alone is insufficient.

- [x] **P64-R7-29 — BUG — MEDIUM**

- **Summary**: Floating-point arithmetic records generic invalid-operation status without its required cause bits.
- **Locations**: [fp_single.c:78](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:78), [fp_single.c:138](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:138), [fp_single.c:228](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/fp_single.c:228).
- **Evidence & Root Cause**: The exception interface reduces invalid arithmetic to `exc |= 16`, which `fp1_record()` maps only to VX. Starting with clear FPSCR, `fdiv 0,0` therefore omits VXZDZ; `fsub +Inf,+Inf` omits VXISI. Software inspecting the architected invalid-cause fields cannot distinguish these operations. [QEMU FP exception handling](https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/ppc/fpu_helper.c).
- **Remediation**: Classify invalid operations from opcode and operand classes, set their specific sticky causes, and derive VX/FEX/FX consistently.

- [x] **P64-R7-30 — BUG — MEDIUM**

- **Summary**: Signal frames expose the internal XER encoding instead of the guest architectural encoding.
- **Locations**: [cpu.h:19](/Users/angerman/Projects/zw3rk/ppc64rt/src/core/cpu.h:19), [vec.c:212](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/vec.c:212), [sigframe.c:246](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c:246), [sigframe.c:339](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/sigframe.c:339).
- **Evidence & Root Cause**: CPU state stores SO/OV/CA in numerical bits 63/62/61. `mfxer` and `mtxer` explicitly translate these to/from guest bits 31/30/29, but signal serialization copies `ctx->xer` verbatim in both directions. After `mtxer 0x20000000`, PT_XER consequently contains `0x2000000000000000`. Conversely, a signal handler setting architectural CA in its saved context restores a value that `adde` does not recognize as carry.
- **Remediation**: Introduce shared architectural XER pack/unpack helpers and use them for SPR access and signal-frame save/restore, preserving CA32 and OV32.

---

## 9. `mips64rt` (`f29422b`) — 18 Round-7 Findings (`18 / 18` Resolved)

Read all ten files in `src/interp/` end-to-end and the CPU/FPU/trap headers present. There is no `include/` directory or separate MSA header. No builds, tests, or edits were performed. Examples below are static deductions.

- [x] **M64-R7-1 — BUG — HIGH**

- **Summary**: R6 binaries are admitted but execute incompatible R2 semantics.
- **Locations**: [interp.c:755](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:755), [cpu.h:142](/Users/angerman/Projects/zw3rk/mips64rt/src/core/cpu.h:142), [loader.c:370](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:370).
- **Evidence & Root Cause**: ELF admission checks ABI without selecting an ISA revision. R6 `BGEUC` uses opcode `0x06`, which the interpreter always executes as `BLEZ`. With distinct source registers containing 2 and 1, a taken compact branch becomes an untaken delayed branch. CPU state also lacks forbidden-slot tracking, so required R6 CTI rejection cannot occur. [MIPS64 instruction reference](https://www.cipunited.com/xlx/files/document/202008/1205490289250.pdf).
- **Remediation**: Introduce revision-aware admission, decoding, and forbidden-slot state. Reject unsupported revisions until implemented.

- [x] **M64-R7-2 — BUG — HIGH**

- **Summary**: LL/SC reservations survive interfering writes through shared-memory aliases.
- **Locations**: [unaligned.c:297](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:297), [unaligned.c:383](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:383), [unaligned.c:494](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:494), [vm_file.c:497](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:497).
- **Evidence & Root Cause**: Reservation generations identify guest virtual addresses, while native `MAP_SHARED` mappings can alias the same backing word. Thread A can load-linked through one mapping; thread B can change and restore the word through another mapping whose epoch bucket differs. Neither A’s generation nor its reservation changes, and the final value CAS succeeds incorrectly. Process-private generation arrays likewise miss writes from another process.
- **Remediation**: Track reservations by backing identity and offset, with invalidation shared across participating mappings/processes. Value comparison alone cannot detect ABA interference.

- [x] **M64-R7-3 — BUG — HIGH**

- **Summary**: COP1 branch delay-slot faults discard the installed signal-handler PC.
- **Locations**: [fp.c:812](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:812), [interp.c:849](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:849).
- **Evidence & Root Cause**: `fp_branch()` executes its slot through `interp_step()`. That function converts handled faults and dispatcher-owned PC changes into return value zero. `fp_branch()` then overwrites the handler PC with the ordinary branch destination. For example, a handled overflow in a `BC1T` delay slot installs a signal frame but skips the handler, continuing with signal-delivery register state.
- **Remediation**: Preserve an explicit redirected-PC outcome when executing a delay slot, or share the integer branch’s slot-execution contract.

- [x] **M64-R7-4 — BUG — HIGH**

- **Summary**: Unaligned merge accesses deliver memory faults twice.
- **Locations**: [unaligned.c:70](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:70), [unaligned.c:88](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:88), [mem.c:91](/Users/angerman/Projects/zw3rk/mips64rt/src/os/mem.c:91).
- **Evidence & Root Cause**: `guest_ld8()`/`guest_st8()` already deliver faults. Successful handler installation deliberately leaves `exit_reason == MIPS64_EXIT_NONE`; `load_bytes()`/`store_bytes()` interpret that as an undelivered fault and call `mips_fault()` again. Normally the first delivery blocks SIGSEGV, so the second marks execution fatal before the handler runs. `SA_NODEFER` instead permits an erroneous nested frame.
- **Remediation**: Propagate accessor failures without raising another fault.

- [x] **M64-R7-5 — BUG — HIGH**

- **Summary**: FCC1–FCC7 branches lose their taken target during delay-slot memory recovery.
- **Locations**: [decode.c:126](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.c:126), [decode.h:207](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/decode.h:207), [mem_recover.c:197](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/mem_recover.c:197).
- **Evidence & Root Cause**: `is_bc()` requires `rt <= 3`, excluding branches whose `rt` field selects FCC1–FCC7. Recovery therefore classifies a taken `bc1t $fcc1,target` as a nonbranch and resumes at `branch_pc+8`. Additionally, the header reverses the BC1T/BC1FL constants, making the likely classifier incorrect.
- **Remediation**: Accept all FCC selectors, derive likely from `rt & 2`, and correct the constants.

- [x] **M64-R7-6 — BUG — HIGH**

- **Summary**: NAN2008 binaries execute legacy NaN semantics.
- **Locations**: [fp.c:86](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:86), [fp.h:39](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.h:39), [loader.c:811](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:811).
- **Evidence & Root Cause**: Admission accepts `EF_MIPS_NAN2008`, but loading never initializes the NaN mode and interpreter classification always uses legacy polarity. Consequently, NAN2008 quiet NaN `0x7fc00000` raises Invalid, signaling NaN `0x7f800001` does not, and invalid arithmetic produces `0x7fbfffff`, which is signaling under NAN2008. [GNU NaN-encoding documentation](https://sourceware.org/binutils/docs-2.24/as/MIPS-NaN-Encodings.html).
- **Remediation**: Initialize and consistently honor the selected NaN mode, including default results and conversions; otherwise reject that mode.

- [x] **M64-R7-7 — BUG — HIGH**

- **Summary**: Destination/source aliasing suppresses signaling-NaN exceptions.
- **Locations**: [fp.c:341](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:341), [fp.c:381](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:381), [fp.c:505](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:505), [fp_ps.c:273](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:273).
- **Evidence & Root Cause**: Several arithmetic paths write the default quiet NaN into `fd` before rereading source registers to detect signaling NaNs. Legacy `SQRT.S $f0,$f0` with `0x7fc00000` therefore replaces its signaling operand before classification, suppressing Invalid and an enabled trap. Binary arithmetic and COP1X have the same ordering defect.
- **Remediation**: Snapshot and classify all source bits before destination writeback.

- [x] **M64-R7-8 — BUG — HIGH**

- **Summary**: COP1X multiply-add uses incorrect rounding semantics and ignores guest RM.
- **Locations**: [fp_ps.c:287](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:287), [fp_ps.c:330](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:330).
- **Evidence & Root Cause**: The R2 path uses host `fma()`/`fmaf()`, although legacy MADD rounds the intermediate product and then the sum. With `fr=-1`, `fs=1+2^-23`, `ft=1-2^-23`, nearest-rounded `MADD.S` should produce zero; this code produces `-2^-46`. Neither path consults guest RM, also breaking directed rounding. [MIPS MADD specification](https://personal.denison.edu/~bressoud/cs281-s10/Supplements/ISA_Vol_2.pdf).
- **Remediation**: Implement the selected architecture’s intermediate and final rounding, using guest RM and combined exception accounting.

- [x] **M64-R7-9 — BUG — MEDIUM**

- **Summary**: Misaligned JR/JALR targets fault before required link and delay-slot effects.
- **Locations**: [interp.c:787](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:787).
- **Evidence & Root Cause**: The target-alignment check returns before writing JALR’s link register or executing its slot. The architectural exception occurs when the target is subsequently fetched. A misaligned `jalr` followed by a store therefore incorrectly skips both the link update and store, and records the jump PC instead of the target. [MIPS instruction reference](https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00086-2B-MIPS32BIS-AFP-6.06.pdf).
- **Remediation**: Commit the link and slot first; raise the alignment fault during target fetch.

- [x] **M64-R7-10 — BUG — MEDIUM**

- **Summary**: Traditional GNU arithmetic BREAK encodings deliver the wrong signal.
- **Locations**: [interp.c:54](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:54), [interp.c:220](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/interp.c:220).
- **Evidence & Root Cause**: `trap_code()` extracts only bits 15:6, suitable for register trap instructions but insufficient for BREAK’s 20-bit code. GNU `break 7` (`0x0007000d`) and `break 6` (`0x0006000d`) become code zero and deliver SIGTRAP instead of the arithmetic SIGFPE mapping. Linux normalizes the historical BREAK encoding separately. [Linux MIPS trap handling](https://code.googlesource.com/linux/torvalds/linux/+/0d19d9e14687ff6f43d6c4806ace9ff682d7703f/arch/mips/kernel/traps.c).
- **Remediation**: Separate BREAK’s full code extraction/normalization from TEQ/TNE-family extraction.

- [x] **M64-R7-11 — BUG — MEDIUM**

- **Summary**: Misaligned LL/SC/LLD/SCD report SIGSEGV instead of SIGBUS.
- **Locations**: [unaligned.c:459](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:459), [unaligned.c:490](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:490), [unaligned.c:588](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:588), [unaligned.c:620](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/unaligned.c:620).
- **Evidence & Root Cause**: All four alignment checks call `mips_fault()`, which raises SIGSEGV. Linux MIPS rejects alignment emulation for these instructions and delivers SIGBUS, including when FIXADE is enabled. [Linux unaligned-access handling](https://codebrowser.dev/linux/linux/arch/mips/kernel/unaligned.c.html).
- **Remediation**: Use the existing `mips_bus_fault()` path for these alignment failures.

- [x] **M64-R7-12 — BUG — MEDIUM**

- **Summary**: FCSR Cause bits accumulate across arithmetic instructions.
- **Locations**: [fp.c:103](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:103), [fp.c:109](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:109), [fp.c:841](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:841).
- **Evidence & Root Cause**: `fp_raise()` only ORs causes; `fp_clear_trap()` resets only thread-local trap state. Masked `DIV.S 1/0` followed by exact `ADD.S 1+1` leaves Cause.Z set. Causes must describe the latest arithmetic operation; only Flags are sticky. [MIPS64 FCSR specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Replace the Cause field per arithmetic operation while preserving cumulative Flags.

- [x] **M64-R7-13 — BUG — MEDIUM**

- **Summary**: Trapped floating-point instructions incorrectly modify sticky Flags.
- **Locations**: [fp.c:109](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:109), [fp.c:144](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:144), [fp.c:207](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:207).
- **Evidence & Root Cause**: Exceptions update Flags independently. With Overflow enabled and Inexact disabled, overflowing arithmetic arms the Overflow trap and then sets Flag.I. Finalization restores the destination and FCC, but leaves that flag changed. Trapped instructions must preserve all Flags. [MIPS64 exception specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Accumulate exceptions, determine whether the instruction traps, then update Flags only on completion.

- [x] **M64-R7-14 — BUG — MEDIUM**

- **Summary**: Division mishandles infinity operands.
- **Locations**: [fp.c:457](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:457), [fp.c:585](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:585).
- **Evidence & Root Cause**: For `DIV.S 1/+∞` under round-toward-positive-infinity, the residual calculation evaluates `0*∞`, obtains NaN, and incorrectly advances zero to `2^-149`, also setting Inexact. Both S and D paths additionally raise Divide-by-zero for `∞/0`, which should return signed infinity without that exception. [MIPS64 division exception rules](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Resolve zero/infinity operand combinations before residual-based rounding.

- [x] **M64-R7-15 — BUG — MEDIUM**

- **Summary**: FCSR’s flush-to-zero control is accepted but ignored.
- **Locations**: [fpmove.c:192](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:192), [fp.c:159](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:159), [fp.c:194](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:194).
- **Evidence & Root Cause**: `CTC1` stores FS bit 24, but arithmetic never reads it. With FS set, `MUL.S(2^-126,0.5)` returns subnormal `2^-127` instead of flushing the result to zero. [MIPS64 FS definition](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Apply FS result handling and exception accounting consistently across scalar arithmetic, conversions, PS, and multiply-add.

- [x] **M64-R7-16 — BUG — MEDIUM**

- **Summary**: Paired-single cancellation produces the wrong zero sign under round-down.
- **Locations**: [fp_ps.c:121](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_ps.c:121), [fp.c:256](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:256).
- **Evidence & Root Cause**: `ADD.PS(+1,-1)` and `SUB.PS(+1,+1)` produce host-rounded positive zero. `fp_adj_f()` preserves it because numeric `r == q`, even when guest RM requires negative zero. Scalar ADD/SUB already contain a dedicated cancellation correction that PS lacks.
- **Remediation**: Apply the signed-zero cancellation rule independently to both PS lanes.

- [x] **M64-R7-17 — DEFECT — MEDIUM**

- **Summary**: Required FCSR alias-register accesses raise SIGILL.
- **Locations**: [fpmove.c:181](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:181).
- **Evidence & Root Cause**: CFC1/CTC1 recognize only control registers 0 and 31. Legal FCCR register 25, FEXR register 26, and FENR register 28 accesses return `MIPS_FAULT`, which becomes SIGILL. These aliases are required when the R2 FPU is implemented. [MIPS64 control-register specification](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Implement alias packing, writable masks, shared FCSR updates, and applicable write-triggered exception checks.

- [x] **M64-R7-18 — DEFECT — MEDIUM**

- **Summary**: Valid floating-point conditional moves are unimplemented.
- **Locations**: [fp.c:667](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp.c:667).
- **Evidence & Root Cause**: `fp_fmt_sd()` has no handling for function codes `0x11`, `0x12`, or `0x13`: MOVF/MOVT, MOVZ, and MOVN `.S/.D`. They reach `MIPS_FAULT` and SIGILL. The integer MOVCI implementation does not cover these FPR destinations. [MIPS64 formatted-move instruction definitions](https://0x04.net/~mwk/doc/mips/MD00083-2B-MIPS64INT-AFP-02.50.pdf).
- **Remediation**: Implement conditional FPR moves with the appropriate FCC/GPR predicate and no arithmetic exception side effects.

---

## 10. `sparc64rt` (`bab379d`) — 35 Round-7 Findings (`35 / 35` Resolved)

Reviewed all 18 files in `src/interp/` and the relevant CPU, window, FPU, VIS, and trap headers end-to-end using read-only review lanes. No builds or tests were run; no files were changed. Counterexamples below are static traces.

- [x] **S64-R7-1 — BUG — HIGH**

- **Summary**: Nested delay-slot branches permit unbounded host recursion.
- **Locations**: [interp.c:244](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:244), [interp.c:349](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:349).
- **Evidence & Root Cause**: `exec_delay` recursively invokes `exec_cti`, which invokes `exec_delay` again. Two adjacent, non-annulled `ba` instructions, each targeting itself, alternate indefinitely through these calls. Guest code can exhaust the translator’s stack and prevent return to the dispatcher.
- **Remediation**: Execute delayed control transfers through an iterative PC/nPC state machine with bounded work per dispatcher entry.

- [x] **S64-R7-2 — BUG — HIGH**

- **Summary**: Quad FP exceptions corrupt architectural state before trapping.
- **Locations**: [fp_quad.c:167](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:167), [fp_qdiv.c:111](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:111), [fp_qconv.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:119).
- **Evidence & Root Cause**: Quad handlers publish destinations/FCC before checking TEM, accrue trapped exceptions, and omit IEEE `FTT`. For `FDIVQ(1,+0)` with initial FSR `0x01000000`, the destination becomes infinity and FSR becomes `0x01000042`. The signal layer consequently classifies it as SIGILL. Quad integer conversions also bypass exception-state completion entirely.
- **Remediation**: Use the shared exception-commit helper before publishing results. Preserve destinations, FCC, and AEXC on enabled exceptions; complete successful conversions through the same helper.

- [x] **S64-R7-3 — BUG — HIGH**

- **Summary**: Directed rounding changes exact results.
- **Locations**: [fp_sd.c:285](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:285), [fp_quad.c:310](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:310), [fp_qdiv.c:245](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:245), [fp_qconv.c:268](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:268).
- **Evidence & Root Cause**: Upward/downward rounding increments based solely on sign, without requiring discarded bits. Upward `FADDS(1,1)` produces `0x40000001` instead of `0x40000000`, with NX clear. The same defect affects double and quad operations and narrowing conversions.
- **Remediation**: Require `g || r || s` before any directed-rounding increment.

- [x] **S64-R7-4 — BUG — HIGH**

- **Summary**: FP addition/subtraction discards information needed for correct arithmetic.
- **Locations**: [fp_sd.c:374](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:374), [fp_sd.c:417](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:417), [fp_quad.c:411](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:411).
- **Evidence & Root Cause**: Single/double alignment collapses discarded bits into sticky before arithmetic. Subtraction omits their borrow; quad subtraction likewise fails to incorporate its separated fractional bits during subtraction and normalization. `FSUBS(0x3f800000,0x3f7fffff)` produces `2^-23` with NX instead of exact `2^-24`.
- **Remediation**: Retain an extended significand through alignment, subtraction, and normalization; round only afterward.

- [x] **S64-R7-5 — BUG — HIGH**

- **Summary**: Quad subnormal packing loses retained fraction bits and boundary rounding information.
- **Locations**: [fp_quad.c:286](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:286), [fp_quad.c:356](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:356), [fp_qdiv.c:221](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:221), [fp_qdiv.c:290](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:290).
- **Evidence & Root Cause**: Subnormal output retains `slo` but discards the fraction in `shi`. Thus `FMULQ(2^-16382,0.5)` returns zero instead of an exact nonzero subnormal. Additionally, `shift >= 113` clears guard/round, making nearest-rounded `min_subnormal × 0.75` incorrectly become zero.
- **Remediation**: Preserve both fraction halves and compute guard/round/sticky correctly at the 113-bit boundary.

- [x] **S64-R7-6 — BUG — HIGH**

- **Summary**: `FQTOS` loses the sign of negative finite results.
- **Locations**: [fp_qconv.c:344](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:344), [fp_qconv.c:379](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:379), [fp_qconv.c:792](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:792).
- **Evidence & Root Cause**: Binary32 packing places the sign in bit **32**. The destination assignment then casts to `uint32_t`, discarding it. `FQTOS(-1.0Q)` therefore yields positive `0x3f800000`. Finite negative overflow and underflow paths have the same defect.
- **Remediation**: Place the binary32 sign in bit 31 in every packing branch.

- [x] **S64-R7-7 — BUG — HIGH**

- **Summary**: `FSMULD` truncates its widened product.
- **Locations**: [fp_conv.c:579](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:579), [fp_sd.c:663](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_sd.c:663).
- **Evidence & Root Cause**: The caller requests a 24-bit product, discards its GRS bits, and widens the truncated significand. Multiplying two single values `0x3f800001` yields double `0x3ff0000040000000` instead of `0x3ff0000040000040`. The full product fits exactly in double precision, as reflected in [QEMU’s widening implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/fop_helper.c).
- **Remediation**: Preserve the complete 48-bit significand product before encoding the double result.

- [x] **S64-R7-8 — BUG — HIGH**

- **Summary**: `STQF` stores the high half twice.
- **Locations**: [fp_ldst.c:208](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:208).
- **Evidence & Root Cause**: Both eight-byte stores use `cpu->fp.d[2U * qi]`. The low 64 bits are never read. Every quad value with unequal halves is corrupted when stored; the comment intentionally reproducing an oracle quirk does not implement the register’s contents.
- **Remediation**: Store `cpu->fp.d[2U * qi + 1U]` at `va + 8`.

- [x] **S64-R7-9 — BUG — HIGH**

- **Summary**: Integer `LDDA/STDA` access floating-point registers.
- **Locations**: [decode.c:481](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:481), [fp_ldst.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:119), [fp_ldst.c:218](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:218).
- **Evidence & Root Cause**: The decoder unconditionally classifies integer alternate doubleword instructions as FPU operations. For example, `ldda [addr] 0x80,%l0` writes `fp.d[8]` and leaves `%l0/%l1` unchanged. `STDA` correspondingly stores unrelated FPR contents.
- **Remediation**: Route integer doubleword instructions to integer handlers; distinguish specialized ASIs without changing the architectural register file.

- [x] **S64-R7-10 — BUG — HIGH**

- **Summary**: Misaligned atomics become fatal internal errors.
- **Locations**: [interp_mem.c:302](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:302), [interp_mem.c:357](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:357), [threads.c:861](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/threads.c:861), [mem_space_write.c:615](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/mem_space_write.c:615).
- **Evidence & Root Cause**: Misaligned CASA/CASXA/SWAP are declined by the host fast path, then forwarded without alignment validation to the atomic substrate. Its rejection becomes `SPARC64_STEP_INTERNAL`, terminating execution instead of delivering a recoverable guest alignment signal.
- **Remediation**: Check natural alignment before either atomic backend and return the architectural misalignment trap.

- [x] **S64-R7-11 — BUG — MEDIUM**

- **Summary**: Tagged arithmetic incorrectly sets `xcc.V` and traps on 64-bit overflow.
- **Locations**: [interp_win.c:644](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:644).
- **Evidence & Root Cause**: Nonzero tags set both overflow bits, and trapping variants test `icc.V | xcc.V`. Consequently, `TADDcc(1,0)` wrongly sets `xcc.V`; `TADDccTV(0x7fffffff00000000,0x100000000)` wrongly traps. Tag overflow affects `icc.V`; 64-bit overflow alone does not trigger the tagged trap. [V9 tagged-arithmetic specification](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=260).
- **Remediation**: Apply tag bits only to `icc.V` and base the TV exception solely on tag/32-bit overflow.

- [x] **S64-R7-12 — BUG — MEDIUM**

- **Summary**: A valid `TADDcc` encoding is misclassified as SIR.
- **Locations**: [decode.c:198](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:198).
- **Evidence & Root Cause**: `op3=TADDcc, rd=31, rs1=0, i=1` is forcibly classified privileged. Thus `taddcc %g0,0,%i7` traps instead of writing zero and updating CCR. SIR uses the WRASR encoding, not this arithmetic opcode.
- **Remediation**: Remove the false SIR special case from the ALU decoder.

- [x] **S64-R7-13 — BUG — MEDIUM**

- **Summary**: Legacy integer division truncates overflow, mishandles signed results, and copies incorrect flags into `xcc`.
- **Locations**: [interp_win.c:502](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:502), [interp_win.c:591](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:591).
- **Evidence & Root Cause**: UDIV with `Y=1`, low dividend zero, divisor one returns zero instead of saturated `0xffffffff`. SDIV producing `-1` zero-extends it. The `cc` variants calculate flags from truncated results and assign identical nibbles, incorrectly propagating 32-bit overflow to `xcc.V`. [V9 division rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=178).
- **Remediation**: Saturate before publishing results, sign-extend signed quotients, and calculate each CCR nibble separately.

- [x] **S64-R7-14 — BUG — MEDIUM**

- **Summary**: `MULScc` implements the wrong multiply-step algorithm.
- **Locations**: [interp_win.c:671](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:671).
- **Evidence & Root Cause**: It uses `xcc.N xor xcc.V` to select the addend, adds before shifting, and inserts `Y[0]` into the result. With `rs1=0`, `rs2=2`, `Y=1`, and CCR zero, it returns `0x80000000` instead of low-word `2`. [QEMU’s implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c) follows the required shift-then-add sequence.
- **Remediation**: Shift using `icc.N xor icc.V`, select the multiplicand using old `Y[0]`, then add and update ICC.

- [x] **S64-R7-15 — BUG — MEDIUM**

- **Summary**: `FLUSHW` unnecessarily spills the current window.
- **Locations**: [interp.c:152](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:152), [interp_win.c:249](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_win.c:249).
- **Evidence & Root Cause**: Architectural `FLUSHW` calls a runtime snapshot helper that always writes the current `%l/%i` image. A second FLUSHW after all caller windows have been flushed still writes 128 bytes, or faults if the current stack pointer is unmapped. Architectural FLUSHW excludes the current window. [V9 A.21](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=193).
- **Remediation**: Separate architectural caller-window flushing from full runtime snapshots.

- [x] **S64-R7-16 — BUG — MEDIUM**

- **Summary**: Legacy `FBfcc` instructions always decode as illegal.
- **Locations**: [decode.c:121](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:121).
- **Evidence & Root Cause**: Only `op2=5` is handled. The code explicitly rejects `op2=6`, which is the legacy floating branch with `disp22` and FCC0. Valid floating branches therefore trap before condition or annul handling. Both families are implemented independently in [QEMU’s SPARC translator](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Decode `op2=6` with FCC0 and signed `disp22`, retaining the existing predicted form.

- [x] **S64-R7-17 — BUG — MEDIUM**

- **Summary**: Register-conditioned `FMOVr` instructions are unimplemented.
- **Locations**: [fp.c:424](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:424), [fp.c:558](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:558).
- **Evidence & Root Cause**: The function named `fp_movr` implements integer-CCR-conditioned FMOVcc. Actual FMOVr encodings, such as `FMOVRsZ` with `opf=0x025`, match neither dispatch condition and always trap.
- **Remediation**: Decode the register-conditioned family separately, evaluate full-width `rs1`, and implement single/double/quad copies.

- [x] **S64-R7-18 — BUG — MEDIUM**

- **Summary**: Floating conditional moves use the wrong “unordered or greater” predicate.
- **Locations**: [fp.c:341](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:341), [fp.c:397](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:397).
- **Evidence & Root Cause**: Condition 5 returns `fcc != 2`, accepting equal/less/unordered and rejecting greater. The already-correct shared evaluator uses `fcc == 3 || fcc == 2`. This causes unwanted destination writes and missed moves.
- **Remediation**: Reuse `sparc64_eval_fcond` instead of maintaining a divergent predicate table.

- [x] **S64-R7-19 — BUG — MEDIUM**

- **Summary**: `ALIGNADDRL` computes the wrong GSR alignment offset.
- **Locations**: [decode.c:318](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:318), [interp.c:135](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:135).
- **Evidence & Root Cause**: ALIGNADDR and ALIGNADDRL share a handler that always stores `sum & 7`. ALIGNADDRL requires `(-sum) & 7`; a sum ending in one should set seven. Subsequent FALIGNDATA therefore splices the wrong bytes. [QEMU ALIGNADDRL implementation](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/translate.c).
- **Remediation**: Select the negated low-three-bit offset for ALIGNADDRL while preserving the aligned destination address.

- [x] **S64-R7-20 — BUG — MEDIUM**

- **Summary**: Immediate `Tcc` ignores `rs1` when calculating the trap number.
- **Locations**: [interp.c:368](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:368).
- **Evidence & Root Cause**: Immediate form uses `d->imm` alone. With `%g2=0x60`, `ta %g2+0x0d` should select trap `0x6d`, but instead takes the generic trap path. The inverse can incorrectly invoke the syscall gate. [V9 Tcc definition](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=264).
- **Remediation**: Always add `rs1` to the selected second operand, mask to seven bits, and carry that evaluated number through dispatch.

- [x] **S64-R7-21 — BUG — MEDIUM**

- **Summary**: Misaligned `JMPL/RETURN` targets produce the wrong signal and fault value.
- **Locations**: [interp.c:298](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:298), [interp.c:316](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:316).
- **Evidence & Root Cause**: Both paths return `SPARC64_TRAP_ILLEGAL` with the instruction word. The signal layer delivers SIGILL instead of the alignment signal, and loses the target address. Misaligned jump targets require an alignment exception. [V9 JMPL definition](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=195).
- **Remediation**: Return an alignment-specific trap carrying the target, with correct SIGBUS mapping and pre-commit state.

- [x] **S64-R7-22 — BUG — MEDIUM**

- **Summary**: A pending branch target of zero is destroyed on a delay-slot trap.
- **Locations**: [interp.c:482](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:482).
- **Evidence & Root Cause**: Trap cleanup treats `cpu->npc == 0` as missing state. After a branch to zero whose delay instruction traps, the branch has already published the correct nPC, but cleanup replaces it with `delay_pc + 4`. Signal recovery resumes along the wrong path.
- **Remediation**: Track whether PC/nPC were published explicitly; never use a guest address as an initialization sentinel.

- [x] **S64-R7-23 — BUG — MEDIUM**

- **Summary**: Integer alternate accesses reject valid `%asi` register forms.
- **Locations**: [decode.c:468](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/decode.c:468), [interp_mem.c:412](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:412), [interp_mem.c:450](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:450).
- **Evidence & Root Cause**: The decoder uses `asi=0xff` for `i=1`; integer handlers pass it unchanged to validation, which rejects it. Thus writing `%asi=0x80` cannot enable ordinary register-ASI loads/stores or CAS. CASA/CASXA decoding also leaves their compare-register field zero in this form.
- **Remediation**: Resolve `regasi` from CPU state before validation and decode CAS `rs2` independently of the `i` bit.

- [x] **S64-R7-24 — BUG — MEDIUM**

- **Summary**: No-fault ASIs behave like ordinary writable ASIs.
- **Locations**: [interp_mem.c:416](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:416), [interp_mem.c:549](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:549), [fp_ldst.c:218](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:218).
- **Evidence & Root Cause**: ASIs `0x82/0x8a` affect only byte order. An aligned no-fault load from unmapped memory traps instead of returning zero; stores through those ASIs modify memory. FP loads and host atomic admission share the omission. [QEMU ASI helpers](https://raw.githubusercontent.com/qemu/qemu/master/target/sparc/ldst_helper.c).
- **Remediation**: Preserve no-fault semantics through execution, suppress only eligible guest access faults, and reject stores/atomics through no-fault ASIs.

- [x] **S64-R7-25 — BUG — MEDIUM**

- **Summary**: `LDD/STD` accept addresses lacking doubleword alignment.
- **Locations**: [interp_mem.c:475](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:475), [interp_mem.c:571](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:571).
- **Evidence & Root Cause**: Two independent four-byte accesses enforce only four-byte alignment. Address `0x1004` succeeds. Four bytes before an inaccessible page, LDD commits its first register and STD writes its first word before faulting, instead of rejecting the original misaligned access.
- **Remediation**: Check eight-byte alignment first and stage the complete load before publishing either register.

- [x] **S64-R7-26 — BUG — MEDIUM**

- **Summary**: FP double/quad memory operations reject valid word-aligned addresses.
- **Locations**: [fp_ldst.c:190](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:190), [fp_ldst.c:219](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:219), [fp_ldst.c:232](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:232).
- **Evidence & Root Cause**: LDDF/STDF inherit eight-byte alignment checks; LDQF/STQF explicitly require sixteen. V9 permits word alignment, with software emulation for optional stricter hardware traps. This user-mode implementation instead delivers SIGBUS for addresses such as `0x1004`. [V9 FP memory alignment](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=197).
- **Remediation**: Support word-aligned transfers using staged four-byte pieces or equivalent checked byte access.

- [x] **S64-R7-27 — BUG — MEDIUM**

- **Summary**: CAS can succeed on read-only memory when comparison fails.
- **Locations**: [interp_mem.c:228](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:228), [interp_mem.c:254](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:254).
- **Evidence & Root Cause**: After the writable-memory fast path declines, fallback LR requires only read permission. A mismatch immediately returns success. A read-only word containing one with compare operand two therefore avoids the required write-permission fault. CAS requires writability even on mismatch. [V9 A.9](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=177).
- **Remediation**: Validate read/write access for the entire atomic operation before comparison.

- [x] **S64-R7-28 — BUG — MEDIUM**

- **Summary**: Generic CASA paths compare the unused upper 32 bits.
- **Locations**: [interp_mem.c:232](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:232), [interp_mem.c:275](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:275), [interp_mem.c:645](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:645).
- **Evidence & Root Cause**: Generic callback/fallback execution compares a zero-extended memory word with the full 64-bit compare register. Memory `1` and compare register `0x100000001` incorrectly mismatch. The host fast path truncates correctly, making behavior backend-dependent.
- **Remediation**: Mask compare and replacement operands to the requested atomic width before selecting any backend.

- [x] **S64-R7-29 — BUG — MEDIUM**

- **Summary**: FSR transfers overwrite preserved state and omit required completion effects.
- **Locations**: [interp_mem.c:515](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:515), [interp_mem.c:590](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:590).
- **Evidence & Root Cause**: LDFSR replaces the whole FSR, clearing FCC1–FCC3. Both load forms accept unrestricted values instead of applying writable-field masks. Successful STFSR/STXFSR never clear FTT. Reserved `rd=2..31` forms also fall through as valid transfers. [V9 FSR transfer rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=249).
- **Remediation**: Validate encodings, preserve unaffected/read-only fields, and clear FTT only after successful stores.

- [x] **S64-R7-30 — BUG — MEDIUM**

- **Summary**: FP register writes never update FPRS dirty bits.
- **Locations**: [fp.c:201](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:201), [fp_ldst.c:223](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_ldst.c:223), [interp.c:95](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp.c:95).
- **Evidence & Root Cause**: Destination writes modify only the FP file. After clearing dirty bits with `wr %g0,4,%fprs`, modifying `%f2` still leaves readable FPRS equal to four. Upper-bank writes similarly omit DU.
- **Remediation**: Set the corresponding DL/DU bits on committed FP writes, including loads, conversions, and VIS operations.

- [x] **S64-R7-31 — BUG — MEDIUM**

- **Summary**: Widening subnormal single/double values to quad changes their values.
- **Locations**: [fp_qconv.c:651](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:651), [fp_qconv.c:702](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:702).
- **Evidence & Root Cause**: Normalization targets bit 22/51 instead of 23/52, then packs the remaining fraction at the normal scale. Single input bits `0x00000003` become `2.5 × 2^-149` instead of `3 × 2^-149`. Double input bits `3` have the analogous error.
- **Remediation**: Normalize at the actual hidden-bit position and remove that bit using the full fraction mask.

- [x] **S64-R7-32 — BUG — MEDIUM**

- **Summary**: Float-to-integer conversions reject valid boundary values and raise spurious overflow.
- **Locations**: [fp_conv.c:274](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:274), [fp_conv.c:307](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_conv.c:307), [fp_qconv.c:568](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qconv.c:568).
- **Evidence & Root Cause**: Quad conversion rejects exact `-2^31/-2^63`; double-to-int32 rejects `-2147483648.5` before truncation. Invalid paths commit NV|OF, so enabling only OF can trap an invalid conversion whose NV is masked.
- **Remediation**: Check representability after truncation, permit the negative endpoint, and raise NV alone for invalid conversions.

- [x] **S64-R7-33 — BUG — MEDIUM**

- **Summary**: Quad zero addition/subtraction ignores operand signs.
- **Locations**: [fp_quad.c:671](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_quad.c:671).
- **Evidence & Root Cause**: Both-zero handling chooses the result sign solely from rounding direction. Nearest `FADDQ(-0,-0)` returns +0; downward `FADDQ(+0,+0)` returns -0. These are same-sign additions, not cancellation.
- **Remediation**: Preserve a common effective operand sign; use rounding direction only for opposite-sign cancellation.

- [x] **S64-R7-34 — BUG — MEDIUM**

- **Summary**: `FDIVQ` raises divide-by-zero for infinity divided by zero.
- **Locations**: [fp_qdiv.c:556](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_qdiv.c:556).
- **Evidence & Root Cause**: The zero-denominator branch precedes the infinite-numerator branch. Consequently, `+Inf / +0` sets DZ and can trap, although the result is infinity without an exception. The single/double implementation already handles this case correctly.
- **Remediation**: Handle an infinite numerator before the finite-nonzero divided-by-zero case.

- [x] **S64-R7-35 — BUG — MEDIUM**

- **Summary**: Enabled FP overflow/underflow traps publish multiple current-exception bits.
- **Locations**: [fp_commit.c:21](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp_commit.c:21), [fp.c:159](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/fp.c:159).
- **Evidence & Root Cause**: Trap commitment copies all fresh flags into CEXC. Overflow supplies `0x09`, leaving OF|NX when trapping. A trapped overflow/underflow must report the corresponding exception alone, including when NXM causes the trap. [V9 CEXC rules](https://www.cs.utexas.edu/~novak/sparcv9.pdf#page=71).
- **Remediation**: Select the architectural trapped exception before writing CEXC; retain combined flags only for nontrapping completion.

---

## 11. `rt-series` (`a7b9bc6`) — 8 Round-7 Findings (`8 / 8` Resolved)

Static review completed without running builds or tests. `tests/qual/` is absent from this checkout; the review included the torture suite’s two helper headers and all nine files under `tools/`.

- [x] **RTS-R7-1 — DEFECT — HIGH**

- **Summary**: The TestFloat pipeline neither invokes the upstream tools correctly nor executes the guest FP operations being qualified.
- **Locations**: [tools/run_grind.sh:410](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:410), lines 410–480.
- **Evidence & Root Cause**: The generator receives `-rounds` without a type/function; upstream requires a type/function and uses `-n` for case counts. The verifier likewise receives no function argument. Beyond those invocation errors, the pipeline feeds generator output directly into the verifier. Function-mode generator results come from SoftFloat; verifying them against SoftFloat does not exercise translated guest FP instructions. Upstream explicitly requires an intervening program that executes the operation. See the [generator interface](https://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_gen.html), [verifier interface](https://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_ver.html), and [required pipeline](https://www.jhauser.us/arithmetic/TestFloat-3/doc/TestFloat-general.html).
- **Remediation**: Add a guest operation runner that produces actual results and exception flags, or use a correctly configured guest `testfloat`. Specify operations and rounding modes explicitly, use supported arguments, and require a positive verified case count.

- [x] **RTS-R7-2 — BUG — MEDIUM**

- **Summary**: The FP preservation comparison invokes undefined behavior by discarding `volatile`.
- **Locations**: [tests/p3_torture.c:396](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:396); declarations at lines 371 and 392.
- **Evidence & Root Cause**: Both `b` and `ref` are defined as `volatile double`, but their addresses are cast to `const void *` and passed to `memcmp`, which reads them through nonvolatile accesses. C11 §6.7.3p6 defines this access as undefined behavior, undermining the supposedly exact comparison. See the [C11 committee draft](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).
- **Remediation**: Read both volatile values into ordinary `double` snapshots and compare those snapshots, or compare their representations through volatile-qualified character pointers.

- [x] **RTS-R7-3 — DEFECT — MEDIUM**

- **Summary**: The signal-frame test never checks `siginfo_t.si_signo` and accepts a missing `siginfo_t`.
- **Locations**: [tests/p3_torture.c:108](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:108), lines 108–115 and 250–320.
- **Evidence & Root Cause**: `g_usr1_signo` captures the handler’s separate `signo` argument, yet its assertion reports `"si_signo mismatch"`. Nothing reads `info->si_signo`. When `info == NULL`, `g_usr1_code` retains its initialized zero, which the test explicitly accepts. A translator supplying the correct handler argument but corrupt or absent signal information can therefore receive the advertised `si_signo/si_code/ucontext` PASS.
- **Remediation**: Record and require a non-null `info`; independently check the handler argument, `info->si_signo`, and the supplied `si_code`.

- [x] **RTS-R7-4 — DEFECT — MEDIUM**

- **Summary**: Nested alternate-stack delivery is advertised but never exercised; dropped nested signals also pass.
- **Locations**: [tests/p3_torture.c:134](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:134), lines 134–148, 170–179, 245–246, 448–458, and 794–797.
- **Evidence & Root Cause**: `usr1_handler` ignores the result of `raise(SIGUSR2)`. The nested handler only changes `g_nest_depth`, which no assertion examines. Suppressing SIGUSR2 leaves every PASS condition unchanged. These handlers also run without `SA_ONSTACK`, before the alternate stack is installed. The actual alternate-stack handler never delivers a nested signal, despite the coverage claim at line 8.
- **Remediation**: Run the nested scenario with an installed alternate stack and appropriate `SA_ONSTACK` dispositions. Assert delivery count, nesting order, and actual stack residency for both handlers.

- [x] **RTS-R7-5 — DEFECT — MEDIUM**

- **Summary**: The SPARC V8 annul rule incorrectly describes branch control flow.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:37](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:37).
- **Evidence & Root Cause**: The matrix describes annul as `pc = npc + 4, npc = npc + 8` without restricting that rule to an untaken conditional branch. A taken conditional branch executes its delay instruction even with `,a`; `ba,a target` skips the delay instruction and transfers directly to `target`. Applying the documented rule universally can discard a required instruction or select the wrong PC. See the [SPARC V8 Architecture Manual](https://www.cs.utexas.edu/~novak/sparcv8.pdf).
- **Remediation**: Document taken conditional, untaken conditional, and unconditional annulled branches separately, with explicit resulting `pc`/`npc` values.

- [x] **RTS-R7-6 — DEFECT — MEDIUM**

- **Summary**: The combined MIPS64/N32 signal-frame description incorrectly assigns N32 a 64-bit `ucontext`.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:58](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:58).
- **Evidence & Root Cause**: N32 retains 64-bit saved registers but uses 32-bit `uc_flags`, `uc_link`, and stack fields. Consequently, `uc_mcontext` begins at offset 24 for N32 versus 40 for N64. Treating the layouts as shared shifts saved-register accesses by 16 bytes. Both frames also have a 24-byte prefix omitted from this row. The distinction appears in [Linux’s N32 definitions](https://code.googlesource.com/linux/torvalds/linux/+/26ba1bf310f0ed43f249a93d0cf8a93675cd8ae8/arch/mips/kernel/signal_n32.c) and the sibling’s [frozen layouts](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigframe_mips64rt.h:162).
- **Remediation**: Specify N64 and N32 layouts separately, including their common prefix, pointer widths, and distinct context offsets.

- [x] **RTS-R7-7 — BUG — MEDIUM**

- **Summary**: The lmbench qualification loop supplies incompatible arguments to multiple tools.
- **Locations**: [tools/run_grind.sh:641](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:641), lines 641–658.
- **Evidence & Root Cause**: Every binary receives `-P 1 null`. That operation is valid for `lat_syscall`, but `lat_proc` requires `procedure`, `fork`, `exec`, or `shell`; `lat_ctx` expects a numeric process count; and `lat_pagefault` expects an existing input file. Correct installations therefore encounter harness-induced failures instead of the intended qualification workloads. See upstream [lat_proc](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_proc.c), [lat_ctx](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_ctx.c), and [lat_pagefault](https://raw.githubusercontent.com/intel/lmbench/master/src/lat_pagefault.c).
- **Remediation**: Dispatch arguments per tool and prepare the page-fault input file explicitly. Validate each tool’s expected completion output.

- [x] **RTS-R7-8 — DEFECT — LOW**

- **Summary**: The SPARC32 signal-frame size contradicts its field offsets and the frozen implementation.
- **Locations**: [lode/ISA-TRAP-AND-ABI-MATRIX.md:55](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:55).
- **Evidence & Root Cause**: The stated size is **348 bytes**, but the final four-byte `rwin_save_ptr` starts at `0x154`, giving an extent of `0x158`, or **344 bytes**. That already satisfies Linux’s eight-byte alignment. The sibling [frame definition](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/sigframe_sparc32rt.h:20) explicitly records the correction to 344, consistent with the [Linux structure](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/kernel/signal_32.c).
- **Remediation**: Change the base frame size to 344 bytes and distinguish structure size from any additional stack-placement padding.

---

## Part II — Round-6 Audit Archive (88 Items Resolved & Verified by `fable`)
### 0.1 Round 6 Audit Matrix (`0 / 88` Resolved)

Following complete remediation, `fable` (`claude-fable-5-1`) verification review, and `muse` post-review follow-up across Round 1 (`187` items), Round 2 (`145` items), Round 3 (`85` items), Round 4 (`125` items), and Round 5 (`109` items), Round 6 performed a fresh `gpt-6-astra` static audit of all 11 repositories at their post-Round-5 `HEAD` commits (`88` findings: `0 Critical`, `44 High`, `33 Medium`, `11 Low`).

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | DRY | YAGNI | CLEAN | **R6 Total** | Raw Round-6 `astra` Transcript |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `0207c7b` | 6 | 3 | 0 | 4 | 5 | 0 | 0 | 0 | **0 / 9** | [`2026-11-03-defects-r6-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r6-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `d4decf8` | 4 | 4 | 0 | 6 | 2 | 0 | 0 | 0 | **8 / 8** | [`2026-11-03-defects-r6-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r6-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `0e879ac` | 5 | 4 | 2 | 6 | 2 | 1 | 1 | 1 | **0 / 11** | [`2026-11-03-defects-r6-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r6-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `540bf78` | 4 | 3 | 0 | 4 | 3 | 0 | 0 | 0 | **0 / 7** | [`2026-11-03-defects-r6-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r6-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `c4a1e7a` | 6 | 2 | 2 | 6 | 2 | 1 | 1 | 0 | **0 / 10** | [`2026-11-03-defects-r6-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r6-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `8b57344` | 2 | 1 | 2 | 2 | 1 | 1 | 1 | 0 | **5 / 5** | [`2026-11-03-defects-r6-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r6-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `494c134` | 5 | 1 | 2 | 5 | 1 | 1 | 1 | 0 | **8 / 8** | [`2026-11-03-defects-r6-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r6-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `28df326` | 4 | 6 | 0 | 5 | 4 | 1 | 0 | 0 | **0 / 10** | [`2026-11-03-defects-r6-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r6-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `a37e353` | 3 | 3 | 1 | 4 | 2 | 0 | 1 | 0 | **0 / 7** | [`2026-11-03-defects-r6-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r6-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `1fc64d4` | 5 | 4 | 0 | 5 | 4 | 0 | 0 | 0 | **0 / 9** | [`2026-11-03-defects-r6-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r6-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `3f4602c` | 0 | 4 | 0 | 2 | 1 | 0 | 0 | 1 | **0 / 4** | [`2026-11-03-defects-r6-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r6-rt-series-astra.md) |
| | **Total (Round 6)** | | | **44** | **35** | **9** | **49** | **27** | **5** | **5** | **2** | **0 / 88** | |

### 0.2 Round 6 Cross-Cutting Defect Clusters (Cross-Runtime Check Index)

- [x] **X-R6-1 — High — Futex Endianness, Private-Flag Keying, Dual-Queue Wake/Requeue Coordination & Timeout Overflow**
  - **Linked Items**: `M32-R6-2`, `M32-R6-3`, `S32-R6-3`, `LA64-R6-5`, `LA64-R6-6`, `M64-R6-1`, `M64-R6-2`, `M64-R6-3`, `M64-R6-6`
  - **Summary**: Big-endian `FUTEX_WAKE_OP` losing `FUTEX_PRIVATE_FLAG` and writing to `PROT_READ`-only mappings (`M32-R6-2..3`), `sparc32rt` `futex_time64` stripping `FUTEX_PRIVATE_FLAG` (`S32-R6-3`), `loongarch64rt` cooperative vs kernel waiter queue double-wake/requeue and `FUTEX_WAIT_BITSET` monotonic deadline handling (`LA64-R6-5..6`), and `mips64rt` BE futex expected-word byte-swapping, `FUTEX_REQUEUE` `val2` count, `CMP_REQUEUE` unsigned `val3`, and relative timeout overflow (`M64-R6-1..3`, `M64-R6-6`).
- [x] **X-R6-2 — High — Clone/Fork/Thread Lifecycle, Reaper Lock Fork-Safety, Child TID/Altstack State & Inter-Thread Signal Atomicity**
  - **Linked Items**: `I686-R6-3`, `I686-R6-4`, `I686-R6-7`, `M32-R6-1`, `M32-R6-8`, `M32-R6-9`, `P32-R6-1`, `P32-R6-3`, `P32-R6-4`, `P32-R6-5`, `P32-R6-6`, `LA64-R6-3`, `LA64-R6-4`, `M64-R6-4`, `M64-R6-5`
  - **Summary**: `i686rt` atomic `pending_signals`/`sig_mask`, clearing child `clear_child_tid`/`pending_signals`/robust list on clone, and thread registry capacity enforcement (`I686-R6-3..4`, `I686-R6-7`), `mips32rt` fork-safe `mips_reap_lock`, clearing child `sigaltstack` on `CLONE_VM & ~CLONE_VFORK`, and rejecting `SS_DISABLE` while executing on the alternate stack (`M32-R6-1`, `M32-R6-8..9`), `ppc32rt` thread-safe translation cache eviction, `exit` vs `exit_group`, child `CR0.SO` clearing, `set_tid_address` guest TID return, and sibling `tkill`/`tgkill` (`P32-R6-1`, `P32-R6-3..6`), `loongarch64rt` `CLONE_CHILD_SETTID` store and failed-clone scheduler rollback (`LA64-R6-3..4`), and `mips64rt` fork-clone `stack_va`/`tls_va` propagation and flag-gated TID pointer checks (`M64-R6-4..5`).
- [x] **X-R6-3 — High — Syscall `statx` Field Ordering/Timestamps, `F_SETFL`/`F_GETFL`/`O_DSYNC`, Socket Ancillary Widths & Errno Translation**
  - **Linked Items**: `A32-R6-1`, `A32-R6-2`, `A32-R6-3`, `A32-R6-4`, `A32-R6-7`, `A32-R6-8`, `I686-R6-8`, `M32-R6-4`, `M32-R6-5`, `M32-R6-6`, `S32-R6-7`, `S32-R6-8`, `RV-R6-2`, `RV-R6-3`, `LA64-R6-1`, `LA64-R6-2`, `P64-R6-2`, `P64-R6-6`, `P64-R6-7`, `P64-R6-8`, `P64-R6-9`, `P64-R6-10`, `S64-R6-1`, `S64-R6-6`, `S64-R6-7`, `S64-R6-8`, `S64-R6-9`
  - **Summary**: `a32rt` `sendmsg` ancillary snapshot, 390-byte Linux `uname`, Darwin-to-Linux errno mapping, `signalfd4` pending integration, and `statx` `btime`/`mtime` ordering & `AT_EMPTY_PATH` (`A32-R6-1..4`, `A32-R6-7..8`), `i686rt` Darwin `dup3(oldfd == newfd)` `-EINVAL` (`I686-R6-8`), `mips32rt` O32 `pipe` vs `pipe2` ABI and `F_SETFL`/`O_DSYNC` (`M32-R6-4..6`), `sparc32rt` negative `statx` timestamps and `F_SETFL` access-mode masking (`S32-R6-7..8`), `rvrt` RV32 `msghdr` and `cmsghdr` 32-bit layouts (`RV-R6-2..3`), `loongarch64rt` `statx` `ctime`/`mtime` offsets and `fchownat` flags (`LA64-R6-1..2`), `ppc64rt` stdio `dup2` fd replacement, unified errno mapping, `pipe2` flags, Darwin `sockaddr` family/len header, and `ppoll` signal mask (`P64-R6-2`, `P64-R6-6..10`), and `sparc64rt` `F_SETFL` parenthesis, `faccessat` 3-arg ABI, `TCGETS` termios, `F_GETFL` `O_PATH`/`O_DIRECTORY`/`O_SYNC`, and `clock_getres(clk, NULL)` (`S64-R6-1`, `S64-R6-6..9`).
- [x] **X-R6-4 — High — Checked Guest Copyin/Copyout (`getcwd`, `memfd_create`, `getdents64`, `readv`/`writev`), Pipe Atomicity & Procfs/Stack Lifetime**
  - **Linked Items**: `A32-R6-5`, `A32-R6-6`, `A32-R6-9`, `M32-R6-7`, `P32-R6-2`, `P32-R6-7`, `S32-R6-1`, `S32-R6-2`, `S32-R6-4`, `S32-R6-5`, `S32-R6-6`, `P64-R6-3`, `P64-R6-4`, `P64-R6-5`, `S64-R6-2`, `S64-R6-3`
  - **Summary**: `a32rt` checked copyout in `getcwd`/`getresuid32`/`getresgid32` and page-checked string read in `memfd_create` (`A32-R6-5..6`, `A32-R6-9`), `ppc32rt` thread-local `getdents64` staging buffer and checked copyout (`P32-R6-2`, `P32-R6-7`), `sparc32rt` `thr_fd_grow` allocation rollback, durable `argv`/`envp` across `execve`, Darwin CSPRNG `AT_RANDOM`, non-blocking procfs backing, and VM-guarded `procfs_copy_in` (`S32-R6-1..2`, `S32-R6-4..6`), `ppc64rt` non-blocking pipe `read`, atomic `write`/`writev`, and partial `writev` progress (`P64-R6-3..5`), and `sparc64rt` releasing `thr_big_lock` around blocking I/O and pre-validating `readv` destination buffers (`S64-R6-2..3`).
- [x] **X-R6-5 — High — ISA / Interpreter / DBT Execution Semantics (BT Memory Offset, Address-Size Prefix, SS Base, RV Div Alias, PPC64 `subfic`/`addic` `RA=0`, SPARC64 FP Traps)**
  - **Linked Items**: `I686-R6-1`, `I686-R6-2`, `I686-R6-5`, `I686-R6-6`, `RV-R6-1`, `P64-R6-1`, `S64-R6-4`, `S64-R6-5`
  - **Summary**: `i686rt` memory `BT`/`BTS`/`BTR`/`BTC` signed register bit offset, address-size `LOOP`/`JCXZ` and `XLAT`, and `SS` base in near `CALL`/`RET` (`I686-R6-1..2`, `I686-R6-5..6`), `rvrt` DBT division `mdst == mr2` divisor-zero check ordering (`RV-R6-1`), `ppc64rt` DBT `subfic`/`addic`/`addic.` reading `r0` when `RA=0` (`P64-R6-1`), and `sparc64rt` trapped FP exception destination preservation and `SIGFPE` (`SPARC64_TRAP_FPE`) delivery (`S64-R6-4..5`).
- [x] **X-R6-6 — Low/Medium — Intra-Repo DRY, YAGNI, CLEAN & `rt-series` Harness Validation**
  - **Linked Items**: `M32-R6-10`, `M32-R6-11`, `S32-R6-9`, `S32-R6-10`, `RV-R6-4`, `RV-R6-5`, `LA64-R6-7`, `LA64-R6-8`, `M64-R6-7`, `RTS-R6-1`, `RTS-R6-2`, `RTS-R6-3`, `RTS-R6-4`

---
## 1. `a32rt` (`0207c7b`) — 9 Round-6 Findings (`0 / 9` Resolved)

Found **nine remaining defects** at HEAD `0207c7b`. Used seven shell commands; read no Markdown and ran no builds or tests. Findings were checked against available remediation history, but novelty against unpublished or Markdown-only audit notes remains unverified.

- [x] **A32-R6-1 — DEFECT — HIGH**  
   **Location:** `src/os/os_sys_sock.c:498–534`  
   `sendmsg` validates ancillary lengths and sizes its buffer in one pass, then rereads guest-controlled lengths without validation in a second pass. Another guest thread can increase a length between passes, overflowing `cbuf_st` or `cbuf_dyn` at the payload `memcpy`. Changing a length below 12 also underflows `payload_len`.  
   **Fix:** Snapshot the message header and bounded ancillary bytes into owned memory, then validate and convert that snapshot with explicit source and destination bounds.

- [x] **A32-R6-2 — BUG — HIGH**  
   **Location:** `src/os/os_sys_thread_sig.c:595–603`  
   `uname` copies the host `struct utsname` directly into guest memory. On Darwin this is five 256-byte fields—1,280 bytes—whereas Linux ARM expects six 65-byte fields, totaling 390 bytes. This corrupts adjacent guest data when writable, returns spurious `EFAULT` near a mapping boundary, and places fields at incorrect offsets.  
   **Fix:** Define the Linux guest layout explicitly, zero-initialize it, and copy each host field into its corresponding bounded guest field.

- [x] **A32-R6-3 — BUG — HIGH**  
   **Location:** `src/os/sys_priv.h:592–598,765–767`  
   Host errors pass directly into the Linux guest ABI. Darwin `EAGAIN` is 35, but Linux ARM expects 11; Darwin `ENOSYS` is 78, but Linux expects 38. Consequently, nonblocking I/O and unsupported-syscall fallback logic receive unrelated errors. Both `host_ret` and `FAIL_ERR` are affected.  
   **Fix:** Introduce explicit Linux guest error constants and a Darwin-to-Linux errno conversion at host-error boundaries. Distinguish already-translated guest errors to avoid double conversion.

- [x] **A32-R6-4 — DEFECT — HIGH**  
   **Location:** `src/os/os_sys_sock.c:281–289`; `src/signals.c:732–755,436–440`  
   `signalfd4` creates a real host signalfd, but guest `rt_sigprocmask` only changes `ctx->sig_mask`. Host handlers consume arriving signals and move them into the emulator’s pending set. A guest that blocks `SIGUSR1`, creates a signalfd, then receives `SIGUSR1` can therefore wait indefinitely: the signal is pending internally, not available through the host descriptor.  
   **Fix:** Integrate signalfd reads and readiness with the guest pending-signal mechanism, or implement coordinated host masking and signal ownership that preserves guest delivery semantics.

- [x] **A32-R6-5 — DEFECT — HIGH**  
   **Location:** `src/os/os_sys_thread_sig.c:672–695`  
   `getcwd` checks only that the destination exceeds `0x1000` and that the supplied size is sufficient. It then calls `memcpy` without verifying writable guest pages. An unmapped, read-only, or boundary-crossing destination faults inside runtime code; the synchronous signal handler terminates faults outside translated blocks instead of returning `EFAULT`.  
   **Fix:** Validate the complete `len + 1` destination extent and use checked guest copyout.

- [x] **A32-R6-6 — DEFECT — HIGH**  
   **Location:** `src/os/os_sys_sock.c:260–266`  
   `memfd_create` validates one readable byte, then executes `strnlen(..., 250)` directly on guest memory. A non-NUL byte at the end of a readable page followed by an inaccessible page causes a runtime fault rather than `EFAULT`.  
   **Fix:** Copy the name through a bounded, page-aware guest-string reader into a local buffer, preserving the length-limit error, and pass that buffer to the host syscall.

- [x] **A32-R6-7 — BUG — MEDIUM**  
   **Location:** `src/os/os_sys_sock.c:209–215`  
   Darwin’s `statx` fallback serializes timestamps as access, modification, change, birth. Linux `statx` requires access at offset 64, **birth at 80**, change at 96, and **modification at 112**. Guest modification and birth times are therefore swapped. The layout comment at lines 184–186 repeats the mistake.  
   **Fix:** Serialize timestamps in Linux field order using named offsets or an explicitly defined guest structure; correct the comment.

- [x] **A32-R6-8 — BUG — MEDIUM**  
   **Location:** `src/os/os_sys_sock.c:165–179`  
   The Darwin `statx` fallback treats any request containing `AT_EMPTY_PATH` as `fstat(dirfd)`, ignoring the supplied pathname. For `statx(dirfd, "child", AT_EMPTY_PATH, ...)`, it returns the directory’s metadata instead of the child’s. An empty pathname with `AT_FDCWD` also incorrectly reaches `fstat(AT_FDCWD)`.  
   **Fix:** Inspect the pathname first. Use descriptor semantics only for an empty path, handle `AT_FDCWD` as the current directory, and resolve nonempty paths normally.

- [x] **A32-R6-9 — BUG — MEDIUM**  
   **Location:** `src/os/os_sys_thread_sig.c:777–798`  
   `getresuid32` and `getresgid32` treat their three output pointers as optional: zero bypasses validation and copyout, and the syscall returns success. These are required output pointers; an inaccessible NULL output must produce `EFAULT`.  
   **Fix:** Validate every required output address and perform checked guest stores, preserving Linux’s output ordering where partial writes matter.

These are static findings, not runtime reproductions. No additional DRY, YAGNI, or CLEAN finding was substantiated strongly enough within the inspection budget.

---

## 2. `i686rt` (`d4decf8`) — 8 Round-6 Findings (`8 / 8` Resolved)

Found **8 remaining defects** at HEAD `d4decf8`. Used exactly **7 shell commands**; read no Markdown and ran no builds, tests, Docker, or QEMU. Findings were compared against available Round 1–5 commit history; complete novelty against unread audit reports cannot be guaranteed.

- [x] **I686-R6-1 — BUG — HIGH**  
   **Location:** `src/interp/h_bit.c:51–79,126–149`  
   Memory BT/BTS/BTR/BTC mask the register bit index to the operand width before computing the address. Consequently, `bts [eax], ecx` with `ecx=32` modifies bit 0 at `[eax]` instead of `[eax+4]`; negative indices also address the wrong memory. DBT delegates these instructions to this handler (`src/dbt/emit_branch.c:655–663`).  
   **Fix:** Distinguish immediate and register indices. For memory register-index forms, sign-extend the operand-sized index and use its signed quotient to adjust the memory address; use the remainder to select the bit.

- [x] **I686-R6-2 — BUG — MEDIUM**  
   **Location:** `src/interp/h_branch.c:190–205,235–242`  
   LOOP/LOOPE/LOOPNE and JCXZ select CX versus ECX using **operand size**, although the counter selection depends on **address size**. In 32-bit code, `67 E3` with `ECX=0x00010000` should branch because CX is zero; this implementation tests ECX and falls through. DBT also reaches these handlers through fallback.  
   **Fix:** Select counter width using normalized `pfx_addrsize`, preserving ECX’s upper half when decrementing CX.

- [x] **I686-R6-3 — BUG — HIGH**  
   **Location:** `src/os/sys_thread.c:85–91`; `src/os/signals_i386.c:639–680`; `src/i686rt.h:180–181`  
   Pending-signal producers use ordinary `|=` while delivery uses ordinary `&=` on a `volatile uint64_t`. These are unsynchronized read-modify-write operations. Concurrent senders can overwrite each other’s signals, and delivery can erase a different signal arriving between its load and store. `volatile` provides no inter-thread synchronization. Cross-thread access to `sig_mask` is also unsynchronized.  
   **Fix:** Use consistently applied, signal-safe lock-free atomic operations for pending bits and synchronized mask access. Consume pending bits with atomic operations that preserve concurrently posted signals.

- [x] **I686-R6-4 — BUG — HIGH**  
   **Location:** `src/os/clone.c:649–698`  
   Copying the entire parent context also copies `clear_child_tid`, `pending_signals`, and robust-list registration. The child’s clear-TID address is only overwritten when `CLONE_CHILD_CLEARTID` is supplied. A child created without that flag can therefore clear the **parent’s** registered TID word during teardown (`src/os/clone.c:542–557`). Pending signals and robust-list registration likewise incorrectly survive into the new thread.  
   **Fix:** Explicitly initialize child-only lifecycle state after copying architectural state: clear pending signals, robust-list registration, and clear-TID address; populate the latter only from the requested clone flags.

- [x] **I686-R6-5 — DEFECT — HIGH**  
   **Location:** `src/interp/h_branch.c:84–100,143–180`  
   Near CALL/RET stack helpers access `guest_base + ESP` without adding the SS segment base. With a valid nonzero-base SS, CALL writes its return address to the wrong memory and RET reads its destination from the wrong memory. PUSH/POP already add SS (`src/interp/h_mov.c:359–375`), making ordinary stack operations inconsistent with calls and returns.  
   **Fix:** Route near CALL/RET through a shared, repository-local stack accessor that applies SS base, stack address size, and segment checks while preserving fault rollback.

- [x] **I686-R6-6 — BUG — MEDIUM**  
   **Location:** `src/interp/h_mov.c:334–343`  
   Address-size-16 XLAT masks BX before adding AL but never masks the resulting offset. With `BX=0xffff` and `AL=1`, it reads `DS.base+0x10000` instead of `DS.base+0`.  
   **Fix:** Compute `(BX + AL) & 0xffff` before adding the segment base when `pfx_addrsize` selects 16-bit addressing.

- [x] **I686-R6-7 — DEFECT — MEDIUM**  
   **Location:** `src/os/clone.c:137–149,716–729`  
   Once 64 thread registry entries exist, registration silently fails, but clone still releases the child and returns success. The running child then cannot be resolved by `tkill`, `tgkill`, or `get_robust_list`; targeted wakeups also depend on this registry.  
   **Fix:** Reserve registry capacity before launching the child. Either grow the registry or return `-EAGAIN` when capacity is exhausted, with proper rollback.

- [x] **I686-R6-8 — BUG — MEDIUM**  
   **Location:** `src/os/sys_pass_io.c:95–109`  
   The Darwin `dup3` implementation delegates to `dup2` without rejecting `oldfd == newfd`. For a valid descriptor, it returns success and may change `FD_CLOEXEC`, whereas Linux `dup3` must return `-EINVAL` without changing the descriptor.  
   **Fix:** Reject identical descriptors before invoking the host operation. Also propagate failure from the subsequent `F_SETFD` operation.

No separate DRY, YAGNI, or CLEAN finding met the evidence threshold within this inspection budget. The stack-helper duplication is directly relevant to R6-5’s fix; no cross-repository sharing is proposed.

---

## 3. `mips32rt` (`0e879ac`) — 11 Round-6 Findings (`0 / 11` Resolved)

Found **11 remaining issues** at confirmed HEAD `0e879ac`. Used exactly **7 shell invocations**; no Markdown reads, builds, tests, Docker, or QEMU. Findings are based on static inspection. Novelty was checked against available Round-1–5 commit descriptions and selected patches; unread audit reports prevent an absolute guarantee of no prior mention.

- [x] **M32-R6-1 — BUG — HIGH**  
   **Location:** `src/os/threads.c:164–198,295–298`; `src/os/fork.c:61–75`  
   **Fork can inherit a permanently locked reaper mutex.** `mips_reap_lock` is absent from fork coordination, and the child hook resets only the live counter. If another thread holds this mutex during `fork()`, the child's next clone blocks forever in `mips_reap_done()`.  
   **Fix:** Include the reaper mutex in fork preparation/release and rebuild child-side reaper ownership, taking care to preserve the surviving thread's stack.

- [x] **M32-R6-2 — BUG — HIGH**  
   **Location:** `src/os/threads.c:664–675,826–828`  
   **Big-endian `FUTEX_WAKE_OP_PRIVATE` loses its private flag.** The helper receives neither `priv` nor `host_op`; both wake calls hard-code plain `FUTEX_WAKE`. These use different futex keys from private waits, leaving waiters asleep despite a successful memory update.  
   **Fix:** Pass the private flag into the helper and preserve it in both wake operations.

- [x] **M32-R6-3 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:630–646,686–695,822–828`  
   **Big-endian `FUTEX_WAKE_OP` writes memory validated only for reading.** `futex_addr_ok()` requires `PROT_READ`, then the helper performs a direct host CAS. A read-only mapping can crash the translator; on host pages with broader aggregate permissions, it can modify guest-read-only memory. Concurrent unmapping adds another fault window.  
   **Fix:** Validate write permission and stabilize the mapping during the atomic update. Return guest `EFAULT` for inaccessible destinations.

- [x] **M32-R6-4 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:533–535,571–583`  
   **`pipe` and `pipe2` incorrectly share one ABI.** Legacy O32 `pipe` returns descriptors in `$v0/$v1` without a buffer argument, but this handler always copies through `$a0`, causing spurious `EFAULT` or unrelated memory corruption. Conversely, `pipe2` correctly uses a buffer but incorrectly returns the first descriptor instead of zero.  
   **Fix:** Separate completion paths: register-only results for legacy `pipe`; buffer copyout and zero return for `pipe2`.

- [x] **M32-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls_meta.c:135–143`; `src/os/syscalls.c:191–202`  
   **`F_SETFL` rejects ordinary write-only descriptors.** The usual `F_GETFL` → add `O_NONBLOCK` → `F_SETFL` sequence retains access mode `1`. OR-ing with `2U` produces mode `3`, which the converter rejects with `EINVAL`.  
   **Fix:** Clear access-mode bits before conversion, or use a dedicated converter for mutable status flags.

- [x] **M32-R6-6 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls.c:207–209,232–235`; `src/os/syscalls_priv.h:29–36`  
   **Valid `O_DSYNC` opens fail with `EINVAL`.** `MIPS_O_SYNC` includes the `O_DSYNC` bit. With `O_DSYNC` alone, the full-mask comparison fails but the following nonzero-mask comparison succeeds, incorrectly treating it as bare `__O_SYNC`.  
   **Fix:** Test the distinct `__O_SYNC` bit separately and accept `O_DSYNC` alone.

- [x] **M32-R6-7 — CLEAN — MEDIUM**  
   **Location:** `src/os/syscalls.c:613–621`  
   **The vectored-I/O scratch layout creates misaligned pointer accesses.** On the 64-bit target, `bases` occupies `4 * count` bytes after the aligned `iovec` array. For odd counts, `tmps` is only four-byte aligned, yet is accessed as an eight-byte pointer array. This violates C alignment requirements even where hardware tolerates unaligned accesses.  
   **Fix:** Place the pointer array before the `uint32_t` array, explicitly align its offset, or allocate a single array of appropriately aligned entry structs.

- [x] **M32-R6-8 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:476–502`; `src/os/signals.c:508–515`  
   **A normal `CLONE_VM` child inherits the parent's alternate signal stack.** The whole context is copied, but `sigalt_sp`, `sigalt_size`, and `sigalt_flags` are not reset. Parent and child can consequently build signal frames over the same memory. Linux clears the alternate stack for `CLONE_VM` without `CLONE_VFORK`.  
   **Fix:** Disable the child's alternate stack under that flag condition.

- [x] **M32-R6-9 — BUG — MEDIUM**  
   **Location:** `src/os/signals.c:741–748`  
   **An executing alternate signal stack can be disabled successfully.** The `SS_DISABLE` branch changes state and returns before the on-stack check. A handler running on that stack should receive `EPERM`; instead, subsequent signal-stack bookkeeping changes underneath it.  
   **Fix:** Check whether execution is on the active alternate stack before applying any requested stack change, including disabling it.

- [x] **M32-R6-10 — DRY — LOW**  
    **Location:** `src/rt32/elf32.c:174–240,519–550,610–653`  
    **Three paths independently decode and validate ELF headers.** Loading, interpreter measurement, and preflight validation repeat magic/class/endian checks and field swapping, with different subsets handled in each path. Admission changes therefore require synchronized edits.  
    **Fix:** Extract repository-local ELF/header decoding helpers and retain operation-specific checks in their callers. No cross-repository sharing is needed.

- [x] **M32-R6-11 — YAGNI — LOW**  
    **Location:** `src/os/backend_posix.c:319–340`; `src/os/backend.h:165–167`  
    **The host-worker alternate-stack API has no callers.** Repository searches found only declarations and definitions. Its “init” function merely allocates memory and does not register a signal stack, leaving an unused and misleading interface.  
    **Fix:** Remove these helpers and declarations until a concrete caller needs an implemented alternate-stack lifecycle.

---

## 4. `ppc32rt` (`540bf78`) — 7 Round-6 Findings (`0 / 7` Resolved)

Found **seven concrete remaining defects** at `540bf78`. Used exactly seven shell commands; no Markdown reads, builds, tests, Docker, or QEMU. Findings are static-analysis conclusions. Novelty was checked against remediation history and source diffs; excluding the earlier audit documents limits certainty that none was previously reported.

- [x] **P32-R6-1 — BUG — HIGH**  
   **Location:** `src/dbt/cache.c:383–391,483–523`; `src/dbt/dbt.c:629–638`  
   Concurrent guest threads share the translation cache, but eviction immediately unmaps code and frees its block. One thread can execute a block while another evicts it through a cache collision or invalidation. Invalidation also clears only the calling context’s IBTC/RAS pointers, leaving peer pointers dangling.  
   **Fix:** Synchronize cache mutation and protect executing blocks with deferred reclamation. Invalidate cached references across all participating contexts. A mutation lock alone does not protect ongoing JIT execution.

- [x] **P32-R6-2 — BUG — HIGH**  
   **Location:** `src/os/syscalls_dyn.c:197–201,220–255`  
   `dyn_getdents64()` uses one process-wide mutable `static` buffer. Concurrent directory reads overwrite that buffer while another thread parses it, mixing names, inode numbers, offsets, and record lengths between calls.  
   **Fix:** Allocate the fixed-size staging buffer per invocation or per thread.

- [x] **P32-R6-3 — DEFECT — HIGH**  
   **Location:** `src/main.c:441–446,472–479,519–524`  
   Guest `exit` and `exit_group` have the same termination path. A worker’s `exit_group` merely returns from that worker, leaving peers running. Conversely, the initial guest thread’s ordinary `exit` returns through `main`, terminating the host process and all remaining guest threads.  
   **Fix:** Implement distinct thread-exit and group-exit paths. Keep the process alive after initial-thread exit while guest peers remain; group exit must stop all peers and preserve the group status.

- [x] **P32-R6-4 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:391,533–536`  
   Clone copies the parent’s CR and sets the child’s `r3` to zero without clearing `CR0.SO`. If SO was set before `sc`, the child sees a successful clone return marked as an error. The parent receives normal return normalization; the child bypasses it.  
   **Fix:** Clear `PPC32_CR0_SO` when constructing the child’s successful syscall-return state.

- [x] **P32-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:254–268,465`; `src/os/signals.c:831–833`  
   `set_tid_address()` returns the native host TID, whereas `gettid()` returns the allocated guest TID. These can differ for cloned threads, exposing two identities for the same guest thread.  
   **Fix:** Return `ctx->guest_tid` from `set_tid_address()` and retain `host_tid` solely for host operations.

- [x] **P32-R6-6 — DEFECT — MEDIUM**  
   **Location:** `src/os/signals.c:842–864`  
   `tkill` and `tgkill` reject every target except the calling thread. With concurrent clones now enabled, targeting a live sibling—including an existence probe with signal zero—incorrectly returns `ESRCH`. This breaks inter-thread signaling and cancellation mechanisms.  
   **Fix:** Resolve guest TIDs through the synchronized thread registry, validate group membership, and queue delivery to the target with a mechanism to interrupt blocked execution.

- [x] **P32-R6-7 — DEFECT — HIGH**  
   **Location:** `src/os/syscalls_dyn.c:207–209,245–255`  
   `getdents64()` validates only numerical address bounds, then writes directly through unchecked scalar stores and `memcpy`. An unmapped destination can fault in the translator instead of returning `EFAULT`; on a shared host page, a guest read-only subpage can be overwritten. These writes also bypass the safe-copy path’s reservation invalidation and staged-file coherence.  
   **Fix:** Convert records in the invocation-local buffer, then use permission-checked `ppc32_vm_copyout_safe()` with explicit error/partial-result handling and appropriate code-cache invalidation.

---

## 5. `sparc32rt` (`c4a1e7a`) — 10 Round-6 Findings (`0 / 10` Resolved)

Found **10 remaining issues** at HEAD `c4a1e7a`. Used seven shell invocations; read no Markdown and ran no builds, tests, Docker, or QEMU. These are static findings. Novelty was checked against inspected Round-1–5 commit messages and patches; unread audit reports may contain additional overlap.

- [x] **S32-R6-1 — BUG — HIGH**  
   **Location:** `src/os/threads_fd.c:63–75`  
   If the first `realloc` succeeds and the second fails, `free(nu)` leaves `thr_fd_used` dangling while its old capacity remains published. Subsequent descriptor operations can access freed memory or pass it to `realloc` again.  
   **Fix:** Allocate and copy both replacement arrays before publishing either, or retain the successful first allocation safely when the second fails.

- [x] **S32-R6-2 — BUG — HIGH**  
   **Locations:** `src/rt32/stack32.c:245–247`; `src/os/threads_exec.c:175–177`; `src/rt32/procfs.c:208–220`  
   Stack setup saves the exec function’s local `argv`/`envp` arrays in `ctx`. Exec immediately frees their strings, and the arrays expire upon return. Later `/proc/self/cmdline` reads dereference dangling arrays and freed strings; `/proc/self/exe` also falls back to that dangling `argv` after `exec_path` is cleared.  
   **Fix:** Give process metadata explicit ownership and retain durable copies across exec, or read argument data from validated guest memory.

- [x] **S32-R6-3 — BUG — HIGH**  
   **Locations:** `src/os/futex.c:262–278,296–325`; `src/os/syscalls_time.c:269–294`  
   `futex_time64` strips `FUTEX_PRIVATE_FLAG` using `op & 15U`, whereas ordinary `futex` preserves it. A private waiter using one syscall and a wake using the other therefore use different host futex keys. The wake can return zero while the waiter remains blocked indefinitely.  
   **Fix:** Preserve supported flags consistently in both entry points and share their host dispatch logic.

- [x] **S32-R6-4 — DEFECT — HIGH**  
   **Location:** `src/rt32/stack32.c:160–170`  
   On Darwin, `if (0)` skips initialization of `rand_bytes` entirely, then copies uninitialized host stack bytes into guest `AT_RANDOM`. On Linux, an interrupted, short, or failed `getrandom` produces a fixed public byte pattern. This exposes host stack contents on Darwin and defeats entropy-dependent guest initialization on the fallback path.  
   **Fix:** Use the existing host entropy backend, handle partial reads and interruption, and fail initialization if secure entropy cannot be obtained.

- [x] **S32-R6-5 — BUG — HIGH**  
   **Locations:** `src/rt32/procfs.c:93–128,195–224`  
   Procfs writes the complete generated file into a blocking pipe before returning its read descriptor. If `/proc/self/cmdline` exceeds pipe capacity, the writer blocks before the guest can read anything. Large argument lists make this reachable.  
   **Fix:** Serve generated content from a seekable anonymous backing file or another mechanism that does not require a reader during `open`.

- [x] **S32-R6-6 — DEFECT — HIGH**  
   **Locations:** `src/rt32/procfs.c:34–57,307–314`  
   `procfs_copy_in` checks guest permissions and then dereferences guest memory without holding the VM reader guard. Concurrent `munmap` or `mprotect` can invalidate the pointer between those operations, causing a host fault during guest `readlink`/`readlinkat`.  
   **Fix:** Replace this duplicate string copier with the already guarded `l2a_copy_cstring` in `src/os/l2a_access.h:159–191`.

- [x] **S32-R6-7 — BUG — MEDIUM**  
   **Locations:** `src/os/syscalls.c:665–669,808–816`  
   Both statx implementations replace negative timestamp seconds with zero. A file timestamp before the Unix epoch silently changes to an epoch timestamp, while retaining its original nanoseconds.  
   **Fix:** Serialize the signed seconds as their full two’s-complement 64-bit representation without clamping.

- [x] **S32-R6-8 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls.c:863–874`  
   `F_SETFL` rejects every bit except `O_NONBLOCK` and `O_APPEND`, including access-mode bits returned by `F_GETFL`. Consequently, the ordinary `fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)` pattern fails for writable descriptors.  
   **Fix:** Ignore immutable access/open flags as appropriate and translate supported mutable status flags.

- [x] **S32-R6-9 — DRY — LOW**  
   **Locations:** `src/os/threads_exec.c:33–40`; `src/os/l2a_access.h:136–149`  
   `thr_ld` duplicates the existing checked big-endian word loader: guarded four-byte load, error propagation, and conversion. Maintaining both adds another place for access semantics to diverge.  
   **Fix:** Call `l2a_ld_be32` directly and remove `thr_ld`. This consolidation stays entirely within `sparc32rt`.

- [x] **S32-R6-10 — YAGNI — LOW**  
    **Locations:** `src/rt32/stack32.c:171–174,185–208`  
    Stack setup pushes `"sparc"` and checks its address, but never publishes that address in auxv or elsewhere. This is unused guest-stack data and an unnecessary failure condition.  
    **Fix:** Remove the allocation and variable unless an explicit platform auxv entry is intended; in that case, publish the entry.

---

## 6. `rvrt` (`8b57344`) — 5 Round-6 Findings (`5 / 5` Resolved)

Found **five findings** at HEAD `8b57344`. Used seven read-only shell invocations; no Markdown, builds, tests, Docker, or QEMU. Novelty was checked against available remediation commit messages and code diffs; exclusion from every historical finding cannot be guaranteed without the prior reports.

- [x] **RV-R6-1 — BUG — HIGH**  
   **Location:** `src/dbt_emit_m.c:110–120`, `:64–76`, `:139–151`  
   Division overwrites its divisor before checking for zero when `mdst == mr2`. The register mapping in `src/dbt_emit_fp.h:418–445` permits this when `rd == rs2`, and for distinct guest registers sharing a cache slot. For example, `div a1,a0,a1` with `a0=1, a1=2` produces quotient zero, then compares that overwritten divisor against zero and replaces the correct result with −1. This affects signed/unsigned division in RV32, RV64, and RV64 word forms.  
   **Fix:** Compare the original divisor before emitting division, preserving those flags through `CSEL`, or retain the divisor in a scratch register. Cover destination/divisor aliases and zero quotients.

- [x] **RV-R6-2 — BUG — HIGH**  
   **Location:** `src/linux/message.c:493–513`  
   `load_message()` accepts RV32’s 28-byte `msghdr`, but `update_header()` always writes RV64 offsets: flags at `+48`, eight-byte control length at `+40`, and name length at `+8`. RV32 requires four-byte fields at `+24`, `+20`, and `+4`. Successful receives therefore overwrite adjacent guest memory or return `EFAULT` after consuming data. A non-null name also causes the guest’s iovec pointer at `+8` to be read and overwritten as a length.  
   **Fix:** Select output offsets and widths with `rv_space_is32()`. Add adjacent-memory canaries and a header ending at a page boundary.

- [x] **RV-R6-3 — DEFECT — MEDIUM**  
   **Location:** `src/linux/message.c:230–244`, `:440–487`  
   Ancillary-data decoding and encoding always use a 16-byte header, eight-byte `cmsg_len`, and eight-byte alignment. RV32 requires a 12-byte header, four-byte length, and four-byte alignment. A valid RV32 single-fd `SCM_RIGHTS` message is rejected because `le64(control)` incorporates `cmsg_level` into the length. Receiving into the normal 16-byte RV32 buffer yields zero descriptor capacity and truncation; larger buffers receive malformed headers.  
   **Fix:** Implement guest-width-aware control-header offsets, length codecs, alignment, and payload capacity for both directions.

- [x] **RV-R6-4 — DRY — LOW**  
   **Location:** `src/loader/stack.c:103–118`, `:190–205`  
   RV32 and RV64 stack builders duplicate the complete `/dev/urandom` open/read/retry/close sequence and its failure handling. Changes to entropy acquisition must be maintained twice within the same file.  
   **Fix:** Extract one file-local helper that fills the 16-byte auxiliary-vector random payload, preserving short-read, `EINTR`, and close-error handling. Keep it entirely within `rvrt`.

- [x] **RV-R6-5 — YAGNI — LOW**  
   **Location:** `src/linux/message.c:42`, `:109–120`  
   `guest_message_t.input_flags` is populated for both ABIs but never read. Actual syscall flags come from `arguments[2]`; receive output flags are computed separately. The field misleadingly suggests that input `msg_flags` participates in processing.  
   **Fix:** Remove the field and both initializer assignments.

These are static findings, not runtime-verified reproductions. No files were changed.

---

## 7. `loongarch64rt` (`494c134`) — 8 Round-6 Findings (`8 / 8` Resolved)

Found **eight remaining issues** at verified HEAD `494c134`. Used **six shell commands**; no Markdown reads, builds, tests, Docker, or QEMU. Findings are static, not runtime-confirmed. Git remediation history was checked, but without the previous audit reports, “never reported in Rounds 1–5” cannot be fully established.

- [x] **LA64-R6-1 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:384–404`  
   **`statx` returns timestamps in the wrong fields.** With `at = dst + 64`, modification time is written at offset 96 (`stx_ctime`), and change time at offset 80 (`stx_btime`). Actual `stx_mtime` at offset 112 remains zero, despite `stx_mask` advertising basic timestamps. Both host branches contain the error. This can break timestamp-based rebuilds and synchronization.  
   **Fix:** Write ctime at offset 96 and mtime at 112, preferably through the already layout-asserted structure instead of relative numeric offsets.

- [x] **LA64-R6-2 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:505–506`, `src/os/syscalls.c:653–661`  
   **`fchownat` silently discards its flags argument.** Dispatch passes only `a0`–`a3` into `sys_at2`; the handler always supplies zero flags. Consequently, `AT_SYMLINK_NOFOLLOW` requests follow the symlink and can change ownership of its target instead. `AT_EMPTY_PATH` also cannot work.  
   **Fix:** Forward `a4`, validate guest flags, and translate supported flags to host constants before calling `fchownat`.

- [x] **LA64-R6-3 — DEFECT — HIGH**  
   **Location:** `src/os/clone.c:555–585`, `src/os/clone.c:447–470`  
   **`CLONE_CHILD_SETTID` never stores the child TID.** The flag causes pointer validation, but `ctid_va` is retained only for `CLONE_CHILD_CLEARTID`. Worker startup begins executing instructions without writing the requested TID. A guest using CHILD_SETTID without PARENT_SETTID observes an unchanged word.  
   **Fix:** Retain the CHILD_SETTID destination separately from the clear-on-exit destination and write the child’s guest TID before its first guest instruction.

- [x] **LA64-R6-4 — BUG — HIGH**  
   **Location:** `src/os/clone.c:532–541`, `src/os/clone.c:560–583`  
   **Failed clone setup leaves a nonexistent thread in the scheduler.** The child enters the scheduler ring before allocation. Allocation failure and subsequent guest-memory failures free/reset the clone slot but omit `la64_sched_abort_clone`. Once scheduling reaches that entry, no worker exists to advance the turn. The `pthread_create` failure path already performs the necessary rollback.  
   **Fix:** Use one cleanup path that removes scheduler registration on every failure after registration, or defer registration until other fallible setup has completed.

- [x] **LA64-R6-5 — BUG — HIGH**  
   **Location:** `src/os/clone.c:284–320`, `src/os/clone.c:329–339`  
   **The two futex waiter queues violate wake and requeue semantics.** Untimed waits use the cooperative queue; timed waits use the kernel queue. WAKE applies the full requested count independently to both, so `WAKE(1)` can wake two waiters. REQUEUE returns after processing only the cooperative queue whenever scheduling is engaged, leaving timed kernel waiters at the original address.  
   **Fix:** Coordinate both queues: subtract cooperative wakes from the kernel wake allowance and implement requeue across both populations. Prefer one consistent waiter implementation if feasible.

- [x] **LA64-R6-6 — BUG — MEDIUM**  
   **Location:** `src/os/clone.c:380–387`  
   **Darwin treats monotonic `FUTEX_WAIT_BITSET` deadlines as relative timeouts.** The absolute-deadline branch requires both WAIT_BITSET and CLOCK_REALTIME. Without CLOCK_REALTIME, an absolute monotonic timestamp is added to the current time, extending the wait by approximately host uptime.  
   **Fix:** Treat every WAIT_BITSET timeout as absolute. Use CLOCK_REALTIME only to select the clock; add the current time only for relative FUTEX_WAIT.

- [x] **LA64-R6-7 — DRY — LOW**  
   **Location:** `src/os/syscalls.c:362–418`, `src/os/backend_darwin_fs.c:253–323`  
   **Two independent `statx` serializers duplicate the same guest ABI layout and have diverged.** The syscall serializer misplaces timestamps; the Darwin backend uses the correct ctime/mtime offsets and preserves nanoseconds, which the syscall’s Darwin branch discards. Maintaining separate numeric-offset implementations makes further drift likely.  
   **Fix:** Consolidate guest `statx` serialization into one helper **within `loongarch64rt`**, with host-specific field extraction and named, asserted guest fields.

- [x] **LA64-R6-8 — YAGNI — LOW**  
   **Location:** `src/os/syscalls_mem.c:263–266`  
   **The O_WRONLY rejection is unreachable.** The preceding condition returns for every access mode other than O_RDWR, necessarily including O_WRONLY. The second check adds no protection and obscures which validation is authoritative.  
   **Fix:** Remove the redundant O_WRONLY branch.

No separate CLEAN finding is asserted merely because files approach 900 lines. This bounded inspection does not establish that the remaining code is defect-free.

---

## 8. `ppc64rt` (`28df326`) — 10 Round-6 Findings (`0 / 10` Resolved)

Found **10 remaining issues** at `28df326`. Used exactly **7 shell invocations**; no Markdown reads, builds, tests, Docker, or QEMU. Working tree was clean.

These findings were checked against available remediation history, but “never reported in Rounds 1–5” cannot be guaranteed without reading those reports. Findings 8–10 concern exported backend functions; I found no live guest-dispatch callers for them.

- [x] **P64-R6-1 — BUG | HIGH**  
   **Location:** `src/dbt/emit_int.c:210–225`  
   DBT treats `RA=0` as literal zero for `subfic`, `addic`, and `addic.`. These instructions must read GPR0, as the interpreter correctly does. With GPR0=5, `subfic r3,r0,7` produces 7 instead of 2; carry and record flags can also differ.  
   **Fix:** Unconditionally load `d->ra` in this branch. Keep zero-base handling confined to `addi`/`addis`.

- [x] **P64-R6-2 — BUG | HIGH**  
   **Locations:** `src/os/proc.c:795–809`; `src/os/fd_table.c:103–114`  
   Repeated stdio redirection closes the newly installed descriptor. After the first `dup2(fd,1)`, the table stores host fd 1. A subsequent redirection first replaces host fd 1, then `syscall_fd_replace()` drops the previous table entry—which also names fd 1—closing the replacement. The syscall reports success with a closed destination.  
   **Fix:** Make replacement ownership-aware: never close the incoming descriptor when the existing entry names that same descriptor.

- [x] **P64-R6-3 — BUG | HIGH**  
   **Location:** `src/os/syscalls.c:460–482`  
   Chunked `read` can block after successfully reading available pipe data. With exactly 512 bytes available, an open writer, and a guest request for 1024 bytes, the first host read fills the chunk and the loop issues another blocking read. A normal pipe read could return the available 512 bytes immediately. Request/response protocols can deadlock here.  
   **Fix:** Preserve one-read semantics through suitable staging, or ensure subsequent collection cannot block after any bytes have been obtained.

- [x] **P64-R6-4 — DEFECT | HIGH**  
   **Locations:** `src/os/syscalls.c:244–269`, `388–408`  
   Guest writes are split into independent 512-byte host writes; `writev` additionally splits at every vector boundary. This loses pipe atomicity even for a guest operation whose total size is within `PIPE_BUF`. Concurrent process writers can interleave fragments of records that should remain contiguous.  
   **Fix:** Stage bounded atomic pipe writes and submit them in one host `write`/`writev` operation. Preserve the atomicity of the entire vector, not individual elements.

- [x] **P64-R6-5 — BUG | MEDIUM**  
   **Location:** `src/os/syscalls.c:408–417`  
   `writev` returns an error from a later vector even when earlier vectors have already written bytes. For example, a valid first vector followed by an inaccessible buffer writes the first payload but reports `EFAULT`. Retrying can duplicate output.  
   **Fix:** Once `total > 0`, return successful partial progress for subsequent payload faults or host I/O errors. Validate vector metadata before producing output.

- [x] **P64-R6-6 — DRY | MEDIUM**  
   **Locations:** `src/os/syscalls_misc.c:47–70`; `src/os/proc.c:243–279`; `src/os/backend_linux.c:69–118`; `src/os/backend_darwin.c:64–110`  
   Several repository-local errno translators have diverged. In particular, `syscall_host_to_linux()` lacks `EINTR`, so the explicit interrupted-`pwrite` branch at `src/os/syscalls.c:340–344` returns `EIO`. The backend tables also turn unmapped errors such as `ENOSPC` into `EINVAL`.  
   **Fix:** Consolidate translation **within `ppc64rt`**. Preserve Linux errno values on Linux and provide a complete mapping for supported operations on Darwin; route syscall helpers through it.

- [x] **P64-R6-7 — DEFECT | MEDIUM**  
   **Location:** `src/os/proc.c:727–736`  
   `pipe2` validates guest flags against host `O_CLOEXEC` and `O_NONBLOCK`. Darwin uses different numeric values, so valid Linux guest flags are rejected or interpreted incorrectly. Other file paths already distinguish guest and host constants.  
   **Fix:** Validate against explicit PPC64 Linux flag values, then translate to host flags before calling `fcntl`.

- [x] **P64-R6-8 — DEFECT | MEDIUM**  
   **Locations:** `src/os/backend_net.c:127–148`, `160–168`  
   Sockaddr conversion assumes the first two bytes are a host `uint16_t` family. Darwin instead stores a length byte followed by a family byte. Writing `AF_INET` as a little-endian 16-bit value sets the Darwin family byte to zero; reverse conversion likewise misreads the header.  
   **Fix:** Construct and decode host sockaddr headers explicitly for each platform, including Darwin length fields and family-specific size validation.

- [x] **P64-R6-9 — BUG | MEDIUM**  
   **Location:** `src/os/backend_net.c:151–169`  
   `xlate_addr_out()` respects the supplied capacity for its initial copy, then unconditionally reads and writes two bytes through the destination. Capacities of zero or one therefore cause out-of-bounds access. It also reports the copied length instead of the actual address length when truncation occurs.  
   **Fix:** Convert into a local buffer, copy only the caller’s capacity, and return the complete converted address length separately.

- [x] **P64-R6-10 — DEFECT | MEDIUM**  
    **Location:** `src/os/backend_net.c:515–534`  
    The Linux `ppoll` implementation uses `SIG_BLOCK`, ordinary `poll`, then `SIG_UNBLOCK`. This neither atomically installs the requested temporary mask nor restores the previous mask. A signal already blocked before entry becomes unblocked afterward; signals omitted from the temporary mask remain blocked during the wait.  
    **Fix:** Use native `ppoll` with the translated mask and original timespec, integrated with the worker’s interruption protocol. This also avoids the current millisecond truncation and one-day timeout cap.

No additional YAGNI or CLEAN finding was established strongly enough to include under this inspection budget.

---

## 9. `mips64rt` (`a37e353`) — 7 Round-6 Findings (`0 / 7` Resolved)

Found seven concrete issues at HEAD `a37e353`. These appear distinct from the Round 1–5 fixes inspected in Git history; full deduplication against prior reports remains unverified because Markdown was excluded.

- [x] **M64-R6-1 — BUG — HIGH**  
   **Location:** `src/os/futex.c:460–468`, `src/os/futex.c:538–539`  
   Linux futex comparisons receive guest logical values without converting them to the host representation of guest memory. For a big-endian guest on little-endian AArch64, a futex containing `1` is read by the kernel as `0x01000000`; `WAIT` therefore returns `EAGAIN` despite the preceding guest-aware comparison succeeding. `CMP_REQUEUE` has the same problem.  
   **Fix:** Convert expected memory-word values to host byte order before invoking the host futex. Preserve bitset masks and counts unchanged.

- [x] **M64-R6-2 — BUG — HIGH**  
   **Location:** `src/os/futex.c:513–539`  
   Plain `FUTEX_REQUEUE` leaves `nrq == NULL`, passing a requeue count of zero to Linux. The code incorrectly treats `val3` as its requeue count; both requeue operations take that count from the fourth syscall argument. A request to move waiters without waking them silently moves none, potentially leaving them blocked indefinitely.  
   **Fix:** Decode and validate the fourth argument as the requeue count for both operations; ignore `val3` for plain `REQUEUE`.

- [x] **M64-R6-3 — BUG — MEDIUM**  
   **Location:** `src/os/futex.c:521–528`  
   `CMP_REQUEUE` rejects every expected word greater than `INT_MAX`. Its comparison operand is a full 32-bit value, so valid words such as `0x80000000` incorrectly produce `EINVAL`.  
   **Fix:** Apply signed count validation only to wake/requeue counts. Accept the complete `uint32_t` range for the comparison operand.

- [x] **M64-R6-4 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:394–422`, `src/os/threads.c:447–462`  
   Process clone drops `stack_va` and `tls_va` when dispatching to `l4b_clone_fork`. Consequently, a successful non-`CLONE_VM` clone with a supplied child stack or `CLONE_SETTLS` resumes with the parent's stack or TLS. Child execution can access the wrong stack objects or thread-local state.  
   **Fix:** Pass both arguments into the process-clone helper. In the child, install a nonzero requested stack and apply TLS when `CLONE_SETTLS` is set.

- [x] **M64-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:297–300`, `src/os/threads.c:400–403`  
   Both clone paths validate parent/child TID pointers unconditionally. When their corresponding flags are absent, those argument registers are ignored by the guest ABI and may contain arbitrary values. Such otherwise-valid clones incorrectly fail with `EFAULT`.  
   **Fix:** Gate TID-pointer handling on the applicable clone flags; do not validate unused arguments.

- [x] **M64-R6-6 — DEFECT — MEDIUM**  
   **Location:** `src/os/futex.c:281–291`  
   Relative timeout conversion performs unchecked signed addition of monotonic seconds and guest-controlled seconds. The timeout parser accepts `INT64_MAX`, so a valid nonnegative N64 timeout can overflow `time_t` on the intended 64-bit host, invoking C undefined behavior or becoming an immediate timeout. Nanosecond normalization can also overflow the seconds field.  
   **Fix:** Use checked, saturating deadline arithmetic, including the nanosecond carry. Apply equivalent checks to the Darwin deadline helper at `src/os/futex.c:135–162`.

- [x] **M64-R6-7 — YAGNI — LOW**  
   **Location:** `src/os/threads.c:552`, `src/os/threads.c:687–698`  
   The thread-local `l4b_ctx` is assigned and cleared but never read anywhere in `src`. Its surrounding comment describes a context-based fault-reporting mechanism that the implementation no longer uses.  
   **Fix:** Remove the variable and its assignments; update the comment to describe the actual host-PC resolution path.

Exactly four shell commands were used. No Markdown, builds, tests, Docker, or QEMU were run. This is a bounded static audit, not exhaustive coverage of all five categories.

---

## 10. `sparc64rt` (`1fc64d4`) — 9 Round-6 Findings (`0 / 9` Resolved)

Found **nine actionable issues** at HEAD `1fc64d4`. Used exactly **seven shell commands**; read no Markdown and ran no builds, tests, Docker, or QEMU. Findings are distinct from fixes described in the inspected Round-1–5 commit history; novelty against the full prior reports remains unverified.

- [x] **S64-R6-1 — DEFECT — HIGH**  
   **Location:** `src/os/syscalls_ext.c:438–440`  
   The `F_SETFL` nonblocking condition has an unmatched opening parenthesis: the outer `if (` remains open when `{` appears. This translation unit is syntactically invalid.  
   **Fix:** Simplify the condition to a single masked test for the supported nonblocking bits, or restore the missing closing parenthesis. Identified by inspection; no compiler was run.

- [x] **S64-R6-2 — BUG — HIGH**  
   **Locations:** `src/os/guest_engines.c:238–258,302–333`; `src/os/syscalls_min.c:190–199`; `src/os/syscalls_ext.c:319–327`  
   Both engines hold `thr_big_lock` while dispatching blocking host I/O. An empty-pipe read can therefore block while the guest thread responsible for writing that pipe cannot acquire the execution lock. The same problem affects blocking writes and vectored I/O.  
   **Fix:** Stage syscall inputs under the lock, release it around blocking host operations, and reacquire it before guest-memory access. Restore window-cache and DBT ownership/invalidation state on reacquisition.

- [x] **S64-R6-3 — BUG — HIGH**  
   **Location:** `src/os/syscalls_ext.c:327–354`  
   `readv` consumes host input before checking whether its guest destinations are writable. An unmapped first destination consumes pipe data and then returns `EFAULT`; a bad later destination can consume more bytes than the reported partial count. The earlier `l2a_range_ok` checks only address bounds.  
   **Fix:** Validate and prepare writable destinations before consuming input, and limit the host transfer to destinations that can receive it. Preserve partial-transfer semantics without discarding unreported bytes.

- [x] **S64-R6-4 — BUG — HIGH**  
   **Locations:** `src/interp/fp_conv.c:187–194,249–262`; `src/interp/fp.c:260–261`; `src/interp/fp_commit.c:18–23`  
   FP operations publish destination registers—or comparison condition codes—before checking enabled exceptions. For example, an invalid conversion with invalid-operation trapping enabled overwrites its destination before returning a trap. The commit helper also updates accrued exceptions before deciding whether the instruction traps.  
   **Fix:** Compute results into temporaries, resolve enabled exceptions first, and publish destination/FCC state only for nontrapping execution. Apply the architectural trapped-versus-completed FSR update rules separately.

- [x] **S64-R6-5 — DEFECT — HIGH**  
   **Locations:** `src/interp/fp_commit.c:21–23`; `src/os/sync_sig.c:323–327,350–377`  
   Enabled FP exceptions become `SPARC64_TRAP_ILLEGAL`. Signal classification maps that to `SIGILL`, and its raw-instruction refinement recognizes integer division and trap instructions but no FP operations. Consequently, an FP exception reaches the wrong signal handler.  
   **Fix:** Introduce an explicit FP exception cause and carry sufficient exception information to deliver `SIGFPE` with the appropriate `FPE_FLT*` code.

- [x] **S64-R6-6 — DEFECT — MEDIUM**  
   **Locations:** `src/os/syscalls_min.c:456–457`; `src/os/syscalls_dirent.c:117–123`  
   The original Linux `faccessat` syscall takes three arguments, but dispatch interprets `%o3` as flags. That unused register can contain arbitrary caller state, causing valid calls to return `EINVAL` or unexpectedly request no-follow behavior.  
   **Fix:** Pass zero flags for `faccessat`; consume the fourth argument only in a separate `faccessat2` dispatch.

- [x] **S64-R6-7 — DEFECT — MEDIUM**  
   **Location:** `src/os/syscalls_ext.c:657–679`  
   `TCGETS` returns success for a terminal without writing any termios data. Thus `tcgetattr` can succeed with an unchanged or uninitialized output structure. An invalid output pointer also succeeds when the descriptor names a terminal.  
   **Fix:** Fetch host termios, translate its flags, speeds, and control characters into the SPARC layout, and copy it through checked guest-memory callbacks.

- [x] **S64-R6-8 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls_ext.c:375–404`  
   `F_GETFL` translation omits supported status flags such as `O_PATH` and `O_DIRECTORY`. Opening with `SP_O_PATH` succeeds, but querying the resulting descriptor loses that property. The `O_SYNC` test also treats any overlapping bit as full synchronous mode, misreporting a host descriptor with only `O_DSYNC`.  
   **Fix:** Translate all applicable status flags supported by the open path, and distinguish composite `O_SYNC` from `O_DSYNC` using full-mask equality.

- [x] **S64-R6-9 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls_ext.c:493–511`  
   `clock_getres(valid_clock, NULL)` should succeed without copying a result. This implementation always calls `store_timespec`, attempting a guest write at address zero and normally returning `EFAULT`.  
   **Fix:** After validating/querying the clock, return success when `is_res && tp_va == 0`; retain mandatory output-pointer handling for `clock_gettime`.

No additional DRY, YAGNI, or CLEAN finding met the evidence and novelty threshold within this inspection budget. This was a bounded static audit, not whole-tree qualification.

---

## 11. `rt-series` (`3f4602c`) — 4 Round-6 Findings (`0 / 4` Resolved)

Found four remaining issues at `3f4602c`. Exactly four shell commands were used; no Markdown files, builds, tests, Docker, or QEMU were run. These are fresh static findings, but novelty against all Round 1–5 entries remains unverified because those finding lists were excluded.

- [x] **RTS-R6-1**
   - **Category:** BUG
   - **Severity:** MEDIUM
   - **Location:** `tools/run_grind.sh:825–835`
   - **Finding:** Weekly execution ignores `--suite` for the soak workloads. Every `weekly --suite <name>` invocation unconditionally runs `run_weekly_soak`, which can execute Csmith, Yarpgen, and a 1,800-second upstream check. An unrelated failure can therefore fail a narrowly selected suite.
   - **Fix:** Apply `want_suite` separately to Csmith, Yarpgen, and upstream-check; execute all three only for `--suite all`. Validate suite names before running jobs.

- [x] **RTS-R6-2**
   - **Category:** CLEAN
   - **Severity:** MEDIUM
   - **Location:** `tools/run_grind.sh:11–14`, `486–487`, `675–676`, `739–740`
   - **Finding:** The EXIT cleanup glob ends in `_<pid>`, but several temporary files end in `_<pid>.c`, `_<pid>.out`, or `_<pid>.log`. Interruption before explicit per-suite cleanup leaves generated sources and differential output behind. Only the libc/LTP logs receive explicit suffix-aware cleanup.
   - **Fix:** Allocate one private `mktemp -d` directory per invocation, place every temporary artifact inside it, and remove that directory from the traps.

- [x] **RTS-R6-3**
   - **Category:** BUG
   - **Severity:** MEDIUM
   - **Location:** `tools/remote_bench.sh:21–22`, `44–91`; `tools/remote_linux_inner.sh:21–22`, `33–39`
   - **Finding:** Neither dispatcher validates its selector. An unknown remote phase, such as `darwn`, skips every execution block and exits successfully. An unknown inner `KIND` likewise runs no benchmark and returns success. Automation can mistake a misspelled invocation for a completed campaign.
   - **Fix:** Validate `PHASE` and `KIND` with explicit `case` allowlists and exit 2 for unsupported values. Also require at least one executed benchmark before returning success.

- [x] **RTS-R6-4**
   - **Category:** DEFECT
   - **Severity:** MEDIUM
   - **Location:** `tests/p3_torture.c:581–589`
   - **Finding:** The newly added deliberate faulting store uses ordinary `memcpy` into memory whose contents are never subsequently checked. Unlike the volatile probes added to `t_mprotect_munmap`, this store has no compiler-enforced observable access. Optimization can eliminate it, causing the test to report “RO cross-page store did not trap” without exercising the translator’s store path.
   - **Fix:** Use an architecture-appropriate explicit store probe with compiler-visible side effects and a memory clobber. Preserve the intended cross-page access width; substituting bytewise volatile writes would test a different operation.

---

## Part III — Round-5 Completed Checklist Archive (`109 / 109` Resolved — 100% Complete)

### 0.1 Round 5 Audit Matrix (`109 / 109` Resolved — 100% Complete)

Following complete remediation, `fable` (`claude-fable-5-1`) verification review, and `muse` post-review follow-up across Round 1 (`187` items), Round 2 (`145` items), Round 3 (`85` items), and Round 4 (`125` items), Round 5 performed a fresh `gpt-6-astra` static audit of all 11 repositories at their post-Round-4 `HEAD` commits (`109` findings: `0 Critical`, `65 High`, `26 Medium`, `18 Low`).

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | DRY | YAGNI | CLEAN | **R5 Total** | Raw Round-5 `astra` Transcript |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `acd2834` | 6 | 3 | 1 | 6 | 1 | 1 | 1 | 1 | **10 / 10** | [`2026-11-03-defects-r5-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r5-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `e993289` | 7 | 2 | 2 | 7 | 2 | 1 | 1 | 0 | **11 / 11** | [`2026-11-03-defects-r5-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r5-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `aa2eb8e` | 8 | 1 | 2 | 6 | 3 | 1 | 1 | 0 | **11 / 11** | [`2026-11-03-defects-r5-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r5-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `a091b8f` | 9 | 0 | 2 | 8 | 1 | 1 | 1 | 0 | **11 / 11** | [`2026-11-03-defects-r5-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r5-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `edfcf6f` | 8 | 2 | 2 | 5 | 5 | 1 | 1 | 0 | **12 / 12** | [`2026-11-03-defects-r5-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r5-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `841d562` | 2 | 3 | 2 | 2 | 3 | 1 | 1 | 0 | **7 / 7** | [`2026-11-03-defects-r5-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r5-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `1256d4b` | 6 | 2 | 1 | 6 | 2 | 1 | 0 | 0 | **9 / 9** | [`2026-11-03-defects-r5-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r5-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `69d193a` | 6 | 2 | 2 | 6 | 2 | 1 | 1 | 0 | **10 / 10** | [`2026-11-03-defects-r5-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r5-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `e8f6ffe` | 6 | 4 | 1 | 7 | 3 | 1 | 0 | 0 | **11 / 11** | [`2026-11-03-defects-r5-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r5-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `750b805` | 4 | 3 | 2 | 4 | 2 | 1 | 1 | 1 | **9 / 9** | [`2026-11-03-defects-r5-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r5-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `448a548` | 3 | 4 | 1 | 4 | 3 | 0 | 0 | 1 | **8 / 8** | [`2026-11-03-defects-r5-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r5-rt-series-astra.md) |
| | **Total (Round 5)** | | | **65** | **26** | **18** | **61** | **27** | **10** | **8** | **3** | **109 / 109** | |

### 0.2 Round 5 Cross-Cutting Defect Clusters (Cross-Runtime Check Index)

- [x] **X-R5-1 — High — Retained Inode FD Access-Mode Mismatch (`O_RDONLY` vs `O_RDWR`), Staged `MAP_SHARED` Store/Read Coherence & Darwin Sub-Page Backing Preservation**
  - **Linked Items**: `A32-R5-2`, `A32-R5-7`, `I686-R5-8`, `M32-R5-7`, `P32-R5-6`, `P32-R5-7`, `S32-R5-8`, `S32-R5-9`, `RV-R5-3`, `RV-R5-4`, `LA64-R5-1`, `LA64-R5-2`, `LA64-R5-3`, `LA64-R5-4`, `LA64-R5-6`, `P64-R5-5`, `P64-R5-6`, `M64-R5-2`, `M64-R5-7`, `M64-R5-8`
  - **Summary**: Inode-level descriptor caching reusing an `O_RDONLY` or `O_WRONLY` descriptor for subsequent writable/readable mappings (`P32-R5-7`, `LA64-R5-3`, `P64-R5-5..6`), staged `MAP_SHARED` store/read propagation and `pread`/`pwrite` error/short-read handling (`M32-R5-7`, `P32-R5-6`, `LA64-R5-2`, `M64-R5-2`), Darwin sub-page replacement and partial-page file overlay (`A32-R5-2`, `RV-R5-3`, `LA64-R5-6`), and transactional `munmap`/`mremap`/region-table rollback (`A32-R5-7`, `I686-R5-8`, `S32-R5-8..9`, `LA64-R5-1`, `LA64-R5-4`, `M64-R5-7..8`).
- [x] **X-R5-2 — High — Syscall Socket (`sendmsg`/`recvmsg`/`sendmmsg`/`recvmmsg`/`select`) & Vectored I/O (`readv`/`writev`) Marshalling, Atomicity & Copyout Permission Checks**
  - **Linked Items**: `A32-R5-3`, `A32-R5-4`, `A32-R5-5`, `I686-R5-4`, `I686-R5-5`, `I686-R5-6`, `I686-R5-7`, `I686-R5-9`, `M32-R5-6`, `P32-R5-3`, `P32-R5-4`, `P32-R5-5`, `M64-R5-1`, `M64-R5-10`, `S64-R5-1`, `S64-R5-2`, `S64-R5-3`, `S64-R5-5`, `S64-R5-6`
  - **Summary**: `sendmsg` writing to read-only guest headers (`A32-R5-3`), ancillary `SCM_RIGHTS` truncation/drop (`A32-R5-4`, `I686-R5-5`), `select` >1024-fd host-word overrun (`A32-R5-5`), `i686rt` socket message marshalling/timeout/copyout checks (`I686-R5-4..7`, `I686-R5-9`), `readv`/`writev` chunking and descriptor snapshot (`M32-R5-6`, `P32-R5-3..5`, `S64-R5-3`), `mips64rt` `clock_nanosleep` & `clock_getres` dispatch (`M64-R5-1`, `M64-R5-10`), and `sparc64rt` composite open flags, `F_SETFL`, and `statx` negative timestamps (`S64-R5-1..2`, `S64-R5-5..6`).
- [x] **X-R5-3 — High — Thread Lifecycle, Futex Emulation/Endianness/Requeue, Signal Queue Ownership & Synchronous vs Asynchronous Delivery**
  - **Linked Items**: `M32-R5-2`, `M32-R5-3`, `M32-R5-4`, `M32-R5-5`, `P32-R5-1`, `P32-R5-8`, `P32-R5-9`, `S32-R5-3`, `S32-R5-4`, `S32-R5-5`, `S32-R5-6`, `S32-R5-7`, `S32-R5-10`, `M64-R5-5`
  - **Summary**: `mips32rt` BE futex value endianness, `REQUEUE`/`WAKE_OP` `val2` count, clone reaper lifecycle, and O32 robust list teardown (`M32-R5-2..5`), `ppc32rt` synchronous `clone(CLONE_VM)` execution, self-directed blocked signal queueing, and callback thread joinability (`P32-R5-1`, `P32-R5-8..9`), `sparc32rt` `rt_sigsuspend` process vs thread signal queue ownership, default-fatal signal handling, `SA_SIGINFO` frame fields, and futex slot recycling (`S32-R5-3..7`, `S32-R5-10`), and `mips64rt` thread-group leader `SYS_exit` vs `SYS_exit_group` (`M64-R5-5`).
- [x] **X-R5-4 — High — Interpreter/DBT Permission Enforcement (`PROT_EXEC`, A2 Sub-Pages), Exclusive Store ABA & Precise Fault State**
  - **Linked Items**: `A32-R5-1`, `A32-R5-6`, `I686-R5-2`, `I686-R5-3`, `M32-R5-1`, `P32-R5-2`, `S32-R5-1`, `S32-R5-2`, `RV-R5-1`, `RV-R5-2`
  - **Summary**: `a32rt` interpreter fetch checking `PROT_EXEC` (`A32-R5-1`) and software `STREX` ABA exclusion (`A32-R5-6`), `i686rt` `LDMXCSR` reserved bits fault and `LOCK`-prefixed shift `#UD` (`I686-R5-2..3`), `mips32rt` A2 sub-page permission enforcement in DBT (`M32-R5-1`), `ppc32rt` FP load/store fault preserving FPR/RA/`nip` (`P32-R5-2`), `sparc32rt` `LDDF`/`STDF` alignment & fault width classification (`S32-R5-1..2`), and `rvrt` Soft-TLB emitter scratch-register/offset validation (`RV-R5-1..2`).
- [x] **X-R5-5 — High — ISA / FPU Rounding, Exception Flags (`Cause` vs Sticky `Flags`, SNaN `CVT`), Prefix Decoding & ELF Loader Bounds/Entropy Validation**
  - **Linked Items**: `I686-R5-1`, `M32-R5-8`, `LA64-R5-5`, `LA64-R5-7`, `P64-R5-1`, `P64-R5-2`, `P64-R5-3`, `P64-R5-4`, `P64-R5-7`, `M64-R5-3`, `M64-R5-4`, `M64-R5-6`, `S64-R5-4`
  - **Summary**: `i686rt` SSE directed rounding adjustment (`I686-R5-1`), `mips32rt` reserved `CVT.S.S`/`CVT.D.D` rejection (`M32-R5-8`), `loongarch64rt` DBT FCSR `Cause` vs sticky `Flags` separation and malformed `PT_INTERP` rejection (`LA64-R5-5`, `LA64-R5-7`), `ppc64rt` `PLHA` sign extension, prefixed scalar FP `rt` decoding, `PLXSD` vs `PLHA` dispatch, and unsigned branch displacement shifts (`P64-R5-2..4`, `P64-R5-7`), `mips64rt` `CVT.S.D`/`CVT.D.S` SNaN `FP_EXC_V`, `CFC1` sign-extension, and OS CSPRNG `AT_RANDOM` (`M64-R5-3..4`, `M64-R5-6`), and overflow-safe ELF header/bias validation (`P64-R5-1`, `S64-R5-4`).
- [x] **X-R5-6 — Medium — Intra-Repo DRY, YAGNI, CLEAN, Differential/Parity Test Verification & `rt-series` Harness**
  - **Linked Items**: `A32-R5-8`, `A32-R5-9`, `A32-R5-10`, `I686-R5-10`, `I686-R5-11`, `M32-R5-9`, `M32-R5-10`, `M32-R5-11`, `P32-R5-10`, `P32-R5-11`, `S32-R5-11`, `S32-R5-12`, `RV-R5-5`, `RV-R5-6`, `RV-R5-7`, `LA64-R5-8`, `LA64-R5-9`, `P64-R5-8`, `P64-R5-9`, `P64-R5-10`, `M64-R5-9`, `M64-R5-11`, `S64-R5-7`, `S64-R5-8`, `S64-R5-9`, `RTS-R5-1..8`

---

## 1. `a32rt` (`acd2834`) — 10 Round-5 Findings (`10 / 10` Resolved)

Found **10 actionable findings**. Used exactly **8 read-only shell commands**; no Markdown reads, builds, tests, Docker, or QEMU. These are static findings, not reproduced failures. Inspection covered the requested areas selectively; no `rt32/` or `family/` paths were found. Family-related state resides in `vm_file.c`.

1. **[A32-R5-1] BUG — Interpreter instruction fetch ignores execute permission.**  
   **Evidence:** [src/interp/interp.c:108](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:108), lines 108–115 and 141–158; dispatch at line 194.  
   Both instruction-fetch helpers call `i_load_bytes()`, which checks only `PROT_READ`. Consequently, readable guest data can execute without `PROT_EXEC`, while execute-only pages fail the read check.  
   **Fix:** Separate instruction fetch from data loads, validate guest execute permission across the complete instruction, and retain the correct fault PC. Add A32 and Thumb cases for readable/non-executable and execute-only mappings.

2. **[A32-R5-2] BUG — Darwin sub-page replacement destroys neighboring shared backing.**  
   **Evidence:** [src/os/backend_darwin.c:108](/Users/angerman/Projects/zw3rk/a32rt/src/os/backend_darwin.c:108), lines 108–150; replacement admission at [src/vm.c:641](/Users/angerman/Projects/zw3rk/a32rt/src/vm.c:641).  
   The replacement path snapshots an entire host page, replaces it with `MAP_PRIVATE | MAP_ANONYMOUS`, and copies neighboring bytes back. This preserves bytes but loses their backing identity. For example, replacing one 4 KiB quarter of a 16 KiB shared mapping makes the surviving quarters private, although their tracking records still describe shared mappings.  
   **Fix:** Preserve shared backing for unaffected sub-pages. Until that is supported, reject this mixed-backing replacement before retiring any mapping. Cover visibility through a second mapping and across `fork()`.

3. **[A32-R5-3] BUG — Successful `sendmsg` writes to its read-only input header.**  
   **Evidence:** [src/os/os_sys_sock.c:474](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:474), lines 474–475 and 537–541.  
   `sendmsg` validates the header for reading, but the common success path writes `msg_namelen` and `msg_flags` for both sending and receiving. A valid header on a read-only page therefore faults after the message has already been sent; on permissive host pages, it silently modifies guest input.  
   **Fix:** Restrict header copyout to `recvmsg`. Add a read-only-header case; the existing [socket test at line 93](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m5_ltp_gdb.c:93) uses a writable stack header.

4. **[A32-R5-4] BUG — Ancillary data is silently dropped when sending.**  
   **Evidence:** [src/os/os_sys_sock.c:491](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:491), lines 491–518.  
   Conversion uses a fixed 1,024-byte host buffer. When the next control message does not fit, the loop simply breaks and sends the converted prefix successfully. Valid control data can disappear without an error. A legal 253-descriptor `SCM_RIGHTS` message alone requires more than this buffer after host-header expansion.  
   **Fix:** Compute the required converted size with overflow checks and allocate bounded storage, or reject excess input before sending anything. Add boundary tests and verify that all requested descriptors arrive.

5. **[A32-R5-5] BUG — Large `select` sets expose guest memory to host-word overrun.**  
   **Evidence:** [src/os/os_sys_sock.c:606](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:606), lines 606–610 and 652–679.  
   Above 1,024 descriptors, the implementation abandons translation and passes guest bitmaps directly to the 64-bit syscall. For `nfds = 1025`, the guest bitmap occupies 132 bytes, but the host rounds it to 136 bytes. With a sufficiently large descriptor table, the kernel can read or overwrite four bytes beyond the guest bitmap. This path also validates only four bytes.  
   **Fix:** Allocate host-word-rounded buffers for large sets, validate the complete guest spans, zero host padding, and copy back only guest-sized data. Extend the existing [small-descriptor test](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m5_ltp_gdb.c:384) with a high descriptor and trailing canary.

6. **[A32-R5-6] BUG — Software exclusive-store validation has an ABA race.**  
   **Evidence:** [src/vm/vm32.c:518](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:518), lines 518–550; ordinary stores at [src/interp/interp.c:127](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:127).  
   Reservation validation and the final value CAS are separate operations. After the last epoch check, another thread can write A→B→A and invalidate the reservation. The CAS still sees A and succeeds, incorrectly reporting a successful `STREX`. Sequentially consistent atomics do not make this multi-operation transaction indivisible.  
   **Fix:** Coordinate reservation validation and the store with all competing writes, using an appropriate per-reservation synchronization protocol. Add a controlled interleaving test around the final epoch check.

7. **[A32-R5-7] DEFECT — `mremap` ignores protection failures and incompletely restores rollback state.**  
   **Evidence:** [src/vm/vm_mremap.c:102](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_mremap.c:102), lines 102–112 and [273–294](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_mremap.c:273).  
   Copy-time protection changes and destination protection restoration discard errors. A failed widening can lead directly to a fault in `memcpy`; failed final protection can leave the moved mapping writable. If retiring the source fails, rollback drops the destination but does not restore source protections widened for copying.  
   **Fix:** Return errors from the copy helper, track temporary protection changes, restore source permissions on every failure, and require successful destination protection before retiring the source. Validate these branches with injected backend failures.

8. **[A32-R5-8] DRY — Reservation-range invalidation has three implementations.**  
   **Evidence:** [src/interp/interp.c:128](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:128), [src/signals.c:281](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:281), and [src/vm/vm32.c:482](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:482).  
   Interpreter stores and signal-frame construction implement their own four-byte loops, while `a32_vm32_copyout_invalidate()` already implements range invalidation by reservation granule. This duplicates boundary and granule policy inside the repository.  
   **Fix:** Route both callers through the existing local helper. Keep write ordering explicit; consolidation alone does not repair finding 6.

9. **[A32-R5-9] YAGNI — Unused Soft-TLB probe contains unreachable cross-page logic.**  
   **Evidence:** [src/vm/vm32.c:136](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:136), lines 136–167; declaration at [src/vm/vm32.h:100](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.h:100).  
   Repository search found only the definition and declaration. Furthermore, accepted widths are powers of two up to 16 and misaligned addresses are rejected first, so the subsequent cross-page branch cannot execute.  
   **Fix:** Remove the unused API if it has no supported external consumer. If retained as a diagnostic interface, remove unreachable handling and add an actual caller/test.

10. **[A32-R5-10] CLEAN — Decoder predicate contains an unconditional override.**  
    **Evidence:** [src/interp/interp_a32.c:164](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:164).  
    `((insn & 0x90U) != 0x90U || true)` is always true. It presents an encoding restriction that does not exist and obscures the decoder’s actual admission rule.  
    **Fix:** Remove the tautological clause if the broad dispatch is intentional; otherwise restore the intended restriction with encoding-specific tests. No inspected C/C++/assembly file exceeds 900 lines; the largest is `signals.c` at 899.

**Cross-runtime propagation notes:** These are inspection targets, not confirmed sibling defects.

| Findings | Sibling runtimes to check |
|---|---|
| 1, 6 | `mips32rt`, `ppc32rt`, `rvrt`, `mips64rt`, `ppc64rt`, `loongarch64rt`: fetch permissions and software reservation protocols |
| 2, 7 | `i686rt`, `mips32rt`, `ppc32rt`: large-host-page replacement, backing preservation, and remap rollback |
| 3–5 | Especially `i686rt`, `mips32rt`, `ppc32rt`: 32/64-bit socket and descriptor-set translation; inspect analogous Darwin socket paths in other runtimes |
| 8–10 | Check copied local helpers and decoder scaffolding; consolidate only within each repository |

ELF loading, DBT dispatch, FP conversion, and file-family bookkeeping received selective inspection without additional sufficiently established findings. This bounded pass does not establish those areas as defect-free.

- [x] **A32-R5-1:** Remediate `A32-R5-1` in `a32rt` and verify with tests.
- [x] **A32-R5-2:** Remediate `A32-R5-2` in `a32rt` and verify with tests.
- [x] **A32-R5-3:** Remediate `A32-R5-3` in `a32rt` and verify with tests.
- [x] **A32-R5-4:** Remediate `A32-R5-4` in `a32rt` and verify with tests.
- [x] **A32-R5-5:** Remediate `A32-R5-5` in `a32rt` and verify with tests.
- [x] **A32-R5-6:** Remediate `A32-R5-6` in `a32rt` and verify with tests.
- [x] **A32-R5-7:** Remediate `A32-R5-7` in `a32rt` and verify with tests.
- [x] **A32-R5-8:** Remediate `A32-R5-8` in `a32rt` and verify with tests.
- [x] **A32-R5-9:** Remediate `A32-R5-9` in `a32rt` and verify with tests.
- [x] **A32-R5-10:** Remediate `A32-R5-10` in `a32rt` and verify with tests.

---

## 2. `i686rt` (`e993289`) — 11 Round-5 Findings (`11 / 11` Resolved)

Static inspection found **11 actionable findings**. Eight shell commands were used; no Markdown files, builds, tests, Docker, or QEMU were run. These are source-derived findings, not reproduced failures. Inspection covered selected interpreter, DBT, VM, syscall, ELF/rt32, and test paths; it does not establish whole-repository correctness.

1. **[I686-R5-1] BUG — SSE directed rounding can move an already-correct result by another ULP.**

   **Evidence:** [src/interp/h_sse.c:82](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse.c:82), especially lines 94–117.

   **Root cause:** After converting double to float, the helper adjusts every inexact normal result solely according to rounding mode and sign. It never checks which side of the exact value the initial conversion landed on.

   **Concrete consequence:** Under round-up, `ADDSS(1.0f, 3 × 2^-25)` should produce `0x3f800001`. With host round-to-nearest, the initial cast already produces that value, but the helper increments it to `0x3f800002`.

   **Fix:** Adjust only when the initial result lies on the wrong side of the exact value. Also preserve arithmetic residuals: the double intermediate at lines 185–192 can itself discard information needed for directed rounding. Add bit-exact cases for all rounding modes.

2. **[I686-R5-2] BUG — LDMXCSR accepts reserved bits, and a test requires that incorrect behavior.**

   **Evidence:** [src/interp/h_sse_int.c:642](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_sse_int.c:642), [tests/unit/test_l5b_cases.c:363](/Users/angerman/Projects/zw3rk/i686rt/tests/unit/test_l5b_cases.c:363). The DBT also documents masking at [src/dbt/emit_sse2.c:388](/Users/angerman/Projects/zw3rk/i686rt/src/dbt/emit_sse2.c:388).

   **Root cause:** The interpreter commits the masked value and sets MXCSR.IE instead of generating the required general-protection fault. The test explicitly expects successful execution with bit 16 set.

   **Fix:** Validate reserved bits before changing MXCSR or advancing EIP. Deliver the guest fault with prior state intact. Apply the same validation to DBT execution and replace the test’s success expectation with fault-and-state-preservation assertions.

3. **[I686-R5-3] BUG — LOCK-prefixed shifts execute instead of faulting.**

   **Evidence:** [src/interp/h_shift.c:203](/Users/angerman/Projects/zw3rk/i686rt/src/interp/h_shift.c:203), [src/x86/decode.c:636](/Users/angerman/Projects/zw3rk/i686rt/src/x86/decode.c:636), [src/interp/interp.c:399](/Users/angerman/Projects/zw3rk/i686rt/src/interp/interp.c:399).

   **Root cause:** There is no common LOCK legality check before handler dispatch. Shift handlers deliberately implement locked atomic updates; zero-count shifts return success even earlier.

   **Concrete consequence:** `F0 D1 20`—LOCK SHL through `[EAX]`—modifies memory instead of raising #UD.

   **Fix:** Validate LOCK against an opcode-and-memory-destination allowlist before either engine executes the instruction. Remove the unreachable shift/rotate atomic machinery after enforcing legality. Cover both zero and nonzero counts.

4. **[I686-R5-4] BUG / DEFECT — Socket message marshalling bypasses fault-safe guest copies.**

   **Evidence:** [src/os/sys_sock_msg.c:137](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:137), lines 199–213 and 315–317; compare [src/os/marshal.c:43](/Users/angerman/Projects/zw3rk/i686rt/src/os/marshal.c:43).

   **Root cause:** Iovec descriptors and ancillary data are dereferenced directly after address-range checks. Those checks do not establish accessibility. Payload pointers are also passed directly to host `sendmsg`/`recvmsg`.

   **Consequences:** An inaccessible descriptor or control buffer can escape to the outer execution fault checkpoint, skipping local cleanup. On A2, a valid guest payload sharing a restricted host page can instead receive host `EFAULT`, because kernel copies cannot invoke the runtime’s user-space healing path.

   **Fix:** Snapshot descriptors and control data through checked copies. Stage payloads through host buffers where A2 requires it, with explicit cleanup and descriptor ownership on every failure.

5. **[I686-R5-5] BUG — Ancillary truncation discards SCM_RIGHTS descriptors that fit.**

   **Evidence:** [src/os/sys_sock_msg.c:79](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:79).

   **Root cause:** Conversion requires an entire control message to fit. Otherwise it drops the entire payload and closes every received descriptor.

   **Concrete consequence:** A two-descriptor SCM_RIGHTS message with guest control capacity of 16 bytes has room for the 12-byte header and one descriptor. The implementation delivers neither descriptor.

   **Fix:** Emit the prefix that fits, retain complete descriptor-sized units, set `MSG_CTRUNC`, and close only undelivered descriptors. Add a partial-rights test; existing tests cover whole-message fit/drop cases.

6. **[I686-R5-6] BUG — Multi-message syscalls count entries whose `msg_len` copyout failed.**

   **Evidence:** [src/os/sys_sock_msg.c:362](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:362) and [src/os/sys_sock_msg.c:468](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:468).

   **Root cause:** Both `sendmmsg` and `recvmmsg` discard `i686_copy_to_guest`’s return value and increment the completed count.

   **Concrete consequence:** Place the 28-byte message header at the end of a writable page and `msg_len` on an inaccessible next page. The syscall reports a completed entry without publishing its length.

   **Fix:** Stop on failed length copyout. Return `-EFAULT` if no previous entry completed, otherwise return the previous completed count. Preserve the distinction between an irreversible send/receive side effect and a successfully reported entry.

7. **[I686-R5-7] BUG — `recvmmsg` timeout emulation changes shared socket state.**

   **Evidence:** [src/os/sys_sock_msg.c:417](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:417), lines 449–461.

   **Root cause:** A per-call deadline is implemented by temporarily replacing `SO_RCVTIMEO`. That option belongs to the socket and is shared across threads and duplicated descriptors.

   **Consequences:** Concurrent receives observe another call’s timeout. Concurrent option changes can be overwritten by restoration of the saved value. Failures from both `setsockopt` calls are ignored.

   **Fix:** Implement the deadline without changing socket options—for example, deadline-aware readiness waits followed by nonblocking receives, with signal and `MSG_WAITFORONE` handling.

8. **[I686-R5-8] DEFECT — Failed `munmap` can leave a live mapping without backing-file tracking.**

   **Evidence:** [src/rt32/rt32_vm_mmap.c:270](/Users/angerman/Projects/zw3rk/i686rt/src/rt32/rt32_vm_mmap.c:270).

   **Root cause:** `i686_vm_file_untrack_map` commits removal before `rt32_vm_reserve_prot_none` performs the fallible host operation. If reservation fails, the function returns without restoring tracking.

   **Consequence:** Guest region metadata and the surviving host mapping can remain while backing-file records and owned descriptors have been removed. Later file-refresh or truncation handling no longer sees that mapping.

   **Fix:** Prepare tracking changes without committing them, perform the host operation, then commit metadata removal. Alternatively retain sufficient state for rollback. Validate with an injected reservation failure.

9. **[I686-R5-9] DEFECT / CLEAN — Guest-controlled time64 values cause signed-overflow undefined behavior.**

   **Evidence:** [src/os/sys_sock_msg.c:390](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock_msg.c:390) and line 410.

   **Root cause:** High words are shifted left as signed `int64_t`; values setting bit 63 exceed the signed range. Separately, adding a large positive timeout to monotonic time can overflow `time_t`, as can the nanosecond carry.

   **Fix:** Assemble raw words using `uint64_t`, then decode their signed representation safely. Validate negative values and use checked deadline addition. Add boundary cases for negative encodings and `INT64_MAX`.

10. **[I686-R5-10] DRY — Darwin readiness waiting is duplicated within this repository.**

    **Evidence:** [src/os/backend_darwin_io.c:47](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_io.c:47), [src/os/backend_darwin_net.c:86](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:86).

    **Root cause:** Both translation units contain the same lease check, wake-pipe polling, timeout handling, and readiness interpretation.

    **Fix:** Keep one private Darwin backend helper inside i686rt. This makes signal, timeout, and invalid-descriptor corrections apply consistently. No cross-repository library extraction is warranted.

11. **[I686-R5-11] YAGNI / CLEAN — Socket backend APIs have no callers while guest syscalls bypass them.**

    **Evidence:** [src/os/backend.h:152](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend.h:152), [src/os/backend_linux_sys.c:293](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_linux_sys.c:293), [src/os/backend_darwin_net.c:118](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:118), versus [src/os/sys_sock.c:123](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock.c:123).

    **Root cause:** Searches found declarations and implementations, but no callers for the inspected `rt_host_socket/socketpair/bind/connect/accept4/sendto/recvfrom` APIs. Actual syscall handlers call libc directly.

    **Consequence:** Two networking paths are maintained, but backend lease handling and platform adaptations do not govern guest socket execution.

    **Fix:** Establish one active path: wire guest handlers through the backend with proper ABI conversion, or remove unused implementations where no current contract requires them. Correct comments claiming Darwin is never a runtime host.

**Cross-runtime propagation notes**

Sibling repositories were not inspected; these are targeted follow-up checks, not confirmed sibling defects.

| Findings | Sibling checks |
|---|---|
| R5-1–3 | Check x86 execution paths in **hyper-linux**, if independently implemented. These opcode semantics do not directly transfer to ARM guest execution in **a32rt**. |
| R5-4–7, R5-9 | Check **a32rt** compat socket marshalling and **hyper-linux** syscall adapters for direct guest pointers, ancillary truncation, ignored copyouts, shared timeout mutation, and signed time assembly. |
| R5-8 | Prioritize **a32rt** VM/file-tracking transaction order; inspect corresponding **hyper-linux** mapping bookkeeping. |
| R5-10–11 | Check both siblings for duplicated Darwin wait helpers and backend APIs bypassed by active syscall paths. Keep remedies repository-local. |

No inspected source file exceeded 900 lines; the largest was `src/os/sys_stat.c` at 898. No additional ELF-loader finding met the confidence threshold within this inspection budget.

- [x] **I686-R5-1:** Remediate `I686-R5-1` in `i686rt` and verify with tests.
- [x] **I686-R5-2:** Remediate `I686-R5-2` in `i686rt` and verify with tests.
- [x] **I686-R5-3:** Remediate `I686-R5-3` in `i686rt` and verify with tests.
- [x] **I686-R5-4:** Remediate `I686-R5-4` in `i686rt` and verify with tests.
- [x] **I686-R5-5:** Remediate `I686-R5-5` in `i686rt` and verify with tests.
- [x] **I686-R5-6:** Remediate `I686-R5-6` in `i686rt` and verify with tests.
- [x] **I686-R5-7:** Remediate `I686-R5-7` in `i686rt` and verify with tests.
- [x] **I686-R5-8:** Remediate `I686-R5-8` in `i686rt` and verify with tests.
- [x] **I686-R5-9:** Remediate `I686-R5-9` in `i686rt` and verify with tests.
- [x] **I686-R5-10:** Remediate `I686-R5-10` in `i686rt` and verify with tests.
- [x] **I686-R5-11:** Remediate `I686-R5-11` in `i686rt` and verify with tests.

---

## 3. `mips32rt` (`aa2eb8e`) — 11 Round-5 Findings (`11 / 11` Resolved)

**Round 5 found 11 actionable issues.** Used exactly eight shell commands for static inspection. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings below are code-based; suggested reproductions remain unexecuted.

1. **[M32-R5-1] BUG — DBT bypasses guest subpage permissions on A2 hosts. High.**

   **Evidence:** [a64_emit.c:419](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/a64_emit.c:419), [trampoline_a64.S:52](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/trampoline_a64.S:52), [dbt.c:772](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/dbt.c:772).

   Generated loads/stores always access `[G, wAddr, uxtw]`; the trampoline always installs `guest_base`, and DBT dispatch does not gate execution on `vm_regime`. The A2 permission validator is used by interpreter accessors, not these generated accesses.

   On Darwin, a writable 4 KiB guest page can therefore make an adjacent read-only or `PROT_NONE` guest page accessible through their shared 16 KiB host page. Existing permission probes at [test_p6_perms.c:300](/Users/angerman/Projects/zw3rk/mips32rt/tests/test_p6_perms.c:300) cover a relevant layout.

   **Fix:** Route A2 memory operations through validated helpers or interpreter fallback until generated accesses enforce guest-page permissions.

2. **[M32-R5-2] BUG — Big-endian futex comparisons use little-endian host values. High.**

   **Evidence:** [threads.c:506](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:506), [threads.c:527](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:527), [threads.c:564](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:564).

   The preliminary load decodes guest endianness, but `FUTEX_WAIT` and `WAIT_BITSET` then pass the unswapped numeric `val` to the host kernel. For a BE word containing `1`, the little-endian host observes `0x01000000`, so the kernel rejects a valid wait with `EAGAIN`. `CMP_REQUEUE` has the same comparison problem. Native `WAKE_OP` arithmetic also operates on the wrong representation.

   **Fix:** Convert comparison operands to host memory representation. Implement an endian-aware atomic path for BE `WAKE_OP`, or explicitly reject unsupported operations. Add raw BE futex tests using nonzero, non-byte-symmetric values.

3. **[M32-R5-3] BUG — Futex requeue and wake-op discard argument four. High.**

   **Evidence:** [threads.c:481](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:481), [threads.c:563](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:563), [threads.c:578](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:578).

   Argument four is decoded into `to_va`, but both requeue operations and `WAKE_OP` pass `NULL` in its place. For these operations, that argument is a count, not a timeout pointer. Consequently, requeue moves zero waiters and wake-op cannot perform the requested second-address wake count.

   **Fix:** Forward the operation-specific integer count. Add tests that require moving waiters between addresses and waking waiters on both addresses.

4. **[M32-R5-4] DEFECT — Successful guest threads permanently retain host resources. High.**

   **Evidence:** [threads.c:320](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:320), [threads.c:328](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:328), [threads.c:207](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:207), [threads.c:403](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:403).

   Each successful clone allocates a record and a 2 MiB host stack. Cleanup exists only on creation failure. Successful threads exit through raw `SYS_exit`, bypassing pthread teardown, and no implemented reaper owns the retained record or stack. Detached status does not reclaim a caller-provided stack.

   **Fix:** Establish explicit completion ownership: terminate through pthread machinery and reclaim caller-owned stacks only after host-thread termination, using a reaper or equivalent lifecycle. Include repeated create/join coverage.

5. **[M32-R5-5] BUG — Robust-list registration succeeds without owner-death processing. High.**

   **Evidence:** [syscalls_meta.c:813](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls_meta.c:813), [threads.c:207](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:207).

   `set_robust_list` records the guest head and returns success. Thread teardown only clears `clear_child_tid`; it never traverses the guest robust list, marks abandoned futexes `OWNER_DIED`, or wakes their waiters. The host kernel cannot process this guest O32 list through the host pthread’s independent robust-list registration.

   **Fix:** Implement bounded, fault-tolerant O32 robust-list teardown, including the pending-operation entry and BE conversion. Until supported, do not report successful registration. Test a thread exiting while holding a robust mutex.

6. **[M32-R5-6] BUG — Round 4 read/readv epoch updates still permit invalid SC success. High.**

   **Evidence:** [syscall_min.c:150](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:150), [syscalls.c:677](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:677), [mem.c:800](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:800).

   Host I/O writes directly into guest memory before acquiring LL/SC exclusion and advancing epochs. Another thread can perform LL, observe a same-value I/O store, and complete SC before the delayed epoch update. Both the epoch check and value comparison then pass despite an intervening write.

   **Fix:** Read into host staging storage, then validate and commit transferred bytes under the established VM/LL locking order. Preserve partial-transfer and iovec ordering semantics; do not hold the LL lock across blocking I/O.

7. **[M32-R5-7] DEFECT — Darwin file synchronization still suppresses errors and destroys mapping contents. High.**

   **Evidence:** [vm_mmap.c:665](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:665), [vm_mmap.c:699](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/vm_mmap.c:699), [vm_file.c:78](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:78).

   `rt32_vm_flush_shared_fd()` discards writeback failures. Write and truncate callers continue, then synchronization zeroes each entire shadow mapping and issues one unchecked `pread`. A failed preflush can lose dirty mapped bytes during refresh; an interrupted, failed, or short refresh can replace valid contents with zeros. Round 4 error propagation therefore does not cover these fd-based paths.

   **Fix:** Return and propagate flush errors. Populate temporary storage using checked, EINTR-aware reads, zero only the verified EOF remainder, and commit only after successful population.

8. **[M32-R5-8] BUG — Reserved FP conversion encodings consume an uninitialized result. Medium.**

   **Evidence:** [fp.c:711](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:711), [fp.c:750](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:750), [fp.c:770](/Users/angerman/Projects/zw3rk/mips32rt/src/interp/fp.c:770).

   `v` is uninitialized. Function 32 with S format and function 33 with D format execute `break`, reaching the shared result-write tail without assigning `v`. These reserved same-format conversions consequently invoke undefined C behavior and mutate guest state instead of taking the reserved-instruction path.

   **Fix:** Reject both combinations before result writeback. Add raw-instruction tests checking the trap and unchanged destination/FCSR state.

9. **[M32-R5-9] DEFECT — Differential testing can certify two failed launches. High for validation.**

   **Evidence:** [run_difftest.sh:71](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:71), [run_difftest.sh:84](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:84), [run_difftest.sh:115](/Users/angerman/Projects/zw3rk/mips32rt/tests/difftest/run_difftest.sh:115).

   The harness accepts equal exit statuses and permits empty trace/register files. If both launches fail before guest execution—for example, `setarch -R` is installed but denied—both empty outputs compare equal and produce `DIFFTEST: 0 divergences`. Matching timeouts can likewise pass when captured evidence matches.

   **Fix:** Reject infrastructure failures and timeouts, require evidence of guest execution and complete expected state records, and explicitly configure expected guest termination where nonzero exits are intentional.

10. **[M32-R5-10] YAGNI / CLEAN — Thread lifecycle bookkeeping has no consumer. Low.**

    **Evidence:** [threads.c:122](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:122), [threads.c:153](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:153), [threads.c:439](/Users/angerman/Projects/zw3rk/mips32rt/src/os/threads.c:439).

    `host_stack` is assigned but never read. `mips_live_clones` is modified but never used to make a decision. Comments promise a reaper that is absent. Moreover, the counter increments after the child can already exit, and a parent-TID write failure skips that increment entirely.

    **Fix:** Integrate these fields into the real lifecycle repair in M32-R5-4, with publication and rollback ordering, or remove unused bookkeeping and obsolete claims.

11. **[M32-R5-11] DRY — Truncate variants duplicate O32 length decoding. Low.**

    **Evidence:** [vm_file.c:109](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:109), [vm_file.c:151](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm_file.c:151).

    Path-based and fd-based truncate independently implement the same signed 32-bit validation, padded 64-bit argument extraction, and BE/LE assembly. This creates two maintenance points for one ABI rule.

    **Fix:** Extract a file-local length decoder returning a validated length or error; retain separate path/fd handling. This is strictly intra-repository consolidation.

**Cross-runtime propagation checks**

Sibling sources were not inspected; these are targeted checks, not confirmed sibling findings.

| Findings | Siblings/patterns to check |
|---|---|
| R5-1, R5-7 | `a32rt`, `i686rt`: copied Class-A substrate, Darwin subpage protection and shadow-file synchronization |
| R5-2, R5-3 | Any sibling with futex forwarding; endian handling especially in BE-capable runtimes |
| R5-4, R5-5, R5-10 | Siblings implementing guest clone through host pthreads and emulated robust lists |
| R5-6 | `a32rt` and other LL/SC runtimes using post-I/O reservation invalidation |
| R5-8 | Other MIPS runtimes sharing COP1 decoding or conversion logic |
| R5-9 | All siblings using this differential-harness pattern |
| R5-11 | No automatic propagation needed; local maintenance issue |

**CLEAN coverage:** The source line-count inspection found no `.c`, `.h`, or `.S` file above 900 lines; the largest inspected source was `src/dbt/emit_int.c` at 899. The FP uninitialized read and misleading lifecycle comments are concrete hygiene findings above. ELF loading was inspected, but this bounded review established no additional ELF finding.

- [x] **M32-R5-1:** Remediate `M32-R5-1` in `mips32rt` and verify with tests.
- [x] **M32-R5-2:** Remediate `M32-R5-2` in `mips32rt` and verify with tests.
- [x] **M32-R5-3:** Remediate `M32-R5-3` in `mips32rt` and verify with tests.
- [x] **M32-R5-4:** Remediate `M32-R5-4` in `mips32rt` and verify with tests.
- [x] **M32-R5-5:** Remediate `M32-R5-5` in `mips32rt` and verify with tests.
- [x] **M32-R5-6:** Remediate `M32-R5-6` in `mips32rt` and verify with tests.
- [x] **M32-R5-7:** Remediate `M32-R5-7` in `mips32rt` and verify with tests.
- [x] **M32-R5-8:** Remediate `M32-R5-8` in `mips32rt` and verify with tests.
- [x] **M32-R5-9:** Remediate `M32-R5-9` in `mips32rt` and verify with tests.
- [x] **M32-R5-10:** Remediate `M32-R5-10` in `mips32rt` and verify with tests.
- [x] **M32-R5-11:** Remediate `M32-R5-11` in `mips32rt` and verify with tests.

---

## 4. `ppc32rt` (`a091b8f`) — 11 Round-5 Findings (`11 / 11` Resolved)

Found **11 issues**, including incomplete Round 4 copyout/coherence fixes. Used **eight shell commands**; no Markdown files, builds, tests, Docker, or QEMU. Findings are static conclusions, not runtime reproductions.

1. **[P32-R5-1] BUG — `clone(CLONE_VM)` blocks the parent until the child exits.**  
   **Evidence:** [syscalls.c:760](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:760), [syscalls.c:771](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:771).  
   The dispatcher creates the child without a runner, then executes it synchronously before returning the child TID. A child waiting for the parent to release a mutex or publish a flag deadlocks inside `clone`. The existing [thread counter test:613](/Users/angerman/Projects/zw3rk/ppc32rt/tests/test_p4_threads_signals.c:613) permits sequential completion and cannot detect this.  
   **Fix:** Schedule parent and child independently, including yielding on blocking operations. Add a parent/child handshake regression.

2. **[P32-R5-2] BUG — FP memory faults commit register and PC changes.**  
   **Evidence:** [fp.c:75](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:75), [fp.c:95](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/fp.c:95), [interp.h:286](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.h:286), [emit_fp.c:260](/Users/angerman/Projects/zw3rk/ppc32rt/src/dbt/emit_fp.c:260).  
   `ld32` returns zero after recording a permission fault. `fp_memop` nevertheless writes the destination FPR and advances `nip`. Update forms also overwrite RA before attempting the access; the DBT explicitly duplicates that ordering. A fault handler therefore sees partially committed instruction state, and retry can use the wrong address.  
   **Fix:** Propagate access failure explicitly. Commit FPR, RA, and `nip` only after successful access; test protected-page faults for D-form and indexed update instructions.

3. **[P32-R5-3] BUG/DEFECT — Raw syscall copyouts bypass Round 4 permission checks.**  
   **Evidence:** [syscalls_dyn.c:414](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_dyn.c:414), [syscalls_dyn.c:426](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_dyn.c:426), [syscalls.c:395](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:395).  
   `getcwd` uses raw `memcpy`; `getrandom` passes the guest pointer directly to the host. Both check address range but omit guest write permissions and landed-store bookkeeping. On A2, a writable neighboring subpage can allow writes into a guest read-only page. `getcwd` can also fault in host code instead of returning `EFAULT`.  
   **Fix:** Route output through checked copyout and common SMC, reservation, and shared-file coherence handling. Test read-only subpages sharing a writable host page.

4. **[P32-R5-4] BUG — `readv` rereads descriptors that its own output can overwrite.**  
   **Evidence:** [syscalls.c:213](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:213), [syscalls.c:239](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:239).  
   Host iovecs are captured before `readv`, but invalidation rereads `base` and `len` from guest memory afterward. A valid destination overlapping the guest iovec array changes those descriptors. Bookkeeping then targets incorrect ranges, leaving the actual destination without reservation, code-cache, or staged-alias updates. Later chunks can also consume overwritten descriptors.  
   **Fix:** Snapshot the complete descriptor array before I/O and retain its guest addresses for all post-I/O processing.

5. **[P32-R5-5] BUG — Chunking vectored I/O changes syscall semantics.**  
   **Evidence:** [syscalls.c:204](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:204), [syscalls.c:230](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:230).  
   More than 16 vectors produce multiple host syscalls. A 17-vector datagram `writev` becomes two datagrams. A small pipe write loses whole-request atomicity, and a read can block again after an earlier chunk completed. Correct partial-byte accounting does not repair these semantic changes.  
   **Fix:** Allocate a bounded host array for the accepted vector count and issue one host `readv`/`writev`.

6. **[P32-R5-6] BUG — Reading into staged `MAP_SHARED` memory does not update its backing file.**  
   **Evidence:** [syscalls.c:113](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:113), [vm_file_stage.c:633](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:633), [vm_file_stage.c:507](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:507).  
   `sys_read_landed` selects `cohere_read`, which passes `write_file=false`. Reading pipe bytes into a writable shared mapping changes destination memory just like any other store, but this path updates only staging objects. The backing file and direct file mappings retain old bytes.  
   **Fix:** Treat successful syscall output as a store to the destination mapping, including backing-file propagation. Keep refresh-from-file operations separate.

7. **[P32-R5-7] BUG — Staged write-through can select a read-only descriptor.**  
   **Evidence:** [vm_file_stage.c:303](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:303), [vm_file_stage.c:510](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:510), [vm_file_stage.c:531](/Users/angerman/Projects/zw3rk/ppc32rt/src/vm/vm_file_stage.c:531).  
   Groups retain a duplicate of their original descriptor. Write-through chooses the first same-inode group without checking access mode. If a read-only mapping was created first, a later writable mapping can send its writeback through that read-only descriptor. `pwrite` fails, and the failure is silently discarded.  
   **Fix:** Retain or select a writable descriptor from an authorized writable mapping. Handle writeback failure explicitly. Add mixed `O_RDONLY`/`O_RDWR` alias coverage.

8. **[P32-R5-8] BUG — Self-directed signals ignore the blocked mask.**  
   **Evidence:** [signals.c:720](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:720), [signals.c:451](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:451), [signals.c:616](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:616).  
   `kill` immediately enters an installed handler through `ppc32_sig_deliver_sync`, without testing `ctx->sig_mask` or queuing a pending signal. Blocking `SIGUSR1` and sending it to self therefore runs the handler immediately instead of making it pending.  
   **Fix:** Separate asynchronous signal enqueueing from synchronous fault delivery. Deliver queued signals at eligible execution boundaries after unmasking.

9. **[P32-R5-9] DEFECT — Callback thread exit races handle publication and destroys joinability.**  
   **Evidence:** [threads.c:582](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:582), [threads.c:615](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:615), [threads.c:654](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:654).  
   In the callback-backed pthread path, the child can exit before the parent records its handle. Exit clears the slot and frees the context; subsequent join returns `ESRCH`, and the joinable pthread resources remain unreaped. The embedded test also dereferences that potentially freed context at [threads.c:790](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/threads.c:790). This is distinct from the currently synchronous syscall path.  
   **Fix:** Publish the handle before releasing a child startup barrier; retain completed-thread records until reaping. Give returned contexts explicit ownership.

10. **[P32-R5-10] DRY/YAGNI/CLEAN — The unused minimal syscall implementation duplicates obsolete behavior.**  
    **Evidence:** [syscalls_min.c:50](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_min.c:50), [syscalls_min.c:161](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_min.c:161), [main.c:481](/Users/angerman/Projects/zw3rk/ppc32rt/src/main.c:481).  
    Repository reference searches found declarations and definitions but no callers of `ppc32_syscall_min`. It duplicates dispatch, return conversion, and memory handling while retaining a different low-address guard (`0x1000`) and unchecked direct buffers. This is an existing source of implementation drift.  
    **Fix:** Remove the unused implementation/header, or make any required compatibility entry points delegate to the maintained dispatcher. Keep consolidation within this repository.

11. **[P32-R5-11] YAGNI — `sig_installed` is write-only state.**  
    **Evidence:** [signals.c:48](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:48), [signals.c:115](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:115), [signals.c:141](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:141), [signals.c:162](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:162).  
    All references initialize or assign the array; none reads it. It adds a second apparent disposition state without influencing behavior.  
    **Fix:** Remove the array and its assignments.

**Cross-runtime propagation notes**

| Patterns | Sibling runtimes to inspect |
|---|---|
| Copyout permissions, vectored I/O, staged-file coherence | `a32rt`, `i686rt`, especially copied Class-A VM and syscall code |
| Clone scheduling, pthread lifecycle, blocked-signal delivery | `a32rt`, `i686rt` wherever equivalent guest-thread/signal layers exist |
| FP fault commit ordering | Sibling interpreter/JIT memory handlers, translated to each ISA’s precise exception rules |
| Legacy dispatchers and write-only state | Sibling repositories containing copied phase-era implementations |

These are propagation targets, **not confirmed sibling findings**; sibling source was not inspected.

**CLEAN check:** Static line counts found no `.c`, `.h`, or `.S` file above 900 lines under `src`, `include`, or `tests`; the largest was `src/os/threads.c` at 884. ELF loading was inspected, but no additional ELF finding met the evidence threshold within this budget.

- [x] **P32-R5-1:** Remediate `P32-R5-1` in `ppc32rt` and verify with tests.
- [x] **P32-R5-2:** Remediate `P32-R5-2` in `ppc32rt` and verify with tests.
- [x] **P32-R5-3:** Remediate `P32-R5-3` in `ppc32rt` and verify with tests.
- [x] **P32-R5-4:** Remediate `P32-R5-4` in `ppc32rt` and verify with tests.
- [x] **P32-R5-5:** Remediate `P32-R5-5` in `ppc32rt` and verify with tests.
- [x] **P32-R5-6:** Remediate `P32-R5-6` in `ppc32rt` and verify with tests.
- [x] **P32-R5-7:** Remediate `P32-R5-7` in `ppc32rt` and verify with tests.
- [x] **P32-R5-8:** Remediate `P32-R5-8` in `ppc32rt` and verify with tests.
- [x] **P32-R5-9:** Remediate `P32-R5-9` in `ppc32rt` and verify with tests.
- [x] **P32-R5-10:** Remediate `P32-R5-10` in `ppc32rt` and verify with tests.
- [x] **P32-R5-11:** Remediate `P32-R5-11` in `ppc32rt` and verify with tests.

---

## 5. `sparc32rt` (`edfcf6f`) — 12 Round-5 Findings (`12 / 12` Resolved)

**Round 5 found 12 actionable issues.** These are static findings, not runtime reproductions. I used eight shell commands; read no Markdown; ran no builds, tests, Docker, or QEMU; and changed no files. Inspection covered selected interpreter, DBT, VM, syscall, ELF, and test paths. This checkout has no `src/rt32/family/` directory; related bookkeeping resides in `src/vm/vm_file.c`.

1. **[S32-R5-1] BUG — FP doubleword alignment differs between engines.**  
   **Evidence:** [interp/fp.c:230](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/fp.c:230), [dbt/emit_fpmem.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/emit_fpmem.c:83).  
   The interpreter executes `LDDF`/`STDF` as two four-byte accesses, accepting an address congruent to four modulo eight. The DBT explicitly faults that address. Additionally, [interp_signal.c:643](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:643) excludes FP doublewords from alignment-fault classification, so the DBT fault becomes SIGSEGV.  
   **Fix:** Make alignment checks and fault classification consistent across both engines. Add mapped `base+4` load/store cases alongside the existing [FP round-trip test:311](/Users/angerman/Projects/zw3rk/sparc32rt/tests/test_p3_fp_simd.c:311).

2. **[S32-R5-2] BUG — Byte and halfword mapping faults can become SIGBUS.**  
   **Evidence:** [interp_signal.c:654](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:654), [interp_mem.c:74](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_mem.c:74).  
   Classification immediately returns SIGBUS whenever `fault_addr & 3` is nonzero. An unmapped byte load at `page+1`, or an aligned halfword load at `page+2`, therefore gets classified as an alignment fault despite satisfying its instruction’s alignment requirement.  
   **Fix:** Record the fault cause at the access site, or determine the instruction’s required alignment before classifying it.

3. **[S32-R5-3] DEFECT — Fault classification bypasses VM reader protection.**  
   **Evidence:** [interp_signal.c:621](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:621), [main.c:259](/Users/angerman/Projects/zw3rk/sparc32rt/src/main.c:259).  
   `sparc32_fault_insn_word()` checks permissions and directly dereferences guest memory without `sparc32_vm_access_enter()`. A sibling can unmap or revoke access between those operations, causing a host fault while the runtime is classifying a guest fault. Ordinary accessors already protect this interval.  
   **Fix:** Hold the VM reader guard across validation and instruction copying, preserving the original guest fault state.

4. **[S32-R5-4] BUG — Signal queues still consume each other’s pending bits.**  
   **Evidence:** [threads_sig.c:107](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:107), [threads_sig.c:123](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:123), [interp_signal.c:418](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:418).  
   `rt_sigsuspend` consumes a process bit while delivering a thread bit. Its process loop also claims and discards a process signal if any thread has that number pending. Separately, the common async commit always clears the current thread’s bit—even when invoked for a process delivery—so a thread signal arriving during frame construction can disappear.  
   **Fix:** Carry queue ownership through selection and delivery; consume only the selected queue. Remove the remaining cross-queue deduplication. Extend the [single-signal suspend test:125](/Users/angerman/Projects/zw3rk/sparc32rt/tests/test_p4_async.c:125) with simultaneous process/thread pending cases.

5. **[S32-R5-5] BUG — `rt_sigsuspend` discards queued default-fatal signals.**  
   **Evidence:** [threads_sig.c:100](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:100), [threads_sig.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_sig.c:126).  
   Both loops treat “no installed handler” as permission to discard the signal. Round 4 explicitly queues default-disposition signals while blocked at [threads_kill.c:197](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads_kill.c:197). If `sigsuspend` unmasks one, it can consume the pending fatal signal and sleep instead of applying its default action.  
   **Fix:** Share disposition handling with normal polling, distinguishing ignored, caught, and default-action signals.

6. **[S32-R5-6] DEFECT — Concurrent disposition changes expose uninitialized handler addresses.**  
   **Evidence:** [interp_signal.c:296](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:296), [interp_signal.c:410](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:410), [syscalls_sig.c:162](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_sig.c:162).  
   Frame construction snapshots one action, then commit fetches it again. If another thread changes the disposition to DFL or IGN between those calls, `sparc32_signal_get_action()` fails without initializing `handler` or `restorer`. Commit ignores that failure and uses both locals. The syscall-delivery path repeats this pattern.  
   **Fix:** Pass one validated action snapshot through construction and commit, with an explicit policy for disposition changes.

7. **[S32-R5-7] BUG — Suspend delivery corrupts `SA_SIGINFO` fields.**  
   **Evidence:** [interp_signal.c:365](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:365), [interp_signal.c:471](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:471).  
   Normal async construction writes legacy PC/NPC mirrors only without `SA_SIGINFO`, because offsets 100 and 104 overlap `si_errno` and `si_code`. `interp_deliver_async_for_syscall()` overwrites those offsets unconditionally. An `SA_SIGINFO` handler entered through `sigsuspend` receives instruction addresses as signal metadata.  
   **Fix:** Apply the same flag guard using the action snapshot; update the real saved PC/NPC independently.

8. **[S32-R5-8] DEFECT — New file mappings start with the wrong tracked size.**  
   **Evidence:** [vm_mmap.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:83), [vm_file.c:109](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:109), [vm_file.c:232](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:232).  
   Mapping registration publishes the file’s size **before** interning the new mapping. The new entry subsequently initializes `file_size` to zero. Its first truncation therefore compares the new size against zero and skips shrink handling.  
   **Fix:** Initialize the mapping entry with the `fstat` size during registration. Test the first shrink immediately after mapping, without an intervening write or second mmap.

9. **[S32-R5-9] DEFECT — File-mapping records outlive their mappings.**  
   **Evidence:** [vm_file.c:90](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:90), [vm_file.c:202](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:202), [vm_mmap.c:357](/Users/angerman/Projects/zw3rk/sparc32rt/src/rt32/vm_mmap.c:357).  
   Entries become permanently live; unmap and exec reset do not retire them. After file A is unmapped and file B occupies its address, shrinking A can clear B’s dirty-page state through the stale range. Moved private mappings copy only pages marked dirty, making this capable of losing B’s private modifications. After 128 distinct records, registration also silently stops.  
   **Fix:** Implement range retirement/splitting for unmap, replacement, remap, and exec. Recycle entries and report registration failure rather than silently dropping tracking.

10. **[S32-R5-10] DEFECT — Futex emulation exhausts slots permanently.**  
    **Evidence:** [futex.c:61](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:61), [futex.c:147](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:147), [futex.c:160](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/futex.c:160).  
    The emulation table has 64 slots. Allocation sets `in_use`, but completion only decrements `waiters`; nothing releases a slot. After waits on 64 distinct addresses, waits on new addresses return EAGAIN even when the value matches and all earlier waiters have finished.  
    **Fix:** Recycle zero-waiter slots under `futex_emu_lock`, preserving safe condition-variable lifetime. Add a sequential test over more than 64 addresses.

11. **[S32-R5-11] DRY — Difftest duplicates production fault classification.**  
    **Evidence:** [difftest.c:159](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/difftest.c:159), [interp_signal.c:617](/Users/angerman/Projects/zw3rk/sparc32rt/src/interp/interp_signal.c:617), [difftest.c:433](/Users/angerman/Projects/zw3rk/sparc32rt/src/dbt/difftest.c:433).  
    Difftest contains another instruction fetch and classifier, including the same erroneous address heuristic. It then delivers that single classification to both contexts. This adds maintenance drift without providing an independent signal oracle.  
    **Fix:** Reuse the repository’s production classifier and validate expected signal numbers in focused guest tests.

12. **[S32-R5-12] YAGNI / CLEAN — Unused file-state machinery overstates implemented behavior.**  
    **Evidence:** [vm_file.c:48](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:48), [vm_file.c:126](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:126), [vm_file.c:248](/Users/angerman/Projects/zw3rk/sparc32rt/src/vm/vm_file.c:248).  
    Repository searches found no callers for `vm_file_promote_cow`, `vm_file_apply_shrink`, `vm_file_generation`, or `vm_file_shared_direct_ok`. The descriptor type supports only these unused helpers; `resize_seq` and `min_shrunk` have no readers. Meanwhile, the opening comment describes family-shared storage surviving fork, but `g_inodes` is an ordinary static array.  
    **Fix:** Remove unused alternate machinery or connect it to a concrete required path. Correct the comments to distinguish implemented behavior from intended behavior.

**Cross-runtime propagation**

| Findings | Sibling checks |
|---|---|
| 1–2 | Any SPARC sibling: FP alignment, access-width-aware fault causes. |
| 3–7 | `a32rt`, `i686rt`, and siblings with copied signal/VM helpers: reader guards, queue ownership, disposition snapshots, suspend-frame updates. |
| 8–9, 12 | `a32rt`, `i686rt`, and runtimes carrying Provider-A file tracking: registration order, mapping lifetime, generation consumers, actual fork sharing. |
| 10 | Darwin-capable siblings using the same condition-variable futex table. |
| 11 | Siblings with duplicated difftest fault-delivery logic. |

These are propagation candidates; sibling repositories were not inspected. No inspected `.c`, `.h`, or `.S` file exceeded 900 lines—the largest was `src/rt32/vm.c` at 883. No additional concrete ELF-loader finding was established within this inspection budget.

- [x] **S32-R5-1:** Remediate `S32-R5-1` in `sparc32rt` and verify with tests.
- [x] **S32-R5-2:** Remediate `S32-R5-2` in `sparc32rt` and verify with tests.
- [x] **S32-R5-3:** Remediate `S32-R5-3` in `sparc32rt` and verify with tests.
- [x] **S32-R5-4:** Remediate `S32-R5-4` in `sparc32rt` and verify with tests.
- [x] **S32-R5-5:** Remediate `S32-R5-5` in `sparc32rt` and verify with tests.
- [x] **S32-R5-6:** Remediate `S32-R5-6` in `sparc32rt` and verify with tests.
- [x] **S32-R5-7:** Remediate `S32-R5-7` in `sparc32rt` and verify with tests.
- [x] **S32-R5-8:** Remediate `S32-R5-8` in `sparc32rt` and verify with tests.
- [x] **S32-R5-9:** Remediate `S32-R5-9` in `sparc32rt` and verify with tests.
- [x] **S32-R5-10:** Remediate `S32-R5-10` in `sparc32rt` and verify with tests.
- [x] **S32-R5-11:** Remediate `S32-R5-11` in `sparc32rt` and verify with tests.
- [x] **S32-R5-12:** Remediate `S32-R5-12` in `sparc32rt` and verify with tests.

---

## 6. `rvrt` (`841d562`) — 7 Round-5 Findings (`7 / 7` Resolved)

**Round 5 found seven actionable issues.** The strongest are incorrect accepted inputs in the Soft-TLB emitter and byte-range corruption in the VM mapping helper. Their integration limits are noted below.

Used exactly **8 shell invocations**, all read-only. No Markdown files, builds, tests, Docker, or QEMU were run. Inspected selected interpreter/FP, DBT, VM, OS, ELF32, signal, family, and test paths; this is a bounded static audit, not whole-repository qualification.

1. **[RV-R5-1] BUG — Soft-TLB stores accept registers that the lookup destroys**

   **Location:** [src/dbt/emit_mem.c:137](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:137), [src/dbt/emit_mem.h:19](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.h:19).

   `rv_dbt_reg_usable()` accepts x2, x3, and x4 as store-value registers. The emitted lookup overwrites all three before executing the store. For example, `is_store=true, val_reg=2` passes validation but stores lookup state instead of the incoming value. Loads into x20 can also destroy the pinned TLB base.

   **Fix:** Enforce the documented x0 value/destination convention, or define operation-specific register exclusions. Add negative cases for scratch registers and x20. Existing shape tests exercise `val_reg=0`.

   **Impact limit:** Repository searches found test callers of this emitter, not a production call path.

2. **[RV-R5-2] DEFECT — Emitter silently truncates site offsets**

   **Location:** [src/dbt/emit_mem.c:135](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:135), [src/dbt/emit_mem.c:152](/Users/angerman/Projects/zw3rk/rvrt/src/dbt/emit_mem.c:152).

   Validation bounds `guest_pc_delta`, but not the host offsets subsequently cast to `uint16_t`. For example, `base_offset=65536, stub_offset=65568` is accepted, yet `seq_start_offset` becomes zero. A sequence starting below 65536 can also overflow its continuation offset. Unaligned offsets are accepted even though branch encoding divides the displacement by four.

   **Fix:** Before emitting anything, validate alignment, checked offset addition, and representability of every stored offset. Add boundary tests around the last representable continuation.

   **Impact limit:** This is a demonstrated API defect; current production reachability was not established.

3. **[RV-R5-3] BUG — Partial-page file replacement overwrites surviving bytes**

   **Location:** [src/vm/vm64.c:603](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:603), [src/vm/vm64.c:618](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:618).

   On a 4 KiB host, matching low address/offset bits select `MAP_FIXED`, even when the requested range covers only part of a host page. The code expands backward by `head`; the kernel also rounds the mapped length upward. VMA removal, however, covers only the original byte range.

   For example, replacing `[4097,4098)` with file offset 1 remaps the whole page beginning at 4096. Bytes outside the requested range change while their surviving VMA metadata remains.

   **Fix:** Use direct file mapping only when the replacement covers complete host pages. Otherwise preserve surrounding bytes through the staged-copy path, or explicitly reject unsupported alignment. Test sentinels before and after a one-byte replacement.

   **Impact limit:** Runtime integration labels this VM a **best-effort shadow** at [src/runtime/runtime_main_exec_wait.c:20](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/runtime_main_exec_wait.c:20); this finding does not establish corruption of authoritative guest memory.

4. **[RV-R5-4] DEFECT / CLEAN — EOF rounding guard uses an impossible threshold**

   **Location:** [src/vm/vm64.c:703](/Users/angerman/Projects/zw3rk/rvrt/src/vm/vm64.c:703).

   The overflow guard compares `new_size / 4096` with `0xffffffffffffff`. That quotient cannot exceed `0xfffffffffffff`. Consequently, `new_size=UINT64_MAX` bypasses the guard and rounds to zero, making ordinary mapped pages appear beyond EOF.

   **Fix:** Replace the literal with checked rounding based on `UINT64_MAX` and `RV_VM64_GUEST_PAGE_SIZE`, or reject sizes outside the supported signed file-offset range.

   **Impact limit:** Normal signed host file sizes do not reach this case; the exposed `uint64_t` callback accepts it.

5. **[RV-R5-5] DEFECT — “Bounded” parity execution becomes unbounded without `timeout`**

   **Location:** [tests/parity_suite.sh:56](/Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh:56), [tests/parity_suite.sh:202](/Users/angerman/Projects/zw3rk/rvrt/tests/parity_suite.sh:202).

   When `timeout` is unavailable, the runner sets an empty prefix and executes guests directly. A looping guest hangs the suite indefinitely. The AOT cold/warm paths use the same fallback.

   **Fix:** Require a supported timeout implementation and report GAP when unavailable, or provide a bounded watchdog that terminates and reaps the child. Test timeout-tool absence and a deliberately nonterminating fixture.

6. **[RV-R5-6] DRY — Family mutation paths duplicate exact identity comparison**

   **Location:** [src/runtime/family_file_pwrite.c:17](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_file_pwrite.c:17), [src/runtime/family_file_truncate.c:269](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/family_file_truncate.c:269).

   Both define identical `same_identity()` implementations for validating staged mutation records. Future identity-field changes can update one validation path without the other.

   **Fix:** Extract one repository-local helper named for exact snapshot equality. **Do not substitute `rv_file_identity_equal()` unchanged:** it validates identities, compares only `length` bytes, and omits `mapped_key_eligible`, so its semantics differ.

7. **[RV-R5-7] YAGNI / CLEAN — Dormant commit-window field claims synchronization it never performs**

   **Location:** [src/os/backend.h:59](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend.h:59), [src/os/backend_linux.c:204](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:204), [src/os/backend_darwin.c:317](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:317).

   The comment says `in_commit_window` guards the commit step. Searches across `src/`, `test/`, and `tests/` found only its declaration and zero initialization—no reads or transitions. It supplies no protection and misstates the implemented protocol.

   **Fix:** Remove the unused field and claim, or explicitly document it as reserved if layout compatibility requires retention. Do not infer a working commit guard from this structure.

**Cross-runtime propagation checks**

| Findings | Sibling checks |
|---|---|
| RV-R5-1–2 | Check a32rt and other rt-series runtimes carrying equivalent Soft-TLB emitters for scratch-register acceptance and narrow site offsets. |
| RV-R5-3–4 | Check corresponding arena/COW providers, especially 4 KiB direct-mapping paths and EOF rounding. |
| RV-R5-5 | Check sibling `tests/parity_suite.sh` runners and the rt-series catalogue’s timeout assumptions. |
| RV-R5-6 | Check equivalent family write/truncate validation pairs; consolidate only within each repository. |
| RV-R5-7 | Check copied Darwin/Linux backend structures and their protocol comments. |

These are propagation targets, not verified sibling defects. No inspected C source/header under `src/` or `tests/` exceeded 900 lines. No additional interpreter, FP, ELF32, or signal finding met the evidence threshold within this budget.

- [x] **RV-R5-1:** Remediate `RV-R5-1` in `rvrt` and verify with tests.
- [x] **RV-R5-2:** Remediate `RV-R5-2` in `rvrt` and verify with tests.
- [x] **RV-R5-3:** Remediate `RV-R5-3` in `rvrt` and verify with tests.
- [x] **RV-R5-4:** Remediate `RV-R5-4` in `rvrt` and verify with tests.
- [x] **RV-R5-5:** Remediate `RV-R5-5` in `rvrt` and verify with tests.
- [x] **RV-R5-6:** Remediate `RV-R5-6` in `rvrt` and verify with tests.
- [x] **RV-R5-7:** Remediate `RV-R5-7` in `rvrt` and verify with tests.

---

## 7. `loongarch64rt` (`1256d4b`) — 9 Round-5 Findings (`9 / 9` Resolved)

Found **9 concrete issues**. This was a static audit using **eight shell invocations**; no Markdown files, builds, tests, Docker, or QEMU were run. No files changed. Local tooling is in `tests/`; shared tooling is in `../rt-series/tools/`.

1. **[LA64-R5-1] BUG — Hole selection can overlap an existing arena mapping.**  
   **Location:** [src/os/mem_min.c:707](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/mem_min.c:707), [src/os/syscalls_mem.c:322](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:322).  
   `la64_mem_find_hole()` checks arena occupancy only at `cand`. If the first page is free but a later page overlaps an arena mapping, it returns the occupied span. `sys_mmap()` then falls through to `la64_mem_map()`, whose overlap checks cover only its own region table. A non-fixed hinted mapping can therefore create overlapping guest mappings with different backing stores.  
   **Fix:** Check the entire candidate range against both ownership tables, advance past every intersecting mapping, and repeat the check under the mutation lock.

2. **[LA64-R5-2] BUG / YAGNI — Shared-map store propagation is implemented but never called.**  
   **Location:** [src/vm/vm_file_sync.c:208](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file_sync.c:208), [src/interp/interp_mem.h:102](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/interp_mem.h:102), [src/dbt/dbt_mem.c:298](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/dbt_mem.c:298).  
   The repository-wide C/header search finds only the declaration and definition of `vmfile_note_store()`. Interpreter stores never notify it, and DBT writable TLB entries bypass it too. On staged shared mappings, a store through one alias remains invisible through another until later synchronization. The dirty-tracking machinery consequently cannot distinguish guest stores from external file changes reliably.  
   **Fix:** Connect post-store notification to scalar, vector, atomic, and syscall copyout paths. Keep staged shared pages off the unrestricted DBT store path unless emitted stores perform equivalent tracking.

3. **[LA64-R5-3] BUG — Inode-level descriptor reuse substitutes the wrong access mode.**  
   **Location:** [src/vm/vm_file.c:362](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:362), [src/vm/vm_file.c:512](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:512), [src/vm/vm_file.c:656](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:656).  
   Registration retains the first process-local descriptor for an inode. Subsequent mappings prefer that descriptor over the descriptor supplied by the caller. If a write notification first registers an `O_WRONLY` descriptor, a later private mapping through a readable descriptor attempts `pread` on the cached write-only descriptor and fails. Conversely, a cached writable descriptor can bypass restrictions of a later read-only mapping descriptor.  
   **Fix:** Validate mapping rights against the supplied descriptor and retain suitable descriptors per mapping or capability. Inode identity alone does not establish equivalent descriptor permissions.

4. **[LA64-R5-4] BUG — Outside-arena file mappings incorrectly require read permission.**  
   **Location:** [src/os/syscalls_mem.c:178](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:178), [src/os/syscalls_mem.c:186](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_mem.c:186).  
   `mmap_file_fill()` installs the final guest protection before tracking obtains the backing pointer using `la64_mem_ptr(..., 0)`. That lookup requires guest read permission. A valid private file mapping outside the arena with `PROT_NONE`, write-only, or execute-only protection is unmapped and reported as `ENOMEM`.  
   **Fix:** Retain the backing pointer during population, or add an internal ownership lookup independent of guest access permission. Publish final protection after tracking succeeds.

5. **[LA64-R5-5] BUG — DBT accumulates FCSR Cause across multiple instructions.**  
   **Location:** [src/dbt/emit_fp_mem.c:145](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:145), [src/dbt/emit_fp_mem.c:295](/Users/angerman/Projects/zw3rk/loongarch64rt/src/dbt/emit_fp_mem.c:295), [src/interp/fp_vec_priv.h:48](/Users/angerman/Projects/zw3rk/loongarch64rt/src/interp/fp_vec_priv.h:48).  
   DBT clears FPSR once per accumulation interval and copies the accumulated exceptions into both guest sticky Flags and Cause. The interpreter replaces Cause after each operation. An exceptional FP operation followed by an exact FP operation and `MOVFCSR2GR` therefore exposes different Cause bits between engines.  
   **Fix:** Track the latest operation’s exceptions separately from accumulated sticky flags. Preserve that distinction at FCSR reads and block exits; add a two-operation regression that reads the complete FCSR.

6. **[LA64-R5-6] DEFECT — Shared file overlay installation occurs outside quiescence.**  
   **Location:** [src/vm/vm_file.c:653](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm_file.c:653), [src/vm/vm64.c:470](/Users/angerman/Projects/zw3rk/loongarch64rt/src/vm/vm64.c:470).  
   The shared-map path calls `vm64_map()` with final permissions, which commits and releases quiescence. It then replaces the backing with `rt_host_map_file()`. The next `vm64_prepare_mutation()` happens only after replacement. A peer can observe accessible zero-filled staging bytes or access the HVA during backing replacement.  
   **Fix:** Install backing and publish final page state in one transaction. Keep the range inaccessible until the host operation and tracking record succeed, and handle preparation failure before mutating backing.

7. **[LA64-R5-7] DEFECT — Malformed `PT_INTERP` silently becomes “no interpreter.”**  
   **Location:** [src/loader.c:279](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:279), [src/loader.c:288](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:288), [src/loader.c:657](/Users/angerman/Projects/zw3rk/loongarch64rt/src/loader.c:657).  
   `read_interp_path()` returns the same result for absence, malformed length, and failed reads. Its caller treats every failure as a static executable and proceeds to the executable entry point. It also appends a terminator rather than requiring the interpreter record itself to contain one.  
   **Fix:** Return distinct absent/present/error outcomes. Reject malformed or unreadable interpreter records with an executable-format error and validate their termination before loading.

8. **[LA64-R5-8] BUG — CoreMark parity can pass when every execution fails.**  
   **Location:** [tests/parity_suite.sh:538](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:538), [tests/parity_suite.sh:551](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:551).  
   CRC extraction suppresses failure and permits empty files. The verdict requires only equal exit codes and equal extracted CRC files. If oracle, interpreter, and DBT all time out before producing CRCs, equal timeout statuses plus three empty files produce `PASS`. This branch also omits comparison with committed CoreMark goldens.  
   **Fix:** Require successful execution, all expected CRC records, and agreement with committed CRC goldens. Treat timeout and setup failures explicitly.

9. **[LA64-R5-9] DRY — Duplicate parity comparators have already diverged.**  
   **Location:** [tests/parity_suite.sh:417](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:417), [tests/parity_suite.sh:505](/Users/angerman/Projects/zw3rk/loongarch64rt/tests/parity_suite.sh:505).  
   The generic Docker comparator checks oracle output and committed goldens. The separately implemented dynamic-loader comparator checks only oracle agreement, despite writing goldens during refresh. A jointly changed oracle/runtime result can pass the dynamic case without matching its committed baseline.  
   **Fix:** Factor result normalization and oracle/golden comparison into one helper within this repository. Keep case-specific execution separate.

**Cross-runtime propagation:** Check `rvrt` first for the copied VM, file-provider, and mutation patterns in findings 1–4 and 6. Check sibling AArch64 DBTs that batch FPSR updates for finding 5, ELF loaders with separate interpreter-path probes for finding 7, and sibling `tests/parity_suite.sh` implementations for findings 8–9. These are propagation targets, not verified sibling defects.

**CLEAN:** The counted source and test `.c`, `.h`, and `.S` files stayed within 900 lines. Targeted searches found no calls to `sprintf`, `strcpy`, or `strcat`. No standalone CLEAN finding warranted inclusion. Runtime reproduction and exhaustive ISA coverage remain unverified under the requested static-only budget.

- [x] **LA64-R5-1:** Remediate `LA64-R5-1` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-2:** Remediate `LA64-R5-2` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-3:** Remediate `LA64-R5-3` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-4:** Remediate `LA64-R5-4` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-5:** Remediate `LA64-R5-5` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-6:** Remediate `LA64-R5-6` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-7:** Remediate `LA64-R5-7` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-8:** Remediate `LA64-R5-8` in `loongarch64rt` and verify with tests.
- [x] **LA64-R5-9:** Remediate `LA64-R5-9` in `loongarch64rt` and verify with tests.

---

## 8. `ppc64rt` (`69d193a`) — 10 Round-5 Findings (`10 / 10` Resolved)

Round 5 identified **10 findings** through static inspection. Used **8 shell commands**; read no Markdown and ran no builds, tests, Docker, or QEMU. No files changed.

This checkout has no `tools/tests/` or `src/elf/`; inspected `tests/` and `src/run/load.c` instead. Findings below are code-derived, not execution-verified.

1. **[P64-R5-1] DEFECT — ELF program-header bounds checks can overflow. High.**  
   **Evidence:** [src/run/load.c:341](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:341), [src/run/load.c:238](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:238).  
   Both checks calculate `phoff + phnum * 56` before comparing with the image length. A near-`UINT64_MAX` offset can wrap below `len`, allowing the subsequent header loop to form and dereference an out-of-bounds pointer.  
   **Fix:** Require `phoff <= len`, then check `phnum <= (len - phoff) / 56` before any pointer arithmetic.

2. **[P64-R5-2] BUG — PLHA zero-extends negative halfwords in both engines. High.**  
   **Evidence:** [src/interp/prefix.c:151](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:151), [src/dbt/emit_mixed.c:297](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mixed.c:297).  
   The interpreter reads two bytes but sign-extends from bit 31. The DBT selects width two without setting `sext`. Thus `0x8000` becomes `32768` instead of `-32768`. Interpreter/DBT agreement masks the defect.  
   **Fix:** Sign-extend the interpreter value from `n * 8` bits and set `sext = true` for emitted PLHA. Include negative halfwords in oracle coverage.

3. **[P64-R5-3] BUG — Prefixed scalar FP accesses select the wrong register for odd RA. High.**  
   **Evidence:** [src/interp/prefix.c:187](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:187), [src/interp/prefix.c:243](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:243), [src/interp/prefix.c:269](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:269).  
   `xt` incorporates suffix bit 16, which belongs to RA. The scalar PLFS/PLFD/PSTFS/PSTFD paths then use this index. With RA odd, an access intended for FPR `rt` instead accesses VSR `rt + 32`.  
   **Fix:** Use `rt` for scalar FPR forms; decode vector register extensions separately for their actual instruction forms.

4. **[P64-R5-4] BUG — PLXSD executes as an integer halfword load. High.**  
   **Evidence:** [src/interp/decode.c:641](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:641), [src/interp/prefix.c:109](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:109).  
   The decoder distinguishes MLS PLHA from 8LS PLXSD using the prefix form. Execution instead routes every suffix opcode 42 through the integer halfword path, reading two bytes and modifying a GPR.  
   **Fix:** Dispatch execution using the decoded instruction identity, or validate the prefix form before selecting the integer path. Implement the scalar VSX operation or explicitly reject it before modifying state.

5. **[P64-R5-5] BUG — Shared writable mmap accepts a read-only descriptor. High.**  
   **Evidence:** [src/os/syscalls_mm_map.c:31](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_mm_map.c:31), [src/os/syscalls_mm_map.c:206](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_mm_map.c:206), [src/vm/vm_file.c:437](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:437).  
   File validation rejects `O_WRONLY` but never requires write access for `MAP_SHARED | PROT_WRITE`. Tracking also omits that check, so a mapping that should fail with `EACCES` succeeds.  
   **Fix:** Validate the descriptor access mode against both mapping type and protection before staging or mutation. Preserve the permitted `MAP_PRIVATE | PROT_WRITE` case on readable descriptors.

6. **[P64-R5-6] BUG — An earlier read-only mapping can silently break later shared writeback. High.**  
   **Evidence:** [src/vm/vm_file.c:193](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:193), [src/vm/vm_file.c:447](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:447), [src/vm/vm_file.c:702](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:702).  
   `vm_file_hold` retains an existing descriptor whenever its inode matches, without checking its access mode. Map an inode through `O_RDONLY`, then map it shared/writable through `O_RDWR`: writeback still uses the retained read-only descriptor. `pwrite` fails, and the write hook silently abandons persistence.  
   **Fix:** Retain suitable read and write capabilities separately, or upgrade the retained descriptor when a writable mapping arrives. Handle writeback failure explicitly.

7. **[P64-R5-7] CLEAN / DEFECT — Branch decoding invokes signed-shift undefined behavior. Medium.**  
   **Evidence:** [src/interp/decode.c:74](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:74), [src/interp/decode.c:87](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:87).  
   `bd << 16` overflows signed `int32_t` for negative branch displacements. `li << 6` shifts a signed value that still includes the primary opcode, also exceeding the representable range. These operations violate the no-undefined-behavior invariant.  
   **Fix:** Mask the displacement into an unsigned value, then sign-extend with representable arithmetic—for example, subtract the displacement modulus when its sign bit is set.

8. **[P64-R5-8] BUG — Phase 6 scripts still compile deleted `src/rt64` sources. Medium.**  
   **Evidence:** [tests/p6_host_contract.sh:84](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_host_contract.sh:84), [tests/p6_run.sh:182](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_run.sh:182).  
   The host-contract script references `src/rt64/aot/{sha256,digest}.c` and `memory/file_identity.c`; the page probe references `memory/{space,space_p1}.c`. Those paths are absent from this checkout, making these compilation stages unusable.  
   **Fix:** Port the harnesses to current APIs and source lists, preferably through maintained Make targets.

9. **[P64-R5-9] DRY — VM atomic fallback logic is duplicated. Low.**  
   **Evidence:** [src/vm/vm_atomic.c:227](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_atomic.c:227), [src/vm/vm_atomic.c:274](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_atomic.c:274).  
   Cross-page and unaligned accesses duplicate the read, reservation creation, lookup, consumption, conditional write, and result handling. Both copies also return success without performing non-LR/SC RMW operations.  
   **Fix:** Define the supported fallback behavior once in a repository-local helper, or reject unsupported alignment explicitly. Do not preserve silent successful no-ops.

10. **[P64-R5-10] YAGNI — Obsolete reservation flag remains threaded through execution. Low.**  
    **Evidence:** [src/interp/interp.c:26](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:26), [src/interp/interp.c:315](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:315), [src/interp/prefix.c:160](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:160).  
    `g_res_unused` is reset and passed to helpers that clear it, but its value does not govern reservation validity. The prefix-file comment nevertheless describes it as clearing the caller’s reservation, obscuring the actual mechanism.  
    **Fix:** Remove the obsolete flag, parameters, and stores; update comments to identify the active reservation-invalidation path.

**Cross-runtime propagation notes**

These are suggested checks, not confirmed sibling defects:

| Findings | Sibling checks |
|---|---|
| R5-1, R5-5, R5-6 | Check `rvrt`, `mips64rt`, `loongarch64rt`, and `sparc64rt` for copied ELF bounds checks, mmap access validation, and inode-level retained descriptors. |
| R5-2–R5-4 | Primarily PPC64-specific. Check `ppc32rt` for analogous algebraic-load extension and FPR/VSR field confusion where applicable. |
| R5-7 | Check `ppc32rt` branch decoding first; inspect other instruction decoders for signed left-shift sign extension. |
| R5-8 | Check sibling phase scripts for stale `src/rt64` paths after source migrations. |
| R5-9–R5-10 | Check runtimes carrying the same atomic fallback or obsolete reservation plumbing. Keep any deduplication within each repository. |

The source-size scan found **no `.c`, `.h`, or `.S` file above 900 lines** under `src/` or `tests/`. This bounded audit does not establish exhaustive signal, threading, or Soft-TLB correctness.

- [x] **P64-R5-1:** Remediate `P64-R5-1` in `ppc64rt` and verify with tests.
- [x] **P64-R5-2:** Remediate `P64-R5-2` in `ppc64rt` and verify with tests.
- [x] **P64-R5-3:** Remediate `P64-R5-3` in `ppc64rt` and verify with tests.
- [x] **P64-R5-4:** Remediate `P64-R5-4` in `ppc64rt` and verify with tests.
- [x] **P64-R5-5:** Remediate `P64-R5-5` in `ppc64rt` and verify with tests.
- [x] **P64-R5-6:** Remediate `P64-R5-6` in `ppc64rt` and verify with tests.
- [x] **P64-R5-7:** Remediate `P64-R5-7` in `ppc64rt` and verify with tests.
- [x] **P64-R5-8:** Remediate `P64-R5-8` in `ppc64rt` and verify with tests.
- [x] **P64-R5-9:** Remediate `P64-R5-9` in `ppc64rt` and verify with tests.
- [x] **P64-R5-10:** Remediate `P64-R5-10` in `ppc64rt` and verify with tests.

---

## 9. `mips64rt` (`e8f6ffe`) — 11 Round-5 Findings (`11 / 11` Resolved)

Found **11 issues** from static inspection. Used **8 shell commands**; read no Markdown files and ran no builds, tests, Docker, or QEMU. No files changed. The actual audit paths are `src/loader.c` and `tests/`; `src/elf/` and `tools/tests/` do not exist.

1. **[M64-R5-1] BUG / DRY — `clock_nanosleep` dispatch uses the wrong argument layout. High.**

   **Evidence:** [syscall_min.c:673](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:673), [syscalls_time.c:103](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_time.c:103).

   The dispatcher passes `(clock, flags, request)` into a helper expecting `(clock, request, remainder)`. A normal call with `flags == 0` therefore reads its timespec from guest address zero and ordinarily returns `EFAULT`. The N32 time64 route repeats this error. The old helper also handles `clock_nanosleep` errors through `errno`, although that host function returns the error number directly.

   **Fix:** Route both variants through the existing four-argument helper at [syscalls_extra.c:128](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_extra.c:128), passing `a0..a3`, and remove the duplicate clock path. Before enabling that helper, fix its absolute-sleep handling: it currently copies uninitialized `rm` after an interrupted `TIMER_ABSTIME` sleep, for which the host does not supply a remainder.

2. **[M64-R5-2] DEFECT — Failed file refreshes become successful zero-filled updates. High.**

   **Evidence:** [vm64.c:442](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:442), [vm_file.c:700](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm_file.c:700).

   `mips_vm_inode_refresh_span` converts every negative `pread` result into zero, zero-fills the requested span, and returns success. Consequently, `vm_inode_apply_write_locked` advances `seen_write_seq` and `seen_resize_seq`. An interrupted or failed read can corrupt an alias and suppress the Round 4 reconciliation retry.

   **Fix:** Retry `EINTR`, complete short reads, distinguish EOF from errors, and return failure after restoring protection. Prefer staging the read before modifying guest bytes.

3. **[M64-R5-3] BUG — Floating-format conversions omit signaling-NaN exceptions. High.**

   **Evidence:** [fp_cvt.c:117](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:117), [fp_cvt.c:134](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fp_cvt.c:134).

   `CVT.S.D` and `CVT.D.S` canonicalize every NaN and return without checking `fp_issn_d`/`fp_issn_s` or raising Invalid. A signaling NaN therefore neither updates the required exception state nor triggers an enabled Invalid trap. DBT NaN conversions fall back to this same interpreter behavior.

   **Fix:** Classify the original source bits, raise `FP_EXC_V` for signaling NaNs, and retain the existing `fp_finish_trap` destination-restoration path.

4. **[M64-R5-4] BUG — `CFC1` zero-extends FCSR instead of sign-extending it. Medium.**

   **Evidence:** [fpmove.c:181](/Users/angerman/Projects/zw3rk/mips64rt/src/interp/fpmove.c:181).

   Casting `ctx->fcsr` directly to `uint64_t` produces a zero-extended result. When FCC7 sets bit 31, `CFC1` must sign-extend its 32-bit control-register result into the 64-bit GPR. For example, `0x80000000` currently becomes `0x0000000080000000`.

   **Fix:** Use `interp_sext32(ctx->fcsr)` and check other 32-bit control-register transfers for the same pattern.

5. **[M64-R5-5] BUG — Raw `exit` from the thread-group leader kills surviving threads. High.**

   **Evidence:** [syscall_min.c:550](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:550), [threads.c:480](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:480).

   Only contexts marked `is_thread_clone` receive thread-only exit handling. Raw guest `exit` from the original thread reaches host `_Exit`, terminating every worker. Linux thread-only exit semantics also apply to the leader; surviving threads must continue.

   **Fix:** Separate thread termination from `exit_group` for every context. Handle leader context ownership explicitly—the current worker cleanup unconditionally frees its context—and preserve final-process exit status when the last thread terminates.

6. **[M64-R5-6] DEFECT — Production `AT_RANDOM` uses predictable clock/PID state. High.**

   **Evidence:** [loader.c:245](/Users/angerman/Projects/zw3rk/mips64rt/src/loader.c:245).

   The loader derives its seed entirely from realtime and PID, then expands it with xorshift. This is not an OS entropy source, despite the comment claiming production entropy. Guest libc can use these bytes for stack canaries and pointer guards.

   **Fix:** Obtain all 16 production bytes from the host OS random facility, handling interruptions and failures. Keep deterministic generation confined to the explicit test override.

7. **[M64-R5-7] BUG — Provider region coalescing inserts duplicate overlapping records. Medium.**

   **Evidence:** [vm64.c:74](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:74).

   After extending the left neighbor, `u0_record` decrements `i` but falls through to insertion. Mapping adjacent equal-protection regions `[A,B)` and `[B,C)` creates two records covering `[A,C)`. Repeated adjacent mappings consume the bounded table despite being coalescible.

   **Fix:** Finish the left merge without inserting another record; if the right neighbor also matches, absorb and remove it. Cover left-only and two-sided merges.

   **Scope:** References inspected show this provider interface exercised by unit tests, rather than the live `mips_mem_*` mapping path.

8. **[M64-R5-8] DEFECT — Provider capacity failures leave host mappings and metadata inconsistent. Medium.**

   **Evidence:** [vm64.c:173](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:173), [vm64.c:113](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:113), [vm64.c:234](/Users/angerman/Projects/zw3rk/mips64rt/src/vm/vm64.c:234).

   Mapping changes host memory before `u0_record` can reject table exhaustion. Conversely, unmapping a straddling region at capacity changes host memory to `PROT_NONE`, then `u0_forget` silently returns without updating metadata; the caller reports success.

   **Fix:** Preflight the resulting region table before host mutation. Make bookkeeping operations return errors and commit metadata only after the corresponding host operation succeeds. This has the same provider-only scope as finding 7.

9. **[M64-R5-9] BUG — Differential-test script can certify two failed executions. High for validation.**

   **Evidence:** [run_difftest.sh:128](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:128), [run_difftest.sh:142](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:142), [run_difftest.sh:153](/Users/angerman/Projects/zw3rk/mips64rt/tests/difftest/run_difftest.sh:153).

   The script requires only equal exit codes. Two loader failures with no instruction or register records produce equal empty streams and print `DIFFTEST: 0 divergences`. Sorting also discards instruction order, and captured stdout is never compared.

   **Fix:** Reject infrastructure failures/timeouts, require expected completion evidence and nonempty captures, and compare stdout. Preserve instruction order per process; use explicit process identification when forked traces need separation.

10. **[M64-R5-10] BUG — Implemented `clock_getres` has no syscall dispatch route. Medium.**

    **Evidence:** [syscalls_extra.c:101](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_extra.c:101), [syscall_nr.h:171](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_nr.h:171), [syscall_min.c:853](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscall_min.c:853).

    The repository defines the syscall numbers and implementation, but no dispatcher calls the helper. Guest calls fall through to `ENOSYS`.

    **Fix:** Wire the ABI-specific dispatch entries. Also fix the helper’s unconditional copyout: a valid clock query with a null result pointer must succeed without writing memory.

11. **[M64-R5-11] DRY / YAGNI / CLEAN — FP emitter retains duplicate guards and obsolete rounding machinery. Low.**

    **Evidence:** [emit_fp.c:200](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:200), [emit_fp.c:215](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:215), [emit_fp.c:130](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:130), [emit_fp.c:371](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_fp.c:371).

    `ef_mode_guard` and `ef_fs_guard` emit identical sequences using the same mask. `ef_fhalf` has no call sites; `(void)ef_fhalf` merely suppresses the unused-function warning. Comments still describe ties-away rounding although mode 4 now emits ties-to-even `FRINTN`.

    **Fix:** Consolidate the identical guard implementation, remove the unused half-constant emitter and suppression, and correct the rounding comments. Keep this consolidation within the repository.

**Cross-runtime propagation checks**

These are suggested inspection targets, not confirmed sibling defects.

| Findings | Sibling runtimes to check |
|---|---|
| 1, 5, 10 | `mips32rt` first; then `rvrt`, `a32rt`, `i686rt`, and other runtimes with copied syscall/thread dispatch |
| 2, 7, 8 | `rvrt` and runtimes carrying the same file-alias reconciliation or provider region code |
| 3, 4 | `mips32rt` first; inspect other FP engines for conversion exception handling |
| 6 | All sibling ELF loaders supplying `AT_RANDOM` |
| 9 | Sibling differential-test scripts, especially copied sorting and exit-comparison logic |
| 11 | `mips32rt` and sibling AArch64 FP emitters with matching helpers |

The source line-count scan found **no `.c`, `.h`, or `.S` file above 900 lines**; `src/os/mem_table.c` is exactly 900. Findings remain statically established paths and failure scenarios, without execution-based confirmation.

- [x] **M64-R5-1:** Remediate `M64-R5-1` in `mips64rt` and verify with tests.
- [x] **M64-R5-2:** Remediate `M64-R5-2` in `mips64rt` and verify with tests.
- [x] **M64-R5-3:** Remediate `M64-R5-3` in `mips64rt` and verify with tests.
- [x] **M64-R5-4:** Remediate `M64-R5-4` in `mips64rt` and verify with tests.
- [x] **M64-R5-5:** Remediate `M64-R5-5` in `mips64rt` and verify with tests.
- [x] **M64-R5-6:** Remediate `M64-R5-6` in `mips64rt` and verify with tests.
- [x] **M64-R5-7:** Remediate `M64-R5-7` in `mips64rt` and verify with tests.
- [x] **M64-R5-8:** Remediate `M64-R5-8` in `mips64rt` and verify with tests.
- [x] **M64-R5-9:** Remediate `M64-R5-9` in `mips64rt` and verify with tests.
- [x] **M64-R5-10:** Remediate `M64-R5-10` in `mips64rt` and verify with tests.
- [x] **M64-R5-11:** Remediate `M64-R5-11` in `mips64rt` and verify with tests.

---

## 10. `sparc64rt` (`750b805`) — 9 Round-5 Findings (`9 / 9` Resolved)

# Round 5 static audit

Five read-only shell commands completed. No Markdown files, builds, tests, Docker, or QEMU were used. Findings below are static conclusions, not reproduced failures. Inspection covered selected interpreter, DBT, VM, OS, ELF-loading, and test paths; this is not exhaustive assurance.

## Findings

### [S64-R5-1] BUG — Composite open flags are decoded by partial matches
**Priority: High**

**Location:** [src/os/syscalls_ext.c:123](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:123), lines 123–153.

The conversion loop accepts any overlapping bit instead of requiring the complete flag. `SP_O_TMPFILE` includes `SP_O_DIRECTORY`, which an earlier entry consumes. A valid request happens to match the remaining bit, but that bit alone also incorrectly enables host `O_TMPFILE`. Likewise, `SP_O_NDELAY` loses its shared `O_NONBLOCK` bit first and is then recognized from its remaining bit alone.

**Fix:** Decode composite flags before their constituent flags, require complete masks, and handle aliases explicitly. Add valid-composite and partial-mask rejection cases.

### [S64-R5-2] BUG — Ordinary `F_GETFL`/`F_SETFL` usage fails
**Priority: Medium**

**Location:** [src/os/syscalls_ext.c:346](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:346), lines 346–357.

`F_SETFL` rejects every bit except `O_APPEND` and `O_NONBLOCK`. Consequently, the usual sequence `flags = fcntl(fd, F_GETFL); fcntl(fd, F_SETFL, flags | O_NONBLOCK)` fails for an `O_RDWR` descriptor because the returned access-mode bits remain present.

**Fix:** Ignore access-mode and other immutable status bits according to the guest ABI; translate supported mutable flags. Test the round trip with read/write descriptors.

### [S64-R5-3] BUG — Vectored I/O changes blocking and atomicity semantics
**Priority: High**

**Location:** [src/os/syscalls_ext.c:243](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:243), lines 243–295.

Each vector—and each 4 KiB chunk—is issued as a separate host `read` or `write`. For example, a pipe containing exactly enough data for the first vector can make the second `read` block even though one native `readv` could return the available prefix. Small multi-vector pipe writes also lose the single-operation atomicity guarantee.

The inspected test uses only one short vector: [tests/test_h2_syscall.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:119).

**Fix:** Gather or pin validated buffers and issue one host vectored operation, then scatter read results. Validate aggregate lengths before side effects. Add multi-vector pipe tests.

### [S64-R5-4] DEFECT — ELF load bias can wrap before address validation
**Priority: High**

**Location:** [src/os/guest_run.c:268](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:268) and [src/os/guest_run.c:349](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:349).

Both `e_entry + bias` and `p_vaddr + bias` use unchecked unsigned addition. A crafted `ET_DYN` address near `UINT64_MAX` can wrap into a low address. The subsequent span validator receives the already-wrapped value, so it cannot detect the original overflow.

**Fix:** Check addition against `UINT64_MAX` before applying the bias, then validate the resulting guest range. Apply checked arithmetic to program-header and file-span calculations too.

### [S64-R5-5] BUG — `statx` silently changes pre-epoch timestamps
**Priority: Medium**

**Location:** [src/os/syscalls_stat.c:260](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:260), lines 260–264.

`put_statx_ts()` replaces every negative `tv_sec` with zero. The timestamp field is signed, so a valid file timestamp before 1970 becomes a different timestamp when returned to the guest.

**Fix:** Serialize the signed value’s 64-bit representation directly. Add a negative-second timestamp case that checks both seconds and nanoseconds.

### [S64-R5-6] DEFECT — The `statx` test passes an undersized, wrong-layout destination
**Priority: High**

**Location:** [tests/test_h2_syscall.c:86](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:86) and [tests/test_h2_syscall.c:170](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:170).

The test passes `&st`, declared as `struct stat`, to raw `SYS_statx`. The runtime writes a 256-byte result, explicitly established at [src/os/syscalls_stat.c:239](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:239) and copied at line 328. This can overwrite adjacent guest stack storage; checking only the return value also misses layout errors.

**Fix:** Use `struct statx`, verify the returned mask and size, and add surrounding canaries if testing the raw ABI.

### [S64-R5-7] DRY — Signal and ordinary syscall commits duplicate errno translation
**Priority: Medium**

**Location:** [src/os/syscalls_min.c:112](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:112) and [src/os/syscalls_sig.c:48](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_sig.c:48).

Two separate switches translate host errors, followed by duplicate `%o0`/carry updates. Their coverage already differs: the ordinary table handles errors such as `ENXIO`, `ECHILD`, and `ELOOP` that the signal table omits.

**Fix:** Keep one repository-local errno translator and result-commit helper. Leave signal-specific PC advancement in its wrapper. Verify guest errno values independently when consolidating.

### [S64-R5-8] YAGNI — An unused signal-mask implementation retains disconnected global state
**Priority: Low**

**Location:** [src/os/syscalls_ext.c:109](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:109), [src/os/syscalls_ext.c:543](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:543), and [src/os/syscalls_ext.h:242](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.h:242).

The source/test reference search found no caller of `sparc64_l2a_rt_sigprocmask`. Dispatch uses `sparc64_sig_rt_sigprocmask` instead, at `src/os/syscalls_min.c:519`. The obsolete implementation maintains its own `l2a_blocked`, disconnected from actual signal delivery.

**Fix:** Remove the unused implementation, declaration, private mask, and constants used only by this path.

### [S64-R5-9] CLEAN — Interpreter memory documentation contradicts implemented alignment traps
**Priority: Low**

**Location:** [src/interp/interp_mem.c:10](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:10), versus [src/interp/interp_mem.c:167](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:167) and line 205.

The file overview says unaligned multi-byte accesses never fault. Integer load/store helpers explicitly raise misalignment traps. This documents the opposite of an important ISA invariant and can mislead future DBT or memory-helper changes.

**Fix:** Distinguish byte-oriented transport from instruction-level alignment enforcement in the overview.

## Cross-runtime propagation

These are inspection targets, **not confirmed sibling defects**:

- **`rvrt` and sibling Linux-user runtimes:** Check copied vectored-I/O loops, `F_SETFL` filters, `statx` timestamp serialization, raw syscall test buffers, and obsolete signal helpers.
- **Sibling ELF loaders, including `hyper-linux`:** Check bias addition before range validation and program-header/file-span arithmetic.
- **Runtimes with non-generic guest ABIs:** Check composite flag translation and duplicated errno mappings using each guest’s own constants.
- Keep the proposed DRY fixes **inside each repository**; no cross-repository shared library is needed.

No inspected `.c`, `.h`, or `.S` file exceeded 900 lines; the largest was `src/os/threads.c` at 895. No additional interpreter/DBT/VM runtime defect is asserted from the limited slices inspected.

- [x] **S64-R5-1:** Remediate `S64-R5-1` in `sparc64rt` and verify with tests.
- [x] **S64-R5-2:** Remediate `S64-R5-2` in `sparc64rt` and verify with tests.
- [x] **S64-R5-3:** Remediate `S64-R5-3` in `sparc64rt` and verify with tests.
- [x] **S64-R5-4:** Remediate `S64-R5-4` in `sparc64rt` and verify with tests.
- [x] **S64-R5-5:** Remediate `S64-R5-5` in `sparc64rt` and verify with tests.
- [x] **S64-R5-6:** Remediate `S64-R5-6` in `sparc64rt` and verify with tests.
- [x] **S64-R5-7:** Remediate `S64-R5-7` in `sparc64rt` and verify with tests.
- [x] **S64-R5-8:** Remediate `S64-R5-8` in `sparc64rt` and verify with tests.
- [x] **S64-R5-9:** Remediate `S64-R5-9` in `sparc64rt` and verify with tests.

---

## 11. `rt-series` (`448a548`) — 8 Round-5 Findings (`8 / 8` Resolved)

Found **8 issues** in the current checkout. There is no `src/` directory here, so this report covers `rt-series` tools and test fixtures—not sibling interpreter, DBT, VM, OS, or ELF implementations.

Used **8 read-only shell invocations**. No Markdown files, builds, tests, Docker, or QEMU were run. Findings are based on static inspection; sibling propagation notes identify follow-up scope, not verified sibling defects.

1. **[RTS-R5-1] BUG / DRY — Duplicate architecture lists omit RV32 from benchmark execution**

   **Evidence:** [tools/bench_harness.sh:78](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:78), [tools/bench_harness.sh:549](/Users/angerman/Projects/zw3rk/rt-series/tools/bench_harness.sh:549), [tools/remote_bench_common.sh:10](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:10).

   `arch_repo` accepts `riscv32`, and the builder contains an RV32 compilation path, but `ALL_ARCHES` excludes it. Consequently, `smoke --arch riscv32` matches zero jobs; `--arch all` silently omits RV32. The shared remote matrix includes it.

   **Fix:** Derive local and remote execution matrices from one repository-local architecture definition. Ensure every accepted architecture filter either selects an executable matrix entry or is explicitly rejected.

   **Propagation:** Check `rvrt` RV32 qualification and scripts consuming these benchmark results.

2. **[RTS-R5-2] BUG — Throughput calculation overstates rates by truncating elapsed milliseconds**

   **Evidence:** [tests/bench_suite.c:112](/Users/angerman/Projects/zw3rk/rt-series/tests/bench_suite.c:112).

   For workloads exceeding 4,000 operations, the calculation divides by `floor(us / 1000)`. For example, 8,000 operations in 1,999 µs report 8,000,000 ops/s instead of approximately 4,002,001. This introduces a large discontinuity around millisecond boundaries.

   **Fix:** Calculate `iters * 1000000 / us` with sufficiently wide arithmetic, including compatible division support for freestanding targets. Define handling for results exceeding the output type.

   **Propagation:** All runtimes using `bench_suite.c`; previously reported `ops_sec` values may need recalculation from recorded microseconds.

3. **[RTS-R5-3] DEFECT — VM restoration check can pass without issuing a load**

   **Evidence:** [tests/p3_torture.c:620](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:620), [tests/p3_torture.c:637](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:637).

   The RW restoration check writes `0xCC` through an ordinary pointer and immediately compares the same location against `0xCC`. The compiler may eliminate that comparison, so it does not establish that a subsequent guest load observes the restored mapping. The deliberately faulting RO store likewise lacks an explicit volatile access.

   **Fix:** Use volatile-qualified accesses for deliberate memory probes, including initialization, faulting accesses, and post-restoration verification. Keep the expected value independently computed.

   **Propagation:** Check equivalent Soft-TLB and permission-transition fixtures in all ten runtimes.

4. **[RTS-R5-4] DEFECT — Cross-page test never creates the claimed protection-generation difference**

   **Evidence:** [tests/p3_torture.c:497](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:497), [tests/p3_torture.c:507](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:507), [tests/p3_torture.c:528](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:528).

   The test claims to cover a crossing access when the second page has a different protection generation. It maps both pages RW and never changes either page’s protection. It therefore cannot detect a crossing-access bug triggered specifically by independently invalidated page permissions.

   **Fix:** Warm both pages, change the second page’s protection independently, then check crossing accesses with explicit expected success and fault outcomes. Retain the existing byte-order checks.

   **Propagation:** All runtime Soft-TLB slow paths, especially independently protected sub-pages under `hyper-linux`.

5. **[RTS-R5-5] BUG / YAGNI — `LTP_DIR` enables a branch that never runs LTP**

   **Evidence:** [tools/run_grind.sh:600](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:600), [tools/run_grind.sh:608](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:608).

   Without a manifest, either `LIBC_TEST_DIR` or `LTP_DIR` sets `_found`. The subsequent execution loop only constructs paths from `LIBC_TEST_DIR`. Setting `LTP_DIR` alone instead probes `/bin/functional`, `/bin/math`, and `/bin/pthread`; no LTP executable is selected.

   **Fix:** Implement explicit LTP selection and invocation, or remove the ineffective `LTP_DIR` fallback and require an LTP manifest. Report libc and LTP coverage separately.

   **Propagation:** All sibling nightly/weekly jobs relying on `LTP_DIR` for syscall coverage.

6. **[RTS-R5-6] BUG — Cancellation traps remove working files without terminating the script**

   **Evidence:** [tools/run_grind.sh:25](/Users/angerman/Projects/zw3rk/rt-series/tools/run_grind.sh:25), [tools/run_catalogue.sh:299](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:299).

   Both scripts install cleanup-only handlers for `INT` and `TERM`. A trapped signal does not itself terminate the shell. Execution can resume after cleanup, potentially continuing suites with deleted inputs or starting additional work after cancellation.

   **Fix:** Use separate signal handlers that exit with 130/143 and an EXIT handler that performs cleanup while preserving status. Ensure active owned child jobs terminate before their files are removed.

   **Propagation:** Check sibling shell runners for the same `trap 'cleanup' EXIT INT TERM` pattern.

7. **[RTS-R5-7] DEFECT — Benchmark extraction accepts lines excluded by validation**

   **Evidence:** [tools/remote_bench_common.sh:147](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:147), [tools/remote_bench_common.sh:172](/Users/angerman/Projects/zw3rk/rt-series/tools/remote_bench_common.sh:172).

   Validation counts anchored, fully formatted records. Extraction subsequently matches unanchored substrings such as `/BENCH coremark/`. Output containing one valid record plus a diagnostic like `debug BENCH coremark us=123` passes validation but yields multiple values, corrupting the emitted TSV row.

   **Fix:** Validate and extract using the same exact record grammar, preferably in one parser. Emit a result only after establishing one value per required field.

   **Propagation:** All remote benchmark consumers and sibling wrappers that add diagnostic output.

8. **[RTS-R5-8] CLEAN — Catalogue runner exceeds the requested size threshold**

   **Evidence:** [tools/run_catalogue.sh:293](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:293), [tools/run_catalogue.sh:976](/Users/angerman/Projects/zw3rk/rt-series/tools/run_catalogue.sh:976).

   The file contains **1,146 lines**, combining guest payloads, embedded programs, parity parsing, container checks, and host orchestration. These independently changing responsibilities make failure paths harder to review.

   **Fix:** Preserve the public entry point while extracting repository-local guest payload and host-gate components. Keep the guest invocation self-contained or explicitly package its dependencies.

   **Propagation:** No runtime implementation change required; preserve sibling callers’ existing command interface.

- [x] **RTS-R5-1:** Remediate `RTS-R5-1` in `rt-series` and verify with tests.
- [x] **RTS-R5-2:** Remediate `RTS-R5-2` in `rt-series` and verify with tests.
- [x] **RTS-R5-3:** Remediate `RTS-R5-3` in `rt-series` and verify with tests.
- [x] **RTS-R5-4:** Remediate `RTS-R5-4` in `rt-series` and verify with tests.
- [x] **RTS-R5-5:** Remediate `RTS-R5-5` in `rt-series` and verify with tests.
- [x] **RTS-R5-6:** Remediate `RTS-R5-6` in `rt-series` and verify with tests.
- [x] **RTS-R5-7:** Remediate `RTS-R5-7` in `rt-series` and verify with tests.
- [x] **RTS-R5-8:** Remediate `RTS-R5-8` in `rt-series` and verify with tests.

---
## Part IV — Round-4 Audit Archive (125 Items Resolved & Verified by `fable`)

### 0.1 Round 4 Audit Matrix (`125 / 125` Resolved & Verified by `fable`)

Following complete remediation, `fable` (`claude-fable-5-1`) verification review, and `muse` post-review follow-up across Round 1 (`187` items), Round 2 (`145` items), and Round 3 (`85` items), Round 4 performed a fresh `gpt-6-astra` static audit of all 11 repositories at their post-Round-3 `HEAD` commits (`125` findings: `0 Critical`, `76 High`, `33 Medium`, `16 Low`).

| # | Repository | Class | Audited `master` | High | Medium | Low | BUG | DEFECT | DRY | YAGNI | CLEAN | **R4 Resolved** | Raw Round-4 `astra` Transcript |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `a32rt` | Class A | `5561e7e` | 8 | 1 | 0 | 8 | 1 | 0 | 0 | 0 | **9 / 9** | [`2026-11-03-defects-r4-a32rt-astra.md`](lode/reviews/2026-11-03-defects-r4-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `ca4c9a2` | 7 | 3 | 2 | 8 | 2 | 1 | 1 | 0 | **12 / 12** | [`2026-11-03-defects-r4-i686rt-astra.md`](lode/reviews/2026-11-03-defects-r4-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `4cead69` | 8 | 2 | 2 | 8 | 2 | 1 | 1 | 0 | **12 / 12** | [`2026-11-03-defects-r4-mips32rt-astra.md`](lode/reviews/2026-11-03-defects-r4-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `f083489` | 12 | 0 | 1 | 11 | 1 | 0 | 1 | 0 | **13 / 13** | [`2026-11-03-defects-r4-ppc32rt-astra.md`](lode/reviews/2026-11-03-defects-r4-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `f7d73db` | 11 | 3 | 2 | 12 | 2 | 1 | 1 | 0 | **16 / 16** | [`2026-11-03-defects-r4-sparc32rt-astra.md`](lode/reviews/2026-11-03-defects-r4-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `b1b08af` | 3 | 5 | 1 | 6 | 2 | 1 | 0 | 0 | **9 / 9** | [`2026-11-03-defects-r4-rvrt-astra.md`](lode/reviews/2026-11-03-defects-r4-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `1907d96` | 12 | 4 | 2 | 13 | 2 | 1 | 1 | 1 | **18 / 18** | [`2026-11-03-defects-r4-loongarch64rt-astra.md`](lode/reviews/2026-11-03-defects-r4-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `56bec31` | 3 | 3 | 2 | 6 | 1 | 1 | 0 | 0 | **8 / 8** | [`2026-11-03-defects-r4-ppc64rt-astra.md`](lode/reviews/2026-11-03-defects-r4-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `f7c6924` | 4 | 4 | 2 | 7 | 1 | 1 | 1 | 0 | **10 / 10** | [`2026-11-03-defects-r4-mips64rt-astra.md`](lode/reviews/2026-11-03-defects-r4-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `5232650` | 8 | 2 | 1 | 9 | 1 | 1 | 0 | 0 | **11 / 11** | [`2026-11-03-defects-r4-sparc64rt-astra.md`](lode/reviews/2026-11-03-defects-r4-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `5e6cbc0` | 0 | 6 | 1 | 2 | 4 | 1 | 0 | 0 | **7 / 7** | [`2026-11-03-defects-r4-rt-series-astra.md`](lode/reviews/2026-11-03-defects-r4-rt-series-astra.md) |
| | **Total (Round 4)** | | | **76** | **33** | **16** | **90** | **19** | **9** | **6** | **1** | **125 / 125** | |

### 0.2 Round 4 Cross-Cutting Defect Clusters (Cross-Runtime Check Index)

- [x] **X-R4-1 — High — File-Mapping Coordinate vs Guest-VA Confusion, Truncate/EOF Handling & Staged `MAP_SHARED` Coherence**
  - **Linked Items**: `A32-R4-4`, `I686-R4-3`, `M32-R4-5`, `M32-R4-9`, `M32-R4-10`, `P32-R4-2..5`, `P32-R4-7`, `P32-R4-9`, `P32-R4-10`, `S32-R4-12`, `LA64-R4-3`, `LA64-R4-5`, `LA64-R4-6`, `LA64-R4-9`, `LA64-R4-10`, `M64-R4-1`, `M64-R4-2`
  - **Summary**: Truncate discard (`LA64-R4-6`) and file-write invalidation (`M64-R4-1`) comparing file offsets against guest VAs instead of intersecting `[file_off, file_off + len)` and translating back to GVA; `ftruncate` hooks (`I686-R4-3`, `P32-R4-9`) calling `memset()` on read-only or beyond-EOF pages; fork snapshots (`A32-R4-4`), `ppc32rt` (`P32-R4-7`), and `sparc32rt` (`S32-R4-12`) reading/exposing zero pages beyond EOF; and staged `MAP_SHARED` writeback/refresh/EOF clamping (`M32-R4-9..10`, `P32-R4-2..5`, `LA64-R4-3`, `LA64-R4-5`, `LA64-R4-9..10`, `M64-R4-2`).
- [x] **X-R4-2 — High — Transactional VMA / File-Backing Splits, `mremap` Growth/Relocation Rollback & Darwin Anonymous Replacement**
  - **Linked Items**: `A32-R4-1`, `A32-R4-2`, `A32-R4-5`, `A32-R4-6`, `A32-R4-8`, `I686-R4-4`, `I686-R4-5`, `I686-R4-11`, `M32-R4-5`, `M32-R4-6`, `M32-R4-7`, `P32-R4-6`, `S32-R4-11`, `S32-R4-13`, `RV-R4-3..6`, `LA64-R4-4`, `P64-R4-3`, `M64-R4-3`, `M64-R4-4`, `S64-R4-3..6`
  - **Summary**: Darwin anonymous `MAP_FIXED` replacement (`PROT_NONE` or over shared-file sub-pages) retaining old bytes or shared-file backing (`A32-R4-2`, `M32-R4-5`, `S32-R4-11`); 16 KiB sub-page protection widening/restoration and shared-tail placement (`I686-R4-4`, `P32-R4-6`, `RV-R4-3`, `RV-R4-6`, `M64-R4-3`); and non-transactional VMA/file-backing splits, `mremap` growth/relocation rollback, and same-start prefix replacement (`A32-R4-1`, `A32-R4-5..6`, `A32-R4-8`, `I686-R4-5`, `M32-R4-6..7`, `S32-R4-13`, `RV-R4-4`, `LA64-R4-4`, `P64-R4-3`, `M64-R4-4`, `S64-R4-3..6`).
- [x] **X-R4-3 — High — `execve` Internal Signal Handoff Env Vars Leaking into Guest Stack & Signal/Exec/FD Lifecycle**
  - **Linked Items**: `A32-R4-7`, `I686-R4-6`, `S32-R4-4..10`, `S32-R4-14`, `LA64-R4-12..14`, `P64-R4-4..7`, `M64-R4-8`, `S64-R4-7..8`
  - **Summary**: `A32RT_EXEC_SIG*` / `PPC64RT_EXEC_SIG*` handoff env vars copied onto the guest stack before `unsetenv()` or duplicated across repeated `execve` (`A32-R4-7`, `P64-R4-6`); worker `execve` pending-signal & default-disposition inheritance (`P64-R4-4..5`, `S32-R4-9`); `SA_RESETHAND` handler snapshotting before reset (`LA64-R4-12`), `sigaltstack` old-state snapshot before overwrite (`M64-R4-8`), thread-safe signal-action snapshots (`I686-R4-6`), SPARC↔host signal translation & per-thread signal state (`S32-R4-4..8`, `S64-R4-8`), and `CLOEXEC` deferral until exec commit (`S32-R4-10`, `S32-R4-14`, `S64-R4-7`).
- [x] **X-R4-4 — High — Multi-Threaded `fork()` / `clone()` Lock Ordering, Shared Metadata Privatization & DBT Quiescence**
  - **Linked Items**: `A32-R4-3`, `I686-R4-1`, `I686-R4-2`, `M32-R4-8`, `P32-R4-8`, `S32-R4-1..3`, `LA64-R4-7..8`, `LA64-R4-11`, `S64-R4-9`
  - **Summary**: `a32rt` resuming parent threads before restoring guest protections after `fork` (`A32-R4-3`), `i686rt` `fork` vs A2 futex lock-order inversion (`I686-R4-1`) and `MAP_SHARED` `s_prot`/`s_state`/`s_flags` metadata (`I686-R4-2`), `ppc32rt` `fork` vs `ftruncate` lock-order inversion (`P32-R4-8`), `sparc32rt` `clone` startup struct UAF (`S32-R4-1`), retired thread copyout (`S32-R4-2`), and DBT invalidation before releasing `vm_lock` (`S32-R4-3`), `loongarch64rt` pre-fork inode refcount & process-local `dupfd` (`LA64-R4-7..8`) and file map/unmap under VM quiescence (`LA64-R4-11`), and `sparc64rt` futex deadline preservation across `-EINTR` retries (`S64-R4-9`).
- [x] **X-R4-5 — High — Syscall Copyout LL/SC Interior Bucket Invalidation, Sub-Page Permission Checks & Vectored I/O**
  - **Linked Items**: `A32-R4-9`, `I686-R4-8`, `I686-R4-9`, `M32-R4-1`, `M32-R4-2`, `P32-R4-1`, `P32-R4-11`, `P32-R4-12`
  - **Summary**: `mips32rt` bulk copyout bumping only the first and last 64-byte LL/SC buckets instead of all spanned buckets (`M32-R4-1`) and `read`/`readv` bypassing tracked copyout (`M32-R4-2`), `ppc32rt` `sys_vec` `readv` subtracting `total` during SMC invalidation and returning `0` (`P32-R4-1`) plus sub-page permission & LL/SC copyout (`P32-R4-11..12`), `a32rt` `epoll_wait` validating only 1 event (`A32-R4-9`), and `i686rt` `pread64`/`pwrite64` A2 marshalling (`I686-R4-8`).
- [x] **X-R4-6 — High — ISA / FPU Emulation, DBT Codegen & Intra-Repo DRY / YAGNI / Harness**
  - **Linked Items**: `I686-R4-7`, `I686-R4-10..12`, `M32-R4-3..4`, `M32-R4-11..12`, `P32-R4-13`, `S32-R4-15..16`, `RV-R4-1..2`, `RV-R4-7..9`, `LA64-R4-1..2`, `LA64-R4-15..18`, `P64-R4-1..2`, `P64-R4-8`, `M64-R4-5..7`, `M64-R4-9..10`, `S64-R4-1..2`, `S64-R4-10..11`, `RTS-R4-1..7`

---

## 1. `a32rt` (`5561e7e`) — 9 Round-4 Findings (`9 / 9` Resolved)

Found **9 actionable issues** at HEAD `5561e7e`. The Round-3 fixes are present, but several replacement, remapping, fork, and exec paths remain incomplete.

Used exactly **7 shell inspection commands**, including the requested history commands. No Markdown files, builds, tests, containers, or QEMU were read or run. These are static findings; runtime reproduction remains outstanding. The working tree is clean.

**A32-R4-1 — Repeated private-file `mremap` loses backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_mremap.c:194`
- **Evidence & Root Cause:** In-place growth creates a separate file-tracking record for the extension. Only shared mappings receive the attempted record merge at line 207. A subsequent private remap spanning the enlarged range fails `mremap_priv_lookup()`’s single-record coverage requirement at line 66. The caller treats this as anonymous backing: further growth supplies zero-filled pages, and relocation drops file identity and EOF behavior. Descriptor-duplication failure also silently takes this anonymous fallback.
- **Concrete Fix:** Coalesce compatible private backing records after growth, or resolve backing across contiguous records with matching inode and offsets. Distinguish absent backing from lookup/resource errors and propagate errors. Add regressions for grow→grow and grow→move, including descriptor exhaustion.

**A32-R4-2 — Darwin anonymous replacement retains old storage and sharing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:77`
- **Evidence & Root Cause:** The replacement branch uses `mprotect`, optional `memset`, and `minherit`; it never replaces the backing object. Replacing a shared-file mapping with private anonymous memory therefore writes zeros into the shared file and leaves subsequent accesses attached to it. Separately, anonymous `PROT_NONE` replacement skips zeroing entirely; a later `mprotect` exposes bytes from the previous mapping.
- **Concrete Fix:** Install genuinely fresh anonymous backing. For sub-page replacements, preserve unaffected 4 KiB siblings while replacing the necessary host-page storage, and retain shared aliases correctly. Add shared-file→anonymous replacement and `PROT_NONE`→read/write zero-fill regressions on Darwin.

**A32-R4-3 — Fork resumes parent threads before restoring protections**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:226`
- **Evidence & Root Cause:** The snapshot path changes guest clusters to `PROT_NONE` at lines 211–218. Immediately after `fork()`, the parent calls `a32_jit_fork_parent()`, clearing the execution barrier and releasing the JIT lock. Guest protections are restored only at lines 250–255. Another guest thread can resume inside this interval and fault on valid memory.
- **Concrete Fix:** Keep parent execution blocked until all guest protections are restored, including the failed-fork path. Check restoration failures before reopening execution. Add a concurrent memory-access/fork regression.

**A32-R4-4 — Fork snapshot reads inaccessible EOF pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:208`
- **Evidence & Root Cause:** Snapshot selection uses VMA permissions, then copies each entire region. File mappings retain their requested VMA permissions even when `a32_vm32_set_eof_cut()` makes trailing pages inaccessible on A1. A readable mapping extending beyond EOF consequently reaches this unconditional `memcpy` over protected pages. Signals are blocked during the operation. The new EOF-aware `mremap` handling has no equivalent here.
- **Concrete Fix:** Snapshot accessible file-backed prefixes page by page, respecting EOF cuts. Preserve cut metadata and protections during restoration rather than applying VMA permissions across the whole region. Add fork coverage for fresh beyond-EOF mappings and mappings truncated before fork.

**A32-R4-5 — Same-start prefix replacement defeats the new capacity preflight**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:151`
- **Evidence & Root Cause:** `a32_vmfile_check_replace()` treats any record beginning at `start_gva` as reusable. If the replacement covers only its prefix, retirement moves that record’s start to `unmap_end` at lines 664–666; its slot remains occupied by the surviving suffix. With a full table, preflight nevertheless succeeds. `a32_vm_mmap_locked()` retires metadata at line 635, then fails its second capacity check at line 639, leaving the old host prefix mapped without its previous tracking.
- **Concrete Fix:** Count same-start records as freed only when fully covered. Reserve replacement and split resources before retiring anything. Add a full-table test replacing only the first page of a larger file mapping.

**A32-R4-6 — Failed backing splits silently preserve records over unmapped memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:634`
- **Evidence & Root Cause:** Middle splits silently `continue` when a slot or duplicated descriptor cannot be obtained; the private-record path does likewise at lines 673–678. The caller receives no error. `munmap` has already replaced the host range, and anonymous `MAP_FIXED` bypasses the file replacement preflight. Old backing records can therefore cover holes or unrelated anonymous mappings. Later file truncation can apply EOF cuts to that unrelated memory.
- **Concrete Fix:** Make backing retirement fallible and reserve all split slots/descriptors before host or VMA mutation. Propagate failure without changing the mapping. Exercise both table exhaustion and `EMFILE` during middle unmap/replacement.

**A32-R4-7 — Exec signal variables survive in the guest environment and override fresh state**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/main.c:349`
- **Evidence & Root Cause:** The guest stack receives `envp` before `exec_signal_restore()` unsets the three transport variables at line 357. Unsetting the host environment does not remove the guest’s copied strings. On another exec, `os_sys_sig_time.c:669` copies those old entries and appends new entries with identical names. Startup `getenv()` can consequently consume the earlier, stale signal mask, ignored set, and pending set. The claimed native-child cleanup is also incomplete because native exec receives the guest-supplied environment.
- **Concrete Fix:** Consume and remove transport entries before constructing the guest environment. Filter existing transport keys when composing subsequent exec environments, then insert exactly one current value per key. Add repeated-exec tests that change masks and dispositions between execs.

**A32-R4-8 — VMA exhaustion makes partial `mprotect` alter unrelated metadata**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:280`
- **Evidence & Root Cause:** When splitting a VMA cannot allocate entries, `vm_mprotect_regions_locked()` substitutes `r->prot = prot` for the whole original region. Similar fallbacks exist at lines 288 and 297. Host permissions and Soft-TLB permissions are changed only for the requested range, while the VMA records claim broader changes. The syscall still reports success, leaving contradictory permission state for subsequent VM operations.
- **Concrete Fix:** Preflight required VMA splits before changing host permissions. Return `-ENOMEM` without mutation when capacity is insufficient; never widen the metadata update. Add a saturated-region-table partial-`mprotect` regression.

**A32-R4-9 — Epoll output validation covers only one event**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/os_sys_fs_arm.c:89`
- **Evidence & Root Cause:** Both `epoll_wait` and `epoll_pwait` validate only `sizeof(struct epoll_event)` bytes, then pass guest memory directly to the kernel with guest-controlled `maxevents`. Additional returned events can cross guest protection boundaries. This matters on A2 Linux hosts, where host-page permissions can permit writes that guest 4 KiB permissions prohibit.
- **Concrete Fix:** Check the complete bounded output extent, or receive events into a host buffer and perform checked guest copyout for the returned count. Share that validation/copyout helper between both branches. Add a multiple-ready-event test with the buffer ending immediately before a protected guest page.

The inspected source files satisfy the 900-line limit, and the targeted search found no forbidden string functions, unity includes, or literal `x18` use. Warning policy includes the requested C11 flags. This was not compilation-based compliance verification. No sufficiently supported standalone DRY, YAGNI, or CLEAN finding emerged; ISA/FPU and concurrency coverage is not exhaustive within the inspection budget.

- [x] **A32-R4-1:** Preserve private backing across repeated remaps and propagate lookup errors.
- [x] **A32-R4-2:** Replace Darwin anonymous backing without retaining old bytes or file aliases.
- [x] **A32-R4-3:** Restore parent protections before reopening JIT execution.
- [x] **A32-R4-4:** Make fork snapshots and restoration respect EOF cuts.
- [x] **A32-R4-5:** Correct capacity accounting for same-start prefix replacements.
- [x] **A32-R4-6:** Reserve backing-split resources before mutation and propagate failures.
- [x] **A32-R4-7:** Remove stale exec signal transport entries from guest environments.
- [x] **A32-R4-8:** Reject partial protection changes when VMA splits cannot be represented.
- [x] **A32-R4-9:** Validate or safely copy out the complete epoll result.

---

## 2. `i686rt` (`ca4c9a2`) — 12 Round-4 Findings (`12 / 12` Resolved)

Found **12 actionable issues** at HEAD `ca4c9a2`. The Round-3 and follow-up changes are present, but fork locking, remap rollback, and file-backing paths remain incomplete.

Used seven shell inspection commands, including the requested history commands. No builds, tests, containers, or QEMU ran. Findings below are static conclusions, not runtime reproductions. The line-count scan found no `.c`, `.h`, or `.S` file over 900 lines; no separate CLEAN finding is asserted.

**I686-R4-1 — Fork preparation reverses the A2 futex lock order**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm32.c:89`
- **Evidence & Root Cause:** `i686_vm32_fork_prepare()` acquires `s_subpage_mtx`, then `s_futex_mtx`. `i686_vm32_futex()` acquires `s_futex_mtx` at line 351 and calls `vm32_futex_load_u32()`, which acquires the subpage lock at line 295. Concurrent fork and A2 `FUTEX_WAIT` can each hold the mutex the other needs. `FUTEX_CMP_REQUEUE` has the same inversion.
- **Concrete Fix:** Establish one lock order for fork, futex value validation, and waiter registration. Preserve atomic check-and-enqueue semantics when restructuring; simply releasing the futex mutex before checking introduces lost wakeups.

**I686-R4-2 — Fork shares address-space protection metadata**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:126`
- **Evidence & Root Cause:** `s_prot`, `s_state`, and `s_flags` use `MAP_SHARED | MAP_ANONYMOUS`. Fork handlers reset locks but do not privatize these arrays. A child's `munmap()` clears protection and mapped flags through `rt32_vm_file_sync_prot_locked()` (`src/rt32/rt32_vm.c:232`), changing the parent's metadata despite separate VMAs. A2 permission checks and host-page protection reconstruction consequently use another process's mapping state.
- **Concrete Fix:** Make per-address-space protection, presence, and private-COW state fork-private. Keep any genuinely shared file-object state separate and keyed by backing identity rather than guest address.

**I686-R4-3 — Truncate maintenance writes directly into inaccessible file pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:336`
- **Evidence & Root Cause:** `i686_pass_r_ftruncate64()` invokes `i686_vm_file_note_ftruncate()` after successful host truncation. That function calls `i686_vm_file_note_shrink()`, which blindly `memset()`s entire pages past EOF. Read-only staged mappings are not writable; native file mappings wholly beyond the new EOF can raise SIGBUS even when writable. The hook also traverses `s_maps` without the VM lock, racing mapping removal and replacement.
- **Concrete Fix:** Serialize tracking changes. Let native mappings retain host EOF behavior without touching invalidated pages. For staged mappings, maintain explicit EOF validity and update accessible partial-page bytes through a checked protection window. Do not implement beyond-EOF pages as ordinarily readable zero pages.

**I686-R4-4 — A2 remap copies through protections that have already been restored**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:525`
- **Evidence & Root Cause:** The provisional destination comes from `vm_mmap2_locked()`, which restores A2 covering-page protections and releases the subpage lock before returning. Relocation then performs raw `memcpy()` at line 534. A valid writable destination sharing a 16 KiB host page with an unmapped subpage can therefore be host `PROT_NONE`. The source workaround at line 529 also passes a merely 4 KiB-aligned address to `mprotect()` and ignores failure.
- **Concrete Fix:** Copy staged mappings under the subpage exclusion protocol, temporarily opening aligned source and destination host-page covers. Check protection changes and restore every opened cover on success and failure.

**I686-R4-5 — File remap rollback can discard the original backing record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:409`
- **Evidence & Root Cause:** In-place growth removes tracking for the entire expanded range before installing its replacement. `i686_vm_file_track_map()` can fail when duplicating the backing descriptor (`src/vm/vm_file.c:348`). The error branch only unmaps the extension; it never restores the original mapping's tracking. HEAD's `rec_rc` check fixes one earlier failure ordering, but does not make this replacement transactional.
- **Concrete Fix:** Prepare the replacement record and owned descriptor before deleting existing records. Commit the replacement atomically under the VM lock; preserve the original record and descriptor on every failure.

**I686-R4-6 — Signal-action lookup returns a process-global scratch object**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sys_pass.c:29`
- **Evidence & Root Cause:** Every `i686_gsig_tab()` call overwrites the same static `v`. Concurrent deliveries for different signals retain pointers to that object while building frames and reading flags and masks. One thread can substitute another signal's action mid-delivery. Concurrent `rt_sigaction()` also reads and writes `s_sigact` without synchronization, allowing torn actions and C data races.
- **Concrete Fix:** Return an action snapshot into caller-owned storage. Synchronize publication and reads of the complete action, using a mechanism suitable for every calling context. Carry that single snapshot through delivery and frame construction.

**I686-R4-7 — Default x87 logarithm handling rejects valid inputs and reverses infinity signs**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/h_x87_math.c:534`
- **Evidence & Root Cause:** The default binary64 path rejects every `a < 0.0`, including valid `FYL2XP1` inputs such as `a = -0.25`. For `FYL2X` with `a = 0` and positive `b`, line 542 produces positive infinity, although `b × log2(0)` is negative infinity. Zero multipliers also need invalid-operation handling rather than unconditional infinity.
- **Concrete Fix:** Separate the two instructions' domain checks. Handle zero, signed multiplier, infinities, and invalid products explicitly before the ordinary logarithm calculation. Add focused cases for negative valid `FYL2XP1` inputs and `FYL2X` zero operands.

**I686-R4-8 — Positioned I/O bypasses A2 guest-buffer marshalling**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sys_pass_io.c:436`
- **Evidence & Root Cause:** `sys_pread64()` and `sys_pwrite64()` pass `i686_guest_ptr()` directly to host I/O after checking only the lower address bound. A valid guest buffer on a restrictive A2 covering page returns host `EFAULT`; kernel copy faults do not enter the runtime's user-space healing checkpoint. These paths also omit the guest-span overflow validation provided by the copy helpers.
- **Concrete Fix:** Use bounded host buffers with checked guest copy-in/copy-out, or a complete validated and synchronized host-access window. Preserve short-I/O semantics and route successful copyout through the required memory-write bookkeeping.

**I686-R4-9 — Darwin file-copy backend ignores the explicit output offset**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/backend_darwin_io.c:280`
- **Evidence & Root Cause:** `rt_host_copy_file_range()` calculates `out` from `*off_out`, then calls `rt_host_sendfile()`. That helper uses `write(out_fd, ...)`, so copying occurs at the descriptor's current position and advances it. The function nevertheless reports advancement of the supplied explicit offset. This differs from the Linux backend contract. No guest syscall caller was found, so this is currently a backend API defect.
- **Concrete Fix:** Implement positioned writes when `off_out` is supplied, leaving the descriptor position unchanged. Advance only the offsets corresponding to bytes actually copied, and reject unsupported flags.

**I686-R4-10 — x86_64 incremental builds ignore header changes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:74`
- **Evidence & Root Cause:** The x86_64 object rule depends only on `src/%.c`, unlike the ordinary and Darwin rules that include `$(HDRS)`. Editing context layouts, decoder declarations, or inline helpers can leave stale interpreter objects and produce an inconsistent binary.
- **Concrete Fix:** Add `$(HDRS)` to this rule, or generate and include compiler dependency files consistently across object variants.

**I686-R4-11 — File-map replacement capacity logic is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/vm/vm_file.c:405`
- **Evidence & Root Cause:** `i686_vm_file_can_replace()` and `i686_vm_file_untrack_map()` independently calculate free slots and interior splits. Their validation already differs: only the former rejects zero-length or beyond-window spans. This duplicates the rules governing a mutation-sensitive operation.
- **Concrete Fix:** Introduce one repo-local replacement planner that validates the span and computes required slots and splits. Use its result for both preflight and commit, including preparation of required descriptors.

**I686-R4-12 — The old registry host-TID setter is unused**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/clone.c:158`
- **Evidence & Root Cause:** Round-3 removed the setter's call from `thread_entry()` in favor of the startup handshake. Source searches found only its declaration and definition, with no callers or public-header declaration. The compatibility comment now preserves unused mutation machinery.
- **Concrete Fix:** Remove `i686_thread_registry_set_host_tid()` and its obsolete compatibility comment.

- [x] **I686-R4-1:** Unify fork and A2 futex lock ordering.
- [x] **I686-R4-2:** Make address-space metadata fork-private.
- [x] **I686-R4-3:** Repair truncate protection, EOF, and synchronization handling.
- [x] **I686-R4-4:** Copy A2 remaps through checked protection windows.
- [x] **I686-R4-5:** Make file-remap tracking replacement transactional.
- [x] **I686-R4-6:** Publish and consume coherent signal-action snapshots.
- [x] **I686-R4-7:** Correct x87 logarithm domain and exceptional results.
- [x] **I686-R4-8:** Marshal positioned-I/O guest buffers safely.
- [x] **I686-R4-9:** Honor Darwin file-copy output offsets.
- [x] **I686-R4-10:** Track headers in x86_64 incremental builds.
- [x] **I686-R4-11:** Unify file-map replacement planning.
- [x] **I686-R4-12:** Remove the unused registry setter.

---

## 3. `mips32rt` (`4cead69`) — 12 Round-4 Findings (`12 / 12` Resolved)

Found **12 actionable issues** at HEAD `4cead69`. The Round-3 and post-fable fixes are present, but several paths remain incomplete.

Used exactly **7 shell inspection commands**, including the requested history commands. No Markdown documents, builds, tests, containers, or QEMU were run. The working tree is clean. Findings below are static traces, not runtime reproductions.

**M32-R4-1 — Bulk copyout misses interior LL/SC reservation epochs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/mem.c:405`
- **Evidence & Root Cause:** `rt32_vm_copy_to()` now reaches `mips_guest_store_commit()`, but `ll_epoch_bump_locked()` increments only the first and last 64-byte buckets. That was sufficient for small stores, not arbitrary copyout or mremap lengths. A peer’s reservation at `base + 64` survives a same-value 192-byte copyout starting at aligned `base`. The Round-3 test covers only four bytes.
- **Concrete Fix:** Increment every affected bucket under the existing lock; for ranges spanning the entire hash table, increment each bucket once. Add a two-context regression reserving an interior word.

**M32-R4-2 — `read` and `readv` still bypass tracked copyout**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscall_min.c:149`
- **Evidence & Root Cause:** `sc_read()` passes the guest address directly to host `read()`. Likewise, `src/os/syscalls.c:665` builds guest-backed iovecs for host `readv()`. Neither path invokes the new store-commit primitive. A host read that overwrites a peer’s reserved word with the same value leaves its epoch unchanged, allowing SC to succeed.
- **Concrete Fix:** Read into host staging storage, then commit the returned bytes through validated, epoch-tracked copyout. Preserve partial-read and iovec ordering semantics. Do not hold the LL spinlock across blocking I/O. Add actual read/readv regressions.

**M32-R4-3 — DBT `CVT.L` destroys the low result word**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_cvt.c:203`
- **Evidence & Root Cause:** The 64-bit conversion initially places its low word in `A64_TMP1`. The negative-overflow check then overwrites that register with a Boolean predicate at lines 203–207. Line 212 selects between `0xFFFFFFFF` and that predicate, and line 215 stores it as the conversion result. For an ordinary exact conversion such as `CVT.L.D(1.0)`, the low word becomes zero.
- **Concrete Fix:** Preserve both result halves while calculating the overflow predicate in separate scratch storage. Add interpreter/DBT comparisons for exact positive and negative values with nonzero low words, plus both overflow boundaries.

**M32-R4-4 — DBT conversion pre-rounding loses Inexact**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_cvt.c:123`
- **Evidence & Root Cause:** For `CVT.W`/`CVT.L` with round-to-nearest, the emitter uses `FRINTN` before `FCVTZS`. The rounding step does not report Inexact, and the subsequent conversion receives an integral operand. In contrast, `src/interp/fp.c:618` raises `FP_E_I` for discarded fractional bits in these conversions. Thus `CVT.W.D(1.5)` can produce matching integer results but divergent FCSR state.
- **Concrete Fix:** Preserve discarded-fraction information or use an appropriate exact rounding sequence, then merge Inexact into the guest exception machinery. Test FCSR flags, causes, and enabled-exception behavior across rounding modes.

**M32-R4-5 — Darwin sub-page replacement retains the previous file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_mmap.c:173`
- **Evidence & Root Cause:** An aligned 16 KiB file mapping takes the direct host `mmap()` path at line 161. Replacing one 4 KiB slice takes the shadow path, which merely changes protection and calls `memset()`/`pread()` on the existing host mapping. If that mapping was `MAP_SHARED`, creating a supposedly anonymous replacement writes zeros into the original file. The replacement also remains physically file-backed despite its new VMA metadata.
- **Concrete Fix:** Convert affected direct host pages to owned shadow backing before replacing sub-pages, preserving neighboring bytes and their backing metadata. Add a regression mapping a shared 16 KiB file page, replacing one 4 KiB slice anonymously, and checking file contents and subsequent isolation.

**M32-R4-6 — `mremap` accepts incompatible adjacent file mappings**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm.c:514`
- **Evidence & Root Cause:** `vm_check_mapped_range_locked()` checks subsequent regions only for matching protection and flags. It returns backing information from the first region without checking subsequent inode identities or file offsets. `rt32_vm_mremap()` then uses that single backing to recreate the whole shared range at `src/rt32/vm_mmap.c:506`. Adjacent mappings of different files with identical flags/protection can therefore become entirely backed by the first file.
- **Concrete Fix:** Require compatible backing identity and contiguous offsets for a remappable range, or preserve each segment explicitly. Reject unsupported multi-mapping ranges before modifying the destination. Cover different files and discontinuous offsets within one file.

**M32-R4-7 — Failed Darwin population leaves modified mappings and elevated protection**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_mmap.c:187`
- **Evidence & Root Cause:** The shadow path elevates the host-rounded range to RW and zeros its contents before reading the file. On a population error, it closes the duplicate descriptor and returns immediately. It neither restores protection nor reconciles the old VMA metadata with the overwritten bytes. With `MAP_FIXED`, an existing mapping can retain its old metadata after its contents have been destroyed.
- **Concrete Fix:** Stage fallible file population before modifying live mappings. Ensure every failure after protection elevation restores host protections and leaves mapping metadata consistent with the actual backing. Add injected read-error coverage for both vacant and occupied destinations.

**M32-R4-8 — Clone writes `ctid` without `CLONE_CHILD_SETTID`**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads.c:250`
- **Evidence & Root Cause:** Clone stores the supplied `ctid` unconditionally in `t->ctid` at line 355. The child then writes its TID whenever that pointer is nonzero, regardless of `CLONE_CHILD_SETTID`. This modifies an argument that should be ignored when neither child-TID flag is set, and adds an unintended startup write for `CLONE_CHILD_CLEARTID` alone.
- **Concrete Fix:** Track startup SETTID and exit CLEARTID separately. Gate the startup write on `CLONE_CHILD_SETTID`; retain the pointer independently for clearing on exit. Revisit the parent alias suppression using the actual startup-write condition.

**M32-R4-9 — Darwin writeback treats read errors as a valid zero baseline**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_darw.c:173`
- **Evidence & Root Cause:** The baseline buffer is zero-initialized. A non-EINTR `pread()` failure merely breaks the loop; it does not set `rc` or abort processing. The function then compares against incomplete baseline data, propagates bytes into aliases, and may write the whole chunk back. A failed baseline read can consequently erase file bytes represented by the untouched zero portion of the buffer.
- **Concrete Fix:** Distinguish EOF from read failure and stop before alias mutation or writeback on failure. Propagate the error through flush callers that currently discard it. Add fault-injected short-read/EIO coverage.

**M32-R4-10 — Shadow flush can overwrite newer direct-mapping writes**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_darw.c:209`
- **Evidence & Root Cause:** Dirty detection compares a shadow against the *current file*, not the shadow’s last synchronized contents. Create a shadow alias and an aligned direct shared alias of the same initially zero bytes. Write `1` through the direct alias; the file now reads `1`, while the shadow still contains `0`. Flushing the untouched shadow classifies its zero as dirty and overwrites both the direct alias and file. The Round-3 shadow-to-shadow propagation does not resolve this mixed-backing case.
- **Concrete Fix:** Use coherent shared backing or actual dirty tracking with a retained synchronization baseline. Do not infer dirtiness solely from disagreement with current file contents. Add both alias-creation orders and direct-write/shadow-flush regressions.

**M32-R4-11 — FPR cache indexing is duplicated across emitters**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/dbt/emit_fp_cvt.c:29`
- **Evidence & Root Cause:** The cache hash implemented by `fpr_slot()` in `src/dbt/emit_fp.c:142` is repeated in conversion invalidation, including line 221. The comment explicitly acknowledges the duplication. A change to indexing can leave invalidation targeting a different slot.
- **Concrete Fix:** Put the cache-index calculation in one repo-local inline helper in `emit_fp_priv.h`, and use it for lookup and invalidation.

**M32-R4-12 — Follow-up kill handling contains unreachable fallback scaffolding**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/kill.c:232`
- **Evidence & Root Cause:** The fallback handles nonzero `mips_signal_pend()` results for real-time `SI_USER`. However, `src/os/sigqueue.c:126` explicitly returns success for that overflow case, making the fallback unreachable. `KILL_SI_QUEUE` at line 59 also has no use.
- **Concrete Fix:** Remove the unreachable fallback and unused macro. Keep overflow policy in `mips_signal_pend()`.

The CLEAN inspection found no source exceeding 900 lines; the largest is `src/dbt/emit_int.c` at 899. Searches found no forbidden string functions, `atoi`, or `.c` includes, and textual `x18`/`w18` matches were comments. Makefile warning flags match the requested set. These checks do not establish full C11 compliance or validate encoded register operands.

- [x] **M32-R4-1:** Update every reservation bucket affected by bulk copyout.
- [x] **M32-R4-2:** Route read/readv results through tracked copyout.
- [x] **M32-R4-3:** Preserve the low word of DBT 64-bit conversion results.
- [x] **M32-R4-4:** Preserve conversion Inexact state.
- [x] **M32-R4-5:** Replace Darwin sub-pages without retaining old file backing.
- [x] **M32-R4-6:** Validate backing continuity before mremap.
- [x] **M32-R4-7:** Make Darwin population failure paths consistent.
- [x] **M32-R4-8:** Honor `CLONE_CHILD_SETTID` independently of CLEARTID.
- [x] **M32-R4-9:** Abort shadow writeback on baseline read errors.
- [x] **M32-R4-10:** Fix mixed direct/shadow shared-mapping coherence.
- [x] **M32-R4-11:** Centralize FPR cache indexing locally.
- [x] **M32-R4-12:** Remove unreachable kill fallback and unused macro.

---

## 4. `ppc32rt` (`f083489`) — 13 Round-4 Findings (`13 / 13` Resolved)

Found **13 actionable issues** at `f083489`, including data corruption, incorrect syscall results, and a fork deadlock.

Used seven shell inspection commands. No Markdown documents, builds, tests, Docker, or QEMU were read or run. History confirms the Round-3 operand snapshot, signal synchronization, and exec-mask changes are present; the VM and fork fixes remain incomplete. Findings below are static code-path conclusions, not runtime reproductions.

**P32-R4-1 — Successful `readv` returns zero**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:198`
- **Evidence & Root Cause:** `sys_vec()` accumulates transferred bytes in `total`, then subtracts those bytes while walking destinations for SMC invalidation. Line 216 returns the depleted `total`. An ordinary successful `readv` therefore reports zero despite modifying its buffers. Earlier error returns after partial progress also bypass this invalidation pass.
- **Concrete Fix:** Preserve the transferred count separately. Invalidate each completed destination range as transfers finish, and return the preserved count on success or subsequent failure. Add regressions for successful and partially successful `readv`.

**P32-R4-2 — Growing a staging object copies the wrong file bytes**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:356`
- **Evidence & Root Cause:** When an existing group grows, `vm_file_shared_acquire()` calls `stage_fill(..., file_offset, old, need - old)` at line 500. The destination incorporates `stage_off`, but `pread()` uses only `file_off + done`. The extension receives bytes from the beginning of the mapped file range instead of `file_offset + old`.
- **Concrete Fix:** Include `stage_off` in the source offset, or explicitly pass `file_offset + old` with a clearly documented helper contract. Test two same-offset aliases with different host-rounded lengths and distinct file-page patterns.

**P32-R4-3 — Overlapping shared mappings do not share storage**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:472`
- **Evidence & Root Cause:** Staging reuse requires identical `(dev, ino, file_offset)`. Overlapping mappings starting at different offsets receive different backing objects. Host-aligned mappings bypass staging altogether through `shared_direct` in `src/rt32/ppc32_vm.c:430`. Stores therefore fail to propagate between overlapping staged aliases or between staged and direct aliases.
- **Concrete Fix:** Track shared storage by inode and covered file pages, with consistent backing for every overlapping alias. Integrate ordinary file I/O with that storage. Extend the existing identical-offset alias test to overlapping offsets and direct/staged combinations.

**P32-R4-4 — Refresh writeback overwrites newer file contents**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:479`
- **Evidence & Root Cause:** The HEAD follow-up detects changed size/mtime, then drains the entire existing staging extent before refilling it. `stage_drain_locked()` writes every byte without dirty tracking. A file write made after staging can therefore be overwritten by stale staged bytes when another alias is mapped. Host-rounded padding is included in the drain.
- **Concrete Fix:** Never resolve a detected file change by blindly writing the old snapshot back. Implement coherent file mutation handling and dirty-range ownership; exclude untouched padding. Test a file update followed by alias acquisition and verify both the file and aliases retain the update.

**P32-R4-5 — Partial unmap discards a live staging group**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:785`
- **Evidence & Root Cause:** GC recognizes a reference only when the VMA’s current `offset` exactly equals the staging group’s original offset. Front trimming changes that offset at line 362. GC then closes and forgets the group even though the remaining mapping still references its host backing. Later aliases receive another object, and subsequent stores through the survivor lose their writeback association.
- **Concrete Fix:** Store a stable backing-object identity and object-relative offset in each VMA fragment. Preserve that identity through splitting, coalescing, and remapping; reclaim only after the last reference disappears. Test front-unmap followed by alias creation and writeback.

**P32-R4-6 — Automatic placement bypasses the new shared-tail guard**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:700`
- **Evidence & Root Cause:** HEAD adds `ppc32_vm_a2_host_page_busy()` checks to fixed and hint placement, but `vm_find_free_gap_aligned_locked()` checks only guest VMAs. For a private allocation, its alignment is 4 KiB, so its scan can choose the unpublished tail of a live 16 KiB shared host page. The A2 private path then zeroes or populates bytes in that shared backing.
- **Concrete Fix:** Make every placement path account for occupied host backing extents. Apply the same rule to cursor placement and fallback gap scans. Test automatic private allocation after a fixed, one-guest-page shared mapping on A2.

**P32-R4-7 — EOF trapping misses empty files and mappings entirely beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:258`
- **Evidence & Root Cause:** `vm_file_trap_beyond_eof()` returns for an empty file and also when rounded EOF precedes `map_offset`. Both cases require trapping the entire mapping. Additionally, `vm_mmap2_locked()` invokes this helper only for shared mappings, leaving A2 private file mappings populated with accessible zeroes beyond EOF.
- **Concrete Fix:** Treat zero length as a valid EOF. Clamp the first trap offset to `max(map_offset, rounded_eof)` and mark the resulting mapped suffix. Apply EOF handling to private file mappings as well. Cover empty files, wholly beyond-EOF offsets, and partial final pages.

**P32-R4-8 — Fork and truncate acquire locks in opposite orders**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/proc.c:122`
- **Evidence & Root Cause:** Fork acquires TLB then inode locks. Conversely, `vm_file_on_truncate_fd()` holds the inode lock while `file_apply_truncate()` calls `vm32_tlb_invalidate_range()` and `vm32_mark_eof_trap()`. A fork thread holding TLB and a truncate thread holding inode can wait permanently for each other. The truncate syscall does not acquire the outer VM lock to serialize these paths.
- **Concrete Fix:** Establish one lock order across fork, truncate, and file mutation paths. Serialize mutation through the VM layer and avoid inode-to-TLB nesting that conflicts with fork. Add a bounded concurrent fork/truncate regression using the translator’s syscall paths.

**P32-R4-9 — Truncate writes through inaccessible guest mappings**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:801`
- **Evidence & Root Cause:** After host `ftruncate()` succeeds, `file_apply_truncate()` unconditionally `memset()`s the resized guest span. A read-only private mapping can fault on that write; a direct mapping beyond the newly shortened EOF can fault with SIGBUS. The inode lock remains held across this access, while host-fault recovery releases only LL/SC and VM locks.
- **Concrete Fix:** Separate direct kernel-backed mappings from staged mappings. Let the kernel handle direct mapping truncation; update staged storage through a safe backing access path. Do not perform fault-prone guest accesses while holding an unrecoverable lock. Test truncation with read-only and beyond-EOF mappings.

**P32-R4-10 — File tracking loses aliases and depends on reusable fd numbers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:105`
- **Evidence & Root Cause:** `file_register()` overwrites the existing record when the same fd creates another mapping, losing the earlier mapping’s range. Truncate matching additionally requires the original fd number at line 863, so truncating through a duplicate or reopened descriptor misses mappings of the same inode. `vm_file_hook_write()` matches only the fd number, allowing descriptor reuse to affect stale records.
- **Concrete Fix:** Track every mapping independently using stable backing identity and retained descriptor ownership. Match file mutations by inode identity rather than descriptor number. Test multiple mappings from one fd, mutation through `dup`, and close/reuse.

**P32-R4-11 — Syscall memory access bypasses guest sub-page permissions**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/os/syscalls.c:118`
- **Evidence & Root Cause:** Read/write and vectored I/O validate only numerical address bounds before passing guest pointers to host syscalls. Likewise, `ppc32_copyin/out()` in `src/os/convert.c:123` use unchecked `memcpy`. On A2, an accessible neighboring sub-page can make the host page writable while the target guest page is read-only or unmapped. These accesses then succeed despite guest permissions.
- **Concrete Fix:** Consolidate syscall access through repo-local, permission-aware copy helpers. Use stable checked buffers or suitable mapping synchronization for blocking I/O, preserving partial-transfer semantics. Cover inaccessible sub-pages sharing an accessible host page.

**P32-R4-12 — Safe copyout does not invalidate peer reservations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/ppc32_vm_regions.c:679`
- **Evidence & Root Cause:** `ppc32_vm_copyout_safe()` writes with `memcpy` without updating reservation epochs or synchronizing with `vm32_sc_attempt()`. Syscall entry invalidates only the calling context’s reservation. Another guest thread can retain a reservation across a syscall copyout that writes the same value, allowing its compare-exchange to succeed incorrectly.
- **Concrete Fix:** Route copyout through a common guest-write mechanism that serializes against SC and invalidates every affected reservation granule. Apply it to signal/thread copyouts and syscall I/O destinations. Test a peer reservation followed by same-value copyout.

**P32-R4-13 — Unused broadcast truncate API remains exposed**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/vm/vm_file.c:829`
- **Evidence & Root Cause:** Repository references to `vm_file_on_truncate()` consist only of its definition and header declaration. Its implementation applies one file size to every registered mapping regardless of file identity, while the actual syscall uses the fd-specific variant.
- **Concrete Fix:** Remove the unused broadcast function and declaration. Keep one identity-aware mutation interface.

The source scan found no files exceeding 900 lines and no matches for prohibited string functions, `atoi`, or `.c` includes. Textual `x18`/`w18` matches were comments; encoded register usage and full C11 compliance were not exhaustively verified. No separate DRY or CLEAN finding is asserted.

- [x] **P32-R4-1:** Preserve `readv` results and invalidate completed transfers.
- [x] **P32-R4-2:** Correct staging-extension source offsets.
- [x] **P32-R4-3:** Unify backing for overlapping shared aliases.
- [x] **P32-R4-4:** Prevent stale staging writeback from overwriting file updates.
- [x] **P32-R4-5:** Preserve backing identity across VMA splits.
- [x] **P32-R4-6:** Guard shared host-page tails during automatic placement.
- [x] **P32-R4-7:** Correct empty-file and beyond-EOF trapping.
- [x] **P32-R4-8:** Remove the fork/truncate lock-order inversion.
- [x] **P32-R4-9:** Make truncate updates safe for inaccessible mappings.
- [x] **P32-R4-10:** Track all aliases independently of fd numbers.
- [x] **P32-R4-11:** Enforce guest permissions for syscall memory access.
- [x] **P32-R4-12:** Invalidate peer reservations on copyout.
- [x] **P32-R4-13:** Remove the unused broadcast truncate API.

---

## 5. `sparc32rt` (`f7d73db`) — 16 Round-4 Findings (`16 / 16` Resolved)

Found **16 actionable issues** at `f7d73db`. The Round-3 and follow-up fixes are present, but thread retirement, signal routing, descriptor tracking, and VM publication still have incomplete paths.

Used **seven shell inspection commands**, including the requested history commands. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings below are static conclusions; commit-message test claims were not independently verified.

**S32-R4-1 — Clone startup storage can be freed before the parent finishes using it**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads.c:777`
- **Evidence & Root Cause:** The child signals `st->ready`, unlocks `st->lock` at lines 616–620, and immediately begins guest execution. A fast exit reaches `thr_thread_finish()`, which frees `st` at line 604. The parent can subsequently lock, read, unlock, or destroy synchronization objects in that freed allocation at lines 777–784. Signaling readiness does not transfer lifetime ownership safely.
- **Concrete Fix:** Separate the startup rendezvous from child-owned execution storage, or add an ownership handshake/reference count that keeps both the allocation and synchronization objects alive until both participants finish. Add a repeated immediate-child-exit regression.

**S32-R4-2 — Retired threads can modify the replacement executable’s memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads.c:489`
- **Evidence & Root Cause:** After roughly two seconds, retirement removes remaining siblings from `thr_live` without stopping their host calls. A sibling blocked in `sys_read()` can later return and execute `l2a_store()` into the reused guest address space (`src/os/syscalls_min.c:221`). Its eventual retirement also calls `thr_thread_finish()`, which clears the old `st->clear_tid_va` at lines 588–590. Sticky retirement marks protect subsequent instruction execution, but neither copyout nor cleanup. Clone admission is also not closed during the retirement snapshot.
- **Concrete Fix:** Serialize exec and clone admission; interrupt and acknowledge sibling shutdown before replacing the address space. Add an address-space generation check before syscall copyout and suppress old-image clear-TID writes. Do not treat deregistration as completed retirement.

**S32-R4-3 — VM writers release DBT quiescence before retiring stale translations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_mmap.c:298`
- **Evidence & Root Cause:** `mprotect`, `munmap`, and mapping replacement release `vm_lock` before calling `vm_invalidate_jit()`. `vm_lock_release()` also releases `g_dbt_lock`. A DBT thread can enter between these operations and execute code compiled from the old mapping. The epoch bump during quiescence does not solve this: `dbt_lookup_locked()` at `src/dbt/dbt.c:258` refreshes the epoch of an otherwise valid block without recompiling it.
- **Concrete Fix:** Retire affected blocks and chaining entries while DBT admission remains closed. Introduce a lock-held invalidation helper and publish the mapping/protection change and cache invalidation as one transaction.

**S32-R4-4 — Guest signal numbers are passed directly to incompatible host ABIs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_sig.c:93`
- **Evidence & Root Cause:** `sig_host_sync()` passes the SPARC signal number directly to host `sigaction()`. `threads_kill.c` similarly passes it to `kill`/`tgkill`, and `sparc32_thr_host_handler()` queues the host number unchanged. SPARC numbering differs from AArch64 Linux and Darwin—for example, the repository’s guest tests identify SIGUSR1 as 30. The special-case exclusion of signal 7 as SIGBUS also uses the wrong SPARC number. Self-generated tests can conceal this by using the same incorrect number in both installation and sending.
- **Concrete Fix:** Implement explicit SPARC↔host signal conversion at every host boundary, including delivery, installation, masks, and wait-status translation. Keep pending queues and guest frames exclusively in SPARC numbering.

**S32-R4-5 — Blocked default-action signals act immediately**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:164`
- **Evidence & Root Cause:** Guest mask updates only change `ctx->sig_mask` (`src/os/syscalls_time.c:46`). Default dispositions are mirrored as host `SIG_DFL`, and the default `tgkill` path immediately invokes the host kernel without checking the guest mask. Blocking guest SIGTERM and then sending it therefore terminates the host process instead of leaving it pending. Process-directed `kill()` has the same problem.
- **Concrete Fix:** Queue maskable default-action signals and apply their actions only when guest delivery permits. Integrate host reception with guest masks; keep genuinely unmaskable signals separate. Add blocked-default, pending-query, and unblock regressions.

**S32-R4-6 — Wakeup “echo” deduplication loses or duplicates real signals**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/interp_signal.c:547`
- **Evidence & Root Cause:** Thread delivery consumes any same-number process-pending bit as an assumed wakeup echo. Process delivery likewise discards a claimed bit whenever another thread has that signal pending. An independent process-directed signal is therefore lost when it coincides with a thread-directed signal. Conversely, the target can consume its thread bit before the sender executes the host wakeup at `threads_kill.c:187`; the later host handler creates a fresh process bit that can deliver again.
- **Concrete Fix:** Use a distinct internal wakeup mechanism that never enters guest pending queues. Maintain process-directed and thread-directed events independently; remove same-number echo inference.

**S32-R4-7 — `tgkill` accepts an unrelated thread-group ID**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:117`
- **Evidence & Root Cause:** Local lookup checks only `tid`. A found target makes the signal-zero path return success without validating `tgid`. Caught and ignored dispositions also succeed locally for an incorrect `tgid`; caught delivery queues the bit before the host wakeup, whose failure is ignored.
- **Concrete Fix:** Validate the requested thread group before local lookup or queue mutation. Preserve host errors where a host operation remains necessary. Cover wrong-group signal-zero, caught, and ignored cases.

**S32-R4-8 — Darwin thread signals use thread IDs as process IDs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/threads_kill.c:94`
- **Evidence & Root Cause:** Darwin `thr_gettid()` derives an integer from `pthread_threadid_np()`. The non-Linux `thr_host_tgkill()` fallback calls `kill((pid_t)host_tid, sig)`. A Darwin thread ID is not a process ID: this can return `ESRCH` or address an unrelated process. Caught-signal wakeup errors are then ignored.
- **Concrete Fix:** Retain a valid `pthread_t` alongside the guest-visible TID and use `pthread_kill()` for live local targets, with correct lifetime protection and signal-number translation. Never reinterpret a thread ID as a PID.

**S32-R4-9 — Successful exec incorrectly clears blocked and pending signals**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_exec.c:196`
- **Evidence & Root Cause:** Exec clears `ctx->pending_signals` and `ctx->sig_mask`; it also clears the process-pending queue at line 165. Linux exec preserves the calling thread’s blocked mask and pending signals. Resetting caught dispositions and disabling the alternate stack do not authorize clearing these states.
- **Concrete Fix:** Preserve the survivor’s mask and relevant pending queues across successful exec. Continue resetting caught dispositions and alternate-stack state. Add a guest that blocks and queues a signal, execs, and queries both states.

**S32-R4-10 — FD bookkeeping races with host descriptor reuse**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:290`
- **Evidence & Root Cause:** Host `close(fd)` happens before acquiring the tracking lock in `sparc32_fd_note_close()`. Another thread can reopen the same descriptor and record it between those operations; the old closer then erases the new descriptor’s tracking. Open, dup, and flag updates similarly separate host operations from metadata commits. Fork’s FD-table lock consequently does not guarantee a consistent host-FD/table snapshot. The exec sweep also unlocks before its actual `close()`.
- **Concrete Fix:** Serialize each descriptor lifecycle operation and its metadata update under one consistent protocol, including fork snapshots and exec sweeping. Account for translator-owned descriptor allocation and reuse in that protocol.

**S32-R4-11 — Darwin anonymous `PROT_NONE` remaps retain old contents**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:243`
- **Evidence & Root Cause:** Fixed anonymous mappings use `mprotect()` rather than replacing their backing. For `PROT_NONE`, the function returns without zeroing the requested bytes, including an immediate return for a partial host page. A guest can write a pattern, replace the range with anonymous `MAP_FIXED|PROT_NONE`, then enable reading with `mprotect()`. The new anonymous mapping exposes the previous bytes.
- **Concrete Fix:** Establish fresh zero-filled anonymous contents independently of requested permissions, preserving neighboring 4 KiB pages on 16 KiB hosts. Add a patterned-page → anonymous `PROT_NONE` remap → readable-page regression.

**S32-R4-12 — Darwin copied file mappings expose zero-filled pages beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:373`
- **Evidence & Root Cause:** The unaligned private-file mapping path zeroes the entire mapping, copies until `pread()` reaches EOF, then returns success. `vm_mmap_publish()` grants the requested protection to every page. Interpreter and syscall accessors check those protections and access the backing directly, so pages wholly beyond EOF return zeros instead of producing a guest SIGBUS.
- **Concrete Fix:** Track file-valid page extents separately from permissions and enforce them in interpreter, DBT, and syscall-access paths. Preserve zero-fill only for the valid final partial page; update validity on truncate/regrow.

**S32-R4-13 — Mapping success ignores failure to record the VMA**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_mmap.c:199`
- **Evidence & Root Cause:** `vm_mmap2_locked()` installs host backing and publishes page permissions, then discards `vm_record_region_ext_locked()`’s result and returns the address. Region-table exhaustion or insertion failure can therefore leave accessible pages absent from the authoritative VMA records. Gap selection, overlap checks, backing retention, and later remapping then operate on incomplete state. The move path repeats this unchecked recording at line 557.
- **Concrete Fix:** Reserve all required region entries and backing resources before destructive mapping operations. Propagate failures and commit host mappings, page tables, and VMA metadata together; provide rollback where preparation cannot guarantee success.

**S32-R4-14 — Descriptors above 8191 silently escape close-on-exec handling**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/threads_fd.c:45`
- **Evidence & Root Cause:** Every tracking operation silently ignores descriptors at or above `THR_FD_TRACK_MAX`, while guest descriptor allocation is not constrained to that range. A successful high-numbered `F_DUPFD` followed by `F_SETFD(FD_CLOEXEC)` remains open after emulated exec because no real host exec performs the kernel sweep.
- **Concrete Fix:** Grow the tracking structure to cover accepted descriptors, or enforce an explicit guest descriptor limit consistently. Never return successful descriptor allocation while silently omitting required lifecycle tracking.

**S32-R4-15 — Checked big-endian guest word access is duplicated across syscall units**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/threads_fd.c:180`
- **Evidence & Root Cause:** `fd_st`, `thr_st`, `sig_st_be32`, and `l2a_st_be32` independently implement the same stack-buffer → `put_be32()` → `l2a_store()` sequence. Similar checked loads exist in the signal and exec units. These copies all depend on the same permission, copyout, and invalidation behavior.
- **Concrete Fix:** Add checked BE32 load/store helpers to the existing repo-local `os/l2a_access.h` and replace equivalent copies. Keep raw loader/stack initialization helpers separate where their contracts differ.

**S32-R4-16 — The retirement survivor global is write-only**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/threads.c:78`
- **Evidence & Root Cause:** `g_exec_survivor` is initialized, reset after fork, and assigned at retirement start. No source or test reads it. Retirement decisions now use `thr_retired_contains()`, so this atomic state no longer participates in the protocol.
- **Concrete Fix:** Remove the global and its stores; update comments that imply it controls survivor selection.

The CLEAN inspection found no oversized `.c`/`.h`/`.S` files, prohibited string-call matches, `.c` includes, or production assembly references to `x18` in the searched paths. The Makefile retains the prescribed warning flags. This was not a compiler-based compliance verification, and the bounded audit does not certify the unreported ISA/FPU paths.

- [x] **S32-R4-1:** Fix clone startup-object ownership.
- [x] **S32-R4-2:** Complete sibling shutdown before exec replacement.
- [x] **S32-R4-3:** Invalidate translations before reopening DBT admission.
- [x] **S32-R4-4:** Translate signal numbers at host boundaries.
- [x] **S32-R4-5:** Honor guest masks for default-action signals.
- [x] **S32-R4-6:** Separate internal wakeups from guest signal queues.
- [x] **S32-R4-7:** Validate `tgkill` thread-group IDs.
- [x] **S32-R4-8:** Use pthread handles for Darwin thread signals.
- [x] **S32-R4-9:** Preserve masks and pending signals across exec.
- [x] **S32-R4-10:** Make FD operations and bookkeeping atomic.
- [x] **S32-R4-11:** Zero anonymous Darwin remaps regardless of initial protection.
- [x] **S32-R4-12:** Enforce EOF faults for copied file mappings.
- [x] **S32-R4-13:** Make VMA registration failures transactional.
- [x] **S32-R4-14:** Track every accepted guest descriptor.
- [x] **S32-R4-15:** Unify checked BE32 syscall access helpers locally.
- [x] **S32-R4-16:** Remove write-only retirement state.

---

## 6. `rvrt` (`b1b08af`) — 9 Round-4 Findings (`9 / 9` Resolved)

Found **nine actionable issues** at `b1b08af`. The Round-3 snapshot fields, VMA growth, and hygiene prerequisite are present, but several correctness gaps remain.

Used **seven shell inspection calls**. Read no Markdown documents and ran no builds, tests, containers, or QEMU. Findings below are static conclusions; proposed regressions were not executed. Coverage included focused traces and broader source searches, not an exhaustive concurrency audit.

**RV-R4-1 — FP stores can write canonicalized operand bits**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt_emit.c:200`
- **Evidence & Root Cause:** `emit_load_unboxed_s()` (`src/dbt_emit_fp.c:184`) replaces an improperly boxed single operand with canonical NaN in the cache while leaving the architectural register unchanged in memory. It records a valid, clean single cache entry. `emit_inline_store()` subsequently trusts that entry: FSW copies its canonicalized low bits; FSD synthesizes a boxed single from it. For example, single arithmetic reading an unboxed `f1`, followed by `fsd f1,0(a0)` in the same block, stores different bits from architectural `f1`.
- **Concrete Fix:** Distinguish cached arithmetic operands from architectural register bits. For clean single operand caches, load raw store data from CPU state; only reconstruct boxed values when the cache represents an actual single-precision register write. Add FSW/FSD regressions after reading an improperly boxed operand without modifying it.

**RV-R4-2 — Inline self-loops lose sticky FP exceptions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt_emit.c:505`
- **Evidence & Root Cause:** JAL and conditional self-loop backedges jump to `loop_top_idx` before `emit_term_pc()` flushes FPSR. That label precedes the block’s first FP operation (`src/darwin_dbt.c:274`). Its emitted `emit_clear_fpsr()` instruction therefore clears FPSR again on every iteration. Exceptions raised only in earlier iterations disappear. Difftest mode sets the loop budget to one, avoiding this backedge and masking the failure.
- **Concrete Fix:** Flush accumulated FPSR into guest `fcsr` before each taken inline backedge, or disable FP self-loop optimization until entry and backedge flag handling are correct. Test an ordinary DBT loop whose first iteration raises an exception and whose final iteration does not.

**RV-R4-3 — Subpage protection removes neighboring mappings’ permissions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:400`
- **Evidence & Root Cause:** `protect_enclosing()` applies one mapping’s protection to its entire enclosing host page. On a 16 KiB host, map a 4 KiB RW subpage, then map its adjacent 4 KiB subpage read-only. The second operation makes both host subpages read-only. `rv_vm64_copyin()` accepts the first VMA as writable and reaches `memcpy()` at line 686, which faults. File mapping at line 554 and protection restoration at line 131 have the same neighbor-permission problem. The new regression exercises RO→RW replacement, not mixed surviving permissions.
- **Concrete Fix:** Compute host protection from all guest subpages sharing each host page, enforcing finer restrictions in software. Alternatively keep anonymous large-page arena backing RW and enforce guest permissions entirely through checked access paths. Add mixed RW/RO/PROT_NONE neighbor tests in both mapping orders.

**RV-R4-4 — Failed file replacement destroys existing VMA metadata**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:513`
- **Evidence & Root Cause:** `vma_remove_overlap()` runs before the fallible `rt_host_map_file()` or pread-based replacement. A closed positive FD passes the initial check; `file_valid_bytes()` suppresses its `fstat()` failure; mapping then fails after the original VMA has been removed. Original page states remain, but protection and inode associations are lost. On large-page hosts, the implementation additionally zeroes old contents before a possible pread failure.
- **Concrete Fix:** Stage and validate replacement backing before committing VMA removal and page states. Preserve the previous mapping on recoverable failures, including descriptor errors and interrupted/failed reads. Add failure-injection checks for preserved bytes, permissions, states, and inode associations.

**RV-R4-5 — New nonzero-offset regression fails on 4 KiB hosts**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `test/u5a_vm_provider.c:476`
- **Evidence & Root Cause:** The test requests page-aligned GVA `868352` with file offset `8000`. On the 4 KiB path, `head = 3904` and `map_gva = 864448` (`src/vm/vm64.c:505`), which is not page-aligned. The backend passes that address to `MAP_FIXED`, so the operation fails rather than satisfying the test’s required success. The pread path accepts the same input, creating backend divergence.
- **Concrete Fix:** Define and enforce a consistent alignment contract before any mutation. If arbitrary file offsets remain supported, use staged copying when GVA and file-offset alignment are incompatible. Otherwise reject them consistently and change this regression to a valid aligned nonzero offset, with a separate rejection test.

**RV-R4-6 — Failed protection widening still reaches `memset()`**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:126`
- **Evidence & Root Cause:** `zero_guest_range()` attempts to make read-only backing writable, but a failed `protect_enclosing()` merely leaves `widened == 0`. It then unconditionally writes through the original protection at line 129. The helper returns `void`, so truncate/regrow callers cannot propagate the failure and may continue publishing new page states.
- **Concrete Fix:** Return a status from the zeroing helper and stop before touching memory when widening fails. Propagate failure through the discard operation and avoid publishing successful state transitions for failed work. Add a protection-failure regression.

**RV-R4-7 — Generic signed-byte emission uses an unsigned load**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/emit_mem.c:65`
- **Evidence & Root Cause:** Width-one loads always select `RV_DBT_W_LDRB_BASE`, ignoring `is_signed`. Thus signed byte `0x80` becomes `0x80`, not `0xffffffffffffff80`. The big-endian width-one branch repeats the error. `test/u5b_dbt_mem.c:215` explicitly expects the incorrect unsigned opcode for a signed request. This emitter is separate from the Darwin inline-load implementation.
- **Concrete Fix:** Select the existing `RV_DBT_W_LDRSB_BASE` for signed byte loads in both branches. Correct the test expectation and add semantic checks for `0x7f`, `0x80`, and `0xff`.

**RV-R4-8 — Generic 16-byte accesses transfer only eight bytes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/dbt/emit_mem.c:71`
- **Evidence & Root Cause:** The public emitter accepts width 16 and records that width in site metadata, but emits one `LDR X` or `STR X`. Big-endian cases likewise transfer and reverse only eight bytes. `test_emit_shapes()` includes width 16 but checks emitted shape rather than a complete 16-byte transfer. Inspected call sites are tests, so this is a latent emitter-contract defect rather than evidence of current RV64GC execution corruption.
- **Concrete Fix:** Reject width 16 until the API can describe a register pair or vector operand and emit the complete transfer. Update acceptance tests accordingly; implement full-width access only when an actual consumer requires it.

**RV-R4-9 — Slow-path cache reload sequences are duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/darwin_dbt_emit.c:172`
- **Evidence & Root Cause:** Inline load and store slow paths separately emit the same GPR reload loop, FPR reload loop, precision selection, and TLB-tag poisoning sequence; the second copy starts at line 244. These sequences encode shared register-cache invariants that must change together.
- **Concrete Fix:** Extract one repo-local emitter helper for restoring live register caches after a helper call and invalidating the retained TLB tag. Keep load-specific snapshot restoration at its call site.

The inspected source trees had no files exceeding 900 lines, prohibited string-function calls, or textual `.c` includes. The `x18` search found comments and a RISC-V guest fixture, not an AArch64 violation. No sufficiently supported standalone YAGNI or CLEAN finding emerged.

- [x] **RV-R4-1:** Preserve architectural FP bits in FSW/FSD after operand unboxing.
- [x] **RV-R4-2:** Preserve sticky FP flags across inline self-loop backedges.
- [x] **RV-R4-3:** Preserve neighboring subpage permissions on large-page hosts.
- [x] **RV-R4-4:** Make failed file replacement preserve existing mapping state.
- [x] **RV-R4-5:** Resolve nonzero-offset alignment divergence and its regression.
- [x] **RV-R4-6:** Propagate zeroing protection failures before writing.
- [x] **RV-R4-7:** Emit sign-extending signed-byte loads.
- [x] **RV-R4-8:** Reject or fully implement 16-byte memory emission.
- [x] **RV-R4-9:** Unify slow-path register-cache reload emission.

---

## 7. `loongarch64rt` (`1907d96`) — 18 Round-4 Findings (`18 / 18` Resolved)

Found **18 actionable issues** at HEAD `1907d96`. The Round-3 and post-fable changes are present, but several fixes remain incomplete.

Used seven shell inspection invocations. Read no Markdown documents; ran no project builds, tests, containers, or QEMU. `git status --short` was clean. `include/` and `tools/` are absent. The source line-count scan found no `.c`, `.h`, or `.S` files over 900 lines. Findings below are static conclusions, not runtime reproductions.

**LA64-R4-1 — Masked FCSR writes corrupt unrelated fields**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_mem.c:43`
- **Evidence & Root Cause:** For field 1, the emitter clears the old enable bits in `x11`, then overwrites all of `x11` with `x10 & 31`; rounding, cause, and sticky fields disappear. For field 2, lines 47–50 extract the two exception fields and recombine them in reversed positions. The interpreter correctly performs `(old & ~mask) | (input & mask)` at `src/interp/fp.c:658`.
- **Concrete Fix:** Emit that masked merge directly for each selector. Add interpreter/DBT comparisons with distinct cause/sticky patterns and nonzero rounding bits.

**LA64-R4-2 — FP-to-integer checks precede rounding and permit undefined casts**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp.c:224`
- **Evidence & Root Cause:** `fp_ftint_wd()` accepts `2147483647.75`, then nearest rounding produces `2147483648.0`; casting that to `int32_t` is undefined. The lower-bound literals in `fp_ftint_w()`, `fp_ftint_l()`, and `fp_ftint_ld()` also round to the minimum representable integer, so their strict comparison incorrectly rejects that valid endpoint.
- **Concrete Fix:** Handle NaNs explicitly, round first, validate the rounded value using exactly representable bounds, then cast. Preserve the required invalid/inexact flags. Cover both endpoints and fractional overflow under every rounding mode.

**LA64-R4-3 — Staged `MAP_SHARED` mappings are independent private copies**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:332`
- **Evidence & Root Cause:** The fallback populates private arena storage with `pread`. Stores become visible to aliases only through explicit `staged_propagate()`, and that scans only process-local records. Two aliases therefore disagree immediately after a store; forked processes retain separate copies. `vmfile_write_hook()` updates metadata without refreshing staged bytes, so later whole-range writeback can overwrite newer file contents.
- **Concrete Fix:** Give mappings of the same inode/file page genuinely shared backing, including across fork, or implement coherent mediated accesses with dirty tracking. Explicit `msync` copying alone cannot provide `MAP_SHARED` semantics.

**LA64-R4-4 — Middle unmap silently loses the surviving tail record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:523`
- **Evidence & Root Cause:** Unmapping the middle page of a three-page mapping takes the `else` branch and shortens the existing record to the head. No tail record is created, although the tail remains mapped. Subsequent sync, truncate, protection bookkeeping, and inode reclamation no longer account for it.
- **Concrete Fix:** Reserve a second record before mutation, split head and tail, adjust the tail’s GVA/HVA/file offset, and acquire its inode reference. Handle record exhaustion before changing mappings.

**LA64-R4-5 — Protection changes suppress dirty writeback for unrelated pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:356`
- **Evidence & Root Cause:** `vmfile_note_protect()` assigns the new protection to every overlapping *whole record*. Protecting one page read-only therefore marks writable siblings read-only in this table. `staged_writeback()` then skips the entire record at line 410. Even a full-range writable-to-read-only transition can leave dirty bytes that still require writeback.
- **Concrete Fix:** Split records at protection boundaries and update them only after successful protection changes. Track dirt independently of current permissions; removing write permission must not discard pending modifications.

**LA64-R4-6 — Truncate discard compares file offsets with guest addresses**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:684`
- **Evidence & Root Cause:** `cut` is an aligned file size, but `start = max(maps[i].gva, cut)` treats it as a guest address and ignores `file_off`. For a private mapping at GVA `0x40000`, file offset zero, shrinking to 4096 selects the entire mapping, discarding dirty bytes in the first page even though that page survives.
- **Concrete Fix:** Intersect the removed file-offset interval with each mapping’s file interval, then translate that intersection back to GVA/HVA. Preserve surviving private pages and partial EOF pages.

**LA64-R4-7 — Child reference acquisition races with parent reclamation**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:78`
- **Evidence & Root Cause:** Inherited references are acquired only when the child reaches `vmfile_fork_child_reset()`. The parent can return from `fork`, unmap its final record, and clear or reuse the shared row first. The child then either skips its missing row or increments a replacement row. The new test waits for the child before the parent unmaps, excluding this ordering.
- **Concrete Fix:** Reserve inherited references before `fork` under family-table synchronization, roll them back on failure, and transfer ownership to the child without a second increment. Add a parent-first-unmap regression.

**LA64-R4-8 — Shared inode rows contain process-local descriptor numbers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:152`
- **Evidence & Root Cause:** `itable` is shared across processes, but `dupfd` belongs to the registering process’s descriptor table. A row created after fork is visible to peers that do not possess that descriptor. Their writeback or reclamation can use or close an unrelated descriptor with the same number. Atomic reference counting does not fix descriptor ownership.
- **Concrete Fix:** Keep retained descriptors in process-local inode-handle tables. Share only stable identity and synchronization metadata; explicitly transfer descriptors when a peer needs access.

**LA64-R4-9 — `MS_INVALIDATE` discards dirty staged data**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:596`
- **Evidence & Root Cause:** Any flags containing bit 2 take the `pread` branch instead of writeback. Thus `MS_SYNC | MS_INVALIDATE` overwrites dirty staged bytes with old file contents and propagates those old bytes to aliases.
- **Concrete Fix:** Validate flags before mutation. Complete required dirty writeback before invalidation, and refresh only where coherence rules permit. Test combined flags on a forced staged mapping.

**LA64-R4-10 — Guest `msync` bypasses Darwin flag and page-size translation**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls.c:509`
- **Evidence & Root Cause:** After `vmfile_msync()`, the handler calls libc `msync()` directly with Linux flags. The Darwin translation already exists in `rt_host_msync()`. It also submits the guest-address-derived pointer directly: a valid 4 KiB guest boundary need not be a valid 16 KiB host boundary. Writeback can complete before the syscall reports a host validation error.
- **Concrete Fix:** Validate guest arguments first and dispatch by backing type. Staged anonymous storage should complete through its file-writeback path; direct overlays should use translated flags and valid host spans.

**LA64-R4-11 — File installation and removal occur outside VM quiescence**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:245`
- **Evidence & Root Cause:** `vm64_map()` commits and resumes peers before `map_bytes_in_place()` performs `pread` and publishes its record. The direct-overlay path likewise installs the host overlay after `vm64_map()` returns. Conversely, `sys_munmap_range()` calls `vmfile_unmap()`—including backing repair—before `vm64_unmap()` obtains quiescence. Peers can access partially installed or replaced bytes through still-valid translations.
- **Concrete Fix:** Make backing changes, population, record changes, page-state publication, and TLB/LL invalidation one transaction. Add internal mapping primitives that operate under an already-held mutation gate.

**LA64-R4-12 — `SA_RESETHAND` redirects execution to address zero**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:243`
- **Evidence & Root Cause:** `act` points into `sf_actions`. Delivery sets `sf_actions[sig].handler = LA64_SIG_DFL`, then line 251 reads `act->handler` into `ctx->pc`. The first delivery therefore uses the reset disposition instead of the registered handler.
- **Concrete Fix:** Snapshot the action before modifying the shared disposition. Redirect using the saved handler and reset only the installed action.

**LA64-R4-13 — Signal delivery loses pending events and uses unsafe async updates**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:240`
- **Evidence & Root Cause:** Polling removes one selected pending source, but `sf_deliver_locked()` subsequently clears the signal from both thread and process queues. If both contain that signal, one event disappears. Separately, `la64_host_signal_note()` performs ordinary read-modify-write operations on `sf_proc_pending` while polling clears it; these are neither atomic nor protected from asynchronous interruption.
- **Concrete Fix:** Remove only the selected queue entry. Use an async-signal-safe publication mechanism and synchronized consumption, including metadata ordering. Test simultaneous process/thread pending signals and arrivals during polling.

**LA64-R4-14 — Failed clone leaves signal records referring to freed contexts**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/os/clone.c:588`
- **Evidence & Root Cause:** `la64_signal_clone_inherit()` allocates child signal state before parent-TID copyout, child-TID validation, and `pthread_create`. Failure paths at lines 588, 602, and 613 free the child without calling `la64_signal_thread_exit()`. The fixed signal table retains stale entries and can exhaust capacity across failures using distinct allocations.
- **Concrete Fix:** Add signal-state cleanup to every post-inheritance failure path, preferably through one cleanup helper, or defer publication until clone setup can commit.

**LA64-R4-15 — New regression fixture reads past its stack buffer**

- **Severity:** Medium
- **Category:** CLEAN
- **Location:** `tests/test_u0_soft_tlb.c:796`
- **Evidence & Root Cause:** `probe` has 16 bytes, but `write(fd, probe, 100)` requests 100 bytes. The test reads beyond the object and writes unrelated stack contents into its fixture. It violates the no-undefined-behavior requirement and can trigger compiler diagnostics.
- **Concrete Fix:** Use an initialized 100-byte fixture buffer, or create the required file size separately and write only `sizeof probe`.

**LA64-R4-16 — Target backend selection is disconnected from test recipes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:65`
- **Evidence & Root Cause:** `U0_TEST_SRCS` and `RC_TEST_SRCS` hard-code Linux backend files and `safe_syscall_a64.S`. Although lines 108–113 compute `U0_TARGET_BACKEND`, neither source list uses it. Native Darwin checks consequently do not exercise the selected Darwin backend.
- **Concrete Fix:** Build both source lists from common sources plus the target-selected backend. Account for Make’s immediate `:=` expansion by defining the selector first or using deferred expansion.

**LA64-R4-17 — FP memory instruction classification is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/dbt/dbt_mem.c:161`
- **Evidence & Root Cause:** `mem_miss_fp()` and `la64_emit_fp_mem()` at `src/dbt/emit_fp_mem.c:386` independently encode the same opcode acceptance, width, store/load, and indexed-mode decisions. A change to one can make generated accesses disagree with their retry decoder.
- **Concrete Fix:** Introduce one repo-local DBT classification helper returning those fields. Keep the independent interpreter/oracle validation separate.

**LA64-R4-18 — Obsolete Linux source-list variable remains unused**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `Makefile:63`
- **Evidence & Root Cause:** `U0_LINUX_SRCS` has no consumers. `U0_LINUX_BACKEND` separately lists the same C files plus assembly, leaving two apparent definitions of the Linux backend source set.
- **Concrete Fix:** Delete the unused variable and retain one authoritative backend source list.

- [x] **LA64-R4-1:** Correct masked FCSR emission.
- [x] **LA64-R4-2:** Validate rounded FP conversion results before casting.
- [x] **LA64-R4-3:** Provide coherent shared-file backing.
- [x] **LA64-R4-4:** Preserve both survivors of middle unmaps.
- [x] **LA64-R4-5:** Separate protection boundaries from dirty tracking.
- [x] **LA64-R4-6:** Translate truncate offsets into mapping coordinates.
- [x] **LA64-R4-7:** Reserve inherited references before fork.
- [x] **LA64-R4-8:** Keep retained descriptors process-local.
- [x] **LA64-R4-9:** Preserve dirty data during invalidation.
- [x] **LA64-R4-10:** Correct guest-to-host `msync` handling.
- [x] **LA64-R4-11:** Keep complete backing mutations under quiescence.
- [x] **LA64-R4-12:** Snapshot handlers before `SA_RESETHAND`.
- [x] **LA64-R4-13:** Fix pending-source consumption and async publication.
- [x] **LA64-R4-14:** Clean up signal state after failed clone.
- [x] **LA64-R4-15:** Fix the fixture’s out-of-bounds write source.
- [x] **LA64-R4-16:** Wire target backend selection into tests.
- [x] **LA64-R4-17:** Unify DBT FP-memory classification.
- [x] **LA64-R4-18:** Remove the unused Linux source-list variable.

---

## 8. `ppc64rt` (`56bec31`) — 8 Round-4 Findings (`8 / 8` Resolved)

Found **8 actionable issues** at `56bec31`. The Round-3 and follow-up commits are present; the `munmap` preflight now precedes table mutation, but exec inheritance and remap error handling still have gaps.

Used seven shell inspection calls. No Markdown documents, builds, tests, containers, or QEMU were read or run. Findings are static, not runtime-confirmed. `include/` and `tools/` are absent.

**P64-R4-1 — Single-precision arithmetic rounds operands prematurely**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp.c:202`
- **Evidence & Root Cause:** PO59 arithmetic reaches `fp_arith_exec()`, which casts both FPR operands to `float` before calculating. This discards input precision before the instruction’s result rounding. For `fadds` with operands `1 + 2^-24` and `-1`, nearest-even input conversion makes the first operand `1`, producing zero instead of the representable result `2^-24`. Operand conversions also contaminate the collected exception flags.
- **Concrete Fix:** Implement the instruction’s operand precision and final binary32 rounding explicitly. Avoid premature operand conversion and account for double-rounding cases. Add oracle regressions for cancellation, rounding boundaries, and FPSCR flags.

**P64-R4-2 — Integer conversions omit FPSCR updates**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:424`
- **Evidence & Root Cause:** The `fctiwz` and `fctidz` branches select integer results for fractional, NaN, and out-of-range inputs but never record conversion exceptions. Their record forms then copy the unchanged FPSCR summary into CR1. For example, converting a NaN leaves `VXCVI` unset; fractional conversion leaves inexact state unchanged.
- **Concrete Fix:** Implement conversion-specific invalid and inexact handling, including applicable signaling-NaN flags and FPSCR summary updates, before updating CR1. Test fractional, boundary, infinity, and NaN inputs.

**P64-R4-3 — Growing file mappings silently accepts refill failures**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file_mremap.c:101`
- **Evidence & Root Cause:** `vm_file_fill_tail()` retries interrupted `pread()` calls but ignores other read errors, accepts short reads without completing them, and discards `ppc64_vm_write_raw()` failure. It still returns success after marking the page CLEAN or SHARED. Because `syscall_mm_mremap()` initially stages a zero-filled extension, a failed refill can produce a successful remap exposing zeros instead of file bytes.
- **Concrete Fix:** Complete reads until the requested span or actual EOF, propagate read and raw-write failures, and let the existing remap rollback restore state. Handle unavailable backing descriptors explicitly. Add injected read/write-failure regressions.

**P64-R4-4 — Worker exec inherits the wrong pending-signal set**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:120`
- **Evidence & Root Cause:** `run_sig_exec_snapshot()` obtains the current task’s mask through `ppc64_syscall_sigmask_get()`, but copies pending signals directly from `run_sig_pending`, the main-task storage. Worker pending signals live in `s_cur_task->sig_pending`, selected by `syscall_p4_sigpending_ptr()` at `src/os/syscalls_p4.c:115`. A worker exec therefore loses its own pending signals and can inherit another task’s pending signals.
- **Concrete Fix:** Snapshot the executing task’s pending set through the task-aware accessor. If process-directed pending signals are represented separately, combine only those with the caller’s thread-directed set. Test exec from a worker with distinct blocked pending signals on worker and main task.

**P64-R4-5 — Exec converts default dispositions into explicit ignore**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:112`
- **Evidence & Root Cause:** The snapshot uses `run_sig_is_ignored()`, which includes default dispositions for signals 17, 18, 23, and 28. Restore installs every resulting bit as `handler = 1`, meaning explicit `SIG_IGN`. Consequently, a default disposition becomes observably different after exec when queried through `rt_sigaction`.
- **Concrete Fix:** Serialize only explicitly installed `SIG_IGN` dispositions (`handler == 1`). Leave default dispositions default. Test disposition queries before and after exec, covering both `SIG_DFL` and explicit `SIG_IGN`.

**P64-R4-6 — Internal exec variables reach the guest before removal**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/core.c:551`
- **Evidence & Root Cause:** `run_build()` constructs the guest stack before invoking `run_sig_exec_restore()` at line 576. `run_build_stack()` copies host `environ` into guest memory at `src/run/load.c:479`. The later `unsetenv()` calls remove only host entries; the guest already holds copies of `PPC64RT_EXEC_SIGMASK`, `PPC64RT_EXEC_SIGIGN`, and `PPC64RT_EXEC_SIGPEND`.
- **Concrete Fix:** Capture and remove the handoff variables before building the guest environment, then apply the captured state after signal initialization. Test that inheritance works while the guest environment contains none of these internal entries.

**P64-R4-7 — Expanded exec environment exceeds cleanup’s bound**

- **Severity:** Low
- **Category:** DEFECT
- **Location:** `src/os/proc.c:443`
- **Evidence & Root Cause:** `proc_envp_inject_sig()` can grow a valid 256-entry environment to 259 entries. After host exec fails, `proc_free_strvec()` frees only indices `0..PROC_MAX_ARGS` inclusive, then frees the vector. Entries 257 and 258 leak on this path. Repeated failed exec calls repeat the leak.
- **Concrete Fix:** Carry the owned element count with each vector, or free validated host-owned vectors through their guaranteed NULL terminator. Make cleanup independent of the guest-input cap. Add a failed-exec regression with a maximum-length environment.

**P64-R4-8 — File staging duplicates logic and error policy**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/syscalls_mm_map.c:42`
- **Evidence & Root Cause:** `mm_stage_file()` and `ppc64_vm_file_fill()` at `src/vm/vm_file.c:767` independently implement allocation, bounded `pread`, EINTR retry, offset checks, short-read termination, and zero-filling. Their error handling already differs: the former preserves `EBADF`, while the latter converts every read error to `EIO`. The new remap-tail reader introduces a third, less complete variant.
- **Concrete Fix:** Introduce one repository-local staged file-read helper with explicit short-read, EOF, offset, and error semantics. Reuse it in mapping and remap population while retaining their separate publication and rollback responsibilities.

The CLEAN scan found no source files above 900 lines—the largest was 890—and no prohibited string-function calls or `.c` includes in the searched trees. Literal `x18` matches were comments; that scan does not establish correctness of encoded JIT register operands. No sufficiently supported YAGNI finding emerged from this bounded inspection.

- [x] **P64-R4-1:** Correct single-precision operand and result rounding.
- [x] **P64-R4-2:** Record integer-conversion FPSCR exceptions.
- [x] **P64-R4-3:** Propagate file-remap refill failures.
- [x] **P64-R4-4:** Preserve the executing task’s pending signals.
- [x] **P64-R4-5:** Preserve the distinction between default and ignored dispositions.
- [x] **P64-R4-6:** Remove internal handoff variables before guest-stack construction.
- [x] **P64-R4-7:** Free every injected environment entry after failed exec.
- [x] **P64-R4-8:** Unify staged file reads in a repository-local helper.

---

## 9. `mips64rt` (`f7c6924`) — 10 Round-4 Findings (`10 / 10` Resolved)

Found **10 actionable issues** at `f7c6924`. The Round-3 staged-copyout changes, single-call vectored I/O, and post-fable CAS changes are present, but edge cases remain.

Used exactly **seven shell inspection commands**, including the requested `git log -n 5 --oneline`, `git show HEAD~1 --stat`, and `git show HEAD`. No Markdown documents, builds, tests, Docker, or QEMU were run. Findings below are static conclusions, not runtime reproductions.

**M64-R4-1 — File writes can leave stale translated code**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:530`
- **Evidence & Root Cause:** `vm_inode_apply_write_locked()` passes file offsets `off` and `wend` to `vm_inode_invalidate_maps()` at line 582. That function compares them against guest virtual addresses `maps[i].va`. For a file mapped at guest `0x100000`, a write to file offset zero fails the overlap check. Fallback bytes can be refreshed while the corresponding DBT translation survives; native mappings also miss invalidation.
- **Concrete Fix:** Intersect the write interval with each mapping’s `[file_offset, file_offset + len)` interval, translate that intersection into guest VA, and invalidate it. Add coverage for executable aliases at different VAs and nonzero file offsets.

**M64-R4-2 — Shared fallback stores past EOF extend the backing file**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:654`
- **Evidence & Root Cause:** `mips_vm_file_shared_sync()` clips stores to the mapping but not to `in->size`. It issues `pwrite()` for the entire intersection. On a fallback shared mapping of a one-byte file, a guest store at offset two extends the file to three bytes. The zero-filled tail of the final mapped page must not become file content merely through a mapped store. The function also ignores short writes and errors before marking the range clean and refreshing aliases.
- **Concrete Fix:** Limit backing-file writes to bytes below EOF. Preserve final-page tail bytes without extending the file. Handle short writes and failures before publishing clean/coherent state. Cover partial-page EOF and failed writeback.

**M64-R4-3 — File refresh helpers violate the 16 KiB host-page strategy**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:377`
- **Evidence & Root Cause:** `mips_vm_inode_refresh_span()` derives host writability from guest permissions and calls `mprotect(p, 4096, ...)` on a guest-page address. `mips_vm_inode_zero_span()` does the same at line 349. On a 16 KiB host, a guest page at host-page offset `0x1000` is not a valid protection boundary: these helpers return without refreshing or zeroing it. On an aligned first subpage, restoring guest permissions can instead alter protection for neighboring subpages, defeating the RW host cover. Callers subsequently advance reconciliation sequence numbers.
- **Concrete Fix:** Make both helpers obey the existing large-host-page cover policy. Keep guest subpage permissions in software; use host-aligned protection changes only where required and propagate failures. Cover refresh and truncation on all four subpages, including mixed guest permissions.

**M64-R4-4 — File-tracking exhaustion silently loses backing metadata**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/vm/vm_file.c:371`
- **Evidence & Root Cause:** `vm_inode_split_at()` silently skips splitting when the 128-entry map table is full. Its `fcntl()` duplication can also fail, yet the new record is committed with `fd_dup == -1`. The middle-unmap path at lines 473–484 discards the right-hand record when full and only sets `wide`. That flag broadens DBT invalidation; it cannot restore missing EOF, coherence, or remap metadata. Mapping registration similarly returns silently when inode allocation fails.
- **Concrete Fix:** Reserve metadata capacity and duplicate descriptors before committing VM changes. Return failures through the map/split/remap interfaces and preserve existing records on failure. Reclaim empty inode slots or grow the repo-local tables. Add capacity and descriptor-exhaustion cases.

**M64-R4-5 — Round-3 absorbed-operand correction is asymmetric**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:678`
- **Evidence & Root Cause:** The correction detects only `qd == a`, where the second operand disappears. With `a = 2^-126`, `b = 1.0f`, and ADD.S, binary64 `qd` equals `b`; the condition fails. Consequently `q == r == 1`, Inexact is omitted, and rounding toward positive infinity incorrectly returns `0x3f800000` instead of `0x3f800001`. The new regression table always puts the larger finite operand first.
- **Concrete Fix:** Detect absorption of either effective operand, preserving the smaller operand’s residual sign after subtraction. Extend tests to both operand orders, both signs, ADD/SUB, and all four rounding modes.

**M64-R4-6 — Paired-single arithmetic ignores guest rounding mode**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp_ps.c:103`
- **Evidence & Root Cause:** `fp_ps_lane()` receives neither FCSR nor a rounding mode. ADD.PS, SUB.PS, and MUL.PS return the host-rounded result directly. For example, `1.0f + 2^-24` under guest rounding toward positive infinity must select the next float, but this path returns the host nearest-even result. Its direct `long double` reference also retains the absorbed-operand problem fixed separately for scalar operations.
- **Concrete Fix:** Share a repo-local single-precision arithmetic implementation that accepts the guest rounding mode and returns result bits plus exceptions. Use it for scalar and paired lanes, preserving whole-destination trap suppression. Test each lane under every mode.

**M64-R4-7 — Quiet comparisons fail to raise Invalid for signaling NaNs**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:791`
- **Evidence & Root Cause:** Comparison handling raises Invalid only when the predicate’s signaling bit, `cond & 8`, is set. It never calls `fp_issn_s()` or `fp_issn_d()`. Thus a quiet predicate such as C.EQ.S with a legacy signaling-NaN operand produces an unordered result without Invalid or an enabled exception trap. The DBT explicitly falls back to this interpreter path for unordered operands.
- **Concrete Fix:** Raise Invalid when either operand is signaling NaN, or when a signaling predicate receives any NaN. Preserve FCC on an enabled trap. Cover quiet/signaling predicates against both NaN classes in S and D formats.

**M64-R4-8 — `sigaltstack` returns a mixture of old and new state**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigact.c:429`
- **Evidence & Root Cause:** `reported` is computed from the original stack at lines 385–388. The function then overwrites `ctx->sigalt_sp` and `ctx->sigalt_size`, and serializes those updated fields into `oss`. Calling `sigaltstack(&new_stack, &old_stack)` therefore returns the new address and size with the old status flags. Disabling an installed stack similarly loses its previous address and size.
- **Concrete Fix:** Snapshot the complete old stack before processing `ss`, and serialize that snapshot into `oss`. Cover replacement, disabling, and aliased input/output buffers for N64 and N32.

**M64-R4-9 — Two syscall copyout implementations duplicate the commit protocol**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/os/syscalls_sync.c:206`
- **Evidence & Root Cause:** `l2a_commit_guest_write()` duplicates the lock, copy, reservation invalidation, COW clearing, code retirement, and shared-file synchronization sequence in `mips_sc_copyout()` (`src/os/syscalls.c:156`). They already differ in range validation and explicit `ctx->llbit` clearing. Future corrections must reach both paths.
- **Concrete Fix:** Route scalar/vector commits through `mips_sc_copyout()`, retaining partial-byte accounting in `l2a_vec_copyout()`. Alternatively, factor one internal commit primitive with explicit validation requirements. Keep the helper repository-local.

**M64-R4-10 — Superseded signal-mask and deferred-copyout scaffolding remains**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/syscalls_sync.c:120`
- **Evidence & Root Cause:** `l2a_sigmask` and `mips_sc_rt_sigprocmask()` remain despite dispatch selecting `mips_l4a_rt_sigprocmask()` at `src/os/syscall_min.c:700`; repository references show no caller of the old implementation. Separately, all remaining `guest_range()` calls use read mode, leaving its write branch, `g_sync_*` queue, and dispatcher flush obsolete after HEAD’s copyout migration.
- **Concrete Fix:** Remove the unused signal-mask implementation and declaration. Remove the deferred write queue and flush call; make `guest_range()` explicitly read-only and update its declarations.

The CLEAN inspection found no over-900-line `.c`, `.h`, or `.S` files, prohibited string functions, source-file includes, or literal `x18` assembly use. `Makefile:22` contains the required warning flags. This is not compiler validation or a complete audit of generated register encodings. The requested `include/` and `tools/` directories do not exist at this HEAD.

- [x] **M64-R4-1:** Translate file offsets to guest addresses before DBT invalidation.
- [x] **M64-R4-2:** Bound shared writeback by EOF and handle write failures.
- [x] **M64-R4-3:** Make refresh/zero helpers respect 16 KiB host-page coverage.
- [x] **M64-R4-4:** Preserve backing metadata on capacity or descriptor exhaustion.
- [x] **M64-R4-5:** Correct absorbed operands in both operand orders.
- [x] **M64-R4-6:** Honor FCSR rounding in paired-single arithmetic.
- [x] **M64-R4-7:** Raise Invalid for signaling NaNs in quiet comparisons.
- [x] **M64-R4-8:** Return a complete old alternate-stack snapshot.
- [x] **M64-R4-9:** Unify syscall copyout commit logic.
- [x] **M64-R4-10:** Remove superseded mask and deferred-copyout scaffolding.

---

## 10. `sparc64rt` (`5232650`) — 11 Round-4 Findings (`11 / 11` Resolved)

Found **11 actionable issues** at HEAD `5232650`. The Round-3 fixes improve registry growth, worker registration, and cache invalidation, but leave important failure paths incomplete.

Used **seven shell inspection commands**, including `git log -n 5 --oneline`, `git show HEAD~1 --stat`, and `git show HEAD`. No Markdown files, builds, tests, Docker, or QEMU were read or run. `tools/` does not exist in this checkout. Findings below are static traces, not runtime reproductions.

**S64-R4-1 — Negative 32-bit integer-to-float conversions use the wrong magnitude**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp_conv.c:191`
- **Evidence & Root Cause:** `cv_itos()` computes negative magnitude as `UINT64_C(0) - (uint64_t)(uint32_t)v`. For `v == -1`, this produces `0xffffffff00000001`, not `1`. Both FITOS and FITOD then convert that enormous magnitude with a negative sign. The DBT uses signed AArch64 conversion instructions, so this also creates interpreter/DBT divergence.
- **Concrete Fix:** Sign-extend before unsigned negation: `UINT64_C(0) - (uint64_t)(int64_t)v`, or negate after widening to `int64_t`. Add FITOS/FITOD vectors for `-1`, `INT32_MIN`, and negative values around single-precision rounding boundaries.

**S64-R4-2 — Directed rounding increments exactly representable integers**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/interp/fp_conv.c:168`
- **Evidence & Root Cause:** `cv_int_bits()` sets `up = neg == 0U` for upward rounding and `up = neg != 0U` for downward rounding, regardless of discarded bits. Thus converting positive integer `1` under upward rounding returns the next representable float above `1`, while reporting NX clear. The helper serves FITOS, FITOD, FXTOS, and FXTOD.
- **Concrete Fix:** Require inexactness for directed increments: `up = (*nx != 0U) && …`. Test exact positive and negative integers under all four rounding modes, checking result bits and FSR flags.

**S64-R4-3 — Failed relocated mremap leaves the source moved and skips the shared code epoch**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem.c:697`
- **Evidence & Root Cause:** The substrate publishes the relocation before `sysmem_file_fill_growth()`. On `-12`, cleanup removes only the growth tail; the original bytes remain at `dest`, and the source has already disappeared. The syscall returns `-ENOMEM`, leaving callers with an invalid original pointer. For FIXED relocation, replaced destination mappings are also lost. `vm64_stxn_abort()` only clears transaction state; unlike commit, it does not bump `vm64_code_epoch`, so sleeping threads can retain translations for mappings that changed.
- **Concrete Fix:** Prepare and populate the entire candidate before publishing relocation, or retain enough backing and registry state to restore both source and replaced destination completely. Fault-inject growth-fill failure and verify mappings, contents, metadata, and cache visibility remain unchanged.

**S64-R4-4 — Retained-fd failures silently turn file growth into anonymous zero-filled memory**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:207`
- **Evidence & Root Cause:** `sysmem_file_note_map()` marks an entry live and returns success even when descriptor duplication fails. Split paths likewise accept failed duplicates. `sysmem_file_fill_overlap()` explicitly returns success for `slot->fd < 0` at `src/os/sysmem_file_fill.c:184`, leaving zero-filled growth pages and bypassing EOF/BUS classification. Descriptor exhaustion therefore changes observable mapping semantics.
- **Concrete Fix:** Acquire required descriptors before publishing mapping changes and propagate acquisition failures. Prefer a repository-local reference-counted backing-description object so splitting ranges does not require additional host descriptors. Test descriptor exhaustion during initial registration and splitting.

**S64-R4-5 — munmap allocation failure silently discards metadata for a surviving mapping**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem.c:410`
- **Evidence & Root Cause:** `sparc64_sysmem_munmap()` ignores the registry reservation result. When a middle excision subsequently cannot claim a tail slot, `sysmem_file_drop_map()` trims the head and continues at line 341 without tracking the still-mapped tail. Later truncation cannot update that tail’s EOF faults; later growth cannot recover its file backing. This contradicts the Round-3 claim that live tracking is never evicted.
- **Concrete Fix:** Return `-ENOMEM` before mutation when required split metadata cannot be reserved, or provide a representation that preserves both survivors without allocation. Add a forced-allocation-failure case for middle-page unmapping.

**S64-R4-6 — Truncation can restore permissions revoked by mprotect**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:488`
- **Evidence & Root Cause:** File registration records `slot->prot`, but `sparc64_sysmem_mprotect()` changes only the address-space pages and caches. Truncate shrink passes the stale `slot->prot` to `sparc64_space_map_bus()`; subsequent growth passes it to `sparc64_space_replace()` at line 511. A mapping originally writable, then made read-only or inaccessible, can regain its original permissions after shrink/growth.
- **Concrete Fix:** Preserve current per-page permissions when changing backing/BUS state, or split and update registry permissions transactionally on every successful `mprotect`. Test whole-range and partial-range permission changes followed by truncate shrink and regrowth.

**S64-R4-7 — Failed execve closes descriptors, including newly retained mapping descriptors**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/proc.c:492`
- **Evidence & Root Cause:** `proc_close_cloexec()` runs before host `execve()` or guest image loading can fail. Its process-wide scan closes every CLOEXEC descriptor numbered three or higher. A failed exec therefore destroys guest descriptors that should survive failure. HEAD’s new `F_DUPFD_CLOEXEC` mapping descriptors are also swept up, while existing registry entries retain their numeric fd values. Subsequent descriptor reuse can make those entries reference unrelated files.
- **Concrete Fix:** Apply guest CLOEXEC closure only at successful guest-image commit, using explicit guest descriptor ownership. Let host `execve()` perform its own atomic CLOEXEC handling. Keep translator-owned retained descriptors outside the guest close sweep. Test failed exec followed by descriptor use and file-backed mremap.

**S64-R4-8 — Signal masks, pending signals, and alternate stacks remain process-global**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sync_sig.c:74`
- **Evidence & Root Cause:** `sync_blocked`, `sync_pending`, and alternate-stack fields are single static variables. The thread structure contains no corresponding per-thread state, and engine lock handoff does not save or restore it. Consequently, one guest thread’s mask or alternate-stack change affects siblings; pending delivery can consume another thread’s state. Serializing execution with the big lock does not provide per-thread semantics.
- **Concrete Fix:** Store thread-specific signal state in the guest thread record and resolve it through the active context. Keep shared dispositions separate. Implement clone inheritance and alternate-stack reset rules explicitly. Add two-thread tests with different masks and alternate stacks.

**S64-R4-9 — Retried relative futex waits restart the full timeout**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads_darwin.c:238`
- **Evidence & Root Cause:** After backend `-EINTR`, the Darwin loop updates `expected_seq` and retries using the original relative `ts`. The backend computes a new deadline from the current time on every invocation. Repeated interruptions can therefore extend a finite WAIT indefinitely. The Linux retry loop in `src/os/threads.c:456` also resubmits the unchanged relative timeout.
- **Concrete Fix:** Compute a monotonic deadline once for relative WAIT and pass the remaining duration on internal retries. Distinguish internal preemption from guest-visible signal interruption. Add a timed-wait case with repeated internal wakeups and an unchanged futex word.

**S64-R4-10 — Round-3 registry tests omit the syscall transaction paths they claim to cover**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `Makefile:155`
- **Evidence & Root Cause:** `check-r3` links the registry, population, memory, and VM files, but excludes `guest_run_sysmem.c`. Its tests exercise registry helpers directly and use counting stubs for invalidation. They cannot exercise mmap/mremap/munmap transaction ordering, mprotect metadata maintenance, or the failing relocation cleanup in S64-R4-3. Successful helper tests therefore leave the consequential integration paths unchecked.
- **Concrete Fix:** Add focused tests that invoke the actual syscall shells, with injectable allocation, descriptor, and fill failures. Assert address-space and registry state before and after failure, plus epoch behavior. Retain the existing helper tests.

**S64-R4-11 — Floating-point exception commit logic is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/interp/fp_conv.c:82`
- **Evidence & Root Cause:** `cv_commit()` duplicates the FSR current-exception update, accrued-exception update, TEM check, and trap construction in `sd_commit()` at `src/interp/fp_sd.c:71`. Both implement the same architectural operation, so future exception corrections require synchronized edits.
- **Concrete Fix:** Introduce one repository-local FP exception-commit helper in an internal header/source pair. Use it from both paths and keep result-publication ordering explicit.

The source-length inspection found no `.c`, `.h`, or `.S` file above 900 lines; the largest was `src/os/threads.c` at 897. The prohibited-call scan found `strcpy`/`strcat` in the libc string test, including intentional coverage of those functions. No confirmed YAGNI finding emerged from the bounded inspection. These checks do not establish complete C11 compliance or prove that encoded JIT instructions avoid `x18`.

- [x] **S64-R4-1:** Correct negative 32-bit conversion magnitudes.
- [x] **S64-R4-2:** Gate directed-rounding increments on inexactness.
- [x] **S64-R4-3:** Make failed mremap relocation fully transactional.
- [x] **S64-R4-4:** Handle retained-descriptor acquisition failures.
- [x] **S64-R4-5:** Preserve surviving mapping metadata on allocation failure.
- [x] **S64-R4-6:** Preserve current permissions across truncate transitions.
- [x] **S64-R4-7:** Defer CLOEXEC closure until successful exec commit.
- [x] **S64-R4-8:** Make signal masks, pending state, and alternate stacks thread-specific.
- [x] **S64-R4-9:** Preserve futex deadlines across retries.
- [x] **S64-R4-10:** Test actual syscall transaction and failure paths.
- [x] **S64-R4-11:** Unify FP exception commit logic locally.

---

## 11. `rt-series` (`5e6cbc0`) — 7 Round-4 Findings (`7 / 7` Resolved)

Found **7 actionable issues** at `5e6cbc0`: **6 Medium, 1 Low**. Findings concern this repository’s harness and fixtures; there is no tracked `src/` translator implementation here.

The Round-3 changes add strict warning flags, separate TestFloat engine runs, require foreign upstream adapters, and restrict `hl` rerouting to automatically selected wrappers. The follow-up LL/SC guard and cleanup verification still have gaps.

**RTS-R4-1 — LL/SC capability guard enables unsupported probe implementations**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tests/p3_llsc.h:26`
- **Evidence & Root Cause:** `P3_HAVE_LLSC` accepts every `__arm__` and `__riscv` target. However, `llsc_pair()` implements ARM only when `__ARM_ARCH >= 6` (line 69), and RISC-V only with `__riscv_atomic` (line 80). Other configurations reach the fallback at line 131, which always sets `stored = 0`. The no-signal control therefore fails all 32 attempts, and `t_llsc_reservation()` reports a translator failure despite executing no LL/SC instructions. This contradicts the follow-up’s claimed exact architecture guard.
- **Concrete Fix:** Make `P3_HAVE_LLSC` match the implementation predicates exactly, including ARM version, RISC-V atomic support, and consistent PowerPC/LoongArch aliases. Make an enabled-but-unimplemented branch a preprocessing error rather than a silent fallback.

**RTS-R4-2 — Extracted LL/SC header does not invalidate guest binaries**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/build_uniform_guests.sh:112`
- **Evidence & Root Cause:** `already_built()` checks only the modification times of `p3_torture.c` and `smoke_tcg.c`. Since `b4f5131`, the reservation implementation lives in `tests/p3_llsc.h`. Changing that header alone leaves every existing P3 guest classified as up to date, allowing qualification to exercise obsolete probe code.
- **Concrete Fix:** Add `tests/p3_llsc.h` to the P3 dependency check. Also invalidate artifacts when the build recipe or compilation flags change, using a dependency/build stamp or equivalent explicit tracking.

**RTS-R4-3 — Container cleanup verification treats inspection failure as success**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/build_uniform_guests.sh:67`
- **Evidence & Root Cause:** Both cleanup and verification suppress `docker ps` failures with `|| true` (lines 47 and 67). Verification interprets empty output as no remaining containers. Failed `docker inspect` calls are likewise converted to empty names, which cannot match the ownership suffix. Consequently, `on_uniform_exit()` can preserve exit status zero even when container removal could not be verified.
- **Concrete Fix:** Track the exact container names or IDs created by this invocation. Propagate listing failures and distinguish a confirmed absent container from an inspection failure. Bound cleanup and inspection commands with timeouts.

**RTS-R4-4 — Sub-page permission fixture never checks write protection**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tests/tcg/smoke_tcg.c:270`
- **Evidence & Root Cause:** `t_test_mmap()` requests RW/RX/RO/NONE pages, but checks only the RW page and a read fault on NONE. It never accesses RX or RO to verify readable contents or rejected writes, yet reports `test-mmap sub-page permissions`. A backend that incorrectly leaves both RX and RO writable passes this fixture.
- **Concrete Fix:** Initialize all pages before protection changes. Use explicit volatile accesses to verify reads from RX/RO and write faults on each, checking fault addresses. Recheck the neighboring RW page after each protection transition to detect widened host-page permissions.

**RTS-R4-5 — Grind compilation and generators can run without a time limit**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:361`
- **Evidence & Root Cause:** Guest execution is bounded, but GCC torture compilation is not. The same omission affects builtin compilation at line 537, Csmith generation/compilation at lines 752–753, and Yarpgen generation/compilation at lines 767, 783, and 794. A stalled generator or compiler prevents the suite from reaching its bounded execution and summary paths.
- **Concrete Fix:** Apply explicit `timeout --kill-after=30s` budgets to each generator and compiler invocation. Report timeout separately from an unsupported-source compilation skip, and clean up temporary artifacts on interruption.

**RTS-R4-6 — Remote benchmark parser returns success for invalid results**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/remote_bench_common.sh:141`
- **Evidence & Root Cause:** `parse_and_print()` extracts fields without validating record counts or workload status. Missing fields become `-`; a missing summary becomes `FAIL`. Its final `printf` still returns success. Thus an executable that exits zero with empty or malformed output can produce a failed-looking result row while `remote_linux_inner.sh` and `remote_bench.sh` complete successfully. The local harness has substantially stricter validation at `tools/bench_harness.sh:388`.
- **Concrete Fix:** Move benchmark record validation into a shared repo-local helper. Require exactly one valid PASS record for each workload and one valid ALL_PASS summary. Have remote callers propagate validation failure as a nonzero exit status.

**RTS-R4-7 — Signal-safe fault-address encoding is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `tests/p3_torture.c:90`
- **Evidence & Root Cause:** The three-word, 22-bit signal-address bridge, width assertion, store routine, and load routine are duplicated in `tests/tcg/smoke_tcg.c:84`. Only the names differ. Changes to this portability-sensitive representation must currently be synchronized manually.
- **Concrete Fix:** Introduce one repo-local test header containing the bridge type, assertion, and static inline encode/decode helpers. Keep a separate bridge instance in each fixture.

Seven shell inspection invocations were used, including the requested history commands, source-filtered commit diffs, numbered source reads, searches, and line counts. No builds, tests, containers, or QEMU were run; no files changed. The requested unrestricted `git show HEAD` exposed Markdown diffs; those were not used as finding evidence.

All inspected C/header files are below 900 lines; the largest is `tests/p3_torture.c` at 750. The targeted scan found no prohibited string calls, `.c` inclusions, or explicit `x18`/`w18` operands. No additional CLEAN or YAGNI finding was sufficiently established. These static checks do not qualify sibling translator semantics.

- [x] **RTS-R4-1:** Match LL/SC capability guards to implemented probes.
- [x] **RTS-R4-2:** Rebuild uniform guests when included headers or recipes change.
- [x] **RTS-R4-3:** Fail cleanup verification when container state cannot be established.
- [x] **RTS-R4-4:** Test RX/RO write rejection and adjacent-page isolation.
- [x] **RTS-R4-5:** Bound grind generators and compiler invocations.
- [x] **RTS-R4-6:** Validate remote benchmark records and propagate failure.
- [x] **RTS-R4-7:** Unify the signal-safe fault-address bridge.

---

## Part V — Round-3 Audit Archive (85 Items Resolved & Verified by `fable`)

### 0.1 Round 3 Audit Matrix (`85 / 85` Resolved & Verified by `fable`)

Following complete remediation, `fable` (`claude-fable-5-1`) verification review, and `muse` post-review follow-up across all 145 Round-2 findings (archived in **Part II** below) and all 187 Round-1 findings (archived in **Part III** below), Round 3 performed a fresh `gpt-6-astra` static audit of all 11 repositories at their post-Round-2 `HEAD` commits (`85` findings: `0 Critical`, `44 High`, `31 Medium`, `10 Low`; steady convergence `187` in R1 → `145` in R2 → `85` in R3). All 85 Round-3 items were remediated via `muse exec`, audited by `claude-fable-5-1` (`lode/reviews/2026-11-02-defects-r3-*-fable.md`), and closed out with post-`fable` `muse exec` follow-up commits across all repositories.

| # | Repository | Class | Audited `master` | R3 `muse` Fix | Post-`fable` `HEAD` | High | Med | Low | **R3 Resolved** | R3 `astra` Audit | R3 `fable` Review |
|---:|---|---|---|---|---|---:|---:|---:|---:|---|---|
| 1 | `a32rt` | Class A | `a76285b` | `a8c5bfd` | `5561e7e` | 4 | 2 | 1 | **7 / 7** | [`r3-a32rt-astra.md`](lode/reviews/2026-11-02-defects-r3-a32rt-astra.md) | [`r3-a32rt-fable.md`](lode/reviews/2026-11-02-defects-r3-a32rt-fable.md) |
| 2 | `i686rt` | Class A | `4a759c6` | `0c82128` | `ca4c9a2` | 9 | 0 | 2 | **11 / 11** | [`r3-i686rt-astra.md`](lode/reviews/2026-11-02-defects-r3-i686rt-astra.md) | [`r3-i686rt-fable.md`](lode/reviews/2026-11-02-defects-r3-i686rt-fable.md) |
| 3 | `mips32rt` | Class A | `a86a161` | `0aa8075` | `4cead69` | 5 | 2 | 1 | **8 / 8** | [`r3-mips32rt-astra.md`](lode/reviews/2026-11-02-defects-r3-mips32rt-astra.md) | [`r3-mips32rt-fable.md`](lode/reviews/2026-11-02-defects-r3-mips32rt-fable.md) |
| 4 | `ppc32rt` | Class A | `2c2a62e` | `d58f57e` | `f083489` | 4 | 3 | 0 | **7 / 7** | [`r3-ppc32rt-astra.md`](lode/reviews/2026-11-02-defects-r3-ppc32rt-astra.md) | [`r3-ppc32rt-fable.md`](lode/reviews/2026-11-02-defects-r3-ppc32rt-fable.md) |
| 5 | `sparc32rt` | Class A | `b40924b` | `7396a37` | `f7d73db` | 6 | 3 | 1 | **10 / 10** | [`r3-sparc32rt-astra.md`](lode/reviews/2026-11-02-defects-r3-sparc32rt-astra.md) | [`r3-sparc32rt-fable.md`](lode/reviews/2026-11-02-defects-r3-sparc32rt-fable.md) |
| 6 | `rvrt` | Class B | `dab0b91` | `b1b08af` | `b1b08af` | 3 | 3 | 1 | **7 / 7** | [`r3-rvrt-astra.md`](lode/reviews/2026-11-02-defects-r3-rvrt-astra.md) | [`r3-rvrt-fable.md`](lode/reviews/2026-11-02-defects-r3-rvrt-fable.md) |
| 7 | `loongarch64rt` | Class B | `00ea803` | `0e3c4bd` | `1907d96` | 2 | 5 | 0 | **7 / 7** | [`r3-loongarch64rt-astra.md`](lode/reviews/2026-11-02-defects-r3-loongarch64rt-astra.md) | [`r3-loongarch64rt-fable.md`](lode/reviews/2026-11-02-defects-r3-loongarch64rt-fable.md) |
| 8 | `ppc64rt` | Class B | `205054f` | `076461d` | `56bec31` | 5 | 3 | 1 | **9 / 9** | [`r3-ppc64rt-astra.md`](lode/reviews/2026-11-02-defects-r3-ppc64rt-astra.md) | [`r3-ppc64rt-fable.md`](lode/reviews/2026-11-02-defects-r3-ppc64rt-fable.md) |
| 9 | `mips64rt` | Class B | `45af6bf` | `385b31a` | `f7c6924` | 1 | 3 | 2 | **6 / 6** | [`r3-mips64rt-astra.md`](lode/reviews/2026-11-02-defects-r3-mips64rt-astra.md) | [`r3-mips64rt-fable.md`](lode/reviews/2026-11-02-defects-r3-mips64rt-fable.md) |
| 10 | `sparc64rt` | Class B | `001f2b1` | `b7c6514` | `5232650` | 4 | 3 | 0 | **7 / 7** | [`r3-sparc64rt-astra.md`](lode/reviews/2026-11-02-defects-r3-sparc64rt-astra.md) | [`r3-sparc64rt-fable.md`](lode/reviews/2026-11-02-defects-r3-sparc64rt-fable.md) |
| 11 | `rt-series` | Harness | `37a9af0` | `4d36271` | `b4f5131` | 1 | 4 | 1 | **6 / 6** | [`r3-rt-series-astra.md`](lode/reviews/2026-11-02-defects-r3-rt-series-astra.md) | [`r3-rt-series-fable.md`](lode/reviews/2026-11-02-defects-r3-rt-series-fable.md) |
| | **Total (Round 3)** | | | | | **44** | **31** | **10** | **85 / 85** | | |

### 0.2 Round 3 Cross-Cutting Defect Clusters (Wave Planning Index)

- [x] **X-R3-1 — High — Transactional VMA / File-Backing / Inode Table Capacity & Registration Ordering**
  - **Linked Items**: `A32-R3-1`, `A32-R3-5`, `I686-R3-3`, `I686-R3-4`, `I686-R3-5`, `RV-R3-4`, `LA64-R3-3`, `LA64-R3-4`, `P64-R3-1`, `P64-R3-2`, `S64-R3-3`
  - **Summary**: `a32rt` `vm_record_region_locked` calling `vm_unmap_regions_locked` and deleting newly registered file backing (`A32-R3-1`), `i686rt` anonymous `MAP_FIXED` leaving stale file registrations (`I686-R3-3`) or VMA split exhaustion broadening `mprotect` to the whole region (`I686-R3-5`), `rvrt`/`a32rt`/`sparc64rt`/`loongarch64rt` dropping surviving VMA tails or evicting live file-backing records on table exhaustion (`A32-R3-5`, `RV-R3-4`, `LA64-R3-3`, `S64-R3-3`), and `ppc64rt` partial/interior `mremap` truncating or inverting file-backing intervals (`P64-R3-1`, `P64-R3-2`).
- [x] **X-R3-2 — High — File-Backed `mmap` Initial EOF Boundaries, `mremap` Growth/Move Backing & Darwin A2 Shared/Sub-Page Semantics**
  - **Linked Items**: `A32-R3-2`, `A32-R3-3`, `I686-R3-2`, `I686-R3-7`, `I686-R3-9`, `M32-R3-2`, `M32-R3-3`, `P32-R3-2`, `P32-R3-3`, `RV-R3-5`, `RV-R3-6`, `LA64-R3-2`, `S64-R3-2`
  - **Summary**: Private/staged file mappings permitting accesses wholly beyond initial EOF (`A32-R3-2`, `RV-R3-5`), `mremap` growth/relocation losing private/file backing and producing anonymous zeros (`A32-R3-3`, `S64-R3-2`), `i686rt` shared anonymous `mremap` falling back to `memcpy` (`I686-R3-9`), `ppc32rt` publishing 16 KiB host-rounded padding as guest-accessible memory (`P32-R3-2`), Darwin A2 unaligned shared mappings silently becoming private copies (`P32-R3-3`, `LA64-R3-2`) or overwriting newer alias data (`M32-R3-2`), and sub-page protection widening/restoration windows (`I686-R3-2`, `M32-R3-3`, `RV-R3-6`).
- [x] **X-R3-3 — High — Multi-Threaded `fork()`, `execve()`, `clone()` TID Coherence & Execution Quiescence**
  - **Linked Items**: `A32-R3-4`, `A32-R3-6`, `I686-R3-1`, `I686-R3-8`, `M32-R3-1`, `P32-R3-4`, `S32-R3-1`, `S32-R3-2`, `S32-R3-3`, `S32-R3-4`, `S32-R3-9`, `P64-R3-4`, `P64-R3-5`, `P64-R3-6`, `P64-R3-7`, `S64-R3-1`, `S64-R3-4`, `S64-R3-5`, `S64-R3-7`
  - **Summary**: `fork()` inheriting vanished-thread JIT execution leases, VM/DBT locks, or thread registries without coordinated preparation/reinitialization (`A32-R3-4`, `I686-R3-8`, `P32-R3-4`, `S32-R3-2`), `sparc32rt` `execve` replacing memory while sibling threads remain alive (`S32-R3-4`) or leaking `FD_CLOEXEC` descriptors (`S32-R3-9`), `i686rt` `clone` publishing synthetic vs host TIDs (`I686-R3-1`), `mips32rt` `brk` updating `vm_gen` without syncing VMA snapshots (`M32-R3-1`), `sparc64rt` peer VM mutations not invalidating sleeping threads' DBT caches (`S64-R3-1`), and `ppc64rt` cooperative futex deadline/signal/requeue handling (`P64-R3-4..7`).
- [x] **X-R3-4 — High — Per-Thread Signal State, `execve` Signal Inheritance, Aliased Input/Output & `sigaltstack`**
  - **Linked Items**: `M32-R3-5`, `M32-R3-6`, `M32-R3-7`, `P32-R3-5`, `P32-R3-6`, `P32-R3-7`, `S32-R3-5`, `S32-R3-6`, `S32-R3-7`, `S32-R3-8`, `LA64-R3-1`, `LA64-R3-6`, `LA64-R3-7`, `P64-R3-3`, `P64-R3-8`
  - **Summary**: Process-global signal masks / alternate stacks instead of per-thread state (`S32-R3-5`, `LA64-R3-1`), `execve` clearing the inherited blocked signal mask or ignored dispositions (`M32-R3-6`, `P32-R3-7`), `rt_sigaction`/`rt_sigprocmask`/`sigaltstack` overwriting aliased input pointers before reading them (`P32-R3-5`, `LA64-R3-6`), `SS_AUTODISARM` and `SS_DISABLE` / `uc_stack` restoration gaps (`LA64-R3-7`, `P64-R3-3`), and `SIG_IGN` handling (`S32-R3-6`, `P64-R3-8`).
- [x] **X-R3-5 — High — Syscall Copyout LL/SC Reservation Invalidation, Fault Containment & Vectored I/O**
  - **Linked Items**: `I686-R3-6`, `M32-R3-4`, `LA64-R3-5`, `M64-R3-1`, `M64-R3-3`, `M64-R3-4`, `S64-R3-6`
  - **Summary**: Syscall copyouts (`rt32_vm_copy_to`, `guest_range` + `putn`) bypassing the LL/SC write lock (`M32-R3-4`, `M64-R3-1`), `i686rt` syscall copy faults `siglongjmp`ing past caller buffer cleanup (`I686-R3-6`), `mips64rt` splitting `readv`/`writev` into 64-iovec chunks (`M64-R3-3`) and omitting current-batch bytes on partial `readv` fault (`M64-R3-4`), and Darwin `getdents64` early-`dup` / eviction cursor loss (`LA64-R3-5`, `S64-R3-6`).
- [x] **X-R3-6 — High — ISA / FPU Rounding, Sticky Exception Flags & DBT Emitter State Rollback**
  - **Linked Items**: `P32-R3-1`, `RV-R3-1`, `RV-R3-2`, `RV-R3-3`, `M64-R3-2`
  - **Summary**: `rvrt` dynamic-rounding slow path flushing uninitialized host FPSR (`RV-R3-1`), `emit_uf_fix` clearing earlier instructions' sticky UFC flags (`RV-R3-2`), and emitter overflow rollback retaining dirty FPR/tag mutations from discarded instructions (`RV-R3-3`), `ppc32rt` `divwo.`/`divwuo.` testing `gpr[rb]` after overwriting `gpr[rt]` when `RT == RB` (`P32-R3-1`), and `mips64rt` `ADD.S`/`SUB.S` directed rounding losing small residuals (`M64-R3-2`).
- [x] **X-R3-7 — Medium — Intra-Repo DRY, YAGNI, `-Werror` / `check-line-limits` Wiring & `rt-series` Harness**
  - **Linked Items**: `A32-R3-7`, `I686-R3-10`, `I686-R3-11`, `M32-R3-8`, `S32-R3-10`, `RV-R3-7`, `P64-R3-9`, `M64-R3-5`, `M64-R3-6`, `RTS-R3-1..RTS-R3-6`

---
## 1. `a32rt` (`a76285b` → `a8c5bfd` → `5561e7e`) — 7 Round-3 Findings (`7 / 7` Resolved)

Found **7 issues** at `a76285b`, including a mapping-registration ordering defect that can discard newly installed file backing.

Reviewed `git log -n 5 --oneline`, both recent commits, and selected VM, JIT, interpreter, signal, syscall, build, and test paths. This was static inspection only; no builds, tests, Docker, or QEMU ran. Findings below are code-derived, not runtime reproductions.

**A32-R3-1 — Region registration deletes newly installed file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:621`; `src/vm.c:235`; `src/vm/vm_file.c:592`
- **Evidence & Root Cause:** `vm_mmap2_locked()` installs the mapping and records its file backing before calling `vm_record_region_locked()`. That function unconditionally calls `vm_unmap_regions_locked()`, which removes file tracking for the same range. Thus registration deletes the metadata just created. On hosts with pages larger than 4 KiB, deleting a fully covered shared entry also replaces its host mapping with anonymous private memory. A successful shared mmap can therefore immediately lose sharing and file contents.
- **Concrete Fix:** Separate removal of the previous mapping from insertion of the new region. Retire old backing before installation, then publish new region and backing metadata together. Do not invoke backing teardown from a generic region-registration helper.

**A32-R3-2 — Initial staged mappings permit accesses wholly beyond EOF**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:284`; `src/vm/vm_file.c:297`
- **Evidence & Root Cause:** Private-file population records `max(file_offset + len, st_size)` as the inode size and clears EOF restrictions across the entire mapping. A2 uses anonymous staging, so the host cannot supply the missing file-backed fault. Mapping 8 KiB from a 4 KiB file consequently leaves the second page accessible. The mapping extent also corrupts the size baseline used to distinguish file growth from shrinkage. This remains incorrect after fixing A32-R3-1.
- **Concrete Fix:** Track the actual file size separately from mapping extent. Mark pages wholly beyond rounded EOF inaccessible when committing the mapping; zero only the last partial page. Preserve these restrictions through region publication.

**A32-R3-3 — Private file mappings lose their backing during mremap**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm.c:784`; `src/vm.c:817`; `src/vm.c:866`
- **Evidence & Root Cause:** Only shared mappings retain a file descriptor and offset in `a32_vm_mremap()`. Private mappings grow through anonymous extension; moving them allocates anonymous memory and copies existing bytes. For a private mapping of the first page of a two-page file, expansion returns zeros instead of the second file page. Moving also drops future file-size/EOF tracking.
- **Concrete Fix:** Carry private backing identity and offsets through both growth and relocation. Populate newly exposed file pages while preserving existing private modifications and EOF state. Transfer backing metadata with the mapping.

**A32-R3-4 — Fork inherits JIT leases belonging to vanished threads**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/os_sys_fork_time.c:157`; `src/vm/vm_jit_mem.c:115`
- **Evidence & Root Cause:** Fork copies the process-global `g_jit_exec_readers`, `g_jit_reset_pending`, and JIT lock state. Their references contain no child-side reinitialization or fork coordination. If another thread holds an execution lease at fork, the child inherits its reader count without that thread. A later cache reset waits forever. Inheriting a held lock or pending reset similarly prevents progress.
- **Concrete Fix:** Coordinate fork with JIT execution and mutation: stop new entrants, quiesce readers, and serialize cache state before fork. Restore parent execution afterward and initialize child synchronization state consistently. Resetting counters alone is insufficient if the snapshot captures partially mutated cache data.

**A32-R3-5 — File-tracking capacity exhaustion silently disables semantics**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:94`; `src/vm/vm_file.c:523`; `src/vm/vm_file.c:606`
- **Evidence & Root Cause:** The inode table has 64 entries and never releases `used` entries. Mapping 64 distinct files over the process lifetime exhausts it, even after unmapping them. Mapping and shared-backing tables also silently discard records on exhaustion or descriptor-duplication failure. A middle unmap truncates the original record before securing the right-hand record, so allocation failure loses tracking for still-mapped memory.
- **Concrete Fix:** Reclaim inode entries when their last mapping disappears. Make backing registration and splitting return errors, and reserve required slots/descriptors before mutation. Either grow these tables or reject operations before changing memory when tracking cannot be maintained.

**A32-R3-6 — Single-step execution acquires its lease after code can be recycled**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/dbt_jit_run.c:579`; `src/dbt/dbt_jit_run.c:590`
- **Evidence & Root Cause:** `a32_jit_compile_block()` returns through `compile_block_internal(..., false)`, releasing the JIT lock without an execution lease. Single-step then reacquires the lock, seals the batch, and increments the reader count. Another thread can reset and reuse the cache between compilation and lease acquisition. The saved `code` pointer is not revalidated before execution.
- **Concrete Fix:** Compile, seal, and acquire the execution lease within one locked operation. Reuse the lease-bearing lookup path or introduce an explicit compiled-block lease API.

**A32-R3-7 — Fixture build recipes do not consistently enforce requested C flags**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:125`; `Makefile:131`; `Makefile:250`
- **Evidence & Root Cause:** Runtime `CFLAGS` include the requested warning policy, but fixture flags omit `-Werror`; the recipe at line 250 also omits `-pedantic`. Consequently, the policy is not enforced consistently across repository C code.
- **Concrete Fix:** Define a shared C warning-policy variable and use it in applicable runtime and fixture recipes, keeping architecture-specific options separate.

The inspected `.c`, `.h`, and `.S` files stayed below 900 lines; the largest was `src/vm.c` at 897. The source/header scan found no forbidden string calls, `.c` inclusions, or literal `x18`/`w18` register references. That scan does not establish reservation of register 18 in numeric instruction encoders. No additional DRY or YAGNI finding was sufficiently substantiated within this review budget.

- [x] **A32-R3-1:** Separate mapping teardown from registration.
- [x] **A32-R3-2:** Enforce initial EOF boundaries.
- [x] **A32-R3-3:** Preserve private-file backing across mremap.
- [x] **A32-R3-4:** Coordinate fork with JIT leases and locks.
- [x] **A32-R3-5:** Make backing-table allocation transactional and reclaim entries.
- [x] **A32-R3-6:** Acquire single-step leases before releasing compiled code.
- [x] **A32-R3-7:** Apply C warning flags consistently.

---

## 2. `i686rt` (`4a759c6` → `0c82128` → `ca4c9a2`) — 11 Round-3 Findings (`11 / 11` Resolved)

Round 3 found **11 actionable issues** at `4a759c6`, including remaining correctness defects in thread identity, sub-page isolation, mapping bookkeeping, and fork handling.

This was a static review using seven shell inspection turns: `git log -n 5 --oneline`, `git show HEAD~1`, `git show HEAD`, and targeted source reads/searches. No builds, tests, Docker, or QEMU ran. No files changed. Findings below are source-derived; this bounded review does not establish complete ISA or backend correctness.

**I686-R3-1 — Clone publishes inconsistent thread IDs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/clone.c:472`
- **Evidence & Root Cause:** `thread_entry()` rekeys the registry to the host TID, then immediately assigns `tid = pre_tid` and writes that synthetic ID into the parent/child TID words. `r_clone()` also returns the synthetic ID, while `sys_gettid()` reads the rekeyed registry. Consequently, targeting the returned clone ID can produce `ESRCH`, and libc ownership words can disagree with robust recovery’s host TID.
- **Concrete Fix:** Choose one guest TID namespace consistently. Given Linux PI-futex forwarding, synchronize child startup so the parent receives the actual host TID and both SETTID words contain it before clone returns. Remove the unsynchronized synthetic counter or protect any remaining allocation.

**I686-R3-2 — Staged mmap bypasses sub-page quiescence**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm.c:126`
- **Evidence & Root Cause:** `rt32_vm_mmap2_staged_a2_locked()` makes the entire host-page cover writable before zeroing or loading the requested sub-pages. Its caller holds the VM bookkeeping lock, but neither path acquires `i686_vm32_subpage_lock()`. Guest execution does not take the bookkeeping lock. A sibling can therefore access a protected neighboring sub-page during this window, including writing through an SMC-protected cover.
- **Concrete Fix:** Quiesce guest execution around every staged mapping protection change, content update, and permission restoration. Establish a consistent lock order and restore restrictive protections on every failure path.

**I686-R3-3 — Anonymous MAP_FIXED leaves stale file registrations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:106`
- **Evidence & Root Cause:** File-map removal occurs only when the *new* mapping is file-backed. Replacing a file mapping with `MAP_FIXED | MAP_ANONYMOUS` leaves the old file association and owned FD registered. File hooks can subsequently treat the anonymous replacement as part of the old file. For an A2 staged shared-file predecessor, state zero also satisfies the refresh condition in `i686_vm_file_note_pwrite()`.
- **Concrete Fix:** Remove overlapping backing registrations for every successful replacement, including anonymous mappings. Reserve required split capacity before changing host mappings, and register new backing only when applicable.

**I686-R3-4 — Mapping registry failures are ignored after mmap succeeds**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/rt32_vm_mmap.c:103`
- **Evidence & Root Cause:** The results of `rt32_vm_record_region_locked()`, `i686_vm_file_untrack_map()`, and `i686_vm_file_track_map()` are discarded. Region exhaustion, backing-table exhaustion, or FD duplication failure can therefore yield a successful guest mmap with absent or stale metadata. Later permission checks, file updates, and remapping operate on a different mapping model from the host.
- **Concrete Fix:** Preallocate metadata slots and backing references before committing the host mapping. Propagate allocation failures and make host mapping plus metadata publication transactional.

**I686-R3-5 — VMA split exhaustion silently changes requested semantics**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm.c:404`
- **Evidence & Root Cause:** When an interior mprotect requires two region slots and capacity is exhausted, the fallback assigns `r->prot = prot` to the entire original region. Other split failures similarly broaden the update. Interior unmap failure at line 346 instead leaves the original region intact. These helpers cannot report failure to callers, which continue returning success.
- **Concrete Fix:** Calculate and reserve split capacity before modifying mappings. Return an error without mutation when capacity is unavailable; never substitute whole-region protection changes or retain a supposedly unmapped interval.

**I686-R3-6 — Guest-copy failure escapes the syscall’s cleanup path**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/marshal.c:110`
- **Evidence & Root Cause:** On an unrecoverable copy fault, `s_copy_tolerant()` jumps to the outer engine checkpoint whenever one exists instead of returning `-I686_EFAULT`. Runtime syscall callers normally have that checkpoint. Their error handling and cleanup are bypassed. For example, A2 `sys_read()` allocates a temporary buffer before `i686_copy_to_guest()`; a fault after a concurrent mapping change skips its `free()` and syscall error return.
- **Concrete Fix:** Make syscall copy helpers contain faults and return `-EFAULT` after restoring protections and releasing locks. Keep guest-instruction fault propagation in a separate interface.

**I686-R3-7 — File refresh races mapping mutation and ignores protected destinations**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:517`
- **Evidence & Root Cause:** `i686_vm_file_note_pwrite()` walks ordinary `s_maps` fields and uses their owned FDs without the VM lock; `sys_pwrite64()` invokes it directly. Concurrent unmap can modify entries and close those FDs. Refresh also calls `pread()` directly into guest pages without opening restrictive A2 covers. A destination fault makes `pread()` fail, but the loop silently stops and still increments `refreshed`.
- **Concrete Fix:** Serialize backing lookup and lifetime management with mapping mutations. Refresh through a checked, quiesced copy path, handle host I/O failures explicitly, and invalidate translations for changed executable bytes.

**I686-R3-8 — Fork retains vanished-thread registry entries and locks**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:353`
- **Evidence & Root Cause:** The fork child only changes `ctx->host_tid`. The only registered atfork handler found resets `vm32` state; it does not reset `s_registry_lock`, `g_vm_lock`, or rebuild the thread registry. Forking while another thread owns either lock can leave the child permanently blocked. Forking from a worker also retains the old main-context pointer and registry entries for threads that no longer exist.
- **Concrete Fix:** Add coordinated fork preparation and parent/child handling for runtime-owned locks. Rebuild the child registry around the surviving context, update its process/thread identity, and discard vanished-thread state.

**I686-R3-9 — Shared anonymous mremap silently falls back to losing sharing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/rt32_vm_mmap.c:409`
- **Evidence & Root Cause:** The new Linux path attempts host `mremap()` to preserve shared anonymous backing. If it fails, execution falls through to `memcpy()` into a newly allocated shared anonymous mapping and returns success. That new object no longer shares identity with an existing fork peer. The fallback therefore defeats the semantic guarantee the new path was added to preserve.
- **Concrete Fix:** Propagate host-mremap failure and clean up the provisional destination. Use copying only where backing identity is irrelevant; other backends need a backing-preserving implementation for this case.

**I686-R3-10 — Exec-reader registration handshake is duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/vm/vm32.c:150`
- **Evidence & Root Cause:** `i686_vm32_subpage_unlock()` duplicates the writer-wait, reader-increment, writer-recheck, and rollback loop from `i686_vm32_exec_enter()`. This is consequential concurrency logic whose memory-ordering fixes must remain identical.
- **Concrete Fix:** Extract one private reader-registration helper. Keep the context/regime eligibility checks in `exec_enter()` and call the shared helper when restoring a dropped registration.

**I686-R3-11 — Obsolete lane ownership lists remain in Makefile**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `Makefile:243`
- **Evidence & Root Cause:** `U3_OWNED` and `P13_OWNED` are defined but never referenced. Their surrounding comments describe lane-scoped enforcement, while `check-line-limits` now scans all of `src`, `include`, and `tests`.
- **Concrete Fix:** Remove both unused lists and replace the obsolete lane commentary with a short description of repository-wide enforcement.

The inspected `.c`, `.h`, and `.S` files under `src`, `include`, and `tests` were all within 900 lines. The Makefile contains the requested warning flags. Those observations are static hygiene checks, not evidence of a warning-clean build.

Checklist summary:

- [x] **I686-R3-1:** Unify clone, SETTID, registry, and gettid identities.
- [x] **I686-R3-2:** Quiesce staged A2 mmap protection windows.
- [x] **I686-R3-3:** Remove stale backing records on anonymous replacement.
- [x] **I686-R3-4:** Handle mapping metadata allocation failures transactionally.
- [x] **I686-R3-5:** Reject VMA split exhaustion without changing semantics.
- [x] **I686-R3-6:** Return syscall copy faults through caller cleanup.
- [x] **I686-R3-7:** Synchronize and safely apply file refreshes.
- [x] **I686-R3-8:** Reinitialize runtime ownership and registry state after fork.
- [x] **I686-R3-9:** Preserve shared backing or fail mremap.
- [x] **I686-R3-10:** Deduplicate reader registration.
- [x] **I686-R3-11:** Remove unused Makefile lane lists.

---

## 3. `mips32rt` (`a86a161` → `0aa8075` → `4cead69`) — 8 Round-3 Findings (`8 / 8` Resolved)

Round 3 found **8 actionable issues** at `a86a161`, including a regression in the new VM generation fast path.

This was a static review using **7 shell inspection turns**. I inspected the five recent commits, both requested changesets, and selected VM, interpreter, DBT, syscall, signal, header, and test paths. No builds, tests, Docker, or QEMU ran. Findings below are source-based; this is not exhaustive runtime qualification.

### M32-R3-1 — `brk` marks stale VMA snapshots current

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm.c:98`, `src/rt32/vm.c:765`

**Evidence & Root Cause:** `vm_sync_brk_to_ctx()` updates only break fields but assigns the latest `vm_gen`. The new synchronization fast path treats that generation as proof that the entire context mapping table is current.

If thread A changes mappings and thread B subsequently calls `brk(0)` or changes its break within the same page, B can acquire the current generation without copying `g_vm_regions`. Subsequent synchronization skips the stale table until another VM mutation occurs.

**Concrete Fix:** Refresh the full context snapshot before assigning its generation, or track break and VMA generations separately. Add a regression covering one thread changing mappings while another queries `brk`.

### M32-R3-2 — Darwin shared-alias flushing overwrites newer data

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm_mmap.c:92`, `src/rt32/vm_mmap.c:164`

**Evidence & Root Cause:** Inode flushing visits every shadow mapping and copies its entire overlapping range into other aliases before writing it back. There is no dirty-byte tracking or authoritative shared backing.

For two shadow aliases A and B of the same file offset, a store through B leaves A stale. Flushing the inode visits A first when A has the lower guest address, copies stale bytes over B, and writes those bytes to the file. B’s subsequent flush cannot recover its update. Ordinary stores also do not provide immediate alias visibility.

**Concrete Fix:** Use coherent shared backing for aliases, or route shared-shadow reads and writes through an authoritative inode/offset representation. Whole-range copying from arbitrary aliases cannot establish which data is current.

### M32-R3-3 — Darwin protection restoration can disable adjacent guest pages

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm_mmap.c:64`, `src/rt32/vm_mmap.c:111`, `src/rt32/vm_mmap.c:707`

**Evidence & Root Cause:** `vm_host_temp_prot()` rounds a guest range to 16 KiB, but restoration applies the protection of only the selected VMA.

If a read-only 4 KiB shared mapping has a writable neighbor in the same host page, synchronization temporarily enables writes and then restores the entire host page to read-only. The neighbor remains writable in guest metadata, yet valid stores can fault on the host.

**Concrete Fix:** Compute host protections from all guest mappings overlapping each host page. Use that common protection calculation for temporary restoration, mapping changes, and unmapping.

### M32-R3-4 — Guest copyout bypasses LL/SC reservation tracking

**Severity:** High  
**Category:** BUG  
**Location:** `src/rt32/vm.c:821`, `src/os/mem.c:464`

**Evidence & Root Cause:** `rt32_vm_copy_to()` performs a plain `memcpy` under the VM lock. Interpreter stores instead use the LL/SC lock and update reservation epochs.

A second thread can copy the same value into a reserved word through a syscall output or thread-TID write without changing its epoch. The reserving thread’s subsequent SC can therefore succeed despite the intervening write. Clearing the syscall caller’s `llbit` does not clear another thread’s reservation.

**Concrete Fix:** Route guest copyout through a common bulk-store primitive that participates in LL/SC exclusion and advances every affected reservation epoch. Establish a consistent lock order.

### M32-R3-5 — Real-time queue overflow silently loses signals

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/signals.c:277`, `src/os/kill.c:216`

**Evidence & Root Cause:** Once `sig_rt_count` reaches its capacity, `mips_signal_pend()` skips enqueueing but still sets the pending bit. Its caller returns success.

For 65 blocked occurrences of the same real-time signal, only 64 queue entries survive. Popping the last entry clears the pending bit, discarding the additional occurrence.

**Concrete Fix:** Make enqueue failure observable and implement explicit overflow handling appropriate to the originating syscall. Preserve all accepted occurrences; never report successful queueing for a discarded event.

### M32-R3-6 — `execve` incorrectly clears inherited signal state

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/signals.c:853`

**Evidence & Root Cause:** `mips32_signals_reset_for_exec()` resets every disposition, clears the blocked mask, and discards pending signals and the real-time queue.

Successful Linux `execve` preserves the signal mask and pending signals, and generally preserves ignored dispositions. The implementation can lose pending events, unblock deliberately blocked signals, and turn an inherited ignored signal into a terminating one.

**Concrete Fix:** Reset caught handlers to default while retaining ignored dispositions, the blocked mask, and pending events. Clear obsolete frame bookkeeping and disable the alternate stack.

### M32-R3-7 — Signal delivery alters the interrupted stack pointer

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/signals.c:631`

**Evidence & Root Cause:** Frame construction saves `$sp` as `ctx->gpr[i] & ~7U` instead of its original value. `rt_sigreturn()` restores that modified value.

Aligning the newly allocated signal frame is appropriate; rounding the saved interrupted register changes architectural state. A synchronous fault during an instruction sequence with a temporarily unaligned stack pointer resumes with a different `$sp`.

**Concrete Fix:** Save the exact interrupted `$sp`. Apply alignment only to the handler’s frame address.

### M32-R3-8 — New errno regression test is disconnected from verification

**Severity:** Low  
**Category:** DEFECT  
**Location:** `tests/test_errno_map.c:1`, `Makefile:78`

**Evidence & Root Cause:** The post-fable commit adds `test_errno_map.c`, but neither `make test` nor `make check` invokes it. The inspected scripts contain no reference to it. Normal verification therefore does not exercise the new errno assertions.

**Concrete Fix:** Add the test to the host-native test target, propagate failures, and exercise its Darwin-specific conditional assertions on Darwin.

The static hygiene scan found no `.c`, `.h`, or `.S` file exceeding 900 lines. The Makefile retains the required C11 warning flags, and `CLAUDE.md` remains symlinked to `AGENTS.md`. The targeted text scan found no prohibited string functions, `.c` includes, or explicit `x18` instruction operands; this does not validate encoded register operands.

- [x] **M32-R3-1:** Keep VMA snapshots consistent with their generation.
- [x] **M32-R3-2:** Prevent stale shared aliases from overwriting newer data.
- [x] **M32-R3-3:** Restore host-page protections using all overlapping mappings.
- [x] **M32-R3-4:** Include copyout writes in LL/SC reservation tracking.
- [x] **M32-R3-5:** Handle real-time queue overflow without silent loss.
- [x] **M32-R3-6:** Preserve required signal state across `execve`.
- [x] **M32-R3-7:** Preserve the exact interrupted stack pointer.
- [x] **M32-R3-8:** Wire the errno regression test into verification.

---

## 4. `ppc32rt` (`2c2a62e` → `d58f57e` → `f083489`) — 7 Round-3 Findings (`7 / 7` Resolved)

Found **7 actionable defects** at `2c2a62e`, including two in the recent fixes. Review used **5 shell inspection turns**. No builds, tests, Docker, or QEMU ran; findings below are based on static code paths.

**P32-R3-1 — Division overflow checks read an overwritten divisor**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/interp/interp.c:380](/Users/angerman/Projects/zw3rk/ppc32rt/src/interp/interp.c:380)
- **Evidence & Root Cause:** The Round-2 change writes `ctx->gpr[insn.rt]` before testing `ctx->gpr[insn.rb] == 0U`. When `RT == RB`, the test examines the quotient. For example, `divwo. r5,r4,r5` with `r4=1`, `r5=2` produces zero and incorrectly sets `XER.OV`, sticky `XER.SO`, and `CR0.SO`. The DBT retains the original divisor in `EI_B`, so the engines diverge. Existing regression cases use distinct destination and divisor registers.
- **Concrete Fix:** Test the saved divisor (`sb == 0`) or calculate overflow before writing the destination. Add signed and unsigned cases with `RT == RB`, a nonzero divisor, and a zero quotient.

**P32-R3-2 — Host-page padding becomes guest-accessible memory**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/rt32/ppc32_vm.c:443](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:443), [src/rt32/ppc32_vm.c:470](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:470)
- **Evidence & Root Cause:** The latest fix extends `rec_end` to the host-rounded mapping end, then uses that end for both `vm32_record_map` and the guest region record. On a 16-KiB host, a 4-KiB shared mapping therefore grants the requested guest permissions to an additional 12 KiB. Unmapping the requested 4 KiB leaves the padding represented as a live guest mapping. This confuses host backing allocation with the specified 4-KiB guest mapping granularity.
- **Concrete Fix:** Track host backing extent separately from guest-visible extent. Publish guest permissions and VMAs only through `map_end`; keep padding inaccessible while accounting for its backing when placing or replacing adjacent mappings. Cover a 4-KiB shared mapping, accesses immediately past its end, and unmapping its exact requested length.

**P32-R3-3 — Unaligned shared mappings silently become private copies**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/rt32/ppc32_vm.c:438](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:438), [src/rt32/ppc32_vm.c:474](/Users/angerman/Projects/zw3rk/ppc32rt/src/rt32/ppc32_vm.c:474)
- **Evidence & Root Cause:** On A2, a shared mapping whose address or file offset is not host-page aligned fails `shared_direct`. It then enters the generic population branch: file contents are copied with `vm_file_populate_private`, or anonymous contents are zeroed. The mapping is nevertheless recorded as `VM32_PAGE_SHARED` and `MAP_SHARED`. A valid guest file offset of 4096 on a 16-KiB host reaches this path. The copied bytes do not provide coherent shared backing between aliases or processes.
- **Concrete Fix:** Implement shared backing for guest-aligned subpages, including alias and fork visibility. Until that exists, return an explicit unsupported-mapping error instead of reporting successful `MAP_SHARED` semantics. Test two mappings of the same file range and parent/child writes.

**P32-R3-4 — Multithreaded fork can inherit permanently locked runtime state**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/os/proc.c:102](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:102)
- **Evidence & Root Cause:** `ppc32_proc_fork` directly calls host `fork()`. Its child refresh changes context identity and reservation fields, but does not coordinate or repair process-global locks and thread bookkeeping. The repository contains custom VM, LL/SC, inode, and thread-table spinlocks, with no `pthread_atfork` registration found. If another host thread owns one at the fork snapshot, the child inherits the locked value without its owner and can spin forever. Resetting locks alone would also risk exposing metadata copied during a partial update.
- **Concrete Fix:** Add a coordinated fork protocol that reaches a consistent runtime state before the snapshot, releases locks in the parent, and rebuilds child lock ownership and thread bookkeeping around the sole surviving thread. Validate with a bounded child operation after forks concurrent with VM activity.

**P32-R3-5 — Signal syscalls overwrite aliased input before reading it**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/os/signals.c:605](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:605), [src/os/signals.c:635](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:635), [src/os/signals.c:704](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:704)
- **Evidence & Root Cause:** `rt_sigaction`, `rt_sigprocmask`, and `sigaltstack` write the old value to the output pointer before copying the requested input. When input and output overlap, the requested change is destroyed. For example, `rt_sigprocmask(SIG_SETMASK, p, p, 8)` rereads the old mask it just wrote and leaves the mask unchanged. Locked scalar copies prevent an unmap race but do not fix this ordering.
- **Concrete Fix:** Copy the complete input into a host-local structure before any output write. Apply validation and state changes using that snapshot. Add identical-pointer and partially overlapping-pointer cases for all three handlers.

**P32-R3-6 — Shared signal dispositions have unsynchronized readers and writers**

- **Severity:** High
- **Category:** BUG
- **Location:** [src/os/signals.c:203](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:203), [src/os/signals.c:224](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:224), [src/os/signals.c:407](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:407)
- **Evidence & Root Cause:** Guest threads share the static `sig_actions` table. Getters copy individual fields, setters assign individual fields, and `SA_RESETHAND` clears them directly, without synchronization. Concurrent guest `sigaction` calls and delivery therefore create C data races and can combine a handler from one disposition with flags, restorer, or mask from another.
- **Concrete Fix:** Synchronize disposition snapshots and updates. Make selection and consumption of a one-shot disposition atomic with respect to other deliveries and updates. Release the disposition lock before frame construction or guest-memory access, and include it in fork coordination.

**P32-R3-7 — Successful exec clears the inherited signal mask**

- **Severity:** Medium
- **Category:** BUG
- **Location:** [src/os/proc.c:428](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/proc.c:428)
- **Evidence & Root Cause:** The successful guest `execve` path unconditionally assigns `ctx->sig_mask = 0ULL`. The calling thread’s blocked signal mask must survive exec. A program that blocks a signal before replacing its image consequently starts the new image with that signal unblocked. The adjacent comment incorrectly describes this reset as Linux exec semantics.
- **Concrete Fix:** Preserve the calling thread’s signal mask across image replacement and correct the comment. Add a guest that blocks a signal, execs another guest, and queries its inherited mask.

The inspected line counts stayed within 900 lines. Text searches found no prohibited string-function calls or C-source inclusions; matching `x18` references were comments. These checks do not establish full C11 compliance or validate emitted register encodings. No additional DRY/YAGNI finding was sufficiently established in this bounded review.

Checklist:

- [x] **P32-R3-1:** Preserve the original divisor for overflow checks.
- [x] **P32-R3-2:** Separate host padding from guest mappings.
- [x] **P32-R3-3:** Preserve sharing for guest-aligned A2 mappings.
- [x] **P32-R3-4:** Coordinate fork with runtime locks and thread state.
- [x] **P32-R3-5:** Snapshot signal syscall inputs before output writes.
- [x] **P32-R3-6:** Synchronize shared signal dispositions.
- [x] **P32-R3-7:** Preserve the signal mask across exec.

---

## 5. `sparc32rt` (`b40924b` → `7396a37` → `f7d73db`) — 10 Round-3 Findings (`10 / 10` Resolved)

Round 3 found **10 remaining issues**, including incomplete concurrency fixes in the latest commits.

Reviewed `b40924b` and `a73ff14`, recent history, and selected VM, DBT, interpreter, syscall, backend, and test paths in **five shell inspection turns**. No builds, tests, Docker, or QEMU ran. These are static findings, not runtime reproductions.

### S32-R3-1 — Context teardown still permits cross-thread use-after-free

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads.c:103`, `src/os/threads.c:136`

**Evidence & Root Cause:** `thr_drop_context()` blocks signals only in the calling thread, removes the context from `thr_live`, and frees it. A handler on another thread can already have loaded that context pointer at line 136 and subsequently write `pending_signals` at line 140 after the free. Atomic publication protects the slot, not the pointed-to allocation. The new comment claiming that a handler cannot observe the freed pointer is incorrect.

**Concrete Fix:** Remove reclaimable context pointers from the asynchronous handler path. Have handlers update stable pending-signal storage and let normal execution route signals to contexts. Alternatively, introduce a signal-safe reclamation protocol that waits for all existing readers before freeing.

### S32-R3-2 — Fork resets VM counters without securing a consistent process snapshot

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads.c:313`, `src/rt32/vm.c:137`, `src/dbt/dbt_cache.c:46`

**Evidence & Root Cause:** `fork()` runs without coordinating VM or DBT mutations. The child resets only the VM reader/writer counters. It still inherits `thr_live_lock`, `g_dbt_lock`, DBT runner counts, and contexts belonging to vanished threads.

A worker can hold `thr_live_lock` when another thread forks; the child then deadlocks on its next `sparc32_threads_ensure_init()`. A child also can inherit a nonzero DBT runner count that can never drain. Resetting the VM lock after the fork does not repair metadata captured halfway through a VM mutation.

**Concrete Fix:** Establish a coordinated fork protocol: stop admission of new work, quiesce execution and VM mutations, acquire shared locks in a defined order, fork, then rebuild child-only thread registration and synchronization state. Reset counters only after obtaining a consistent snapshot.

### S32-R3-3 — VM reader protection does not cover generated memory accesses

**Severity:** High  
**Category:** BUG  
**Location:** `src/dbt/emit_fast.c:162`, `src/dbt/dbt.c:355`, `src/rt32/vm_mmap.c:294`

**Evidence & Root Cause:** Generated fast paths check the protection byte and then access the guest window directly. `dbt_exec_enter()` registers a DBT runner but does not join the VM reader protocol. Conversely, `vm_lock_acquire()` waits only for VM readers.

A worker can therefore change or remove a mapping after the main DBT thread passes its permission check but before its load/store. Mapping invalidation occurs after mutation and lock release; it cannot protect an already executing access. This permits host faults or accesses to replacement mappings.

**Concrete Fix:** Integrate VM mutation with execution quiescence. Before changing host mappings or permissions, prevent new translated execution and drain existing runners and memory helpers. Define lock ordering explicitly, including helpers invoked from generated code.

### S32-R3-4 — Exec replaces memory while sibling guest threads remain alive

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/threads_exec.c:155`, `src/rt32/vm.c:749`

**Evidence & Root Cause:** Successful `execve` resets dispositions and replaces the shared guest window without terminating sibling guest threads. Those threads retain old PCs, stacks, and contexts and can resume against the new image. Additionally, `rt32_vm_reset_for_exec()` releases its VM lock before the window-wide `MAP_FIXED` operation and permission-table resets.

This is independently incorrect even after protecting individual DBT memory accesses: old guest threads must not survive successful exec.

**Concrete Fix:** After preparation succeeds, stop and retire all sibling guest threads before destroying the old image. Keep the replacement transaction protected through mapping and table publication, then resume only the exec caller.

### S32-R3-5 — Signal masks and alternate stacks are incorrectly process-global

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/syscalls_time.c:36`, `src/os/syscalls_sig.c:59`, `src/interp/interp_signal.c:513`

**Evidence & Root Cause:** `l2a_blocked` is shared mutable storage, and delivery combines it with each context’s mask. Blocking a signal in one guest thread therefore blocks it in unrelated threads. Its plain loads and stores also race.

Likewise, the single `sigalt` object shares the alternate-stack address and `onstack` state across all guest threads. Concurrent handlers can use another thread’s stack or incorrectly consider themselves already on an alternate stack. Atomic accesses do not correct this ownership error.

**Concrete Fix:** Store both mask and alternate-stack state in the guest thread context. Remove the global mask merge. Apply explicit clone inheritance and exec-reset rules to those context fields.

### S32-R3-6 — Ignored signals become default-action signals

**Severity:** High  
**Category:** BUG  
**Location:** `src/os/syscalls_sig.c:205`, `src/os/threads.c:151`

**Evidence & Root Cause:** Installing either `SIG_DFL` or `SIG_IGN` clears `sigact[sig].installed`. `sparc32_signal_get()` subsequently reports both as absent. The host handler responds by restoring `SIG_DFL` and re-raising the signal.

For example, a guest that ignores `SIGTERM` can still be terminated. Querying the disposition also loses `SIG_IGN`, because the query path returns handler zero when `installed` is false.

**Concrete Fix:** Represent default, ignored, and caught dispositions distinctly. Preserve and return `SIG_IGN`; discard ignored signals rather than re-raising them.

### S32-R3-7 — One host signal is delivered to every guest thread

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/threads.c:125`

**Evidence & Root Cause:** `sparc32_thr_note_signal()` sets the pending bit on every live context. Each context independently consumes that bit. A single process-directed signal can consequently invoke the guest handler multiple times. Thread-directed delivery also loses its target through this broadcast path.

**Concrete Fix:** Maintain separate process-pending and thread-pending signals. Let one eligible thread atomically claim a process-directed signal, and route thread-directed signals only to their target context.

### S32-R3-8 — Signal-action updates are atomic by field but not coherent

**Severity:** Medium  
**Category:** BUG  
**Location:** `src/os/syscalls_sig.c:90`, `src/os/syscalls_sig.c:212`

**Evidence & Root Cause:** Replacing an installed action writes its handler, restorer, flags, and mask independently while `installed` remains true. A concurrent reader can obtain the new handler with the old restorer or flags. The final release-store of `installed = 1` does not make earlier readers obtain a coherent snapshot.

This can construct a signal frame using incompatible action fields.

**Concrete Fix:** Serialize action updates and snapshots outside asynchronous host handlers. If asynchronous access remains necessary, publish an immutable action snapshot with safe lifetime management; avoid a retry loop that can deadlock when a signal interrupts its own writer.

### S32-R3-9 — Guest exec does not close close-on-exec descriptors

**Severity:** Medium  
**Category:** DEFECT  
**Location:** `src/os/threads_exec.c:42`, `src/os/threads_exec.c:155`

**Evidence & Root Cause:** The exec implementation explicitly leaves descriptors open. Guest open and pipe paths set host `FD_CLOEXEC`, but guest exec only reloads an image; it never performs host exec, so those flags are never acted upon.

Descriptors leak into the replacement guest image. A leaked pipe endpoint can also prevent EOF and hang another process.

**Concrete Fix:** Track guest-owned descriptors and close those marked close-on-exec when exec commits. Keep translator-owned backing and control descriptors separate from that sweep.

### S32-R3-10 — ELF overlap validation duplicates loader geometry

**Severity:** Low  
**Category:** DRY  
**Location:** `src/rt32/elf32.c:592`

**Evidence & Root Cause:** `elf_collect_spans()` reparses ELF headers and independently reproduces the program-header limit, load-bias decision, and page-span calculations already performed by `load_elf32_image()`. Its comment explicitly acknowledges that it mirrors the loader. Preparation now has multiple interpretations of the same image geometry that must remain synchronized.

**Concrete Fix:** Retain validated segment spans in `rt32_elf_plan_t`, or produce a single internal parsed-image representation used by overlap validation and commit. Keep this abstraction local to this repository.

The inspected source counts were within 900 lines, and the Makefile’s default C flags include the required strict warnings. This limited static review does not establish complete ISA/FPU correctness or runtime parity.

### Checklist

- [x] **S32-R3-1:** Make context reclamation safe against remote signal handlers.
- [x] **S32-R3-2:** Coordinate fork and rebuild child synchronization state.
- [x] **S32-R3-3:** Quiesce generated accesses before VM mutations.
- [x] **S32-R3-4:** Retire sibling threads before exec replaces memory.
- [x] **S32-R3-5:** Make signal masks and alternate stacks per-thread.
- [x] **S32-R3-6:** Preserve and honor ignored dispositions.
- [x] **S32-R3-7:** Route each signal to the appropriate recipient.
- [x] **S32-R3-8:** Publish coherent signal-action snapshots.
- [x] **S32-R3-9:** Implement guest close-on-exec handling.
- [x] **S32-R3-10:** Reuse validated ELF segment geometry.

---

## 6. `rvrt` (`dab0b91` → `b1b08af`) — 7 Round-3 Findings (`7 / 7` Resolved)

Reviewed `dab0b91` with six shell inspection turns. No builds, tests, containers, or QEMU were run. Findings below are static conclusions; the bounded review does not establish correctness of unexamined paths.

**RV-R3-1 — Dynamic-rounding slow path flushes uninitialized FPSR**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt_emit_fp.c:393`; `src/dbt_emit_fp.h:339`
- **Evidence & Root Cause:** The pre-instruction snapshot restores FPR cache metadata but omits `fpsr_dirty`. When the first FP instruction uses dynamic rounding, its guard branches before `emit_clear_fpsr()` executes. Emitting the fast path nevertheless sets `fpsr_dirty`, so the slow tail flushes host FPSR into guest `fcsr`. The trampoline does not clear FPSR on entry. Host or previous-block exception flags can therefore contaminate guest flags. The FPR snapshot repair itself is appropriate because the helper path exits.
- **Concrete Fix:** Preserve and restore FPSR initialization/dirty state at each slow-path branch point. Emit a flush only if that execution path has accumulated guest flags. Add a regression with nonzero host FPSR, clear guest flags, and an exact dynamic-rounding instruction with non-RNE `frm`.

**RV-R3-2 — Underflow correction erases earlier instructions’ sticky flags**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt_emit_fp.c:313`
- **Evidence & Root Cause:** FPSR accumulates flags across a block. `emit_uf_fix()` checks that cumulative UFC bit and clears it whenever the current multiplication produces a normal result. An earlier underflow-producing instruction followed by an ordinary static-RNE `FMUL.S` can consequently lose its required UF flag before block-exit accumulation.
- **Concrete Fix:** Preserve previously accumulated flags separately before correcting the current instruction’s flags, or flush and clear FPSR before the operation requiring correction. Test an underflowing operation followed by an exact normal multiplication in the same block.

**RV-R3-3 — Emitter rollback retains state from discarded instructions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt.c:294`
- **Evidence & Root Cause:** On overflow or `RV_DBT_EMIT_STOP_BEFORE`, compilation restores only the word count and exit-patch count. FPR dirty bits, register tags, boxing knowledge, FPSR state, and other emitter metadata remain modified by the discarded instruction. The subsequently generated exit flush can store a host register using the wrong guest tag or omit a necessary store.
- **Concrete Fix:** Snapshot all mutable emitter state before attempting an instruction and restore it when discarding that instruction. Reserve enough space for exit emission. Add a boundary regression with dirty FPRs and an instruction that exhausts the emission buffer.

**RV-R3-4 — VMA capacity exhaustion silently loses surviving mappings**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:162`; `src/vm/vm64.c:334`
- **Evidence & Root Cause:** Splitting an overlapping VMA drops its surviving tail when all 64 slots are occupied. The backing and page states remain, but inode association and protection metadata disappear. Separately, mapping functions modify backing and states before `vma_add()` can return `-ENOSPC`. Failed mappings can thus leave changed memory without matching metadata. These are provider-level defects; this review does not establish their reachability through the main runtime.
- **Concrete Fix:** Preflight and reserve all required VMA slots before changing backing or metadata. Return a capacity error without mutation, or grow the table. Test middle-range removal and mapping failure with a full table.

**RV-R3-5 — Large-page file mapping retains bytes beyond EOF**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:393`
- **Evidence & Root Cause:** The large-host-page fallback copies file contents into existing arena backing. When `pread` returns zero, it stops without clearing the remaining destination bytes, then marks every page `COW_CLEAN`. Replacing populated memory with a shorter file therefore retains old bytes in the partial EOF page; whole pages beyond EOF also lack the promised fault state.
- **Concrete Fix:** Initialize replacement backing, zero the partial EOF tail, and mark whole pages beyond EOF appropriately before publishing the mapping. Add a populated-arena-to-short-file replacement regression on a large-page host.

**RV-R3-6 — Subpage remapping can write into read-only host backing**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:128`; `src/vm/vm64.c:325`
- **Evidence & Root Cause:** `prepare_writable()` changes protection only when the requested address is host-page aligned. On a 16 KiB host, mapping a read-only range at an aligned address protects the encompassing host page. A subsequent 4 KiB anonymous remap at offset 4096 skips protection widening and executes `memset()` against that read-only page. The file-copy fallback has the same alignment assumption.
- **Concrete Fix:** Manage protection over enclosing host pages while retaining precise guest permissions in metadata. Propagate protection failures before touching memory. Test remapping each 4 KiB subpage of a read-only 16 KiB host page.

**RV-R3-7 — Source hygiene gate is absent from `make check`**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:8759`
- **Evidence & Root Cause:** `check-line-limits` exists as a standalone target but is not a prerequisite of `check`. Routine checks therefore do not enforce the newly stated line-count and textual-include rules.
- **Concrete Fix:** Add `check: check-line-limits`. The direct inspection found no first-party `.c`, `.h`, or `.S` files above 900 lines and no prohibited string calls or textual `.c` includes. The observed assembly `x18` use is a RISC-V guest fixture, not an AArch64 platform-register violation.

No additional DRY or YAGNI finding was established with sufficient evidence in this inspection budget.

- [x] **RV-R3-1:** Restore path-specific FPSR state for dynamic-rounding helpers.
- [x] **RV-R3-2:** Preserve prior sticky underflow flags.
- [x] **RV-R3-3:** Restore complete emitter state on rollback.
- [x] **RV-R3-4:** Make VMA capacity failures transactional.
- [x] **RV-R3-5:** Clear EOF tails and classify beyond-EOF pages.
- [x] **RV-R3-6:** Handle writable backing at host-page granularity.
- [x] **RV-R3-7:** Include source hygiene enforcement in `make check`.

---

## 7. `loongarch64rt` (`00ea803` → `0e3c4bd` → `1907d96`) — 7 Round-3 Findings (`7 / 7` Resolved)

Round 3 found **7 actionable defects** at `00ea803`. Review used six shell inspection turns; no builds, tests, Docker, or QEMU ran. Findings are static, not runtime-verified.

Inspected the five latest commits, Round-2 and post-fable diffs, mapping/DBT/thread/signal/backend paths, selected tests, and `Makefile`. `include/` is absent. Inspected `.c`, `.h`, and `.S` files stay below 900 lines; required compiler flags are present.

The suspected SMC hash-collision issue did **not** survive tracing: unmap invalidates the entire block-cache epoch, forcing surviving blocks to be translated and marked again. It is excluded below.

### LA64-R3-1 — Thread signal state is process-global

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:51`
- **Evidence & Root Cause:** `sf_blocked`, `sf_pending`, pending metadata, and alternate-stack state are global variables. `la64_sigprocmask_sys()` ignores `ctx` and changes the shared mask. Consequently, one guest thread blocking a signal changes delivery for every thread; installing an alternate stack changes where other threads receive handlers. Cooperative scheduling does not correct this state ownership error.
- **Concrete Fix:** Put masks, thread-directed pending signals, and alternate-stack state in per-thread guest state. Keep shared dispositions separate. Implement clone inheritance explicitly, including alternate-stack clearing where required by clone flags. Add a two-thread regression with different masks and alternate stacks.

### LA64-R3-2 — Shared mapping fallback silently becomes a private snapshot

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:267`; `src/os/syscalls_mem.c:170`
- **Evidence & Root Cause:** The shared-map fallback calls `map_bytes_in_place()`, which populates anonymous arena backing with `pread`. The outside-arena route likewise allocates anonymous memory and copies file bytes. Recording `shared = 1` does not make these bytes shared with the file or another mapping. The comment promises synchronization on `msync/write/ftruncate/munmap`, but the inspected implementation contains no corresponding `pwrite` writeback. On Darwin, valid 4 KiB mappings that do not satisfy host-page alignment reach this fallback.
- **Concrete Fix:** Implement coherent shared backing for these placements, including alias visibility and file synchronization. Until supported, fail unsupported placements explicitly instead of returning successful `MAP_SHARED` mappings with private behavior. Test two aliases plus file reads after a mapped write.

### LA64-R3-3 — Failed file mapping leaves a live, untracked mapping

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:192`
- **Evidence & Root Cause:** `map_bytes_in_place()` commits `vm64_map()` before reading the file or registering the map. A later `pread` error, page-state failure, or full record table returns an error without undoing the mapping. The direct shared-overlay path also returns at line 264 without cleanup when `record_map()` fails. A failed guest `mmap` can therefore consume address space and leave accessible backing without its file record.
- **Concrete Fix:** Reserve bookkeeping capacity before publishing mappings and unwind every subsequent failure. Remove the VM mapping, restore arena backing after overlays, and release newly acquired resources. Add fault-injection coverage for read failure and record-table exhaustion.

### LA64-R3-4 — `mmap` skips essential argument validation

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_mem.c:212`
- **Evidence & Root Cause:** `file_backed` requires both absence of `MAP_ANONYMOUS` and `fd != -1`. Thus a non-anonymous mapping with `fd == -1` becomes an anonymous allocation instead of returning `EBADF`. The entry point also does not validate the mapping type or guest-page alignment of the file offset. Copy-based file mapping routes accept offsets that the guest ABI should reject. These checks must precede destructive `MAP_FIXED` replacement.
- **Concrete Fix:** Determine file-backed status solely from `MAP_ANONYMOUS`; validate the descriptor separately. Validate supported mapping types and offset alignment before selecting or removing mappings. Add cases for `fd == -1`, absent mapping type, and offset `1`.

### LA64-R3-5 — Duplicating an unread directory loses shared cursor identity

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/darwin_dir.h:160`
- **Evidence & Root Cause:** The post-fable change records a duplicate only when `oldfd` already has a cursor. For `open(directory); dup(fd); getdents64(fd); getdents64(duplicate)`, each descriptor later acquires a separate buffered `DIR *`. Although host duplicates share their underlying offset, their userspace buffers and pending entries are independent. Alternating reads can skip entries or report premature EOF. The full-table branch at line 184 similarly returns silently without recording an alias.
- **Concrete Fix:** Track descriptor alias groups independently of lazy `DIR *` allocation. Create one cursor on first enumeration and share it across all aliases. Propagate bookkeeping exhaustion rather than silently losing the relationship. Test duplication before and after enumeration with small output buffers.

### LA64-R3-6 — Signal action and alternate-stack calls overwrite aliased input

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigframe.c:447`; `src/os/sigframe.c:514`
- **Evidence & Root Cause:** Both `la64_sigaction_sys()` and `la64_sigaltstack_sys()` write the old-state output before reading the requested new state. If input and output point to the same guest buffer, the new request is overwritten and the old state is installed again. Partially overlapping buffers have the same problem.
- **Concrete Fix:** Copy the complete input structure into local storage before writing any output. Validate and apply that saved input in guest-kernel order. Add exact-alias and partial-overlap regressions for both syscalls.

### LA64-R3-7 — Alternate-stack disable and signal-return lifecycle are incomplete

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigframe.c:538`; `src/os/sigframe.c:370`
- **Evidence & Root Cause:** The `SS_DISABLE` branch bypasses the active-stack check, which exists only in the enabling branch at line 547. A handler can therefore disable its currently active alternate stack instead of receiving `EPERM`. Separately, delivery saves `uc_stack` at frame offsets 144–160, but `la64_sigreturn_sys()` never restores it; it restores registers, mask, and FP state only.
- **Concrete Fix:** Apply the active-stack restriction before either enabling or disabling the stack. Restore and validate the saved alternate-stack configuration during `rt_sigreturn`, respecting supported flag semantics. Test disabling from an alternate-stack handler and restoring a modified `uc_stack`.

### Checklist

- [x] **LA64-R3-1:** Separate per-thread signal state from shared dispositions.
- [x] **LA64-R3-2:** Preserve shared-file semantics in fallback mappings.
- [x] **LA64-R3-3:** Roll back failed file-map installation.
- [x] **LA64-R3-4:** Validate `mmap` descriptor, mapping type, and offset.
- [x] **LA64-R3-5:** Preserve directory cursor identity across early duplication.
- [x] **LA64-R3-6:** Snapshot signal syscall inputs before copyout.
- [x] **LA64-R3-7:** Correct alternate-stack disable and sigreturn behavior.

---

## 8. `ppc64rt` (`205054f` → `076461d` → `56bec31`) — 9 Round-3 Findings (`9 / 9` Resolved)

Found **8 correctness defects and 1 unused API** in the inspected code. Two defects are in the latest `mremap` changes.

Used exactly four shell inspection turns, including `git show HEAD~1 --stat` and `git show HEAD`. No Markdown files, builds, tests, Docker, or QEMU were read or run. Findings are static; runtime behavior remains unverified.

**P64-R3-1 — Partial `mremap` loses the moved region’s file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:330`
- **Evidence & Root Cause:** The first loop truncates every partially overlapping file record to the portion outside the source range. The second loop only relocates records still inside that range. Consequently, moving a prefix, suffix, or interior portion of a file mapping creates no file record at the destination. The final sweep then drops its relocated COW slots. This path is reachable: `syscall_mm_mremap()` accepts covered subranges with uniform attributes. Untracked destination pages subsequently take the dirty/private fallback in `ppc64_vm_file_cow_get()` and can bypass shared-write tracking.
- **Concrete Fix:** Split each affected record into surviving source fragments and a relocated intersection. Preserve the intersection’s inode, sharing mode, and adjusted file offset. Reserve metadata capacity before mutation and return an error through the existing rollback path if allocation fails.

**P64-R3-2 — Interior `mremap` creates an inverted right-hand file record**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:340`
- **Evidence & Root Cause:** For a record spanning both sides of the moved range, `m->gva_end` is first changed to `old_addr`. The right-hand record then copies this already-truncated record and sets its start to `old_end`, without restoring the original end. Its resulting interval is `[old_end, old_addr)`. The surviving right-hand guest mapping therefore loses valid file coverage even when a free metadata slot exists.
- **Concrete Fix:** Save the original record before modification. Construct the right fragment with its original end and adjusted offset. Preflight capacity so a full table cannot silently discard the right fragment.

**P64-R3-3 — `SS_AUTODISARM` can cause nested signals to overwrite the active frame**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:242`; `src/os/sigframe.c:480`
- **Evidence & Root Cause:** Signal delivery initializes `d.stack` to zero instead of saving the current alternate stack. It never disables an autodisarm stack after selecting it. Meanwhile, `ppc64_sigaltstack_onstack()` deliberately returns false for `SS_AUTODISARM`, so another `SA_ONSTACK` delivery selects the same stack top and can overwrite the first frame. `run_sig_restore()` also ignores the decoded `sout.stack`, preventing restoration of alternate-stack state.
- **Concrete Fix:** Save the current alternate-stack descriptor in the frame, disable autodisarm state after successful frame construction, and restore validated stack state on `rt_sigreturn`. Cover nested delivery and handler-driven stack replacement.

**P64-R3-4 — Idle scheduling fabricates timeouts and can terminate a live process**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:332`, `src/os/syscalls_p4.c:568`, `src/os/syscalls_p4.c:734`
- **Evidence & Root Cause:** `p4_check_futex_deadlines(..., true)` returns `ETIMEDOUT` to the earliest waiter without waiting for its deadline. The parent’s wait path likewise breaks when no child is schedulable and returns `ETIMEDOUT` merely because a timeout was supplied. After the main task exits, indefinitely waiting children cause the exit loop to break and report process completion despite remaining live tasks.
- **Concrete Fix:** Keep waiting tasks alive when the ready queue empties. Wait for an actual deadline or wake event, then recheck state. Compare remaining durations when selecting between realtime and monotonic deadlines; never expire a future deadline merely to make progress.

**P64-R3-5 — Signals cannot interrupt the main task’s futex wait**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:168`; `src/os/syscalls_p4.c:702`
- **Evidence & Root Cause:** Queuing a signal to the main task only sets `main_pending`. Child waiters receive an explicit READY/EINTR transition, but the main task has no equivalent. Its futex loop checks wake state, group exit, memory contents, and deadlines without checking pending signals. A child can send a handled signal to the blocked main task and continue running while the handler remains undelivered.
- **Concrete Fix:** Give the main task the same interruptible wait state as children, or explicitly check its deliverable pending signals in the wait loop and return `EINTR` before draining signal delivery.

**P64-R3-6 — Futex requeue omits the main waiter and misreports the result**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:794`
- **Evidence & Root Cause:** Requeue moves only entries in `s_tasks`; it never updates `s_parent_wait_addr`. If a child requeues the blocked main task, a subsequent wake at the destination cannot reach it. Additionally, line 813 returns `woken + reqd` only for `FUTEX_CMP_REQUEUE`; ordinary `FUTEX_REQUEUE` returns just `woken`, excluding successfully requeued waiters.
- **Concrete Fix:** Include the main waiter in requeue selection and accounting, respecting the wake and requeue limits. Return the number of awakened plus requeued waiters for both commands.

**P64-R3-7 — Valid large futex timeouts wrap into short or expired deadlines**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_p4.c:675`
- **Evidence & Root Cause:** The timespec validation rejects negative seconds and invalid nanoseconds, but `sec * 1000000000 + nsec` and `now_ns + dur_ns` use unchecked `uint64_t` arithmetic. Large valid positive durations can wrap and satisfy the immediately following expiration check.
- **Concrete Fix:** Use checked multiplication and addition, saturating large valid timeouts to the maximum supported deadline. Apply equivalent handling to absolute deadlines.

**P64-R3-8 — Installing an ignored disposition leaves stale child-pending signals**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/run/sigdeliver.c:138`
- **Evidence & Root Cause:** When a disposition becomes ignored, `run_sig_record()` clears only `run_sig_pending`. Pending bits stored in each child’s `sig_pending` remain. A blocked signal queued to a child can therefore survive a transition to `SIG_IGN`, then be delivered after a handler is reinstalled and the child unmasks it. Scheduler wake logic can also act on these stale bits.
- **Concrete Fix:** Add a scheduler helper that discards the signal from every task’s pending set and call it when installing an ignored disposition.

**P64-R3-9 — Obsolete VMA rollback API remains exposed**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/syscalls_mm.c:188`; `src/os/syscalls_mm_vma.h:58`
- **Evidence & Root Cause:** Searches across `src/` and `tests/` found no callers of `syscall_vma_snapshot()` or `syscall_vma_restore()`. Active rollback uses the full-table helpers. The obsolete restore implementation also retains the overlapping-fragment problem described by the replacement’s comment: it removes only the replacement interval before reinserting complete original spans.
- **Concrete Fix:** Remove the unused functions and declarations, retaining the full-table rollback API.

The static line-count scan found no `.c`, `.h`, or `.S` files over 900 lines in `src/` or `tests/`. The Makefile includes the requested warning flags. The targeted hygiene search found no prohibited string calls or `.c` includes; textual `x18` matches were comments. This does not establish correctness of encoded register operands or compiler acceptance.

Checklist:

- [x] **P64-R3-1:** Preserve relocated partial file mappings.
- [x] **P64-R3-2:** Preserve the right fragment’s original end.
- [x] **P64-R3-3:** Implement alternate-stack save, autodisarm, and restore.
- [x] **P64-R3-4:** Wait for real deadlines and preserve blocked live tasks.
- [x] **P64-R3-5:** Interrupt main-task futex waits for deliverable signals.
- [x] **P64-R3-6:** Requeue the main waiter and correct return counts.
- [x] **P64-R3-7:** Check timeout arithmetic.
- [x] **P64-R3-8:** Discard ignored signals from every task.
- [x] **P64-R3-9:** Remove obsolete VMA rollback helpers.

---

## 9. `mips64rt` (`45af6bf` → `385b31a` → `f7c6924`) — 6 Round-3 Findings (`6 / 6` Resolved)

Round 3 found **six actionable issues** at `45af6bf`, including an incomplete LL/SC fix and incorrect floating-point and vectored-I/O behavior.

This was a static review using five batched shell inspections, including `git log -n 5 --oneline`, recent commit diffs, source reads, and hygiene searches. No builds, tests, Docker containers, or QEMU ran. Findings below are source-derived, not runtime reproductions. The working tree was clean. No inspected `.c`, `.h`, or `.S` file exceeded 900 lines; `include/` does not exist in this checkout.

**M64-R3-1 — Syscall copyouts still race with LL/SC**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:147`, `src/os/syscalls.c:464`, `src/interp/unaligned.c:559`
- **Evidence & Root Cause:** `guest_range(..., write=1)` invalidates reservations before returning a writable pointer. Callers subsequently write without holding `sc_lock`. HEAD adds another `mips_llsc_note_write()` afterward, but neither notification serializes the intervening write with SC. A peer can perform LL after the first notification, observe an intervening same-value copyout, then successfully SC before the second notification. Host CAS cannot detect that intervening write when the bytes still equal the reserved value. The unlocked byte-wise `putn()` writes also permit interleaving with SC.
- **Concrete Fix:** Stage syscall output in host memory, then commit guest bytes and reservation invalidation together under `mips_llsc_write_lock()`. Reuse one repository-local copyout helper for these paths. Do not hold the lock across blocking host operations. Add a coordinated same-value-copyout/LL/SC regression.

**M64-R3-2 — Single-precision directed rounding loses small operands**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:607`, `src/interp/fp.c:305`, `src/interp/fp.c:196`
- **Evidence & Root Cause:** ADD.S/SUB.S treat a `long double` intermediate as exact. It is not exact for all binary32 operand exponent gaps, even with binary128 precision. For example, `1.0f + 0x1p-120f` rounds to `1.0` in the intermediate. `fp_adj_f()` therefore sees equality and skips correction; `fp_inexact()` also sees equality and omits Inexact. Under rounding toward positive infinity, the guest result should instead be `0x3f800001`, with Inexact set.
- **Concrete Fix:** Determine the exact residual sign for addition/subtraction using an error-free transformation or integer significand arithmetic. Use that residual for directed rounding and exception flags. Cover widely separated exponents under all four rounding modes.

**M64-R3-3 — Splitting vectored I/O changes syscall semantics**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_sync.c:239`, `src/os/syscalls_sync.c:307`
- **Evidence & Root Cause:** `mips_sc_vec()` splits a guest vector into separate host calls of at most 64 entries. A 65-entry `writev()` to a datagram socket becomes two datagrams. A corresponding `readv()` can consume separate messages or discard the first message’s remaining bytes. Splitting also loses the single-operation atomicity of small pipe writes and permits shared file-offset operations to interleave between chunks.
- **Concrete Fix:** Import the complete guest vector and issue one host vectored-I/O call. Use heap allocation for the descriptor array to preserve the no-VLA requirement. Apply the transfer-size limit to the aggregate request, not independently to each element.

**M64-R3-4 — Partial readv copyout returns the wrong byte count**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_sync.c:339`
- **Evidence & Root Cause:** After reacquiring the lease, the read path copies each vector entry and decrements `rem`. If a later destination is no longer writable, the error path returns only `total` from previous batches—or `EFAULT` when `total == 0`. Bytes already copied in the current batch are omitted. Thus a mapping change during the blocking read can produce a negative return despite successfully copying an earlier vector.
- **Concrete Fix:** Track bytes committed in the current operation. On a later copyout fault, return the committed count when nonzero; return `EFAULT` only when nothing was copied. Add a regression that invalidates a later destination while the read is blocked.

**M64-R3-5 — Obsolete double-rounding helper remains exported**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/interp/fp.c:284`, `src/interp/fp.h:56`
- **Evidence & Root Cause:** Repository search finds `fp_adj_d` only at its definition and declaration. The revised double-precision arithmetic uses `fp_round_d()` instead. The unused helper retains the old assumption that a `long double` intermediate supplies an exact value, making it a misleading alternative for future callers.
- **Concrete Fix:** Remove `fp_adj_d()` and its declaration.

**M64-R3-6 — Unaligned-access comments contradict the implementation**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `src/interp/unaligned.c:7`, `src/interp/unaligned.c:185`
- **Evidence & Root Cause:** The file header claims endian-natural spans and explicitly rejects QEMU’s little-endian swapped roles. The function-level comment and implementation instead use endian-dependent spans: LDL takes `pa..addr` on LE and `addr..pa+7` on BE. The header also claims the `(0,7)` pair round-trips on every variant, contradicting the later comment.
- **Concrete Fix:** Replace the historical header claims with the implemented endian-specific rules and correct load-pair offsets. Keep historical adjudication in the experiment notes.

Checklist:

- [x] **M64-R3-1:** Serialize syscall copyout and LL/SC invalidation.
- [x] **M64-R3-2:** Preserve exact residuals for single-precision rounding.
- [x] **M64-R3-3:** Preserve one-operation vectored-I/O semantics.
- [x] **M64-R3-4:** Return bytes already committed before a copyout fault.
- [x] **M64-R3-5:** Remove unused `fp_adj_d()`.
- [x] **M64-R3-6:** Correct contradictory unaligned-access comments.

---

## 10. `sparc64rt` (`001f2b1` → `b7c6514` → `5232650`) — 7 Round-3 Findings (`7 / 7` Resolved)

Found **7 actionable findings** at `001f2b1`. Inspection used **7 shell turns**, including `git log -n 5 --oneline`, `git show HEAD~1`, `git show HEAD`, targeted source reads, reference searches, and source line counts. No builds, tests, Docker, or QEMU ran; no files changed.

The findings below distinguish active guest-path defects from defects in currently unwired backend helpers. Static inspection does not establish full ISA/FPU or runtime correctness.

**S64-R3-1 — VM mutations do not invalidate sleeping threads’ DBT caches**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:578`; `src/os/guest_run_sysmem.c:640`; `src/os/threads.c:410`
- **Evidence & Root Cause:** VM preparation increments each peer’s `dbt_epoch`, but the repository contains no reader of that field. Mapping operations invalidate only `g->dbt`, while `run_dbt` explicitly keeps separate DBT instances per thread. After a futex wait reacquires the execution lock, only the register-window cache is invalidated. A thread can therefore resume cached code after another thread replaces, unmaps, or removes execute permission from its code pages.
- **Concrete Fix:** Connect a shared address-space code generation to every DBT instance. Check it upon lock reacquisition and before cached execution, flushing stale blocks and chaining entries. Validate with a thread that caches code, sleeps, and resumes after a peer changes that mapping.

**S64-R3-2 — File-backed `mremap` growth produces anonymous zero pages**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/mem_space.c:623`; `src/os/guest_run_sysmem_file.c:447`
- **Evidence & Root Cause:** Guest file `mmap` populates ordinary space pages through `sysmem_file_fill` and records file identity separately. Remap extends backing from `original->file`, which this population path does not attach. The registry update merely expands coverage and assigns chunk states; it does not load the corresponding file bytes or establish beyond-EOF BUS pages. Growing an 8 KiB mapping of a larger file therefore exposes zeros instead of the next file page.
- **Concrete Fix:** Preserve a retained file-backing object and offset on mapped pages. Grow through the file-population/EOF path, including beyond-EOF fault classification, before committing the remap.

**S64-R3-3 — File-range registry silently discards live mapping semantics**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/guest_run_sysmem_file.c:117`
- **Evidence & Root Cause:** `sysmem_file_note_map` selects `sysmem_file_next % 64` and overwrites that entry without checking whether it is live. The source explicitly acknowledges that eviction leaves stale readable bytes. After 65 live file mappings, truncating the first file can leave its mapping readable instead of producing the required beyond-EOF fault. Split handling also drops survivors when no slot is available.
- **Concrete Fix:** Store this metadata with live mappings or use a growable registry. If allocation fails, reject the operation before mutation; never silently remove correctness metadata for an existing mapping.

**S64-R3-4 — Darwin backend fixes remain disconnected from guest futex dispatch**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/os/threads.c:402`
- **Evidence & Root Cause:** The active futex wait path calls `thr_host_futex` only under `__linux__`; its Darwin branch assigns `-ENOSYS`. The newly repaired `rt_host_futex_wait_bitset`, wake, and requeue implementations have no callers outside their backend definitions. Consequently, the Round-2 Darwin futex repairs do not provide guest-thread synchronization on the standalone Darwin runtime.
- **Concrete Fix:** Route guest futex operations through the backend contract, including worker signal state, validated keys, and pinned backing lifetime. Exercise the actual guest dispatch path rather than testing backend helpers alone.

**S64-R3-5 — Darwin worker registration leaks slots across thread lifetimes**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin_sync.c:78`; `src/vm/vm64.c:710`
- **Evidence & Root Cause:** `darwin_worker_register` fills a fixed 256-entry table, but no path removes entries. `vm64_worker_unregister` even calls `rt_host_register_self` before clearing only the separate VM worker table. Once enough distinct thread IDs have accumulated, registration silently fails and `rt_host_preempt_worker` cannot locate new live workers.
- **Concrete Fix:** Add backend worker unregistration and invoke it during thread teardown. Propagate table exhaustion instead of reporting successful registration, and synchronize lookup with worker lifetime.

**S64-R3-6 — Directory-cache eviction loses unread entries**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin.c:456`
- **Evidence & Root Cause:** When all 32 directory slots are occupied, `rt_host_getdents64` closes slot zero’s `DIR *` and discards its pending entry. `readdir` may have buffered multiple entries while advancing the shared underlying descriptor offset. Recreating a stream from `dup(fd)` cannot recover that discarded buffer or pending entry, so interleaved pagination across 33 directories can skip entries.
- **Concrete Fix:** Retain streams until their associated open descriptions close, or reject new cache allocation without disturbing existing streams. Track duplicated descriptors through shared directory state.
- **Reachability:** This is a backend API defect; the inspected guest getdents path does not call this helper.

**S64-R3-7 — Wake-pipe sleep can return success before the requested deadline**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/backend_darwin_sync.c:496`
- **Evidence & Root Cause:** `rt_host_clock_nanosleep` floors fractional milliseconds, caps long waits at `INT_MAX` milliseconds, performs one `poll`, and treats its timeout as successful completion. It neither rounds the full duration upward nor checks the original deadline afterward. Long requests are shortened to the cap, and fractional requests can finish early.
- **Concrete Fix:** Maintain a validated deadline, round each bounded poll interval upward, and recompute remaining time until the deadline is reached. Preserve remaining-time reporting on interruption.
- **Reachability:** This helper currently has no guest-dispatch caller; the defect affects its backend contract.

The source line-count inspection found no `.c`, `.h`, or `.S` file under `src/`, `include/`, or `tests/` exceeding 900 lines. The targeted forbidden-construct search found no prohibited string functions or `.c` includes; textual `x18` matches were comments. These checks do not constitute compiler or emitted-instruction validation.

- [x] **S64-R3-1:** Connect peer VM changes to every thread’s DBT invalidation.
- [x] **S64-R3-2:** Preserve file contents and EOF semantics during remap growth.
- [x] **S64-R3-3:** Stop evicting live file-mapping metadata.
- [x] **S64-R3-4:** Wire Darwin futex helpers into guest dispatch.
- [x] **S64-R3-5:** Unregister Darwin workers and handle table exhaustion.
- [x] **S64-R3-6:** Preserve unread directory entries across cache pressure.
- [x] **S64-R3-7:** Wait until the requested sleep deadline.

---

## 11. `rt-series` (`37a9af0` → `4d36271` → `b4f5131`) — 6 Round-3 Findings (`6 / 6` Resolved)

**Round 3 verdict: changes required.** Six findings remain at `37a9af0`, including a path that credits host tests to foreign translators.

Reviewed recent history, the Round-2 and follow-up changes, shared headers, fixtures, Makefile, and relevant runners in six shell inspection turns. No builds, tests, containers, or QEMU were run. This repository has no `src/`; translator ISA, VM, and backend implementations therefore remain outside this audit’s verified scope.

**RTS-R3-1 — Weekly upstream checks can falsely qualify foreign translators**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:690`
- **Evidence & Root Cause:** Each foreign-architecture job executes plain `make -C "$UPSTREAM_CHECK_DIR" check`. Neither the selected translator nor a target-specific execution hook is passed. Success increments `GRIND_PASS` under `CURRENT_ARCH`. With `--arch all`, the same host check can produce ten architecture-labelled passes, even when translator-dependent suites skip.
- **Concrete Fix:** Require an explicit target-aware upstream test adapter for foreign jobs. Pass the selected engine, guest artifacts, and execution wrapper through that adapter. Without it, report SKIP; reserve unwrapped `make check` for `--arch host`.

**RTS-R3-2 — Grind bypasses the repaired RVRT host-policy selector**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/run_grind.sh:174`
- **Evidence & Root Cause:** The `hl` wrapper is constructed as `$_hl_bin $_interp_cmd` or `$_hl_bin $_dbt_cmd`, omitting `--rvrt-native`. HEAD repairs this selector in `rt_run_bounded_hl`, but grind never calls that helper. The inspected `hyper-linux/src/hl.c:854` selects RVRT policy from explicit RVRT launch state; ordinary invocation of an AArch64 translator does not itself establish that state.
- **Concrete Fix:** Route grind through a common executable wrapper that uses `rt_run_bounded_hl`, including its RVRT selector and guest environment. Avoid separately assembling a second `hl` command policy.

**RTS-R3-3 — Reservation probe does not isolate signal-return invalidation**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tests/p3_torture.c:217`
- **Evidence & Root Cause:** Every architecture branch places a libc `raise()` call between LL and SC. That interval also contains nested signal delivery and `atomic_store(&g_cas_cell, 2)` in `usr1_handler`. Library synchronization, handler atomics, and intervening execution can destroy the reservation independently of the signal-return behavior under review. The test accepts any SC failure and has no successful-reservation control, so an implementation that always fails SC also passes this probe.
- **Concrete Fix:** Separate this from the GPR/CAS fixture. Use a minimal dedicated handler and architecture-specific assembly around a controlled delivery boundary. Add a bounded no-signal control demonstrating successful LL/SC, and document precisely which boundary the interrupted case validates.

**RTS-R3-4 — TestFloat defaults to interpreter-only coverage**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `tools/run_grind.sh:373`
- **Evidence & Root Cause:** `_tf_wrap="${GRIND_INTERP:-${GRIND_DBT:-}}"` selects the interpreter whenever both default wrappers exist. Consequently, the TestFloat suite can pass without executing the DBT FPU implementation.
- **Concrete Fix:** Feed the same generated vectors to both configured engines and report their outcomes separately. Require both for dual-engine qualification; explicitly label any intentionally single-engine run.

**RTS-R3-5 — Uniform guest builder retains nonterminating signal traps**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `tools/build_uniform_guests.sh:52`
- **Evidence & Root Cause:** `trap cleanup_containers EXIT INT TERM` handles INT and TERM by cleaning containers and returning. It does not explicitly terminate the script, so interruption can resume the build sequence depending on the interrupted command’s status. Cleanup also suppresses removal errors, and its EXIT path does not perform the final lingering-container check. The corresponding benchmark trap was repaired in HEAD, leaving this duplicate behavior inconsistent.
- **Concrete Fix:** Add terminating INT/TERM handlers with exit codes 130/143. On EXIT, preserve the original failure status, verify owned-container removal, and turn cleanup failure into a nonzero result.

**RTS-R3-6 — Build recipes omit the requested general warning gate**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:9`
- **Evidence & Root Cause:** Default `CFLAGS` contain `-Werror=vla` but omit `-Werror`. The same omission appears in `tools/build_uniform_guests.sh:67` and benchmark compilation recipes. Warnings other than VLAs therefore do not fail these builds.
- **Concrete Fix:** Add `-Werror` to first-party host and guest compilation flags, keeping necessary architecture-specific exceptions narrow and explicit.

The inspected C/H files satisfy the 900-line limit; the largest is `tests/p3_torture.c` at 819 lines. The hygiene search found no banned string functions, unity `.c` includes, `_Generic`, `<threads.h>`, or explicit `x18`/`w18` references. These are static observations, not compilation evidence.

- [x] **RTS-R3-1:** Prevent host upstream checks from qualifying foreign translators.
- [x] **RTS-R3-2:** Preserve RVRT host policy in grind execution.
- [x] **RTS-R3-3:** Isolate reservation invalidation and add a successful control.
- [x] **RTS-R3-4:** Run TestFloat against both engines.
- [x] **RTS-R3-5:** Terminate builder signal traps and verify cleanup.
- [x] **RTS-R3-6:** Enforce general `-Werror` for first-party builds.

---

## Part VI — Round-2 Audit Archive (145 Items Resolved & Verified by `fable`)

> [!NOTE]
> All 145 Round-2 `gpt-6-astra` findings and 9 Round-2 cross-cutting clusters below were remediated across all 11 repositories, independently reviewed by `fable` (`claude-fable-5-1`, transcripts in `lode/reviews/2026-11-02-defects-r2-*-fable.md`), and followed up via `muse exec` commits (`a76285b`, `4a759c6`, `a86a161`, `2c2a62e`, `b40924b`, `dab0b91`, `00ea803`, `205054f`, `45af6bf`, `001f2b1`, `37a9af0`).

### 0.2 Round 2 Cross-Cutting Defect Clusters (Wave Planning Index)

- [x] **X-R2-1 — High — Darwin A2 Sub-Page Protection, Soft-TLB Synchronization & Signed-Load Tag Classification**
  - **Linked Items**: `A32-R2-2`, `A32-R2-3`, `A32-R2-4`, `A32-R2-13`, `I686-R2-1`, `I686-R2-2`, `I686-R2-3`, `M32-R2-8`, `P32-R2-8`, `S32-R2-13`, `LA64-R2-1`, `LA64-R2-3`
  - **Summary**: `a32rt` `LDRSB`/`LDRSH` checking write tags instead of read tags (`A32-R2-2`), `i686rt` pinned/widened host pages remaining open to sibling threads (`I686-R2-1`) and `smc_protect` widening `PROT_NONE` sub-pages to `PROT_READ` (`I686-R2-2`), `loongarch64rt` read misses restoring writable tags on code pages (`LA64-R2-1`) and `mprotect` committing guest metadata before host `mprotect` (`LA64-R2-3`), and unsynchronized C/JIT reads vs writes on Soft-TLB/permission tables (`A32-R2-13`, `P32-R2-8`, `S32-R2-13`).
- [x] **X-R2-2 — High — `MAP_SHARED`, `mremap` Owned FD Lifetime, Region Coalescing & Split Rollback**
  - **Linked Items**: `A32-R2-3`, `A32-R2-4`, `A32-R2-8`, `A32-R2-10`, `I686-R2-6`, `I686-R2-7`, `M32-R2-2`, `M32-R2-3`, `M32-R2-4`, `M32-R2-5`, `M32-R2-6`, `P32-R2-1`, `P32-R2-4`, `P32-R2-7`, `S32-R2-5`, `S32-R2-6`, `RV-R2-2`, `LA64-R2-4`
  - **Summary**: `mremap` storing borrowed guest fd numbers that break after `close()` or fd reuse (`I686-R2-6`, `P32-R2-1`), moving `MAP_SHARED | MAP_ANONYMOUS` losing shared identity across `fork()` (`A32-R2-8`, `P32-R2-4`, `S32-R2-6`), `sparc32rt` coalescing adjacent file mappings without checking backing identity (`S32-R2-5`), and `mips32rt` `mprotect`/`munmap`/`mmap` mutating host mappings before reserving region-split capacity (`M32-R2-4..6`).
- [x] **X-R2-3 — High — Code-Cache Rollover Quiescence, SMC Collision/Tracking & W^X Reopen Failures**
  - **Linked Items**: `A32-R2-1`, `I686-R2-4`, `I686-R2-5`, `S32-R2-1`, `S32-R2-2`, `M64-R2-3`, `S64-R2-3`
  - **Summary**: `a32rt` code-cache overflow resetting RX pages while other threads execute (`A32-R2-1`), `sparc32rt` `vpn & 4095` code-mask aliasing across 16 MiB boundaries (`S32-R2-1`) and partial-page invalidation clearing tracking for surviving blocks (`S32-R2-2`), `i686rt` stamping post-compile page generations without comparing pre-compile generations (`I686-R2-4`), `mips64rt` speculative delay-slot fetches faulting during compilation (`M64-R2-3`), and `sparc64rt` `dbt_flush_all` ignoring `a32h_wx_reopen` failure (`S64-R2-3`).
- [x] **X-R2-4 — High — Atomic / LL-SC Reservation Coherence, Lock Fault Safety & TSO Completeness**
  - **Linked Items**: `I686-R2-8`, `P32-R2-3`, `LA64-R2-2`, `P64-R2-5`, `P64-R2-6`, `M64-R2-1`
  - **Summary**: `ppc32rt` `STWCX` faulting while holding `g_ll_lock` and `siglongjmp`ing past unlock (`P32-R2-3`), `mips64rt` scalar stores modifying memory before acquiring `sc_lock` (`M64-R2-1`), `ppc64rt` ignoring per-context reservation tokens (`P64-R2-5`) and bypassing SMC/shared-file write hooks on atomic stores (`P64-R2-6`), `loongarch64rt` page-wide writable refill bypassing active reservations (`LA64-R2-2`), and `i686rt` TSO mode omitting string/SSE/interpreter fences (`I686-R2-8`).
- [x] **X-R2-5 — High — Signal Delivery, Frame Permission Checks, `sigsuspend` / `ppoll` Wakeup Races & Async-Signal-Safety**
  - **Linked Items**: `A32-R2-7`, `A32-R2-15`, `I686-R2-14`, `I686-R2-15`, `M32-R2-1`, `M32-R2-7`, `M32-R2-9`, `M32-R2-13`, `S32-R2-11`, `S32-R2-12`, `S32-R2-14`, `P64-R2-4`, `M64-R2-7`, `S64-R2-1`, `S64-R2-5`, `S64-R2-7`
  - **Summary**: `sparc64rt` `put_u64be` at `0x1d8` clobbering the saved `Y` register with `magic` at `0x1dc` (`S64-R2-1`) and locking `g_futex_mu` inside signal notification (`S64-R2-7`), `mips32rt` `sigreturn` advancing PC past an unexecuted `syscall` (`M32-R2-7`) and double-delivering FP delay-slot fetch faults (`M32-R2-1`), `sparc32rt` `sigsuspend` lost-wakeup window (`S32-R2-12`) and `%o0` overwrite (`S32-R2-11`), and unchecked signal-frame writes (`A32-R2-7`, `M32-R2-13`).
- [x] **X-R2-6 — High — Cooperative/Threaded Execution, Quiescence Leases, `fork` State & `execve` Staging**
  - **Linked Items**: `A32-R2-9`, `I686-R2-13`, `M32-R2-10`, `M32-R2-12`, `P32-R2-2`, `S32-R2-3`, `S32-R2-4`, `LA64-R2-5`, `P64-R2-1`, `P64-R2-2`, `P64-R2-3`, `P64-R2-8`, `P64-R2-10`, `P64-R2-11`, `M64-R2-2`, `M64-R2-4`, `M64-R2-8`, `S64-R2-4`, `S64-R2-6`, `S64-R2-8`, `S64-R2-9`
  - **Summary**: `ppc64rt` cooperative thread scheduling, `exit`/`exit_group` scope, `futex` deadlines, and per-task `clear_child_tid` (`P64-R2-1..3, 8`), `mips64rt` blocking syscalls holding quiescence leases (`M64-R2-2`), `fork` inheriting stale worker registry/locks (`M64-R2-4`), and premature slot publication (`M64-R2-8`), plus `sparc32rt` `execve` closing validated fds before teardown (`S32-R2-4`).
- [x] **X-R2-7 — High — ISA Decode, Delay-Slot, FP Rounding / Exception & DBT Lowering Bugs**
  - **Linked Items**: `A32-R2-5`, `A32-R2-6`, `A32-R2-11`, `A32-R2-12`, `A32-R2-14`, `I686-R2-9`, `I686-R2-10`, `I686-R2-11`, `I686-R2-12`, `P32-R2-5`, `P32-R2-6`, `S32-R2-7`, `S32-R2-8`, `S32-R2-9`, `S32-R2-10`, `RV-R2-1`, `P64-R2-7`, `P64-R2-9`, `M64-R2-5`, `M64-R2-6`, `S64-R2-2`
  - **Summary**: `rvrt` fused FP (`fmadd.d` etc.) overwriting dirty cache victims in `v16..v31` before spilling (`RV-R2-1`), `a32rt` Thumb-2 memory decode (`Rt` bitfield/width) and VFP fault swallowing (`A32-R2-5`, `A32-R2-6`), `i686rt` `REP` address-size count & 16-bit index preservation (`I686-R2-9`), `LODSB`/`LODSW` zero-extending `EAX` (`I686-R2-10`), and `MOVSS`/`MOVSD` memory loads preserving upper lanes (`I686-R2-11`), `ppc32rt` `OE=1` `subf`/`add` overflow (`P32-R2-5`) and divide-by-zero `OV` (`P32-R2-6`), `sparc32rt` `JMPL` delay-slot link order (`S32-R2-7`), and `sparc64rt` delay-slot syscall losing branch target (`S64-R2-2`).
- [x] **X-R2-8 — Low — Intra-Repo DRY & YAGNI Cleanup (Round 2)**
  - **Linked Items**: `A32-R2-16`, `A32-R2-17`, `I686-R2-16`, `M32-R2-14`, `M32-R2-15`, `S32-R2-15`, `S32-R2-16`, `RV-R2-3`, `LA64-R2-6`, `P64-R2-13`, `P64-R2-14`, `M64-R2-9`, `S64-R2-10`, `S64-R2-11`, `RTS-R2-16`, `RTS-R2-17`
- [x] **X-R2-9 — Medium — CLEAN Hygiene, `rvrt` `test/*.c` Unity Includes & `rt-series` Harness Qualification**
  - **Linked Items**: `A32-R2-18`, `I686-R2-17`, `I686-R2-18`, `M32-R2-11`, `M32-R2-16`, `P32-R2-9`, `S32-R2-17`, `RV-R2-4`, `RV-R2-5`, `LA64-R2-7`, `P64-R2-12`, `P64-R2-15`, `M64-R2-10`, `S64-R2-12`, `RTS-R2-1..RTS-R2-15`, `RTS-R2-18`

---

### R2-1. `a32rt` (`a5f53b4` → `d6e67c8` → `a76285b`) — 18 / 18 Resolved (`fable` Reviewed)

### 1.1 Bugs & Defects

#### High

- [x] **A32-R2-1 — High — BUG — Code-cache rollover reclaims blocks still executing**
  - **Where**: `src/vm/vm_jit_mem.c:108-149`, `src/vm/vm_jit_mem.c:198-214` (`a32_jit_reset_cache_locked`, `a32_jit_allocate_code_space_locked`); `src/dbt/dbt_jit_run.c:348-355` (`a32_jit_run`).
  - **What breaks / Why**: Allocation overflow resets the entire cache, changes its protection to RW on Linux, and immediately reuses its storage. Guest execution proceeds outside the JIT lock. Another thread can therefore be executing a block when its page loses execute permission or its instructions are overwritten. Publishing epoch zero cannot stop a block already executing, or protect a code pointer selected immediately before reset.
  - **Fix**: Retire cache generations and reclaim them only after every executing thread reaches a quiescent point. Alternatively, stop guest threads before reset. Protect the interval from selecting a block through completing its execution.

- [x] **A32-R2-2 — High — BUG — Signed loads use write permission checks**
  - **Where**: `src/core/core_emit_mem.c:167-182`, `src/core/core_emit_mem.c:224-241` (`emit_guest_mem`, `a64_emit_guest_ldrsb_w`, `a64_emit_guest_ldrsh_w`).
  - **What breaks / Why**: `is_store` is inferred solely from opcode bit 22. The signed-load opcodes `0x38A04800` and `0x78A04800` have that bit clear, so LDRSB/LDRSH consult the write tag. Valid signed loads from read-only pages fault; pages represented as writable but unreadable pass the wrong permission check. The site-recording code uses the same classification.
  - **Fix**: Pass access direction explicitly, or decode the complete load/store opcode field. Verify signed byte and halfword loads against read-only, write-only, and inaccessible guest pages.

- [x] **A32-R2-3 — High — BUG — Darwin shared-file mapping can overwrite adjacent guest mappings**
  - **Where**: `src/vm.c:570-607` (`vm_mmap2_locked`); `src/os/backend_darwin.c:116-142` (`a32_backend_map_file`).
  - **What breaks / Why**: The remediation replaces copied shared mappings with native `MAP_FIXED` file mappings. The allocator aligns a nonfixed shared-file mapping’s start to the host page size, but reserves/checks only its guest-rounded length. A 4 KiB mapping on a 16 KiB host occupies a complete host page and can replace neighboring 4 KiB guest mappings. Fixed guest addresses and file offsets are also accepted at 4 KiB alignment even when native mapping cannot represent them.
  - **Fix**: Validate the complete host-page footprint before native replacement. Implement a coherent subpage backing strategy, or explicitly reject layouts that cannot preserve neighboring mappings and file-offset semantics.

- [x] **A32-R2-4 — High — BUG — Darwin anonymous sharing changes neighboring mappings and survives private replacement**
  - **Where**: `src/os/backend_darwin.c:69-95` (`a32_backend_map_anon`).
  - **What breaks / Why**: The replacement path applies `VM_INHERIT_SHARE` to the entire covering host-page range. A 4 KiB shared guest allocation can consequently make adjacent private guest pages shared across fork. Replacing the allocation with a private mapping only clears bytes; it never restores private inheritance. The `minherit` result is also ignored, allowing success without the requested sharing semantics.
  - **Fix**: Track backing and inheritance at host-page granularity. Preserve neighboring private mappings, restore private semantics on replacement, and propagate inheritance failures. Reject unsupported mixed-sharing layouts until they are implemented correctly.

- [x] **A32-R2-5 — High — BUG — Thumb-2 memory interpreter decodes the wrong register and access width**
  - **Where**: `src/interp/interp_thumb.c:647-690` (`t32_step`).
  - **What breaks / Why**: These memory paths extract `Rt` from `hw2[11:8]` instead of `hw2[15:12]`, perform word accesses for byte-transfer encodings, and round effective addresses down to four-byte alignment. For example, an `F810` register-offset LDRB encoding enters the first path and executes an aligned word load into a register selected from offset/control bits. Successfully returning from this path silently corrupts state rather than invoking an unsupported-instruction fallback.
  - **Fix**: Decode each supported Thumb-2 memory format explicitly, including `Rt`, transfer width, register/immediate offset, and indexing controls. Preserve valid unaligned-access semantics; reject formats not yet implemented.

- [x] **A32-R2-6 — High — BUG — Thumb VFP memory faults are reported as successful instructions**
  - **Where**: `src/interp/interp_thumb.c:595-605` (`t32_step`); `src/interp/interp_vfp.c:99-118`, `src/interp/interp_vfp.c:738-749` (`mem_r`, `mem_w`, `a32_interp_vfp_step`); `src/interp/interp.c:194-213` (`a32_interp_step`).
  - **What breaks / Why**: VFP memory helpers set `ctx->exit_reason = A32_EXIT_FAULT`, and the VFP dispatcher returns `true` to indicate that it recognized the instruction. The Thumb caller treats that boolean as successful execution, advances PC, and returns `A32_EXIT_NONE`. The next step clears `exit_reason`. A faulting Thumb VLDR/VSTR can therefore be skipped without delivering its fault.
  - **Fix**: Separate “recognized” from execution status, or propagate `ctx->exit_reason` before advancing PC. Preserve the faulting PC and IT state.

- [x] **A32-R2-7 — High — BUG — Signal-frame construction bypasses guest write permissions**
  - **Where**: `src/signals.c:256-276` (`deliver_guest_signal`).
  - **What breaks / Why**: Frame construction checks only numeric address bounds, then directly clears and writes the frame. It never validates that the complete destination is mapped and writable. On A2, a guest-selected SP or alternate stack can overwrite guest read-only or inaccessible memory because the covering host page remains RW. On Linux, an invalid destination faults inside the translator’s signal-delivery path.
  - **Fix**: Validate the complete frame span through a signal-safe guest-memory mechanism before writing. Define controlled fatal-signal handling for an invalid signal stack without recursively faulting in the host handler.

- [x] **A32-R2-8 — High — BUG — Moving shared anonymous mappings loses their backing identity**
  - **Where**: `src/vm.c:779-784`, `src/vm.c:848-870` (`a32_vm_mremap`).
  - **What breaks / Why**: Only shared file mappings receive a backing-preserving remap path. Shared anonymous mappings allocate a new anonymous mapping, copy bytes, and unmap the old range. After fork, another process still references the original shared object while the moving process references a new one. Shared-memory communication and shared futex identity break despite both mappings retaining `MAP_SHARED` flags.
  - **Fix**: Preserve the existing backing object when moving shared anonymous mappings. Use native remapping where suitable, or maintain an explicit shared backing handle and remap that same object.

- [x] **A32-R2-9 — High — BUG — PR_SET_NAME retains the unchecked guest-string overread**
  - **Where**: `src/os/os_sys_fs_arm.c:423-434` (`ARM_NR_prctl`, `PR_SET_NAME`).
  - **What breaks / Why**: Only one byte is validated before `strnlen(src, 15)` and `memcpy` read the guest string. A nonterminated name at the end of a readable page crosses into unchecked memory. On Linux this can terminate the translator through the newly fatal outside-JIT fault path; on A2 it can read guest-inaccessible bytes.
  - **Fix**: Copy the bounded name through the checked guest-string helper and pass the resulting host buffer to `prctl`.

#### Medium

- [x] **A32-R2-10 — Medium — BUG — File-shrink invalidation does not establish durable EOF semantics**
  - **Where**: `src/vm/vm_file.c:294-334` (`vmfile_sync_size`); `src/vm/vm32.c:176-202`, `src/vm/vm32.c:205-227` (TLB invalidation/refill); `src/interp/interp.c:108-115` (`i_load_bytes`).
  - **What breaks / Why**: The remediation now translates file offsets into guest ranges, but only invalidates TLB tags. It leaves mapping permissions and staged bytes intact. Interpreter reads still pass region validation and access the stale anonymous storage; the C miss helper can refill from unchanged `g_prot`. Conversely, invalidating at least 512 pages clears **all** TLB tags, while emitted checks treat misses as guest faults, so unrelated valid DBT accesses can fault. Regrowth does not repopulate the discarded file tail.
  - **Fix**: Represent EOF validity independently of mapping permissions and enforce it consistently in interpreter and DBT accesses. Invalidate only affected translations, preserve unrelated full-coverage entries, and define backing refresh on regrowth.

- [x] **A32-R2-11 — Medium — BUG — Interpreter exits after successful GDB fault recovery**
  - **Where**: `src/interp/interp.c:255-260` (`a32_interp_run`); `src/gdb.c:585-613`, `src/gdb.c:662` (`a32_gdb_handle_stop`).
  - **What breaks / Why**: The new fault branch returns `128 + SIGSEGV` when `a32_gdb_handle_stop` returns zero. Zero is its normal result after continue or step. Thus a debugger can repair state and request continuation, only for the interpreter to exit. The adjacent BKPT path uses the opposite success test.
  - **Fix**: Continue execution on zero and terminate on a failed debugger interaction. Apply the same return convention to the existing UNDEF branch.

- [x] **A32-R2-12 — Medium — BUG — Interpreter floating-point operations ignore guest FPSCR control and exceptions**
  - **Where**: `src/interp/interp_vfp.c:201-204`, `src/interp/interp_vfp.c:489-519`, `src/interp/interp_vfp.c:525-559` (`vfp_mcr_mrc`, `vfp_cdp`).
  - **What breaks / Why**: VMSR updates only `ctx->fpscr`. Arithmetic and `nearbyint` use the host floating-point environment without applying the guest rounding mode, and arithmetic does not collect exception flags into guest FPSCR. For example, changing guest rounding before VCVTR does not control `nearbyint`, and floating-point division by zero does not update the guest cumulative divide-by-zero flag.
  - **Fix**: Implement explicit guest floating-point environment handling, including rounding and cumulative exceptions, with host state saved/restored. Ensure compiler floating-point settings preserve the required semantics.

### 1.2 Curated C11 & UB Issues

- [x] **A32-R2-13 — High — C11 — Shared Soft-TLB state has unsynchronized readers and writers**
  - **Where**: `src/vm/vm32.c:21-26`, `src/vm/vm32.c:145-170`, `src/vm/vm32.c:186-224`, `src/vm/vm32.c:268-302` (`g_tlb`, `g_prot`, probe/fill/invalidation/sync).
  - **What breaks / Why**: Global tags, addends, and permission bytes are ordinary objects. Mapping changes write them while other guest threads can read them through C helpers or emitted loads. Writer-side VM locking does not synchronize those readers. C helper accesses can race, and generated accesses have no coherent publication protocol for a tag/addend pair or permission revocation.
  - **Fix**: Define a reader/writer protocol covering both C and generated code. Use appropriate atomic publication and access ordering, together with a mechanism that prevents guest execution from racing backing replacement or revocation.

- [x] **A32-R2-14 — Medium — C11 — Thumb effective-address arithmetic still overflows signed integers**
  - **Where**: `src/interp/interp_thumb.c:651-656`, `src/interp/interp_thumb.c:669-677` (`t32_step`).
  - **What breaks / Why**: Effective addresses use `(int32_t)base + off`. A base near `INT32_MAX` plus a positive offset overflows signed `int32_t`; casting the result to `uint32_t` afterward does not repair the UB. Guest address arithmetic requires modulo-32-bit behavior.
  - **Fix**: Construct offsets as unsigned bit patterns and perform the addition in `uint32_t`, alongside correcting the memory decoder.

- [x] **A32-R2-15 — Medium — C11 — Synchronous signal handler calls async-signal-unsafe stdio**
  - **Where**: `src/signals.c:460-463` (`host_sig_handler`).
  - **What breaks / Why**: The host signal handler calls `fprintf` before `_exit`. Stdio is not async-signal-safe and can access interrupted or concurrently locked libc state. The fatal path therefore cannot reliably guarantee termination.
  - **Fix**: Use a fixed diagnostic through an async-signal-safe operation, or defer formatting to normal execution after safely escaping the translated block.

### 1.3 DRY — Intra-Repo Duplication

- [x] **A32-R2-16 — Low — DRY — Duplicate interpreter memory helpers have divergent reservation behavior**
  - **Where**: `src/interp/interp.c:108-137` (`i_load_bytes`, `i_store_bytes`); `src/interp/interp_vfp.c:99-118` (`mem_r`, `mem_w`).
  - **What breaks / Why**: Both implement guest range validation, fault recording, and copying. The integer store helper additionally invalidates exclusive reservations; the VFP helper does not. This is already semantic drift: a VFP store touching a reserved location can leave interpreter reservation bookkeeping valid.
  - **Fix**: Route VFP accesses through the existing internal interpreter memory helpers, preserving one implementation of permission checks, fault state, and reservation invalidation within a32rt.

### 1.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **A32-R2-17 — Low — YAGNI — File generation counters are maintained but never consumed**
  - **Where**: `src/vm/vm_file.c:38-59`, `src/vm/vm_file.c:100-105`, `src/vm/vm_file.c:299-307` (`resize_seq`, inode `code_generation`, `g_code_generation`).
  - **What breaks / Why**: Repository searches found initialization and updates, but no consumer of the per-inode sequence or generation fields. Incrementing them does not invalidate compiled code or make staged mappings coherent, despite comments suggesting generation-based coordination.
  - **Fix**: Remove the unused counters, or connect them to a concrete invalidation protocol as part of fixing file-backed mapping coherence. Do not retain them as apparent correctness machinery.

### 1.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **A32-R2-18 — Low — CLEAN — A2 protection documentation contradicts backend behavior**
  - **Where**: `src/vm/vm32.c:310-316` (`a32_vm32_protect` contract); `src/os/backend_darwin.c:153-165` (`a32_backend_protect`).
  - **What breaks / Why**: The VM comment promises faithful unioned permissions, including execute permission, and says sibling permissions are not widened. The Darwin backend explicitly ignores the requested protection on large-page hosts and makes the entire covering range RW. This obscures the fact that correctness depends entirely on software checks for guest permissions.
  - **Fix**: Document the actual host-backing policy and the software enforcement boundary. Keep claims about permission preservation aligned with the implemented mechanism.

**Verification limits:** These are source-supported findings, not reproduced failures. No runtime evidence establishes their frequency or confirms remediation. The seven-turn budget and truncated outputs leave additional ISA, syscall, AOT relocation, signal-state recovery, and test coverage unverified. All proposed consolidation is internal to a32rt; no cross-repository runtime library is proposed.

---

### R2-2. `i686rt` (`8db8727` → `a870267` → `4a759c6`) — 18 / 18 Resolved (`fable` Reviewed)

### 2.1 Bugs & Defects

#### High

- [x] **I686-R2-1 — High — BUG — Temporary and pinned permissions remain visible to other guest threads**
  - **Where**: `src/vm/vm32.c:144-173`, `src/vm/vm32.c:176-211` (`i686_vm32_widen_prot`, `i686_vm32_pin_page`); `src/os/sys_pass.c:260-308` (`sys_futex`).
  - **What breaks / Why**: Pinning applies the union of all sub-page permissions, releases the mutex, and retains that protection throughout a potentially blocking futex operation. `widen_prot` deliberately preserves union permissions for pinned pages. Another guest thread can consequently read a `PROT_NONE` neighbor or write a read-only neighbor without faulting. Temporary emulation/copy windows have the same problem: ordinary guest accesses do not acquire the sub-page mutex. Round-1 I686-1 therefore remains unresolved.
  - **Fix**: Enforce permissions on every guest access to mixed-permission host pages, or coordinate all guest execution while permissions are widened. Use a futex design that does not expose protected neighbors for the duration of a wait.

- [x] **I686-R2-2 — High — BUG — SMC protection grants read access to inaccessible neighbors**
  - **Where**: `src/dbt/engine_smc.c:135-152` (`smc_protect`).
  - **What breaks / Why**: Compiling code unconditionally applies `PROT_READ` to its entire host page. On A2, that host page can contain unmapped or `PROT_NONE` 4 KiB neighbors. The operation overrides the restrictive intersection established by the remediation, making those neighbors readable. This bypass exists even with one guest thread.
  - **Fix**: Derive SMC protection from current guest permissions. Remove write permission from the effective restrictive cover without adding permissions to any sub-page.

- [x] **I686-R2-3 — High — BUG — Decode and REP recovery can escape while holding the sub-page mutex**
  - **Where**: `src/os/signals_subpage.c:137-167` (`safe_decode_eip`); `src/os/signals_subpage.c:658-680`, `src/os/signals_subpage.c:744-770` (`emulate_rep_string`, `i686_spurious_emulate`); `src/x86/decode.c:76-80` (`fetch8`).
  - **What breaks / Why**: `safe_decode_eip` locks and widens memory before calling the raw decoder without an inner fault checkpoint. Its `max_len` restriction is checked only after decoding, so an instruction requiring an inaccessible following page can fault first. The REP branch likewise executes before the cleanup checkpoint used by the non-REP branch. A host fault can jump to the outer engine checkpoint, skipping protection restoration and mutex unlock. Subsequent recovery can deadlock on the same mutex.
  - **Fix**: Install cleanup checkpoints before every fault-capable operation under the mutex, including decoding and REP stepping. Decode from a bounded validated byte buffer, and restore every opened cover on all exits.

- [x] **I686-R2-4 — High — BUG — Translation publication accepts a generation changed during compilation**
  - **Where**: `src/dbt/engine.c:355-359`, `src/dbt/engine.c:397-441` (`dbt_get_or_compile`); `src/dbt/engine_smc.c:184-189` (`smc_drop_host`).
  - **What breaks / Why**: Compilation reads guest bytes, then reloads the page generation and stamps the completed translation with that newer value. It never compares the pre-compilation and post-compilation generations. A concurrent writer can invalidate and modify the source during translation; stale or mixed decoded bytes are then published as current. Installing SMC protection only after publication leaves another interval for an undetected write.
  - **Fix**: Establish source write tracking before decoding, retain the starting generation, and publish only if all source-page generations remain unchanged under a protocol synchronized with writers. Otherwise discard and retry.

- [x] **I686-R2-5 — High — BUG — Fault permission lookup trusts stale thread-local mappings**
  - **Where**: `src/interp/interp.c:211-239` (`i686_fault_region_prot`); `src/dbt/engine_smc.c:305-318` (`i686_dbt_smc_write_fault`); `src/rt32/rt32_vm_mmap.c:177-192` (`rt32_vm_mprotect`).
  - **What breaks / Why**: Region lookup refreshes a cloned thread’s snapshot only when the address is absent. A snapshot containing the address with obsolete permissions returns immediately. After another thread changes an existing mapping from RW to read-only, an SMC fault can therefore consult stale RW permissions. On A1, the subsequent SMC unprotection can restore write access using that same stale snapshot.
  - **Fix**: Version mapping snapshots and refresh them before permission decisions whenever the shared VM generation changes. SMC restoration must use authoritative current permissions.

- [x] **I686-R2-6 — High — BUG — mremap backing identity is a reusable descriptor number**
  - **Where**: `src/vm/vm_file.c:292-304`, `src/vm/vm_file.c:340-363` (`i686_vm_file_track_map`, `i686_vm_file_lookup_map`); `src/rt32/rt32_vm_mmap.c:284-290`, `src/rt32/rt32_vm_mmap.c:315-327`, `src/rt32/rt32_vm_mmap.c:359-367` (`rt32_vm_mremap`); `src/os/sys_pass_fs.c:501-504` (`i686_pass_r_close`).
  - **What breaks / Why**: Mapping metadata stores the caller’s descriptor without retaining an independent reference. Closing the descriptor leaves the mapping valid but makes later remapping use a closed descriptor—or a descriptor reused for a different file. Growth can fail incorrectly; relocation of a shared mapping can silently select another backing object. This defeats Round-1 I686-7’s backing-preservation fix.
  - **Fix**: Retain an owned backing-object reference for each mapping, with explicit lifetime management across splits and unmaps. Never reconstruct mapping identity from a guest-reusable descriptor number.

- [x] **I686-R2-8 — High — BUG — TSO repair omits string, SIMD, and interpreter fence paths**
  - **Where**: `src/dbt/emit_string.c:175-205` (`i686_emit_string`); `src/dbt/emit_sse.c:99-154` (`sse_emit_movx`); `src/interp/h_sse_int.c:633-638` (`h_sfence`).
  - **What breaks / Why**: Enabling `e->tso` repairs selected scalar emitters, but string and SIMD memory operations still emit ordinary loads/stores without corresponding ordering barriers. For example, successive STOS stores or SIMD stores remain reorderable on AArch64. Interpreter SFENCE still only advances EIP. Mixed DBT/interpreter execution therefore does not consistently provide x86 ordering after cloning.
  - **Fix**: Apply the ordering policy to every guest-memory lowering family and the interpreter fallback. Implement interpreter fence semantics and verify ordering across transitions between engines.

- [x] **I686-R2-9 — High — BUG — REP count uses operand size and 16-bit indices lose upper halves**
  - **Where**: `src/interp/h_string.c:104-131` (`str_bump`, `rep_count_get`, `rep_count_dec`); `src/os/signals_subpage.c:337-340`, `src/os/signals_subpage.c:595-599`, `src/os/signals_subpage.c:658-676` (REP classification and emulation).
  - **What breaks / Why**: REP selects CX versus ECX using `pfx_opsize`; the selection must follow address size. Thus `66 F3 A5` incorrectly truncates the count, while `67 F3 A4` incorrectly uses full ECX. Separately, 16-bit SI/DI updates clear the upper halves of ESI/EDI. The newly added sub-page emulator repeats the count error.
  - **Fix**: Select count width using `pfx_addrsize`, preserve upper halves when updating CX/SI/DI, and share those semantics between normal interpretation and fault recovery.

#### Medium

- [x] **I686-R2-7 — Medium — BUG — Partial unmapping discards backing metadata for the surviving suffix**
  - **Where**: `src/vm/vm_file.c:310-336` (`i686_vm_file_untrack_map`); `src/rt32/rt32_vm_mmap.c:287-290`, `src/rt32/rt32_vm_mmap.c:315-320` (`rt32_vm_mremap`).
  - **What breaks / Why**: When an unmapped interval lies strictly inside a tracked mapping, the final branch retains only the prefix. The still-mapped suffix loses its backing record. A later mremap of that suffix fails lookup and falls back to anonymous backing, losing file/shared semantics.
  - **Fix**: Split the record into prefix and suffix, adjusting the suffix file offset. Reserve metadata capacity before committing the VM change and propagate allocation/capacity failures.

- [x] **I686-R2-10 — Medium — BUG — DBT LODSB and LODSW clear upper EAX bits**
  - **Where**: `src/dbt/emit_string.c:208-220` (`i686_emit_string`, LODS cases).
  - **What breaks / Why**: LODSB and LODSW load directly into the AArch64 register holding EAX. LDRB/LDRH zero-extend, whereas x86 updates only AL/AX. With EAX=`0x12345678` and a source byte of `0xAA`, LODSB produces `0x000000AA` instead of `0x123456AA`.
  - **Fix**: Load into a scratch register and merge the low 8 or 16 bits into EAX. Correct the accompanying comment claiming zero-extension matches x86 register writes.

- [x] **I686-R2-11 — Medium — BUG — Scalar SSE memory loads preserve lanes that must be cleared**
  - **Where**: `src/dbt/emit_sse.c:95-114` (`sse_emit_movx`).
  - **What breaks / Why**: MOVSS/MOVSD loads use the same upper-preserving destination helpers for register and memory sources. Legacy MOVSS from memory must clear destination bits 127:32; MOVSD from memory must clear bits 127:64. The emitted memory-load paths retain the previous upper lanes.
  - **Fix**: Distinguish memory sources from register sources when committing the destination. Use zeroing destination writes for memory loads and preserving writes for register copies.

- [x] **I686-R2-12 — Medium — BUG — DBT string comparisons leave PF and AF unchanged**
  - **Where**: `src/dbt/emit_string.c:132-153` (`l3s_store_flags`); `src/dbt/emit_string.c:223-233` (`CMPS` lowering).
  - **What breaks / Why**: The comparison helper explicitly updates only CF, ZF, SF, and OF, leaving PF and AF unchanged. CMPS and SCAS define both flags from subtraction. Subsequent parity branches, LAHF, PUSHF, or signal-state inspection can observe incorrect flags.
  - **Fix**: Compute all defined subtraction flags, preferably through an existing i686rt-local flag implementation. Keep the eager result and lazy-flag state consistent.

- [x] **I686-R2-13 — Medium — BUG — Guest-copy wrappers discard recoverable EFAULT results**
  - **Where**: `src/os/marshal.c:98-131` (`s_copy_tolerant`); `src/os/marshal.c:161-194` (`i686_copy_from_guest`, `i686_copy_to_guest`).
  - **What breaks / Why**: The inner copy helper returns `-EFAULT` when it catches a fault without an outer checkpoint. Both public wrappers ignore that return and report success. Callers can consume incomplete or uninitialized destination data, or believe an unsuccessful guest write completed. This matters especially for thread setup/teardown paths outside an armed engine checkpoint.
  - **Fix**: Return `s_copy_tolerant`’s status directly and audit callers that ignore copy failures.

### 2.2 Curated C11 & UB Issues

- [x] **I686-R2-14 — Medium — C11 — Cleanup reads an indeterminate array after longjmp**
  - **Where**: `src/os/marshal.c:93-137` (`s_copy_tolerant`, `opened`).
  - **What breaks / Why**: `opened` is a non-volatile automatic array modified after `sigsetjmp`. If a retried copy faults again, its contents are indeterminate after `siglongjmp`. Cleanup subsequently reads those contents to choose pages to re-protect. Marking `tries`, `locked`, and `healed` volatile does not preserve `opened`.
  - **Fix**: Store the cleanup journal in storage with a lifetime unaffected by setjmp/longjmp rules, such as a carefully scoped thread-local recovery record, or use appropriately volatile storage.

- [x] **I686-R2-15 — High — C11 — Synchronous signal handling can acquire an interrupted VM lock**
  - **Where**: `src/interp/interp.c:124-135` (`host_fault_handler`); `src/dbt/engine_smc.c:305-307` (`i686_dbt_smc_write_fault`); `src/interp/interp.c:233-234` (`i686_fault_region_prot`); `src/rt32/rt32_vm.c:718-726` (`rt32_vm_sync_ctx`).
  - **What breaks / Why**: The signal handler calls SMC recovery, which can refresh a cloned context by acquiring the global VM spinlock. A fault while that same thread holds the VM lock—for example during a guest-memory operation inside a VM update—can spin forever because the interrupted owner cannot resume. Signal recovery is therefore not restricted to signal-safe, nonblocking state handling.
  - **Fix**: Keep synchronous handlers to bounded state capture and redirection. Perform VM synchronization and substantive invalidation at a recovery point with explicit lock ownership and cleanup, or use an immutable signal-readable mapping snapshot.

The targeted scans found no direct banned string/number-conversion calls or textual `.c` includes in the inspected C sources. Textual x18 matches were comments; that does not prove reservation across every numeric register encoding.

### 2.3 DRY — Intra-Repo Duplication

- [x] **I686-R2-16 — Low — DRY — Recovery duplicates private decoder opcode numbers**
  - **Where**: `src/os/signals_subpage.c:40-53` (`SUBPAGE_OP7_*`); `src/x86/decode.c:70-73` (`I686_OP7_*`).
  - **What breaks / Why**: Recovery introduces a second manually maintained numeric opcode namespace, including the same 470–473 SSE assignments used by the decoder. A decoder change can silently make permission classification interpret an instruction as a different operation, width, or access direction.
  - **Fix**: Define these identifiers once in an i686rt-local decoder interface. Reuse them in recovery; do not introduce a cross-repository library.

### 2.4 YAGNI — Dead Code & Speculative Scaffolding

No additional YAGNI finding met the evidence threshold in this bounded pass. The remaining Soft-TLB descriptor and reserved context slot alone do not establish a defect: the context slot is explicitly documented as reserved.

### 2.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **I686-R2-17 — Medium — CLEAN — Test and fixture drivers lack required lifecycle bounds**
  - **Where**: `Makefile:300-303` (`test-u3`); `tools/build_fixture.sh:54-62` (fixture container).
  - **What breaks / Why**: The default test dependency executes its test binary without an explicit wall-clock deadline. The fixture builder launches Docker without a unique container identity, timeout, resource limits, or identity-based cleanup. A hung build or cancelled client can leave an uncontrolled container running; `--rm` does not stop it.
  - **Fix**: Add bounded execution to the test target. Give fixture containers task-owned identities, suitable CPU/memory limits, and cleanup traps that stop/remove and verify termination of only those containers.

- [x] **I686-R2-18 — Low — CLEAN — Comments retain claims contradicted by current implementations**
  - **Where**: `src/dbt/emit_atomic.c:122-125` (`em_atomic_site` comment); `src/interp/h_muldiv.c:156-166` (`h_imul3` comment).
  - **What breaks / Why**: Atomic-site documentation still says `e->tso` is never set, although the remediation enables it after cloning. IMUL documentation says `dest = dest * rm * imm`, while the implementation correctly computes `rm * imm`. These comments obscure precisely the semantics under review.
  - **Fix**: Describe the current TSO-independent atomic-site offset and the two-factor IMUL operation.

The source-file size repair is confirmed for the counted scope: **no `.c`, `.h`, or `.S` file in `src/`, `include/`, or `tests/` exceeds 900 lines**.

---

### R2-3. `mips32rt` (`366ca9b` → `d75013f` → `a86a161`) — 16 / 16 Resolved (`fable` Reviewed)

### 3.1 Bugs & Defects

#### High

- [x] **M32-R2-1 — High — BUG — FP delay-slot fetch failure can deliver the same fault twice**
  - **Where**: `src/interp/fp.c:818-829` (`fp_bc1`); `src/os/mem.c:204-228` (`mips_fault`); `src/os/signals.c:660-665` (`mips_raise_guest_code`)
  - **What breaks / Why**: The fetch-failure branch treats `exit_reason == MIPS32_EXIT_NONE` as a reason to raise another fault. Successful guest signal delivery deliberately clears that field. A delay-slot fetch fault already delivered to a handler therefore triggers another delivery, now from the handler context with delay-slot state cleared. This creates an extra frame, or terminates if `SA_RESETHAND` removed the handler.
  - **Fix**: Propagate the fetch failure without raising it again. Preserve the context installed by the memory fault path. Add a focused case with an inaccessible FP branch delay slot and a returning signal handler.

- [x] **M32-R2-2 — High — BUG — Darwin sub-page shared mappings remain independent snapshots**
  - **Where**: `src/rt32/vm_mmap.c:132-157` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:147-175` (`vm_writeback_darw_locked`)
  - **What breaks / Why**: The unaligned Darwin path still populates existing arena memory with `pread`. Setting `darw_sync` adds eventual writeback, not shared backing. Two mappings of the same file do not observe each other’s stores, and changes through file I/O are not reflected in existing snapshots. Writing back the entire snapshot can overwrite newer file contents with stale bytes.
  - **Fix**: Implement coherent backing and alias coordination for sub-page shared mappings. Until supported, reject such mappings explicitly rather than advertise `MAP_SHARED` semantics.

- [x] **M32-R2-3 — High — BUG — Darwin writeback occurs after the old mapping becomes inaccessible or is replaced**
  - **Where**: `src/rt32/vm_mmap.c:304-312` (`vm_munmap_locked`), `src/rt32/vm_mmap.c:144-155` and `194-199` (`vm_mmap2_ext_locked`); `src/rt32/vm.c:178-185` (`vm_remove_region_at`)
  - **What breaks / Why**: Unmapping first applies `PROT_NONE`, then removes metadata and attempts writeback. A sub-page-backed mapping spanning complete host pages can consequently produce `EFAULT` during `pwrite`; that error is discarded. Fixed replacement similarly installs or populates new bytes before removing the old region, so old-backing writeback can write replacement contents into the old file.
  - **Fix**: Complete checked writeback while the original bytes remain accessible, before protection changes or replacement. Propagate failures and preserve consistent mapping state.

- [x] **M32-R2-4 — High — BUG — mprotect capacity preflight disagrees with the mutation**
  - **Where**: `src/rt32/vm.c:353-368` (`vm_can_mprotect_regions_locked`), `src/rt32/vm.c:371-405` (`vm_mprotect_regions_locked`)
  - **What breaks / Why**: Preflight skips regions whose protection already equals the requested protection. The mutation does not skip them: it still splits partial overlaps and ignores insertion failures. With a full region table, a same-protection operation on the middle of a region passes preflight, truncates the original entry, and loses the unrecorded remainder.
  - **Fix**: Apply the same unchanged-protection condition in both passes. Check insertion results and guarantee all necessary entries before modifying any region.

- [x] **M32-R2-5 — High — BUG — munmap reports success when its metadata split fails**
  - **Where**: `src/rt32/vm.c:276-302` (`vm_unmap_regions_locked`); `src/rt32/vm_mmap.c:304-316` (`vm_munmap_locked`)
  - **What breaks / Why**: Removing the middle of a region requires another entry. If insertion fails after coalescing, the original region remains recorded across the hole. The host mapping has already changed, and `munmap` returns success. On Darwin, a sub-page hole may remain host-accessible and be accepted by stale software permissions.
  - **Fix**: Reserve split capacity before changing host mappings. Make metadata removal return an error, and leave both host and guest mapping state unchanged when the split cannot be represented.

- [x] **M32-R2-6 — High — BUG — mmap can return failure after replacing live memory**
  - **Where**: `src/rt32/vm_mmap.c:159-199` (`vm_mmap2_ext_locked`)
  - **What breaks / Why**: Host `MAP_FIXED` occurs before duplicating the backing descriptor and before ensuring region-table capacity. Descriptor exhaustion or metadata insertion failure returns an error after guest bytes or protections have already changed. The old metadata can remain associated with replacement memory.
  - **Fix**: Acquire backing descriptors and reserve metadata capacity before host mutation. Provide explicit rollback or a commit sequence that cannot fail after replacement.

- [x] **M32-R2-7 — High — BUG — Pending delivery after sigreturn can skip an unexecuted syscall**
  - **Where**: `src/os/signals.c:295-305` (`mips_signal_deliver_pending`), `src/os/signals.c:734-751` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Pending delivery fetches the instruction at the current PC and advances past it whenever it equals `syscall`. That helper also runs after restoring a signal frame. If the restored PC points to a syscall that has not executed, delivering another pending signal saves `PC + 4`, permanently skipping that syscall.
  - **Fix**: Pass an explicit resume PC or delivery-boundary reason. Advance the PC only in the syscall completion path that knows the instruction has executed; never infer completion from instruction bytes.

- [x] **M32-R2-8 — High — BUG — A2 private-file population writes through read-only mappings**
  - **Where**: `src/rt32/vm_mmap.c:117-128` and `180-190` (`vm_mmap2_ext_locked`); `src/vm/vm_file.c:65-78` (`mips32_file_populate_private`)
  - **What breaks / Why**: An aligned Darwin private file mapping is installed using its requested host protection, then populated again whenever the regime is A2. For `PROT_READ`, `pread` writes into read-only memory and fails with `EFAULT`. If EOF is encountered, the fallback `memset` can fault directly. Valid read-only mappings therefore fail after being installed.
  - **Fix**: Avoid repopulating an already established native file mapping. For copied backing, populate writable staging or arena memory before applying final protections, with rollback on failure.

#### Medium

- [x] **M32-R2-9 — Medium — BUG — Real-time pending signals are coalesced**
  - **Where**: `src/os/signals.c:262-271` (`mips_signal_pend`), `src/os/signals.c:281-291` (`mips_signal_deliver_pending`)
  - **What breaks / Why**: Pending state stores one bit and one code per signal number. Repeated blocked real-time signals overwrite the same slot and produce one delivery. This violates the repository’s required FIFO handling of duplicate signals in the 32–128 namespace.
  - **Fix**: Add bounded per-thread real-time queues preserving each delivery and its information. Keep bit-based coalescing for standard signals.

- [x] **M32-R2-10 — Medium — BUG — Syscall errno translation handles only ENOSYS**
  - **Where**: `src/os/syscalls.c:81-99` (`xerrno`, `mips_sc_ret`); `src/os/proc.c:72-87` (`proc_ret`)
  - **What breaks / Why**: Every host errno except `ENOSYS` passes through unchanged. MIPS has additional differences, including overflow and unsupported-operation errors; Darwin introduces further differences. Guests can receive an unrelated error number and choose the wrong recovery path.
  - **Fix**: Use one complete host-to-MIPS errno translation table, selected for the host platform, across all syscall return helpers.

- [x] **M32-R2-11 — Medium — DEFECT — Interpreter header edits do not trigger incremental rebuilding**
  - **Where**: `Makefile:36-37` (`SRCS`, `HDRS`), `Makefile:66-68` (object rule)
  - **What breaks / Why**: Interpreter sources enter `SRCS`, but `src/interp/*.h` is absent from `HDRS`. The object rule does not generate compiler dependency files. Editing decoder or FP declarations can leave existing interpreter and DBT objects stale.
  - **Fix**: Generate and include compiler dependency files, or at minimum include interpreter headers in the declared dependencies.

### 3.2 Curated C11 & UB Issues

- [x] **M32-R2-12 — High — C11 — Atomic generation counters do not protect root-context snapshots**
  - **Where**: `src/rt32/vm.c:110-131` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`), `src/rt32/vm.c:763-781` (`rt32_vm_sync_ctx`); `src/mips32rt.h:303-317` (`mips32_range_ok`)
  - **What breaks / Why**: A sibling VM operation directly writes the root context’s ordinary `regions`, `region_count`, and `vm_gen` fields. The root thread reads those fields without holding the VM lock. The atomic global generation neither makes those accesses atomic nor prevents concurrent modification during the region walk. This remains a C data race with potentially inconsistent permission decisions.
  - **Fix**: Stop writing another running thread’s snapshot. Refresh owner-thread snapshots under the VM lock, and protect every authoritative-region traversal with a consistent synchronization scheme.

- [x] **M32-R2-13 — High — C11 — Signal guest-memory access still races with VM mutation**
  - **Where**: `src/os/signals.c:352-375` (`mips_sc_rt_sigaction`), `src/os/signals.c:605-627` (`mips_raise_guest_code`), `src/os/signals.c:719-740` (`mips_rt_sigreturn`)
  - **What breaks / Why**: Signal paths check permissions, release any synchronization used by that check, then directly read or write guest pointers. A sibling can unmap or reprotect the range between validation and access. Frame construction uses raw `memset` and stores, so the translator can fault inside C rather than report a controlled guest-memory failure. The new lock-held copy helpers do not cover these paths.
  - **Fix**: Serialize frames and syscall structures into local buffers, then use the checked lock-held copy interfaces. Ensure complete range validation and copying occur under the same VM protection.

The targeted search found no direct banned string-function calls, `_Generic`, `<threads.h>`, or textual `.c` includes in the searched scope. This does not establish absence of every VLA, UB case, or encoded use of register 18.

### 3.3 DRY — Intra-Repo Duplication

- [x] **M32-R2-14 — Low — DRY — Guest argument and return helpers remain duplicated**
  - **Where**: `src/os/proc.c:72-118` (`proc_ret`, `proc_arg`); `src/os/signals.c:196-232` (`l4a_arg`, `l4a_ret`); `src/os/syscalls.c:89-118` and `124-145` (`mips_sc_ret`, copy helpers, `mips_sc_arg`)
  - **What breaks / Why**: Three implementations encode the same O32 access and return conventions. They have already diverged: the shared argument helper uses locked copies and endian decoding, while the process helper uses a checked-then-raw native-endian `memcpy`.
  - **Fix**: Consolidate these helpers inside `mips32rt`, retaining module-specific behavior only where required. Do not introduce a cross-repository runtime library.

### 3.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **M32-R2-15 — Low — YAGNI — COW state constants describe an unused state machine**
  - **Where**: `src/vm/vm32.h:89-93` (`MIPS32_PAGE_COW_CLEAN`, `MIPS32_PAGE_COW_DIRTY`)
  - **What breaks / Why**: The searched source contains these COW constants only as definitions; other matching mentions are comments. The population helper copies bytes, and the TLB miss helper installs tags without implementing the advertised clean-to-dirty state transition.
  - **Fix**: Remove unused state constants and speculative contracts, or implement the required state tracking with explicit consumers. Keep the documented contract aligned with the actual backing strategy.

### 3.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **M32-R2-16 — Low — CLEAN — File-backing comments claim nonexistent coherence machinery**
  - **Where**: `src/vm/vm_file.c:18-27`, `src/vm/vm_file.c:47-51`, and `src/vm/vm_file.c:95-101`
  - **What breaks / Why**: Comments claim family-shared backing, inode-keyed control state, resize generations, mutation hooks, and COW promotion. The implementation shown performs population and ordinary truncation without that machinery. These claims obscure the actual limitations identified above.
  - **Fix**: Replace the comments with the implemented behavior and explicit limitations. Track future coherence work in the existing backlog.

**File-size result:** No inventoried `.c`, `.h`, or `.S` exceeds 900 lines. `emit_int.c` is at 899 lines, `emit_fp.c` at 897, and interpreter `fp.c` at 893; these comply but leave little room for focused fixes.

---

### R2-4. `ppc32rt` (`abe6b0b` → `2ff47c1` → `2c2a62e`) — 9 / 9 Resolved (`fable` Reviewed)

### 4.1 Bugs & Defects

#### High

- [x] **P32-R2-1 — High — BUG — Remapping relies on a borrowed file descriptor**
  - **Where**: `src/rt32/ppc32_vm_regions.c:75-103` (`vm_insert_region_raw_ex`); `src/rt32/ppc32_vm.c:671-688`, `src/rt32/ppc32_vm.c:710-718`, `src/rt32/ppc32_vm.c:752-759` (`ppc32_vm_mremap`)
  - **What breaks / Why**: The remediation stores the supplied descriptor number directly in the region and later uses that number to recreate or extend its backing. A mapping must survive closing its original descriptor. After close, remapping can fail with `EBADF`; after descriptor reuse, it can map an unrelated file. In the A1 shared-file relocation path, copying is deliberately skipped, so a reused descriptor can replace the original contents outright. Numeric descriptor equality also does not establish stable backing identity for region coalescing.
  - **Fix**: Retain an owned backing object with a private duplicated descriptor and explicit lifetime management across region splits, merges, and unmaps. Use backing identity rather than the guest descriptor number. Cover close-before-remap and descriptor-reuse cases.

- [x] **P32-R2-2 — High — BUG — Futex pointer validation uses stale, unlocked region snapshots**
  - **Where**: `src/os/threads.c:58-83` (`thread_range_ok`, `thread_ld32be`); `src/os/threads.c:279-289` (`futex_get_timeout`); `src/rt32/ppc32_vm_regions.c:41-60` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`)
  - **What breaks / Why**: The new permission check reads `ctx->regions` without the VM lock. VM updates refresh the operating context and root context, not every existing child context. A child can therefore validate a timeout against stale mappings after another thread unmaps or protects that memory, then fault in the subsequent `memcpy`. Conversely, newly mapped valid memory can be rejected. Root-context readers can also race with another thread copying its region array. Even a fresh snapshot leaves a validation-to-copy race.
  - **Fix**: Validate against authoritative shared VM state and perform a fault-safe guest copy with a defined mapping-lifetime protocol. Do not use unlocked per-context snapshots as syscall memory authority.

- [x] **P32-R2-3 — High — BUG — A fault during conditional store permanently strands the reservation lock**
  - **Where**: `src/interp/interp.c:60-84` (`vm32_sc_attempt`); `src/interp/interp.c:721-730` (`PPC32_OP_STWCX`); `src/os/hostfault.c:65-85`, `src/os/hostfault.c:106-137` (`hf_handler`, `ppc32_hostfault_run`)
  - **What breaks / Why**: STWCX validates the address before entering `vm32_sc_attempt`, which holds `g_ll_lock` across the host compare-exchange. Another thread can unmap or revoke access after validation; the reservation lock does not protect VM mappings. If the compare-exchange faults, the host handler `siglongjmp`s past the unlock. Subsequent LWARX/STWCX operations spin forever on the stranded global lock. Mapping-generation checks cannot close the interval between their comparison and the actual memory access.
  - **Fix**: Give checked atomic accesses a mapping-lifetime guard and a fault-recovery protocol that cannot abandon held locks. Establish a consistent VM/reservation lock order and ensure every exceptional exit releases acquired guards.

- [x] **P32-R2-4 — High — BUG — Moving shared anonymous memory loses its original shared backing**
  - **Where**: `src/rt32/ppc32_vm.c:684-688`, `src/rt32/ppc32_vm.c:752-786` (`ppc32_vm_mremap`)
  - **What breaks / Why**: Anonymous mappings are moved by creating another anonymous mapping and copying bytes. For `MAP_SHARED | MAP_ANONYMOUS`, that creates a different shared object. After a fork, a parent that moves its mapping no longer shares subsequent writes with the child’s original mapping. Preserving `MAP_SHARED` in the flags does not preserve backing identity.
  - **Fix**: Move the existing backing with a supported host remap operation, or represent shared anonymous memory with an owned backing object that can be mapped again. Reject unsupported moves before mutation rather than silently breaking sharing.

#### Medium

- [x] **P32-R2-5 — Medium — BUG — Newly reachable overflow arithmetic computes incorrect XER flags**
  - **Where**: `src/interp/interp.c:214-232`, `src/interp/interp.c:239-270` (`interp_step`, ADD/SUBF families); `src/interp/interp.h:152-159` (`add_overflow`, `sub_overflow`)
  - **What breaks / Why**: The subtraction helper tests `((a ^ r) & (a ^ b))`, although its callers calculate `r = b - a`. Overflow must compare the result sign with the minuend `b`. For example, `a=0x80000000`, `b=0` produces an overflowing mathematical result but the helper clears OV. The addition path also folds carry into a truncated second operand: `addeo` with `a=0`, `b=0x7fffffff`, CA=1 produces `0x80000000` but reports no overflow. The decoder remediation makes these previously inaccessible OE paths executable.
  - **Fix**: Calculate the signed mathematical result in `int64_t`, including the original carry input and instruction-specific operands, then compare against `INT32_MIN..INT32_MAX`. Cover boundary cases with independent expected OV/SO values.

- [x] **P32-R2-6 — Medium — BUG — Overflow-enabled division clears OV on division by zero**
  - **Where**: `src/interp/interp.c:325-348` (`interp_step`, DIVW/DIVWU)
  - **What breaks / Why**: The overflow predicate recognizes only signed `INT32_MIN / -1`. A zero divisor therefore clears OV for both `divwo` and `divwuo`; unsigned division always supplies false. Division by zero must set the overflow indication when OE is enabled, irrespective of the undefined quotient value.
  - **Fix**: Include a zero divisor in both signed and unsigned overflow predicates, retaining the signed minimum/-1 case. Check OV, sticky SO, and record-form CR0 propagation separately from quotient behavior.

- [x] **P32-R2-7 — Medium — DEFECT — Remap commits success after ignoring protection and teardown failures**
  - **Where**: `src/rt32/ppc32_vm.c:778-795` (`ppc32_vm_mremap`)
  - **What breaks / Why**: Source-read permission changes, destination protection restoration, region recording, and source unmapping have discarded return values. A failed source permission change can lead directly to a host fault in `memcpy`. A failed destination protection change can leave the new mapping more permissive than requested while region metadata advertises the intended permissions. The function can subsequently return success despite failed bookkeeping or teardown.
  - **Fix**: Check each operation and make relocation transactional. Preserve enough original state to restore temporary source permissions and discard the destination on failure. Preflight region capacity and do not publish success until protections, metadata, and source removal agree.

#### Critical / Low

No additional findings established at these severities.

### 4.2 Curated C11 & UB Issues

- [x] **P32-R2-8 — High — C11 — Soft-TLB publication mixes atomic reads with ordinary concurrent writes**
  - **Where**: `src/vm/vm32_tlb.c:86-119` (`vm32_tlb_probe`); `src/vm/vm32_tlb.c:122-144` (`vm32_tlb_fill`); `src/vm/vm32_tlb.c:207-250` (invalidation)
  - **What breaks / Why**: Lock-free probes use atomic builtins to load tags, but writers assign the same tag fields normally under a lock that probes never acquire. The addend is also read and written ordinarily. Writer-only locking does not establish synchronization with readers; naturally aligned AArch64 loads do not remove C data-race UB. There is also no coherent tag/addend snapshot protocol.
  - **Fix**: Use synchronized access on both sides or a fully specified atomic publication protocol, including replacement and invalidation. If the addend is always the immutable Class-A guest base, remove it from mutable cache publication and document that invariant. Address mapping lifetime separately from metadata publication.

The textual scan found no calls to `sprintf`, `strcpy`, `strcat`, or `atoi`, and no textual `.c` includes. Literal `x18`/`w18` matches were comments. This does not certify dynamically encoded register operands or exclude every possible VLA.

### 4.3 DRY — Intra-Repo Duplication

No additional duplication finding established with sufficient evidence. Moving common pthread wrappers into `src/os/backend_common.c` addresses the previously identified duplication. No cross-repository library extraction is proposed.

### 4.4 YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding established with sufficient reference coverage. The remediation’s removal of signal scaffolding is reflected in the changed-file summary, but this inspection does not certify all remaining backend APIs as live.

### 4.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **P32-R2-9 — Low — CLEAN — Normal build flags omit the required general warnings-as-errors setting**
  - **Where**: `Makefile:25` (`CFLAGS`); `Makefile:72-78` (`build-darwin`)
  - **What breaks / Why**: Both normal build configurations include `-Werror=vla` but omit the project-required general `-Werror`. The separate syntax-check target supplies it, so normal builds and checks enforce different warning policies. Non-VLA diagnostics can therefore pass ordinary builds.
  - **Fix**: Add `-Werror` to both default build configurations. Keep any necessary platform-specific warning exceptions explicit and narrow.

All inventoried `.c`, `.h`, and `.S` files under `src/`, `include/`, and `tests/` are within 900 lines. The largest observed files are `src/os/threads.c` at 878 and `src/os/signals.c` at 861. These counts establish file-size compliance only; no runtime or compilation claims are made.

---

### R2-5. `sparc32rt` (`dad95da` → `a73ff14` → `b40924b`) — 17 / 17 Resolved (`fable` Reviewed)

### 5.1 Bugs & Defects

#### High

- [x] **S32-R2-1 — High — BUG — SMC mask collisions suppress required invalidation**
  - **Where**: `src/vm/vm32.c:276-292`, `src/vm/vm32.c:296-337` (`vm32_note_code_page`, `vm32_clear_code_range`, `vm32_range_has_code`)
  - **What breaks / Why**: The code-line mask indexes guest pages with `vpn & 4095`. Pages separated by 16 MiB share one mask. Clearing one page zeroes the shared mask even when another colliding page retains live translations and `RT_PAGE_HAS_CODE`. A subsequent short write to that other page returns false from `vm32_range_has_code`, leaving stale instructions cached. This is a new Round-1 remediation defect.
  - **Fix**: Use per-guest-page masks, or maintain collision-safe ownership/reference information. Clearing one page must never remove another page’s tracking bits.

- [x] **S32-R2-2 — High — BUG — Partial-range invalidation clears tracking for surviving blocks**
  - **Where**: `src/dbt/dbt_cache.c:297-317` (`sparc32_dbt_invalidate_range`)
  - **What breaks / Why**: Blocks are retired using the exact byte range, but any range at least 4096 bytes long clears code tracking on every rounded boundary page. For example, a copyout covering `[P+128, P+4224)` leaves a block at `P+32` valid while clearing its page’s code marker and enabling fast writes. Later modifications to that block bypass SMC invalidation.
  - **Fix**: Retire all blocks on every page whose code tracking is cleared, or preserve/recompute tracking for surviving blocks. Distinguish mapping invalidation from arbitrary byte writes.

- [x] **S32-R2-3 — High — BUG — Checked syscall copies still race with guest unmapping**
  - **Where**: `src/os/l2a_access.h:52-85`, `src/os/l2a_access.h:93-105` (`l2a_range_ok_prot`, `l2a_store`); `src/interp/interp_mem.c:76-111` (`interp_mem_rd`, `interp_mem_wr`)
  - **What breaks / Why**: Permission validation and host-memory access remain separate operations without mapping lifetime protection. Another `CLONE_VM` thread can unmap or revoke access after validation and before `memcpy`, causing a translator fault. On a large host page, the access can instead succeed against a guest subpage whose permission was revoked. Atomic permission loads do not close this gap. Round-1 S32-1 remains incomplete.
  - **Fix**: Introduce a coherent access/mapping synchronization contract: pin or lock mappings across short copies, and use suitable fault-safe or pinned handling for blocking operations.

- [x] **S32-R2-4 — High — BUG — Exec prevalidation still permits failure after destroying the old image**
  - **Where**: `src/os/threads_exec.c:158-179` (`sparc32_thr_execve`); `src/rt32/elf32.c:624-639`, `src/rt32/elf32.c:656-697` (`rt32_elf_validate`, `rt32_elf_load`)
  - **What breaks / Why**: Validation closes the executable and interpreter descriptors. Exec then resets dispositions and destroys the old VM before reopening and loading those paths. File replacement/removal, mapping failure, interpreter failure, or stack allocation failure can therefore return an error to a destroyed process image. Prevalidation reduces failures but does not make replacement transactional.
  - **Fix**: Retain validated descriptors and stage the complete image and stack before committing. After an unavoidable point of no return, terminate through an explicit exec-failure path rather than returning to the former program.

- [x] **S32-R2-5 — High — BUG — Region coalescing merges mappings of different files**
  - **Where**: `src/rt32/vm.c:219-240` (`vm_coalesce_regions_locked`); `src/rt32/vm_mmap.c:189-193` (`vm_mmap2_locked`)
  - **What breaks / Why**: `same_backing` checks only that both descriptors exist and their page offsets are consecutive. It never compares backing identity. File mappings also receive the same `"[mmap]"` name. Adjacent mappings of different files with matching protections and consecutive offsets can therefore merge; the second descriptor is closed and its identity lost. Subsequent remapping uses the first file for the combined region.
  - **Fix**: Track an explicit backing-object identity and coalesce only matching objects with contiguous offsets and compatible sharing semantics.

- [x] **S32-R2-6 — High — BUG — Remap reconstruction loses shared-anonymous identity and private COW history**
  - **Where**: `src/rt32/vm_mmap.c:469-510` (`rt32_vm_mremap`)
  - **What breaks / Why**: Relocation creates a new mapping and copies anonymous data. For `MAP_SHARED | MAP_ANONYMOUS`, this creates a different shared object, breaking sharing with a forked process retaining the original mapping. For private file mappings, copying only pages whose bytes differ from a fresh mapping also loses COW history: a previously dirtied page that currently equals the file becomes file-backed again and may observe later file changes.
  - **Fix**: Preserve the original backing object and private-page state during relocation. Use a suitable host remap or explicit backing/page ownership; reject unsupported cases instead of approximating identity with byte comparison.

- [x] **S32-R2-7 — High — BUG — JMPL delay slots observe the old link register**
  - **Where**: `src/interp/interp.c:586-592`, `src/interp/interp.c:626-630` (`interp_cti`); `src/dbt/emit_cti.c:316-332` (`sparc32_emit_jmpl`)
  - **What breaks / Why**: Both engines defer the JMPL destination-register write until after the delay instruction. JMPL writes its link before that instruction executes. A delay slot reading the destination, such as `%o7`, therefore sees the old value. A delay-slot write to that register is also overwritten by the delayed link commit. Agreement between these two implementations cannot establish correctness.
  - **Fix**: Compute and validate the target, commit the link, then execute the delay slot. Preserve the resulting architectural state on a delay-slot fault.

- [x] **S32-R2-12 — High — BUG — Sigsuspend has a lost-wakeup window**
  - **Where**: `src/os/threads_sig.c:72-107` (`sparc32_thr_rt_sigsuspend`)
  - **What breaks / Why**: The function scans software pending bits and then calls host `sigsuspend` without first blocking the relevant host signals. A signal arriving between the last scan and the syscall can run the host handler and set a pending bit, after which `sigsuspend` sleeps waiting for another signal. A single expected notification can hang the guest indefinitely.
  - **Fix**: Block host delivery before inspecting pending state, then atomically release that block while sleeping. Restore the prior host mask and keep guest-mask selection consistent.

#### Medium

- [x] **S32-R2-8 — Medium — BUG — NaN propagation can return a finite operand**
  - **Where**: `src/interp/fp_arith.c:136-153`, `src/interp/fp_arith.c:335-362` (`fp_f32_pick_nan`, `fp_f64_pick_nan`, `fp_f32_nan2`, `fp_f64_nan2`)
  - **What breaks / Why**: The payload-selection helper assumes both operands are NaNs, but callers invoke it when either operand is NaN. A finite operand with larger fraction bits wins. For example, single-precision inputs `0x7fc00000` and `0x3fffffff` select the finite second operand.
  - **Fix**: Return the sole NaN when exactly one operand is NaN. Apply payload arbitration only when both operands are NaNs, preserving signaling-NaN handling.

- [x] **S32-R2-9 — Medium — BUG — Nondefault FP rounding falls back to an interpreter that ignores it**
  - **Where**: `src/dbt/emit_fp.c:48-78` (`fp_guard_fast`); `src/interp/fp_arith.c:400-444` (`fp_add_f32`, `fp_add_f64`)
  - **What breaks / Why**: The DBT rejects nonzero `FSR.RD` and replays in the interpreter. Arithmetic helpers nevertheless use ordinary host arithmetic without applying guest rounding. With round-toward-positive-infinity, single-precision `1.0 + 2^-24` should produce the next representable value; default round-to-nearest produces `1.0`.
  - **Fix**: Implement guest rounding for arithmetic and square root, including exception flags. Ensure the fallback actually implements the modes rejected by the fast path.

- [x] **S32-R2-10 — Medium — BUG — Batched FPSR flags corrupt current-exception state**
  - **Where**: `src/dbt/emit_fp.c:320-338`, `src/dbt/emit_fp.c:385-393`, `src/dbt/emit_fp.c:447-453` (`fp_flags_commit`, `sparc32_emit_fp_flush`, `fp_emit_arith`)
  - **What breaks / Why**: Consecutive arithmetic instructions share cumulative host FPSR flags. The final commit writes that union to both accrued exceptions and current exceptions. After an inexact operation followed by an exact operation, guest `cexc` incorrectly retains inexact; only `aexc` should retain it.
  - **Fix**: Track each instruction’s current exceptions separately from accumulated exceptions. Any batching must preserve the last instruction’s `cexc`.

- [x] **S32-R2-11 — Medium — BUG — Sigsuspend overwrites the handler’s signal-number argument**
  - **Where**: `src/interp/interp_signal.c:491-503` (`interp_deliver_async_for_syscall`); `src/os/threads_sig.c:93-105` (`sparc32_thr_rt_sigsuspend`); `src/os/syscalls_min.c:781-789` (syscall return commit)
  - **What breaks / Why**: Delivery sets `%o0` to the signal number and redirects execution to the handler. Returning `-EINTR` then runs the ordinary syscall tail, which overwrites `%o0` with errno 4 before the handler starts. The handler receives the wrong signal number.
  - **Fix**: Store the interrupted syscall’s `EINTR` result in the saved frame and bypass ordinary return-register commit when delivery has redirected execution.

### 5.2 Curated C11 & UB Issues

- [x] **S32-R2-13 — High — C11 — Permission and code-state tables have unsynchronized accesses**
  - **Where**: `src/vm/vm32.c:74-82`, `src/vm/vm32.c:208-216`, `src/vm/vm32.c:290-313`; `src/interp/interp_mem.c:36-41`; `src/os/l2a_access.h:75-77`
  - **What breaks / Why**: VM updates and DBT code marking write ordinary bytes under different locks, while interpreter accesses read them without either lock. Some readers use atomic builtins, but writers remain non-atomic. Concurrent accesses are data races, and read-modify-write updates can lose permission or code-state changes.
  - **Fix**: Define one synchronization discipline for table publication and code-state updates. Use matching atomic operations where lock-free access is required, while separately protecting mapping lifetimes.

- [x] **S32-R2-14 — High — C11 — Signal handlers race on live-context and pending-signal state**
  - **Where**: `src/os/threads.c:97-129` (`sparc32_thr_note_signal`, `thr_host_handler`); `src/interp/interp_signal.c:414-415`, `src/interp/interp_signal.c:518-538`
  - **What breaks / Why**: The host handler traverses the live-context table and performs plain read-modify-write operations on pending masks. Guest workers concurrently inspect and clear those masks. These operations lack a signal-safe atomic ownership protocol, allowing lost signals and cross-thread data races; live-context lifetime also needs protection during handler traversal.
  - **Fix**: Use lock-free atomic pending operations and a signal-safe context-lifetime design. Prefer recording delivery for the appropriate recipient and handling process-directed routing at safe points.

### 5.3 DRY — Intra-Repo Duplication

- [x] **S32-R2-15 — Low — DRY — Exec validation duplicates loader policy**
  - **Where**: `src/rt32/elf32.c:513-612`, `src/rt32/elf32.c:615-644`, `src/rt32/elf32.c:679-694` (`validate_elf32_fd`, `rt32_elf_validate`, `rt32_elf_load`)
  - **What breaks / Why**: The new prevalidation pass independently parses and validates an image that the loader subsequently processes again. Policy already differs: interpreter validation uses a fixed `0x3f000000` base, while loading can choose a higher base based on the executable’s break. The duplicated decisions undermine prevalidation’s guarantee.
  - **Fix**: Parse and validate once into a repository-local load plan containing retained descriptors, segment ranges, and chosen load biases. Consume that plan during staging and commit.

### 5.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **S32-R2-16 — Low — YAGNI — Removed TLB subsystem leaves a public no-op lifecycle hook**
  - **Where**: `src/vm/vm32.c:251-257` (`vm32_tlb_invalidate`); `src/rt32/vm.c:332-337` (`vm_record_region_ext_locked`)
  - **What breaks / Why**: Round-1 removed the disconnected TLB implementation but retained its public invalidation function and lifecycle calls. The function does nothing, while its name implies a coherence operation that callers may mistakenly rely on.
  - **Fix**: Remove the obsolete hook, declaration, and calls. Document the actual protection-table publication contract at the functions that implement it.

### 5.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **S32-R2-17 — Low — CLEAN — Store-path comment contradicts the SMC remediation**
  - **Where**: `src/dbt/emit_fast.c:130-154`
  - **What breaks / Why**: The comment says stores to code-bearing pages run “without cache invalidation” and retain approximate semantics. The new helper path invalidates translations and introduces an early block exit. This obsolete explanation can lead future maintainers to preserve or reintroduce incorrect behavior.
  - **Fix**: Describe the current write notification, translation retirement, and block-exit behavior, including delay-slot constraints.

The source inventory stays within the 900-line ceiling; `src/os/syscalls.c` is largest at 865 lines. Targeted searches found no banned string-conversion calls or textual `.c` includes in the inspected production scope. Those searches do not establish absence of all VLAs, UB, or encoded-register violations. All proposed consolidation remains inside `sparc32rt`; no cross-repository library extraction is recommended.

---

### R2-6. `rvrt` (`8e207fb` → `dab0b91`) — 5 / 5 Resolved (`fable` Reviewed)

### 6.1 Bugs & Defects

#### High

- [x] **RV-R2-1 — High — BUG — Fused FP operations overwrite a dirty cache victim before spilling it**
  - **Where**: `src/dbt_emit_fp.c:847-855` (fused-operation lowering in `rv_dbt_fp_try_emit`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: Fused operations emit their result directly into `16 + (rd & 15)`. Only afterward does `emit_str_d` check whether that cache slot contains a dirty, different guest register and emit its spill. The physical register already contains the new result, so the spill saves that result under the old guest register’s identity. For example, with dirty `f0` cached in `v16`, `fmadd.d f16,f1,f2,f3` overwrites `v16`, then spills the new `f16` result into architectural `f0`. The subsequent slot rename cannot recover the original value. This is separate from the repaired load-miss branch.
  - **Fix**: Preserve a dirty destination-slot victim before emitting the arithmetic instruction. Alternatively, compute into an uncached temporary, spill the victim, then move the result into the destination slot. Cover all four fused operations with dirty `fN`/`f(N+16)` collisions, including destination/source overlap.

#### Medium

- [x] **RV-R2-2 — Medium — DEFECT — Darwin anonymous mapping silently ignores no-replace semantics**
  - **Where**: `src/os/backend_darwin.c:61-74` (`rt_host_map_anon`).
  - **What breaks / Why**: The function explicitly discards `noreplace`, while independently enabling `MAP_FIXED` whenever `fixed` is nonzero. A caller requesting fixed placement without replacement can therefore overwrite an existing host mapping. With `fixed` zero, the address remains merely a hint. Neither behavior implements the requested exclusion guarantee. This is a backend API defect; production guest reachability was not established.
  - **Fix**: Implement collision-safe placement with the required ownership synchronization, or explicitly reject unsupported no-replace requests before calling `mmap`. Never silently downgrade them to destructive fixed mapping. Add an occupied-address case that verifies the original mapping survives.

#### Critical / Low

No additional confirmed findings at these severities within the completed inspection.

### 6.2 Curated C11 & UB Issues

No independently confirmed new C11/UB finding emerged from the inspected material.

The Makefile includes the required C11 warning flags. Searches found no first-party calls to the specified banned string/parsing functions. The `x18` hit in `test/fixtures/signal_context.S` is a **RISC-V guest register**, not evidence of AArch64 platform-register misuse. These observations do not establish complete C11 or generated-register compliance.

### 6.3 DRY — Intra-Repo Duplication

No additional duplication finding was established with sufficient context to recommend consolidation. No cross-repository shared library is proposed.

### 6.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **RV-R2-3 — Low — YAGNI — Return-address stack integration only maintains unused bookkeeping**
  - **Where**: `src/darwin_dbt.c:378-395` (`note_block_ras`, `check_indirect_ras`); `src/darwin_dbt_emit.c:313-328` (`emit_term_pc`).
  - **What breaks / Why**: The new hooks push return PCs and pop them on indirect exits. A mismatch only resets `ras_top`; the popped address never selects a block, supplies a dispatch target, or changes fallback behavior. Generated chaining still uses the fast indirect-branch cache. Thus the Round-1 unused-feature finding was addressed by adding activity around the stack without implementing a consumer. Moreover, treating every indirect exit as a return cannot faithfully maintain call/return history.
  - **Fix**: Remove the unused mechanism, or implement an explicit return-prediction consumer with architectural-target validation, proper RISC-V call/return classification, and coverage for generated chaining. Adding push/pop calls alone does not resolve the original issue.

### 6.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **RV-R2-4 — Medium — CLEAN — Prohibited textual implementation includes remain throughout tests**
  - **Where**: `test/test_exec_state.c:47` (production implementation inclusion); `test/test_space_alloc.c:48` (allocator-intercepted implementation inclusion).
  - **What breaks / Why**: These tests still textually include production `.c` files. Repository-wide searches also found the pattern in tests for native signals, MM operations, family state, descriptor handling, file backing, and loader transport. This directly violates the requested no-unity-includes rule and leaves tests coupled to implementation-private declarations and macro substitution. RV-9 therefore remains open despite selected tests being converted.
  - **Fix**: Compile production implementation files separately and expose narrow private test interfaces or explicit dependency-injection seams. Convert all remaining occurrences, then add a source check rejecting textual `.c` includes.

- [x] **RV-R2-5 — Low — CLEAN — Header slicing meets file limits without decomposing large implementation units**
  - **Where**: `src/runtime_main.c:115-125` (eleven implementation-header inclusions); `src/runtime/family.c:34-38` (five implementation-header inclusions).
  - **What breaks / Why**: The remediation moves large sequences of implementation into headers that are textually assembled into the original translation units. Physical files now meet the ceiling, but the runtime orchestration and family implementations retain their broad shared scope, include-order dependencies, and weak internal ownership boundaries. This is a maintainability gap in RV-10’s requested decomposition, **not a remaining literal violation of the 900-line limit**.
  - **Fix**: Split coherent responsibilities into separately compiled private modules with small interfaces and explicit state ownership. Keep headers for declarations, types, and justified small inline helpers. Preserve the standalone repository boundary.

All findings above are static deductions. Runtime reproduction, remediation test coverage, complete syscall/VM semantics, concurrent cache lifecycle, and comprehensive signal/fork lock ordering remain unverified.

---

### R2-7. `loongarch64rt` (`026e87d` → `38f01b0` → `00ea803`) — 7 / 7 Resolved (`fable` Reviewed)

### 7.1 Bugs & Defects

#### High

- [x] **LA64-R2-1 — High — BUG — Read misses restore writable tags on translated code pages**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/dbt/dbt.c:487-502` (`translate_block`); `src/dbt/dbt_smc.c:136-143` (`dbt_smc_store`).
  - **What breaks / Why**: Translation revokes writable tags for code pages, but a subsequent **read** miss computes `writable` solely from guest mapping permissions and publishes that page’s `write_tag`. The code-page check runs only when servicing a store miss. Consequently, loading from an RWX code page can re-enable direct stores that bypass `dbt_smc_store`. Those stores do not bump the SMC epoch, allowing cached instructions to remain stale.
  - **Fix**: Apply the code-page write gate whenever publishing a writable tag, regardless of which access caused the fill. Keep code pages readable but never directly writable through this path. Cover translate → read miss → modify instructions → execute again.

- [x] **LA64-R2-2 — High — BUG — Reservation protection checks an access while granting permission to an entire page**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/interp/interp_amo.c:194-225` (`interp_step_amo`); `src/dbt/dbt_smc.c:151-163` (`dbt_revoke_write`).
  - **What breaks / Why**: LL revokes the page’s writable tag. The refill path refuses a store only if that particular access overlaps the current context’s reserved eight-byte range. A store elsewhere on the same page can refill the **whole page** as writable; a read miss can do so without checking the reservation at all. A later native store to the reserved address then bypasses reservation invalidation, allowing SC to succeed incorrectly. The refill check also considers only `ctx->ll_valid`, not reservations held by other contexts.
  - **Fix**: Gate writable publication at page granularity against every live reservation relevant to that mapping. Keep the page on the checked store path until reservations are cleared. Use one reservation policy across interpreter and DBT memory paths.

- [x] **LA64-R2-3 — High — BUG — Mprotect releases the mutation transaction before updating host permissions**
  - **Where**: `src/os/mem_min.c:575-626` (`la64_mem_protect`); `src/os/mem_min.c:169-194` (`protect_host_page`).
  - **What breaks / Why**: The function updates guest protection metadata and calls `vm64_commit_mutation` before applying host-page protection changes. This puts the host synchronization outside the intended quiescent transaction. When permissions are relaxed, another worker can observe the new guest permission while the host page still denies access, producing a translator fault. If host `mprotect` fails, the function returns an error after publishing the new guest permissions, leaving inconsistent state.
  - **Fix**: Keep peers quiescent until host permissions and guest metadata agree. Stage protection changes, handle host failures with rollback or explicitly consistent partial state, then invalidate translations/TLBs and release the transaction.

#### Medium

- [x] **LA64-R2-4 — Medium — BUG — Fixed mmap silently rounds down invalid addresses**
  - **Where**: `src/os/syscalls_mem.c:212-231` (`sys_mmap`).
  - **What breaks / Why**: Both `MAP_FIXED` and the nonzero-address `MAP_FIXED_NOREPLACE` paths mask off the low address bits instead of rejecting an unaligned address. For `MAP_FIXED`, a malformed request can therefore replace an existing mapping at the preceding page boundary instead of returning `EINVAL`. This contradicts the series’ explicit syscall-alignment contract.
  - **Fix**: Validate page alignment before modifying mappings for either fixed-address flag. Reserve hint rounding for non-fixed mappings. Validate the zero-address `MAP_FIXED_NOREPLACE` case through the same fixed-address path.

- [x] **LA64-R2-5 — Medium — BUG — Darwin directory cursors remain descriptor-local and can lose buffered entries**
  - **Where**: `src/os/darwin_dir.h:25-40` (`darwin_dir_slot_t`); `src/os/darwin_dir.h:53-105` (`darwin_dir_acquire`); `src/os/darwin_dir.h:125-147` (`darwin_dir_getdents64`).
  - **What breaks / Why**: The new cache retains pending entries for repeated calls on one descriptor, but it keys streams by numeric fd and creates a separate `DIR *` for each descriptor. Duplicated descriptors share the underlying directory offset while their libc buffers and pending entries remain separate. Alternating enumeration through aliases can therefore skip entries. Additionally, exhausting the cache silently closes slot zero, discarding its pending entry and buffered read-ahead; recreating that stream resumes from the advanced underlying offset.
  - **Fix**: Associate one reference-counted cursor with each shared open-file description and attach descriptor aliases to it. Do not evict a live cursor without preserving its logical position and buffered state; return a resource error if safe retention is impossible.

#### Critical / Low

No additional findings established at these severities in this section.

### 7.2 Curated C11 & UB Issues

No additional standalone C11/UB finding met the evidence threshold within this inspection budget.

The inspected negative-immediate shift change moves the shift before the signed cast, addressing the previously reported signed-left-shift issue. Searches found no textual `.c` includes or calls to the listed banned string functions. Textual `x18` matches were comments and checks; this does **not** prove every generated instruction preserves the register.

The IBTC fields remain ordinary `uint64_t` and pointer fields, despite the remediation commit’s atomic-publication claim. A complete concurrency proof would require tracing scheduler serialization and signal interleavings; absence of atomics alone is not reported here as a proven data race.

### 7.3 DRY — Intra-Repo Duplication

No additional independently substantiated duplication finding is reported. The former duplicated JIT lifecycle now routes through repository-local helpers in `src/os/jit_wx.h`.

All proposed fixes remain within this standalone repository.

### 7.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **LA64-R2-6 — Low — YAGNI — C IBTC lookup API has no production caller**
  - **Where**: `src/dbt/dbt_chain.c:49-56` (`dbt_ibtc_lookup`); `src/dbt/dbt.h:149` (declaration).
  - **What breaks / Why**: Production reference searches found only the definition and declaration. The trampoline probes the table directly, while `dbt_chain_next` uses `dbt_lookup_code`. This leaves an unused public lookup interface with a separate validation policy to maintain.
  - **Fix**: Remove the unused production API, or make its specific test-only purpose explicit and restrict its exposure accordingly.

### 7.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **LA64-R2-7 — Low — CLEAN — Chaining documentation describes removed and nonexistent state**
  - **Where**: `src/dbt/dbt_chain.c:4-7`, `src/dbt/dbt_chain.c:21-22`; `src/dbt/dbt.h:136-146`.
  - **What breaks / Why**: Comments still describe a per-thread IBTC and a RAS. The IBTC is a process-global array without thread-local storage, and the RAS was removed in the remediation. These claims obscure the actual ownership and synchronization requirements during precisely the concurrency review the code needs.
  - **Fix**: Remove the RAS references and document the IBTC’s actual process-wide ownership, invalidation rules, and serialization assumptions.

The inspected file-size gate now includes `src/` and `tests/`, and static counts found no oversized source files. Complete FP/ISA semantics, file-backed alias coherence, clone/exec behavior, and asynchronous recovery remain unqualified by this bounded audit.

---

### R2-8. `ppc64rt` (`bd3e73f` → `d2f0105` → `205054f`) — 15 / 15 Resolved (`fable` Reviewed)

### 8.1 Bugs & Defects

#### Critical

None established.

#### High

- [x] **P64-R2-1 — High — DEFECT — Cooperative children lack general scheduling and are killed at an instruction cap**
  - **Where**: `src/os/syscalls_p4.c:173-200`, `src/os/syscalls_p4.c:245-305`, `src/os/syscalls_p4.c:397-413` (`p4_task_step_quantum`, `p4_sched_run_ready`, clone/wake dispatch).
  - **What breaks / Why**: Clone runs a bounded batch of child quanta before returning. Ready children subsequently advance through selected clone/futex paths, rather than through a scheduler integrated into ordinary parent execution. A child waiting for a parent-written flag can remain ready after clone returns, while the parent subsequently waits for the child using ordinary memory operations; neither makes progress. Blocking child host syscalls can also prevent the parent from running. Independently, exceeding 40 million child instructions silently frees the task and returns `EFAULT`, without normal exit cleanup.
  - **Fix**: Integrate task selection into the main execution loop, with bounded quanta and suspension around blocking operations. Remove the lifetime instruction cap from normal execution; keep any diagnostic execution limit explicit and separate from guest syscall results.

- [x] **P64-R2-2 — High — BUG — Thread exit and thread-group exit still have incorrect scope**
  - **Where**: `src/os/syscalls_p4.c:208-211` (`p4_task_step_quantum`); `src/run/core.c:382-385` (`run` exit dispatch).
  - **What breaks / Why**: A child’s `exit_group` follows exactly the same path as `exit`, finishing only that child. Conversely, the main task’s `exit` breaks the whole runner even when other guest threads remain live. Programs can continue after a requested process-wide termination or lose live workers when only their initial thread exits.
  - **Fix**: Represent individual task termination separately from group termination. Continue scheduling surviving tasks after a thread exits; propagate `exit_group` and its status to the complete guest thread group.

- [x] **P64-R2-3 — High — DEFECT — Futex timeout validation does not implement timeout behavior**
  - **Where**: `src/os/syscalls_p4.c:333-395` (`syscall_p4_futex`).
  - **What breaks / Why**: Timeout seconds and nanoseconds are read and validated, then discarded. A waiting child records no deadline and can remain suspended indefinitely. A parent returns `ETIMEDOUT` as soon as no child is ready, regardless of the requested interval; with perpetually ready children, the loop does not enforce a deadline. An untimed matching wait can still return `EAGAIN` merely because there is nothing locally runnable.
  - **Fix**: Store deadlines in waiter state, distinguish relative WAIT from absolute WAIT_BITSET deadlines and clock selection, and suspend until wake, interruption, or actual expiry. Couple this with the scheduler rather than interpreting an empty ready queue as timeout or mismatch.

- [x] **P64-R2-4 — High — BUG — Child execution bypasses the repaired signal machinery**
  - **Where**: `src/os/syscalls_p4.c:193-200`, `src/os/syscalls_p4.c:223-237` (`p4_task_step_quantum`); `src/run/core.c:387-418` (main-task signal dispatch); `src/os/syscalls_access.c:209-219` (`x_sigmask`).
  - **What breaks / Why**: The child runner sends syscalls directly to `ppc64_syscall`, bypassing the main runner’s sigaction, kill/tgkill, sigreturn, and altstack interception. A child memory fault frees the task and returns `EFAULT` instead of delivering its installed guest handler. Signal masks are also held in one static variable, so one child’s mask change changes the parent’s mask. The Round-1 signal fixes therefore do not provide per-thread Linux signal behavior.
  - **Fix**: Use the same trap/syscall/signal dispatch for every guest task. Keep blocked masks, pending thread-directed signals, altstack, and return-frame state per task; share dispositions only according to clone semantics.

- [x] **P64-R2-5 — High — BUG — VM atomics ignore the interpreter’s per-context reservation token**
  - **Where**: `src/interp/vec.c:110-149`, `src/interp/vec.c:151-180` (`ppc64_exec_larx_stcx`); `src/vm/vm_atomic.c:263-290`, `src/vm/vm_atomic.c:303-315` (`vm_mem_atomic`, `ppc64_vm_reserve`).
  - **What breaks / Why**: The interpreter saves and passes a reservation token, but the VM callback does not populate or check that token. It uses one `vm->resv_*` record shared by guest contexts. A later context’s LR can replace the record that an earlier context’s SC checks. This becomes a false-success risk when a write invalidates the VM reservation without clearing the earlier interpreter slot, followed by another context’s LR at the same address: the earlier SC can consume the newer reservation and overwrite data despite its original reservation having been lost.
  - **Fix**: Return an actual reservation identity/version from LR and validate that exact identity on SC. Keep ownership per guest context and invalidate it across all relevant writes and task lifecycle transitions.

- [x] **P64-R2-6 — High — BUG — Successful atomic stores bypass code invalidation and shared-file write propagation**
  - **Where**: `src/vm/vm_atomic.c:271-297` (`vm_mem_atomic`); `src/vm/vm64.c:288-315` (`vm_mem_write`).
  - **What breaks / Why**: The aligned SC/RMW path modifies host backing directly and only calls `ppc64_vm_reserve_note_store`. Ordinary writes additionally retire translated code and propagate MAP_SHARED writes to the file and sibling mappings. Routing guest SC through the atomic callback makes this omission reachable: an atomic patch to translated code can leave stale executable translations, and an atomic modification to a shared file mapping can remain local.
  - **Fix**: Integrate atomic stores with the VM write protocol: perform required COW/code invalidation before publication and shared-backing propagation after successful modification. Preserve atomicity rather than replacing CAS with an ordinary copy.

- [x] **P64-R2-7 — High — BUG — Scalar FP arithmetic ignores guest rounding and single-precision result rounding**
  - **Where**: `src/interp/fp.c:92-125` (`fp_add`, `fp_sub`, `fp_mul`, `fp_div`); `src/interp/fp.c:259-279` (`fp_po63`); `src/interp/fp.c:794-797` (`ppc64_fp_step`).
  - **What breaks / Why**: Opcodes 59 and 63 use the same host-double arithmetic path. Single-precision instructions therefore retain double-precision results instead of rounding to binary32 and representing that rounded value in the FPR. For example, single-precision addition of `1.0` and `2^-24` under nearest-even should produce `1.0`; this path retains `1.0 + 2^-24`. Arithmetic also never consults FPSCR.RN, so guest rounding-mode changes do not govern results. DBT fallback inherits these interpreter errors.
  - **Fix**: Implement format-specific arithmetic with guest rounding control, preferably through the existing established software-FP substrate or a carefully controlled host-FP layer. Add oracle cases for all rounding modes and binary32 halfway values.

- [x] **P64-R2-8 — High — BUG — Child cleanup can clear the parent’s clear-TID address**
  - **Where**: `src/os/syscalls.c:563-579` (`SET_TID_ADDRESS`, clone dispatch); `src/os/syscalls_p4.c:156-169`, `src/os/syscalls_p4.c:297-301` (`p4_task_finish`, `syscall_p4_clone`).
  - **What breaks / Why**: `set_tid_address` updates a single global `s_clear_tid`, which is passed into clone and copied into the child’s `set_tid_addr`. Child exit clears and wakes that address in addition to its requested `CLONE_CHILD_CLEARTID` address. A parent that registered its own clear-TID word can therefore have that word zeroed when an unrelated child exits. A child calling `set_tid_address` also changes global state rather than its own task’s cleanup address.
  - **Fix**: Store clear-TID state per task. Initialize the child according to clone flags, update the current task on `set_tid_address`, and clear only the exiting task’s registered address.

#### Medium

- [x] **P64-R2-9 — Medium — BUG — FPSCR exception and record-form updates are fabricated**
  - **Where**: `src/interp/fp.c:31-41` (`ppc64_fpscr_record`); `src/interp/fp.c:280-298` (`fp_po63`).
  - **What breaks / Why**: Finite division results are treated as inexact whenever repeating the same host division produces the same bits; exact division such as `4.0 / 2.0` satisfies that condition. The exception helper places flags in an ad hoc `exc << 4` layout and sets bit 32, rather than implementing architectural FPSCR status fields. Record forms then write CR1 as zero rather than copying the required FPSCR summary. Guest exception inspection and branches on FP status are incorrect.
  - **Fix**: Collect actual operation exceptions, map them into named Power FPSCR fields, maintain summary/sticky status, and derive CR1 from the architectural fields.

- [x] **P64-R2-10 — Medium — BUG — Access syscalls reject valid relative paths and directory descriptors**
  - **Where**: `src/os/syscalls_access.c:109-115` (`acc_guest_abs`); `src/os/syscalls_access.c:147-158` (`syscall_faccessat`); `src/os/syscalls_access.c:173-180` (`syscall_access`).
  - **What breaks / Why**: Relative paths unconditionally return `EBADF`. `faccessat` also rejects every directory descriptor except `AT_FDCWD`, even for an absolute path where the descriptor should be ignored. Ordinary `access("file", F_OK)` and descriptor-relative access checks fail despite valid files and descriptors.
  - **Fix**: Resolve relative paths against guest cwd or the translated directory descriptor. Ignore `dirfd` for absolute paths and preserve Linux error semantics.

- [x] **P64-R2-11 — Medium — BUG — Path copy-in reads beyond a valid terminating NUL**
  - **Where**: `src/os/syscalls_access.c:98-115` (`acc_guest_abs`).
  - **What breaks / Why**: The function reads an entire 256-byte chunk before checking for a terminating NUL. A valid short pathname near the end of a readable guest page returns `EFAULT` if the chunk crosses into an inaccessible page, even though the complete string is readable.
  - **Fix**: Bound each read to the remaining bytes in the current guest page, inspect for NUL, and only access the next page when necessary. Reuse the corrected copy-string helper within this repository.

#### Low

No additional low-severity BUG/DEFECT findings.

### 8.2 Curated C11 & UB Issues

- [x] **P64-R2-12 — Low — C11 — Generated test source still calls banned strcpy**
  - **Where**: `tests/h2_run.sh:100-106` (generated `t_string` function).
  - **What breaks / Why**: The generated first-party C source uses `strcpy`, contrary to the explicitly requested curated subset. This particular literal fits the destination, so this is a policy violation rather than an established overflow.
  - **Fix**: Initialize the array directly or use a bounded copy with a known size. Include generated C embedded in scripts in source-policy scans.

No additional definite C undefined behavior was established within the inspected excerpts. The targeted scan found no textual `.c` unity includes or explicit assembly access to `x18`; this does not verify every encoded JIT instruction.

### 8.3 DRY — Intra-Repo Duplication

- [x] **P64-R2-13 — Low — DRY — Access and faccessat duplicate resolution and retry logic**
  - **Where**: `src/os/syscalls_access.c:159-170`, `src/os/syscalls_access.c:181-192` (`syscall_faccessat`, `syscall_access`).
  - **What breaks / Why**: Both functions repeat the initial access call, fallback buffer construction, sysroot remapping, and retry. Their path-semantics fixes must consequently be maintained twice.
  - **Fix**: Use a repository-local helper for the resolved-path access and fallback operation, with cwd/dirfd resolution handled explicitly by its caller. No cross-repository library is needed.

### 8.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **P64-R2-14 — Low — YAGNI — Guest rounding-mode accessor has no production caller**
  - **Where**: `src/interp/fp.c:24-29` (`ppc64_fpscr_rn`).
  - **What breaks / Why**: The repository symbol search finds its declaration and definition but no caller. The accessor suggests a rounding integration point while live arithmetic ignores the mode, as described in P64-R2-7.
  - **Fix**: Connect it to the corrected arithmetic implementation, or remove the unused exported API until that integration exists.

### 8.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **P64-R2-15 — Low — CLEAN — Thread module documentation describes the removed execution model**
  - **Where**: `src/os/syscalls_p4.c:4-17` (file header).
  - **What breaks / Why**: The header still says clone runs a child inline to completion, unchanged-word futex WAIT is unreachable, and WAKE has no waiters. The implementation now retains runnable and waiting tasks. These claims conceal the actual scheduling and lifetime obligations precisely where maintainers need an accurate concurrency description.
  - **Fix**: Document the current cooperative task model, its scheduling entry points, task ownership, and remaining limitations. Remove assertions based solely on the old gate-test execution order.

The line-count scan found no current first-party ceiling violation. Complete mremap rollback, synchronous host-fault recovery, AOT validation, and concurrent cache/quiescence safety remain **unqualified by this bounded audit**.

---

### R2-9. `mips64rt` (`32d5c9e` → `4153fd6` → `45af6bf`) — 10 / 10 Resolved (`fable` Reviewed)

### 9.1 Bugs & Defects

#### High

- [x] **M64-R2-1 — High — BUG — Ordinary stores remain outside the LL/SC critical section**
  - **Where**: `src/os/mem.c:209-223`, `src/os/mem.c:302-329` (`guest_st8`, `guest_st32`); `src/interp/unaligned.c:370-377`, `src/interp/unaligned.c:442-479` (`mips_llsc_note_write`, `do_sc`).
  - **What breaks / Why**: The Round-1 fix locks reservation bookkeeping, but ordinary stores modify guest memory **before** calling the notification hook. SC holds `sc_lock` across its generation/value check and store; ordinary writers do not hold that lock while writing. Another thread can therefore modify the reserved word between SC’s comparison and commit, then wait for the lock to report its write. SC can incorrectly succeed and overwrite that intervening store. The new generation counters do not close this window.
  - **Fix**: Serialize the actual memory write and reservation invalidation with SC’s check-and-commit. Provide a shared write transaction covering scalar stores and other guest-memory writers, with explicit handling for writes already executing inside SC.

- [x] **M64-R2-2 — High — BUG — Blocking syscalls can prevent every VM mutation from completing**
  - **Where**: `src/os/syscall_min.c:848-861` (`mips_syscall`); `src/os/quiesce.c:306-340` (`mips_qs_begin`); `src/os/quiesce.c:169-171` (`qs_preempt_handler`).
  - **What breaks / Why**: The syscall wrapper holds a memory lease across the entire syscall body, including potentially indefinite host waits. A VM mutator waits until every peer is parked with zero leases. Leased peers are deliberately excluded from preemption, and the preemption handler returns if a lease is active. A thread blocked in a read or wait can consequently prevent another thread’s `mmap`, `mprotect`, or `munmap` from completing indefinitely.
  - **Fix**: Separate guest-memory access from blocking host waits. Use staging buffers or explicit mapping pins where needed, release the quiescence lease before blocking, and reacquire and revalidate before guest-memory copyout.

- [x] **M64-R2-3 — High — BUG — DBT compilation performs faulting speculative instruction fetches**
  - **Where**: `src/dbt/dbt.c:443-474` (`dbt_compile`); `src/interp/interp.c:794-810` (`exec_branch`).
  - **What breaks / Why**: Compilation calls the architectural `mips_fetch` on subsequent instructions and on a branch’s delay slot before executing the branch. When the delay-slot fetch fails, compilation merely removes the branch from the candidate block. Any fault or signal-delivery side effect of that fetch has already happened. In particular, a not-taken branch-likely at a page boundary must annul its inaccessible delay slot; the interpreter explicitly skips the fetch, while compilation attempts it unconditionally.
  - **Fix**: Use a side-effect-free fetch/probe for block construction. On an inaccessible speculative instruction or delay slot, end the block or fall back at the branch PC. Only execution should deliver the architectural fault.

- [x] **M64-R2-4 — High — BUG — Fork inherits quiescence entries for threads that no longer exist**
  - **Where**: `src/os/syscall_min.c:429-439` (`sc_fork`); `src/os/quiesce.c:46-63`, `src/os/quiesce.c:314-337` (worker registry and mutation drain); `src/interp/unaligned.c:290-308` (`sc_lock`).
  - **What breaks / Why**: The fork child inherits the process-wide worker registry, including parent-process TIDs, pthread identities, and lease counts. Only the calling host thread survives. A later child VM mutation can wait forever for inherited peers that cannot park or release leases; preemption also uses the saved parent PID/TID. The newly introduced LL/SC spinlock can likewise be inherited as locked if another thread held it at fork. The inspected atfork registrations cover memory/file bookkeeping, not these registries and locks.
  - **Fix**: Add a coordinated fork lifecycle that stabilizes relevant state before fork and reconstructs child-only thread, quiescence, and reservation state afterward. Reset inherited locks safely and refresh the surviving thread’s PID/TID binding.

#### Medium

- [x] **M64-R2-5 — Medium — BUG — Double-precision FP emulation assumes wider long-double arithmetic**
  - **Where**: `src/interp/fp.c:202-223` (`fp_adj_d`); `src/interp/fp.c:395-396`, `src/interp/fp.c:417-447`, `src/interp/fp.c:469-473` (double arithmetic and exception accounting).
  - **What breaks / Why**: The interpreter treats `long double` calculations as an exact reference for rounding and inexact detection. Native Apple Silicon Darwin uses binary64 `long double`, so this reference can equal the already-rounded `double`. For example, adding `1.0` and `2^-54` under round-toward-positive must produce the next representable double; the comparison can instead see equality and leave `1.0` unchanged. Inexact flags are also lost. The Round-1 integer conversion fix avoids this assumption, but arithmetic still uses it.
  - **Fix**: Replace precision-dependent reference calculations with reliable rounding and exception handling on every supported host, using an established FP implementation or proven operation-specific residual calculations.

- [x] **M64-R2-6 — Medium — BUG — Interpreter never raises underflow through its result-accounting helper**
  - **Where**: `src/interp/fp.c:176-187` (`fp_inexact`); `src/interp/fp_cvt.c:121-125` (`fp_cvt_sd`).
  - **What breaks / Why**: The helper explicitly omits underflow and raises only overflow and inexact. A tiny, inexact result—for example a sufficiently small finite double converted to single precision—therefore lacks the underflow cause/flag. With underflow enabled, the new enabled-exception mechanism cannot deliver SIGFPE because no underflow exception is recorded.
  - **Fix**: Implement tininess and inexactness accounting for narrowing and arithmetic according to the supported MIPS FP profile. Route underflow through `fp_raise` so enabled exceptions also suppress destination writeback.

- [x] **M64-R2-7 — Medium — DEFECT — Instruction traps still collapse distinct signal codes to one**
  - **Where**: `src/os/sigframe.c:537-561` (`mips_trap`); `src/interp/interp.c:329-342` (trapping integer arithmetic); `src/interp/fp.c:161-170` (`fp_finish_trap`).
  - **What breaks / Why**: Round 1 corrected the signal number, but `mips_trap` assigns `si_code = 1` to every SIGFPE. Integer overflow and enabled FP invalid, overflow, underflow, and inexact exceptions consequently receive the same diagnostic code. Signal handlers cannot distinguish the actual architectural exception; code 1 denotes integer division rather than this collection of causes.
  - **Fix**: Carry an explicit exception kind and signal code from the instruction or FP exception source into signal-frame construction. Preserve the existing precise PC and delay-slot handling.

#### Critical / Low

No additional confirmed findings at these severities in this category.

### 9.2 Curated C11 & UB Issues

- [x] **M64-R2-8 — High — C11 — Quiescence slots are published before initialization**
  - **Where**: `src/os/quiesce.c:70-104` (`qs_slot_for`); `src/os/quiesce.c:163-165`, `src/os/quiesce.c:314-337` (registry readers); `src/os/quiesce.c:403-425` (`mips_qs_unregister`).
  - **What breaks / Why**: Slot creation changes atomic `used` from zero to one **before** initializing non-atomic `key`, `pthread`, `tid`, and `pid`. Other threads and the preemption handler treat nonzero `used` as a fully initialized slot and read those fields concurrently. Atomic publication cannot order writes that happen afterward. Unregistration similarly modifies `key` while the slot remains published. This creates C data races and can direct preemption at stale or uninitialized thread identifiers, preventing quiescence.
  - **Fix**: Distinguish FREE, INITIALIZING, and LIVE states. Initialize fields before release-publishing LIVE, and let readers acquire-observe only LIVE slots. Add a safe retirement/reuse protocol so readers cannot overlap teardown or reinitialization.

The inventory found no file exceeding 900 lines. The searches found no direct calls to the listed banned functions or textual `.c` includes in the searched production/test paths. This does not establish absence of all VLAs, UB, or numerically encoded `x18` use.

### 9.3 DRY — Intra-Repo Duplication

- [x] **M64-R2-9 — Low — DRY — Pending signal queue insertion remains duplicated**
  - **Where**: `src/os/sigact.c:135-152` (`l4a_pend_enqueue`); `src/os/sigframe.c:130-146` (`l4b_pend_enqueue`).
  - **What breaks / Why**: Both implementations duplicate capacity checks, slot arithmetic, event-field writes, and count updates. The comments explicitly justify duplication by historical lane isolation. Changes to queue synchronization, overflow behavior, or event representation must now be applied consistently in two signal paths.
  - **Fix**: Move pending-queue operations into one separately compiled internal module within **mips64rt**, with a narrow header and explicit synchronization contract. Preserve the standalone repository boundary.

### 9.4 YAGNI — Dead Code & Speculative Scaffolding

No additional dead-code finding was established with sufficient confidence within the inspection budget. The former write-only arena retention array now has a reclamation reader and should not be reported again as unchanged dead bookkeeping.

### 9.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **M64-R2-10 — Low — CLEAN — Arena lifetime comments contradict the reclamation implementation**
  - **Where**: `src/dbt/arena.c:15-18`, `src/dbt/arena.c:42-43`, `src/dbt/arena.c:58-73`; `src/dbt/dbt.c:131-134`, `src/dbt/dbt.c:150-151`.
  - **What breaks / Why**: Comments still promise that published mappings are never unmapped and remain valid until process exit, using the 1024-entry cache as the lifetime justification. The remediation now explicitly frees tracked mappings in `dbt_arena_reset`. These comments describe an obsolete pointer-lifetime guarantee precisely where maintainers need to understand reclamation safety.
  - **Fix**: Document the actual reclamation boundary, required cache/IBTC invalidation, thread ownership, and prohibition on retaining code pointers across reset. Remove the obsolete process-lifetime and cache-size justification.

**Validation status:** All findings are static source conclusions with line-numbered locations. No runtime reproduction or release qualification was performed.

---

### R2-10. `sparc64rt` (`3ead4f9` → `0428b42` → `001f2b1`) — 12 / 12 Resolved (`fable` Reviewed)

### 10.1 Bugs & Defects

#### High

- [x] **S64-R2-1 — High — BUG — Signal frames corrupt the Y register**
  - **Where**: `src/os/sync_sig.c:482-486` (`sparc64_sync_sig_deliver`); `src/os/sync_sig.c:585-590` (`sparc64_sync_sig_return`).
  - **What breaks / Why**: The frame contains adjacent **32-bit** `y` and `magic` fields. Delivery writes `ctx->y` using `put_u64be` at `0x1d8`, then overwrites its lower four bytes with `magic` at `0x1dc`. For an ordinary 32-bit Y value, the actual frame Y becomes zero. Return reads eight bytes, incorporating the magic value into restored Y. A signal round trip therefore changes arithmetic state, affecting subsequent Y-dependent multiplication/division sequences.
  - **Fix**: Write and read Y as a big-endian 32-bit field. Keep magic separate. Add a regression that sets a nonzero Y, checks the handler-visible frame, and verifies Y after sigreturn.

- [x] **S64-R2-2 — High — BUG — Delay-slot syscalls lose the pending branch destination**
  - **Where**: `src/interp/interp.c:254-260` (`exec_delay`); `src/interp/interp.c:312-325,339-364` (`exec_cti`); `src/os/guest_engines.c:244-257` (`run_interp`).
  - **What breaks / Why**: A taken branch executes its delay slot before publishing the delay instruction’s architectural `pc` and pending target in `npc`. If the slot contains a syscall trap, `exec_delay` returns immediately and the branch never commits its target. `run_interp` passes the unchanged CPU context into syscall handling; `step.pc` is used to identify the trap, but does not repair the pending control transfer. The syscall therefore sees the branch’s old PC/NPC pair, and ordinary syscall advancement cannot resume at the branch target.
  - **Fix**: Represent the architectural transition explicitly: before executing the delay instruction, publish its PC and the selected next PC. Preserve that pair across traps and syscalls. Test a taken branch with a returning syscall in its delay slot, including interpreter fallback from DBT.

- [x] **S64-R2-3 — High — BUG — Cache flush forgets a failed RX-to-RW transition**
  - **Where**: `src/dbt/emit_rt.c:70-93` (`dbt_flush_all`); `src/dbt/dbt.c:122-142` (`dbt_stage`).
  - **What breaks / Why**: `dbt_flush_all` ignores `a32h_wx_reopen` failure, clears `arena_published`, and resets `arena_used`. If the permission change fails, the arena remains RX while bookkeeping says it is writable. Subsequent staging skips reopening and returns that memory for code emission, causing a host write fault. The Round-1 publication fix covers entry into unpublished code but not this reverse transition.
  - **Fix**: Change arena state only after successful reopening. Propagate failure or discard the arena and fall back to interpretation. Exercise both publication and reopening failures through an injectable host-memory interface.

#### Medium

- [x] **S64-R2-4 — Medium — DEFECT — Futex requeue reports the wrong count and permits ineffective moves**
  - **Where**: `src/os/backend_darwin_sync.c:348-387` (`rt_host_futex_requeue`); `src/os/backend_darwin_sync.c:148-157` (`futex_match`).
  - **What breaks / Why**: The implementation counts moved waiters in `requeued` but returns only `woken`. A request that moves waiters without waking any returns zero despite changing the queue. If `key2 == NULL`, it increments `requeued` without changing either the key or address. Additionally, keyed moves retain the old `uaddr`; a subsequent address-only lookup can still match the source address.
  - **Fix**: Return the total number woken and requeued. Require a valid destination identity and update the matching representation consistently. Reject unsupported keyed/address-only combinations rather than reporting an ineffective move.

- [x] **S64-R2-5 — Medium — DEFECT — Temporary poll masks still permit lost signal wakeups**
  - **Where**: `src/os/backend_darwin.c:578-615` (`darwin_sigmask_enter`, `rt_host_ppoll`); `src/os/backend_darwin.c:680-702` (`rt_host_epoll_pwait`).
  - **What breaks / Why**: `pthread_sigmask` and the blocking operation are separate calls. A pending signal can be delivered after the mask changes but before `poll` or `kevent` starts. With no worker wake pipe, `ppoll` can then sleep for the entire timeout or indefinitely. The epoll path does not register the worker wake pipe with this wait; checking `sig_seq` after `kevent` cannot wake a wait already sleeping. Thus Round-1’s atomic-mask requirement remains unresolved.
  - **Fix**: Use a platform-supported atomic mask-and-wait mechanism or a complete signal-notification protocol with persistent readiness included in every wait. Define and enforce behavior when `ws == NULL`.

- [x] **S64-R2-6 — Medium — DEFECT — Darwin directory reads discard unread entries**
  - **Where**: `src/os/backend_darwin.c:385-403` (`rt_host_getdents64`).
  - **What breaks / Why**: Each call creates a fresh buffered `DIR` on a duplicate of the caller’s descriptor. `readdir` can advance the shared underlying directory offset beyond the entries returned to the caller. When the output buffer fills, `closedir` discards remaining buffered entries, and the next call resumes past them. The entry that fails the size check has also already been consumed. If even the first record does not fit, the function returns zero, falsely indicating EOF.
  - **Fix**: Preserve directory stream state across calls or use an unbuffered directory-entry interface with explicit offsets. Retain the first unreturned entry and report an appropriate error when the buffer cannot hold any record.

#### Critical / Low

No additional findings established in these severity groups.

### 10.2 Curated C11 & UB Issues

- [x] **S64-R2-7 — Medium — C11 — Signal notification now locks a pthread mutex**
  - **Where**: `src/os/backend_darwin_sync.c:135-145,160-169` (`futex_lock`, `futex_broadcast_all_signals`); `src/os/backend_darwin_sync.c:210-216` (`rt_host_worker_notify_signal`); `src/os/backend.h:45-59` (signal-wakeup contract).
  - **What breaks / Why**: The notification function now enters `g_futex_mu` and broadcasts pthread condition variables. These operations are not async-signal-safe. If invoked by a signal handler interrupting a thread that holds this mutex, notification deadlocks on that same thread. First-use notification can also initialize condition variables inside the handler. This is a regression in the intended signal-notification interface; a current production handler-to-function call chain was not found.
  - **Fix**: Keep handler notification limited to async-signal-safe operations. Arrange for normal execution context to process the persistent wake notification and signal waiters without losing wakeups.

- [x] **S64-R2-8 — Medium — C11 — Worker mutex initialization races between first callers**
  - **Where**: `src/os/backend_darwin_sync.c:65-79` (`g_workers`, `workers_lock`); `src/os/backend_darwin_sync.c:82-115` (worker registration and lookup).
  - **What breaks / Why**: `g_workers.init` is read and written without synchronization before the mutex is acquired. Concurrent first callers can both initialize the same mutex, or one can reinitialize it while another begins using it. The flag accesses constitute a C data race, and concurrent initialization invalidates the pthread synchronization object.
  - **Fix**: Initialize the mutex statically with `PTHREAD_MUTEX_INITIALIZER`, removing the flag, or use `pthread_once` for any initialization that genuinely needs execution.

- [x] **S64-R2-9 — Medium — C11 — Futex timeout conversion overflows signed arithmetic**
  - **Where**: `src/os/backend_darwin_sync.c:250-271` (`rt_host_futex_wait_bitset`).
  - **What breaks / Why**: Only nanoseconds are validated. Relative seconds are multiplied by one billion in `int64_t`; absolute deadlines also subtract and multiply in signed arithmetic. A large positive timeout, such as `tv_sec = INT64_MAX`, causes signed overflow and undefined behavior instead of a well-defined long wait or error. Negative relative seconds are reported as timeout expiration rather than rejected as an invalid timespec.
  - **Fix**: Validate seconds and nanoseconds, use checked arithmetic, and retain a normalized seconds/nanoseconds representation instead of collapsing unrestricted deadlines into signed nanoseconds.

### 10.3 DRY — Intra-Repo Duplication

- [x] **S64-R2-10 — Low — DRY — MOVcc adds another copy of the FP condition table**
  - **Where**: `src/dbt/emit_cond.c:184-187,218-220` (`sparc64_emit_movcc`); `src/dbt/emit_fpcmp.c:19-33` (`fp_taken_mask`, `fp_taken_compute`).
  - **What breaks / Why**: The remediation introduces a second identical 16-entry FP condition mask inside the DBT. MOVcc and floating conditional operations now maintain the same truth table separately, creating another drift point immediately after consolidating the raw decoder.
  - **Fix**: Define one internal DBT condition table or emission helper and use it from both files. Keep independent oracle tests. No cross-repository extraction is needed.

### 10.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **S64-R2-11 — Low — YAGNI — Obsolete runtime helpers have no callers**
  - **Where**: `src/dbt/emit_rt.c:182-222` (`s64_rt_mem`, `s64_rt_win`).
  - **What breaks / Why**: Repository-wide searches found definitions and historical comments but no calls or function-address references to either helper. They retain superseded memory/window execution paths and misleading claims about active call sites, adding code that must appear correct without contributing to execution.
  - **Fix**: Remove these internal helpers and update stale references, unless a concrete external consumer requires them. If such a consumer exists, declare and document that interface explicitly.

### 10.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **S64-R2-12 — Low — CLEAN — Backend contract describes synchronization mechanisms the code no longer uses**
  - **Where**: `src/os/backend.h:45-59` (blocking and preemption contract); `src/os/backend_darwin_sync.c:303-319` (`rt_host_futex_wait_bitset`); `src/os/backend_darwin_sync.c:403-420` (`rt_host_clock_nanosleep`).
  - **What breaks / Why**: The public contract describes futex sleeping through `__ulock_wait2` and signal wakeup through `__ulock_wake`. The implementation now uses pthread condition variables. The same comment promises kqueue-based sleep including a worker wake descriptor, while `rt_host_clock_nanosleep` discards `ws` and `expected_seq` and calls `nanosleep`. These comments incorrectly assure reviewers that lost-wakeup protection exists.
  - **Fix**: Document the actual mechanisms and supported guarantees. Remove obsolete ulock descriptions and identify unsupported wake protocols until implemented.

**Static hygiene results:** No inventoried source exceeded 900 lines. Searches found no production banned string calls or textual `.c` includes. Banned string calls in `test_h2_string.c` exercise libc behavior. Textual `x18` matches were comments; numeric emitter encodings were not exhaustively decoded, so register reservation is not fully qualified.

---

### R2-11. `rt-series` (`6fc9fbc` → `6d06558` → `37a9af0`) — 18 / 18 Resolved (`fable` Reviewed)

### 11.1 Bugs & Defects

#### Critical

No confirmed findings.

#### High

- [x] **RTS-R2-1 — High — DEFECT — Qualification accepts unrelated tests as software-tier evidence**
  - **Where**: `tools/run_catalogue.sh:107-141` (`check_parity_categories`).
  - **What breaks / Why**: The RTS-6 remediation accepts `hello` as T2 evidence, ISA cases as T1 evidence, and FP/thread cases as T3 evidence. `p3-torture` itself also matches the T3 `p3-` alternative. Matching searches the entire row rather than its case field, and requires no per-ABI or per-engine coverage. A small collection of passing runtime fixtures can therefore qualify a repository without executing compression/database tools, scripting runtimes, or the full required ABI/engine matrix.
  - **Fix**: Parse tab-separated fields and require explicit category evidence for every required ABI/engine tuple. Map only tests that actually implement the category; require separate guest-payload tier results.

- [x] **RTS-R2-2 — High — DEFECT — Grind still credits host execution to selected foreign architectures**
  - **Where**: `tools/run_grind.sh:69-72` (`resolve_arch_defaults`), `tools/run_grind.sh:442-485` (`run_libc_ltp_suite`), `tools/run_grind.sh:489-529` (`run_lmbench_suite`).
  - **What breaks / Why**: `--arch all` returns without constructing a translator matrix. Even with an explicit foreign architecture, libc/LTP and lmbench binaries execute directly, ignoring the resolved translator wrappers. Native binaries can produce PASS results under a foreign-architecture campaign heading; foreign binaries instead fail direct execution. RTS-4 is only partially fixed.
  - **Fix**: Expand `all` into explicit architecture jobs. Route every guest suite through a validated architecture/backend runner, and record native diagnostics separately from translator qualification.

#### Medium

- [x] **RTS-R2-3 — Medium — BUG — Grind chooses executable format before resolving the backend**
  - **Where**: `tools/run_grind.sh:73-98`, `tools/run_grind.sh:115-123` (`resolve_arch_defaults`, `BACKEND`).
  - **What breaks / Why**: Discovery prefers `*-darwin-arm64`, then Linux, based only on executable permission. Backend selection happens afterward and does not influence the runner. A Linux host with both artifacts selects Mach-O; Darwin can select a Linux ELF when its native artifact is absent. `GRIND_BACKEND=hl` never adds an `hl` launcher.
  - **Fix**: Resolve and validate the backend first. Select matching binary formats and construct explicit native-Linux, Darwin, or hyper-linux commands.

- [x] **RTS-R2-4 — Medium — DEFECT — Weekly differential checks never compare results**
  - **Where**: `tools/run_grind.sh:537-575` (`run_weekly_soak`).
  - **What breaks / Why**: Csmith and Yarpgen run one selected wrapper and accept exit zero. Csmith output is never compared; Yarpgen output is discarded. Both report “differential OK.” A translator returning incorrect generated-program checksums can pass. The new RTS-22 implementation therefore adds execution without the claimed correctness oracle.
  - **Fix**: Run the identical generated binary through an independent oracle and each required engine. Compare complete outputs and exit statuses before reporting differential success.

- [x] **RTS-R2-5 — Medium — BUG — Yarpgen compilation passes unmatched source globs**
  - **Where**: `tools/run_grind.sh:560-574` (`run_weekly_soak`, Yarpgen branch).
  - **What breaks / Why**: The compiler receives both `"$_ydir"/*.c` and `"$_ydir"/*.cpp`. In POSIX shell, an unmatched glob remains a literal filename. A generated corpus containing only C++ or only C sources therefore supplies a nonexistent input and fails compilation. This becomes a tolerated SKIP under the default policy. The selected C compiler also does not explicitly provide C++ linkage.
  - **Fix**: Select the generator’s language explicitly, collect only existing source files, and use the matching compiler/linker. Treat compilation failure after successful prerequisite discovery as a failure.

- [x] **RTS-R2-6 — Medium — DEFECT — Signal remediation still does not test interrupted reservations or register restoration reliably**
  - **Where**: `tests/p3_torture.c:202-240`, `tests/p3_torture.c:272-293`, `tests/p3_torture.c:313-359` (`t_sig_frame_gpr`, `t_sig_frame_fpr`).
  - **What breaks / Why**: The atomic load precedes delivery, but the compare-exchange starts afterward; no LL/SC reservation spans the signal. A value-changing handler makes the later CAS fail even if reservation invalidation is entirely broken. Ordinary C variables across `raise()` do not guarantee particular registers remain live. The FP fallback similarly invokes a normal function call while operands reside in volatile memory, and the handler neither changes rounding mode nor deliberately raises the exception flags being checked.
  - **Fix**: Use small per-ISA fixtures to establish live registers and an actual exclusive-load/store interval across controlled delivery. Explicitly alter handler FP state and verify resumed state. Keep the portable cases, but label their narrower guarantees accurately.

- [x] **RTS-R2-7 — Medium — DEFECT — SPARC smoke binary bypasses the new freshness checks**
  - **Where**: `tools/bench_harness.sh:213-217`, `tools/bench_harness.sh:248-255`, `tools/bench_harness.sh:284-289`, `tools/bench_harness.sh:373-375`.
  - **What breaks / Why**: The fast builder refreshes `bench-sparc32`, while smoke execution prefers any existing `bench-sparc32-smoke`. The latter is rebuilt only by the broad fallback container. After a source/header change, a successful fast rebuild leaves the old smoke executable selected, so RTS-11 remains reproducible on this path.
  - **Fix**: Use one executable with `--smoke`, or apply the same dependency checks and rebuild/publication rules to both artifacts before selection.

- [x] **RTS-R2-8 — Medium — BUG — Benchmark EXIT trap references an expired local variable**
  - **Where**: `tools/bench_harness.sh:257-301`, `tools/bench_harness.sh:532-535` (`build_guest_bins`).
  - **What breaks / Why**: The EXIT trap stores a deferred reference to local `cname`. After a successful build returns, that local no longer exists. At shell exit, `set -u` makes its expansion fail. Cleanup can emit an unbound-variable error and does not reliably address the intended container. The trap also remains installed for later execution.
  - **Fix**: Scope the trap to a subshell whose lifetime owns the local variable, or maintain explicit invocation-level container ownership. Clear traps after successful cleanup.

- [x] **RTS-R2-9 — Medium — BUG — Linux benchmark load check selects an unsupported sysctl key**
  - **Where**: `tools/bench_harness.sh:303-319` (`check_calm_host`).
  - **What breaks / Why**: Presence of `sysctl` selects `vm.loadavg`, a Darwin/BSD key. Linux commonly has `sysctl` but exposes load through `/proc/loadavg`. The failed pipeline, combined with `set -euo pipefail`, aborts normal `run` before reaching benchmarks; the `/proc` fallback is never attempted.
  - **Fix**: Select the load source by platform or successful query, validate the numeric result, and fall back to `/proc/loadavg` when appropriate.

- [x] **RTS-R2-10 — Medium — DEFECT — Catalogue ignores failed summary counters**
  - **Where**: `tools/run_catalogue.sh:79-104`, `tools/run_catalogue.sh:896-907` (`check_parity_no_skip`, `run_repo_gate`).
  - **What breaks / Why**: Despite its updated contract, the checker extracts only `skip`. A delegated command returning zero with `PARITY_SUMMARY ... pass=0 fail=1 gap=0 skip=0` passes this check if no matching FAIL row exists. Smoke mode also accepts an empty log because category validation is disabled there.
  - **Fix**: Validate summary presence and syntax, repository identity, positive pass count, and zero failure/gap counts. Explicitly distinguish a supported non-parity fallback from malformed parity output.

- [x] **RTS-R2-11 — Medium — DEFECT — Benchmark success does not require complete workload records**
  - **Where**: `tools/bench_harness.sh:349-361` (`check_bench_output`).
  - **What breaks / Why**: Exit zero plus any `ALL_PASS` substring is sufficient. The five workload records, their checksums/statuses, and a valid final timing record are not required; absent timing is printed as `?`. This leaves RTS-3’s requested complete-record validation unfinished. Truncated or incorrectly forwarded output can still receive PASS.
  - **Fix**: Require exactly one valid record for each expected workload and one anchored final summary. Reject missing, duplicate, malformed, or contradictory records.

- [x] **RTS-R2-12 — Medium — BUG — Concurrent catalogue runs overwrite each other’s evidence**
  - **Where**: `tools/run_catalogue.sh:896-930` (`run_repo_gate`).
  - **What breaks / Why**: Logs use `/tmp/cat-$CMD-$_repo.log` without an invocation identifier. Concurrent runs for the same repository truncate and write the same file. Validation can read another run’s PASS rows or a mixed log, producing false results and destroying diagnostic evidence.
  - **Fix**: Allocate a unique invocation directory and pass its log paths through execution and validation. Preserve failed logs and clean up only owned files.

- [x] **RTS-R2-13 — Medium — DEFECT — Benchmark container cleanup remains incomplete on timeout and interruption**
  - **Where**: `tools/bench_harness.sh:213-243`, `tools/bench_harness.sh:448-457`, `tools/bench_harness.sh:468-485`.
  - **What breaks / Why**: Fast-path build containers have no cleanup trap or explicit removal after timeout. Runtime containers are removed only after command substitution completes; interrupting the harness bypasses that code. `--rm` removes a container when it exits, but terminating a Docker client does not establish that the daemon-owned workload exited. Removal failures are swallowed without verification.
  - **Fix**: Track all owned container IDs, install invocation-scoped exit/signal cleanup, and verify removal after success, failure, timeout, and interruption.

- [x] **RTS-R2-14 — Medium — DEFECT — Golden-update failures can return success**
  - **Where**: `tools/parity_contract.sh:89-101` (`parity_check_golden`).
  - **What breaks / Why**: Update mode executes `mkdir` and `cp`, then unconditionally returns zero. When called in an `if` or other tested context, shell `errexit` does not reliably terminate on those failures. Missing input or an unwritable golden can therefore be reported as a successful update.
  - **Fix**: Explicitly propagate directory-creation and copy errors. Copy to a temporary file and atomically rename only after successful completion.

#### Low

No additional BUG/DEFECT findings.

### 11.2 Curated C11 & UB Issues

- [x] **RTS-R2-15 — Medium — C11 — Fault handlers communicate through ordinary static address objects**
  - **Where**: `tests/p3_torture.c:84-88`, `tests/p3_torture.c:163-172`, `tests/p3_torture.c:529-545`; `tests/tcg/smoke_tcg.c:80-96`, `tests/tcg/smoke_tcg.c:160-175` (`g_segv_addr`, `g_got_addr`).
  - **What breaks / Why**: Both handlers assign ordinary static `uintptr_t` objects that normal execution subsequently reads. These objects have neither the `volatile sig_atomic_t` signal-communication guarantee nor lock-free atomic semantics. The deliberate fault probes necessarily depend on platform extensions, but that does not establish portable C11 signal communication for these address fields.
  - **Fix**: Use a demonstrably lock-free atomic address representation supported by the target, or an explicitly documented platform signal bridge. Verify lock-free support before entering the handler; do not introduce a locking atomic helper there.

No banned-function calls, textual `.c` includes, explicit `x18` references, `_Generic`, or `<threads.h>` references were returned by the source search. All inventoried `.c`/`.h` files are below 900 lines; the largest is `tests/p3_torture.c` at 658 lines. These observations are not compiler or sanitizer validation.

### 11.3 DRY — Intra-Repo Duplication

- [x] **RTS-R2-16 — Low — DRY — Translator invocation policy is duplicated across runners**
  - **Where**: `tools/bench_harness.sh:322-347` (`build_rt_args`), `tools/run_grind.sh:83-97` (`resolve_arch_defaults`), `tools/remote_bench.sh:26-88`, `tools/remote_linux_inner.sh:36-68`.
  - **What breaks / Why**: Four paths independently encode engine flags, environment variables, separators, and backend invocation. They already differ: remote `rvrt` interpreter execution uses `--engine interp`, while benchmark/grind construction uses `--interp`; other engines alternate between environment and command-line selection. Each future CLI change requires synchronized edits.
  - **Fix**: Centralize the architecture/backend invocation contract in a repository-local helper, retaining argument boundaries. This is tooling reuse within `rt-series`, not a shared translator C library.

### 11.4 YAGNI — Dead Code & Speculative Scaffolding

- [x] **RTS-R2-17 — Low — YAGNI — Fault signal code is recorded but never checked**
  - **Where**: `tests/p3_torture.c:87-87`, `tests/p3_torture.c:167-169`, `tests/p3_torture.c:539-599` (`g_segv_code`, `t_mprotect_munmap`).
  - **What breaks / Why**: `g_segv_code` is write-only. The fixture collects fault provenance but never distinguishes protection faults from unmapped-address faults. Later probes also omit fresh address validation, despite the combined success message claiming fault-address checking.
  - **Fix**: Reset and validate signal number, platform-appropriate code, and fault address for each probe. Otherwise remove unused collection and narrow the advertised coverage.

### 11.5 CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [x] **RTS-R2-18 — Medium — CLEAN — HEAD declares complete remediation despite demonstrably incomplete fixes**
  - **Where**: `DEFECTS.md:14-14`, `DEFECTS.md:28-29` (remediation status and `rt-series` verification row).
  - **What breaks / Why**: HEAD declares all findings resolved and `rt-series` fully verified. Current code still has incomplete RTS-4 architecture routing, RTS-6 qualification evidence, RTS-11 freshness handling, and RTS-16 signal coverage. Reported passing gates cannot establish those missing semantics.
  - **Fix**: Reopen the affected original findings and distinguish implemented changes, executed checks, and remaining verification gaps. Retain historical results without presenting them as proof of complete remediation.

The 900-line C/header ceiling is satisfied. The 1,059-line catalogue shell script is outside that specific ceiling; its size alone is not counted as a violation.

---

## Part VII — Round-1 Audit Archive (187 Items Addressed in Round-1 Commits)

> [!NOTE]
> The 187 items below record the Round-1 `gpt-6-astra` audit and the Round-1 commits (`a5f53b4`, `8db8727`, `366ca9b`, `abe6b0b`, `dad95da`, `8e207fb`, `026e87d`, `bd3e73f`, `32d5c9e`, `3ead4f9`, `96e1fe6`). Where Round-2 static inspection found that a Round-1 fix was incomplete or introduced a follow-up edge case, the corresponding open item is tracked in **Part I (Round 2)** above (`§0.1` and `§1..§11`).

### Cross-Cutting Defect Clusters (Wave Planning Index)

- [x] **X-1 — High — Darwin A2 16 KiB Sub-Page Protection & Soft-TLB Fast-Path Integrity**
  - **Linked Items**: `A32-1`, `A32-2`, `I686-1`, `I686-16`, `M32-7`, `P32-4`, `S32-1`, `S32-15`, `RV-4`, `LA64-1`, `LA64-2`, `LA64-8`, `M64-2`
  - **Summary**: Cross-page unaligned accesses only checking the starting 4 KiB page (`A32-1`), multiword/atomic emitters bypassing Soft-TLB on A2 (`A32-2`, `P32-4`), `i686rt` spurious fault counter permanently opening 16 KiB host pages after 64 faults (`I686-1`), write-only pages leaving stale `read_tag` (`RV-4`) or zero `addend` (`M64-2`), and mixed sub-page permissions on Darwin leaving host pages inaccessible (`LA64-2`).
- [x] **X-2 — High — `MAP_SHARED` File / Anonymous Backing & `mremap` Backing Preservation**
  - **Linked Items**: `A32-3`, `A32-4`, `A32-11`, `I686-7`, `M32-3`, `M32-4`, `M32-17`, `P32-5`, `S32-7`, `S32-8`, `LA64-7`, `P64-7`, `P64-8`, `P64-9`, `M64-1`, `S64-6`, `S64-9`
  - **Summary**: Darwin sub-page `MAP_SHARED` file mappings silently falling back to private `pread` copies (`A32-4`, `M32-3`, `S32-8`), `MAP_SHARED | MAP_ANONYMOUS` forced to `MAP_PRIVATE` (`A32-3`), `mremap` replacing file/shared backing with anonymous memory (`I686-7`, `M32-4`, `P32-5`, `S32-7`) or destroying destination mappings on failed `MREMAP_FIXED` (`P64-7`, `P64-8`, `P64-9`).
- [x] **X-3 — High — Multi-Threaded SMC / Code-Cache Invalidation, W^X & Arena Lifecycle**
  - **Linked Items**: `I686-2`, `I686-3`, `I686-6`, `I686-11`, `M32-5`, `M32-6`, `S32-4`, `S32-5`, `RV-1`, `RV-3`, `M64-11`, `M64-16`, `S64-2`
  - **Summary**: Thread-local code caches missing cross-thread SMC/munmap invalidation (`I686-2`, `M32-5`), clone threads unmapping shared JIT arenas while parent threads execute (`S32-5`), ignored W^X `mprotect` errors (`RV-3`, `S64-2`), Linux RWX JIT allocation in `i686rt` (`I686-11`), and unbounded arena growth (`M64-11`).
- [x] **X-4 — High — Atomic / LL-SC Reservation Coherence, Memory Barriers & Data Races**
  - **Linked Items**: `A32-13`, `I686-4`, `P32-3`, `P32-4`, `P32-10`, `S32-3`, `P64-1`, `P64-11`, `M64-3`
  - **Summary**: Unsynchronized process-global reservation state (`A32-13`, `P32-10`, `P64-1`), ABA-vulnerable value-comparison SC without write invalidation (`M64-3`), `LDSTUB` holding a process-wide lock across guest execution (`S32-3`), no-op memory barriers (`P32-3`, `I686-4`), and narrow atomics performing 8-byte CAS across page boundaries (`P64-11`).
- [x] **X-5 — High — Signal Multiplexing, Blocked-Mask Coherence, `rt_sigaction` & `rt_sigreturn`**
  - **Linked Items**: `A32-6`, `A32-9`, `I686-5`, `I686-8`, `I686-10`, `M32-1`, `M32-8`, `M32-11`, `M32-12`, `S32-9`, `S32-10`, `S32-11`, `LA64-3`, `P64-4`, `P64-5`, `P64-6`, `M64-4`, `M64-6`
  - **Summary**: Blocked signals delivered immediately or disconnected masks between `rt_sigprocmask` and delivery/sigreturn (`M32-8`, `S32-9`, `P64-5`), `rt_sigaction(sig, NULL, oldact)` wiping dispositions (`P64-4`), `SIG_DFL` pending signals silently dropped (`I686-8`), instruction traps routed as `SIGSEGV` (`M64-4`), and unsynchronized global signal state across threads (`M32-12`).
- [x] **X-6 — High — Syscall Pointer Validation (`-EFAULT`), Transactional `execve`, `clone` & `futex`**
  - **Linked Items**: `A32-5`, `A32-10`, `M32-2`, `M32-9`, `M32-13`, `P32-6`, `P32-8`, `P32-9`, `S32-1`, `S32-2`, `S32-6`, `RV-2`, `LA64-6`, `P64-2`, `P64-3`, `P64-10`, `M64-7`, `M64-12`, `S64-4`, `S64-5`, `S64-7`, `S64-8`, `S64-11`
  - **Summary**: Unchecked guest pointers faulting in translator C/libc instead of returning `-EFAULT` (`A32-5`, `M32-13`, `P32-6`, `S32-1`), `execve` destroying the caller's VM/signals before validating the target ELF (`M32-2`, `S32-2`), inline child-to-completion `clone` (`P64-2`) or interpreter-only `clone` workers (`M64-12`), stubbed `futex` (`P64-3`, `S64-5`), and `pthread_create`/`pthread_kill` returning `-errno` instead of `-rc` (`RV-2`, `P32-9`) or reading expired parent stack (`S64-11`).
- [x] **X-7 — High — ISA Decode / Lowering Bugs & Curated C11 Undefined Behavior**
  - **Linked Items**: `A32-7`, `A32-8`, `A32-12`, `A32-14`, `I686-9`, `I686-12`, `I686-13`, `I686-14`, `M32-10`, `M32-14`, `P32-1`, `P32-2`, `P32-7`, `P32-11`, `S32-12`, `S32-13`, `RV-5`, `RV-6`, `LA64-4`, `LA64-5`, `LA64-9`, `P64-12`, `M64-5`, `M64-8`, `M64-9`, `M64-10`, `M64-13`, `M64-14`, `S64-1`, `S64-3`, `S64-10`, `RTS-1`, `RTS-18`, `RTS-19`
  - **Summary**: Thumb-2 `B.W` condition/displacement bugs (`A32-7`), PowerPC `OE=1` decode failure (`P32-1`), PowerPC `tw`/`twi` ANDing instead of ORing TO predicates (`P32-2`), MIPS64 `MADD`/`MSUB` unmasked sign-extended `LO` (`M64-5`), SPARC64 `MOVcc (fcc)` misclassified as `MEMBAR` (`S64-3`), LoongArch64 LSX failing to zero upper 128 bits of LASX (`LA64-4`) and difftest re-running interpreter instead of DBT (`LA64-5`), plus signed left-shift UB and float-to-int UB.
- [x] **X-8 — Medium — Intra-Repo DRY & YAGNI Cleanup**
  - **Linked Items**: `A32-15`, `A32-16`, `I686-15`, `I686-16`, `M32-15`, `M32-16`, `M32-17`, `M32-18`, `P32-12`, `P32-13`, `S32-14`, `S32-15`, `RV-7`, `RV-8`, `LA64-10`, `LA64-11`, `P64-13`, `P64-14`, `M64-15`, `M64-16`, `S64-12`, `S64-13`, `RTS-20`, `RTS-21`, `RTS-22`
- [x] **X-9 — Medium — CLEAN Hygiene (`#include "*.c"` Unity Includes, 900-Line Ceiling, `-Werror` & Harness Gates)**
  - **Linked Items**: `A32-17`, `A32-18`, `I686-17`, `I686-18`, `I686-19`, `I686-20`, `M32-19`, `M32-20`, `P32-14`, `P32-15`, `S32-16`, `S32-17`, `S32-18`, `RV-9`, `RV-10`, `LA64-12`, `LA64-13`, `P64-15`, `P64-16`, `M64-17`, `M64-18`, `S64-14`, `RTS-2..RTS-17`, `RTS-23..RTS-25`

---

### R1-1. `a32rt` (`55cdc5f` → `a5f53b4`) — 18 / 18 Resolved

### 1.1 Bugs & Defects

- [x] **A32-1 — High — BUG — Soft-TLB fast path checks only the starting page**
  - **Where**: `src/core/core_emit_alu.c:676-732` (`emit_guest_mem`); `src/os/backend_darwin.c:164-184` (`a32_backend_protect`).
  - **What breaks / Why**: Generated A2 accesses compare the starting virtual page’s tag and then execute the host access without checking alignment or whether the access crosses a 4 KiB boundary. A word load at page offset `4094` can read two bytes from an adjacent guest `PROT_NONE` page because Darwin keeps covering 16 KiB host pages RW.
  - **Fix**: Check the complete access span before the host instruction (or reject unaligned/cross-page offsets on the fast path) and route cross-page accesses through a checked slow path that validates both guest pages and preserves fault state.

- [x] **A32-2 — High — BUG — Doubleword transfers bypass A2 guest permissions**
  - **Where**: `src/core/core_emit_mem.c:20-40` (`a64_emit_guest_ldrd_w`, `a64_emit_guest_strd_w`); `src/interp/interp_t32_mem.c:269-305` (LDRD/STRD lowering); `src/os/backend_darwin.c:175-184` (`a32_backend_protect`).
  - **What breaks / Why**: `LDRD`/`STRD` emit a direct guest-base addition followed by host `LDP`/`STP`, bypassing the Soft-TLB. On Darwin A2, `STRD` can modify guest read-only memory and `LDRD` can read guest-inaccessible memory.
  - **Fix**: Give `a64_emit_guest_ldrd_w` / `a64_emit_guest_strd_w` (and any other multiword/vector/exclusive emitters) an A2 permission-checked implementation covering the full 8-byte span.

- [x] **A32-3 — High — BUG — Anonymous shared mappings become private**
  - **Where**: `src/vm/vm_file.c:145-147` (`a32_vmfile_map_commit`); `src/os/backend_linux.c:67-84` and `src/os/backend_darwin.c:65-95` (`a32_backend_map_anon`).
  - **What breaks / Why**: The anonymous branch discards the requested sharing mode; both backends hardcode `MAP_PRIVATE | MAP_ANONYMOUS`. A guest `MAP_SHARED | MAP_ANONYMOUS` mapping becomes private across host `fork()`, breaking shared-memory IPC and shared futexes.
  - **Fix**: Carry `shared` through `a32_backend_map_anon` and preserve it across fork and remap paths.

- [x] **A32-4 — High — BUG — Darwin MAP_SHARED file mappings are private byte copies**
  - **Where**: `src/os/backend_darwin.c:107-142` (`a32_backend_map_file`); `src/vm/vm_file.c:149-151` (`a32_vmfile_map_commit`).
  - **What breaks / Why**: The normal replacement path zeroes the arena and fills it with `pread`, returning before the actual file-backed `mmap` even when `shared` is true. Writes through the mapping do not update the underlying file or alias mappings.
  - **Fix**: Implement shared file backing that preserves file identity and alias coherence (or reject unsupported unaligned shared mappings explicitly instead of silently copying them).

- [x] **A32-5 — High — BUG — Pathname validation can fault inside the translator**
  - **Where**: `src/os/os_sys_path.c:416-430` (`resolve_guest_path_at`).
  - **What breaks / Why**: Only the first byte is checked with `a32_guest_range_ok`; `strnlen(gpath, PATH_MAX)` then reads directly across subsequent pages. A nonterminated string ending at a readable page boundary followed by an inaccessible page faults in host libc instead of returning guest `-EFAULT`.
  - **Fix**: Copy guest strings into a bounded host buffer using page-aware, fault-safe reads before resolving the path.

- [x] **A32-6 — High — BUG — Synchronous faults outside JIT blocks retry forever**
  - **Where**: `src/signals.c:392-429` (`host_sig_handler`).
  - **What breaks / Why**: A genuine synchronous fault whose host PC is outside the JIT cache is enqueued as an asynchronous signal, then the handler returns without advancing the faulting PC, causing an infinite fault loop.
  - **Fix**: Distinguish user-generated signals (`si_code <= 0`) from synchronous hardware faults outside the JIT cache; recover checked guest-memory helper accesses via fault recovery and abort on genuine translator crashes.

- [x] **A32-7 — High — BUG — Thumb-2 interpreter branch decoder ignores conditions and mixes encodings**
  - **Where**: `src/interp/interp_thumb.c:606-633` (`t32_step`).
  - **What breaks / Why**: The broad branch match includes conditional `B.W` (`T3`) and unconditional `B.W` (`T4`), never evaluates the condition for `T3`, selects displacement format using `hw1 & 0x0800` instead of `hw2` bit 12, and writes `LR` on one `B.W` path.
  - **Fix**: Decode conditional `B.W` (`T3`) and unconditional `B.W` (`T4`) separately using `hw2` bits `[15:12]`, evaluate the condition code for `T3`, reconstruct `J1`/`J2`/`S` displacements per ARMv7-A spec, and never write `LR` on non-link branches.

- [x] **A32-8 — Medium — BUG — Thumb immediate shifts produce incorrect flags and LSR results**
  - **Where**: `src/interp/interp_thumb.c:95-124` (Thumb immediate shifts).
  - **What breaks / Why**: Immediate `LSR` with `imm5 == 0` encodes `LSR #32`, but the interpreter treats `imm5 == 0` as shift-by-0 and calls `i_set_nzcv(..., false)`, clearing `V` instead of preserving `V`.
  - **Fix**: Handle `LSR #32` (`result = 0`, `C = Rm[31]`) and `ASR #32` (`result = Rm >> 31`, `C = Rm[31]`) explicitly, preserve `V`, and respect IT-block flag suppression.

- [x] **A32-9 — Medium — BUG — Interpreter memory faults bypass guest signal handlers**
  - **Where**: `src/interp/interp.c:243-268` (`a32_interp_run`).
  - **What breaks / Why**: `A32_EXIT_FAULT` immediately returns exit code `139` instead of routing through guest `SIGSEGV`/`SIGBUS` signal delivery, unlike the DBT dispatcher.
  - **Fix**: Route interpreter memory faults through the guest fault-delivery policy and resume execution when a guest handler catches the signal.

- [x] **A32-10 — Medium — BUG — Startup silently truncates arguments and environment**
  - **Where**: `src/stack32.c:84-100` (`push_string_table`); `src/stack32.c:144-150` (`a32_stack_setup`).
  - **What breaks / Why**: Collection silently stops at 511 `argv` or `envp` strings without reporting `-E2BIG`, starting the guest with truncated arguments/environment.
  - **Fix**: Dynamically size the pointer table from validated counts or return an explicit `-E2BIG` error when the limit is exceeded.

- [x] **A32-11 — Medium — BUG — File-shrink invalidation uses file offsets as guest addresses and invalidates nothing**
  - **Where**: `src/vm/vm_file.c:248-274` (`vmfile_sync_size`); `src/vm/vm32.c:176-191` (`a32_vm32_tlb_invalidate_range`).
  - **What breaks / Why**: Shrinking an inode computes `cut` as a file offset and calls `a32_vm32_tlb_invalidate_range(cut, 0U)`, which does nothing because `end <= start` and `cut` is not a guest VA.
  - **Fix**: Translate the truncated file offset range into each mapping's guest VA range and invalidate the corresponding guest pages.

### 1.2 Curated C11 & UB Issues

- [x] **A32-12 — High — C11 — Thumb shifts and branch arithmetic invoke undefined behavior**
  - **Where**: `src/interp/interp_thumb.c:54-56`, `src/interp/interp_thumb.c:114-121`, `src/interp/interp_thumb.c:556-560`, `src/interp/interp_thumb.c:620-632`.
  - **What breaks / Why**: `ASR` with `imm == 0` evaluates a 32-bit shift by 32 before overwriting the result; backward short/wide branches left-shift negative signed `int32_t` values.
  - **Fix**: Guard `imm == 0` before shifting and construct branch displacements using unsigned arithmetic before casting to signed.

- [x] **A32-13 — High — C11 — Interpreter exclusive-monitor state is process-global and unsynchronized**
  - **Where**: `src/interp/interp_a32.c:20-62` (`g_excl_valid`, `g_excl_addr`, `g_excl_size`, `do_ldrex`, `do_strex`).
  - **What breaks / Why**: Concurrent interpreter steps or DBT fallbacks read and write static globals without synchronization (C11 data race) and overwrite sibling threads' local monitor state.
  - **Fix**: Move local exclusive-monitor state into `a32_ctx_t` and synchronize shared global reservation invalidation atomically.

- [x] **A32-14 — Medium — C11 — Failed fstat leaves EOF handling reading uninitialized data**
  - **Where**: `src/vm/vm_file.c:165-203` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: `struct stat st` is uninitialized; if `fstat` fails, execution continues and reads uninitialized `st.st_size` on EOF.
  - **Fix**: Check and return the `fstat` error before entering the population loop.

### 1.3 DRY, YAGNI & CLEAN

- [x] **A32-15 — Low — DRY — File population is implemented independently in two layers**
  - **Where**: `src/os/backend_darwin.c:125-140` (`a32_backend_map_file`); `src/vm/vm_file.c:185-214` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: Both implement a `pread` loop with `EINTR` retry and EOF zero-fill with diverging error handling.
  - **Fix**: Consolidate private-file population into one helper inside `a32rt`.

- [x] **A32-16 — Low — YAGNI — Obsolete global file hooks remain publicly declared without callers**
  - **Where**: `src/vm/vm_file.c:303-340` (`a32_vmfile_on_truncate`, `a32_vmfile_hook_write`); `src/vm/vm32.h:214-215`.
  - **What breaks / Why**: Dead public functions with zero callers in `src/`, `tests/`, or `tools/`.
  - **Fix**: Remove the unused declarations and definitions.

- [x] **A32-17 — Medium — CLEAN — Source splitting relies on forbidden textual unity includes**
  - **Where**: `src/a64_emit.c:9-11`, `src/decode_a32.c:9-10`, `src/decode_t32.c:9-11`, `src/vfp_neon.c:9-11`, `src/jit.c:9-12`, `src/aot.c:9-10`, `src/syscalls.c:9-15`.
  - **What breaks / Why**: Seven top-level `.c` files textually `#include` sub-`.c` files, violating the no-unity-includes rule.
  - **Fix**: Compile each implementation `.c` file as a separate translation unit in `Makefile` with narrow internal headers.

- [x] **A32-18 — Low — CLEAN — Four test sources exceed the mandatory 900-line ceiling**
  - **Where**: `tests/test_m1_isa_fs.c:1-3702`, `tests/test_m3_threads_signals.c:1-3182`, `tests/test_m4_vfp_neon.c:1-3233`, `tests/test_m5_ltp_gdb.c:1-2587`.
  - **What breaks / Why**: Four test translation units exceed 900 lines (`2,587` to `3,702` lines); `src/vm.c` (`895`) and `src/os/os_sys_sig_time.c` (`885`) are also near the ceiling.
  - **Fix**: Split the four test suites into separately compiled `<900`-line files and extend `check-line-limits` to `tests/`.

---

### R1-2. `i686rt` (`2fa17fb` → `8db8727`) — 20 / 20 Resolved

### 2.1 Bugs & Defects

- [x] **I686-1 — High — BUG — A2 fault recovery permanently opens protected sub-pages**
  - **Where**: `src/os/signals_i386.c:707-754` (`i686_spurious_emulate`); `src/vm/vm32.c:148-173` (`i686_vm32_union_prot`).
  - **What breaks / Why**: After a 16 KiB host page's spurious-fault counter reaches 64, recovery applies the union of 4 KiB sub-page permissions and returns without restoring the restrictive cover. A writable 4 KiB neighbor permanently exposes adjacent `PROT_NONE` or read-only 4 KiB sub-pages to direct guest reads/writes.
  - **Fix**: Remove the leave-open heuristic and wire the A2 Soft-TLB fast path (`I686-16`) so sub-page permissions are enforced in software on every access.

- [x] **I686-2 — High — BUG — SMC invalidation leaves other threads executing stale code**
  - **Where**: `src/dbt/engine.c:86-116` (`s_ht`, `s_code_pages`, `s_run_ctx`); `src/dbt/engine.c:302-332` (`smc_drop_host`); `src/dbt/engine.c:403-426` (`i686_dbt_smc_write_fault`).
  - **What breaks / Why**: Code caches are thread-local (`_Thread_local`), while `s_code_pages` and host page protections are shared. An SMC write fault clears only the faulting thread's cache and unprotects the page process-wide, leaving sibling threads executing stale translations.
  - **Fix**: Maintain shared per-page code generations and validate/invalidate caches across all worker threads on SMC and `munmap`/`mprotect`.

- [x] **I686-3 — High — BUG — SMC handling overrides guest memory permissions**
  - **Where**: `src/dbt/engine.c:174-207` (`smc_unprotect_host`, `smc_protect`); `src/dbt/engine.c:335-360` (`i686_dbt_invalidate_range`); `src/rt32/rt32_vm.c:974-988` (`rt32_vm_mprotect`).
  - **What breaks / Why**: `smc_unprotect_host` blindly sets `PROT_READ | PROT_WRITE` without checking whether the guest VMA is actually writable. Calling `rt32_vm_mprotect(..., PROT_READ)` followed by `i686_dbt_invalidate_range` immediately re-applies `PROT_READ | PROT_WRITE` to pages marked in `s_code_pages`.
  - **Fix**: Treat a write fault as SMC only if the guest VMA has `PROT_WRITE`, and restore host permissions from the current guest VMA protection mask rather than hardcoded `PROT_READ | PROT_WRITE`.

- [x] **I686-4 — High — BUG — Threaded DBT execution never enables TSO lowering**
  - **Where**: `src/dbt/emit_exit.c:38-47` (`i686_emit_begin`); `src/dbt/emit_alu.c:128-155` (guest-memory lowering); `src/dbt/emit_sse.c:786-792` (`I686_OP_SFENCE`).
  - **What breaks / Why**: `i686_emit_begin` zeroes `e->tso` and nothing ever sets `e->tso = true` when threads are spawned; `SFENCE` is also emitted as a no-op. Multi-threaded guest code runs with weak AArch64 memory ordering instead of x86 TSO (`LDAR`/`STLR` / `DMB`).
  - **Fix**: Enable `e->tso` (and flush single-threaded translations) as soon as a second thread is created, and emit `dmb ishst` / `dmb ish` for `SFENCE` / `MFENCE`.

- [x] **I686-5 — High — BUG — Flag elimination crosses faulting instructions**
  - **Where**: `src/dbt/translate.c:98-105`, `src/dbt/translate.c:160-182`, `src/dbt/translate.c:239-260` (`tr_classify`, skip analysis); `src/dbt/emit_alu.c:258-264`, `src/dbt/emit_alu.c:379-408`.
  - **What breaks / Why**: Dead-flag elimination treats memory `MOV` instructions as flag-transparent and elides flag computation before a memory access if a subsequent instruction overwrites flags. If the `MOV` faults, the guest `SIGSEGV` `ucontext` receives stale `EFLAGS`.
  - **Fix**: Treat any potentially faulting memory or division instruction as a flag-observation barrier during dead-flag analysis.

- [x] **I686-6 — High — BUG — Translation pre-scan faults on instructions that will not execute**
  - **Where**: `src/dbt/translate.c:224-238` (`i686_dbt_translate` pre-scan); `src/x86/decode.c:76-80` (`fetch8`).
  - **What breaks / Why**: The pre-scan loop decodes up to 64 instructions without stopping at unconditional control-flow terminators (`RET`, `JMP`, `INT`). Decoding past a terminator at the end of a page can fault on an unmapped following page.
  - **Fix**: Stop the pre-scan loop at basic-block terminators and page boundaries.

- [x] **I686-7 — High — BUG — Moving or growing mremap loses backing-object semantics**
  - **Where**: `src/rt32/rt32_vm.c:1079-1081`, `src/rt32/rt32_vm.c:1102-1107`, `src/rt32/rt32_vm.c:1141-1162` (`rt32_vm_mremap`).
  - **What breaks / Why**: `rt32_vm_mremap` allocates anonymous mappings for extensions and moves regardless of the original file/shared backing.
  - **Fix**: Preserve file backing, offset, and `MAP_SHARED` identity across `mremap` extensions and moves.

- [x] **I686-8 — High — BUG — Default-action pending signals are silently discarded**
  - **Where**: `src/os/signals_i386.c:823-852` (`i686_deliver_pending`).
  - **What breaks / Why**: Unblocked pending signals whose handler is `SIG_DFL` (`0`) take the same bit-clearing branch as `SIG_IGN`, silently dropping fatal or stop signals.
  - **Fix**: Implement the Linux default-action table (`Term`, `Core`, `Stop`, `Ign`, `Cont`) when delivering unblocked `SIG_DFL` signals.

- [x] **I686-9 — Medium — BUG — SSE double arithmetic ignores guest rounding mode**
  - **Where**: `src/interp/h_sse.c:405-458` (`sse_f64_op`).
  - **What breaks / Why**: `ADDSD`/`SUBSD`/`MULSD`/`DIVSD`/`ADDPD` etc. execute host `double` arithmetic without applying `MXCSR.RC`.
  - **Fix**: Apply the guest `MXCSR` rounding mode (`fesetround` or FPCR rounding control) around SSE FP operations.

- [x] **I686-10 — Medium — BUG — Signal frames export binary64 storage as x87 extended precision**
  - **Where**: `src/i686rt.h:144-146` (`x87_st` representation contract); `src/os/signals_i386.c:159-171` (`i686_sigframe_build`).
  - **What breaks / Why**: In default binary64 x87 mode, `i686_sigframe_build` raw-copies 10 bytes from each slot into the 80-bit `_fpstate` register array without converting `double` to 80-bit IEEE extended precision.
  - **Fix**: Convert binary64 `x87_st` values to/from 80-bit `fp80` when constructing and restoring signal frames.

- [x] **I686-11 — Medium — DEFECT — Linux JIT mappings remain writable and executable**
  - **Where**: `src/dbt/engine.c:656-704` (`dbt_get_or_compile`).
  - **What breaks / Why**: On Linux, the JIT code buffer is mapped `PROT_READ | PROT_WRITE | PROT_EXEC` and never sealed `PROT_READ | PROT_EXEC`, violating the `AGENTS.md` §2.2 W^X invariant.
  - **Fix**: Emit into RW staging or toggle W^X (`PROT_READ | PROT_WRITE` -> `PROT_READ | PROT_EXEC`) on Linux as well as Darwin.

### 2.2 Curated C11 & UB Issues

- [x] **I686-12 — High — C11 — Fault recovery unlocks a mutex without proving ownership**
  - **Where**: `src/dbt/engine.c:44-51` (`s_jit_toggle_mutex`); `src/dbt/engine.c:744-762` (`i686_dbt_run` fault recovery).
  - **What breaks / Why**: On `sigsetjmp` recovery from any guest fault on Darwin, `i686_dbt_run` calls `pthread_mutex_unlock(&s_jit_toggle_mutex)` even when the fault occurred during normal JIT execution with the mutex unlocked. Unlocking an unowned/unlocked default mutex is C11/POSIX UB.
  - **Fix**: Track lock ownership in a `_Thread_local` flag and only unlock `s_jit_toggle_mutex` if the current thread holds it.

- [x] **I686-13 — High — C11 — Global fault-site cursor races between translators**
  - **Where**: `src/dbt/emit_mov.c:91-127` (`s_pc_ctx`, `s_pc_base`, `s_pc_buf`, `s_pc_cur`, `site_pc`).
  - **What breaks / Why**: `site_pc` mutates four static non-atomic globals during translation without a lock on Linux, racing across threads and corrupting fault-recovery PC metadata.
  - **Fix**: Use `e->insn_pc` directly from the per-translation `i686_emit_t` struct and delete the static globals.

- [x] **I686-14 — Medium — C11 — Signal tracing dereferences byte arrays through uint32_t pointers**
  - **Where**: `src/os/signals_i386.c:293-318` (`i686_sigframe_build`).
  - **What breaks / Why**: Casts `uint8_t tcbdump[16]` to `const uint32_t *`, violating strict aliasing and alignment rules.
  - **Fix**: Read words via `memcpy` into `uint32_t` locals.

### 2.3 DRY, YAGNI & CLEAN

- [x] **I686-15 — Low — DRY — Host-page-size discovery is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:71-81`; `src/os/backend_darwin.c:56-66` (`rt_host_page_size`).
  - **What breaks / Why**: Identical `sysconf(_SC_PAGESIZE)` caching helper duplicated in both backend files.
  - **Fix**: Share a single internal helper within `i686rt`.

- [x] **I686-16 — Low — YAGNI — Allocated Soft-TLB has no production fill integration**
  - **Where**: `src/vm/vm32.c:58-75` (`i686_vm32_init`); `src/vm/vm32.c:91-120` (`i686_vm32_tlb_fill`); `src/trampoline.S:47-48` (`i686_jit_run_block`).
  - **What breaks / Why**: `i686_vm32_init` allocates a Soft-TLB, but `i686_vm32_tlb_fill` has no production callers and `trampoline.S` loads `guest_base` into `x20`.
  - **Fix**: Wire the Soft-TLB into A2 memory emission and miss handling (fixing `I686-1`), or remove the dead allocation until wired.

- [x] **I686-17 — Medium — CLEAN — Twenty-three files exceed the 900-line limit**
  - **Where**: 14 runtime files (`src/interp/x87_80.c` 2971, `src/interp/h_x87.c` 2276, `src/interp/h_sse.c` 2156, `src/os/sys_pass.c` 2108, `src/os/sys_misc.c` 1249, `src/rt32/rt32_a64_emit.c` 1235, `src/os/sys_sock.c` 1216, `src/rt32/rt32_vm.c` 1182, `src/os/sys_ipc.c` 1170, `src/os/sys_time.c` 1080, `src/interp/v86.c` 975, `src/x86/insn_tab.h` 960, `src/os/syscalls_i386.h` 951, `src/dbt/engine.c` 930) and 9 test files (`tests/probe_strfuncs.c` 1473, `tests/unit/test_l5d.c` 1301, `tests/unit/test_l1d.c` 1271, `tests/unit/test_l1e.c` 1083, `tests/test_p1_isa.c` 1039, `tests/unit/test_l5c.c` 998, `tests/unit/test_l1b.c` 966, `tests/unit/test_l5b.c` 957, `tests/unit/test_l5a.c` 938); `Makefile:238-262`.
  - **What breaks / Why**: 23 files exceed the mandatory 900-line ceiling because `Makefile` only checks a subset of files.
  - **Fix**: Split all 23 files into separately compiled `<900`-line translation units and enforce a repo-wide `check-line-limits` gate.

- [x] **I686-18 — Low — CLEAN — Default test target reports obsolete phase-zero status**
  - **Where**: `Makefile:91-97` (`test`, `test-p0-lima`).
  - **What breaks / Why**: `make test` prints `"phase 0: no tests yet"` and exits 0 without running any tests.
  - **Fix**: Wire `make test` to the active unit/parity test suite.

- [x] **I686-19 — Low — CLEAN — A2 VM documentation describes a different execution path**
  - **Where**: `src/vm/vm32.c:14-21`; `src/i686rt.h:64-67`; `src/trampoline.S:47-48`.
  - **What breaks / Why**: Comments claim `x20` holds the Soft-TLB base on A2 and emits a 7-instruction probe, contradicting `trampoline.S`.
  - **Fix**: Keep comments synchronized with the actual `x20` / Soft-TLB implementation.

- [x] **I686-20 — Low — CLEAN — Pending-signal documentation contradicts its clearing behavior**
  - **Where**: `src/os/signals_i386.c:814-844` (`i686_deliver_pending`).
  - **What breaks / Why**: Comment claims `SIG_DFL`/`SIG_IGN` bits survive polling while the code clears them.
  - **Fix**: Update the comment alongside fixing `I686-8`.

---

### R1-3. `mips32rt` (`e0b10a2` → `366ca9b`) — 20 / 20 Resolved

### 3.1 Bugs & Defects

- [x] **M32-1 — High — BUG — FP branch fault handling overwrites the delivered signal handler PC**
  - **Where**: `src/interp/fp.c:829-843` (`fp_bc1`); `src/os/signals.c:673-682` (`mips_raise_guest_code`).
  - **What breaks / Why**: When a delay-slot instruction under `BC1T`/`BC1F` faults and synchronously delivers a guest signal handler (which sets `ctx->pc` to the handler), `fp_bc1` overwrites `ctx->pc` with `branch_pc`, retrying the branch instead of running the signal handler.
  - **Fix**: Set delay-slot state before fetching the slot and preserve `ctx->pc` when a guest signal handler has been delivered.

- [x] **M32-2 — High — BUG — Failed execve destroys the calling program**
  - **Where**: `src/os/proc.c:384-412` (`mips_proc_execve`).
  - **What breaks / Why**: `rt32_vm_reset_for_exec` destroys the old guest address space before validating the ELF header, loading `PT_INTERP`, or allocating the new stack. Any subsequent error returns `-errno` into an empty address space.
  - **Fix**: Validate the target ELF and `PT_INTERP` headers before resetting the caller's VM.

- [x] **M32-3 — High — BUG — Darwin sub-page MAP_SHARED mappings lose sharing**
  - **Where**: `src/rt32/vm_mmap.c:96-126` (`vm_mmap2_locked`).
  - **What breaks / Why**: Mappings not aligned to 16 KiB fall back to `mprotect` + `memset` + `pread` into anonymous arena memory even when `MAP_SHARED` is set, losing writeback and alias coherence; negative `pread` errors are also ignored.
  - **Fix**: Provide shared sub-page backing or reject unsupported unaligned `MAP_SHARED` file mappings explicitly, and propagate `pread` errors.

- [x] **M32-4 — High — BUG — mremap replaces file-backed memory with anonymous storage**
  - **Where**: `src/rt32/vm_mmap.c:310-338`, `src/rt32/vm_mmap.c:372-393` (`rt32_vm_mremap`).
  - **What breaks / Why**: Both in-place growth and relocation create anonymous mappings, losing file backing and `MAP_SHARED` coherence.
  - **Fix**: Preserve file descriptor/inode backing and offsets across `mremap`.

- [x] **M32-5 — High — BUG — Translation invalidation misses sibling threads**
  - **Where**: `src/dbt/dbt.c:100-105`, `src/dbt/dbt.c:328-394`, `src/dbt/dbt.c:428-435` (`dbt_cache`, `dbt_smc_bump`, `mips32_dbt_invalidate_range`, `dbt_lookup_bi`).
  - **What breaks / Why**: `dbt_cache` and SMC page versions are `_Thread_local`. An SMC write or `munmap`/`mprotect` in one thread never invalidates translations cached in sibling threads.
  - **Fix**: Store per-page SMC/code generation counters in shared VM state so all threads observe invalidations immediately.

- [x] **M32-6 — High — BUG — Full SMC table silently drops invalidations**
  - **Where**: `src/dbt/dbt.c:328-359` (`dbt_smc_bump`); `src/dbt/dbt.c:374-394` (`mips32_dbt_invalidate_range`).
  - **What breaks / Why**: When all slots in the fixed-size SMC table are occupied, `dbt_smc_bump` returns without bumping the version or flushing the cache, leaving stale code executable.
  - **Fix**: Flush the code cache and reset the SMC table whenever the SMC table reaches capacity.

- [x] **M32-7 — High — BUG — Region-table exhaustion changes permissions outside the requested range**
  - **Where**: `src/rt32/vm.c:269-295` (`vm_mprotect_regions_locked`); `src/rt32/vm_mmap.c:200-210` (`vm_mprotect_locked`).
  - **What breaks / Why**: If splitting a region fails due to table capacity, the fallback overwrites `prot` on the entire unsplit VMA while host `mprotect` only updated the requested sub-range.
  - **Fix**: Pre-check free VMA slots before mutating host protections and return `-ENOMEM` if the split cannot be recorded.

- [x] **M32-8 — High — BUG — Blocked signals are delivered immediately**
  - **Where**: `src/os/signals.c:386-444` (`mips_l4a_rt_sigprocmask`); `src/os/kill.c:151-178` (`mips_sc_kill`).
  - **What breaks / Why**: `mips_sc_kill` delivers self-signals immediately without checking the blocked signal mask recorded by `rt_sigprocmask`.
  - **Fix**: Record blocked signals as pending and deliver them only when unmasked.

- [x] **M32-9 — High — BUG — CLONE_VM children retain stale mapping metadata**
  - **Where**: `src/os/threads.c:315-329` (`mips_sc_clone`); `src/rt32/vm.c:107-126` (`vm_copy_state_to_ctx`, `vm_sync_to_ctx`); `src/os/syscalls.c:116-132` (`mips_sc_range_ok`).
  - **What breaks / Why**: `mips_sc_clone` copies the VMA region snapshot into `child`, and subsequent `mmap`/`munmap`/`mprotect` calls only update the calling context and `g_root_ctx`, leaving sibling threads with stale VMA tables.
  - **Fix**: Validate ranges against the authoritative shared VM table under the VM lock (or synchronize generation-stamped snapshots).

- [x] **M32-10 — Medium — BUG — Integer branch-likely fetches an annulled delay slot**
  - **Where**: `src/interp/interp.c:775-789` (`exec_branch`); `src/dbt/dbt.c:609-612` (`dbt_compile`).
  - **What breaks / Why**: A not-taken branch-likely (`BEQL`, `BNEL`, etc.) still fetches `pc + 4` before annulling it, which can fault if the annulled delay slot lies on an unmapped next page.
  - **Fix**: Advance directly to `pc + 8` when a branch-likely condition is false without fetching `pc + 4`.

- [x] **M32-11 — Medium — BUG — Default signal handling treats stop and ignore actions as process exit**
  - **Where**: `src/os/kill.c:70-80` (`kill_die`), `src/os/kill.c:147-155` (`mips_sc_kill`).
  - **What breaks / Why**: Unhandled signals (including default-ignore signals like `SIGCHLD`/`SIGURG`/`SIGWINCH`) call `kill_die`, which exits with `_Exit(128 + signo)`.
  - **Fix**: Implement the MIPS Linux default-action table (`Ign`, `Stop`, `Cont`, `Term`, `Core`).

### 3.2 Curated C11 & UB Issues

- [x] **M32-12 — High — C11 — Signal state has unsynchronized cross-thread access**
  - **Where**: `src/os/signals.c:123-129`, `src/os/signals.c:342-378`, `src/os/signals.c:655-666`, `src/os/signals.c:732-773`.
  - **What breaks / Why**: Signal masks, frame addresses, and nesting depth (`g_depth`) are unsynchronized process globals shared across threads (C11 data race and cross-thread `sigreturn` frame corruption).
  - **Fix**: Move signal mask and frame stack/depth into per-thread `mips32_ctx_t` and protect the shared `sigaction` table with a mutex.

- [x] **M32-13 — High — C11 — Guest copy helpers race VM changes and can crash the host**
  - **Where**: `src/os/syscalls.c:136-155` (`mips_sc_copy_from`, `mips_sc_copy_to`); `src/rt32/vm.c:113-125` (`vm_copy_state_to_ctx`); `src/os/hostfault.c:104-110` (`hf_handler`).
  - **What breaks / Why**: Copy helpers read unsynchronized per-context region arrays and call `memcpy` without holding the VM lock or registering fault recovery.
  - **Fix**: Synchronize VM validation/copy helpers and guard guest memory copies with fault recovery.

- [x] **M32-14 — Medium — C11 — Fault-PC range check compares unrelated pointers**
  - **Where**: `src/os/hostfault.c:106-108` (`hf_handler`).
  - **What breaks / Why**: `pc < hf_pool` uses relational `<` on pointers from unrelated mappings (C11 UB).
  - **Fix**: Cast both `pc` and `hf_pool` to `uintptr_t` before comparing.

### 3.3 DRY, YAGNI & CLEAN

- [x] **M32-15 — Medium — DRY — Guest range validation is independently copied across syscall modules**
  - **Where**: `src/os/syscalls.c:102-133` (`mips_sc_range_ok`); `src/os/proc.c:91-124` (`proc_range_ok`); `src/os/signals.c:172-205` (`l4a_range_ok`).
  - **What breaks / Why**: Three copy-pasted implementations of the VMA region walk with subtly different null/zero-length checks.
  - **Fix**: Unify into a single `mips32rt`-internal VM range validation helper.

- [x] **M32-16 — Low — DRY — Host backends duplicate identical POSIX wrappers**
  - **Where**: `src/os/backend_linux.c:348-420`; `src/os/backend_darwin.c:338-410`.
  - **What breaks / Why**: Identical `close`/`read`/`write`/`pread`/`pwrite`/`lseek`/`ftruncate` wrappers duplicated across both backend files.
  - **Fix**: Move common POSIX fd wrappers into a shared internal file within `mips32rt`.

- [x] **M32-17 — Medium — YAGNI — File-family tracking consumes resources without enforcing its advertised coherence**
  - **Where**: `src/vm/vm_file.c:55-73`, `src/vm/vm_file.c:110-129`, `src/vm/vm_file.c:175-228`.
  - **What breaks / Why**: `dup`s file descriptors into a static table without a close path and defines `mips32_file_check_truncate` with zero callers.
  - **Fix**: Wire file-truncate invalidation into the VM lifecycle and close retained fds on unmap, or remove the dead tracking code.

- [x] **M32-18 — Low — YAGNI — Unused branch classifier suppresses its own warning**
  - **Where**: `src/dbt/dbt.c:146-163` (`dbt_is_likely`).
  - **What breaks / Why**: Unused `__attribute__((unused))` static function duplicating branch-likely decoding.
  - **Fix**: Delete `dbt_is_likely`.

- [x] **M32-19 — Medium — CLEAN — Two test sources violate the line limit and evade its check**
  - **Where**: `tests/test_p1_isa.c:1-1030`; `tests/test_p3_fpu.c:1-1164`; `Makefile:89-96` (`check-line-limits`).
  - **What breaks / Why**: `test_p1_isa.c` (`1,030` lines) and `test_p3_fpu.c` (`1,164` lines) exceed 900 lines; `check-line-limits` only scans `src/` and `include/`.
  - **Fix**: Split both test files below 900 lines and include `tests/` in `check-line-limits`.

- [x] **M32-20 — Low — CLEAN — Default build flags omit required global Werror**
  - **Where**: `Makefile:21` (`CFLAGS`); `Makefile:44` (`DARWIN_CFLAGS`).
  - **What breaks / Why**: Includes `-Werror=vla` but omits `-Werror`.
  - **Fix**: Add `-Werror` to `CFLAGS` and `DARWIN_CFLAGS`.

---

### R1-4. `ppc32rt` (`3582753` → `abe6b0b`) — 15 / 15 Resolved

### 4.1 Bugs & Defects

- [x] **P32-1 — High — BUG — Overflow-enabled arithmetic instructions fail decoding**
  - **Where**: `src/interp/decode.c:325-335`, `src/interp/decode.c:444-446`, `src/interp/decode.c:559-561` (`ppc_decode`).
  - **What breaks / Why**: `ppc_decode` extracts the 10-bit `XO` (`bits 21..30`, which includes `OE` at bit 21) for opcode 31 and switches on all 10 bits, but XO-form arithmetic cases (`add`, `subf`, `neg`, `mullw`, `divw`, `divwu`) only list `OE=0` constants. Any `OE=1` instruction (`addo`, `subfo`, `nego`, `mullwo`, `divwo`, `divwuo`) falls through to `PPC32_OP_UNDEF` in both interp and DBT.
  - **Fix**: Mask out the `OE` bit (`xo & 0x1ffU`) when matching XO-form arithmetic instructions while setting `d->oe = (xo & 0x200U) != 0`.

- [x] **P32-2 — High — BUG — DBT traps combine predicates incorrectly**
  - **Where**: `src/dbt/emit_int.c:541-579` (`ei_trap`).
  - **What breaks / Why**: For each enabled `TO` bit in `tw`/`twi`, `ei_trap` emits a conditional branch that skips the trap when that single condition is false. Thus the trap only fires when **all** enabled `TO` bits hold simultaneously instead of **any** enabled bit (e.g., `twnei` with `TO=24` never traps because `<` and `>` cannot both be true), and signed `<` uses `A64_CC_PL` instead of `A64_CC_LT`.
  - **Fix**: Emit positive conditional branches (`A64_CC_LT`, `A64_CC_GT`, `A64_CC_EQ`, `A64_CC_CC`, `A64_CC_HI`) to a shared trap-taken label when any enabled `TO` bit matches.

- [x] **P32-3 — High — BUG — Memory barriers are discarded**
  - **Where**: `src/interp/decode.c:519-521`, `src/interp/decode.c:540-545` (`ppc_decode`); `src/interp/interp.c:844-848` (`interp_step`); `src/dbt/emit_int.c:856-858` (`ppc32_emit_int`).
  - **What breaks / Why**: `sync`/`lwsync` and `eieio` decode to `PPC32_OP_SYNC`, which both the interpreter and DBT treat as a no-op instead of emitting a memory barrier (`__atomic_thread_fence` / `dmb ish`).
  - **Fix**: Emit `dmb ish` in DBT and `__atomic_thread_fence(__ATOMIC_SEQ_CST)` in the interpreter for `PPC32_OP_SYNC`.

- [x] **P32-4 — High — BUG — Atomic accesses bypass A2 guest permissions**
  - **Where**: `src/interp/interp.c:36-47` (`vm32_sc_attempt`), `src/interp/interp.c:796-815` (`LWARX`/`STWCX`); `src/dbt/emit_int.c:605-611`, `src/dbt/emit_int.c:642-659` (`ei_lwarx`, `ei_stwcx`).
  - **What breaks / Why**: `LWARX`/`STWCX` form raw `guest_base + ea` pointers and execute host atomics without consulting the A2 Soft-TLB or COW page table, bypassing 4 KiB sub-page `PROT_NONE`/`PROT_READ` protections on 16 KiB Darwin hosts.
  - **Fix**: Validate guest page read/write permissions (and trigger COW if needed) before performing the host atomic operation.

- [x] **P32-5 — High — BUG — mremap replaces file backing with anonymous memory**
  - **Where**: `src/rt32/ppc32_vm.c:678-679`, `src/rt32/ppc32_vm.c:701-706`, `src/rt32/ppc32_vm.c:740-765` (`ppc32_vm_mremap`).
  - **What breaks / Why**: Both extension and relocation force `PPC32_MAP_ANONYMOUS`, severing `MAP_SHARED` and file-backed mappings from their underlying file.
  - **Fix**: Preserve file backing, offset, and sharing flags across `ppc32_vm_mremap`.

- [x] **P32-6 — High — BUG — Invalid futex timeout pointers can crash the translator**
  - **Where**: `src/os/threads.c:52-85` (`thread_range_ok`, `thread_ld32be`); `src/os/threads.c:274-284` (`futex_get_timeout`); `src/main.c:437-448` (`ppc32_run_guest_child`).
  - **What breaks / Why**: `thread_range_ok` checks only arithmetic address bounds (`< 4 GiB`), not whether the guest page is mapped and readable. Dereferencing an unmapped timeout pointer in `futex_get_timeout` crashes the translator in host C code instead of returning `-EFAULT`.
  - **Fix**: Validate timeout pointers against the VM mapping table with `PROT_READ` before reading.

- [x] **P32-7 — Medium — BUG — neg corrupts XER.CA in both engines**
  - **Where**: `src/interp/interp.c:246-257` (`interp_step`, `NEG`); `src/dbt/emit_int.c:166-170` (`ei_addsub_xo`).
  - **What breaks / Why**: Both interpreter and DBT update `XER.CA` during `neg`/`neg.`, whereas PowerPC `neg` does not affect `XER.CA`.
  - **Fix**: Remove the `XER.CA` update from `PPC32_OP_NEG` in both `interp.c` and `emit_int.c`.

- [x] **P32-8 — Medium — BUG — Futex requeue count is passed in the wrong argument**
  - **Where**: `src/os/threads.c:255-264` (`futex_host`); `src/os/threads.c:341-346` (`ppc32_futex`).
  - **What breaks / Why**: `FUTEX_REQUEUE` and `FUTEX_CMP_REQUEUE` pass `NULL` as the 4th argument (`val2` / `nr_requeue`) to `futex_host`, causing the kernel to always requeue 0 waiters.
  - **Fix**: Pass `(const struct timespec *)(uintptr_t)val2` as the 4th syscall argument for `REQUEUE` and `CMP_REQUEUE`.

- [x] **P32-9 — Medium — DEFECT — pthread failures are reported using unrelated errno**
  - **Where**: `src/os/backend_linux.c:605-609`, `src/os/backend_darwin.c:801-805` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:399-407` (`rt_host_preempt_worker`).
  - **What breaks / Why**: `pthread_create` and `pthread_kill` return their error code directly without setting `errno`, but the wrappers return `-errno` (which may be `0`).
  - **Fix**: Capture `int rc = pthread_create(...)` / `pthread_kill(...)` and return `-rc`.

### 4.2 Curated C11 & UB Issues

- [x] **P32-10 — High — C11 — Reservation metadata has unsynchronized shared accesses**
  - **Where**: `src/interp/interp.c:24-26`, `src/interp/interp.c:43-51`, `src/interp/interp.c:804-806` (`g_ll_table`, `vm32_sc_attempt`, `LWARX`).
  - **What breaks / Why**: Non-atomic fields (`owner`, `addr`, `val`, `snap`, `gensnap`) in shared `g_ll_table` are read and written concurrently by multiple threads without a lock (C11 data race).
  - **Fix**: Store per-thread reservation state in `ppc32_ctx_t` and synchronize shared cacheline generation counters atomically.

- [x] **P32-11 — Medium — C11 — Signed offset construction left-shifts negative values**
  - **Where**: `src/os/syscalls.c:710-712` (`ppc32_syscall`, `PREAD64`).
  - **What breaks / Why**: `((int64_t)(int32_t)a3 << 32)` left-shifts a negative signed value when `a3` has bit 31 set (C11 UB).
  - **Fix**: Use `(int64_t)(((uint64_t)a3 << 32) | (uint64_t)a4)`.

### 4.3 DRY, YAGNI & CLEAN

- [x] **P32-12 — Low — DRY — Worker-spawn plumbing is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:575-615`, `src/os/backend_darwin.c:771-811` (`spawn_slot_t`, `spawn_tramp`, `rt_host_spawn_worker`).
  - **What breaks / Why**: Duplicated worker-spawn trampoline and slot management in both backend files (both sharing bug `P32-9`).
  - **Fix**: Extract common worker-spawn logic into a shared internal file within `ppc32rt`.

- [x] **P32-13 — Low — YAGNI — Signal installation API is unwired scaffolding that reports success**
  - **Where**: `src/os/backend_darwin.c:875-890` (`rt_host_install_signal_handlers`).
  - **What breaks / Why**: Discards all three callback arguments, sets `SIG_IGN`, and returns `0` with no callers in `src/`.
  - **Fix**: Wire to `hostfault.c` or remove the unused stub.

- [x] **P32-14 — Low — CLEAN — Core files have effectively exhausted the line budget**
  - **Where**: `src/interp/interp.c:1-900`, `src/interp/fp.h:1-899`, `src/os/syscalls.c:1-898`, `src/os/backend_darwin.c:1-895`.
  - **What breaks / Why**: Four core files are at `895–900` lines, leaving zero headroom for bug fixes.
  - **Fix**: Split cohesive sub-units into separate `.c` files when applying the fixes above.

- [x] **P32-15 — Low — CLEAN — Execution comments contradict current behavior**
  - **Where**: `src/interp/interp.h:38-42`, `src/interp/interp.c:837-843`, `src/dbt/dbt.c:17-21`, `src/dbt/dbt.c:44-45`.
  - **What breaks / Why**: Header comments state `interp_step` advances `NIP` on `sc`, whereas `interp.c` leaves `NIP` at `sc` for the caller to advance; `dbt.c` comments still describe native emission as future work.
  - **Fix**: Update the comments to match the actual `sc` NIP convention and active DBT emitter architecture.

---

### R1-5. `sparc32rt` (`816cc90` → `dad95da`) — 18 / 18 Resolved

### 5.1 Bugs & Defects

- [x] **S32-1 — High — BUG — Syscall pointer checks accept inaccessible guest memory**
  - **Where**: `src/os/l2a_access.h:49-69` (`l2a_range_ok`, `l2a_store`); `src/os/futex.c:269-277` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: `l2a_range_ok` checks only arithmetic bounds (`addr >= 0x1000`), not whether the guest pages are mapped with required permissions. Unmapped syscall buffer/timeout pointers fault the translator in host `memcpy` instead of returning `-EFAULT`, and bypass A2 sub-page permissions on Darwin.
  - **Fix**: Validate every covered guest page against the VM permission/mapping table in `l2a_range_ok` / copyin / copyout helpers.

- [x] **S32-2 — High — BUG — Failed execve changes the running process**
  - **Where**: `src/os/threads_exec.c:137-161` (`sparc32_thr_execve`).
  - **What breaks / Why**: Signal dispositions and the VM are reset before validating the pathname pointer or opening/validating the new ELF image, and all loader errors are collapsed to `-ENOENT`.
  - **Fix**: Copy in arguments and validate/open the target ELF before resetting signal dispositions and the guest VM, and return the actual loader errno.

- [x] **S32-3 — High — BUG — LDSTUB retains a process-wide lock across guest execution**
  - **Where**: `src/dbt/aot/aot_atomic.h:89-117` (`sparc32_atomic_ldstub`); `src/interp/interp_mem.c:109-115` (`interp_mem_wr`).
  - **What breaks / Why**: When `LDSTUB` reads `0x00`, it keeps `g_sparc32_ldstub_lock.owner` held across subsequent guest instructions until the owning thread stores to that address. Any other thread executing `LDSTUB` on an **unrelated** address spins waiting for `owner` to clear, causing cross-lock deadlocks.
  - **Fix**: Execute `LDSTUB` as a single atomic byte exchange (`__atomic_exchange_n(ptr, 0xffU, __ATOMIC_SEQ_CST)`) and release any helper lock immediately before returning.

- [x] **S32-4 — High — BUG — Guest stores do not invalidate translated code**
  - **Where**: `src/interp/interp_mem.c:96-117` (`interp_mem_wr`); `src/dbt/aot/aot_atomic.h:124-161` (`sparc32_atomic_swap`, `sparc32_atomic_casa`); `src/dbt/emit_priv.h:423-455` (`sparc32_rt_mem`); `src/dbt/dbt.c:469-488` (`dbt_lookup`).
  - **What breaks / Why**: Interpreter stores, DBT slow-path stores, and atomic writes modify guest memory without invalidating cached DBT blocks covering that page (`dbt_lookup` does not verify source instruction words either).
  - **Fix**: Call `sparc32_dbt_invalidate_range` (or bump per-page SMC generation tags) on stores to pages containing translated blocks.

- [x] **S32-5 — High — BUG — A clone thread can unmap code executing in its parent**
  - **Where**: `src/dbt/dbt.c:114-121` (`dbt_arena_reset`), `src/dbt/dbt.c:491-517` (`dbt_flush`, `sparc32_dbt_invalidate_range`); `src/rt32/vm_mmap.c:311-327` (`rt32_vm_munmap`); `src/os/threads.c:410-443` (`thr_thread_entry`).
  - **What breaks / Why**: `sparc32_dbt_invalidate_range` calls `dbt_flush`, which immediately `munmap`s the global JIT code arena. If a cloned thread calls `munmap` or `mprotect` while the parent thread is executing inside the JIT code arena, the parent faults on unmapped host instructions.
  - **Fix**: Quiesce executing threads before unmapping/resetting the shared JIT arena or defer arena reclamation until no thread is inside JIT code.

- [x] **S32-6 — High — BUG — Timed futex waits and wakes use different queues on AArch64 Linux**
  - **Where**: `src/os/futex.c:235-300` (`sparc32_l2a_futex_time64`).
  - **What breaks / Why**: On AArch64 Linux (`__NR_futex_time64` is not defined because 64-bit Linux `__NR_futex` already uses 64-bit `timespec`), `sparc32_l2a_futex_time64` falls back to the user-space pthread condvar emulator while `FUTEX_WAKE` uses kernel `SYS_futex`, so timed waiters are never woken by `FUTEX_WAKE`.
  - **Fix**: Use kernel `SYS_futex` with a native 64-bit `struct timespec` on 64-bit Linux hosts.

- [x] **S32-7 — High — BUG — mremap loses file backing and shared-map identity**
  - **Where**: `src/rt32/vm_mmap.c:372-374`, `src/rt32/vm_mmap.c:395-417`, `src/rt32/vm_mmap.c:438-463` (`rt32_vm_mremap`).
  - **What breaks / Why**: `rt32_vm_mremap` creates anonymous mappings for growth and relocation, losing file backing and `MAP_SHARED` alias coherence.
  - **Fix**: Preserve file backing, offset, and `MAP_SHARED` state across `rt32_vm_mremap`.

- [x] **S32-8 — High — BUG — Darwin subpage file mappings silently discard MAP_SHARED semantics**
  - **Where**: `src/os/backend_darwin.c:307-349` (`rt_host_map_file`).
  - **What breaks / Why**: Unaligned fixed file mappings on Darwin fall back to `mprotect` + `memset` + `pread` into anonymous arena memory even when `shared` is true.
  - **Fix**: Provide coherent shared sub-page backing or reject unsupported unaligned `MAP_SHARED` file mappings explicitly.

- [x] **S32-9 — Medium — BUG — Signal frames omit mask preservation and restoration**
  - **Where**: `src/interp/interp_signal.c:202-208`, `src/interp/interp_signal.c:337-343`; `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Signal delivery writes `0` to the saved mask words in the frame, and `sparc32_sys_rt_sigreturn` never restores the signal mask from the frame.
  - **Fix**: Save the pre-delivery signal mask into the signal frame and restore it in `sigreturn` / `rt_sigreturn`.

- [x] **S32-10 — Medium — BUG — Signal FPU state is hidden outside the guest ABI frame**
  - **Where**: `src/interp/interp_signal.c:66-67`, `src/interp/interp_signal.c:208-210`; `src/os/syscalls_sig.c:329-330`, `src/os/syscalls_sig.c:360-361`.
  - **What breaks / Why**: FPU state is saved in a translator-private array with `fpu_save = 0` in the guest frame, and `rt_sigreturn` rejects any non-zero `fpu_save` pointer.
  - **Fix**: Serialize the SPARC32 FPU save area onto the guest signal stack when used and restore from it on `sigreturn`.

- [x] **S32-11 — Medium — BUG — Clone threads misclassify doubleword alignment faults**
  - **Where**: `src/os/threads.c:421-428` (`thr_thread_entry`); `src/interp/interp.c:449-474`.
  - **What breaks / Why**: `thr_thread_entry` checks `(fault_addr & 3U) != 0U` for `SIGBUS`, misclassifying 4-byte-aligned (but not 8-byte-aligned) `LDD`/`STD` faults as `SIGSEGV` instead of `SIGBUS`.
  - **Fix**: Share the instruction-aware `SIGBUS`/`SIGSEGV` classifier from `src/main.c:237-244`.

### 5.2 Curated C11 & UB Issues

- [x] **S32-12 — High — C11 — Signed shifts make normal branch and division decoding undefined**
  - **Where**: `src/interp/decode.c:343-364` (`sparc32_decode_word`); `src/interp/interp.c:275`, `src/interp/interp.c:304` (signed dividend construction).
  - **What breaks / Why**: Left-shifting negative sign-extended `int32_t` branch displacements (`disp << 2`) and negative `%y` (`(int64_t)(int32_t)y << 32`) invokes C11 signed left-shift UB.
  - **Fix**: Left-shift as unsigned (`(uint32_t)` / `(uint64_t)`) before casting to signed.

- [x] **S32-13 — Medium — C11 — Futex timeout saturation still permits signed overflow**
  - **Where**: `src/os/futex.c:113-123` (`sparc32_futex_wait_emu`).
  - **What breaks / Why**: Adding `now` to a capped `int64_t` relative timeout up to `9e18` ns can overflow `INT64_MAX`.
  - **Fix**: Clamp `rel_ns` against `INT64_MAX - now_ns` before adding.

### 5.3 DRY, YAGNI & CLEAN

- [x] **S32-14 — Low — DRY — Signal-return functions duplicate register restoration**
  - **Where**: `src/os/syscalls_sig.c:263-312` (`sparc32_sys_sigreturn`); `src/os/syscalls_sig.c:315-362` (`sparc32_sys_rt_sigreturn`).
  - **What breaks / Why**: Both functions duplicate register window, PSR, PC/nPC, and FPU restoration logic.
  - **Fix**: Extract a common frame-restore helper inside `src/os/syscalls_sig.c`.

- [x] **S32-15 — Medium — YAGNI — Soft-TLB miss machinery is disconnected from production callers**
  - **Where**: `src/vm/vm32.c:87-101` (`t_tlb`, `vm32_tlb_reset_thread`), `src/vm/vm32.c:268-336` (`vm_tlb_miss_helper`), `src/vm/vm32.c:339-364` (`vm32_tlb_invalidate`).
  - **What breaks / Why**: `vm_tlb_miss_helper` has no callers in `src/`; active execution uses the protection table directly.
  - **Fix**: Either wire `vm_tlb_miss_helper` into the DBT fast path or remove the unused `t_tlb` scaffolding.

- [x] **S32-16 — Low — CLEAN — Memory-access comments contradict current alignment handling**
  - **Where**: `src/interp/interp_mem.c:67-72`; `src/interp/interp_signal.c:20-33`.
  - **What breaks / Why**: Comments state `LDD`/`STD` 8-byte alignment is an unimplemented Phase-3 gap, contradicting `interp.c:449-474`.
  - **Fix**: Update the stale comments to reflect current alignment trap behavior.

- [x] **S32-17 — Low — CLEAN — Default build flags omit the required general warning gate**
  - **Where**: `Makefile:29-33` (`CFLAGS`).
  - **What breaks / Why**: Includes `-Werror=vla` but omits `-Werror`.
  - **Fix**: Add `-Werror` to `CFLAGS`.

- [x] **S32-18 — Low — CLEAN — Three core files have almost no line-limit headroom**
  - **Where**: `src/dbt/dbt.c:1-888`, `src/os/threads.c:1-883`, `src/dbt/emit_int.c:1-882`.
  - **What breaks / Why**: Within 12–18 lines of the 900-line ceiling.
  - **Fix**: Extract cohesive helpers into separate `.c` files when modifying these modules.

---

### R1-6. `rvrt` (`29ce5fd` → `8e207fb`) — 10 / 10 Resolved

### 6.1 Bugs & Defects

- [x] **RV-1 — High — BUG — FP load miss loses previously dirty guest registers**
  - **Where**: `src/darwin_dbt.c:312-346`, `src/darwin_dbt.c:364-389` (`emit_inline_load`); `src/dbt_emit_fp.c:141-154` (`emit_str_d`).
  - **What breaks / Why**: In `emit_inline_load`, the Soft-TLB miss branch is emitted *before* the FP register-cache eviction spill, and the fast path then updates the slot's guest FP register identity and clears its dirty bit at compile time. When the cold miss path is emitted afterward, `emit_flush_fp_cache` uses the *post-load* compile-time cache metadata even though runtime execution jumped over the fast-path spill. If `f0` was dirty in slot 0 and `fld f16, ...` misses the Soft-TLB (both map to slot `0`), the dirty value of `f0` is never written back and is silently lost.
  - **Fix**: Snapshot pre-instruction FP/GPR cache metadata before the fast path mutates it (or emit the dirty-slot eviction spill before the TLB miss branch) so the cold miss path flushes the actual live pre-load register state.

- [x] **RV-2 — Medium — BUG — pthread failures can be reported as success**
  - **Where**: `src/os/backend_linux.c:274-279`, `src/os/backend_darwin.c:351-356` (`rt_host_spawn_worker`); `src/os/backend_darwin.c:302-309` (`rt_host_preempt_worker`).
  - **What breaks / Why**: `pthread_create` and `pthread_kill` return an error number directly without setting `errno`, but these wrappers discard the return value and return `-errno` (which is `0` if `errno` was clear).
  - **Fix**: Capture `int rc = pthread_create(...)` / `pthread_kill(...)` and return `-rc`.

- [x] **RV-3 — Medium — DEFECT — Failed writable transitions leave code caches reusable**
  - **Where**: `src/dbt/cache.c:299-312` (`rv_dbt_invalidate`), `src/dbt/cache.c:82-85` (`rv_dbt_publish`); `src/os/backend_linux.c:153-160` (`rt_host_jit_begin_write`).
  - **What breaks / Why**: `rv_dbt_invalidate` ignores `mprotect(..., PROT_READ | PROT_WRITE)` errors and resets `used = 0`. A subsequent `rv_dbt_publish` then `memcpy`s into memory that may still be `PROT_READ | PROT_EXEC`, crashing the host process.
  - **Fix**: Check and propagate `mprotect` / `rt_host_jit_begin_write` failures before resetting `used` or writing to the code arena.

- [x] **RV-4 — Medium — BUG — TLB refill can pair an old read tag with a new host address**
  - **Where**: `src/darwin_dbt.c:102-125` (`tlb_fill_page`), `src/darwin_dbt.c:296-300` (`emit_tlb_lookup`).
  - **What breaks / Why**: When refilling a Soft-TLB slot for a write-only page (`PROT_WRITE` without `PROT_READ`), `tlb_fill_page` updates `entry->addend` and `entry->write_tag` without invalidating `entry->read_tag`. If a previously cached readable page A collides with write-only page B in the 4096-entry table, a subsequent load from page A matches A's stale `read_tag` and uses B's `addend`.
  - **Fix**: Unconditionally invalidate both `read_tag` and `write_tag` (`~0ULL`) before writing `entry->addend` and installing the permitted tag(s).

### 6.2 Curated C11 & UB Issues

- [x] **RV-5 — Medium — C11 — File-offset reconstruction can overflow signed `off_t`**
  - **Where**: `src/os/backend_linux.c:66-77` (`rt_host_map_file`).
  - **What breaks / Why**: `(off_t)(aligned_file_offset >> 12) * (off_t)4096` overflows signed 64-bit `off_t` when bit 63 of `aligned_file_offset` is set.
  - **Fix**: Validate `(aligned_file_offset & 0xfffULL) == 0ULL && aligned_file_offset <= (uint64_t)INT64_MAX` and cast `(off_t)aligned_file_offset` directly.

- [x] **RV-6 — Low — C11 — Test argument parsing uses prohibited `atoi`**
  - **Where**: `test/test_family_leave.c:90-92` (`notify_fd` parsing); `test/test_family_backing.c:39` (`pin_sender` / `pin_receiver` parsing).
  - **What breaks / Why**: Uses banned `atoi` without error checking.
  - **Fix**: Replace with `strtol` and range validation.

### 6.3 DRY, YAGNI & CLEAN

- [x] **RV-7 — Low — DRY — Worker startup protocol is duplicated across backends**
  - **Where**: `src/os/backend_linux.c:233-300`, `src/os/backend_darwin.c:312-377` (`spawn_context_t`, `spawn_trampoline`, `rt_host_spawn_worker`).
  - **What breaks / Why**: Both backends duplicate the ready-pipe handshake, thread detach, and TID read loop (both sharing bug `RV-2`).
  - **Fix**: Consolidate the worker-spawn handshake into an internal module within `rvrt`.

- [x] **RV-8 — Low — YAGNI — Return-address stack has no production consumer**
  - **Where**: `src/dbt/cache.c:223-240` (`rv_dbt_ras_push`, `rv_dbt_ras_pop`); `src/dbt/cache.h:83-84`.
  - **What breaks / Why**: Only called in `test/u5b_dbt_cache.c`; no production DBT execution path uses it.
  - **Fix**: Wire into DBT call/return dispatch or remove the unused API.

- [x] **RV-9 — Medium — CLEAN — Tests extensively use prohibited textual implementation includes**
  - **Where**: `test/test_linux_memory_alloc.c:42-54`, `test/test_mm_remap.c:38-47`, `test/test_runtime_file_exec_codec.c:11` (and other `test/*.c` files).
  - **What breaks / Why**: Tests textually `#include "../src/.../*.c"` implementation files (requiring macro renames like `#define valid_range ...` to avoid static symbol collisions).
  - **Fix**: Compile production `.c` files separately and expose narrow internal headers for unit testing.

- [x] **RV-10 — Medium — CLEAN — Twenty-nine source files exceed the 900-line ceiling**
  - **Where**: 17 production files under `src/` (`runtime_main.c` 8201, `runtime/family.c` 4641, `runtime/guest_memory.c` 2574, `runtime/native_signal.c` 1894, `runtime/file_caps.c` 1851, `linux/file.c` 1531, `memory/file_backing.c` 1518, `memory/space.c` 1484, `runtime/mm_view.c` 1372, `linux/fd.c` 1338, `runtime/scheduler.c` 1100, `darwin_dbt.c` 1061, `runtime/family_file_recovery.c` 988, `runtime/exec_state.c` 982, `linux/futex.c` 978, `runtime/process_children.c` 938, `linux/signal.c` 909), 9 test files under `test/` (`test_linux_file.c` 1426, `r6_inherited_children.c` 1304, `test_family_file_attributed.c` 1293, `r5_exec.c` 1212, `test_linux_file_workers.c` 1133, `test_file_caps.c` 1022, `test_family_file_recovery.c` 984, `test_family.c` 970, `test_linux_signal.c` 954), and 3 vendored files under `vendor/`.
  - **What breaks / Why**: 26 first-party `.c` files exceed the mandatory 900-line ceiling.
  - **Fix**: Split all 26 first-party files into separately compiled `<900`-line translation units and add a `check-line-limits` target to `Makefile` (with explicit exclusion for `vendor/`).

---

### R1-7. `loongarch64rt` (`0f57c40` → `026e87d`) — 13 / 13 Resolved

### 7.1 Bugs & Defects

- [x] **LA64-1 — High — BUG — Instruction fetch ignores guest execute permission**
  - **Where**: `src/interp/interp.c:71-79` (`interp_step`); `src/dbt/dbt.c:370-389` (`translate_block`); `src/os/mem_min.c:274-305` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:46-67` (`vm64_ptr`).
  - **What breaks / Why**: Both interpreter and DBT fetch guest instructions via `la64_mem_ptr(pc, 4, 0)`, which checks `PROT_READ` instead of `PROT_EXEC`. Non-executable `PROT_READ` data pages can be executed as code, while `PROT_EXEC`-only pages fail instruction fetch.
  - **Fix**: Add an instruction-fetch access mode that checks `PROT_EXEC` and invalidate DBT translations when `mprotect` removes `PROT_EXEC`.

- [x] **LA64-2 — High — BUG — Mixed guest protections can leave a Darwin host page inaccessible**
  - **Where**: `src/os/mem_min.c:150-173` (`protect_host_page`), `src/os/mem_min.c:478-519` (`la64_mem_protect`).
  - **What breaks / Why**: When 4 KiB guest sub-pages sharing a 16 KiB Darwin host page have differing protections, `protect_host_page` returns early without calling host `mprotect`. If a 16 KiB range was first marked `PROT_READ` (or `PROT_NONE`) and one 4 KiB sub-page is then restored to `PROT_READ | PROT_WRITE`, the host page stays `PROT_READ` (or `PROT_NONE`), causing valid guest accesses to fault in the translator.
  - **Fix**: Set the 16 KiB host page protection to the union of its live 4 KiB sub-pages while enforcing sub-page permissions in software/Soft-TLB tags.

- [x] **LA64-3 — High — BUG — Vector memory faults terminate the translator**
  - **Where**: `src/interp/interp_vec.c:83-110` (`interp_step_vec`); `src/interp/interp.c:817-848` (`interp_step`); `src/interp/interp_mem.h:29-35` (`die_at`).
  - **What breaks / Why**: Faulting LSX/LASX vector loads/stores return an error string that `interp_step` passes to `die_at`, which calls `exit(3)` instead of raising a guest `SIGSEGV`, and partial bytes are written to the destination vector register before later bytes are validated.
  - **Fix**: Stage vector load bytes into a temporary buffer, validate the entire span before committing to `vr[vd]`, and route faults through the guest `SIGSEGV` delivery path.

- [x] **LA64-4 — High — BUG — Bootstrap LSX instructions retain stale LASX upper halves**
  - **Where**: `src/interp/interp_vec.c:83-93`, `src/interp/interp_vec.c:114-188` (`interp_step_vec`); `src/interp/interp.c:817-833` (`interp_step`).
  - **What breaks / Why**: The bootstrap LSX handler in `interp_vec.c` (`VLD`, broadcasts, shuffles, `VOR.V`, shifts) writes only `vr[rd][0..1]` without zeroing `vr[rd][2..3]`, violating the LoongArch64 LSX upper-128-bit zeroing contract.
  - **Fix**: Zero `vr[rd][2]` and `vr[rd][3]` after every LSX instruction that writes a vector register.

- [x] **LA64-5 — High — DEFECT — Difftest does not compare DBT register or PC state**
  - **Where**: `src/main.c:302-382` (`diff_child_verify`); `src/main.c:579-639` (`run_difftest`).
  - **What breaks / Why**: `run_difftest` compares DBT vs interpreter only on process exit status and stdout; `diff_child_verify` then replays `interp_step` against a second `interp_step` trace instead of stepping the DBT engine, yet prints `difftest: 0 divergences`.
  - **Fix**: Step the DBT single-block/single-instruction engine against `interp_step` and compare architectural GPR/FPR/FCC/FCSR/PC state at each boundary.

- [x] **LA64-6 — Medium — BUG — Darwin directory enumeration loses unread entries**
  - **Where**: `src/os/syscalls_file.c:173-210` (`sys_getdents64`).
  - **What breaks / Why**: Each `sys_getdents64` call on Darwin `dup`s the fd, calls `fdopendir`, reads entries until the guest buffer is full, and `closedir`s the stream. Both the uncopied overflow entry and any entries pre-buffered by `fdopendir` into libc's internal buffer are lost on the next `getdents64` call.
  - **Fix**: Use `seekdir`/`telldir` with a retained `DIR *` per open directory fd (or `getdirentries` / ` lseek` to the exact offset of the last emitted entry).

- [x] **LA64-7 — Medium — BUG — Mprotect succeeds across unmapped holes**
  - **Where**: `src/os/mem_min.c:478-522` (`la64_mem_protect`); `src/os/syscalls_mem.c:424-434` (`sys_mprotect_range`).
  - **What breaks / Why**: `la64_mem_protect` sets `covered = 1` as soon as *any* sub-region overlaps `[addr, addr + len)` and returns `0` even if part of `[addr, addr + len)` is unmapped, instead of returning `-ENOMEM`.
  - **Fix**: Verify contiguous VMA coverage across the entire `[addr, addr + len)` interval before returning success.

- [x] **LA64-8 — Medium — BUG — Write validation incorrectly requires read permission**
  - **Where**: `src/os/mem_min.c:299-304` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:62-65` (`vm64_ptr`).
  - **What breaks / Why**: Both helpers check `(r->prot & PROT_READ) == 0` unconditionally even for write accesses (`write == 1`), rejecting valid guest stores into write-only (`PROT_WRITE`) mappings.
  - **Fix**: Check `PROT_WRITE` for writes, `PROT_READ` for reads, and `PROT_EXEC` for instruction fetches.

### 7.2 Curated C11 & UB Issues

- [x] **LA64-9 — Medium — C11 — Negative vector offsets invoke signed left-shift UB**
  - **Where**: `src/interp/fp_shuf.c:113-118` (`vec_mem_step`).
  - **What breaks / Why**: `((int32_t)si12 << 20) >> 20` left-shifts a signed `int32_t` into bit 31 when `si12 >= 0x800` (negative 12-bit offset), which is C11 UB.
  - **Fix**: Sign-extend via `(int64_t)(int32_t)((uint32_t)si12 << 20) >> 20`.

### 7.3 DRY, YAGNI & CLEAN

- [x] **LA64-10 — Low — DRY — JIT memory lifecycle is implemented twice**
  - **Where**: `src/dbt/dbt_code.c:55-104` (`dbt_alloc_rw`, `dbt_seal_page`); `src/os/backend_linux.c:288-326` and `src/os/backend_darwin.c:200-264` (`rt_host_jit_*`).
  - **What breaks / Why**: `dbt_code.c` duplicates platform `mmap`/`mprotect`/`pthread_jit_write_protect_np`/`sys_icache_invalidate` logic already implemented in `rt_host_jit_*`.
  - **Fix**: Route `dbt_code.c` through `rt_host_jit_*`.

- [x] **LA64-11 — Low — YAGNI — Return-address stack is populated but never consumed**
  - **Where**: `src/dbt/dbt_chain.c:23-24`, `src/dbt/dbt_chain.c:51-62` (`chain_ras`, `dbt_ras_push`, `dbt_ras_pop`); `src/dbt/dbt.c:728-735` (`dbt_run`).
  - **What breaks / Why**: `dbt_ras_push` is called on block exits, but `dbt_ras_pop` has zero callers in the repository.
  - **Fix**: Wire RAS prediction into `JR $ra` return dispatch or delete the dead RAS array/functions.

- [x] **LA64-12 — Medium — CLEAN — Textual C includes bypass module boundaries**
  - **Where**: `src/interp/interp.c:40-56`, `src/os/syscalls.c:41-100`, `src/os/minsys.c:23`, `src/os/clone.c:217-218`, `src/main.c:20`.
  - **What breaks / Why**: Production `.c` files textually `#include` other `.c` files (`decode.c`, `fp.c`, `syscalls_*.c`, etc.), violating the no-unity-includes rule.
  - **Fix**: Compile each `.c` file as an independent translation unit in `Makefile` with proper internal headers.

- [x] **LA64-13 — Low — CLEAN — File-size gate excludes an oversized test**
  - **Where**: `tests/test_p3_fp_simd.c:1-940`; `Makefile:156-163` (`check-line-limits`).
  - **What breaks / Why**: `tests/test_p3_fp_simd.c` is 940 lines (`> 900`), and four `src/` files (`emit_int.c` 899, `a64_emit.c` 898, `fp.c` 895, `emit_fp.c` 890) have almost no headroom.
  - **Fix**: Split `tests/test_p3_fp_simd.c` below 900 lines and include `tests/` in `check-line-limits`.

---

### R1-8. `ppc64rt` (`f42cf1a` → `bd3e73f`) — 16 / 16 Resolved

### 8.1 Bugs & Defects

- [x] **P64-1 — High — BUG — Guest LL/SC bypasses the atomic memory interface**
  - **Where**: `src/interp/interp.c:25-38`, `src/interp/interp.c:537-557` (`g_res_valid`, `lwarx`/`ldarx`/`stwcx.`/`stdcx.`).
  - **What breaks / Why**: `lwarx`/`ldarx` performs an ordinary `mem->read` and stores the reservation in process-global `g_res_valid`/`g_res_addr`; `stwcx.`/`stdcx.` checks those globals and calls `mem->write`, never invoking `mem->atomic` or invalidating reservations on normal stores. Concurrent threads also race on the globals.
  - **Fix**: Make reservation tracking per-thread/worker, invalidate reservations on all guest/DBT/syscall stores, and perform atomic CAS via the fixed width-accurate `vm_mem_atomic` (`P64-11`).

- [x] **P64-2 — High — DEFECT — Clone executes the child to completion before returning to the parent**
  - **Where**: `src/os/syscalls_p4.c:104-139`, `src/os/syscalls_p4.c:159-184` (`syscall_clone_child_run`, `syscall_p4_clone`); `src/os/syscalls.c:570-579`.
  - **What breaks / Why**: `syscall_p4_clone` synchronously runs the child in an inline interpreter loop to completion before returning the child TID to the parent. Any child thread that waits on the parent deadlocks immediately.
  - **Fix**: Spawn a host worker thread (or preemptive/cooperative green-thread scheduler) so parent and child execute concurrently.

- [x] **P64-3 — High — DEFECT — Futex WAIT always returns EAGAIN and WAKE never wakes**
  - **Where**: `src/os/syscalls_p4.c:188-214` (`syscall_p4_futex`); `src/os/syscalls.c:585-590`.
  - **What breaks / Why**: `FUTEX_WAIT` unconditionally returns `-EAGAIN` even when `*uaddr == val`, and `FUTEX_WAKE` unconditionally returns `0`.
  - **Fix**: Route `syscall_p4_futex` to the real futex wait/wake backend (`rt_host_futex_wait_bitset` / `rt_host_futex_wake_bitset` or waiter table).

- [x] **P64-4 — High — BUG — Querying sigaction destroys the disposition and never returns the old action**
  - **Where**: `src/run/sigdeliver.c:54-84` (`run_sig_record`).
  - **What breaks / Why**: When `act == NULL` (a query), `run_sig_record` zeroes the signal's disposition instead of preserving it, and it completely ignores `args[2]` (`oldact`), never writing back the previous `struct sigaction`.
  - **Fix**: Copy out the previous `sigaction` to `oldact` when non-NULL, and only modify the stored disposition when `act != NULL` (rejecting `SIGKILL`/`SIGSTOP`).

- [x] **P64-5 — High — BUG — Signal delivery and sigprocmask maintain disconnected masks**
  - **Where**: `src/run/sigdeliver.c:33-44`, `src/run/sigdeliver.c:160-202` (`run_sig_blocked`, `run_deliver`); `src/os/syscalls_conv.c:818-845` (`x_sigprocmask`); `src/run/core.c:453-460`.
  - **What breaks / Why**: `rt_sigprocmask` updates `x_sigmask`, while signal delivery reads/saves `run_sig_blocked` (which is always `0`), does not mask the delivered signal or `sa_mask` on handler entry, and `rt_sigreturn` fails to restore the saved mask.
  - **Fix**: Unify `x_sigmask` and `run_sig_blocked` into a single per-thread signal mask, apply `sa_mask` + the delivered signal during handler entry, and restore the saved mask on `rt_sigreturn`.

- [x] **P64-6 — Medium — BUG — kill/tgkill mishandles probes, ignored signals, and syscall return state**
  - **Where**: `src/run/core.c:428-451`; `src/run/sigdeliver.c:79-83`, `src/run/sigdeliver.c:195-199`.
  - **What breaks / Why**: `sig == 0` is rejected instead of probing existence; sending a signal with `SIG_DFL` returns `-ESRCH`; `SIG_IGN` (`1`) is treated as a function pointer at guest address `0x1`; and synchronous self-delivery saves the pre-syscall `r3` instead of the `0` syscall return value in the signal frame.
  - **Fix**: Handle `sig == 0`, `SIG_IGN`, and `SIG_DFL` properly, and commit the `0` syscall return value + `NIP += 4` before constructing the signal frame on self-signaling `kill`/`tgkill`.

- [x] **P64-7 — Medium — BUG — Fixed mremap silently ignores the requested destination for equal-size and shrinking moves**
  - **Where**: `src/os/syscalls_mm.c:729-755` (`syscall_mm_mremap`).
  - **What breaks / Why**: Equal-size (`new_len == old_len`) and shrinking (`new_len < old_len`) calls return `old_addr` before checking `MREMAP_FIXED`, ignoring the requested relocation to `new_addr`.
  - **Fix**: Bypass the in-place equal/shrink fast paths whenever `MREMAP_FIXED` is set.

- [x] **P64-8 — High — BUG — Failed fixed mremap destroys the previous destination mapping**
  - **Where**: `src/os/syscalls_mm.c:777-802` (`syscall_mm_mremap`).
  - **What breaks / Why**: `syscall_mm_mremap` unmaps `new_addr` before inserting/copying the moved mapping; if insertion or copying fails, the error path unmaps `new_addr` again without restoring whatever mapping previously lived at `new_addr`.
  - **Fix**: Validate and stage the relocation before unmapping the destination, or snapshot and restore overwritten destination mappings on failure.

- [x] **P64-9 — Medium — BUG — mremap copies through guest read permissions**
  - **Where**: `src/os/syscalls_mm.c:687-707`, `src/os/syscalls_mm.c:767-789` (`syscall_mremap_transfer`, `syscall_mm_mremap`).
  - **What breaks / Why**: `syscall_mremap_transfer` reads the source range using `PPC64_ACCESS_LOAD`, failing with `-EFAULT` if a `PROT_NONE` or write-only mapping is moved with `mremap`.
  - **Fix**: Copy backing pages using an internal VM transfer helper that does not require guest `PROT_READ`.

- [x] **P64-10 — Medium — BUG — nanosleep writes remaining time through the wrong argument**
  - **Where**: `src/os/syscalls_conv.c:734-758` (`x_nanosleep`).
  - **What breaks / Why**: On `EINTR`, `x_nanosleep` copies the remaining `timespec` to `args[2]` instead of `args[1]` (`rem`).
  - **Fix**: Copy the remainder to `args[1]`.

### 8.2 Curated C11 & UB Issues

- [x] **P64-11 — Medium — C11 — Narrow VM atomics perform unaligned and out-of-range 64-bit accesses**
  - **Where**: `src/vm/vm_atomic.c:180-216`, `src/vm/vm_atomic.c:225-241` (`vm_mem_atomic`).
  - **What breaks / Why**: Casts the host pointer to `uint64_t *` and performs 8-byte `__atomic_load_n` / `__atomic_compare_exchange_n` even when `width` is 1, 2, or 4. A 4-byte atomic at page offset `4092` is only 4-byte aligned and crosses the end of the 4 KiB page.
  - **Fix**: Dispatch width-specific (`uint8_t`, `uint16_t`, `uint32_t`, `uint64_t`) atomic operations.

- [x] **P64-12 — Low — C11 — Image descriptor parsing uses banned atoi**
  - **Where**: `src/main.c:91-100` (`main`, `--image-fd` parsing).
  - **What breaks / Why**: Uses banned `atoi` to parse `--image-fd`.
  - **Fix**: Replace with `strtol` and range validation.

### 8.3 DRY, YAGNI & CLEAN

- [x] **P64-13 — Low — DRY — Syscall return convention is implemented independently in two runners**
  - **Where**: `src/run/core.c:52-82` (`run_is_scv`, `run_apply_sc`); `src/os/syscalls_p4.c:78-101` (`syscall_child_apply`).
  - **What breaks / Why**: Duplicated `sc`/`scv` `r3` and `CR0.SO` return-value application in `core.c` and `syscalls_p4.c`.
  - **Fix**: Share one internal helper within `ppc64rt`.

- [x] **P64-14 — Low — YAGNI — Unused conditional-store API reports success without storing**
  - **Where**: `src/vm/vm_atomic.c:281-291` (`ppc64_vm_conditional`); `src/vm/vm.h:127-128`.
  - **What breaks / Why**: `ppc64_vm_conditional` ignores `val`, performs no store, and has no callers in `src/`.
  - **Fix**: Delete `ppc64_vm_conditional`.

- [x] **P64-15 — Low — CLEAN — Current specifications mix obsolete paths with unrelated ISA concepts**
  - **Where**: `SPEC.md:30-36`, `SPEC.md:78`, `SPEC.md:93`; `GOAL.md:36-43`.
  - **What breaks / Why**: Mentions obsolete `src/rt64/` paths and SPARC/MIPS concepts (delay slots, register windows) in `ppc64rt`'s repo-local `SPEC.md`/`GOAL.md`.
  - **Fix**: Update `ppc64rt/SPEC.md` and `ppc64rt/GOAL.md` to reflect PowerPC64 ELFv2 and the current `src/vm/`, `src/os/`, `src/run/` layout.

- [x] **P64-16 — Low — CLEAN — Repository-wide line ceiling is not enforced by the source-only gate**
  - **Where**: `Makefile:52-60` (`check-line-limits`); `src/interp/interp.c` (`900`), `src/interp/decode.c` (`900`), `src/os/syscalls_conv.c` (`893`), `src/dbt/emit_int.c` (`888`).
  - **What breaks / Why**: `interp.c` and `decode.c` sit at exactly 900 lines with zero headroom; `check-line-limits` only scans `src/`.
  - **Fix**: Split `interp.c` and `decode.c` when modifying them, and extend `check-line-limits` to `tests/` (excluding `vendor/`).

---

### R1-9. `mips64rt` (`8d5950c` → `32d5c9e`) — 18 / 18 Resolved

### 9.1 Bugs & Defects

- [x] **M64-1 — High — BUG — ELF segment rounding can wrap before bounds validation**
  - **Where**: `src/loader.c:432-444`, `src/loader.c:467-488` (`PT_LOAD` mapping and initialization).
  - **What breaks / Why**: `bias + ph.vaddr` and `ph.memsz + page_off + 4095` are computed before overflow checks. If `ph.memsz + page_off + 4095` wraps `uint64_t` to a small value (e.g. `4096`), the bounds check passes on the wrapped length while `memset` uses the huge unrounded `ph.memsz - ph.filesz`, overflowing the host mapping.
  - **Fix**: Validate `ph.vaddr`, `ph.filesz`, `ph.memsz`, `bias`, and page-rounding additions against unsigned overflow before mapping or zero-filling.

- [x] **M64-2 — High — BUG — Write-only TLB entries use a zero host-address addend**
  - **Where**: `src/os/backend_linux.c:251-264`, `src/os/backend_darwin.c:254-267` (`mips_soft_tlb_fill`); `src/dbt/emit_mem.c:193-202` (`ei_probe_open`).
  - **What breaks / Why**: In `mips_soft_tlb_fill`, `addend` is only set when `mips_mem_ok(ctx, page_va, 1, 0)` (read permission) succeeds; otherwise `addend = 0`. However, `write_tag` is set whenever `mips_mem_ok(ctx, page_va, 1, 1)` (write permission) succeeds. For a write-only guest page (`PROT_WRITE`), the DBT fast-path store matches `write_tag` and adds `addend = 0`, storing to the raw guest VA in host memory!
  - **Fix**: Populate `addend = (uintptr_t)host_page - (uintptr_t)page_va` whenever either `can_read` or `can_write` is true.

- [x] **M64-3 — High — BUG — LL/SC implements value comparison instead of reservation invalidation**
  - **Where**: `src/interp/unaligned.c:269-284`, `src/interp/unaligned.c:305-337`, `src/interp/unaligned.c:342-389` (`do_ll`, `do_sc`, `do_lld`, `do_scd`).
  - **What breaks / Why**: `SC`/`SCD` succeeds whenever the current memory word equals `ctx->llval` without tracking intervening stores (classic ABA bug), and ordinary stores do not acquire `g_sc_lock` or invalidate reservations.
  - **Fix**: Maintain atomic per-cacheline reservation epochs bumped by all guest stores, and validate the epoch atomically during `SC`/`SCD`.

- [x] **M64-4 — High — BUG — Instruction exceptions are delivered as SIGSEGV**
  - **Where**: `src/interp/interp.c:22-31` (`fault_at`), `src/interp/interp.c:188-189` (`BREAK`), `src/interp/interp.c:282-295` (overflow), `src/interp/interp.c:381-382` (unrecognized instruction); `src/os/mem.c:69-85` (`mips_fault`).
  - **What breaks / Why**: `fault_at` calls `mips_fault`, which unconditionally raises signal `11` (`SIGSEGV`). Thus `BREAK` (`SIGTRAP`), `ADD`/`SUB`/`DADD` signed overflow (`SIGFPE`), and illegal instructions (`SIGILL`) all deliver `SIGSEGV` instead of their architectural signals.
  - **Fix**: Pass an explicit signal number (`SIGTRAP`, `SIGFPE`, `SIGILL`, `SIGBUS`, `SIGSEGV`) from the interpreter/DBT trap site to `mips_trap`.

- [x] **M64-5 — High — BUG — Sign-extended LO corrupts MADD/MSUB accumulation**
  - **Where**: `src/interp/interp.c:395-428` (`exec_special2`); `src/dbt/emit_alu.c:414-419` (`ei_special2`).
  - **What breaks / Why**: In the interpreter, `MADD`/`MADDU`/`MSUB`/`MSUBU` construct the 64-bit accumulator as `(hi << 32) | lo` without masking `lo` to 32 bits (`(uint32_t)lo`). Because `LO` holds a sign-extended 32-bit value in MIPS64, a negative `LO` (`0xffffffff80000000`) bitwise-ORs `0xffffffff` into the upper 32 bits (`HI`), corrupting `HI` and diverging from the DBT.
  - **Fix**: Construct the accumulator as `((uint64_t)(uint32_t)ctx->hi << 32) | (uint64_t)(uint32_t)ctx->lo` in all four `MADD`/`MADDU`/`MSUB`/`MSUBU` handlers.

- [x] **M64-6 — High — BUG — Thread-directed signals reject valid worker TIDs**
  - **Where**: `src/os/sigact.c:676-699` (`l4a_tkill`); `src/os/threads.c:180-199`, `src/os/threads.c:312-322`.
  - **What breaks / Why**: `l4a_tkill` rejects any `tid != getpid()` with `-ESRCH`, even though cloned threads publish their distinct host TID (`SYS_gettid`). Thus `pthread_kill` or `raise()` inside a worker thread fails with `-ESRCH`.
  - **Fix**: Look up `tid` in the active guest thread table and deliver/queue the signal to that thread's context.

- [x] **M64-7 — Medium — BUG — Backend context slots are never released**
  - **Where**: `src/os/backend_linux.c:28-39`, `src/os/backend_linux.c:82-109`; `src/os/backend_darwin.c:31-42`, `src/os/backend_darwin.c:85-112`; `src/os/threads.c:424-437` (`u0_slot_for`, `mips_thread_exit`).
  - **What breaks / Why**: `u0_slot_for` has only 16 fixed slots and never frees a slot when a thread exits in `mips_thread_exit`. After 16 threads, subsequent threads silently fail to allocate a backend slot.
  - **Fix**: Release the thread's backend slot in `mips_thread_exit` and increase the table size to match the 128-thread limit.

- [x] **M64-8 — Medium — BUG — A valid DSRA32 encoding is treated as a breakpoint**
  - **Where**: `src/interp/interp.c:375-379` (`exec_special`); `src/dbt/emit_alu.c:382-392` (`ei_special`).
  - **What breaks / Why**: `SPECIAL` function `0x3f` with `rt=0, rd=0, sa=0` (`0x0000003f`) is `DSRA32 $zero, $zero, 0`, a valid no-op, but both engines treat it as `SDBBP` and trap (`SDBBP` is in `SPECIAL2`, not `SPECIAL`).
  - **Fix**: Remove the `0x3f` `SDBBP` trap from `SPECIAL` (`exec_special` and `ei_special`), keeping `SDBBP` solely under `SPECIAL2`.

- [x] **M64-9 — Medium — DEFECT — Interpreter FP exception enables are ignored**
  - **Where**: `src/interp/fp.c:135-144` (`fp_raise`).
  - **What breaks / Why**: `fp_raise` sets `FCSR` cause and sticky flags without checking `FCSR` enable bits `[11:7]` or delivering `SIGFPE`.
  - **Fix**: Check `FCSR` enable bits in `fp_raise` and trigger a `SIGFPE` guest trap when an enabled FP exception fires.

- [x] **M64-10 — Medium — BUG — Integer-to-FP conversions omit inexact exceptions**
  - **Where**: `src/interp/fp_cvt.c:170-204` (`fp_cvt_wl`).
  - **What breaks / Why**: `CVT.S.W`, `CVT.S.L`, and `CVT.D.L` do not check whether the converted float/double round-trips back to the exact integer, omitting `FCSR` inexact flags.
  - **Fix**: Compare the round-tripped integer value against the source operand and call `fp_raise(ctx, FP_X_I)` when they differ.

- [x] **M64-11 — Medium — DEFECT — Code-arena allocation grows without reclamation**
  - **Where**: `src/dbt/arena.c:7-18`, `src/dbt/arena.c:42-80` (`arena_retain`, `dbt_arena_alloc`).
  - **What breaks / Why**: Exhausted JIT code chunks are retired into `arena_maps[]` and never unmapped or reused.
  - **Fix**: Reclaim retired arena chunks at a safe quiescence/flush point.

- [x] **M64-12 — Medium — DEFECT — Cloned threads always run the interpreter**
  - **Where**: `src/os/threads.c:170-205` (`l4b_entry`).
  - **What breaks / Why**: `l4b_entry` unconditionally calls `interp_run(child)` even when the process was launched in `--dbt` mode.
  - **Fix**: Dispatch `child` through the active engine (`dbt_run` when DBT is enabled, `interp_run` otherwise).

### 9.2 Curated C11 & UB Issues

- [x] **M64-13 — High — C11 — FP conversion validates the source instead of the rounded result**
  - **Where**: `src/interp/fp_cvt.c:67-84` (`fp_to_int`).
  - **What breaks / Why**: `fp_to_int` checks bounds on the unrounded input `q` (`q < 2147483648.0`) and then casts the *rounded* value `t` (`(int32_t)t`). For `CEIL.W.D` on `2147483647.5`, `q` passes the check, `t` rounds to `2147483648.0`, and `(int32_t)t` invokes C11 float-to-int overflow UB.
  - **Fix**: Check the bounds of the rounded value `t` (`t >= -2147483648.0 && t < 2147483648.0`) before casting `t` to `int32_t` / `int64_t`.

- [x] **M64-14 — High — C11 — Signed MADD/MSUB accumulation can overflow**
  - **Where**: `src/interp/interp.c:396-401`, `src/interp/interp.c:415-420` (`exec_special2`).
  - **What breaks / Why**: `MADD` and `MSUB` perform `int64_t` `+=` / `-=` which overflows signed `int64_t` (C11 UB).
  - **Fix**: Perform the 64-bit accumulator addition/subtraction in `uint64_t`.

### 9.3 DRY, YAGNI & CLEAN

- [x] **M64-15 — Low — DRY — Linux and Darwin duplicate the backend state registry**
  - **Where**: `src/os/backend_linux.c:28-328`; `src/os/backend_darwin.c:31-331` (`u0_slot_for`, FIXADE state, delay targets, soft-TLB management).
  - **What breaks / Why**: ~300 lines of host-independent slot/TLB state management are copy-pasted between `backend_linux.c` and `backend_darwin.c` (both sharing bugs `M64-2` and `M64-7`).
  - **Fix**: Extract the shared state registry and Soft-TLB fill logic into a common internal file within `mips64rt`.

- [x] **M64-16 — Low — YAGNI — Arena retention array is write-only bookkeeping**
  - **Where**: `src/dbt/arena.c:42-57`, `src/dbt/arena.c:74` (`arena_maps`, `arena_nmaps`, `arena_retain`).
  - **What breaks / Why**: `arena_maps` is written by `arena_retain` and never read anywhere in `src/`.
  - **Fix**: Use `arena_maps` to `munmap` retired chunks (`M64-11`) or remove the write-only array.

- [x] **M64-17 — Medium — CLEAN — Production and test code use textual C unity includes**
  - **Where**: `src/os/syscalls.c:32-36` (`#include "proc.c"`); `tests/check_host_contract.c:37-43`.
  - **What breaks / Why**: `src/os/syscalls.c` textually includes `proc.c`, and `tests/check_host_contract.c` textually includes seven `src/` `.c` files.
  - **Fix**: Compile `src/os/proc.c` and the test dependencies as separate `.o` files in `Makefile`.

- [x] **M64-18 — Low — CLEAN — A test exceeds 900 lines and the gate excludes tests**
  - **Where**: `tests/test_p1_isa.c:1-902`; `Makefile:215-222` (`check-line-limits`).
  - **What breaks / Why**: `tests/test_p1_isa.c` is 902 lines (`> 900`), and four `src/` files (`mem_table.c` 899, `interp.c` 897, `syscalls.c` 896, `emit_mem.c` 895) are within 5 lines of the ceiling.
  - **Fix**: Trim/split `tests/test_p1_isa.c` below 900 lines and include `tests/` in `check-line-limits`.

---

### R1-10. `sparc64rt` (`71fe7a5` → `3ead4f9`) — 14 / 14 Resolved

### 10.1 Bugs & Defects

- [x] **S64-1 — High — BUG — CPU initialization leaves half the FP register file unchanged**
  - **Where**: `src/core/cpu.h:137-141,202-218` (`sparc64_ctx_init`); `src/os/guest_run.c:450-465,549-550,683-688` (initial execution and exec reset).
  - **What breaks / Why**: The SPARC V9 FP register file union is 256 bytes (`32 × 64-bit` doubles `d[0..31]`, or `f[0..31]` covering only the first 128 bytes), but `sparc64_ctx_init` and `execve` reset only zero `f[0..31]` (`128` bytes), leaving `d[16..31]` (`%d32..%d62`) uninitialized or retaining pre-`execve` register values.
  - **Fix**: Zero all 32 double registers (`d[0..31]` / `memset(&ctx->fp, 0, sizeof(ctx->fp))`) in `sparc64_ctx_init` and `execve` reset.

- [x] **S64-2 — High — BUG — Failed RX publication does not prevent JIT execution**
  - **Where**: `src/dbt/dbt.c:228-242` (`dbt_publish`), `src/dbt/dbt.c:820-824` (`sparc64_dbt_run`).
  - **What breaks / Why**: `dbt_publish` ignores failure from `a32h_wx_publish` and returns; `sparc64_dbt_run` then jumps into `b->host_code` while the arena page is still non-executable (`PROT_READ | PROT_WRITE`).
  - **Fix**: Have `dbt_publish` return `bool` and fall back to the interpreter if RX publication fails.

- [x] **S64-3 — Medium — BUG — Floating-condition MOVcc encodings become no-op barriers**
  - **Where**: `src/interp/interp.c:239-257` (`sparc64_decode_op2`); `src/dbt/emit_int.c:596-598` (`sparc64_emit_int`).
  - **What breaks / Why**: In SPARC V9 `MOVcc` (`op3 = 0x2c`), bit 18 (`cc2`) clear selects floating-point condition codes (`%fcc0..%fcc3`), but `sparc64_decode_op2` misclassifies bit 18 clear as `SPARC64_ICLS_MEMBAR`, turning `MOVcc (%fccn)` into a no-op in both interpreter and DBT.
  - **Fix**: Decode `MOVcc` with `cc2 == 0` as floating-condition `MOVcc` reading `%fcc0..%fcc3` from `FSR`.

- [x] **S64-4 — Medium — DEFECT — Darwin socket wrappers omit address-layout conversion**
  - **Where**: `src/os/backend_darwin.c:529-535,543-567` (`rt_host_bind`, `rt_host_connect`, address-returning socket wrappers).
  - **What breaks / Why**: Casts Linux `struct sockaddr` buffers (`uint16_t sa_family` at offset 0) directly to Darwin `struct sockaddr` (`uint8_t sa_len, uint8_t sa_family` at offsets 0–1) without converting `sa_len`/`sa_family` or `AF_INET6` (`10` vs `30`).
  - **Fix**: Translate Linux `<->` Darwin `sockaddr` headers (`sa_len`, `sa_family`) in the Darwin socket backend wrappers.

- [x] **S64-5 — Medium — DEFECT — Darwin futex implementation discards essential semantics**
  - **Where**: `src/os/backend_darwin.c:684-716` (`rt_host_futex_wait_bitset`, `rt_host_futex_wake_bitset`, `rt_host_futex_requeue`).
  - **What breaks / Why**: Ignores the futex address key, bitset, wake count, and requeue comparison/target, broadcasting to a single process-wide condition variable on every wake/requeue.
  - **Fix**: Key waiters by address and bitset, honor `max_wake` and `max_requeue`, and check `*uaddr == cmpval` under the futex lock.

- [x] **S64-6 — Medium — DEFECT — Darwin no-replace mapping can overwrite an existing mapping**
  - **Where**: `src/os/backend_darwin.c:202-213` (`rt_host_map_anon`).
  - **What breaks / Why**: When `fixed && noreplace` are both set, the `if (fixed)` branch runs first and calls `mmap(..., MAP_FIXED)` without probing `mincore`.
  - **Fix**: Check `noreplace` before `fixed` and guard the probe+map under the VM lock.

- [x] **S64-7 — Medium — DEFECT — Darwin copy fallback loses partial-write accounting**
  - **Where**: `src/os/backend_darwin.c:373-390` (`darwin_copy_loop`).
  - **What breaks / Why**: Updates `done` and `*in_off` only after an entire read chunk is written; if a subsequent write fails after a partial write succeeded, the already-written bytes are not accounted for.
  - **Fix**: Advance `done` and `*in_off` immediately after each successful `write`/`pwrite`.

- [x] **S64-8 — Medium — DEFECT — Darwin ppoll drops signal-mask and empty-set waiting behavior**
  - **Where**: `src/os/backend_darwin.c:578-593` (`rt_host_ppoll`).
  - **What breaks / Why**: Ignores `linux_sigmask` and immediately returns `0` when `nfds == 0` instead of sleeping for `timeout_ns`.
  - **Fix**: Honor `timeout_ns` even when `nfds == 0` (via `poll(NULL, 0, ...)` or wake-pipe poll) and apply/restore the temporary signal mask.

- [x] **S64-9 — Medium — DEFECT — VM validation helpers admit wrapped and out-of-range spans**
  - **Where**: `src/vm/vm64.c:125-127,161-177,182-204,210-225` (`vm64_align_up_8k`, VM argument validators).
  - **What breaks / Why**: Subtracts `addr` from `VM64_TASK_SIZE` without first checking `addr <= VM64_TASK_SIZE`, and `vm64_align_up_8k(UINT64_MAX)` wraps to `0`.
  - **Fix**: Check `addr <= VM64_TASK_SIZE` and check `val <= UINT64_MAX - 0x1fffULL` before aligning up.

### 10.2 Curated C11 & UB Issues

- [x] **S64-10 — Medium — C11 — Backward branch decoding left-shifts negative signed values**
  - **Where**: `src/interp/interp.c:94,109,116,131,149` (`sparc64_classify_word`); `src/interp/decode.c:215,230,247,256,564` (`sparc64_decode_word`).
  - **What breaks / Why**: Left-shifts negative sign-extended branch displacements (`<< 2`) in both decoders (C11 signed left-shift UB).
  - **Fix**: Perform the `<< 2` shift on `uint64_t` / `uint32_t` before sign-extending, or multiply the signed `int64_t` value by `4`.

- [x] **S64-11 — High — C11 — Darwin worker startup reads a parent stack object after its lifetime**
  - **Where**: `src/os/backend_darwin.c:763-786` (`worker_tramp`, `rt_host_spawn_worker`).
  - **What breaks / Why**: In `worker_tramp`, the child thread sets `st->ready = 1`, signals the condition variable, and unlocks `st->mu` *before* reading `st->fn` and `st->arg`. The parent thread wakes up and returns from `rt_host_spawn_worker`, destroying stack-allocated `st` before the child reads `st->fn(st->arg)` (stack use-after-return UB).
  - **Fix**: Copy `fn` and `arg` into local variables in `worker_tramp` *before* setting `st->ready = 1` and unlocking `st->mu`.

### 10.3 DRY, YAGNI & CLEAN

- [x] **S64-12 — Medium — DRY — Two instruction decoders have already diverged**
  - **Where**: `src/interp/interp.c:68-170,239-257` (`sparc64_classify_word`); `src/interp/decode.c:200-258,316-327,528-577` (`sparc64_decode_word`); `src/dbt/difftest.c:224-227`.
  - **What breaks / Why**: `sparc64rt` maintains two separate instruction decoders (`sparc64_classify_word` in `interp.c` and `sparc64_decode_word` in `decode.c`) that already disagree on `MOVcc` (`S64-3`).
  - **Fix**: Consolidate raw instruction decoding in `sparc64rt` so `interp`, `dbt`, and `difftest` share one authoritative decode table.

- [x] **S64-13 — Low — YAGNI — VM syscall validators are disconnected from production callers**
  - **Where**: `src/vm/vm64.c:182-204,210-242` (`vm64_check_munmap_args`, `vm64_check_mremap_args`).
  - **What breaks / Why**: Defined in `src/vm/vm64.c` with no production callers in `src/`.
  - **Fix**: Wire into the `munmap`/`mremap` syscall handlers (after fixing `S64-9`) or remove the unused functions.

- [x] **S64-14 — Low — CLEAN — Core implementation files have almost no size headroom**
  - **Where**: `src/interp/interp.c:1-900`, `src/os/syscalls_ext.c:1-894`, `src/dbt/dbt.c:1-892`, `src/interp/fp_sd.c:1-889`.
  - **What breaks / Why**: `interp.c` is at 900 lines and three other core files are at `889–894` lines.
  - **Fix**: Extract cohesive helpers into separate `.c` files when applying fixes `S64-2`, `S64-3`, and `S64-12`.

---

### R1-11. `rt-series` (`4e4512d` → `96e1fe6`) — 25 / 25 Resolved

### 11.1 Bugs & Defects

- [x] **RTS-1 — High — BUG — Cross-page fixture rejects correct big-endian execution**
  - **Where**: `tests/p3_torture.c:361-374` (`t_unaligned_cross_page`).
  - **What breaks / Why**: `memcpy(&got, edge, sizeof(got))` loads 8 bytes in native guest endianness, but `want` always packs `edge[0]` into the least-significant byte (`want |= (uint64_t)edge[i] << (i * 8)`). On big-endian guests (`ppc32`, `sparc32`, `sparc64`, big-endian MIPS), `got` and `want` have opposite byte orders, so a correct big-endian translator fails `t_unaligned_cross_page`.
  - **Fix**: Construct `want` in native guest byte order (or compare byte-for-byte via an aligned staging buffer) so both little-endian and big-endian guests are tested accurately.

- [x] **RTS-2 — High — DEFECT — Assembler/linker test substitutes a shell script and reports PASS**
  - **Where**: `tools/run_catalogue.sh:652-691` (`run_guest_payload`, Tier 4).
  - **What breaks / Why**: In `run_guest_payload`, assembly source for `as+ld .s link + exit 42` is only provided for `aarch64` and `x86_64`; the `*)` branch writes a `#!/bin/sh\nexit 42` shell script instead of assembling and linking a guest `.s` file, yet records `PASS` for `as+ld .s link + exit 42`.
  - **Fix**: Provide minimal `_start` exit-42 assembly snippets for all 10 guest architectures (`arm`, `i686`, `mips`, `ppc`, `sparc`, `riscv`, `loongarch64`, `ppc64le`, `mips64`, `sparc64`) and require `as` + `ld` to produce an ELF binary.

- [x] **RTS-3 — High — DEFECT — Benchmark PASS ignores process failure**
  - **Where**: `tools/bench_harness.sh:318-331`, `tools/bench_harness.sh:344-353`, `tools/bench_harness.sh:364-399` (`run_one_target`).
  - **What breaks / Why**: Benchmark invocations append `|| true`, discarding non-zero exit codes or timeouts if `ALL_PASS` was printed earlier, and converting QEMU checksum failures that lack `ALL_PASS` into `SKIP` instead of `FAIL`.
  - **Fix**: Capture the command exit code, require both `rc == 0` and `ALL_PASS`, and report `FAIL` when a runnable target crashes, times out, or fails checksum verification.

- [x] **RTS-4 — High — DEFECT — Grind architecture selection does not select a translator**
  - **Where**: `tools/run_grind.sh:39-46`, `tools/run_grind.sh:116-130`, `tools/run_grind.sh:164-207`, `tools/run_grind.sh:464-482` (`ARCH_FILTER`, grind dispatch).
  - **What breaks / Why**: `--arch <repo>` sets `ARCH_FILTER`, which is printed in the banner but never used to select a cross-compiler or `<arch>rt` translator binary; `stress-ng` and `gcc-torture` run on the host unless `GRIND_INTERP`/`GRIND_DBT` env vars are manually supplied.
  - **Fix**: Map `--arch <repo>` to the repository's cross-compiler and `--interp`/`--dbt` translator binaries automatically when `GRIND_*` overrides are not set.

- [x] **RTS-5 — High — DEFECT — Grind converts executed failures into tolerated skips**
  - **Where**: `tools/run_grind.sh:262-270`, `tools/run_grind.sh:409-435`, `tools/run_grind.sh:490-498` (`run_testfloat_suite`, `run_lmbench_suite`, final gate).
  - **What breaks / Why**: Non-zero exits from executed `testfloat` or `lmbench` runs increment `skip` instead of `fail`, and `GRIND_ALLOW_SKIP` (documented in the header) is never read.
  - **Fix**: Count non-zero exits from executed `testfloat`/`lmbench` binaries as `FAIL` and honor `GRIND_ALLOW_SKIP=0`.

- [x] **RTS-6 — High — DEFECT — Qualification checks fixture presence without requiring execution evidence**
  - **Where**: `tools/run_catalogue.sh:99-118`, `tools/run_catalogue.sh:751-780`, `tools/run_catalogue.sh:832-848` (`check_uniform_guests`, `run_repo_gate`, `run_host_qualify`).
  - **What breaks / Why**: `check_uniform_guests` verifies that `p3_torture.elf`, `smoke_tcg.elf`, `dyn_pie_test.elf`, and `rootfs/bin/busybox` exist on disk, then `run_repo_gate` delegates to `tests/parity_suite.sh` without verifying that the delegated script actually emitted `PASS` rows for all 10 required catalogue categories.
  - **Fix**: Verify in `run_repo_gate` / `run_host_qualify` that the delegated parity output contains `PASS` rows covering all required catalogue categories (`p3-torture`, `tcg-smoke`, `dyn-pie`, `t1-busybox`, `t2-core`, `t3-system`, `t4-compiler`) and zero `FAIL`/`GAP`/`SKIP` rows.

- [x] **RTS-7 — Medium — BUG — Tier 4 strips the symbol it later requires**
  - **Where**: `tools/run_catalogue.sh:553-560`, `tools/run_catalogue.sh:696-700` (`run_guest_payload`).
  - **What breaks / Why**: Tier 4 runs `strip "$hello_bin"` in place during the `strip` check and later runs `objdump -d "$hello_bin" | grep -q "main"`, which fails when `strip` removes the symbol table.
  - **Fix**: Run `strip` on a copy (`${hello_bin}.stripped`) or run `objdump -d` before `strip`.

- [x] **RTS-8 — Medium — BUG — Requested benchmark engine is not consistently passed**
  - **Where**: `tools/bench_harness.sh:306-327`, `tools/bench_harness.sh:344-349`, `tools/bench_harness.sh:364-377` (`run_one_target`).
  - **What breaks / Why**: `run_one_target` passes `--$ENGINE` only for 7 of the 10 translators on Darwin/Linux (omitting engine selection for `a32rt`, `i686rt`, and `rvrt`) and omits it on `hl`, yet labels all output rows with `$ENGINE`.
  - **Fix**: Pass each translator's engine selection flag/env (`A32_INTERP=1`, `I686_NO_JIT=1`, `RVRT_ENGINE=...`, `--interp`/`--dbt`) consistently or skip unsupported engine combinations explicitly.

- [x] **RTS-9 — Medium — DEFECT — Empty benchmark matrices succeed**
  - **Where**: `tools/bench_harness.sh:301-304`, `tools/bench_harness.sh:311-401`, `tools/bench_harness.sh:404-420` (`run_one_target`, `run_matrix`).
  - **What breaks / Why**: Passing an unknown `--arch` or `--target` runs zero benchmarks and exits `0`.
  - **Fix**: Reject unknown `--arch`/`--target`/`--engine` arguments and fail if zero benchmark rows were executed.

- [x] **RTS-10 — Medium — BUG — Optional grind settings become fatal unset-variable expansions**
  - **Where**: `tools/run_grind.sh:191-193`, `tools/run_grind.sh:234-235` (`run_gcc_torture_suite`, `run_testfloat_suite`).
  - **What breaks / Why**: Under `set -u`, `eval "_cmd=\$$_runner_var"` aborts when `GRIND_QEMU` is unset, and `${TESTFLOAT_ROUNDS_WEEKLY:-$TESTFLOAT_ROUNDS}` aborts when both env vars are unset instead of falling back to `$_rounds`.
  - **Fix**: Use `eval "_cmd=\${${_runner_var}:-}"` and `${TESTFLOAT_ROUNDS_WEEKLY:-$_rounds}`.

- [x] **RTS-11 — Medium — DEFECT — Existing binaries bypass source changes**
  - **Where**: `tools/build_uniform_guests.sh:43-48`, `tools/bench_harness.sh:146-174`, `tools/bench_harness.sh:212-221` (`already_built`, `build_guest_bins`).
  - **What breaks / Why**: `already_built` checks only `[ -x "$out/p3_torture.elf" ] && [ -x "$out/smoke_tcg.elf" ]`, skipping rebuilds when `tests/p3_torture.c`, `tests/tcg/smoke_tcg.c`, or `tests/bench_suite.c` is modified.
  - **Fix**: Rebuild whenever the C source file is newer than the output binary (`[ "$src" -nt "$bin" ]`) or `FORCE_REBUILD=1` is set.

- [x] **RTS-12 — Medium — BUG — Uniform container names collide and cleanup is not guaranteed**
  - **Where**: `tools/build_uniform_guests.sh:52-83`, `tools/build_uniform_guests.sh:259-296`.
  - **What breaks / Why**: Uses a hardcoded `--name rt-u-*-23194` suffix instead of `$$` and lacks an `EXIT`/`INT`/`TERM` trap to remove containers on interruption.
  - **Fix**: Use `$$` in container names and register a `trap` that removes any lingering `rt-u-*-$$` containers and verifies `docker ps`.

- [x] **RTS-13 — Medium — DEFECT — Remote benchmark execution has no wall-clock bound**
  - **Where**: `tools/remote_bench.sh:98-145`, `tools/remote_linux_inner.sh:40-75`.
  - **What breaks / Why**: Benchmark invocations in `remote_bench.sh` and `remote_linux_inner.sh` run without `timeout --kill-after=30s`.
  - **Fix**: Wrap every remote and inner benchmark execution in `timeout --kill-after=30s`.

- [x] **RTS-14 — Medium — BUG — Failed clock reads produce valid-looking benchmark timings**
  - **Where**: `tests/bench_suite.c:32-38`, `tests/bench_suite.c:291-304`, `tests/bench_suite.c:390-400` (`get_monotonic_time`, `elapsed_us_between`).
  - **What breaks / Why**: Ignores `clock_gettime` return values and clamps `0 us` to `1 us`, reporting fabricated timings if `clock_gettime` fails.
  - **Fix**: Check the `clock_gettime` return value and fail the benchmark if the clock syscall fails.

- [x] **RTS-15 — Medium — BUG — Alternate-stack error paths free a registered stack**
  - **Where**: `tests/p3_torture.c:313-338` (`t_sigaltstack`).
  - **What breaks / Why**: If `sigaction` or `raise` fails after `sigaltstack(&ss, &old_ss)` succeeds, `free(alt)` runs without disabling the registered alternate signal stack first.
  - **Fix**: Disable the alternate stack (`SS_DISABLE`) before calling `free(alt)` on all exit paths.

- [x] **RTS-16 — Medium — DEFECT — Signal torture passes without exercising the claimed register/reservation conditions**
  - **Where**: `tests/p3_torture.c:173-235`, `tests/p3_torture.c:238-293` (`t_sig_frame_gpr`, `t_sig_frame_fpr`).
  - **What breaks / Why**: `t_sig_frame_gpr` only checks `ucontext != NULL` and runs `__sync_bool_compare_and_swap` *after* `raise(SIGUSR1)` returns; `t_sig_frame_fpr` allows the fallback `raise(SIGALRM)` after the FP loop finishes and leaves the alarm armed during the reference loop.
  - **Fix**: Cancel any pending `alarm(0)` before the reference loop and verify live volatile/callee-saved register preservation across asynchronous signal delivery.

- [x] **RTS-17 — Medium — DEFECT — Missing core fixture capabilities still produce ALL_OK**
  - **Where**: `tests/p3_torture.c:531-550`, `tests/tcg/smoke_tcg.c:443-461` (`main`).
  - **What breaks / Why**: Both fixtures print `ALL_OK` and return `0` as long as `g_fail == 0 && g_pass > 0`, even if `g_skip > 0` because `mmap`, `sigaction`, `sigaltstack`, or `pthread_create` returned `ENOSYS`.
  - **Fix**: Require `g_skip == 0` (unless an explicit allow-skip flag/env is set) before printing `ALL_OK`.

- [x] **RTS-25 — Medium — DEFECT — Stderr normalization hides input failures**
  - **Where**: `tools/parity_contract.sh:72-77` (`parity_norm_stderr`).
  - **What breaks / Why**: `grep -v -E ... "$_pns_in" > "$_pns_out" || true` masks exit code `2` (missing/unreadable input file), producing an empty output file that matches an empty golden stderr.
  - **Fix**: Check `[ -r "$_pns_in" ]` and allow only `grep` exit codes `0` and `1`.

### 11.2 Curated C11 & UB Issues

- [x] **RTS-18 — High — C11 — Thread arithmetic overflows signed long on 32-bit guests**
  - **Where**: `tests/tcg/smoke_tcg.c:265-284` (`thread_fn`, `t_testthread`).
  - **What breaks / Why**: With `n = 200000`, `sum += i` reaches `19,999,900,000` and `n * (n - 1) / 2` reaches `39,999,800,000`, overflowing 32-bit signed `long` on all five Class-A ILP32 guests (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt` + `rv32gc`), which is C11 signed integer overflow UB.
  - **Fix**: Use `int64_t` / `uint64_t` for `sum` and `(int64_t)n * (n - 1) / 2` (or reduce `n` so `n * (n - 1)` fits in `int32_t`).

- [x] **RTS-19 — Medium — C11 — Thread error path can leave a pointer to an expired stack object**
  - **Where**: `tests/tcg/smoke_tcg.c:265-267`, `tests/tcg/smoke_tcg.c:283-310` (`thread_fn`, `t_testthread`).
  - **What breaks / Why**: `pthread_create` receives `&n` (a stack local); if `munmap` fails before `pthread_join`, `t_testthread` returns while the child thread is still running and reading `&n`.
  - **Fix**: Always `pthread_join` a created thread before returning from `t_testthread`.

### 11.3 DRY, YAGNI & CLEAN

- [x] **RTS-20 — Low — DRY — Remote benchmark parser and architecture matrix are duplicated**
  - **Where**: `tools/remote_bench.sh:15-31`, `tools/remote_linux_inner.sh:14-30` (`ARCH_LIST`, `parse_and_print`).
  - **What breaks / Why**: Identical `ARCH_LIST` and 7-field output parser duplicated across both scripts.
  - **Fix**: Factor into a shared shell helper sourced by both scripts.

- [x] **RTS-21 — Low — DRY — Uniform guest builders repeat the same build procedure fourteen times**
  - **Where**: `tools/build_uniform_guests.sh:52-255`, `tools/build_uniform_guests.sh:259-277` (`build_*`).
  - **What breaks / Why**: Fourteen nearly identical `build_<abi>` functions repeat directory setup, container invocation, and compiler flags.
  - **Fix**: Drive uniform guest builds from a single parameterized helper function.

- [x] **RTS-22 — Medium — YAGNI — Weekly soak is permanently skipped scaffolding**
  - **Where**: `tools/run_grind.sh:438-452`, `tools/run_grind.sh:474-482` (`run_weekly_soak`).
  - **What breaks / Why**: Both `csmith` and `yarpgen` branches in `run_weekly_soak` unconditionally increment `skip` even when the tools are installed.
  - **Fix**: Execute bounded `csmith` / `yarpgen` generation+differential runs when installed, or remove the no-op branches.

- [x] **RTS-23 — Low — CLEAN — Catalogue status documentation contradicts current skip behavior**
  - **Where**: `docs/CATALOGUE-TODO.md:3`, `docs/CATALOGUE-TODO.md:47`; `tools/run_catalogue.sh:733-747`.
  - **What breaks / Why**: `docs/CATALOGUE-TODO.md` still describes pre-Wave-C2 behavior where missing T2–T4 tools were silently skipped.
  - **Fix**: Mark the historical audit findings in `docs/CATALOGUE-TODO.md` as resolved by Wave C1/C2.

- [x] **RTS-24 — Low — CLEAN — Benchmark implementation is seven lines below the C file ceiling**
  - **Where**: `tests/bench_suite.c:1-893`.
  - **What breaks / Why**: At 893 lines, leaving only 7 lines of headroom under the 900-line ceiling.
  - **Fix**: Split architecture syscall/startup glue (`tests/bench_sys.h`) from the benchmark kernels (`tests/bench_suite.c`) when touching `bench_suite.c`.
