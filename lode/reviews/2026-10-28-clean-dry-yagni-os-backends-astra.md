The audit found live memory-safety, ABI, signal, and syscall defects, plus substantial duplicated and unused backend code.

The literal filename scope contains **78 files and 36,255 lines; none exceeds 1,000 lines**. Several repositories achieve that through textual `.c` inclusion, leaving large coupled implementations. I followed the active syscall/signal implementations outside those globs where necessary.

All ten working trees remained clean. This was a **static source audit** with caller/build-wiring checks; no builds, guest regressions, or sanitizer tests were run.

**P1 — Address these behavior defects first.**

- [ ] **PPC64: replace predictable production `getrandom`.**  
  [syscalls_misc.c:80](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:80) initializes a fixed seed; [the active implementation:157](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:157) generates xorshift bytes and ignores flags. [syscalls.c:630](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls.c:630) dispatches ordinary guest calls here. Use host entropy, with deterministic input explicitly confined to differential tests. Verify flags, partial results, failure handling, and independent executions.

- [ ] **i686: fix the empty-argv script heap overflow.**  
  [syscalls.c:557](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:557) allocates `argc + 3` pointers. For `execve(script, NULL, envp)` with a shebang argument, it writes interpreter, argument, script, and terminating NULL: four pointers into three slots. Compute the final argument count before allocating and return that count explicitly. Add a sanitizer regression for this case.

- [ ] **i686: make exec preparation transactional and give the executable path owned storage.**  
  [syscalls.c:662](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:662) destroys the current mappings before ELF loading can fail. Returning `-ENOEXEC` then resumes a destroyed image. Separately, [line 675](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:675) stores automatic `path[4096]` in `ctx->exec_path`; later `/proc/self/exe` handling dereferences expired stack storage. Prepare the image, stack, and owned metadata before commitment. Test malformed ELF rollback and successful exec followed by `/proc/self/exe` access.

- [ ] **i686: use symmetric x87 signal-frame packing and unpacking.**  
  Delivery correctly packs eight 10-byte registers at [signals_i386.c:142](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:142). Restoration at [line 372](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:372) bulk-copies 128 bytes from the 80-byte packed bank into eight 16-byte slots, mixing registers and adjacent fields. Introduce explicit codec helpers and test all eight registers through signal delivery/return.

- [ ] **PPC32 and SPARC32: replace address-range checks with checked guest-memory access.**  
  [PPC32 signals.c:76](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:76) checks numeric bounds, but [line 565](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/signals.c:565) directly reads the guest action outside the engine’s fault guard. [SPARC32 syscalls.c:106](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls.c:106) similarly dereferences pathname memory; [l2a_access.h:68](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/l2a_access.h:68) performs unchecked copyout. In-range unmapped/protected addresses can fault the translator instead of returning `EFAULT`. Centralize mapping-, permission-, and COW-aware copyin/copyout/string helpers. Test cross-page and read-only buffers.

- [ ] **PPC32: preserve the successful `readv` result during invalidation.**  
  [syscalls.c:198](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:198) subtracts bytes from `total` while invalidating translated code, then returns the depleted counter at line 216. Successful reads ordinarily report zero after modifying memory. Keep the result immutable and use a separate remaining-byte counter. Cover partial reads and transfers spanning multiple iovec batches.

- [ ] **a32: introduce explicit Darwin-to-guest signal and structure codecs.**  
  [signals.c:674](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:674) interprets Linux mask operations using Darwin `SIG_*` constants. [Line 644](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:644) installs unconverted guest signal numbers, while [line 373](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:373) treats incoming host numbers as guest numbers. Also, [os_sys_thread_sig.c:541](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_thread_sig.c:541) copies native `struct utsname`: **1,280 bytes on Darwin versus the guest’s 390-byte Linux layout**. Use fixed guest layouts and explicit conversions; test signal-number mapping, all mask operations, and canaries around `uname` output.

- [ ] **LoongArch64: route actual Darwin syscalls through the correct conversions.**  
  [syscalls_file.c:29](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_file.c:29) produces AArch64 Linux numeric open flags, then [line 135](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_file.c:135) passes them to Darwin libc. The Darwin converter already exists at [backend_darwin_priv.h:41](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_darwin_priv.h:41). Signal forwarding also assigns host numbers directly to `linux_si_signo` at [backend_darwin_sync.c:534](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_darwin_sync.c:534). Establish one conversion boundary and exercise create/truncate flags and SIGCHLD delivery on Darwin.

