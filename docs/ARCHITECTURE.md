# `rt-series` Architecture

This manual describes the implemented architecture shared by all 10 `rt-series`
translators: two address-space classes, a uniform 5-module repository layout, a
7-instruction Soft-TLB, in-place non-relocating copy-on-write, and dual host
OS backends. It distills the normative rules of the archived
[master specification](archive/plans/SPEC.md) and
[unification plan](archive/plans/UNIFICATION-PLAN.md) into present-tense
engineering documentation.

## 1. Series Overview & Standalone Zero-Dependency Invariant

`rt-series` is a family of 10 user-mode binary translators that run foreign
Linux userspace on AArch64 hosts. Five translators cover 32-bit guests
(`a32rt` for AArch32, `i686rt` for x86-32, `mips32rt`, `ppc32rt`, `sparc32rt`
for SPARC V8) and five cover 64-bit guests (`rvrt` for RV64GC and RV32GC,
`loongarch64rt`, `ppc64rt` for `ppc64le` ELFv2, `mips64rt` for N64/N32, and
`sparc64rt` for SPARC V9).

Every translator repository is standalone and zero-dependency: it builds with
only static `musl` libc plus the host system libraries, and it never imports a
shared cross-repository library. Substrate reuse between translators is
copy-first — each repository vendors the code it needs — so every repository
remains independently buildable and no cross-repo API churn can break a
translator. Bug clusters found in one translator are checked against the
sibling codebases as shared knowledge, never as shared code.

All translators run in three environments from the same source tree: native
AArch64 Linux, `hyper-linux` (`hl`) on Apple Silicon, and standalone macOS on
Apple Silicon with no virtual machine involved.

## 2. Address-Space Classes & Three-Layer Page-Size Contract

### 2.1 Class A — 32-Bit Fixed 4 GiB Window (`vm32`)

Each Class-A translator reserves a contiguous 4 GiB window `[G, G + 4 GiB)` in
its own 64-bit host virtual address space. `G` is `0` when `[0x10000, 4 GiB)`
is free on native Linux, and `G = 0x1_0000_0000` in offset mode under
`hyper-linux`, negotiated at startup through `/dev/a32host`
(`A32H_ABI 1.0/1.1`) with explicit `--window` and `<RT>_WINDOW` overrides.

Two regimes share one invariant — every 32-bit guest effective address is
computed in a 32-bit `W` register, giving exact modulo-2³² wraparound:

- **Regime A1 (`H == 4096`).** Reserved register `x20` holds the window base
  `xG`, and translation is a single instruction: `[x20, wAddr, uxtw]`.
- **Regime A2 (`H > 4096`, e.g. 16 KiB macOS or 16/64 KiB Linux).**
  `x20` holds `&ctx->tlb[0]` and every access goes through the 7-instruction
  Soft-TLB described in §4 (`x23` carries `xG` where the emitter needs it).

### 2.2 Class B — 64-Bit Sparse Radix Address Space (`vm64`)

Class-B translators never force a 64-bit guest into a 4 GiB window. Guest VA
(`uint64_t`), translator VA, and host GPA are strictly separated by a checked
sparse software radix page table (`rv_space`) with 4 KiB granularity
(`RV_PAGE_SHIFT = 12`). The same machinery also hosts 32-bit pointer profiles
(RV32GC with `va_bits = 32`, MIPS N32 with a 31-bit task size).

Each guest profile declares its own exclusive limit below which stacks, the
`mmap` region, the interpreter area, and signal trampolines live:
`0x7fff8000` for MIPS O32/N32, `4 GiB` for RV32, `1 TiB` (`1ULL << 40`) for
MIPS64 N64, and `128 TiB` (`1ULL << 47`) for RV64, LoongArch64, PPC64, and
SPARC64. Inside the arena, translation is a constant offset:
`HVA = arena_base + gva`.

### 2.3 Three-Layer Page-Size Contract

Guest ABI pages, translation granules, and host backing pages are three
independent layers:

