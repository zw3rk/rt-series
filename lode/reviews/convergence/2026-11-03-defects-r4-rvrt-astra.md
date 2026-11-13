Found **nine actionable issues** at `b1b08af`. The Round-3 snapshot fields, VMA growth, and hygiene prerequisite are present, but several correctness gaps remain.

Used **seven shell inspection calls**. Read no Markdown documents and ran no builds, tests, containers, or QEMU. Findings below are static conclusions; proposed regressions were not executed. Coverage included focused traces and broader source searches, not an exhaustive concurrency audit.

**RV-R4-1 — FP stores can write canonicalized operand bits**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt_emit.c:200`
- **Evidence & Root Cause:** `emit_load_unboxed_s()` (`src/dbt_emit_fp.c:184`) replaces an improperly boxed single operand with canonical NaN in the cache while leaving the architectural register unchanged in memory. It records a valid, clean single cache entry. `emit_inline_store()` subsequently trusts that entry: FSW copies its canonicalized low bits; FSD synthesizes a boxed single from it. For example, single arithmetic reading an unboxed `f1`, followed by `fsd f1,0(a0)` in the same block, stores different bits from architectural `f1`.
- **Concrete Fix:** Distinguish cached arithmetic operands from architectural register bits. For clean single operand caches, load raw store data from CPU state; only reconstruct boxed values when the cache represents an actual single-precision register write. Add FSW/FSD regressions after reading an improperly boxed operand without modifying it.

**RV-R4-2 — Inline self-loops lose sticky FP exceptions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt_emit.c:505`
- **Evidence & Root Cause:** JAL and conditional self-loop backedges jump to `loop_top_idx` before `emit_term_pc()` flushes FPSR. That label precedes the block’s first FP operation (`src/darwin_dbt.c:274`). Its emitted `emit_clear_fpsr()` instruction therefore clears FPSR again on every iteration. Exceptions raised only in earlier iterations disappear. Difftest mode sets the loop budget to one, avoiding this backedge and masking the failure.
- **Concrete Fix:** Flush accumulated FPSR into guest `fcsr` before each taken inline backedge, or disable FP self-loop optimization until entry and backedge flag handling are correct. Test an ordinary DBT loop whose first iteration raises an exception and whose final iteration does not.

**RV-R4-3 — Subpage protection removes neighboring mappings’ permissions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm64.c:400`
- **Evidence & Root Cause:** `protect_enclosing()` applies one mapping’s protection to its entire enclosing host page. On a 16 KiB host, map a 4 KiB RW subpage, then map its adjacent 4 KiB subpage read-only. The second operation makes both host subpages read-only. `rv_vm64_copyin()` accepts the first VMA as writable and reaches `memcpy()` at line 686, which faults. File mapping at line 554 and protection restoration at line 131 have the same neighbor-permission problem. The new regression exercises RO→RW replacement, not mixed surviving permissions.
- **Concrete Fix:** Compute host protection from all guest subpages sharing each host page, enforcing finer restrictions in software. Alternatively keep anonymous large-page arena backing RW and enforce guest permissions entirely through checked access paths. Add mixed RW/RO/PROT_NONE neighbor tests in both mapping orders.

**RV-R4-4 — Failed file replacement destroys existing VMA metadata**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:513`
- **Evidence & Root Cause:** `vma_remove_overlap()` runs before the fallible `rt_host_map_file()` or pread-based replacement. A closed positive FD passes the initial check; `file_valid_bytes()` suppresses its `fstat()` failure; mapping then fails after the original VMA has been removed. Original page states remain, but protection and inode associations are lost. On large-page hosts, the implementation additionally zeroes old contents before a possible pread failure.
- **Concrete Fix:** Stage and validate replacement backing before committing VMA removal and page states. Preserve the previous mapping on recoverable failures, including descriptor errors and interrupted/failed reads. Add failure-injection checks for preserved bytes, permissions, states, and inode associations.

