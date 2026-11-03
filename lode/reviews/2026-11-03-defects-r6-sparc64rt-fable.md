# Verification report: `sparc64rt` commit `6498d0b` vs. Round-6 defects S64-R6-1..9

**Scope and method.** Static inspection of `git show 6498d0b` (8 files, +441/−84) plus targeted `git grep` at that revision. No build, test, container, or QEMU run. `6498d0b` is current `HEAD` of `sparc64rt` (parent `1fc64d4`, the revision astra audited).

**Summary:** 6 VERIFIED, 3 PARTIAL, 0 NOT FIXED, 0 REGRESSION.

| ID | Sev | Verdict | One-line |
|---|---|---|---|
| S64-R6-1 | HIGH | VERIFIED | `F_SETFL` parentheses balanced |
| S64-R6-2 | HIGH | VERIFIED | Big lock dropped around `read`/`write` in read, write, readv, writev |
| S64-R6-3 | HIGH | VERIFIED | readv destinations pinned before host input consumed |
| S64-R6-4 | HIGH | PARTIAL | fp.c / fp_conv.c / fp_commit fixed; `fp_sd.c` arithmetic still publishes before commit |
| S64-R6-5 | HIGH | PARTIAL | SIGFPE + `FPE_FLT*` delivered via raw-word/FSR refinement; no explicit FP trap cause, `ftt` not checked for FPops |
| S64-R6-6 | MED | VERIFIED | `faccessat` passes 0 flags; `faccessat2` (439) separate |
| S64-R6-7 | MED | PARTIAL | TCGETS now copies a 36-byte termios through checked store, but flags/`c_cc` are not translated to SPARC layout |
| S64-R6-8 | MED | VERIFIED | `O_DIRECTORY`/`O_PATH` added; `O_SYNC` full-mask, `O_DSYNC` distinguished |
| S64-R6-9 | MED | VERIFIED | `clock_getres(clk, NULL)` returns 0 |

---

## S64-R6-1 — `F_SETFL` unbalanced parenthesis — **VERIFIED**

`src/os/syscalls_ext.c:536-539` (post-commit):
```c
if (((rest & (uint64_t)SP_O_NDELAY) == (uint64_t)SP_O_NDELAY) ||
    ((rest & (uint64_t)SP_O_NONBLOCK) != 0U) ||
    (((rest & (uint64_t)0x0004U) != 0U))) {
```
Three balanced disjuncts, outer `if (` closed before `{`. The pre-image (`-` lines in the diff at the same hunk) was indeed missing a `)` after the second disjunct. Semantics unchanged (NDELAY | NONBLOCK | 0x0004 all map to `O_NONBLOCK`).

## S64-R6-2 — Blocking host I/O under `thr_big_lock` — **VERIFIED**

- `src/os/syscalls_min.c:201-203` (`sys_read`): `sparc64_thread_big_unlock(); got = read(...); sparc64_thread_big_lock();` after `prepare_write` of the destination (line 196) and before copy-out into the guest.
- `src/os/syscalls_min.c:246-248` (`sys_write`): same bracket after `mem->read` staged the chunk (line 242).
- `src/os/syscalls_ext.c:369-371` (writev) and `:403-405` (readv) in `sys_rwvec`: single host call bracketed by unlock/lock; inputs staged / destinations validated beforehand.
- `src/os/threads.h:71-72` comment updated to document the new drop points.
- `sparc64_thread_big_lock/unlock` are plain `pthread_mutex_lock/unlock` wrappers (`src/os/threads.c:170-178`), the same pattern already used for futex WAIT at `threads.c:424-438` and `threads_darwin.c:254-278`, so the drop is consistent with the existing lock discipline.

Notes (not blocking): astra's suggested "restore window-cache and DBT ownership/invalidation state on reacquisition" is not done explicitly, but the existing futex-WAIT drop point does no such restore either, so this commit introduces no new invariant gap. The `prepare_write` pin is taken before the unlock; a concurrent guest `munmap` during the blocked read is handled by the post-reacquire `mem->write` copy-out failing (existing path). Not verifiable without a run.

## S64-R6-3 — readv consumes input before checking destinations — **VERIFIED**

- New helper `l2a_range_prot_ok` at `src/os/syscalls_ext.c:246-262`: bounds check, then `mem->prepare_write` when `PROT_WRITE` requested.
- readv path `src/os/syscalls_ext.c:380-402`: iterates destinations, calls `l2a_range_prot_ok(..., PROT_WRITE)`; first invalid entry sets `valid_cnt = k`. If `valid_total == 0` → `-EFAULT` with no host I/O; otherwise `total`/`iovcnt` are capped to the valid prefix *before* `read()` at line 404, so the host never consumes bytes that cannot be scattered. This satisfies "limit the host transfer to destinations that can receive it" and "preserve partial-transfer semantics without discarding unreported bytes".
- writev path `:340-350` adds a `PROT_READ` pre-check (bounds only; readability is proven by the staging copy, as the comment states).

