**`be664a0`: both findings cannot be marked resolved.**

1. **#3 — STILL OPEN, P1.** Full 64-bit epochs and pre-write checks are present in [mem.c:694](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:694) and [emit_mem.c:476](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:476), but serialization is broken:
   - Interpreter helpers lock a static `atomic_flag`; DBT locks a different, window-relative word. They do not exclude each other. [mem.c:62](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:62), [emit_mem.c:135](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:135).
   - SWL/SWR branches for offsets 0–2 jump past lock acquisition, then execute the common unlock. [emit_mem.c:339](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:339), [emit_mem.c:408](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:408).
   - Host-fault recovery clears only the interpreter lock, leaving an acquired DBT lock held. [hostfault.c:178](/Users/angerman/Projects/zw3rk/mips32rt/src/os/hostfault.c:178), [mem.c:82](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:82).
   - Lock acquisition overwrites `w30`, although emitted `RET` uses `x30`; the misaligned-store exit reaches that return after acquiring the lock. [emit_mem.c:124](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:124), [emit_mem.c:275](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:275), [a64_emit.c:736](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/a64_emit.c:736).

2. **#4 — PARTIALLY RESOLVED.** Truncate dispatch now reaches `mips32_file_sc_truncate`. [syscall_min.c:479](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:479), [syscalls.c:799](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:799). Guest helpers now call **`mips32_vm_tlb_miss`**, but the permitted files do not establish its connection to the requested **`mips32_vm32_handle_miss`**. DBT memory emission still uses direct accesses. Full miss-path wiring therefore remains unverified within this scope. [mem.c:208](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:208), [emit_mem.c:259](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:259).

Confirmed `master` HEAD `be664a0`. Static inspection only; no files changed, builds, tests, or Docker.

Verdict: ACTION_REQUIRED.