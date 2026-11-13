# Fresh-Context Adversarial Review: `docs/UNIFICATION-PLAN.md` (Rev 3)

Reviewer: `fable` (`claude-fable-5-1`). Scope: the plan audited against the pinned trees of all 11 sibling repositories. No files were modified. No prior review transcripts in `lode/reviews/` were read.

## Executive Summary

The plan's AArch64 fast path is sound. I assembled every sequence in §4.3 with `clang -arch arm64`: the swapped-destination `ldp x3, x2, [x2, #8]` is legal (Rt2 == Rn without writeback), all four `and` masks for N in {1,2,4,8} plus N=16 encode as logical immediates, no instruction in steps 1 through 6 writes NZCV, and the `~0` invalid tag can never compare equal because step 4 clears bits [11:3]. The §4.1 register table matches all four `trampoline_a64.S` files exactly.

The architecture around that fast path has four defects that make Rev 3 unshippable as written:

1. The Class-A dual-view `G + S` design (§4.4) silently breaks guest `fork()`, because every Class-A translator implements fork with host `fork()` over a `MAP_PRIVATE` window, and a `MAP_SHARED` memfd/shm backing is inherited shared, not copied.
2. Provider A's COW promotion (§5.1) relocates a 4 KiB page to a new host address without stop-the-world, so sibling threads keep reading the stale file page through their own Soft-TLB entries. CLONE_VM threads lose coherence.
3. The quiescence protocol (§4.3.4) has no mechanism to interrupt a worker spinning in chained DBT blocks, so any `mprotect` racing a guest spin-wait deadlocks the process.
4. The mixed-page `interp_step` escape hatch (§4.4.3) runs i686rt's interpreter, which treats `LOCK` as a no-op, and i686rt has no precise mid-block EIP or GPR recovery at all.

Beyond those, the plan misdescribes the current rt64 memory lowering in two of four repos, contradicts `SPEC.md` on the sparc64 page size, under-scopes Provider B against what `hyper-linux` actually has, and misclassifies MIPS64 Linux unaligned-access semantics.

## Findings

Severity legend: **Critical** blocks correctness for a real workload. **Major** blocks a wave gate or materially misstates the codebase. **Minor** is a precision or documentation defect.

### Critical

**C1. Dual-view `MAP_SHARED` backing breaks guest `fork()` in every Class-A translator (§4.4.2, plan lines 301-304).**
- Evidence: the plan allocates the 4 GiB window from `memfd_create` / `shm_open` and maps it `MAP_SHARED` twice. Today the window is a `MAP_PRIVATE | MAP_ANONYMOUS` reservation (`mips32rt/src/rt32/vm.c:391-394`, `i686rt/src/rt32/rt32_vm.c:406-409`), and guest fork is host `fork()` relying on private COW: `i686rt/src/os/clone.c:530-537` says so explicitly, and `a32rt/src/syscalls.c` and `mips32rt/src/os/proc.c` call `fork()` the same way.
- Failure scenario: on a 16 KiB host, a guest shell runs `fork()` then the child writes to its stack or heap. The parent observes the child's writes because both processes map the same memfd pages. Every `fork`+`exec` pattern corrupts the parent. The plan never mentions fork in §4.4 or §8 Mode 2.
- Fix (recommended): drop `G + S` for Class A and reuse the Class-B Soft-TLB in Class A on >4 KiB hosts. The same 7-instruction sequence works with a 32-bit `wAddr` (`ubfx` on `w1`, addend relative to `G`), the host window stays `MAP_PRIVATE` with permissions widened to the union of the sub-pages, and 4 KiB protection is enforced in software. Host `fork()` keeps working unchanged. This also eliminates C4 and M3.
- Fix (if `G + S` is retained): define a fork protocol in §4.4: the child creates a fresh backing object, copies every mapped 4 KiB page recorded in `vma_page_prot`, remaps `G` and `S` with `MAP_FIXED` before resuming guest code, and the parent blocks until the child signals completion. State the cost (full RSS copy per fork) in §8.

