Found seven concrete issues at HEAD `a37e353`. These appear distinct from the Round 1–5 fixes inspected in Git history; full deduplication against prior reports remains unverified because Markdown was excluded.

1. **mips64rt-R6-1 — BUG — HIGH**  
   **Location:** `src/os/futex.c:460–468`, `src/os/futex.c:538–539`  
   Linux futex comparisons receive guest logical values without converting them to the host representation of guest memory. For a big-endian guest on little-endian AArch64, a futex containing `1` is read by the kernel as `0x01000000`; `WAIT` therefore returns `EAGAIN` despite the preceding guest-aware comparison succeeding. `CMP_REQUEUE` has the same problem.  
   **Fix:** Convert expected memory-word values to host byte order before invoking the host futex. Preserve bitset masks and counts unchanged.

2. **mips64rt-R6-2 — BUG — HIGH**  
   **Location:** `src/os/futex.c:513–539`  
   Plain `FUTEX_REQUEUE` leaves `nrq == NULL`, passing a requeue count of zero to Linux. The code incorrectly treats `val3` as its requeue count; both requeue operations take that count from the fourth syscall argument. A request to move waiters without waking them silently moves none, potentially leaving them blocked indefinitely.  
   **Fix:** Decode and validate the fourth argument as the requeue count for both operations; ignore `val3` for plain `REQUEUE`.

3. **mips64rt-R6-3 — BUG — MEDIUM**  
   **Location:** `src/os/futex.c:521–528`  
   `CMP_REQUEUE` rejects every expected word greater than `INT_MAX`. Its comparison operand is a full 32-bit value, so valid words such as `0x80000000` incorrectly produce `EINVAL`.  
   **Fix:** Apply signed count validation only to wake/requeue counts. Accept the complete `uint32_t` range for the comparison operand.

4. **mips64rt-R6-4 — DEFECT — HIGH**  
   **Location:** `src/os/threads.c:394–422`, `src/os/threads.c:447–462`  
   Process clone drops `stack_va` and `tls_va` when dispatching to `l4b_clone_fork`. Consequently, a successful non-`CLONE_VM` clone with a supplied child stack or `CLONE_SETTLS` resumes with the parent's stack or TLS. Child execution can access the wrong stack objects or thread-local state.  
   **Fix:** Pass both arguments into the process-clone helper. In the child, install a nonzero requested stack and apply TLS when `CLONE_SETTLS` is set.

5. **mips64rt-R6-5 — BUG — MEDIUM**  
   **Location:** `src/os/threads.c:297–300`, `src/os/threads.c:400–403`  
   Both clone paths validate parent/child TID pointers unconditionally. When their corresponding flags are absent, those argument registers are ignored by the guest ABI and may contain arbitrary values. Such otherwise-valid clones incorrectly fail with `EFAULT`.  
   **Fix:** Gate TID-pointer handling on the applicable clone flags; do not validate unused arguments.

6. **mips64rt-R6-6 — DEFECT — MEDIUM**  
   **Location:** `src/os/futex.c:281–291`  
   Relative timeout conversion performs unchecked signed addition of monotonic seconds and guest-controlled seconds. The timeout parser accepts `INT64_MAX`, so a valid nonnegative N64 timeout can overflow `time_t` on the intended 64-bit host, invoking C undefined behavior or becoming an immediate timeout. Nanosecond normalization can also overflow the seconds field.  
   **Fix:** Use checked, saturating deadline arithmetic, including the nanosecond carry. Apply equivalent checks to the Darwin deadline helper at `src/os/futex.c:135–162`.

7. **mips64rt-R6-7 — YAGNI — LOW**  
   **Location:** `src/os/threads.c:552`, `src/os/threads.c:687–698`  
   The thread-local `l4b_ctx` is assigned and cleared but never read anywhere in `src`. Its surrounding comment describes a context-based fault-reporting mechanism that the implementation no longer uses.  
   **Fix:** Remove the variable and its assignments; update the comment to describe the actual host-PC resolution path.

Exactly four shell commands were used. No Markdown, builds, tests, Docker, or QEMU were run. This is a bounded static audit, not exhaustive coverage of all five categories.