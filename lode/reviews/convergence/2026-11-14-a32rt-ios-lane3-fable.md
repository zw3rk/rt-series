# a32rt 32-bit iOS review: `ios_svc_mach.c` and `ios_stubs.c`

Scope: the two files read. Register-layout claims below follow the armv7 XNU trap convention: the libsyscall stub loads stack words into r4-r6, r8 and the kernel copies r0-r6, r8 verbatim, so the kernel sees the AAPCS layout, including 8-byte alignment of 64-bit arguments to even register pairs and 8-byte stack slots.

## P1

1. **Mach VM traps decode 64-bit args from odd register pairs.** `src/ios/ios_svc_mach.c:375-381` (vm_deallocate) reads `addr = r2:r1`, `size = r4:r3`; `:397-400` (vm_protect) reads `addr = r2:r1`, `size = r4:r3`, `set_max = r5`, `prot = r6`. AAPCS aligns the first 64-bit arg after `target` to r2:r3 and `size` to r4:r5, so vm_deallocate/vm_protect operate on garbage ranges (currently the "address" is `size_lo<<32|addr_lo`), typically returning KERN_INVALID_ADDRESS or hitting the wrong pages. Fix: `addr = r3:r2`, `size = r5:r4`, `set_max = r6`, `prot = regs[8]`. vm_allocate (`:321-324`) is correct because its 64-bit `size` already lands on r2:r3.

2. **8th trap argument read from `[sp+16]` instead of r8.** `src/ios/ios_svc_mach.c:440` (vm_map `cur_protection`) and `:722` (mach_msg_overwrite_trap `rcv_msg`). `[sp+16]` is the 5th arg's stack copy (= r4), so vm_map maps with `prot = mask_lo & 7` (usually 0, PROT_NONE) and overwrite-receive lands in `mask`/`rcv_name`. Fix: use `ctx->regs[8]`. Same bug in `mach_trap_vm_purgable` `:506`: `state` pointer is r5 (after `addr` in r2:r3, `control` in r4), not r4.

3. **`lseek` and `mmap` stubs mis-split `off_t`.** `src/ios/ios_stubs.c:759-760`: offset is r2:r3 and `whence` is `[sp]`, not `r1|r2<<32` / r3. `:768-769`: mmap's `fd` is `[sp]`, pad `[sp+4]`, `off_t` at `[sp+8]:[sp+12]`, not `[sp+4]:[sp+8]`. Any non-zero file offset mmaps or seeks the wrong location. Fix: `u = r2 | r3<<32; whence = sld(c,0)` and `of = sld(c,8) | sld(c,12)<<32`.

4. **`fprintf` arguments shifted by one.** `src/ios/ios_stubs.c:617-620` moves r2→r1, r3→r2 then starts fetching at index 1, which maps to `regs[2]` (original r3). First vararg is thus the second one, and the third is a duplicate of r3. Fix: delete the register shuffle; `fetch_rs` with `start = 1` already yields r2, r3, `[sp]`, … correctly.

5. **Host stack over-read in the printf engine.** `src/ios/ios_stubs.c:364-384`: `snprintf` into `tmp[256]` returns the untruncated length `w`; the copy loop then reads `tmp[k]` for `k` up to `w` (e.g. a 1 KiB `%s`). `:646-650`, `:667-671`, `:686-690`: `cp = n` is clamped to the guest `size` but not to `sizeof(buf)-1`, so a guest `snprintf(buf, 8192, ...)` with a long result copies past the 2 KiB host buffer. Fix: `w = min(w, sizeof(tmp)-1)` before copying, and `cp = min(cp, sizeof(buf)-1)`.

6. **Guest heap is a fixed 1 MiB arena that never grows.** `src/ios/ios_stubs.c:181-227`: `heap_ensure_locked` maps one chunk; `gmalloc` fails once `g_arena_off` hits 1 MiB or for any request above ~1 MiB (`:194`). The `calloc` cap at 16 MiB (`:864`) is unreachable. Real armv7 apps exhaust this during startup. Fix: on arena exhaustion mmap another chunk and chain arenas (or route requests ≥ 64 KiB to a dedicated `a32_vm_mmap2` with a distinct header magic so `gfree` can munmap).

## P2

