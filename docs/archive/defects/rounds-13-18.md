# rt-series Defect Archive — Rounds 13–18 (2026-11-05 to 2026-11-13, 191 / 191 Resolved)

## Round 13 — Five-lens review, resolved (2026-11-05; remediated 2026-11-13)

Pinned `master` revisions at the start of the review, alongside the remediation commits across all 11 repositories (`191 / 191` Round 13–18 findings resolved and verified). Each finding names its runtime, lens, path, line range, and audited revision. Performance entries name a structural cost and do not claim a measured time.

| Runtime | Audited Revision | Remediated Commit | Items (R13–R18) |
|---|---|---|---:|
| `a32rt` | `4b94c1527beaa57665444c2578dc9f7e1fec9e04` | `25ef1aa` | 19 / 19 |
| `i686rt` | `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a` | `226c880` | 17 / 17 |
| `mips32rt` | `3fb98db8f8ca14d64889feca687443fce55788f6` | `a0794d2` | 18 / 18 |
| `ppc32rt` | `621e36892ffb8d5f68ddd615b670324d4e437c07` | `4a35f01` | 20 / 20 |
| `sparc32rt` | `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d` | `1dd1f22` | 20 / 20 |
| `rvrt` | `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff` | `f978775` | 14 / 14 |
| `loongarch64rt` | `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e` | `c98e960` | 14 / 14 |
| `ppc64rt` | `3c236f2584e9e0a2e5ebf07fa77d3110b032202c` | `8ec83bc` | 18 / 18 |
| `mips64rt` | `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c` | `71ac358` | 15 / 15 |
| `sparc64rt` | `e33935f73e3a097c65435ff026c9168c2724d823` | `5486608` | 19 / 19 |
| `rt-series` | `7144388926db4ad6ab23ce1d8fbfcdd95d630e42` | `026eb5b` | 17 / 17 |

Same-site duplicates from a later pass are not listed again: the mips32rt mremap mprotect failure, the ppc32rt A2 mmap final sync, the sparc32rt large-page PROT_NONE failure, the mips64rt mmap mprotect failure, and the catalogue `docker ps` failure.

### `a32rt` (`4b94c1527bea`)

- [x] **A32-R13-1 — High — SECURITY — Writable guest pages keep host execute**
  - **Where**: `a32rt` `src/a32rt.h:261-272` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: a32_host_prot keeps the execute bit on a writable guest protection unless A32H_CAP_WX_ENFORCED is set, and returns that word as the host protection. A guest-writable page remains host-executable when the W^X capability is absent.
  - **Fix**: Strip host execute from a guest-writable protection, and fail the mapping if that protect call fails.

- [x] **A32-R13-2 — High — SECURITY — Guest open falls back to the host path**
  - **Where**: `a32rt` `src/elf32.c:72-78` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: If sysroot resolution or the resolved open fails, a32_open_guest_ro opens the unresolved guest path on the host. A guest interpreter or ELF path that is missing from the sysroot is opened from the host filesystem.
  - **Fix**: If sysroot resolution fails, return the open error. Do not open the unresolved guest path on the host.

- [x] **A32-R13-3 — High — SECURITY — Proc sys and dev resolve to the host**
  - **Where**: `a32rt` `src/os/os_sys_path.c:303-309` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: Once a walked path is under /proc/, /sys/, or /dev/, the resolver returns that path as the host path with no sysroot prefix. Guest path synthesis returns a host /proc, /sys, or /dev path.
  - **Fix**: Return a synthesized guest file or ENOENT. Do not hand /proc, /sys, or /dev to the host as a real path.

- [x] **A32-R13-4 — High — SECURITY — Send and recv skip the buffer check**
  - **Where**: `a32rt` `src/os/os_sys_sock.c:451-466` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: sendto and recvfrom pass the guest buffer length and the sockaddr pointer to the host with no range check. A guest-chosen socket buffer or address pointer is used for a host copy that can leave the guest window.
  - **Fix**: Reject a socket buffer or sockaddr that is not fully inside the guest window.

- [x] **A32-R13-5 — High — SECURITY — Read and write ignore the guest length**
  - **Where**: `a32rt` `src/os/os_sys_thread_sig.c:340-357` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: read and write reject only a buffer below 0x1000 and then copy the full guest length a2 at that guest pointer. A guest length whose end passes 4 GiB is copied outside the guest window.
  - **Fix**: Reject a guest length whose end wraps past the 4 GiB window before the host copy.

- [x] **A32-R13-6 — High — SECURITY — A2 host protect result dropped**
  - **Where**: `a32rt` `src/vm/vm32.c:269-277` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: vm32_sync_host_pages_a2 ORs the guest prot bits into the host protect request and discards a32_backend_protect's result. An A2 host page keeps its previous permissions, including a prior PROT_EXEC or PROT_WRITE mapping, when the union mprotect fails.
  - **Fix**: If the host protect call fails, return the error and do not rewind a frontier onto a page that is still executable.

- [x] **A32-R13-7 — High — SECURITY — EOF-cut ignores mprotect failure**
  - **Where**: `a32rt` `src/vm/vm32.c:385-401` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: a32_vm32_set_eof_cut discards the a32_backend_protect result on Regime A1 for both the cut and the restore. An EOF-cut page stays host-accessible at its previous protection when mprotect fails.
  - **Fix**: If the host protect call fails, return the error and do not rewind a frontier onto a page that is still executable.

- [x] **A32-R13-8 — Medium — PERFORMANCE — JIT lock held across block translation**
  - **Where**: `a32rt` `src/dbt/dbt_jit_query.c:120-175` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: a32_translate_t32_block or a32_translate_a32_block runs, and runs a second time for a VFP self-loop, before this span calls jit_lock_release, and a32_jit_flush_batch_locked is still before that release. Another thread spinning in jit_lock_acquire waits out translation of the block and the locked flush that follows it.
  - **Fix**: Hold the lock only around the table update. Do the copy or the probe outside the lock.

- [x] **A32-R13-9 — Medium — PERFORMANCE — Copyout walks every reservation line under lock**
  - **Where**: `a32rt` `src/vm/vm32.c:507-530` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: a32_vm32_copyout_invalidate sets g_res_lock and then bumps g_ll for every 64-byte line of [gva, gva+len) with no stride cap. A large syscall copyout holds the reservation spinlock for one iteration per 64 bytes, repeating buckets after the 1024-line hash period.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **A32-R13-10 — Low — DRY — T32 load/store decoded twice**
  - **Where**: `a32rt` `src/interp/interp_t32_mem.c:189-267` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: The T32 single load/store rule (PC literal, imm12, shifted register, imm8 pre/post, and rn==rt writeback suppression) is copied in src/interp/interp_thumb.c:706-770. A change to T32 addressing or writeback must be made in both decoders or the interpreter and the DBT diverge.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **A32-R13-11 — Low — DRY — Wake-pipe protocol copied**
  - **Where**: `a32rt` `src/os/backend_linux.c:196-243` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: The host-independent nonblocking wake-pipe and sig_seq protocol in worker_sync_init, destroy, and notify is copied in src/os/backend_darwin.c:339-386. Linux and Darwin quiescence diverge if only one backend's wake-pipe or sig_seq update is changed.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **A32-R13-12 — Low — YAGNI — Uncalled difftest dbt runner**
  - **Where**: `a32rt` `src/dbt/difftest.c:77-87` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: A search of the a32rt repository found no caller of a32_difftest_run_dbt; the only occurrences are the difftest.h declaration and this definition, while main calls a32_jit_run for DBT mode. The --dbt wrapper never runs, so its blocks_executed and dbt_hash recording has no effect.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **A32-R13-13 — Low — YAGNI — Uncalled worker preempt**
  - **Where**: `a32rt` `src/os/backend_linux.c:245-258` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: A search of the a32rt repository found no caller of a32_backend_preempt_worker; the only occurrences are the backend.h declaration and the definitions in backend_linux.c and backend_darwin.c. Nothing sends the reserved preemption signal through this symbol, so the helper never runs.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **A32-R13-14 — Low — YAGNI — Uncalled soft-tlb miss filler**
  - **Where**: `a32rt` `src/vm/vm32.c:213-244` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: A search of the a32rt repository found no caller of a32_vm32_tlb_miss; the only occurrences are the vm32.h declaration and this definition. The g_prot soft-TLB fill-on-miss path never runs; emitters fault on a tag miss without calling it.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **A32-R13-15 — Low — YAGNI — Uncalled private map lookup**
  - **Where**: `a32rt` `src/vm/vm_file_map.c:233-282` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: A search of the a32rt repository found no caller of a32_vmfile_lookup_private; the only occurrences are the vm32.h declaration and this definition, while mremap calls a32_vmfile_lookup_private_span. The single-address private-map lookup never dups a backing descriptor and has no effect.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **A32-R13-16 — Medium — CLEAN — Brk shrink ignores re-reserve**
  - **Where**: `a32rt` `src/vm.c:613-628` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: After a successful tracking retire, a32_vm_brk discards vm_reserve_prot_none and still stores and returns new_brk. The guest break moves while the released pages stay mapped and untracked if the PROT_NONE re-reserve fails.
  - **Fix**: Keep the old break when the PROT_NONE re-reserve fails.

### `i686rt` (`92fc0afb23d6`)

- [x] **I686-R13-1 — High — SECURITY — Cleartid write is not confined to the guest window**
  - **Where**: `i686rt` `src/os/clone.c:587-605` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: Thread exit memcpy's 4 bytes at the guest-supplied clear_child_tid through i686_guest_ptr with no test that ctid_va+4 stays below 2^32. A clear_child_tid in the last three bytes of the 4 GiB window makes the host write past the reserved guest mapping.
  - **Fix**: Reject clear_child_tid unless all four bytes sit inside the guest window.

- [x] **I686-R13-2 — High — SECURITY — Select reports success after a failed fd_set copy**
  - **Where**: `i686rt` `src/os/sys_misc.c:199-234` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: do_select ignores i686_copy_to_guest errors on the three fd_sets and returns the original non-negative ret. A failed fd_set copy-out is reported as a successful select, leaving the guest with stale descriptor sets.
  - **Fix**: If any fd_set copy-out fails, return EFAULT instead of the host select result.

- [x] **I686-R13-3 — High — SECURITY — Opens fall through to the host filesystem**
  - **Where**: `i686rt` `src/os/sys_pass_fs.c:146-190` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: open_guest opens the raw path when the sysroot-prefixed open fails or does not fit, and sys_open uses that helper for every path i686_proc_open_at declines. Guest open is not confined to the sysroot or to synthesized /proc files and can open host paths.
  - **Fix**: If the sysroot open fails, return that error. Do not open the raw guest path on the host.

- [x] **I686-R13-4 — Low — DRY — Open-flag maps disagree**
  - **Where**: `i686rt` `src/os/sys_misc_internal.h:57-95` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: This table says i386 and aarch64 O_ bits are bit-identical and sets I686_HO_DIRECT/DIRECTORY/NOFOLLOW to 0x4000/0x10000/0x20000, but src/os/sys_pass_internal.h:114-150 sets HOST_O_DIRECT/DIRECTORY/NOFOLLOW to 0x10000/0x4000/0x8000. The two host encodings of O_DIRECT, O_DIRECTORY, and O_NOFOLLOW are swapped, so one map cannot be substituted for the other without flipping those bits.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **I686-R13-5 — Low — YAGNI — Cache_dir is write-only**
  - **Where**: `i686rt` `src/main.c:148-150` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: A search found no caller that reads cache_dir; these lines only store I686RT_CACHE into it. --cache and I686RT_CACHE are kept on the context and never consulted, so the directory does not select an AOT or file cache.
  - **Fix**: Read the field on the path that is supposed to consume it, or delete the write.

- [x] **I686-R13-6 — Low — YAGNI — I686_thread_registry_add has no caller**
  - **Where**: `i686rt` `src/os/clone.c:182-195` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: A search found no caller of i686_thread_registry_add; the only mentions are this prototype and definition. The exported registry insert is dead, so clone keeps using thread_registry_commit and this copy can diverge from the reservation accounting.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **I686-R13-7 — Low — YAGNI — I686_threads_init has no caller**
  - **Where**: `i686rt` `src/os/clone.c:890-899` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: A search found no caller of i686_threads_init; the body only registers the clone syscall. A second thread-init entry stays linked and can drift from i686_threads_main_init, which is the init main actually runs.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **I686-R13-8 — Low — YAGNI — I686_vm_file_note_shrink has no caller**
  - **Where**: `i686rt` `src/vm/vm_file.c:426-434` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: A search found no caller of i686_vm_file_note_shrink; the function only locks and calls vm_file_shrink_locked. The exported shrink hook is never used; ftruncate already calls vm_file_shrink_locked from i686_vm_file_note_ftruncate under the same lock.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **I686-R13-9 — Low — CLEAN — Epilogue comment spills GPRs**
  - **Where**: `i686rt` `src/dbt/emit_exit.c:9-87` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: The header says i686_emit_exit stores live guest GPRs w0..w7 back to ctx->gpr, but the function body only writes the exit triplet from w8/w9/w10 and, for BRANCH, eip. A block exit does not spill EAX..EDI; those registers stay live until the trampoline's .Lexit, so any path that trusts this epilogue drops the guest GPRs.
  - **Fix**: Spill the live guest GPRs in this epilogue, or correct the header so it does not say that it does.

- [x] **I686-R13-10 — Medium — CLEAN — Sigreturn drops a bad fpstate**
  - **Where**: `i686rt` `src/os/signals_i386.c:499-529` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: When sc.fpstate is nonzero and i686_copy_from_guest fails, i686_sigreturn skips the x87/XMM restore and still returns 0. A bad fpstate pointer resumes the guest as a successful sigreturn with the saved x87 and XMM state dropped, instead of the -1/SIGSEGV path used for a bad sigcontext.
  - **Fix**: Take the bad-frame path when the fpstate copy fails instead of returning 0.

- [x] **I686-R13-11 — Medium — CLEAN — Futex load ignores protect failure**
  - **Where**: `i686rt` `src/vm/vm32.c:309-326` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: On regime A2, vm32_futex_load_u32 discards i686_vm32_union_prot and i686_vm32_widen_prot failures and still returns 0. A failed re-widen leaves the host page at the union protection while the futex waiter treats the load as successful, so a PROT_NONE neighbor on that host page stays accessible.
  - **Fix**: Return the protect error and do not report the futex load as success.

