# Round-5 post-remediation verification — `sparc32rt` @ `3e219a4`

**Result: 9 of 12 items VERIFIED, 3 PARTIAL (S32-R5-4, S32-R5-9, S32-R5-12), 0 REGRESSION, 0 NOT FIXED.** Static review only. No build, test, container, or QEMU run. The commit touches 7 source files and 0 test files, so every regression test astra asked for is still missing.

| Item | Verdict | Primary evidence |
|---|---|---|
| S32-R5-1 FP doubleword alignment | VERIFIED | `src/interp/fp.c:236-240`, `:260-264`; `src/interp/interp_signal.c:716-717` |
| S32-R5-2 byte/halfword faults → SIGBUS | VERIFIED | `src/interp/interp_signal.c:694-731`, `:741-766` |
| S32-R5-3 classifier bypasses VM gate | VERIFIED | `src/interp/interp_signal.c:678-690` |
| S32-R5-4 cross-queue pending-bit consumption | PARTIAL | `src/interp/interp_signal.c:438-440`; `src/os/threads_sig.c:169`, `:188-190` |
| S32-R5-5 sigsuspend discards default-fatal | VERIFIED | `src/os/threads_sig.c:143-166`, `:191-214` |
| S32-R5-6 uninitialized handler on disposition race | VERIFIED | `src/interp/interp_signal.c:282-298`, `:457`, `:497` |
| S32-R5-7 SA_SIGINFO slots clobbered | VERIFIED | `src/interp/interp_signal.c:513-520` |
| S32-R5-8 registration order / file_size 0 | VERIFIED | `src/rt32/vm_mmap.c:89-92` |
| S32-R5-9 file records outlive mappings | PARTIAL | `src/vm/vm_file.c:63-104`, `:212-298`; `src/rt32/vm_mmap.c:137`, `:401`, `:708` |
| S32-R5-10 futex slot exhaustion | VERIFIED | `src/os/futex.c:66-77`, `:95-99` |
| S32-R5-11 difftest duplicate classifier | VERIFIED | `src/dbt/difftest.c:159-162`, `:377` |
| S32-R5-12 unused file-state machinery | PARTIAL | `src/vm/vm_file.c:1-16`, `:33-40` |

## Per-item evidence

**S32-R5-1 — VERIFIED.** The interpreter now faults LDDF and STDF on `addr & 7` before touching memory (`fp.c:236-240`, `:260-264`), setting `exit_reason = SPARC32_EXIT_FAULT` and `fault_addr = addr` exactly like the DBT helper in `emit_fpmem.c:83`. The classifier maps op3 `0x23`/`0x27` to width 8 (`interp_signal.c:716-717`), so the 4-mod-8 fault is SIGBUS in both engines. Unverified: whether the DBT emitter has an inline LDDF/STDF fast path that bypasses `sparc32_rt_fpmem`. `emit_fpmem.c` is unchanged since P13-4, so if such a path exists it predates this round.

**S32-R5-2 — VERIFIED.** The `(va & 3) → SIGBUS` shortcut is gone. `sparc32_classify_fault` decodes first and derives the required width from `sparc32_fault_req_align` (`:694-731`), then returns SIGBUS only when `va & (width-1)` is nonzero (`:765`). An unmapped byte at `page+1` (width 1) and an aligned halfword at `page+2` (width 2) are SIGSEGV. Byte, halfword, and ASI alternates are covered via raw op3 values; SWAP/LDSTUB fall through to 4 and 1 respectively, which is correct. Behavioral change worth noting: an undecodable PC now yields SIGSEGV where a sub-word-misaligned address previously yielded SIGBUS.

**S32-R5-3 — VERIFIED.** `sparc32_fault_insn_word` holds `sparc32_vm_access_enter()`/`leave()` across both the `interp_range_ok` check and the dereference (`:678-690`); it still never writes exit state. Assumption I could not confirm in budget: the gate is a nestable reader gate, since both callers (`main.c:260`, `threads.c:719`) run in the dispatch loop and may already be inside an access section.

**S32-R5-4 — PARTIAL.** Fixed: `interp_async_commit` takes `from_process` and clears the thread bit only for thread deliveries (`:438-440`); the process path in `interp_poll_async` (`:657`) and sigsuspend Phase 2 (`threads_sig.c:220`) use the new `_process` variants; Phase 1 no longer calls `sparc32_thr_claim_global` (`:169`). Not fixed: Phase 2 still skips a process-queued signal whenever any thread has the same number pending (`threads_sig.c:188-190`). It no longer *consumes* that bit, but the cross-queue deduplication astra asked to remove is still present and now disagrees with `interp_poll_async`, which dropped it under R4-6. Failure scenario: thread A holds a blocked thread-directed SIGUSR1 pending; thread B in `sigsuspend` unmasking SIGUSR1 will never deliver a process-directed SIGUSR1 until A unblocks.

