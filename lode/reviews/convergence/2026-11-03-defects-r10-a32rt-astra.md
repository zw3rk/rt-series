# A32-R10 Static Audit — Threading / Lifecycle / Futex

Scope: `src/os/os_sys_fork_time.c`, `src/os/os_sys_thread_sig.c`, `src/os/os_sys_sig_time.c`, `src/os/sys_priv.h`, `src/os/backend_linux.c`, `src/os/backend_darwin.c`, `src/os/backend.h`, plus `src/a32rt.h`, `src/vm/vm_jit_mem.c`, `src/vm/vm32.c`, `src/vm.c`, `src/signals.c`, `src/os/os_sys_fs_arm.c`, `src/os/os_sys_sock.c`.

## 1. `clone` — verified, no defect

- Child `r0 = 0`: [os_sys_fork_time.c:420](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c) (thread), [:499](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c) (process fork).
- `TPIDRURO` init: `child_ctx->tls_tp = a3` on `CLONE_SETTLS` [:434-436](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c), inherited otherwise; `__kuser_get_tls` reads `tls_tp` (`src/elf32.c:570-576`, `src/interp/interp_a32.c:833`).
- `PTID/CTID` stored synchronously before `started=1`; parent spins on `started` [:461-465](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c), so no parent-return-before-store race. Validation `PROT_WRITE` + `EINVAL` for `SIGHAND`-without-`VM` / `THREAD`-without-`SIGHAND` [:403-410](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c).
- `clear_child_tid` zero-store + `FUTEX_WAKE,1`: [os_sys_thread_sig.c:10-20](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_thread_sig.c). `guest_write` fails safe on `0`/unmapped; slot lifecycle is heap `calloc` → detached `pthread` → `free` after cleanup [:22-52](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_thread_sig.c).

## 2. `fork`/`vfork`/`wait4` — verified, no defect

- Quiescence `JIT → VM → vmfile`, no inversion: `fork_prepare` holds JIT lock + drains `exec_readers` (`src/vm/vm_jit_mem.c:122-127`); `a32_vm_sync_ctx` takes VM lock only briefly (`src/vm.c:890-899`); VM paths release VM lock before `a32_vm_invalidate_jit` (`src/vm.c:552-623,762-884`); truncate takes only `g_vmfile_lock` (`src/vm/vm_file.c:375-470`); futex takes none.
- `LDREX`/`STREX` cleared on every child path: [:266-268,387-389,421-422,479-481](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_fork_time.c) + `a32_vm32_ll_clear_owner` (`src/vm/vm32.c:558-566`).
- Single-thread reset: signals blocked across `fork()` + `fork_child_reset` drops `g_jit_lock`, `g_vm_lock`, `g_vmfile_lock` (`src/vm/vm_jit_mem.c:137-142`, `src/vm.c:50-55`, `src/vm/vm_file_map.c:286-292`).

## 3. `execve` — verified, no defect

Host `execve` replaces the image, terminating sibling host threads, closing `CLOEXEC`, and resetting VM/JIT by construction. Signal carry `CAUGHT→DFL`, `IGN` preserved, mask + pending carried via `A32RT_EXEC_*` and filtered (`src/os/os_sys_sig_time.c:660-694`, `src/main.c:122-156`). `AT_EMPTY_PATH` `CLOEXEC` save/clear/restore [:581-587,733-737](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sig_time.c).

## 4. `futex`/`tgkill` — verified, no defect

`uaddr`/`uaddr2` range-checked, timeout via `read_guest_timespec`, `PRIVATE` stripped for dispatch but full `op` passed to host [:792-829](/Users/angerman/Projects/zw3rk/a32rt/src/os/os_sys_sig_time.c); host kernel does the atomic compare (no lost wakeup); `EINTR`/`EINVAL` propagated. `tkill`/`tgkill` forward guest `pid`/`tid` = host values (`src/os/os_sys_fs_arm.c:553-575`).

## Summary

| ID | Area | Finding |
|----|------|---------|
| — | Threading / `clone` / `fork` / `execve` / `futex` | `0 defects found` |

No concrete, reproducible behavioral bug was found. No files were modified and no builds or tests were run.

