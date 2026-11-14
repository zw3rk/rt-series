## a32rt 32-bit iOS / Thumb-2 / DBT review

Scope: the eight files requested, read-only. Findings ranked; items marked *verify* depend on code outside this set.

### P1

1. **Relocating AOT loader rewrites arbitrary 32-bit constants.** `src/dbt/dbt_aot_cache.c:457-471` treats every `movz wX,#hi,lsl 16` + `movk wX,#lo` pair whose value lands in `[min_va, kuser)` as a guest PC and adds `delta`. Guest `MOVW/MOVT` immediates, compare constants, VFP/NEON immediates such as `0x3F800000`, and masks all match that pattern, so the fdcache path (`a32_aot_load_fd`, used for `AT_EXECFD`/relocatable loads) silently corrupts data when `load_bias` differs. Conversely a PC whose high half is zero emits a lone `movz` and is never relocated. Fix: have `a64_emit_mov_pc32` record word offsets into a per-block reloc list, serialize it (bump `A32_AOT_VERSION`), and relocate only those words.

2. **AOT cache executes attacker-seedable host code.** With no `A32RT_CACHE`/`XDG_CACHE_HOME`, `format_cache_path` falls back to shared `/tmp` (`dbt_aot_cache.c:151`). `load_cache_from_path` (`:523-531`) checks `O_NOFOLLOW`, regular file, and not group/world writable, but not ownership. Any local user can pre-create `/tmp/a32rt-cache-<hash>.bin` (hash is deterministic from the ELF) containing raw AArch64 code that `a32_jit_install_aot_block` will execute. Fix: require `st.st_uid == geteuid()`, default to `/tmp/a32rt-<uid>/` created `0700`, and add a per-block FNV-1a of the guest bytes `[guest_pc, guest_end_pc)` verified at `:473` before install. The latter also closes the correctness hole where a block saved for a library at VA X is installed over a *different* library mapped at X in a later run (the key includes `elf_base`/`interp_base` only, not other mmap bases).

3. **Site staging is process-global while translation is now per-thread.** `src/core/core_emit_mem.c:27-30` keeps `g_site_stage*` in plain statics, but `dbt_jit_query.c:73-75,131` deliberately translates with the JIT lock dropped. Two threads translating concurrently interleave records, attribute them to the wrong `guest_start_pc`, and the unguarded `g_site_stage[g_site_stage_count++]` after the bound check at `:50` can write one past the array. Fault recovery then uses wrong width/register metadata. Fix: make the four statics `_Thread_local`; flush at the locked commit (`dbt_jit_query.c:224`) and in `a32_emit_sites_flush` for the calling thread only.

4. **Unlocked translation commits stale guest bytes after an epoch bump.** `dbt_jit_query.c:184-193` notices `cur_epoch != use_epoch` but only re-checks executability, then commits code translated from bytes read *before* the invalidation (SMC pattern: `mprotect RW`, patch, `mprotect RX`, invalidate). The block enters the new epoch with old semantics. Fix: on epoch mismatch discard the staging buffer and retranslate (loop back to the pre-check) instead of falling through to `a32_jit_allocate_code_space_locked`.

### P2

5. **XNU fault signal mapping.** `dbt_jit_run.c:147-158` always raises SIGSEGV. Darwin delivers SIGBUS for `KERN_PROTECTION_FAILURE` (write to RO page, exec of NX page) and SIGSEGV only for unmapped addresses; 32-bit iOS crash handlers and `objc` guard-page probes observe the difference. When `ctx->is_ios`, classify by region lookup of `fault_addr`. Related: the UNDEF fallback at `:521-531` maps an interpreter `A32_EXIT_BKPT` to SIGILL instead of SIGTRAP.

6. **`a32_dbt_single_step` skips `pthread_jit_write_protect_np(1)`** (`dbt_jit_run.c:592`) while `a32_jit_run` sets it at `:361-363` before every `a32_jit_run_block`. If the compile path leaves the thread in writable state, difftest on macOS executes MAP_JIT memory while it is W-not-X. *Verify*, then mirror the call.

7. **Per-block site payload files keyed by `guest_pc` only** (`dbt_aot_cache.c:301-305`, `:490-493`). Different binaries share low VAs (`0x10000`, `0x4000`), so one program's fault-recovery records are restored for another. *Verify* `a32_aot_site_save` adds the ELF hash to the name; if not, prefix with the `fd_hash`.

8. **Difftest arena switch covers the ref step too.** `difftest.c:343` points the arena-global Soft-TLB at the shadow window and leaves it there while `a32_interp_step(&ref)` runs at `:356`. If the interpreter resolves addresses through `a32_vm32_tlb_base` in regime A2, ref reads and writes the dut window and the comparison is self-against-self. *Verify*; otherwise swap the arena base around the dut step only.

