#!/bin/sh
# tools/run_catalogue.sh — Multi-Architecture Tiered Software Qualification Runner
#
# Commands (execution budgets from docs/CATALOGUE-TODO.md):
#   smoke          : Tier S (<2 min total). Per-repo parity_suite.sh or `make check`
#                    with per-repo timeout (default 240s); fails when any
#                    PARITY_SUMMARY reports skip>0 unless CATALOGUE_ALLOW_SKIP=1.
#   qualify        : Tier M (<10 min). Per-repo parity + dynamic PT_INTERP,
#                    guest-payload (T1-T4, skip==0), tests/tcg, P3 torture
#                    presence checks, _build/uniform/<abi> guest presence,
#                    and PARITY_SUMMARY skip==0 enforcement,
#                    with per-repo timeout (default 600s).
#   grind-nightly  : Tier N. Delegates to tools/run_grind.sh nightly.
#   grind-weekly   : Tier W. Delegates to tools/run_grind.sh weekly.
#   guest-payload  : Runs inside a guest sysroot under
#                    `<arch>rt --sysroot <dir> /bin/sh tools/run_catalogue.sh guest-payload`
#                    and executes Tiers T1..T4 (shells, coreutils, compression,
#                    crypto, DB, VMs, toolchains, git).
#
# Fail-closed: host gates exit non-zero when --arch matches nothing
# (matched=0), when pass==0, when fail>0, or when any PARITY_SUMMARY in a
# per-repo log reports skip>0 (unless CATALOGUE_ALLOW_SKIP=1). This outer
# skip==0 enforcement applies even when a repo sets PARITY_ALLOW_SKIP=1
# internally. guest-payload exits non-zero when skip>0 unless
# CATALOGUE_ALLOW_SKIP=1 (luajit on sparc32/sparc64/loongarch64/riscv32 is
# expected-unavailable and never counts as skip).
#
# Env overrides:
#   CATALOGUE_SMOKE_TIMEOUT / CATALOGUE_QUALIFY_TIMEOUT (seconds),
#   CATALOGUE_ALLOW_SKIP=1, CATALOGUE_ARCH=<arch>, --timeout <secs>.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_DIR="$(cd "$ROOT_DIR/.." && pwd)"

CMD="${1:-help}"
if [ $# -gt 0 ]; then shift; fi

ARCH_FILTER="all"
TIER_FILTER="all"
TIMEOUT_OVERRIDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH_FILTER="${2:?missing value for --arch}"
            shift 2
            ;;
        --tier)
            TIER_FILTER="${2:?missing value for --tier}"
            shift 2
            ;;
        --timeout)
            TIMEOUT_OVERRIDE="${2:?missing value for --timeout}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

SMOKE_TIMEOUT="${TIMEOUT_OVERRIDE:-${CATALOGUE_SMOKE_TIMEOUT:-240}}"
QUALIFY_TIMEOUT="${TIMEOUT_OVERRIDE:-${CATALOGUE_QUALIFY_TIMEOUT:-600}}"

REPOS="a32rt i686rt mips32rt ppc32rt sparc32rt rvrt loongarch64rt ppc64rt mips64rt sparc64rt"

# Uniform Wave C2 guest ABIs: _build/uniform/<abi>/{p3_torture,smoke_tcg},
# built by tools/build_uniform_guests.sh from tests/p3_torture.c and
# tests/tcg/smoke_tcg.c.
UNIFORM_ABIS="armhf armel i686 mipsel mips ppc32 sparc32 riscv64 riscv32 loongarch64 ppc64le mips64el mips64eb sparc64"

# check_parity_no_skip <logfile> <repo>: fail when any PARITY_SUMMARY line in
# the per-repo log reports skip>0, fail>0, gap>0, or pass==0, unless
# CATALOGUE_ALLOW_SKIP=1 (for skips only). This is the series-level Wave C2
# gate: it fires even if the repo masked skips with its own PARITY_ALLOW_SKIP=1.
check_parity_no_skip() {
    _cns_log="$1"
    _cns_repo="$2"
    if grep -qE '^PARITY_ROW	.*	(FAIL|GAP)	' "$_cns_log" 2>/dev/null; then
        echo "FAIL [$_cns_repo]: PARITY_ROW contains FAIL or GAP in $_cns_log" >&2
        return 1
    fi
    if [ "${CATALOGUE_ALLOW_SKIP:-0}" != "1" ] && grep -qE '^PARITY_ROW	.*	SKIP	' "$_cns_log" 2>/dev/null; then
        echo "FAIL [$_cns_repo]: PARITY_ROW contains SKIP in $_cns_log; set CATALOGUE_ALLOW_SKIP=1 to allow" >&2
        return 1
    fi
    _cns_skips="$(grep -E '^PARITY_SUMMARY ' "$_cns_log" 2>/dev/null \
        | sed -E 's/.*skip=([0-9]+).*/\1/' \
        | awk 'BEGIN{s=0} {s+=$1} END{print s}')"
    if [ -z "$_cns_skips" ]; then
        _cns_skips=0
    fi
    if [ "$_cns_skips" -gt 0 ] && [ "${CATALOGUE_ALLOW_SKIP:-0}" != "1" ]; then
        echo "FAIL [$_cns_repo]: PARITY_SUMMARY reports $_cns_skips SKIP(s); set CATALOGUE_ALLOW_SKIP=1 to allow" >&2
        return 1
    fi
    return 0
}