**C2. Relocating COW promotion without quiescence breaks cross-thread coherence and futex wakeups (§5.1.2, plan line 330; §4.3.3 Case 1, line 263).**
- Evidence: the plan copies a clean `MAP_PRIVATE` page "into a dedicated private anonymous 4 KiB slot" inside `.L_tlb_miss_site_k` and only updates the promoting thread's `write_tag`. Step 3 of §4.3.4 (line 285) is the only place that flushes sibling TLBs, and promotion is not listed as a §4.3.4 transaction. The Linux backend futex API takes `host_uaddr` (plan lines 512-520).
- Failure scenario 1: thread B stores to `libc.so` `.data` (a clean private file page at host `H1`). The miss helper copies the page to `H2` and B continues at `H2`. Thread C already has `read_tag` valid with `addend` pointing at `H1`. C reads stale data from the file page forever. This affects every static mutex and `errno`-adjacent global in a dynamically linked guest.
- Failure scenario 2: thread A does `FUTEX_WAIT` on a word in that page (host `H1`). B's first store promotes to `H2`, then B issues `FUTEX_WAKE`, which the backend performs on `H2`. A never wakes.
- Fix: never relocate a page in place of the thread that touched it. On 4 KiB hosts, let the host kernel's `MAP_PRIVATE` COW do promotion in place and track dirtiness with a write-protect trap on the first store (no address change). On 16/64 KiB hosts, eagerly copy `MAP_PRIVATE` file pages into anonymous backing at `mmap` time (every page is dirty from the start) and document in §8 that clean-page `SIGBUS` on truncate is not reproduced for private mappings on those hosts. If relocation is kept anyway, promotion must be a §4.3.4 transaction batched per host page, and every futex op must promote before computing `host_uaddr`.

**C3. Stop-the-world quiescence cannot interrupt a worker in chained DBT code (§4.3.4 Step 2, plan line 281).**
- Evidence: Step 2 sets `peer->yield_requested` and waits. The plan lists the only park points as the miss stub, `interp_step`, and lease entry. The rt64 dispatchers chain blocks directly (`mips64rt/src/dbt/dbt.h:7-10`, `sparc64rt/src/dbt/trampoline_a64.S` x27/x28 epoch chaining); nothing in any emitter polls a flag. The rvrt JIT only has a translation budget check (`rvrt/src/jit/a64.c:610`), not a runtime preemption point.
- Failure scenario: thread A spins on a flag with TLB hits only (`while (!ready) ;`), waiting for thread B. B calls `mprotect` (a GC or JIT in the guest), enters Step 1, and waits for A to park. A never reaches a park point. The whole process hangs.
- Fix: preempt with a reserved host RT signal (`tgkill`) to each running worker. The handler runs on the per-worker altstack, inspects the interrupted PC, and parks if the PC is inside the code cache. Because steps 1 through 6 have no side effects, add `seq_start_offset` to `dbt_mem_site_t` so the handler can rewind a PC that falls between `ubfx` and instruction 7 to the sequence start; otherwise a stale `addend` already loaded into `x3` would be used after resume. Guest state is memory-resident in all rt64 emitters (`mips64rt/src/dbt/dbt.h:16-21`, `loongarch64rt/src/dbt/emit_int.c:6-7`), so parking at an arbitrary host instruction is otherwise safe.

**C4. The mixed-page `interp_step` escape hatch is not atomic and has no precise-state foundation in i686rt (§4.4.3, plan lines 310-313).**
- Evidence: i686rt's interpreter documents `LOCK` as a no-op (`i686rt/src/interp/h_alu.c:12`, `:458`, `h_shift.c:37`). i686rt's host fault handler ignores the ucontext and longjmps (`i686rt/src/interp/interp.c:36-57`), and the DBT fault path reuses the stale block-entry `ctx->eip` without syncing `w0..w7` (`i686rt/src/dbt/engine.c:425-440`, `emit.h:7-12`). Only a32rt has a host-PC side table plus register sync (`a32rt/src/signals.c:380-395`).
- Failure scenario: a glibc mutex word sits in a 4 KiB RW page whose 16 KiB host page is narrowed to `PROT_READ` by an adjacent RELRO page. Thread A's DBT `lock cmpxchg` traps and is re-executed by `interp_step` as a plain read-modify-write through `S`. Thread B's DBT executes `ldaxr/stlxr` on `G` at the same time. The lock is acquired twice.
- Fix: adopt the C1 recommendation (Soft-TLB in Class A on >4 KiB hosts) so no DBT access ever traps on a mixed page. If the trap path is retained, Wave U3 must first add to i686rt a host-PC to `(eip, lazy-flag state)` side table with ucontext GPR sync, and implement all `LOCK`-prefixed operations with `__atomic` builtins in the interpreter. Both are prerequisites, not follow-ups.

