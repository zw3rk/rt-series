Found **12 actionable issues** at HEAD `4cead69`. The Round-3 and post-fable fixes are present, but several paths remain incomplete.

Used exactly **7 shell inspection commands**, including the requested history commands. No Markdown documents, builds, tests, containers, or QEMU were run. The working tree is clean. Findings below are static traces, not runtime reproductions.

**M32-R4-1 — Bulk copyout misses interior LL/SC reservation epochs**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/mem.c:405`
- **Evidence & Root Cause:** `rt32_vm_copy_to()` now reaches `mips_guest_store_commit()`, but `ll_epoch_bump_locked()` increments only the first and last 64-byte buckets. That was sufficient for small stores, not arbitrary copyout or mremap lengths. A peer’s reservation at `base + 64` survives a same-value 192-byte copyout starting at aligned `base`. The Round-3 test covers only four bytes.
- **Concrete Fix:** Increment every affected bucket under the existing lock; for ranges spanning the entire hash table, increment each bucket once. Add a two-context regression reserving an interior word.

**M32-R4-2 — `read` and `readv` still bypass tracked copyout**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/syscall_min.c:149`
- **Evidence & Root Cause:** `sc_read()` passes the guest address directly to host `read()`. Likewise, `src/os/syscalls.c:665` builds guest-backed iovecs for host `readv()`. Neither path invokes the new store-commit primitive. A host read that overwrites a peer’s reserved word with the same value leaves its epoch unchanged, allowing SC to succeed.
- **Concrete Fix:** Read into host staging storage, then commit the returned bytes through validated, epoch-tracked copyout. Preserve partial-read and iovec ordering semantics. Do not hold the LL spinlock across blocking I/O. Add actual read/readv regressions.

**M32-R4-3 — DBT `CVT.L` destroys the low result word**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_cvt.c:203`
- **Evidence & Root Cause:** The 64-bit conversion initially places its low word in `A64_TMP1`. The negative-overflow check then overwrites that register with a Boolean predicate at lines 203–207. Line 212 selects between `0xFFFFFFFF` and that predicate, and line 215 stores it as the conversion result. For an ordinary exact conversion such as `CVT.L.D(1.0)`, the low word becomes zero.
- **Concrete Fix:** Preserve both result halves while calculating the overflow predicate in separate scratch storage. Add interpreter/DBT comparisons for exact positive and negative values with nonzero low words, plus both overflow boundaries.

**M32-R4-4 — DBT conversion pre-rounding loses Inexact**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/emit_fp_cvt.c:123`
- **Evidence & Root Cause:** For `CVT.W`/`CVT.L` with round-to-nearest, the emitter uses `FRINTN` before `FCVTZS`. The rounding step does not report Inexact, and the subsequent conversion receives an integral operand. In contrast, `src/interp/fp.c:618` raises `FP_E_I` for discarded fractional bits in these conversions. Thus `CVT.W.D(1.5)` can produce matching integer results but divergent FCSR state.
- **Concrete Fix:** Preserve discarded-fraction information or use an appropriate exact rounding sequence, then merge Inexact into the guest exception machinery. Test FCSR flags, causes, and enabled-exception behavior across rounding modes.

**M32-R4-5 — Darwin sub-page replacement retains the previous file backing**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_mmap.c:173`
- **Evidence & Root Cause:** An aligned 16 KiB file mapping takes the direct host `mmap()` path at line 161. Replacing one 4 KiB slice takes the shadow path, which merely changes protection and calls `memset()`/`pread()` on the existing host mapping. If that mapping was `MAP_SHARED`, creating a supposedly anonymous replacement writes zeros into the original file. The replacement also remains physically file-backed despite its new VMA metadata.
- **Concrete Fix:** Convert affected direct host pages to owned shadow backing before replacing sub-pages, preserving neighboring bytes and their backing metadata. Add a regression mapping a shared 16 KiB file page, replacing one 4 KiB slice anonymously, and checking file contents and subsequent isolation.

**M32-R4-6 — `mremap` accepts incompatible adjacent file mappings**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm.c:514`
- **Evidence & Root Cause:** `vm_check_mapped_range_locked()` checks subsequent regions only for matching protection and flags. It returns backing information from the first region without checking subsequent inode identities or file offsets. `rt32_vm_mremap()` then uses that single backing to recreate the whole shared range at `src/rt32/vm_mmap.c:506`. Adjacent mappings of different files with identical flags/protection can therefore become entirely backed by the first file.
- **Concrete Fix:** Require compatible backing identity and contiguous offsets for a remappable range, or preserve each segment explicitly. Reject unsupported multi-mapping ranges before modifying the destination. Cover different files and discontinuous offsets within one file.

