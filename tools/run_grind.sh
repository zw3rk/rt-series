#!/bin/sh
# tools/run_grind.sh — Tier N (nightly) / Tier W (weekly) grind.
# Suites: stress-ng, gcc-torture (same-binary diff), TestFloat, compiler-rt,
# libc-test+LTP, lmbench; weekly adds Csmith/Yarpgen soak + upstream check.
# Usage: tools/run_grind.sh <nightly|weekly> [--arch <repo|all|host>] [--suite <name>]
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu
grind_cleanup() { rm -rf /tmp/grind_*_$$ /tmp/grind_*_$$.* "${_ydir:-}" /tmp/grind_libc_$$.log /tmp/grind_ltp_$$.log /tmp/rt_grind_*_$$ /tmp/rt_grind_*_$$.* /tmp/csmith_*_$$ /tmp/csmith_*_$$.* /tmp/yarpgen_*_$$ /tmp/yarpgen_*_$$.* 2>/dev/null; }
trap '_rc=$?; grind_cleanup; exit $_rc' EXIT
trap 'grind_cleanup; exit 130' INT
trap 'grind_cleanup; exit 143' TERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_DIR="$(cd "$ROOT_DIR/.." && pwd)"

# shellcheck source=tools/remote_bench_common.sh
. "$SCRIPT_DIR/remote_bench_common.sh"

TIER="${1:-help}"
if [ $# -gt 0 ]; then shift; fi

ARCH_FILTER="all"
SUITE_FILTER="all"
GRIND_ALLOW_SKIP="${GRIND_ALLOW_SKIP:-1}"

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

case "$ARCH_FILTER" in
    all|host|a32rt|i686rt|mips32rt|ppc32rt|sparc32rt|rvrt|loongarch64rt|ppc64rt|mips64rt|sparc64rt) ;;
    *)
        echo "ERROR: Invalid --arch '$ARCH_FILTER'" >&2
        exit 2
        ;;
esac

case "$SUITE_FILTER" in
    all|stress-ng|gcc-torture|torture|testfloat|compiler-rt|libc-ltp|libc|ltp|lmbench|csmith|yarpgen|upstream-check|upstream) ;;
    *)
        echo "ERROR: Invalid --suite '$SUITE_FILTER' (expected all|stress-ng|gcc-torture|torture|testfloat|compiler-rt|libc-ltp|libc|ltp|lmbench|csmith|yarpgen|upstream-check)" >&2
        exit 2
        ;;
esac

# Resolve and validate BACKEND first (RTS-R2-3) before any translator artifact
# discovery so binary format (Mach-O vs Linux ELF vs hl wrapper) matches host.
BACKEND="${GRIND_BACKEND:-}"
if [ -z "$BACKEND" ]; then
    case "$(uname -s 2>/dev/null || echo Linux)" in
        Darwin*) BACKEND="darwin" ;;
        *) BACKEND="linux" ;;
    esac
fi
case "$BACKEND" in
    linux|hl|darwin) ;;
    *)
        echo "ERROR: Invalid GRIND_BACKEND '$BACKEND' (expected linux|hl|darwin)" >&2
        exit 2
        ;;
esac

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
CURRENT_ARCH="host"

USER_GRIND_CC="${GRIND_CC:-}"
USER_GRIND_CXX="${GRIND_CXX:-}"
USER_GRIND_QEMU="${GRIND_QEMU:-}"
USER_GRIND_INTERP="${GRIND_INTERP:-}"
USER_GRIND_DBT="${GRIND_DBT:-}"
GRIND_RT_BIN=""
GRIND_HL_BIN=""
GRIND_AUTO_INTERP=""
GRIND_AUTO_DBT=""

grind_pass() {
    GRIND_PASS=$((GRIND_PASS + 1))
    echo "PASS [$CURRENT_ARCH/$1]: $2"
}
grind_fail() {
    GRIND_FAIL=$((GRIND_FAIL + 1))
    echo "FAIL [$CURRENT_ARCH/$1]: $2" >&2
}
grind_skip() {
    GRIND_SKIP=$((GRIND_SKIP + 1))
    echo "SKIP [$CURRENT_ARCH/$1]: $2"
}

