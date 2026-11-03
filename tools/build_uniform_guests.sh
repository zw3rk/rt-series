#!/bin/sh
# tools/build_uniform_guests.sh — Wave C2-1: cross-compile shared torture guests.
#
# Builds tests/p3_torture.c (-lm) and tests/tcg/smoke_tcg.c (-lm) into
#   _build/uniform/<abi>/{p3_torture,smoke_tcg}
# for all 14 guest ABIs (10 translators):
#   armhf, armel (a32rt), i686 (i686rt), mipsel, mips (mips32rt),
#   ppc32 (ppc32rt), sparc32 (sparc32rt), riscv64, riscv32 (rvrt),
#   loongarch64 (loongarch64rt), ppc64le (ppc64rt),
#   mips64el, mips64eb (mips64rt), sparc64 (sparc64rt).
#
# Every ABI builds inside one bounded Docker run:
#   timeout --kill-after=30s 180s docker run --rm --name "rt-u-${_abi}-$$" ...
#
# Already-built guests are skipped unless FORCE=1, FORCE_REBUILD=1, or a source
# file is newer than the binary. Leftover containers fail the gate.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/_build/uniform"
P3_SRC="$ROOT_DIR/tests/p3_torture.c"
TCG_SRC="$ROOT_DIR/tests/tcg/smoke_tcg.c"
P3_LLSC_H="$ROOT_DIR/tests/p3_llsc.h"
SIG_FAULT_H="$ROOT_DIR/tests/sig_fault_addr.h"
BUILD_RECIPE="$SCRIPT_DIR/build_uniform_guests.sh"
FORCE="${FORCE:-${FORCE_REBUILD:-0}}"
ABI_FILTER="${1:-all}"
OWNED_FILE="/tmp/rt-uniform-owned-$$.list"
: > "$OWNED_FILE" 2>/dev/null || true

# Record an exact container name owned by this invocation.
track_owned_container() {
    printf '%s\n' "$1" >> "$OWNED_FILE" 2>/dev/null || true
}

if [ ! -f "$P3_SRC" ]; then
    echo "GAP: $P3_SRC missing" >&2
    exit 1
fi
if [ ! -f "$TCG_SRC" ]; then
    echo "GAP: $TCG_SRC missing" >&2
    exit 1
fi

# Remove only containers owned by this script invocation (exact names in
# OWNED_FILE plus the "-$$" suffix sweep). Every docker invocation is
# bounded; listing/inspection failures propagate as nonzero results.
cleanup_owned_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    _rm_rc=0
    if [ -f "$OWNED_FILE" ]; then
        while IFS= read -r _owned; do
            [ -n "$_owned" ] || continue
            if timeout --kill-after=30s 30s docker inspect "$_owned" >/dev/null 2>&1; then
                if ! timeout --kill-after=30s 30s docker rm -f "$_owned" >/dev/null 2>&1; then
                    echo "FAIL: could not remove owned container: $_owned" >&2
                    _rm_rc=1
                fi
            fi
        done < "$OWNED_FILE"
    fi
    if ! _left="$(timeout --kill-after=30s 30s docker ps -aq --filter "name=rt-u-" 2>/dev/null)"; then
        echo "FAIL: docker ps failed during owned-container cleanup" >&2
        return 1
    fi
    for _cid in $_left; do
        if ! _cname="$(timeout --kill-after=30s 30s docker inspect --format '{{.Name}}' "$_cid" 2>/dev/null)"; then
            echo "FAIL: docker inspect failed for $_cid during cleanup" >&2
            _rm_rc=1
            continue
        fi
        case "$_cname" in
            *"-$$")
                if ! timeout --kill-after=30s 30s docker rm -f "$_cid" >/dev/null 2>&1; then
                    echo "FAIL: could not remove owned container: ${_cname:-$_cid}" >&2
                    _rm_rc=1
                fi
                ;;
        esac
    done
    return $_rm_rc
}

# Fail when any container owned by this invocation is still present, and
# fail when container state cannot be established (docker ps/inspect error).
verify_no_lingering_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    if [ -f "$OWNED_FILE" ]; then
        while IFS= read -r _owned; do
            [ -n "$_owned" ] || continue
            if timeout --kill-after=30s 30s docker inspect "$_owned" >/dev/null 2>&1; then
                echo "FAIL: lingering owned container: $_owned" >&2
                return 1
            fi
        done < "$OWNED_FILE"
    fi
    if ! _left="$(timeout --kill-after=30s 30s docker ps -aq --filter "name=rt-u-" 2>/dev/null)"; then
        echo "FAIL: docker ps failed during lingering-container verification" >&2
        return 1
    fi
    for _cid in $_left; do
        if ! _cname="$(timeout --kill-after=30s 30s docker inspect --format '{{.Name}}' "$_cid" 2>/dev/null)"; then
            echo "FAIL: docker inspect failed for $_cid during verification" >&2
            return 1
        fi
        case "$_cname" in
            *"-$$")
                echo "FAIL: lingering owned container: ${_cname:-$_cid}" >&2
                return 1
                ;;
        esac
    done
    return 0
}

