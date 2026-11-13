Found **11 remaining issues** at confirmed HEAD `0e879ac`. Used exactly **7 shell invocations**; no Markdown reads, builds, tests, Docker, or QEMU. Findings are based on static inspection. Novelty was checked against available Round-1–5 commit descriptions and selected patches; unread audit reports prevent an absolute guarantee of no prior mention.

1. **mips32rt-R6-1 — BUG — HIGH**  
   **Location:** `src/os/threads.c:164–198,295–298`; `src/os/fork.c:61–75`  
   **Fork can inherit a permanently locked reaper mutex.** `mips_reap_lock` is absent from fork coordination, and the child hook resets only the live counter. If another thread holds this mutex during `fork()`, the child's next clone blocks forever in `mips_reap_done()`.  
   **Fix:** Include the reaper mutex in fork preparation/release and rebuild child-side reaper ownership, taking care to preserve the surviving thread's stack.

2. **mips32rt-R6-2 — BUG — HIGH**  
   **Location:** `src/os/threads.c:664–675,826–828`  
   **Big-endian `FUTEX_WAKE_OP_PRIVATE` loses its private flag.** The helper receives neither `priv` nor `host_op`; both wake calls hard-code plain `FUTEX_WAKE`. These use different futex keys from private waits, leaving waiters asleep despite a successful memory update.  
   **Fix:** Pass the private flag into the helper and preserve it in both wake operations.

3. **mips32rt-R6-3 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:630–646,686–695,822–828`  
   **Big-endian `FUTEX_WAKE_OP` writes memory validated only for reading.** `futex_addr_ok()` requires `PROT_READ`, then the helper performs a direct host CAS. A read-only mapping can crash the translator; on host pages with broader aggregate permissions, it can modify guest-read-only memory. Concurrent unmapping adds another fault window.  
   **Fix:** Validate write permission and stabilize the mapping during the atomic update. Return guest `EFAULT` for inaccessible destinations.

4. **mips32rt-R6-4 — BUG — HIGH**  
   **Location:** `src/os/syscalls.c:533–535,571–583`  
   **`pipe` and `pipe2` incorrectly share one ABI.** Legacy O32 `pipe` returns descriptors in `$v0/$v1` without a buffer argument, but this handler always copies through `$a0`, causing spurious `EFAULT` or unrelated memory corruption. Conversely, `pipe2` correctly uses a buffer but incorrectly returns the first descriptor instead of zero.  
   **Fix:** Separate completion paths: register-only results for legacy `pipe`; buffer copyout and zero return for `pipe2`.

5. **mips32rt-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls_meta.c:135–143`; `src/os/syscalls.c:191–202`  
   **`F_SETFL` rejects ordinary write-only descriptors.** The usual `F_GETFL` → add `O_NONBLOCK` → `F_SETFL` sequence retains access mode `1`. OR-ing with `2U` produces mode `3`, which the converter rejects with `EINVAL`.  
   **Fix:** Clear access-mode bits before conversion, or use a dedicated converter for mutable status flags.

6. **mips32rt-R6-6 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls.c:207–209,232–235`; `src/os/syscalls_priv.h:29–36`  
   **Valid `O_DSYNC` opens fail with `EINVAL`.** `MIPS_O_SYNC` includes the `O_DSYNC` bit. With `O_DSYNC` alone, the full-mask comparison fails but the following nonzero-mask comparison succeeds, incorrectly treating it as bare `__O_SYNC`.  
   **Fix:** Test the distinct `__O_SYNC` bit separately and accept `O_DSYNC` alone.

7. **mips32rt-R6-7 — CLEAN — MEDIUM**  
   **Location:** `src/os/syscalls.c:613–621`  
   **The vectored-I/O scratch layout creates misaligned pointer accesses.** On the 64-bit target, `bases` occupies `4 * count` bytes after the aligned `iovec` array. For odd counts, `tmps` is only four-byte aligned, yet is accessed as an eight-byte pointer array. This violates C alignment requirements even where hardware tolerates unaligned accesses.  
   **Fix:** Place the pointer array before the `uint32_t` array, explicitly align its offset, or allocate a single array of appropriately aligned entry structs.

8. **mips32rt-R6-8 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:476–502`; `src/os/signals.c:508–515`  
   **A normal `CLONE_VM` child inherits the parent's alternate signal stack.** The whole context is copied, but `sigalt_sp`, `sigalt_size`, and `sigalt_flags` are not reset. Parent and child can consequently build signal frames over the same memory. Linux clears the alternate stack for `CLONE_VM` without `CLONE_VFORK`.  
   **Fix:** Disable the child's alternate stack under that flag condition.

9. **mips32rt-R6-9 — BUG — MEDIUM**  
   **Location:** `src/os/signals.c:741–748`  
   **An executing alternate signal stack can be disabled successfully.** The `SS_DISABLE` branch changes state and returns before the on-stack check. A handler running on that stack should receive `EPERM`; instead, subsequent signal-stack bookkeeping changes underneath it.  
   **Fix:** Check whether execution is on the active alternate stack before applying any requested stack change, including disabling it.

10. **mips32rt-R6-10 — DRY — LOW**  
    **Location:** `src/rt32/elf32.c:174–240,519–550,610–653`  
    **Three paths independently decode and validate ELF headers.** Loading, interpreter measurement, and preflight validation repeat magic/class/endian checks and field swapping, with different subsets handled in each path. Admission changes therefore require synchronized edits.  
    **Fix:** Extract repository-local ELF/header decoding helpers and retain operation-specific checks in their callers. No cross-repository sharing is needed.

11. **mips32rt-R6-11 — YAGNI — LOW**  
    **Location:** `src/os/backend_posix.c:319–340`; `src/os/backend.h:165–167`  
    **The host-worker alternate-stack API has no callers.** Repository searches found only declarations and definitions. Its “init” function merely allocates memory and does not register a signal stack, leaving an unused and misleading interface.  
    **Fix:** Remove these helpers and declarations until a concrete caller needs an implemented alternate-stack lifecycle.