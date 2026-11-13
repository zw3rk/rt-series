**RC-U5-C-r2 — a175916: ACTION_REQUIRED.**

The work order has four unnumbered U5-C bullets. Below, 2.1–2.12 expand those requirements, grouping the split-register file offsets together. Citations refer to the reviewed [worktree](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32).

| Item | Status | Finding |
|---|---|---|
| **2.1 — sigaction** | **RESOLVED** | Correct 16-byte read/write layout, mask at +8: [signal.c:436](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/signal.c:436), lines 448, 469–470. Nonzero-mask install/readback coverage added in [u5c-sigmask.S:30](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/test/fixtures/u5c-sigmask.S:30). |
| **2.2 — rt_sigframe** | **RESOLVED** | Required offsets and 944-byte size match: [rv32_frame.h:20](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/rv32_frame.h:20), lines 24–28. |
| **2.3 — FP address wrapping** | **RESOLVED** | Both FP load/store paths use `rv_ea()`: [interp.c:168](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/core/interp.c:168), line 197. |
| **2.4 — mmap2 offsets** | **STILL OPEN** | Main paths scale correctly, but worker paths still pass raw page counts as byte offsets: [runtime_main.c:2691](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/runtime_main.c:2691), line 2961. The worker eligibility check still requires byte alignment at line 5672. |
| **2.5 — _llseek** | **RESOLVED** | Five arguments, high/low reconstruction, and 64-bit result copyout implemented: [file.c:1059](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/file.c:1059). |
| **2.6 — pread64/pwrite64/ftruncate64 pairs** | **RESOLVED** | Uses unpadded RV32 pairs: `a3:a4` for positioned I/O and `a1:a2` for truncation: [file.c:624](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/file.c:624), line 1354. The work order’s blanket `a4:a5` wording is inaccurate. |
| **2.7 — futex_time64 (422)** | **RESOLVED** | Runtime dispatch reaches the existing 16-byte timeout decoder: [runtime_main.c:5884](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/runtime_main.c:5884), [futex.c:517](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/futex.c:517). |
| **2.8 — clock_nanosleep_time64 (407)** | **RESOLVED** | Accepted for RV32 and routed through clock/16-byte timespec handling: [sleep.c:204](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/sleep.c:204), lines 221–259. Existing multiworker sleep restrictions remain. |
| **2.9 — ppoll_time64 (414)** | **STILL OPEN** | Handler exists, but the runtime’s multiworker allowlist admits 73 and omits 414, returning `EOPNOTSUPP`: [runtime_main.c:6015](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/runtime_main.c:6015), lines 6021–6030. |
| **2.10 — pselect6_time64 (413)** | **STILL OPEN** | RV32 fd sets still round to 64-bit words: [poll.c:463](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/poll.c:463). For `nfds=1`, this copies eight bytes instead of four, risking overread/overwrite or false `EFAULT`. Also omitted from the multiworker allowlist above. |
| **2.11 — utimensat_time64 (412)** | **STILL OPEN** | Valid negative `tv_sec` values incorrectly return `EINVAL`: [metadata.c:256](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/metadata.c:256). Additionally, line 442 incorrectly assigns ordinary `utimensat` to syscall 280 (`bpf`); its number is 88. |
| **2.12 — statx (291)** | **STILL OPEN** | Empty-path branches discard guest synchronization flags, including `AT_STATX_FORCE_SYNC`: [metadata.c:188](/Users/angerman/Projects/zw3rk/rvrt-u5c-rv32/src/linux/metadata.c:188), line 198. |

Verification was limited to `git show a175916` and source inspection. No tests, Docker runs, or file modifications.