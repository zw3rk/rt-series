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

case "$KIND" in
    dbt|interp|qemu) ;;
    *)
        echo "ERROR: Invalid KIND '$KIND' (expected dbt|interp|qemu)" >&2
        exit 2
        ;;
esac
REMOTE_INNER_COUNT=0

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
        REMOTE_INNER_COUNT=$((REMOTE_INNER_COUNT + 1))
    elif [ "$KIND" = "dbt" ] || [ "$KIND" = "interp" ]; then
        out=$(rt_run_bounded_translator "$REMOTE_BENCH_TIMEOUT" "$rt" "$KIND" "$bin" "$guest" "$MODE")
        parse_and_print "linux" "$arch" "$KIND" "$out"
        REMOTE_INNER_COUNT=$((REMOTE_INNER_COUNT + 1))
    fi
done

if [ "$REMOTE_INNER_COUNT" -eq 0 ]; then
    echo "ERROR: no benchmarks executed for KIND='$KIND'" >&2
    exit 1
fi
