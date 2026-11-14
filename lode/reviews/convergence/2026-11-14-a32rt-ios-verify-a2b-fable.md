# Round 19 Post-Remediation Review — Track A2b (BSD Sockets & Kqueue, `claude-fable-5-1`)

Both ledger entries and both source files are read. Here is the verification.

## Scope note

`A32-IOS-P8` lives in `src/ios/ios_svc_bsd.c:156-175`, which is outside the two files I was told to read. Neither in-scope file calls `ios_cstr` (AF_UNIX paths are copied raw by `sk_sa_g2h`), so P8 has no bearing on them. P8 is **NOT VERIFIABLE** within this scope. `a32_ios_kq_atfork_reset` and `a32_ios_kq_close` call sites are also out of scope; I verified their bodies only.

## VERIFIED (sound)

- **MSG flag mapping, both directions** (`ios_svc_bsd_sock.c:121-173`). Darwin `MSG_DONTWAIT 0x80`, `MSG_WAITALL 0x40`, `MSG_NOSIGNAL 0x80000`, `MSG_EOR/TRUNC/CTRUNC` all mapped bit by bit, never passed raw.
- **12-byte guest `cmsghdr` encode/decode** (`sk_ctl_g2h` 353-398, `sk_ctl_h2g` 403-446). Uses only `CMSG_FIRSTHDR/NXTHDR/LEN/SPACE/DATA`, so the 12-byte macOS and 16-byte Linux host headers are both correct. `used` accounting matches `CMSG_NXTHDR` stepping. The `gp + cl` 32-bit wrap at line 378 is caught by the 64-bit-promoted `CMSG_SPACE(dlen)` bound at line 380, so no over-read. Guest stride `(gl+3)&~3` matches `__DARWIN_ALIGN32`.
- **28-byte Darwin `msghdr`** offsets (namelen 4, controllen 20, flags 24) and all socket/kqueue syscall numbers and argument positions, including `kevent` timeout at `a[5]` and `kevent64` at `a[6]`.
- **sockaddr translation** (`sk_sa_g2h`/`sk_sa_h2g`): no overflow of `sockaddr_storage`, BSD `sa_len` honoured, `accept` fd closed on store failure.
- **`(ident, filter)` knote key** (`kevent.c:140-149`), `EV_ONESHOT` removal after delivery (382-384), one-shot timers via `period_ns = 0` (173, 381).
- **Timer wait rounding**: ceil to ms (347), expired deadline forces `wait_ms = 0` (331-333), 8-byte 32-bit `timespec` (430-435) with no overflow.
- **20-byte `kevent` and 48-byte `kevent64_s`** layouts (203-206, 211-214) match XNU.
- **fork reset** (124-129): resetting only the spinlock is correct for the surviving thread. kqueue fds staying valid in the child is more permissive than XNU but not a defect.

## RESIDUAL DEFECTS

**R1. SCM_RIGHTS fd leak on truncated or unwritable guest control buffer; `MSG_CTRUNC` never set** (`ios_svc_bsd_sock.c:575-578, 410-411, 431, 585-589, 597-603`).
Host `recvmsg` always gets a 256-byte control buffer regardless of the guest `msg_controllen`, so the host kernel installs every received fd. `sk_ctl_h2g` then breaks at line 431 when `gp + gl > gmax`, or returns `-EFAULT` at 410, and the fds already in the fd table are never passed to the guest or closed. The `msg_flags` writeback at 585-589 runs before control translation, so `D_MSG_CTRUNC` cannot be added. A guest passing a 16-byte control buffer while 60 fds arrive leaks all 60.
Fix: in `sk_ctl_h2g`, on break or fault, walk the remaining host cmsgs and `close()` each `int` in `CMSG_DATA` for `SOL_SOCKET/SCM_RIGHTS`; return a truncated flag; move the msg_flags store after the control store and OR in `D_MSG_CTRUNC`. Pre-check `m.msg_control` writability before calling `recvmsg`.

**R2. Zero-length host address makes `recvfrom` fail with `EINVAL` after consuming data** (`ios_svc_bsd_sock.c:206, 604-607`; `590-596` for `recvmsg`).
Connected stream sockets return `msg_namelen == 0` on both hosts. `sk_sa_h2g` rejects `slen < 2` with `-D_EINVAL`, `sk_store_addr` propagates it, and line 607 reports `EINVAL` to the guest even though the bytes were read. XNU writes `*fromlen = 0` and succeeds. On the `recvmsg` path the failure is silent and `msg_namelen` is left at the guest's input value.
Fix: at line 206 add `if (slen == 0U) { return 0; }` before the `< 2` check.

