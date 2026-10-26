**Rev 2 is not ready to freeze.** Several corrections are sound, but the dispositions overstate closure. The remaining problems affect memory safety, guest syscall behavior, executable-file truncation, fork coherence, and register preservation.

No repository files were edited. “Resolved” below means resolved **in the proposed design**, not implemented or qualified.

## (A) Verification of Review #1 findings

| # | Verdict | Verification |
|---:|---|---|
| 1 | **Partially resolved** | The load lookup assembles, selects the correct index, preserves NZCV, and checks natural alignment and page boundaries. The store listing contradicts the correct operand order elsewhere; signed-width and miss-recovery contracts remain incomplete. [Plan:189](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:189), [Plan:205](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:205). See B3–B4. |
| 2 | **Unresolved** | Intersection protection prevents permissive hardware accesses, but guest-valid syscall buffers can fail, and the interpreter’s accessible, coherent backing is unspecified. [Plan:241](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:241), [Plan:246](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:246). See B1. |
| 3 | **Partially resolved** | Provider A and native-Linux retirement gates are substantial improvements. Direct host mapping does not supply guest-granule EOF semantics on large-page Linux or invalidate detached generated code. [Plan:264](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:264), [Plan:534](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:534). See B5–B6. |
| 4 | **Partially resolved** | Rev 2 correctly treats inode backing as new functionality. Cross-spawn invalidation, fork transport, and host-copyout integration remain undefined. [Plan:273](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:273), [Plan:520](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:520). See B7–B8. |
| 5 | **Partially resolved** | Live SPARC64 dependencies are acknowledged, but U1 still explicitly removes a reachable, tested family operation as “unused.” [Plan:490](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:490). See B10. |
| 6 | **Resolved as a planning correction** | The PPC64 production stub is accurately identified, and U0 now requires execution through the shipped entry point. [Plan:135](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:135), [Plan:479](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:479). |
| 7 | **Partially resolved** | Owner-only TLB updates solve cross-thread publication tearing. The epoch protocol does not specify parked workers, refill exclusion, mutation publication, or in-flight host accesses. [Plan:228](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:228), [Plan:232](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:232). See B2. |
| 8 | **Partially resolved** | Inode ownership and the partial dirty-private-page rule are corrected. Correctness still depends on dirty classification covering host writes and surviving fork. [Plan:277](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:277), [Plan:284](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:284). See B7–B8. |
| 9 | **Partially resolved** | The operation inventory is much broader. Race-free blocking calls, canonical shared-futex identity, and complete asynchronous signal information remain absent. [Plan:406](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:406), [Plan:420](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:420). See B11. |
| 10 | **Partially resolved** | Separating guest VMA management from host mapping primitives is sound. Querying host page size does not resolve offset alignment, guest EOF granularity, or the four-quarter algorithm on 64 KiB hosts. [Plan:165](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:165), [Plan:326](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:326). See B5. |
| 11 | **Unresolved** | The replacement register table still misstates SPARC64, PPC64, and A32 conventions. [Plan:151](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:151), [Plan:154](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:154). See B9. |
| 12 | **Partially resolved** | Missing suites and premature RV32 dispatch are addressed. Prototype acceptance, GAP policy, provider dependencies, and continuous AOT gates remain inconsistent. [Plan:477](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:477), [Plan:503](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:503). See B12. |
| 13 | **Partially resolved** | Top-level translator counts match pinned objects. Donor-tree partitions remain wrong, and the published command does not count pinned blobs. [Plan:121](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:121), [Plan:133](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:133). See B13. |
| 14 | **Mostly resolved** | The per-repository Darwin descriptions are improved and LoongArch’s defect is accurately described. SPARC64’s existing host-page rounding remains omitted. [Plan:133](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:133), [a32host.h:86](/Users/angerman/Projects/zw3rk/sparc64rt/include/a32host.h:86). |
| 15 | **Substantially resolved** | Stage-1 versus Stage-2, conservative ACL authority, and SPARC64’s ABI page size are corrected. The replacement “>99%” uniform-page assertion is still unsupported. [Plan:137](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:137), [Plan:242](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:242). |

## (B) New or remaining findings

### Critical

**B1. Class-A mixed-page mediation does not cover the complete memory-access path.**

At [Plan:241](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:241), a neighboring quarter can narrow an otherwise guest-writable buffer’s host page to `PROT_READ` or `PROT_NONE`.

