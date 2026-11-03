# Round-5 Post-Remediation Verification — `loongarch64rt` @ `f9f59e1`

Scope: static read of `git show f9f59e1` plus targeted greps of the resulting tree. No build, test, Docker, or QEMU run. Four tool turns used.

**Verdict: 5 VERIFIED, 3 PARTIAL, 1 REGRESSION.** The FCSR item (R5-5) needs rework before the round can close. Hygiene is clean.

| Item | Status | Anchor |
|---|---|---|
| LA64-R5-1 arena hole scan | VERIFIED | `src/os/mem_min.c:716-735` |
| LA64-R5-2 shared-store dirty wiring | PARTIAL | `src/interp/interp_mem.h:112`, `src/dbt/dbt_mem.c:279-282` |
| LA64-R5-3 inode fd rights | PARTIAL | `src/vm/vm_file.c:385-402`, `:699-710` |
| LA64-R5-4 host ptr before final prot | VERIFIED | `src/os/syscalls_mem.c:186-200` |
| LA64-R5-5 FCSR Cause vs sticky | REGRESSION | `src/dbt/emit_fp_mem.c:147-151`, `src/dbt/emit_fp.c:90`, `:133` |
| LA64-R5-6 overlay under PROT_NONE | VERIFIED | `src/vm/vm_file.c:694`, `:729-735` |
| LA64-R5-7 PT_INTERP tri-state | VERIFIED | `src/loader.c:288-299`, `:662-667` |
| LA64-R5-8 CoreMark strict verdict | VERIFIED | `tests/parity_suite.sh:255-263`, `:578-592` |
| LA64-R5-9 parity comparator DRY | PARTIAL | `tests/parity_suite.sh:217`, `:412` |

## Per-item evidence

**LA64-R5-1 — VERIFIED.** `la64_mem_find_hole` now walks every page of `[cand, cand+size)` through `vm64_owned_end` and restarts past the first owned span (`src/os/mem_min.c:716-735`); the regions-table pass that follows already checked the full range (`:738-748`). The reported overlap is closed. Residuals, not blocking: the walk is one `vm64_owned_end` call per free page, so a 1 GiB request costs ~262k probes; the astra suggestion to re-check under the mutation lock was not adopted, so the hint-to-map window remains a TOCTOU against a concurrent arena mapper.

**LA64-R5-2 — PARTIAL.** Wired: interpreter scalar stores and SC/AM stores via `st_bytes` (`src/interp/interp_mem.h:112`, callers `src/interp/interp.c:494-557,733,745`); DBT miss-fill refuses to install a writable TLB entry on a staged shared page and forces the interpreter path (`src/dbt/dbt_mem.c:279-282`); `mmap_file_fill` copyout (`src/os/syscalls_mem.c:143-144`); strong definitions in `src/vm/vm_file_sync.c:242-262` with weak no-op fallbacks in `src/os/mem_min.c:67-77`. Not wired, contrary to the fix text ("scalar, vector, atomic, and syscall copyout"):
- Vector stores write through `la64_mem_ptr(va+i, 1, 1)` with no note: `src/interp/fp_vec.c:75`, `src/interp/fp_shuf.c:152`, `src/interp/fp_vec_lasx.c:637`, `:701`.
- Syscall copyouts to guest memory have no note, e.g. `read()`-style buffer fill at `src/os/syscalls.c:203`, plus `:284`, `:462`, `:508`, `src/os/sigframe.c:196`, `src/os/minsys.c:71`. A `read()` into a `MAP_SHARED` buffer still leaves aliases stale.
- Dead code: `src/dbt/dbt_mem.c:304` can never see a shared page because `:281` already returned, so that note is always a no-op.
- Cost note: `la64_vm_file_shared_covers` takes the vmfile lock and scans `VMFILE_MAX_MAPS` on every DBT store miss-fill (`src/vm/vm_file_sync.c:252-261`). Measure before shipping; a per-page flag in the arena page state would be O(1).

**LA64-R5-3 — PARTIAL.** `vmfile_register` now replaces the cached dup only when the new fd's rights are a strict superset (`src/vm/vm_file.c:385-402`); the condition is correct. `map_bytes_in_place` prefers a readable fd for `pread` (`:547-553`), fixing the `O_WRONLY`-cache failure. The second half of the finding is still open: in `vmfile_map_shared` a cached `O_RDWR` dup is chosen whenever it covers the requested rights, regardless of the caller's fd (`:703-705`). A guest `mmap(PROT_WRITE, MAP_SHARED)` on an `O_RDONLY` fd whose inode already has a cached RDWR dup succeeds where Linux returns `EACCES`; no `O_ACCMODE`/`EACCES` check exists in `src/os/syscalls_mem.c` (grep empty). Fix: validate `prot` against `host_fd` rights first and fail `-EACCES`; only then substitute the cached fd.

**LA64-R5-4 — VERIFIED.** The host pointer is taken right after `la64_mem_map(va, size, map_prot)` where `map_prot` includes `LA64_PROT_WRITE` (`src/os/syscalls_mem.c:164,182,187`), before `mmap_file_fill` drops to the requested protection. `LA64_MEM_WRITE` is `1` (`src/os/mem_min.h:29`), so the lookup is a write lookup against the still-widened region. Nit: use the macro instead of literal `1` at `:187`.