7. **`task_get_special_port` reply is malformed MIG.** `src/ios/ios_svc_mach.c:692-706` sends a 40-byte non-complex reply with a raw port name at offset 36. MIG clients see `!COMPLEX && size != 36` and return `MIG_TYPE_ERROR`, so `task_get_bootstrap_port` fails. Fix: set `bits = MACH_MSGH_BITS_COMPLEX`, emit `msgh_body.msgh_descriptor_count = 1` at 24, then a 12-byte `mach_msg_port_descriptor_t {name, pad, disposition=MOVE_SEND(17), type=PORT(0)}`, size 40, and drop the NDR/RetCode words. Same problem will hit `semaphore_create` (3418) and `mach_port_*` MIG calls; today every non-trap Mach RPC on the task port returns a plain `KERN_SUCCESS` error-shaped reply.

8. **Port slots leak; `mach_port_destruct` is a no-op.** `src/ios/ios_svc_mach.c:821-822` routes trap 25 to the validating stub. libpthread/libdispatch tear down reply ports via `mach_port_destruct`, so with `MACH_PORT_COUNT = 256` (`:63`) a long-running guest exhausts the table and `mach_reply_port` returns `KERN_RESOURCE_SHORTAGE`. Thread ports (`:222-235`) are also never released on thread exit and `mach_thread_self` does not bump `refs`, so the libpthread exit-path `mach_port_deallocate` frees the slot under the live thread. Fix: 25 → `mach_trap_port_destroy` semantics; free thread-kind slots in the thread-exit path; `refs++` on repeat `thread_self`.

9. **Full queue silently drops the oldest message.** `src/ios/ios_svc_mach.c:250-256`. XNU blocks or returns `MACH_SEND_TIMED_OUT`/`MACH_SEND_NO_BUFFER`; dropping a dispatch or reply message deadlocks the receiver. Fix: return `MACH_SEND_NO_BUFFER` (0x10000005) or block on the port cond until `qcount < depth`.

10. **Stub `mach_thread_self` and trap 27 disagree.** `src/ios/ios_stubs.c:834` fabricates `0x203 + (tid & 0xFF) * 4`, which is not in `g_ports`, collides across threads, and makes `mach_port_deallocate` return `KERN_INVALID_NAME`. Fix: call the same `mach_ensure_thread_port` path as trap 27 (export it from `ios_svc_mach.c`).

11. **64-bit varargs ignore AAPCS alignment; `%f` family unsupported.** `src/ios/ios_stubs.c:369-372` fetches `lo, hi` at the current index without rounding to an even register / 8-byte stack slot, so `printf("%lld", x)` reads the pad word. `:377-378` emits `%(f)` for `%f/%e/%g` and consumes no argument, mis-aligning every following conversion. Fix: for `l`/`ll`/floating conversions round `*ai` up to odd (r1-based index ⇒ even register; `(i-3)` even ⇒ 8-byte stack slot), for `fetch_ap` align the computed address to 8; implement `%f/%e/%g/%a` by fetching two words and `memcpy` into a `double`.

12. **`strtol`/`strtoul` never write `endptr`.** `src/ios/ios_stubs.c:297` passes `NULL` and ignores r1; callers reading `*endptr` get stack garbage. Fix: compute `end - x` on the host and `guest_write` `a0 + off` to r1 when non-zero.

13. **sysctl error path negates errno.** `src/ios/ios_stubs.c:806` passes the Darwin carry-set positive `errno` in r0 to `sigerr`, which negates it (`:711`), storing `-errno`. Fix: write `(int32_t)c->regs[0]` directly (or make `sigerr` take a signed sign-normalised value).

14. **`abort`/`__assert_rtn`/`__stack_chk_fail` call `_exit(134)`.** `src/ios/ios_stubs.c:857`, `:436`. No `SIGABRT` is delivered, so guest handlers, parent `WIFSIGNALED`, and the crash path differ from XNU. Fix: route through `a32_ios_sys_kill(c, getpid-equivalent, SIGABRT, 1)` then fall back to `_exit`.

15. **`nanosleep` EINTR returns success and copies uninitialised `rem`.** `src/ios/ios_stubs.c:788-791`. Fix: on EINTR write `rem` and `serr(c, EINTR)`; on success skip the copy.

16. **`qsort` comparator state is not re-entrant.** `src/ios/ios_stubs.c:881-891` reuses the single per-thread `gcall_t`; a comparator that itself calls `qsort` (or any future guest-call stub) clobbers `saved[]`/`tmp`. Fix: make `gcall_t` a small stack (depth 4) pushed in `qsort_step`, popped in `qsort_resume`.