## S64-R6-4 — FP ops publish destination/FCC before trap check — **PARTIAL**

Fixed at every location astra cited, and more:
- `src/interp/fp_commit.c:17-29` and the static twin `src/interp/fp.c:79-98`: `fresh & tem` is evaluated first. Trap path writes `cexc` and sets `ftt = 1` (IEEE_754_exception, bits 14-16) **without** touching `aexc`; non-trap path writes `cexc`, ORs `aexc`, clears `ftt`. This fixes "commit helper updates accrued exceptions before deciding whether the instruction traps".
- `src/interp/fp_conv.c`: `cv_itos` (:187-208), `cv_xtos` (:218-240), `cv_dtoi32` (:272-293), `cv_dtoi64` (:305-325), `cv_stod` (:337-368), `sparc64_sd_sqrt_op` (:470-520), `sparc64_sd_fsmuld` (:526-595), `sparc64_sd_dtos` (:600-655) all compute into a temporary, call `sparc64_fp_commit`, and publish only on `SPARC64_STEP_CONTINUE`.
- `src/interp/fp.c`: `fp_move_s/d` (:113-138), `fp_cmp_s/d` (:150-176, `fp_fcc_write` now after commit), `fp_movcc` (:200-213), `fp_movr` (:237-250).

**Not fixed:** `src/interp/fp_sd.c` (not touched by the commit) still stores the destination before committing in the core FADD/FSUB/FMUL/FDIV paths:
```
fp_sd.c:544  sd_store(cpu, w, d->rd, o);
fp_sd.c:545  return sparc64_fp_commit(cpu, pc, d, fl);
fp_sd.c:550-551, 557-558, 562-563, 569-570, 573-574, 578-579, 586-590, 598-599, 602-603
fp_sd.c:616  sd_store(cpu, w, d->rd, o);
fp_sd.c:617  return sparc64_fp_commit(cpu, pc, d, fl);
```
e.g. `fp_sd.c:562-563` (0/0 or inf-inf style invalid → NV, `0x10`) and `:589-590` (divide-by-zero, `0x02`) overwrite `rd` before `fp_commit` can return the trap. With `TEM.NV` or `TEM.DZ` enabled, the astra defect ("invalid operation with trapping enabled overwrites its destination before returning a trap") still reproduces for the main arithmetic ops. Same temporary-then-publish transformation is needed there (~12 sites).

## S64-R6-5 — Enabled FP exception delivered as SIGILL — **PARTIAL**

What is done:
- `src/os/syscalls_sig.h:57-63`: `SPARC64_FPE_INTOVF..FLTSUB` (2..8) added.
- `src/os/sync_sig.c:350-369` `sync_fpe_code_for_cexc`: maps `cexc` bits NV→FLTINV, OF→FLTOVF, UF→FLTUND, DZ→FLTDIV, NX→FLTRES in Linux priority order.
- `src/os/sync_sig.c:376-385` `classify_raw`: `op==2, op3==0x34/0x35` (FPop1/FPop2) → `SIGFPE`.
- `src/os/sync_sig.c:528-541` `deliver`: for FPop raw words the code is recomputed from `ctx->fsr & 0x1F`; `ctx->fsr` exists (`src/core/cpu.h:132`). Combined with R6-4's `ftt=1` + `cexc` write on the trap path, the handler now sees `SIGFPE` with a meaningful `FPE_FLT*` `si_code`.

Why PARTIAL:
1. **No explicit FP exception cause.** Trap kind is still `SPARC64_TRAP_ILLEGAL` (`fp_commit.c:25`, `fp.c:93`); classification depends on the raw word being passed in `fault_addr` and decoding as FPop. This is the "refinement" path astra flagged as fragile, now extended rather than replaced.
2. **`ftt` is not consulted for FPop words.** `classify_raw` returns `SIGFPE` for *every* FPop ILLEGAL trap (`sync_sig.c:376-385`), so the `else if (signo == SIG_ILL && ftt == 1U)` branch at `:537-540` is unreachable for FPops. An FPop that trapped for a non-IEEE reason (e.g. the `qd > 15U` invalid-quad-register `ILLEGAL` at `fp.c:194-196,231-233`, or a genuinely undecoded `opf`) now becomes `SIGFPE` with a code derived from possibly stale `cexc`. Linux delivers `SIGFPE` for `unimplemented_FPop`/`invalid_fp_register` too, so the signal number is arguably right, but the code should then come from `ftt`, not `cexc`.
3. Dependent on R6-4 being complete: for `fp_sd.c` trap paths the FSR trap-state (`ftt=1`, `cexc`) is set correctly by the new `fp_commit`, so SIGFPE delivery works there even though the destination was clobbered.

## S64-R6-6 — `faccessat` reads `%o3` as flags — **VERIFIED**

