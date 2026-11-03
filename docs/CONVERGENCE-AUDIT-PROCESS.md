# Multi-Agent Convergence Audit & Remediation Process (`astra` $\rightarrow$ `muse` $\rightarrow$ `fable`)

**Repository Family:** `zw3rk/rt-series` (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `rvrt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`, and `rt-series`)  
**Status:** Authoritative Engineering Process Specification  
**Copyright:** 2026 Moritz Angermann `<moritz@zw3rk.com>`, zw3rk pte. ltd. (`Apache-2.0`)

---

## 1. Overview & Tri-Model Architecture

Across a family of 10 standalone user-mode binary translators (~300,000 lines of Curated C11 and AArch64 assembly) plus the `rt-series` qualification harness, single-pass reviews and single-model fix loops either miss deep architectural corner cases or exhaust coordinator context tokens.

To achieve high-assurance convergence across all 11 repositories simultaneously while conserving coordinator tokens, the `rt-series` audit-and-remediation pipeline separates **Static Hunting**, **Cross-Runtime Clustering**, **Surgical Code Remediation**, and **Independent Verification** across distinct tools and models executing in 11 concurrent lanes:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Phase A: Static Hunting (11 Concurrent Read-Only Lanes)                     │
│   Model: gpt-6-astra (codex exec -m gpt-6-astra --sandbox read-only)        │
│   Output: lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Phase B: Cross-Runtime Clustering & Checklist Aggregation                   │
│   Owner: Coordinator on rt-series master                                    │
│   Action: Synthesize X-R<N>-* cross-cutting clusters across all 10 ISAs     │
│           and populate Part I of DEFECTS.md (archiving prior rounds).       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Phase C: Surgical Remediation (11 Concurrent Worker Lanes)                  │
│   Engine: muse (muse exec --yolo --parallel-tool-calls)                     │
│   Gates: Curated C11 (-Werror=vla -pedantic -Wall -Wextra -Werror),         │
│          <= 900 lines/file (make check-line-limits), 0 .c includes,         │
│          make test, and cross-runtime sibling check.                        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Phase D: Independent Post-Remediation Verification (11 Concurrent Lanes)    │
│   Model: claude-fable-5-1 (claude -p --model claude-fable-5-1 --effort high)│
│   Input: Exact remediation commit(s) + original astra report + DEFECTS.md   │
│   Output: lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-fable.md              │
│           (Per-item verdict: VERIFIED | PARTIAL | REGRESSION)               │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Phase E: Post-Fable Surgical Follow-Up & Round Closeout                     │
│   Engine: muse exec on any repository with PARTIAL or REGRESSION items      │
│   Closeout: Mark all Round-<N> checkboxes [x] in DEFECTS.md and commit.     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Optimization Dynamics: Why Fixed-Step Loops Oscillate & How Step-Size Annealing Converges

### 2.1 The Parabola Oscillation Problem

In an iterative audit-and-fix process, the net change in true defects $D_{t+1} - D_t$ at round $t$ is governed by two competing terms:

$$\Delta D_t = -(\text{true bugs fixed in round } t) + (\text{new edge cases introduced by edits in round } t)$$

This behaves identically to numerical optimization (gradient descent) on a parabola:

1. **Far from the Minimum (Early Rounds, e.g., Rounds 1–3):**
   - True bugs are plentiful and high-amplitude (`187` in Round 1 $\rightarrow$ `145` in Round 2 $\rightarrow$ `85` in Round 3).
   - Even if code edits carry a 10–15% perturbation side-effect rate, fixing 180 real defects while introducing 20 second-order edge cases produces a large net downward step toward the minimum.
2. **Near the Valley Floor (Later Rounds):**
   - If the static auditor (`gpt-6-astra`) is implicitly pressured to always return ~8–10 findings per repository—including subjective `DRY`, `YAGNI`, and `CLEAN` refactorings—two failure modes emerge:
     - **High-Perturbation Refactoring Under Hard Line Limits ($\le 900$ lines):** Consolidating helpers for `DRY` or splitting/compacting files to stay under 900 lines touches dozens of call sites across C11, JIT emitters, signal handlers, and lock hierarchies. Every line touched carries a non-zero perturbation risk.
     - **Fix-Induced Second-Order Bugs:** Adding a new mutex to fix a cache race (`P32-R6-1`) introduces a `fork()` deadlock if `pthread_atfork` (`proc_fork_prepare/parent/child`) is not updated at the same time; widening a flag mask to fix `O_DSYNC` (`S32-R5-7`) collides with `SP_O_ASYNC` (`S32-R6-8`) in the next round.
   - Once true remaining defects in a broad skim drop to ~3–4 per repository while 8–10 invasive edits introduce ~3–4 new edge cases, $\Delta D_t \approx 0$. The loop bounces back and forth between the two walls of the parabola without ever hitting the minimum.