### `mips32rt` (`3fb98db8f8ca`)

- [x] **M32-R13-1 — High — SECURITY — Apple sigtramp page left writable**
  - **Where**: `mips32rt` `src/os/signals.c:381-446` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: On Apple, l4a_ensure_sigtramp mprotects a 16KiB span to PROT_READ|PROT_WRITE and the only later drop to PROT_READ is inside #ifndef __APPLE__, while both comments say the host mapping stays PROT_READ. The sigtramp host page and the other pages in that 16KiB span stay writable after a successful install, so host write protection does not match the non-writable guest VMA.
  - **Fix**: After writing the trampoline, mprotect the whole 16 KiB span to PROT_READ on Apple as well.

- [x] **M32-R13-2 — High — SECURITY — Mremap ignores a failed mprotect**
  - **Where**: `mips32rt` `src/rt32/vm_mmap.c:597-611` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: When prot differs from rw_prot, the mprotect result is discarded with (void) and rt32_vm_mremap still returns new_va. A guest mremap is reported successful even when the host protection change did not happen, leaving the moved pages at the pre-mprotect host protection.
  - **Fix**: If the post-mremap mprotect fails, undo the remap and return the error.

- [x] **M32-R13-3 — Medium — PERFORMANCE — SMC version lookup locks and scans**
  - **Where**: `mips32rt` `src/dbt/dbt.c:316-348` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: When any SMC slot is in use and the one-page memo misses, dbt_smc_version holds g_smc_lock while it scans every DBT_SMC_TABLE_SIZE entry. Each block lookup whose guest page is not the single memoized page serializes on the process-wide SMC lock and walks all 1024 table slots.
  - **Fix**: Hold the lock only around the table update. Do the copy or the probe outside the lock.

- [x] **M32-R13-4 — Low — PERFORMANCE — Publish reprotects the whole pool**
  - **Where**: `mips32rt` `src/dbt/dbt.c:610-623` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: This publish branch mprotects from the pool page base through pool_used plus the new length, twice, around the copy. Every newly translated block changes protection on the entire occupied code pool, and that span grows with pool_used up to the 16 MiB pool.
  - **Fix**: Do this work once and reuse the result.

- [x] **M32-R13-5 — Medium — PERFORMANCE — Region permission walk is linear**
  - **Where**: `mips32rt` `src/mips32rt.h:297-334` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: mips32_range_ok calls rt32_vm_sync_ctx and then walks ctx->regions from index 0 until the range is covered or rejected. Every interpreter instruction fetch, and every A1 guest memory access, scans the region map from the bottom, up to 512 entries, with no page cache.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **M32-R13-6 — Low — PERFORMANCE — A2 validate misses once per byte**
  - **Where**: `mips32rt` `src/os/mem.c:272-283` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: a2_validate calls mips32_vm_tlb_miss once per byte of len, always with width 1. On regime A2 every interpreter fetch and every guest load or store repeats the Soft-TLB miss helper once per byte, so a 4-byte access pays four miss calls and four region walks.
  - **Fix**: Do this work once and reuse the result.

- [x] **M32-R13-7 — Medium — DRY — Delay-slot rule disagrees**
  - **Where**: `mips32rt` `src/dbt/trace.c:84-119` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: has_delay_slot returns true for REGIMM rt 0x12..0x13 and for COP0 or COP1 with rs in 8..11, while is_regimm_branch and mips_is_branch at src/interp/decode.c:77-106 list only BLTZ/BGEZ/BLTZL/BGEZL/BLTZAL/BGEZAL and accept COP1 only when rs==MIPS_COP1_RS_BC and rt<=MIPS_COP1_BC1TL. Trace replay and the shared branch decoder do not use one delay-slot rule, so COP0/COP1 rs 9..11 and BLTZALL/BGEZALL are delay slots in one copy and not in the other.
  - **Fix**: Keep one copy in this repository and make the other site call it, using the interpreter or the documented contract where the copies already disagree.

- [x] **M32-R13-8 — Medium — DRY — Link rule disagrees**
  - **Where**: `mips32rt` `src/interp/decode.c:141-154` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: mips_is_link returns true for every JALR and only REGIMM BLTZAL or BGEZAL, while dbt_is_link at src/dbt/dbt.c:145-161 requires JALR rd==MIPS32_REG_RA and also returns true for REGIMM rt 0x12 and 0x13. The return-address stack and the shared link decoder disagree on JALR with rd other than MIPS32_REG_RA and on BLTZALL/BGEZALL.
  - **Fix**: Keep one copy in this repository and make the other site call it, using the interpreter or the documented contract where the copies already disagree.

- [x] **M32-R13-9 — Low — YAGNI — Unused mips32_host_map_anon**
  - **Where**: `mips32rt` `src/os/backend_linux.c:79-106` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: A search of the repository found no caller of mips32_host_map_anon. The function is compiled in through Makefile U3_BACKEND_SRC and never invoked; guest mapping calls mmap directly.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M32-R13-10 — Low — YAGNI — Unused mips_sc_futex**
  - **Where**: `mips32rt` `src/os/syscalls_meta.c:719-786` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: A search of the repository found no caller of mips_sc_futex. This WAIT/WAKE futex handler is linked and never reached; the syscall switch calls mips_sc_futex_thread instead.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M32-R13-11 — Low — YAGNI — Unused rt32_vm_mremap**
  - **Where**: `mips32rt` `src/rt32/vm_mmap.c:450-469` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: A search of the repository found no caller of rt32_vm_mremap. The guest mremap implementation that begins here and ends at line 652 is linked and never reached.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M32-R13-12 — Low — YAGNI — Unused mips32_fixade_sysmips**
  - **Where**: `mips32rt` `src/vm/vm32.c:64-71` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: A search of the repository found no caller of mips32_fixade_sysmips. The FIXADE helper is linked and never reached; the sysmips case writes fixade_enabled inline.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M32-R13-13 — Low — CLEAN — Exact float-to-int skips Inexact**
  - **Where**: `mips32rt` `src/interp/fp.c:557-586` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: The fp_to_int comment says the conversion always raises Inexact, but a zero operand returns 0 with no fp_raise and an exact INT_MIN/LONG_MIN returns 0 with an explicit no-flags comment. Exact float-to-int results leave the Inexact flag clear.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

- [x] **M32-R13-14 — Low — CLEAN — Unaligned FP moves fault**
  - **Where**: `mips32rt` `src/interp/fpmove.c:14-86` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: The file header says aligned and unaligned addresses behave identically through byte-wise guest_ld/st8, but fpmove_mem calls mips_fault_align and returns MIPS_FAULT when an LWC1/SWC1 address is not 4-byte aligned. Unaligned LWC1/SWC1 take an alignment fault instead of the byte-wise transfer the header describes.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

### `ppc32rt` (`621e36892ffb`)

- [x] **P32-R13-1 — High — SECURITY — DBT fetch skips guest NX**
  - **Where**: `ppc32rt` `src/dbt/dbt.c:440-465` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: The comment says guest fetch mirrors interp fetch_raw, but the translator's only fetch is memcpy through ppc32_guest_ptr after a same-page test, with no execute-permission or mapping check. A readable non-executable guest page is translated and run, so guest NX is not enforced on the DBT path.
  - **Fix**: Fetch through the same guest execute-permission check the interpreter uses.

- [x] **P32-R13-2 — High — SECURITY — Statx writes the guest buffer unchecked**
  - **Where**: `ppc32rt` `src/os/syscalls_dyn.c:120-149` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: dyn_put_statx zero-fills and stores the 256-byte statx image through ppc32_guest_ptr and ppc32_st*be after only ppc32_range_ok, then returns 0. An unmapped or non-writable statx buffer is not rejected, so the syscall writes through a raw host pointer and can SIGSEGV the translator.
  - **Fix**: Reject a statx buffer that is unmapped or not guest-writable before any store.

- [x] **P32-R13-3 — High — SECURITY — A2 mmap ignores final union sync**
  - **Where**: `ppc32rt` `src/rt32/ppc32_vm.c:483-504` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: The A2 private mmap checks the temporary RW union sync and returns ENOMEM on failure, then records the real guest prot and ignores the second vm32_sync_host_range. If the final host-page mprotect fails, mmap continues and the host page stays writable from the temporary RW mapping.
  - **Fix**: If the final host-page sync fails, drop the new mapping and return the error.

- [x] **P32-R13-4 — High — SECURITY — Truncate zero leaves host pages writable**
  - **Where**: `ppc32rt` `src/vm/vm_file.c:407-441` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: After mprotect widens the span to PROT_READ|PROT_WRITE, a failed vm32_sync_host_range is ignored and the function returns, so the widened host protection is not restored. A failed permission restore after truncate zeroing leaves the guest file pages host-writable.
  - **Fix**: If the permission restore after zeroing fails, put the previous host protection back and return the error.

- [x] **P32-R13-5 — Medium — PERFORMANCE — Cache hit recopies guest bytes under lock**
  - **Where**: `ppc32rt` `src/dbt/cache.c:404-466` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: ppc32_cache_lookup holds s_cache_lock across snapshot_clean, which copyin-compares up to 4096 recorded guest bytes, and the comment says that copy runs under the VM lock. Every translation-cache hit that has a snapshot serializes on the process-wide cache mutex while re-reading the translated guest bytes.
  - **Fix**: Hold the lock only around the table update. Do the copy or the probe outside the lock.

- [x] **P32-R13-6 — Low — PERFORMANCE — Install walks the entire block table**
  - **Where**: `ppc32rt` `src/dbt/cache.c:540-618` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: While holding s_cache_lock, a colliding ppc32_cache_install rewrites keyepoch for every occupied table slot after bumping the epoch, and every install then walks all PPC32_DBT_HT_SIZE slots to backfill links. Each translated-block install scans the whole direct-mapped cache under the process-wide mutex, and a collision rewrites every other block's epoch.
  - **Fix**: Do this work once and reuse the result.

- [x] **P32-R13-7 — Low — DRY — String byte-pack loop copied**
  - **Where**: `ppc32rt` `src/interp/interp.c:609-649` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: The lswi/stswi byte pack and unpack loop is repeated for lswx/stswx at src/interp/interp.c:669-708, with the same register wrap, big-endian shift, partial-word clear, and fault-stop rule. A change to partial-word clearing or the fault-stop rule must be applied twice or lswi and lswx diverge.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **P32-R13-8 — Low — DRY — Guest stat layouts declared twice**
  - **Where**: `ppc32rt` `src/os/sigframe_ppc32.h:84-132` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: ppc32_stat_t and ppc32_stat64_t are declared again at src/os/convert.h:38-83, with named st_pad_nlink and st_pad2b[6] where this copy leaves those bytes as unnamed holes after st_nlink and __pad2. A padding or offset edit in one guest stat layout is not type-checked against the other, and the two ppc32_stat_t typedefs cannot be included in one translation unit.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **P32-R13-9 — Low — DRY — Host stat timestamps copied**
  - **Where**: `ppc32rt` `src/os/syscalls_dyn.c:339-388` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: The Linux st_atim, Darwin st_*timespec, and strict-C11 st_atime selection for atime, ctime, and mtime is copied from src/os/convert.c:38-106. A host stat member change must be edited in both places or stat and statx report different timestamps for the same file.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **P32-R13-10 — Low — YAGNI — Unused SPE saturating add**
  - **Where**: `ppc32rt` `src/interp/fp_spe.h:182-196` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: fp_mac_sat_add saturates a signed 32-bit lane add and a search found no caller. fp_spe_mac saturates lanes with its own unsigned carry test, so this signed clamp and its SPEFSCR SOV/OV raise never run.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P32-R13-11 — Low — YAGNI — Unused add overflow helper**
  - **Where**: `ppc32rt` `src/interp/interp.h:153-156` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: add_overflow computes the signed-add overflow bit and a search found no caller. interp_step addo. sets XER.OV from a wide signed sum via xer_set_ov, so this bit formula never updates XER.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P32-R13-12 — Low — YAGNI — Unused sub overflow helper**
  - **Where**: `ppc32rt` `src/interp/interp.h:159-162` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: sub_overflow computes the signed-subtract overflow bit and a search found no caller. interp_step subfo. sets XER.OV from a wide signed difference via xer_set_ov, so this bit formula never updates XER.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P32-R13-13 — Low — YAGNI — Unused r15 PC loader**
  - **Where**: `ppc32rt` `src/rt32/ppc32_a64_emit.h:143-150` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: ppc32_load_reg treats register 15 as a PC immediate and a search found no caller. No emitter loads a guest GPR through this helper, so the A32 r15-as-PC special case is dead in the PPC encoder header.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P32-R13-14 — Medium — CLEAN — Futex wake reports success on failure**
  - **Where**: `ppc32rt` `src/os/backend_darwin.c:556-569` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: rt_host_futex_wake returns 0 when __ulock_wake is missing and returns count after discarding the wake call's result. A missing or failed Darwin wake is reported as a successful futex wake, so waiters stay asleep while the guest is told they were woken.
  - **Fix**: Return the wake error when the Darwin wake is missing or fails.

- [x] **P32-R13-15 — Medium — CLEAN — Brk shrink ignores unmap failure**
  - **Where**: `ppc32rt` `src/rt32/ppc32_vm.c:288-318` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: ppc32_vm_brk discards a failed vm32_unmap_union or vm_reserve_prot_none and still stores and returns new_brk. The guest break shrinks even though the host range was not unmapped or reprotected, so the released heap can stay mapped.
  - **Fix**: Keep the old break when unmap or the PROT_NONE reserve fails.

- [x] **P32-R13-16 — Medium — CLEAN — Staged map ignores sync failure**
  - **Where**: `ppc32rt` `src/vm/vm_file_stage.c:405-429` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: vm_file_shared_map_at says it returns a negative errno on failure, then discards vm32_sync_host_range's error and returns 0. A failed host permission sync still publishes the staged MAP_SHARED mapping as success, so the arena page can stay PROT_READ|PROT_WRITE when the guest prot was narrower.
  - **Fix**: Return the sync error and do not publish the mapping as success.

### `sparc32rt` (`f343b8b2a375`)

