#!/bin/sh
# tools/grind_suites.sh — Tier N (nightly) / Tier W (weekly) payload-heavy suite runners.
#
# Sourced by tools/run_grind.sh near the top (after remote_bench_common.sh).
# Holds the payload-builder / differential / soak suite functions so that both
# run_grind.sh and this file stay well below the 900-line ceiling:
#   run_testfloat_one_engine, run_testfloat_suite, run_builtins_suite,
#   run_libc_ltp_suite, run_ltp_one_binary, run_lmbench_suite,
#   run_differential_binary, run_upstream_adapter_check, run_weekly_soak.
# Zero behavioral change: all function names, variables, CLI flags, and exit
# codes are preserved verbatim from run_grind.sh.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0
# Run one TestFloat engine pass over the shared operand vectors and report
# it under its own engine label. The guest operation runner executes the
# vectors under the engine wrapper; host testfloat_ver then checks the
# runner's result lines for $_op. Upstream (TestFloat-general.html 5)
# requires this middle program: generator SoftFloat expectations must
# never be fed to the verifier directly, since that tests SoftFloat
# against itself instead of the translated guest FP instructions. Uses
# the caller's $_ver/$_op/$_rm/$_vec globals and a per-engine
# /tmp/grind_testfloat_<label> log; the runner result file must hold a
# positive verified case count or the engine fails. The runner exit status
# and captured stdout are preserved for the shared dual-engine comparison
# in run_testfloat_suite (no second execution of $TESTFLOAT_RUNNER).
run_testfloat_one_engine() {
    _tfo_label="$1"
    _tfo_wrap="$2"
    _tfo_res="/tmp/grind_testfloat_res_${CURRENT_ARCH}_${_tfo_label}_$$"
    _tfo_keep="/tmp/grind_testfloat_kept_${CURRENT_ARCH}_${_tfo_label}_$$"
    _tfo_rcfile="/tmp/grind_testfloat_rc_${CURRENT_ARCH}_${_tfo_label}_$$"
    _tfo_log="/tmp/grind_testfloat_${_tfo_label}_$$.log"
    rm -f "$_tfo_res" "$_tfo_keep" "$_tfo_rcfile" "$_tfo_log"
    if [ ! -s "$_vec" ]; then
        grind_fail "$_tfo_label" "empty generator vectors for '$_op'"
        return 0
    fi
    if [ -n "$_tfo_wrap" ]; then
        if grind_run_guest 600 "$_tfo_wrap" "$TESTFLOAT_RUNNER" <"$_vec" >"$_tfo_res" 2>"$_tfo_log"; then
            _tfo_rc=0
        else
            _tfo_rc=$?
        fi
    else
        if timeout --kill-after=30s 600s "$TESTFLOAT_RUNNER" <"$_vec" >"$_tfo_res" 2>"$_tfo_log"; then
            _tfo_rc=0
        else
            _tfo_rc=$?
        fi
    fi
    # Preserve the runner exit status and captured stdout for the shared
    # dual-engine comparison below; run_testfloat_suite cleans them up.
    printf '%s' "$_tfo_rc" > "$_tfo_rcfile"
    cp "$_tfo_res" "$_tfo_keep" 2>/dev/null || true
    if [ "$_tfo_rc" -ne 0 ]; then
        grind_fail "$_tfo_label" "guest runner exited non-zero (rc=$_tfo_rc, see $_tfo_log)"
        return 0
    fi
    _tfo_cases="$(wc -l <"$_tfo_res" 2>/dev/null | tr -d '[:space:]')"
    case "$_tfo_cases" in
        '' | *[!0-9]* | 0)
            grind_fail "$_tfo_label" "runner produced no result cases for '$_op' (positive verified case count required)"
            return 0
            ;;
    esac
    if timeout --kill-after=30s 600s "$_ver" "${TESTFLOAT_CHECK_FLAGS:--checkAll}" "-r${_rm}" "$_op" <"$_tfo_res" >>"$_tfo_log" 2>&1; then
        _tfo_rc=0
    else
        _tfo_rc=$?
    fi
    if [ "$_tfo_rc" -eq 0 ]; then
        # Clean verifier line is "In N tests, no errors found in ...":
        # require it, and keep it from matching the failure grep.
        if grep -qi 'no errors found' "$_tfo_log" && ! grep -Eqi '(^|[^o] )errors? found|fail|mismatch' "$_tfo_log"; then
            grind_pass "$_tfo_label" "'$_op' ($_rm): $_tfo_cases cases verified clean"
        else
            grind_fail "$_tfo_label" "verifier reported failures (see $_tfo_log)"
        fi
    else
        grind_fail "$_tfo_label" "verifier exited non-zero (rc=$_tfo_rc, see $_tfo_log)"
    fi
}