Host `read`, `pread64`, and `recvfrom` then encounter an inaccessible destination during kernel copyout. They can return `EFAULT` or a short transfer; they do not enter the DBT instruction-fault handler. Host copyin similarly fails on `PROT_NONE`.

This affects actual direct-pointer paths, including [i686 read/write:94](/Users/angerman/Projects/zw3rk/i686rt/src/os/syscalls.c:94), [pread:1818](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_pass.c:1818), and [recvfrom:581](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_sock.c:581). `getdents64` already uses a bounce buffer, but its final copy still reaches raw protected-window `memcpy`: [sys_stat.c:740](/Users/angerman/Projects/zw3rk/i686rt/src/os/sys_stat.c:740), [marshal.c:39](/Users/angerman/Projects/zw3rk/i686rt/src/os/marshal.c:39).

The interpreter fallback at [Plan:246](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:246) merely names “shadow/pread or temporary per-thread alias.” Existing MIPS helpers validate permissions and then access the same protected window: [mem.c:120](/Users/angerman/Projects/zw3rk/mips32rt/src/os/mem.c:120). They would fault again. Temporarily widening the shared window would let sibling DBT threads access forbidden quarters.

**Fix:** Choose a coherent backing-and-alias design. Require all interpreter, instruction-fetch, syscall, futex, and signal-frame accesses to use validated memory operations with mapping lifetime protection. Define partial-transfer and side-effect behavior. Test all four named syscalls, copyin, and simultaneous interpreter/DBT access on mixed pages.

**B2. The quiescence protocol does not establish a safe mutation transaction.**

[Plan:231](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:231) lets workers flush and adopt the new epoch; [Plan:232](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:232) waits for acknowledgement before reclaiming backing. It never states that acknowledged workers remain parked.

A worker can acknowledge, refill from the old mapping, and resume while the writer completes reclamation. Its epoch already matches, so another flush is not guaranteed. Blocking syscalls retaining guest-buffer pointers also cannot be handled solely by block-boundary checks.

**Fix:** Specify request → park/drain → mutate → publish → release. Prevent refills during mutation, cover interpreter/helpers and kernel I/O, define lock ordering, and prohibit backing reclamation until every relevant access has drained.

### Major

**B3. The store example selects the wrong fields unless the `ldp` destinations are swapped.**

[Plan:189](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:189) is correct:

```asm
ldp x3, x2, [x2, #8]   // x3=addend; x2=write_tag
```

But [Plan:205](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:205) says to use `[x2,#8]` for stores while retaining `ldp x2,x3`. That loads `addend` into the comparison register and `write_tag` into the address-addend register. Both forms assemble; assembler acceptance does not detect the semantic error.

**Fix:** Publish separate complete load and store listings. Require `reg_val` to be distinct from address and lookup scratch registers. With the sample allocation, instructions 1–6 preserve a store value in `x0`; a miss helper or endian conversion needs an explicit preservation rule.

**B4. Signed-load and miss-stub semantics remain insufficiently specified.**

The signed endian ordering at [Plan:222](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:222) is directionally correct. Exact variants should be frozen:

```asm
// Little-endian signed loads into a 64-bit guest register:
ldrsb x0, [x1, x3]
ldrsh x0, [x1, x3]
ldrsw x0, [x1, x3]

// Big-endian signed halfword:
ldrh  w0, [x1, x3]
rev16 w0, w0
sxth  x0, w0

// Big-endian signed word:
ldr   w0, [x1, x3]
rev   w0, w0
sxtw  x0, w0
```

Using a `W` destination for the signed byte/halfword result does not produce a sign-extended 64-bit result. Big-endian sign extension must follow byte reversal.

More seriously, `cbnz` at [Plan:208](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:208) provides no return address. The shared stub has no specified descriptor identifying width, signedness, operation, guest PC, continuation, or spilled architectural state. Existing MIPS lowering explicitly records the fault PC before a potentially faulting access: [emit_mem.c:73](/Users/angerman/Projects/zw3rk/mips64rt/src/dbt/emit_mem.c:73).

**Fix:** Define per-access recovery metadata or specialized stubs, including hardware faults at instruction 7, store-value preservation, NZCV/LR preservation, and delay-slot state. Distinguish refill-and-retry from completed emulation and guest fault delivery.

**B5. Advertised 16/64 KiB native-Linux support lacks guest-granule semantics.**