**RV-R4-5 — New nonzero-offset regression fails on 4 KiB hosts**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `test/u5a_vm_provider.c:476`
- **Evidence & Root Cause:** The test requests page-aligned GVA `868352` with file offset `8000`. On the 4 KiB path, `head = 3904` and `map_gva = 864448` (`src/vm/vm64.c:505`), which is not page-aligned. The backend passes that address to `MAP_FIXED`, so the operation fails rather than satisfying the test’s required success. The pread path accepts the same input, creating backend divergence.
- **Concrete Fix:** Define and enforce a consistent alignment contract before any mutation. If arbitrary file offsets remain supported, use staged copying when GVA and file-offset alignment are incompatible. Otherwise reject them consistently and change this regression to a valid aligned nonzero offset, with a separate rejection test.

**RV-R4-6 — Failed protection widening still reaches `memset()`**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:126`
- **Evidence & Root Cause:** `zero_guest_range()` attempts to make read-only backing writable, but a failed `protect_enclosing()` merely leaves `widened == 0`. It then unconditionally writes through the original protection at line 129. The helper returns `void`, so truncate/regrow callers cannot propagate the failure and may continue publishing new page states.
- **Concrete Fix:** Return a status from the zeroing helper and stop before touching memory when widening fails. Propagate failure through the discard operation and avoid publishing successful state transitions for failed work. Add a protection-failure regression.

**RV-R4-7 — Generic signed-byte emission uses an unsigned load**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/dbt/emit_mem.c:65`
- **Evidence & Root Cause:** Width-one loads always select `RV_DBT_W_LDRB_BASE`, ignoring `is_signed`. Thus signed byte `0x80` becomes `0x80`, not `0xffffffffffffff80`. The big-endian width-one branch repeats the error. `test/u5b_dbt_mem.c:215` explicitly expects the incorrect unsigned opcode for a signed request. This emitter is separate from the Darwin inline-load implementation.
- **Concrete Fix:** Select the existing `RV_DBT_W_LDRSB_BASE` for signed byte loads in both branches. Correct the test expectation and add semantic checks for `0x7f`, `0x80`, and `0xff`.

**RV-R4-8 — Generic 16-byte accesses transfer only eight bytes**

- **Severity:** Medium
- **Category:** DEFECT
- **Location:** `src/dbt/emit_mem.c:71`
- **Evidence & Root Cause:** The public emitter accepts width 16 and records that width in site metadata, but emits one `LDR X` or `STR X`. Big-endian cases likewise transfer and reverse only eight bytes. `test_emit_shapes()` includes width 16 but checks emitted shape rather than a complete 16-byte transfer. Inspected call sites are tests, so this is a latent emitter-contract defect rather than evidence of current RV64GC execution corruption.
- **Concrete Fix:** Reject width 16 until the API can describe a register pair or vector operand and emit the complete transfer. Update acceptance tests accordingly; implement full-width access only when an actual consumer requires it.

**RV-R4-9 — Slow-path cache reload sequences are duplicated**

- **Severity:** Low
- **Category:** DRY
- **Location:** `src/darwin_dbt_emit.c:172`
- **Evidence & Root Cause:** Inline load and store slow paths separately emit the same GPR reload loop, FPR reload loop, precision selection, and TLB-tag poisoning sequence; the second copy starts at line 244. These sequences encode shared register-cache invariants that must change together.
- **Concrete Fix:** Extract one repo-local emitter helper for restoring live register caches after a helper call and invalidating the retained TLB tag. Keep load-specific snapshot restoration at its call site.

The inspected source trees had no files exceeding 900 lines, prohibited string-function calls, or textual `.c` includes. The `x18` search found comments and a RISC-V guest fixture, not an AArch64 violation. No sufficiently supported standalone YAGNI or CLEAN finding emerged.

- [ ] **RV-R4-1:** Preserve architectural FP bits in FSW/FSD after operand unboxing.
- [ ] **RV-R4-2:** Preserve sticky FP flags across inline self-loop backedges.
- [ ] **RV-R4-3:** Preserve neighboring subpage permissions on large-page hosts.
- [ ] **RV-R4-4:** Make failed file replacement preserve existing mapping state.
- [ ] **RV-R4-5:** Resolve nonzero-offset alignment divergence and its regression.
- [ ] **RV-R4-6:** Propagate zeroing protection failures before writing.
- [ ] **RV-R4-7:** Emit sign-extending signed-byte loads.
- [ ] **RV-R4-8:** Reject or fully implement 16-byte memory emission.
- [ ] **RV-R4-9:** Unify slow-path register-cache reload emission.