# Round-11 Deep-Dive 5 audit: signals / altstack / frames / host faults

Read-only. No subagents, edits, builds, or tests. Files read: `sigact.c`, `sigframe.c`, `sigframe_mips64rt.h`, `signal_core.c`, `syscall_nr.h`, `cpu.h`, `syscall_min.c`, `threads.c` (host-fault guard), `backend_state.c`, `backend.h`, `mem.c`, `mem_recover.c`, `dbt.c`, `trampoline_a64.S`, `quiesce.c/h`, `exec.c`. `src/os/safe_syscall_a64.S` does not exist in this tree; host-fault recovery lives in [threads.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/threads.c:546) (`mips_hostfault_install/run/disarm`) plus `dbt/mem_recover.c`.

| ID | Where | Impact |
|---|---|---|
| M64-R11-1 | [sigact.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:336) N32BE set | Block bit mislands, deliver-while-blocked |

## M64-R11-1 — BUG: N32 `sigset_t` marshaled as 2×u64 in `sigact.c`, wrong on N32BE

N32 kernel `sigset_t` is 4×u32 ([header](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigframe_mips64rt.h:49)); N64 is 2×u64. On LE the two encodings coincide; on BE they swap each 32-bit half. These sites use unconditional 8-byte accesses with no `is_n32` branch:

- [procmask read](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:336): `nw0 = getn(p, 8, be)`, `nw1 = getn(p+8, 8, be)`
- [procmask old-set report](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:354): `putn(img, cur0, 8, be)` (+8)
- [pending report](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:556): `putn(img, w0, 8, be)` (+8)
- [suspend mask install](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:607): `getn(p, 8, be)` (+8)

The same file already does it right for `rt_sigaction` N32 ([read](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:247)/[report](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigact.c:279) as 4×u32 splits), and [sigframe.c](/Users/angerman/Projects/zw3rk/mips64rt/src/os/sigframe.c:371) saves/restores the N32 `uc_sigmask` as 4×u32, proving the 8-byte sites inconsistent.

Reproduction: N32BE guest `rt_sigprocmask(SIG_BLOCK, {SIGUSR1=16})`, then raise `SIGUSR1`. Expected blocked + pending; actual delivers while blocked. Independent corroboration: `docs/h2-report.md` G7 pins exactly `H2SIG-FAIL still-blocked, H2SIG-FAIL pending` on `h2sig-n32be` only, with N64BE green on identical handler code.

Fix: add `n32` detection to the three functions and use the existing 4×u32 pattern on N32, e.g. `getn(p,4,be)|(getn(p+4,4,be)<<32)` / matching `putn` splits, mirroring `rt_sigaction`/`sigframe.c`.

## Clean (0 defects)

- Signal numbering/range (`1..128`, 16-byte set, `KILL=9`/`STOP=23` unblockable/uncatchable, mask ops `1/2/3`, `kill/tkill/tgkill`, `wait4` status endian handling): no behavioral defect found.
- `sigaltstack` sizes (`N64 24` / `N32 12`), `MINSIGSTKSZ=2048`, `SS_ONSTACK/DISABLE/AUTODISARM`, on-stack `EPERM`: no defect found.
- Frame sizes (`N64 808` / `N32 792`, `rs_ass[4]`, `rs_pad[2]`, `rs_info@24`, `rs_uc@152`, 600-byte `sigcontext`, no `sc_cause`), `rt_sigreturn 5211/6211`, `$a0/$a1/$a2/$t9/$ra`, delay-slot `sc_pc`, `llbit=0`, GPR/`$0`/HI/LO/FPR/FCSR/PC restore, `x18` untouched: no defect found.
- Host-fault guard (`setjmp`, unblock-before-`longjmp`, pool check, foreign-forward, precise-pc resolve) and `trampoline_a64.S`: no defect found.