run_testfloat_suite() {
    echo "== Grind [$CURRENT_ARCH]: Berkeley TestFloat (host testfloat_gen <type> | guest runner | host testfloat_ver <function>, per-engine) =="
    _gen="${TESTFLOAT_GEN:-}"
    _ver="${TESTFLOAT_VER:-}"
    if [ -z "$_gen" ] || [ ! -x "$_gen" ]; then
        if command -v testfloat_gen >/dev/null 2>&1; then
            _gen="testfloat_gen"
        else
            grind_skip "testfloat" "TESTFLOAT_GEN not set (host testfloat_gen missing)"
            return 0
        fi
    fi
    if [ -z "$_ver" ]; then
        grind_skip "testfloat" "TESTFLOAT_VER not set (host testfloat_ver binary missing)"
        return 0
    fi
    if [ -z "${TESTFLOAT_RUNNER:-}" ]; then
        grind_skip "testfloat" "TESTFLOAT_RUNNER not set (guest FP executor required; refusing vacuous SoftFloat-vs-SoftFloat pass)"
        return 0
    fi
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "${GRIND_INTERP:-}" ] && [ -z "${GRIND_DBT:-}" ]; then
        grind_skip "testfloat" "translator wrapper missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    _op="${TESTFLOAT_OP:-f32_add}"
    _rm="${TESTFLOAT_ROUNDING:-near_even}"
    case "$_rm" in
        near_even | near_maxMag | minMag | min | max | odd) ;;
        *)
            grind_fail "testfloat" "invalid TESTFLOAT_ROUNDING '$_rm' (expected near_even|near_maxMag|minMag|min|max|odd)"
            return 0
            ;;
    esac
    _op_base="${_op%%_*}"
    case "$_op" in
        *_mulAdd) _nops=3 ;;
        *sqrt* | *roundToInt* | *_to_*) _nops=1 ;;
        *) _nops=2 ;;
    esac
    _type="${TESTFLOAT_TYPE:-${_op_base} ${_nops}}"
    # The guest runner contract: a single binary path (like TESTFLOAT_GEN)
    # that reads testfloat_gen operand lines on stdin, executes $_op on the
    # guest under rounding $_rm, and writes testfloat_ver result lines on
    # stdout. Op and rounding travel via TESTFLOAT_OP/TESTFLOAT_ROUNDING.
    TESTFLOAT_OP="$_op"
    TESTFLOAT_ROUNDING="$_rm"
    export TESTFLOAT_OP TESTFLOAT_ROUNDING
    _rounds="${TESTFLOAT_ROUNDS:-10000}"
    if [ "$TIER" = "weekly" ]; then _rounds="${TESTFLOAT_ROUNDS_WEEKLY:-$_rounds}"; fi
    case "$_rounds" in
        '' | *[!0-9]* | 0)
            grind_fail "testfloat" "TESTFLOAT_ROUNDS must be a positive integer"
            return 0
            ;;
    esac
    _vec="/tmp/grind_testfloat_vec_${CURRENT_ARCH}_$$"
    # shellcheck disable=SC2086
    if ! timeout --kill-after=30s 300s "$_gen" -n "$_rounds" $_type >"$_vec" 2>/tmp/grind_testfloat_$$.log; then
        grind_fail "testfloat" "testfloat_gen failed to produce vectors (see /tmp/grind_testfloat_$$.log)"
        rm -f "$_vec" /tmp/grind_testfloat_$$.log
        return 0
    fi
    # Feed the same generated vectors to both configured engines and report
    # their outcomes separately. Dual-engine qualification needs both; a job
    # with only one engine configured is explicitly labelled single-engine.
    if [ "$CURRENT_ARCH" = "host" ]; then
        run_testfloat_one_engine "testfloat" ""
    else
        if [ -n "${GRIND_INTERP:-}" ]; then
            run_testfloat_one_engine "testfloat-interp" "$GRIND_INTERP"
        else
            grind_skip "testfloat-interp" "GRIND_INTERP not configured for $CURRENT_ARCH ($BACKEND); single-engine run"
        fi
        if [ -n "${GRIND_DBT:-}" ]; then
            if [ "$GRIND_DBT" = "${GRIND_INTERP:-}" ]; then
                grind_skip "testfloat-dbt" "GRIND_DBT duplicates GRIND_INTERP (single-engine run)"
            else
                run_testfloat_one_engine "testfloat-dbt" "$GRIND_DBT"
            fi
        else
            grind_skip "testfloat-dbt" "GRIND_DBT not configured for $CURRENT_ARCH ($BACKEND); single-engine run"
        fi
    fi
    # Dual-engine cross-check reuses the saved runner exit statuses and
    # captured stdout from the testfloat-interp / testfloat-dbt runs above
    # (no second execution of $TESTFLOAT_RUNNER per engine).
    if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
        _tfc_i_rcf="/tmp/grind_testfloat_rc_${CURRENT_ARCH}_testfloat-interp_$$"
        _tfc_d_rcf="/tmp/grind_testfloat_rc_${CURRENT_ARCH}_testfloat-dbt_$$"
        _tfc_i_keep="/tmp/grind_testfloat_kept_${CURRENT_ARCH}_testfloat-interp_$$"
        _tfc_d_keep="/tmp/grind_testfloat_kept_${CURRENT_ARCH}_testfloat-dbt_$$"
        if [ -f "$_tfc_i_rcf" ] && [ -f "$_tfc_d_rcf" ] && [ -f "$_tfc_i_keep" ] && [ -f "$_tfc_d_keep" ]; then
            _tfc_i="$(cat "$_tfc_i_rcf")"
            _tfc_d="$(cat "$_tfc_d_rcf")"
            if [ "$_tfc_i" != "$_tfc_d" ]; then
                grind_fail "testfloat" "interp exit=$_tfc_i vs dbt exit=$_tfc_d on shared vectors"
            elif [ "$_tfc_i" != "0" ]; then
                grind_fail "testfloat" "runner exit=$_tfc_i on shared vectors (both engines agree)"
            elif ! cmp -s "$_tfc_i_keep" "$_tfc_d_keep"; then
                grind_fail "testfloat" "interp vs dbt runner output mismatch on shared vectors"
            else
                grind_pass "testfloat" "interp-vs-dbt runner outputs match on shared vectors"
            fi
        else
            grind_skip "testfloat" "interp-vs-dbt runner comparison skipped (an engine produced no saved output)"
        fi
    fi
    for _tfo_l in testfloat testfloat-interp testfloat-dbt; do
        rm -f "/tmp/grind_testfloat_res_${CURRENT_ARCH}_${_tfo_l}_$$" "/tmp/grind_testfloat_kept_${CURRENT_ARCH}_${_tfo_l}_$$" "/tmp/grind_testfloat_rc_${CURRENT_ARCH}_${_tfo_l}_$$" "/tmp/grind_testfloat_${_tfo_l}_$$.log"
    done
    rm -f "$_vec" /tmp/grind_testfloat_$$.log
}

