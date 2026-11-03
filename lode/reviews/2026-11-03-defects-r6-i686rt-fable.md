# Verification report: i686rt commit `8c81f62` vs. Round-6 defects I686-R6-1..8

Scope: 3 read-only tool turns (defect card + full diff, grep of remaining signal-field accesses, clone.c/stack-helper context). No build, test, container, or QEMU run; compile-cleanliness is not verified here.

**Summary: 6 VERIFIED, 2 PARTIAL, 0 NOT FIXED, 0 REGRESSION.**

| Item | Severity | Verdict |
|---|---|---|
| R6-1 BT/BTS/BTR/BTC register-index memory addressing | HIGH | VERIFIED |
| R6-2 LOOP/JCXZ counter width by address size | MEDIUM | VERIFIED |
| R6-3 Unsynchronized `pending_signals` / `sig_mask` RMW | HIGH | PARTIAL |
| R6-4 Child ctx inherits `clear_child_tid`, pending signals, robust list | HIGH | VERIFIED |
| R6-5 Near CALL/RET ignore SS base | HIGH | VERIFIED |
| R6-6 XLAT 16-bit offset not wrapped | MEDIUM | VERIFIED |
| R6-7 Thread registry overflow returns clone success | MEDIUM | PARTIAL |
| R6-8 Darwin `dup3` with `oldfd == newfd` | MEDIUM | VERIFIED |

---

## I686-R6-1 — VERIFIED

`src/interp/h_bit.c:52-53` adds a `from_reg` parameter to `bt_common`. The register-destination path keeps the modulo rule (`h_bit.c:58`). The memory path now splits:

- `h_bit.c:84-98`: register index is sign-extended (16-bit via `int16_t`, 32-bit via `int32_t`), the EA is adjusted by `(bit_ofs >> 4) * 2` or `(bit_ofs >> 5) * 4` (arithmetic shift = floor divide, matching the SDM), and the residual `bit_ofs & 15/31` selects the bit.
- `h_bit.c:99-102`: immediate index (0F BA) stays modulo width.
- Callers: `h_bit.c:156,162,168,174` pass `1U` for the Gv forms; `h_bit.c:181,187,193,199` pass `0U` for the Ib forms.

The reported case `bts [eax], ecx` with `ecx = 32` now targets `[eax+4]` bit 0; negative indices move backward. DBT still delegates to this handler, so both engines are covered.