**S32-R5-5 — VERIFIED.** Both loops now distinguish IGN / ignore-default (discard, `:163-165`), fatal-default (restore masks, `kill(getpid())`, `:148-155` and `:192-202`), and stop-default (return `-EINTR` with the bit left for normal polling, `:156-162` and `:203-209`). Two observations, not blockers: the sets are duplicated as `thr_sig_dfl_terminates`/`thr_sig_dfl_ignores` rather than shared with `interp_dfl_terminates`, contrary to the "share disposition handling" fix note; and the stop-default branch returns EINTR to the guest without running a handler, a spurious wakeup bounded by the next poll consuming the bit.

**S32-R5-6 — VERIFIED.** One validated `struct interp_sig_action` snapshot (`:282-298`) is taken before build and reused by commit in all three paths (`:457`, `:471`, `:497`). The commit no longer re-fetches; a failed snapshot aborts delivery with nothing partially applied. Policy for a mid-delivery disposition change: delivery is skipped and the caller keeps or clears the bit as before.

**S32-R5-7 — VERIFIED.** The compat mirrors at offsets 100/104 are written only when `act.flags & SPARC32_SA_SIGINFO` is zero (`:513-520`); the real saved PC/NPC at `0xe4`/`0xe8` are written unconditionally (`:504-509`).

**S32-R5-8 — VERIFIED.** `vm_mmap_note_file` now calls `vm_file_note_mapping` before `vm_file_note_mutation` (`vm_mmap.c:89-92`), so the fresh entry observes the fstat size on its first shrink. Equivalent to initializing at registration.

**S32-R5-9 — PARTIAL.** Implemented: `vm_file_unregister_range` with full retire, head/tail trim, and middle split (`vm_file.c:212-289`); `vm_file_reset` on exec (`:291-298`); slot recycling in `vmf_alloc` (`:66-84`); call sites for munmap (`vm_mmap.c:401`), MAP_FIXED replacement (`:137`), and exec reset (`:708`). Not done: no mremap call site exists although the file header (`vm_file.c:12`) and the function comment claim "mremap source retirement"; I could not confirm in budget whether mremap routes through `vm_munmap_locked`. Also not done: registration failure is still silent. `vmf_alloc` returns NULL on a full table (`:85-87`) and `vm_mmap_note_file` returns void, so tracking is still dropped without report. Minor: the MAP_FIXED retire at `:137` runs before the host mmap succeeds, so a failed replacement loses tracking for a mapping that still exists.

**S32-R5-10 — VERIFIED.** `futex_emu_find` records the first `in_use` slot with `waiters == 0` (`futex.c:72-75`) and recycles it when the free list is empty (`:95-99`). The caller holds `futex_emu_lock` (`:160`), and `waiters--` happens only after `pthread_cond_wait` reacquires the mutex (`:175`), so a slot can never be recycled under a waiter. The condvar is reused initialized.

**S32-R5-11 — VERIFIED.** The duplicate fetch and classifier are deleted; difftest calls the production `sparc32_classify_fault` (`difftest.c:377`). Hygiene nit: `difftest.c:162` re-declares the prototype locally although `src/interp/interp.h:37` already exports it.

**S32-R5-12 — PARTIAL.** Removed: `vm_file_promote_cow`, `vm_file_apply_shrink`, `vm_file_generation`, `vm_file_shared_direct_ok`, and the `vm_file_page_t` type; the header comment now describes a process-local table (`vm_file.c:1-16`). Remaining: `resize_seq` and `min_shrunk` (`:39-40`) are still stored in alloc, mutation, and split paths but have no reader anywhere in `src/`; and the typedef comment at `:33` still reads "Family-shared inode entry (section 5.1.3; MAP_SHARED in full impl)" above an ordinary static array.

## Hygiene, test gaps, and hand-off

**Line limits:** all seven touched files are under 900 lines. Largest is `src/interp/interp_signal.c` at 766; others are 718, 414, 335, 308, 304, 299.

**Curated C11:** no `sprintf`/`strcpy`/`strcat`/`_Generic`/`alloca`/`<threads.h>`/Annex K in the touched files. No VLA patterns found. `kill`/`getpid` are covered by the new `<unistd.h>` include in `threads_sig.c:19`. Three new file-local `extern` prototypes work around frozen headers (`vm_mmap.c:73-74`, `threads_sig.c:27-28`, `difftest.c:162`) and should move into `sparc32rt.h` / `threads.h` / an existing include at the next header unfreeze.

**Test coverage:** zero test files changed and no `R5` marker in `tests/`. Astra explicitly requested regression cases for R5-1 (`base+4` LDDF/STDF), R5-4 (simultaneous process/thread pending in sigsuspend), R5-8 (first shrink right after mmap), R5-10 (more than 64 futex addresses), and R5-11 (expected signo per fault kind). None exist.

**Recommended follow-up for the coordinator, in priority order:**
1. R5-4: drop the `sparc32_thr_thread_has_pending` skip at `threads_sig.c:188-190` or justify why sigsuspend must differ from `interp_poll_async`.
2. R5-9: wire `vm_file_unregister_range` into the mremap source path, and surface `vmf_alloc` failure from `vm_mmap_note_file`.
3. R5-12: delete `resize_seq`/`min_shrunk` or add a reader; fix the comment at `vm_file.c:33`.
4. Add the five missing regression tests above; R5-5 should share one DFL table with `interp_dfl_terminates`.
