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

# Shared Tier 4 payload emitters (keeps both files <= 900 lines).
# shellcheck source=tools/catalogue_payloads.sh
. "$SCRIPT_DIR/catalogue_payloads.sh"

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

# check_parity_no_skip <logfile> <repo> [require_summary]: fail when the log is
# empty, when any PARITY_ROW has FAIL/GAP (or SKIP unless CATALOGUE_ALLOW_SKIP=1),
# or when PARITY_SUMMARY is missing/malformed or reports repo!=<repo>, pass==0,
# fail>0, gap>0, or skip>0 (unless CATALOGUE_ALLOW_SKIP=1).
check_parity_no_skip() {
    _cns_log="$1"
    _cns_repo="$2"
    _cns_req_sum="${3:-1}"
    if [ ! -s "$_cns_log" ]; then
        echo "FAIL [$_cns_repo]: empty or missing gate log $_cns_log" >&2
        return 1
    fi
    if grep -qE '^PARITY_ROW	.*	(FAIL|GAP)	' "$_cns_log" 2>/dev/null; then
        echo "FAIL [$_cns_repo]: PARITY_ROW contains FAIL or GAP in $_cns_log" >&2
        return 1
    fi
    if [ "${CATALOGUE_ALLOW_SKIP:-0}" != "1" ] && grep -qE '^PARITY_ROW	.*	SKIP	' "$_cns_log" 2>/dev/null; then
        echo "FAIL [$_cns_repo]: PARITY_ROW contains SKIP in $_cns_log; set CATALOGUE_ALLOW_SKIP=1 to allow" >&2
        return 1
    fi
    if [ "$_cns_req_sum" = "1" ] || grep -qE '^PARITY_SUMMARY' "$_cns_log" 2>/dev/null; then
        if ! awk -v repo="$_cns_repo" -v allow_skip="${CATALOGUE_ALLOW_SKIP:-0}" '
            /^PARITY_SUMMARY/ {
                n++
                if ($0 !~ /^PARITY_SUMMARY repo=[^ ]+ pass=[0-9]+ fail=[0-9]+ gap=[0-9]+ skip=[0-9]+$/) {
                    bad_syntax = 1
                }
                r = $2; sub(/^repo=/, "", r)
                p = $3; sub(/^pass=/, "", p)
                f = $4; sub(/^fail=/, "", f)
                g = $5; sub(/^gap=/, "", g)
                s = $6; sub(/^skip=/, "", s)
                if (r != repo) bad_repo = 1
                if (p + 0 <= 0) zero_pass = 1
                tot_pass += p + 0
                tot_fail += f + 0
                tot_gap  += g + 0
                tot_skip += s + 0
            }
            END {
                if (n == 0 || bad_syntax || bad_repo || zero_pass || tot_pass <= 0 || tot_fail > 0 || tot_gap > 0) {
                    exit 1
                }
                if (tot_skip > 0 && allow_skip != "1") {
                    exit 2
                }
                exit 0
            }
        ' "$_cns_log"; then
            echo "FAIL [$_cns_repo]: invalid or failing PARITY_SUMMARY in $_cns_log" >&2
            return 1
        fi
    fi
    return 0
}

required_repo_abis() {
    case "$1" in
        a32rt)         echo "armhf armel" ;;
        i686rt)        echo "i686" ;;
        mips32rt)      echo "mipsel mips" ;;
        ppc32rt)       echo "ppc32" ;;
        sparc32rt)     echo "sparc32" ;;
        rvrt)          echo "riscv64 riscv32" ;;
        loongarch64rt) echo "loongarch64" ;;
        ppc64rt)       echo "ppc64le" ;;
        mips64rt)      echo "mips64el mips64eb" ;;
        sparc64rt)     echo "sparc64" ;;
        *)             echo "" ;;
    esac
}