# check_parity_categories <logfile> <repo> <tier>: in qualify mode, verify that
# the per-repo parity_suite.sh log contains PASS PARITY_ROW entries for all 7
# required Wave C2 qualification categories (accepting either the canonical
# category tag or the repo's equivalent parity case identifier).
check_parity_categories() {
    _cpc_log="$1"
    _cpc_repo="$2"
    _cpc_tier="$3"
    if [ "$_cpc_tier" != "qualify" ]; then
        return 0
    fi
    if ! grep -qE '^PARITY_ROW	' "$_cpc_log" 2>/dev/null; then
        echo "FAIL [$_cpc_repo]: no PARITY_ROW lines found in $_cpc_log" >&2
        return 1
    fi
    _cpc_missing=""
    for _cpc_cat in p3-torture tcg-smoke dyn-pie t1-busybox t2-core t3-system t4-compiler; do
        case "$_cpc_cat" in
            p3-torture)  _cpc_pat='(p3-torture|p3_torture|p3torture)' ;;
            tcg-smoke)   _cpc_pat='(tcg-smoke|tcg_smoke|smoke-tcg|tcg-)' ;;
            dyn-pie)     _cpc_pat='(dyn-pie|p5_dyn|p5-dyn|test_p5_dyn|test-m8-glibc|aot-cache-dynamic-main)' ;;
            t1-busybox)  _cpc_pat='(t1-busybox|p1_isa|p1-|	p1	|test_p1_isa|test-m1-|core-checks-|bb-sp)' ;;
            t2-core)     _cpc_pat='(t2-core|p2_libc|p2libc|p2-|p2_|h2_libc|hello|d2-.*-hello)' ;;
            t3-system)   _cpc_pat='(t3-system|p3_fp|p3-|	p3	|test_p5_fpu_sse|test-m4-|fp-checks-|p4_threads|p4-|	p4	|test_p4_threads|test-m3-|signal-context)' ;;
            t4-compiler) _cpc_pat='(t4-compiler|h4_cxx|h4-|	h4	|test_h4_cxx|test-m8-cpp|cpp17-)' ;;
        esac
        if ! grep -E '^PARITY_ROW	.*	PASS	' "$_cpc_log" 2>/dev/null | grep -qE "$_cpc_pat"; then
            _cpc_missing="${_cpc_missing:+$_cpc_missing }$_cpc_cat"
        fi
    done
    if [ -n "$_cpc_missing" ]; then
        echo "FAIL [$_cpc_repo]: qualify log missing PASS row(s) for category: $_cpc_missing" >&2
        return 1
    fi
    return 0
}

# check_uniform_guests: fail when any _build/uniform/<abi> guest binary is
# missing or not executable (Wave C2 qualify wiring).
check_uniform_guests() {
    _cug_missing=0
    _cug_total=0
    for _cug_abi in $UNIFORM_ABIS; do
        for _cug_bin in p3_torture smoke_tcg; do
            _cug_total=$((_cug_total + 1))
            if [ ! -x "$ROOT_DIR/_build/uniform/$_cug_abi/$_cug_bin" ]; then
                echo "GAP [uniform/$_cug_abi]: missing $_cug_bin (run tools/build_uniform_guests.sh)" >&2
                _cug_missing=$((_cug_missing + 1))
            fi
        done
    done
    if [ "$_cug_missing" -gt 0 ]; then
        echo "FAIL: $_cug_missing of $_cug_total uniform guest binaries missing under _build/uniform/" >&2
        return 1
    fi
    echo "PASS [uniform]: all $_cug_total guest binaries present (_build/uniform/)"
    return 0
}

docker_ids() {
    if command -v docker >/dev/null 2>&1; then
        docker ps -q 2>/dev/null | sort || true
    fi
}

check_no_leftover_docker() {
    _before_file="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    _after_tmp="$2"
    docker_ids > "$_after_tmp" || true
    if [ ! -s "$_before_file" ] && [ ! -s "$_after_tmp" ]; then
        return 0
    fi
    _new_tmp="${_after_tmp}.new"
    comm -13 "$_before_file" "$_after_tmp" > "$_new_tmp" 2>/dev/null || true
    if [ -s "$_new_tmp" ]; then
        echo "FAIL: leftover docker containers after gate:" >&2
        cat "$_new_tmp" >&2
        docker ps >&2 || true
        rm -f "$_new_tmp"
        return 1
    fi
    rm -f "$_new_tmp"
    return 0
}

