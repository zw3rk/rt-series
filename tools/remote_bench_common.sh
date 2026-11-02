#!/bin/sh
# tools/remote_bench_common.sh — Shared benchmark matrix definitions, parser,
# and bounded-execution helpers for remote_bench.sh and remote_linux_inner.sh.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

ARCH_LIST="armhf:a32rt:qemu-arm i686:i686rt:qemu-i386 mipsel:mips32rt:qemu-mipsel ppc32:ppc32rt:qemu-ppc sparc32:sparc32rt:qemu-sparc riscv64:rvrt:qemu-riscv64 riscv32:rvrt:qemu-riscv32 loongarch64:loongarch64rt:qemu-loongarch64 ppc64le:ppc64rt:qemu-ppc64le mips64el:mips64rt:qemu-mips64el sparc64:sparc64rt:qemu-sparc64"

REMOTE_BENCH_TIMEOUT="${REMOTE_BENCH_TIMEOUT:-90}"
REMOTE_LIMA_TIMEOUT="${REMOTE_LIMA_TIMEOUT:-600}"

run_bounded() {
    _rb_secs="$1"
    shift
    timeout --kill-after=30s "${_rb_secs}s" "$@"
}

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
