Repository: **loongarch64rt**  
HEAD: **`026e87d41bb403a85eabc4bb9327e1ada0adafe3`**

**Round-2 result: Round-1 remediation is incomplete.** The strongest remaining defects concern writable Soft-TLB publication, reservation invalidation, protection-update ordering, and Darwin directory cursors.

Seven batched shell inspections were used. Source inventory totals **29,213 production lines** and **39,814 lines including tests and experiments** across `.c`, `.h`, and `.S` files. Inspection covered selected paths through the remediation, interpreter, DBT, memory, signals, threading, backends, loader, tests, and Makefile. This is a bounded static audit, **not exhaustive verification of every line or module**. No builds, tests, emulators, or containers were run; no files were changed. `include/` is absent.

Round-1 changes visibly introduce execute-permission checks, independent read/write validation, mapping-hole checks, staged vector loads, LSX upper-half clearing, actual DBT difftest execution, shared JIT helpers, and separate compilation. The RAS was removed. No inspected source exceeds 900 lines; the largest is `src/interp/interp.c` at 861. However, the commit message’s claims about reference-counted directory cursors and atomic IBTC entries are not reflected in the inspected definitions.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 3 | 0 | 0 | 0 | 0 | 0 | 3 |
| Medium | 2 | 0 | 0 | 0 | 0 | 0 | 2 |
| Low | 0 | 0 | 0 | 0 | 1 | 1 | 2 |
| **Total** | **5** | **0** | **0** | **0** | **1** | **1** | **7** |

## 1. Bugs & Defects

### High

