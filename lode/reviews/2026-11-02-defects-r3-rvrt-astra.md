Reviewed `dab0b91` with six shell inspection turns. No builds, tests, containers, or QEMU were run. Findings below are static conclusions; the bounded review does not establish correctness of unexamined paths.

**RV-R3-1 — Dynamic-rounding slow path flushes uninitialized FPSR**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt_emit_fp.c:393`; `src/dbt_emit_fp.h:339`
- **Evidence & Root Cause:** The pre-instruction snapshot restores FPR cache metadata but omits `fpsr_dirty`. When the first FP instruction uses dynamic rounding, its guard branches before `emit_clear_fpsr()` executes. Emitting the fast path nevertheless sets `fpsr_dirty`, so the slow tail flushes host FPSR into guest `fcsr`. The trampoline does not clear FPSR on entry. Host or previous-block exception flags can therefore contaminate guest flags. The FPR snapshot repair itself is appropriate because the helper path exits.
- **Concrete Fix:** Preserve and restore FPSR initialization/dirty state at each slow-path branch point. Emit a flush only if that execution path has accumulated guest flags. Add a regression with nonzero host FPSR, clear guest flags, and an exact dynamic-rounding instruction with non-RNE `frm`.

**RV-R3-2 — Underflow correction erases earlier instructions’ sticky flags**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/dbt_emit_fp.c:313`
- **Evidence & Root Cause:** FPSR accumulates flags across a block. `emit_uf_fix()` checks that cumulative UFC bit and clears it whenever the current multiplication produces a normal result. An earlier underflow-producing instruction followed by an ordinary static-RNE `FMUL.S` can consequently lose its required UF flag before block-exit accumulation.
- **Concrete Fix:** Preserve previously accumulated flags separately before correcting the current instruction’s flags, or flush and clear FPSR before the operation requiring correction. Test an underflowing operation followed by an exact normal multiplication in the same block.

**RV-R3-3 — Emitter rollback retains state from discarded instructions**

- **Severity:** High
- **Category:** BUG
- **Location:** `src/darwin_dbt.c:294`
- **Evidence & Root Cause:** On overflow or `RV_DBT_EMIT_STOP_BEFORE`, compilation restores only the word count and exit-patch count. FPR dirty bits, register tags, boxing knowledge, FPSR state, and other emitter metadata remain modified by the discarded instruction. The subsequently generated exit flush can store a host register using the wrong guest tag or omit a necessary store.
- **Concrete Fix:** Snapshot all mutable emitter state before attempting an instruction and restore it when discarding that instruction. Reserve enough space for exit emission. Add a boundary regression with dirty FPRs and an instruction that exhausts the emission buffer.

**RV-R3-4 — VMA capacity exhaustion silently loses surviving mappings**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:162`; `src/vm/vm64.c:334`
- **Evidence & Root Cause:** Splitting an overlapping VMA drops its surviving tail when all 64 slots are occupied. The backing and page states remain, but inode association and protection metadata disappear. Separately, mapping functions modify backing and states before `vma_add()` can return `-ENOSPC`. Failed mappings can thus leave changed memory without matching metadata. These are provider-level defects; this review does not establish their reachability through the main runtime.
- **Concrete Fix:** Preflight and reserve all required VMA slots before changing backing or metadata. Return a capacity error without mutation, or grow the table. Test middle-range removal and mapping failure with a full table.

**RV-R3-5 — Large-page file mapping retains bytes beyond EOF**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:393`
- **Evidence & Root Cause:** The large-host-page fallback copies file contents into existing arena backing. When `pread` returns zero, it stops without clearing the remaining destination bytes, then marks every page `COW_CLEAN`. Replacing populated memory with a shorter file therefore retains old bytes in the partial EOF page; whole pages beyond EOF also lack the promised fault state.
- **Concrete Fix:** Initialize replacement backing, zero the partial EOF tail, and mark whole pages beyond EOF appropriately before publishing the mapping. Add a populated-arena-to-short-file replacement regression on a large-page host.

**RV-R3-6 — Subpage remapping can write into read-only host backing**

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm64.c:128`; `src/vm/vm64.c:325`
- **Evidence & Root Cause:** `prepare_writable()` changes protection only when the requested address is host-page aligned. On a 16 KiB host, mapping a read-only range at an aligned address protects the encompassing host page. A subsequent 4 KiB anonymous remap at offset 4096 skips protection widening and executes `memset()` against that read-only page. The file-copy fallback has the same alignment assumption.
- **Concrete Fix:** Manage protection over enclosing host pages while retaining precise guest permissions in metadata. Propagate protection failures before touching memory. Test remapping each 4 KiB subpage of a read-only 16 KiB host page.

**RV-R3-7 — Source hygiene gate is absent from `make check`**

- **Severity:** Low
- **Category:** CLEAN
- **Location:** `Makefile:8759`
- **Evidence & Root Cause:** `check-line-limits` exists as a standalone target but is not a prerequisite of `check`. Routine checks therefore do not enforce the newly stated line-count and textual-include rules.
- **Concrete Fix:** Add `check: check-line-limits`. The direct inspection found no first-party `.c`, `.h`, or `.S` files above 900 lines and no prohibited string calls or textual `.c` includes. The observed assembly `x18` use is a RISC-V guest fixture, not an AArch64 platform-register violation.

No additional DRY or YAGNI finding was established with sufficient evidence in this inspection budget.

- [ ] **RV-R3-1:** Restore path-specific FPSR state for dynamic-rounding helpers.
- [ ] **RV-R3-2:** Preserve prior sticky underflow flags.
- [ ] **RV-R3-3:** Restore complete emitter state on rollback.
- [ ] **RV-R3-4:** Make VMA capacity failures transactional.
- [ ] **RV-R3-5:** Clear EOF tails and classify beyond-EOF pages.
- [ ] **RV-R3-6:** Handle writable backing at host-page granularity.
- [ ] **RV-R3-7:** Include source hygiene enforcement in `make check`.