### 2.2 Step-Size Annealing (How to Actually Hit the Minimum)

To converge to the bottom of the parabola instead of oscillating across it, the process **anneals the step size** as the codebase matures:

1. **Drop `DRY` / `YAGNI` / `CLEAN` & Cosmetic Churn (Zero Structural Perturbation):**
   - In convergence rounds (and strictly in Rounds 10+), only touch code for **concrete, demonstrable behavioral bugs** (wrong instruction result, memory corruption, race/deadlock, wrong syscall/signal ABI behavior).
   - If code is functionally correct and passes Curated C11 + `make check-line-limits` ($\le 900$ lines), **do not refactor it for style or `DRY`**.
2. **Allow `0` Findings (Stop Quota-Filling):**
   - Explicitly instruct `gpt-6-astra` that returning **`0` findings** (`No concrete behavioral defects found in this subsystem`) is the expected, desired outcome once a module converges, rather than scraping the bottom of the barrel for speculative nits.
3. **Narrow, Orthogonal Subsystem Deep-Dives + Minimal Surgical Diffs:**
   - Instead of asking the auditor to skim all ~40 files (~30,000 LOC) in one pass, partition the codebase into **6 orthogonal subsystem deep-dives** (~4–8 files per round) so the auditor reads 100% of every file in that subsystem end-to-end.
   - Require `muse exec` to apply the **smallest possible surgical diff** (preserving existing control flow, lock order, and line budgets) and verify every diff with `claude-fable-5-1` in the same round. This drives the perturbation term near zero so $D_t \to 0$.

---

## 3. Two-Regime Execution Roadmap (Start to Finish)

### Regime I — Broad Whole-Repository Sweep Rounds (Rounds 1–6)

Used when bringing up new translators or after major architectural migrations (such as the Wave-U 5-Module & Dual-Backend Unification):

- **Scope:** Whole repository (`src/`, `include/`, `tests/`).
- **Categories Audited:** `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` across `BUG`, `DEFECT`, `SECURITY`, Curated-C11 compliance, and intra-repo `DRY`/`YAGNI`/`CLEAN`.
- **Historical Yield Across the 11 `rt-series` Repositories:**
  - **Round 1:** `187` per-repo items + `8` cross-runtime clusters = `195` checkboxes (eliminated all `Critical` defects, unity `.c` includes, and $>900$-line files).
  - **Round 2:** `145` per-repo items + `8` clusters = `153` checkboxes.
  - **Round 3:** `85` per-repo items + `6` clusters = `91` checkboxes.
  - **Round 4:** `125` per-repo items + `8` clusters = `133` checkboxes (expanded cross-runtime sibling checks).
  - **Round 5:** `109` per-repo items + `7` clusters = `116` checkboxes.
  - **Round 6:** `88` per-repo items + `6` clusters = `94` checkboxes.
  - **Regime I Total:** **`651 + 88 = 739` per-repo items + `43` cross-runtime clusters = `782 / 782` verified items**.

### Regime II — Orthogonal Subsystem Deep-Dives with Step-Size Annealing (Rounds 7–12+)

Once whole-repo sweeps reach steady state, execution switches to **6 orthogonal subsystem deep-dives**, partitioning the 5 unified translator modules so every line of C11 and AArch64 assembly is read end-to-end:

| Round | Deep-Dive Subsystem | Target Files in `<arch>rt` | Target Files in `rt-series` | Step-Size Policy |
|---:|---|---|---|---|
| **Round 7** | **1. ISA Interpreter & CPU State/Trap Semantics** | `src/interp/*`, CPU/FPU/vector state & trap headers in `src/` & `include/` | `lode/ISA-TRAP-AND-ABI-MATRIX.md`, `tests/p3_torture.c`, `tests/qual/*` | High/Medium behavioral ISA/FPU/trap bugs; surgical fixes |
| **Round 8** | **2. AArch64 DBT / JIT Emitters, Code Cache, IBTC/RAS & Dispatcher** | `src/dbt/*`, `src/*a64_emit*`, `src/jit/*`, `src/trampoline*.S` | JIT/SMC/cross-page/loop torture in `tests/p3_torture.c`, `tools/*` | High/Medium JIT encoding, register aliasing, W^X, & cache coherence bugs |
| **Round 9** | **3. Virtual Memory (`src/vm/*`), Soft-TLB, Checked Copy & ELF/Auxv Loader** | `src/vm/*`, `src/rt32/vm*`, `src/memory/*`, `src/loader/*`, `src/*elf*`, `src/*stack*`, `src/main.c` | `docs/HOST-CONTRACT.md`, `include/a32host.h`, VM torture tests | High/Medium `mmap`/`mprotect`/COW/Soft-TLB/copyin-out/loader bugs |
| **Round 10** | **4. Threading, `clone`/`fork`/`execve`, `atfork` Locks & Futex / Scheduler** | `src/os/threads*`, `src/os/clone*`, `src/os/proc*`, `src/os/fork*`, `src/os/family*`, `src/os/sched*`, `src/linux/futex*` | Thread/futex/fork/execve qualification tests | **Annealed (Rounds 10+):** Concrete behavioral bugs only; 0 `DRY`/`YAGNI`/`CLEAN` churn; `0` findings encouraged if clean |
| **Round 11** | **5. Signal Multiplexing, Host Fault Recovery, `sigaltstack` & RT Frames** | `src/os/signals*`, `src/os/sig*`, `src/os/hostfault*`, `src/os/safe_syscall*.S`, `src/linux/signal*` | Signal frame, `sigaltstack`, fault-recovery, and `EINTR` tests | **Annealed (Rounds 10+):** Concrete behavioral bugs only; 0 `DRY`/`YAGNI`/`CLEAN` churn; `0` findings encouraged if clean |
| **Round 12** | **6. Syscall ABI, Struct/Flag/Errno Marshaling, `/proc/self` & Backends** | `src/os/syscalls*`, `src/os/sys_*`, `src/os/procfs*`, `src/os/backend_*`, `src/os/host*`, `src/linux/*` | Syscall/fs/socket/poll qualification & harness scripts | **Annealed (Rounds 10+):** Concrete behavioral bugs only; 0 `DRY`/`YAGNI`/`CLEAN` churn; `0` findings encouraged if clean |

---

## 4. Step-by-Step Operational Playbook

### Phase A: Concurrent `gpt-6-astra` Static Hunting

Launch 11 concurrent read-only `codex exec` tasks (one per repository), bounded by `timeout --kill-after=30s 900s`, with stdin redirected from `< /dev/null` and wrapped in a 3-attempt retry loop to handle transient API capacity spikes:

```sh
for attempt in 1 2 3; do
  cd /Users/angerman/Projects/zw3rk/<repo> && \
  timeout --kill-after=30s 900s codex exec -m gpt-6-astra --sandbox read-only \
    "<Subsystem Deep-Dive Prompt>" \
    < /dev/null > /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md
  if [ -s /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md ] && \
     [ $(wc -l < /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md) -gt 5 ]; then
    exit 0
  fi
  sleep 15
done
exit 1
```

**Mandatory Prompt Clauses for Annealed Rounds (Rounds 10+):**
1. *"Only report concrete, demonstrable behavioral bugs (`BUG` / `DEFECT` / `SECURITY` causing wrong execution results, memory corruption, races/deadlocks, or wrong guest ABI behavior). Do NOT report `DRY`, `YAGNI`, `CLEAN`, or stylistic refactorings."*
2. *"Returning `0 findings` (`No concrete behavioral defects found`) is the expected and desired outcome if the target subsystem files are correct. Do NOT pad or invent low-severity items to fill a quota."*

---

### Phase B: Cross-Runtime Clustering & `DEFECTS.md` Aggregation

