# Verification report: `ppc64rt` commit `976fe1b` vs. Round-6 defects P64-R6-1..10

**Scope and method.** Commit `976fe1b` ("ppc64rt: remediate Round-6 defects (P64-R6-1..10)") is `HEAD` of `ppc64rt`; the working tree has no further source changes. Verification is static only: the full diff plus four targeted spot-checks of the post-commit tree. No build, test, Docker, or QEMU run. Line numbers below refer to the post-commit tree.

**Summary**

| Item | Severity | Verdict |
|---|---|---|
| P64-R6-1 `subfic`/`addic` RA=0 | HIGH | VERIFIED |
| P64-R6-2 repeated stdio `dup2` closes replacement | HIGH | VERIFIED |
| P64-R6-3 chunked `read` blocks after data | HIGH | VERIFIED (with caveat) |
| P64-R6-4 pipe write atomicity | HIGH | VERIFIED |
| P64-R6-5 `writev` partial-progress error | MEDIUM | VERIFIED |
| P64-R6-6 diverged errno translators | MEDIUM | PARTIAL |
| P64-R6-7 `pipe2` host-flag validation | MEDIUM | VERIFIED |
| P64-R6-8 Darwin sockaddr header | MEDIUM | VERIFIED |
| P64-R6-9 `xlate_addr_out` OOB / length | MEDIUM | VERIFIED |
| P64-R6-10 `ppoll` sigmask handling | MEDIUM | PARTIAL |

No REGRESSION found. Two items are PARTIAL because the structural fix Astra asked for was not done, though the concrete symptoms were addressed.

---

## P64-R6-1 — VERIFIED

`src/dbt/emit_int.c:211`: the `if (d->ra == 0u) e_mov_imm(...R_A, 0) else e_ldg(...)` branch is replaced by an unconditional `e_ldg(e, R_A, d->ra)`. This is the `subfic`/`addic`/`addic.` branch only (the `addi`/`addis` early return at `:208-209` is untouched), so zero-base handling stays confined to `addi`/`addis` as requested. GPR0 is now read, matching the interpreter.

## P64-R6-2 — VERIFIED

`src/os/fd_table.c:114-126` (`syscall_fd_replace`): the unconditional `fdt_drop(guest_fd)` is gone. The function now snapshots the existing entry, and if `old_fd == host_fd` it re-marks the slot used and returns without closing (`:118-122`). Only a genuinely different previous host fd is closed (`:123-124`).

Caller check: `src/os/proc.c:836-841` (`ppc64_proc_dup2`, `newfd < 3`) does host `dup2(host_old, newfd)` then `syscall_fd_replace(newfd, newfd)`. After the first redirection the slot holds host fd `newfd`, so the second redirection hits the `old_fd == host_fd` path and no longer closes the freshly installed descriptor. The `newfd >= 3` path (`:852`) installs a fresh `dup()` result, where closing the old entry remains correct.

## P64-R6-3 — VERIFIED (caveat)

`src/os/syscalls.c:538-591` (`syscall_read`): the 512-byte chunk loop is replaced by a single `ppc64_host_read` of `min(count, 64 KiB)` into a heap stage (`:562-569`), followed by one `mem->write` (`:581`). One host read means a pipe read returns whatever is available and can no longer re-block after a full first chunk. Error and `n == 0` paths return `*out = 0` with the errno or success respectively (`:571-580`).

Caveat, not a defect in the fixed behavior: reads are now capped at `SYSCALL_STAGE_MAX` (64 KiB, `:135`) per syscall. A guest `read` of more than 64 KiB on a regular file returns a short count. That is POSIX-legal and libc loops over it, but it is a visible behavior change from the previous full-count loop. Worth a line in the DEFECTS log.

## P64-R6-4 — VERIFIED

- `src/os/syscalls.c:232-268` (`syscall_write_range`): stages up to 64 KiB into one heap buffer and issues **one** `ppc64_host_write` (`:258-259`). `syscall_write` (`:272-320`) only loops across 64 KiB stages, each far above `PIPE_BUF`, so any `PIPE_BUF`-bounded guest write is one host write.
- `src/os/syscalls.c:384-532` (`syscall_writev`): all iovec metadata is read first (`:417-440`); if `total_len <= 64 KiB` the whole vector is gathered into one stage and written with a single `ppc64_host_write` (`:448-487`), so atomicity covers the entire vector, not per-element. Larger vectors fall back to per-element staged chunks (`:489-521`), which is fine since those exceed `PIPE_BUF` anyway.

`SYSCALL_IO_CHUNK` remains in use only by `pwrite64` (`:325`, `:344`), which cannot target pipes (`ESPIPE`), so it is out of scope for this item.

## P64-R6-5 — VERIFIED

`src/os/syscalls.c`:
- Metadata is validated before any output (`:417-440`); a metadata fault with `total == 0` returns `EFAULT` (`:425-432`).
- In the single-stage path, a payload fault happens before the host write, so `EFAULT` with `*out = 0` (`:462-472`) is correct; no bytes were emitted.
- In the chunked path, a later failure after `total > 0` returns success with the short count (`:505-516`); the `rc` only surfaces when nothing was written (`:517-518`).

