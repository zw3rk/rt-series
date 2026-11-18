# rt-series Defect Archive — Round 21: 5-Track Expansion (`s390xrt`, `ppc64` BE ELFv1, `G02` `darwin32`) (2026-11-15 to 2026-11-17)

Audited across 5 concurrent campaign tracks and remediated on isolated worker
lanes between `2026-11-15` and `2026-11-17 02:00:00 +0900`, independently
re-verified by post-remediation review-commit (`RC`) passes with `make check`
green on every track. Round 21 converges standalone Class-B `s390xrt`
(`a53ee31..8410b2c`), `ppc64rt` big-endian ELFv1 (`8ec83bc..09832a3`),
`ppc32rt` Darwin G4 CPU & `A32H_ABI 1.2` `G02` bridge (`4a35f01..a2ccdfc`),
`a32rt` `G02` bridge & `a32rt-slim` decoupling (`6bf6d76..a53ee27`), and the
`hyper-linux` unified 32-bit PowerPC/ARM Darwin personality
(`darwin32/personality` campaign `661d7a11..b8cc19a0`).

| Runtime | Audited Revision | Remediated Commit | Items (Round 21) |
|---|---|---|---:|
| `a32rt` | `6bf6d76` | `a53ee27` | `7 / 7` |
| `ppc32rt` | `4a35f01` | `a2ccdfc` | `5 / 5` |
| `ppc64rt` | `8ec83bc` | `09832a3` | `9 / 9` |
| `s390xrt` | `a53ee31` | `8410b2c` | `12 / 12` |
| `hyper-linux` (`darwin32`) | `9905a615` (branch base) | `b8cc19a0` | `3 / 3` |
| **Total** | | | **`36 / 36`** |

---

## 1. `a32rt` — `A32H_ABI 1.2` `G02` Darwin Host Bridge & `a32rt-slim` Decoupling (`A32-R21-D1`..`D7`)

- [x] **A32-R21-D1 — High — BRIDGE — Missing `A32H_ABI 1.2` `G02` Darwin host bridge and slim build decoupling**
  - **Where**: `a32rt` `src/os/darwin*`, `Makefile`, `include/a32host.h` @ `6bf6d76`.
  - **What breaks / Why**: No in-tree `G02` (`A32H_ABI 1.2`) Darwin host bridge exists, so the 32-bit ARM personality cannot negotiate host capabilities via `/dev/a32host`, and the full `a32rt` build cannot be decoupled into the standalone `a32rt-slim` configuration.
  - **Fix**: Add the `A32H_ABI 1.2` Darwin host bridge and slim build decoupling (`71a1cd7`); sync the frozen `A32H_ABI 1.2` `a32host.h` (`369bcf6`).

- [x] **A32-R21-D2 — High — BRIDGE/SOFT-TLB — `G02` bridge, Soft-TLB sync, and slim decoupling `RC4` items open**
  - **Where**: `a32rt` `src/os/darwin/*`, Soft-TLB sync paths @ `71a1cd7`.
  - **What breaks / Why**: Post-bridge review (`RC4`) finds `G02` bridge edge cases, Soft-TLB synchronization gaps against Darwin host mappings, and incomplete slim-decoupling guards, any of which can serve stale translations or break the slim build.
  - **Fix**: Close the `RC4` `G02` bridge, Soft-TLB sync, and slim decoupling items (`a001b01`).

- [x] **A32-R21-D3 — High — STORE-CLASSIFIER — Loose Thumb2/ARM store fault opcode classification in `darwin_host_cpu`**
  - **Where**: `a32rt` `src/os/darwin_host_cpu.c` @ `a001b01`.
  - **What breaks / Why**: The store-fault opcode classifier accepts opcodes outside the true Thumb2/ARM store set, so non-store faults are misattributed to guest stores and recovery writes back the wrong register state.
  - **Fix**: Tighten Thumb2/ARM store fault opcode classification (`2e7699e`).

