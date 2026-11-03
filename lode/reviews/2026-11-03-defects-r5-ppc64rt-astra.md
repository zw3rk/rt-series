Round 5 identified **10 findings** through static inspection. Used **8 shell commands**; read no Markdown and ran no builds, tests, Docker, or QEMU. No files changed.

This checkout has no `tools/tests/` or `src/elf/`; inspected `tests/` and `src/run/load.c` instead. Findings below are code-derived, not execution-verified.

1. **[P64-R5-1] DEFECT — ELF program-header bounds checks can overflow. High.**  
   **Evidence:** [src/run/load.c:341](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:341), [src/run/load.c:238](/Users/angerman/Projects/zw3rk/ppc64rt/src/run/load.c:238).  
   Both checks calculate `phoff + phnum * 56` before comparing with the image length. A near-`UINT64_MAX` offset can wrap below `len`, allowing the subsequent header loop to form and dereference an out-of-bounds pointer.  
   **Fix:** Require `phoff <= len`, then check `phnum <= (len - phoff) / 56` before any pointer arithmetic.

2. **[P64-R5-2] BUG — PLHA zero-extends negative halfwords in both engines. High.**  
   **Evidence:** [src/interp/prefix.c:151](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:151), [src/dbt/emit_mixed.c:297](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/emit_mixed.c:297).  
   The interpreter reads two bytes but sign-extends from bit 31. The DBT selects width two without setting `sext`. Thus `0x8000` becomes `32768` instead of `-32768`. Interpreter/DBT agreement masks the defect.  
   **Fix:** Sign-extend the interpreter value from `n * 8` bits and set `sext = true` for emitted PLHA. Include negative halfwords in oracle coverage.

3. **[P64-R5-3] BUG — Prefixed scalar FP accesses select the wrong register for odd RA. High.**  
   **Evidence:** [src/interp/prefix.c:187](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:187), [src/interp/prefix.c:243](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:243), [src/interp/prefix.c:269](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:269).  
   `xt` incorporates suffix bit 16, which belongs to RA. The scalar PLFS/PLFD/PSTFS/PSTFD paths then use this index. With RA odd, an access intended for FPR `rt` instead accesses VSR `rt + 32`.  
   **Fix:** Use `rt` for scalar FPR forms; decode vector register extensions separately for their actual instruction forms.

4. **[P64-R5-4] BUG — PLXSD executes as an integer halfword load. High.**  
   **Evidence:** [src/interp/decode.c:641](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:641), [src/interp/prefix.c:109](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:109).  
   The decoder distinguishes MLS PLHA from 8LS PLXSD using the prefix form. Execution instead routes every suffix opcode 42 through the integer halfword path, reading two bytes and modifying a GPR.  
   **Fix:** Dispatch execution using the decoded instruction identity, or validate the prefix form before selecting the integer path. Implement the scalar VSX operation or explicitly reject it before modifying state.

5. **[P64-R5-5] BUG — Shared writable mmap accepts a read-only descriptor. High.**  
   **Evidence:** [src/os/syscalls_mm_map.c:31](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_mm_map.c:31), [src/os/syscalls_mm_map.c:206](/Users/angerman/Projects/zw3rk/ppc64rt/src/os/syscalls_mm_map.c:206), [src/vm/vm_file.c:437](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:437).  
   File validation rejects `O_WRONLY` but never requires write access for `MAP_SHARED | PROT_WRITE`. Tracking also omits that check, so a mapping that should fail with `EACCES` succeeds.  
   **Fix:** Validate the descriptor access mode against both mapping type and protection before staging or mutation. Preserve the permitted `MAP_PRIVATE | PROT_WRITE` case on readable descriptors.

6. **[P64-R5-6] BUG — An earlier read-only mapping can silently break later shared writeback. High.**  
   **Evidence:** [src/vm/vm_file.c:193](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:193), [src/vm/vm_file.c:447](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:447), [src/vm/vm_file.c:702](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_file.c:702).  
   `vm_file_hold` retains an existing descriptor whenever its inode matches, without checking its access mode. Map an inode through `O_RDONLY`, then map it shared/writable through `O_RDWR`: writeback still uses the retained read-only descriptor. `pwrite` fails, and the write hook silently abandons persistence.  
   **Fix:** Retain suitable read and write capabilities separately, or upgrade the retained descriptor when a writable mapping arrives. Handle writeback failure explicitly.

