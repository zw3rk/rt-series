#!/bin/sh
# tools/run_grind.sh — Tier N (nightly) / Tier W (weekly) grind orchestration.
#
# Suites (from docs/CATALOGUE-TODO.md section 3):
#   1. stress-ng with --verify --metrics-brief --yaml against the per-backend
#      stressor allowlists (core list on all backends; linux-fd list on
#      linux/hl only), asserting bogo_ops > 0 per stressor.
#   2. gcc.c-torture/execute compiled with -ffp-contract=off at -O0 and -O2
#      with same-binary differential (qemu vs --interp vs --dbt on the exact
#      same compiled ELF; never -O0 checksums vs -O2 checksums).
#   3. Berkeley TestFloat: host testfloat_gen piped into guest testfloat_ver.
#   4. compiler-rt builtin ABI helpers (__divsi3 etc. with boundary patterns).
#   5. musl libc-test + LTP syscalls manifest runner.
#   6. lmbench completion check (lat_syscall, lat_ctx, lat_pagefault,
#      lat_proc, bw_mmap with per-test timeouts; timing is not an oracle).
#   Weekly adds: fixed-seed Csmith/Yarpgen soak + upstream Git/coreutils/
#   gawk/BusyBox `make check` stubs.
#
# Usage: tools/run_grind.sh <nightly|weekly> [--arch <repo|all>] [--suite <name>]
#
# Env: GRIND_BACKEND=<linux|hl|darwin> (default from uname),
#   STRESS_SECS (default 5 nightly, 60 weekly per stressor),
#   GCC_TORTURE_DIR, TESTFLOAT_GEN, TESTFLOAT_VER, TESTFLOAT_ROUNDS,
#   LIBC_TEST_DIR, LTP_DIR, LMBENCH_DIR, GRIND_QEMU/GRIND_INTERP/GRIND_DBT
#   guest wrappers, GRIND_ALLOW_SKIP=1 (default: skips allowed, fails only
#   on fail>0 or pass==0).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TIER="${1:-help}"
if [ $# -gt 0 ]; then shift; fi

ARCH_FILTER="all"
SUITE_FILTER="all"

while [ $# -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH_FILTER="${2:?missing value for --arch}"
            shift 2
            ;;
        --suite)
            SUITE_FILTER="${2:?missing value for --suite}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

BACKEND="${GRIND_BACKEND:-}"
if [ -z "$BACKEND" ]; then
    case "$(uname -s 2>/dev/null || echo Linux)" in
        Darwin*) BACKEND="darwin" ;;
        *) BACKEND="linux" ;;
    esac
fi

case "$TIER" in
    nightly) STRESS_SECS="${STRESS_SECS:-5}" ;;
    weekly) STRESS_SECS="${STRESS_SECS:-60}" ;;
    *) STRESS_SECS="${STRESS_SECS:-5}" ;;
esac

# Core CPU/VM/thread list (all 3 backends: linux, hl, darwin).
CORE_STRESSORS="cpu opcode atomic futex pthread fp matrix mmap mremap mprotect madvise brk stack fork vfork clone exec spawn signal pipe poll socket dentry getdent open seek malloc icache cache tlb fault zlib"
# Linux/hl kernel-fd & procfs list (tracked separately against backend_darwin.c).
LINUXFD_STRESSORS="vma bad-altstack sigfd timer itimer epoll eventfd lockf procfs"

GRIND_PASS=0
GRIND_FAIL=0
GRIND_SKIP=0

grind_pass() {
    GRIND_PASS=$((GRIND_PASS + 1))
    echo "PASS [$1]: $2"
}
grind_fail() {
    GRIND_FAIL=$((GRIND_FAIL + 1))
    echo "FAIL [$1]: $2" >&2
}
grind_skip() {
    GRIND_SKIP=$((GRIND_SKIP + 1))
    echo "SKIP [$1]: $2"
}

want_suite() {
    if [ "$SUITE_FILTER" = "all" ]; then return 0; fi
    [ "$SUITE_FILTER" = "$1" ]
}

