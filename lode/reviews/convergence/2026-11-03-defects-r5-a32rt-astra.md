Found **10 actionable findings**. Used exactly **8 read-only shell commands**; no Markdown reads, builds, tests, Docker, or QEMU. These are static findings, not reproduced failures. Inspection covered the requested areas selectively; no `rt32/` or `family/` paths were found. Family-related state resides in `vm_file.c`.

1. **[A32-R5-1] BUG — Interpreter instruction fetch ignores execute permission.**  
   **Evidence:** [src/interp/interp.c:108](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:108), lines 108–115 and 141–158; dispatch at line 194.  
   Both instruction-fetch helpers call `i_load_bytes()`, which checks only `PROT_READ`. Consequently, readable guest data can execute without `PROT_EXEC`, while execute-only pages fail the read check.  
   **Fix:** Separate instruction fetch from data loads, validate guest execute permission across the complete instruction, and retain the correct fault PC. Add A32 and Thumb cases for readable/non-executable and execute-only mappings.

2. **[A32-R5-2] BUG — Darwin sub-page replacement destroys neighboring shared backing.**  
   **Evidence:** [src/os/backend_darwin.c:108](/Users/angerman/Projects/zw3rk/a32rt/src/os/backend_darwin.c:108), lines 108–150; replacement admission at [src/vm.c:641](/Users/angerman/Projects/zw3rk/a32rt/src/vm.c:641).  
   The replacement path snapshots an entire host page, replaces it with `MAP_PRIVATE | MAP_ANONYMOUS`, and copies neighboring bytes back. This preserves bytes but loses their backing identity. For example, replacing one 4 KiB quarter of a 16 KiB shared mapping makes the surviving quarters private, although their tracking records still describe shared mappings.  
   **Fix:** Preserve shared backing for unaffected sub-pages. Until that is supported, reject this mixed-backing replacement before retiring any mapping. Cover visibility through a second mapping and across `fork()`.

3. **[A32-R5-3] BUG — Successful `sendmsg` writes to its read-only input header.**  
   **Evidence:** [src/os/os_sys_sock.c:474](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:474), lines 474–475 and 537–541.  
   `sendmsg` validates the header for reading, but the common success path writes `msg_namelen` and `msg_flags` for both sending and receiving. A valid header on a read-only page therefore faults after the message has already been sent; on permissive host pages, it silently modifies guest input.  
   **Fix:** Restrict header copyout to `recvmsg`. Add a read-only-header case; the existing [socket test at line 93](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m5_ltp_gdb.c:93) uses a writable stack header.

4. **[A32-R5-4] BUG — Ancillary data is silently dropped when sending.**  
   **Evidence:** [src/os/os_sys_sock.c:491](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:491), lines 491–518.  
   Conversion uses a fixed 1,024-byte host buffer. When the next control message does not fit, the loop simply breaks and sends the converted prefix successfully. Valid control data can disappear without an error. A legal 253-descriptor `SCM_RIGHTS` message alone requires more than this buffer after host-header expansion.  
   **Fix:** Compute the required converted size with overflow checks and allocate bounded storage, or reject excess input before sending anything. Add boundary tests and verify that all requested descriptors arrive.

5. **[A32-R5-5] BUG — Large `select` sets expose guest memory to host-word overrun.**  
   **Evidence:** [src/os/os_sys_sock.c:606](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sock.c:606), lines 606–610 and 652–679.  
   Above 1,024 descriptors, the implementation abandons translation and passes guest bitmaps directly to the 64-bit syscall. For `nfds = 1025`, the guest bitmap occupies 132 bytes, but the host rounds it to 136 bytes. With a sufficiently large descriptor table, the kernel can read or overwrite four bytes beyond the guest bitmap. This path also validates only four bytes.  
   **Fix:** Allocate host-word-rounded buffers for large sets, validate the complete guest spans, zero host padding, and copy back only guest-sized data. Extend the existing [small-descriptor test](/Users/angerman/Projects/zw3rk/a32rt/tests/test_m5_ltp_gdb.c:384) with a high descriptor and trailing canary.