### Major

**M1. The plan misstates the current rt64 memory lowering (plan line 22 and §3 line 149).**
- Evidence: only `mips64rt` has an `emit_mem.c`, and it already inlines `[x20 + va]` with a `task_size` bounds check and a per-op `str pc, [ctx, #scratch]` precise-PC record (`mips64rt/src/dbt/emit_mem.c:69-98`). `loongarch64rt` does not lower loads, stores, or atomics at all; every one exits to `interp_step` (`loongarch64rt/src/dbt/emit_int.c:777-800`). Only `sparc64rt` (`src/dbt/emit_rt.c:23`) and `ppc64rt` (`src/dbt/emit_int.c:732`) call a helper.
- Impact: the U0 prototype gate on `loongarch64rt` starts from zero memory lowering, which is fine but is not an "upgrade". For `mips64rt`, Wave U2 must explicitly replace the `ctx->scratch` PC-record mechanism with `dbt_mem_site_t` and delete the per-op store, or the two schemes coexist and the bounds-check branches double the sequence length.
- Fix: correct the two sentences, and add a per-repo "current lowering" column to the §4.1 table.

**M2. The per-page `addend` model silently abandons the linear `guest_base + va` window every Class-B syscall and loader path depends on (§4.3.1, §5.1.1).**
- Evidence: `mips64rt/src/core/cpu.h:166-172` reserves `task_size` (1 TiB for N64) as one host range and `mips64_guest_ptr()` is `guest_base + va` (`cpu.h:311`); `mips64rt/src/os/mem.c:7-12` and the LL/SC lowering in `emit_mem.c` compute host addresses the same way. Host-page-biased file mapping (plan line 325) requires guest VA and host VA to diverge per 4 KiB page, which makes every contiguous `guest_ptr()` buffer non-contiguous across page boundaries.
- Failure scenario: a guest `read()` into a 12 KiB buffer that spans a biased file page and an anonymous page is handed to the host as one pointer and writes into the wrong host pages.
- Fix: decide explicitly. Recommended: keep the linear window (addend is constant `guest_base` for every page) and support 4 KiB-granular file mappings on >4 KiB hosts only when `(gva ^ file_off) & (H-1) == 0` and the mapping covers whole host pages; otherwise fall back to copy semantics via `pread`. If the scatter model is chosen instead, §6 needs `vm64_copyin`/`vm64_copyout` iterating 4 KiB pages, and every `rt_host_read`-style call must take a bounce buffer, which the plan currently only requires for blocking calls.

**M3. Intersection protection guarantees a trap storm on 16 KiB hosts for every dynamically linked guest (§4.4.1, plan lines 295-300).**
- Evidence: with glibc and musl layouts, the RELRO/GOT page (read-only after relocation) is immediately followed by `.data`, so the 16 KiB host page straddling them is narrowed to `PROT_READ`. Every store to the first up to 12 KiB of `.data` takes a host signal plus `interp_step`. The plan defers measurement to U3 (line 314).
- Fix: measure in the U0 prototype gate, not U3, and define the fallback now. The Soft-TLB-in-Class-A path from C1 removes the problem entirely. If intersection is kept, specify per-site retranslation after N traps.

**M4. Quiescence protocol deadlocks under concurrent mutators and signals (§4.3.4).**
- Scenario A: worker A holds `g_vm_mutation_lock` and waits for all peers to park. Worker B calls `mprotect`, blocks on the same lock while still in `RT_WORKER_RUNNING`. A waits for B forever.
- Scenario B: an async guest signal lands on the mutator thread during Step 3. If the handler builds a sigframe (which needs a lease), lease entry sees `g_vm_mutating` and parks the mutator on itself.
- Scenario C: `lease_active = 1; if (g_vm_mutating)` on the worker and `g_vm_mutating = 1; wait lease_active == 0` on the mutator is a Dekker pattern; with the plan's plain atomic stores both sides can read stale values.
- Fix: acquire the mutation lock only from `RT_WORKER_PARKED`; host signal handlers only bump `sig_seq` and set a pending bit, with sigframes built at the next safe point; add `atomic_thread_fence(memory_order_seq_cst)` after the store on both sides and say so in the text.

