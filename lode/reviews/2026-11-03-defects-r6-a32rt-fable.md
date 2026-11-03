# Verification report: a32rt commit `2a84154` vs. Round-6 defects A32-R6-1..9

Scope: static review of the commit diff plus targeted greps of the tree at HEAD `2a84154`. No build, test, container, or QEMU run. Line numbers are post-commit unless marked "old".

## Summary

| Item | Severity | Verdict | One-line reason |
|---|---|---|---|
| A32-R6-1 sendmsg TOCTOU | HIGH | **PARTIAL** | Ancillary bytes are snapshotted and re-validated, so the overflow is closed. The `msghdr` itself is still read live from guest memory, so a racing length/pointer change can still fault the runtime. |
| A32-R6-2 uname layout | HIGH | **VERIFIED** | Explicit 6×65 guest layout, zeroed, bounded copy, checked write. |
| A32-R6-3 errno translation | HIGH | **PARTIAL** | `host_ret` and `FAIL_ERR` now translate; negative values pass through. Some direct `-errno` stores bypass the boundary. |
| A32-R6-4 signalfd vs. guest pending set | HIGH | **PARTIAL** | Blocking `read` on a signalfd now drains the guest pending set. Readiness via poll/ppoll/epoll/select is not integrated. |
| A32-R6-5 getcwd copyout | HIGH | **VERIFIED** | Full `len+1` extent checked and checked `guest_write`. |
| A32-R6-6 memfd_create name read | HIGH | **VERIFIED** | Byte-wise checked read into local buffer, limit preserved. |
| A32-R6-7 statx timestamp order | MEDIUM | **VERIFIED** | Order is now atime, btime, ctime, mtime; comment corrected. |
| A32-R6-8 statx AT_EMPTY_PATH | MEDIUM | **VERIFIED** | Path inspected first; fd semantics only for empty path; AT_FDCWD handled. |
| A32-R6-9 getresuid32/getresgid32 NULL | MEDIUM | **VERIFIED** | All three pointers required, EFAULT on NULL, checked stores in ruid/euid/suid order. |

No item regressed to a worse state than before. Two behaviour changes outside the defect list are noted at the end.

---

## A32-R6-1 — sendmsg two-pass ancillary parsing — PARTIAL

**What the commit does** (`src/os/os_sys_sock.c`):
- `:558-559` introduces `csnap` and captures `ctl_len = gm->msg_controllen` once.
- `:562-565` mallocs `ctl_len` bytes and copies the guest control block into owned memory; both passes now parse `gctl = csnap`.
- `:568-572` first pass validates `l32 < 12 || l32 > ctl_len - t32`.
- `:589` second pass **re-validates** `len32` with the same predicate, closing the `payload_len` underflow.
- `:594` adds `off64 + space64 > cbuf_cap` before writing `cm64`, closing the `cbuf_st`/`cbuf_dyn` overflow.
- `:617`, `:684` free `csnap` on both exit paths; all early-fail paths free it too.

**Why not fully VERIFIED:** the defect's prescribed fix was to snapshot the message header as well. `gm` is still a live pointer into guest memory (`:541`), and `gm->msg_control` / `gm->msg_controllen` are read more than once:
- `:544-546` range-checks `gm->msg_control` for `gm->msg_controllen` bytes.
- `:559` re-reads `msg_controllen` into `ctl_len`.
- `:564` re-reads `msg_control` for the `memcpy` source.

A racing guest thread that grows `msg_controllen` or moves `msg_control` between `:544` and `:564` makes the `memcpy` read beyond the validated range. Because `a32_guest_ptr` stays inside the 4 GiB window, this is an unmapped-page host fault (terminated at `src/signals.c:444` `_exit(128+sig)`), not a heap overflow. The write-side corruption is fixed; a crash-only TOCTOU remains. Same pattern exists for `msg_name`, `msg_iov`, `msg_iovlen` (`:538`, `:548-551`), which are pre-existing and out of this item's scope.

Minor: `malloc(ctl_len)` at `:562` uses a guest-controlled size with no cap before the 64 KiB `need64` check; bounded in practice by the range check at `:544`, so low severity.

---

## A32-R6-2 — uname host-layout copy — VERIFIED

`src/os/os_sys_thread_sig.c`:
- `:615` defines the Linux `new_utsname` layout as six `char[65]` fields (390 bytes).
- `:616` range-checks `sizeof(gu)` for `PROT_WRITE`, replacing the old `sizeof(struct utsname)` (1280 on Darwin).
- `:619` zero-initialises; `:620-629` copy each host field with bounded `snprintf`; Darwin lacks `domainname` and gets `"(none)"` under `#ifdef __APPLE__`.
- `:630` uses checked `guest_write`.