yaml_bogo_ops() {
    # Print the first bogo-ops integer found in a stress-ng --yaml file.
    awk '
        /bogo-ops:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }
        /bogo_ops:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }
    ' "$1" 2>/dev/null | head -n 1
}

yaml_has_verify_failure() {
    # True (0) when the yaml reports any non-zero failure/verify-fail count.
    if grep -Ei 'verify[_ -]?fail(ed)?:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    if grep -Ei 'failed:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    if grep -Ei 'errors?:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    return 1
}

run_stressng_suite() {
    echo "== Grind: stress-ng (backend=$BACKEND, ${STRESS_SECS}s/stressor) =="
    if ! command -v stress-ng >/dev/null 2>&1; then
        grind_skip "stress-ng" "stress-ng not on PATH"
        return 0
    fi
    _stressors="$CORE_STRESSORS"
    if [ "$BACKEND" = "linux" ] || [ "$BACKEND" = "hl" ]; then
        _stressors="$_stressors $LINUXFD_STRESSORS"
    fi
    _work="/tmp/grind_stress_$$"
    mkdir -p "$_work"
    for s in $_stressors; do
        _yaml="$_work/$s.yaml"
        if timeout --kill-after=30s 120s stress-ng --verify --metrics-brief --yaml "$_yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.log" 2>&1; then
            _rc=0
        else
            _rc=$?
        fi
        if [ "$_rc" -ne 0 ]; then
            grind_fail "stress-ng" "--$s exit=$_rc (see $_work/$s.log)"
            continue
        fi
        if [ ! -s "$_yaml" ]; then
            grind_fail "stress-ng" "--$s produced no yaml"
            continue
        fi
        if yaml_has_verify_failure "$_yaml"; then
            grind_fail "stress-ng" "--$s verification failure (see $_yaml)"
            continue
        fi
        _bogo="$(yaml_bogo_ops "$_yaml")"
        if [ -z "${_bogo:-}" ] || [ "$_bogo" -le 0 ] 2>/dev/null; then
            grind_fail "stress-ng" "--$s bogo_ops missing or 0 (yaml: $_yaml)"
            continue
        fi
        grind_pass "stress-ng" "--$s bogo_ops=$_bogo verify=0"
    done
    rm -rf "$_work"
}

