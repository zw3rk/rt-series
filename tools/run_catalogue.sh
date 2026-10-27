#!/usr/bin/env bash
# tools/run_catalogue.sh — Multi-Architecture 5-Tier Real-World Software Qualification Runner
#
# Modes:
#   1. `guest-payload` : Runs inside a guest sysroot under `<arch>rt --sysroot <dir> /bin/sh`
#                        and executes Tiers T1..T4 (shells, coreutils/gawk/grep/sed/find/diff,
#                        xz/zstd/openssl/jq/sqlite3, lua5.4/luajit/python3, and self-hosted
#                        binutils + gcc C11 + g++ C++17 + make + git).
#   2. `smoke`         : Host-side orchestrator that runs per-translator qualification gates
#                        across `<arch>rt` repositories (`--arch <arch|all> --tier <1..5|all>`).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_DIR="$(cd "$ROOT_DIR/.." && pwd)"

CMD="${1:-help}"
shift || true

ARCH_FILTER="all"
TIER_FILTER="all"

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
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

run_guest_payload() {
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export HOME="/tmp"
    local work="/tmp/rt_series_cat_$$"
    rm -rf "$work"
    mkdir -p "$work"
    trap 'rm -rf "$work"' EXIT

    local pass=0
    local skip=0

    # --- Tier 1: Shells, Coreutils, Grep, Sed, Gawk, Find, Diff ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "1" ]; then
        echo "== Tier 1: Shells & POSIX Stream Utilities =="
        local sh_out
        sh_out="$(sh -c 'x=17; y=25; echo $((x + y))')"
        [ "$sh_out" = "42" ] || { echo "FAIL [T1]: sh arithmetic ($sh_out)"; exit 1; }
        pass=$((pass + 1))

        printf "gamma\nalpha\nbeta\nalpha\n" | sort | uniq -c | sed -E 's/^[[:space:]]+//' > "$work/sorted.txt"
        grep -q "^2 alpha$" "$work/sorted.txt" || { echo "FAIL [T1]: sort/uniq/sed/grep"; exit 1; }
        pass=$((pass + 1))

        if command -v gawk >/dev/null 2>&1 || command -v awk >/dev/null 2>&1; then
            local awk_bin="awk"
            command -v gawk >/dev/null 2>&1 && awk_bin="gawk"
            local awk_out
            awk_out="$(printf "a 10.5\nb 20.25\na 4.25\n" | "$awk_bin" '{ sum[$1] += $2 } END { printf "%.2f:%.2f", sum["a"], sum["b"] }')"
            [ "$awk_out" = "14.75:20.25" ] || { echo "FAIL [T1]: $awk_bin ($awk_out)"; exit 1; }
            pass=$((pass + 1))
        fi

        mkdir -p "$work/tree_dir/sub1" "$work/tree_dir/sub2"
        echo "one" > "$work/tree_dir/sub1/f1.txt"
        echo "two" > "$work/tree_dir/sub2/f2.txt"
        local found_cnt
        found_cnt="$(find "$work/tree_dir" -name '*.txt' | wc -l | tr -d ' ')"
        [ "$found_cnt" = "2" ] || { echo "FAIL [T1]: find ($found_cnt)"; exit 1; }
        pass=$((pass + 1))
    fi

    # --- Tier 2: Compression, Crypto, JSON & SQLite ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "2" ]; then
        echo "== Tier 2: Compression, Cryptography & Structured Data =="
        printf "The quick brown fox jumps over the lazy dog 0123456789\n" > "$work/plain.txt"

        if command -v openssl >/dev/null 2>&1; then
            openssl enc -aes-256-cbc -pbkdf2 -iter 1000 -pass pass:rt_series_key \
                -in "$work/plain.txt" -out "$work/cipher.bin"
            openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000 -pass pass:rt_series_key \
                -in "$work/cipher.bin" -out "$work/dec.txt"
            cmp -s "$work/plain.txt" "$work/dec.txt" || { echo "FAIL [T2]: openssl aes-256-cbc"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v zstd >/dev/null 2>&1; then
            zstd -T1 -q -f "$work/plain.txt" -o "$work/plain.txt.zst"
            zstd -T1 -d -q -f "$work/plain.txt.zst" -o "$work/plain.unzst"
            cmp -s "$work/plain.txt" "$work/plain.unzst" || { echo "FAIL [T2]: zstd"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v xz >/dev/null 2>&1; then
            xz -T1 -z -k -f "$work/plain.txt"
            xz -T1 -d -c "$work/plain.txt.xz" > "$work/plain.unxz"
            cmp -s "$work/plain.txt" "$work/plain.unxz" || { echo "FAIL [T2]: xz"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v jq >/dev/null 2>&1; then
            local jq_out
            jq_out="$(printf '{"items":[{"k":"a","v":3},{"k":"b","v":7},{"k":"c","v":5}]}' | jq -r '[.items[] | select(.v >= 5) | .k] | join(",")')"
            [ "$jq_out" = "b,c" ] || { echo "FAIL [T2]: jq ($jq_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v sqlite3 >/dev/null 2>&1; then
            local sql_out
            sql_out="$(sqlite3 "$work/test.db" "
                CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL);
                INSERT INTO t (name, score) VALUES ('alice', 91.5), ('bob', 84.0), ('carol', 96.5);
                SELECT name, CAST(ROUND(AVG(score) OVER ()) AS INTEGER) FROM t WHERE score > 90 ORDER BY score DESC;
                PRAGMA integrity_check;
            ")"
            printf "%s\n" "$sql_out" | grep -q "^carol|94$" || { echo "FAIL [T2]: sqlite3 ($sql_out)"; exit 1; }
            printf "%s\n" "$sql_out" | grep -q "^ok$" || { echo "FAIL [T2]: sqlite3 integrity"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi
    fi

    # --- Tier 3: Scripting VMs, Language Runtimes & Nested JITs ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "3" ]; then
        echo "== Tier 3: Language Runtimes & Nested JITs =="
        if command -v lua5.4 >/dev/null 2>&1; then
            local lua_out
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
            [ "$lua_out" = "LUA54_OK:5050" ] || { echo "FAIL [T3]: lua5.4 ($lua_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v luajit >/dev/null 2>&1; then
            local lj_out
            lj_out="$(luajit -e '
                local acc = 0
                for i = 1, 100000 do
                    acc = bit.bxor(acc + i, bit.lshift(i, 1))
                end
                print("LUAJIT_OK:" .. tostring(acc))
            ')"
            [ "$lj_out" = "LUAJIT_OK:675631440" ] || { echo "FAIL [T3]: luajit ($lj_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v python3 >/dev/null 2>&1; then
            local py_out
            py_out="$(python3 -B -c '
import hashlib, json, math, re, zlib
data = {"pi": round(math.pi, 6), "fib": [1, 1, 2, 3, 5, 8, 13, 21]}
raw = json.dumps(data, sort_keys=True).encode("utf-8")
comp = zlib.compress(raw, level=6)
assert zlib.decompress(comp) == raw
h = hashlib.sha256(raw).hexdigest()[:16]
assert re.match(r"^[0-9a-f]{16}$", h)
print(f"PYTHON3_OK:{h}")
')"
            [ "$py_out" = "PYTHON3_OK:b5abbd2c04884798" ] || { echo "FAIL [T3]: python3 ($py_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi
    fi

    # --- Tier 4: Toolchains, Compilers (gcc/g++/binutils) & Git ---
    if [ "$TIER_FILTER" = "all" ] || [ "$TIER_FILTER" = "4" ]; then
        echo "== Tier 4: Self-Hosted Compiler Toolchain (binutils + gcc/g++) & Git =="
        if command -v git >/dev/null 2>&1; then
            mkdir -p "$work/repo"
            (
                cd "$work/repo"
                git init -q -b main
                git config user.email "test@zw3rk.com"
                git config user.name "rt-series test"
                echo "hello git" > README.md
                git add README.md
                git commit -q -m "Initial commit"
                local log_msg
                log_msg="$(git log -1 --pretty=%s)"
                [ "$log_msg" = "Initial commit" ] || { echo "FAIL [T4]: git log ($log_msg)"; exit 1; }
            )
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

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
            gcc -O2 "$work/selfhost.c" -lm -o "$work/selfhost.elf"
            readelf -h "$work/selfhost.elf" | grep -q "ELF" || { echo "FAIL [T4]: readelf"; exit 1; }
            nm -D "$work/selfhost.elf" | grep -q "printf" || { echo "FAIL [T4]: nm"; exit 1; }
            strip "$work/selfhost.elf"
            local self_out
            self_out="$("$work/selfhost.elf")"
            [ "$self_out" = "GCC_SELFHOST_OK:6765:1.414" ] || { echo "FAIL [T4]: gcc selfhost ($self_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi

        if command -v g++ >/dev/null 2>&1; then
            cat << 'EOF' > "$work/selfhost_cxx.cc"
#include <iostream>
#include <stdexcept>
#include <typeinfo>
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
    std::cout << "GXX_SELFHOST_OK:" << caught << ":" << rtti << "\n";
    return (caught == 1 && rtti == 1) ? 0 : 1;
}
EOF
            g++ -O2 -std=c++17 "$work/selfhost_cxx.cc" -o "$work/selfhost_cxx.elf"
            local cxx_out
            cxx_out="$("$work/selfhost_cxx.elf")"
            [ "$cxx_out" = "GXX_SELFHOST_OK:1:1" ] || { echo "FAIL [T4]: g++ selfhost ($cxx_out)"; exit 1; }
            pass=$((pass + 1))
        else
            skip=$((skip + 1))
        fi
    fi

    echo "CATALOGUE PAYLOAD RESULT: pass=$pass skip=$skip ALL_OK"
}

run_host_smoke() {
    local repos=(
        a32rt
        i686rt
        mips32rt
        ppc32rt
        sparc32rt
        rvrt
        loongarch64rt
        ppc64rt
        mips64rt
        sparc64rt
    )
    local pass=0
    local fail=0
    for r in "${repos[@]}"; do
        if [ "$ARCH_FILTER" != "all" ] && [ "$ARCH_FILTER" != "$r" ]; then
            continue
        fi
        local ps="$PROJECTS_DIR/$r/tests/parity_suite.sh"
        if [ -f "$ps" ]; then
            echo "== Catalogue smoke gate: $r =="
            if timeout --kill-after=30s 180s sh "$ps" >/tmp/cat-smoke-"$r".log 2>&1; then
                echo "PASS [$r]: parity_suite.sh"
                pass=$((pass + 1))
            else
                echo "FAIL [$r]: parity_suite.sh (see /tmp/cat-smoke-$r.log)"
                fail=$((fail + 1))
            fi
        fi
    done
    echo "CATALOGUE SMOKE SUMMARY: pass=$pass fail=$fail"
    [ "$fail" -eq 0 ]
}

case "$CMD" in
    guest-payload)
        run_guest_payload
        ;;
    smoke)
        run_host_smoke
        ;;
    *)
        cat << 'EOF'
Usage: tools/run_catalogue.sh <guest-payload|smoke> [options]

Commands:
  guest-payload         Execute Tier 1..4 real-world software suite inside a guest sysroot
                        (e.g. `<arch>rt --sysroot <dir> /bin/sh tools/run_catalogue.sh guest-payload`)
  smoke                 Run host-side parity & qualification gates across `<arch>rt` repos

Options:
  --arch <repo|all>     Filter by translator repo (default: all)
  --tier <1..4|all>     Filter guest-payload by tier (1=Shells/POSIX, 2=Crypto/DB/Compress,
                        3=VMs/LuaJIT/Python, 4=Self-hosted gcc/g++/binutils/git; default: all)
EOF
        ;;
esac
