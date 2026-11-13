# Round-4 remediation review: `3eeec69` vs `1907d96`

**Scope and evidence.** Read the Round-4 audit, the full diff for the DBT, interpreter, signal, clone, Makefile, syscall, and test files, and the first ~750 lines of the `vm_file.c` diff. My last inspection turn failed on a shell glob, so I did **not** see the new `src/vm/vm_file_sync.c`, the tail of `vm_file.c` (unmap, protect, truncate, msync bodies), the fork-syscall call sites, or the symbol-collision checks. Items that depend on those are marked accordingly. No builds, tests, containers, or QEMU were run.

**Curated C11 compliance:** no `#include "*.c"` anywhere in `src/` or `tests/`. Largest touched files: `clone.c` 878, `test_u0_soft_tlb.c` 873, `vm_file_sync.c` 865, `fp.c` 828, `vm_file.c` 795. All ≤ 900, but three are within 40 lines of the cap.

## Item-by-item

**LA64-R4-1 (FCSR masked writes) — VERIFIED.** `src/dbt/emit_fp_mem.c:42` now emits `x11 = x11 BIC mask; x10 = x10 AND mask; x11 = x11 ORR x10` for all three selectors with masks `0x1F`, `0x1F1F0000`, `0x300`. That is exactly the interpreter's `(old & ~mask) | (in & mask)`. The reversed cause/flags recombination is gone.

**LA64-R4-2 (FTINT range checks) — REGRESSION in `fp_ftint_w`; the other three are fixed.** `src/interp/fp.c:316` checks `r > 2147483647.0f`. That literal is not representable in `float` and rounds to `2147483648.0f`. An input of exactly 2^31 (`0x4F000000`) now passes the check and reaches `(int32_t)r`, which is undefined behaviour, and `FE_INVALID` is never raised. The pre-fix strict `x < 2147483648.0f` was correct on that side. Fix: `r >= 2147483648.0f`. `fp_ftint_l`, `fp_ftint_wd`, and `fp_ftint_ld` use exactly representable bounds and are correct. NaN-first handling is correct.

**LA64-R4-3 (staged MAP_SHARED coherence) — PARTIAL (design unchanged, not inspected in full).** The fallback remains private arena storage populated by `pread` with explicit alias propagation. The commit message describes stronger dirt detection in `vm_file_sync.c` so flush/sync propagate alias stores, but the audit's core demand, genuinely shared backing for sub-host-page and cross-fork aliases, is not met by that architecture. I could not read `vm_file_sync.c`, so the propagation details are unverified.

**LA64-R4-4 (middle-unmap tail record) — NOT VERIFIED.** The unmap body lives in the part of the diff I did not reach. The commit message does not mention a head/tail split. Treat as open until someone confirms a second record is reserved and created.

**LA64-R4-5 (protection vs dirty tracking) — PARTIAL.** New per-record arrays `vmfile_dirty[]` and `vmfile_writable_ever[]` (`src/vm/vm_file.c:812`) track dirt independently of current protection, which addresses the "dirt survives write-removal" half. Whether `vmfile_note_protect()` now splits records at protection boundaries was not visible.

**LA64-R4-6 (truncate offset coordinates) — PLAUSIBLY FIXED, NOT VERIFIED.** The commit message states truncate now uses a byte-granular cut, intersects pages, retires to `COW_CLEAN`, and zeroes tracked bytes above EOF. That matches the requested fix. Body not read.

**LA64-R4-7 (child refcount race) — PARTIAL.** `vmfile_fork_reserve()` and `vmfile_fork_parent_done()` exist (`src/vm/vm_file.c:975`) and the child-side reset consumes the reservation. Two gaps:
- I could not confirm the fork syscall path actually calls `vmfile_fork_reserve()` before `fork` and `vmfile_fork_parent_done()` afterwards. Without callers the old racy path still runs.
- The non-reserved fallback in `vmfile_fork_child_reset()` increments any row that is `used`, without checking `dev`/`ino`. If the parent reclaimed the row and a different inode reused it, the child bumps the wrong row. That is the audit's "replacement row" case; only the `!used` case is repaired via `fstat`.

**LA64-R4-8 (process-local descriptors) — VERIFIED (core), with one leak.** Shared rows now store `host_fd = -1`; dups live in the process-local `vmfile_local_fds[]` and are closed in `vmfile_fini()`. One follow-up: in `map_bytes_in_place()`, the `vm64_protect` failure path wipes the record but never releases the refcount taken by `record_map_locked()`, so the inode row can never be reclaimed.

**LA64-R4-9 (MS_INVALIDATE discards dirt) — NOT VERIFIED.** `vmfile_msync()` body not reached. The syscall layer now rejects invalid flag combinations before calling it, but that does not by itself fix the writeback-before-invalidate ordering.

**LA64-R4-10 (guest msync translation) — PARTIAL.** `src/os/syscalls.c:700` adds flag translation, host-page alignment, and the Linux `MS_ASYNC|MS_SYNC` EINVAL rule, and guest alignment is validated before any writeback. Two concerns:
- It is a new `static long rt_host_msync()` in `syscalls.c`. The audit says the backend already exports `rt_host_msync()`. If `backend.h` declares it and is included here, this is a compile error. If not, it is a duplicated translation table under a misleading name. Either way it should delegate to the backend.
- Host `msync` still runs unconditionally on staged (anonymous) mappings. Harmless, but the audit asked to dispatch by backing type.