want_suite() {
    if [ "$SUITE_FILTER" = "all" ]; then return 0; fi
    if [ "$SUITE_FILTER" = "$1" ]; then return 0; fi
    case "$SUITE_FILTER" in
        torture) [ "$1" = "gcc-torture" ] ;;
        libc|ltp|libc-ltp) [ "$1" = "libc-ltp" ] ;;
        upstream|upstream-check) [ "$1" = "upstream-check" ] ;;
        *) return 1 ;;
    esac
}

find_backend_rt_bin() {
    _fbr_repo="$1"
    _fbr_dir="$PROJECTS_DIR/$_fbr_repo/_build"
    case "$BACKEND" in
        darwin)
            for _cand in "$_fbr_dir/${_fbr_repo}-darwin-arm64" "$_fbr_dir/${_fbr_repo}-darwin" "$_fbr_dir/${_fbr_repo}"; do
                if [ -x "$_cand" ] && file "$_cand" 2>/dev/null | grep -q "Mach-O 64-bit"; then
                    printf '%s' "$_cand"
                    return 0
                fi
            done
            ;;
        linux|hl)
            for _cand in "$_fbr_dir/${_fbr_repo}-linux-aarch64" "$_fbr_dir/${_fbr_repo}"; do
                if [ -x "$_cand" ] && file "$_cand" 2>/dev/null | grep -q "ELF 64-bit"; then
                    printf '%s' "$_cand"
                    return 0
                fi
            done
            ;;
    esac
    return 1
}

find_hl_launcher() {
    for _cand in "$PROJECTS_DIR/hyper-linux-u4/_build/hl" "$PROJECTS_DIR/hyper-linux/_build/hl"; do
        if [ -x "$_cand" ]; then
            printf '%s' "$_cand"
            return 0
        fi
    done
    return 1
}

# Run guest via wrapper; auto wrappers on BACKEND=hl go via rt_run_bounded_hl,
# user/embedded-hl/QEMU wrappers run literally via run_bounded.
# Usage: grind_run_guest <timeout_s> <wrapper> <guest> [args...]
grind_run_guest() {
    _gr_secs="$1"
    _gr_wrap="$2"
    _gr_guest="$3"
    shift 3
    if [ "$BACKEND" = "hl" ] && [ "$CURRENT_ARCH" != "host" ] \
        && [ -n "${GRIND_HL_BIN:-}" ] && [ -n "${GRIND_RT_BIN:-}" ] \
        && [ -n "$_gr_wrap" ]; then
        case "$_gr_wrap" in
            *"${GRIND_HL_BIN}"*)
                ;;
            *)
                _gr_eng=""
                if [ -n "${GRIND_AUTO_DBT:-}" ] && [ "$_gr_wrap" = "$GRIND_AUTO_DBT" ]; then
                    _gr_eng="dbt"
                elif [ -n "${GRIND_AUTO_INTERP:-}" ] && [ "$_gr_wrap" = "$GRIND_AUTO_INTERP" ]; then
                    _gr_eng="interp"
                fi
                if [ -n "$_gr_eng" ]; then
                    rt_run_bounded_hl "$_gr_secs" "$GRIND_HL_BIN" "$CURRENT_ARCH" \
                        "$_gr_eng" "$GRIND_RT_BIN" "$_gr_guest" "$@"
                    return $?
                fi
                ;;
        esac
    fi
    # shellcheck disable=SC2086
    run_bounded "$_gr_secs" $_gr_wrap "$_gr_guest" "$@"
}