1. **Guest ABI page size.** Every translator reports `AT_PAGESZ = 4096`,
   except `sparc64rt`, which reports `AT_PAGESZ = 8192` per the SPARC V9 Linux
   ABI. On `sparc64rt` all guest-visible VM semantics — `mmap`/`mprotect`/
   `munmap`/`mremap` alignment, COW promotion, EOF rounding — operate on the
   8 KiB granule, with pairs of 4 KiB Soft-TLB entries (`vpn`, `vpn ^ 1`)
   updated together.
2. **Translation granule (`4096`).** The Soft-TLB is indexed by 4 KiB virtual
   page number (`(gva >> 12) & 0xFFF`) on every translator, including
   `sparc64rt`.
3. **Host backing page (`H`).** The host page size is queried at startup
   (`4096`, `16384`, or `65536`). Inside `hyper-linux` the guest Stage-1 MMU
   always uses 4 KiB pages, so `H == 4096` there even on 16 KiB Apple Silicon
   hosts. `ppc64le` ELFs linked with `p_align = 0x10000` (64 KiB) load
   directly onto 4 KiB pages because `0x10000` is an exact multiple of
   `0x1000` (`p_vaddr % 4096 == p_offset % 4096`).

## 3. Uniform 5-Module Layout & Source Discipline

Every repository uses the same five source modules:

| Module | Contents |
| --- | --- |
| `src/core/` | CPU context ABI, loader, ELF and `PT_INTERP` handling |
| `src/interp/` | Portable Curated-C11 reference interpreter, the correctness oracle |
| `src/dbt/` | AArch64 DBT engine (`dbt.c`, `a64_emit.c`, block cache, chaining, IBTC, RAS), per-ISA emitters, `trampoline_a64.S`, `difftest.c` lockstep verifier, and `aot/` (persistent cache format plus relative `dbt_mem_site_t[]` tables) |
| `src/vm/` | Guest address space and fault recovery (`vm32.c` for Class A, `vm64.c` for Class B, `vm_file.c` for file-backed COW) |
| `src/os/` | Guest Linux ABI normalization (syscalls, signals, threads, `execve`, `/proc/self` synthesis) plus `backend_linux.c` and `backend_darwin.c` |

All modules obey one source discipline:

- **Curated C11** (`-std=c11 -Werror=vla -pedantic -Wall -Wextra`): no VLAs,
  no Annex K (`*_s`), no `<threads.h>`, no `_Generic`, no
  `sprintf`/`strcpy`/`strcat`.
- **At most 900 lines per file**, with zero textual `#include "*.c"` unity
  includes.
- **Register `x18` is permanently reserved** on AArch64 across all JIT
  emitters and assembly trampolines; `x19` is the CPU context pointer and
  `x20` is `xG` (Regime A1) or `&ctx->tlb[0]` (everywhere else).
- **Write-through FPR cache.** Emitted code keeps guest floating-point
  registers in AArch64 `d8..d15` (callee-saved, so helper calls preserve
  them) and writes every update through to the CPU context, spilling the
  cache at each block exit so signals and fallback paths always observe
  coherent FP state.

## 4. 7-Instruction Soft-TLB, 2-Instruction Miss Stub & `dbt_mem_site_t`

### 4.1 Soft-TLB Entry Layout (32 Bytes per Entry)

```c
typedef struct {
    uint64_t  read_tag;       /* (gva & ~0xFFF) if readable and below EOF */
    uintptr_t addend;         /* host_page_base - (gva & ~0xFFF)           */
    uint64_t  write_tag;      /* (gva & ~0xFFF) if writable, clean of code,
                                 COW-clean pages, and LL/SC reservations  */
    uint64_t  flags_reserved; /* zero-initialized, 32-byte cache aligned  */
} rt_tlb_entry_t;
```

4096 entries (`RT_TLB_BITS = 12`) cover the hot working set per thread; a tag
of `~0ULL` never matches a valid page number.

### 4.2 Fast-Path Instruction Sequence

Loads fetch `read_tag`/`addend` with `ldp x2, x3, [x2, #0]`; stores fetch
`addend`/`write_tag` with the swapped pair `ldp x3, x2, [x2, #8]`. The first
six instructions never touch `PSTATE.NZCV` and never clobber `x0`
(value/destination) or `x1` (guest address):