- [ ] **LA64-R2-1 — High — BUG — Read misses restore writable tags on translated code pages**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/dbt/dbt.c:487-502` (`translate_block`); `src/dbt/dbt_smc.c:136-143` (`dbt_smc_store`).
  - **What breaks / Why**: Translation revokes writable tags for code pages, but a subsequent **read** miss computes `writable` solely from guest mapping permissions and publishes that page’s `write_tag`. The code-page check runs only when servicing a store miss. Consequently, loading from an RWX code page can re-enable direct stores that bypass `dbt_smc_store`. Those stores do not bump the SMC epoch, allowing cached instructions to remain stale.
  - **Fix**: Apply the code-page write gate whenever publishing a writable tag, regardless of which access caused the fill. Keep code pages readable but never directly writable through this path. Cover translate → read miss → modify instructions → execute again.

- [ ] **LA64-R2-2 — High — BUG — Reservation protection checks an access while granting permission to an entire page**
  - **Where**: `src/dbt/dbt_mem.c:306-334` (`dbt_mem_miss_fill`); `src/interp/interp_amo.c:194-225` (`interp_step_amo`); `src/dbt/dbt_smc.c:151-163` (`dbt_revoke_write`).
  - **What breaks / Why**: LL revokes the page’s writable tag. The refill path refuses a store only if that particular access overlaps the current context’s reserved eight-byte range. A store elsewhere on the same page can refill the **whole page** as writable; a read miss can do so without checking the reservation at all. A later native store to the reserved address then bypasses reservation invalidation, allowing SC to succeed incorrectly. The refill check also considers only `ctx->ll_valid`, not reservations held by other contexts.
  - **Fix**: Gate writable publication at page granularity against every live reservation relevant to that mapping. Keep the page on the checked store path until reservations are cleared. Use one reservation policy across interpreter and DBT memory paths.

- [ ] **LA64-R2-3 — High — BUG — Mprotect releases the mutation transaction before updating host permissions**
  - **Where**: `src/os/mem_min.c:575-626` (`la64_mem_protect`); `src/os/mem_min.c:169-194` (`protect_host_page`).
  - **What breaks / Why**: The function updates guest protection metadata and calls `vm64_commit_mutation` before applying host-page protection changes. This puts the host synchronization outside the intended quiescent transaction. When permissions are relaxed, another worker can observe the new guest permission while the host page still denies access, producing a translator fault. If host `mprotect` fails, the function returns an error after publishing the new guest permissions, leaving inconsistent state.
  - **Fix**: Keep peers quiescent until host permissions and guest metadata agree. Stage protection changes, handle host failures with rollback or explicitly consistent partial state, then invalidate translations/TLBs and release the transaction.

### Medium

- [ ] **LA64-R2-4 — Medium — BUG — Fixed mmap silently rounds down invalid addresses**
  - **Where**: `src/os/syscalls_mem.c:212-231` (`sys_mmap`).
  - **What breaks / Why**: Both `MAP_FIXED` and the nonzero-address `MAP_FIXED_NOREPLACE` paths mask off the low address bits instead of rejecting an unaligned address. For `MAP_FIXED`, a malformed request can therefore replace an existing mapping at the preceding page boundary instead of returning `EINVAL`. This contradicts the series’ explicit syscall-alignment contract.
  - **Fix**: Validate page alignment before modifying mappings for either fixed-address flag. Reserve hint rounding for non-fixed mappings. Validate the zero-address `MAP_FIXED_NOREPLACE` case through the same fixed-address path.

- [ ] **LA64-R2-5 — Medium — BUG — Darwin directory cursors remain descriptor-local and can lose buffered entries**
  - **Where**: `src/os/darwin_dir.h:25-40` (`darwin_dir_slot_t`); `src/os/darwin_dir.h:53-105` (`darwin_dir_acquire`); `src/os/darwin_dir.h:125-147` (`darwin_dir_getdents64`).
  - **What breaks / Why**: The new cache retains pending entries for repeated calls on one descriptor, but it keys streams by numeric fd and creates a separate `DIR *` for each descriptor. Duplicated descriptors share the underlying directory offset while their libc buffers and pending entries remain separate. Alternating enumeration through aliases can therefore skip entries. Additionally, exhausting the cache silently closes slot zero, discarding its pending entry and buffered read-ahead; recreating that stream resumes from the advanced underlying offset.
  - **Fix**: Associate one reference-counted cursor with each shared open-file description and attach descriptor aliases to it. Do not evict a live cursor without preserving its logical position and buffered state; return a resource error if safe retention is impossible.

### Critical / Low

No additional findings established at these severities in this section.

## 2. Curated C11 & UB Issues

No additional standalone C11/UB finding met the evidence threshold within this inspection budget.

The inspected negative-immediate shift change moves the shift before the signed cast, addressing the previously reported signed-left-shift issue. Searches found no textual `.c` includes or calls to the listed banned string functions. Textual `x18` matches were comments and checks; this does **not** prove every generated instruction preserves the register.

The IBTC fields remain ordinary `uint64_t` and pointer fields, despite the remediation commit’s atomic-publication claim. A complete concurrency proof would require tracing scheduler serialization and signal interleavings; absence of atomics alone is not reported here as a proven data race.

## 3. DRY — Intra-Repo Duplication

No additional independently substantiated duplication finding is reported. The former duplicated JIT lifecycle now routes through repository-local helpers in `src/os/jit_wx.h`.

All proposed fixes remain within this standalone repository.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **LA64-R2-6 — Low — YAGNI — C IBTC lookup API has no production caller**
  - **Where**: `src/dbt/dbt_chain.c:49-56` (`dbt_ibtc_lookup`); `src/dbt/dbt.h:149` (declaration).
  - **What breaks / Why**: Production reference searches found only the definition and declaration. The trampoline probes the table directly, while `dbt_chain_next` uses `dbt_lookup_code`. This leaves an unused public lookup interface with a separate validation policy to maintain.
  - **Fix**: Remove the unused production API, or make its specific test-only purpose explicit and restrict its exposure accordingly.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **LA64-R2-7 — Low — CLEAN — Chaining documentation describes removed and nonexistent state**
  - **Where**: `src/dbt/dbt_chain.c:4-7`, `src/dbt/dbt_chain.c:21-22`; `src/dbt/dbt.h:136-146`.
  - **What breaks / Why**: Comments still describe a per-thread IBTC and a RAS. The IBTC is a process-global array without thread-local storage, and the RAS was removed in the remediation. These claims obscure the actual ownership and synchronization requirements during precisely the concurrency review the code needs.
  - **Fix**: Remove the RAS references and document the IBTC’s actual process-wide ownership, invalidation rules, and serialization assumptions.

The inspected file-size gate now includes `src/` and `tests/`, and static counts found no oversized source files. Complete FP/ISA semantics, file-backed alias coherence, clone/exec behavior, and asynchronous recovery remain unqualified by this bounded audit.