## Round-4 remediation review: `03c3092` vs `4cead69`

Static review only. No builds, tests, containers, or QEMU were run. Four tool turns were used.

**Headline:** ten of twelve items are fixed as specified. One item is a regression: the M32-R4-4 Inexact fix sets the wrong host FPSR bit, so every inexact `CVT.W`/`CVT.L` now reports Invalid instead of Inexact and can mis-saturate at the INT_MIN boundary. One item is partial: M32-R4-9 aborts the writeback but the error is still discarded by every flush caller except msync. The commit touches only `src/` and adds none of the regression tests the audit asked for.

### Per-item findings

**M32-R4-1 (bulk copyout epochs) - VERIFIED.** `ll_epoch_bump_locked` now walks every 64-byte line from the first bucket, wrapping modulo the table, and caps at the table size so a whole-table range bumps each bucket once. The line count is computed in 64-bit so `va + len` cannot overflow. Cost is bounded by `MIPS32_LL_EPOCH_WORDS` atomics under the LL lock per bulk store. No test added.

**M32-R4-2 (read/readv tracked commit) - VERIFIED, with a Low follow-up.** Both paths now call `mips_guest_store_commit` on the transferred bytes after the host call returns, so the LL lock is never held across blocking I/O. The readv loop walks slices in iovec order and clips to the returned byte count, so partial reads are handled. Two caveats:
- The commit is a self-copy. `mips_store_locked` does `memcpy(dst, src, len)` with `src == dst`. That is formally undefined under C11 7.24.2.1 and violates the `restrict` contract. It works on every real libc, but the project rule is no UB. Skip the copy when the pointers are equal, or use `memmove`, and keep the epoch bump.
- Other host calls that write guest memory through a raw pointer were not verified in this pass: `pread` in `src/os/backend_posix.c:165`, `recvfrom` at line 288, and `readlinkat` in `src/os/syscalls_meta.c:528`. If any of those receives a guest pointer, it has the same gap the audit described for `read`.

**M32-R4-3 (CVT.L low word) - VERIFIED.** Traced the new 64-bit sequence: the negative-overflow predicate is built in W24, then ANDed with the Invalid bit, and only the final two CSELs touch TMP1/TMP2. An exact `CVT.L.D(1.0)` now keeps its low word. The claim that W24 is dead in this op was not checked against the GPR host-register table. No test added.

**M32-R4-4 (conversion Inexact) - REGRESSION (High).** The fix shelters the input in V3, compares it against the FRINT result, and on NE ORs the value `1` into the FPSR word before `fp_finish`. Bit 0 of the AArch64 FPSR is IOC (Invalid), not IXC. IXC is bit 4. `fp_finish` in `src/dbt/emit_fp.c:395` extracts bits 4:0, reverses them, and maps bit 0 to FCSR Cause V (bit 16) and Flag V (bit 6). The same file's own overflow predicate reads bit 0 as Invalid. Consequences:
- `CVT.W.D(1.5)` now sets Cause V and Flag V in FCSR, never I. With V enabled in FCSR (common after `feenableexcept(FE_INVALID)`), every inexact conversion traps. Interp sets I only, so FCSR diverges on every inexact conversion.
- `CVT.W.D(-2147483648.5)` under round-to-nearest-even rounds to `0x80000000`, which is in range. The overflow predicate in the W path checks `result == 0x80000000 && bit0`, and bit0 is now set by the inexact path, so the DBT saturates to `0x7FFFFFFF`. Interp returns `0x80000000` with I set. That is a register divergence, not just a flag divergence.

The fix is one constant: emit `0x10U` instead of `1U` at `src/dbt/emit_fp_cvt.c:193`. Also correct the comment that calls bit 0 the IXC bit. The FCMP comment claiming cumulative bits are untouched is slightly wrong for signalling NaN inputs, but that case already sets Invalid through the conversion itself, so it is harmless.

**M32-R4-5 (Darwin sub-page replacement) - VERIFIED by construction.** Darwin no longer creates direct `MAP_SHARED` file pages at all. File mappings always take the shadow path. The sub-page anonymous replacement therefore only ever memsets owned anonymous host pages, and the pre-replacement flush at `src/rt32/vm_mmap.c:147` preserves dirty bytes. See the Darwin follow-ups below for the costs this trade carries.

**M32-R4-6 (mremap backing continuity) - VERIFIED.** Subsequent regions must match file-vs-anonymous kind, `darw_sync`, dev/ino, and have `file_off == first.file_off + (cur - start)`. The offset math uses the first region's offset already adjusted for `start`, so it is correct. Only the mremap call site at `src/rt32/vm_mmap.c:450` passes `out_back`; the mmap-fixed caller passes NULL and keeps prior behaviour. No test added.