- [x] **A32-R21-D4 — High — STORE-CLASSIFIER — `STREXH`/`STREXD` and SIMD store fault masks uncovered**
  - **Where**: `a32rt` `src/os/darwin_host_cpu.c` @ `2e7699e`.
  - **What breaks / Why**: Exclusive halfword/doubleword stores (`STREXH`/`STREXD`) and SIMD stores miss their fault masks, so a faulting exclusive or vector store skips the single-step recovery path and the guest observes a torn exclusive-monitor update.
  - **Fix**: Cover `STREXH`/`STREXD` and SIMD store fault masks (`7acddf0`).

- [x] **A32-R21-D5 — High — STORE-CLASSIFIER — Conditional ARM VFP stores and media ops escape fault handling**
  - **Where**: `a32rt` `src/os/darwin_host_cpu.c` @ `7acddf0`.
  - **What breaks / Why**: Conditionally executed ARM VFP stores and media-operation stores are not recognized as stores by the fault classifier, so a predicated faulting store either aborts the guest or silently drops the write.
  - **Fix**: Handle conditional ARM VFP stores and media ops in the fault classifier (`5013c52`).

- [x] **A32-R21-D6 — Medium — TESTS — Hardcoded Thumb test vector length in `tests/g02`**
  - **Where**: `a32rt` `tests/g02/*` @ `5013c52`.
  - **What breaks / Why**: The Thumb test vector length is hardcoded instead of derived from the first halfword, so Thumb-2 32-bit instruction vectors are truncated or over-read and the `G02` store-classifier tests assert on the wrong bytes.
  - **Fix**: Derive the Thumb test vector length from the first halfword (`9f17ff5`).

- [x] **A32-R21-D7 — Medium — RC4 — Store classifier, worker `tid`, signal poll, CLI, and AOT image hash follow-ups**
  - **Where**: `a32rt` `src/os/darwin_host_cpu.c`, worker/signal/CLI/AOT paths @ `a001b01`.
  - **What breaks / Why**: The `rc4_v2` review pass finds residual defects in the store classifier, worker thread-id attribution, host signal polling, CLI option plumbing, and AOT image hashing, each a standalone guest-visible or cache-poisoning fault.
  - **Fix**: Close the `rc4_v2` store classifier, worker `tid`, signal poll, CLI, and AOT image hash items (`0387553`).

---

## 2. `ppc32rt` — PowerPC 7400 G4 AltiVec + `A32H_ABI 1.2` `G02` Darwin Bridge (`P32-R21-D1`..`D5`)

- [x] **P32-R21-D1 — High — ISA — G4 AltiVec interpreter and initial `G02` Darwin host bridge missing**
  - **Where**: `ppc32rt` `src/interp/*`, `src/os/*` @ `4a35f01`.
  - **What breaks / Why**: No G4-class AltiVec interpreter exists and no `G02` Darwin host bridge is wired, so AltiVec guests trap to `EXIT_UNDEF` and Darwin-hosted `ppc32rt` cannot negotiate `/dev/a32host` capabilities.
  - **Fix**: Add the G4 AltiVec interpreter and initial `G02` Darwin host bridge (`d8e8af5`); sync the frozen `A32H_ABI 1.2` `a32host.h` (`3c23376`).

- [x] **P32-R21-D2 — High — FAULT — `G02` `[G, G + 4 GiB)` fault recovery and DBT G4/Darwin traps broken**
  - **Where**: `ppc32rt` fault-recovery paths, `src/dbt/*` @ `d8e8af5`.
  - **What breaks / Why**: Faults inside the parametric `[G, G + 4 GiB)` window recover against the wrong base, and DBT-emitted G4/Darwin trap sequences miss their host handoff, aborting Altivec/Darwin guests on first trap.
  - **Fix**: Repair `G02` `[G, G + 4 GiB)` fault recovery and DBT G4/Darwin traps through full `make check` (`9f3e731`).

