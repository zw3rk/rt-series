**#3 remains open; #4 is resolved within the requested Class-A scope.** Confirmed `master` at `fae96cf`; inspected both requested commits.

1. **#3 — PARTIALLY RESOLVED.**
   - SWL/SWR acquire the lock before the offset dispatch. [emit_mem.c:345](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:345)
   - SH/SW check alignment before acquiring the lock, so misaligned returns cannot retain it. [emit_mem.c:283](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:283)
   - SC now uses `A64_TMP1` instead of `x30`. However, `fae96cf` also replaces the **X-width** mismatch branch with `a64_emit_cbz_w_placeholder`: the 64-bit XOR is checked through its low 32 bits, allowing epochs differing only in their upper half to pass. Restore the X-width placeholder. [emit_mem.c:496](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:496), [emit_mem.c:498](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:498)

2. **#4 — RESOLVED under Class A.** Direct window accesses are consistent with the stated architecture. The VM32 helper validates mappings/permissions and fills TLB entries, and guest memory validation calls it. All four truncate variants reach `mips32_file_sc_truncate`. [vm32.c:143](/Users/angerman/Projects/zw3rk/mips32rt/src/vm/vm32.c:143), [mem.c:258](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:258), [syscall_min.c:479](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscall_min.c:479), [syscalls.c:803](/Users/angerman/Projects/zw3rk/mips32rt/src/os/syscalls.c:803)

Static inspection only; no modifications, builds, tests, or Docker.

Verdict: ACTION_REQUIRED