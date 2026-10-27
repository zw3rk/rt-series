#!/bin/sh
# remote_linux_inner.sh — Inside-Lima-VM benchmark helper for Linux standalone
# (<arch>rt) and QEMU 10.0.13 (qemu-<arch>).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

MODE="${1:---smoke}"
KIND="${2:-dbt}"
B="/tmp/rt-bench"

ARCH_LIST="armhf:a32rt:qemu-arm i686:i686rt:qemu-i386 mipsel:mips32rt:qemu-mipsel ppc32:ppc32rt:qemu-ppc sparc32:sparc32rt:qemu-sparc riscv64:rvrt:qemu-riscv64 riscv32:rvrt:qemu-riscv32 loongarch64:loongarch64rt:qemu-loongarch64 ppc64le:ppc64rt:qemu-ppc64le mips64el:mips64rt:qemu-mips64el sparc64:sparc64rt:qemu-sparc64"

parse_and_print() {
    target="$1"
    arch="$2"
    engine="$3"
    out="$4"
    cm=$(printf '%s\n' "$out" | awk '/BENCH coremark/ {for(i=1;i<=NF;i++) if($i ~ /^us=/) {sub(/^us=/,"",$i); print $i}}')
    cc=$(printf '%s\n' "$out" | awk '/BENCH chacha20/ {for(i=1;i<=NF;i++) if($i ~ /^us=/) {sub(/^us=/,"",$i); print $i}}')
    vf=$(printf '%s\n' "$out" | awk '/BENCH vfp_simd/ {for(i=1;i<=NF;i++) if($i ~ /^us=/) {sub(/^us=/,"",$i); print $i}}')
    ib=$(printf '%s\n' "$out" | awk '/BENCH calls_ibtc/ {for(i=1;i<=NF;i++) if($i ~ /^us=/) {sub(/^us=/,"",$i); print $i}}')
    sc=$(printf '%s\n' "$out" | awk '/BENCH syscalls/ {for(i=1;i<=NF;i++) if($i ~ /^us=/) {sub(/^us=/,"",$i); print $i}}')
    tot=$(printf '%s\n' "$out" | awk '/BENCH total_us=/ {for(i=1;i<=NF;i++) if($i ~ /^total_us=/) {sub(/^total_us=/,"",$i); print $i}}')
    st=$(printf '%s\n' "$out" | awk '/BENCH total_us=/ {print $NF}')
    printf "RESULT\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$target" "$arch" "$engine" "${cm:--}" "${cc:--}" "${vf:--}" "${ib:--}" "${sc:--}" "${tot:--}" "${st:-FAIL}"
}

for item in $ARCH_LIST; do
    arch=${item%%:*}
    rest=${item#*:}
    rt=${rest%%:*}
    q=${rest#*:}
    guest="$B/bench/bench-$arch"
    bin="$B/rt-linux/$rt"

    if [ "$KIND" = "qemu" ]; then
        out=$("$B/qemu/$q" "$guest" "$MODE")
        parse_and_print "qemu" "$arch" "tcg" "$out"
    elif [ "$KIND" = "dbt" ]; then
        case "$rt" in
            rvrt|i686rt)
                out=$("$bin" -- "$guest" "$MODE")
                ;;
            loongarch64rt|ppc64rt|mips64rt|sparc64rt)
                out=$("$bin" --dbt "$guest" "$MODE")
                ;;
            *)
                out=$("$bin" "$guest" "$MODE")
                ;;
        esac
        parse_and_print "linux" "$arch" "dbt" "$out"
    elif [ "$KIND" = "interp" ]; then
        case "$rt" in
            rvrt)
                out=$("$bin" --engine interp -- "$guest" "$MODE")
                ;;
            i686rt)
                out=$(I686RT_ENGINE=interp "$bin" -- "$guest" "$MODE")
                ;;
            mips32rt)
                out=$(MIPS32RT_ENGINE=interp "$bin" "$guest" "$MODE")
                ;;
            ppc32rt)
                out=$(PPC32RT_ENGINE=interp "$bin" "$guest" "$MODE")
                ;;
            sparc32rt)
                out=$(SPARC32RT_ENGINE=interp "$bin" "$guest" "$MODE")
                ;;
            *)
                out=$("$bin" --interp "$guest" "$MODE")
                ;;
        esac
        parse_and_print "linux" "$arch" "interp" "$out"
    fi
done