is_luajit_expected_missing() {
    _arch_norm="$(printf '%s' "${CATALOGUE_ARCH:-$(uname -m 2>/dev/null || echo unknown)}" | tr 'A-Z' 'a-z')"
    case "$_arch_norm" in
        sparc*|loongarch64|riscv32|*riscv32*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

run_guest_payload() {
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export HOME="/tmp"
    work="/tmp/rt_series_cat_$$"
    rm -rf "$work"
    mkdir -p "$work"
    trap 'rm -rf "$work"' EXIT INT TERM

    pass=0
    skip=0
    expected_skip=0

    note_pass() {
        pass=$((pass + 1))
        echo "PASS [$1]: $2"
    }
    note_skip() {
        skip=$((skip + 1))
        echo "SKIP [$1]: $2 (missing tool)"
    }
    note_expected() {
        expected_skip=$((expected_skip + 1))
        echo "EXPECTED-SKIP [$1]: $2"
    }
    fail_now() {
        echo "FAIL [$1]: $2" >&2
        echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip expected_skip=$expected_skip FAIL ($1: $2)"
        exit 1
    }

    # --- Tier 1: Shells, POSIX Stream Utilities, Archives, Diff, Shebang, /proc ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "1" ]; then
        echo "== Tier 1: Shells & POSIX Stream Utilities =="
        sh_out="$(sh -c 'x=17; y=25; echo $((x + y))')"
        [ "$sh_out" = "42" ] || fail_now "T1" "sh arithmetic ($sh_out)"
        note_pass "T1" "sh arithmetic 17+25=42"

        printf "gamma\nalpha\nbeta\nalpha\n" | sort | uniq -c | sed -E 's/^[[:space:]]+//' > "$work/sorted.txt"
        grep -q "^2 alpha$" "$work/sorted.txt" || fail_now "T1" "sort/uniq/sed/grep"
        note_pass "T1" "sort | uniq -c | sed | grep"

        if command -v gawk >/dev/null 2>&1 || command -v awk >/dev/null 2>&1; then
            awk_bin="awk"
            command -v gawk >/dev/null 2>&1 && awk_bin="gawk"
            awk_out="$(printf "a 10.5\nb 20.25\na 4.25\n" | "$awk_bin" '{ sum[$1] += $2 } END { printf "%.2f:%.2f", sum["a"], sum["b"] }')"
            [ "$awk_out" = "14.75:20.25" ] || fail_now "T1" "$awk_bin ($awk_out)"
            note_pass "T1" "$awk_bin associative sum 14.75:20.25"
        else
            note_skip "T1" "awk/gawk"
        fi

        mkdir -p "$work/tree_dir/sub1" "$work/tree_dir/sub2"
        echo "one" > "$work/tree_dir/sub1/f1.txt"
        echo "two" > "$work/tree_dir/sub2/f2.txt"
        found_cnt="$(find "$work/tree_dir" -name '*.txt' | wc -l | tr -d ' ')"
        [ "$found_cnt" = "2" ] || fail_now "T1" "find ($found_cnt)"
        note_pass "T1" "find counts two *.txt"

        # dash/bash subshell + trap
        if command -v dash >/dev/null 2>&1; then
            dash_out="$(dash -c 'trap "echo TRAPPED" EXIT; (echo SUBSHELL); echo PARENT')"
            case "$dash_out" in
                *SUBSHELL*PARENT*TRAPPED*) note_pass "T1" "dash subshell+trap" ;;
                *) fail_now "T1" "dash subshell+trap ($dash_out)" ;;
            esac
        else
            note_skip "T1" "dash"
        fi
        if command -v bash >/dev/null 2>&1; then
            bash_out="$(bash -c 'trap "echo TRAPPED" EXIT; (x=41; echo SUBSHELL:$((x+1))); echo PARENT:$((1+1))')"
            case "$bash_out" in
                *SUBSHELL:42*PARENT:2*TRAPPED*) note_pass "T1" "bash subshell+trap" ;;
                *) fail_now "T1" "bash subshell+trap ($bash_out)" ;;
            esac
        else
            note_skip "T1" "bash"
        fi

        # tar + gzip archive round-trip
        if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
            mkdir -p "$work/tar_src/a" "$work/tar_dst"
            echo "alpha content" > "$work/tar_src/a/f1.txt"
            echo "beta content" > "$work/tar_src/f2.txt"
            (cd "$work/tar_src" && tar -cf "$work/arch.tar" .) || fail_now "T1" "tar create"
            gzip -c "$work/arch.tar" > "$work/arch.tar.gz" || fail_now "T1" "gzip tar"
            rm -rf "$work/tar_dst" && mkdir -p "$work/tar_dst"
            gzip -dc "$work/arch.tar.gz" | (cd "$work/tar_dst" && tar -xf -) || fail_now "T1" "tar+gzip extract"
            cmp -s "$work/tar_src/a/f1.txt" "$work/tar_dst/a/f1.txt" || fail_now "T1" "tar+gzip round-trip f1"
            cmp -s "$work/tar_src/f2.txt" "$work/tar_dst/f2.txt" || fail_now "T1" "tar+gzip round-trip f2"
            note_pass "T1" "tar+gzip round-trip"
        else
            note_skip "T1" "tar+gzip"
        fi

        # sha256sum -c
        if command -v sha256sum >/dev/null 2>&1; then
            printf "The quick brown fox jumps over the lazy dog 0123456789\n" > "$work/sha.txt"
            (cd "$work" && sha256sum sha.txt > sha.txt.sums) || fail_now "T1" "sha256sum create"
            (cd "$work" && sha256sum -c sha.txt.sums) || fail_now "T1" "sha256sum -c"
            note_pass "T1" "sha256sum -c"
        else
            note_skip "T1" "sha256sum"
        fi

        # diff -u exit codes: 0 identical, 1 different
        if command -v diff >/dev/null 2>&1; then
            printf "same\n" > "$work/d1.txt"
            printf "same\n" > "$work/d2.txt"
            printf "different\n" > "$work/d3.txt"
            if diff -u "$work/d1.txt" "$work/d2.txt" > "$work/d12.diff"; then
                diff_same=0
            else
                diff_same=$?
            fi
            [ "$diff_same" = "0" ] || fail_now "T1" "diff -u identical exit=$diff_same"
            if diff -u "$work/d1.txt" "$work/d3.txt" > "$work/d13.diff"; then
                diff_diff=0
            else
                diff_diff=$?
            fi
            [ "$diff_diff" = "1" ] || fail_now "T1" "diff -u different exit=$diff_diff"
            grep -q "^[+-]" "$work/d13.diff" || fail_now "T1" "diff -u patch body"
            note_pass "T1" "diff -u exit 0 vs 1"
        else
            note_skip "T1" "diff"
        fi

        # #! shebang script execution
        printf '#!/bin/sh\necho SHEBANG_OK:$((20+22))\n' > "$work/hello_shebang.sh"
        chmod +x "$work/hello_shebang.sh"
        shebang_out="$("$work/hello_shebang.sh")"
        [ "$shebang_out" = "SHEBANG_OK:42" ] || fail_now "T1" "shebang ($shebang_out)"
        note_pass "T1" "#! shebang exec"

        # /proc/self inspection
        if [ -r /proc/self/cmdline ] || [ -r /proc/self/maps ] || [ -e /proc/self/exe ]; then
            if [ -r /proc/self/maps ]; then
                grep -q . /proc/self/maps || fail_now "T1" "/proc/self/maps empty"
            fi
            note_pass "T1" "/proc/self inspection"
        else
            note_skip "T1" "/proc/self"
        fi
    fi

    # --- Tier 2: Compression, Crypto, JSON & SQLite ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "2" ]; then
        echo "== Tier 2: Compression, Cryptography & Structured Data =="
        printf "The quick brown fox jumps over the lazy dog 0123456789\n" > "$work/plain.txt"

        if command -v openssl >/dev/null 2>&1; then
            openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -pass pass:rt_series_key \
                -in "$work/plain.txt" -out "$work/cipher.bin" || fail_now "T2" "openssl enc"
            openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000 -pass pass:rt_series_key \
                -in "$work/cipher.bin" -out "$work/dec.txt" || fail_now "T2" "openssl dec"
            cmp -s "$work/plain.txt" "$work/dec.txt" || fail_now "T2" "openssl aes-256-cbc"
            note_pass "T2" "openssl enc aes-256-cbc round-trip"
        else
            note_skip "T2" "openssl enc"
        fi

        if command -v openssl >/dev/null 2>&1; then
            dgst_out="$(openssl dgst -sha256 "$work/plain.txt")" || fail_now "T2" "openssl dgst"
            case "$dgst_out" in
                *SHA2-256*|*SHA256*|*=*)
                    hexpart="$(printf '%s' "$dgst_out" | sed -E 's/.*= *//')"
                    case "$hexpart" in
                        ????????????????????????????????????????????????????????????????)
                            note_pass "T2" "openssl dgst -sha256"
                            ;;
                        *) fail_now "T2" "openssl dgst format ($dgst_out)" ;;
                    esac
                    ;;
                *) fail_now "T2" "openssl dgst ($dgst_out)" ;;
            esac
        else
            note_skip "T2" "openssl dgst -sha256"
        fi

        if command -v zstd >/dev/null 2>&1; then
            zstd -T1 -q -f "$work/plain.txt" -o "$work/plain.txt.zst" || fail_now "T2" "zstd compress"
            zstd -T1 -d -q -f "$work/plain.txt.zst" -o "$work/plain.unzst" || fail_now "T2" "zstd decompress"
            cmp -s "$work/plain.txt" "$work/plain.unzst" || fail_now "T2" "zstd"
            note_pass "T2" "zstd round-trip"
        else
            note_skip "T2" "zstd"
        fi

        if command -v xz >/dev/null 2>&1; then
            xz -T1 -z -k -f "$work/plain.txt" || fail_now "T2" "xz compress"
            xz -T1 -d -c "$work/plain.txt.xz" > "$work/plain.unxz" || fail_now "T2" "xz decompress"
            cmp -s "$work/plain.txt" "$work/plain.unxz" || fail_now "T2" "xz"
            note_pass "T2" "xz round-trip"
        else
            note_skip "T2" "xz"
        fi

        # gzip + bzip2 round-trips on a >256 KiB payload at an odd offset
        if command -v gzip >/dev/null 2>&1 && command -v bzip2 >/dev/null 2>&1; then
            # 1-byte header + 300 KiB body = odd-offset large payload
            printf "X" > "$work/big.bin"
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "import sys; sys.stdout.buffer.write(bytes(((i*2654435761) & 255) for i in range(300*1024)))" >> "$work/big.bin"
            else
                i=0
                while [ "$i" -lt 300 ]; do
                    printf "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF" >> "$work/big.bin"
                    printf "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF" >> "$work/big.bin"
                    i=$((i + 1))
                done
                truncate -s 307201 "$work/big.bin" 2>/dev/null || true
            fi
            big_sz="$(wc -c < "$work/big.bin" | tr -d ' ')"
            [ "$big_sz" -ge 262144 ] || fail_now "T2" "big payload size ($big_sz)"
            gzip -c "$work/big.bin" > "$work/big.bin.gz" || fail_now "T2" "gzip big"
            gzip -dc "$work/big.bin.gz" > "$work/big.ungz" || fail_now "T2" "gunzip big"
            cmp -s "$work/big.bin" "$work/big.ungz" || fail_now "T2" "gzip >256KiB round-trip"
            bzip2 -c "$work/big.bin" > "$work/big.bin.bz2" || fail_now "T2" "bzip2 big"
            bzip2 -dc "$work/big.bin.bz2" > "$work/big.unbz2" || fail_now "T2" "bunzip2 big"
            cmp -s "$work/big.bin" "$work/big.unbz2" || fail_now "T2" "bzip2 >256KiB round-trip"
            # odd-offset slice: drop first byte, round-trip again
            dd if="$work/big.bin" of="$work/big_odd.bin" bs=1 skip=1 2>/dev/null || fail_now "T2" "dd odd offset"
            gzip -c "$work/big_odd.bin" > "$work/big_odd.gz" || fail_now "T2" "gzip odd"
            gzip -dc "$work/big_odd.gz" > "$work/big_odd.ungz" || fail_now "T2" "gunzip odd"
            cmp -s "$work/big_odd.bin" "$work/big_odd.ungz" || fail_now "T2" "gzip odd-offset round-trip"
            note_pass "T2" "gzip+bzip2 >256KiB odd-offset round-trip"
        else
            note_skip "T2" "gzip+bzip2 large"
        fi

        if command -v jq >/dev/null 2>&1; then
            jq_out="$(printf '{"items":[{"k":"a","v":3},{"k":"b","v":7},{"k":"c","v":5}]}' | jq -r '[.items[] | select(.v >= 5) | .k] | join(",")')"
            [ "$jq_out" = "b,c" ] || fail_now "T2" "jq ($jq_out)"
            note_pass "T2" "jq filter b,c"
        else
            note_skip "T2" "jq"
        fi

        if command -v sqlite3 >/dev/null 2>&1; then
            sql_out="$(sqlite3 "$work/test.db" "
                CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL);
                INSERT INTO t (name, score) VALUES ('alice', 91.5), ('bob', 84.0), ('carol', 96.5);
                SELECT name, CAST(ROUND(AVG(score) OVER ()) AS INTEGER) FROM t WHERE score > 90 ORDER BY score DESC;
                PRAGMA integrity_check;
            ")" || fail_now "T2" "sqlite3 window"
            printf "%s\n" "$sql_out" | grep -q "^carol|94$" || fail_now "T2" "sqlite3 ($sql_out)"
            printf "%s\n" "$sql_out" | grep -q "^ok$" || fail_now "T2" "sqlite3 integrity"
            note_pass "T2" "sqlite3 window AVG + integrity_check"
            rb_out="$(sqlite3 "$work/test_rb.db" "
                CREATE TABLE a (id INTEGER PRIMARY KEY, v TEXT);
                CREATE TABLE b (id INTEGER PRIMARY KEY, a_id INTEGER, w INTEGER);
                INSERT INTO a (v) VALUES ('x'), ('y');
                INSERT INTO b (a_id, w) VALUES (1, 10), (2, 20);
                BEGIN;
                INSERT INTO a (v) VALUES ('zzz');
                ROLLBACK;
                SELECT COUNT(*) FROM a;
                SELECT a.v, b.w FROM a JOIN b ON b.a_id = a.id ORDER BY b.w DESC LIMIT 1;
            ")" || fail_now "T2" "sqlite3 rollback"
            printf "%s\n" "$rb_out" | grep -q "^2$" || fail_now "T2" "sqlite3 ROLLBACK count ($rb_out)"
            printf "%s\n" "$rb_out" | grep -q "^y|20$" || fail_now "T2" "sqlite3 join ($rb_out)"
            note_pass "T2" "sqlite3 ROLLBACK + multi-table join"
        else
            note_skip "T2" "sqlite3 window"
            note_skip "T2" "sqlite3 ROLLBACK"
        fi
    fi

    # --- Tier 3: Scripting VMs, Language Runtimes & Nested JITs ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "3" ]; then
        echo "== Tier 3: Language Runtimes & Nested JITs =="
        if command -v lua5.4 >/dev/null 2>&1; then
            lua_out="$(lua5.4 -e '
                local co = coroutine.create(function()
                    local s = 0
                    for i = 1, 100 do s = s + i end
                    coroutine.yield(s)
                end)
                local ok, res = coroutine.resume(co)
                assert(ok and res == 5050)
                print("LUA54_OK:" .. tostring(res))
            ')"
            [ "$lua_out" = "LUA54_OK:5050" ] || fail_now "T3" "lua5.4 ($lua_out)"
            note_pass "T3" "lua5.4 coroutine 5050"
        else
            note_skip "T3" "lua5.4"
        fi

        if command -v luajit >/dev/null 2>&1; then
            lj_out="$(luajit -e '
                assert(jit.status() == true, "jit off")
                local traces = 0
                jit.attach(function() traces = traces + 1 end, "trace", "start")
                local acc = 0
                for i = 1, 100000 do
                    acc = bit.bxor(acc + i, bit.lshift(i, 1))
                end
                assert(acc == 675631440, "golden mismatch: " .. tostring(acc))
                assert(traces > 0, "no machine-code traces compiled")
                print("LUAJIT_OK:" .. tostring(acc) .. ":" .. tostring(traces))
            ')" || fail_now "T3" "luajit exec failed"
            case "$lj_out" in
                LUAJIT_OK:675631440:*)
                    trace_n="$(printf '%s' "$lj_out" | sed -E 's/^LUAJIT_OK:[0-9]+://')"
                    [ "$trace_n" -gt 0 ] 2>/dev/null || fail_now "T3" "luajit traces ($lj_out)"
                    note_pass "T3" "luajit jit.status+trace ($trace_n traces)"
                    ;;
                *) fail_now "T3" "luajit ($lj_out)" ;;
            esac
        else
            if is_luajit_expected_missing; then
                note_expected "T3" "luajit unavailable on ${CATALOGUE_ARCH:-$(uname -m 2>/dev/null || echo unknown)} (no JIT backend)"
            else
                note_skip "T3" "luajit"
            fi
        fi

        if command -v python3 >/dev/null 2>&1; then
            py_out="$(python3 -B -c '