[Plan:264](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:264) passes a guest file offset directly to host `mmap`. Offset `4096` fails on a 16/64 KiB kernel. Aligning down and retaining a bias fixes that call; existing code already demonstrates this bookkeeping at [rvrt_shared.c:94](/Users/angerman/Projects/zw3rk/hyper-linux/src/rvrt_shared.c:94).

It does **not** fix [Plan:267](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:267): after shrinking a file to 4096 bytes on a 16 KiB host, offset 8192 remains inside the host’s partial final page, while it is a whole removed page for a 4 KiB guest. Host COW-tail behavior is likewise host-page granular.

Separately, Class A claims all hosts above 4096 bytes but hardcodes `sub_prot[4]` and `&3`: [Plan:238](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:238). A 64 KiB host requires sixteen subpages.

**Fix:** Define aligned mapping/bias ownership plus software guest-granule EOF/COW mediation. Derive projection size from host page size. Qualify actual 16 KiB and 64 KiB kernels.

**B6. Truncating executable source mappings does not invalidate generated code.**

The kernel can invalidate a source mapping while a detached DBT block continues executing generated instructions. The vague tracking promise at [Plan:264](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:264) supplies no inode-to-block invalidation transaction.

Current RVRT preserves a family guard from source refresh through execution and checks block memory generations: [runtime_main.c:5011](/Users/angerman/Projects/zw3rk/rvrt/src/runtime_main.c:5011). Shrink advances the source generation: [file_backing.c:246](/Users/angerman/Projects/zw3rk/rvrt/src/memory/file_backing.c:246).

**Fix:** Track code dependencies by backing identity and range. Revoke blocks, direct links, IBTC/RAS entries, and active execution safely when source validity changes. Define external-writer handling and rearm code watches whenever translations are installed. Preserve executable-file truncation tests before retiring the existing machinery.

**B7. Provider B has no cross-`fork_ipc` inode authority or invalidation protocol.**

The registry at [Plan:273](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:273) is VM-local, but [Plan:520](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:520) promises tracking across fork.

`hyper-linux` uses spawned processes and explicit IPC. Its fork code distinguishes copied private primary pages from retained shared backing and spans: [fork_ipc.c:1620](/Users/angerman/Projects/zw3rk/hyper-linux/src/fork_ipc.c:1620). The existing shared wire state lacks the proposed generations, COW classifications, and EOF markers: [rvrt_shared.h:12](/Users/angerman/Projects/zw3rk/hyper-linux/src/rvrt_shared.h:12).

Flushing one VM’s Stage-1 PTEs does not revoke another VM’s mappings. The RWX Stage-2 primary mapping supplies no replacement enforcement: [guest.c:325](/Users/angerman/Projects/zw3rk/hyper-linux/src/guest.c:325).

**Fix:** Define retained inode authority, versioned fork state, and acknowledged cross-process shrink/regrow invalidation. Include parent/child private-COW provenance and mapping lifetime.

**B8. Stage-1 first-write faults do not classify host syscall writes.**

[Plan:278](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:278) makes clean writable private pages read-only until a guest fault.

Current `read` validation requires writable Stage-1 mappings, so an otherwise valid clean-private destination would fail: [syscall_io.c:1611](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_io.c:1611). Other paths write through host pointers without a Stage-1 write fault, including [recvfrom:1931](/Users/angerman/Projects/zw3rk/hyper-linux/src/syscall_net.c:1931). Those writes can remain classified clean and subsequently be erased by clean-tail truncation.

**Fix:** Centralize COW promotion for guest faults **and every host copyout**, with mapping synchronization, reservation bookkeeping, and code invalidation. Test syscall writes followed by partial shrink/regrow.

**B9. The register inventory still contradicts the actual engines.**

[Plan:154](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:154) assigns SPARC64 context to `x28`. Actual code uses `x19` for context and `x28` for the chaining epoch: [trampoline:37](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/trampoline_a64.S:37), [trampoline:79](/Users/angerman/Projects/zw3rk/sparc64rt/src/dbt/trampoline_a64.S:79).

PPC64 enters generated code with `x0=cpu`, `x1=mem_ops`, `x2=mem_ctx`: [trampoline:10](/Users/angerman/Projects/zw3rk/ppc64rt/src/dbt/trampoline_a64.S:10). A32 maps guest registers to `w0..w14`, not `x21..x27`: [a64_emit.h:20](/Users/angerman/Projects/zw3rk/a32rt/src/a64_emit.h:20).

