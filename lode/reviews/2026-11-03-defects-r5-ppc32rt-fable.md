# Round-5 Post-Remediation Verification — `ppc32rt` @ `70a723d`

**Scope:** static review of commit `70a723d` ("ppc32rt: remediate Round-5 defects (P32-R5-1..11)") against `lode/reviews/2026-11-03-defects-r5-ppc32rt-astra.md`. No builds, tests, containers, or QEMU were run. Four tool turns used.

**Verdict:** 8 VERIFIED, 2 PARTIAL, 1 NOT FIXED. The commit message claims all 11 items; P32-R5-11 was not touched at all, and P32-R5-9 introduces a new per-thread leak on the real syscall path.

| Item | Status | Summary |
|---|---|---|
| P32-R5-1 | VERIFIED | CLONE_VM child now runs on a host pthread; parent returns immediately. |
| P32-R5-2 | VERIFIED | FPR/RA/nip committed only after successful access, interp and DBT. |
| P32-R5-3 | VERIFIED | `getcwd`/`getrandom` use prot check + checked copyout + landed bookkeeping. |
| P32-R5-4 | VERIFIED | iovec `(base,len)` snapshotted before I/O; post-I/O uses the snapshot. |
| P32-R5-5 | VERIFIED | One host `readv`/`writev` per guest call. |
| P32-R5-6 | VERIFIED | Landed read bytes now go through `cohere_store` (write-through). |
| P32-R5-7 | PARTIAL | Writable fd selected; writeback failure still silently discarded; no test. |
| P32-R5-8 | VERIFIED | Blocked self-signal becomes pending; pumped after signal-syscall tail. |
| P32-R5-9 | PARTIAL | Publication race fixed; but syscall-created threads are never reaped (new leak). |
| P32-R5-10 | VERIFIED | `syscalls_min.c` reduced to a delegating alias. |
| P32-R5-11 | NOT FIXED | `sig_installed` still present and still write-only. |

---

## Per-item evidence

### P32-R5-1 — `clone(CLONE_VM)` blocked the parent — **VERIFIED**
- `src/os/syscalls.c:414-420` adds `sys_clone_run`, which calls `ppc32_run_guest_child` on the child.
- `src/os/syscalls.c:778-779` passes `sys_clone_run` as the runner to `ppc32_clone` instead of `NULL`; the inline `sync_kid_record(...ppc32_run_guest_child(child))` + `ppc32_thread_exit(child)` sequence is removed (old lines 771-773).
- `src/os/threads.c:580` creates the host pthread, `thread_entry` (`threads.c:448-469`) runs the child to exit.

Residual notes (not blocking the classification):
- No parent/child handshake regression was added (astra asked for one; `tests/` untouched).
- The removed RC4 comment explicitly warned that a host-thread child "would race the interpreter's non-atomic reservation ops" for `lwarx`/`stwcx.`. That race is now live. Nothing in this commit hardens the interpreter reservation path. Flag for the thread-safety follow-up.
- `sync_kids[]` / `sync_kid_reap` (`syscalls.c:479-514`, called at `:587`) are now dead: `sync_kid_record` was deleted and nothing populates the table. New YAGNI leftover.

### P32-R5-2 — FP memory faults committed state — **VERIFIED**
- Interp: `src/interp/fp.c:78-95` (`fp_memop`) checks `ctx->exit_reason != PPC32_EXIT_NONE` after `ld32`/`fp_ld64`/`st32`/`fp_st64` and returns before writing `fpr[rt]` or advancing `nip`.
- Interp update forms: `fp.c:100-105` (`fp_lsD`) and `fp.c:118-123` (`fp_lsX`) now call `fp_memop` first and write `gpr[ra] = ea` only when `exit_reason == PPC32_EXIT_NONE`.
- DBT: `src/dbt/emit_fp.c:260-270` moves `ei_st(b, A64_ADDR, insn->ra)` after `ei_guard_low` + `fp_ldst_mem`, so a host fault on the load/store leaves RA intact.
- Nit: `interp_failed()` added at `src/interp/interp.h:312` is not used anywhere (`fp.c` open-codes the comparison). Dead helper.
- No protected-page fault test was added.

