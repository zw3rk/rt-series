#!/usr/bin/env bash
# tools/bench_harness.sh — Unified 10-Translator × 4-Target Benchmark & Smoke Harness
#
# Separates:
#   1. Setup (`build`) : Cross-compiles `tests/bench_suite.c` into `_build/bench/bench-<arch>`
#                        and ensures `<arch>rt` Linux + Darwin translator binaries exist.
#   2. Smoke (`smoke`) : Runs `bench-<arch> --smoke` across requested target(s)
#                        (`darwin`, `hl`, `linux`, `qemu`) to verify `ALL_PASS` + CRCs (<1s/run).
#   3. Run   (`run`)   : Checks host load (`BENCH_MAX_LOAD`, default 2.5) and runs full 5-trial
#                        timed benchmarks (`bench-<arch> --full`).
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BENCH_DIR="$ROOT_DIR/_build/bench"
SRC_FILE="$ROOT_DIR/tests/bench_suite.c"
HDR_FILE="$ROOT_DIR/tests/bench_sys.h"

# shellcheck source=tools/remote_bench_common.sh
. "$SCRIPT_DIR/remote_bench_common.sh"

MODE="${1:-help}"
shift || true

TARGET="all"
ARCH_FILTER="all"
ENGINE="dbt"
BENCH_MAX_LOAD="${BENCH_MAX_LOAD:-2.5}"
BENCH_FORCE="${BENCH_FORCE:-0}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            TARGET="${2:?missing value for --target}"
            shift 2
            ;;
        --arch)
            ARCH_FILTER="${2:?missing value for --arch}"
            shift 2
            ;;
        --engine)
            ENGINE="${2:?missing value for --engine}"
            shift 2
            ;;
        --force)
            BENCH_FORCE=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

case "$TARGET" in
    darwin|hl|linux|qemu|all) ;;
    *)
        echo "ERROR: Invalid --target '$TARGET' (expected darwin|hl|linux|qemu|all)" >&2
        exit 2
        ;;
esac

case "$ENGINE" in
    dbt|interp) ;;
    *)
        echo "ERROR: Invalid --engine '$ENGINE' (expected dbt|interp)" >&2
        exit 2
        ;;
esac

ALL_ARCHES=(
    armhf
    i686
    mipsel
    ppc32
    sparc32
    riscv64
    loongarch64
    ppc64le
    mips64el
    sparc64
)

arch_repo() {
    case "$1" in
        armhf|thumb)        echo "a32rt" ;;
        i686)               echo "i686rt" ;;
        mipsel|mips)        echo "mips32rt" ;;
        ppc32)              echo "ppc32rt" ;;
        sparc32)            echo "sparc32rt" ;;
        riscv64|riscv32)    echo "rvrt" ;;
        loongarch64)        echo "loongarch64rt" ;;
        ppc64le)            echo "ppc64rt" ;;
        mips64el|mips64)    echo "mips64rt" ;;
        sparc64)            echo "sparc64rt" ;;
        *)                  return 1 ;;
    esac
}

if [ "$ARCH_FILTER" != "all" ] && ! arch_repo "$ARCH_FILTER" >/dev/null 2>&1; then
    echo "ERROR: Invalid --arch '$ARCH_FILTER'" >&2
    exit 2
fi

cleanup_bench_containers() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    local cids
    cids="$(docker ps -aq --filter "name=rt-bench-" 2>/dev/null || true)"
    for cid in $cids; do
        local cname
        cname="$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null || true)"
        case "$cname" in
            *"-$$") docker rm -f "$cid" >/dev/null 2>&1 || true ;;
        esac
    done
    local lingering
    lingering="$(docker ps --filter "name=rt-bench-" --format '{{.Names}}' 2>/dev/null | grep -E -- "-$$\$" || true)"
    if [ -n "$lingering" ]; then
        echo "ERROR: Lingering benchmark container(s): $lingering" >&2
        return 1
    fi
    return 0
}
trap cleanup_bench_containers EXIT INT TERM

need_bench_rebuild() {
    local bin="$1"
    if [ "$FORCE_REBUILD" = "1" ] || [ "$BENCH_FORCE" = "1" ]; then
        return 0
    fi
    if [ ! -x "$bin" ] || [ "$SRC_FILE" -nt "$bin" ] || [ "$HDR_FILE" -nt "$bin" ]; then
        return 0
    fi
    return 1
}

