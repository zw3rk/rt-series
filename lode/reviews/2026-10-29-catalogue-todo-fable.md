# Review: `docs/CATALOGUE-TODO.md` — `fable` (`claude-fable-5-1`)

## Part 1: Runner Unification, Smoke vs `guest-payload` & P0–P2 Gates

Critique of `docs/CATALOGUE-TODO.md` Sections 1, 2, and 4 (P0 to P2):

**Runner unification**

- **CRITICAL.** P0 says "same runner" but names no owner or interface. Each repo already has a `parity_suite.sh` with a different row schema. Fix: freeze a `parity_contract.sh` row format in `rt-series` (case, engine, oracle, stdout, stderr, exit, siginfo) and have each repo's `parity_suite.sh` emit it. The smoke branch then only aggregates.
- **HIGH.** "A variant that was not built fails the run" collides with Darwin hosts that cannot build Docker-only variants. Fix: separate `GAP` (host cannot run) from `FAIL`, but make `GAP` fail only on the Linux CI leg where every variant is buildable.

**`smoke` vs `guest-payload`**

- **HIGH.** Both modes live in one script with different exit semantics. Smoke fails on `GAP`, payload prints `ALL_OK` with `pass=0`. Fix: split into two scripts, give both the same three outcomes, and make `pass < expected_cases` a failure in payload.
- **MEDIUM.** Payload runs only by hand inside a guest shell, so P2 fixes are never exercised by CI. Fix: add a `smoke` row per repo that launches payload under `--dbt` against the pinned sysroot manifest.

**Host and oracle contracts**

- **CRITICAL.** P0 asks for Linux, Darwin, and `hl` legs but defines the oracle as `qemu-<arch>`, which only exists on Linux. On Darwin the `sparc64rt` row already degrades to `GAP`. Fix: record the Linux QEMU baseline once per fixture as a golden file, and compare Darwin and `hl` against that golden, not against a live oracle.
- **HIGH.** The `hl` leg uses 16 KiB pages and `A32H_CAP_ICACHE_TRAP_IALLU`, so stderr text from the kernel loader differs. Fix: normalise stderr with a per-host filter before diffing.

**`si_addr` and `si_code`**

- **HIGH.** QEMU linux-user does not report `si_addr` faithfully on every ISA, and Class A guests see a window-relative address. Fix: compare `si_code` exactly, compare `si_addr` masked to the guest VA width, and let a fixture declare `si_addr=unspecified` where QEMU is known wrong.

**AOT reload**

- **HIGH.** P1 compares a reloaded image to a cold `--dbt` run by output only. Identical output does not prove the image was used. Fix: require a translator counter (blocks translated equals zero) and a hash of the loaded code region in the row.

**CI runtime budgets**

- **CRITICAL.** The 360 s wrapper cannot hold ten repos when `mips64rt` alone needs 480 s and `rvrt`'s full check is thirty minutes. Fix: per-repo budget in the manifest, outer timeout equals the sum plus margin, and report elapsed per row so the budget is measured rather than guessed.
- **MEDIUM.** No budget tier for `smoke` versus nightly. Fix: tag each row `smoke` or `nightly` in the contract and let the aggregator select by tag.

---

## Part 2: Grind Suites (§3), Feature Coverage (P3–P4) & Missing Edge Cases

Here is the critique.

## Section 3 — Grind suites

- **CRITICAL — the oracle does not exist on Darwin.** `qemu-<arch>` linux-user builds only on Linux hosts, yet Section 3 and P4 demand an exit-status or stdout differential "on both engines and all three hosts". Fix: generate golden `stdout`/`stderr`/exit/`si_code` bundles once on a Linux oracle job, commit them per ABI under `tests/golden/<abi>/`, and compare against the bundle on Darwin and `hl`. Only Linux CI runs live QEMU.
- **CRITICAL — `stress-ng` exit status is not a pass rule.** It exits 0 when a stressor is skipped, unimplemented, or returns `EOPNOTSUPP`. Half the allowlist (`procfs`, `sigfd`, `eventfd`, `epoll`, `timer`, `getdent`, `dentry`, `vma`, `icache`, `tlb`) depends on backend emulation that `backend_darwin.c` lacks or synthesises. Fix: run with `--verify --yaml`, diff per-stressor status, and keep a per-host expected-fail manifest, not an open-ended skip.
- **HIGH — `tests/tcg/multiarch` needs page-size parameters.** `test-mmap` and `prot-none` take the page size; `float_*` need per-arch `.ref` files. Fix: vendor the `.ref` files, run `test-mmap 4096` under Darwin, and add an explicit 4 KiB-`mprotect`-inside-16 KiB-host-page case, which is exactly what the Soft-TLB must fake.
- **HIGH — LTP and `libc-test` cannot be matched to one QEMU pass set.** `mremap`, `MAP_FIXED_NOREPLACE`, `statx`, `getdents64` cookies, and `MAP_SHARED` + `ftruncate` past EOF differ between Linux, Darwin, and `hl` kernels. Fix: three recorded pass sets keyed by host and Provider; a translator must match its host's set, and the diff between sets is a tracked document.
- **MEDIUM — TestFloat and Csmith portability.** TestFloat needs host `testfloat_gen` piped into a guest `testfloat_ver`, otherwise it runs for days. Csmith on `i686` produces legitimate `-O0` vs `-O2` deltas from x87 excess precision. Fix: compare each binary only against the same binary under the oracle, never across optimisation levels. Bound every program with `timeout`.

## Section 4 — P3–P4 gaps

- **HIGH — No Soft-TLB shootdown case.** P3 covers quiesce for SMC only. Add: thread B `munmap`/`mprotect` while thread A holds a cached TLB entry, and child TLB invalidation after `fork` under Provider A and Provider B COW, with both parent and child writing a translated page.
- **HIGH — FPR-cache signal frames.** A handler must see live FPRs that are still in host registers, and a handler-modified FPR must survive `sigreturn`. Add this to the P3 signal row for every P13-cached translator.
- **MEDIUM — Delay-slot and window frames are listed but underspecified.** Add: `sigreturn` resuming into a delay slot, SPARC signal during `save` overflow with pending `FLUSHW`, and `si_addr` for an annulled slot.
- **MEDIUM — 16 KiB host cases.** Add `AT_PAGESZ`/`sysconf` returning 4096, `brk` growth in 4 KiB steps, `MADV_DONTNEED` zero-fill at 4 KiB granularity, and a guest JIT (LuaJIT) flipping RW to RX inside one host page.
- **MEDIUM — Matrix cost.** Nightly suites × 14 ABIs × 2 engines × 3 hosts is unbounded. Run the full matrix on Linux only; Darwin and `hl` run one ABI per repo nightly, all weekly.