resolve_arch_defaults() {
    CURRENT_ARCH="$1"
    GRIND_CC="$USER_GRIND_CC"
    GRIND_CXX="$USER_GRIND_CXX"
    GRIND_QEMU="$USER_GRIND_QEMU"
    GRIND_INTERP="$USER_GRIND_INTERP"
    GRIND_DBT="$USER_GRIND_DBT"
    GRIND_RT_BIN=""
    GRIND_HL_BIN=""
    GRIND_AUTO_INTERP=""
    GRIND_AUTO_DBT=""

    if [ "$CURRENT_ARCH" = "host" ]; then
        : "${GRIND_CC:=${CC:-cc}}"
        : "${GRIND_CXX:=${CXX:-c++}}"
        return 0
    fi

    _rt_bin="$(find_backend_rt_bin "$CURRENT_ARCH" || true)"
    if [ -n "$_rt_bin" ]; then
        _interp_cmd="$(rt_format_cmd_prefix "$CURRENT_ARCH" "interp" "$_rt_bin")"
        _dbt_cmd="$(rt_format_cmd_prefix "$CURRENT_ARCH" "dbt" "$_rt_bin")"
        _hl_bin=""
        if [ "$BACKEND" = "hl" ]; then
            _hl_bin="$(find_hl_launcher || true)"
            if [ -n "$_hl_bin" ]; then
                GRIND_HL_BIN="$_hl_bin"
                GRIND_RT_BIN="$_rt_bin"
            fi
        fi
        if [ "$BACKEND" != "hl" ] || [ -n "$_hl_bin" ]; then
            if [ -z "${GRIND_INTERP:-}" ]; then
                GRIND_INTERP="$_interp_cmd"
                GRIND_AUTO_INTERP="$_interp_cmd"
            fi
            if [ -z "${GRIND_DBT:-}" ]; then
                GRIND_DBT="$_dbt_cmd"
                GRIND_AUTO_DBT="$_dbt_cmd"
            fi
        fi
    fi

    if [ -z "$GRIND_CC" ]; then
        case "$CURRENT_ARCH" in
            a32rt)         GRIND_CC="arm-linux-gnueabihf-gcc" ;;
            i686rt)        GRIND_CC="i686-linux-gnu-gcc" ;;
            mips32rt)      GRIND_CC="mipsel-linux-gnu-gcc" ;;
            ppc32rt)       GRIND_CC="powerpc-linux-gnu-gcc" ;;
            sparc32rt)     GRIND_CC="sparc-linux-gnu-gcc" ;;
            rvrt)          GRIND_CC="riscv64-linux-gnu-gcc" ;;
            loongarch64rt) GRIND_CC="loongarch64-linux-gnu-gcc" ;;
            ppc64rt)       GRIND_CC="powerpc64le-linux-gnu-gcc" ;;
            mips64rt)      GRIND_CC="mips64el-linux-gnuabi64-gcc" ;;
            sparc64rt)     GRIND_CC="sparc64-linux-gnu-gcc" ;;
        esac
    fi
    if [ -z "$GRIND_CXX" ] && [ -n "$GRIND_CC" ]; then
        GRIND_CXX="$(printf '%s' "$GRIND_CC" | sed 's/gcc$/g++/')"
    fi
}

yaml_bogo_ops() {
    awk '
        /bogo-ops:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }
        /bogo_ops:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }
    ' "$1" 2>/dev/null | head -n 1
}

yaml_has_verify_failure() {
    if grep -Ei 'verify[_ -]?fail(ed)?:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    if grep -Ei 'failed:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    if grep -Ei 'errors?:[[:space:]]*[1-9]' "$1" >/dev/null 2>&1; then return 0; fi
    return 1
}

