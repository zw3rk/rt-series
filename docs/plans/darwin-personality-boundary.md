# Class-A Translator & `hyper-linux` Darwin Personality Boundary (`docs/plans/darwin-personality-boundary.md`)

**Status**: Active architectural boundary governing `a32rt`, `ppc32rt`, and `hyper-linux` (`hl`).

## 1. Core Architectural Rule: Keep Translators Small; Put Darwin OS & UI in `hl`

1. **Class-A Translators (`a32rt`, `ppc32rt`) Stay Small**:
   - Own **only** ISA state, portable C11 reference interpreter (`src/interp/`), AArch64 DBT + persistent AOT (`src/dbt/`, `src/core/`), 4 GiB guest memory window / Soft-TLB (`src/vm/`), Linux ELF userspace (`src/os/`), and a **narrow, versioned external guest-execution & trap contract (`G02`)**.
   - Carry **zero** GUI, WindowServer, Carbon, Cocoa, X11, CoreAudio, `.app` bundle, or native Darwin framework policy.
2. **`hyper-linux` (`hl`) Owns Darwin/XNU OS Personalities & UI**:
   - Owns Mach-O / FAT admission, `dyld` & symbol/rebase/bind resolution, commpage population, BSD syscalls, Mach traps/ports/MIG, `pthread`/`psynch`/`ulock` policy, Darwin signals / Mach exceptions, Wine-style synthetic compatibility libraries, user-supplied native framework bundles, and all UI/audio/X11 services (`ppc-darwin` + `ppc-darwin-ui`).
3. **Migrate `a32rt/src/ios/` into `hyper-linux`**:
   - Round 19–20 proved out a complete 32-bit iOS (`armv7`/`armv7s`) Mach-O, `dyld`, BSD/Mach, `kqueue`, `pthread`, signal, and synthetic `libSystem` implementation in `a32rt/src/ios/` (`16` files, `61 / 61` tests passing).
   - To keep `a32rt` small and match `ppc32rt`'s clean separation, `a32rt/src/ios/` will migrate into `hyper-linux` (see [`../../../a32rt/docs/plans/ios-hl-extraction.md`](../../../a32rt/docs/plans/ios-hl-extraction.md)), sharing endian-parameterized 32-bit Mach-O / Mach / XNU infrastructure with `ppc-darwin` where ABIs genuinely match while never conflating ARMv7 iOS with PowerPC Mac OS X 10.4/10.5 ABIs.

## 2. Narrow Cross-Repo Execution Contract (`G02` Surface)

Both `a32rt` and `ppc32rt` expose the same minimal primitives to `hl` (versioned header contract, zero shared linked cross-repo library):

1. **Lifecycle & Thread Contexts**: Create/clone/destroy guest 4 GiB VM arena and per-thread architectural CPU state (`GPR`s, `FPR`s, `NEON`/`AltiVec` vectors, `CPSR`/`FPSCR` or `CR`/`XER`/`FPSCR`/`VRSAVE`).
2. **Checked Guest Memory Operations**: Map/unmap/protect 4 KiB guest pages (maintaining Soft-TLB & SMC `A32_PROT_WATCH` invariants), validated `copyin`/`copyout`, and explicit I-cache / AOT invalidation ranges.
3. **Run-Until-Exit Loop**: Step `interp` or `dbt` (or `--difftest`) until a typed guest exit:
   - `EXIT_TRAP` (`svc #0x80` / `svc #0x81` on ARMv7; `sc` `r0 < 0` Mach / `r0 >= 0` BSD / ultra-fast traps on PPC32),
   - `EXIT_FAULT` (precise guest VA, read/write/exec access kind, unaligned/protection vs. unmapped classification for `SIGBUS` / `SIGSEGV` / Mach `EXC_BAD_ACCESS`),
   - `EXIT_BKPT` / `EXIT_ILLEGAL` (`EXC_BREAKPOINT` / `EXC_BAD_INSTRUCTION`),
   - `EXIT_INTERRUPT` (async cancellation / pending signal delivery / quiescence).
4. **AOT Cache Isolation**: Personality/ABI tag mixed into the persistent AOT cache key so Linux ELF translations and `hl` Darwin Mach-O translations never collide.

## 3. Ownership Split Summary

| Subsystem | `a32rt` / `ppc32rt` | `hyper-linux` (`hl`) |
|---|---|---|
| Guest CPU, `interp`, AArch64 `dbt`, `--difftest`, Soft-TLB, AOT | **Owner** | Consumer via `G02` |
| Linux 32-bit ELF (`armhf`/`armel`, `ppc32`) | **Owner** | Auto-dispatches via `hl` |
| Mach-O / FAT admission, `dyld`, rebase/bind, commpage | — *(migrating out of `a32rt`)* | **Owner** (`armv7`/`armv7s` iOS & `ppc` Tiger/Leopard) |
| XNU BSD syscalls, Mach ports/MIG, `pthread`, `_sigtramp` | Register snapshot hooks only | **Owner** |
| Wine-style stub dylibs & native framework bundle loader | Optional guest-code trampoline bytes mapped into VM | **Owner** |
| X11, WindowServer, Quartz, Carbon, Cocoa, CoreAudio (`ppc-darwin-ui`) | **None** | **Owner** (`hl` worker) |
