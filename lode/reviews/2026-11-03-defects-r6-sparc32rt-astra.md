Found **10 remaining issues** at HEAD `c4a1e7a`. Used seven shell invocations; read no Markdown and ran no builds, tests, Docker, or QEMU. These are static findings. Novelty was checked against inspected Round-1–5 commit messages and patches; unread audit reports may contain additional overlap.

1. **sparc32rt-R6-1 — BUG — HIGH**  
   **Location:** `src/os/threads_fd.c:63–75`  
   If the first `realloc` succeeds and the second fails, `free(nu)` leaves `thr_fd_used` dangling while its old capacity remains published. Subsequent descriptor operations can access freed memory or pass it to `realloc` again.  
   **Fix:** Allocate and copy both replacement arrays before publishing either, or retain the successful first allocation safely when the second fails.

2. **sparc32rt-R6-2 — BUG — HIGH**  
   **Locations:** `src/rt32/stack32.c:245–247`; `src/os/threads_exec.c:175–177`; `src/rt32/procfs.c:208–220`  
   Stack setup saves the exec function’s local `argv`/`envp` arrays in `ctx`. Exec immediately frees their strings, and the arrays expire upon return. Later `/proc/self/cmdline` reads dereference dangling arrays and freed strings; `/proc/self/exe` also falls back to that dangling `argv` after `exec_path` is cleared.  
   **Fix:** Give process metadata explicit ownership and retain durable copies across exec, or read argument data from validated guest memory.

3. **sparc32rt-R6-3 — BUG — HIGH**  
   **Locations:** `src/os/futex.c:262–278,296–325`; `src/os/syscalls_time.c:269–294`  
   `futex_time64` strips `FUTEX_PRIVATE_FLAG` using `op & 15U`, whereas ordinary `futex` preserves it. A private waiter using one syscall and a wake using the other therefore use different host futex keys. The wake can return zero while the waiter remains blocked indefinitely.  
   **Fix:** Preserve supported flags consistently in both entry points and share their host dispatch logic.

4. **sparc32rt-R6-4 — DEFECT — HIGH**  
   **Location:** `src/rt32/stack32.c:160–170`  
   On Darwin, `if (0)` skips initialization of `rand_bytes` entirely, then copies uninitialized host stack bytes into guest `AT_RANDOM`. On Linux, an interrupted, short, or failed `getrandom` produces a fixed public byte pattern. This exposes host stack contents on Darwin and defeats entropy-dependent guest initialization on the fallback path.  
   **Fix:** Use the existing host entropy backend, handle partial reads and interruption, and fail initialization if secure entropy cannot be obtained.

5. **sparc32rt-R6-5 — BUG — HIGH**  
   **Locations:** `src/rt32/procfs.c:93–128,195–224`  
   Procfs writes the complete generated file into a blocking pipe before returning its read descriptor. If `/proc/self/cmdline` exceeds pipe capacity, the writer blocks before the guest can read anything. Large argument lists make this reachable.  
   **Fix:** Serve generated content from a seekable anonymous backing file or another mechanism that does not require a reader during `open`.

6. **sparc32rt-R6-6 — DEFECT — HIGH**  
   **Locations:** `src/rt32/procfs.c:34–57,307–314`  
   `procfs_copy_in` checks guest permissions and then dereferences guest memory without holding the VM reader guard. Concurrent `munmap` or `mprotect` can invalidate the pointer between those operations, causing a host fault during guest `readlink`/`readlinkat`.  
   **Fix:** Replace this duplicate string copier with the already guarded `l2a_copy_cstring` in `src/os/l2a_access.h:159–191`.

7. **sparc32rt-R6-7 — BUG — MEDIUM**  
   **Locations:** `src/os/syscalls.c:665–669,808–816`  
   Both statx implementations replace negative timestamp seconds with zero. A file timestamp before the Unix epoch silently changes to an epoch timestamp, while retaining its original nanoseconds.  
   **Fix:** Serialize the signed seconds as their full two’s-complement 64-bit representation without clamping.

8. **sparc32rt-R6-8 — BUG — MEDIUM**  
   **Location:** `src/os/syscalls.c:863–874`  
   `F_SETFL` rejects every bit except `O_NONBLOCK` and `O_APPEND`, including access-mode bits returned by `F_GETFL`. Consequently, the ordinary `fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)` pattern fails for writable descriptors.  
   **Fix:** Ignore immutable access/open flags as appropriate and translate supported mutable status flags.

9. **sparc32rt-R6-9 — DRY — LOW**  
   **Locations:** `src/os/threads_exec.c:33–40`; `src/os/l2a_access.h:136–149`  
   `thr_ld` duplicates the existing checked big-endian word loader: guarded four-byte load, error propagation, and conversion. Maintaining both adds another place for access semantics to diverge.  
   **Fix:** Call `l2a_ld_be32` directly and remove `thr_ld`. This consolidation stays entirely within `sparc32rt`.

10. **sparc32rt-R6-10 — YAGNI — LOW**  
    **Locations:** `src/rt32/stack32.c:171–174,185–208`  
    Stack setup pushes `"sparc"` and checks its address, but never publishes that address in auxv or elsewhere. This is unused guest-stack data and an unnecessary failure condition.  
    **Fix:** Remove the allocation and variable unless an explicit platform auxv entry is intended; in that case, publish the entry.