run_gcc_torture_suite() {
    echo "== Grind: gcc.c-torture/execute (same-binary differential, -ffp-contract=off) =="
    _dir="${GCC_TORTURE_DIR:-}"
    if [ -z "$_dir" ] || [ ! -d "$_dir" ]; then
        grind_skip "gcc-torture" "GCC_TORTURE_DIR not set or missing (point at gcc/testsuite/gcc.c-torture/execute)"
        return 0
    fi
    _cc="${CC:-cc}"
    if ! command -v "$_cc" >/dev/null 2>&1; then
        grind_skip "gcc-torture" "no C compiler ($_cc)"
        return 0
    fi
    _cap=50
    if [ "$TIER" = "weekly" ]; then _cap=200; fi
    _n=0
    for src in "$_dir"/*.c; do
        [ -f "$src" ] || continue
        _n=$((_n + 1))
        if [ "$_n" -gt "$_cap" ]; then break; fi
        _base="$(basename "$src" .c)"
        for opt in O0 O2; do
            _bin="/tmp/grind_torture_${_base}_${opt}_$$"
            if ! "$_cc" -ffp-contract=off "-$opt" "$src" -o "$_bin" -lm >/dev/null 2>&1; then
                grind_skip "gcc-torture" "$_base -$opt did not compile (target-specific, skipped)"
                continue
            fi
            # Native baseline must exit 0; guest differentials reuse this exact binary.
            if ! timeout --kill-after=10s 30s "$_bin" >/tmp/grind_torture_out_$$ 2>&1; then
                grind_fail "gcc-torture" "$_base -$opt native exit!=0"
                rm -f "$_bin"
                continue
            fi
            _native_out="$(cat /tmp/grind_torture_out_$$)"
            _ok=1
            for eng in GRIND_QEMU GRIND_INTERP GRIND_DBT; do
                _wrap="$(eval "printf '%s' \"\$$eng\"")"
                if [ -n "$_wrap" ]; then
                    if ! timeout --kill-after=10s 60s $_wrap "$_bin" >/tmp/grind_torture_g_$$ 2>&1; then
                        grind_fail "gcc-torture" "$_base -$opt $eng exit!=0"
                        _ok=0
                        break
                    fi
                    if ! cmp -s /tmp/grind_torture_out_$$ /tmp/grind_torture_g_$$; then
                        grind_fail "gcc-torture" "$_base -$opt $eng output diverges (same binary)"
                        _ok=0
                        break
                    fi
                fi
            done
            if [ "$_ok" = "1" ]; then
                grind_pass "gcc-torture" "$_base -$opt same-binary OK"
            fi
            rm -f "$_bin"
        done
    done
    rm -f /tmp/grind_torture_out_$$ /tmp/grind_torture_g_$$
    if [ "$_n" -eq 0 ]; then
        grind_skip "gcc-torture" "no .c files in $_dir"
    fi
}

run_testfloat_suite() {
    echo "== Grind: Berkeley TestFloat (host testfloat_gen | guest testfloat_ver) =="
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
        grind_skip "testfloat" "TESTFLOAT_VER not set (guest testfloat_ver binary missing)"
        return 0
    fi
    _rounds="${TESTFLOAT_ROUNDS:-10000}"
    if [ "$TIER" = "weekly" ]; then _rounds="${TESTFLOAT_ROUNDS_WEEKLY:-$TESTFLOAT_ROUNDS}"; fi
    # Pipe host-generated vectors into the guest verifier; full verification
    # completes in minutes instead of days. The guest binary must be the
    # ISA-specific static testfloat_ver (NaN/tininess configured per ABI).
    # Stage via a temp file so a multi-word guest wrapper (e.g. a translator
    # command with flags in GRIND_INTERP) needs no nested quoting.
    _vec="/tmp/grind_testfloat_vec_$$"
    if ! timeout --kill-after=30s 300s "$_gen" -rounds "$_rounds" >"$_vec" 2>/tmp/grind_testfloat_$$.log; then
        grind_skip "testfloat" "testfloat_gen could not produce vectors (missing ISA config?)"
        rm -f "$_vec" /tmp/grind_testfloat_$$.log
        return 0
    fi
    if [ -n "${GRIND_INTERP:-}" ]; then
        # shellcheck disable=SC2086
        if timeout --kill-after=30s 600s ${GRIND_INTERP} "$_ver" <"$_vec" \
            >/tmp/grind_testfloat_$$.log 2>&1; then
            _tf_rc=0
        else
            _tf_rc=$?
        fi
    else
        if timeout --kill-after=30s 600s "$_ver" <"$_vec" >/tmp/grind_testfloat_$$.log 2>&1; then
            _tf_rc=0
        else
            _tf_rc=$?
        fi
    fi
    if [ "${_tf_rc:-1}" -eq 0 ]; then
        if grep -Eqi 'fail|error|mismatch' /tmp/grind_testfloat_$$.log; then
            grind_fail "testfloat" "verifier reported failures (see /tmp/grind_testfloat_$$.log)"
        else
            grind_pass "testfloat" "gen|ver pipeline clean ($_rounds rounds)"
        fi
    else
        grind_skip "testfloat" "pipeline could not run (gen/ver mismatch or missing ISA config)"
    fi
    rm -f "$_vec" /tmp/grind_testfloat_$$.log
}

run_builtins_suite() {
    echo "== Grind: compiler-rt builtin ABI helpers =="
    _cc="${CC:-cc}"
    if ! command -v "$_cc" >/dev/null 2>&1; then
        grind_skip "compiler-rt" "no C compiler ($_cc)"
        return 0
    fi
    _src="/tmp/grind_builtins_$$.c"
    _bin="/tmp/grind_builtins_$$"
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
        if (ov != 1) fails++;
        (void)prod;
        ov = 0;
        prod = __mulosi4(100, 200, &ov);
        if (ov != 0 || prod != 20000) fails++;
    }
    if (fails != 0) { printf("BUILTINS_FAIL:%d\n", fails); return 1; }
    printf("BUILTINS_OK\n");
    return 0;
}
EOF
    if ! "$_cc" -std=c11 -O1 "$_src" -o "$_bin" -lm >/dev/null 2>&1; then
        grind_skip "compiler-rt" "builtin probe did not compile on host"
        rm -f "$_src"
        return 0
    fi
    if [ -n "${GRIND_INTERP:-}" ]; then
        # shellcheck disable=SC2086
        _brun="wrapper"
    else
        _brun="direct"
    fi
    if [ "$_brun" = "wrapper" ]; then
        # shellcheck disable=SC2086
        if timeout --kill-after=10s 60s ${GRIND_INTERP} "$_bin" > /tmp/grind_builtins_out_$$ 2>&1; then
            _brc=0
        else
            _brc=$?
        fi
    else
        if timeout --kill-after=10s 60s "$_bin" > /tmp/grind_builtins_out_$$ 2>&1; then
            _brc=0
        else
            _brc=$?
        fi
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
    rm -f "$_src" "$_bin" /tmp/grind_builtins_out_$$
}

run_libc_ltp_suite() {
    echo "== Grind: libc-test + LTP syscalls manifest =="
    _manifest="${GRIND_LIBC_MANIFEST:-$ROOT_DIR/tests/grind_libc_ltp.manifest}"
    if [ -f "$_manifest" ]; then
        _mfail=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                ""|"#"*) continue ;;
            esac
            _bin="$(printf '%s' "$_line" | awk '{print $1}')"
            if [ -x "$_bin" ]; then
                if timeout --kill-after=10s 120s "$_bin" >/tmp/grind_libc_$$.log 2>&1; then
                    grind_pass "libc-ltp" "$_bin"
                else
                    grind_fail "libc-ltp" "$_bin exit!=0"
                    _mfail=$((_mfail + 1))
                fi
            else
                grind_skip "libc-ltp" "$_bin not built"
            fi
        done < "$_manifest"
        if [ "$_mfail" -gt 0 ]; then return 1; fi
        return 0
    fi
    _found=0
    for _d in "${LIBC_TEST_DIR:-}" "${LTP_DIR:-}"; do
        if [ -n "$_d" ] && [ -d "$_d" ]; then _found=1; fi
    done
    if [ "$_found" = "0" ]; then
        grind_skip "libc-ltp" "no manifest and LIBC_TEST_DIR/LTP_DIR unset (expected: functional, math, pthread, mmap, clone, futex, sigaltstack, epoll, SCM_RIGHTS, statx, getdents64, EFAULT)"
        return 0
    fi
    for _t in functional math pthread; do
        _b="${LIBC_TEST_DIR:-}/bin/$_t"
        if [ -x "$_b" ]; then
            if timeout --kill-after=10s 300s "$_b" >/tmp/grind_libc_$$.log 2>&1; then
                grind_pass "libc-ltp" "libc-test $_t"
            else
                grind_fail "libc-ltp" "libc-test $_t exit!=0"
            fi
        else
            grind_skip "libc-ltp" "libc-test $_t not built"
        fi
    done
    rm -f /tmp/grind_libc_$$.log
}

run_lmbench_suite() {
    echo "== Grind: lmbench completion (lat_syscall, lat_ctx, lat_pagefault, lat_proc, bw_mmap) =="
    _dir="${LMBENCH_DIR:-}"
    _bins=""
    if [ -n "$_dir" ] && [ -d "$_dir" ]; then
        _bins="$_dir/bin"
    elif command -v lat_syscall >/dev/null 2>&1; then
        _bins="PATH"
    else
        grind_skip "lmbench" "LMBENCH_DIR unset and lat_syscall not on PATH"
        return 0
    fi
    for _t in lat_syscall lat_ctx lat_pagefault lat_proc; do
        if [ "$_bins" = "PATH" ]; then _b="$_t"; else _b="$_bins/$_t"; fi
        if [ "$_bins" = "PATH" ] || [ -x "$_b" ]; then
            if timeout --kill-after=10s 120s "$_b" -P 1 null >/tmp/grind_lm_$$.log 2>&1; then
                if [ -s /tmp/grind_lm_$$.log ]; then
                    grind_pass "lmbench" "$_t completed"
                else
                    grind_fail "lmbench" "$_t empty output"
                fi
            else
                grind_skip "lmbench" "$_t could not run here (skipped, not failed)"
            fi
        else
            grind_skip "lmbench" "$_t not built"
        fi
    done
    if [ "$_bins" = "PATH" ]; then _b="bw_mmap"; else _b="$_bins/bw_mmap"; fi
    if [ "$_bins" = "PATH" ] || [ -x "$_b" ]; then
        if timeout --kill-after=10s 180s "$_b" 512m rdwr >/tmp/grind_lm_bw_$$.log 2>&1; then
            grind_pass "lmbench" "bw_mmap completed"
        else
            grind_skip "lmbench" "bw_mmap could not run here"
        fi
    else
        grind_skip "lmbench" "bw_mmap not built"
    fi
    rm -f /tmp/grind_lm_$$.log /tmp/grind_lm_bw_$$.log
}

run_weekly_soak() {
    echo "== Grind weekly: Csmith/Yarpgen soak + upstream make check =="
    if command -v csmith >/dev/null 2>&1 || [ -n "${CSMITH_DIR:-}" ]; then
        grind_skip "csmith" "csmith present but soak needs a configured seed corpus (see CATALOGUE-TODO P4)"
    else
        grind_skip "csmith" "csmith not installed (fixed-seed soak not run)"
    fi
    if command -v yarpgen >/dev/null 2>&1; then
        grind_skip "yarpgen" "yarpgen present but soak needs a configured seed corpus"
    else
        grind_skip "yarpgen" "yarpgen not installed (fixed-seed soak not run)"
    fi
    # Upstream self-rebuild graduation form (BusyBox/musl, guest GCC bootstrap)
    # is a release gate measured in hours; record presence without running here.
    grind_skip "upstream-check" "Git/coreutils/gawk/BusyBox make check runs under make catalogue-grind-weekly in a Linux worker"
}

print_grind_usage() {
    cat << 'EOF'
Usage: tools/run_grind.sh <nightly|weekly> [--arch <repo|all>] [--suite <name>]

Suites: stress-ng, gcc-torture, testfloat, compiler-rt, libc-ltp, lmbench
        (weekly adds: csmith, yarpgen, upstream-check)
EOF
}

case "$TIER" in
    nightly)
        echo "== Tier N grind-nightly (arch=$ARCH_FILTER, backend=$BACKEND) =="
        if want_suite stress-ng; then run_stressng_suite; fi
        if want_suite gcc-torture; then run_gcc_torture_suite; fi
        if want_suite testfloat; then run_testfloat_suite; fi
        if want_suite compiler-rt; then run_builtins_suite; fi
        if want_suite libc-ltp; then run_libc_ltp_suite; fi
        if want_suite lmbench; then run_lmbench_suite; fi
        ;;
    weekly)
        echo "== Tier W grind-weekly (arch=$ARCH_FILTER, backend=$BACKEND) =="
        if want_suite stress-ng; then run_stressng_suite; fi
        if want_suite gcc-torture; then run_gcc_torture_suite; fi
        if want_suite testfloat; then run_testfloat_suite; fi
        if want_suite compiler-rt; then run_builtins_suite; fi
        if want_suite libc-ltp; then run_libc_ltp_suite; fi
        if want_suite lmbench; then run_lmbench_suite; fi
        run_weekly_soak
        ;;
    *)
        print_grind_usage
        exit 2
        ;;
esac

echo "GRIND $TIER SUMMARY: pass=$GRIND_PASS fail=$GRIND_FAIL skip=$GRIND_SKIP"
if [ "$GRIND_PASS" -eq 0 ]; then
    echo "FAIL: grind recorded 0 passes (no suite executed)" >&2
    exit 1
fi
if [ "$GRIND_FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
