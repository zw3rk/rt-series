# Round-5 Post-Remediation Verification — `a32rt` @ `39a81d6`

Scope: static verification only (4 read-only tool turns: defect card + `git show 39a81d6`, then targeted `sed`/`grep`/`wc`). No build, tests, Docker, or QEMU were run. Working tree is clean at `39a81d6`.

**Headline:** 8 of 10 items VERIFIED, 2 PARTIAL (A32-R5-1, A32-R5-2). No REGRESSION found in the fix commit itself, but A32-R5-6 introduces one new hazard worth a Round-6 card. No Round-5 item received a regression test; every astra card asked for one.

| Item | Verdict | Evidence |
|---|---|---|
| A32-R5-1 exec-permission fetch | **PARTIAL** | `src/interp/interp.c:133-141`, `:148`, `:159` |
| A32-R5-2 Darwin sub-page shared siblings | **PARTIAL** | `src/vm.c:690-704`, `src/os/backend_darwin.c:114-116` |
| A32-R5-3 sendmsg writes input header | **VERIFIED** | `src/os/os_sys_sock.c:559-562` |
| A32-R5-4 ancillary data dropped | **VERIFIED** | `src/os/os_sys_sock.c:491-518`, `:550`, `:616` |
| A32-R5-5 large select overrun | **VERIFIED** | `src/os/os_sys_sock.c:628-632`, `:681-728`, `:738-763` |
| A32-R5-6 STREX ABA race | **VERIFIED** (new hazard, see below) | `src/vm/vm32.c:427-437`, `:445-455`, `:474-481`, `:499-540` |
| A32-R5-7 mremap prot failures / rollback | **VERIFIED** | `src/vm/vm_mremap.c:85-121`, `:279-304`, `:312-316` |
| A32-R5-8 reservation invalidation DRY | **VERIFIED** | `src/interp/interp.c:128`, `src/signals.c:281` |
| A32-R5-9 unused `tlb_probe` | **VERIFIED** | removed from `src/vm/vm32.c` and `src/vm/vm32.h`; zero remaining references in `src/ include/ tests/ docs/` |
| A32-R5-10 tautological predicate | **VERIFIED** | `src/interp/interp_a32.c:164-165` |

## Per-item notes

**A32-R5-1 — PARTIAL.** A dedicated `i_fetch_bytes()` now requests `PROT_EXEC` and both `i_fetch32`/`i_fetch16` route through it, so R-only data no longer executes and X-only pages fetch. Fault PC is the aligned fetch address, correct for A32 and for each Thumb halfword. Two gaps: (1) the enforcement depends on `a32_guest_range_ok()` honoring the exec bit; `a32_vm32_range_prot_ok()` (`src/vm/vm32.c:302-321`) masks `req_prot & 0x7` against the per-page table, which is right, but I could not locate `a32_guest_range_ok`'s body in `src/vm.c` within budget to confirm it delegates there. (2) No A32/Thumb X-only or R-only fixture was added. Downgrade to VERIFIED once (1) is confirmed and a fixture lands.

**A32-R5-2 — PARTIAL.** The new guard in `a32_vm_mmap_locked` (`src/vm.c:691-704`) rejects a private replacement with `-EINVAL` when any 4 KiB sibling in the first/last host page outside the target is a tracked shared mapping. This is the "reject before retiring" option and fires before the retire step, as requested. Concerns: (a) `a32_vmfile_lookup_shared(start_gva, ...)` is named and used elsewhere (`src/vm/vm_mremap.c:164`) as a lookup keyed by mapping *start*; if it does not match interior pages, a sibling in the middle of a 16 KiB shared mapping is missed and the original defect persists for that case. (b) Only file-tracked shared mappings are consulted; `MAP_SHARED|MAP_ANONYMOUS` siblings are not covered unless `vm_file.c` tracks them. (c) The Darwin backend change is comment-only (`backend_darwin.c:114-116`); correctness rests entirely on the `vm.c` guard. (d) No second-mapping or `fork()` visibility test. Needs a one-line confirmation of lookup semantics or a range-walk variant.

**A32-R5-3 — VERIFIED.** `msg_namelen`/`msg_flags` copy-out is now gated on `nr == ARM_NR_recvmsg` (`:559`); `recvmsg` headers are already validated `PROT_READ|PROT_WRITE` at `:475-476`.

