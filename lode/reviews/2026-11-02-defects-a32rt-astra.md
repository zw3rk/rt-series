# a32rt — static audit

**HEAD:** `55cdc5fcdf6fda8d7df6d1e9b1b871a7bb72d3da`

**Inventory:** 25,128 physical lines of `.c`, `.h`, and `.S` under `src/` and `include/`; 39,951 including matching files under `tests/`.

Seven batched shell inspections were used. No builds, tests, emulators, or repository modifications were performed. Inspection covered selected loader/runtime, interpreter, emitter, VM, backend, syscall, signal, JIT/AOT, and build paths. Some large outputs were truncated; this is a bounded static audit, **not exhaustive verification of every module**.

The strongest findings concern guest protection bypasses on A2 hosts, incorrect shared mappings, unsafe pathname reads, interpreter semantics, and C undefined behavior. No Critical finding was established.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 7 | 0 | 2 | 0 | 0 | 0 | 9 |
| Medium | 4 | 0 | 1 | 0 | 0 | 1 | 6 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **11** | **0** | **3** | **1** | **1** | **2** | **18** |

## 1. Bugs & Defects

### High

- [ ] **A32-1 — High — BUG — Soft-TLB fast path checks only the starting page**
  - **Where**: `src/core/core_emit_alu.c:676-732` (`emit_guest_mem`); `src/os/backend_darwin.c:164-184` (`a32_backend_protect`).
  - **What breaks / Why**: Generated A2 accesses compare the starting virtual page’s tag and then execute the host access. They do not check alignment or whether the access crosses a 4 KiB boundary. For example, a word load at page offset `4094` can read two bytes from an adjacent guest `PROT_NONE` page. Darwin keeps the covering host pages RW, so host protection does not enforce the missing check. The alignment checks in the C probe do not protect this independently emitted path.
  - **Fix**: Check the complete access span before the host instruction. Send cross-page accesses through a checked slow path that validates both guest pages and preserves fault state.

- [ ] **A32-2 — High — BUG — Doubleword transfers bypass A2 guest permissions**
  - **Where**: `src/core/core_emit_mem.c:20-40` (`a64_emit_guest_ldrd_w`, `a64_emit_guest_strd_w`); `src/interp/interp_t32_mem.c:269-305` (LDRD/STRD lowering); `src/os/backend_darwin.c:175-184` (`a32_backend_protect`).
  - **What breaks / Why**: LDRD/STRD emit a direct guest-base addition followed by host LDP/STP, bypassing the Soft-TLB. A guest read-only or inaccessible subpage remains host-writable/readable on Darwin. STRD can therefore modify guest read-only memory, and LDRD can read guest-inaccessible memory.
  - **Fix**: Give these emitters an A2 permission-checked implementation covering the entire eight-byte span. Audit other direct multiword, vector, and exclusive access emitters for the same bypass.

- [ ] **A32-3 — High — BUG — Anonymous shared mappings become private**
  - **Where**: `src/vm/vm_file.c:145-147` (`a32_vmfile_map_commit`); `src/os/backend_linux.c:67-84` and `src/os/backend_darwin.c:65-95` (`a32_backend_map_anon`).
  - **What breaks / Why**: The anonymous branch discards the requested sharing mode. Both backends hardcode `MAP_PRIVATE | MAP_ANONYMOUS`. A guest `MAP_SHARED | MAP_ANONYMOUS` mapping consequently becomes private across a native host fork, breaking shared-memory communication and shared futex use.
  - **Fix**: Carry the sharing mode through the anonymous backend API and preserve it through fork and remap paths. Use genuinely shared backing where the host requires it.

- [ ] **A32-4 — High — BUG — Darwin MAP_SHARED file mappings are private byte copies**
  - **Where**: `src/os/backend_darwin.c:107-142` (`a32_backend_map_file`); `src/vm/vm_file.c:149-151` (`a32_vmfile_map_commit`).
  - **What breaks / Why**: The normal replacement path zeroes the arena and fills it with `pread`, returning before the actual file-backed `mmap`. This happens even when `shared` is true. Writes through the mapping do not update the file or another mapping of it; external file changes are not coherently visible either. Calling `msync` on anonymous arena memory cannot restore those semantics.
  - **Fix**: Implement shared file backing that preserves file identity and alias coherence, including host-page alignment constraints. Until supported, reject unsupported shared mappings explicitly instead of silently copying them.

- [ ] **A32-5 — High — BUG — Pathname validation can fault inside the translator**
  - **Where**: `src/os/os_sys_path.c:416-430` (`resolve_guest_path_at`).
  - **What breaks / Why**: Only the first byte is checked with `a32_guest_range_ok`; `strnlen(gpath, PATH_MAX)` then reads directly across subsequent pages. A nonterminated string ending at a readable page boundary followed by an inaccessible page faults in host libc instead of returning guest `-EFAULT`. On A2, it can read bytes from guest-inaccessible but host-readable subpages.
  - **Fix**: Copy guest strings into a bounded host buffer using page-aware, fault-safe reads. Distinguish inaccessible memory from an accessible string exceeding `PATH_MAX`, and resolve only the copied string.

