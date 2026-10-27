**RESOLVED.** Confirmed `master` at `5f7f285`.

The commit restores `a64_emit_cbz_x_placeholder(b, true, A64_TMP2)` at [emit_mem.c:498](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:498). It checks the full 64-bit XOR from line 497, so upper-half epoch mismatches reach the SC failure path through the matching X-width patch at [emit_mem.c:511](/Users/angerman/Projects/zw3rk/mips32rt/src/dbt/emit_mem.c:511).

Static inspection only; no modifications, builds, tests, or Docker.

Verdict: PASS