# EXIT trap: preserve the script's own status, then require owned-container
# removal and a clean lingering-container check to hold as well. A docker
# ps failure or any remaining owned container fails the gate.
on_uniform_exit() {
    _exit_rc=$?
    trap '' EXIT INT TERM
    _trap_rc=0
    cleanup_owned_containers || _trap_rc=1
    verify_no_lingering_containers || _trap_rc=1
    rm -f "$OWNED_FILE" 2>/dev/null || true
    if [ "$_trap_rc" -ne 0 ]; then
        exit 1
    fi
    exit "$_exit_rc"
}

on_uniform_int() {
    trap '' EXIT INT TERM
    cleanup_owned_containers || true
    verify_no_lingering_containers || true
    exit 130
}

on_uniform_term() {
    trap '' EXIT INT TERM
    cleanup_owned_containers || true
    verify_no_lingering_containers || true
    exit 143
}

trap on_uniform_exit EXIT
trap on_uniform_int INT
trap on_uniform_term TERM

already_built() {
    _abi="$1"
    [ "$FORCE" != "1" ] \
        && [ -x "$OUT_DIR/$_abi/p3_torture" ] \
        && [ -x "$OUT_DIR/$_abi/smoke_tcg" ] \
        && [ -f "$P3_LLSC_H" ] \
        && [ -f "$SIG_FAULT_H" ] \
        && ! [ "$P3_SRC" -nt "$OUT_DIR/$_abi/p3_torture" ] \
        && ! [ "$TCG_SRC" -nt "$OUT_DIR/$_abi/smoke_tcg" ] \
        && ! [ "$P3_LLSC_H" -nt "$OUT_DIR/$_abi/p3_torture" ] \
        && ! [ "$P3_LLSC_H" -nt "$OUT_DIR/$_abi/smoke_tcg" ] \
        && ! [ "$SIG_FAULT_H" -nt "$OUT_DIR/$_abi/p3_torture" ] \
        && ! [ "$SIG_FAULT_H" -nt "$OUT_DIR/$_abi/smoke_tcg" ] \
        && ! [ "$BUILD_RECIPE" -nt "$OUT_DIR/$_abi/p3_torture" ] \
        && ! [ "$BUILD_RECIPE" -nt "$OUT_DIR/$_abi/smoke_tcg" ]
}

want_abi() {
    [ "$ABI_FILTER" = "all" ] || [ "$ABI_FILTER" = "$1" ]
}

COMMON_CFLAGS="-std=c11 -O1 -static -pthread -Wall -Wextra -Werror -Werror=vla -pedantic"

# build_trixie_abi <abi> <apt_pkgs> <cc_cmd> [extra_libs]
build_trixie_abi() {
    _abi="$1"
    _pkgs="$2"
    _cc="$3"
    _libs="${4:--lm}"
    if ! want_abi "$_abi"; then return 0; fi
    if already_built "$_abi"; then echo "SKIP [$_abi]: present and up-to-date"; return 0; fi
    mkdir -p "$OUT_DIR/$_abi"
    _cname="rt-u-${_abi}-$$"
    track_owned_container "$_cname"
    echo "== Building uniform guests for $_abi (container=$_cname) =="
    timeout --kill-after=30s 180s docker run --rm --name "$_cname" \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c "
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq $_pkgs
            mkdir -p /w/_build/uniform/$_abi
            $_cc $COMMON_CFLAGS /w/tests/p3_torture.c $_libs -o /w/_build/uniform/$_abi/p3_torture.tmp.$$
            $_cc $COMMON_CFLAGS /w/tests/tcg/smoke_tcg.c $_libs -o /w/_build/uniform/$_abi/smoke_tcg.tmp.$$
            mv /w/_build/uniform/$_abi/p3_torture.tmp.$$ /w/_build/uniform/$_abi/p3_torture
            mv /w/_build/uniform/$_abi/smoke_tcg.tmp.$$ /w/_build/uniform/$_abi/smoke_tcg
        "
}