run_builtins_suite() {
    echo "== Grind [$CURRENT_ARCH]: compiler-rt builtin ABI helpers =="
    _cc="${GRIND_CC:-}"
    if ! grind_has_compiler "$_cc"; then
        grind_skip "compiler-rt" "compiler '$_cc' for $CURRENT_ARCH not on PATH"
        return 0
    fi
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "${GRIND_INTERP:-}" ] && [ -z "${GRIND_DBT:-}" ]; then
        grind_skip "compiler-rt" "translator wrapper (GRIND_INTERP/GRIND_DBT) missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    _src="/tmp/grind_builtins_${CURRENT_ARCH}_$$.c"
    _bin="/tmp/grind_builtins_${CURRENT_ARCH}_$$"
    cat << 'EOF' > "$_src"
#include <stdio.h>
#include <stdint.h>
extern int32_t __divsi3(int32_t, int32_t);
extern int32_t __modsi3(int32_t, int32_t);
extern int64_t __divdi3(int64_t, int64_t);
extern int __mulosi4(int32_t, int32_t, int32_t *);
int main(void) {
    int fails = 0;
    /* Boundary patterns: never trigger C signed-division UB in the harness. */
    if (__divsi3((int32_t)0x80000000u, -1) != (int32_t)0x80000000u) fails++;
    if (__modsi3((int32_t)0x80000000u, -1) != 0) fails++;
    if (__divsi3(-7, 3) != -2) fails++;
    if (__modsi3(-7, 3) != -1) fails++;
    if (__divdi3((int64_t)0x8000000000000000ull, -1) != (int64_t)0x8000000000000000ull) fails++;
    {
        int32_t ov = 0;
        /* __mulosi4 returns the wrapped product; overflow flag via pointer. */
        int32_t prod = __mulosi4(1000000, 1000000, &ov);
        if (ov != 1 || prod != (int32_t)0xD4A51000u) fails++;
        ov = 0;
        prod = __mulosi4(100, 200, &ov);
        if (ov != 0 || prod != 20000) fails++;
    }
    if (fails != 0) { printf("BUILTINS_FAIL:%d\n", fails); return 1; }
    printf("BUILTINS_OK\n");
    return 0;
}
EOF
    if grind_run_compiler "$_cc" -std=c11 -O1 "$_src" -o "$_bin" -lm >/dev/null 2>&1; then :; else _br_cc_rc=$?
        rm -f "$_src" "$_bin"
        if [ "$_br_cc_rc" -eq 124 ] || [ "$_br_cc_rc" -eq 137 ]; then grind_fail "compiler-rt" "builtin probe compilation timed out with $_cc"; else grind_skip "compiler-rt" "builtin probe did not compile with $_cc"; fi
        return 0
    fi
    _wrap="${GRIND_INTERP:-${GRIND_DBT:-}}"
    if run_dual_or_single_guest 60 "compiler-rt" "builtins" "$_bin"; then
        if grep -q "BUILTINS_OK" /tmp/grind_dual_out_$$; then
            grind_pass "compiler-rt" "div/mod/mulosi boundary patterns OK (interp-vs-dbt match)"
        else
            grind_fail "compiler-rt" "unexpected output (see /tmp/grind_dual_out_$$)"
        fi
        rm -f /tmp/grind_dual_out_$$
    elif [ "$?" -eq 1 ]; then
        :
    elif [ -n "$_wrap" ]; then
        if grind_run_guest 60 "$_wrap" "$_bin" > /tmp/grind_builtins_out_$$ 2>&1; then
            _brc=0
        else
            _brc=$?
        fi
        if [ "$_brc" -eq 0 ]; then
            if grep -q "BUILTINS_OK" /tmp/grind_builtins_out_$$; then
                grind_pass "compiler-rt" "div/mod/mulosi boundary patterns OK"
            else
                grind_fail "compiler-rt" "unexpected output (see /tmp/grind_builtins_out_$$)"
            fi
        else
            grind_fail "compiler-rt" "builtin probe exit!=0 (see /tmp/grind_builtins_out_$$)"
        fi
    else
        if timeout --kill-after=10s 60s "$_bin" > /tmp/grind_builtins_out_$$ 2>&1; then
            _brc=0
        else
            _brc=$?
        fi
        if [ "$_brc" -eq 0 ]; then
            if grep -q "BUILTINS_OK" /tmp/grind_builtins_out_$$; then
                grind_pass "compiler-rt" "div/mod/mulosi boundary patterns OK"
            else
                grind_fail "compiler-rt" "unexpected output (see /tmp/grind_builtins_out_$$)"
            fi
        else
            grind_fail "compiler-rt" "builtin probe exit!=0 (see /tmp/grind_builtins_out_$$)"
        fi
    fi
    rm -f "$_src" "$_bin" /tmp/grind_builtins_out_$$ /tmp/grind_dual_out_$$
}