**M32-R4-7 (failed Darwin population) - VERIFIED for the audited path.** The file read now goes into a zeroed malloc staging buffer before any mprotect or memset, so a read failure or ENOMEM returns with nothing modified. Residual, pre-existing on all hosts: if `vm_record_region_backed_locked` fails after the memcpy, the old region's bytes are already overwritten while its metadata survives.

**M32-R4-8 (CLONE_CHILD_SETTID gating) - VERIFIED, with a Medium follow-up.** `set_ctid` and `clear_ctid` are tracked separately, the child writes its TID only for SETTID, the clear address is retained only for CLEARTID, and the EFAULT range check now covers both flags. The parent-side suppression was revisited exactly as asked, which reintroduces the race the old comment warned about for one ABI shape. See follow-up N-2.

**M32-R4-9 (writeback baseline read error) - PARTIAL.** A non-EINTR `pread` failure now sets `rc` and breaks before propagation and file write. The second half of the audit ask, propagating the error, was not done: `vm_flush_darw_range_locked` is still `(void)`-discarded at `src/rt32/vm_mmap.c:147`, `:379`, `src/rt32/vm.c:618`, and `:712`, and `vm_flush_darw_inode_locked` discards it internally. A failed flush before an mmap replacement still silently drops dirty bytes.

**M32-R4-10 (mixed direct/shadow coherence) - VERIFIED by construction.** With no direct file pages on Darwin the mixed case cannot arise. The underlying dirty inference by diff against the current file is unchanged, so an external writer to the same file still gets overwritten by an untouched shadow on flush. That is Darwin-only and pre-existing for unaligned mappings.

**M32-R4-11 (FPR slot hash) - VERIFIED.** One `static inline fpr_slot` in `emit_fp_priv.h`, used by lookup and both invalidation sites. `fp_slot` (byte offset) and `fpr_slot` (cache index) coexist with confusingly similar names, cosmetic only.

**M32-R4-12 (kill fallback) - VERIFIED.** The unreachable SI_USER overflow branch and `KILL_SI_QUEUE` are gone, and `mips_signal_pend` in `src/os/sigqueue.c` confirms it returns 0 for that case.

### Curated C11 and hygiene

- No `#include "*.c"`, no `sprintf`/`strcpy`/`strcat`, no `x18`/`w18` code references.
- All sources are at or under 899 lines. The largest changed file, `src/os/syscalls.c`, is at 889 and has little headroom left.
- `static inline` in a header is permitted. The `bases` pointer carved from the iovec allocation is correctly aligned.

### Summary table

| Item | Status | Tests added |
|---|---|---|
| M32-R4-1 | VERIFIED | no |
| M32-R4-2 | VERIFIED (Low follow-up N-1) | no |
| M32-R4-3 | VERIFIED | no |
| M32-R4-4 | REGRESSION (High) | no |
| M32-R4-5 | VERIFIED (Darwin follow-up N-3) | no |
| M32-R4-6 | VERIFIED | no |
| M32-R4-7 | VERIFIED | no |
| M32-R4-8 | VERIFIED (Medium follow-up N-2) | no |
| M32-R4-9 | PARTIAL | no |
| M32-R4-10 | VERIFIED | no |
| M32-R4-11 | VERIFIED | no |
| M32-R4-12 | VERIFIED | no |

### Newly discovered consequential follow-ups

- **N-0 (High, blocks RC):** `src/dbt/emit_fp_cvt.c:193` ORs bit 0 (IOC) instead of bit 4 (IXC). Change the constant to `0x10U`, fix the comment, and add an interp/DBT comparison for `CVT.W.D(1.5)` FCSR state and `CVT.W.D(-2147483648.5)` result.
- **N-1 (Low):** `mips_store_locked` self-copies with `memcpy` on identical pointers from the read/readv commit path. Skip the copy when `src == dst` and keep the epoch bump. Confirm whether pread, recvfrom, and readlinkat also write guest memory through raw host pointers.
- **N-2 (Medium):** With `PARENT_SETTID | CHILD_CLEARTID`, no `CHILD_SETTID`, and `ptid == ctid` (musl before 1.2 passes `&new->tid` for both), the parent now writes the TID after the start handshake. A child that runs to exit first clears the word, then the parent resurrects it and the join hangs. Linux performs the parent write before the child is scheduled. Have the child perform the parent SETTID write before publishing `started` when `ptid` aliases `clear_ctid`.
- **N-3 (Medium, Darwin only):** Every file mapping is now eagerly populated through a malloc staging buffer of the full mapping length plus a memcpy. Large aligned file mappings were previously lazy host mmaps. This doubles transient memory and front-loads I/O for big mappings, and `MAP_SHARED` file mappings are no longer live-coherent across fork or with external processes until a flush. Acceptable for a development host, but it should be documented in the Darwin notes.
- **N-4 (Medium):** No regression tests accompany any of the twelve fixes, although the audit asked for them on nine items. The commit message does not say they were deferred.