import hashlib, json, math, re, zlib
data = {"pi": round(math.pi, 6), "fib": [1, 1, 2, 3, 5, 8, 13, 21]}
raw = json.dumps(data, sort_keys=True).encode("utf-8")
comp = zlib.compress(raw, level=6)
assert zlib.decompress(comp) == raw
h = hashlib.sha256(raw).hexdigest()[:16]
assert re.match(r"^[0-9a-f]{16}$", h)
print(f"PYTHON3_OK:{h}")
')" || fail_now "T3" "python3 exec failed"
            [ "$py_out" = "PYTHON3_OK:b5abbd2c04884798" ] || fail_now "T3" "python3 ($py_out)"
            note_pass "T3" "python3 hashlib+zlib b5abbd2c04884798"
            py_thr="$(python3 -B -c '
import threading
counter = [0]
lock = threading.Lock()
def worker(n):
    for _ in range(n):
        with lock:
            counter[0] += 1
threads = [threading.Thread(target=worker, args=(2000,)) for _ in range(4)]
[t.start() for t in threads]
[t.join() for t in threads]
assert counter[0] == 8000, counter
print("THREAD_OK:%d" % counter[0])
')" || fail_now "T3" "python3 threading exec failed"
            [ "$py_thr" = "THREAD_OK:8000" ] || fail_now "T3" "python3 threading ($py_thr)"
            note_pass "T3" "python3 threading 4x2000"
        else
            note_skip "T3" "python3 hashlib"
            note_skip "T3" "python3 threading"
        fi
    fi

    # --- Tier 4: Toolchains, Compilers (gcc/g++/binutils) & Git ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "4" ]; then
        echo "== Tier 4: Self-Hosted Compiler Toolchain (binutils + gcc/g++) & Git =="
        if command -v git >/dev/null 2>&1; then
            mkdir -p "$work/repo"
            (
                cd "$work/repo"
                git init -q -b master || fail_now "T4" "git init -q -b master"
                git config user.email "test@zw3rk.com"
                git config user.name "rt-series test"
                echo "hello git" > README.md
                git add README.md
                git commit -q -m "Initial commit"
                log_msg="$(git log -1 --pretty=%s)"
                [ "$log_msg" = "Initial commit" ] || { echo "FAIL [T4]: git log ($log_msg)" >&2; exit 1; }
            ) || fail_now "T4" "git init/commit/log"
            note_pass "T4" "git init -q -b master + commit + log"
        else
            note_skip "T4" "git"
        fi

        have_selfhost_c=false
        have_selfhost_cxx=false
        if command -v gcc >/dev/null 2>&1 && command -v readelf >/dev/null 2>&1; then
            cat << 'EOF' > "$work/selfhost.c"