- [ ] **A32-6 — High — BUG — Synchronous faults outside JIT blocks retry forever**
  - **Where**: `src/signals.c:392-429` (`host_sig_handler`).
  - **What breaks / Why**: A genuine synchronous fault whose host PC is outside the JIT cache is enqueued as an asynchronous signal, then the handler returns without changing the faulting PC. The same host instruction faults again immediately. The pathname overread above is one concrete trigger. Guest pending-signal processing never gets a chance to run.
  - **Fix**: Distinguish user-generated signals from genuine host faults independently of JIT membership. Recover checked guest-memory operations through an explicit fault-recovery mechanism; terminate unexpected translator faults rather than returning to the same instruction.

- [ ] **A32-7 — High — BUG — Thumb-2 interpreter branch decoder ignores conditions and mixes encodings**
  - **Where**: `src/interp/interp_thumb.c:606-633` (`t32_step`).
  - **What breaks / Why**: The broad branch match includes conditional B.W, but the code never evaluates its condition. It also chooses the displacement format using `hw1 & 0x0800` instead of the relevant second-halfword encoding discriminator, and one B.W path writes LR despite the preceding match excluding BL/BLX. Valid branches can execute when their condition is false, compute the wrong target, or corrupt LR.
  - **Fix**: Decode conditional B.W and unconditional B.W separately using their complete masks. Apply each format’s displacement construction, evaluate conditional branches, and update LR only for actual link instructions.

### Medium

- [ ] **A32-8 — Medium — BUG — Thumb immediate shifts produce incorrect flags and LSR results**
  - **Where**: `src/interp/interp_thumb.c:95-124` (Thumb immediate shifts).
  - **What breaks / Why**: Immediate LSR with encoded `imm5 == 0` means a shift by 32, but the interpreter preserves the input and carry. The same block calls `i_set_nzcv(..., false)`, clearing V for shift instructions that should preserve it. Subsequent condition-dependent instructions can diverge.
  - **Fix**: Handle LSR #32 explicitly, setting result to zero and C to input bit 31. Update N/Z/C while preserving V. Respect IT-block flag-update rules as part of the same decoder correction.

- [ ] **A32-9 — Medium — BUG — Interpreter memory faults bypass guest signal handlers**
  - **Where**: `src/interp/interp.c:243-268` (`a32_interp_run`).
  - **What breaks / Why**: BKPT and undefined instructions have signal-delivery paths, but `A32_EXIT_FAULT` immediately returns `139`. A guest SIGSEGV handler cannot recover from an interpreter-detected memory fault. This differs from the DBT dispatcher’s fault handling.
  - **Fix**: Route interpreter faults through the guest fault-delivery policy, preserving fault address and instruction state, and resume when the guest handler accepts delivery.

- [ ] **A32-10 — Medium — BUG — Startup silently truncates arguments and environment**
  - **Where**: `src/stack32.c:84-100` (`push_string_table`); `src/stack32.c:144-150` (`a32_stack_setup`).
  - **What breaks / Why**: Collection stops at 511 strings without reporting overflow. The resulting guest starts successfully with omitted arguments or environment entries. This silently changes application behavior even when the strings would fit in the allocated stack.
  - **Fix**: Size pointer storage from validated counts, or return an explicit argument-size error when the supported limit is exceeded. Never silently shorten either vector.

- [ ] **A32-11 — Medium — BUG — File-shrink invalidation uses file offsets as guest addresses and invalidates nothing**
  - **Where**: `src/vm/vm_file.c:248-274` (`vmfile_sync_size`); `src/vm/vm32.c:176-191` (`a32_vm32_tlb_invalidate_range`).
  - **What breaks / Why**: Shrinking an inode computes `cut` from its file size and calls `a32_vm32_tlb_invalidate_range(cut, 0U)`. The invalidator interprets that as zero pages because `end <= start`. Moreover, a file offset is not a guest mapping address. Staged private mappings therefore retain accessible stale bytes despite the comment claiming removed tails are discarded.
  - **Fix**: Track each mapping’s inode, file offset, and guest range. Translate the new EOF into affected guest pages, enforce beyond-EOF faults, and invalidate explicit valid ranges. Define endpoint representation without relying on an undocumented zero sentinel.

## 2. Curated C11 & UB Issues

- [ ] **A32-12 — High — C11 — Thumb shifts and branch arithmetic invoke undefined behavior**
  - **Where**: `src/interp/interp_thumb.c:114-121`, `src/interp/interp_thumb.c:54-56`, `src/interp/interp_thumb.c:556-560`, and `src/interp/interp_thumb.c:620-632`.
  - **What breaks / Why**: ASR with encoded zero evaluates a 32-bit shift by 32 before replacing the result. Backward short branches left-shift negative `off`; wide-branch sign extension shifts signed values into an unrepresentable result. Signed PC addition can also overflow. A later correction or cast does not undo earlier UB.
  - **Fix**: Special-case full-width shifts before evaluating them. Construct and sign-extend displacement bit patterns with unsigned arithmetic, and perform PC addition modulo `uint32_t`.