### P32-R5-3 — raw copyouts bypassed permission checks — **VERIFIED**
- `getcwd`: `src/os/syscalls_dyn.c:418-420` adds `ppc32_vm_range_prot_ok(ctx, buf_va, size, 2U)`; `:430-435` replaces raw `memcpy` with `ppc32_vm_copyout_safe` + `ppc32_smc_store` + `vm32_store_invalidate_range` + `vm_file_shared_cohere_store`.
- `getrandom`: `src/os/syscalls.c:404-420` adds the prot check, reads into a host `malloc` buffer, copies out via `ppc32_vm_copyout_safe`, and calls `sys_read_landed`.
- Nit: `syscalls.c:422-423` calls `free(host)` then `host_ret(n, errno)`; on the `n < 0` path `errno` may be clobbered by `free`. Capture `errno` before `free`.

### P32-R5-4 — `readv` re-read guest iovecs after I/O — **VERIFIED**
- `src/os/syscalls.c:205-236` allocates `bases[]`/`lens[]` and fills them in the pre-I/O loop.
- `syscalls.c:246-255` landed-bookkeeping loop uses `bases[j]`/`lens[j]` only; no `ppc32_ld32be` of guest iovec memory after `readv`.

### P32-R5-5 — chunked vectored I/O changed semantics — **VERIFIED**
- `src/os/syscalls.c:237-238` issues exactly one `writev`/`readv` with `count` entries; the `while (done < count)` loop is gone. `PPC32_IOV_MAX 1024` (`:98`) bounds the allocation.
- Nit: `PPC32_IOV_CHUNK` at `syscalls.c:97` is now unreferenced. Remove.

### P32-R5-6 — reads into staged `MAP_SHARED` did not update the file — **VERIFIED**
- `src/os/syscalls.c:120` (`sys_read_landed`) now calls `vm_file_shared_cohere_store` (write_file = true path at `vm_file_stage.c:626`) instead of `vm_file_shared_cohere_read`. All `read`/`pread64`/`readv`/`getrandom`/`getcwd` landed bytes route through it (`:144`, `:253`, `:420`, `syscalls_dyn.c:435`).

### P32-R5-7 — write-through could select a read-only fd — **PARTIAL**
Done:
- `src/vm/vm_file_stage.c:77-86` adds `stage_fd_writable` (`F_GETFL & O_ACCMODE`).
- `vm_file_stage.c:302-309` upgrades a group's retained `src_fd` to a `vm_dup_fd` of a later writable mapping's fd.
- `vm_file_stage.c:536-539` (`stage_fanout_groups`) only selects a `src_fd` that is writable.

Not done:
- Astra's "handle writeback failure explicitly": `vm_file_stage.c:554` is still `if (stage_pwrite_all(wfd, ...) == 0 && ...)` with no else branch, so a failed `pwrite` is still silently discarded.
- No mixed `O_RDONLY`/`O_RDWR` alias test was added.
- Nit: `stage_fd_writable` calls `fcntl(fd, F_GETFL)` before the `fd < 0` check (`:79-82`). Harmless (EBADF) but reorder.

### P32-R5-8 — self-directed signals ignored the blocked mask — **VERIFIED**
- `src/os/signals.c:721-727` in `ppc32_sig_kill`: if `ctx->sig_mask & sig_bit(sig)` the signal is OR'd into `ctx->pending_signals` and `kill` returns 0 without entering the handler.
- `signals.c:753-786` adds `ppc32_sig_pump_pending`, which delivers the first pending, unblocked, catchable signal via `ppc32_sig_deliver_sync`, drops IGN, and host-`raise`s DFL.
- `src/os/syscalls.c:578` calls the pump after the signal-syscall tail (post-`nip += 4`), so the frame captures the post-`sc` nip.
- Coverage note: the pump runs only after syscalls handled by `ppc32_sig_syscall` (kill/tkill/tgkill/sigprocmask/sigreturn/sigsuspend, `signals.c:839-861`). Since unmasking can only happen through those same syscalls, the pending-then-unmask case is covered. Pending signals are not pumped at other execution boundaries; acceptable for this item. No regression test added.

### P32-R5-9 — callback thread exit raced handle publication — **PARTIAL**
Done:
- `src/os/threads.c:576-590`: `thread_lock()` is held across `pthread_create` and `slot->host = host`. Since `ppc32_thread_exit` takes the same lock (`:657`), an instant child cannot clear its slot before the handle is published.
- `threads.c:655-672`: for a host-backed slot, exit now marks `exited = true` and leaves `slot`/`ctx` as a zombie; `free(child)` happens only for host-less inline slots.
- `threads.c:621-634`: `ppc32_thread_join` reaps the zombie (clears slot, frees ctx) after `pthread_join`. Double join returns `-ESRCH` (new assert at `:845-848`).
- The self-test deref at old `:790` is now safe because the ctx survives until join.