1. Read all 11 `lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md` reports.
2. Group related defects into **Cross-Runtime Defect Clusters (`X-R<N>-1..K`)** at the top of `DEFECTS.md`. Whenever `astra` finds a subtle bug in one translator (e.g., big-endian `FUTEX_WAKE_OP` bitfields, `F_SETFL` flag clobbering, `s_cache_lock` missing from `pthread_atfork`, or `statx` timestamp signedness), link the sibling translators so `muse` checks whether the same bug exists in the sibling codebases.
3. Archive the completed prior round into `Part II` of `DEFECTS.md` and commit `DEFECTS.md` + `lode/reviews/YYYY-MM-DD-defects-r<N>-*-astra.md` on `rt-series` `master`.

---

### Phase C: Concurrent `muse exec` Surgical Remediation

Launch `muse exec --yolo --parallel-tool-calls` across all repositories that have Round-`<N>` findings:

```sh
cd /Users/angerman/Projects/zw3rk/<repo> && \
timeout --kill-after=30s 1200s muse exec --yolo --parallel-tool-calls \
  'Remediate all Round-<N> findings (<PREFIX>-R<N>-1..M) for <repo> documented in /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md and /Users/angerman/Projects/zw3rk/rt-series/DEFECTS.md.
   Rules:
   1. Make the smallest possible surgical diffs that fix each concrete behavioral defect without perturbing unrelated code or lock hierarchies.
   2. Enforce Curated C11 (-std=c11 -Werror=vla -pedantic -Wall -Wextra -Werror), zero .c unity includes, and <= 900 lines per .c/.h/.S file (make check-line-limits).
   3. Run make check-line-limits && make test and ensure both pass with 0 warnings/errors.
   4. Stage only your modified files and commit on master with --author="Moritz Angermann <moritz@zw3rk.com>" and message "<repo>: remediate Round-<N> defects (<PREFIX>-R<N>-1..M)". Never include AI or model names in commits.' \
  < /dev/null
```

---

### Phase D: Concurrent `claude-fable-5-1` Verification Reviews

Once `muse exec` commits on `<repo>` `master`, run `claude-fable-5-1` to independently verify the commit against the `astra` report:

```sh
cd /Users/angerman/Projects/zw3rk/<repo> && \
timeout --kill-after=30s 900s claude -p --model claude-fable-5-1 --effort high \
  "Review the latest Round-<N> remediation commit HEAD in /Users/angerman/Projects/zw3rk/<repo> against /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-astra.md and /Users/angerman/Projects/zw3rk/rt-series/DEFECTS.md.
   Classify each item as VERIFIED, PARTIAL, or REGRESSION, and check whether the surgical diff introduced any second-order edge cases (e.g. fork lock ordering, sign-extension, line limits, or unguarded fault paths). Output a concise markdown report." \
  < /dev/null > /Users/angerman/Projects/zw3rk/rt-series/lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-fable.md
```

---

### Phase E: Post-`fable` Surgical Follow-Up & Round Closeout

1. Read every `lode/reviews/YYYY-MM-DD-defects-r<N>-<repo>-fable.md` report.
2. For any repository where `fable` marked an item `PARTIAL` or `REGRESSION` (or identified a second-order hazard introduced by the fix), run a focused `muse exec` follow-up commit (`<repo>: Round-<N> post-fable follow-up (...)`) and re-verify `make check-line-limits && make test`.
3. Confirm all 11 repositories are clean (`git status --porcelain` is empty) and pass `make check-line-limits`.
4. Mark all Round-`<N>` checkboxes (`- [x]`) in `DEFECTS.md` and commit `DEFECTS.md` + `lode/reviews/YYYY-MM-DD-defects-r<N>-*-fable.md` on `rt-series` `master`.

---

## 5. Operational Safeguards & Lessons Learned

1. **Always Redirect `< /dev/null` on Non-Interactive Subprocesses:**
   - Both `codex exec` and `claude -p` check whether `stdin` is a pipe and will hang indefinitely printing `Reading additional input from stdin...` if launched in a background subshell without `< /dev/null`.
2. **Single-Quote `muse exec` Prompts:**
   - Prompts referencing C identifiers in markdown backticks (e.g., `` `s_cache_lock` ``) will trigger `zsh` command substitution if double-quoted. Always single-quote `muse exec '...'` prompts or read the prompt from a file.