- [x] **P32-R21-D3 — High — DBT/PROFILE — `RC3` AltiVec, SPE/VMX profile dispatch, and `G02` bridge items open**
  - **Where**: `ppc32rt` `src/dbt/*`, CPU profile dispatch @ `9f3e731`.
  - **What breaks / Why**: `RC3` review finds AltiVec lowering gaps, SPE/VMX profile mis-dispatch (classic vs. e500v2 vs. G4), and residual `G02` bridge items, each capable of silently executing the wrong vector semantics.
  - **Fix**: Close the `RC3` AltiVec, SPE/VMX profile dispatch, and `G02` bridge items (`2871247`).

- [x] **P32-R21-D4 — High — VMX/BRIDGE — `rc3_v2` VMX/bridge defects and unguarded 4 KiB Darwin low page**
  - **Where**: `ppc32rt` VMX paths, Darwin low-memory guard @ `2871247`.
  - **What breaks / Why**: Residual `rc3_v2` VMX/bridge defects corrupt vector results across the bridge, and the 4 KiB Darwin low guard page is missing, so NULL-page guest accesses trap the host instead of the guest.
  - **Fix**: Close the `rc3_v2` VMX/bridge defects and install the 4 KiB Darwin low guard (`b2dbb8d`).

- [x] **P32-R21-D5 — High — DBT — `rc3_v3` DBT invalidation ownership and emitter guard initialization**
  - **Where**: `ppc32rt` `src/dbt/*` @ `b2dbb8d`.
  - **What breaks / Why**: DBT code-cache invalidation ownership is ambiguous across threads (`rc3_v3`), and emitter guards initialize late, so a racing SMC/invalidation can execute a half-invalidated block.
  - **Fix**: Close the `rc3_v3` DBT invalidation ownership and emitter guard init items (`97b10f9`).

---

## 3. `ppc64rt` — 64-Bit PowerPC Big-Endian ELFv1 ABI, `.opd`, and BE Syscalls/Signals (`P64-R21-D1`..`D9`)

- [x] **P64-R21-D1 — High — LOADER — Big-endian ELFv1 admission missing**
  - **Where**: `ppc64rt` ELF admission @ `8ec83bc`.
  - **What breaks / Why**: Only little-endian ELFv2 images are admitted, so every big-endian ELFv1 binary is rejected at load time and the BE campaign has no entry point.
  - **Fix**: Add big-endian ELFv1 admission (`3a096be`); record the BE execution plan and `G01..G20` goals (`794831f`).

- [x] **P64-R21-D2 — High — INTERP — Big-endian interpreter and OS ABI missing**
  - **Where**: `ppc64rt` `src/interp/*`, OS ABI layer @ `8ec83bc`.
  - **What breaks / Why**: Without a BE interpreter and BE OS ABI mapping, admitted ELFv1 images decode with swapped byte order and every syscall number marshals to the wrong host call.
  - **Fix**: Add the big-endian ELFv1 interpreter, OS ABI, and initial BE DBT (`3a096be`).

- [x] **P64-R21-D3 — High — DBT — BE DBT registry broken; `torture_int` / `torture_fp_vec` fail under `difftest`**
  - **Where**: `ppc64rt` `src/dbt/*`, torture harness @ `3a096be`.
  - **What breaks / Why**: The BE DBT registry keys blocks by the wrong endianness tag, so BE blocks alias LE entries, and `torture_int` / `torture_fp_vec` diverge between `interp` and `dbt`.
  - **Fix**: Repair the BE DBT registry and pass `torture_int` and `torture_fp_vec` under `difftest` (`1dad706`).

- [x] **P64-R21-D4 — High — ELFv1/ABI — `RC2` big-endian ELFv1, Soft-TLB/EOF, and BE syscall items open**
  - **Where**: `ppc64rt` ELFv1, Soft-TLB, EOF table, syscall layer @ `1dad706`.
  - **What breaks / Why**: `RC2` review finds BE ELFv1 descriptor gaps, Soft-TLB endianness-tag leaks, EOF-table truncation, and BE syscall marshaling errors, each fatal to BE userland bring-up.
  - **Fix**: Close the `RC2` big-endian ELFv1, Soft-TLB/EOF, and BE syscall items (`2edf3f5`).