**M5. §4.3.3 Case 2 misclassifies MIPS64 Linux unaligned semantics, and `mips64rt` currently gets it wrong twice.**
- Evidence: the Linux MIPS kernel sets `TIF_FIXADE` in `INIT_THREAD_INFO` and `do_ade` emulates unaligned integer loads and stores silently by default; only `sysmips(MIPS_FIXADE, 0)` or `/proc/sys/debug/unaligned` changes that. `mips64rt` raises a fault on any misaligned 16/32/64-bit access (`mips64rt/src/os/mem.c:17-19`, `src/interp/unaligned.c:406-407`) and delivers it as signal 11 via `mips_fault` (`mem.c:55`), whereas the kernel would deliver `SIGBUS` with `BUS_ADRALN` if it signalled at all.
- Fix: in Case 2, `mips64rt` emulates by default (both pages validated, byte-wise merge), gated on a per-process fixade flag; sparc64rt keeps `SIGBUS`. Add an unaligned fixture to the U0/U2 torture suite and fix the signal number.

**M6. Provider B is described as an extension of machinery `hyper-linux` does not have (§5.2).**
- Evidence: hl implements file-backed `MAP_SHARED` as a slab snapshot with `MAP_PRIVATE` semantics outside Android and RVRT (`hyper-linux/src/syscall.c:2241-2247`). `guest_region_t` carries `backing_dev/ino/size` only for Android alias views (`src/guest.h:359-386`). There is no `PTE_COW_CLEAN` concept; the Stage-1 tables express permissions only. The TLBI mailbox is a single word consumed at the next trap of some vCPU (`src/syscall.c:5286-5296`, `src/shim.S:110,172`), and `fork_ipc.c:1620-1623` says multi-vCPU fork capture is unfinished.
- Impact: U4 scope omits the largest piece, a per-4 KiB-page file identity table for all file mappings, a real host-file mapping path for non-RVRT guests, and a vCPU kick (`hv_vcpus_exit`) so a VM with all vCPUs in guest mode observes a sibling's truncate before its next trap.
- Fix: list those three items in the U4 scope and the `RC-U4` gate; refresh the `be7721f` pin at U4 start (HEAD is `5c72284` with 176 dirty files from the live session).

**M7. Per-site miss stubs as specified multiply code size by roughly six per memory operation (§4.3.3, plan line 262).**
- Evidence: saving `x0..x17`, `x30`, and NZCV, calling, restoring, and branching back is about 45 instructions per site. `MIPS64_DBT_STAGING_WORDS` is 4096 words per block (`mips64rt/src/dbt/dbt.h:44`). Guest state is memory-resident in every rt64 emitter, so most of that save set is dead.
- Fix: a 2-instruction per-site stub (`adr x4, site_k; b block_miss_common`) and one shared per-block trampoline. The site record carries the continuation offset. Save only the emitter's declared scratch set plus NZCV (sparc64rt keeps guest CCR in host NZCV: `sparc64rt/src/dbt/emit_priv.h:737-757`).

**M8. `sparc64rt` page size: the plan contradicts both the code and `SPEC.md` (§4.2, plan line 177).**
- Evidence: `sparc64rt/src/os/guest_run_priv.h:39` defines `GUEST_PAGE_SIZE` as 4096 (the mapping granule) and line 43 defines `GUEST_AT_PAGESZ_VALUE` as 8192; there is no `SPARC64_PAGE_SIZE`. `rt-series/SPEC.md:92` (D11) says all translators report `AT_PAGESZ = 4096`.
- Fix: amend D11 in `SPEC.md` to carve out sparc64, and add to the U2 sparc64 scope the behavioral change from a 4 KiB to an 8 KiB `mmap`/`mprotect`/`mremap` granule, including `EINVAL` on 4 KiB-only alignment and the ELF loader's `p_align` handling.

**M9. Class-A file mappings on 16 KiB hosts are undefined, and the naive mapping forks `MAP_PRIVATE` into two divergent copies (§4.4).**
- Evidence: the window is fixed at `G + gva`, so a file mapping whose `(gva - off) & 0x3fff != 0` cannot be a host mapping at all. Mapping a file `MAP_PRIVATE` into both `G` and `S` creates two independent COW objects; a `read()` through `S` lands in S's private copy while DBT loads through `G` see the pristine file bytes. A host file mapping also drags 12 KiB of neighbouring file bytes over foreign guest pages. Current rt32 passes file mappings straight through (`mips32rt/src/rt32/vm_mmap.c:36-39,75`).
- Fix: on >4 KiB hosts, Class A implements `MAP_PRIVATE` files by `pread` into the shared backing (coherent in both views, and host `fork()` COW still applies after C1 is fixed), and `MAP_SHARED` only when host-page-compatible and whole-host-page covered, else `EOPNOTSUPP`, which is what hl does today (`hyper-linux/src/syscall.c:2291-2314`).

