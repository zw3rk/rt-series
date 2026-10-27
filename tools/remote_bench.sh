#!/bin/sh
# remote_bench.sh — Execute the 4-target x 11-architecture benchmark matrix on
# aarch64-darwin-5.lan (macOS host + Apple Virtualization.framework Lima VM).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

MODE="${1:---smoke}"
PHASE="${2:-all}"
B="/Users/angerman/rt-bench"
LIMACTL="/Users/angerman/.nix-profile/bin/limactl"

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

run_darwin_dbt() {
    arch="$1"
    rt="$2"
    guest="$B/bench/bench-$arch"
    bin="$B/rt-darwin/${rt}-darwin"
    case "$rt" in
        rvrt|i686rt)
            "$bin" -- "$guest" "$MODE"
            ;;
        loongarch64rt|ppc64rt|mips64rt|sparc64rt)
            "$bin" --dbt "$guest" "$MODE"
            ;;
        *)
            "$bin" "$guest" "$MODE"
            ;;
    esac
}

run_darwin_interp() {
    arch="$1"
    rt="$2"
    guest="$B/bench/bench-$arch"
    bin="$B/rt-darwin/${rt}-darwin"
    case "$rt" in
        rvrt)
            "$bin" --engine interp -- "$guest" "$MODE"
            ;;
        i686rt)
            I686RT_ENGINE=interp "$bin" -- "$guest" "$MODE"
            ;;
        mips32rt)
            MIPS32RT_ENGINE=interp "$bin" "$guest" "$MODE"
            ;;
        ppc32rt)
            PPC32RT_ENGINE=interp "$bin" "$guest" "$MODE"
            ;;
        sparc32rt)
            SPARC32RT_ENGINE=interp "$bin" "$guest" "$MODE"
            ;;
        *)
            "$bin" --interp "$guest" "$MODE"
            ;;
    esac
}

run_hl_dbt() {
    arch="$1"
    rt="$2"
    guest="$B/bench/bench-$arch"
    lrt="$B/rt-linux/$rt"
    case "$rt" in
        rvrt)
            HL_EXACT_CLOCK=1 "$B/hl" --rvrt-native -- "$lrt" -- "$guest" "$MODE"
            ;;
        *)
            HL_EXACT_CLOCK=1 \
            LOONGARCH64RT_ENGINE=dbt \
            PPC64RT_ENGINE=dbt \
            MIPS64RT_ENGINE=dbt \
            SPARC64RT_ENGINE=dbt \
            "$B/hl" "--${rt}" "$lrt" -- "$guest" "$MODE"
            ;;
    esac
}

if [ "$PHASE" = "all" ] || [ "$PHASE" = "baseline" ]; then
    out=$("$B/bench/bench-darwin-arm64" "$MODE")
    parse_and_print "native-darwin" "arm64" "native" "$out"
    out=$("$LIMACTL" shell --workdir /tmp/rt-bench bench /tmp/rt-bench/bench/bench-aarch64 "$MODE")
    parse_and_print "native-linux" "aarch64" "native" "$out"
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "darwin" ]; then
    for item in $ARCH_LIST; do
        arch=${item%%:*}
        rest=${item#*:}
        rt=${rest%%:*}
        out=$(run_darwin_dbt "$arch" "$rt")
        parse_and_print "darwin" "$arch" "dbt" "$out"
    done
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "darwin-interp" ]; then
    for item in $ARCH_LIST; do
        arch=${item%%:*}
        rest=${item#*:}
        rt=${rest%%:*}
        out=$(run_darwin_interp "$arch" "$rt")
        parse_and_print "darwin" "$arch" "interp" "$out"
    done
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "hl" ]; then
    for item in $ARCH_LIST; do
        arch=${item%%:*}
        rest=${item#*:}
        rt=${rest%%:*}
        out=$(run_hl_dbt "$arch" "$rt")
        parse_and_print "hl" "$arch" "dbt" "$out"
    done
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "linux" ]; then
    "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "dbt"
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "linux-interp" ]; then
    "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "interp"
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "qemu" ]; then
    "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "qemu"
fi