- [ ] **MIPS32 and SPARC32: make each thread’s signal mask authoritative.**  
  [MIPS32 signals.c:127](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:127) keeps blocked masks, frame pointers, and nesting depth globally despite real pthread workers. [SPARC32 syscalls.c:83](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls.c:83) maintains a global blocked mask in addition to context masks; [threads.c:173](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/threads.c:173) combines them during delivery. One thread can block another’s signals; MIPS32 also shares handler-return bookkeeping. Move thread-owned state into the worker context and test simultaneous handlers with opposing masks.

- [ ] **LoongArch64: make asynchronous signal capture C-safe.**  
  The host callback at [signal_core.c:69](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/signal_core.c:69) reaches [sigframe.c:607](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:607), which reads ordinary shared dispositions and modifies a non-atomic pending mask. Normal execution clears that mask at [line 305](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/sigframe.c:305). Use signal-safe capture storage and defer guest-state mutation; ordinary read/modify/write operations permit lost updates and violate signal-handler access rules.

- [ ] **i686: correct Darwin futex wait/wake/requeue semantics.**  
  [backend_darwin_net.c:507](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:507) discards wait bitsets. [Line 573](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:573) ignores wake bitsets, turns nonpositive counts into wake-all, and returns zero. [Line 594](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin_net.c:594) ignores requeue destination/count/comparison. Implement explicit supported semantics or return an unsupported error. Distinguishing tests: zero/one wake, disjoint bitsets, immediate timeout, and failed comparison.

- [ ] **LoongArch64: preserve nonblocking I/O behavior.**  
  [backend_darwin_fs.c:43](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_darwin_fs.c:43) waits indefinitely before attempting I/O even when the descriptor already has `O_NONBLOCK`. Lines 46–52 then modify shared open-file-description flags and restore a potentially stale snapshot. Attempt nonblocking I/O first; wait/retry only for logically blocking calls, with coordinated flag ownership. Test empty nonblocking pipes, competing readers, and duplicated descriptors.

- [ ] **MIPS64 and SPARC64: give backend registries explicit lifetimes.**  
  [MIPS64 backend_linux.c:82](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_linux.c:82) and [backend_darwin.c:85](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_darwin.c:85) permanently consume sixteen context slots; thread destruction does not release them. Address reuse can inherit stale state, and exhaustion yields unchecked missing TLB state.  
  [SPARC64 backend_darwin.c:183](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_darwin.c:183) appends duplicate worker IDs on every registration, including [every mutation preparation](/Users/angerman/Projects/zw3rk/sparc64rt/src/vm/vm64.c:752), filling its 256-slot table. Add idempotent registration, removal/reset, explicit exhaustion errors, and safe initialization. Test repeated registrations and sequential worker lifetimes beyond capacity.

- [ ] **rvrt: honor the signal dispatcher’s waiting result in the Darwin/fast-Linux runner.**  
  [linux/signal.c:695](/Users/angerman/Projects/zw3rk/rvrt/src/linux/signal.c:695) returns `waiting=true` for `rt_sigsuspend`. [darwin_main.c:193](/Users/angerman/Projects/zw3rk/rvrt/src/darwin_main.c:193) ignores it, advances PC, and returns `EINTR` immediately; without a pending signal, delivery leaves the temporary mask installed. The full runner handles waiting at [runtime_main.c:6366](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:6366). Share the completion policy and add a no-pending-signal suspend regression.

**P2 — Consolidate semantics and remove misleading implementations.**