run_libc_ltp_suite() {
    echo "== Grind [$CURRENT_ARCH]: libc-test + LTP syscalls manifest =="
    _wrap="${GRIND_DBT:-${GRIND_INTERP:-}}"
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "$_wrap" ]; then
        grind_skip "libc-ltp" "translator wrapper missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    _manifest="${GRIND_LIBC_MANIFEST:-$ROOT_DIR/tests/grind_libc_ltp.manifest}"
    if [ -f "$_manifest" ]; then
        _mfail=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                ""|"#"*) continue ;;
            esac
            _bin="$(printf '%s' "$_line" | awk '{print $1}')"
            if [ -x "$_bin" ]; then
                if run_dual_or_single_guest 120 "libc-ltp" "$_bin" "$_bin"; then
                    cp /tmp/grind_dual_out_$$ /tmp/grind_libc_$$.log
                    grind_pass "libc-ltp" "$_bin (interp-vs-dbt match)"
                    rm -f /tmp/grind_dual_out_$$
                elif [ "$?" -eq 1 ]; then
                    _mfail=$((_mfail + 1))
                elif grind_run_guest 120 "$_wrap" "$_bin" >/tmp/grind_libc_$$.log 2>&1; then
                    grind_pass "libc-ltp" "$_bin"
                else
                    grind_fail "libc-ltp" "$_bin exit!=0"
                    _mfail=$((_mfail + 1))
                fi
            else
                grind_skip "libc-ltp" "$_bin not built"
            fi
        done < "$_manifest"
        rm -f /tmp/grind_libc_$$.log
        if [ "$_mfail" -gt 0 ]; then return 1; fi
        return 0
    fi
    _found=0
    if [ -n "${LIBC_TEST_DIR:-}" ] && [ -d "${LIBC_TEST_DIR:-}" ]; then _found=1; fi
    if [ "$_found" = "1" ]; then
        for _t in functional math pthread; do
            _b="$LIBC_TEST_DIR/bin/$_t"
            if [ -x "$_b" ]; then
                if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
                    if grind_run_guest 300 "$GRIND_INTERP" "$_b" >/tmp/grind_libc_i_$$ 2>&1; then _lci=0; else _lci=$?; fi
                    if grind_run_guest 300 "$GRIND_DBT" "$_b" >/tmp/grind_libc_d_$$ 2>&1; then _lcd=0; else _lcd=$?; fi
                    if [ "$_lci" -ne "$_lcd" ]; then grind_fail "libc-ltp" "libc-test $_t interp exit=$_lci vs dbt exit=$_lcd";
                    elif [ "$_lci" -ne 0 ]; then grind_fail "libc-ltp" "libc-test $_t exit=$_lci (both engines agree)";
                    elif ! cmp -s /tmp/grind_libc_i_$$ /tmp/grind_libc_d_$$; then grind_fail "libc-ltp" "libc-test $_t interp vs dbt output mismatch";
                    elif [ ! -s /tmp/grind_libc_i_$$ ]; then grind_fail "libc-ltp" "libc-test $_t empty output";
                    else grind_pass "libc-ltp" "libc-test $_t (interp-vs-dbt output match)"; fi
                    rm -f /tmp/grind_libc_i_$$ /tmp/grind_libc_d_$$
                elif grind_run_guest 300 "$_wrap" "$_b" >/tmp/grind_libc_$$.log 2>&1; then
                    if [ -s /tmp/grind_libc_$$.log ]; then grind_pass "libc-ltp" "libc-test $_t"; else grind_fail "libc-ltp" "libc-test $_t empty output"; fi
                else grind_fail "libc-ltp" "libc-test $_t exit!=0"; fi
            else
                grind_skip "libc-ltp" "libc-test $_t not built"
            fi
        done
        rm -f /tmp/grind_libc_$$.log
    else
        grind_skip "libc-ltp" "LIBC_TEST_DIR unset (expected: functional, math, pthread)"
        if [ -z "${LTP_DIR:-}" ]; then grind_skip "ltp" "LTP_DIR unset (point at LTP install)"; return 0; fi
    fi
    if [ -n "${LTP_DIR:-}" ] && [ -d "${LTP_DIR:-}" ]; then
        export LTPROOT="$LTP_DIR"; TMPDIR="${TMPDIR:-/tmp}"; export TMPDIR
        _ln=0
        if [ -n "${LTP_MANIFEST:-}" ] && [ -f "$LTP_MANIFEST" ]; then
            while IFS= read -r _lb || [ -n "$_lb" ]; do case "$_lb" in ""|"#"*) continue ;; *.sh) continue ;; esac; [ -x "$_lb" ] || continue; _ln=$((_ln+1)); if [ "$_ln" -gt 50 ]; then break; fi; run_ltp_one_binary "$_lb" "$_wrap"; done < "$LTP_MANIFEST"
        else
            for _lb in "$LTP_DIR/testcases/bin"/* "$LTP_DIR/bin"/* "$LTP_DIR/testcases/kernel/syscalls"/*/*; do case "$_lb" in *.sh) continue ;; esac; [ -f "$_lb" ] && [ -x "$_lb" ] || continue; _ln=$((_ln+1)); if [ "$_ln" -gt 50 ]; then break; fi; run_ltp_one_binary "$_lb" "$_wrap"; done
        fi
        rm -f /tmp/grind_ltp_$$.log
        if [ "$_ln" -eq 0 ]; then grind_fail "ltp" "LTP_DIR=$LTP_DIR yielded 0 binaries (check LTP install or LTP_MANIFEST)"; fi
    else
        grind_skip "ltp" "LTP_DIR unset (point at LTP install for syscall binaries)"
    fi
}