Residual note (not a defect in the item's scope): the EA adjustment is not wrapped to 16 bits under a `67h` address-size prefix. Consistent with the rest of the interpreter's EA handling.

## I686-R6-2 — VERIFIED

`src/interp/h_branch.c:196` (`do_loop`) and `h_branch.c:241` (`h_jcxz`) now derive the counter width from `insn->pfx_addrsize`, not `opnd_width`. The 16-bit path at `h_branch.c:201-205` preserves the upper half of ECX while decrementing CX. `67 E3` with `ECX = 0x00010000` now branches.

Not checked within budget: whether `do_loop` still truncates the target to IP under a `66h` operand-size prefix after `width` was removed from the function. If it no longer calls `set_eip` with the operand width, that is a separate pre-existing/independent behaviour, not a regression of this item.

## I686-R6-3 — PARTIAL

Done in the commit:

- `src/os/sys_thread.c:87-93`: producer uses `__atomic_fetch_or` on `pending_signals` and `__atomic_load_n` on `sig_mask`.
- `src/os/signals_i386.c:503-507,520`: SIGALRM bridge uses atomic load + `fetch_or`.
- `src/os/signals_i386.c:647-648,660,669,675,680,694-695`: `i686_deliver_pending` loads atomically and consumes each bit with `__atomic_fetch_and(~bit)`, so a signal posted between load and consume is no longer erased.
- `src/os/signals_i386.c:242-247,405-413`: frame build and sigreturn use atomic load/store on `sig_mask`.
- `src/os/clone.c:667`: child copy resets `pending_signals` to 0 (plain store on a not-yet-shared object, fine).
- `src/i686rt.h:180-185`: `volatile` removed, comment asserts every access is atomic.

Still plain (non-atomic) after the commit:

- `src/interp/v86_internal.h:285` and `:293`: `ctx->pending_signals |= ...` for synchronous SIGILL/SIGSEGV posting. This is a plain read-modify-write on the same word another thread may `fetch_or` into via `tkill`/`tgkill`. A concurrent cross-thread post can still be lost. This is exactly the defect class of the item.
- `src/os/sys_pass.c:190,201,204,207,505`: `rt_sigprocmask` reads and writes `sig_mask` with `memcpy`, `|=`, `&=`, `=`. These are owning-thread accesses but race formally with the atomic loads in `sys_thread_raise` and the SIGALRM handler. On AArch64 the aligned 64-bit stores are single-copy atomic in practice, so the practical risk is low, but the new header comment ("every access ... runs through the `__atomic` builtins") is not true.
- Polling reads at `src/dbt/engine.c:649` and `src/interp/interp.c:642` are plain, and `volatile` was removed. They sit in loops that call out to block execution, so hoisting is unlikely, but the item asked for consistency and these were not converted. The JIT `ldp` in `src/rt32/rt32_a64_emit_exit.c:197-200` is a plain load, acceptable for a poll.

Remaining work to close: convert the two `v86_internal.h` producers to `__atomic_fetch_or`, convert `sys_pass.c` mask accesses to atomic load/store (or `fetch_or`/`fetch_and`), and either make the two C poll sites `__atomic_load_n(..., RELAXED)` or correct the header comment.

## I686-R6-4 — VERIFIED

`src/os/clone.c:667-671`, immediately after the `memcpy` of the parent ctx: `pending_signals = 0`, `robust_list_head = 0`, `robust_list_len = 0`, and `clear_child_tid` is set from `child_tid` only when `I686_CLONE_CHILD_CLEARTID` is in `flags`, otherwise 0. The old conditional overwrite at the former `clone.c:696-698` is removed (`clone.c:718-719` comment). `child_tid` is EDI (`clone.c:611`), which is the i386 clone `ctid` argument, so the source is correct. Teardown at `clone.c:555` still gates on a nonzero `clear_child_tid`, so a child created without the flag can no longer clear the parent's TID word. Field names match `src/i686rt.h:228-230`.

## I686-R6-5 — VERIFIED

`src/interp/h_branch.c:91` (`stack_push`) and `h_branch.c:99` (`stack_pop`) now address `ctx->seg_base[I686_SEG_SS] + sp`, identical to `push_val`/`pop_val` in `src/interp/h_mov.c:366,374`. Callers at `h_branch.c:150,161,169,178` (near CALL rel/Ev, RET, RET iw) are unchanged and inherit the fix. Fault rollback is preserved: the memory access still runs before the ESP commit (`h_branch.c:91-92,99-101`).

The card's suggested shared accessor was not introduced; the two helper pairs remain duplicated. That is a DRY leftover, not a correctness gap. Neither pair handles a 16-bit stack address size (`SS.B = 0`) or segment limits, which is pre-existing and consistent across both.

## I686-R6-6 — VERIFIED

`src/interp/h_mov.c:336-340`: `off = EBX + AL`, then `off &= 0xffff` when `pfx_addrsize` is set, then the DS (or override) base is added at `h_mov.c:343-344`. `BX = 0xffff`, `AL = 1` now reads `DS.base + 0`.

## I686-R6-7 — PARTIAL

Done: `src/os/clone.c:140-148` adds `thread_registry_has_space()`; `clone.c:721-726` calls it before `pthread_create` (`clone.c:736`) and returns `-EAGAIN` after destroying `ca->mtx`/`ca->cond` and freeing `child` and `ca`. The common overflow case now fails the clone instead of running an untracked thread.

Not done: the item asked to *reserve* capacity. The check drops `s_registry_lock` at `clone.c:146` and the actual insert happens at `clone.c:749`, after the child thread exists. Two or more `clone` calls racing with `s_registry_n == MAX - 1` can all pass the check; the losers hit the still-silent overflow path in `i686_thread_registry_add` (`clone.c:154-161`) and the syscall still returns success with an unregistered thread. Closing it requires either incrementing `s_registry_n` (or marking a slot) under the lock at check time and releasing it on failure, or making `registry_add` return a status that `r_clone` turns into `-EAGAIN`. Whether `r_clone` is externally serialized was not checked within budget.

## I686-R6-8 — VERIFIED

`src/os/sys_pass_io.c:105-110`: `oldfd == newfd` is rejected before the host `dup2`; `sys_pass_io.c:116-120`: a failed `F_SETFD` closes the new fd and returns `-errno`.

Minor residual, not blocking: for `oldfd == newfd` the code returns `-EBADF` when the fd is closed and `-EINVAL` otherwise (`sys_pass_io.c:106-109`). Linux's `ksys_dup3` checks `oldfd == newfd` before looking up the file and returns `-EINVAL` in both cases. The comment at `sys_pass_io.c:103-104` encodes the wrong ordering. Guest-visible only for a closed descriptor duplicated onto itself.

---

## Follow-ups to carry into DEFECTS.md

1. **R6-3 (HIGH, PARTIAL)**: atomic-ize `src/interp/v86_internal.h:285,293` and `src/os/sys_pass.c:190-207,505`; decide on the two C poll sites; fix the header comment at `src/i686rt.h:180-183`.
2. **R6-7 (MEDIUM, PARTIAL)**: reserve the registry slot under lock, or make `i686_thread_registry_add` report failure and have `r_clone` fail with `-EAGAIN` before releasing the child (`clone.c:749-754`).
3. **R6-8 (LOW)**: return `-EINVAL` for `oldfd == newfd` regardless of validity; fix the comment.
4. **R6-5 (DRY)**: optional consolidation of `stack_push`/`stack_pop` with `push_val`/`pop_val`.
