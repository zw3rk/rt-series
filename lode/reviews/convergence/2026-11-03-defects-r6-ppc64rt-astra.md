Found **10 remaining issues** at `28df326`. Used exactly **7 shell invocations**; no Markdown reads, builds, tests, Docker, or QEMU. Working tree was clean.

These findings were checked against available remediation history, but “never reported in Rounds 1–5” cannot be guaranteed without reading those reports. Findings 8–10 concern exported backend functions; I found no live guest-dispatch callers for them.

1. **ppc64rt-R6-1 — BUG | HIGH**  
   **Location:** `src/dbt/emit_int.c:210–225`  
   DBT treats `RA=0` as literal zero for `subfic`, `addic`, and `addic.`. These instructions must read GPR0, as the interpreter correctly does. With GPR0=5, `subfic r3,r0,7` produces 7 instead of 2; carry and record flags can also differ.  
   **Fix:** Unconditionally load `d->ra` in this branch. Keep zero-base handling confined to `addi`/`addis`.

2. **ppc64rt-R6-2 — BUG | HIGH**  
   **Locations:** `src/os/proc.c:795–809`; `src/os/fd_table.c:103–114`  
   Repeated stdio redirection closes the newly installed descriptor. After the first `dup2(fd,1)`, the table stores host fd 1. A subsequent redirection first replaces host fd 1, then `syscall_fd_replace()` drops the previous table entry—which also names fd 1—closing the replacement. The syscall reports success with a closed destination.  
   **Fix:** Make replacement ownership-aware: never close the incoming descriptor when the existing entry names that same descriptor.

3. **ppc64rt-R6-3 — BUG | HIGH**  
   **Location:** `src/os/syscalls.c:460–482`  
   Chunked `read` can block after successfully reading available pipe data. With exactly 512 bytes available, an open writer, and a guest request for 1024 bytes, the first host read fills the chunk and the loop issues another blocking read. A normal pipe read could return the available 512 bytes immediately. Request/response protocols can deadlock here.  
   **Fix:** Preserve one-read semantics through suitable staging, or ensure subsequent collection cannot block after any bytes have been obtained.

4. **ppc64rt-R6-4 — DEFECT | HIGH**  
   **Locations:** `src/os/syscalls.c:244–269`, `388–408`  
   Guest writes are split into independent 512-byte host writes; `writev` additionally splits at every vector boundary. This loses pipe atomicity even for a guest operation whose total size is within `PIPE_BUF`. Concurrent process writers can interleave fragments of records that should remain contiguous.  
   **Fix:** Stage bounded atomic pipe writes and submit them in one host `write`/`writev` operation. Preserve the atomicity of the entire vector, not individual elements.

5. **ppc64rt-R6-5 — BUG | MEDIUM**  
   **Location:** `src/os/syscalls.c:408–417`  
   `writev` returns an error from a later vector even when earlier vectors have already written bytes. For example, a valid first vector followed by an inaccessible buffer writes the first payload but reports `EFAULT`. Retrying can duplicate output.  
   **Fix:** Once `total > 0`, return successful partial progress for subsequent payload faults or host I/O errors. Validate vector metadata before producing output.

6. **ppc64rt-R6-6 — DRY | MEDIUM**  
   **Locations:** `src/os/syscalls_misc.c:47–70`; `src/os/proc.c:243–279`; `src/os/backend_linux.c:69–118`; `src/os/backend_darwin.c:64–110`  
   Several repository-local errno translators have diverged. In particular, `syscall_host_to_linux()` lacks `EINTR`, so the explicit interrupted-`pwrite` branch at `src/os/syscalls.c:340–344` returns `EIO`. The backend tables also turn unmapped errors such as `ENOSPC` into `EINVAL`.  
   **Fix:** Consolidate translation **within `ppc64rt`**. Preserve Linux errno values on Linux and provide a complete mapping for supported operations on Darwin; route syscall helpers through it.

7. **ppc64rt-R6-7 — DEFECT | MEDIUM**  
   **Location:** `src/os/proc.c:727–736`  
   `pipe2` validates guest flags against host `O_CLOEXEC` and `O_NONBLOCK`. Darwin uses different numeric values, so valid Linux guest flags are rejected or interpreted incorrectly. Other file paths already distinguish guest and host constants.  
   **Fix:** Validate against explicit PPC64 Linux flag values, then translate to host flags before calling `fcntl`.

8. **ppc64rt-R6-8 — DEFECT | MEDIUM**  
   **Locations:** `src/os/backend_net.c:127–148`, `160–168`  
   Sockaddr conversion assumes the first two bytes are a host `uint16_t` family. Darwin instead stores a length byte followed by a family byte. Writing `AF_INET` as a little-endian 16-bit value sets the Darwin family byte to zero; reverse conversion likewise misreads the header.  
   **Fix:** Construct and decode host sockaddr headers explicitly for each platform, including Darwin length fields and family-specific size validation.

9. **ppc64rt-R6-9 — BUG | MEDIUM**  
   **Location:** `src/os/backend_net.c:151–169`  
   `xlate_addr_out()` respects the supplied capacity for its initial copy, then unconditionally reads and writes two bytes through the destination. Capacities of zero or one therefore cause out-of-bounds access. It also reports the copied length instead of the actual address length when truncation occurs.  
   **Fix:** Convert into a local buffer, copy only the caller’s capacity, and return the complete converted address length separately.

10. **ppc64rt-R6-10 — DEFECT | MEDIUM**  
    **Location:** `src/os/backend_net.c:515–534`  
    The Linux `ppoll` implementation uses `SIG_BLOCK`, ordinary `poll`, then `SIG_UNBLOCK`. This neither atomically installs the requested temporary mask nor restores the previous mask. A signal already blocked before entry becomes unblocked afterward; signals omitted from the temporary mask remain blocked during the wait.  
    **Fix:** Use native `ppoll` with the translated mask and original timespec, integrated with the worker’s interruption protocol. This also avoids the current millisecond truncation and one-day timeout cap.

No additional YAGNI or CLEAN finding was established strongly enough to include under this inspection budget.