# Run one LTP syscall binary under both engines (dual-engine exit match)
# or the single configured wrapper, sharing one /tmp/grind_ltp log.
run_ltp_one_binary() {
    _lob_bin="$1"
    _lob_wrap="$2"
    if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
        if grind_run_guest 120 "$GRIND_INTERP" "$_lob_bin" >/tmp/grind_ltp_$$.log 2>&1; then _li=0; else _li=$?; fi
        if grind_run_guest 120 "$GRIND_DBT" "$_lob_bin" >/tmp/grind_ltp_$$.log 2>&1; then _ld=0; else _ld=$?; fi
        if [ "$_li" -ne "$_ld" ]; then grind_fail "ltp" "$(basename "$_lob_bin") interp exit=$_li vs dbt exit=$_ld"
        elif [ "$_li" -ne 0 ]; then grind_fail "ltp" "$(basename "$_lob_bin") exit=$_li (both engines agree)"
        else grind_pass "ltp" "$(basename "$_lob_bin") (interp-vs-dbt exit match)"
        fi
    elif grind_run_guest 120 "$_lob_wrap" "$_lob_bin" >/tmp/grind_ltp_$$.log 2>&1; then
        grind_pass "ltp" "$(basename "$_lob_bin")"
    else
        grind_fail "ltp" "$(basename "$_lob_bin") exit!=0"
    fi
}

run_lmbench_suite() {
    echo "== Grind [$CURRENT_ARCH]: lmbench completion (lat_syscall, lat_ctx, lat_pagefault, lat_proc, bw_mmap) =="
    _wrap="${GRIND_DBT:-${GRIND_INTERP:-}}"
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "$_wrap" ]; then
        grind_skip "lmbench" "translator wrapper missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    _dir="${LMBENCH_DIR:-}"
    _bins=""
    if [ -n "$_dir" ] && [ -d "$_dir" ]; then
        _bins="$_dir/bin"
    elif [ "$CURRENT_ARCH" = "host" ] && command -v lat_syscall >/dev/null 2>&1; then
        _bins="PATH"
    else
        grind_skip "lmbench" "LMBENCH_DIR unset for $CURRENT_ARCH"
        return 0
    fi
    for _t in lat_syscall lat_ctx lat_pagefault lat_proc; do
        if [ "$_bins" = "PATH" ]; then _b="$_t"; else _b="$_bins/$_t"; fi
        if [ "$_bins" = "PATH" ] && command -v "$_t" >/dev/null 2>&1; then
            _have_lm=1
        elif [ -x "$_b" ]; then
            _have_lm=1
        else
            _have_lm=0
        fi
        if [ "$_have_lm" -eq 1 ]; then
            # Each tool takes its own arguments (upstream lat_*.c usage):
            # lat_syscall names a syscall, lat_proc names a procedure kind,
            # lat_ctx takes a process count, and lat_pagefault takes an
            # existing input file (>= 1 MiB) prepared here.
            case "$_t" in
                lat_syscall) _lm_args="-P 1 null" ;;
                lat_proc) _lm_args="-P 1 procedure" ;;
                lat_ctx) _lm_args="-P 1 2" ;;
                lat_pagefault)
                    _lm_pf="/tmp/grind_pagefault_${CURRENT_ARCH}_$$"
                    if ! dd if=/dev/zero of="$_lm_pf" bs=4096 count=1024 2>/dev/null || [ ! -s "$_lm_pf" ]; then
                        grind_fail "lmbench" "lat_pagefault input setup failed"
                        rm -f "$_lm_pf"
                        continue
                    fi
                    _lm_args="-P 1 $_lm_pf"
                    ;;
            esac
            # shellcheck disable=SC2086
            if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
                if grind_run_guest 120 "$GRIND_INTERP" "$_b" $_lm_args >/tmp/grind_lm_$$.log 2>&1; then
                    _lmi=0
                else
                    _lmi=$?
                fi
                if grind_run_guest 120 "$GRIND_DBT" "$_b" $_lm_args >/tmp/grind_lm_$$.log 2>&1; then
                    _lmd=0
                else
                    _lmd=$?
                fi
                if [ "$_lmi" -ne "$_lmd" ]; then
                    grind_fail "lmbench" "$_t interp exit=$_lmi vs dbt exit=$_lmd"
                elif [ "$_lmi" -ne 0 ]; then
                    grind_fail "lmbench" "$_t exited non-zero or timed out (both engines agree)"
                elif [ -s /tmp/grind_lm_$$.log ]; then
                    grind_pass "lmbench" "$_t completed (interp-vs-dbt exit match)"
                else
                    grind_fail "lmbench" "$_t empty output"
                fi
            elif grind_run_guest 120 "$_wrap" "$_b" $_lm_args >/tmp/grind_lm_$$.log 2>&1; then
                if [ -s /tmp/grind_lm_$$.log ]; then
                    grind_pass "lmbench" "$_t completed"
                else
                    grind_fail "lmbench" "$_t empty output"
                fi
            else
                grind_fail "lmbench" "$_t exited non-zero or timed out"
            fi
            [ "$_t" = "lat_pagefault" ] && rm -f "$_lm_pf"
        else
            grind_skip "lmbench" "$_t not built"
        fi
    done
    if [ "$_bins" = "PATH" ]; then _b="bw_mmap"; else _b="$_bins/bw_mmap"; fi
    if { [ "$_bins" = "PATH" ] && command -v bw_mmap >/dev/null 2>&1; } || [ -x "$_b" ]; then
        if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
            if grind_run_guest 180 "$GRIND_INTERP" "$_b" 512m rdwr >/tmp/grind_lm_bw_i_$$ 2>&1; then
                _lmi=0
            else
                _lmi=$?
            fi
            if grind_run_guest 180 "$GRIND_DBT" "$_b" 512m rdwr >/tmp/grind_lm_bw_d_$$ 2>&1; then
                _lmd=0
            else
                _lmd=$?
            fi
            if [ "$_lmi" -ne "$_lmd" ]; then
                grind_fail "lmbench" "bw_mmap interp exit=$_lmi vs dbt exit=$_lmd"
            elif [ "$_lmi" -ne 0 ]; then
                grind_fail "lmbench" "bw_mmap exited non-zero or timed out (both engines agree)"
            elif [ ! -s /tmp/grind_lm_bw_i_$$ ] || [ ! -s /tmp/grind_lm_bw_d_$$ ]; then
                grind_fail "lmbench" "bw_mmap empty output"
            else
                grind_pass "lmbench" "bw_mmap completed (interp-vs-dbt exit match)"
            fi
        elif grind_run_guest 180 "$_wrap" "$_b" 512m rdwr >/tmp/grind_lm_bw_$$.log 2>&1; then
            if [ -s /tmp/grind_lm_bw_$$.log ]; then
                grind_pass "lmbench" "bw_mmap completed"
            else
                grind_fail "lmbench" "bw_mmap empty output"
            fi
        else
            grind_fail "lmbench" "bw_mmap exited non-zero or timed out"
        fi
    else
        grind_skip "lmbench" "bw_mmap not built"
    fi
    rm -f /tmp/grind_lm_$$.log /tmp/grind_lm_bw_$$.log /tmp/grind_lm_bw_i_$$ /tmp/grind_lm_bw_d_$$
}