7. **[P64-R5-7] CLEAN / DEFECT — Branch decoding invokes signed-shift undefined behavior. Medium.**  
   **Evidence:** [src/interp/decode.c:74](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:74), [src/interp/decode.c:87](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/decode.c:87).  
   `bd << 16` overflows signed `int32_t` for negative branch displacements. `li << 6` shifts a signed value that still includes the primary opcode, also exceeding the representable range. These operations violate the no-undefined-behavior invariant.  
   **Fix:** Mask the displacement into an unsigned value, then sign-extend with representable arithmetic—for example, subtract the displacement modulus when its sign bit is set.

8. **[P64-R5-8] BUG — Phase 6 scripts still compile deleted `src/rt64` sources. Medium.**  
   **Evidence:** [tests/p6_host_contract.sh:84](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_host_contract.sh:84), [tests/p6_run.sh:182](/Users/angerman/Projects/zw3rk/ppc64rt/tests/p6_run.sh:182).  
   The host-contract script references `src/rt64/aot/{sha256,digest}.c` and `memory/file_identity.c`; the page probe references `memory/{space,space_p1}.c`. Those paths are absent from this checkout, making these compilation stages unusable.  
   **Fix:** Port the harnesses to current APIs and source lists, preferably through maintained Make targets.

9. **[P64-R5-9] DRY — VM atomic fallback logic is duplicated. Low.**  
   **Evidence:** [src/vm/vm_atomic.c:227](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_atomic.c:227), [src/vm/vm_atomic.c:274](/Users/angerman/Projects/zw3rk/ppc64rt/src/vm/vm_atomic.c:274).  
   Cross-page and unaligned accesses duplicate the read, reservation creation, lookup, consumption, conditional write, and result handling. Both copies also return success without performing non-LR/SC RMW operations.  
   **Fix:** Define the supported fallback behavior once in a repository-local helper, or reject unsupported alignment explicitly. Do not preserve silent successful no-ops.

10. **[P64-R5-10] YAGNI — Obsolete reservation flag remains threaded through execution. Low.**  
    **Evidence:** [src/interp/interp.c:26](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:26), [src/interp/interp.c:315](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/interp.c:315), [src/interp/prefix.c:160](/Users/angerman/Projects/zw3rk/ppc64rt/src/interp/prefix.c:160).  
    `g_res_unused` is reset and passed to helpers that clear it, but its value does not govern reservation validity. The prefix-file comment nevertheless describes it as clearing the caller’s reservation, obscuring the actual mechanism.  
    **Fix:** Remove the obsolete flag, parameters, and stores; update comments to identify the active reservation-invalidation path.

**Cross-runtime propagation notes**

These are suggested checks, not confirmed sibling defects:

| Findings | Sibling checks |
|---|---|
| R5-1, R5-5, R5-6 | Check `rvrt`, `mips64rt`, `loongarch64rt`, and `sparc64rt` for copied ELF bounds checks, mmap access validation, and inode-level retained descriptors. |
| R5-2–R5-4 | Primarily PPC64-specific. Check `ppc32rt` for analogous algebraic-load extension and FPR/VSR field confusion where applicable. |
| R5-7 | Check `ppc32rt` branch decoding first; inspect other instruction decoders for signed left-shift sign extension. |
| R5-8 | Check sibling phase scripts for stale `src/rt64` paths after source migrations. |
| R5-9–R5-10 | Check runtimes carrying the same atomic fallback or obsolete reservation plumbing. Keep any deduplication within each repository. |

The source-size scan found **no `.c`, `.h`, or `.S` file above 900 lines** under `src/` or `tests/`. This bounded audit does not establish exhaustive signal, threading, or Soft-TLB correctness.