1. `ubfx x2, x1, #12, #12` — page-table index from the guest address.
2. `add x2, x20, x2, lsl #5` — address of `ctx->tlb[index]`.
3. `ldp` — load the tag pair.
4. `and`/`bic` — fold the access size into the alignment check.
5. `sub` — zero if and only if tag and alignment both match.
6. `cbnz` — leave the fast path on miss or misalign (`x0`/`x1` intact).
7. `ldr`/`str [x1, x3]` — the host access (with `REV16`/`REV32`/`REV64`
   lowering for big-endian guests).

On a miss, control reaches a compact **2-instruction per-site stub** that
preserves the faulting guest address and value register, records the site,
and routes to the cold resolver — avoiding a full register save/restore at
every memory operation.

### 4.3 Relative `dbt_mem_site_t` (24 Bytes per Site)

Every translated memory operation carries a position-independent recovery
record so signals, preemption, and AOT reload can reconstruct exact guest
state without absolute code addresses:

```c
typedef struct {
    uint32_t seq_start_offset;  /* byte offset of the lookup start (rewind) */
    int16_t  sp_rollback_delta; /* pre-store stack/base adjustment to undo  */
    uint8_t  npc_mode;          /* delay-slot mode, incl. RT_NPC_DYNAMIC_CTX */
    uint8_t  addr_base_reg;     /* architectural base register, if rolled back */
    /* ... size and access-kind fields ... */
} dbt_mem_site_t;
```

`seq_start_offset` lets the preemption handler rewind `ucontext->pc` to the
lookup start when it interrupts instructions 1–6 (which have no architectural
side effects). `sp_rollback_delta` undoes pre-store writebacks of
`PUSH`/`POP`/`CALL`/`LDM`/`STM` before raising a guest signal or entering
`interp_step`. `RT_NPC_DYNAMIC_CTX` recovers dynamic indirect delay-slot
targets (MIPS `JR`/`JALR`, SPARC `JMPL`) from `ctx->delay_target`. Because
every field is block-relative, serialized site tables reload at any AOT
rebase address.

## 5. In-Place Non-Relocating COW & 6-Step Quiescence

### 5.1 Provider A — In-Place Arena COW (`src/vm/vm_file.c`)

On native Linux and standalone Darwin, `Provider A` keeps **every guest page
at its fixed canonical arena address** (`HVA = arena_base + gva`), so the
Soft-TLB `addend` stays constant across the whole arena. File-backed mappings
stay backed by their host file descriptor; `MAP_PRIVATE` pages promote
in place from `PAGE_COW_CLEAN` to `PAGE_COW_DIRTY` on first write, and a
lightweight family-shared inode table tracks `MAP_SHARED` identity, EOF
truncation, and futex admission across `fork` without relocating any page.

### 5.2 Provider B — `hyper-linux` Stage-1 COW

Under `hyper-linux`, `Provider B` (`hl_inode_backing_t`) performs the same
promotion in the VMM: copy-on-write repoints guest Stage-1 L3 PTEs to freshly
allocated physical pages, actively preempts running vCPUs (`hv_vcpus_exit`),
and broadcasts the invalidation through a shared DBT ring so translators drop
translated blocks that observed the stale mapping. Futex identity is pinned
before the bucket lock to keep the wait queue stable across promotion.

### 5.3 Deadlock-Free `Prepare -> Quiesce -> Host-Op -> Commit` Protocol

Every operation that mutates mappings visible to running translated code —
`mmap`, `mprotect`, `mremap`, COW promotion, truncation — runs one
transaction:

1. **Prepare.** Describe the pending mutation and take the VM mutation lock.
2. **Quiesce.** Bump each peer worker's DBT epoch (breaking block-to-block
   direct chains); for every peer still running translated code, deliver the
   reserved preemption signal (`SIGRTMIN + 1` via `tgkill` on Linux,
   `SIGUSR2` via `pthread_kill` on Darwin).
3. **Signal-handler rewind.** A handler that lands inside a translated block
   rewinds `ucontext->pc` to `block_base + site->seq_start_offset` when the
   interrupted PC sits inside a Soft-TLB lookup, marks the worker parked, and
   waits on the quiescence futex/condvar.
4. **Host-Op.** Perform the host mapping change while no worker can observe
   a half-mutated table.
5. **Commit.** Publish tags, invalidate affected translated blocks under the
   code-version lock, and release the mutation lock so parked workers resume.