Note the machine string changed from `"armv8l"` to `"armv7l"` (`:624`). This was not requested by the defect; see "Other observations".

---

## A32-R6-3 — Darwin errno leaking into the Linux ABI — PARTIAL

`src/os/sys_priv.h`:
- `:592-622` adds `host_errno_to_linux()`; identity on non-Apple, `err <= 0` passed through unchanged (the "already translated" discriminator).
- `:627` `host_ret` now returns `-host_errno_to_linux(errno)`.
- `:801` `FAIL_ERR(err)` translates positive values and stores negative values verbatim.

I checked the Darwin→Linux table by hand against both errno sets. Every listed pair is correct, including the two cited in the defect (35→11 EAGAIN, 78→38 ENOSYS) and the EDEADLK swap (11→35). Not mapped but existent on Darwin: `ENOATTR` 93 (Linux `ENODATA` 61), `EPROCLIM` 67, `EBADRPC`..`EPROGMISMATCH` 72-76. Those fall through unchanged; low impact.

Double-translation check: `grep` found no `FAIL_ERR(<literal>)` sites. The pre-existing guest-literal stores at `src/os/os_sys_thread_sig.c:227,234,261` (`(uint32_t)-11`, `(uint32_t)-110` in the Darwin futex path) write directly to `regs[0]` and so are not re-translated. `FAIL_ERR(-irc)` at `:350` and `FAIL_ERR(-r)` at `:591,:600` negate a host `-errno` back to positive and go through translation, which is correct.

**Remaining bypasses** (reason for PARTIAL):
- `src/os/os_sys_fs_arm.c:671` stores `(uint32_t)(-errno)` directly, untranslated.
- `src/os/os_sys_fork_time.c:741` and twelve sites in `src/os/backend_darwin.c` (`:97,:102,:152,:171,:207,:244,:249,:266,:277,:331,:356,:402`) `return -errno`. Whether each caller routes that through `FAIL_ERR(-rc)` or stores it raw was not checked within budget. Any raw store leaks Darwin numbering.
- `src/os/os_sys_sock.c:620` stores `iov_rc` raw; the helper most likely returns `-EFAULT`/`-EINVAL`, which are numerically identical on both hosts, so no practical effect.

Style note: the mapping is a wall of bare integers (`case 11: return 35;`). It is correct but unauditable without a table; symbolic constants would be safer against future edits.

---

## A32-R6-4 — signalfd4 not integrated with guest pending signals — PARTIAL

**What the commit does:**
- `src/os/os_sys_sock.c:10-39` adds a 32-entry global fd→(mask, flags) tracker (`a32_sigfd_track/untrack/lookup`).
- `:322-324` for every signal in the mask calls `a32_signals_ensure_host_handler()` so the host handler enqueues into `ctx->pending_signals`. The symbol is defined at `src/signals.c:541` and already used by `src/main.c:148` and `src/os/os_sys_sig_time.c:59`; the new `sys_priv.h:762` declaration duplicates `src/a32rt.h:348` with an identical signature, so the link is sound.
- Linux (`:325-345`): still creates a real host signalfd, now tracked. Darwin (`:347-355`): returns a tracked `/dev/null` fd instead of ENOSYS.
- `src/os/os_sys_thread_sig.c:302-349` intercepts `ARM_NR_read` on a tracked fd: EINVAL if `count < 128`, EFAULT if unwritable, then spins (5 ms `nanosleep`) until `pending_signals & mask` is non-zero, honours O_NONBLOCK with EAGAIN, dequeues the lowest signal, and writes a 128-byte `signalfd_siginfo` with only `ssi_signo` populated.
- `:397` untracks on `close`.

This fixes exactly the scenario in the defect text (block SIGUSR1, create signalfd, receive SIGUSR1, blocking `read`).

**Not fixed — readiness:** the defect asks for "reads and readiness". `poll`/`ppoll` (`src/os/os_sys_fs_arm.c:41-87`), `epoll_wait`/`epoll_pwait` (`:88-111`) and `_newselect` (`src/os/os_sys_sock.c:690`) still hand the host fd straight to the kernel.
- On Linux the host handler consumes the signal before the host signalfd sees it, so the fd never becomes readable: the common `poll()` then `read()` pattern (glib, systemd, libuv) still waits forever.
- On Darwin `/dev/null` is always readable, so `poll` reports `POLLIN` immediately and the guest busy-loops on EAGAIN or blocks in the emulated `read`.

