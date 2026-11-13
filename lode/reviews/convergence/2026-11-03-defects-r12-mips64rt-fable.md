Here's the complete static review of commit `a2c9cb1` against M64-R12-1.

---

## M64-R12-1: **VERIFIED**

The commit correctly remediates every item in the defect report.

### Linux (`#else`) branch — all 8 mappings correct

| Host (asm-generic) | MIPS | Errno name | Line |
|---|---|---|---|
| 35 → 45 | EDEADLK | `errno_map.h:60` |
| 36 → 78 | ENAMETOOLONG | `errno_map.h:62` |
| 38 → 89 | ENOSYS | `errno_map.h:64` (preserved) |
| 39 → 93 | ENOTEMPTY | `errno_map.h:66` |
| 40 → 90 | ELOOP | `errno_map.h:68` |
| 75 → 79 | EOVERFLOW | `errno_map.h:70` |
| 95 → 122 | EOPNOTSUPP | `errno_map.h:72` |
| 122 → 1133 | EDQUOT | `errno_map.h:74` |

All values match `arch/mips/include/uapi/asm/errno.h` as cited in the defect report and corroborated by the ABI matrix.

### Darwin (`__APPLE__`) branch — all 6 corrections correct

| Case | Before (asm-generic) | After (MIPS) | Errno name | Line |
|---|---|---|---|---|
| 11 | 35 | 45 | EDEADLK | `errno_map.h:29` |
| 62 | 40 | 90 | ELOOP | `errno_map.h:41` |
| 63 | 36 | 78 | ENAMETOOLONG | `errno_map.h:43` |
| 66 | 39 | 93 | ENOTEMPTY | `errno_map.h:45` |
| 69 | 122 | 1133 | EDQUOT | `errno_map.h:47` |
| 84 | 75 | 79 | EOVERFLOW | `errno_map.h:52` |

### Call-site integration verified

`l2a_errno_from_host` is called at `syscalls.c:112` and `syscall_min.c:184` via `l2a_ret`/`sc_ret`, which extract the positive errno with `-raw` before passing to the mapper. The flow is correct.

### No regressions introduced

The switch has no duplicate cases, no fall-throughs, and the `default` pass-through is preserved for errnos that happen to share asm-generic and MIPS values.

### Curated C11 compliance: PASS

- No VLAs
- No `.c` includes anywhere in `src/`
- `errno_map.h`: 140 lines (limit 900)
- Uses `<stdint.h>`, `static inline`, `#if defined()` — clean C11
- No `sprintf`/`strcpy`/`strcat`

---

## Observations (not regressions)

**1. Stale header comment** (`errno_map.h:7,10`): Lines 7 and 10 still read *"MIPS follows the asm-generic numbers except ENOSYS"* and *"Linux hosts differ only on ENOSYS."* Both are now contradicted by the 8-case Linux switch the commit added. Documentation-only; no behavioral impact.

**2. Pre-existing Darwin EOPNOTSUPP gap** (`errno_map.h:26-56`): `sigact.c:661,692` return `-(int64_t)EOPNOTSUPP`. On Darwin, `EOPNOTSUPP` is 102, which falls through to `default` and delivers 102 to the guest instead of MIPS 122. The Linux branch correctly maps 95 → 122. This was not reported in M64-R12-1 and is not introduced by this commit, but it's the same class of bug the commit fixes on the Linux side. A `case 102: return 122;` in the Darwin switch would close it.
