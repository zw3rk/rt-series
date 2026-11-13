# Round-4 post-remediation review: i686rt `1a16534` vs `ca4c9a2`

**Scope and method.** Static review only. I read the astra Round-4 report, the full diff of the remediation commit, and the post-fix context in `src/vm/vm32.c`, `src/os/sys_pass.c`, `src/rt32/rt32_vm_mmap.c`, and `src/vm/vm_file.c`. No build, test, container, or QEMU run. The diff output I captured was cut at 1500 lines, so the tail of the `vm_file.c` hunk, `vm_file.h`, and `tests/unit/test_u3_sites.c` were checked only through HEAD greps, not line by line.

**Overall result.** 10 of 12 items are verified. Two are partial. No regression that breaks previously working behaviour was found. Curated C11 hygiene holds: no `#include "*.c"` anywhere under `src/` or `tests/`, and the largest file is 898 lines.

## Per-item verification

**I686-R4-1, fork vs futex lock order: VERIFIED.**
`i686_vm32_fork_prepare` now takes the futex mutex first and the subpage mutex second, and the parent hook releases in reverse. That matches `FUTEX_WAIT`, which holds the futex mutex across `vm32_futex_load_u32` and its subpage window. The commit also fixed a second inversion the audit did not name: `robust_handle_death` in `src/os/clone.c` called the futex wake while holding the subpage lock. It now computes the wake decision, releases the subpage lock, then wakes. The global order is documented as VM spinlock, registry, futex, subpage. One point remains unverified within budget, listed under follow-ups.

**I686-R4-2, fork-shared metadata tables: VERIFIED.**
All three sub-page tables in `i686_vm_file_init` are now `MAP_PRIVATE | MAP_ANONYMOUS`. The map record array `s_maps` was already process-private. No other shared table exists in `vm_file.c`. The old header rationale that cited plan section 5.1.3 was removed rather than reconciled, see follow-ups.

**I686-R4-3, truncate writes into inaccessible pages: PARTIAL.**
What is fixed: `i686_vm_file_note_ftruncate` now takes the VM lock and iterates `s_maps` under it, calling the `_locked` worker, so there is no self-deadlock. Native mappings are never touched. Staged mappings carry a new per-record `staged` flag, set at `vm_mmap2_locked` and propagated through splits and replacement. Under A2 the shrink opens one host-aligned RW cover inside the subpage lock, checks the `mprotect` result, and widens back on both paths. On 4 KiB hosts each page is opened and restored individually.
What is not fixed: pages wholly beyond the new EOF are zeroed and marked `I686_PAGE_ANON` with their guest protection intact. That is exactly the "ordinarily readable zero pages" shape the audit asked not to implement. It also changes the old regrow behaviour. The previous code set those pages to COW-clean so a later regrow re-read file bytes. After this commit a shrink-then-regrow leaves stale zeros in a staged mapping permanently. Explicit EOF validity was not added.

**I686-R4-4, A2 remap copy through restored protections: VERIFIED.**
The copy now runs under the subpage lock with the VM lock already held. Source and destination covers are host-page aligned, both `mprotect` calls are checked, and failure widens only the covers that were opened before unmapping the provisional destination and returning `ENOMEM`. The non-A2 branch now checks the `PROT_READ` reopen as well. The old 4 KiB-aligned, unchecked `mprotect` is gone.

**I686-R4-5, file remap rollback losing the original record: VERIFIED.**
`i686_vm_file_replace_map` runs the planner with tracking required, duplicates the new owned descriptor, prepares all interior-split tail descriptors, and only then commits the untrack and inserts the replacement. Every fallible step precedes the first mutation. The caller in `rt32_vm_mremap` merges the `staged` flags of the original and extension records.

**I686-R4-6, process-global signal-action scratch: VERIFIED.**
`i686_gsig_tab` is gone. `i686_gsig_snapshot` and `i686_gsig_consume_oneshot` copy into caller storage under a new mutex. The handler word is additionally atomic so the async host bridge can read it lock-free, and every writer uses an atomic store under the mutex. Both delivery paths carry one snapshot through the decision, the one-shot reset, and the frame build. The reset-before-frame ordering matches the Linux kernel, which resets `SA_ONESHOT` in `get_signal` before frame setup. Delivery callers are the engine and interpreter loops, not the host signal handler, so taking a mutex there is safe. The fork child reinitializes the mutex. The frozen `i686_sigframe_build` export keeps its signature and still ignores the handler and restorer arguments as before.

**I686-R4-7, x87 logarithm domain: VERIFIED.**
I checked the cases by hand. `FYL2X` with a zero argument now yields infinity with the sign opposite to the multiplier, raising `#Z`, and a zero multiplier raises `#I`. Infinite argument yields infinity with the multiplier's sign. Unit argument with an infinite multiplier raises `#I`. `FYL2XP1` accepts `-1 < a < 0`, treats `a = -1` like the zero case, and rejects `a < -1`. The old sign reversal is gone. The expected `h_x87_math.c` sits well under the line ceiling.