**Other gaps, lower severity:**
- Only `ssi_signo` is filled (`:320-321`); `ssi_code`, `ssi_pid`, `ssi_uid`, `ssi_int`/`ssi_ptr` from `sigqueue` are zero. The `siginfo_t` captured by `enqueue_async_signal` is discarded.
- The spin loop is not interruptible: a non-masked signal arriving during the wait is not delivered and Linux's `EINTR` is never returned.
- Only the calling thread's `ctx->pending_signals` is consulted; a process-directed signal enqueued on another thread's ctx is invisible to this signalfd.
- `g_sigfd` is global and unsynchronised; `dup`/`dup2`/`F_DUPFD` copies are not tracked, so a duplicated signalfd falls back to a raw host `read`.
- Dead code: `known`, `old`, `ofl` at `:335-336`, `:339` are computed and `(void)`-discarded. `SIGFD_MAX` is defined at `:10` but the array at `:11` uses the literal `32`.

---

## A32-R6-5 — getcwd unchecked copyout — VERIFIED

`src/os/os_sys_thread_sig.c:718-720`: ERANGE check retained, then `a32_guest_range_ok(ctx, a0, len+1, PROT_WRITE)` and checked `guest_write` of `len+1` bytes. The raw `buf` pointer (old `:674`) is gone. The range check at `:719` is redundant with `guest_write` at `:720` but harmless.

---

## A32-R6-6 — memfd_create strnlen on guest memory — VERIFIED

`src/os/os_sys_sock.c:295-305`: a 250-byte local buffer is filled by per-byte `guest_read`; any unreadable byte yields EFAULT, an unterminated 250-byte name yields EINVAL (same threshold as before), and the host syscall receives the local buffer. Per-byte `guest_read` is slow but memfd_create is not hot.

---

## A32-R6-7 — statx timestamp order — VERIFIED

`src/os/os_sys_sock.c:240-243`: `secs[]`/`nsecs[]` are now atime, birthtime, ctime, mtime, which lands them at guest offsets 64, 80, 96, 112 via the unchanged `64 + ti*16` loop. The misleading layout comment was replaced at `:217` with the correct order.

---

## A32-R6-8 — statx AT_EMPTY_PATH ignores pathname — VERIFIED

`src/os/os_sys_sock.c:196-208`: rejects NULL path with EFAULT, reads the first byte via `guest_read`, and takes descriptor semantics only when `first == '\0' && AT_EMPTY_PATH`. `AT_FDCWD` maps to `stat(".")`; a non-empty path falls into the existing resolve branch. Empty path without the flag reaches `fstatat` with `""` and gets ENOENT, matching Linux. Rejecting a NULL path diverges from Linux ≥ 6.11, which accepts NULL with AT_EMPTY_PATH, but glibc uses `""` so this is cosmetic.

---

## A32-R6-9 — getresuid32/getresgid32 optional outputs — VERIFIED

`src/os/os_sys_thread_sig.c:806-809`: EFAULT if any of the three pointers is zero or unwritable. `:822` performs three checked `guest_write`s in ruid, euid, suid order, preserving Linux partial-write ordering.

---

## Other observations (not Round-6 items)

- **`uname` machine string changed** from `armv8l` to `armv7l` (`src/os/os_sys_thread_sig.c:624`). Likely an improvement for 32-bit ARM guests (Debian armhf tooling expects `armv7l`), but it is an undeclared behaviour change and should be mentioned in the DEFECTS.md closeout.
- **Comment erosion.** The commit shortens or deletes explanatory comments in `src/signals.c` (`:37-38`, `:119-126`, `:373`, `:444`, `:859`, `:871`) and the Darwin futex rationale at `src/os/os_sys_thread_sig.c:216`. None of these are behavioural, but the deleted text documented non-obvious platform semantics (si_code classification, VFP frame layout, guest-vs-host errno in futex). This runs against the "adequate, high-quality comments" rule and makes the next audit harder.
- **Unverified:** nothing in this report was compiled or executed. The `ARM_NR_read` interception, the Darwin `/dev/null` signalfd stand-in, and the errno table are the three areas most worth a runtime probe before sign-off.

## Recommended follow-ups before closing R6-1, R6-3, R6-4

1. R6-1: copy `arm_msghdr32_t` into a local struct once at `os_sys_sock.c:541` and use that for every subsequent field read.
2. R6-3: route `os_sys_fs_arm.c:671` and the `-errno` returns from `backend_darwin.c` / `os_sys_fork_time.c:741` through `FAIL_ERR(-rc)` or `host_ret`, and add `ENOATTR`→`ENODATA`.
3. R6-4: short-circuit tracked fds in `poll`/`ppoll`/`epoll_*`/`_newselect` to report readiness from `pending_signals & mask`, fill the remaining `signalfd_siginfo` fields from the enqueued `siginfo_t`, and make the wait loop return EINTR on non-masked pending signals.
