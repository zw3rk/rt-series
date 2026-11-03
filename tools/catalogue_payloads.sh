#!/bin/sh
# tools/catalogue_payloads.sh — Embedded C guest source generators / payload
# emitters for tools/run_catalogue.sh guest-payload Tier 4.
#
# Sourced by tools/run_catalogue.sh; provides pure file emitters plus the
# Tier 4 toolchain runner so both files stay <= 900 lines.
#
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
# SPDX-License-Identifier: Apache-2.0

# Emit self-host C probe ($1 = output path).
catalogue_emit_selfhost_c() {
    cat << 'EOF' > "$1"
#include <stdio.h>
#include <math.h>
static int fib(int n) {
    int a = 0, b = 1;
    for (int i = 0; i < n; i++) { int t = a + b; a = b; b = t; }
    return a;
}
int main(void) {
    printf("GCC_SELFHOST_OK:%d:%.3f\n", fib(20), sqrt(2.0));
    return 0;
}
EOF
}

# Emit self-host C++ probe ($1 = output path).
catalogue_emit_selfhost_cxx() {
    cat << 'EOF' > "$1"
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>
struct Base { virtual ~Base() = default; };
struct Derived : Base { int v = 42; };
static int unwind_probe(int x) {
    if (x < 0) throw std::runtime_error("unwind_ok");
    return x;
}
int main() {
    int caught = 0;
    try { unwind_probe(-1); } catch (const std::runtime_error &) { caught = 1; }
    Base *b = new Derived();
    Derived *d = dynamic_cast<Derived *>(b);
    int rtti = (d != nullptr && d->v == 42) ? 1 : 0;
    delete b;
    std::atomic<int> acc(0);
    std::thread t1([&acc]() { for (int i = 0; i < 5000; i++) acc.fetch_add(1); });
    std::thread t2([&acc]() { for (int i = 0; i < 5000; i++) acc.fetch_add(1); });
    t1.join();
    t2.join();
    int thr = (acc.load() == 10000) ? 1 : 0;
    std::cout << "GXX_SELFHOST_OK:" << caught << ":" << rtti << ":" << thr << "\n";
    return (caught == 1 && rtti == 1 && thr == 1) ? 0 : 1;
}
EOF
}

# Emit minimal as/ld probe for the current machine/OS ($1 = output path).
catalogue_emit_mini_s() {
    _cms_out="$1"
    _cms_machine="$(uname -m)"
    _cms_os="$(uname -s)"
    case "$_cms_os" in
        Darwin*)
            case "$_cms_machine" in
                arm64|aarch64)
                    cat << 'EOF' > "$_cms_out"
    .text
    .globl _main
_main:
    mov x0, #42
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0
EOF
                    ;;
                *)
                    cat << 'EOF' > "$_cms_out"
    .text
    .globl _main
_main:
    movl $42, %edi
    movl $0x2000001, %eax
    syscall
EOF
                    ;;
            esac
            ;;
        *)
            case "$_cms_machine" in
                aarch64|arm64)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    mov x0, #42
    mov x8, #93
    svc #0
EOF
                    ;;
                x86_64|amd64)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    mov $60, %rax
    mov $42, %rdi
    syscall
EOF
                    ;;
                i386|i486|i586|i686)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    movl $1, %eax
    movl $42, %ebx
    int $0x80
EOF
                    ;;
                arm*|armv*)
                    cat << 'EOF' > "$_cms_out"
    .syntax unified
    .text
    .global _start
_start:
    mov r0, #42
    mov r7, #1
    svc #0
EOF
                    ;;
                mips64*)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    li $4, 42
    li $2, 5058
    syscall
EOF
                    ;;
                mips|mipsel|mipseb)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    li $4, 42
    li $2, 4001
    syscall
EOF
                    ;;
                ppc*|powerpc*)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    li 3, 42
    li 0, 1
    sc
EOF
                    ;;
                sparc64|sparcv9)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    mov 42, %o0
    mov 1, %g1
    ta 0x6d
EOF
                    ;;
                sparc*)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    mov 42, %o0
    mov 1, %g1
    ta 0x10