run_stressng_suite() {
    echo "== Grind [$CURRENT_ARCH]: stress-ng (backend=$BACKEND, ${STRESS_SECS}s/stressor) =="
    _sng_cmd="stress-ng"
    _sng_is_guest=0
    if [ "$CURRENT_ARCH" != "host" ]; then
        if [ -n "${GRIND_STRESS_NG:-}" ] && [ -n "${GRIND_DBT:-}" ]; then
            _sng_is_guest=1
        else
            grind_skip "stress-ng" "foreign-arch ($CURRENT_ARCH) requires GRIND_STRESS_NG + GRIND_DBT"
            return 0
        fi
    elif ! command -v stress-ng >/dev/null 2>&1; then
        grind_skip "stress-ng" "stress-ng not on PATH"
        return 0
    fi
    _stressors="$CORE_STRESSORS"
    if [ "$BACKEND" = "linux" ] || [ "$BACKEND" = "hl" ]; then
        _stressors="$_stressors $LINUXFD_STRESSORS"
    fi
    _work="/tmp/grind_stress_${CURRENT_ARCH}_$$"
    mkdir -p "$_work"
    for s in $_stressors; do
        _yaml="$_work/$s.yaml"
        if [ "$_sng_is_guest" -eq 1 ]; then
            if grind_run_guest 120 "$GRIND_DBT" "$GRIND_STRESS_NG" --verify --metrics-brief --yaml "$_yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.log" 2>&1; then
                _rc=0
            else
                _rc=$?
            fi
        # shellcheck disable=SC2086
        elif timeout --kill-after=30s 120s $_sng_cmd --verify --metrics-brief --yaml "$_yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.log" 2>&1; then
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
    echo "== Grind [$CURRENT_ARCH]: gcc.c-torture/execute (same-binary differential, -ffp-contract=off) =="
    _dir="${GCC_TORTURE_DIR:-}"
    if [ -z "$_dir" ] || [ ! -d "$_dir" ]; then
        grind_skip "gcc-torture" "GCC_TORTURE_DIR not set or missing (point at gcc/testsuite/gcc.c-torture/execute)"
        return 0
    fi
    _cc="${GRIND_CC:-}"
    if [ -z "$_cc" ] || ! command -v "$_cc" >/dev/null 2>&1; then
        grind_skip "gcc-torture" "compiler '$_cc' for $CURRENT_ARCH not on PATH"
        return 0
    fi
    if [ "$CURRENT_ARCH" != "host" ] && { [ -z "${GRIND_INTERP:-}" ] || [ -z "${GRIND_DBT:-}" ]; }; then
        grind_skip "gcc-torture" "translator wrappers (GRIND_INTERP + GRIND_DBT) missing for $CURRENT_ARCH ($BACKEND)"
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
            _bin="/tmp/grind_torture_${CURRENT_ARCH}_${_base}_${opt}_$$"
            if timeout --kill-after=30s 120s "$_cc" -ffp-contract=off "-$opt" "$src" -o "$_bin" -lm >/dev/null 2>&1; then :; else _cc_rc=$?
                rm -f "$_bin"
                if [ "$_cc_rc" -eq 124 ] || [ "$_cc_rc" -eq 137 ]; then grind_fail "gcc-torture" "$_base -$opt compilation timed out"; else grind_skip "gcc-torture" "$_base -$opt did not compile (target-specific, skipped)"; fi
                continue
            fi
            _have_ref=0
            if [ "$CURRENT_ARCH" = "host" ]; then
                if ! timeout --kill-after=10s 30s "$_bin" >/tmp/grind_torture_out_$$ 2>&1; then
                    grind_fail "gcc-torture" "$_base -$opt native exit!=0"
                    rm -f "$_bin"
                    continue
                fi
                _have_ref=1
            fi
            _ok=1
            for eng in GRIND_QEMU GRIND_INTERP GRIND_DBT; do
                case "$eng" in
                    GRIND_QEMU)   _wrap="${GRIND_QEMU:-}" ;;
                    GRIND_INTERP) _wrap="${GRIND_INTERP:-}" ;;
                    GRIND_DBT)    _wrap="${GRIND_DBT:-}" ;;
                    *)            _wrap="" ;;
                esac
                if [ -n "$_wrap" ]; then
                    if ! grind_run_guest 60 "$_wrap" "$_bin" >/tmp/grind_torture_g_$$ 2>&1; then
                        grind_fail "gcc-torture" "$_base -$opt $eng exit!=0"
                        _ok=0
                        break
                    fi
                    if [ "$_have_ref" -eq 0 ]; then
                        cp /tmp/grind_torture_g_$$ /tmp/grind_torture_out_$$
                        _have_ref=1
                    elif ! cmp -s /tmp/grind_torture_out_$$ /tmp/grind_torture_g_$$; then
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