The order is deadlock-free because translators never take the VM mutation
lock while holding the code lock, and the preemption signal never blocks.

## 6. Dual Host OS Backends

Both backends implement the same frozen `rt_host_*` interface over
`src/core/` + `src/os/`; only the bottom layer differs.

| Concern | `backend_linux.c` (static-PIE) | `backend_darwin.c` (Mach-O `arm64`) |
| --- | --- | --- |
| Binary | `aarch64-unknown-linux-musl-gcc -static-pie -fPIE`, runs on AArch64 Linux and under `hyper-linux` | Native Mach-O, runs directly on macOS with no Hypervisor dependency |
| Syscalls | Raw AArch64 `svc #0` through signal-atomic `safe_syscall_a64.S` | Direct branches into `libSystem`, per-class `kqueue`/wakeup-pipe signal-atomic blocking |
| Guest ABI | Linux UAPI directly; `/dev/a32host` handshake plus family shared-memory inode table | Linux-to-Darwin `errno`, open-flag, `stat`, `dirent`, and `sockaddr` translation |
| W^X JIT | Host `mprotect` plus I-cache seal and invalidate | `MAP_JIT` with `pthread_jit_write_protect_np` APRR toggling plus I-cache seal and invalidate |

Guest data pages are never mapped `PROT_EXEC` on the host. Translated code is
emitted into RW staging pages, flipped to `PROT_READ | PROT_EXEC`, and the
instruction cache is invalidated at seal time (trapping `IC IVAU` at EL2 only
when `A32H_CAP_ICACHE_TRAP_IALLU` is active under `hyper-linux`).

## 7. Cross-ISA Architectural Decisions (`D1–D11`)

| # | Decision | Rule |
| --- | --- | --- |
| D1 | Language, toolchain, binary format | Curated C11 plus minimal AArch64 assembly, static-PIE `musl`, zero dependencies, `x18` reserved. |
| D2 | Two address-space classes | Class A fixed 4 GiB window; Class B checked sparse radix with per-profile task-size limits. |
| D3 | Copy-first substrate reuse | Each repository vendors what it needs; no shared library is ever extracted across repositories. |
| D4 | Dual engines with single-step fallback | Portable `interp` oracle plus AArch64 DBT; declined instructions trap to `interp_step` and resume DBT, with an independent `qemu-<arch>` oracle at every gate. |
| D5 | Big-endian guest memory | Guest bytes stay in guest-native order in RAM; 16/32/64-bit accesses lower to `REV16`/`REV32`/`REV64` around host loads/stores. |
| D6 | Delay-slot and annul state machine | Explicit `(pc, npc)` with page-boundary progress rules; annulled delay slots never fault on the unmapped page after the branch. |
| D7 | Syscall error polarity adapters | Each guest gets its exact kernel ABI: `-errno` (ARM/x86/RISC-V/LoongArch/PPC64-`scv`), `$a3 = 1, $v0 = +errno` (MIPS), `CR0.SO = 1, r3 = +errno` (PowerPC `sc`), `PSR.icc.C = 1, %o0 = +errno` (SPARC V8), `icc.C \| xcc.C = 1` (SPARC V9). |
| D8 | Guest errno/signal/socket/flag tables & MIPS 128-signal namespace | Compile-time verified tables from pinned Linux UAPI headers; MIPS owns the full 1–128 signal space with guest-owned action/pending/queue tables. |
| D9 | Unaligned-safe software TSO | TSO guests emit unaligned-capable loads/stores with fences by default; hardware TSO elision requires readback-verified capability on every vCPU path. |
| D10 | FPU/SIMD before dynamic libc | FPU and SIMD land before signals and `PT_INTERP`; `AT_HWCAP`/`CPUCFG` advertise exactly the implemented profile. |
| D11 | Three-layer page-size policy | 4 KiB guest ABI (8 KiB on `sparc64rt`), 4 KiB translation granule, 4/16/64 KiB host backing, 64 KiB-tolerant ELF loading. |

Together these decisions keep one invariant everywhere: the guest observes
exact Linux ABI behavior — byte order, error codes, signal frames, page
permissions, and memory ordering — while the host observes only ordinary
user-mode AArch64 execution.
