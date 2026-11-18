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

_GRIND_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/grind_suites.sh
. "$_GRIND_SCRIPT_DIR/grind_suites.sh"

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
    all|host|a32rt|i686rt|mips32rt|ppc32rt|sparc32rt|rvrt|loongarch64rt|ppc64rt|mips64rt|sparc64rt|s390xrt) ;;
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

# grind_has_compiler <cc-string>: true when <cc-string> names an installed
# compiler (only the first word — the command — is probed, so multi-word
# "compiler + ABI flags" strings like GRIND_CC work).
grind_has_compiler() {
    [ -n "${1:-}" ] && command -v "${1%% *}" >/dev/null 2>&1
}

# grind_run_compiler <cc-string> [args...]: compile with a bounded timeout.
# The compiler string undergoes intentional word-splitting so embedded ABI
# flags ("sparc64-linux-gnu-gcc -m32 -mcpu=v8") work seamlessly.
grind_run_compiler() {
    _grc_cc="$1"
    shift
    # shellcheck disable=SC2086
    timeout --kill-after=30s 120s $_grc_cc "$@"
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
            sparc32rt)
                if command -v sparc64-linux-gnu-gcc >/dev/null 2>&1; then
                    GRIND_CC="sparc64-linux-gnu-gcc -m32 -mcpu=v8"
                elif command -v sparc-linux-gnu-gcc >/dev/null 2>&1; then
                    GRIND_CC="sparc-linux-gnu-gcc"
                else
                    GRIND_CC="sparc64-linux-gnu-gcc -m32 -mcpu=v8"
                fi
                ;;
            rvrt)          GRIND_CC="riscv64-linux-gnu-gcc" ;;
            loongarch64rt) GRIND_CC="loongarch64-linux-gnu-gcc" ;;
            ppc64rt)       GRIND_CC="powerpc64le-linux-gnu-gcc" ;;
            mips64rt)      GRIND_CC="mips64el-linux-gnuabi64-gcc" ;;
            sparc64rt)     GRIND_CC="sparc64-linux-gnu-gcc" ;;
            s390xrt)       GRIND_CC="s390x-linux-gnu-gcc" ;;
        esac
    fi
    if [ -z "$GRIND_CXX" ] && [ -n "$GRIND_CC" ]; then
        GRIND_CXX="$(printf '%s' "$GRIND_CC" | sed -e 's/-gcc /-g++ /' -e 's/-gcc$/-g++/' -e 's/^gcc /g++ /' -e 's/^gcc$/g++/')"
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

# Dual-engine comparison (RTS-R8-7): when both GRIND_INTERP and GRIND_DBT are
# configured and distinct on a foreign arch, run <guest> under BOTH engines
# and compare exit codes plus stdout. Leaves the matching DBT output at
# /tmp/grind_dual_out_$$ on success. Returns 0 with output staged, 1 after
# recording grind_fail on divergence, 2 when single-engine fallback applies.
run_dual_or_single_guest() {
    _dos_secs="$1"
    _dos_suite="$2"
    _dos_label="$3"
    _dos_guest="$4"
    shift 4
    rm -f /tmp/grind_dual_out_$$
    if [ "$CURRENT_ARCH" != "host" ] && [ -n "${GRIND_INTERP:-}" ] && [ -n "${GRIND_DBT:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT}" ]; then
        if grind_run_guest "$_dos_secs" "$GRIND_INTERP" "$_dos_guest" "$@" >/tmp/grind_dual_interp_$$ 2>&1; then
            _dos_i=0
        else
            _dos_i=$?
        fi
        if grind_run_guest "$_dos_secs" "$GRIND_DBT" "$_dos_guest" "$@" >/tmp/grind_dual_dbt_$$ 2>&1; then
            _dos_d=0
        else
            _dos_d=$?
        fi
        if [ "$_dos_i" -ne "$_dos_d" ]; then
            grind_fail "$_dos_suite" "$_dos_label interp exit=$_dos_i vs dbt exit=$_dos_d"
            rm -f /tmp/grind_dual_interp_$$ /tmp/grind_dual_dbt_$$ /tmp/grind_dual_out_$$
            return 1
        fi
        if [ "$_dos_i" -ne 0 ]; then
            grind_fail "$_dos_suite" "$_dos_label exit=$_dos_i (both engines agree)"
            rm -f /tmp/grind_dual_interp_$$ /tmp/grind_dual_dbt_$$ /tmp/grind_dual_out_$$
            return 1
        fi
        if ! cmp -s /tmp/grind_dual_interp_$$ /tmp/grind_dual_dbt_$$; then
            grind_fail "$_dos_suite" "$_dos_label interp vs dbt output mismatch"
            rm -f /tmp/grind_dual_interp_$$ /tmp/grind_dual_dbt_$$ /tmp/grind_dual_out_$$
            return 1
        fi
        cp /tmp/grind_dual_dbt_$$ /tmp/grind_dual_out_$$
        rm -f /tmp/grind_dual_interp_$$ /tmp/grind_dual_dbt_$$
        return 0
    fi
    return 2
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
            if [ -n "${GRIND_INTERP:-}" ] && [ "${GRIND_INTERP}" != "${GRIND_DBT:-}" ]; then
                if grind_run_guest 120 "$GRIND_INTERP" "$GRIND_STRESS_NG" --verify --metrics-brief --yaml "$_work/$s.interp.yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.interp.log" 2>&1; then
                    _rc_i=0
                else
                    _rc_i=$?
                fi
                if grind_run_guest 120 "$GRIND_DBT" "$GRIND_STRESS_NG" --verify --metrics-brief --yaml "$_work/$s.dbt.yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.dbt.log" 2>&1; then
                    _rc_d=0
                else
                    _rc_d=$?
                fi
                cat "$_work/$s.interp.log" "$_work/$s.dbt.log" >"$_work/$s.log" 2>/dev/null
                if [ "$_rc_i" -ne "$_rc_d" ]; then
                    _rc=1
                    echo "interp exit=$_rc_i vs dbt exit=$_rc_d" >>"$_work/$s.log"
                elif [ "$_rc_i" -ne 0 ]; then
                    _rc="$_rc_i"
                else
                    _rc=0
                    _yaml="$_work/$s.dbt.yaml"
                fi
            elif grind_run_guest 120 "$GRIND_DBT" "$GRIND_STRESS_NG" --verify --metrics-brief --yaml "$_yaml" -t "$STRESS_SECS" --"$s" 1 >"$_work/$s.log" 2>&1; then
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
    if ! grind_has_compiler "$_cc"; then
        grind_skip "gcc-torture" "compiler '$_cc' for $CURRENT_ARCH not on PATH"
        return 0
    fi
    if [ "$CURRENT_ARCH" != "host" ] && { [ -z "${GRIND_INTERP:-}" ] || [ -z "${GRIND_DBT:-}" ]; }; then
        grind_skip "gcc-torture" "translator wrappers (GRIND_INTERP + GRIND_DBT) missing for $CURRENT_ARCH ($BACKEND)"
        return 0
    fi
    if [ "$CURRENT_ARCH" != "host" ] && [ -z "${GRIND_QEMU:-}" ] && [ "${GRIND_ALLOW_NO_ORACLE:-0}" != "1" ]; then
        grind_skip "gcc-torture" "GRIND_QEMU oracle missing for $CURRENT_ARCH (GAP without independent oracle; set GRIND_ALLOW_NO_ORACLE=1 for interp-vs-dbt only)"
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
            if grind_run_compiler "$_cc" -ffp-contract=off "-$opt" "$src" -o "$_bin" -lm >/dev/null 2>&1; then :; else _cc_rc=$?
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
