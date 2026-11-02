Repository: **loongarch64rt**  
HEAD: **`0f57c40a3e2f29318c318e5ea772877050468887`**

Seven batched shell inspections completed. Source inventory: **90 production `.c`/`.h`/`.S` files, 28,859 lines**; **124 such files, 39,446 lines** including tests and experiments. Inspection covered selected implementation paths across the interpreter, DBT, VM, loader, syscalls, signals, backends, and build declarations. This bounded audit is **not an exhaustive verification of every module**.

No builds, tests, emulators, or containers were run. Findings below follow from static source inspection; suggested triggers were not executed. All remediation stays within this standalone repository.

| Severity | BUG | DEFECT | C11 | DRY | YAGNI | CLEAN | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Critical | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| High | 4 | 1 | 0 | 0 | 0 | 0 | 5 |
| Medium | 3 | 0 | 1 | 0 | 0 | 1 | 5 |
| Low | 0 | 0 | 0 | 1 | 1 | 1 | 3 |
| **Total** | **7** | **1** | **1** | **1** | **1** | **2** | **13** |

## 1. Bugs & Defects

### High

- [ ] **LA64-1 — High — BUG — Instruction fetch ignores guest execute permission**
  - **Where**: `src/interp/interp.c:71-79` (`interp_step`); `src/dbt/dbt.c:370-389` (`translate_block`); `src/os/mem_min.c:274-305` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:46-67` (`vm64_ptr`).
  - **What breaks / Why**: Both engines fetch instructions through `la64_mem_ptr(pc, 4, 0)`. This validates readability, not executability. Instructions placed in readable, non-executable mappings can execute. Conversely, execute-only mappings fail the read check. Host W^X does not enforce guest execute permission because the translator reads guest instructions as data.
  - **Fix**: Introduce an explicit fetch access type that checks guest execute permission independently of data-read permission. Use it for interpreter fetch and DBT translation, and invalidate cached translations when execute permission changes.

- [ ] **LA64-2 — High — BUG — Mixed guest protections can leave a Darwin host page inaccessible**
  - **Where**: `src/os/mem_min.c:150-173` (`protect_host_page`), `src/os/mem_min.c:478-519` (`la64_mem_protect`).
  - **What breaks / Why**: When guest regions sharing a host page have different protections, `protect_host_page` returns without updating host permissions. For example, protect a complete 16 KiB allocation as read-only, then restore write permission to one 4 KiB subpage. Guest metadata allows the write, but the host page remains read-only. A permitted guest store then faults in the translator. Starting from `PROT_NONE` produces the same problem for restored read access.
  - **Fix**: Set host-page permissions to the union required by its live guest subpages, while enforcing individual guest permissions in software/TLB tags. Propagate host protection failures instead of ignoring them.

- [ ] **LA64-3 — High — BUG — Vector memory faults terminate the translator**
  - **Where**: `src/interp/interp_vec.c:83-110` (`interp_step_vec`); `src/interp/interp.c:817-848` (`interp_step`); `src/interp/interp_mem.h:29-35` (`die_at`).
  - **What breaks / Why**: Invalid vector memory accesses return an error string. The dispatcher sends that string to `die_at`, which calls `exit(3)`. Guest `SIGSEGV` handlers cannot recover. DBT instructions routed through interpreter fallback inherit this behavior. Vector loads also modify destination bytes before checking later bytes, leaving partially updated state when a cross-page access fails.
  - **Fix**: Return structured guest faults with the access address and type, then deliver them through the signal subsystem. Stage vector load results and commit the destination only after the complete access succeeds.

- [ ] **LA64-4 — High — BUG — Bootstrap LSX instructions retain stale LASX upper halves**
  - **Where**: `src/interp/interp_vec.c:83-93`, `src/interp/interp_vec.c:114-188` (`interp_step_vec`); `src/interp/interp.c:817-833` (`interp_step`).
  - **What breaks / Why**: The bootstrap LSX path writes only the low 128 bits. Successful `VLD`, broadcasts, shuffles, `VOR.V`, and shifts never clear `vr[rd][2]` and `[3]`. The caller does not clear them either. This violates the repository’s specified LSX upper-half-zeroing contract and exposes stale values to subsequent LASX instructions.
  - **Fix**: Clear the upper 128 bits after successful LSX instructions that write a vector destination. Keep stores unchanged. Cover sequences that initialize all 256 bits, execute each LSX family, then inspect the complete LASX register.

- [ ] **LA64-5 — High — DEFECT — Difftest does not compare DBT register or PC state**
  - **Where**: `src/main.c:302-382` (`diff_child_verify`); `src/main.c:579-639` (`run_difftest`).
  - **What breaks / Why**: The DBT run is checked only for exit status and stdout. The register/PC comparison replays the interpreter against another interpreter trace: `diff_child_verify` calls `interp_step`. Nevertheless, success reports `difftest: 0 divergences`. A DBT register error that does not affect stdout or exit status passes, contrary to the required cross-engine register/PC parity.
  - **Fix**: Compare DBT state against interpreter state at controlled instruction or block boundaries, including FP/vector state and relevant memory effects. Until implemented, label the existing result as output equivalence plus interpreter determinism.

### Medium

- [ ] **LA64-6 — Medium — BUG — Darwin directory enumeration loses unread entries**
  - **Where**: `src/os/syscalls_file.c:173-210` (`sys_getdents64`).
  - **What breaks / Why**: Each call creates a fresh `DIR *` from a duplicated descriptor. `readdir` consumes an entry before checking whether it fits the guest buffer. Breaking on insufficient space loses that entry; buffered directory read-ahead can also advance the shared descriptor beyond entries copied to the guest. Small-buffer enumeration can skip names.
  - **Fix**: Preserve directory stream state across calls, or restore the directory position to the cookie preceding the first unreturned entry. Account for libc buffering when managing the underlying descriptor.

- [ ] **LA64-7 — Medium — BUG — Mprotect succeeds across unmapped holes**
  - **Where**: `src/os/mem_min.c:478-522` (`la64_mem_protect`); `src/os/syscalls_mem.c:424-434` (`sys_mprotect_range`).
  - **What breaks / Why**: `covered` becomes true when any region lies within the requested range. The function returns success without establishing that the entire range is mapped. A request covering a mapped page followed by an unmapped page therefore succeeds instead of reporting `ENOMEM`. The syscall wrapper preserves that success.
  - **Fix**: Walk coverage across the complete requested interval and detect gaps. Return the required error when any page is unmapped; explicitly define any partial-update behavior.

- [ ] **LA64-8 — Medium — BUG — Write validation incorrectly requires read permission**
  - **Where**: `src/os/mem_min.c:299-304` (`la64_mem_ptr`); `src/vm/vm64_dispatch.c:62-65` (`vm64_ptr`).
  - **What breaks / Why**: Both validators require `PROT_READ` unconditionally, then additionally require `PROT_WRITE` for writes. Guest stores and syscall copyouts into a write-only mapping are rejected despite having write permission. This also makes access policy inconsistent with the VM store slow path, which checks write permission separately.
  - **Fix**: Select the required permission by access type: read, write, or instruction fetch. Apply the same policy across region memory, arena memory, and TLB paths.

## 2. Curated C11 & UB Issues

- [ ] **LA64-9 — Medium — C11 — Negative vector offsets invoke signed left-shift UB**
  - **Where**: `src/interp/fp_shuf.c:113-118` (`vec_mem_step`).
  - **What breaks / Why**: The 12-bit immediate is cast to `int32_t` before shifting left by 20. For values `0x800` through `0xfff`, the mathematical result exceeds `INT32_MAX`; signed left shift is undefined. These encodings represent ordinary negative offsets, so valid guest instructions trigger the UB.
  - **Fix**: Sign-extend without signed overflow, for example by converting the bounded immediate to `int64_t` and subtracting `4096` when bit 11 is set.

No concrete host `x18` access or banned string-function call was established by the source searches. This does not establish absence of all UB or concurrency defects.

## 3. DRY — Intra-Repo Duplication

- [ ] **LA64-10 — Low — DRY — JIT memory lifecycle is implemented twice**
  - **Where**: `src/dbt/dbt_code.c:55-104` (`dbt_alloc_rw`, `dbt_seal_page`); `src/os/backend_linux.c:288-326` (`rt_host_jit_*`); `src/os/backend_darwin.c:200-264` (`rt_host_jit_*`).
  - **What breaks / Why**: DBT code allocation directly implements platform mappings, Apple write protection, executable sealing, and cache flushing, while backend APIs implement those operations separately. The Apple allocation flags already differ. Fixes to one lifecycle do not automatically reach the other.
  - **Fix**: Keep block allocation and packing in `dbt_code.c`, but route platform allocation, write transitions, sealing, and freeing through one repository-local implementation. Preserve support for build configurations without the full backend.

## 4. YAGNI — Dead Code & Speculative Scaffolding

- [ ] **LA64-11 — Low — YAGNI — Return-address stack is populated but never consumed**
  - **Where**: `src/dbt/dbt_chain.c:23-24`, `src/dbt/dbt_chain.c:51-62` (`chain_ras`, `dbt_ras_push`, `dbt_ras_pop`); `src/dbt/dbt.c:728-735` (`dbt_run`).
  - **What breaks / Why**: Repository reference searches found no caller of `dbt_ras_pop`. The dispatcher pushes resume PCs for fallthrough, direct, and indirect exits, rather than specifically recording call return addresses. The stack fills and then stops accepting entries, without influencing execution.
  - **Fix**: Remove the unused stack and push path, or implement actual call/return prediction with validation and measured benefit. Do not describe the current bookkeeping as an operational RAS.

## 5. CLEAN — Hygiene, Comments, Module Boundaries & File Size

- [ ] **LA64-12 — Medium — CLEAN — Textual C includes bypass module boundaries**
  - **Where**: `src/interp/interp.c:40-56`; `src/os/syscalls.c:41-100`; `src/os/minsys.c:23`; `src/os/clone.c:217-218`; `src/main.c:20`.
  - **What breaks / Why**: Production sources textually include implementation files, including the decoder, FP engines, signal frames, clone handling, scheduler, syscall helpers, and argument parser. This directly violates the requested no-unity-includes rule. File splitting leaves large coupled translation units with include-order dependencies and shared private symbols.
  - **Fix**: Compile implementation files separately. Introduce narrow internal headers for required interfaces, move genuinely shared helpers into repository-local modules, and list translation units explicitly in the Makefile.

- [ ] **LA64-13 — Low — CLEAN — File-size gate excludes an oversized test**
  - **Where**: `tests/test_p3_fp_simd.c:901-940`; `Makefile:156-163` (`check-line-limits`).
  - **What breaks / Why**: Static `wc -l` inspection reports **940 lines** for `tests/test_p3_fp_simd.c`. The gate checks only `src/`, so it does not enforce the requested repository-wide 900-line ceiling. Production files are below the ceiling, but `emit_int.c` has 899 lines, `a64_emit.c` 898, `fp.c` 895, and `emit_fp.c` 890.
  - **Fix**: Split the FP/SIMD test into coherent separately compiled units and extend the gate to applicable tests and experiments. When extending near-limit production files, extract cohesive modules without textual `.c` includes.

The strongest established risks are guest execute-permission bypass, valid Darwin accesses becoming host faults, vector faults bypassing guest signals, and a parity harness that cannot substantiate DBT register correctness. Atomic interleavings, complete FP semantics, file-backed alias coherence, and full clone/exec behavior remain unqualified by this bounded static audit.