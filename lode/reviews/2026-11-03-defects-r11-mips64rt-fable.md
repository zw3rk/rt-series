All evidence gathered. Here's the review:

---

## M64-R11-1 — **VERIFIED**

**Defect**: N32BE `sigset_t` marshaled as 2×u64 instead of 4×u32, swapping each 32-bit half on big-endian and causing signals to be delivered while nominally blocked.

**Four sites identified in report, all fixed:**

| Site | Report ref | Fix location | Pattern |
|---|---|---|---|
| `sigprocmask` read | sigact.c:336 | `sigact.c:338-345` | `getn(p, 4, be) \| (getn(p+4, 4, be) << 32)` |
| `sigprocmask` old-set | sigact.c:354 | `sigact.c:363-371` | `putn(img, (uint32_t)cur0, 4, be)` × 4 |
| `pending` report | sigact.c:556 | `sigact.c:574-582` | `putn(img, (uint32_t)w0, 4, be)` × 4 |
| `suspend` mask install | sigact.c:607 | `sigact.c:634-644` | `getn(p, 4, be) \| (getn(p+4, 4, be) << 32)` |

**Correctness of the fix:**

- `getn` returns `uint64_t` (`sigact.c:55`), so `getn(p+4, 4, be) << 32` is a well-defined 64-bit shift — no truncation.
- `putn` takes `uint64_t v` (`sigact.c:54`); `(uint32_t)cur0` zero-extends back to `uint64_t` with upper bits cleared — equivalent to the `& UINT64_C(0xffffffff)` mask used in the pre-existing `rt_sigaction` N32 path at lines 279-283.
- The N32 branch pattern is identical to the pre-existing `rt_sigaction` read pattern at `sigact.c:247-250`, confirming internal consistency.
- N64 paths are untouched — `getn(p, 8, be)` / `putn(img, v, 8, be)` remain correct for 2×u64 encoding.
- All `n32` variables are initialized as `ctx->is_n32 != 0U` (boolean coercion, no UB).

**No missed sites**: Grep of all `getn`/`putn` calls in `sigact.c` confirms the remaining call sites are `rt_sigaction` (already N32-aware), `sigaltstack` (marshals `stack_t`, not `sigset_t`), and `sigqueueinfo` (marshals `siginfo_t` fields) — none require the sigset 4×u32 split.

## Newly Introduced Bugs

**None found.** The diff is purely additive `if (n32) { ... } else { <original code> }` branches — the `else` paths are byte-identical to the pre-patch code. No control-flow, allocation, or locking changes.

**Minor style inconsistency** (not a bug): The new `putn` calls use `(uint32_t)x` for masking while the pre-existing `rt_sigaction` path at lines 279-283 uses `x & UINT64_C(0xffffffff)`. Semantically identical; no behavioral difference.

## Curated C11 Compliance

| Check | Result |
|---|---|
| File size (`sigact.c`) | **762 lines** <= 900 |
| VLAs | None (grep clean) |
| `.c` includes | None |
| `sprintf`/`strcpy`/`strcat` | None in diff |
| `x18` usage | N/A (no assembly in diff) |

**Verdict: M64-R11-1 is VERIFIED — all four defect sites remediated with correct 4×u32 N32 marshaling, no regressions, C11-compliant.**