# build_image_abi <abi> <image> <cc_cmd> [extra_libs]
build_image_abi() {
    _abi="$1"
    _img="$2"
    _cc="$3"
    _libs="${4:--lm}"
    if ! want_abi "$_abi"; then return 0; fi
    if already_built "$_abi"; then echo "SKIP [$_abi]: present and up-to-date"; return 0; fi
    mkdir -p "$OUT_DIR/$_abi"
    _cname="rt-u-${_abi}-$$"
    track_owned_container "$_cname"
    echo "== Building uniform guests for $_abi (image=$_img, container=$_cname) =="
    timeout --kill-after=30s 180s docker run --rm --name "$_cname" \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w "$_img" sh -c "
            set -eu
            mkdir -p /w/_build/uniform/$_abi
            $_cc $COMMON_CFLAGS /w/tests/p3_torture.c $_libs -o /w/_build/uniform/$_abi/p3_torture.tmp.$$
            $_cc $COMMON_CFLAGS /w/tests/tcg/smoke_tcg.c $_libs -o /w/_build/uniform/$_abi/smoke_tcg.tmp.$$
            mv /w/_build/uniform/$_abi/p3_torture.tmp.$$ /w/_build/uniform/$_abi/p3_torture
            mv /w/_build/uniform/$_abi/smoke_tcg.tmp.$$ /w/_build/uniform/$_abi/smoke_tcg
        "
}

build_riscv32() {
    if ! want_abi riscv32; then return 0; fi
    if already_built riscv32; then echo "SKIP [riscv32]: present and up-to-date"; return 0; fi
    mkdir -p "$OUT_DIR/riscv32"
    _cname="rt-u-riscv32-$$"
    track_owned_container "$_cname"
    echo "== Building uniform guests for riscv32 (container=$_cname) =="
    timeout --kill-after=30s 180s docker run --rm --name "$_cname" \
        --platform linux/amd64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c "
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl ca-certificates bzip2
            mkdir -p /opt/rv32 /w/_build/uniform/riscv32
            curl -fsSL -o /tmp/rv32.tgz https://musl.cc/riscv32-linux-musl-cross.tgz
            tar -xzf /tmp/rv32.tgz -C /opt/rv32 --strip-components=1
            rv32cc=\"\$(ls /opt/rv32/bin/*-gcc | head -n 1)\"
            [ -x \"\$rv32cc\" ] || { echo 'GAP: no *-gcc in musl.cc riscv32 toolchain' >&2; exit 1; }
            \"\$rv32cc\" $COMMON_CFLAGS /w/tests/p3_torture.c -lm -o /w/_build/uniform/riscv32/p3_torture.tmp.$$
            \"\$rv32cc\" $COMMON_CFLAGS /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/riscv32/smoke_tcg.tmp.$$
            mv /w/_build/uniform/riscv32/p3_torture.tmp.$$ /w/_build/uniform/riscv32/p3_torture
            mv /w/_build/uniform/riscv32/smoke_tcg.tmp.$$ /w/_build/uniform/riscv32/smoke_tcg
        "
}

build_trixie_abi armhf   "gcc-arm-linux-gnueabihf libc6-dev-armhf-cross" "arm-linux-gnueabihf-gcc"
build_trixie_abi armel   "gcc-arm-linux-gnueabi libc6-dev-armel-cross"   "arm-linux-gnueabi-gcc"
build_trixie_abi i686    "gcc-i686-linux-gnu libc6-dev-i386-cross"       "i686-linux-gnu-gcc"
build_trixie_abi mipsel  "gcc-mipsel-linux-gnu libc6-dev-mipsel-cross"   "mipsel-linux-gnu-gcc -mips32r2"
build_trixie_abi mips    "gcc-mips-linux-gnu libc6-dev-mips-cross"       "mips-linux-gnu-gcc -mips32r2"
build_trixie_abi ppc32   "gcc-powerpc-linux-gnu libc6-dev-powerpc-cross" "powerpc-linux-gnu-gcc"
build_image_abi  sparc32 "sparc32rt-oracle:latest"                       "sparc64-linux-gnu-gcc -m32 -mcpu=v8" "-lm -latomic"
build_trixie_abi riscv64 "gcc-riscv64-linux-gnu libc6-dev-riscv64-cross" "riscv64-linux-gnu-gcc"
build_riscv32
build_image_abi  loongarch64 "loongarch64rt-l3a-tool:latest"             "loongarch64-linux-gnu-gcc"
build_image_abi  ppc64le     "ppc64rt-l3a-tool:latest"                   "powerpc64le-linux-gnu-gcc"
build_image_abi  mips64el    "mips64rt-parity-env:trixie"                "mips64el-linux-gnuabi64-gcc -mabi=64"
build_image_abi  mips64eb    "mips64rt-parity-env:trixie"                "mips64-linux-gnuabi64-gcc -mabi=64"
build_image_abi  sparc64     "sparc64rt-l6a-tool:latest"                 "sparc64-linux-gnu-gcc"

cleanup_owned_containers || exit 1
verify_no_lingering_containers || exit 1

echo "== Uniform guest inventory: $OUT_DIR =="
find "$OUT_DIR" -type f | sort