6. **[A32-R5-6] BUG — Software exclusive-store validation has an ABA race.**  
   **Evidence:** [src/vm/vm32.c:518](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:518), lines 518–550; ordinary stores at [src/interp/interp.c:127](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:127).  
   Reservation validation and the final value CAS are separate operations. After the last epoch check, another thread can write A→B→A and invalidate the reservation. The CAS still sees A and succeeds, incorrectly reporting a successful `STREX`. Sequentially consistent atomics do not make this multi-operation transaction indivisible.  
   **Fix:** Coordinate reservation validation and the store with all competing writes, using an appropriate per-reservation synchronization protocol. Add a controlled interleaving test around the final epoch check.

7. **[A32-R5-7] DEFECT — `mremap` ignores protection failures and incompletely restores rollback state.**  
   **Evidence:** [src/vm/vm_mremap.c:102](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_mremap.c:102), lines 102–112 and [273–294](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm_mremap.c:273).  
   Copy-time protection changes and destination protection restoration discard errors. A failed widening can lead directly to a fault in `memcpy`; failed final protection can leave the moved mapping writable. If retiring the source fails, rollback drops the destination but does not restore source protections widened for copying.  
   **Fix:** Return errors from the copy helper, track temporary protection changes, restore source permissions on every failure, and require successful destination protection before retiring the source. Validate these branches with injected backend failures.

8. **[A32-R5-8] DRY — Reservation-range invalidation has three implementations.**  
   **Evidence:** [src/interp/interp.c:128](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp.c:128), [src/signals.c:281](/Users/angerman/Projects/zw3rk/a32rt/src/signals.c:281), and [src/vm/vm32.c:482](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:482).  
   Interpreter stores and signal-frame construction implement their own four-byte loops, while `a32_vm32_copyout_invalidate()` already implements range invalidation by reservation granule. This duplicates boundary and granule policy inside the repository.  
   **Fix:** Route both callers through the existing local helper. Keep write ordering explicit; consolidation alone does not repair finding 6.

9. **[A32-R5-9] YAGNI — Unused Soft-TLB probe contains unreachable cross-page logic.**  
   **Evidence:** [src/vm/vm32.c:136](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.c:136), lines 136–167; declaration at [src/vm/vm32.h:100](/Users/angerman/Projects/zw3rk/a32rt/src/vm/vm32.h:100).  
   Repository search found only the definition and declaration. Furthermore, accepted widths are powers of two up to 16 and misaligned addresses are rejected first, so the subsequent cross-page branch cannot execute.  
   **Fix:** Remove the unused API if it has no supported external consumer. If retained as a diagnostic interface, remove unreachable handling and add an actual caller/test.

10. **[A32-R5-10] CLEAN — Decoder predicate contains an unconditional override.**  
    **Evidence:** [src/interp/interp_a32.c:164](/Users/angerman/Projects/zw3rk/a32rt/src/interp/interp_a32.c:164).  
    `((insn & 0x90U) != 0x90U || true)` is always true. It presents an encoding restriction that does not exist and obscures the decoder’s actual admission rule.  
    **Fix:** Remove the tautological clause if the broad dispatch is intentional; otherwise restore the intended restriction with encoding-specific tests. No inspected C/C++/assembly file exceeds 900 lines; the largest is `signals.c` at 899.

**Cross-runtime propagation notes:** These are inspection targets, not confirmed sibling defects.

| Findings | Sibling runtimes to check |
|---|---|
| 1, 6 | `mips32rt`, `ppc32rt`, `rvrt`, `mips64rt`, `ppc64rt`, `loongarch64rt`: fetch permissions and software reservation protocols |
| 2, 7 | `i686rt`, `mips32rt`, `ppc32rt`: large-host-page replacement, backing preservation, and remap rollback |
| 3–5 | Especially `i686rt`, `mips32rt`, `ppc32rt`: 32/64-bit socket and descriptor-set translation; inspect analogous Darwin socket paths in other runtimes |
| 8–10 | Check copied local helpers and decoder scaffolding; consolidate only within each repository |

ELF loading, DBT dispatch, FP conversion, and file-family bookkeeping received selective inspection without additional sufficiently established findings. This bounded pass does not establish those areas as defect-free.