- [x] **S32-R13-1 — High — SECURITY — Signal delivery ignores a failed window spill**
  - **Where**: `sparc32rt` `src/interp/interp_signal.c:39-70` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: Flush and live-window stores are cast to void, a failed range check skips the live spill, and the function still returns a stack pointer. Signal delivery continues after a failed window flush or a skipped live-window spill, so the interrupted register windows are not on the guest stack.
  - **Fix**: Abort signal delivery if the window flush or the live-window spill fails.

- [x] **S32-R13-2 — High — SECURITY — Sigreturn drops the window cursor**
  - **Where**: `sparc32rt` `src/os/syscalls_sig.c:531-560` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: The success path writes ctx->psr, the live g/o/l/i registers, pc, and npc, then returns 0 without assigning ctx->cwp, win_valid, or winfile. sigreturn leaves the register-window cursor and cached windows on the handler's window, so the interrupted window chain is not restored.
  - **Fix**: Restore cwp, win_valid, and winfile from the signal frame before returning success.

- [x] **S32-R13-3 — High — SECURITY — Sysroot ELF open fails open onto the host**
  - **Where**: `sparc32rt` `src/rt32/elf32.c:132-143` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: When the sysroot-prefixed open fails or the joined path does not fit, the function opens the original absolute guest path on the host. Execve and interpreter opens that miss the sysroot still open the absolute path on the host filesystem.
  - **Fix**: If the sysroot-prefixed open fails, return that error instead of opening the guest path on the host.

- [x] **S32-R13-4 — High — SECURITY — Large-page munmap ignores mprotect failure**
  - **Where**: `sparc32rt` `src/rt32/vm_mmap.c:690-698` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: When the host page is larger than 4 KiB, a failed mprotect to PROT_NONE is discarded and the function returns 0. Guest munmap reports success while the host pages keep their previous permissions.
  - **Fix**: If the large-page PROT_NONE mprotect fails, return -errno and do not report the range as unmapped.

- [x] **S32-R13-5 — Low — PERFORMANCE — Interpreter re-decodes every step**
  - **Where**: `sparc32rt` `src/interp/interp.c:751-808` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: Every interp_step call fetch-decodes ctx->pc into a fresh stack sparc32_decoded_t, and interp_run calls that on every iteration with no stored decode. Re-executing a guest PC, including each iteration of a loop, pays a full fetch and decode again because the dispatch loop keeps no decoded-instruction cache.
  - **Fix**: Do this work once and reuse the result.

- [x] **S32-R13-6 — Low — DRY — Page-final branch path copied**
  - **Where**: `sparc32rt` `src/dbt/emit_cti.c:237-281` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: src/dbt/emit_fpbranch.c:206-241 copies this page-final path (cache snapshot, not-taken delay, cache restore, taken delay, then single-step the target) but always arms and disarms the jmpl record, while this copy gates both on need_rec. Bicc and FBfcc page-final delay exits can diverge because the annul and jmpl-record rule is maintained twice.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **S32-R13-7 — Low — DRY — Double-dest opf sets disagree**
  - **Where**: `sparc32rt` `src/interp/decode.c:37-63` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: src/dbt/emit_fp.c:696-713 treats opf 0x02A as a double destination and FPop2 opf 0x069 as one, while this switch omits 0x02A and returns 0 for every FPop2. Odd-rd FSQRTd (opf 0x02A) stays a legal FPop here and is rejected by the DBT copy.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **S32-R13-8 — Low — DRY — SPARC ENOSYS numbers disagree**
  - **Where**: `sparc32rt` `src/os/syscalls_min.c:113-151` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: src/os/futex.c:39-45 encodes the same guest errno set with SP_ENOSYS 38, while this switch returns 90 for ENOSYS. Unsupported futex ops are guest errno 90 through this map and 38 through the futex constants.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **S32-R13-9 — Low — YAGNI — Uncalled JMPL recorder**
  - **Where**: `sparc32rt` `src/dbt/dbt_cache.c:447-455` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: A search of the repository found no caller of dbt_jmpl_record_target; the only occurrence is this definition. Dead global: nothing invokes it, so its stores to jmpl_target, jmpl_delay_armed, and the AOT delay target never run.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S32-R13-10 — Low — YAGNI — Uncalled Darwin JIT allocator**
  - **Where**: `sparc32rt` `src/os/backend_darwin.c:96-110` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: A search of the repository found no caller of rt_host_jit_alloc_darwin; the only occurrence is this definition. Dead allocator: the DBT arena is mapped in dbt_arena_ensure_rw_locked, so this MAP_JIT function is never used.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S32-R13-11 — Low — YAGNI — Uncalled blocked-mask getter**
  - **Where**: `sparc32rt` `src/os/syscalls_time.c:39-45` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: A search of the repository found no caller of sparc32_l2a_blocked_mask; the only occurrence is this definition. Dead getter that always returns 0 and never reports ctx->sig_mask; live updates go through sparc32_l2a_set_blocked_mask.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S32-R13-12 — Low — YAGNI — Uncalled regime getter**
  - **Where**: `sparc32rt` `src/vm/vm32.c:117-121` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: A search of the repository found no caller of vm32_regime; the only occurrence is this definition. Dead getter: g_vm32_regime is stored when the window is reserved or attached and this function is its only read, so the A1/A2 regime is never observed.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S32-R13-13 — Low — CLEAN — TEM recheck comment is once-per-block**
  - **Where**: `sparc32rt` `src/dbt/emit_fp.c:48-80` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: The comment says TEM is rechecked on every op while the RD check stays once-per-block, but a set fp_fast_checked flag returns before both checks and is then set for the rest of the block. After the first successful guard, later FP ops in the block skip the TEM test the comment says runs on every op.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

- [x] **S32-R13-14 — Low — CLEAN — Convert comment names FRINT32X**
  - **Where**: `sparc32rt` `src/dbt/emit_fp.c:593-639` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: The comment says the conversion sequence rounds with FRINT32X per FSR.RD, but fp_emit_convert emits SCVTF and FCVTZS and the FsTOi case is explicitly round-toward-zero. The emitted float conversions do not use FRINT32X, and FsTOi does not honor FSR.RD.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

- [x] **S32-R13-15 — Medium — CLEAN — Brk shrink ignores reserve failure**
  - **Where**: `sparc32rt` `src/rt32/vm.c:811-871` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: brk growth returns the old break when mprotect or mmap fails, but a shrink discards vm_reserve_prot_none's result and still returns new_brk. A failed shrink reserve still commits the new break, so the guest is told the pages are gone while the host mapping may remain.
  - **Fix**: Return the failed call's error instead of 0 or the new break.

### `rvrt` (`ca1ef7bc3a4d`)

- [x] **RV-R13-1 — Medium — PERFORMANCE — Block lookup scans every cached block**
  - **Where**: `rvrt` `src/dbt/cache.c:165-181` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: rv_dbt_block_lookup walks cache->blocks from slot zero through block_count, comparing guest_pc_base and generation, with no direct index. Each lookup compares every live block in the array, and a hit also increments that block's hits and its chain_next block's hits.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **RV-R13-2 — Low — PERFORMANCE — Validation re-fetches the block**
  - **Where**: `rvrt` `src/jit/a64.c:593-626` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: rv_jit_source_validate reads every instruction of the block through memory->read and rebuilds the raw word to compare with the stored source_words. Each validation performs one guest instruction fetch per instruction in the block instead of using the cached source words.
  - **Fix**: Do this work once and reuse the result.

- [x] **RV-R13-3 — Medium — PERFORMANCE — JIT dispatch scans the block array**
  - **Where**: `rvrt` `src/runtime/runtime_main_worker.c:187-207` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: Every JIT dispatch walks blocks[] from the first slot until guest_pc and memory_generation match, and a matching slot then calls rv_dbt_block_lookup. Each return to the dispatcher scans the whole live prefix of the block array, then a hit starts a second series-cache lookup before the block runs.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **RV-R13-4 — Low — DRY — Handoff import skips restat**
  - **Where**: `rvrt` `src/linux/fd_handoff.c:401-419` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: rv_fd_handoff_receive decodes the pread bytes with no second stat, while src/runtime/exec_state.c:840-842 rejects the import unless same_record_stat still matches. A same-length rewrite during pread can be restored as a guest FD table even though exec-state import treats that as a changed record.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **RV-R13-5 — Low — DRY — ELF load rule copied**
  - **Where**: `rvrt` `src/loader/image.c:320-376` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: map_snapshot repeats the writable-implies-readable permission, bias placement, and map-then-fill rule that src/loader/elf32.c:197-254 applies to ELF32. A change to W-implies-R, PIE placement, or map-before-write must be made in both mappers or ELF32 and ELF64 diverge.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **RV-R13-6 — Low — DRY — Stat snapshot fields disagree**
  - **Where**: `rvrt` `src/runtime/aot_cache.c:103-112` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: runtime_digest treats dev, ino, size, and mtime as an unchanged file, while metadata_same in src/aot/reader.c:66-82 also requires mode, uid, gid, nlink, and ctime. A mode or ctime change during the runtime hash still accepts the digest that an AOT record read rejects.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **RV-R13-7 — Low — YAGNI — Rv32_wrap_add has no caller**
  - **Where**: `rvrt` `src/core/rv32.h:20-23` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: A search of the repository found no caller of rv32_wrap_add; the only match is this static inline definition. The header advertises a 32-bit wrapping add that no interpreter, JIT, or loader call uses.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RV-R13-8 — Low — YAGNI — Rv_elf32_entry has no caller**
  - **Where**: `rvrt` `src/loader/elf32.c:55-58` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: A search of the repository found no caller of rv_elf32_entry; the symbol appears only as this definition and its header declaration. An exported ELF32 e_entry reader is linked with no call site, while map_snapshot loads the same field itself.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RV-R13-9 — Low — YAGNI — Cleanup prepare wrapper has no caller**
  - **Where**: `rvrt` `src/runtime/family.c:480-486` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: A search of the repository found no caller of rv_family_cleanup_service_prepare; the symbol appears only as this definition and its header declaration. The AUTO-authority cleanup prepare wrapper is never installed or called; the service hook uses rv_family_cleanup_service_prepare_context.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RV-R13-10 — Low — YAGNI — Rv_vm_file_resize_seq has no caller**
  - **Where**: `rvrt` `src/vm/vm_file.c:303-308` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: A search of the repository found no caller of rv_vm_file_resize_seq; the symbol appears only as this definition and its header declaration. resize_seq is incremented on truncate, write growth, and stale refresh, but this uncalled getter is the only read, so the sequence is never observed.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RV-R13-11 — Low — CLEAN — FPSR flush is not between CMP and Bcc**
  - **Where**: `rvrt` `src/darwin_dbt_emit.c:577-586` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: The comment says the FPSR flush sits between CMP and Bcc because it is flag-neutral, but the compare's Bcc is emitted on the line before the flush. The compare's Bcc already consumed NZCV before the flush, so the comment's flag-preservation placement is not what this block emits.
  - **Fix**: Emit the FPSR flush between CMP and Bcc, or correct the comment.

- [x] **RV-R13-12 — Low — CLEAN — Beyond-EOF comment zeros the page**
  - **Where**: `rvrt` `src/vm/vm64.c:759-779` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: The comment says a wholly past-EOF page never touches its bytes, but when prepare_writable does not install a fresh mapping the code memset's that page to zero. A live file-backed page past the rounded end of file is written on the non-fresh path, which the comment says the host turns into SIGBUS.
  - **Fix**: Leave a wholly past-EOF page untouched, or correct the comment if zeroing is the intended contract.

### `loongarch64rt` (`eec0f3d517bd`)

- [x] **LA64-R13-1 — Medium — PERFORMANCE — Decode walks the opcode table**
  - **Where**: `loongarch64rt` `src/interp/decode.c:350-358` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: la64_decode searches dc_table from index 0 until a mask/match hit. Every interp_step, every word of translate_block, and every soft-TLB miss calls this, so each of those walks dc_table from the first row; branch rows sit after the integer ALU and load/store rows.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **LA64-R13-2 — Low — PERFORMANCE — Stores resolve each byte twice**
  - **Where**: `loongarch64rt` `src/interp/interp_mem.h:104-149` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: st_bytes calls la64_mem_ptr with length 1 for every byte in a precheck loop and again for every byte in the commit loop. Each interpreter scalar store of n bytes performs 2n la64_mem_ptr resolutions while the store lock is held, and each resolution that misses the arena rescans regions[].
  - **Fix**: Do this work once and reuse the result.

- [x] **LA64-R13-3 — Medium — PERFORMANCE — Address lookup scans regions**
  - **Where**: `loongarch64rt` `src/os/mem_min.c:306-378` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: find_containing walks regions from index 0, and la64_mem_ptr calls it whenever vm64_ptr does not return a pointer. LA64_MEM_MAX_REGIONS is 256. Loader text is a mem_min mapping inside the 1 GiB arena, so vm64_ptr misses and each interpreter fetch, translation fetch, and miss-path lookup scans the region table.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **LA64-R13-4 — Medium — PERFORMANCE — Hole search steps one page at a time**
  - **Where**: `loongarch64rt` `src/os/mem_min.c:738-766` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: la64_mem_find_hole calls vm64_owned_end on every guest page of the candidate span and can repeat that walk once per kick. sys_mmap's anonymous hole search uses this. The default candidate is 0x4000000000, above the 1 GiB arena, where vm64_owned_end returns the same address, so the walk still costs one call per page of the request and up to 257 kicks.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **LA64-R13-5 — Low — DRY — FCMP -0/+0 copies disagree**
  - **Where**: `loongarch64rt` `src/dbt/emit_fp_mem.c:228-248` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: This sequence selects the equal predicate only when the raw operand bits match and otherwise orders opposite signs by sign(j), while src/interp/fp.c:235-237 also treats opposite-sign zeros as equal before that less-than test. Translated FCMP reports -0 and +0 as ordered, while the interpreter reports them equal, so fcc differs for the same guest word.
  - **Fix**: Use one FCMP ±0 rule so the DBT and the interpreter agree.