- [ ] **Use one complete host-to-guest errno codec per repository.**  
  Incomplete mappings occur at [MIPS32 syscalls.c:80](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:80), [MIPS64 syscalls.c:100](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:100), [SPARC32 syscalls_min.c:135](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/syscalls_min.c:135), and [SPARC64 syscalls_min.c:144](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:144). SPARC64 repeats the problem in [syscalls_sig.c:76](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_sig.c:76). For example, SPARC requires `ENAMETOOLONG=63`, `ELOOP=62`, `EOVERFLOW=92`; MIPS requires `ENAMETOOLONG=78`, `EOVERFLOW=79`. Verify against the [SPARC](https://raw.githubusercontent.com/torvalds/linux/master/arch/sparc/include/uapi/asm/errno.h) and [MIPS UAPI headers](https://raw.githubusercontent.com/torvalds/linux/master/arch/mips/include/uapi/asm/errno.h). Raw Darwin errno also leaks through [a32 os_sys_path.c:43](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_path.c:43) and [i686 syscalls.c:73](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:73).

- [ ] **Normalize direct-error APIs separately from `-1/errno` APIs.**  
  [MIPS64 syscalls_time.c:113](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls_time.c:113) receives `clock_nanosleep`’s positive error but substitutes stale `errno` at line 125. Failure can become success. [PPC64 syscalls_misc.c:47](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_misc.c:47) also lacks `EINTR`, so an explicit interrupted-pwrite path becomes `EIO`. Add injected-error tests with stale and zero `errno`.

- [ ] **Preserve MIPS32 signal inheritance across exec.**  
  [signals.c:857](/Users/angerman/Projects/zw3rk/mips32rt/src/os/signals.c:857) resets ignored dispositions and clears the blocked mask. Preserve both; reset caught handlers and transient frame/altstack state appropriately.

- [ ] **Preserve LoongArch64 directory enumeration state.**  
  [syscalls_file.c:177](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls_file.c:177) creates a fresh `DIR*` each call, consumes an entry before checking whether it fits, then closes the stream at line 226. Unreturned and buffered entries are lost through the shared directory offset. Keep per-description cursor/buffering state and test repeated small-buffer calls.

- [ ] **Replace fabricated LoongArch64 `statfs` success.**  
  [syscalls.c:530](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls.c:530) writes 120 zero bytes and returns success without querying a filesystem. Implement the guest codec or return an explicit unsupported result.

**P2 — Refactor actual coupling and duplication.**

The strongest size problems are hidden implementation units and large functions:

| Location | Finding and recommended boundary |
|---|---|
| [a32rt/src/syscalls.c:9](/Users/angerman/Projects/zw3rk/a32rt/src/syscalls.c:9) | Includes seven `.c` fragments totaling **4,713 lines**. The switch beginning at [os_sys_thread_sig.c:226](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_thread_sig.c:226) spans four files, approximately **2,770 lines and 228 cases**. Compile subsystem handlers separately. |
| [loongarch64rt/src/os/syscalls.c:41](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/syscalls.c:41) | Nested `.c` inclusions assemble roughly **4,390 lines** of syscall, signal, clone, process, and scheduler implementation. Replace textual inclusion with narrow private interfaces. |
| [mips64rt/src/os/syscalls.c:36](/Users/angerman/Projects/zw3rk/mips64rt/src/os/syscalls.c:36) | Includes the 471-line `proc.c`; the nominally 893-line syscall file represents roughly **1,364 lines** before headers. Compile process handling separately. |
| [rvrt/src/runtime_main.c:5218](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5218) | `run_worker` occupies approximately **1,520 lines** within an **8,201-line** file. Extract syscall completion and dispatch policy while preserving scheduler/ownership ordering. |
| [rvrt/src/runtime/native_signal.c:297](/Users/angerman/Projects/zw3rk/rvrt/src/runtime/native_signal.c:297) | **1,892-line** file mixes capture, process ownership, worker lifecycle, fork, and exec transitions. Separate those responsibilities. |
| [rvrt/src/linux/file.c:618](/Users/angerman/Projects/zw3rk/rvrt/src/linux/file.c:618) | **1,531-line** file includes a **417-line** transfer function. Separate staging/ownership, operation execution, and completion; `linux/fd.c` is also **1,338 lines**. |

Concrete Linux/Darwin duplication worth consolidating **within each repository**:

| Repository | Exact starting references | Common responsibility |
|---|---|---|
| a32rt | [Linux:196](/Users/angerman/Projects/zw3rk/a32rt/src/os/backend_linux.c:196), [Darwin:284](/Users/angerman/Projects/zw3rk/a32rt/src/os/backend_darwin.c:284) | Wake-pipe initialization, destruction, notification |
| i686rt | [Linux:267](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_linux.c:267), [Darwin:310](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin.c:310) | Altstack and worker-allocation lifecycle |
| mips32rt | [Linux:332](/Users/angerman/Projects/zw3rk/mips32rt/src/os/backend_linux.c:332), [Darwin:322](/Users/angerman/Projects/zw3rk/mips32rt/src/os/backend_darwin.c:322) | 94-line descriptor-wrapper block |
| ppc32rt | [Linux:573](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/backend_linux.c:573), [Darwin:769](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/backend_darwin.c:769) | 47-line worker-spawn implementation |
| rvrt | [Linux:201](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:201), [Darwin:281](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:281) | Worker cleanup and notification |
| loongarch64rt | [Linux sync:292](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_linux_sync.c:292), [Darwin sync:314](/Users/angerman/Projects/zw3rk/loongarch64rt/src/os/backend_darwin_sync.c:314) | Altstack, trampoline, and worker ownership |
| ppc64rt | [Linux:217](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_linux.c:217), [Darwin:223](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/backend_darwin.c:223) | 58-line memory-advice block |
| mips64rt | [Linux:115](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_linux.c:115), [Darwin:118](/Users/angerman/Projects/zw3rk/mips64rt/src/os/backend_darwin.c:118) | **222 identical lines** of fixade, delay-target, and TLB logic |
| sparc64rt | [Linux:633](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_linux.c:633), [Darwin:773](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_darwin.c:773) | Worker-spawn lifecycle |

SPARC32’s first cleanup target is its **orphan Darwin API variant**, beginning at [backend_darwin.c:62](/Users/angerman/Projects/zw3rk/sparc32rt/src/os/backend_darwin.c:62), rather than mechanically merging backend functions. Keep platform-specific ABI conversion, JIT publication, and memory operations explicit. Preserve the standalone-repository invariant.

- [ ] **Resolve unused API surfaces before investing in them.** Repo-wide source/test searches found no consumers of MIPS32’s backend `mips32_host_*` API or PPC32’s `rt_host_*` API, although their Makefiles link the files. PPC32’s [syscalls_min.c:161](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls_min.c:161) is also unreferenced. a32, i686, rvrt, SPARC32, and SPARC64 retain additional unconsumed worker/I/O shims. Reconcile required contracts, remove obsolete internal implementations, and isolate future interfaces with explicit qualification requirements.

- [ ] **Treat defects in those shims as latent, not current guest failures.** Examples include stale-`errno` handling after `pthread_create` in [rvrt Linux:275](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:275) and [Darwin:352](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:352), reversed Linux `MS_ASYNC`/`MS_INVALIDATE` translation at [rvrt Darwin:183](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_darwin.c:183), and unsafe dormant worker-start handoff at [SPARC64 Linux:628](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/backend_linux.c:628). Qualify them before wiring them into production.

**P2/P3 — Finish the concrete Curated-C11 work.**

- [ ] **Remove signed-shift UB:** [PPC32 syscalls.c:270](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:270) and [line 712](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/syscalls.c:712) left-shift negative signed high halves when assembling offsets. Assemble unsigned bits and convert deliberately. [rvrt backend_linux.c:77](/Users/angerman/Projects/zw3rk/rvrt/src/os/backend_linux.c:77) can also overflow signed `off_t` multiplication for offsets above `INT64_MAX`; validate representability before conversion.

- [ ] **Remove unaligned/effective-type reads:** [i686 signals_i386.c:282](/Users/angerman/Projects/zw3rk/i686rt/src/os/signals_i386.c:282) reads a byte array through `uint32_t *` casts in the trace path. Use explicit endian loads or `memcpy` into aligned locals.

- [ ] **Replace the banned `strcpy`:** [i686 syscalls.c:495](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:495). Its preceding length check bounds the current copy; this is a style violation, not a demonstrated overflow.

- [ ] **Check formatting results:** [a32 os_sys_sig_time.c:706](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sig_time.c:706) silently truncates generated environment values; [i686 backend_darwin.c:120](/Users/angerman/Projects/zw3rk/i686rt/src/os/backend_darwin.c:120) ignores shared-memory-name truncation. Check negative returns and `n >= capacity`.

- [ ] **Validate retained output-pointer contracts:** the unused PPC32 Linux shared-memory fast path dereferences `out_host_fd` without validation at [backend_linux.c:135](/Users/angerman/Projects/zw3rk/ppc32rt/src/os/backend_linux.c:135). Validate once at the API boundary. Inspected allocation sites generally checked allocation failure; the stronger active problems were allocation-size arithmetic, lifetime, and guest-memory validation.

Verification used `git status --short`, `git rev-parse`, `wc -l`, `rg` caller/build searches, numbered source inspection, backend comparisons, and local Darwin SDK definitions. The proposed regression cases above remain unexecuted; this audit does not establish runtime or release qualification.