EOF
                    ;;
                riscv*)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    li a0, 42
    li a7, 93
    ecall
EOF
                    ;;
                loongarch*)
                    cat << 'EOF' > "$_cms_out"
    .text
    .global _start
_start:
    li.w $a0, 42
    li.w $a7, 93
    syscall 0
EOF
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
}

# Emit guest make -j2 fixture Makefile ($1 = output path).
catalogue_emit_guest_makefile() {
    cat << 'EOF' > "$1"
CC ?= cc
CFLAGS ?= -O1
all: a.o b.o
a.o: a.c
EOF
    printf '\t$(CC) $(CFLAGS) -c a.c -o a.o\n' >> "$1"
    cat << 'EOF' >> "$1"
b.o: b.c
EOF
    printf '\t$(CC) $(CFLAGS) -c b.c -o b.o\n' >> "$1"
}

# Tier 4 runner: git + gcc/g++ self-host + as/ld + objdump + make -j2.
# $1 = work dir. Uses caller-provided fail_now / note_pass / note_skip.
catalogue_run_tier4() {
    _ct4_work="$1"
    echo "== Tier 4: Self-Hosted Compiler Toolchain (binutils + gcc/g++) & Git =="
    if command -v git >/dev/null 2>&1; then
        mkdir -p "$_ct4_work/repo"
        (
            cd "$_ct4_work/repo"
            git init -q -b master || fail_now "T4" "git init -q -b master"
            git config user.email "test@zw3rk.com"
            git config user.name "rt-series test"
            echo "hello git" > README.md
            git add README.md
            git commit -q -m "Initial commit"
            log_msg="$(git log -1 --pretty=%s)"
            [ "$log_msg" = "Initial commit" ] || { echo "FAIL [T4]: git log ($log_msg)" >&2; exit 1; }
        ) || fail_now "T4" "git init/commit/log"
        note_pass "T4" "git init -q -b master + commit + log"
    else
        note_skip "T4" "git"
    fi
    _ct4_have_c=false
    _ct4_have_cxx=false
    if command -v gcc >/dev/null 2>&1 && command -v readelf >/dev/null 2>&1; then
        catalogue_emit_selfhost_c "$_ct4_work/selfhost.c"
        gcc -O2 "$_ct4_work/selfhost.c" -lm -o "$_ct4_work/selfhost.elf" || fail_now "T4" "gcc build selfhost"
        readelf -h "$_ct4_work/selfhost.elf" | grep -q "ELF" || fail_now "T4" "readelf"
        if command -v nm >/dev/null 2>&1; then
            nm -D "$_ct4_work/selfhost.elf" | grep -q "printf" || fail_now "T4" "nm printf"
        fi
        if command -v strip >/dev/null 2>&1; then
            cp "$_ct4_work/selfhost.elf" "$_ct4_work/selfhost.elf.stripped" || fail_now "T4" "cp selfhost.elf"
            strip "$_ct4_work/selfhost.elf.stripped" || fail_now "T4" "strip"
            strip_out="$("$_ct4_work/selfhost.elf.stripped")" || fail_now "T4" "run selfhost.elf.stripped"
            [ "$strip_out" = "GCC_SELFHOST_OK:6765:1.414" ] || fail_now "T4" "stripped selfhost ($strip_out)"
        fi
        self_out="$("$_ct4_work/selfhost.elf")" || fail_now "T4" "run selfhost.elf"
        [ "$self_out" = "GCC_SELFHOST_OK:6765:1.414" ] || fail_now "T4" "gcc selfhost ($self_out)"
        note_pass "T4" "gcc -O2 selfhost + run selfhost.elf"
        _ct4_have_c=true
    else
        note_skip "T4" "gcc selfhost"
    fi
    if command -v g++ >/dev/null 2>&1; then
        catalogue_emit_selfhost_cxx "$_ct4_work/selfhost_cxx.cc"
        g++ -O2 -std=c++17 -pthread "$_ct4_work/selfhost_cxx.cc" -o "$_ct4_work/selfhost_cxx.elf" || fail_now "T4" "g++ build selfhost_cxx"
        cxx_out="$("$_ct4_work/selfhost_cxx.elf")" || fail_now "T4" "run selfhost_cxx.elf"
        [ "$cxx_out" = "GXX_SELFHOST_OK:1:1:1" ] || fail_now "T4" "g++ selfhost ($cxx_out)"
        note_pass "T4" "g++ -std=c++17 std::thread + run selfhost_cxx.elf"
        _ct4_have_cxx=true
    else
        note_skip "T4" "g++ selfhost_cxx"
    fi
    if command -v as >/dev/null 2>&1 && command -v ld >/dev/null 2>&1; then
        if ! catalogue_emit_mini_s "$_ct4_work/mini.s"; then
            fail_now "T4" "unsupported machine '$(uname -m)' for as+ld"
        fi
        case "$(uname -s)" in
            Darwin*)
                as "$_ct4_work/mini.s" -o "$_ct4_work/mini.o" || fail_now "T4" "as mini.s"
                _sdk=""
                if command -v xcrun >/dev/null 2>&1; then
                    _sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
                fi
                if [ -n "$_sdk" ]; then
                    ld -syslibroot "$_sdk" "$_ct4_work/mini.o" -o "$_ct4_work/mini.elf" -lSystem || fail_now "T4" "ld mini.o"
                elif command -v cc >/dev/null 2>&1; then
                    cc "$_ct4_work/mini.o" -o "$_ct4_work/mini.elf" || fail_now "T4" "ld mini.o"
                else
                    ld "$_ct4_work/mini.o" -o "$_ct4_work/mini.elf" -lSystem || fail_now "T4" "ld mini.o"
                fi
                ;;
            *)
                as "$_ct4_work/mini.s" -o "$_ct4_work/mini.o" || fail_now "T4" "as mini.s"
                ld "$_ct4_work/mini.o" -o "$_ct4_work/mini.elf" || fail_now "T4" "ld mini.o"
                if command -v readelf >/dev/null 2>&1; then
                    readelf -h "$_ct4_work/mini.elf" | grep -q "ELF" || fail_now "T4" "mini.elf not ELF"
                fi
                ;;
        esac
        if "$_ct4_work/mini.elf"; then
            mini_code=0
        else
            mini_code=$?
        fi
        [ "$mini_code" = "42" ] || fail_now "T4" "as+ld mini exit=$mini_code"
        note_pass "T4" "as+ld .s link + exit 42"
    else
        note_skip "T4" "as+ld"
    fi
    if command -v objdump >/dev/null 2>&1; then
        if [ "$_ct4_have_c" = "true" ]; then
            objdump -d "$_ct4_work/selfhost.elf" | grep -q "main" || fail_now "T4" "objdump -d main"
            note_pass "T4" "objdump -d selfhost.elf"
        elif [ "$_ct4_have_cxx" = "true" ]; then
            objdump -d "$_ct4_work/selfhost_cxx.elf" | grep -q "main" || fail_now "T4" "objdump -d main"
            note_pass "T4" "objdump -d selfhost_cxx.elf"
        else
            note_skip "T4" "objdump (no selfhost ELF)"
        fi
    else
        note_skip "T4" "objdump"
    fi
    if command -v make >/dev/null 2>&1 && command -v cc >/dev/null 2>&1; then
        mkdir -p "$_ct4_work/mk"
        catalogue_emit_guest_makefile "$_ct4_work/mk/Makefile"
        printf 'int fa(void){return 21;}\n' > "$_ct4_work/mk/a.c"
        printf 'int fa(void);\nint fb(void){return 21;}\nint main(void){return !(fa()+fb()==42);}\n' > "$_ct4_work/mk/b.c"
        make -j2 -C "$_ct4_work/mk" || fail_now "T4" "make -j2"
        [ -f "$_ct4_work/mk/a.o" ] && [ -f "$_ct4_work/mk/b.o" ] || fail_now "T4" "make -j2 outputs"
        note_pass "T4" "make -j2 jobserver build"
    else
        note_skip "T4" "make -j2"
    fi
}