- [x] **LA64-R13-6 — Low — YAGNI — Unused a64e_ldr_w**
  - **Where**: `loongarch64rt` `src/dbt/a64_emit.c:503-513` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: A search found no caller of a64e_ldr_w, and a64_emit.h does not declare it. The 32-bit scaled LDR encoder is linked into a64_emit.c and never executed.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **LA64-R13-7 — Low — YAGNI — Unused la64_sigframe_size**
  - **Where**: `loongarch64rt` `src/linux/signal_frame_loongarch64rt.c:12-29` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: A search found no caller of la64_sigframe_size; delivery uses LA64_RT_SIGFRAME_SIZE instead. The sctx size helper is linked from signal_frame_loongarch64rt.c and its result is never read.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **LA64-R13-8 — Low — YAGNI — Unused la64_clone_child_tid**
  - **Where**: `loongarch64rt` `src/os/clone.c:619-626` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: A search found no caller of la64_clone_child_tid; thread exit reads slot->ctid_va directly. The weak getter is linked from clone.c and never consulted by exit or join.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **LA64-R13-9 — Low — YAGNI — Unused la64_worker_loop_run**
  - **Where**: `loongarch64rt` `src/os/worker_loop.c:31-47` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: A search found no caller of la64_worker_loop_run; main calls interp_run and dbt_run instead. The compiled worker entry only prints a Phase 0 refusal and returns 2, so it cannot start a guest.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **LA64-R13-10 — Low — CLEAN — CPUCFG comment says phase-2**
  - **Where**: `loongarch64rt` `src/dbt/emit_int.c:349-375` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: The comment says CPUCFG selects the phase-2 word, but index 2 replaces words[2] (0x1840c000) with 0x1840c00f or 0x1840c0cf before the compare-select. A guest CPUCFG of word 2 observes the phase-3 value, not the phase-2 word the comment states.
  - **Fix**: Select the phase-2 CPUCFG word the comment names, or correct the comment to the phase-3 value this code stores.

- [x] **LA64-R13-11 — Medium — CLEAN — Pipe2 ignores fcntl failure**
  - **Where**: `loongarch64rt` `src/os/minsys.c:658-690` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: The non-Linux path ignores failed F_SETFD and F_SETFL calls and sys_pipe2 still returns 0 after publishing the new fds. A guest pipe2 with O_CLOEXEC or O_NONBLOCK returns 0 even when the flag fcntl failed, so the pipe lacks the requested flag.
  - **Fix**: Return the fcntl error and do not publish the new fds as a successful pipe2.

- [x] **LA64-R13-12 — Medium — CLEAN — Unmap ignores writeback failure**
  - **Where**: `loongarch64rt` `src/vm/vm_file_sync.c:824-898` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: vmfile_unmap discards vmfile_staged_writeback_locked's result, clears the shared map row anyway, and returns 0. A failed shared writeback is not reported, the dirty row is dropped, and the unmap succeeds, so those guest bytes never reach the file.
  - **Fix**: Return the writeback error and keep the dirty row until the bytes reach the file.

### `ppc64rt` (`3c236f2584e9`)

- [x] **P64-R13-1 — High — SECURITY — Cache reset ignores mprotect failure**
  - **Where**: `ppc64rt` `src/dbt/cache.c:155-168` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: ppc64_dbt_cache_reset discards the ppc64_host_protect result and still rewinds both write and RX frontiers to the arena base. W^X: a failed mprotect leaves the sealed JIT prefix executable while the write frontier is reset onto it.
  - **Fix**: If the host protect call fails, return the error and do not rewind a frontier onto a page that is still executable.

- [x] **P64-R13-2 — High — SECURITY — Execve uses the guest path as a host path**
  - **Where**: `ppc64rt` `src/os/proc.c:488-550` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: After rejecting only a /proc/ prefix, execve passes that same path buffer to ppc64_host_execve with no root join. A guest execve pathname is a host executable path, so the call fails open into the host filesystem.
  - **Fix**: Join the guest pathname to the guest root before the host execve, and reject a path outside that root.

- [x] **P64-R13-3 — High — SECURITY — Relative faccessat skips root resolution**
  - **Where**: `ppc64rt` `src/os/syscalls_access.c:144-174` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: A relative faccessat copies the guest string into raw and passes that raw string to host faccessat on the directory fd, while the absolute path calls syscall_resolve_path. A guest-controlled relative path is resolved by the host from a directory fd, so the lookup fails open outside the configured guest root.
  - **Fix**: Resolve a relative faccessat path inside the guest root before the host call.

- [x] **P64-R13-4 — Medium — PERFORMANCE — Block registry lookup is a linear scan**
  - **Where**: `ppc64rt` `src/dbt/dbt.c:327-348` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: ppc64_dbt_block_lookup finds block_id by walking every g_blocks entry from index 0 through g_nblocks-1. Every Soft-TLB miss starts with this scan, and the registry gains one entry per sealed block, so miss cost grows with the number of translated blocks.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **P64-R13-5 — Low — PERFORMANCE — 16-byte miss never fills the Soft-TLB**
  - **Where**: `ppc64rt` `src/vm/vm64.c:644-660` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: This Soft-TLB fill runs only when width <= 8, so a 16-byte miss does not execute ppc64_vm_tlb_fill. A guest loop of only 16-byte accesses never installs a tag for that page, so each access re-enters the miss helper and its block-registry scan.
  - **Fix**: Do this work once and reuse the result.

- [x] **P64-R13-6 — Low — DRY — Wait4 poll loop copied into both backends**
  - **Where**: `ppc64rt` `src/os/backend_linux.c:407-470` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: ppc64_host_wait4 translates Linux wait bits 1, 2, and 8 and polls with ppc64_back_wait_fd until sig_seq changes, and src/os/backend_darwin.c:452-517 repeats that same host-independent control flow. A change to the wait-option mask or the EINTR and sig_seq loop must be edited in both backends or the hosts diverge.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **P64-R13-7 — Medium — DRY — Two rt_sigaction installers disagree**
  - **Where**: `ppc64rt` `src/os/syscalls_access.c:361-405` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: syscall_sigaction copies the raw sa_mask into x_sigact and discards a pending signal only when the handler word is 1, while src/run/sigdeliver.c:238-283 stores run_sigacts after applying ~RUN_SIG_UNMASKABLE and discards when run_sig_is_ignored(sig) is true. Syscall 173 updates one of two disposition tables, so the saved mask and whether a pending signal is dropped depend on which installer ran.
  - **Fix**: Keep one copy in this repository and make the other site call it, using the interpreter or the documented contract where the copies already disagree.

- [x] **P64-R13-8 — Medium — DRY — Host errno translators disagree**
  - **Where**: `ppc64rt` `src/os/syscalls_misc.c:64-123` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: syscall_host_to_linux returns the raw errno on Linux and otherwise has no case for ENOTDIR, ELOOP, EROFS, ENOTEMPTY, or EOVERFLOW, while src/os/syscalls_conv.c:47-59 maps those and returns 5 for ETIMEDOUT and EOPNOTSUPP, which this switch returns as named constants. The same host errno becomes a different guest errno depending on which translator the syscall calls.
  - **Fix**: Keep one copy in this repository and make the other site call it, using the interpreter or the documented contract where the copies already disagree.

- [x] **P64-R13-9 — Low — YAGNI — Hash-only AOT note is unused**
  - **Where**: `ppc64rt` `src/dbt/aot/aot.c:150-156` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: A search of the repository found no caller of ppc64_aot_note_block_hash. Publish and image load call ppc64_aot_note_block_code_hash, ppc64_aot_note_block, and ppc64_aot_note_block_code, so a sites-only hashed note is never recorded.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P64-R13-10 — Low — YAGNI — Ppc64_op_name has no caller**
  - **Where**: `ppc64rt` `src/interp/decode_fp.c:316-324` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: A search of the repository found no caller of ppc64_op_name. The op_names mnemonic table in this file is referenced only by this export, so those strings stay in the decode translation unit with no trace or difftest use.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P64-R13-11 — Low — YAGNI — Syscall_vma_uniform_attr has no caller**
  - **Where**: `ppc64rt` `src/os/syscalls_mm.c:748-771` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: A search of the repository found no caller of syscall_vma_uniform_attr. mremap coverage uses syscall_vma_cover_spans, so this overlapping prot and heap scan is dead code.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P64-R13-12 — Low — YAGNI — Vm_page_discard_from has no caller**
  - **Where**: `ppc64rt` `src/vm/vm64.c:141-146` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: A search of the repository found no caller of vm_page_discard_from. vm_dir_discard_from is invoked only from this function, so the page-directory discard walk never runs; file shrink zeroes tails in vm_file_shrink_map instead.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **P64-R13-13 — Low — CLEAN — Fast IBTC comment omits link and return**
  - **Where**: `ppc64rt` `src/dbt/dbt.c:117-138` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: The comment says link and return blocks are not inserted into the fast table, but dbt_fast_sync inserts every block that is not a fallback or a syscall. Link and return blocks stay in the fast IBTC, so the trampoline chains them instead of returning to C for RAS accounting.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

- [x] **P64-R13-14 — Medium — CLEAN — Darwin pipe2 ignores fcntl failure**
  - **Where**: `ppc64rt` `src/os/backend_fs_paths.c:194-211` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: On the non-Linux pipe2 path, failed fcntl calls that apply CLOEXEC or NONBLOCK are discarded and the function still returns 0. pipe2 reports success when the requested close-on-exec or nonblocking flag was not set.
  - **Fix**: Return the failed fcntl result instead of 0.

- [x] **P64-R13-15 — Low — CLEAN — Arena comment says reservation always succeeds**
  - **Where**: `ppc64rt` `src/vm/vm_dir.c:38-83` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: The comment says the 64 TiB PROT_NONE reservation always succeeds with no fallback, but vm_dir_arena_reserve returns false and latches g_arena_failed when mmap fails. A failed reservation is treated as impossible, so pages below VM_DIR_SPLIT are not guaranteed the single arena-wide addend the comment states.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

### `mips64rt` (`92e86b9ed717`)

- [x] **M64-R13-1 — High — SECURITY — Mmap ignores mprotect around the file copy**
  - **Where**: `mips64rt` `src/os/syscall_min.c:378-395` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: For a non-writable file mapping, sc_mmap discards both mprotect results around the memcpy and still returns the guest address. A failed restore leaves that host mapping writable while mmap still reports the guest mapping as installed.
  - **Fix**: If either mprotect around the file copy fails, unmap the new range and return the error.

- [x] **M64-R13-2 — Medium — PERFORMANCE — Soft-TLB fill holds U0 lock**
  - **Where**: `mips64rt` `src/os/backend_state.c:347-362` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: mips_soft_tlb_fill holds u0_lock across mips_vm_page_writable and u0_slot_locked until it stores one direct-mapped soft-TLB entry. Each soft-TLB miss keeps the process-wide U0 mutex while the page-flag hash is locked and probed and u0_slot_locked walks up to U0_MAX_SLOTS context rows.
  - **Fix**: Hold the lock only around the table update. Do the copy or the probe outside the lock.

- [x] **M64-R13-3 — Medium — PERFORMANCE — Region table scanned under lock**
  - **Where**: `mips64rt` `src/os/mem_table.c:186-218` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: mips_mem_ok takes mem_lock and walks g_regions from index zero until the span is covered or a gap or missing prot stops the walk. Every guest load and store, every soft-TLB fill, and every DBT word probe calls this, so each check is linear in g_region_count while the process-wide region mutex is held.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **M64-R13-4 — Medium — PERFORMANCE — Fetch walks the region table**
  - **Where**: `mips64rt` `src/os/mem_table.c:787-802` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: mips_mem_exec_ok takes mem_lock and walks g_regions from index zero until one region contains the four-byte pc, with no stop when a later start passes pc. Every interpreter instruction pays this scan under the process-wide region mutex, because mips_fetch calls mips_mem_exec_ok before it copies the word.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **M64-R13-5 — Low — DRY — Delay-slot classifiers disagree**
  - **Where**: `mips64rt` `src/dbt/emit_int.c:242-279` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: ei_is_control returns 1 for COP1 BC (op 0x11 with rs 0x08) while the same delay-slot classifier at src/interp/interp.h:149-182 has no op 0x11 case and returns 0. The DBT block end and the interpreter step do not share one delay-slot set, so BC1 is a control transfer in one copy and not in the other.
  - **Fix**: Use one delay-slot classifier so the DBT and the interpreter agree.

- [x] **M64-R13-6 — Low — YAGNI — Dbt_lookup has no caller**
  - **Where**: `mips64rt` `src/dbt/dbt.c:360-378` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: A search found no caller of dbt_lookup; dbt_run calls lookup_entry instead. The exported IBTC refresh lookup is dead code beside the lookup_entry path the run loop actually uses.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M64-R13-7 — Low — YAGNI — Sigalt_flags is never read**
  - **Where**: `mips64rt` `src/os/sigact.c:436-447` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: A search found no caller that reads sigalt_flags; these stores are never loaded. SS_AUTODISARM and the saved alt-stack flags never change delivery, which recomputes on-stack state from sigalt_sp and sigalt_size only.
  - **Fix**: Read the field on the path that is supposed to consume it, or delete the write.

- [x] **M64-R13-8 — Low — YAGNI — Mips_sc_unlink has no caller**
  - **Where**: `mips64rt` `src/os/syscalls.c:756-761` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: A search found no caller of mips_sc_unlink, so this legacy unlink wrapper is never dispatched. Guest sys_unlink (N64 5085 / N32 6085) never enters this handler and falls through to ENOSYS.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M64-R13-9 — Low — YAGNI — Mips_sc_symlinkat has no caller**
  - **Where**: `mips64rt` `src/os/syscalls.c:801-828` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: A search found no caller of mips_sc_symlinkat, so this symlinkat handler is never dispatched. Guest symlinkat (N64 5256 / N32 6260) never enters this handler and falls through to ENOSYS.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **M64-R13-10 — Low — CLEAN — X1 called guest base**
  - **Where**: `mips64rt` `src/dbt/trampoline_a64.S:46-71` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: The enter comment says x1 is the guest base, but mov x20, x1 is the pin the next comment names as the U0 soft-TLB base. The trampoline ABI comment names the wrong pointer, so x20 is not the guest window base.
  - **Fix**: Name x1 as the U0 soft-TLB base in the enter comment.

- [x] **M64-R13-11 — Low — CLEAN — Indexed COP1X comment is false**
  - **Where**: `mips64rt` `src/interp/fp_ps.c:13-62` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: The header says indexed COP1X memory ops fault, but PREFX returns 0 and an aligned LWXC1 writes the FPR word and returns 0. The fault rule stated for indexed COP1X ops is not what fp_cop1x_mem does on PREFX or an aligned LWXC1.
  - **Fix**: Change the comment so it matches this code, or change the code so it does what the comment says.