9. **Chain/IBTC/RAS loads lack acquire ordering.** `trampoline.S:118,127,144,164` and the inline `ldp x22,x17,[x23]` at `core_emit_mem.c:711` read `key|epoch` and `host_code` with plain loads, so a reader may pair a fresh `key|epoch` with a stale `host_code`. This is safe only if `a32_jit_reset_cache_locked` drains `g_jit_exec_readers` before recycling code space. If it does not, load `key|epoch` with `ldar` first and make `host_code` address-dependent on it.

10. **Uncached blocks consume code space until a full reset.** Every mid-IT entry (return from SVC/signal inside an `IT` block) or GDB step compiles via `a32_jit_allocate_code_space_locked` (`dbt_jit_query.c:212`) into the shared cache with no free path. Thumb-2 iOS code is IT-dense, so signal-heavy apps churn resets. Fix: bump-allocate oneshot blocks from a per-thread scratch page or small ring.

11. **`a32_jit_run` exits with code 1 and no `exit_reason` on translation overflow** (`dbt_jit_query.c:170-176`, `dbt_jit_run.c:321`). Retry once with `max_insns = 1` before giving up.

### PERF (hypotheses, unmeasured)

- **PERF-1: IBTC conflict misses on `objc_msgSend`.** The IBTC is direct-mapped, 1024 entries, indexed by `(pc >> 1) & 1023` (`trampoline.S:140`, `core_emit_mem.c:814`). Every IMP whose address is congruent mod 2 KiB collides, so the message-send tail jump falls to the C dispatcher. Measure `ibtc_hits` against slow exits on an ObjC-heavy fixture; if confirmed, go 4096-entry 2-way with `(pc >> 1) ^ (pc >> 13)`.
- **PERF-2: Global lock on warm paths.** Every slow-exited call that finds its return block takes `jit_lock` for `set_ht_ret_slot_locked` even when `ret_entry` already equals `found_e` (`dbt_jit_run.c:428-436`), and every chain/IBTC miss takes it for the hash-table hit at `dbt_jit_query.c:42-64`. Add an equality early-out; probe `g_ht` lock-free with acquire loads since the fields are already atomics.
- **PERF-3: NEON FP ops pay `MRS/MSR FPCR` plus ctx load/store per instruction** (`decode_priv.h:169-178,188-202`). Hoist the standard-FPCR install to once per NEON run between flush points and keep operands in the existing VFP register cache.
- **PERF-4 (test only):** `difftest_mem_hash` byte-mixes every readable region twice per syscall and `difftest_sync_dut` remaps all regions (`difftest.c:146-169,208-241`). Hash only regions whose `prot` includes write, or track dirty pages via the dut's write TLB tags.

### POLISH

- **CommPage.** The scanner caps iOS VA at `0xFFFF8000` (`dbt_aot_scan.c:69,406`), implying a commpage at `0xFFFF4000`. Confirm `_COMM_PAGE_VERSION`, `_NCPUS`, `_CPU_CAPABILITIES`, `_MEMORY_SIZE`, `_TIMEBASE_OFFSET`, `_GTOD_*`/`_NT_*` fields and the `"commpage 32-bit"` signature are populated; libsystem_platform's `gettimeofday` and `OSAtomic` fast paths read them.
- **TLS and signals.** 32-bit iOS reads TLS via `mrc p15,0,rX,c13,c0,3` (TPIDRURO), not the Linux kuser page; the `0xFFFF0FA8` filter at `dbt_jit_run.c:390` and the `r7 == 0x0f0001` check at `:460` are Linux-only and harmless but worth gating on `!is_ios`. `_sigtramp` expects `ucontext` plus 32-bit `mcontext` (exception, thread, VFP state) and `__sigreturn(uctx, infostyle)`.
- **AOT seeding for Mach-O.** `seed_elf_symbols` is ELF-only (`dbt_aot_scan.c:76-154`); iOS binaries fall back to byte heuristics. Seed from `LC_FUNCTION_STARTS` and `LC_MAIN`.
- **Observability.** Add counters for slow exits by reason, IBTC conflict misses, uncached compiles, cache resets, and lookahead-compiled blocks; the hypotheses above cannot be tested without them.
- **Offset pinning.** `trampoline.S` and `core_emit_mem.c` hardcode ctx offsets (64, 72, 352..424, 448, 2496, 96, 152). Confirm `_Static_assert(offsetof(...))` guards exist for each.

The four P1 items are independent and each fix is local to the cited lines. Items 6, 7, 8, and 9 need a look at the compile, site-save, interpreter, and reset code respectively before acting.