# Run a compiled differential binary against an independent reference oracle
# (GRIND_QEMU) and every configured translator engine, verifying identical
# output. Unlike run_gcc_torture (which skips without GRIND_QEMU unless
# GRIND_ALLOW_NO_ORACLE=1), this gate must never silently treat GRIND_INTERP
# as an independent oracle: without GRIND_QEMU it requires an explicit
# GRIND_ALLOW_NO_ORACLE=1 opt-in and compares interp-vs-dbt only.
run_differential_binary() {
    _rdb_suite="$1"
    _rdb_label="$2"
    _rdb_bin="$3"
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "${GRIND_QEMU:-}" ] && [ "${GRIND_ALLOW_NO_ORACLE:-0}" != "1" ]; then
        grind_skip "$_rdb_suite" "GRIND_QEMU oracle missing for $CURRENT_ARCH (GAP without independent oracle; set GRIND_ALLOW_NO_ORACLE=1 for interp-vs-dbt only)"
        return 0
    fi
    if [ -n "${GRIND_QEMU:-}" ]; then
        _rdb_engines=""
        if [ -n "${GRIND_INTERP:-}" ] && [ "${GRIND_INTERP}" != "$GRIND_QEMU" ]; then
            _rdb_engines="INTERP"
        fi
        if [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_DBT}" != "$GRIND_QEMU" ]; then
            _rdb_engines="${_rdb_engines:+$_rdb_engines }DBT"
        fi
        if [ -z "$_rdb_engines" ]; then
            grind_skip "$_rdb_suite" "differential soak requires a translator engine (GRIND_INTERP/GRIND_DBT) distinct from GRIND_QEMU for $CURRENT_ARCH"
            return 0
        fi
        _rdb_ref_out="/tmp/grind_diff_ref_$$.out"
        if ! grind_run_guest 60 "$GRIND_QEMU" "$_rdb_bin" >"$_rdb_ref_out" 2>&1; then
            grind_fail "$_rdb_suite" "$_rdb_label reference (GRIND_QEMU) wrapper exited non-zero"
            rm -f "$_rdb_ref_out"
            return 1
        fi
        _rdb_fail=0
        # shellcheck disable=SC2086
        for _rdb_eng in $_rdb_engines; do
            case "$_rdb_eng" in
                INTERP) _rdb_wrap="$GRIND_INTERP" ;;
                DBT)    _rdb_wrap="$GRIND_DBT" ;;
            esac
            _rdb_dbt_out="/tmp/grind_diff_dbt_$$.out"
            if ! grind_run_guest 60 "$_rdb_wrap" "$_rdb_bin" >"$_rdb_dbt_out" 2>&1; then
                grind_fail "$_rdb_suite" "$_rdb_label $_rdb_eng wrapper exited non-zero"
                _rdb_fail=1
            elif ! cmp -s "$_rdb_ref_out" "$_rdb_dbt_out"; then
                grind_fail "$_rdb_suite" "$_rdb_label $_rdb_eng vs GRIND_QEMU output mismatch"
                _rdb_fail=1
            fi
            rm -f "$_rdb_dbt_out"
        done
        rm -f "$_rdb_ref_out"
        if [ "$_rdb_fail" -ne 0 ]; then
            return 1
        fi
        grind_pass "$_rdb_suite" "$_rdb_label QEMU-oracle differential OK"
        return 0
    fi
    # No QEMU oracle with GRIND_ALLOW_NO_ORACLE=1: interp-vs-dbt only.
    if [ -z "${GRIND_QEMU:-}" ] && [ "${GRIND_ALLOW_NO_ORACLE:-0}" != "1" ]; then
        grind_skip "$_rdb_suite" "GRIND_QEMU oracle missing for $CURRENT_ARCH (GAP without independent oracle; set GRIND_ALLOW_NO_ORACLE=1 for interp-vs-dbt only)"
        return 0
    fi
    if [ -z "${GRIND_INTERP:-}" ] || [ -z "${GRIND_DBT:-}" ] || [ "${GRIND_INTERP}" = "${GRIND_DBT}" ]; then
        grind_skip "$_rdb_suite" "differential soak requires distinct GRIND_INTERP and GRIND_DBT wrappers for $CURRENT_ARCH (no external oracle)"
        return 0
    fi
    _rdb_ref_out="/tmp/grind_diff_ref_$$.out"
    _rdb_dbt_out="/tmp/grind_diff_dbt_$$.out"
    if ! grind_run_guest 60 "$GRIND_INTERP" "$_rdb_bin" >"$_rdb_ref_out" 2>&1; then
        grind_fail "$_rdb_suite" "$_rdb_label interp wrapper exited non-zero"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    if ! grind_run_guest 60 "$GRIND_DBT" "$_rdb_bin" >"$_rdb_dbt_out" 2>&1; then
        grind_fail "$_rdb_suite" "$_rdb_label dbt wrapper exited non-zero"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    if ! cmp -s "$_rdb_ref_out" "$_rdb_dbt_out"; then
        grind_fail "$_rdb_suite" "$_rdb_label interp vs dbt output mismatch"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
    grind_pass "$_rdb_suite" "$_rdb_label interp-vs-dbt differential OK (no external oracle)"
    return 0
}

