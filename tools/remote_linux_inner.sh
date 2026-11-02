#!/bin/sh
# remote_linux_inner.sh — Inside-Lima-VM benchmark helper for Linux standalone
# (<arch>rt) and QEMU 10.0.13 (qemu-<arch>).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -r "$SCRIPT_DIR/remote_bench_common.sh" ]; then
    # shellcheck source=tools/remote_bench_common.sh
    . "$SCRIPT_DIR/remote_bench_common.sh"
elif [ -r "/tmp/rt-bench/remote_bench_common.sh" ]; then
    . "/tmp/rt-bench/remote_bench_common.sh"
else
    echo "ERROR: remote_bench_common.sh not found" >&2
    exit 1
fi

MODE="${1:---smoke}"
KIND="${2:-dbt}"
B="/tmp/rt-bench"

for item in $ARCH_LIST; do
    arch=${item%%:*}
    rest=${item#*:}
    rt=${rest%%:*}
    q=${rest#*:}
    guest="$B/bench/bench-$arch"
    bin="$B/rt-linux/$rt"

    if [ "$KIND" = "qemu" ]; then
        out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$B/qemu/$q" "$guest" "$MODE")
        parse_and_print "qemu" "$arch" "tcg" "$out"
    elif [ "$KIND" = "dbt" ]; then
        case "$rt" in
            rvrt|i686rt)
                out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" -- "$guest" "$MODE")
                ;;
            loongarch64rt|ppc64rt|mips64rt|sparc64rt)
                out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --dbt "$guest" "$MODE")
                ;;
            *)
                out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE")
                ;;
        esac
        parse_and_print "linux" "$arch" "dbt" "$out"
    elif [ "$KIND" = "interp" ]; then
        case "$rt" in
            rvrt)
                out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --engine interp -- "$guest" "$MODE")
                ;;
            i686rt)
                out=$(I686RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" -- "$guest" "$MODE")
                ;;
            mips32rt)
                out=$(MIPS32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE")
                ;;
            ppc32rt)
                out=$(PPC32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE")
                ;;
            sparc32rt)
                out=$(SPARC32RT_ENGINE=interp run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" "$guest" "$MODE")
                ;;
            *)
                out=$(run_bounded "$REMOTE_BENCH_TIMEOUT" "$bin" --interp "$guest" "$MODE")
                ;;
        esac
        parse_and_print "linux" "$arch" "interp" "$out"
    fi
done