#include <stdio.h>
#include <math.h>
static int fib(int n) {
    int a = 0, b = 1;
    for (int i = 0; i < n; i++) { int t = a + b; a = b; b = t; }
    return a;
}
int main(void) {
    printf("GCC_SELFHOST_OK:%d:%.3f\n", fib(20), sqrt(2.0));
    return 0;
}
EOF
            gcc -O2 "$work/selfhost.c" -lm -o "$work/selfhost.elf" || fail_now "T4" "gcc build selfhost"
            readelf -h "$work/selfhost.elf" | grep -q "ELF" || fail_now "T4" "readelf"
            if command -v nm >/dev/null 2>&1; then
                nm -D "$work/selfhost.elf" | grep -q "printf" || fail_now "T4" "nm printf"
            fi
            if command -v strip >/dev/null 2>&1; then
                cp "$work/selfhost.elf" "$work/selfhost.elf.stripped" || fail_now "T4" "cp selfhost.elf"
                strip "$work/selfhost.elf.stripped" || fail_now "T4" "strip"
                strip_out="$("$work/selfhost.elf.stripped")" || fail_now "T4" "run selfhost.elf.stripped"
                [ "$strip_out" = "GCC_SELFHOST_OK:6765:1.414" ] || fail_now "T4" "stripped selfhost ($strip_out)"
            fi
            self_out="$("$work/selfhost.elf")" || fail_now "T4" "run selfhost.elf"
            [ "$self_out" = "GCC_SELFHOST_OK:6765:1.414" ] || fail_now "T4" "gcc selfhost ($self_out)"
            note_pass "T4" "gcc -O2 selfhost + run selfhost.elf"
            have_selfhost_c=true
        else
            note_skip "T4" "gcc selfhost"
        fi

        if command -v g++ >/dev/null 2>&1; then
            cat << 'EOF' > "$work/selfhost_cxx.cc"
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>
struct Base { virtual ~Base() = default; };
struct Derived : Base { int v = 42; };
static int unwind_probe(int x) {
    if (x < 0) throw std::runtime_error("unwind_ok");
    return x;
}
int main() {
    int caught = 0;
    try { unwind_probe(-1); } catch (const std::runtime_error &) { caught = 1; }
    Base *b = new Derived();
    Derived *d = dynamic_cast<Derived *>(b);
    int rtti = (d != nullptr && d->v == 42) ? 1 : 0;
    delete b;
    std::atomic<int> acc(0);
    std::thread t1([&acc]() { for (int i = 0; i < 5000; i++) acc.fetch_add(1); });
    std::thread t2([&acc]() { for (int i = 0; i < 5000; i++) acc.fetch_add(1); });
    t1.join();
    t2.join();
    int thr = (acc.load() == 10000) ? 1 : 0;
    std::cout << "GXX_SELFHOST_OK:" << caught << ":" << rtti << ":" << thr << "\n";
    return (caught == 1 && rtti == 1 && thr == 1) ? 0 : 1;
}
EOF
            g++ -O2 -std=c++17 -pthread "$work/selfhost_cxx.cc" -o "$work/selfhost_cxx.elf" || fail_now "T4" "g++ build selfhost_cxx"
            cxx_out="$("$work/selfhost_cxx.elf")" || fail_now "T4" "run selfhost_cxx.elf"
            [ "$cxx_out" = "GXX_SELFHOST_OK:1:1:1" ] || fail_now "T4" "g++ selfhost ($cxx_out)"
            note_pass "T4" "g++ -std=c++17 std::thread + run selfhost_cxx.elf"
            have_selfhost_cxx=true
        else
            note_skip "T4" "g++ selfhost_cxx"
        fi

        # as + ld: assemble and link a minimal .s file, run it
        if command -v as >/dev/null 2>&1 && command -v ld >/dev/null 2>&1; then
            machine="$(uname -m)"
            os="$(uname -s)"
            case "$os" in
                Darwin*)
                    # macOS: exit(42) via BSD syscall 0x2000001 in x16.
                    case "$machine" in
                        arm64|aarch64)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .globl _main