# Run one TestFloat verifier pass over the shared vector file and report it
# under its own engine label. An empty wrapper runs the verifier directly
# (host). Otherwise the wrapper runs through grind_run_guest so hl-backend
# foreign jobs keep the single shared hl policy. Uses the caller's $_ver,
# $_vec, and $_rounds globals and the per-engine /tmp/grind_testfloat log.
run_testfloat_one_engine() {
    _tfo_label="$1"
    _tfo_wrap="$2"
    if [ -n "$_tfo_wrap" ]; then
        if grind_run_guest 600 "$_tfo_wrap" "$_ver" <"$_vec" >/tmp/grind_testfloat_$$.log 2>&1; then
            _tfo_rc=0
        else
            _tfo_rc=$?
        fi
    else
        if timeout --kill-after=30s 600s "$_ver" <"$_vec" >/tmp/grind_testfloat_$$.log 2>&1; then
            _tfo_rc=0
        else
            _tfo_rc=$?
        fi
    fi
    if [ "$_tfo_rc" -eq 0 ]; then
        if grep -Eqi 'fail|error|mismatch' /tmp/grind_testfloat_$$.log; then
            grind_fail "$_tfo_label" "verifier reported failures (see /tmp/grind_testfloat_$$.log)"
        else
            grind_pass "$_tfo_label" "gen|ver pipeline clean ($_rounds rounds)"
        fi
    else
        grind_fail "$_tfo_label" "verifier exited non-zero (rc=$_tfo_rc, see /tmp/grind_testfloat_$$.log)"
    fi
}

run_testfloat_suite() {
    echo "== Grind [$CURRENT_ARCH]: Berkeley TestFloat (host testfloat_gen | guest testfloat_ver, per-engine) =="
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
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "${GRIND_INTERP:-}" ] && [ -z "${GRIND_DBT:-}" ]; then
        grind_skip "testfloat" "translator wrapper missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    _rounds="${TESTFLOAT_ROUNDS:-10000}"
    if [ "$TIER" = "weekly" ]; then _rounds="${TESTFLOAT_ROUNDS_WEEKLY:-$_rounds}"; fi
    _vec="/tmp/grind_testfloat_vec_${CURRENT_ARCH}_$$"
    if ! timeout --kill-after=30s 300s "$_gen" -rounds "$_rounds" >"$_vec" 2>/tmp/grind_testfloat_$$.log; then
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
    rm -f "$_vec" /tmp/grind_testfloat_$$.log
}