- [x] **M64-R13-12 — Medium — CLEAN — Span restore mprotect ignored**
  - **Where**: `mips64rt` `src/vm/vm_file_sync.c:535-544` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: The widen mprotect failure returns -errno, but the restore mprotect is cast to void and the function then returns 0. A PROT_NONE guest page widened for the copy can stay host-writable after a failed restore that is reported as success.
  - **Fix**: Return the restore mprotect error instead of 0.

### `sparc64rt` (`e33935f73e3a`)

- [x] **S64-R13-1 — High — SECURITY — Readlinkat returns a host /proc target**
  - **Where**: `sparc64rt` `src/os/guest_proc.c:651-677` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: readlinkat returns ENOENT only for a literal "/proc/self" prefix and otherwise copies host readlinkat bytes into the guest, so "/proc/./self/exe" or "proc/self/exe" on a dirfd for "/" returns the translator binary path. A guest readlink of a non-canonical /proc/self link receives the host translator path instead of ENOENT or the guest image path.
  - **Fix**: Return ENOENT or the guest image path for every /proc/self link, including non-canonical spellings.

- [x] **S64-R13-2 — High — SECURITY — Proc/self open falls through to the host**
  - **Where**: `sparc64rt` `src/os/syscalls_ext.c:201-219` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: After rejecting only the exact strings "/proc/self" and "/proc/self/", openat passes the unchanged guest path and dirfd to host openat, so a dirfd for "/" plus "proc/self/mem" or the path "/proc/./self/mem" opens the translator's proc tree. A guest open reaches the translator's own /proc entries, including maps, fd, and mem, which the literal prefix was written to keep closed.
  - **Fix**: Treat every /proc/self path, including non-canonical spellings, as a guest-synthesized open or ENOENT.

- [x] **S64-R13-3 — Medium — PERFORMANCE — Precise invalidate scans whole cache**
  - **Where**: `sparc64rt` `src/dbt/emit_rt.c:151-172` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: After dbt_page_bump on only the touched VPNs, sparc64_dbt_invalidate still walks every SPARC64_DBT_CACHE_SIZE block-cache slot and every SPARC64_IBTC_SIZE IBTC slot. A short or one-page invalidate costs a linear pass over the whole block-cache array and the whole IBTC array, not a pass over the touched pages.
  - **Fix**: Index this lookup so the dispatch path does not rescan the table for every item.

- [x] **S64-R13-4 — Low — PERFORMANCE — Instruction fetch is four byte reads**
  - **Where**: `sparc64rt` `src/interp/interp_mem.c:357-386` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: sparc64_fetch_word loads one aligned instruction with four separate 1-byte mem->read calls. Every interpreter step and every DBT fetch repeats the guest memory read four times for the same 4-byte instruction word.
  - **Fix**: Do this work once and reuse the result.

- [x] **S64-R13-5 — Low — DRY — Quad GRS packers disagree on sticky**
  - **Where**: `sparc64rt` `src/interp/fp_quad.c:232-240` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: The shift-113 sticky mask here is 0x7FFFFFFFFFFF, while the same binary128 denormal shift in src/interp/fp_qdiv.c:222-230 uses 0xFFFFFFFFFFFF. Quad add/sub and quad div/sqrt do not share one sticky residue for a 113-bit right shift: significand bit 111 is excluded here and included in the divide packer.
  - **Fix**: Use one sticky-mask helper so the two sites cannot drift.

- [x] **S64-R13-6 — Low — DRY — Quad NaN propagation copied**
  - **Where**: `sparc64rt` `src/interp/fp_quad.c:562-598` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: qq_nan2 copies the quad NaN rule at src/interp/fp_qdiv.c:313-349, where an SNaN sets NV 0x10 and wins, two QNaNs take the larger payload, and a signaling operand is quieted with bit 0x0000800000000000. faddq/fsubq and fdivq/fsqrtq each own this 37-line rule, so a NaN-propagation change has to be applied twice or the op families diverge.
  - **Fix**: Use one NaN-propagation helper so the two sites cannot drift.

- [x] **S64-R13-7 — Low — DRY — Guest ENOSYS is both 38 and 90**
  - **Where**: `sparc64rt` `src/os/threads_darwin.c:47-56` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: This block fixes guest-visible ENOSYS at 38 and says the value passes through unchanged, while src/os/syscalls_min.c:113-155 maps the ENOSYS macro to 90 and returns every other code raw. An unsupported futex result of -38 becomes guest errno 90 only when host ENOSYS is 38, and stays guest errno 38 on Darwin where ENOSYS is 78.
  - **Fix**: Return one errno for this ENOSYS case in both copies.

- [x] **S64-R13-8 — Low — YAGNI — Unused atomic edge**
  - **Where**: `sparc64rt` `src/dbt/emit_mem.c:298-312` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: A search of the repository found no caller of sparc64_mem_emit_atomic_edge, which these lines define. Dead DBT emitter: sparc64_mem_emit_site calls sparc64_mem_emit_fast, so this always-taken cbz edge is never appended to a block.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S64-R13-9 — Low — YAGNI — Unused fetch_decode**
  - **Where**: `sparc64rt` `src/interp/decode.c:637-676` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: A search of the repository found no caller of sparc64_fetch_decode, which these lines define. Dead interpreter entry: sparc64_step decodes through sparc64_fetch_word and sparc64_classify_word, so this helper never fetches a guest instruction.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S64-R13-10 — Low — YAGNI — Unused proc open**
  - **Where**: `sparc64rt` `src/os/guest_proc.c:571-616` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: A search of the repository found no caller of sparc64_guest_proc_open, which these lines define. Dead syscall helper: open and openat call sparc64_guest_proc_openat, so this second flag translator never serves a synthetic /proc path.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S64-R13-11 — Low — YAGNI — Unused tlb publish**
  - **Where**: `sparc64rt` `src/vm/vm64.c:377-399` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: A search of the repository found no caller of vm64_tlb_publish_pair, which these lines define. Dead Soft-TLB writer: nothing publishes an 8 KiB page through this helper; live fills use sparc64_tlb_fill.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **S64-R13-12 — Low — CLEAN — LDR/STR comment swaps V and 111**
  - **Where**: `sparc64rt` `src/dbt/emit_mem.c:104-122` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: The comment says the register-offset LDR/STR word is size:V:111:00:opc:1, but (7<<27) places 111 in bits 29:27 immediately after size in bits 31:30, which is size:111:V:00:opc:1. A reader using the comment's field order will mis-decode every register-offset load and store this encoder emits.
  - **Fix**: Correct the field order to size:111:V:00:opc:1, which is what (7<<27) encodes.

- [x] **S64-R13-13 — Low — CLEAN — Tcc comment omits 0x6e and 0x6f**
  - **Where**: `sparc64rt` `src/interp/interp.c:342-371` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: The opening comment says a true trap other than 0x6d is ILLEGAL, but the test returns SPARC64_STEP_SYSCALL when (trapno-0x6d) is 0, 1, or 2. A reader following the opening comment will treat ta 0x6e and ta 0x6f as illegal instructions, but the code reports them as syscalls.
  - **Fix**: State that traps 0x6d, 0x6e, and 0x6f are syscall gates, matching the test below the comment.

- [x] **S64-R13-14 — Medium — CLEAN — Wake-pipe fcntl failures return success**
  - **Where**: `sparc64rt` `src/os/backend_darwin_sync.c:159-169` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: pipe failure is returned, but the four fcntl calls that set FD_CLOEXEC and O_NONBLOCK are ignored and the function still returns 0. A failed flag update leaves the wake pipe blocking or inheritable while worker-sync init reports success.
  - **Fix**: Return the fcntl error and do not report worker-sync init as success.

### `rt-series` (`7144388926db`)

- [x] **RTS-R13-1 — Medium — SECURITY — Bench cleanup ignores docker failure and has no timeout**
  - **Where**: `rt-series` `tools/bench_harness.sh:108-127` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: docker ps, docker inspect, and docker rm have no timeout, and || true turns a failed docker ps into an empty list so the function returns 0. A benchmark run can exit 0 while a leftover rt-bench container is still present or while docker ps never returns.
  - **Fix**: Give docker ps, inspect, and rm a timeout, and return failure when the listing command fails.

- [x] **RTS-R13-2 — Medium — SECURITY — Failed docker ps passes the leftover check**
  - **Where**: `rt-series` `tools/run_catalogue.sh:256-282` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: docker ps is not under a timeout, its failure is swallowed by || true, and an empty id list or empty comm result makes check_no_leftover_docker return 0. A catalogue smoke or qualify gate treats a failed or hung docker listing as proof that no container leaked.
  - **Fix**: Give docker ps a timeout, and fail the leftover check when the listing command fails.

- [x] **RTS-R13-3 — Medium — SECURITY — Openssl dgst accepts any 64-character token**
  - **Where**: `rt-series` `tools/run_catalogue.sh:462-470` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: note_pass runs when the text after '=' is any 64 characters, with no comparison to a fixed SHA-256 digest. A wrong SHA-256 of the fixed plaintext is recorded as PASS for the openssl dgst check.
  - **Fix**: Compare the openssl dgst token to the expected SHA-256 of the fixed plaintext.

- [x] **RTS-R13-4 — Low — PERFORMANCE — Testfloat runner executed twice**
  - **Where**: `rt-series` `tools/run_grind.sh:621-630` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: The dual-engine block runs TESTFLOAT_RUNNER again on the same vectors under each engine after tools/run_grind.sh:494-524 already ran that runner and deleted its result file. Each foreign dual-engine TestFloat op executes the guest runner twice per engine on unchanged vectors.
  - **Fix**: Do this work once and reuse the result.

- [x] **RTS-R13-5 — Low — DRY — Identical translator flag arms**
  - **Where**: `rt-series` `tools/remote_bench_common.sh:39-88` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: rt_format_cmd_prefix's a32rt|rvrt|mips32rt|ppc32rt arm and its default arm both print the same --%s prefix, and rt_run_bounded_translator's matching arm and default arm repeat that same env block and --$_rrt_eng invocation. An engine-flag or env edit applied to only one arm makes listed repos and every other repo launch the translator differently.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **RTS-R13-6 — Medium — DRY — Sparc32 compiler triplet drifted**
  - **Where**: `rt-series` `tools/run_grind.sh:240-251` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: resolve_arch_defaults selects sparc-linux-gnu-gcc for sparc32rt, while tools/build_uniform_guests.sh:259-272 builds that ABI with sparc64-linux-gnu-gcc -m32. grind compiles sparc32rt guests with a different gcc triplet than the uniform and bench builders, or skips when that triplet is absent.
  - **Fix**: Use the same sparc32 compiler triplet as build_uniform_guests.sh.

- [x] **RTS-R13-7 — Low — DRY — Libc-test dual gate drops stdout**
  - **Where**: `rt-series` `tools/run_grind.sh:780-786` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: The LIBC_TEST_DIR dual-engine gate deletes both captures and passes on matching exits, while tools/run_grind.sh:277-314 fails that same case unless cmp -s of the two outputs succeeds. interp and dbt can print different libc-test results and still be recorded as PASS.
  - **Fix**: Compare the captured stdout and fail the gate when the runner drops it.

- [x] **RTS-R13-8 — Low — DRY — Copied LTP dual-engine body**
  - **Where**: `rt-series` `tools/run_grind.sh:801-803` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: The LTP_MANIFEST while-read loop and the LTP_DIR glob for-loop copy the same dual-engine grind_run_guest exit comparison and the same single-wrapper fallback. A change to how interp and dbt exits are compared has to be edited in both loops or the manifest path and the directory path accept different results.
  - **Fix**: Keep one copy in this repository and make the other site call it.

- [x] **RTS-R13-9 — Low — DRY — Bw_mmap dual gate ignores empty output**
  - **Where**: `rt-series` `tools/run_grind.sh:894-911` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: bw_mmap's dual-engine gate passes on matching zero exits with no output check, while tools/run_grind.sh:869-876 rejects that same exit match when the captured log is empty. A bw_mmap run that exits 0 and prints nothing is recorded as PASS.
  - **Fix**: Fail the gate when the mmap benchmark produces no output.

- [x] **RTS-R13-10 — Low — YAGNI — Unused LoongArch CPUCFG2 constants**
  - **Where**: `rt-series` `tests/check_abi_invariants.c:287-303` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: LA_CPUCFG2_FP, LA_CPUCFG2_FP_SP, LA_CPUCFG2_FP_DP, LA_CPUCFG2_FP_VER_1, LA_CPUCFG2_LSX, LA_CPUCFG2_LASX, LA_CPUCFG2_LLFTP, LA_CPUCFG2_LLFTP_VER_1, LA_CPUCFG2_LAM_BH, and LA_CPUCFG2_LAMCAS are defined here and a search found no caller; only LA_CPUCFG2_LAM is read, by the _Static_assert on line 303. A wrong value for those ten CPUCFG2 bits still compiles, because no assert or other reader uses them.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RTS-R13-11 — Low — YAGNI — Parity_now_ms has no caller**
  - **Where**: `rt-series` `tools/parity_contract.sh:42-48` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: parity_now_ms is defined here and a repository search found no caller. The parity contract advertises a shared millisecond clock that no script, Makefile, or lane entry invokes, so elapsed_ms is never produced by this helper.
  - **Fix**: Remove the unused symbol, or call it from the production path that owns this behavior.

- [x] **RTS-R13-12 — Low — CLEAN — NaN conversion comment is not implemented**
  - **Where**: `rt-series` `tests/tcg/smoke_tcg.c:493-497` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: The comment says NaN and infinity must not trap the conversion path, but the code only creates those values and discards them without a conversion. float_convs does not check the NaN or infinity conversion behavior its comment states.
  - **Fix**: Convert the NaN and infinity values on the path the comment describes, and check that they do not trap.

## Round 14 — Multi-review loop 1/16, integer ALU and flag consumers, resolved (2026-11-11; remediated 2026-11-13)

Same pinned revisions as Round 13. Each item below was opened in the current tree and confirmed by two independent read-only checks. Nothing here repeats an open Round 13 cause. No product code was changed.

### `i686rt` (`92fc0afb23d6`)