## PERF (unmeasured hypotheses, instrument with `A32RT_STATS` first)

- **PERF-1: `qsort_resume` invalidates the whole array per swap.** `src/ios/ios_stubs.c:468` calls `a32_vm32_copyout_invalidate_exec(c, base, n*sz)` on every comparison-swap of an O(n²) insertion sort, i.e. O(n²·array) invalidation work plus one full guest round-trip per compare. Candidate fix: invalidate only the two swapped elements (or once at `qdone`), and switch to heap/merge sort to cut compares from n²/4 to n log n.

- **PERF-1: single global `g_mach_lock` plus linear 256-slot scans and 25 ms polling.** `src/ios/ios_svc_mach.c:135-143`, `:200-220`, `:265-273`, `:656-669`, `:758-766`. Every trap takes the global mutex twice (`mach_ensure_init` and the op), finds ports by O(256) scan, `mach_is_server_port` rescans, waiters wake every 25 ms to poll `pending_signals`, and `cond_broadcast` wakes all waiters on a port. Candidate fix: `__atomic` fast-path for init, name→index hash (`(name - USER_BASE) / 4`), per-port mutex, and signal-driven wakeup (cond broadcast from the signal-delivery path) instead of the timer step.

- **PERF-2: `gmalloc` first-fit scan with no coalescing and no size classes.** `src/ios/ios_stubs.c:198-217`: up to 4096 header reads per allocation through `a32_guest_range_ok`. Candidate fix: power-of-two bins keyed off `need`.

## POLISH

- `mach_build_reply` returns `KERN_FAILURE` for every bootstrap request (`ios_svc_mach.c:688-689`) and `host_info` for every other host RPC (`:690-691`); `host_get_clock_service`, `host_page_size`, `host_statistics` all come back shaped as `host_info`. Add a tiny id switch (200 host_info, 206 host_page_size, 219 host_get_clock_service) and `BOOTSTRAP_UNKNOWN_SERVICE` (1102) for `bootstrap_look_up` (404).
- Traps 41/42 (`mach_port_guard`/`unguard`), 44-46 (`task_name_for_pid`, `task_for_pid`, `pid_for_task`), 76 (`mach_port_type`), 77 (`request_notification`) fall to `KERN_FAILURE` (`ios_svc_mach.c:866`); libdispatch guards its reply ports and expects `KERN_SUCCESS`.
- `semaphore_signal_all` (34) only increments by one (`ios_svc_mach.c:649`); should release all current waiters.
- Forwarded messages keep the sender's `msgh_bits` (`:745`); swap the remote/local disposition fields as XNU does.
- `mach_timebase_info` reports {1,1} while real armv7 hardware reports {125,3}. Fine for correctness, but apps that hard-code 24 MHz tick assumptions will mis-time. Document.
- `atexit`/`__cxa_atexit` registrations are discarded (`ios_stubs.c:860`) and `exit` goes straight to `_exit` (`:859`); at minimum run them LIFO before exiting.
- Synthetic `FILE*` values at `0xFFFF5600/5680/5700/5800+` (`ios_stubs.c:418-435`) have no backing memory, so inlined `getc`/`putc`/`ferror` macros that touch `_r`/`_w`/`_flags` fault. Back them with a zeroed RW page.
- `__memcpy_chk`/`__memmove_chk`/`__memset_chk`/`__strcpy_chk` ignore the destination-size argument (`ios_stubs.c:285`, `:292-293`); they should abort on overflow, which is their only purpose.
- Mixing Darwin errno constants (`DE_AGAIN 35`, `DE_TIMEDOUT 60`) into `serr`, which maps host→Darwin (`ios_stubs.c:37-41`, `:68-74`), is wrong on a Linux host for any value that differs. Currently only values identical in both tables are used; add a `serr_darwin` that bypasses the mapping before someone uses the others.
- Trap 0x80000000 `__builtin___clear_cache` on guest memory (`ios_svc_mach.c:291`) is a no-op for translated code and only costs an IC IVAU loop; the `a32_jit_invalidate_range` call is the one that matters.
- `fwrite`/`fread` compute `a1 * a2` in 32 bits without overflow check (`ios_stubs.c:515`); return 0 with `EINVAL` on overflow.