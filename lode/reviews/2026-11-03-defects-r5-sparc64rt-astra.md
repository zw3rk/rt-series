# Round 5 static audit

Five read-only shell commands completed. No Markdown files, builds, tests, Docker, or QEMU were used. Findings below are static conclusions, not reproduced failures. Inspection covered selected interpreter, DBT, VM, OS, ELF-loading, and test paths; this is not exhaustive assurance.

## Findings

### [S64-R5-1] BUG — Composite open flags are decoded by partial matches
**Priority: High**

**Location:** [src/os/syscalls_ext.c:123](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:123), lines 123–153.

The conversion loop accepts any overlapping bit instead of requiring the complete flag. `SP_O_TMPFILE` includes `SP_O_DIRECTORY`, which an earlier entry consumes. A valid request happens to match the remaining bit, but that bit alone also incorrectly enables host `O_TMPFILE`. Likewise, `SP_O_NDELAY` loses its shared `O_NONBLOCK` bit first and is then recognized from its remaining bit alone.

**Fix:** Decode composite flags before their constituent flags, require complete masks, and handle aliases explicitly. Add valid-composite and partial-mask rejection cases.

### [S64-R5-2] BUG — Ordinary `F_GETFL`/`F_SETFL` usage fails
**Priority: Medium**

**Location:** [src/os/syscalls_ext.c:346](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:346), lines 346–357.

`F_SETFL` rejects every bit except `O_APPEND` and `O_NONBLOCK`. Consequently, the usual sequence `flags = fcntl(fd, F_GETFL); fcntl(fd, F_SETFL, flags | O_NONBLOCK)` fails for an `O_RDWR` descriptor because the returned access-mode bits remain present.

**Fix:** Ignore access-mode and other immutable status bits according to the guest ABI; translate supported mutable flags. Test the round trip with read/write descriptors.

### [S64-R5-3] BUG — Vectored I/O changes blocking and atomicity semantics
**Priority: High**

**Location:** [src/os/syscalls_ext.c:243](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:243), lines 243–295.

Each vector—and each 4 KiB chunk—is issued as a separate host `read` or `write`. For example, a pipe containing exactly enough data for the first vector can make the second `read` block even though one native `readv` could return the available prefix. Small multi-vector pipe writes also lose the single-operation atomicity guarantee.

The inspected test uses only one short vector: [tests/test_h2_syscall.c:119](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:119).

**Fix:** Gather or pin validated buffers and issue one host vectored operation, then scatter read results. Validate aggregate lengths before side effects. Add multi-vector pipe tests.

### [S64-R5-4] DEFECT — ELF load bias can wrap before address validation
**Priority: High**

**Location:** [src/os/guest_run.c:268](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:268) and [src/os/guest_run.c:349](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/guest_run.c:349).

Both `e_entry + bias` and `p_vaddr + bias` use unchecked unsigned addition. A crafted `ET_DYN` address near `UINT64_MAX` can wrap into a low address. The subsequent span validator receives the already-wrapped value, so it cannot detect the original overflow.

**Fix:** Check addition against `UINT64_MAX` before applying the bias, then validate the resulting guest range. Apply checked arithmetic to program-header and file-span calculations too.

### [S64-R5-5] BUG — `statx` silently changes pre-epoch timestamps
**Priority: Medium**

**Location:** [src/os/syscalls_stat.c:260](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:260), lines 260–264.

`put_statx_ts()` replaces every negative `tv_sec` with zero. The timestamp field is signed, so a valid file timestamp before 1970 becomes a different timestamp when returned to the guest.

**Fix:** Serialize the signed value’s 64-bit representation directly. Add a negative-second timestamp case that checks both seconds and nanoseconds.

### [S64-R5-6] DEFECT — The `statx` test passes an undersized, wrong-layout destination
**Priority: High**

**Location:** [tests/test_h2_syscall.c:86](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:86) and [tests/test_h2_syscall.c:170](/Users/angerman/Projects/zw3rk/sparc64rt/tests/test_h2_syscall.c:170).

The test passes `&st`, declared as `struct stat`, to raw `SYS_statx`. The runtime writes a 256-byte result, explicitly established at [src/os/syscalls_stat.c:239](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_stat.c:239) and copied at line 328. This can overwrite adjacent guest stack storage; checking only the return value also misses layout errors.

**Fix:** Use `struct statx`, verify the returned mask and size, and add surrounding canaries if testing the raw ABI.

### [S64-R5-7] DRY — Signal and ordinary syscall commits duplicate errno translation
**Priority: Medium**

**Location:** [src/os/syscalls_min.c:112](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_min.c:112) and [src/os/syscalls_sig.c:48](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_sig.c:48).

Two separate switches translate host errors, followed by duplicate `%o0`/carry updates. Their coverage already differs: the ordinary table handles errors such as `ENXIO`, `ECHILD`, and `ELOOP` that the signal table omits.

**Fix:** Keep one repository-local errno translator and result-commit helper. Leave signal-specific PC advancement in its wrapper. Verify guest errno values independently when consolidating.

### [S64-R5-8] YAGNI — An unused signal-mask implementation retains disconnected global state
**Priority: Low**

**Location:** [src/os/syscalls_ext.c:109](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:109), [src/os/syscalls_ext.c:543](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.c:543), and [src/os/syscalls_ext.h:242](/Users/angerman/Projects/zw3rk/sparc64rt/src/os/syscalls_ext.h:242).

The source/test reference search found no caller of `sparc64_l2a_rt_sigprocmask`. Dispatch uses `sparc64_sig_rt_sigprocmask` instead, at `src/os/syscalls_min.c:519`. The obsolete implementation maintains its own `l2a_blocked`, disconnected from actual signal delivery.

**Fix:** Remove the unused implementation, declaration, private mask, and constants used only by this path.

### [S64-R5-9] CLEAN — Interpreter memory documentation contradicts implemented alignment traps
**Priority: Low**

**Location:** [src/interp/interp_mem.c:10](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:10), versus [src/interp/interp_mem.c:167](/Users/angerman/Projects/zw3rk/sparc64rt/src/interp/interp_mem.c:167) and line 205.

The file overview says unaligned multi-byte accesses never fault. Integer load/store helpers explicitly raise misalignment traps. This documents the opposite of an important ISA invariant and can mislead future DBT or memory-helper changes.

**Fix:** Distinguish byte-oriented transport from instruction-level alignment enforcement in the overview.

## Cross-runtime propagation

These are inspection targets, **not confirmed sibling defects**:

- **`rvrt` and sibling Linux-user runtimes:** Check copied vectored-I/O loops, `F_SETFL` filters, `statx` timestamp serialization, raw syscall test buffers, and obsolete signal helpers.
- **Sibling ELF loaders, including `hyper-linux`:** Check bias addition before range validation and program-header/file-span arithmetic.
- **Runtimes with non-generic guest ABIs:** Check composite flag translation and duplicated errno mappings using each guest’s own constants.
- Keep the proposed DRY fixes **inside each repository**; no cross-repository shared library is needed.

No inspected `.c`, `.h`, or `.S` file exceeded 900 lines; the largest was `src/os/threads.c` at 895. No additional interpreter/DBT/VM runtime defect is asserted from the limited slices inspected.