**A32-R5-4 — VERIFIED.** A pre-pass walks the guest cmsg chain with the same stride as the conversion loop, validates each `cmsg_len`, sums `CMSG_SPACE`, caps at 64 KiB (`ENOBUFS`), and mallocs when the 1 KiB stack buffer is too small. The silent `break` is gone. `cbuf_dyn` is freed on the iov-failure path and after the syscall; the only `FAIL_*` returns between allocation and free do not exist (name/control validation happens earlier at `:481-485`). The `recvmsg` side still caps host control at 1 KiB; that is pre-existing and outside this item.

**A32-R5-5 — VERIFIED.** Full `fd_bytes32` spans are validated for all three sets (`:628-632`), sets above 16 MiB are rejected `EINVAL`, and the `> 1024` path now uses zeroed host-word-rounded malloc buffers with copy-in/copy-out of exactly `fd_bytes32` bytes; all allocations are freed on every path. Host-side `FD_SETSIZE` limits on Darwin `pselect` are out of scope. Minor: `fd_chk` at `:628` is redundant once the `EINVAL` check at `:629` has run.

**A32-R5-6 — VERIFIED, with a new hazard.** A global `atomic_flag` spinlock now encloses `ll_record`, `reservation_bump`, `copyout_invalidate`, and the whole validate-then-CAS sequence in `sc_attempt`. All early `return false` paths precede `res_lock()`; every `goto consume` path unlocks. Interpreter stores and signal-frame writes go through `copyout_invalidate`, so the A→B→A window described in the card is closed for those writers. **Hazard:** the spinlock is not async-signal-safe. `deliver_guest_signal()` (which takes the lock via `copyout_invalidate`, `signals.c:281`) is called from `signals.c:496`, which sits inside the region following `host_sig_handler` at `:426`. If a host SIGSEGV/SIGBUS fires while the same thread holds `g_res_lock` inside `sc_attempt` (the guest-memory load/CAS at `vm32.c:509-531` touches guest pages directly), and the handler synchronously delivers a guest signal, the thread spins on its own lock. Whether this is reachable depends on whether `interp_a32.c:56` pre-validates `PROT_WRITE` before `sc_attempt`, which I did not confirm. Recommend a Round-6 card: either pre-validate and document, or make the signal path skip the lock. Also note DBT-emitted stores are not serialized by this lock; the card scoped the race to interpreter stores, so that is a follow-up, not a defect in this fix.

**A32-R5-7 — VERIFIED.** `mremap_copy_prefix` returns the first failed `a32_backend_protect` rc; the caller requires success of widen, copy, and final `a32_vm_protect_locked` before retiring the source, and on any failure restores source protection (when widened), unmaps the destination, releases `priv`, syncs, and unlocks (`:293-304`). The retire-failure rollback now also restores source protection (`:312-316`). Unverified: whether `a32_backend_protect` returns `-errno` (what the guest will see via `return (uint32_t)pre_rc`) or `-1`. No injected-failure test.

**A32-R5-8 — VERIFIED.** Both duplicate loops are replaced by `a32_vm32_copyout_invalidate`. The helper now inlines the bump under the lock (avoiding recursive locking), which leaves `a32_vm32_reservation_bump` with no callers outside `vm32.c` though still exported at `vm32.h:169`. Harmless; candidate for removal.

**A32-R5-9 / A32-R5-10 — VERIFIED.** Clean removals; no stale references, no behavior change.

## Hygiene

- **Curated C11:** Makefile keeps `-std=c11 -Werror -Werror=vla -pedantic -Wall -Wextra` (`Makefile:45`). The diff uses `<stdatomic.h>` `atomic_flag` (C11, permitted; no `<threads.h>`), `malloc`/`free`, `memcpy` with validated bounds. No VLAs, Annex K, `_Generic`, or banned string functions. The `vm.c:694-701` guard packs multiple declarators and a one-line `if (...) continue;` per line; legal but below the repo's usual readability bar.
- **Line limits (≤ 900):** all nine touched files pass. `src/vm.c` is at **899** and `src/signals.c` at **897**; both will breach on the next edit. Recommend splitting before Round 6 (e.g. move the R5-2 guard and gap logic out of `vm.c`).
- **Tests:** the commit touches no files under `tests/`. All ten cards requested regression coverage; none was added. This is the largest remaining gap across the round.

## Recommended Round-6 cards

1. Confirm `a32_vmfile_lookup_shared` interior-page semantics (or walk regions) and cover anonymous shared siblings; add second-mapping + `fork()` test (R5-2).
2. Confirm `a32_guest_range_ok` exec-bit delegation; add X-only / R-only A32 and Thumb fixtures (R5-1).
3. Address `g_res_lock` reentrancy from `host_sig_handler` (R5-6 follow-up).
4. Regression tests for R5-3/4/5/7 as specified in the astra card; pre-split `vm.c` and `signals.c`.