run_builtins_suite() {
    echo "== Grind [$CURRENT_ARCH]: compiler-rt builtin ABI helpers =="
    _cc="${GRIND_CC:-}"
    if [ -z "$_cc" ] || ! command -v "$_cc" >/dev/null 2>&1; then
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
    if timeout --kill-after=30s 120s "$_cc" -std=c11 -O1 "$_src" -o "$_bin" -lm >/dev/null 2>&1; then :; else _br_cc_rc=$?
        rm -f "$_src" "$_bin"
        if [ "$_br_cc_rc" -eq 124 ] || [ "$_br_cc_rc" -eq 137 ]; then grind_fail "compiler-rt" "builtin probe compilation timed out with $_cc"; else grind_skip "compiler-rt" "builtin probe did not compile with $_cc"; fi
        return 0
    fi
    _wrap="${GRIND_INTERP:-${GRIND_DBT:-}}"
    if [ -n "$_wrap" ]; then
        if grind_run_guest 60 "$_wrap" "$_bin" > /tmp/grind_builtins_out_$$ 2>&1; then
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
                if grind_run_guest 120 "$_wrap" "$_bin" >/tmp/grind_libc_$$.log 2>&1; then
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
                if grind_run_guest 300 "$_wrap" "$_b" >/tmp/grind_libc_$$.log 2>&1; then grind_pass "libc-ltp" "libc-test $_t"; else grind_fail "libc-ltp" "libc-test $_t exit!=0"; fi
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
            while IFS= read -r _lb || [ -n "$_lb" ]; do case "$_lb" in ""|"#"*) continue ;; *.sh) continue ;; esac; [ -x "$_lb" ] || continue; _ln=$((_ln+1)); if [ "$_ln" -gt 50 ]; then break; fi; if grind_run_guest 120 "$_wrap" "$_lb" >/tmp/grind_ltp_$$.log 2>&1; then grind_pass "ltp" "$(basename "$_lb")"; else grind_fail "ltp" "$(basename "$_lb") exit!=0"; fi; done < "$LTP_MANIFEST"
        else
            for _lb in "$LTP_DIR/testcases/bin"/* "$LTP_DIR/bin"/* "$LTP_DIR/testcases/kernel/syscalls"/*/*; do case "$_lb" in *.sh) continue ;; esac; [ -f "$_lb" ] && [ -x "$_lb" ] || continue; _ln=$((_ln+1)); if [ "$_ln" -gt 50 ]; then break; fi; if grind_run_guest 120 "$_wrap" "$_lb" >/tmp/grind_ltp_$$.log 2>&1; then grind_pass "ltp" "$(basename "$_lb")"; else grind_fail "ltp" "$(basename "$_lb") exit!=0"; fi; done
        fi
        rm -f /tmp/grind_ltp_$$.log
        if [ "$_ln" -eq 0 ]; then grind_fail "ltp" "LTP_DIR=$LTP_DIR yielded 0 binaries (check LTP install or LTP_MANIFEST)"; fi
    else
        grind_skip "ltp" "LTP_DIR unset (point at LTP install for syscall binaries)"
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
            if grind_run_guest 120 "$_wrap" "$_b" -P 1 null >/tmp/grind_lm_$$.log 2>&1; then
                if [ -s /tmp/grind_lm_$$.log ]; then
                    grind_pass "lmbench" "$_t completed"
                else
                    grind_fail "lmbench" "$_t empty output"
                fi
            else
                grind_fail "lmbench" "$_t exited non-zero or timed out"
            fi
        else
            grind_skip "lmbench" "$_t not built"
        fi
    done
    if [ "$_bins" = "PATH" ]; then _b="bw_mmap"; else _b="$_bins/bw_mmap"; fi
    if { [ "$_bins" = "PATH" ] && command -v bw_mmap >/dev/null 2>&1; } || [ -x "$_b" ]; then
        if grind_run_guest 180 "$_wrap" "$_b" 512m rdwr >/tmp/grind_lm_bw_$$.log 2>&1; then
            grind_pass "lmbench" "bw_mmap completed"
        else
            grind_fail "lmbench" "bw_mmap exited non-zero or timed out"
        fi
    else
        grind_skip "lmbench" "bw_mmap not built"
    fi
    rm -f /tmp/grind_lm_$$.log /tmp/grind_lm_bw_$$.log
}

