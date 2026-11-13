## RC-U12-sparc64 (fable#high) — verdict: **ACTION_REQUIRED**

Audited `sparc64rt` at `c3732c8` read-only against UNIFICATION-PLAN Rev 4 §2, §4.2–4.5, §5.1, §6, §8, Waves U1–U2. Structural deliverables (rt64 deletion, 8 KiB ABI granule, emitter and site-record shapes, Darwin link) are present and correct. The two headline runtime claims are not live: the 7-instruction Soft-TLB is never emitted into any block, and the Provider-A 6-step quiescence code has no callers and no installed preemption handler.

### P1

- **Soft-TLB emitter is dead code; every DBT load/store still calls the interpreter.** `sparc64_mem_emit_fast`, `sparc64_mem_emit_tail`, `sparc64_mem_block_alloc`, and `sparc64_tlb_init` have no callers outside `src/dbt/emit_mem.c` and `src/dbt/mem_sites.c`. The live lowering is `e_emit_mem` at `src/dbt/emit_int.c:718` which BLRs into `s64_rt_mem` at `src/dbt/emit_rt.c:28`, which runs a full `sparc64_mem_slow_step`. The miss helper at `src/dbt/mem_sites.c:129-159` never fills a TLB entry, so even when wired the hit rate is zero. Because `sparc64_tlb_init` is never called, the BSS table has `read_tag = 0, addend = 0`, which would match VPN 0 and dereference the raw guest VA on the host once the fast path is emitted. Wave U2 scope item 2 and §4.3 are therefore unmet.

### P2

- **Load-miss continuation contract is broken** (latent, blocks wiring). The per-block trampoline resumes with `br x0` where `x0` is the host resume address (`src/dbt/emit_mem.c:332-340`), while the interpreter has written the result to `ctx->r[rd]` (`src/dbt/mem_sites.c:153`). The header contract says `x0`/`vd` holds the loaded value (`src/dbt/emit_mem.h:14-17`). A caller honoring that contract writes a host pointer back into the guest register on every miss. The slow path must reload `vd` from `ctx` before branching, or the contract must be redefined.
- **Quiescence is comments plus TLB invalidation, not the 6-step protocol.** `vm64_txn_prepare/host_op/commit` (`src/vm/vm64.c:470-552`), `vm64_preempt_via_rt_host` (`src/vm/vm64.c:112`), and `vm64_seq_rewind` (`src/vm/vm64.c:451`) have zero callers. `rt_host_install_signal_handlers` is never called by the engine, so the SIGRTMIN+1 / SIGUSR2 handlers at `src/os/backend_linux.c:726` and `src/os/backend_darwin.c` are never installed and no PC rewind exists. Commit `2701c13` only narrows `sparc64_dbt_invalidate` and adds `sparc64_tlb_invalidate_gva` at `src/os/guest_run.c:284,297,315,347,384`. Benign today only because all guest threads serialize on `thr_big_lock` (`src/os/threads.c:81,180`).
- **No ftruncate/truncate or mremap guest paths exist.** Numbers 77, 84, 129, 130 (`src/os/syscall_nr.h:102,109,154,155`) and 250 (`src/os/syscall_nr.h:275`) have no handler in `src/os/syscalls_*.c` and fall to `-ENOSYS` at `src/os/syscalls_min.c:553`. §4.2 requires 8 KiB `mremap` alignment and §5.1 requires the truncate hook; `syscalls_ext.c:281-283` is a comment placeholder.
- **Provider A and 8 KiB COW/EOF semantics are unreachable.** `src/vm/vm_file.c` has no callers (only a comment mention). File mappings are populated by `copy_from_fd` into 4 KiB heap pages (`src/os/guest_run.c:292`, `src/os/mem_space.h:83`), so `vm64_cow_promote_8k` (`src/vm/vm64.c:280`) and `vm64_eof_upper_half` (`src/vm/vm64.c:316`) never run.
- **No `dbt_mem_site_t[]` AOT serialization** (U2 scope item 3). Nothing under `src/dbt/aot/` references the site table.
- **RC-U2 gate tests are absent.** `tests/` has no 8 KiB COW/EOF, failed-ftruncate/mprotect state-preservation, cross-fork truncate, or CLONE_VM COW+futex coherence test. Only `tests/test_thr_resolve_granule.c` was added.