Retry duplication is no longer possible from the reported scenario.

## P64-R6-6 — PARTIAL

What was fixed:
- `src/os/syscalls_misc.c:56-120` (`syscall_host_to_linux`): Linux passthrough via `#ifdef __linux__ return err;` (`:58-60`); Darwin table now includes `EINTR` (`:70-71`), so the interrupted-`pwrite` branch no longer reports `EIO`. `ENOSPC`, `ESPIPE`, `ENAMETOOLONG`, `EBUSY`, `ENODEV`, `EOPNOTSUPP`, `ETIMEDOUT` etc. added.
- `src/os/proc.c:253-309` (`proc_host_to_linux`): same Linux passthrough and the same Darwin extension.
- `src/os/backend_linux.c:71-74, 124`: default now `return err;` instead of `22`, so unmapped errnos like `ENOSPC` are no longer folded into `EINVAL` on Linux.
- `src/os/backend_darwin.c:85-86, 103-108`: `E2BIG`, `ENOSPC`, `ESPIPE`, `ENAMETOOLONG` added.

What was not done:
- Astra's fix was to **consolidate** translation into one routine. Three independent translators still exist (`backend_*.c`, `syscalls_misc.c`, `proc.c`), now with three parallel Darwin tables that must be kept in sync by hand.
- The Darwin tables still diverge on the fallback: `backend_darwin.c:118` still returns `22` (`EINVAL`) for unmapped errnos, while `syscalls_misc.c:117` and `proc.c:307` return `EIO`. So on Darwin an unmapped host errno maps differently depending on which path raised it.

Net: the two concrete symptoms are fixed; the DRY finding itself stands.

## P64-R6-7 — VERIFIED

`src/os/proc.c:757-766` (`ppc64_proc_pipe2`): validation now uses explicit guest Linux values `0x80000` (`O_CLOEXEC` 02000000) and `0x800` (`O_NONBLOCK` 04000), which are correct for PowerPC Linux, and translates to host `FD_CLOEXEC` / `O_NONBLOCK` via `fcntl`. Host constants no longer leak into the guest ABI check.

## P64-R6-8 — VERIFIED

`src/os/backend_net.c:129-161` (`xlate_addr_in`): guest family is decoded explicitly as little-endian u16 from the first two bytes (`:144`); on `__APPLE__` the host header is written as `(sa_len = addrlen, sa_family = hfamily)` byte-wise (`:154-157`), otherwise as the u16 family. `xlate_addr_out` (`:163-202`) reads the Darwin family from byte 1 (`:181`) and always writes the Linux header as two explicit LE bytes (`:193-194`). The `sockaddr_in`/`in6`/`un` body layouts are identical across the two hosts, so the header fix is sufficient.

## P64-R6-9 — VERIFIED

`src/os/backend_net.c:163-202`: conversion happens in a local `tmp[sizeof(*host_addr)]` buffer (`:166`, `:179`, `:193-194`); the copy to the guest buffer is bounded by `min(cap, full)` and skipped entirely when `copy == 0` (`:195-197`); `*addrlen_inout` reports the full converted length `full` (`:198`), which is the Linux truncation contract. Capacity 0 or 1 no longer touches out-of-bounds guest memory. `host_len` is clamped to `sizeof(*host_addr)` first (`:172-173`), and `full == 0` short-circuits (`:176-179`).

## P64-R6-10 — PARTIAL

What was fixed (`src/os/backend_net.c:556-567`, Linux path): the mask is now installed with `SIG_SETMASK` saving the original (`:556`), and the original is restored afterwards with `SIG_SETMASK` (`:566-567`). This corrects both reported symptoms: previously-blocked signals are no longer unblocked on exit, and signals omitted from the temporary mask are no longer left blocked during the wait.

What was not done:
- Still `pthread_sigmask` + plain `poll()` (`:565`) rather than native `ppoll`. The install/wait is therefore not atomic: a signal arriving between `:556` and `:565` is delivered without interrupting the wait, the classic race `ppoll` exists to close.
- Millisecond truncation and the one-day cap remain (`:563`).
- No integration with the worker interruption protocol beyond what the existing wake path already provides.

Net: the mask-restoration bug is fixed; the "use native `ppoll`" remedy, the atomicity gap, and the timeout fidelity items remain open.

---

**Residual notes for the coordinator**

1. P64-R6-6 and P64-R6-10 should stay open in `DEFECTS.md` as reduced-severity follow-ups: unify the Darwin errno tables and the backend default (`backend_darwin.c:118`), and switch the Linux `ppoll` backend to native `ppoll` with a `timespec`.
2. Record the new 64 KiB per-syscall short-read behavior from P64-R6-3 as an intentional semantics change.
3. All verdicts are static; the commit was not compiled here. The new `SYSCALL_ENOMEM` uses in `syscalls.c` resolve against that file's local enum (`syscalls.c:92`), so no obvious compile hazard was observed, but a build and the existing syscall fixture run are still required before sign-off.
