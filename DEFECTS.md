# `rt-series` Master Defect, Curated-C11, DRY, YAGNI & CLEAN Checklist

**Audit Date:** 2026-11-02  
**Reviewer:** `gpt-6-astra` (`codex exec -m gpt-6-astra --sandbox read-only`) across 11 concurrent read-only static audit lanes  
**Scope:** All 10 `<arch>rt` binary translator repositories (Class A 32-bit 4 GiB-window & Class B 64-bit full-address-space) plus the `rt-series` coordination, benchmark, and qualification harness repository.  
**Architectural Invariants Enforced:**
1. **Standalone Zero-Dependency Repositories (`AGENTS.md` §2.1):** Each `<arch>rt` repository is standalone; **DRY findings are strictly intra-repository** (never extract a shared cross-repo `librt32` or `librt64` C library).
2. **Curated C11 (`AGENTS.md` §2.2):** `-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror`, no VLAs, no banned libc functions (`strcpy`, `strcat`, `sprintf`, `atoi`), `x18` permanently reserved on AArch64, no textual `#include "*.c"` unity includes, and every `.c`/`.h`/`.S` file $\le 900$ lines.

---

## 0. Executive Summary & Per-Repository Audit Matrix

**Remediation Status:** **187 / 187 RESOLVED (`100%`)** across all 11 repositories (`0` files $> 900$ lines outside third-party `vendor/`, `0` textual `#include "*.c"` unity includes, all repository unit & `parity_suite.sh` gates passing).

| # | Repository | Class | Audit Base | Resolved `master` | High | Medium | Low | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | **Total** | Verification Gate | Raw `astra` Transcript |
|---:|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | `a32rt` | Class A | `55cdc5f` | `a5f53b4` | 9 | 6 | 3 | 11 | 0 | 3 | 1 | 1 | 2 | **18 / 18** | `45/45 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-a32rt-astra.md`](lode/reviews/2026-11-02-defects-a32rt-astra.md) |
| 2 | `i686rt` | Class A | `2fa17fb` | `8db8727` | 10 | 5 | 5 | 10 | 1 | 3 | 1 | 1 | 4 | **20 / 20** | `41/41 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-i686rt-astra.md`](lode/reviews/2026-11-02-defects-i686rt-astra.md) |
| 3 | `mips32rt` | Class A | `e0b10a2` | `366ca9b` | 11 | 6 | 3 | 11 | 0 | 3 | 2 | 2 | 2 | **20 / 20** | `143/143 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-mips32rt-astra.md`](lode/reviews/2026-11-02-defects-mips32rt-astra.md) |
| 4 | `ppc32rt` | Class A | `3582753` | `abe6b0b` | 7 | 4 | 4 | 8 | 1 | 2 | 1 | 1 | 2 | **15 / 15** | `106/106 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-ppc32rt-astra.md`](lode/reviews/2026-11-02-defects-ppc32rt-astra.md) |
| 5 | `sparc32rt` | Class A | `816cc90` | `dad95da` | 9 | 5 | 4 | 11 | 0 | 2 | 1 | 1 | 3 | **18 / 18** | `30/30 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-sparc32rt-astra.md`](lode/reviews/2026-11-02-defects-sparc32rt-astra.md) |
| 6 | `rvrt` | Class B | `29ce5fd` | `8e207fb` | 1 | 6 | 3 | 3 | 1 | 2 | 1 | 1 | 2 | **10 / 10** | `68/68 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-rvrt-astra.md`](lode/reviews/2026-11-02-defects-rvrt-astra.md) |
| 7 | `loongarch64rt` | Class B | `0f57c40` | `026e87d` | 5 | 5 | 3 | 7 | 1 | 1 | 1 | 1 | 2 | **13 / 13** | `53/53 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-loongarch64rt-astra.md`](lode/reviews/2026-11-02-defects-loongarch64rt-astra.md) |
| 8 | `ppc64rt` | Class B | `f42cf1a` | `bd3e73f` | 6 | 5 | 5 | 8 | 2 | 2 | 1 | 1 | 2 | **16 / 16** | `35/35 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-ppc64rt-astra.md`](lode/reviews/2026-11-02-defects-ppc64rt-astra.md) |
| 9 | `mips64rt` | Class B | `8d5950c` | `32d5c9e` | 8 | 7 | 3 | 9 | 3 | 2 | 1 | 1 | 2 | **18 / 18** | `56/56 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-mips64rt-astra.md`](lode/reviews/2026-11-02-defects-mips64rt-astra.md) |
| 10 | `sparc64rt` | Class B | `71fe7a5` | `3ead4f9` | 3 | 9 | 2 | 3 | 6 | 2 | 1 | 1 | 1 | **14 / 14** | `32/32 PASS` (`parity_suite.sh`) | [`2026-11-02-defects-sparc64rt-astra.md`](lode/reviews/2026-11-02-defects-sparc64rt-astra.md) |
| 11 | `rt-series` | Harness | `4e4512d` | `96e1fe6` | 7 | 14 | 4 | 7 | 11 | 2 | 2 | 1 | 2 | **25 / 25** | `ALL_OK` (`check` + `p3_torture` + `tcg_smoke` + `catalogue`) | [`2026-11-02-defects-rt-series-astra.md`](lode/reviews/2026-11-02-defects-rt-series-astra.md) |
| | **Total** | | | | **76** | **72** | **39** | **88** | **26** | **24** | **13** | **12** | **24** | **187 / 187** | **All 11 Repositories Verified** | |

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

## 1. `a32rt` (`55cdc5f` → `a5f53b4`) — 18 / 18 Resolved

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

## 2. `i686rt` (`2fa17fb` → `8db8727`) — 20 / 20 Resolved

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

## 3. `mips32rt` (`e0b10a2` → `366ca9b`) — 20 / 20 Resolved

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

## 4. `ppc32rt` (`3582753` → `abe6b0b`) — 15 / 15 Resolved

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

## 5. `sparc32rt` (`816cc90` → `dad95da`) — 18 / 18 Resolved

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

## 6. `rvrt` (`29ce5fd` → `8e207fb`) — 10 / 10 Resolved

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

## 7. `loongarch64rt` (`0f57c40` → `026e87d`) — 13 / 13 Resolved

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

## 8. `ppc64rt` (`f42cf1a` → `bd3e73f`) — 16 / 16 Resolved

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

## 9. `mips64rt` (`8d5950c` → `32d5c9e`) — 18 / 18 Resolved

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

## 10. `sparc64rt` (`71fe7a5` → `3ead4f9`) — 14 / 14 Resolved

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

## 11. `rt-series` (`4e4512d` → `96e1fe6`) — 25 / 25 Resolved

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