# Run a compiled differential binary across reference oracle (GRIND_QEMU or
# GRIND_INTERP) and DBT (GRIND_DBT) and verify identical output.
run_differential_binary() {
    _rdb_suite="$1"
    _rdb_label="$2"
    _rdb_bin="$3"
    _rdb_ref_wrap="${GRIND_QEMU:-${GRIND_INTERP:-}}"
    _rdb_dbt_wrap="${GRIND_DBT:-}"
    if [ -z "$_rdb_ref_wrap" ] || [ -z "$_rdb_dbt_wrap" ] || [ "$_rdb_ref_wrap" = "$_rdb_dbt_wrap" ]; then
        grind_skip "$_rdb_suite" "differential soak requires distinct reference (GRIND_QEMU/GRIND_INTERP) and GRIND_DBT wrappers for $CURRENT_ARCH"
        return 0
    fi
    _rdb_ref_out="/tmp/grind_diff_ref_$$.out"
    _rdb_dbt_out="/tmp/grind_diff_dbt_$$.out"
    if ! grind_run_guest 60 "$_rdb_ref_wrap" "$_rdb_bin" >"$_rdb_ref_out" 2>&1; then
        grind_fail "$_rdb_suite" "$_rdb_label reference wrapper exited non-zero"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    if ! grind_run_guest 60 "$_rdb_dbt_wrap" "$_rdb_bin" >"$_rdb_dbt_out" 2>&1; then
        grind_fail "$_rdb_suite" "$_rdb_label DBT wrapper exited non-zero"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    if ! cmp -s "$_rdb_ref_out" "$_rdb_dbt_out"; then
        grind_fail "$_rdb_suite" "$_rdb_label reference vs DBT output mismatch"
        rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
        return 1
    fi
    rm -f "$_rdb_ref_out" "$_rdb_dbt_out"
    grind_pass "$_rdb_suite" "$_rdb_label reference-vs-DBT differential OK"
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
    if command -v csmith >/dev/null 2>&1 && [ -n "$_cc" ] && command -v "$_cc" >/dev/null 2>&1; then
        _cinc="${CSMITH_INCLUDE:-/usr/include/csmith}"
        if [ ! -f "$_cinc/csmith.h" ]; then
            grind_skip "csmith" "csmith.h not found in '$_cinc'"
        else
            _csrc="/tmp/grind_csmith_${CURRENT_ARCH}_$$.c"
            _cbin="/tmp/grind_csmith_${CURRENT_ARCH}_$$"
            if timeout --kill-after=30s 60s csmith --seed "${CSMITH_SEED:-1}" > "$_csrc" 2>/dev/null; then _cs_gen_rc=0; else _cs_gen_rc=$?; fi
            if [ "$_cs_gen_rc" -eq 124 ] || [ "$_cs_gen_rc" -eq 137 ]; then grind_fail "csmith" "seed=${CSMITH_SEED:-1} generation timed out"; rm -f "$_csrc" "$_cbin"
            elif [ "$_cs_gen_rc" -ne 0 ]; then grind_fail "csmith" "seed=${CSMITH_SEED:-1} generation failed with csmith"; rm -f "$_csrc" "$_cbin"
            elif timeout --kill-after=30s 120s "$_cc" -ffp-contract=off -O1 -I"$_cinc" "$_csrc" -o "$_cbin" -lm >/dev/null 2>&1; then run_differential_binary "csmith" "seed=${CSMITH_SEED:-1}" "$_cbin" || true; rm -f "$_csrc" "$_cbin"
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
                if [ -z "$_cc" ] || ! command -v "$_cc" >/dev/null 2>&1; then
                    grind_skip "yarpgen" "C compiler '$_cc' for $CURRENT_ARCH not on PATH"
                else
                    # shellcheck disable=SC2086
                    if timeout --kill-after=30s 120s "$_cc" -ffp-contract=off -O1 $_yc_files -o "$_ydir/yarp_bin" -lm >/dev/null 2>&1; then
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
                if [ -z "$_cxx" ] || ! command -v "$_cxx" >/dev/null 2>&1; then
                    grind_skip "yarpgen" "C++ compiler '$_cxx' for $CURRENT_ARCH not on PATH"
                else
                    # shellcheck disable=SC2086
                    if timeout --kill-after=30s 120s "$_cxx" -ffp-contract=off -O1 $_ycpp_files -o "$_ydir/yarp_bin" -lm >/dev/null 2>&1; then
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

run_arch_job() {
    resolve_arch_defaults "$1"
    if want_suite stress-ng; then run_stressng_suite; fi
    if want_suite gcc-torture; then run_gcc_torture_suite; fi
    if want_suite testfloat; then run_testfloat_suite; fi
    if want_suite compiler-rt; then run_builtins_suite; fi
    if want_suite libc-ltp; then run_libc_ltp_suite; fi
    if want_suite lmbench; then run_lmbench_suite; fi
    if [ "$TIER" = "weekly" ]; then
        run_weekly_soak
    fi
}

print_grind_usage() {
    cat << 'EOF'
Usage: tools/run_grind.sh <nightly|weekly> [--arch <repo|all|host>] [--suite <name>]

Suites: stress-ng, gcc-torture, testfloat, compiler-rt, libc-ltp, lmbench
        (weekly adds: csmith, yarpgen, upstream-check)
EOF
}

case "$TIER" in
    nightly|weekly)
        echo "== Tier $TIER grind (arch=$ARCH_FILTER, backend=$BACKEND) =="
        if [ "$ARCH_FILTER" = "all" ]; then
            for _arch_repo in $ALL_RT_REPOS; do
                run_arch_job "$_arch_repo"
            done
        else
            run_arch_job "$ARCH_FILTER"
        fi
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
if [ "$GRIND_SKIP" -gt 0 ] && [ "$GRIND_ALLOW_SKIP" != "1" ]; then
    echo "FAIL: grind recorded $GRIND_SKIP skipped suite(s) (GRIND_ALLOW_SKIP=$GRIND_ALLOW_SKIP)" >&2
    exit 1
fi
exit 0