- [x] **I686-R14-1 — High — BUG — Register SETP/SETNP drops the parity descriptor**
  - **Where**: `i686rt` `src/dbt/translate.c:240-244` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: `tr_classify` treats register `SETcc` as an NZCV reader when `(insn->imm & 0xEU) != 10U`. Decode parks the `SETcc` condition in `modrm_reg` (`src/x86/decode.c:748-749`) and leaves `imm` at 0, so `SETP`/`SETNP` (conditions 10 and 11) still return `TRC_NZCV_READER`. A later register flag writer then sets `skip_lazy = 3` on the producer (`translate.c:450-452`). `emit_lazy` returns without storing the descriptor when `skip_lazy` is 3 (`src/dbt/emit_alu.c:244-245`). The emitter then declines parity `SETcc` (`src/dbt/emit_branch.c:92-93` and `:620-624`) and the interpreter runs it against the stale descriptor. `i686_flags_cc` case `0xa` reads `I686_EF_PF`.
  - **Fix**: Classify `SETcc` from `modrm_reg`, the same field `CMOVcc` keeps in `imm`. Do not mark conditions 10 and 11 as `TRC_NZCV_READER`.
  - **Test**: Enter with PF=1, then `cmp eax, 1` / `setp bl` / `add ecx, edx`. The interpreter leaves BL=0. The DBT leaves BL=1.

- [x] **I686-R14-2 — Medium — BUG — Immediate ROL/ROR with count other than 1 clears OF**
  - **Where**: `i686rt` `src/dbt/emit_alu_ext.c:466-508` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: The eager rotate path does `a64_emit_movz_w(b, XALU_T1, 0x0801U, 0U)` and `BIC`s that mask, clearing both CF and OF. OF is written back only when the count register compares equal to 1, or when the immediate count is 1. `h_rol` and `h_ror` call `sh_set_of` only inside `if (cnt == 1U)` and otherwise leave OF (`src/interp/h_shift.c:242-246` and `:266-270`). An immediate rotate by 2 clears OF in the DBT and preserves it in the interpreter.
  - **Fix**: `BIC` only CF. Write OF only when the masked count is 1, and keep the previous OF otherwise.
  - **Test**: `add eax, 1` on `0x7fffffff` sets OF. Then `mov eax, 0x81` / `rol al, 2`. A following `jo` is taken in the interpreter and not taken in the DBT.

- [x] **I686-R14-3 — Low — CLEAN — Shift comment says AF is left as-is**
  - **Where**: `i686rt` `src/interp/h_shift.c:20-24` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: The comment says `AF is architecturally undefined and is left as-is in ctx->eflags`. `SHL`/`SHR`/`SAR` call `i686_flags_logiczx`, which executes `ctx->eflags &= ~(I686_EF_ARITH_MASK | I686_EF_AF)` (`src/interp/flags.c:293`).
  - **Fix**: Say AF is cleared, matching `i686_flags_logiczx`.

### `rt-series` (`7144388926db`)

- [x] **RTS-R14-1 — Medium — CLEAN — Sort checksum ignores order**
  - **Where**: `rt-series` `tests/bench_suite.c:224-229` and `:258-259` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: After the bubble-sort swaps, `l_sum += p->val` adds the node values and that sum is the only list input to `crc16_update`. The smoke CRC `0xedd5` and the full CRC `0x41dd` (`bench_suite.c:176`) stay the same if the `curr->val > curr->next->val` branch never swaps.
  - **Fix**: Fold an index-weighted value, or the sorted sequence, into the CRC.
  - **Test**: Invert the compare. Both CRCs still match.

- [x] **RTS-R14-2 — Medium — CLEAN — Overflow product is discarded**
  - **Where**: `rt-series` `tools/run_grind.sh:674-679` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: `__mulosi4(1000000, 1000000, &ov)` is checked with `if (ov != 1) fails++` and then `(void)prod`. The comment on line 676 says the helper returns the wrapped product. A product of 0 with `ov == 1` still prints `BUILTINS_OK`. The non-overflow call on the next lines does check `prod != 20000`.
  - **Fix**: Fail unless `prod` equals the low 32 bits of `1000000 * 1000000` as well as `ov == 1`.

- [x] **RTS-R14-3 — Medium — CLEAN — Soak oracle falls back to the interpreter**
  - **Where**: `rt-series` `tools/run_grind.sh:923-933` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: `run_differential_binary` sets `_rdb_ref_wrap="${GRIND_QEMU:-${GRIND_INTERP:-}}"`. Csmith and Yarpgen use that helper. With `GRIND_QEMU` empty and `GRIND_INTERP` distinct from `GRIND_DBT`, a matching wrong result is `grind_pass`ed as reference-vs-DBT differential OK. The gcc-torture gate in the same file (`run_grind.sh:411-412`) skips unless `GRIND_QEMU` is set or `GRIND_ALLOW_NO_ORACLE=1`, and it calls the interpreter-only case a GAP.
  - **Fix**: Require `GRIND_QEMU` here, or skip unless `GRIND_ALLOW_NO_ORACLE=1`, and compare both engines to that oracle.

### `ppc32rt` (`621e36892ffb`)

- [x] **P32-R14-1 — High — BUG — addco and subfco overflow uses the carry temps**
  - **Where**: `ppc32rt` `src/dbt/emit_int.c:252-255` and `src/dbt/emit_int.h:242-249` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: `PPC32_OP_ADDC` and `PPC32_OP_SUBFC` call `ei_xer_ca_from_c` before the OE block. That helper does `ei_cset(b, EI_A, A64_COND_CS)` and `a64_emit_mov_imm32(b, EI_B, EI_XER_CA)`, replacing the original operands. `addco.` then calls `ei_add_ov(b, EI_A, EI_B, EI_R)` and `subfco.` calls `ei_sub_ov(b, EI_A, EI_B, EI_R)`. Overflow is computed from the carry bit and the CA mask. With Rc=1, `ei_finish` also writes that wrong SO into CR0.
  - **Fix**: Compute signed overflow from the original RA, RB, and result before `ei_xer_ca_from_c` clobbers `EI_A` and `EI_B`.
  - **Test**: `li r3,-1; li r4,-1; addco. r5,r3,r4` must leave OV clear (result `0xFFFFFFFE`, CA=1). `lis r4,0x8000; li r3,1; subfco. r5,r3,r4` must set OV. The DBT does the opposite.

### `sparc32rt` (`f343b8b2a375`)

- [x] **S32-R14-1 — High — BUG — Conditional Ticc sense is inverted**
  - **Where**: `sparc32rt` `src/dbt/emit_int.c:376-429` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: For `cond` other than `TN` (0) and `TA` (8), `sparc32_emit_trap` emits `a64_emit_b_cond_placeholder(b, sparc32_emit_icc_cond(d->cond))` and later `a64_patch_b_cond(b, p_taken, b->count)` onto `a64_emit_exit_branch(b, npc)`. `a64_emit_b_cond_placeholder` emits `0x54000000 | cond`, which branches when the condition is true. The trap body is the fall-through. A true Ticc skips the trap. `TA` has no branch and still traps.
  - **Fix**: Branch on the inverted condition, or put the trap body on the taken edge.
  - **Test**: `orcc %g0, %g0, %g0; te 1` traps in the interpreter (Z=1) and falls through in the DBT.

- [x] **S32-R14-2 — High — BUG — Taken Bicc drops its target when the delay is a trap**
  - **Where**: `sparc32rt` `src/dbt/emit_cti.c:100-105` and `:201-203` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: `sparc32_emit_branch` sets `ec->fault_pc = npc` and then `e_emit_delay` single-steps a `CALL`, `BRANCH`, `JMPL`, or `TRAP` delay with `sparc32_emit_exit_singlestep(ec, ec->fault_pc)`. The replay runs the delay alone, with `npc = delay+4`, and the branch target is lost. `sparc32_emit_call` and `sparc32_emit_jmpl` single-step at the CTI `pc` (`emit_cti.c:362` and `:405`). The comment at lines 81-83 says the whole CTI is replayed.
  - **Fix**: For those delay classes, single-step at the branch PC so the interpreter runs the pair.
  - **Test**: `ba 1f; tn; nop; 1: nop` reaches `1f` in the interpreter and the `nop` after `tn` in the DBT.

### `sparc64rt` (`e33935f73e3a`)

- [x] **S64-R14-1 — High — BUG — Taken conditional Tcc jumps past the trap**
  - **Where**: `sparc64rt` `src/dbt/emit_cond.c:460-491` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: For `cond != 8`, the emitter places `sb_b_cond_placeholder(b, e_a64_cond[d->cond & 15U])` and then `e_exit_imm(b, ec->pc + 4U, SPARC64_EXIT_BRANCH)` as the fall-through. `sb_patch_b_cond(b, p_taken, e_a64_cond[d->cond & 15U], b->count)` aims that true branch after the trap body. A true Tcc skips the trap. `exec_tcc` traps when the condition is true. Unconditional `ta` (`cond == 8`) still falls into the body.
  - **Fix**: Patch `p_taken` to the first instruction of the trap-number sequence, and keep the `pc+4` exit on the false edge.
  - **Test**: `subcc %g0, %g0, %g0; te 0x6d`. The interpreter stops in `SYSCALL` on the `te`. The DBT takes `B.EQ` off the end of the sequence and never exits `SYSCALL`.

- [x] **S64-R14-2 — High — BUG — WR %ccr leaves stale live NZCV**
  - **Where**: `sparc64rt` `src/dbt/emit_int.c:430-436` and `:34-40` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: The `%ccr` write stores the new CCR with `sb_ldst_imm(b, false, true, ES0, ECTX, SPARC64_CTX_CCR_OFFSET)` and does not set `nzcv_state = SPARC64_NZCV_NONE`. `e_cc_transparent` returns true for every `SPARC64_ICLS_WRASR`. A later `Bicc`/`BPcc`/`MOVcc` in the block keeps the host NZCV from the previous `*cc` op.
  - **Fix**: Set `nzcv_state = SPARC64_NZCV_NONE` on the `%ccr` write.
  - **Test**: `subcc %g0, %g0, %g0; wr %g0, 0, %ccr; be,a tgt` with delay `add %g0, 1, %g1`. The interpreter sees Z clear, skips the annulled delay, and falls through. The DBT takes the branch on the stale Z.

### `mips32rt` (`3fb98db8f8ca`)

- [x] **M32-R14-1 — High — BUG — Signed overflow is delivered as SIGSEGV**
  - **Where**: `mips32rt` `src/dbt/emit_int.c:454-456` and `src/dbt/dbt.c:882-887` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: `MIPS_FUNCT_ADD` and `MIPS_FUNCT_SUB` call `emit_cond_fault(b, A64_COND_VS, cur, fpc, ind_slot)` before `put_rd`, leaving `MIPS32_EXIT_FAULT`. The dispatcher then does `int signo = (ctx->fixade_enabled != 0U || (info & 3U) == 0U) ? 11 : 10` and `mips_trap`. An aligned overflow address is signal 11. The interpreter returns `fault_code_at(ctx, cur_pc, 8, 2)` (`SIGFPE` / `FPE_INTOVF`) before writing the destination.
  - **Fix**: Deliver integer overflow through the trap path the interpreter uses (`SIGFPE`, code 2), and do not write the destination.
  - **Test**: `lui $t0, 0x7fff; ori $t0, $t0, 0xffff; addiu $t1, $zero, 1; add $t2, $t0, $t1` with a SIGFPE handler. The interpreter raises SIGFPE and leaves `$t2` unchanged. The DBT raises SIGSEGV.

- [x] **M32-R14-2 — High — BUG — Unaligned JR/JALR target is SIGSEGV**
  - **Where**: `mips32rt` `src/dbt/dbt.c:669-673` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: A block whose first fetch fails, with `exit_reason == MIPS32_EXIT_NONE`, calls `mips_fault(ctx, cur)`. With default `fixade_enabled = 1` that is signal 11. `fetch_decode` calls `mips_fault_align` for an unaligned PC, which is `SIGBUS` / `BUS_ADRALN`. An inlined `JR`/`JALR` to an odd address takes the compile path.
  - **Fix**: If `(cur & 3) != 0`, call `mips_fault_align(ctx, cur)`.
  - **Test**: `addiu $t0, $zero, 1; jr $t0; nop` under default FIXADE. The interpreter raises SIGBUS `si_code=1`. The DBT raises SIGSEGV.

### `mips64rt` (`92e86b9ed717`)

- [x] **M64-R14-1 — High — BUG — Integer traps exit as SIGSEGV**
  - **Where**: `mips64rt` `src/dbt/mem_recover.c:434-437` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: `BREAK`, trap compares, and signed overflow leave through `MIPS64_EXIT_FAULT`. `dbt_mem_recover` calls `mips_fault(ctx, slot_pc)` when `dbt_mem_span` says the word is not a memory operation. `mips_fault` delivers signal 11. The interpreter uses `trap_at_code` with signal 8 for overflow, 5 for `BREAK`/`TGE`, or 4 for `SIGILL`.
  - **Fix**: On a non-memory `EXIT_FAULT`, run that word through the interpreter trap path.
  - **Test**: `break 7` (`0x0007000D`). The interpreter delivers signal 5. The DBT delivers signal 11.

- [x] **M64-R14-2 — High — BUG — BLTZAL $ra re-reads the link**
  - **Where**: `mips64rt` `src/dbt/mem_recover.c:244-251` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: `BLTZAL`/`BGEZAL`/`BLTZALL`/`BGEZALL` store `pc+8` into `$ra` before the delay slot. A soft-TLB miss in that slot re-evaluates the branch with `rs_v = ctx->gpr[b.rs]`. When `rs` is `$ra`, the test sees the new non-negative link. The interpreter tests `rs` before the link write.
  - **Fix**: Snapshot `rs` before the link write and have the resolver use that snapshot when the link register is `rs`.
  - **Test**: `$ra = -1`, then `bltzal $ra, 1f` with a delay load that misses the soft-TLB. The interpreter lands at `1f`. The DBT falls through to `pc+8`.

### `loongarch64rt` (`eec0f3d517bd`)

- [x] **LA64-R14-1 — High — BUG — Misaligned JIRL target is executed**
  - **Where**: `loongarch64rt` `src/dbt/dbt.c:378-379` and `src/interp/interp.c:61-65` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: `translate_block` fetches with `la64_mem_ptr(pc, 4, LA64_MEM_EXEC)` and assembles `fp[0]` through `fp[3]` with no `pc & 3` test. `interp_step` raises `SIGBUS` / `BUS_ADRALN` when `(pc & 3) != 0`. `JIRL` stores the raw `rj + imm` target, so an odd executable address runs the shifted word in the DBT.
  - **Fix**: If `pc & 3`, end the block with `LA64_DBT_EXIT_SINGLE_STEP` and let `interp_step` raise the bus fault.
  - **Test**: From aligned `B`, `pcaddi $r5, 3; addi.d $r5, $r5, 1; jirl $r4, $r5, 0` with `addi.d $r12, $r0, 1` at `B+13`. The interpreter bus-faults at `B+13` and leaves `$r12` unchanged. The DBT sets `$r12 = 1`.

