Round 3 found **7 actionable defects** at `00ea803`. Review used six shell inspection turns; no builds, tests, Docker, or QEMU ran. Findings are static, not runtime-verified.

Inspected the five latest commits, Round-2 and post-fable diffs, mapping/DBT/thread/signal/backend paths, selected tests, and `Makefile`. `include/` is absent. Inspected `.c`, `.h`, and `.S` files stay below 900 lines; required compiler flags are present.

The suspected SMC hash-collision issue did **not** survive tracing: unmap invalidates the entire block-cache epoch, forcing surviving blocks to be translated and marked again. It is excluded below.

### LA64-R3-1 — Thread signal state is process-global

- **Severity:** High
- **Category:** BUG
- **Location:** `src/os/sigframe.c:51`
- **Evidence & Root Cause:** `sf_blocked`, `sf_pending`, pending metadata, and alternate-stack state are global variables. `la64_sigprocmask_sys()` ignores `ctx` and changes the shared mask. Consequently, one guest thread blocking a signal changes delivery for every thread; installing an alternate stack changes where other threads receive handlers. Cooperative scheduling does not correct this state ownership error.
- **Concrete Fix:** Put masks, thread-directed pending signals, and alternate-stack state in per-thread guest state. Keep shared dispositions separate. Implement clone inheritance explicitly, including alternate-stack clearing where required by clone flags. Add a two-thread regression with different masks and alternate stacks.

### LA64-R3-2 — Shared mapping fallback silently becomes a private snapshot

- **Severity:** High
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:267`; `src/os/syscalls_mem.c:170`
- **Evidence & Root Cause:** The shared-map fallback calls `map_bytes_in_place()`, which populates anonymous arena backing with `pread`. The outside-arena route likewise allocates anonymous memory and copies file bytes. Recording `shared = 1` does not make these bytes shared with the file or another mapping. The comment promises synchronization on `msync/write/ftruncate/munmap`, but the inspected implementation contains no corresponding `pwrite` writeback. On Darwin, valid 4 KiB mappings that do not satisfy host-page alignment reach this fallback.
- **Concrete Fix:** Implement coherent shared backing for these placements, including alias visibility and file synchronization. Until supported, fail unsupported placements explicitly instead of returning successful `MAP_SHARED` mappings with private behavior. Test two aliases plus file reads after a mapped write.

### LA64-R3-3 — Failed file mapping leaves a live, untracked mapping

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/vm/vm_file.c:192`
- **Evidence & Root Cause:** `map_bytes_in_place()` commits `vm64_map()` before reading the file or registering the map. A later `pread` error, page-state failure, or full record table returns an error without undoing the mapping. The direct shared-overlay path also returns at line 264 without cleanup when `record_map()` fails. A failed guest `mmap` can therefore consume address space and leave accessible backing without its file record.
- **Concrete Fix:** Reserve bookkeeping capacity before publishing mappings and unwind every subsequent failure. Remove the VM mapping, restore arena backing after overlays, and release newly acquired resources. Add fault-injection coverage for read failure and record-table exhaustion.

### LA64-R3-4 — `mmap` skips essential argument validation

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/syscalls_mem.c:212`
- **Evidence & Root Cause:** `file_backed` requires both absence of `MAP_ANONYMOUS` and `fd != -1`. Thus a non-anonymous mapping with `fd == -1` becomes an anonymous allocation instead of returning `EBADF`. The entry point also does not validate the mapping type or guest-page alignment of the file offset. Copy-based file mapping routes accept offsets that the guest ABI should reject. These checks must precede destructive `MAP_FIXED` replacement.
- **Concrete Fix:** Determine file-backed status solely from `MAP_ANONYMOUS`; validate the descriptor separately. Validate supported mapping types and offset alignment before selecting or removing mappings. Add cases for `fd == -1`, absent mapping type, and offset `1`.

### LA64-R3-5 — Duplicating an unread directory loses shared cursor identity

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/darwin_dir.h:160`
- **Evidence & Root Cause:** The post-fable change records a duplicate only when `oldfd` already has a cursor. For `open(directory); dup(fd); getdents64(fd); getdents64(duplicate)`, each descriptor later acquires a separate buffered `DIR *`. Although host duplicates share their underlying offset, their userspace buffers and pending entries are independent. Alternating reads can skip entries or report premature EOF. The full-table branch at line 184 similarly returns silently without recording an alias.
- **Concrete Fix:** Track descriptor alias groups independently of lazy `DIR *` allocation. Create one cursor on first enumeration and share it across all aliases. Propagate bookkeeping exhaustion rather than silently losing the relationship. Test duplication before and after enumeration with small output buffers.

### LA64-R3-6 — Signal action and alternate-stack calls overwrite aliased input

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigframe.c:447`; `src/os/sigframe.c:514`
- **Evidence & Root Cause:** Both `la64_sigaction_sys()` and `la64_sigaltstack_sys()` write the old-state output before reading the requested new state. If input and output point to the same guest buffer, the new request is overwritten and the old state is installed again. Partially overlapping buffers have the same problem.
- **Concrete Fix:** Copy the complete input structure into local storage before writing any output. Validate and apply that saved input in guest-kernel order. Add exact-alias and partial-overlap regressions for both syscalls.

### LA64-R3-7 — Alternate-stack disable and signal-return lifecycle are incomplete

- **Severity:** Medium
- **Category:** BUG
- **Location:** `src/os/sigframe.c:538`; `src/os/sigframe.c:370`
- **Evidence & Root Cause:** The `SS_DISABLE` branch bypasses the active-stack check, which exists only in the enabling branch at line 547. A handler can therefore disable its currently active alternate stack instead of receiving `EPERM`. Separately, delivery saves `uc_stack` at frame offsets 144–160, but `la64_sigreturn_sys()` never restores it; it restores registers, mask, and FP state only.
- **Concrete Fix:** Apply the active-stack restriction before either enabling or disabling the stack. Restore and validate the saved alternate-stack configuration during `rt_sigreturn`, respecting supported flag semantics. Test disabling from an alternate-stack handler and restoring a modified `uc_stack`.

### Checklist

- [ ] **LA64-R3-1:** Separate per-thread signal state from shared dispositions.
- [ ] **LA64-R3-2:** Preserve shared-file semantics in fallback mappings.
- [ ] **LA64-R3-3:** Roll back failed file-map installation.
- [ ] **LA64-R3-4:** Validate `mmap` descriptor, mapping type, and offset.
- [ ] **LA64-R3-5:** Preserve directory cursor identity across early duplication.
- [ ] **LA64-R3-6:** Snapshot signal syscall inputs before copyout.
- [ ] **LA64-R3-7:** Correct alternate-stack disable and sigreturn behavior.