### P3

- **Line limits vs the 850 bound of this brief.** Repo gate is ≤900 (`Makefile:63-72`) and passes. Nine files exceed 850: `src/interp/interp.c` 900, `src/dbt/emit_int.c` 899, `src/interp/interp_win.c` 897, `src/os/guest_run.c` 894, `src/os/syscalls_ext.c` 894, `src/dbt/emit_priv.h` 892, `src/interp/fp_sd.c` 889, `src/interp/fp_quad.c` 863, `src/os/backend_darwin.c` 863. Rev 4 itself specifies 900, so this is a brief/plan mismatch to resolve, not a code defect.
- **Stale 4 KiB constant contradicts D11.** `SPARC64_AT_PAGESZ UINT64_C(4096)` with "AT_PAGESZ = 4096" comment at `src/os/mem_space.h:19-23`. Unused, but misleading.
- **NZCV save/restore location.** It is not in `src/dbt/trampoline_a64.S` (that file only pins x19/x20/x27/x28, lines 35-68). It is emitted per block at `src/dbt/emit_mem.c:325-347` (`mrs x5` … `msr nzcv, x5`), which is correct and equivalent. Task cards should cite the right file.
- **Process-global TLB instead of per-thread.** `x20` binds `sparc64_dbt_tlb` (`src/dbt/trampoline_a64.S:39-48`, `src/dbt/mem_sites.c:21`), acknowledged at `src/dbt/mem_sites.h:11-14`. Once more than one thread runs translated code, `ldp` readers can tear against invalidation writers.
- **Darwin `-Werror` weakened** via `-Wno-error=unused-function` for all Darwin TUs (`Makefile:108-112`), and `build-darwin` is not part of `make check` (`Makefile:61`).
- **16-byte store swaps `x5` in place** (`src/dbt/emit_mem.c:282`). Consistent with "x5-x8 dead scratch" but undocumented in the header's preservation claim.

### What passed

- `src/rt64/` is gone (0 files); `make check-line-limits` passes at the repo's 900 bound.
- 8 KiB ABI: `GUEST_ABI_PAGE_SIZE = 8192` (`src/os/guest_run_priv.h:48`), `AT_PAGESZ` from it (`src/os/guest_stack.c:298,308`), `-EINVAL` on non-8K offset/addr for mmap (`src/os/guest_run.c:197-199,260`), munmap (`:336-341`), mprotect (`:371-374`). `sparc64_space_protect` validates before mutating (`src/os/mem_space.c:520-543`).
- `thr_resolve` resolves at the 4 KiB granule (`src/os/threads.c:235-262`, `SPARC64_PAGE_SIZE = 4096` at `src/os/mem_space.h:13`) with the `check-thr-granule` gate wired into `make check`.
- Emitter words match §4.3 exactly: `ubfx` / `add lsl #5` / swapped `ldp` for stores / logical-immediate mask / `sub` / `cbnz`, BE `rev` into `x4` preserving `x0` (`src/dbt/emit_mem.c:186-286`); 32-byte entry and 24-byte site `_Static_assert`s with `SPARC64_NPC_DYNAMIC_CTX` (`src/dbt/mem_sites.h:48,70,91`).
- Darwin standalone: `c3732c8` publishes `_sparc64_dbt_enter(_step)` natively (`src/dbt/trampoline_a64.S:92-97,112-115`), `-Wl,-alias` dropped, `nm` on the built object confirms. Live run of `_build/guest_h1` under `_build/sparc64rt-darwin-arm64` exits 0 with `PAGESZ-OK value=8192` and `H1-SMC-PASS`; `guest_h1_smc` exits 0.
- Informational: untracked `_build/fsprobe` traps ILLEGAL on word `0x91b20e0c` (IMPDEP1/VIS opcode) under both DBT and `--interp`, so it is a decoder gap, not a Darwin regression.

**Required before PASS:** wire the fast path into `e_emit_mem` with a TLB fill in the miss helper and a `sparc64_tlb_init` call; fix the load-miss `vd` reload; either install the preemption handlers and call the `vm64_txn_*` sequence from `sysmem_*` or restate the S2 commit as "invalidation only"; add `ftruncate`/`mremap` dispatch; add the RC-U2 gate tests listed above.