- [x] **P64-R21-D5 — High — AOT — `rc2_v2` AOT profile reset drops BE function descriptors**
  - **Where**: `ppc64rt` AOT profile cache @ `2edf3f5`.
  - **What breaks / Why**: The AOT profile reset path clears BE `.opd` function-descriptor state, so warm-reloaded BE blocks jump to stale descriptors and crash on first indirect call.
  - **Fix**: Close the `rc2_v2` AOT profile reset item (`70ce821`).

- [x] **P64-R21-D6 — High — CHECK — `check-be` not fail-closed on BE ABI violations**
  - **Where**: `ppc64rt` `check-be` gate @ `2edf3f5`.
  - **What breaks / Why**: The BE conformance gate warns instead of failing on ABI violations, letting malformed BE images proceed into DBT and fault deep inside translated code.
  - **Fix**: Make `check-be` fail-closed (`70ce821`).

- [x] **P64-R21-D7 — High — SIGNALS — BE `ucontext`/`siginfo` layout checks missing**
  - **Where**: `ppc64rt` signal frame paths @ `2edf3f5`.
  - **What breaks / Why**: BE `ucontext`/`siginfo` layouts are unchecked, so signal delivery writes LE-ordered frames the guest handler misreads, corrupting the entire register file on return.
  - **Fix**: Add BE `ucontext`/`siginfo` checks (`70ce821`).

- [x] **P64-R21-D8 — Medium — FP — Classic `frsp` (`PO 63 XO 12`) missing; BE `stfiwx` byte order swapped**
  - **Where**: `ppc64rt` FP interpreter/DBT @ `70ce821`.
  - **What breaks / Why**: Classic `frsp` (single-precision round, `PO 63 XO 12`) is unimplemented and BE `stfiwx` stores bytes in LE order, so FP store-and-reload sequences return bit-swapped words.
  - **Fix**: Add classic `frsp` and fix BE `stfiwx` byte order (`e4dfc73`).

- [x] **P64-R21-D9 — Medium — SIGNALS — BE sigframe `vmx` base misaligned with `v_regs`; residual BE syscall findings**
  - **Where**: `ppc64rt` BE sigframe, syscall layer @ `e4dfc73`.
  - **What breaks / Why**: The BE signal frame `vmx` base does not match the `v_regs` layout, so vector registers restore from the wrong offsets, and residual BE syscall findings mis-marshal trailing arguments.
  - **Fix**: Align the BE sigframe `vmx` base with `v_regs` and close the BE syscall findings (`5425db2`).

---

## 4. `s390xrt` — Standalone Class-B `z13` Bring-Up, Shadow-VM `difftest`, Torture Qualification (`S390-R21-D1`..`D12`)

- [x] **S390-R21-D1 — High — CONTRACTS — Frozen CPU/VM64 contracts missing**
  - **Where**: `s390xrt` `include/*`, `src/vm/*` @ `a53ee31`.
  - **What breaks / Why**: Without frozen CPU and VM64 contracts, the interpreter, DBT, and VM disagree on register-file and address-space layout, making every later subsystem integration undefined.
  - **Fix**: Add the frozen CPU/VM64 contracts, ELF/syscall core, and z/Architecture interpreter (`7e1dbdb`); sync `A32H_ABI 1.2` `a32host.h` (`cf36276`).

- [x] **S390-R21-D2 — High — INTERP — z/Architecture interpreter core missing**
  - **Where**: `s390xrt` `src/interp/*` @ `a53ee31`.
  - **What breaks / Why**: No instruction interpreter exists, so no `s390x` guest instruction can execute and there is no correctness oracle for the future DBT.
  - **Fix**: Add the z/Architecture interpreter alongside the frozen contracts (`7e1dbdb`).

- [x] **S390-R21-D3 — High — LOADER — ELF64 and syscall core missing**
  - **Where**: `s390xrt` ELF loader, syscall layer @ `a53ee31`.
  - **What breaks / Why**: 64-bit big-endian ELF images cannot load and no guest syscall marshals, so even a correct interpreter has nothing to run.
  - **Fix**: Add the ELF/syscall core (`7e1dbdb`).