**R3. `SO_ERROR` returns the host errno untranslated** (`ios_svc_bsd_sock.c:299-311`). On a Linux host a failed non-blocking `connect` yields `ECONNREFUSED = 111` in the guest buffer; Darwin expects `61`. The generic non-`SOL_SOCKET` passthrough at line 105 has the same class of hazard (e.g. Darwin `IPV6_V6ONLY 27` vs Linux `26`).
Fix: when `a[1] == D_SOL_SOCKET && a[2] == D_SO_ERROR && hlen >= 4`, run the value through `a32_ios_host_to_darwin_errno` before the copy at line 308.

**R4. `kevent_qos` (374) uses a 32-byte kevent64 prefix; `struct kevent_qos_s` is 72 bytes** (`ios_svc_bsd_kevent.c:207-210, 217, 236-239, 298-305, 485-486`).
XNU layout is `ident u64 @0, filter i16 @8, flags u16 @10, qos i32 @12, udata u64 @16, fflags u32 @24, xflags u32 @28, data i64 @32, ext[4] @40`. The code reads `fflags` from the `qos` slot, `data` from `udata`, `udata` from `fflags|xflags`, and every entry after the first from the wrong address. The eventlist is written back with the same wrong stride and offsets.
Fix: add a 72-byte `kq_evqos_t` with the XNU field order, a `_Static_assert(sizeof == 72)`, a dedicated decode branch, and emit with `qos = 0, xflags = 0, ext = {0}`; pass `esz = 72U` at line 486.

**R5. `EV_CLEAR` (0x20), `EV_DISPATCH` (0x80) and `EV_RECEIPT` (0x40) are not implemented** (`ios_svc_bsd_kevent.c:39-44, 131-175, 371-389`).
Every knote is level-triggered. `EVFILT_WRITE | EV_ADD | EV_CLEAR` on a connected socket returns on every call without ever blocking, so a guest loop waiting for "writable again" spins. `EV_DISPATCH` sources are not disabled after delivery and re-fire. `EV_RECEIPT` changes produce no `EV_ERROR` receipt entry, so the guest reads an unrelated event or none.
Fix: store `clear`, `dispatch` on `kq_knote_t`; for `clear` keep `last_data`/`last_ready` and report only on a not-ready to ready transition or `FIONREAD` growth; set `disabled = true` after delivering a `dispatch` note; for `EV_RECEIPT` emit the change back with `EV_ERROR` and `data = 0` when `nev > 0`.

**R6. Timer units: only `NOTE_SECONDS` is recognised; 64-bit `data` is clamped to `int32`** (`ios_svc_bsd_kevent.c:171-172, 306-308`).
`NOTE_USECONDS (0x2)` and `NOTE_NSECONDS (0x4)` fall into the millisecond branch, so a 500 ms timer in µs becomes 500 s and in ns becomes 500,000 s. For `kevent64`/`kevent_qos` the clamp at 307 turns any ns period above 2.147 s into 2.147 s.
Fix: pass `int64_t data` into `kq_knote_change`; select the multiplier by `fflags & (1|2|4)` (1e9, 1e3, 1; default 1e6); reject `NOTE_MACHTIME`/`NOTE_ABSOLUTE` with `EINVAL` or implement them explicitly.

**R7. Normal EOF reported as `EV_ERROR` with `data = EBADF`** (`ios_svc_bsd_kevent.c:186-190, 385-387`).
`POLLHUP` on a pipe or socket whose peer closed is ordinary EOF. XNU sets only `EV_EOF` with `data` = bytes still readable. The code sets `EV_EOF | EV_ERROR` and `data = 9`, so a guest checking `flags & EV_ERROR` treats a clean close as a kqueue failure, and pending bytes are never reported because the `FIONREAD` path is skipped.
Fix: only `POLLNVAL` maps to `EV_ERROR`/`EBADF`; for `POLLHUP|POLLERR` set `EV_EOF`, still run `FIONREAD` for READ, and return `data` as the byte count.

**R8. Blocked `kevent` is never woken by concurrent changes; explicit timeouts above 60 s return early** (`ios_svc_bsd_kevent.c:80, 92-104, 340-360, 406-416`).
The pipe `wfd` is allocated but never written and `rfd` is never polled, so a thread sleeping in `poll`/`nanosleep` does not see a knote added, deleted, or the kqueue closed by another thread until the sleep ends. A guest-supplied timeout of 120 s with any READ/WRITE knote takes the `wait_ms` path, is capped to 60 s at line 344-345, and returns 0 events at 60 s. The `nfds == 0` path at 352-355 sleeps the full duration, so behaviour differs by whether fd knotes exist.
Fix: include `rfd` with `POLLIN` in `pfds`, `write(wfd, "", 1)` in `kq_knote_change`/`a32_ios_kq_close`, drain `rfd` after `poll`; loop on `poll` until the computed deadline instead of returning after one 60 s slice.

**8 RESIDUAL DEFECTS**