# Foreign-arch upstream qualification (RTS-R3-1).
#
# An unwrapped host `make check` must never qualify a foreign translator:
# with --arch all the same host result would otherwise be recorded once per
# foreign repo under CURRENT_ARCH. Foreign jobs therefore require an
# explicit target-aware adapter (UPSTREAM_CHECK_ADAPTER, an executable)
# that runs the upstream suite for that target with the selected engine,
# guest artifacts, and execution wrapper. Without an adapter the suite is
# SKIPped, never passed; unwrapped `make check` is reserved for --arch host.
#
# Adapter contract: "$UPSTREAM_CHECK_ADAPTER" <arch> <upstream_dir> with
# GRIND_INTERP/GRIND_DBT/GRIND_QEMU wrappers, GRIND_CC/GRIND_CXX compilers,
# GRIND_RT_BIN/GRIND_HL_BIN binaries, and GRIND_BACKEND in the environment.
# Exit 0 qualifies the foreign arch; nonzero fails it.
run_upstream_adapter_check() {
    _up_adapter="${UPSTREAM_CHECK_ADAPTER:-}"
    if [ -z "$_up_adapter" ] || [ ! -x "$_up_adapter" ]; then
        grind_skip "upstream-check" "foreign arch $CURRENT_ARCH needs executable UPSTREAM_CHECK_ADAPTER (target-aware upstream test adapter); unwrapped host 'make check' refused"
        return 0
    fi
    if GRIND_INTERP="${GRIND_INTERP:-}" GRIND_DBT="${GRIND_DBT:-}" \
        GRIND_QEMU="${GRIND_QEMU:-}" GRIND_CC="${GRIND_CC:-}" GRIND_CXX="${GRIND_CXX:-}" \
        GRIND_RT_BIN="${GRIND_RT_BIN:-}" GRIND_HL_BIN="${GRIND_HL_BIN:-}" \
        GRIND_BACKEND="$BACKEND" \
        timeout --kill-after=30s 1800s "$_up_adapter" "$CURRENT_ARCH" "$UPSTREAM_CHECK_DIR" \
        >/tmp/grind_upstream_$$.log 2>&1; then
        grind_pass "upstream-check" "$_up_adapter $CURRENT_ARCH passed"
    else
        grind_fail "upstream-check" "$_up_adapter $CURRENT_ARCH failed (see /tmp/grind_upstream_$$.log)"
    fi
    rm -f /tmp/grind_upstream_$$.log
}