- [x] **S390-R21-D4 — High — HARNESS — Interpreter/ELF64/OS wiring and torture harness incomplete**
  - **Where**: `s390xrt` `src/interp/*`, OS layer, `tests/*` @ `7e1dbdb`.
  - **What breaks / Why**: The interpreter, ELF64 loader, and OS subsystems are unwired and no torture harness exists, so regressions have no executable oracle.
  - **Fix**: Wire the interpreter, ELF64/OS subsystems, and the initial `s390x` torture harness (`04b5577`).

- [x] **S390-R21-D5 — High — DBT — AArch64 `REV` DBT, Soft-TLB, and chaining/IBTC/RAS missing**
  - **Where**: `s390xrt` `src/dbt/*` @ `04b5577`.
  - **What breaks / Why**: Big-endian guest loads need byte-reversing (`REV`) emitters, and without Soft-TLB plus chaining/IBTC/RAS every block exits to the runtime, leaving DBT slower than the interpreter.
  - **Fix**: Add the AArch64 `REV` DBT, Soft-TLB, chaining/IBTC/RAS, AOT cache, and DBT test suite (`edf2db9`).

- [x] **S390-R21-D6 — High — AOT — AOT cache and DBT test suite missing**
  - **Where**: `s390xrt` AOT cache, `tests/*` @ `04b5577`.
  - **What breaks / Why**: Without an AOT cache, translated blocks never persist across runs, and without a DBT test suite BE lowering regressions go undetected.
  - **Fix**: Add the AOT cache and DBT test suite (`edf2db9`).

- [x] **S390-R21-D7 — High — BUILD — Unified `interp`+`dbt`+`aot` build unwired; `t_alu` fails in interpreter**
  - **Where**: `s390xrt` build, `tests/t_alu` @ `edf2db9`.
  - **What breaks / Why**: The three engines do not link into one binary and the ALU torture test fails under the interpreter, blocking the single-binary qualification gate.
  - **Fix**: Link the unified `interp`+`dbt`+`aot` build and pass `t_alu` in the interpreter (`4cec5cf`).

- [x] **S390-R21-D8 — High — DBT — Rem-B2 integer/branch/memory/FP lowerings and Soft-TLB faults**
  - **Where**: `s390xrt` `src/dbt/*` @ `4cec5cf`.
  - **What breaks / Why**: Remediation-batch-2 review finds wrong integer, branch, memory, and FP lowerings plus Soft-TLB fault-path errors, each producing guest-silent wrong results under DBT.
  - **Fix**: Fix the DBT integer/branch/memory/FP lowerings and Soft-TLB (`70242af`).

- [x] **S390-R21-D9 — High — AUDIT — `RC1` interpreter, decode, ELF64, syscall, and signal items open**
  - **Where**: `s390xrt` interp/decode/ELF64/syscall/signal paths @ `70242af`.
  - **What breaks / Why**: The `RC1` audit files defects across all five bring-up subsystems; leaving any open leaves the first userland boot on a known-broken path.
  - **Fix**: Close the `RC1` interpreter, decode, ELF64, syscall, and signal items (`5e5ac73`).

- [x] **S390-R21-D10 — High — DBT/W^X — Runtime `x18` reservation latch and Apple Silicon W^X helpers missing**
  - **Where**: `s390xrt` `src/dbt/*` @ `5e5ac73`.
  - **What breaks / Why**: Without a runtime `x18` reservation latch, emitted code can clobber the platform-reserved register, and without Apple Silicon W^X helpers JIT pages cannot transition to executable on Darwin hosts.
  - **Fix**: Add the runtime `x18` reservation latch and Apple Silicon W^X helpers (`6486463`).

- [x] **S390-R21-D11 — High — HEADER — `A32H_ABI 1.2` `a32host.h` out of sync**
  - **Where**: `s390xrt` `include/a32host.h` @ `a53ee31`.
  - **What breaks / Why**: A stale host-contract header desynchronizes the `G02` capability negotiation from the frozen cross-repo contract, so capability probes misreport under `hyper-linux`.
  - **Fix**: Sync `A32H_ABI 1.2` `a32host.h` from `rt-series` (`cf36276`).

