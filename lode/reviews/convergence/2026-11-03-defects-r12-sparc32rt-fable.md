Good — `procfs_serve_bytes` correctly applies `O_CLOEXEC` and `O_NONBLOCK` from `host_flags` (lines 95-101), and the four callers now pass `host_flags` instead of the hardcoded `O_RDONLY`. The fix is complete.

---

## Static Review: Commit `3fb9976` — Round-12 Remediation (S32-R12-1..3)

### S32-R12-1: Wrong SPARC errno values — **VERIFIED**

**Defect:** `sparc_errno_from_host` returned asm-generic errno numbers instead of SunOS/SPARC numbers for 4 errnos.

**Evidence:** The diff changes `syscalls_min.c:144-148` from `38/36/40/75` to `90/63/62/92`, which matches `arch/sparc/include/uapi/asm/errno.h`:

| errno | Was (asm-generic) | Now | SPARC kernel UAPI |
|---|---|---|---|
| `ENOSYS` | 38 | 90 | 90 |
| `ENAMETOOLONG` | 36 | 63 | 63 |
| `ELOOP` | 40 | 62 | 62 |
| `EOVERFLOW` | 75 | 92 | 92 |

The comment is also corrected: "SunOS numbering" and "SPARC as 90" (was "SPARC as 38"). All 28 unchanged errnos (1-34) are identical between generic and SPARC, so they're correct as-is. The `default` fallthrough returns the raw host value, which is valid for the AArch64 Linux host where remaining errnos match generic numbering — appropriate given the review doc notes only listed errnos are produced by this layer.

**Verdict: VERIFIED. No regressions.**

---

### S32-R12-2: `TCGETS` can never match, and succeeds without a payload — **PARTIAL**

**Defect (a):** Constant was `0x80245408` (wrong direction bits), so `SP_TCGETS` never matched a real guest `ioctl(fd, 0x40245408, &t)`.

**Fix for (a):** `syscalls_time.c:32` changed to `0x40245408U`. **Correct.**

**Defect (b):** The old match arm returned 0 on `isatty` without storing anything.

**Fix for (b):** Lines 360-387 now implement a full TCGETS handler: `EFAULT` check, `isatty` check, `tcgetattr` call, BE marshaling of 4 flag words + `c_line` + 17 `c_cc` bytes into a 36-byte buffer, then `l2a_store`. The struct layout (4×BE u32 flags, u8 c_line, u8 c_cc[17], 2 padding = 36 bytes) matches the SPARC userspace `struct termios` with NCCS=17 (consistent with the 0x24=36 size encoded in the ioctl number). The `<termios.h>` include is added. **Core fix is correct.**

**Newly introduced issues in the TCGETS handler:**

1. **`c_cc` index mismatch (medium severity).** The code copies `ht.c_cc[i]` to guest `c_cc[i]` at `syscalls_time.c:382-383` without remapping indices. AArch64 (generic) and SPARC use different `c_cc` index assignments:

   | Index | AArch64 (host) | SPARC (guest) |
   |---|---|---|
   | 5 | VTIME | VEOL |
   | 6 | VMIN | VEOL2 |
   | 11 | VEOL | VDSUSP |
   | 16 | VEOL2 | (unused) |

   Indices 0-4, 7-10, 12-15 are the same on both. The practical impact is limited (VEOL/VEOL2/VDSUSP are usually disabled, and VTIME at index 5 accidentally lands correctly for raw-mode reads), but a guest program inspecting or setting VMIN in canonical-to-raw transitions via this returned `termios` will read the wrong value.

2. **`c_lflag` FLUSHO/DEFECHO bit mismatch (low severity).** SPARC has `DEFECHO=0x1000, FLUSHO=0x2000`; generic has `FLUSHO=0x1000` (no DEFECHO). The code stores host `c_lflag` directly with only endianness conversion (`syscalls_time.c:378`), so host FLUSHO (0x1000) would appear as DEFECHO to the guest. FLUSHO is rarely set in practice.

3. **`tcgetattr` failure fallthrough (`syscalls_time.c:374-386`).** If `tcgetattr` fails after `isatty` succeeds (unlikely but possible race), the code falls through and stores the zero-filled buffer instead of returning `-errno`. Minor — the window is tiny and the result is a valid (all-zero) termios rather than garbage.

**Verdict: PARTIAL.** The two primary defects (wrong constant, empty success) are fixed. The handler is now functional and stores a BE termios. However, the `c_cc` index remapping and `c_lflag` bit translation are missing, making the marshaled payload incorrect for indices 5/6/11/16 and the FLUSHO bit.

---

### S32-R12-3: `/proc/self/{maps,cmdline,stat,auxv}` discard guest `O_CLOEXEC` — **VERIFIED**

**Defect:** The four `procfs_open_*` helpers hardcoded `O_RDONLY` in their call to `procfs_serve_bytes`, discarding the guest's `host_flags` (which could include `O_CLOEXEC`/`O_NONBLOCK`).

**Evidence:**
- `procfs.c:125`: `procfs_open_maps` signature now takes `int host_flags` (was void of it).
- `procfs.c:163`: passes `host_flags` to `procfs_serve_bytes` (was `O_RDONLY`).
- Same pattern for `procfs_open_cmdline` (`:170,197`), `procfs_open_stat` (`:205,227`), `procfs_open_auxv` (`:234,248`).
- All four call sites in `rt32_procfs_openat` (`procfs.c:263,266,269,272`) now pass `host_flags`.
- `procfs_serve_bytes` (`procfs.c:95-101`) already correctly applies `O_CLOEXEC` via `fcntl(F_SETFD)` and `O_NONBLOCK` via `fcntl(F_SETFL)` when the respective bits are set in `host_flags`.
- `procfs_open_exe` was already correct (not changed).

**Verdict: VERIFIED. No regressions.**

---

### Curated C11 Compliance

| Check | Result |
|---|---|
| VLAs | None (grep clean) |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None |
| Annex K (`*_s`) | None |
| File sizes | `syscalls_min.c`: 899, `syscalls_time.c`: 389, `procfs.c`: 333 — all <= 900 |

**All three files pass Curated C11 discipline.**

---

### Summary

| Item | Verdict | Notes |
|---|---|---|
| S32-R12-1 | **VERIFIED** | All 4 SPARC errnos corrected to SunOS values |
| S32-R12-2 | **PARTIAL** | Constant fixed, handler implemented and stores BE termios; `c_cc` index remapping and `c_lflag` FLUSHO bit translation missing |
| S32-R12-3 | **VERIFIED** | `host_flags` threaded through all 4 procfs helpers correctly |
| New bugs | 3 findings in TCGETS handler (see S32-R12-2) | c_cc indices, c_lflag bit, tcgetattr fallthrough |
| C11 compliance | **PASS** | No violations, all files <= 900 lines |