**Fix:** Correct the inventory and distinguish preserved conventions from proposed migrations. Cover emitters, trampolines, helpers, chaining, recovery metadata, and cache compatibility together.

**B10. U1 removes a live, tested SPARC64 self-test dependency.**

[Plan:490](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:490) calls family creation unused. It is reached by `sparc64_host_selftest`: [host_contract_identity.c:707](/Users/angerman/Projects/zw3rk/sparc64rt/src/rt64/runtime/host_contract_identity.c:707), which calls the verifier that creates families at [line 452](/Users/angerman/Projects/zw3rk/sparc64rt/src/rt64/runtime/host_contract_identity.c:452). The host-contract test explicitly requires its output: [check_host_contract.sh:433](/Users/angerman/Projects/zw3rk/sparc64rt/tests/check_host_contract.sh:433).

**Fix:** Migrate or behaviorally replace that closure before deletion. Removing it contradicts U1’s identical-before/after acceptance.

**B11. The “complete frozen” backend still lacks consequential contracts.**

Three concrete gaps remain:

- **Blocking-call commitment:** [Plan:421](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:421) provides a wake operation without closing the pending-check → host-call lost-wakeup window. Existing D18 explicitly supplies generation checking and PC recovery: [safe_syscall_a64.S:6](/Users/angerman/Projects/zw3rk/mips32rt/src/rt32/safe_syscall_a64.S:6).
- **Shared futex identity:** pointer plus `shared` at [Plan:406](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:406) leaves Darwin alias/fork keying undefined. Existing RVRT distinguishes MM/address keys from backing identity/offset: [futex_key.c:74](/Users/angerman/Projects/zw3rk/rvrt/src/linux/futex_key.c:74).
- **Signal information:** [Plan:431](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:431) cannot represent asynchronous sender PID/UID, queued value, or timer payload. Per-worker alternate-stack lifecycle is also absent.

**Fix:** Freeze interruption/commit/restart semantics, canonical futex identity and lifetime, and separate synchronous-fault/asynchronous-signal structures before declaring the interface complete.

**B12. Acceptance gates still permit incomplete qualification.**

At [Plan:476](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:476), scope requires `0 FAIL, 0 GAP`; RC-U0 only requires `0 FAIL` at [line 480](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:480). Existing SPARC64 parity permits GAP outcomes: [parity_suite.sh:45](/Users/angerman/Projects/zw3rk/sparc64rt/tests/parity_suite.sh:45).

The U0 prototype has no explicit semantic acceptance. U2’s three-host dirty-COW acceptance precedes Provider B’s U4 implementation. The dispositions also claim continuous AOT gates that U2/U4 do not contain: [dispositions:24](/Users/angerman/Projects/zw3rk/rt-series/lode/reviews/2026-10-26-astra-unification-review-dispositions.md:24).

**Fix:** Define required rows and permitted oracle omissions, require prototype results before freezing, stage provider-dependent acceptance after integration, and add affected AOT preservation checks.

### Minor

**B13. The reproducible baseline still contains incorrect partitions.**

The command at [Plan:121](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:121) selects working-tree bytes, not pinned blobs; `git -C` also does not change `xargs wc`’s directory.

Pinned tracked donor counts are:

| Repository | Rev 2 files / LOC | Verified files / LOC |
|---|---:|---:|
| loongarch64rt | 75 / 28,505 | **81 / 27,969** |
| mips64rt | 76 / 28,505 | **81 / 28,355** |
| ppc64rt | 223 / 48,653 | **242 / 54,930** |
| sparc64rt | 225 / 49,889 | **252 / 57,529** |

The verified sum is **168,783 LOC**, matching the headline but contradicting its component rows at [Plan:133](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:133).

**Fix:** Count `git ls-tree REV` paths and `git show REV:path` newline bytes. Publish working-tree status separately.

**B14. The replacement performance assertion remains unmeasured.**

The “>99%” uniform-page claim at [Plan:242](/Users/angerman/Projects/zw3rk/rt-series/docs/UNIFICATION-PLAN.md:242) has no supporting workload measurement.

**Fix:** Remove the percentage or instrument mapping uniformity and mediation frequency before making that claim.

Validation comprised source inspection, pinned Git-object counts, an AArch64 assembler probe, and an exhaustive mathematical check of all 4096 page offsets for widths 1/2/4/8. The load alignment/tag check passed all 16,384 cases. Both store operand orders assemble, confirming that assembly alone cannot establish correctness. No integrated runtime suites or actual 16/64 KiB Linux tests were run.