#!/bin/sh
# remote_bench.sh — Execute the 4-target x 11-architecture benchmark matrix on
# aarch64-darwin-5.lan (macOS host + Apple Virtualization.framework Lima VM).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -r "$SCRIPT_DIR/remote_bench_common.sh" ]; then
    # shellcheck source=tools/remote_bench_common.sh
    . "$SCRIPT_DIR/remote_bench_common.sh"
elif [ -r "/Users/angerman/rt-bench/remote_bench_common.sh" ]; then
    . "/Users/angerman/rt-bench/remote_bench_common.sh"
else
    echo "ERROR: remote_bench_common.sh not found" >&2
    exit 1
fi

MODE="${1:---smoke}"
PHASE="${2:-all}"
B="/Users/angerman/rt-bench"
LIMACTL="/Users/angerman/.nix-profile/bin/limactl"

run_darwin_dbt() {
    arch="$1"
    rt="$2"
    guest="$B/bench/bench-$arch"
    bin="$B/rt-darwin/${rt}-darwin"
    case "$rt" in
        rvrt|i686rt)
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" -- "$guest" "$MODE"
            ;;
        loongarch64rt|ppc64rt|mips64rt|sparc64rt)
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --dbt "$guest" "$MODE"
            ;;
        *)
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE"
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
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --engine interp -- "$guest" "$MODE"
            ;;
        i686rt)
            I686RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" -- "$guest" "$MODE"
            ;;
        mips32rt)
            MIPS32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE"
            ;;
        ppc32rt)
            PPC32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE"
            ;;
        sparc32rt)
            SPARC32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE"
            ;;
        *)
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --interp "$guest" "$MODE"
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
            HL_EXACT_CLOCK=1 run_bounded "$REMOTE_BENCH_TIMEOUT" "$B/hl" --rvrt-native -- "$lrt" -- "$guest" "$MODE"
            ;;
        *)
            HL_EXACT_CLOCK=1 \
            LOONGARCH64RT_ENGINE=dbt \
            PPC64RT_ENGINE=dbt \
            MIPS64RT_ENGINE=dbt \
            SPARC64RT_ENGINE=dbt \
            run_bounded "$REMOTE_BENCH_TIMEOUT" "$B/hl" "--${rt}" "$lrt" -- "$guest" "$MODE"
            ;;
    esac
}

if [ "$PHASE" = "all" ] || [ "$PHASE" = "baseline" ]; then
    out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$B/bench/bench-darwin-arm64" "$MODE")
    parse_and_print "native-darwin" "arm64" "native" "$out"
    out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$LIMACTL" shell --workdir /tmp/rt-bench bench /tmp/rt-bench/bench/bench-aarch64 "$MODE")
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
    run_bounded "$REMOTE_LIMA_TIMEOUT" "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "dbt"
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "linux-interp" ]; then
    run_bounded "$REMOTE_LIMA_TIMEOUT" "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "interp"
fi

if [ "$PHASE" = "all" ] || [ "$PHASE" = "qemu" ]; then
    run_bounded "$REMOTE_LIMA_TIMEOUT" "$LIMACTL" shell --workdir /tmp/rt-bench bench sh /tmp/rt-bench/remote_linux_inner.sh "$MODE" "qemu"
fi