**LA64-R5-5 — REGRESSION.** The interpreter side is fine: `fp_sync` overwrites Cause, ORs Flags, then clears host exceptions (`src/interp/fp_vec_priv.h:63-68`). The DBT side is not fixed and introduces a new hazard:
- `fp_fpsr_clear` is now unconditional (`src/dbt/emit_fp_mem.c:147-151`) and its comment says it runs "before each FP op". It does not. Its only callers are the FPCR programming paths at `src/dbt/emit_fp.c:90` and `:133` (fixed-rounding reprogram and the once-per-block `FPCR_DYN` enter) and `fp_s_fcmp` (`src/dbt/emit_fp_mem.c:186`). Consecutive same-rounding-mode FP ops still accumulate in FPSR until the deferred flush (`:296-312`), so `FADD(invalid); FADD(exact); MOVFCSR2GR` still reports Cause=V in DBT and Cause=0 in the interpreter. The original defect stands.
- New loss of sticky Flags: before this commit the clear at `emit_fp.c:90`/`:133` was guarded by `fpsr_dirty == 0`, so it never discarded pending bits. Now any pending FPSR bits from an earlier op in the block are wiped when a fixed-rounding op (`:90`) or a re-enter (`:133`) follows, unless a flush precedes those calls. Only `fp_s_fcmp` flushes first (`emit_fp_mem.c:185`); I saw no flush ahead of `:90` or `:133` in the inspected ranges (lines before 78 not read, flagged as unverified). Sequence that loses `IXC`: dyn `FADD` (inexact) → `FADD.rm` fixed → block end.
- No two-operation regression test was added; `tests/` has no `movfcsr2gr`-based case (only `tests/check_abi_invariants.c` mentions `fcsr`).

Fix: either emit `fp_fpsr_flags`+`fp_fcsr_store` after every FP op (per-op cost), or keep deferred accumulation but record "last op" by emitting a flush before each FP op when `fpsr_dirty` is set, and call `la64_emit_flush_fcsr` ahead of the two `emit_fp.c` clears. Add the two-op FCSR test.

**LA64-R5-6 — VERIFIED.** The shared path now stages with `vm64_map(gva, len, 0u, 1)` (`src/vm/vm_file.c:694`), replaces the backing, sets page state under prepare/commit (`:716-722`), records the map, and only then publishes final protection via `vm64_protect` (`:729-735`) with rollback on failure. Peers fault on `PROT_NONE` instead of reading zero fill. Observations: `vm64_map` still zero-fills pages that are immediately replaced (`src/vm/vm64.c:467`), harmless; `vm64_set_page_state` runs even when `prepare_mutation` failed (`:719-721`), pre-existing.

**LA64-R5-7 — VERIFIED.** `read_interp_path` returns 0/1/-1 (`src/loader.c:288-299`), requires a NUL inside the record and a non-empty path, and `la64_load` fails with `ENOEXEC` on -1 (`:662-667`). No other callers (grep). Minor leniency: the kernel requires the last byte to be NUL; this accepts a NUL anywhere in `p_filesz`.

**LA64-R5-8 — VERIFIED.** Fast leg (`tests/parity_suite.sh:255-263`) and Docker leg (`:578-592`) both require exit 0, a non-empty CRC file with ≥4 lines containing all four `crc*` tags, oracle agreement, and the committed golden (`tests/golden/coremark.crc`, `coremark.code` exist). Timeout exit 124 now yields FAIL with a "crc strict" detail.

**LA64-R5-9 — PARTIAL.** `og_verdict` (`tests/parity_suite.sh:412-425`) is now the single comparator for the Docker `check_guest` loop (`:462`) and `p5_dyn` (`:535`, `:537`), so the dynamic-loader case now checks goldens. However `cmp_oracle_golden` (`:217-233`) is defined and never called (grep shows only its definition) and is a second copy of the same logic parameterised on `$GOLDEN`. The DRY fix introduced a new duplicate. Delete it or route `run_fast` through it. `sh -n` passes.

## Hygiene

- **Line limits:** all 11 touched files ≤ 900. `src/vm/vm_file.c` 894 and `src/vm/vm_file_sync.c` 892 are within 10 lines of the cap; the next fix to R5-3 will likely need a split. `src/vm/vm64.c` 869, `src/os/mem_min.c` 853.
- **Curated C11:** no `sprintf`/`strcpy`/`strcat`/`_Generic`/`<threads.h>`/`alloca` in touched C files (only a comment hit at `src/vm/vm64.c:61`). No VLAs. Declarations at block heads. `MEM_WEAK_DEF` is a pre-existing GNU-attribute pattern, unchanged in scope.
- **Commit hygiene:** author/attribution correct, no agent trailers, working tree clean at `f9f59e1`.

## Required follow-up before Round-5 closeout

1. R5-5: rework DBT Cause/sticky handling as described and add the two-op `MOVFCSR2GR` regression. Treat as a blocker.
2. R5-3: add the `EACCES` rights check against the caller's fd in the shared-write path.
3. R5-2: note stores in the four vector store sites and in syscall copyout helpers, or document the accepted gap; remove the dead note at `dbt_mem.c:304`; measure `shared_covers` cost on the miss-fill path.
4. R5-9: remove the unused `cmp_oracle_golden`.

Propagation targets (unverified): `rvrt` for R5-1/3/6 patterns, sibling DBTs batching FPSR for R5-5, sibling `parity_suite.sh` for R5-8/9.