arch_qemu() {
    case "$1" in
        armhf|thumb)        echo "qemu-arm" ;;
        i686)               echo "qemu-i386" ;;
        mipsel)             echo "qemu-mipsel" ;;
        mips)               echo "qemu-mips" ;;
        ppc32)              echo "qemu-ppc" ;;
        sparc32)            echo "qemu-sparc" ;;
        riscv64)            echo "qemu-riscv64" ;;
        riscv32)            echo "qemu-riscv32" ;;
        loongarch64)        echo "qemu-loongarch64" ;;
        ppc64le)            echo "qemu-ppc64le" ;;
        mips64el)           echo "qemu-mips64el" ;;
        mips64)             echo "qemu-mips64" ;;
        sparc64)            echo "qemu-sparc64" ;;
        *)                  return 1 ;;
    esac
}

find_linux_rt() {
    local repo="$1"
    local d="$PROJECTS_DIR/$repo/_build"
    for cand in "$d/${repo}-linux-aarch64" "$d/${repo}"; do
        if [ -f "$cand" ] && file "$cand" 2>/dev/null | grep -q "ELF 64-bit"; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

find_darwin_rt() {
    local repo="$1"
    local d="$PROJECTS_DIR/$repo/_build"
    for cand in "$d/${repo}-darwin-arm64" "$d/${repo}-darwin" "$d/${repo}"; do
        if [ -f "$cand" ] && file "$cand" 2>/dev/null | grep -q "Mach-O 64-bit"; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

find_hl_bin() {
    for cand in "$PROJECTS_DIR/hyper-linux-u4/_build/hl" "$PROJECTS_DIR/hyper-linux/_build/hl"; do
        if [ -x "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

build_guest_bins() {
    mkdir -p "$BENCH_DIR"
    echo "== Building unified guest benchmark binaries into $BENCH_DIR =="

    # 1. Fast-path: use local clang + ld.lld for freestanding ELF targets (zero container)
    local clang_raw="/nix/store/15n3slfdsd5zhyxrvaa7vm36f1jydwqp-clang-21.1.8/bin/clang"
    local lld_raw="/nix/store/smnrx7kvgcxbl6s2scgwk6zp0np6yw7q-lld-21.1.8/bin/ld.lld"
    local fs_flags="-std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 -ffreestanding -fno-stack-protector -fno-builtin -nostdlib -DBENCH_FREESTANDING=1"
    if [ -x "$clang_raw" ] && [ -x "$lld_raw" ]; then
        if need_bench_rebuild "$BENCH_DIR/bench-armhf"; then
            "$clang_raw" --target=armv7a-unknown-linux-eabihf -march=armv7ve -mfpu=neon-vfpv4 -mfloat-abi=hard $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-armhf.o" && \
            "$lld_raw" -m armelf_linux_eabi -Bstatic --no-dynamic-linker --image-base=0x00010000 -e _start "$BENCH_DIR/bench-armhf.o" -o "$BENCH_DIR/bench-armhf.tmp.$$" && \
            mv "$BENCH_DIR/bench-armhf.tmp.$$" "$BENCH_DIR/bench-armhf" && rm -f "$BENCH_DIR/bench-armhf.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-i686"; then
            "$clang_raw" --target=i686-unknown-linux-gnu -march=i686 -msse2 -mfpmath=sse $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-i686.o" && \
            "$lld_raw" -m elf_i386 -Bstatic --no-dynamic-linker --image-base=0x08048000 -e _start "$BENCH_DIR/bench-i686.o" -o "$BENCH_DIR/bench-i686.tmp.$$" && \
            mv "$BENCH_DIR/bench-i686.tmp.$$" "$BENCH_DIR/bench-i686" && rm -f "$BENCH_DIR/bench-i686.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-mipsel"; then
            "$clang_raw" --target=mipsel-unknown-linux-gnu -march=mips32r2 -mabi=32 -mhard-float $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-mipsel.o" && \
            "$lld_raw" -m elf32ltsmip -Bstatic --no-dynamic-linker --image-base=0x00400000 -e _start "$BENCH_DIR/bench-mipsel.o" -o "$BENCH_DIR/bench-mipsel.tmp.$$" && \
            mv "$BENCH_DIR/bench-mipsel.tmp.$$" "$BENCH_DIR/bench-mipsel" && rm -f "$BENCH_DIR/bench-mipsel.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-ppc32"; then
            "$clang_raw" --target=powerpc-unknown-linux-gnu -mcpu=7400 -mhard-float $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-ppc32.o" && \
            "$lld_raw" -m elf32ppclinux -Bstatic --no-dynamic-linker --image-base=0x10000000 -e _start "$BENCH_DIR/bench-ppc32.o" -o "$BENCH_DIR/bench-ppc32.tmp.$$" && \
            mv "$BENCH_DIR/bench-ppc32.tmp.$$" "$BENCH_DIR/bench-ppc32" && rm -f "$BENCH_DIR/bench-ppc32.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-riscv64"; then
            "$clang_raw" --target=riscv64-unknown-linux-gnu -march=rv64gc -mabi=lp64d $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-riscv64.o" && \
            "$lld_raw" -m elf64lriscv -Bstatic --no-dynamic-linker --image-base=0x00010000 -e _start "$BENCH_DIR/bench-riscv64.o" -o "$BENCH_DIR/bench-riscv64.tmp.$$" && \
            mv "$BENCH_DIR/bench-riscv64.tmp.$$" "$BENCH_DIR/bench-riscv64" && rm -f "$BENCH_DIR/bench-riscv64.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-riscv32"; then
            "$clang_raw" --target=riscv32-unknown-linux-gnu -march=rv32gc -mabi=ilp32d $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-riscv32.o" && \
            "$lld_raw" -m elf32lriscv -Bstatic --no-dynamic-linker --image-base=0x00010000 -e _start "$BENCH_DIR/bench-riscv32.o" -o "$BENCH_DIR/bench-riscv32.tmp.$$" && \
            mv "$BENCH_DIR/bench-riscv32.tmp.$$" "$BENCH_DIR/bench-riscv32" && rm -f "$BENCH_DIR/bench-riscv32.o" || true
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-aarch64"; then
            "$clang_raw" --target=aarch64-unknown-linux-gnu $fs_flags -c "$SRC_FILE" -o "$BENCH_DIR/bench-aarch64.o" && \
            "$lld_raw" -m aarch64linux -Bstatic --no-dynamic-linker --image-base=0x00400000 -e _start "$BENCH_DIR/bench-aarch64.o" -o "$BENCH_DIR/bench-aarch64.tmp.$$" && \
            mv "$BENCH_DIR/bench-aarch64.tmp.$$" "$BENCH_DIR/bench-aarch64" && rm -f "$BENCH_DIR/bench-aarch64.o" || true
        fi
    fi
    if need_bench_rebuild "$BENCH_DIR/bench-darwin-arm64" && command -v cc >/dev/null 2>&1; then
        cc -std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 "$SRC_FILE" -o "$BENCH_DIR/bench-darwin-arm64.tmp.$$" && \
        mv "$BENCH_DIR/bench-darwin-arm64.tmp.$$" "$BENCH_DIR/bench-darwin-arm64" || true
    fi
    if { need_bench_rebuild "$BENCH_DIR/bench-sparc32" || need_bench_rebuild "$BENCH_DIR/bench-sparc32-smoke"; } && \
       command -v docker >/dev/null 2>&1 && docker image inspect sparc32rt-oracle:latest >/dev/null 2>&1; then
        timeout --kill-after=10s 45s docker run --rm --name "rt-bench-sparc32-$$" --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w sparc32rt-oracle:latest sh -c "
                set -eu
                sparc64-linux-gnu-gcc -m32 -mcpu=v8 -std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 -ffreestanding -fno-stack-protector -nostdlib -static -DBENCH_FREESTANDING=1 /w/tests/bench_suite.c -lgcc -o /w/_build/bench/bench-sparc32.tmp.$$
                sparc64-linux-gnu-gcc -m32 -mcpu=v8 -std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 -ffreestanding -fno-stack-protector -nostdlib -static -DBENCH_FREESTANDING=1 -DBENCH_SMOKE=1 /w/tests/bench_suite.c -lgcc -o /w/_build/bench/bench-sparc32-smoke.tmp.$$
                mv /w/_build/bench/bench-sparc32.tmp.$$ /w/_build/bench/bench-sparc32
                mv /w/_build/bench/bench-sparc32-smoke.tmp.$$ /w/_build/bench/bench-sparc32-smoke
            " || true
        cleanup_bench_containers
    fi

    # 2. Fast-path: use locally cached per-arch toolchain images if present (zero network)
    if need_bench_rebuild "$BENCH_DIR/bench-loongarch64" && command -v docker >/dev/null 2>&1 && docker image inspect loongarch64rt-l3a-tool:latest >/dev/null 2>&1; then
        timeout --kill-after=10s 45s docker run --rm --name "rt-bench-la64-$$" --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w loongarch64rt-l3a-tool:latest \
            loongarch64-linux-gnu-gcc -std=c11 -O2 -fno-tree-vectorize -static -Wall -Wextra -Werror=vla -pedantic \
            /w/tests/bench_suite.c -o /w/_build/bench/bench-loongarch64 || true
        cleanup_bench_containers
    fi
    if need_bench_rebuild "$BENCH_DIR/bench-ppc64le" && command -v docker >/dev/null 2>&1 && docker image inspect ppc64rt-l3a-tool:latest >/dev/null 2>&1; then
        timeout --kill-after=10s 45s docker run --rm --name "rt-bench-ppc64-$$" --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w ppc64rt-l3a-tool:latest \
            powerpc64le-linux-gnu-gcc -std=c11 -O1 -mcpu=power8 -fno-stack-protector -static -Wall -Wextra -Werror=vla -pedantic \
            /w/tests/bench_suite.c -o /w/_build/bench/bench-ppc64le || true
        cleanup_bench_containers
    fi
    if need_bench_rebuild "$BENCH_DIR/bench-mips64el" && command -v docker >/dev/null 2>&1 && docker image inspect mips64rt-parity-env:trixie >/dev/null 2>&1; then
        timeout --kill-after=10s 45s docker run --rm --name "rt-bench-mips64-$$" --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w mips64rt-parity-env:trixie \
            mips64el-linux-gnuabi64-gcc -std=c11 -O2 -mabi=64 -static -Wl,-z,common-page-size=65536 -Wall -Wextra -Werror=vla -pedantic \
            /w/tests/bench_suite.c -o /w/_build/bench/bench-mips64el || true
        cleanup_bench_containers
    fi
    if need_bench_rebuild "$BENCH_DIR/bench-sparc64" && command -v docker >/dev/null 2>&1 && docker image inspect sparc64rt-l6a-tool:latest >/dev/null 2>&1; then
        timeout --kill-after=10s 45s docker run --rm --name "rt-bench-sparc64-$$" --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w sparc64rt-l6a-tool:latest \
            sparc64-linux-gnu-gcc -std=c11 -O2 -static -Wall -Wextra -Werror=vla -pedantic \
            /w/tests/bench_suite.c -o /w/_build/bench/bench-sparc64 || true
        cleanup_bench_containers
    fi

    # 3. Build any still-missing guest ELF binaries in a bounded Debian container
    local missing=0
    for a in "${ALL_ARCHES[@]}"; do
        if [ "$ARCH_FILTER" != "all" ] && [ "$ARCH_FILTER" != "$a" ]; then
            continue
        fi
        if need_bench_rebuild "$BENCH_DIR/bench-$a"; then
            missing=1
        fi
    done

    if [ "$missing" -eq 1 ]; then
        local build_cname="rt-bench-build-$$"
        timeout --kill-after=30s 300s docker run --rm --name "$build_cname" \
            --platform linux/arm64 \
            -v "$ROOT_DIR:/w" -w /w \
            debian:trixie-slim bash -c '
                set -euo pipefail
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq >/dev/null
                apt-get install -y -qq \
                    gcc-arm-linux-gnueabihf libc6-dev-armhf-cross \
                    gcc-i686-linux-gnu libc6-dev-i386-cross \
                    gcc-mipsel-linux-gnu libc6-dev-mipsel-cross \
                    gcc-powerpc-linux-gnu libc6-dev-powerpc-cross \
                    gcc-sparc64-linux-gnu libc6-dev-sparc64-cross \
                    gcc-riscv64-linux-gnu libc6-dev-riscv64-cross \
                    gcc-loongarch64-linux-gnu libc6-dev-loong64-cross \
                    gcc-powerpc64le-linux-gnu libc6-dev-ppc64el-cross \
                    gcc-mips64el-linux-gnuabi64 libc6-dev-mips64el-cross >/dev/null

                mkdir -p /w/_build/bench
                CFLAGS="-std=c11 -O2 -static -Wall -Wextra -Werror=vla -pedantic"
                arm-linux-gnueabihf-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-armhf
                i686-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-i686
                mipsel-linux-gnu-gcc $CFLAGS -mips32r2 /w/tests/bench_suite.c -o /w/_build/bench/bench-mipsel
                powerpc-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-ppc32
                sparc64-linux-gnu-gcc -m32 -std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 -ffreestanding -nostdlib -static \
                    -DBENCH_FREESTANDING=1 -DBENCH_SMOKE=1 /w/tests/bench_suite.c -lgcc \
                    -o /w/_build/bench/bench-sparc32-smoke
                sparc64-linux-gnu-gcc -m32 -std=c11 -Werror=vla -pedantic -Wall -Wextra -O2 -ffreestanding -nostdlib -static \
                    -DBENCH_FREESTANDING=1 /w/tests/bench_suite.c -lgcc \
                    -o /w/_build/bench/bench-sparc32
                riscv64-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-riscv64
                loongarch64-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-loongarch64
                powerpc64le-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-ppc64le
                mips64el-linux-gnuabi64-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-mips64el
                sparc64-linux-gnu-gcc $CFLAGS /w/tests/bench_suite.c -o /w/_build/bench/bench-sparc64
            '
        cleanup_bench_containers
    fi

    echo "== Guest benchmark binaries ready in $BENCH_DIR =="
    ls -lh "$BENCH_DIR"/bench-* 2>/dev/null || true
}

check_calm_host() {
    if [ "$BENCH_FORCE" = "1" ]; then
        return 0
    fi
    local load=""
    if [ -r /proc/loadavg ]; then
        load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || true)"
    fi
    if [ -z "$load" ] && command -v sysctl >/dev/null 2>&1; then
        load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || true)"
    fi
    if ! printf '%s' "$load" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        echo "ERROR: Could not query numeric 1-min host loadavg (got '$load')." >&2
        exit 1
    fi
    if awk "BEGIN { exit !($load > $BENCH_MAX_LOAD) }"; then
        echo "ERROR: Host 1-min loadavg ($load) exceeds BENCH_MAX_LOAD ($BENCH_MAX_LOAD)." >&2
        echo "       Run on a calm host (or idle aarch64-darwin-{1,3,4,5}.lan for --target darwin)," >&2
        echo "       or pass --force / BENCH_FORCE=1 to override." >&2
        exit 1
    fi
    echo "== Host load check OK (1-min loadavg=$load <= $BENCH_MAX_LOAD) =="
}

check_bench_output() {
    local label="$1"
    local rc="$2"
    local out="$3"
    if [ "$rc" -ne 0 ] || printf "%s\n" "$out" | grep -qE "FAIL|FAILED"; then
        echo "FAIL [$label] (rc=$rc):"
        printf "%s\n" "$out"
        return 1
    fi
    for wl in coremark chacha20 vfp_simd calls_ibtc syscalls; do
        local cnt
        cnt="$(printf "%s\n" "$out" | grep -cE "^BENCH $wl us=[0-9]+ ops_sec=[0-9]+ crc=0x[0-9a-f]{8} PASS$" || true)"
        if [ "$cnt" -ne 1 ]; then
            echo "FAIL [$label]: workload '$wl' expected 1 PASS record, got $cnt:"
            printf "%s\n" "$out"
            return 1
        fi
    done
    local tot_cnt
    tot_cnt="$(printf "%s\n" "$out" | grep -cE "^BENCH total_us=[0-9]+ ALL_PASS$" || true)"
    if [ "$tot_cnt" -ne 1 ]; then
        echo "FAIL [$label]: expected 1 anchored 'BENCH total_us=<N> ALL_PASS' summary, got $tot_cnt:"
        printf "%s\n" "$out"
        return 1
    fi
    local tot
    tot="$(printf "%s\n" "$out" | sed -n 's/^BENCH total_us=\([0-9][0-9]*\) ALL_PASS$/\1/p')"
    echo "PASS [$label]: total_us=$tot ALL_PASS"
    return 0
}

# Returns: 0 = PASS, 1 = FAIL, 2 = SKIP
run_one_target() {
    local suite_mode="$1"   # smoke | full
    local target="$2"       # darwin | hl | linux | qemu
    local arch="$3"
    local repo
    repo="$(arch_repo "$arch")"
    local guest_bin="$BENCH_DIR/bench-$arch"
    local guest_flag="--$suite_mode"
    if [ "$arch" = "sparc32" ] && [ "$suite_mode" = "smoke" ] && ! need_bench_rebuild "$BENCH_DIR/bench-sparc32-smoke"; then
        guest_bin="$BENCH_DIR/bench-sparc32-smoke"
        guest_flag=""
    fi

    if [ ! -x "$guest_bin" ]; then
        echo "SKIP [$target/$arch]: $guest_bin not built (run 'tools/bench_harness.sh build' first)"
        return 2
    fi

    local a32_interp=0
    local i686_nojit=0
    if [ "$ENGINE" = "interp" ]; then
        a32_interp=1
        i686_nojit=1
    fi

    case "$target" in
        darwin)
            local drt
            if ! drt="$(find_darwin_rt "$repo")"; then
                echo "SKIP [darwin/$arch]: Darwin binary for $repo not built (run 'make -C ../$repo build-darwin')"
                return 2
            fi
            local out=""
            local rc=0
            if [ -n "$guest_flag" ]; then
                out="$(rt_run_bounded_translator 60 "$repo" "$ENGINE" "$drt" "$guest_bin" "$guest_flag" 2>&1)" || rc=$?
            else
                out="$(rt_run_bounded_translator 60 "$repo" "$ENGINE" "$drt" "$guest_bin" 2>&1)" || rc=$?
            fi
            check_bench_output "darwin/$arch/$ENGINE" "$rc" "$out"
            return $?
            ;;
        hl)
            local hl_bin lrt
            if ! hl_bin="$(find_hl_bin)"; then
                echo "SKIP [hl/$arch]: hyper-linux binary not found"
                return 2
            fi
            if ! lrt="$(find_linux_rt "$repo")"; then
                echo "SKIP [hl/$arch]: Linux $repo binary not found"
                return 2
            fi
            local out=""
            local rc=0
            if [ -n "$guest_flag" ]; then
                out="$(rt_run_bounded_hl 90 "$hl_bin" "$repo" "$ENGINE" "$lrt" "$guest_bin" "$guest_flag" 2>&1)" || rc=$?
            else
                out="$(rt_run_bounded_hl 90 "$hl_bin" "$repo" "$ENGINE" "$lrt" "$guest_bin" 2>&1)" || rc=$?
            fi
            check_bench_output "hl/$arch/$ENGINE" "$rc" "$out"
            return $?
            ;;
        linux)
            local lrt
            if ! lrt="$(find_linux_rt "$repo")"; then
                echo "SKIP [linux/$arch]: Linux $repo binary not found"
                return 2
            fi
            local cname="rt-bench-linux-${arch}-$$"
            local c_lrt="/p/$repo/_build/$(basename "$lrt")"
            local c_guest="/p/rt-series/_build/bench/$(basename "$guest_bin")"
            local cmd_prefix
            cmd_prefix="$(rt_format_cmd_prefix "$repo" "$ENGINE" "$c_lrt")"
            # shellcheck disable=SC2206
            local rt_cmd=($cmd_prefix "$c_guest")
            if [ -n "$guest_flag" ]; then
                rt_cmd+=("$guest_flag")
            fi
            local out=""
            local rc=0
            out="$(timeout --kill-after=15s 90s docker run --rm --name "$cname" --platform linux/arm64 \
                -e "A32_INTERP=$a32_interp" -e "I686_NO_JIT=$i686_nojit" \
                -e "I686RT_ENGINE=$ENGINE" -e "RVRT_ENGINE=$ENGINE" \
                -e "MIPS32RT_ENGINE=$ENGINE" -e "PPC32RT_ENGINE=$ENGINE" \
                -e "SPARC32RT_ENGINE=$ENGINE" -e "LOONGARCH64RT_ENGINE=$ENGINE" \
                -e "PPC64RT_ENGINE=$ENGINE" -e "MIPS64RT_ENGINE=$ENGINE" \
                -e "SPARC64RT_ENGINE=$ENGINE" \
                -v "$PROJECTS_DIR:/p:ro" debian:trixie-slim \
                "${rt_cmd[@]}" 2>&1)" || rc=$?
            cleanup_bench_containers
            check_bench_output "linux/$arch/$ENGINE" "$rc" "$out"
            return $?
            ;;
        qemu)
            local qbin
            qbin="$(arch_qemu "$arch")"
            if ! command -v docker >/dev/null 2>&1 || ! docker image inspect mips64rt-qemu:10.0.13 >/dev/null 2>&1; then
                echo "SKIP [qemu/$arch]: mips64rt-qemu:10.0.13 image not present"
                return 2
            fi
            local qcheck_name="rt-bench-qchk-${arch}-$$"
            if ! timeout --kill-after=10s 30s docker run --rm --name "$qcheck_name" --platform linux/arm64 \
                mips64rt-qemu:10.0.13 sh -c "command -v \"$qbin\" >/dev/null 2>&1"; then
                cleanup_bench_containers
                echo "SKIP [qemu/$arch]: $qbin not installed in mips64rt-qemu:10.0.13"
                return 2
            fi
            cleanup_bench_containers
            local cname="rt-bench-qemu-${arch}-$$"
            local out=""
            local rc=0
            local qargs=("$qbin" "/p/rt-series/_build/bench/$(basename "$guest_bin")")
            if [ -n "$guest_flag" ]; then
                qargs+=("$guest_flag")
            fi
            out="$(timeout --kill-after=15s 90s docker run --rm --name "$cname" --platform linux/arm64 \
                -v "$PROJECTS_DIR:/p:ro" mips64rt-qemu:10.0.13 \
                "${qargs[@]}" 2>&1)" || rc=$?
            cleanup_bench_containers
            check_bench_output "qemu/$arch" "$rc" "$out"
            return $?
            ;;
    esac
}

