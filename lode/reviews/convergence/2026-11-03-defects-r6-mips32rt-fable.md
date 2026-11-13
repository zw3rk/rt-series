# Verification report: mips32rt `d9357df` vs. Round-6 astra defects (M32-R6-1..11)

**Scope and method.** Static diff review of commit `d9357df` (parent `0e879ac`, current HEAD of `mips32rt`) against `lode/reviews/2026-11-03-defects-r6-mips32rt-astra.md`. No build, tests, Docker, or QEMU were run. Line numbers refer to the post-commit tree.

## Summary

| Item | Severity | Verdict | Note |
|---|---|---|---|
| M32-R6-1 | HIGH | **VERIFIED** | Reaper mutex now in fork prepare/release; child re-inits. Nit: redundant double unlock in child. |
| M32-R6-2 | HIGH | **VERIFIED** | Private flag propagated to both BE WAKE_OP wake calls. |
| M32-R6-3 | HIGH | **PARTIAL** | Write-permission check and EFAULT added; mapping is not stabilised across the CAS, so the unmap race window remains. |
| M32-R6-4 | HIGH | **VERIFIED** | Legacy `pipe` is register-only; `pipe2` copies out and returns 0. |
| M32-R6-5 | MEDIUM | **VERIFIED** | Access-mode and creation-only bits stripped before conversion. |
| M32-R6-6 | MEDIUM | **VERIFIED** | Distinct `__O_SYNC` bit tested; `O_DSYNC` alone accepted. Nit: raw `0x4000U` literal. |
| M32-R6-7 | MEDIUM | **VERIFIED** | Pointer array placed directly after the aligned `iovec` array. |
| M32-R6-8 | HIGH | **VERIFIED** | Alternate stack reset for non-VFORK clones. Nit: magic `2U`. |
| M32-R6-9 | MEDIUM | **VERIFIED** | On-altstack `EPERM` check precedes `SS_DISABLE`. |
| M32-R6-10 | LOW | **VERIFIED** | Single `elf32_check_swap` helper used by all three paths. |
| M32-R6-11 | LOW | **VERIFIED** | Altstack API removed; no remaining references in `src/` or `tests/`. |

Totals: 10 VERIFIED, 1 PARTIAL, 0 NOT FIXED, 0 REGRESSION.

## Per-item evidence

### M32-R6-1 — Fork inherits locked reaper mutex — VERIFIED

- `src/os/fork.c:46-47` declare weak `mips_threads_fork_prepare` / `mips_threads_fork_release`.
- `src/os/fork.c:77-79` call prepare last in `fork_stages_prepare`; `src/os/fork.c:84-86` call release first in `fork_stages_release`. Lock order is consistent (vm → sig → dbt → ll → reap, released in reverse).
- `src/os/threads.c:251-258` implement prepare/release as lock/unlock of `mips_reap_lock`.
- `src/os/threads.c:260-267` child hook: resets live counter, unlocks, destroys and re-inits the mutex, and clears `mips_reap_head`.
- `src/os/threads.c:852-857` add no-op stubs for the non-Linux build so the weak symbols resolve.
- `mips_reap_lock` is a leaf lock: every holder (`threads.c:131-158`, `555-558`, `564-567`) takes no other lock while holding it, so adding it last in prepare introduces no inversion.

Nit (not a regression): in the child, `src/os/fork.c:122` runs `fork_stages_release()` which already unlocks `mips_reap_lock`, then `src/os/fork.c:124` runs the child hook which unlocks it again at `src/os/threads.c:263`. Unlocking an unlocked default mutex is undefined per POSIX. Static musl tolerates it for `PTHREAD_MUTEX_NORMAL`, but line 263 should be dropped; destroy and init are sufficient.

### M32-R6-2 — BE `FUTEX_WAKE_OP_PRIVATE` loses private flag — VERIFIED

- `src/os/threads.c:574-575` helper signature gains `int priv`.
- `src/os/threads.c:589-590` compute `wop = MIPS_FUTEX_WAKE | (priv ? MIPS_FUTEX_PRIVATE_FLAG : 0)`; constants at `src/os/syscalls_priv.h:59-60` are 1 and 128, matching the host ABI.
- `src/os/threads.c:642-643` and `650-651` both wake calls use `wop` instead of the hard-coded `(int)1`.
- `src/os/threads.c:804-805` caller passes `priv`.

### M32-R6-3 — BE `FUTEX_WAKE_OP` writes read-validated memory — PARTIAL

Fixed:
- `src/os/threads.c:584-588` check `mips_sc_range_ok(ctx, uaddr2, 4, PROT_READ|PROT_WRITE)` before the CAS loop, returning `-1` with `errno = EFAULT`, which the caller translates to guest `EFAULT`.

Not fixed:
- The astra fix text asks to "stabilize the mapping during the atomic update". No VM or region lock is held across the CAS loop that follows `threads.c:591`. A peer thread issuing `munmap` on the page between the check and the host `ldxr/stxr` still faults the translator. The TOCTOU window the defect explicitly names ("Concurrent unmapping adds another fault window") remains.
- `futex_addr_ok` at `src/os/threads.c:664-673` still only requires `PROT_READ`. This is acceptable because it is used for the read-only futex paths, and the only translator-side writer is the BE helper, which now checks write permission itself.

### M32-R6-4 — `pipe` and `pipe2` share one ABI — VERIFIED

- `src/os/syscalls.c:494` initialises `fds_va = 0U`; `syscalls.c:499-502` read `$a0`/`$a1` only when `is_pipe2`, so legacy `pipe` never touches a buffer argument.
- `src/os/syscalls.c:537-542` legacy path writes `$v0 = fd0`, `$v1 = fd1`, `$a3 = 0` and returns.
- `src/os/syscalls.c:543-554` `pipe2` path byte-swaps as needed, copies 8 bytes to the guest buffer, closes both fds on `EFAULT`, and returns `mips_sc_ret(ctx, 0)` (so `$v0 = 0`).