- [x] **S390-R21-D12 — High — VERIFY — `z13` decode/interp/DBT convergence, shadow-VM `difftest`, torture qualification**
  - **Where**: `s390xrt` full tree @ `00d703e`.
  - **What breaks / Why**: Subsystem fixes mean nothing without end-to-end proof: decode/interp/DBT agreement, shadow-VM lock-step `difftest` with `0` divergences, and torture qualification are the exit criteria for the round.
  - **Fix**: Converge `z13` decode/interp/DBT with shadow-VM `difftest` and torture qualification (`c91effe`, merged in `8410b2c`).

---

## 5. `hyper-linux` `darwin32` — Unified 32-Bit PowerPC/ARM Darwin Personality (`HL-DARWIN-R21-D1`..`D3`)

- [x] **HL-DARWIN-R21-D1 — High — LOADER — `darwin32` loader, bundle, `dylib`, and binder defects**
  - **Where**: `hyper-linux` `src/darwin32/*` (loader, bundle, `dylib`, binder) @ branch base `9905a615`.
  - **What breaks / Why**: The 32-bit Darwin loader mishandles bundles, `dylib` binding fails on weak imports, and binder defects corrupt the launch image, so no PPC32/ARM32 Darwin guest reaches userspace.
  - **Fix**: Remediate the `darwin32` loader, bundle, `dylib`, and binder defects (`73cefb3f`, building on `0ef27ade`, `9c46291c`).

- [x] **HL-DARWIN-R21-D2 — High — OS/MACH — OS/Mach/shim/`a32host` server defects; `ppc32rt` VM launch unwired**
  - **Where**: `hyper-linux` `src/darwin32/*` (OS services, Mach traps, shim, `a32host` server) @ `73cefb3f`.
  - **What breaks / Why**: OS/Mach/shim/`a32host` server defects break guest trap delivery, and the `ppc32rt` VM launch path is unwired, so even a well-formed guest cannot boot under the HVF backend.
  - **Fix**: Remediate the OS/Mach/shim/`a32host` server and wire `ppc32rt` VM launch (`d92e7f29`, merged via `58f5dfb4`).

- [x] **HL-DARWIN-R21-D3 — Medium — LAUNCH — `rc5_v2` fixes, live guest launch, `--ppc32rt` CLI, clean signal-poll exit**
  - **Where**: `hyper-linux` `src/darwin32/*`, CLI @ `d92e7f29`.
  - **What breaks / Why**: `rc5_v2` review leaves launch-blocking defects; without the `--ppc32rt` CLI option and live HVF guest launch wiring (`rc=37` PPC32, `rc=42` ARM32 slim) the personality is untestable, and `A32H_DEXIT_NONE` spuriously fails signal-poll exits.
  - **Fix**: Converge the `rc5_v2` fixes, wire live `ppc32rt`/`a32rt` HVF guest launch (`51add23c`), add the `--ppc32rt` CLI option and `HL_OBJECT_BUILD` subdir creation (`fd83e372`), and treat `A32H_DEXIT_NONE` as a clean signal-poll no-op (`b8cc19a0`).

---

## 6. Pre-Merge Review Provenance

Each track's remediation commits double as the review record: `a32rt` `RC4`/`rc4_v2`
(`a001b01`, `0387553`), `ppc32rt` `RC3`/`rc3_v2`/`rc3_v3` (`2871247`, `b2dbb8d`,
`97b10f9`), `ppc64rt` `RC2`/`rc2_v2` (`2edf3f5`, `70ce821`), `s390xrt` `RC1`/`Rem-B2`
(`5e5ac73`, `70242af`), and `darwin32` `rc5_v2` (`51add23c`). Post-merge,
`docs/DEFECTS.md` §1 records the converged revisions (`a53ee27`, `a2ccdfc`,
`09832a3`, `8410b2c`, `b8cc19a0`) with `36 / 36` resolved and `0` open.