run_weekly_soak() {
    echo "== Grind weekly [$CURRENT_ARCH]: Csmith/Yarpgen soak + upstream check (host make check / foreign adapter) =="
    _cc="${GRIND_CC:-}"
    _cxx="${GRIND_CXX:-}"
    if want_suite csmith; then
    if command -v csmith >/dev/null 2>&1 && grind_has_compiler "$_cc"; then
        _cinc="${CSMITH_INCLUDE:-/usr/include/csmith}"
        if [ ! -f "$_cinc/csmith.h" ]; then
            grind_skip "csmith" "csmith.h not found in '$_cinc'"
        else
            _csrc="/tmp/grind_csmith_${CURRENT_ARCH}_$$.c"
            _cbin="/tmp/grind_csmith_${CURRENT_ARCH}_$$"
            if timeout --kill-after=30s 60s csmith --seed "${CSMITH_SEED:-1}" > "$_csrc" 2>/dev/null; then _cs_gen_rc=0; else _cs_gen_rc=$?; fi
            if [ "$_cs_gen_rc" -eq 124 ] || [ "$_cs_gen_rc" -eq 137 ]; then grind_fail "csmith" "seed=${CSMITH_SEED:-1} generation timed out"; rm -f "$_csrc" "$_cbin"
            elif [ "$_cs_gen_rc" -ne 0 ]; then grind_fail "csmith" "seed=${CSMITH_SEED:-1} generation failed with csmith"; rm -f "$_csrc" "$_cbin"
            elif grind_run_compiler "$_cc" -ffp-contract=off -O1 -I"$_cinc" "$_csrc" -o "$_cbin" -lm >/dev/null 2>&1; then run_differential_binary "csmith" "seed=${CSMITH_SEED:-1}" "$_cbin" || true; rm -f "$_csrc" "$_cbin"
            else _cs_cc_rc=$?; rm -f "$_csrc" "$_cbin"
                if [ "$_cs_cc_rc" -eq 124 ] || [ "$_cs_cc_rc" -eq 137 ]; then grind_fail "csmith" "seed=${CSMITH_SEED:-1} compilation timed out with $_cc"; else grind_fail "csmith" "seed=${CSMITH_SEED:-1} compilation failed with $_cc"; fi
            fi
        fi
    else
        grind_skip "csmith" "csmith or cross-compiler ($_cc) not installed"
    fi
    fi

    if want_suite yarpgen; then
    if command -v yarpgen >/dev/null 2>&1; then
        _ydir="/tmp/grind_yarpgen_${CURRENT_ARCH}_$$"
        mkdir -p "$_ydir"
        if timeout --kill-after=30s 120s yarpgen --seed="${YARPGEN_SEED:-1}" -o "$_ydir" >/dev/null 2>&1; then _yg_rc=0; else _yg_rc=$?; fi
        if [ "$_yg_rc" -eq 124 ] || [ "$_yg_rc" -eq 137 ]; then grind_fail "yarpgen" "yarpgen --seed=${YARPGEN_SEED:-1} timed out"; rm -rf "$_ydir"
        elif [ "$_yg_rc" -ne 0 ]; then grind_fail "yarpgen" "yarpgen --seed=${YARPGEN_SEED:-1} failed"; rm -rf "$_ydir"
        else
            _yc_files=""
            _ycpp_files=""
            for _yf in "$_ydir"/*.c; do
                if [ -f "$_yf" ]; then _yc_files="${_yc_files:+$_yc_files }$_yf"; fi
            done
            for _yf in "$_ydir"/*.cpp; do
                if [ -f "$_yf" ]; then _ycpp_files="${_ycpp_files:+$_ycpp_files }$_yf"; fi
            done
            if [ -n "$_yc_files" ]; then
                if ! grind_has_compiler "$_cc"; then
                    grind_skip "yarpgen" "C compiler '$_cc' for $CURRENT_ARCH not on PATH"
                else
                    # shellcheck disable=SC2086
                    if grind_run_compiler "$_cc" -ffp-contract=off -O1 $_yc_files -o "$_ydir/yarp_bin" -lm >/dev/null 2>&1; then
                        run_differential_binary "yarpgen" "seed=${YARPGEN_SEED:-1}" "$_ydir/yarp_bin" || true
                    else
                        _yg_cc_rc=$?
                        if [ "$_yg_cc_rc" -eq 124 ] || [ "$_yg_cc_rc" -eq 137 ]; then
                            grind_fail "yarpgen" "seed=${YARPGEN_SEED:-1} C compilation timed out with $_cc"
                        else
                            grind_fail "yarpgen" "seed=${YARPGEN_SEED:-1} C compilation failed with $_cc"
                        fi
                    fi
                fi
            elif [ -n "$_ycpp_files" ]; then
                if ! grind_has_compiler "$_cxx"; then
                    grind_skip "yarpgen" "C++ compiler '$_cxx' for $CURRENT_ARCH not on PATH"
                else
                    # shellcheck disable=SC2086
                    if grind_run_compiler "$_cxx" -ffp-contract=off -O1 $_ycpp_files -o "$_ydir/yarp_bin" -lm >/dev/null 2>&1; then
                        run_differential_binary "yarpgen" "seed=${YARPGEN_SEED:-1}" "$_ydir/yarp_bin" || true
                    else
                        _yg_cxx_rc=$?
                        if [ "$_yg_cxx_rc" -eq 124 ] || [ "$_yg_cxx_rc" -eq 137 ]; then
                            grind_fail "yarpgen" "seed=${YARPGEN_SEED:-1} C++ compilation timed out with $_cxx"
                        else
                            grind_fail "yarpgen" "seed=${YARPGEN_SEED:-1} C++ compilation failed with $_cxx"
                        fi
                    fi
                fi
            else
                grind_fail "yarpgen" "yarpgen produced no .c or .cpp files in $_ydir"
            fi
            rm -rf "$_ydir"
        fi
    else
        grind_skip "yarpgen" "yarpgen not installed (fixed-seed soak not run)"
    fi
    fi

    if want_suite upstream-check; then
    if [ -n "${UPSTREAM_CHECK_DIR:-}" ] && [ -f "${UPSTREAM_CHECK_DIR}/Makefile" ]; then
        if [ "$CURRENT_ARCH" = "host" ]; then
            if timeout --kill-after=30s 1800s make -C "$UPSTREAM_CHECK_DIR" check >/tmp/grind_upstream_$$.log 2>&1; then
                grind_pass "upstream-check" "make -C $UPSTREAM_CHECK_DIR check passed"
            else
                grind_fail "upstream-check" "make -C $UPSTREAM_CHECK_DIR check failed"
            fi
            rm -f /tmp/grind_upstream_$$.log
        else
            run_upstream_adapter_check
        fi
    else
        grind_skip "upstream-check" "UPSTREAM_CHECK_DIR not set (point at guest source tree for upstream make check)"
    fi
    fi
}
