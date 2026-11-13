# P32 Round-12 Deep-Dive 6 — Syscall / Marshaling / procfs / Backends

Scope (read-only, no builds/tests): `src/os/syscalls.c`, `src/os/syscalls_file.c`, `src/os/syscalls_dyn.c`, `src/os/convert.c`, `src/os/procfs.c`, `src/os/backend_common.c`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/rt32/ppc32_host.c`.

| ID | Severity | Location | Finding |
|---|---|---|---|
| P32-R12-1 | `BUG` | `src/os/syscalls_dyn.c:115-149`, `src/os/syscalls_dyn.c:314-398` | `statx` leaves UAPI reserved/spare bytes stale instead of zero |
| P32-R12-2 | `BUG` | `src/os/syscalls_file.c:192-194`, `src/os/syscalls_file.c:231-233` | Host `EDEADLK` 35 passed to PPC guest expecting 58 |

## P32-R12-1: `statx` reserved holes not zeroed

`dyn_put_statx()` (`src/os/syscalls_dyn.c:115`) and `dyn_put_stat_fallback()` (`src/os/syscalls_dyn.c:314`) check only `ppc32_range_ok(va,256)` then emit members with `ppc32_st*be()` at `0,4,8,16,20,24,28,32,40,48,56,64,72,80,88,96,104,112,120,128,132,136,140,144`.

Unwritten per Linux `statx` UAPI: `__spare0` at 30-31, `__reserved` at 76-79, 92-95, 108-111, 124-127, `__spare2+` at 152-255 (~122 B). No `memset`.

Repro: fill guest 256 B with `0xAA`, call `statx(383)`, read back offsets above. Translator returns `0xAA`; kernel/`qemu-ppc -cpu 750/e500v2` returns `0`. Sibling `ppc32_put_stat/stat64` in `src/os/convert.c:240,269` do `memset(&gs,0)`, proving the contract.

Fix (surgical, also gains `prot`+coherence via safe copyout): build a zeroed local and publish once:

```c
uint8_t tmp[DYN_STATX_SIZE];
memset(tmp, 0, sizeof tmp);
/* fill tmp BE with memcpy, then: */
return (long)ppc32_vm_copyout_safe(ctx, va, tmp, sizeof tmp);
```

## P32-R12-2: `EDEADLK` not translated PPC 58 vs host 35

PPC `EDEADLK=58`; Linux asm-generic/aarch64 host `EDEADLK=35` (`ENOSYS=38` matches, no fix needed). No `host2ppc` errno helper exists; lock arms return host value directly:

```c
// src/os/syscalls_file.c:193-194 and :232-233
r = fcntl((int)fd, (int)cmd, &hs);
if (r < 0) return -(long)errno;
```

Repro: circular `F_SETLKW`/`F_SETLKW64` (`12/13/14` → `5/6/7` at `src/os/syscalls_file.c:212-237`) deadlock. Host returns 35; guest sees `r3=35,CR0.SO=1`, expected `r3=58`. Guest libc `errno==58` check fails.

Fix:

```c
static long ppc_errno_host2ppc(int e) {
#ifdef __linux__
    if (e == 35) return 58L;
#endif
    return (long)e;
}
/* lock arms: return -ppc_errno_host2ppc(errno); */
```

## Clean (0 defects)

`sc` dispatch (`r0`, `r3..r8`, `r3`+`CR0.SO`, `nip+=4`), `pipe r3=0`+BE `fd[2]` (`src/os/proc.c:763-788`), `pread64 hi=r6/lo=r7` (`src/os/syscalls.c:571-575`), `_llseek` pair+BE result (`src/os/syscalls_file.c:285-299`), `stat/stat64` BE+sizes (`src/os/convert.h:145-160`), `clock_gettime/64` (`src/os/syscalls.c:361-389`), `ioctl` allowlist BE (`src/os/syscalls_file.c:332-406`), `O_* LARGEFILE/DIRECT` swap (`src/os/syscalls_file.c:52-78`), `MAP_*` passthrough (numerically identical), `fcntl64 12/13/14→5/6/7`+`flock64` (`src/os/convert.h:161-164`), `/proc/self/{exe,maps,cmdline,stat,auxv}`+`readlink/at`, sysroot fallback, `/dev/a32host` probe (`src/rt32/ppc32_host.c:33-68`): no concrete behavioral defect found. Unimplemented `pwrite64/truncate/statfs/socket/poll` correctly take documented `-ENOSYS`.

Audit stands as delivered — no change from that output.