### `a32rt` (`4b94c1527bea`)

- [x] **A32-R14-1 — High — BUG — Thumb CBZ/CBNZ with a short offset adjusts SP**
  - **Where**: `a32rt` `src/interp/interp_thumb.c:585-592` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: The interpreter treats `(hw & 0xF600U) == 0xB000U` as `ADD`/`SUB` SP by `(hw & 0x7FU) << 2`. Thumb `CBZ`/`CBNZ` with offset bit `i` clear matches that mask (`0xB100`–`0xB1FF` and `0xB900`–`0xB9FF`). No earlier test in the 16-bit step matches `0xB110`. The DBT recognizes `(insn & 0xF500U) == 0xB100U` as `CBZ`/`CBNZ` and branches (`src/interp/interp_t16.c:362-370`).
  - **Fix**: Match `CBZ`/`CBNZ` with `(hw & 0xF500U) == 0xB100U` before the SP immediate, and keep `(hw & 0xFF00U) == 0xB000U` for `ADD`/`SUB` SP.
  - **Test**: Thumb `movs r0, #0` at 0 and `.inst 0xb110` at address 2, then three `movs`. The interpreter adds `0x40` to SP and executes the three `movs`. The DBT branches to `0xA` and skips them.

### `ppc64rt` (`3c236f2584e9`)

- [x] **P64-R14-1 — Medium — BUG — cmp and cmpl with Rc=1 are executed**
  - **Where**: `ppc64rt` `src/dbt/emit_int.c:603-629` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: `e_cmp` accepts `PPC64_OP_CMP` and `PPC64_OP_CMPL` and calls `e_cmp_cr` with no `d->rc` test. `ppc64_emit_int_one` reaches it at line 727. The interpreter rejects that form: `if (xo10 == 0u || xo10 == 32u) { if (rc) return interp_ill_at(pc, 4); }` (`src/interp/interp.c:515-517`).
  - **Fix**: Return false from `e_cmp` when `d->rc` is set so the word takes the illegal-instruction path.
  - **Test**: Word `0x7C032001`. The interpreter traps. The DBT writes CR.

- [x] **P64-R14-2 — Medium — BUG — mtcrf with Rc=1 updates CR**
  - **Where**: `ppc64rt` `src/dbt/emit_int.c:653-665` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: `e_cr_move` returns false when `PPC64_OP_MFCR` has Rc set, then handles `PPC64_OP_MTCRF` with no Rc test and stores CR. The interpreter rejects XO 144 when `rc` or bit 11 is set (`src/interp/vec.c:274-279`).
  - **Fix**: Return false from the `MTCRF` arm when `d->rc` is set, or when bit 11 is set.
  - **Test**: Word `0x7C680121`. The interpreter traps. The DBT updates CR.

## Round 15 — Multi-review loop 2/16, FP narrowing and FP oracles, resolved (2026-11-11; remediated 2026-11-13)

Same pinned revisions as Round 13. Each item below was opened in the current tree and confirmed by two independent read-only checks. Nothing here repeats an open Round 13 cause. No product code was changed.

### `i686rt` (`92fc0afb23d6`)

- [x] **I686-R15-1 — Medium — BUG — CVTSD2SS and CVTPD2PS keep the source NaN**
  - **Where**: `i686rt` `src/dbt/emit_sse2.c:323` and `:344` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: `sse_emit_cvt_5a` narrows with `sse_fcvtn_2s` (`0x0E616800`, `emit_sse_shared.h:573`) for `CVTPD2PS` and `sse_fcvt_s_d` (`0x1E624000`, `emit_sse_shared.h:563`) for `CVTSD2SS`. `i686_emit_sse2` calls that helper for `I686_OP_CVTPS2PD` with no NaN exit (`emit_sse2.c:767-768`). Host `FCVT`/`FCVTN` keep the source sign and a truncated payload, so the canonical double quiet NaN `0x7FF8000000000000` becomes `0x7FC00000`. The interpreter's `sse_round_f64_to_f32` returns `F32_QNAN_INDEF` for every NaN (`src/interp/h_sse.c:75-76`). That macro is `0xFFC00000u` (`src/interp/h_sse_internal.h:30`). `CVTSD2SS` (`pfx_rep == 2`) and `CVTPD2PS` (`pfx_66`) both call it (`h_sse.c:798-806`).
  - **Fix**: Write `0xFFC00000` for a NaN source lane, with the same MXCSR side effects as `sse_round_f64_to_f32`, or decline the instruction to the interpreter.
  - **Test**: `cvtsd2ss` of `0x7FF8000000000000`. The interpreter stores `0xFFC00000`. The DBT stores `0x7FC00000`.

### `rvrt` (`ca1ef7bc3a4d`)

- [x] **RV-R15-1 — Medium — BUG — fcvt.s.d raises underflow on a tininess-after result**
  - **Where**: `rvrt` `src/dbt_emit_fp.c:730` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: Static-RNE `fcvt.s.d` emits `0x1e624000` (`FCVT Sd, Dn`) and accumulates host FPSR. `emit_fmul_s` is the only fast path that strips a spurious UFC (`dbt_emit_fp.c:340-349`). The interpreter sets `softfloat_detectTininess` to after-rounding (`src/fp/semantic.c:96`) and converts with `f64_to_f32`. For `0x380fffffffffffff` under RNE, that pack is not tiny: the result is `0x00800000` with inexact only. Host `FCVT` detects tininess before rounding, so the same input also sets UFC.
  - **Fix**: Drop this conversion's UFC when the exact value rounds to the minimum normal and is not tiny after rounding, or decline the fast path.
  - **Test**: `fcvt.s.d` of `0x380fffffffffffff` with `rm=RNE` and a clear `fcsr`. The result is `0x00800000` on both sides. The interpreter sets inexact only. The DBT also sets underflow.

### `rt-series` (`7144388926db`)

- [x] **RTS-R15-1 — High — CLEAN — TestFloat accepts a quiet-NaN payload mismatch**
  - **Where**: `rt-series` `tools/run_grind.sh:519` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: The verifier is invoked as `"$_ver" "-r${_rm}" "$_op"` with neither `-checkNaNs` nor `-checkAll`. Berkeley `testfloat_ver` reports `no errors found` for a quiet NaN whose payload differs when the exception flags match. Line 529 then records `cases verified clean`. A translated quiet-NaN payload can pass this gate.
  - **Fix**: Pass `-checkNaNs`, or `-checkAll` when the vectors include signaling NaNs, and fail the gate on that verifier's NaN-payload errors.

- [x] **RTS-R15-2 — Medium — CLEAN — float_convs accumulation window is a tenth either way**
  - **Where**: `rt-series` `tests/tcg/smoke_tcg.c:500-508` @ `7144388926db4ad6ab23ce1d8fbfcdd95d630e42`.
  - **What breaks / Why**: One thousand `d += (double)f` additions of `float f = 0.1f` fail only when `!(d > 99.9 && d < 100.1)`. A sum such as `99.91` passes. The exact accumulation of that loop is about `100.00000149011612`.
  - **Fix**: Compare `d` with the exact accumulated value, or with a bound of a few ulps around it.

### `sparc32rt` (`f343b8b2a375`)

- [x] **S32-R15-1 — High — BUG — FsTOi and FdTOi turn a NaN into 0**
  - **Where**: `sparc32rt` `src/dbt/emit_fp.c:635` and `:642` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: `FsTOi` emits `a64_emit_fcvtzs_s_to_w` and `FdTOi` emits `a64_emit_fcvtzs_d_to_w`, then stores that word. Host `FCVTZS` writes 0 for a NaN. `fp_to_i32` does `if (isnan(v)) { fp_raise(ctx, FP_FSR_NVC_BIT); return 0x7FFFFFFFU; }` (`src/interp/fp_arith.c:254-255`), and both converts return that value.
  - **Fix**: On a NaN source, store `0x7FFFFFFF` and raise `NVC`, or decline the convert to the interpreter.
  - **Test**: `%f0 = 0x7fc00000`, then `fstoi %f0, %f1`. The interpreter writes `0x7FFFFFFF` and sets `NVC`. The DBT writes 0.

- [x] **S32-R15-2 — Medium — BUG — Quiet-NaN add keeps the first payload**
  - **Where**: `sparc32rt` `src/dbt/emit_fp.c:312` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: `fp_canon` branches on `A64_COND_VS` after comparing each input with itself, so a NaN input skips the canonical `0x7FFFFFFF` and the host `FADD` result stays. That `FADD` uses `Vn` as `rs1`, and the host keeps the first NaN. `fp_f32_pick_nan` returns the larger fraction, with `rs1` winning a tie (`src/interp/fp_arith.c:160-163`), and `fp_f32_nan2` returns that value for a quiet NaN (`fp_arith.c:378-379`).
  - **Fix**: When both inputs are quiet NaNs, select the larger fraction the way `fp_f32_pick_nan` does, or decline the op to the interpreter.
  - **Test**: `fadds` of `0x7fc00001` and `0x7fc00002`. The interpreter returns `0x7fc00002`. The DBT returns `0x7fc00001`.

### `sparc64rt` (`e33935f73e3a`)

- [x] **S64-R15-1 — High — BUG — A batched FPSR flush leaves cexc set after an exact op**
  - **Where**: `sparc64rt` `src/dbt/emit_fp.c:100-102` and `:173` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: `fp_guard_rd0` clears host FPSR only when `fpsr_dirty` is false, then sets `fpsr_dirty`. A later arithmetic op in the block does not clear FPSR, so the flags OR together. `fp_sync_fsr` clears `cexc` and then `sb_orr_reg`s that accumulated mask back in. `fp_commit` overwrites `cexc` with the current op and only ORs `aexc` (`src/interp/fp.c:174-175`). With `TEM` clear, an inexact op followed by an exact op leaves `cexc` set under the DBT.
  - **Fix**: Clear host FPSR at each FPop, or flush `cexc` from that op alone before the next one.
  - **Test**: `TEM=0`, an inexact `fdivs`, then `fadds` of 1.0 and 1.0, then `stfsr`. The interpreter shows `cexc=0` and `aexc.NX=1`. The DBT leaves `cexc` set.

- [x] **S64-R15-2 — High — BUG — FCMP publishes fcc before the TEM.NV check**
  - **Where**: `sparc64rt` `src/dbt/emit_fpcmp.c:44-52` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: `fp_fcc_nv_commit` stores `fcc[idx]` at context offset `0x240` before the `TEM` test and `e_fault_here`. The trap exit does not roll that store back. Later `FBfcc` reloads that shadow. The interpreter calls `fp_fcc_write` only after `fp_commit` returns continue (`src/interp/fp.c:287-291`).
  - **Fix**: Store the fcc shadow on the no-trap path, after the `TEM` check.
  - **Test**: `fcc0=0`, `TEM.NV=1`, `fbe dest` with delay `fcmpes %fcc0` of a quiet NaN. The interpreter traps and leaves `fcc0` at 0. The DBT publishes 3 before the trap, and a resumed `FBfcc` follows 3.

### `ppc32rt` (`621e36892ffb`)

- [x] **P32-R15-1 — High — BUG — fmsub and fnmsub use the swapped ARM op**
  - **Where**: `ppc32rt` `src/dbt/emit_fp.c:289-290` and `:377` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: `fp_a_op[28]` selects `SP_MSUB` (`0x1F008000` / `0x1F408000`, ARM `FMSUB`) and `fp_a_op[30]` selects `SP_NMSUB` (`0x1F208000` / `0x1F608000`, ARM `FNMSUB`). `fp_calc(b, op, prec, 2U, 1U)` encodes `Rn=frA`, `Rm=frC`, `Ra=frB`, so ARM `FMSUB` is `frB - frA*frC`. The interpreter's kind 1 is `fma(frA, frC, -frB)` (`src/interp/fp.c:394`), which is `frA*frC - frB`. `fmadd` and `fnmadd` match.
  - **Fix**: Give PPC `fmsub` the ARM `FNMSUB` encoding and PPC `fnmsub` the ARM `FMSUB` encoding, with this operand placement.
  - **Test**: `fmsub` of `3*4-5` is `+7` in the interpreter and `-7` in the DBT. `fnmsub` of the same inputs is the other way around.

- [x] **P32-R15-2 — Medium — BUG — Infinity FPRF drops the FU bit**
  - **Where**: `ppc32rt` `src/dbt/emit_fp_class.c:53-55` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: `fp_fprf` compares the result with `+0` (`0x1E602008` / `0x1E202008`) and builds `[LT,GT,EQ,UN]` from NZCV. `+inf` is GT (`0x04`) and `-inf` is LT (`0x08`). The extra class bit is OR'd only for a quiet NaN, a denormal, or `-0`. `fp_fprf64` and `fp_fprf32` return `0x05` for `+inf` and `0x09` for `-inf` (`src/interp/fp.h:182` and `:275`).
  - **Fix**: Set the FU bit for an infinity as well as the GT or LT bit.
  - **Test**: `fdiv` of `1.0/0.0` and of `-1.0/0.0`, then `mffs`. The interpreter FPRF is `0x05` and `0x09`. The DBT FPRF is `0x04` and `0x08`.

## Round 16 — Multi-review loop 10/16 and 11/16, uncalled definitions and false comments, resolved (2026-11-11; remediated 2026-11-13)

Same pinned revisions as Round 13. Each item below was opened in the current tree and confirmed by two independent read-only checks. Nothing here repeats an open Round 13 cause. No product code was changed.

### `a32rt` (`4b94c1527bea`)