Not done / new problem:
- **Syscall-path threads are never reaped.** `sys_clone_run` → `thread_entry` → `ppc32_thread_exit` marks the slot zombie, but nothing on the guest syscall path ever calls `ppc32_thread_join` (only caller is the embedded self-test, `threads.c:829/845`; `grep` finds no other). Every `clone(CLONE_VM)` therefore leaks its `ppc32_ctx_t`, keeps its `g_thread_table` slot `used`, and leaves the joinable host pthread unjoined (no `pthread_detach` in `threads.c`). `ppc32_thread_count` (`:187-200`) counts zombies as live. A thread-churning guest exhausts `PPC32_MAX_THREADS` and then gets clone failures. Before this commit the syscall path freed the slot on exit; this is a behavioral regression introduced by the R5-1 + R5-9 combination. Fix: on the syscall path either `pthread_detach` + self-reap in `thread_entry` when no joiner exists, or reap zombies opportunistically in `thread_claim_locked`.
- `exited` (`threads.c:61`) is write-only: set at `:91,:174,:629,:669`, never read. Same class as R5-11.

### P32-R5-10 — unused minimal dispatcher duplicated behavior — **VERIFIED**
- `src/os/syscalls_min.c` shrinks to 33 lines; `ppc32_syscall_min` (`:30-33`) delegates to `ppc32_syscall`. The duplicate switch, `0x1000` guard, and unchecked buffers are gone.
- `grep` finds no caller outside the header and the file itself (the astra-cited `main.c:481` reference no longer exists).
- Nit: `src/os/syscalls.h:23` still says "syscalls_min.c itself is untouched". Stale comment.

### P32-R5-11 — `sig_installed` write-only — **NOT FIXED**
- `src/os/signals.c:48` `static int sig_installed[PPC32_NSIG + 1U];` still declared.
- `signals.c:115`, `:141`, `:162` still assign it; no reads anywhere in `src/`, `include/`, or `tests/`.
- The `signals.c` hunk in `70a723d` contains only the R5-8 change. The commit message's "P32-R5-1..11" claim is inaccurate for this item.

---

## Curated C11 & line-limit hygiene

**Line limits (touched files, all ≤ 900):**

| File | Lines |
|---|---|
| `src/os/threads.c` | 898 |
| `src/os/signals.c` | 881 |
| `src/dbt/emit_fp.c` | 852 |
| `src/os/syscalls.c` | 807 |
| `src/vm/vm_file_stage.c` | 772 |
| `src/interp/interp.h` | 738 |
| `src/interp/fp.c` | 583 |
| `src/os/syscalls_dyn.c` | 512 |
| `src/os/syscalls_min.c` | 33 |

No `.c`/`.h`/`.S` under `src/`, `include/`, `tests/` exceeds 900. `threads.c` grew from 884 to 898 and is 2 lines from the ceiling; the R5-9 reaper fix will need to land elsewhere or be paired with a split.

**C11 checks on touched files:** no `sprintf`/`strcpy`/`strcat`/`_Generic`/`<threads.h>` hits. No VLAs introduced; the vectored-I/O arrays use `malloc` (`syscalls.c:205-207`) with `<stdlib.h>` added. `stdatomic.h` + `pthread` usage unchanged.

---

## Required follow-ups (priority order)

1. **P32-R5-9 leak (regression):** reap or detach syscall-path CLONE_VM threads; zombies currently accumulate forever.
2. **P32-R5-11:** delete `sig_installed` and its three assignments.
3. **P32-R5-7:** surface `stage_pwrite_all` failure at `vm_file_stage.c:554` (log or propagate), add RO/RDWR alias test.
4. **Dead code introduced by this commit:** `sync_kids`/`sync_kid_reap` (`syscalls.c:479-514,587`), `PPC32_IOV_CHUNK` (`:97`), `interp_failed` (`interp.h:312`), `exited` field (`threads.c:61`), stale comment `syscalls.h:23`.
5. **Tests:** none of the astra-requested regressions (clone handshake, FP fault commit, RO-subpage copyout, blocked self-signal) were added; `tests/` is untouched in this commit.
6. **Thread-safety exposure:** with real concurrency now enabled (R5-1), the interpreter's non-atomic `lwarx`/`stwcx.` reservation path is racy across host threads. Track as a new item for Round 6.