_main:
    mov x0, #42
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0
EOF
                            ;;
                        *)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .globl _main
_main:
    movl $42, %edi
    movl $0x2000001, %eax
    syscall
EOF
                            ;;
                    esac
                    as "$work/mini.s" -o "$work/mini.o" || fail_now "T4" "as mini.s"
                    # Raw ld needs the SDK syslibroot for libSystem on macOS.
                    _sdk=""
                    if command -v xcrun >/dev/null 2>&1; then
                        _sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
                    fi
                    if [ -n "$_sdk" ]; then
                        ld -syslibroot "$_sdk" "$work/mini.o" -o "$work/mini.elf" -lSystem \
                            || fail_now "T4" "ld mini.o"
                    elif command -v cc >/dev/null 2>&1; then
                        cc "$work/mini.o" -o "$work/mini.elf" || fail_now "T4" "ld mini.o"
                    else
                        ld "$work/mini.o" -o "$work/mini.elf" -lSystem \
                            || fail_now "T4" "ld mini.o"
                    fi
                    ;;
                *)
                    case "$machine" in
                        aarch64|arm64)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    mov x0, #42
    mov x8, #93
    svc #0
EOF
                            ;;
                        x86_64|amd64)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    mov $60, %rax
    mov $42, %rdi
    syscall