- [x] **A32-R16-1 — Low — CLEAN — TLB range comment promises a 512-page cutoff**
  - **Where**: `a32rt` `src/vm/vm32.h:107` and `src/vm/vm32.c:184-197` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`.
  - **What breaks / Why**: The declaration says `Range-selective invalidation (< 512 pages) else full clear.` `a32_vm32_tlb_invalidate_range` computes `pages` and then walks every page in the span. It never compares that count with 512 and never calls `a32_vm32_tlb_invalidate_all`.
  - **Fix**: Describe the walk the function performs, or call `a32_vm32_tlb_invalidate_all` when `pages >= 512`.

### `i686rt` (`92fc0afb23d6`)

- [x] **I686-R16-1 — Low — CLEAN — Fault-code comment says si_code selects the catch**
  - **Where**: `i686rt` `src/interp/interp.c:213-217` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: The comment on `i686_fault_code` says `SEGV_MAPERR` versus `SEGV_ACCERR` selects remap-and-resume versus deliver. The interpreter catch at `interp.c:621` and the DBT catch at `src/dbt/engine.c:626` branch on `i686_fault_region_prot(...) != 0`. Neither catch reads `i686_fault_code`. A search found no caller of that getter.
  - **Fix**: Say the catch uses the region mirror. Remove `i686_fault_code` if it stays uncalled.

### `mips32rt` (`3fb98db8f8ca`)

- [x] **M32-R16-1 — Low — CLEAN — COP1X break comment skips the MADD keep**
  - **Where**: `mips32rt` `src/dbt/dbt.c:166-176` and `:680` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: The comment says only COP1X and COP2 force a block break into `interp_step`. `dbt_is_unhandled_coproc` returns 0 for COP1X when `(d->funct & 0x26U) == 0x20U`. The loop breaks only when that predicate is nonzero, so those encodings stay in the block. That funct test is the MADD/MSUB/NMADD/NMSUB family the FP emitter keeps.
  - **Fix**: Say COP2, and COP1X forms other than `funct & 0x26 == 0x20`, force the break.

### `loongarch64rt` (`eec0f3d517bd`)

- [x] **LA64-R16-1 — Low — CLEAN — FCVT/FRINT width comment is inverted**
  - **Where**: `loongarch64rt` `src/dbt/emit_fp.c:417-418` @ `eec0f3d517bdf9c1fb3d6abe842ceebd9ed0a36e`.
  - **What breaks / Why**: The comment says `S out iff exactly one of (D in, convert) holds.` `f_result` stores a double when `is_d != 0` (`emit_fp.c:177-178`). The call passes 1 when exactly one of `is_d_in` and `cvt` is true, so that case stores D. `FCVT.S.D`, `FCVT.D.S`, `FRINT.S`, and `FRINT.D` still store S, D, S, and D.
  - **Fix**: Say D is stored iff exactly one of (D in, convert) holds.

### `mips64rt` (`92e86b9ed717`)

- [x] **M64-R16-1 — Low — YAGNI — mips_sc_futex has no caller**
  - **Where**: `mips64rt` `src/os/syscalls_sync.c:87` @ `92e86b9ed717c89e371c7df21b88a6e7ac7f5f4c`.
  - **What breaks / Why**: `mips_sc_futex` is defined here. The only other mention is the `extern` at `src/os/syscall_min.c:53`. Futex numbers return `mips_futex_op` at `syscall_min.c:713-715`. This is a different function from the open `M32-R13-10` handler and from `M64-R13-9` (`mips_sc_symlinkat`).
  - **Fix**: Remove `mips_sc_futex` and that extern.

### `sparc64rt` (`e33935f73e3a`)

- [x] **S64-R16-1 — Low — YAGNI — vm64_tlb_invalidate_pair has no caller**
  - **Where**: `sparc64rt` `src/vm/vm64.c:402` @ `e33935f73e3a097c65435ff026c9168c2724d823`.
  - **What breaks / Why**: `vm64_tlb_invalidate_pair` clears a paired TLB slot and has no C caller. `vm64_tlb_invalidate_range` clears tags itself and is what `vm64.c:871` calls. The name in `SPEC.md` is not a call. This is not the open `vm64_tlb_publish_pair` item.
  - **Fix**: Remove `vm64_tlb_invalidate_pair`, or call it from the invalidation path that owns the pair.

### `ppc32rt` (`621e36892ffb`)

- [x] **P32-R16-1 — Low — CLEAN — Stack header still defers the auxv this file writes**
  - **Where**: `ppc32rt` `src/rt32/ppc32_stack32.c:12-16` @ `621e36892ffb8d5f68ddd615b670324d4e437c07`.
  - **What breaks / Why**: The file header says `AT_PHDR`, `AT_ENTRY`, `AT_UID`, `AT_DCACHEBSIZE`, `AT_RANDOM`, `AT_EXECFN`, and the `PPC32_SIGTRAMP_BASE` mapping arrive with the Phase 2 os lane. `ppc32_stack_setup` already stores `AT_PHDR` (line 159), `AT_ENTRY` (line 169), `AT_UID` (line 171), `AT_RANDOM` (line 186), `AT_EXECFN` (line 190), and `AT_DCACHEBSIZE` (line 201). `PPC32_SIGTRAMP_BASE` appears only in that header.
  - **Fix**: Describe the auxv `ppc32_stack_setup` writes. Keep only the vDSO/sigtramp mapping as not built in this file.

### `sparc32rt` (`f343b8b2a375`)

- [x] **S32-R16-1 — Low — CLEAN — Header still says AT_HWCAP stays 0**
  - **Where**: `sparc32rt` `src/rt32/stack32.c:13` and `:345-347` @ `f343b8b2a37554ee2e64cb8204dc7cb2fd915b3d`.
  - **What breaks / Why**: The header says `AT_HWCAP is 0 until Phase 2 HWCAP discovery.` The same function stores `SPARC_HWCAP_FLUSH | SPARC_HWCAP_STBAR | SPARC_HWCAP_SWAP | SPARC_HWCAP_MULDIV` (`1|2|4|8`, value `0x0F`) into `SPARC_AT_HWCAP`. `AT_HWCAP2` at line 348 stays 0.
  - **Fix**: Say `AT_HWCAP` is the FLUSH/STBAR/SWAP/MULDIV set, and that only `AT_HWCAP2` stays 0.

## Round 17 — Multi-review loop 8/16, Darwin host errno, resolved (2026-11-11; remediated 2026-11-13)

Same pinned revisions as Round 13. Each item below was opened in the current tree and confirmed by two independent read-only checks. Nothing here repeats an open Round 13 cause. No product code was changed.

### `rvrt` (`ca1ef7bc3a4d`)

- [x] **RV-R17-1 — Medium — BUG — Fork and exec rejection returns the host EOPNOTSUPP**
  - **Where**: `rvrt` `src/runtime/runtime_main_syscall.c:365` and `:373`, and `src/runtime/runtime_main_fork_spawn.c:14`, `:372`, and `:377` @ `ca1ef7bc3a4d01cd318fb2c7544d147c662ad5ff`.
  - **What breaks / Why**: Those five sites store `UINT64_C(0) - EOPNOTSUPP` in the guest result. The same functions use `rv_linux_errno` for other failures (`runtime_main_syscall.c:543`, `runtime_main_fork_spawn.c:394`). `rv_linux_errno` maps `EOPNOTSUPP` to 95 (`src/linux/error.c:142`). The TUs include `<errno.h>` after `_POSIX_C_SOURCE 200809L`. On Darwin that macro is 102, so the guest sees `-102`. On Linux the macro is already 95.
  - **Fix**: Return `UINT64_C(0) - (uint64_t)rv_linux_errno(EOPNOTSUPP)` at each of the five sites.
  - **Test**: On Darwin, a guest `clone` or `execve` that hits one of these rejections returns `-102`. The Linux errno for `EOPNOTSUPP` is `-95`.

## Round 18 — Multi-review loop 3/16, memory and atomics, resolved (2026-11-11; remediated 2026-11-13)

Same pinned revisions as Round 13. Each item below was opened on the interpreter path and on the DBT path. The paired read-only verifiers exited on a usage-balance error before returning a verdict, so the confirmation is the two source paths read in this session. Nothing here repeats an open Round 13 cause. No product code was changed.

### `a32rt` (`4b94c1527bea`)

- [x] **A32-R18-1 — Medium — BUG — Thumb STMIA and LDMIA commit earlier transfers**
  - **Where**: `a32rt` `src/interp/interp_thumb.c:467-492` and `src/interp/interp_t16.c:430-434` @ `4b94c1527beaa57665444c2578dc9f7e1fec9e04`. The DBT side is `src/core/core_emit_shared.c:543-589`.
  - **What breaks / Why**: The Thumb loop calls `i_store_u32` or `i_load_u32` and returns `A32_EXIT_FAULT` on the first failure. Earlier stores are already in memory, and earlier load destinations are already written. Base writeback sits after the loop, so `Rn` stays at the pre-instruction value. `a64_emit_ldm_stm` probes the first byte and the last byte with `LDRB` before any store or load (`core_emit_shared.c:552-556`). An unmapped far end faults with memory and registers unchanged. The A32 interpreter checks the whole span first (`src/interp/interp_a32_mem.c:140-150`). Closed `A32-R7-8` is the probe being a read.
  - **Fix**: Give the Thumb loop the same full-span check the A32 interpreter uses, before the first transfer.
  - **Test**: Thumb `STMIA r0!, {r1,r2}` (`0xC006`), `r0=0x1FFC`, `r1=0x11111111`, writable `[0x1000,0x2000)`, unmapped `[0x2000,0x3000)`. The interpreter stores `0x11111111` at `0x1FFC` and faults with `r0` still `0x1FFC`. The DBT faults on the byte at `0x2003` and leaves `0x1FFC` unchanged.

### `i686rt` (`92fc0afb23d6`)

- [x] **I686-R18-1 — High — BUG — Unaligned LOCK RMW commits in the interpreter and faults in the DBT**
  - **Where**: `i686rt` `src/interp/h_alu.c:304-313` and `:399-429`, `src/interp/h_alu_lock.c:64-78`, `src/x86/decode.c:185-193`, `src/dbt/emit_atomic.c:75-77` and `:381-385`, `src/os/signals_subpage.c:809-812`, `src/dbt/engine.c:625-646`, `src/os/signals_i386.c:654-688` @ `92fc0afb23d6f0b9ebfcbb24ede7a59f6b92e95a`.
  - **What breaks / Why**: `alu_lock_enter` returns 0 only for a naturally aligned address. A writable unaligned address returns 1, and `alu_exec` then falls through to `x86_rm_write`. `mem_store` copies the result with `memcpy`, so the locked add commits. `i686_emit_atomic` emits an LSE atomic at `xG + ea` with no alignment bailout. The file header says a misaligned element takes a host alignment fault. `i686_spurious_emulate` returns `-1` when `vm_host_page <= 4096`, so the 4 KiB host does not replay the instruction. `i686_deliver_sync` maps that host `SIGBUS` to guest signal 11 and trap 14.
  - **Fix**: Decline a misaligned LOCK form from `i686_emit_atomic` so the interpreter runs it, or emit the same byte RMW the interpreter uses.
  - **Test**: `lock add dword ptr [eax], ebx` (`F0 01 18`), `eax=1`, `ebx=1`, the dword at guest 1 is 0, one writable page `[0, 0x1000)`, `vm_host_page <= 4096`. The interpreter writes 1. The DBT delivers `SIGSEGV` / `#PF` and leaves the dword at 0.

### `mips32rt` (`3fb98db8f8ca`)

- [x] **M32-R18-1 — High — BUG — A dead SC on read-only memory succeeds in the DBT**
  - **Where**: `mips32rt` `src/os/mem.c:820-832`, `src/interp/interp.c:562-576`, `src/dbt/emit_mem.c:693-743` @ `3fb98db8f8ca14d64889feca687443fce55788f6`.
  - **What breaks / Why**: `guest_sc32` checks `PROT_WRITE` (`a2_validate(..., 1)` or `range_covered(..., PROT_WRITE)`) before the `llbit == 0` early return. The interpreter leaves `rt` unchanged and returns `MIPS_FAULT`. `emit_sc` loads the word with `LDR` (`emit_mem.c:696`) and, when `llbit` is 0, joins the fail path that stores 0 into `rt`. That `LDR` succeeds on a host-readable `PROT_READ` page. The `STR` at line 730 is only the success path. The interpreter comment at `interp.c:562-570` states the store check.
  - **Fix**: Fault a store to a page without `PROT_WRITE` before the `llbit` test in `emit_sc`.
  - **Test**: `[0x1000,0x2000)` mapped `PROT_READ` and host-readable, `$4=0x1000`, `$2=0x99`, `llbit=0`, `SC $2, 0($4)`. The interpreter raises `SIGSEGV` and leaves `$2` at `0x99`. The DBT writes `$2=0` and continues.

### `ppc64rt` (`3c236f2584e9`)

- [x] **P64-R18-1 — High — BUG — A cross-page access past EOF is SIGSEGV in the DBT**
  - **Where**: `ppc64rt` `src/vm/vm64.c:230-246`, `:267-290`, `:555-561`, and `:617-624`, `src/interp/interp.c:315-324`, `src/dbt/emit_mem.c:270-280` and `:400-405` and `:579-581`, `src/dbt/dbt.c:826-832`, `src/run/core.c:379-383`, `src/run/sigdeliver.c:578-582`, `src/vm/vm_file.c:723-732` @ `3c236f2584e9e0a2e5ebf07fa77d3110b032202c`.
  - **What breaks / Why**: `vm_mem_read` and `vm_mem_write` walk the span after `vm_validate` fails and set `fault->address` to the first page that `ppc64_vm_file_is_beyond_eof` accepts. `mem_access` passes that address to `interp_trap_at`. The DBT fast path uses mask `0xfffffffffffff003` for a 4-byte access, so `lwz` at `0x10FFE` misses and enters `ppc64_vm_tlb_miss`. `miss_fail` stores the start address in `OUT_TVAL`. The fault exit is `exit(2, cause, tval)`, and `ppc64_dbt_step` copies `x2` into `r.tval`. `run_access_signal` returns 7 only when that address's page is wholly past EOF, so an in-file start page becomes signal 11. `lwz` has no data-alignment trap in `mem_access`. Open `P64-R13-*` items do not cover this `tval`.
  - **Fix**: When the failing span contains a wholly past-EOF page, pass that page as `tval`, the way `vm_mem_read` does.
  - **Test**: `MAP_PRIVATE` file mapping at `0x10000`, length 8192, file size 4096, so page `0x11000` is wholly past EOF. `r3=0x10FFE`, then `lwz r4, 0(r3)`. The interpreter delivers `SIGBUS` (7). The DBT delivers `SIGSEGV` (11).
