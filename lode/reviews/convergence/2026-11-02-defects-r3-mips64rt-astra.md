Round 3 found **six actionable issues** at `45af6bf`, including an incomplete LL/SC fix and incorrect floating-point and vectored-I/O behavior.

This was a static review using five batched shell inspections, including `git log -n 5 --oneline`, recent commit diffs, source reads, and hygiene searches. No builds, tests, Docker containers, or QEMU ran. Findings below are source-derived, not runtime reproductions. The working tree was clean. No inspected `.c`, `.h`, or `.S` file exceeded 900 lines; `include/` does not exist in this checkout.

**M64-R3-1 — Syscall copyouts still race with LL/SC**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscalls.c:147`, `src/os/syscalls.c:464`, `src/interp/unaligned.c:559`
- **Evidence & Root Cause:** `guest_range(..., write=1)` invalidates reservations before returning a writable pointer. Callers subsequently write without holding `sc_lock`. HEAD adds another `mips_llsc_note_write()` afterward, but neither notification serializes the intervening write with SC. A peer can perform LL after the first notification, observe an intervening same-value copyout, then successfully SC before the second notification. Host CAS cannot detect that intervening write when the bytes still equal the reserved value. The unlocked byte-wise `putn()` writes also permit interleaving with SC.
- **Concrete Fix:** Stage syscall output in host memory, then commit guest bytes and reservation invalidation together under `mips_llsc_write_lock()`. Reuse one repository-local copyout helper for these paths. Do not hold the lock across blocking host operations. Add a coordinated same-value-copyout/LL/SC regression.

**M64-R3-2 — Single-precision directed rounding loses small operands**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/interp/fp.c:607`, `src/interp/fp.c:305`, `src/interp/fp.c:196`
- **Evidence & Root Cause:** ADD.S/SUB.S treat a `long double` intermediate as exact. It is not exact for all binary32 operand exponent gaps, even with binary128 precision. For example, `1.0f + 0x1p-120f` rounds to `1.0` in the intermediate. `fp_adj_f()` therefore sees equality and skips correction; `fp_inexact()` also sees equality and omits Inexact. Under rounding toward positive infinity, the guest result should instead be `0x3f800001`, with Inexact set.
- **Concrete Fix:** Determine the exact residual sign for addition/subtraction using an error-free transformation or integer significand arithmetic. Use that residual for directed rounding and exception flags. Cover widely separated exponents under all four rounding modes.

**M64-R3-3 — Splitting vectored I/O changes syscall semantics**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_sync.c:239`, `src/os/syscalls_sync.c:307`
- **Evidence & Root Cause:** `mips_sc_vec()` splits a guest vector into separate host calls of at most 64 entries. A 65-entry `writev()` to a datagram socket becomes two datagrams. A corresponding `readv()` can consume separate messages or discard the first message’s remaining bytes. Splitting also loses the single-operation atomicity of small pipe writes and permits shared file-offset operations to interleave between chunks.
- **Concrete Fix:** Import the complete guest vector and issue one host vectored-I/O call. Use heap allocation for the descriptor array to preserve the no-VLA requirement. Apply the transfer-size limit to the aggregate request, not independently to each element.

**M64-R3-4 — Partial readv copyout returns the wrong byte count**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_sync.c:339`
- **Evidence & Root Cause:** After reacquiring the lease, the read path copies each vector entry and decrements `rem`. If a later destination is no longer writable, the error path returns only `total` from previous batches—or `EFAULT` when `total == 0`. Bytes already copied in the current batch are omitted. Thus a mapping change during the blocking read can produce a negative return despite successfully copying an earlier vector.
- **Concrete Fix:** Track bytes committed in the current operation. On a later copyout fault, return the committed count when nonzero; return `EFAULT` only when nothing was copied. Add a regression that invalidates a later destination while the read is blocked.

**M64-R3-5 — Obsolete double-rounding helper remains exported**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/interp/fp.c:284`, `src/interp/fp.h:56`
- **Evidence & Root Cause:** Repository search finds `fp_adj_d` only at its definition and declaration. The revised double-precision arithmetic uses `fp_round_d()` instead. The unused helper retains the old assumption that a `long double` intermediate supplies an exact value, making it a misleading alternative for future callers.
- **Concrete Fix:** Remove `fp_adj_d()` and its declaration.

**M64-R3-6 — Unaligned-access comments contradict the implementation**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `src/interp/unaligned.c:7`, `src/interp/unaligned.c:185`
- **Evidence & Root Cause:** The file header claims endian-natural spans and explicitly rejects QEMU’s little-endian swapped roles. The function-level comment and implementation instead use endian-dependent spans: LDL takes `pa..addr` on LE and `addr..pa+7` on BE. The header also claims the `(0,7)` pair round-trips on every variant, contradicting the later comment.
- **Concrete Fix:** Replace the historical header claims with the implemented endian-specific rules and correct load-pair offsets. Keep historical adjudication in the experiment notes.

Checklist:

- [ ] **M64-R3-1:** Serialize syscall copyout and LL/SC invalidation.
- [ ] **M64-R3-2:** Preserve exact residuals for single-precision rounding.
- [ ] **M64-R3-3:** Preserve one-operation vectored-I/O semantics.
- [ ] **M64-R3-4:** Return bytes already committed before a copyout fault.
- [ ] **M64-R3-5:** Remove unused `fp_adj_d()`.
- [ ] **M64-R3-6:** Correct contradictory unaligned-access comments.