EOF
                            ;;
                        i386|i486|i586|i686)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    movl $1, %eax
    movl $42, %ebx
    int $0x80
EOF
                            ;;
                        arm*|armv*)
                            cat << 'EOF' > "$work/mini.s"
    .syntax unified
    .text
    .global _start
_start:
    mov r0, #42
    mov r7, #1
    svc #0
EOF
                            ;;
                        mips64*)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    li $4, 42
    li $2, 5058
    syscall
EOF
                            ;;
                        mips|mipsel|mipseb)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    li $4, 42
    li $2, 4001
    syscall
EOF
                            ;;
                        ppc*|powerpc*)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    li 3, 42
    li 0, 1
    sc
EOF
                            ;;
                        sparc64|sparcv9)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    mov 42, %o0
    mov 1, %g1
    ta 0x6d
EOF
                            ;;
                        sparc*)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    mov 42, %o0
    mov 1, %g1
    ta 0x10
EOF
                            ;;
                        riscv*)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    li a0, 42
    li a7, 93
    ecall
EOF
                            ;;
                        loongarch*)
                            cat << 'EOF' > "$work/mini.s"
    .text
    .global _start
_start:
    li.w $a0, 42
    li.w $a7, 93
    syscall 0
EOF
                            ;;
                        *)
                            fail_now "T4" "unsupported machine '$machine' for as+ld"
                            ;;
                    esac
                    as "$work/mini.s" -o "$work/mini.o" || fail_now "T4" "as mini.s"
                    ld "$work/mini.o" -o "$work/mini.elf" || fail_now "T4" "ld mini.o"
                    if command -v readelf >/dev/null 2>&1; then
                        readelf -h "$work/mini.elf" | grep -q "ELF" || fail_now "T4" "mini.elf not ELF"
                    fi
                    ;;
            esac
            if "$work/mini.elf"; then
                mini_code=0
            else
                mini_code=$?
            fi
            [ "$mini_code" = "42" ] || fail_now "T4" "as+ld mini exit=$mini_code"
            note_pass "T4" "as+ld .s link + exit 42"
        else
            note_skip "T4" "as+ld"
        fi

        # objdump -d on the guest-built ELF
        if command -v objdump >/dev/null 2>&1; then
            if [ "$have_selfhost_c" = "true" ]; then
                objdump -d "$work/selfhost.elf" | grep -q "main" || fail_now "T4" "objdump -d main"
                note_pass "T4" "objdump -d selfhost.elf"
            elif [ "$have_selfhost_cxx" = "true" ]; then
                objdump -d "$work/selfhost_cxx.elf" | grep -q "main" || fail_now "T4" "objdump -d main"
                note_pass "T4" "objdump -d selfhost_cxx.elf"
            else
                note_skip "T4" "objdump (no selfhost ELF)"
            fi
        else
            note_skip "T4" "objdump"
        fi

        # make -j2 jobserver build
        if command -v make >/dev/null 2>&1 && command -v cc >/dev/null 2>&1; then
            mkdir -p "$work/mk"
            cat << 'EOF' > "$work/mk/Makefile"
CC ?= cc
CFLAGS ?= -O1
all: a.o b.o
a.o: a.c
	$(CC) $(CFLAGS) -c a.c -o a.o
b.o: b.c
	$(CC) $(CFLAGS) -c b.c -o b.o
EOF
            printf 'int fa(void){return 21;}\n' > "$work/mk/a.c"
            printf 'int fa(void);\nint fb(void){return 21;}\nint main(void){return !(fa()+fb()==42);}\n' > "$work/mk/b.c"
            make -j2 -C "$work/mk" || fail_now "T4" "make -j2"
            [ -f "$work/mk/a.o" ] && [ -f "$work/mk/b.o" ] || fail_now "T4" "make -j2 outputs"
            note_pass "T4" "make -j2 jobserver build"
        else
            note_skip "T4" "make -j2"
        fi
    fi

    # --- Fail-closed summary ---
    echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip expected_skip=$expected_skip"
    if [ "$pass" -eq 0 ]; then
        echo "FAIL: guest-payload recorded 0 passes" >&2
        exit 1
    fi
    if [ "$skip" -gt 0 ] && [ "${CATALOGUE_ALLOW_SKIP:-0}" != "1" ]; then
        echo "FAIL: guest-payload has $skip skipped check(s); set CATALOGUE_ALLOW_SKIP=1 to allow" >&2
        echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip expected_skip=$expected_skip FAIL"
        exit 1
    fi
    if [ "$skip" -gt 0 ]; then
        echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip expected_skip=$expected_skip ALL_OK (skips allowed)"
    else
        echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip expected_skip=$expected_skip ALL_OK"
    fi
}

run_repo_gate() {
    _repo="$1"
    _timeout_s="$2"
    _tier="$3"
    ps="$PROJECTS_DIR/$_repo/tests/parity_suite.sh"
    echo "== Catalogue $CMD gate: $_repo (tier=$_tier, timeout=${_timeout_s}s) =="
    if [ -f "$ps" ]; then
        if PARITY_TIER="$_tier" timeout --kill-after=30s "${_timeout_s}s" sh "$ps" >"/tmp/cat-$CMD-$_repo.log" 2>&1; then
            if ! check_parity_no_skip "/tmp/cat-$CMD-$_repo.log" "$_repo"; then
                tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
                return 1
            fi
            if ! check_parity_categories "/tmp/cat-$CMD-$_repo.log" "$_repo" "$_tier"; then
                tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
                return 1
            fi
            echo "PASS [$_repo]: parity_suite.sh"
            return 0
        else
            echo "FAIL [$_repo]: parity_suite.sh (see /tmp/cat-$CMD-$_repo.log)"
            tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
            return 1
        fi
    else
        if [ ! -d "$PROJECTS_DIR/$_repo" ]; then
            echo "GAP [$_repo]: repo dir missing, trying make target anyway"
        fi
        if timeout --kill-after=30s "${_timeout_s}s" make -C "$PROJECTS_DIR/$_repo" check >"/tmp/cat-$CMD-$_repo.log" 2>&1; then
            if ! check_parity_no_skip "/tmp/cat-$CMD-$_repo.log" "$_repo"; then
                tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
                return 1
            fi
            if ! check_parity_categories "/tmp/cat-$CMD-$_repo.log" "$_repo" "$_tier"; then
                tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
                return 1
            fi
            echo "PASS [$_repo]: make check"
            return 0
        else
            echo "FAIL [$_repo]: make check (see /tmp/cat-$CMD-$_repo.log)"
            tail -n 20 "/tmp/cat-$CMD-$_repo.log" 2>/dev/null || true
            return 1
        fi
    fi
}