Unverified minor: the legacy path now returns `fds[0]` as the raw C return value (previously `0`). This matches the `mips_sc_ret` convention of returning the raw host value and flows up through `mips_syscall_extra` to `src/os/syscall_min.c:474`. I did not trace whether any caller inspects that value beyond sign. No evidence of harm.

### M32-R6-5 — `F_SETFL` rejects write-only descriptors — VERIFIED

- `src/os/syscalls_meta.c:136-138` mask `arg` with `~(3U | CREAT | TRUNC | EXCL | NOCTTY | DIRECTORY | NOFOLLOW | CLOEXEC | LARGEFILE)` before conversion, so the access mode presented is always `0` (`O_RDONLY`), which the converter accepts at `src/os/syscalls.c:174-176`.
- `src/os/syscalls_meta.c:142-155` additionally strip the corresponding host bits before `fcntl(F_SETFL)` at line 156.

The reported `GETFL → OR O_NONBLOCK → SETFL` sequence on a mode-1 descriptor no longer reaches mode `3` and no longer returns `EINVAL`.

### M32-R6-6 — Valid `O_DSYNC` opens fail with `EINVAL` — VERIFIED

- `src/os/syscalls.c:215-217` now test only the distinct `__O_SYNC` bit (`mips & 0x4000U`) and map it to host `O_SYNC`. The prior `else if … return -EINVAL` branch is gone.
- `O_DSYNC` alone passes through the pre-existing mapping at `src/os/syscalls.c:189-191` (`MIPS_O_DSYNC` → `O_DSYNC`).
- Bare `__O_SYNC` without `O_DSYNC` is now accepted and upgraded to host `O_SYNC`. This matches Linux `build_open_flags`, which sets `O_DSYNC` whenever `__O_SYNC` is present.

Nit: `0x4000U` is a raw literal; `src/os/syscalls_priv.h:36` documents it only in a comment. A named `MIPS___O_SYNC` constant would be clearer.

### M32-R6-7 — Misaligned vectored-I/O scratch layout — VERIFIED

- `src/os/syscalls.c:582-583` allocation size unchanged in total.
- `src/os/syscalls.c:587` places `tmps` (`uint8_t **`) immediately after the `struct iovec` array (8-byte aligned on AArch64), and `src/os/syscalls.c:588` places `bases` (`uint32_t *`) after it. The pointer array is now always naturally aligned for any `count`.

### M32-R6-8 — `CLONE_VM` child inherits alternate signal stack — VERIFIED

- `src/os/threads.c:462-466` reset `sigalt_sp`, `sigalt_size`, and `sigalt_flags` when `CLONE_VFORK` is clear. Since non-`CLONE_VM` clones are rejected earlier in `mips_sc_clone`, this is equivalent to the Linux condition `(CLONE_VM|CLONE_VFORK) == CLONE_VM`.

Nit: `sigalt_flags = 2U` is a magic number. `L4A_SS_DISABLE` is defined file-locally at `src/os/signals.c:67` and not visible from `threads.c`; the value is correct, but it should be hoisted to a shared header.

### M32-R6-9 — Executing altstack can be disabled — VERIFIED

- `src/os/signals.c:741-743` the `l4a_on_altstack(ctx)` → `EPERM` check now runs before the `SS_DISABLE` branch at `src/os/signals.c:744-749`. The old post-branch check was removed, so there is no duplicate.

### M32-R6-10 — Triplicated ELF header decode — VERIFIED

- `src/rt32/elf32.c:135-166` new file-local `elf32_check_swap` validates magic/class/endian and swaps all header fields.
- Callers: `src/rt32/elf32.c:206-210` (`load_elf32_image`), `529-532` (`interp_measure_span`), `610-613` (`validate_elf32_image`). Operation-specific checks (`EM_MIPS`, ABI flags, `phentsize`, `phnum` bounds) remain in the callers as the astra fix requested. No cross-repository sharing introduced.

Behavioural notes, not regressions: the loader's distinct "not a 32-bit MIPS ELF" diagnostic is now folded into "not an ELF file" (`elf32.c:208`). `interp_measure_span` now swaps every header field rather than four; a harmless superset.

### M32-R6-11 — Unused host-worker altstack API — VERIFIED

- `src/os/backend.h:164` declarations removed; section comment updated.
- `src/os/backend_posix.c` definitions removed (old lines 319-340).
- `grep -rn 'altstack_init\|altstack_destroy' src/ tests/` returns no matches.

## Other observations

- **Comment stripping outside scope.** The commit also deletes the provenance header comments in `src/os/syscalls.c:1-9` and `src/os/threads.c:1-50` (including the verified O32 syscall-number provenance against `unistd_o32.h`) and several section comments. None of the 11 items asked for this. Not a regression, but it loses documented evidence that the global comment policy asks to keep.
- **Not verified:** compilation under `-std=c11 -pedantic -Wall -Wextra -Werror=vla`. The mid-block `bool is_be = false;` declarations in `elf32.c:206` and `610` are legal C11. No build was run per the budget.

## Recommended follow-ups

1. M32-R6-3: hold the VM region lock (or equivalent) across the CAS loop in `futex_wake_op_be`, or document why a concurrent `munmap` cannot race it. This is the only open HIGH item.
2. M32-R6-1: remove the redundant `pthread_mutex_unlock` at `src/os/threads.c:263`.
3. Replace `0x4000U` (`syscalls.c:215`) and `2U` (`threads.c:465`) with named constants.