**LA64-R4-11 (backing changes under quiescence) — PARTIAL.** The map path now populates a temporary buffer, publishes with guest protection NONE, copies under `vm64_prepare_mutation()`, sets page state, commits, records, and only then raises protection (`src/vm/vm_file.c:1409` region). Peers can no longer read partial bytes. However:
- Peers that touch the range between the NONE publish and the final `vm64_protect()` take a fault. Unless the fault handler retries on a transient NONE state, a racing thread receives a spurious guest `SIGSEGV`.
- The unmap ordering (`vmfile_unmap()` before `vm64_unmap()` quiescence) was not visible and the message does not mention it.
- `map_bytes_in_place()` now `malloc`s the full mapping length as a staging copy. For a large private file mapping this doubles transient host memory and adds a full memcpy, a material regression against the previous direct `pread` into the arena. The dead `if (len <= 65536u)` branch suggests a chunked design was intended and not finished.

**LA64-R4-12 (SA_RESETHAND) — VERIFIED.** `src/os/sigframe.c:622` snapshots `*act` before resetting the disposition and redirects via the copy.

**LA64-R4-13 (pending consumption, async safety) — PARTIAL.** Delivery no longer clears both queues, and `sf_proc_pending` is accessed via `__atomic_*`. Remaining defect: `la64_host_signal_note()` sets the bit with `fetch_or` **before** writing `sf_proc_code[s]` and `sf_proc_addr[s]`, all relaxed. A poller on another thread can observe the bit and read stale metadata. Store the metadata first, then `fetch_or` with release, and load with acquire in `la64_signal_poll()`.

**LA64-R4-14 (failed clone cleanup) — VERIFIED.** All three failure paths call `la64_signal_thread_exit(child)` before freeing.

**LA64-R4-15 (fixture overread) — VERIFIED.** Writes `sizeof probe` then `ftruncate(fd, 100)`.

**LA64-R4-16 (backend selection in tests) — VERIFIED, with an unchecked link hazard.** `U0_TARGET_BACKEND` is defined before `U0_TEST_SRCS` and `RC_TEST_SRCS` consume it; `U0_DARWIN_BACKEND` now includes `safe_syscall_a64.S`. `backend_darwin_sync.c` now defines `la64_safe_syscall_pc_in_window()` and references `la64_safe_syscall_start/commit`. I could not check whether the `.S` or a fallback TU also defines that function (duplicate symbol) or whether the `.S` assembles under `-target arm64-apple-macos13`. The commit message implies the Darwin test binary linked, so this is likely fine.

**LA64-R4-17 (FP-mem classification DRY) — VERIFIED.** Single `static inline la64_fp_mem_classify()` in `src/dbt/dbt.h:117`; both consumers delegate. The `is_float` argument `(width == 4 && !store)` matches the old `FLD_S`/`FLDX_S` selection.

**LA64-R4-18 (unused `U0_LINUX_SRCS`) — VERIFIED.** Removed.

## Summary table

| Item | Status | Note |
|---|---|---|
| R4-1 | VERIFIED | masked merge for all 3 selectors |
| R4-2 | REGRESSION | `fp_ftint_w` upper bound: 2^31 float input is UB, no INVALID |
| R4-3 | PARTIAL | staged copy + propagate design retained; sync file not read |
| R4-4 | NOT VERIFIED | unmap body not reached; no mention of tail split |
| R4-5 | PARTIAL | dirt tracked independently; record splitting unverified |
| R4-6 | NOT VERIFIED | commit message matches fix; body not read |
| R4-7 | PARTIAL | reserve API exists; callers unconfirmed; wrong-row bump in fallback |
| R4-8 | VERIFIED | refcount leak on protect-failure path |
| R4-9 | NOT VERIFIED | `vmfile_msync` body not reached |
| R4-10 | PARTIAL | static `rt_host_msync` shadows/duplicates backend helper |
| R4-11 | PARTIAL | map path serialized; NONE-window faults; unmap order unseen |
| R4-12 | VERIFIED | |
| R4-13 | PARTIAL | metadata written after the pending bit, relaxed ordering |
| R4-14 | VERIFIED | |
| R4-15 | VERIFIED | |
| R4-16 | VERIFIED | Darwin link of `safe_syscall_a64.S` + new symbol unchecked |
| R4-17 | VERIFIED | |
| R4-18 | VERIFIED | |

## Newly discovered consequential follow-ups

1. **`fp_ftint_w` UB at exactly 2^31** (`src/interp/fp.c:316`). Use `r >= 2147483648.0f`. Add an oracle case for `0x4F000000` and `0xCF000000`.
2. **Full-length staging `malloc` in `map_bytes_in_place()`**. Large private file mappings now allocate and copy the whole range through the heap. Chunk the populate or stream `pread` under the mutation gate.
3. **Inode refcount leak** when `vm64_protect()` fails after `record_map_locked()` in `map_bytes_in_place()`.
4. **Wrong-row refcount bump** in the non-reserved branch of `vmfile_fork_child_reset()`: a `used` row is trusted without a `dev`/`ino` match.
5. **Signal metadata ordering** in `la64_host_signal_note()`: publish `sf_proc_code/addr` before the `fetch_or`, with release/acquire pairing.
6. **`rt_host_msync` name collision or duplication** in `src/os/syscalls.c`: confirm against `backend.h` and delegate to the backend version.
7. **Clone.c comment stripping.** The commit deletes the rationale comments for `ctid`/`tls` ordering, the SPEC 2.1 LL/SC rule, and futex dual-queue wakes, apparently to stay under 900 lines (now 878). That provenance should move to `docs/` rather than vanish.
8. **Oracle semantics to confirm** (pre-existing, not introduced here): QEMU's LoongArch `ftint` helpers return `0x7fffffff` / `0x7fffffffffffffff` for NaN and for overflow in both directions. The interpreter returns 0 for NaN and `INT_MIN` for negative overflow. Worth one difftest case before trusting R4-2 endpoint coverage.