- [ ] **A32-13 — High — C11 — Interpreter exclusive-monitor state is process-global and unsynchronized**
  - **Where**: `src/interp/interp_a32.c:20-62` (`g_excl_valid`, `g_excl_addr`, `g_excl_size`, `do_ldrex`, `do_strex`).
  - **What breaks / Why**: Concurrent interpreter steps or DBT fallbacks access these ordinary static objects without synchronization. That is a C data race. Independently, one guest thread’s LDREX/STREX can overwrite or clear another thread’s local monitor bookkeeping.
  - **Fix**: Store the local reservation in `a32_ctx_t` and consume only the issuing context’s reservation. Keep shared invalidation state separately synchronized; atomic operations on the shared table do not protect these globals.

- [ ] **A32-14 — Medium — C11 — Failed fstat leaves EOF handling reading uninitialized data**
  - **Where**: `src/vm/vm_file.c:165-203` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: `struct stat st` is uninitialized. Failure of `fstat` does not stop the function, but a later zero-byte `pread` reads `st.st_size`. This consumes indeterminate data and makes the zero-fill bounds unreliable.
  - **Fix**: Return the captured `fstat` error before entering the population loop. Only use file-size fields after successful initialization.

## 3. DRY — Intra-Repo Duplication

- [ ] **A32-15 — Low — DRY — File population is implemented independently in two layers**
  - **Where**: `src/os/backend_darwin.c:125-140` (`a32_backend_map_file`); `src/vm/vm_file.c:185-214` (`a32_vmfile_populate_private`).
  - **What breaks / Why**: Both implement a `pread` loop with EINTR retry and EOF handling. Their surrounding zero-fill and backing semantics differ, increasing the chance that EOF fixes land in only one path. The Darwin implementation also obscures the MAP_SHARED defect above.
  - **Fix**: Keep a single private-file population helper inside a32rt. Backends should establish the requested backing; the VM layer should own private-copy population policy. Preserve a separate genuine shared-mapping path.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **A32-16 — Low — YAGNI — Obsolete global file hooks remain publicly declared without callers**
  - **Where**: `src/vm/vm_file.c:303-340` (`a32_vmfile_on_truncate`, `a32_vmfile_hook_write`); `src/vm/vm32.h:214-215`.
  - **What breaks / Why**: Repository searches found definitions and declarations but no callers in `src`, `tests`, or `tools`. These hooks update every tracked inode rather than a specified file, while identity-aware entry points already exist. They advertise an unsafe alternative API that is not integrated.
  - **Fix**: Remove the unused declarations and implementations, or replace a demonstrated caller with an explicitly identity-scoped API. Do not retain global mutation hooks as speculative functionality.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **A32-17 — Medium — CLEAN — Source splitting relies on forbidden textual unity includes**
  - **Where**: `src/a64_emit.c:9-11`, `src/decode_a32.c:9-10`, `src/decode_t32.c:9-11`, `src/vfp_neon.c:9-11`, `src/jit.c:9-12`, `src/aot.c:9-10`, and `src/syscalls.c:9-15`.
  - **What breaks / Why**: These wrappers textually include implementation `.c` files. The apparent file-size reduction preserves large translation units and hidden cross-file dependencies on static declarations and include order. This directly violates the audit’s no-unity-include requirement.
  - **Fix**: Compile implementation files separately. Introduce small private headers and explicit internal interfaces, and move genuinely shared state into a clearly owned module. Update `Makefile` source declarations accordingly.

- [ ] **A32-18 — Low — CLEAN — Four test sources exceed the mandatory 900-line ceiling**
  - **Where**: `tests/test_m1_isa_fs.c:901-3702`; `tests/test_m3_threads_signals.c:901-3182`; `tests/test_m4_vfp_neon.c:901-3233`; `tests/test_m5_ltp_gdb.c:901-2587` (test translation units).
  - **What breaks / Why**: Verified lengths are 3,702, 3,182, 3,233, and 2,587 lines respectively. The requirement applies to every `.c/.h/.S`, including tests. Production files also have little headroom: `src/vm.c` has 895 lines and `src/os/os_sys_sig_time.c` has 885.
  - **Fix**: Split tests by semantic area into separately compiled files with explicit registration or driver interfaces. Keep reusable fixture helpers within this repository and avoid replacing oversized files with textual `.c` includes.

**Verification limits:** These are source-based findings, not reproduced failures. The audit does not establish correctness of the remaining ISA coverage, FP exception behavior, clone/exec semantics, AOT relocation, synchronous register recovery, or concurrent code-cache reclamation. No cross-repository shared library is proposed.