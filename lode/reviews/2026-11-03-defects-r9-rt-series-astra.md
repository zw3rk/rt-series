# Round-9 Deep-Dive 3 audit: VM, Soft-TLB, COW, ELF/auxv

Scope was read-only. No files changed, no builds or tests run. Three of the four named torture files do not exist, so only `tests/p3_torture.c` plus its two headers could be audited.

| ID | Area | Severity | Fix gist |
|---|---|---|---|
| RTS-R9-1 | Missing P1/P2/P4 | Blocks audit | Add files or narrow scope |
| RTS-R9-2 | N64 placements | Spec conflict | Align SPEC to matrix |
| RTS-R9-3 | N32 placements | Spec conflict | Align SPEC to matrix |
| RTS-R9-4 | SPARC32 frame | Wrong layout | Use 344 B order |
| RTS-R9-5 | PPC64 vmx math | Arithmetic slip | Fix word breakdown |
| RTS-R9-6 | P3 memcpy probe | Async-signal UB | Byte-loop probe |
| RTS-R9-7 | P3 si_addr check | False pass | Require 2nd page |
| RTS-R9-8 | P3 missing VM tests | Coverage hole | Add brk/mremap/COW |

## RTS-R9-1 — Named torture files absent

`tests/` contains `bench_suite.c`, `bench_sys.h`, `check_abi_invariants.c`, `p3_llsc.h`, `p3_torture.c`, and `sig_fault_addr.h`. There is no `tests/p1_torture.c:1`, `tests/p2_torture.c:1`, or `tests/p4_torture.c:1`. Any claim that VM, `brk`, `mremap`, COW, ELF, or auxv behavior is covered by P1/P2/P4 cannot be checked. Fix: add the three files or restate the scope as P3-only.

## RTS-R9-2 — N64 placement contradiction

[SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:475) places N64 `mmap_base` at `0x0000005500000000`, `PT_INTERP` bias at `0x0000007f00000000`, and sigtramp at `0x000000fffffe0000`. The matrix row at [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:22) gives `0xc0_0000_0000`, `0xf0_0000_0000`, and `0xff_ffff_1000`. Stack tops agree; the other three do not. Fix: make `SPEC.md:475` match the `[F]`-tagged matrix values, or designate one document as the single source.

## RTS-R9-3 — N32 placement contradiction

[SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:476) places N32 `mmap_base` at `0x3f000000` and `PT_INTERP` bias at `0x3f800000`. The same matrix row at [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:22) gives `0x60000000` and `0x70000000`. Sigtramp and stack top agree. Fix: same as RTS-R9-2, one value per field.

## RTS-R9-4 — SPARC32 frame size and order

[SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:365) describes a 348-byte frame with an `extramask[1]` field and `stack_t` last. The matrix entry at [ISA-TRAP-AND-ABI-MATRIX.md](/Users/angerman/Projects/zw3rk/rt-series/lode/ISA-TRAP-AND-ABI-MATRIX.md:55) describes 344 bytes (`extent 0x158`) with `stack_t` at `0x144`, then `extra_size` and `rwin_save`. The 344-byte order matches Linux `signal_32.c`; the extra 4-byte `extramask` field has no kernel counterpart. Fix: delete `extramask`, move `stack_t` before `extra_size`/`rwin_save`, total 344.

## RTS-R9-5 — PPC64 `vmx_reserve` arithmetic

[SPEC.md](/Users/angerman/Projects/zw3rk/rt-series/SPEC.md:463) states `vmx_reserve[101]` is `808 B = 69 + 32 uint64_t`s holding a `544 B` vrregset plus `256 B` `vsr_low[32]`. `544 / 8` is 68, not 69, and `544 + 256` is 800 (`100` words), leaving 8 bytes of slack to reach 101. Fix: state `68 + 32 + 1 slack`.

## RTS-R9-6 — Fault probe calls `memcpy` under handler

[tests/p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:612) performs `memcpy(edge, &bad, ...)` inside the `sigsetjmp` window where `SIGSEGV`/`SIGBUS` long-jumps out. `memcpy` is not async-signal-safe, so interrupting it with `siglongjmp` is undefined and the copy may partially mutate the readable page first. Fix: probe with a `volatile unsigned char` byte loop.

## RTS-R9-7 — Weak `si_addr` acceptance, no partial-write check

[tests/p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:634) accepts any `si_addr` in `[base, base + two)`, so a translator reporting the readable first page instead of the faulting second page still passes. The test never re-reads first-page bytes after the fault, so a non-atomic cross-page store also passes. Fix: require `si_addr` in `[base + ps, base + 2 * ps)` and verify pre-fault first-page bytes are unchanged.

## RTS-R9-8 — No brk, mremap, fork-COW, auxv, or 8K tests

[tests/p3_torture.c](/Users/angerman/Projects/zw3rk/rt-series/tests/p3_torture.c:876) runs eight checks covering signals, `mprotect`/`munmap`, cross-page access, atomics, and SMC. Nothing exercises byte-granular `brk`, `mremap` file-backing preservation, `fork` private-COW isolation, `AT_PAGESZ`/auxv values, or SPARC64 indivisible 8K COW and EOF rounding. A translator with those defects passes P3. Fix: add those probes here or restore the missing P1/P2/P4 files that own them.

