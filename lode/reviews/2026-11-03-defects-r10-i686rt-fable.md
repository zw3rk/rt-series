I have all the data. Here's the complete review.

---

## Round-10 Remediation Review — Commit `3c383a3`

### I686-R10-1 — `execve` stores dead stack pointer in `ctx->exec_path`
**VERIFIED**

The fix at `src/os/syscalls.c:738` calls `strdup(path)` to heap-duplicate the stack-local `path[4096]` before it goes out of scope. The heap copy is assigned to `ctx->exec_path` at line 763 instead of the raw stack pointer. Error paths are handled correctly:
- `strdup` failure returns `-ENOMEM` after freeing `argv`/`envp` (lines 739-742)
- `rt32_elf_load` failure frees `path_copy` (line 747)
- The two post-exec readers (`src/os/proc.c:284`, `src/os/sys_pass_fs.c:284`) now dereference valid heap memory

**Note (not a new bug):** On re-exec, the previous `ctx->exec_path` (itself a `strdup` from the prior exec) leaks. This follows the audit's guidance ("do not free the old value: initial images point at process argv per main.c:366") and is consistent with the existing pattern at `src/main.c:252` which also does an unfreed `strdup`. One string per exec — bounded and benign.

---

### I686-R10-2 — `execve` in multithreaded guest leaves siblings running
**VERIFIED**

Two-part fix:

1. **Registry guard** — `i686_thread_exec_begin()` (`src/os/sys_thread.c:53-84`) is called at `r_execve` entry (`src/os/syscalls.c:663-668`). Under `s_registry_lock`, it:
   - Rejects with `-ENOSYS` if `s_registry_reserved != 0` (in-flight clones, line 61)
   - Rejects with `-ENOSYS` if any registry entry belongs to a different ctx (line 68-70)
   - Prunes the registry to the single caller (lines 76-81)

2. **Futex slot reset** — `i686_vm32_futex_reset()` (`src/vm/vm32.c:119-130`) clears all `I686_VM32_FUTEX_SLOTS` entries under `s_futex_mtx`, called from the exec success path (`src/os/syscalls.c:759-761`).

The `struct i686_thread_entry` is manually duplicated between `src/os/clone.c:90-93` and `src/os/sys_thread.c:41-44` with identical layout (`uint32_t tid`, `int host_tid`, `i686_ctx_t *ctx`). Valid C11 per §6.2.7 (compatible types across TUs), but a maintenance risk — a shared header would be safer. The five formerly-`static` symbols (`s_registry`, `s_registry_n`, `s_registry_reserved`, `s_registry_lock`, `s_main_ctx`) are now file-scope non-static in `clone.c` to support the `extern` declarations in `sys_thread.c`.

---

### I686-R10-3 — `fork`/`vfork` child inherits pending signals
**VERIFIED**

Single-line fix at `src/os/clone.c:855`:
```c
__atomic_store_n(&surviving->pending_signals, 0ULL, __ATOMIC_SEQ_CST);
```
Placed inside the `if (surviving != NULL)` block in `fork_child()`, exactly where the audit recommended. This is the `pthread_atfork` child handler, so it covers both `fork()` and `vfork()` with `CLONE_VM`. The SEQ_CST ordering matches the existing pattern for `pending_signals` access throughout the codebase. Mask and dispositions remain inherited per `signal(7)` — only the pending set is cleared.

---

### I686-R10-4 — Missing `timespec` validation on vm32 futex path
**VERIFIED**

Validation added at `src/vm/vm32.c:377-381`:
```c
if (timeout != NULL &&
    (timeout->tv_sec < 0 || timeout->tv_nsec < 0 ||
     timeout->tv_nsec >= 1000000000L)) {
    return -EINVAL;
}
```

Placed before the mutex lock, inside the shared `case 0u: /* FUTEX_WAIT */ case 9u: /* FUTEX_WAIT_BITSET */` block, so it covers both ops. The guest timespec is marshalled in `sys_futex` (`src/os/sys_pass.c:340-345`) as `{ int32_t sec; uint32_t nsec }` → `struct timespec`. Since guest `nsec` is `uint32_t`, the `tv_nsec < 0` arm is effectively dead for guest-sourced values, but `tv_nsec >= 1000000000L` catches the audit's reproduction case (`{0, 2000000000}`). The `tv_sec < 0` check is live because guest `sec` is `int32_t` and sign-extends correctly through `(time_t)`.

The Linux-A1 path (`src/os/sys_pass.c:369`) passes directly to `syscall(SYS_futex)` where the kernel validates — no translator check needed, matching the audit's "Linux-A1 is host-backed and correct."

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| File sizes | `syscalls.c`: 888, `clone.c`: 899, `vm32.c`: 461, `sys_thread.c`: 342 — all ≤ 900 |
| VLAs | None |
| `.c` includes | None |
| Banned functions (`sprintf`, `strcpy`, `strcat`) | None |
| `<threads.h>` / Annex K / `_Generic` | None (`os/threads.h` is a project header) |

### Newly Introduced Issues

No correctness bugs introduced. Two design-quality observations:

1. **Struct duplication**: `struct i686_thread_entry` is defined identically in two TUs (`clone.c:90`, `sys_thread.c:41`). A shared header would eliminate the manual synchronization risk.

2. **Exposed internals**: Five registry variables lost `static` linkage. Consider a narrow accessor API (e.g., a single `i686_thread_exec_begin` entry point in a header) rather than raw `extern` access to internal state.