**M10. The Darwin blocking-syscall gate has the lost-wakeup race it claims to resolve (§6 item 4, plan lines 409-410).**
- Evidence: `rvrt`'s window is race-free because the handler rewrites the PC between `ldar` and `svc` (`rvrt/src/runtime/safe_syscall_a64.S:17-25`). Calling into `libSystem` via `blr` offers no such window, and a token pipe cannot interrupt a `read()` already blocked on a pipe or tty.
- Fix: specify per call class: `poll`/`kevent` on `{fd, wake_pipe}` followed by a non-blocking op for fd I/O, `__ulock_wait` for futex (wakeable), `kqueue EVFILT_PROC` for `wait4`, and `kevent` timeouts for `nanosleep`. Any `sig_seq` change between the check and the `kevent` call is covered because the wake pipe is in the set.

### Minor

- **m1.** The BE store note at plan line 226 says "rev into x4 after step 5", but `x4` is live until the `cbnz` in step 6. The table at line 241 is right ("after cbnz"). Make the listing say "after instruction 6".
- **m2.** N in {1,2,4,8} omits 16-byte and vector accesses (SPARC `ldq/stq`, PPC64 `lq/stq` and VSX, LSX/LASX, MSA). The N=16 mask `0xfffffffffffff00f` assembles; either add it or state those go to the slow path.
- **m3.** `rt64_tlb_entry_t.pad` is called a generation witness but nothing reads it. Either compare it in the miss path or label it reserved.
- **m4.** External truncation by an unrelated process is invisible to the in-process inode table on native 16 KiB Linux. Have the miss path `fstat` when the recorded state is past-EOF, and document the residual window in §8.
- **m5.** Step 3 flushes 128 KiB per thread on every `mprotect`. For small ranges, flush only the affected index range.
- **m6.** `a32rt/src/elf32.c:588` maps the kuser helper guest page `PROT_READ | PROT_EXEC` on the host, violating the series W^X invariant. Add it to the `U3-a32` scope.
- **m7.** `SPEC.md:155` already names the dispatch header `src/translator.h`; U4 (plan line 648) says `src/translator_dispatch.[ch]`. Pick one.
- **m8.** The user's audit scope lists `hyper-linux/src/memory.c`; no such file exists. The relevant code is in `guest.c`, `syscall.c`, `rvrt_shared.c`, and `fork_ipc.c`, which the plan cites correctly.
- **m9.** All other cited hl lines check out: `syscall_fs.c:5749` EBUSY, `syscall.c:2291-2314` EOPNOTSUPP, `syscall_io.c:1611` already bounce-buffers and requires a writable Stage-1 mapping (so the B8 funnel has an obvious hook), `syscall_net.c:1931`, `guest.h:80`, `hl_posix_acl.h:18`, `rvrt_shared.c:94`, `loongarch64rt/src/dbt/dbt.c:146-189`, `ppc64rt/src/main.c:99`, `sparc64rt/src/main.c:17`, and the three rt64 Makefile link lists.

## Verified Correct and Rev 4 Checklist

Verified without issue: §4.3 encodings and NZCV neutrality (assembled), §4.1 register conventions for all seven DBTs, the `ppc64rt` caller-saved `x0 = cpu` hazard, the `sparc64rt` live `src/rt64/` closure, `rvrt/src/linux/futex_key.c` existence, and `rvrt/docs/SUPPORT.md:18` RV32 status.

Rev 4 must, in priority order:

1. Decide the Class-A >4 KiB-host model (recommendation: Soft-TLB, not `G + S`), and define fork either way (C1, C4, M3, M9).
2. Make COW promotion non-relocating or stop-the-world, and promote on futex (C2).
3. Add signal-based worker preemption with sequence rewind (C3) and fix the lock ordering, handler discipline, and fences (M4).
4. Correct the rt64 lowering narrative and choose linear-window vs scatter addend explicitly (M1, M2).
5. Fix MIPS unaligned semantics, the sparc64 page-size contradiction, and the Provider B scope (M5, M6, M8).
6. Shrink the miss stub and specify the Darwin blocking-call protocol (M7, M10).