**I686-R4-8, positioned I/O bypassing marshalling: VERIFIED.**
Both syscalls now reject a span that overflows the guest window, go through a 4 KiB stack buffer in chunks, and use the checked copy helpers. Short counts are preserved on host short I/O and on a guest copy fault after partial progress, which matches Linux. The `pwrite` bookkeeping hook still runs with the total written.

**I686-R4-9, Darwin copy_file_range offset: VERIFIED.**
The backend no longer uses `rt_host_sendfile`. With an explicit output offset it uses `pwrite` and leaves the descriptor position alone. Without one it uses `write` and advances. The input side uses `pread` and only seeks when no explicit input offset was given. Non-zero flags return `EINVAL`.

**I686-R4-10, x86_64 object rule headers: VERIFIED.**
The rule now depends on `$(HDRS)`.

**I686-R4-11, duplicated replacement planning: VERIFIED.**
One planner validates the span and counts splits and free slots. Preflight, untrack, and replace all use it. The untrack path now rejects zero-length and beyond-window spans too, which the audit noted as drift. The sole large untrack caller at `src/rt32/rt32_vm.c:738` passes a non-zero in-window span, so it is unaffected.

**I686-R4-12, unused registry setter: VERIFIED.**
The function and its comment are removed. No other references exist.

## Summary table

| Item | Topic | Status |
|------|-------|--------|
| R4-1 | Fork and futex lock order | VERIFIED |
| R4-2 | Fork-private metadata tables | VERIFIED |
| R4-3 | Truncate protection, EOF, sync | PARTIAL |
| R4-4 | A2 remap copy windows | VERIFIED |
| R4-5 | Transactional remap tracking | VERIFIED |
| R4-6 | Signal-action snapshots | VERIFIED |
| R4-7 | x87 logarithm semantics | VERIFIED |
| R4-8 | Positioned I/O marshalling | VERIFIED |
| R4-9 | Darwin copy offset | VERIFIED |
| R4-10 | x86_64 header deps | VERIFIED |
| R4-11 | Replacement planner | VERIFIED |
| R4-12 | Unused setter removed | VERIFIED |

Curated C11 check: no `#include "*.c"`; largest files are `src/os/sys_stat.c` at 898, `src/rt32/rt32_vm.c` at 895, `src/interp/h_alu.c` at 890, and `src/vm/vm_file.c` at 880 lines. All within the ceiling, though four files sit within 20 lines of it.

## Newly discovered consequential follow-ups

- **Beyond-EOF staged pages stay readable and lose regrow semantics (Medium, from R4-3).** `vm_file_shrink_locked` marks wholly-truncated staged pages `I686_PAGE_ANON` while leaving guest protection intact. A guest that reads past EOF gets zeros instead of a fault, and a later `ftruncate` growth never re-populates those pages from the file. The previous COW-clean marking at least restored file bytes on regrow. Add an explicit EOF-invalid state that faults on access and clears on regrow.

- **DBT invalidation now runs inside VM lock plus subpage lock (Low, unverified).** The new shrink helper calls `i686_dbt_invalidate_range` while holding both locks. Every `rt32_vm_*` caller invalidates JIT only after `rt32_vm_lock_release`, which suggests a convention. The pre-existing `note_pwrite` path already invalidates under the VM lock, so this is not new in kind, but the added subpage nesting is. Confirm the DBT cache lock is never held while a thread takes the subpage or VM lock.

- **`FYL2XP1` loses precision for small arguments (Low, pre-existing).** The default binary64 path computes `log2(a + 1.0)`. The instruction exists to avoid that cancellation. Use `log1p(a) * M_LOG2E`.

- **Darwin copy backend discards partial progress on error (Low).** After copying some bytes, a failing `pread` or `pwrite` returns a negative errno rather than the count copied. Linux `copy_file_range` reports the partial count. Return `done` when it is non-zero.

- **Large positioned writes are no longer single host calls (Low).** A `pwrite` above 4 KiB is now several host `pwrite` calls. Concurrent readers or writers on the same file can observe interleaving that a single kernel write would not expose.

- **Untrack commit swallows an impossible planner miss (Low).** When no free slot is found during an interior split, the loop continues without closing the prepared tail descriptor and leaves the original record spanning the hole. The planner makes this unreachable today. A defensive close and an assertion-free error return would make the invariant explicit.

- **Design note reconciliation (Low, docs).** The removed `vm_file.c` header cited plan section 5.1.3 as the reason for shared tables across fork. SPEC or the unification plan should record that this decision was reversed by R4-2.
