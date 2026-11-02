#!/bin/sh
# tools/remote_bench_common.sh — Shared benchmark matrix definitions, parser,
# bounded-execution helpers, and centralized translator CLI/env invocation
# policy for bench_harness.sh, run_grind.sh, remote_bench.sh, and
# remote_linux_inner.sh.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

ARCH_LIST="armhf:a32rt:qemu-arm i686:i686rt:qemu-i386 mipsel:mips32rt:qemu-mipsel ppc32:ppc32rt:qemu-ppc sparc32:sparc32rt:qemu-sparc riscv64:rvrt:qemu-riscv64 riscv32:rvrt:qemu-riscv32 loongarch64:loongarch64rt:qemu-loongarch64 ppc64le:ppc64rt:qemu-ppc64le mips64el:mips64rt:qemu-mips64el sparc64:sparc64rt:qemu-sparc64"

ALL_RT_REPOS="a32rt i686rt mips32rt ppc32rt sparc32rt rvrt loongarch64rt ppc64rt mips64rt sparc64rt"

REMOTE_BENCH_TIMEOUT="${REMOTE_BENCH_TIMEOUT:-90}"
REMOTE_LIMA_TIMEOUT="${REMOTE_LIMA_TIMEOUT:-600}"

run_bounded() {
    _rb_secs="$1"
    shift
    timeout --kill-after=30s "${_rb_secs}s" "$@"
}

# Print the canonical command prefix `<rt_bin> <engine_flags>` for `<repo>` and `<engine>`.
rt_format_cmd_prefix() {
    _rfp_repo="$1"
    _rfp_eng="$2"
    _rfp_bin="$3"
    case "$_rfp_repo" in
        i686rt|sparc32rt)
            printf '%s --engine %s --' "$_rfp_bin" "$_rfp_eng"
            ;;
        a32rt|rvrt|mips32rt|ppc32rt)
            printf '%s --%s --' "$_rfp_bin" "$_rfp_eng"
            ;;
        *)
            printf '%s --%s' "$_rfp_bin" "$_rfp_eng"
            ;;
    esac
}

# Execute `<rt_bin>` for `<repo>` with `<engine>` (`dbt` or `interp`) on `<guest_bin> [args...]`
# under `timeout --kill-after=30s <timeout_s>s`.
rt_run_bounded_translator() {
    _rrt_secs="$1"
    _rrt_repo="$2"
    _rrt_eng="$3"
    _rrt_bin="$4"
    _rrt_guest="$5"
    shift 5
    _rrt_a32=0
    _rrt_i686=0
    if [ "$_rrt_eng" = "interp" ]; then
        _rrt_a32=1
        _rrt_i686=1
    fi
    case "$_rrt_repo" in
        i686rt|sparc32rt)
            A32_INTERP="$_rrt_a32" I686_NO_JIT="$_rrt_i686" \
            I686RT_ENGINE="$_rrt_eng" RVRT_ENGINE="$_rrt_eng" MIPS32RT_ENGINE="$_rrt_eng" \
            PPC32RT_ENGINE="$_rrt_eng" SPARC32RT_ENGINE="$_rrt_eng" LOONGARCH64RT_ENGINE="$_rrt_eng" \
            PPC64RT_ENGINE="$_rrt_eng" MIPS64RT_ENGINE="$_rrt_eng" SPARC64RT_ENGINE="$_rrt_eng" \
            run_bounded "$_rrt_secs" "$_rrt_bin" --engine "$_rrt_eng" -- "$_rrt_guest" "$@"
            ;;
        a32rt|rvrt|mips32rt|ppc32rt)
            A32_INTERP="$_rrt_a32" I686_NO_JIT="$_rrt_i686" \
            I686RT_ENGINE="$_rrt_eng" RVRT_ENGINE="$_rrt_eng" MIPS32RT_ENGINE="$_rrt_eng" \
            PPC32RT_ENGINE="$_rrt_eng" SPARC32RT_ENGINE="$_rrt_eng" LOONGARCH64RT_ENGINE="$_rrt_eng" \
            PPC64RT_ENGINE="$_rrt_eng" MIPS64RT_ENGINE="$_rrt_eng" SPARC64RT_ENGINE="$_rrt_eng" \
            run_bounded "$_rrt_secs" "$_rrt_bin" "--$_rrt_eng" -- "$_rrt_guest" "$@"
            ;;
        *)
            A32_INTERP="$_rrt_a32" I686_NO_JIT="$_rrt_i686" \
            I686RT_ENGINE="$_rrt_eng" RVRT_ENGINE="$_rrt_eng" MIPS32RT_ENGINE="$_rrt_eng" \
            PPC32RT_ENGINE="$_rrt_eng" SPARC32RT_ENGINE="$_rrt_eng" LOONGARCH64RT_ENGINE="$_rrt_eng" \
            PPC64RT_ENGINE="$_rrt_eng" MIPS64RT_ENGINE="$_rrt_eng" SPARC64RT_ENGINE="$_rrt_eng" \
            run_bounded "$_rrt_secs" "$_rrt_bin" "--$_rrt_eng" "$_rrt_guest" "$@"
            ;;
    esac
}

