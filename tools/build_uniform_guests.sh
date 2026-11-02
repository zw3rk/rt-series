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
#   timeout --kill-after=30s 180s docker run --rm --name c2-uniform-<abi>-23194 ...
# Debian trixie provides the arm/i686/mips/ppc32/riscv64 cross toolchains,
# cached <arch>rt images provide loongarch64/ppc64le/mips64/sparc guests,
# and riscv32 (no glibc port exists) uses an emulated amd64 container with
# the musl.cc riscv32-linux-musl cross toolchain.
#
# Already-built guests are skipped unless FORCE=1. Leftover containers fail
# the gate (docker names are unique per ABI, no orphans expected).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/_build/uniform"
P3_SRC="$ROOT_DIR/tests/p3_torture.c"
TCG_SRC="$ROOT_DIR/tests/tcg/smoke_tcg.c"
FORCE="${FORCE:-0}"

if [ ! -f "$P3_SRC" ]; then
    echo "GAP: $P3_SRC missing" >&2
    exit 1
fi
if [ ! -f "$TCG_SRC" ]; then
    echo "GAP: $TCG_SRC missing" >&2
    exit 1
fi

already_built() {
    _abi="$1"
    [ "$FORCE" != "1" ] \
        && [ -x "$OUT_DIR/$_abi/p3_torture" ] \
        && [ -x "$OUT_DIR/$_abi/smoke_tcg" ]
}

# --- Debian trixie cross builds (native arm64 container, apt toolchain) ---

build_armhf() {
    if already_built armhf; then echo "SKIP [armhf]: present"; return 0; fi
    mkdir -p "$OUT_DIR/armhf"
    echo "== Building uniform guests for armhf =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-armhf-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-arm-linux-gnueabihf libc6-dev-armhf-cross
            mkdir -p /w/_build/uniform/armhf
            arm-linux-gnueabihf-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/armhf/p3_torture
            arm-linux-gnueabihf-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/armhf/smoke_tcg
        '
}

build_armel() {
    if already_built armel; then echo "SKIP [armel]: present"; return 0; fi
    mkdir -p "$OUT_DIR/armel"
    echo "== Building uniform guests for armel =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-armel-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-arm-linux-gnueabi libc6-dev-armel-cross
            mkdir -p /w/_build/uniform/armel
            arm-linux-gnueabi-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/armel/p3_torture
            arm-linux-gnueabi-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/armel/smoke_tcg
        '
}

build_i686() {
    if already_built i686; then echo "SKIP [i686]: present"; return 0; fi
    mkdir -p "$OUT_DIR/i686"
    echo "== Building uniform guests for i686 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-i686-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-i686-linux-gnu libc6-dev-i386-cross
            mkdir -p /w/_build/uniform/i686
            i686-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/i686/p3_torture
            i686-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/i686/smoke_tcg
        '
}

build_mipsel() {
    if already_built mipsel; then echo "SKIP [mipsel]: present"; return 0; fi
    mkdir -p "$OUT_DIR/mipsel"
    echo "== Building uniform guests for mipsel =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-mipsel-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-mipsel-linux-gnu libc6-dev-mipsel-cross
            mkdir -p /w/_build/uniform/mipsel
            mipsel-linux-gnu-gcc -mips32r2 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/mipsel/p3_torture
            mipsel-linux-gnu-gcc -mips32r2 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/mipsel/smoke_tcg
        '
}

build_mips() {
    if already_built mips; then echo "SKIP [mips]: present"; return 0; fi
    mkdir -p "$OUT_DIR/mips"
    echo "== Building uniform guests for mips (BE) =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-mips-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-mips-linux-gnu libc6-dev-mips-cross
            mkdir -p /w/_build/uniform/mips
            mips-linux-gnu-gcc -mips32r2 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/mips/p3_torture
            mips-linux-gnu-gcc -mips32r2 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/mips/smoke_tcg
        '
}

build_ppc32() {
    if already_built ppc32; then echo "SKIP [ppc32]: present"; return 0; fi
    mkdir -p "$OUT_DIR/ppc32"
    echo "== Building uniform guests for ppc32 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-ppc32-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-powerpc-linux-gnu libc6-dev-powerpc-cross
            mkdir -p /w/_build/uniform/ppc32
            powerpc-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/ppc32/p3_torture
            powerpc-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/ppc32/smoke_tcg
        '
}

build_riscv64() {
    if already_built riscv64; then echo "SKIP [riscv64]: present"; return 0; fi
    mkdir -p "$OUT_DIR/riscv64"
    echo "== Building uniform guests for riscv64 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-riscv64-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq gcc-riscv64-linux-gnu libc6-dev-riscv64-cross
            mkdir -p /w/_build/uniform/riscv64
            riscv64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/riscv64/p3_torture
            riscv64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/riscv64/smoke_tcg
        '
}

# --- Cached <arch>rt toolchain images (no apt, bounded builds) ---