run_matrix() {
    local suite_mode="$1"
    local targets=()
    if [ "$TARGET" = "all" ]; then
        targets=(darwin linux hl qemu)
    else
        targets=("$TARGET")
    fi

    local matched=0
    local passed=0
    local failed=0
    local skipped=0

    for t in "${targets[@]}"; do
        for a in "${ALL_ARCHES[@]}"; do
            if [ "$ARCH_FILTER" != "all" ] && [ "$ARCH_FILTER" != "$a" ]; then
                continue
            fi
            matched=$((matched + 1))
            local rc=0
            run_one_target "$suite_mode" "$t" "$a" || rc=$?
            case "$rc" in
                0) passed=$((passed + 1)) ;;
                2) skipped=$((skipped + 1)) ;;
                *) failed=$((failed + 1)) ;;
            esac
        done
    done

    echo "BENCH HARNESS SUMMARY ($suite_mode): matched=$matched pass=$passed fail=$failed skip=$skipped"
    if [ "$matched" -eq 0 ] || [ "$failed" -gt 0 ] || [ "$passed" -eq 0 ]; then
        exit 1
    fi
    if [ "$skipped" -gt 0 ] && [ "${BENCH_ALLOW_SKIP:-0}" != "1" ]; then
        echo "ERROR: $skipped target(s) skipped; set BENCH_ALLOW_SKIP=1 to permit skips" >&2
        exit 1
    fi
}

case "$MODE" in
    build)
        build_guest_bins
        ;;
    smoke)
        run_matrix "smoke"
        ;;
    run)
        check_calm_host
        run_matrix "full"
        ;;
    *)
        cat << 'EOF'
Usage: tools/bench_harness.sh <build|smoke|run> [options]

Commands:
  build                 Cross-compile guest benchmark ELFs into _build/bench/
  smoke                 Run fast deterministic --smoke CRC verification (<1s/target)
  run                   Run full 5-trial timed benchmark campaign (checks host loadavg)

Options:
  --target <t>          darwin | hl | linux | qemu | all (default: all)
  --arch <a>            armhf | i686 | mipsel | ppc32 | sparc32 | riscv64 |
                        loongarch64 | ppc64le | mips64el | sparc64 | all (default: all)
  --engine <e>          dbt | interp (default: dbt)
  --force               Bypass BENCH_MAX_LOAD check during 'run'
EOF
        ;;
esac