# Execute `<hl_bin>` wrapping `<lrt_bin>` for `<repo>` with `<engine>` on `<guest_bin> [args...]`.
rt_run_bounded_hl() {
    _rrh_secs="$1"
    _rrh_hl="$2"
    _rrh_repo="$3"
    _rrh_eng="$4"
    _rrh_lrt="$5"
    _rrh_guest="$6"
    shift 6
    _rrh_a32=0
    _rrh_i686=0
    if [ "$_rrh_eng" = "interp" ]; then
        _rrh_a32=1
        _rrh_i686=1
    fi
    case "$_rrh_repo" in
        i686rt|sparc32rt)
            HL_EXACT_CLOCK=1 run_bounded "$_rrh_secs" "$_rrh_hl" \
                --env "A32_INTERP=$_rrh_a32" --env "I686_NO_JIT=$_rrh_i686" \
                --env "I686RT_ENGINE=$_rrh_eng" --env "RVRT_ENGINE=$_rrh_eng" \
                --env "MIPS32RT_ENGINE=$_rrh_eng" --env "PPC32RT_ENGINE=$_rrh_eng" \
                --env "SPARC32RT_ENGINE=$_rrh_eng" --env "LOONGARCH64RT_ENGINE=$_rrh_eng" \
                --env "PPC64RT_ENGINE=$_rrh_eng" --env "MIPS64RT_ENGINE=$_rrh_eng" \
                --env "SPARC64RT_ENGINE=$_rrh_eng" \
                "$_rrh_lrt" --engine "$_rrh_eng" -- "$_rrh_guest" "$@"
            ;;
        rvrt)
            HL_EXACT_CLOCK=1 run_bounded "$_rrh_secs" "$_rrh_hl" \
                --rvrt-native \
                --env "A32_INTERP=$_rrh_a32" --env "I686_NO_JIT=$_rrh_i686" \
                --env "I686RT_ENGINE=$_rrh_eng" --env "RVRT_ENGINE=$_rrh_eng" \
                --env "MIPS32RT_ENGINE=$_rrh_eng" --env "PPC32RT_ENGINE=$_rrh_eng" \
                --env "SPARC32RT_ENGINE=$_rrh_eng" --env "LOONGARCH64RT_ENGINE=$_rrh_eng" \
                --env "PPC64RT_ENGINE=$_rrh_eng" --env "MIPS64RT_ENGINE=$_rrh_eng" \
                --env "SPARC64RT_ENGINE=$_rrh_eng" \
                "$_rrh_lrt" "--$_rrh_eng" -- "$_rrh_guest" "$@"
            ;;
        a32rt|mips32rt|ppc32rt)
            HL_EXACT_CLOCK=1 run_bounded "$_rrh_secs" "$_rrh_hl" \
                --env "A32_INTERP=$_rrh_a32" --env "I686_NO_JIT=$_rrh_i686" \
                --env "I686RT_ENGINE=$_rrh_eng" --env "RVRT_ENGINE=$_rrh_eng" \
                --env "MIPS32RT_ENGINE=$_rrh_eng" --env "PPC32RT_ENGINE=$_rrh_eng" \
                --env "SPARC32RT_ENGINE=$_rrh_eng" --env "LOONGARCH64RT_ENGINE=$_rrh_eng" \
                --env "PPC64RT_ENGINE=$_rrh_eng" --env "MIPS64RT_ENGINE=$_rrh_eng" \
                --env "SPARC64RT_ENGINE=$_rrh_eng" \
                "$_rrh_lrt" "--$_rrh_eng" -- "$_rrh_guest" "$@"
            ;;
        *)
            HL_EXACT_CLOCK=1 run_bounded "$_rrh_secs" "$_rrh_hl" \
                --env "A32_INTERP=$_rrh_a32" --env "I686_NO_JIT=$_rrh_i686" \
                --env "I686RT_ENGINE=$_rrh_eng" --env "RVRT_ENGINE=$_rrh_eng" \
                --env "MIPS32RT_ENGINE=$_rrh_eng" --env "PPC32RT_ENGINE=$_rrh_eng" \
                --env "SPARC32RT_ENGINE=$_rrh_eng" --env "LOONGARCH64RT_ENGINE=$_rrh_eng" \
                --env "PPC64RT_ENGINE=$_rrh_eng" --env "MIPS64RT_ENGINE=$_rrh_eng" \
                --env "SPARC64RT_ENGINE=$_rrh_eng" \
                "$_rrh_lrt" "--$_rrh_eng" "$_rrh_guest" "$@"
            ;;
    esac
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