build_loongarch64() {
    if already_built loongarch64; then echo "SKIP [loongarch64]: present"; return 0; fi
    mkdir -p "$OUT_DIR/loongarch64"
    echo "== Building uniform guests for loongarch64 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-loongarch64-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w loongarch64rt-l3a-tool:latest sh -c '
            set -eu
            mkdir -p /w/_build/uniform/loongarch64
            loongarch64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/loongarch64/p3_torture
            loongarch64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/loongarch64/smoke_tcg
        '
}

build_ppc64le() {
    if already_built ppc64le; then echo "SKIP [ppc64le]: present"; return 0; fi
    mkdir -p "$OUT_DIR/ppc64le"
    echo "== Building uniform guests for ppc64le =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-ppc64le-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w ppc64rt-l3a-tool:latest sh -c '
            set -eu
            mkdir -p /w/_build/uniform/ppc64le
            powerpc64le-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/ppc64le/p3_torture
            powerpc64le-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/ppc64le/smoke_tcg
        '
}

build_mips64el() {
    if already_built mips64el; then echo "SKIP [mips64el]: present"; return 0; fi
    mkdir -p "$OUT_DIR/mips64el"
    echo "== Building uniform guests for mips64el =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-mips64el-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w mips64rt-parity-env:trixie sh -c '
            set -eu
            mkdir -p /w/_build/uniform/mips64el
            mips64el-linux-gnuabi64-gcc -mabi=64 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/mips64el/p3_torture
            mips64el-linux-gnuabi64-gcc -mabi=64 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/mips64el/smoke_tcg
        '
}

build_mips64eb() {
    if already_built mips64eb; then echo "SKIP [mips64eb]: present"; return 0; fi
    mkdir -p "$OUT_DIR/mips64eb"
    echo "== Building uniform guests for mips64eb (BE) =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-mips64eb-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w mips64rt-parity-env:trixie sh -c '
            set -eu
            mkdir -p /w/_build/uniform/mips64eb
            mips64-linux-gnuabi64-gcc -mabi=64 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/mips64eb/p3_torture
            mips64-linux-gnuabi64-gcc -mabi=64 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/mips64eb/smoke_tcg
        '
}

build_sparc64() {
    if already_built sparc64; then echo "SKIP [sparc64]: present"; return 0; fi
    mkdir -p "$OUT_DIR/sparc64"
    echo "== Building uniform guests for sparc64 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-sparc64-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w sparc64rt-l6a-tool:latest sh -c '
            set -eu
            mkdir -p /w/_build/uniform/sparc64
            sparc64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/sparc64/p3_torture
            sparc64-linux-gnu-gcc -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/sparc64/smoke_tcg
        '
}

build_sparc32() {
    if already_built sparc32; then echo "SKIP [sparc32]: present"; return 0; fi
    mkdir -p "$OUT_DIR/sparc32"
    echo "== Building uniform guests for sparc32 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-sparc32-23194 \
        --platform linux/arm64 \
        -v "$ROOT_DIR:/w" -w /w sparc32rt-oracle:latest sh -c '
            set -eu
            mkdir -p /w/_build/uniform/sparc32
            sparc64-linux-gnu-gcc -m32 -mcpu=v8 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -latomic -o /w/_build/uniform/sparc32/p3_torture
            sparc64-linux-gnu-gcc -m32 -mcpu=v8 -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -latomic -o /w/_build/uniform/sparc32/smoke_tcg
        '
}

# riscv32 has no glibc port, so build with the musl.cc riscv32 cross
# toolchain (i686-hosted) inside an emulated amd64 container.
build_riscv32() {
    if already_built riscv32; then echo "SKIP [riscv32]: present"; return 0; fi
    mkdir -p "$OUT_DIR/riscv32"
    echo "== Building uniform guests for riscv32 =="
    timeout --kill-after=30s 180s docker run --rm --name c2-uniform-riscv32-23194 \
        --platform linux/amd64 \
        -v "$ROOT_DIR:/w" -w /w debian:trixie-slim bash -c '
            set -eu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl ca-certificates bzip2
            mkdir -p /opt/rv32 /w/_build/uniform/riscv32
            curl -fsSL -o /tmp/rv32.tgz https://musl.cc/riscv32-linux-musl-cross.tgz
            tar -xzf /tmp/rv32.tgz -C /opt/rv32 --strip-components=1
            rv32cc="$(ls /opt/rv32/bin/*-gcc | head -n 1)"
            [ -x "$rv32cc" ] || { echo "GAP: no *-gcc in musl.cc riscv32 toolchain" >&2; exit 1; }
            "$rv32cc" -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/p3_torture.c -lm -o /w/_build/uniform/riscv32/p3_torture
            "$rv32cc" -std=c11 -O1 -static -pthread -Wall -Wextra -Werror=vla /w/tests/tcg/smoke_tcg.c -lm -o /w/_build/uniform/riscv32/smoke_tcg
        '
}

build_armhf
build_armel
build_i686
build_mipsel
build_mips
build_ppc32
build_sparc32
build_riscv64
build_riscv32
build_loongarch64
build_ppc64le
build_mips64el
build_mips64eb
build_sparc64

echo "== Uniform guest inventory: $OUT_DIR =="
find "$OUT_DIR" -type f | sort