**M32-R4-7 — Failed Darwin population leaves modified mappings and elevated protection**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_mmap.c:187`
- **Evidence & Root Cause:** The shadow path elevates the host-rounded range to RW and zeros its contents before reading the file. On a population error, it closes the duplicate descriptor and returns immediately. It neither restores protection nor reconciles the old VMA metadata with the overwritten bytes. With `MAP_FIXED`, an existing mapping can retain its old metadata after its contents have been destroyed.
- **Concrete Fix:** Stage fallible file population before modifying live mappings. Ensure every failure after protection elevation restores host protections and leaves mapping metadata consistent with the actual backing. Add injected read-error coverage for both vacant and occupied destinations.

**M32-R4-8 — Clone writes `ctid` without `CLONE_CHILD_SETTID`**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/threads.c:250`
- **Evidence & Root Cause:** Clone stores the supplied `ctid` unconditionally in `t->ctid` at line 355. The child then writes its TID whenever that pointer is nonzero, regardless of `CLONE_CHILD_SETTID`. This modifies an argument that should be ignored when neither child-TID flag is set, and adds an unintended startup write for `CLONE_CHILD_CLEARTID` alone.
- **Concrete Fix:** Track startup SETTID and exit CLEARTID separately. Gate the startup write on `CLONE_CHILD_SETTID`; retain the pointer independently for clearing on exit. Revisit the parent alias suppression using the actual startup-write condition.

**M32-R4-9 — Darwin writeback treats read errors as a valid zero baseline**

- **Severity:** High
- **Category:** DEFECT
- **Location:** `src/rt32/vm_darw.c:173`
- **Evidence & Root Cause:** The baseline buffer is zero-initialized. A non-EINTR `pread()` failure merely breaks the loop; it does not set `rc` or abort processing. The function then compares against incomplete baseline data, propagates bytes into aliases, and may write the whole chunk back. A failed baseline read can consequently erase file bytes represented by the untouched zero portion of the buffer.
- **Concrete Fix:** Distinguish EOF from read failure and stop before alias mutation or writeback on failure. Propagate the error through flush callers that currently discard it. Add fault-injected short-read/EIO coverage.

**M32-R4-10 — Shadow flush can overwrite newer direct-mapping writes**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/rt32/vm_darw.c:209`
- **Evidence & Root Cause:** Dirty detection compares a shadow against the *current file*, not the shadow’s last synchronized contents. Create a shadow alias and an aligned direct shared alias of the same initially zero bytes. Write `1` through the direct alias; the file now reads `1`, while the shadow still contains `0`. Flushing the untouched shadow classifies its zero as dirty and overwrites both the direct alias and file. The Round-3 shadow-to-shadow propagation does not resolve this mixed-backing case.
- **Concrete Fix:** Use coherent shared backing or actual dirty tracking with a retained synchronization baseline. Do not infer dirtiness solely from disagreement with current file contents. Add both alias-creation orders and direct-write/shadow-flush regressions.

**M32-R4-11 — FPR cache indexing is duplicated across emitters**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/dbt/emit_fp_cvt.c:29`
- **Evidence & Root Cause:** The cache hash implemented by `fpr_slot()` in `src/dbt/emit_fp.c:142` is repeated in conversion invalidation, including line 221. The comment explicitly acknowledges the duplication. A change to indexing can leave invalidation targeting a different slot.
- **Concrete Fix:** Put the cache-index calculation in one repo-local inline helper in `emit_fp_priv.h`, and use it for lookup and invalidation.

**M32-R4-12 — Follow-up kill handling contains unreachable fallback scaffolding**

- **Severity:** Low
- **Category:** YAGNI
- **Location:** `src/os/kill.c:232`
- **Evidence & Root Cause:** The fallback handles nonzero `mips_signal_pend()` results for real-time `SI_USER`. However, `src/os/sigqueue.c:126` explicitly returns success for that overflow case, making the fallback unreachable. `KILL_SI_QUEUE` at line 59 also has no use.
- **Concrete Fix:** Remove the unreachable fallback and unused macro. Keep overflow policy in `mips_signal_pend()`.

The CLEAN inspection found no source exceeding 900 lines; the largest is `src/dbt/emit_int.c` at 899. Searches found no forbidden string functions, `atoi`, or `.c` includes, and textual `x18`/`w18` matches were comments. Makefile warning flags match the requested set. These checks do not establish full C11 compliance or validate encoded register operands.

- [ ] **M32-R4-1:** Update every reservation bucket affected by bulk copyout.
- [ ] **M32-R4-2:** Route read/readv results through tracked copyout.
- [ ] **M32-R4-3:** Preserve the low word of DBT 64-bit conversion results.
- [ ] **M32-R4-4:** Preserve conversion Inexact state.
- [ ] **M32-R4-5:** Replace Darwin sub-pages without retaining old file backing.
- [ ] **M32-R4-6:** Validate backing continuity before mremap.
- [ ] **M32-R4-7:** Make Darwin population failure paths consistent.
- [ ] **M32-R4-8:** Honor `CLONE_CHILD_SETTID` independently of CLEARTID.
- [ ] **M32-R4-9:** Abort shadow writeback on baseline read errors.
- [ ] **M32-R4-10:** Fix mixed direct/shadow shared-mapping coherence.
- [ ] **M32-R4-11:** Centralize FPR cache indexing locally.
- [ ] **M32-R4-12:** Remove unreachable kill fallback and unused macro.