3. **Never Exceed the 900-Line Ceiling (`make check-line-limits`):**
   - Every `.c`, `.h`, and `.S` file across all 10 translators must stay $\le 900$ lines with zero `#include "*.c"` unity includes. Run `make check-line-limits` before every commit.
4. **Watchdog & Process Hygiene:**
   - Every `codex exec`, `muse exec`, `claude -p`, build, and test command must be wrapped in `timeout --kill-after=30s <duration>`. Periodically inspect `ps aux | grep -E "codex|muse|claude|qemu"` to ensure no orphaned processes remain.
5. **Standalone Repository Invariant (`AGENTS.md` §2.1):**
   - Never extract a cross-repository shared C library (`librt32` / `librt64`). Cross-runtime bug clusters (`X-R<N>-*`) share knowledge and test patterns, while each `<arch>rt` repository remains 100% standalone.

---

## 6. Empirical Convergence Trajectory Across Rounds 1–12

The table below records the actual defect counts remediated and verified across all 11 repositories (`a32rt`, `i686rt`, `mips32rt`, `ppc32rt`, `sparc32rt`, `rvrt`, `loongarch64rt`, `ppc64rt`, `mips64rt`, `sparc64rt`, `rt-series`), demonstrating the parabola-floor plateau in Rounds 3–6, the orthogonal subsystem deep-dives in Rounds 7–9, and the collapse toward `0` once Step-Size Annealing was applied in Rounds 10–12:

| Round | Regime & Scope | Total Items Remediated & Verified | Repositories Converged to `0` |
|---:|---|---:|---:|
| **Round 1** | Regime I — Broad Whole-Repo Sweep 1 | `187 / 187` | `0 / 11` |
| **Round 2** | Regime I — Broad Whole-Repo Sweep 2 | `145 / 145` | `0 / 11` |
| **Round 3** | Regime I — Broad Whole-Repo Sweep 3 | `85 / 85` | `0 / 11` |
| **Round 4** | Regime I — Broad Whole-Repo Sweep 4 (Plateau) | `91 / 91` | `0 / 11` |
| **Round 5** | Regime I — Broad Whole-Repo Sweep 5 (Plateau) | `91 / 91` | `0 / 11` |
| **Round 6** | Regime I — Broad Whole-Repo Sweep 6 (Plateau) | `87 / 87` | `0 / 11` |
| **Round 7** | Regime II — Deep-Dive 1 of 6: ISA Interpreter & Decode (`src/interp/*`) | `277 / 277` | `0 / 11` |
| **Round 8** | Regime II — Deep-Dive 2 of 6: AArch64 DBT, Chaining, IBTC/RAS & AOT Cache (`src/dbt/*`) | `55 / 55` | `1 / 11` (`rvrt`) |
| **Round 9** | Regime II — Deep-Dive 3 of 6: Virtual Memory, Soft-TLB, Checked Copy, `fork()` COW & ELF Loader (`src/vm/*`) | `96 / 96` | `0 / 11` |
| **Round 10** | **Regime III (Step-Size Annealed)** — Deep-Dive 4 of 6: Threading, `clone`/`fork`/`execve`, `atfork` Locks & Futex | **`19 / 19`** | **`6 / 11`** (`a32rt`, `mips32rt`, `sparc32rt`, `rvrt`, `ppc64rt`, `rt-series`) |
| **Round 11** | **Regime III (Step-Size Annealed)** — Deep-Dive 5 of 6: Signal Multiplexing, Host Fault Recovery & RT Signal Frames | **`24 / 24`** | **`4 / 11`** (`a32rt`, `rvrt`, `loongarch64rt`, `ppc64rt`; `3` more had only `1` item) |
| **Round 12** | **Regime III (Step-Size Annealed)** — Deep-Dive 6 of 6: Syscall ABI, Struct/Flag/Errno Marshaling, `/proc/self` & Backends | **`23 / 23`** | **`2 / 11`** (`rvrt`, `rt-series`) |
| **Total** | **All 12 Rounds (6 Broad Sweeps + 6 Orthogonal Subsystem Deep-Dives)** | **`1,180 / 1,180` (`1,234` incl. clusters)** | **100% Verified Across All 11 Repositories** |
