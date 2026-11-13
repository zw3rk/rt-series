# Round-4 remediation review — `a32rt` `14f1872` vs `5561e7e`

Static review only. No builds, tests, containers, or QEMU were run. Four tool turns were used: the audit report, the commit diff, the post-fix sources for `vm_mremap.c`, `vm_file_map.c`, `vm_file.c`, `vm.c`, `backend_darwin.c`, `os_sys_fork_time.c`, `signals.c`, `main.c`, and a tree-wide line-count and unity-include scan.

## Compliance and cross-cutting observations

- **Curated C11 structure**: no `#include "*.c"` anywhere under `src/`, `include/`, `tests/`. Every source file is at most 899 lines. Two files sit at the limit: `src/signals.c` at 899 and `src/vm.c` at 884. The `vm_file.c` split into `vm_file_map.c` with tables shared through `vm_priv.h` is clean: storage stays in one TU, the other TUs see `extern` declarations, and the lock is shared rather than duplicated.
- **No regression tests were added.** The commit touches only `src/`. Every one of the nine audit items ended with a concrete "Add regressions for …" requirement. None of those appeared. Every status below is therefore a code-level verdict, not a tested one.
- **Dead code introduced**: `copyout_commit_range` and `copyout_commit_iov` in `src/os/sys_priv.h:529-558` have no callers. Only `guest_write` uses the new `a32_vm32_copyout_invalidate`. They are `static inline`, so they compile silently. Either wire them into the `read`/`readv` kernel-direct paths they describe, or drop them.

## Per-item verification

**A32-R4-1 — Repeated private `mremap` loses backing: VERIFIED.**
`a32_vmfile_lookup_private_span` (`src/vm/vm_file_map.c:304`) walks contiguous records, requires matching `(dev, ino)` and a contiguous file offset, and returns 1/0/negative errno. `mremap_priv_lookup` (`src/vm/vm_mremap.c:56`) propagates negative results and the caller returns them to the guest instead of falling back to anonymous (`vm_mremap.c:164-171`). After in-place growth, `a32_vmfile_coalesce_private` (`vm_file_map.c:404`) merges the extension record back, closing the extension's duplicate descriptor. The grow→grow and grow→move chains the audit described now resolve. Minor: the span walk is O(slots) per step, which is fine at 1024 slots.

**A32-R4-2 — Darwin anonymous replacement retains old storage: PARTIAL.**
The host-page-aligned branch (`src/os/backend_darwin.c:98-112`) now installs a fresh `MAP_FIXED` anonymous mapping, which correctly detaches from a shared file and zero-fills `PROT_NONE` replacements. Two problems remain in the sub-page branch (`backend_darwin.c:120-154`):
- It reads the whole host page with `memcpy(saved, start, hlen)` without widening protections first. The old code did an `mprotect(..., RW)` before touching the page. On a 16 KiB Darwin host, `a32_backend_protect` keeps guest pages RW, so most siblings are readable, but a sibling that is a private file mapping installed with host `PROT_NONE` through `a32_backend_map_file`, or an EOF-cut page, would fault inside the translator with signals possibly blocked. I could not confirm within budget whether such a sibling can exist; treat it as an open hazard and add the RW widening back before the snapshot copy.
- A `shared != 0` request whose start is aligned but whose length is not a host-page multiple passes the `-EINVAL` guard at line 90 and falls into the sub-page branch, which always maps `MAP_PRIVATE` with `VM_INHERIT_COPY`. If any shared anonymous request can reach this branch, the sharing is silently lost. Returning `-EINVAL` for `shared != 0` in the sub-page branch is a cheap, safe hardening regardless of whether the path is currently reachable.

**A32-R4-3 — Fork resumes parent before restoring protections: VERIFIED.**
`a32_jit_fork_parent()` now runs after the restore loop for both the success and failed-fork paths (`src/os/os_sys_fork_time.c:466-510`). Restore failures are recorded and reported to stderr. The decision to still reopen execution after a failed restore is documented and is the right call versus deadlocking every future JIT user.

**A32-R4-4 — Fork snapshot reads inaccessible EOF pages: VERIFIED, with a note.**
Snapshot copying is now per 4 KiB page and skips `a32_vm32_page_eof_cut` pages (`os_sys_fork_time.c:385-405`). Child and parent restores keep cut runs at `PROT_NONE` and only widen non-cut runs. Note: the restore loops call raw `mprotect` at 4 KiB granularity, as the pre-existing code did. On a 16 KiB host a non-aligned run returns `EINVAL`; the parent now surfaces that as the new "protection restore failed" message, so the diagnostic may be noisy there. Routing through `a32_backend_protect` would centralize the host-page policy.

