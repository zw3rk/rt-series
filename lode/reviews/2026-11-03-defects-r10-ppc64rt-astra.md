# Round-10 Deep-Dive 4 Audit — Threading / Lifecycle / Futex

Read-only audit. No subagents, no file modifications, no builds or tests.

## Verdict

**0 defects found** across the audited subsystem.

No concrete, demonstrable behavioral bug was found in `clone`/`fork`/`vfork`/`execve` lifecycle, `atfork` handling, `tgkill` quiescence, or `futex`. No `P64-R10-*` IDs issued.

## 1. `clone` / `clone3`

Clean. `src/os/linux_abi.c:30-61` enforces the pthread profile and documents `clone3`/PIDFD as out of scope. `src/os/threads.c:48-60` copies parent state, sets `r1` from stack, `r13` only on `SETTLS`, and `r3 = 0`. `CR0.SO = 0` is established by the caller via `ppc64_syscall_apply_return` in `src/os/syscalls_p4.c:490` and `src/os/syscalls.h:101-128`. `src/os/threads.c:97-122` plus `src/os/syscalls_p4.c:244-248` do the 32-bit LE zero store and cooperative wake. Slot allocation, `clear_tid` capture in `src/os/syscalls_p4.c:485-497`, and `FREE` on `exit`/`exit_group` match the cooperative model.

## 2. `fork` / `vfork` / `wait4` / `waitid`

Clean for dispatched paths. `src/os/proc.c:428-458` implements `fork` via host `fork` with Darwin `kqueue` rebuild via `src/os/syscalls.c:196-214`. `wait4` option mask in `src/os/proc.c:568` and `waitid` type/option checks in `src/os/proc.c:639-646` match Linux. Empty `vm_file_atfork_child` in `src/vm/vm_file.c:47-49` is benign: after host `fork` address spaces separate, and the stale ASID still tags only the child-local tables. `vfork`/`waitid` helpers have no guest-number dispatch, consistent with frozen `src/os/syscall_nr.h` and the `fork`+`execve`+`wait4` Phase-4 gate; not reported as a bug.

## 3. `execve`

Clean. `src/os/proc.c:460-551` stages path/argv/envp boundedly, injects `PPC64RT_EXEC_SIG*` with override semantics, and calls host `execve`; sibling termination, `O_CLOEXEC`, and VM/TLB/DBT reset are effected by the host image replacement. Signal inheritance in `src/run/sigdeliver.c:108-229` with `src/run/core.c:553-579` resets caught handlers via fresh `run_sig_reset`, preserves `IGN`, and drops handoff words.

## 4. `futex` + `tgkill` quiescence

Clean. `src/os/syscalls_p4_futex.c:223-424` does 32-bit LE compare, `EAGAIN` on mismatch, signed `sec`/`nsec` validation, relative versus absolute deadline via `p4_futex_deadline`, parent re-check loop, and bounded `p4_sleep_until_earliest` with `EAGAIN` when deadline-free. No lost wakeup is possible in the cooperative scheduler. `src/os/backend_futex.c:68-242` validates `bitset`, timeouts, and value mismatch. `src/vm/vm_quiesce.c:229-380` bounds `tgkill` preemption with a 50 ms park timeout and `EAGAIN` unwind without mutation.

