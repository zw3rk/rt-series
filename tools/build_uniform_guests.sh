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
FORCE="${FORCE:-${FORCE_REBUILD:-0}}"
ABI_FILTER="${1:-all}"

if [ ! -f "$P3_SRC" ]; then
    echo "GAP: $P3_SRC missing" >&2
    exit 1
fi
if [ ! -f "$TCG_SRC" ]; then
    echo "GAP: $TCG_SRC missing" >&2
    exit 1
fi

cleanup_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    _left="$(docker ps -aq --filter "name=rt-u-" 2>/dev/null || true)"
    for _cid in $_left; do
        _cname="$(docker inspect --format '{{.Name}}' "$_cid" 2>/dev/null || true)"
        case "$_cname" in
            *"-$$") docker rm -f "$_cid" >/dev/null 2>&1 || true ;;
        esac
    done
}
trap cleanup_containers EXIT INT TERM

already_built() {
    _abi="$1"
    [ "$FORCE" != "1" ] \
        && [ -x "$OUT_DIR/$_abi/p3_torture" ] \
        && [ -x "$OUT_DIR/$_abi/smoke_tcg" ] \
        && ! [ "$P3_SRC" -nt "$OUT_DIR/$_abi/p3_torture" ] \
        && ! [ "$TCG_SRC" -nt "$OUT_DIR/$_abi/smoke_tcg" ]
}

want_abi() {
    [ "$ABI_FILTER" = "all" ] || [ "$ABI_FILTER" = "$1" ]
}

COMMON_CFLAGS="-std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla -pedantic"

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

cleanup_containers
if command -v docker >/dev/null 2>&1; then
    _lingering="$(docker ps --filter "name=rt-u-" --format '{{.Names}}' 2>/dev/null | grep -E -- "-$$\$" || true)"
    if [ -n "$_lingering" ]; then
        echo "FAIL: lingering docker containers: $_lingering" >&2
        exit 1
    fi
fi

echo "== Uniform guest inventory: $OUT_DIR =="
find "$OUT_DIR" -type f | sort