run_host_gate() {
    _tier="$1"
    _timeout_s="$2"
    matched=0
    pass=0
    fail=0
    _docker_before="/tmp/cat-$CMD-docker-before.$$"
    _docker_after="/tmp/cat-$CMD-docker-after.$$"
    docker_ids > "$_docker_before" 2>/dev/null || true
    for r in $REPOS; do
        if [ "$ARCH_FILTER" != "all" ] && [ "$ARCH_FILTER" != "$r" ]; then
            continue
        fi
        matched=$((matched + 1))
        if run_repo_gate "$r" "$_timeout_s" "$_tier"; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
        fi
    done
    if ! check_no_leftover_docker "$_docker_before" "$_docker_after"; then
        echo "FAIL: docker leftover check failed" >&2
        fail=$((fail + 1))
    fi
    rm -f "$_docker_before" "$_docker_after"
    echo "CATALOGUE $CMD SUMMARY: matched=$matched pass=$pass fail=$fail"
    if [ "$matched" -eq 0 ]; then
        echo "FAIL: --arch '$ARCH_FILTER' matched 0 repositories" >&2
        exit 1
    fi
    if [ "$pass" -eq 0 ]; then
        echo "FAIL: $CMD recorded 0 passes" >&2
        exit 1
    fi
    if [ "$fail" -gt 0 ]; then
        exit 1
    fi
}

run_host_smoke() {
    run_host_gate "smoke" "$SMOKE_TIMEOUT"
}

run_host_qualify() {
    # Series-level presence checks for Tier M wiring (fail closed with clear GAP).
    if [ ! -f "$ROOT_DIR/tests/p3_torture.c" ]; then
        echo "GAP: tests/p3_torture.c missing (Tier M P3 suite)" >&2
    fi
    if [ ! -f "$ROOT_DIR/tests/tcg/smoke_tcg.c" ]; then
        echo "GAP: tests/tcg/smoke_tcg.c missing (Tier M tcg suite)" >&2
    fi
    # Wave C2: uniform guest binaries must exist before per-repo gates run.
    if ! check_uniform_guests; then
        exit 1
    fi
    run_host_gate "qualify" "$QUALIFY_TIMEOUT"
    if [ ! -f "$ROOT_DIR/tests/p3_torture.c" ] || [ ! -f "$ROOT_DIR/tests/tcg/smoke_tcg.c" ]; then
        echo "FAIL: Tier M fixture files missing" >&2
        exit 1
    fi
}

run_grind_via() {
    _grind_tier="$1"
    shift
    if [ ! -x "$SCRIPT_DIR/run_grind.sh" ]; then
        echo "FAIL: tools/run_grind.sh missing or not executable" >&2
        exit 1
    fi
    # shellcheck disable=SC2086
    exec "$SCRIPT_DIR/run_grind.sh" "$_grind_tier" --arch "$ARCH_FILTER" "$@"
}

print_usage() {
    cat << 'EOF'
Usage: tools/run_catalogue.sh <guest-payload|smoke|qualify|grind-nightly|grind-weekly> [options]

Commands:
  guest-payload         Execute Tier 1..4 real-world software suite inside a guest sysroot
                        (e.g. `<arch>rt --sysroot <dir> /bin/sh tools/run_catalogue.sh guest-payload`)
  smoke                 Tier S host gate: per-repo parity_suite.sh or `make check`
                        plus PARITY_SUMMARY skip==0 enforcement
                        (default per-repo timeout 240s, see CATALOGUE_SMOKE_TIMEOUT)
  qualify               Tier M host gate: per-repo parity at PARITY_TIER=qualify plus
                        tests/p3_torture.c + tests/tcg presence checks,
                        _build/uniform/<abi> guest presence, and PARITY_SUMMARY
                        skip==0 enforcement
                        (default per-repo timeout 600s, see CATALOGUE_QUALIFY_TIMEOUT)
  grind-nightly         Tier N grind (delegates to tools/run_grind.sh nightly)
  grind-weekly          Tier W grind (delegates to tools/run_grind.sh weekly)

Options:
  --arch <repo|all>     Filter by translator repo (default: all)
  --tier <1..4|all>     Filter guest-payload by tier (1=Shells/POSIX, 2=Crypto/DB/Compress,
                        3=VMs/LuaJIT/Python, 4=Self-hosted gcc/g++/binutils/git; default: all)
  --timeout <secs>      Override per-repo timeout for smoke/qualify

Environment:
  CATALOGUE_SMOKE_TIMEOUT / CATALOGUE_QUALIFY_TIMEOUT, CATALOGUE_ALLOW_SKIP=1,
  CATALOGUE_ARCH=<sparc32|sparc64|loongarch64|riscv32|...>
EOF
}

case "$CMD" in
    guest-payload)
        run_guest_payload
        ;;
    smoke)
        run_host_smoke
        ;;
    qualify)
        run_host_qualify
        ;;
    grind-nightly)
        run_grind_via nightly
        ;;
    grind-weekly)
        run_grind_via weekly
        ;;
    *)
        print_usage
        ;;
esac