# check_parity_categories <logfile> <repo> <tier>: in qualify mode, parse
# tab-separated PARITY_ROW fields and verify that every required (abi, engine,
# category) tuple for <repo> has an explicit PASS row on the exact case column.
check_parity_categories() {
    _cpc_log="$1"
    _cpc_repo="$2"
    _cpc_tier="$3"
    if [ "$_cpc_tier" != "qualify" ]; then
        return 0
    fi
    _cpc_abis="$(required_repo_abis "$_cpc_repo")"
    if [ -z "$_cpc_abis" ]; then
        echo "FAIL [$_cpc_repo]: unknown repository for ABI matrix" >&2
        return 1
    fi
    if ! awk -F '\t' -v repo="$_cpc_repo" -v req_abis="$_cpc_abis" '
        function norm_abi(a) {
            if (a == "o32le") return "mipsel"
            if (a == "o32be") return "mips"
            if (a == "rv64" || a == "rv64gc") return "riscv64"
            if (a == "rv32" || a == "rv32gc") return "riscv32"
            if (a == "lp64d") return "loongarch64"
            if (a == "elfv2") return "ppc64le"
            if (a == "n64le") return "mips64el"
            if (a == "n64be") return "mips64eb"
            if (a == "v8") return "sparc32"
            if (a == "v9") return "sparc64"
            return a
        }
        function map_cat(c) {
            if (c ~ /^(p3-torture|p3_torture|p3torture)(-[a-z0-9_]+)?$/) return "p3-torture"
            if (c ~ /^(tcg-smoke|tcg_smoke|smoke-tcg)(-[a-z0-9_]+)?$/) return "tcg-smoke"
            if (c ~ /^(dyn-pie|p5_dyn|p5-dyn|test_p5_dyn)(-[a-z0-9_]+)?$/) return "dyn-pie"
            if (c ~ /^(t1-busybox|t1_busybox|busybox-t1|guest-payload-t1)(-[a-z0-9_]+)?$/) return "t1-busybox"
            if (c ~ /^(t2-core|t2_core|guest-payload-t2)(-[a-z0-9_]+)?$/) return "t2-core"
            if (c ~ /^(t3-system|t3_system|guest-payload-t3)(-[a-z0-9_]+)?$/) return "t3-system"
            if (c ~ /^(t4-compiler|t4_compiler|h4_cxx|test_h4_cxx|guest-payload-t4)(-[a-z0-9_]+)?$/) return "t4-compiler"
            return ""
        }
        BEGIN {
            n_abis = split(req_abis, abis, " ")
            n_cats = split("p3-torture tcg-smoke dyn-pie t1-busybox t2-core t3-system t4-compiler", cats, " ")
        }
        $1 == "PARITY_ROW" && $2 == repo && $7 == "PASS" {
            abi = norm_abi($3)
            cat = map_cat($5)
            eng = $6
            if (cat == "") next
            has_interp = (eng ~ /(^|[,+\/])(interp|dual|both)($|[,+\/])/)
            has_dbt    = (eng ~ /(^|[,+\/])(dbt|dual|both)($|[,+\/])/)
            if (has_interp) seen[abi, "interp", cat] = 1
            if (has_dbt)    seen[abi, "dbt", cat] = 1
        }
        END {
            missing = ""
            for (i = 1; i <= n_abis; i++) {
                a = abis[i]
                for (e_idx = 1; e_idx <= 2; e_idx++) {
                    e = (e_idx == 1) ? "interp" : "dbt"
                    for (c_idx = 1; c_idx <= n_cats; c_idx++) {
                        c = cats[c_idx]
                        if (!seen[a, e, c]) {
                            missing = missing (missing ? " " : "") a "/" e "/" c
                        }
                    }
                }
            }
            if (missing != "") {
                printf "FAIL [%s]: qualify log missing PASS tuple(s): %s\n", repo, missing > "/dev/stderr"
                exit 1
            }
            exit 0
        }
    ' "$_cpc_log"; then
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
    _cat_work="$work"
    cat_cleanup() { rm -rf "$_cat_work" 2>/dev/null; }
    trap '_rc=$?; cat_cleanup; exit $_rc' EXIT
    trap 'cat_cleanup; exit 130' INT
    trap 'cat_cleanup; exit 143' TERM

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
    # Payload emitters + toolchain checks live in tools/catalogue_payloads.sh.
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "4" ]; then
        catalogue_run_tier4 "$work"
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
    _log_file="$4"
    ps="$PROJECTS_DIR/$_repo/tests/parity_suite.sh"
    echo "== Catalogue $CMD gate: $_repo (tier=$_tier, timeout=${_timeout_s}s) =="
    if [ -f "$ps" ]; then
        if PARITY_TIER="$_tier" timeout --kill-after=30s "${_timeout_s}s" sh "$ps" >"$_log_file" 2>&1; then
            if ! check_parity_no_skip "$_log_file" "$_repo" 1; then
                tail -n 20 "$_log_file" 2>/dev/null || true
                return 1
            fi
            if ! check_parity_categories "$_log_file" "$_repo" "$_tier"; then
                tail -n 20 "$_log_file" 2>/dev/null || true
                return 1
            fi
            echo "PASS [$_repo]: parity_suite.sh"
            return 0
        else
            echo "FAIL [$_repo]: parity_suite.sh (see $_log_file)"
            tail -n 20 "$_log_file" 2>/dev/null || true
            return 1
        fi
    else
        if [ ! -d "$PROJECTS_DIR/$_repo" ]; then
            echo "GAP [$_repo]: repo dir missing, trying make target anyway"
        fi
        if timeout --kill-after=30s "${_timeout_s}s" make -C "$PROJECTS_DIR/$_repo" check >"$_log_file" 2>&1; then
            if ! check_parity_no_skip "$_log_file" "$_repo" 0; then
                tail -n 20 "$_log_file" 2>/dev/null || true
                return 1
            fi
            if ! check_parity_categories "$_log_file" "$_repo" "$_tier"; then
                tail -n 20 "$_log_file" 2>/dev/null || true
                return 1
            fi
            echo "PASS [$_repo]: make check"
            return 0
        else
            echo "FAIL [$_repo]: make check (see $_log_file)"
            tail -n 20 "$_log_file" 2>/dev/null || true
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
    _gate_dir="$(mktemp -d "/tmp/rt-cat-${CMD}.XXXXXX")"
    _docker_before="$_gate_dir/docker-before"
    _docker_after="$_gate_dir/docker-after"
    docker_ids > "$_docker_before" 2>/dev/null || true
    for r in $REPOS; do
        if [ "$ARCH_FILTER" != "all" ] && [ "$ARCH_FILTER" != "$r" ]; then
            continue
        fi
        matched=$((matched + 1))
        if run_repo_gate "$r" "$_timeout_s" "$_tier" "$_gate_dir/$r.log"; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
        fi
    done
    if ! check_no_leftover_docker "$_docker_before" "$_docker_after"; then
        echo "FAIL: docker leftover check failed" >&2
        fail=$((fail + 1))
    fi
    rm -f "$_docker_before" "$_docker_after" "${_docker_after}.new"
    echo "CATALOGUE $CMD SUMMARY: matched=$matched pass=$pass fail=$fail"
    if [ "$matched" -eq 0 ]; then
        rm -rf "$_gate_dir"
        echo "FAIL: --arch '$ARCH_FILTER' matched 0 repositories" >&2
        exit 1
    fi
    if [ "$pass" -eq 0 ] || [ "$fail" -gt 0 ]; then
        echo "Diagnostic logs preserved in $_gate_dir" >&2
        exit 1
    fi
    rm -rf "$_gate_dir"
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
Note: tools/catalogue_payloads.sh must be present alongside run_catalogue.sh.

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