`src/os/syscalls_min.c:464-469`: `SPARC64__NR_faccessat` → `sparc64_l2a_faccessat(ctx, mem, o0, o1, o2, 0)`; new `SPARC64__NR_faccessat2` → `..., o3)`. Both numbers present in the frozen table (`src/os/syscall_nr.h:321` `X(296, faccessat)`, `:437` `X(439, faccessat2)`). `sparc64_l2a_faccessat` (`syscalls_dirent.c:103`) unchanged and already accepts the flags argument.

## S64-R6-7 — `TCGETS` succeeds without writing termios — **PARTIAL**

Done (`src/os/syscalls_ext.c:769-797`): range-check `arg_va` for 36 bytes (bad pointer on a TTY now → `-EFAULT`), `tcgetattr` (non-TTY → `-ENOTTY`), fill `c_iflag/c_oflag/c_cflag/c_lflag` as BE u32 at 0/4/8/12, `c_line` at 16, `c_cc[0..min(NCCS,19))` at 17.., store via `l2a_store_buf` (checked). Old `isatty`-only shortcut removed (`:814`). The 36-byte size matches the SPARC `struct termios` (`_IOR('T',1,36)` = `0x80245408`, `syscalls_ext.c:99`).

Why PARTIAL: the defect text asks to "translate its flags, speeds, and control characters into the SPARC layout". The commit copies host values verbatim:
- `c_cc` index map differs (SPARC: `VEOL=5, VEOL2=6, VDSUSP=11, VMIN=VEOF, VTIME=VEOL`; generic Linux: `VTIME=5, VMIN=6, VEOL=11, VEOL2=16`). A raw copy misplaces `VMIN/VTIME/VEOL/VEOL2`, so a guest `tcgetattr`/`tcsetattr` round-trip or raw-mode setup reads the wrong bytes.
- `c_lflag` differs in `FLUSHO` (SPARC `0x2000` vs generic `0x1000`) and SPARC-only `DEFECHO 0x1000`, `EXTPROC 0x10000`.
- On a Darwin host (`backend_darwin`/`threads_darwin.c` exists) the BSD bit layouts for `c_iflag/c_lflag/c_cflag` are entirely different; nothing is translated.
- Any `tcgetattr` failure is folded to `-ENOTTY` (loses `EBADF`). Minor.

The core defect (success with no data, success on bad pointer) is closed; layout fidelity remains open.

## S64-R6-8 — `F_GETFL` omits status flags, `O_SYNC` misreported — **VERIFIED**

`src/os/syscalls_ext.c:463-487` in `flags_host_to_guest`: `O_DIRECTORY → SP_O_DIRECTORY (0x10000)`, `O_PATH → SP_O_PATH (0x1000000)`, `(host & O_SYNC) == O_SYNC → SP_O_SYNC (0x802000)` else `O_DSYNC → SP_O_DSYNC (0x2000)`, with a `#elif defined(O_DSYNC)` fallback. All `SP_O_*` constants exist (`syscalls_ext.c:77-88`) and match `arch/sparc` `fcntl.h`. Full-mask equality fixes the `O_DSYNC`-only misreport.

## S64-R6-9 — `clock_getres(clk, NULL)` returns `EFAULT` — **VERIFIED**

`src/os/syscalls_ext.c:604-619` in `sys_clock_get`: range check skipped when `is_res && tp_va == 0`; after the host query, `if (is_res != 0 && tp_va == 0U) return 0;` before `store_timespec`. `clock_gettime(clk, NULL)` still goes through the range check and fails with `-EFAULT`, matching Linux. The `if (is_res == 0 && tp_va == 0U) { range_ok(0,16) }` branch is convoluted but equivalent to the previous behavior for gettime. Code-quality nit only.

---

## Follow-ups to carry into DEFECTS.md

1. **S64-R6-4 (HIGH, open residue):** apply temporary-then-commit to all 12 `sd_store` + `sparc64_fp_commit` pairs in `src/interp/fp_sd.c:544-617`.
2. **S64-R6-5 (HIGH, design residue):** either add an explicit `SPARC64_TRAP_FP_EXC` cause, or at minimum gate the FPop→`SIGFPE` classification on `ftt` and derive `si_code` from `ftt` when `ftt != 1` (`sync_sig.c:376-385, 528-541`).
3. **S64-R6-7 (MED, fidelity residue):** translate `c_cc` indices (`VMIN/VTIME/VEOL/VEOL2/VDSUSP`) and `c_lflag` `FLUSHO`/`DEFECHO` into the SPARC layout; add Darwin-host flag translation or document TCGETS as Linux-host-only.

**Unverified limits:** no compile or runtime check was performed per the brief, so I cannot confirm that the TU compiles after the `<termios.h>` / `sa_handler` `#undef` additions on both Linux-musl and Darwin, or that `sparc64_ctx_t` and `sparc64_cpu_t` are the same type (the diff uses both with `->fsr`; `cpu.h:132` shows the field, and `fp.c:253` already mixes the names, so this is very likely fine).