**A32-R4-5 — Same-start prefix defeats capacity preflight: VERIFIED.**
`a32_vmfile_check_replace` (`src/vm/vm_file.c:115`) now counts a record as freed only when fully covered, and `need = 1 + middle_splits` unconditionally. The call order in `a32_vm_mmap_locked` is preflight (`vm.c:687`) → transactional retire (`vm.c:698`) → `check_record` (`vm.c:707`), which is correct. Minor: `a32_vmfile_preflight_unmap` does not credit to-be-freed fully covered slots, so a full table can pass `check_replace` and then be refused by the retire. That is a safe conservative refusal, not corruption.

**A32-R4-6 — Failed backing splits silently preserve records: VERIFIED.**
`a32_vmfile_unmap_shared` (`vm_file.c:626`) counts needed slots, reserves every duplicate descriptor before any mutation, and unwinds fully on failure. The reservation and consumption loops apply the same predicate in the same index order, and right halves inserted during mutation can never match the middle-split predicate, so the `si`/`fi` pairing holds. `vm_unmap_regions_locked` now runs the preflight and retire first and returns an error; `a32_vm_unmap_locked`, `a32_vm_brk`, `a32_vm_mmap_locked`, and the mremap move path all propagate it, and mremap rolls back the new mapping (`vm_mremap.c:287-296`). One ordering trade-off: `a32_vm_unmap_locked` now retires metadata before `vm_reserve_prot_none`, so a reserve failure leaves the host mapping present with metadata already dropped. Reserve can now fail with `-ENOMEM` on Darwin via the new sub-page `malloc`. Low risk, worth a comment.

**A32-R4-7 — Exec signal variables survive in guest environment: PARTIAL.**
The defect is fixed: transport entries are consumed and the guest stack is built from a filtered copy (`src/main.c:112-121`), and both exec branches strip stale triples (`src/os/os_sys_sig_time.c:678-698`). Two side effects of the fix need attention:
- `exec_signal_restore` now runs before `a32_signals_init`. The restore installs host handlers for masked and ignored signals and marks them in `g_host_handler_installed_mask`; `a32_signals_init` then sets that mask to zero (`src/signals.c:598`) and reinstalls only the monitored set. Handlers for non-monitored signals such as realtime signals stay installed in the kernel but are no longer recorded. I could not confirm a consumer that depends on the mask, so this is a latent inconsistency rather than a confirmed fault. The clean fix is to order `a32_signals_init` → `exec_signal_restore` → filter → `a32_stack_setup` → `a32_jit_init`; signal init has no dependency on the guest stack.
- The native exec branch now copies into a fixed `native_envp[520]` and stops at 519 entries. Previously the guest environment was passed through unbounded. A guest with more than 519 environment variables now silently loses entries when exec'ing a native binary.

**A32-R4-8 — VMA exhaustion makes partial `mprotect` alter metadata: VERIFIED.**
`vm_mprotect_preflight_locked` (`src/vm.c:706`) counts two entries per middle split and one per edge split and refuses with `-ENOMEM` before `a32_vm32_protect` touches host permissions (`vm.c:785-790`). The fallback `r->prot = prot` widening is gone from all three branches; the middle-split branch restores `orig` on the impossible failure path.

**A32-R4-9 — Epoll output validation covers one event: VERIFIED.**
`epoll_out_ok` (`src/os/os_sys_fs_arm.c:98`) validates `maxevents * sizeof(struct epoll_event)` with `PROT_WRITE`, shared by both branches and Linux-guarded consistently with the dispatch.

## Summary

| Item | Status | Note |
|---|---|---|
| A32-R4-1 | VERIFIED | Span lookup, coalesce, error propagation all present |
| A32-R4-2 | PARTIAL | Sub-page branch: no RW widening before snapshot read; shared request can be silently privatized |
| A32-R4-3 | VERIFIED | Restore precedes JIT reopen on both paths |
| A32-R4-4 | VERIFIED | Raw 4 KiB `mprotect` may be noisy on 16 KiB hosts |
| A32-R4-5 | VERIFIED | Conservative mismatch with retire preflight is safe |
| A32-R4-6 | VERIFIED | Unmap ordering trade-off noted |
| A32-R4-7 | PARTIAL | Signal-init ordering clears installed-handler mask; native env capped at 519 entries |
| A32-R4-8 | VERIFIED | Preflight before host mutation |
| A32-R4-9 | VERIFIED | Full extent validated |

Newly discovered consequential follow-ups:

1. **No regression tests for any of the nine items.** The commit is src-only. Each audit entry's requested regression is still outstanding; the verdicts above are unexercised.
2. **R4-7 ordering**: move `a32_signals_init` ahead of `exec_signal_restore` so the installed-handler mask is not zeroed after restore. Trivial reorder.
3. **R4-7 native exec**: the 519-entry cap on the native environment is a new behavioral regression. Size the buffer from the input or allocate dynamically.
4. **R4-2 sub-page branch**: widen the host page to RW before the snapshot `memcpy`, and reject `shared != 0` in that branch instead of silently mapping private.
5. **Dead helpers**: `copyout_commit_range` and `copyout_commit_iov` are unreferenced. Wire them into the kernel-direct read paths they document, or remove them.
