/*
 * tests/bench_sys.h — Hosted and freestanding syscall/time glue for bench_suite.c
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef RT_SERIES_BENCH_SYS_H
#define RT_SERIES_BENCH_SYS_H

#if !defined(BENCH_FREESTANDING)
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

struct bench_timespec64 {
    int64_t tv_sec;
    int64_t tv_nsec;
};

static bool get_monotonic_time(struct bench_timespec64 *ts)
{
    struct timespec hts = { 0, 0 };
    if (clock_gettime(CLOCK_MONOTONIC, &hts) != 0 ||
        hts.tv_sec < 0 || hts.tv_nsec < 0 || hts.tv_nsec >= 1000000000L) {
        ts->tv_sec  = 0;
        ts->tv_nsec = 0;
        return false;
    }
    ts->tv_sec  = (int64_t)hts.tv_sec;
    ts->tv_nsec = (int64_t)hts.tv_nsec;
    return true;
}

static int32_t do_getpid(void)
{
    return (int32_t)getpid();
}

static void do_write_stdout(const char *buf, size_t len)
{
    ssize_t r = write(STDOUT_FILENO, buf, len);
    (void)r;
}

#else /* BENCH_FREESTANDING */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

__attribute__((weak)) void *memcpy(void *dst, const void *src, size_t n)
{
    volatile uint8_t *d = (volatile uint8_t *)dst;
    const volatile uint8_t *s = (const volatile uint8_t *)src;
    for (size_t i = 0U; i < n; i++) {
        d[i] = s[i];
    }
    return dst;
}

__attribute__((weak)) void *memset(void *dst, int c, size_t n)
{
    volatile uint8_t *d = (volatile uint8_t *)dst;
    for (size_t i = 0U; i < n; i++) {
        d[i] = (uint8_t)c;
    }
    return dst;
}

struct bench_timespec64 {
    int64_t tv_sec;
    int64_t tv_nsec;
};

struct bench_timespec32 {
    int32_t tv_sec;
    int32_t tv_nsec;
};

#if defined(__arm__)
static inline int32_t sys_call(uint32_t nr, uint32_t a0, uint32_t a1, uint32_t a2)
{
    register uint32_t r7 __asm__("r7") = nr;
    register uint32_t r0 __asm__("r0") = a0;
    register uint32_t r1 __asm__("r1") = a1;
    register uint32_t r2 __asm__("r2") = a2;
    __asm__ volatile("svc #0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2) : "memory", "cc");
    return (int32_t)r0;
}
#define FS_32BIT_TIME 1
#define NR_WRITE       4U
#define NR_GETPID      20U
#define NR_EXIT_GROUP  248U
#define NR_CLOCK_GETTIME 263U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, %function\n"
    "_start:\n"
    "    mov r0, sp\n"
    "    bic sp, sp, #7\n"
    "    bl _start_c\n"
);

#elif defined(__i386__)
static inline int32_t sys_call(uint32_t nr, uint32_t a0, uint32_t a1, uint32_t a2)
{
    uint32_t ret = nr;
    __asm__ volatile(
        "int $0x80"
        : "+a"(ret)
        : "b"(a0), "c"(a1), "d"(a2)
        : "memory", "cc"
    );
    return (int32_t)ret;
}
#define FS_32BIT_TIME 1
#define NR_WRITE       4U
#define NR_GETPID      20U
#define NR_EXIT_GROUP  252U
#define NR_CLOCK_GETTIME 265U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, @function\n"
    "_start:\n"
    "    movl %esp, %eax\n"
    "    andl $-16, %esp\n"
    "    subl $12, %esp\n"
    "    pushl %eax\n"
    "    call _start_c\n"
);

#elif defined(__mips__) && !defined(__mips64)
static inline int32_t sys_call(uint32_t nr, uint32_t a0, uint32_t a1, uint32_t a2)
{
    register uint32_t v0 __asm__("$2") = nr;
    register uint32_t r4 __asm__("$4") = a0;
    register uint32_t r5 __asm__("$5") = a1;
    register uint32_t r6 __asm__("$6") = a2;
    register uint32_t r7 __asm__("$7");
    __asm__ volatile(
        "syscall"
        : "+r"(v0), "=r"(r7), "+r"(r4), "+r"(r5), "+r"(r6)
        :
        : "$1", "$3", "$8", "$9", "$10", "$11", "$12", "$13", "$14", "$15",
          "$24", "$25", "hi", "lo", "memory"
    );
    return (r7 != 0U) ? -(int32_t)v0 : (int32_t)v0;
}
#define FS_32BIT_TIME 1
#define NR_WRITE       4004U
#define NR_GETPID      4020U
#define NR_EXIT_GROUP  4246U
#define NR_CLOCK_GETTIME 4263U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, @function\n"
    "_start:\n"
    "    move $4, $29\n"
    "    addiu $29, $29, -32\n"
    "    lui $25, %hi(_start_c)\n"
    "    addiu $25, $25, %lo(_start_c)\n"
    "    jalr $25\n"
    "    nop\n"
);

#elif defined(__powerpc__) && !defined(__powerpc64__)
static inline int32_t sys_call(uint32_t nr, uint32_t a0, uint32_t a1, uint32_t a2)
{
    register uint32_t r0 __asm__("r0") = nr;
    register uint32_t r3 __asm__("r3") = a0;
    register uint32_t r4 __asm__("r4") = a1;
    register uint32_t r5 __asm__("r5") = a2;
    __asm__ volatile(
        "sc"
        : "+r"(r0), "+r"(r3), "+r"(r4), "+r"(r5)
        :
        : "r6", "r7", "r8", "r9", "r10", "r11", "r12", "cr0", "ctr", "memory"
    );
    return (int32_t)r3;
}
#define FS_32BIT_TIME 1
#define NR_WRITE       4U
#define NR_GETPID      20U
#define NR_EXIT_GROUP  234U
#define NR_CLOCK_GETTIME 246U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, @function\n"
    "_start:\n"
    "    mr 3, 1\n"
    "    clrrwi 1, 1, 4\n"
    "    stwu 1, -16(1)\n"
    "    bl _start_c\n"
);

#elif defined(__sparc__) && !defined(__arch64__)
static inline int32_t sys_call(uint32_t nr, uint32_t a0, uint32_t a1, uint32_t a2)
{
    register uint32_t g1 __asm__("g1") = nr;
    register uint32_t o0 __asm__("o0") = a0;
    register uint32_t o1 __asm__("o1") = a1;
    register uint32_t o2 __asm__("o2") = a2;
    __asm__ volatile("ta 0x10" : "+r"(o0) : "r"(g1), "r"(o1), "r"(o2) : "memory", "cc");
    return (int32_t)o0;
}
#define FS_32BIT_TIME 1
#define NR_WRITE       4U
#define NR_GETPID      20U
#define NR_EXIT_GROUP  188U
#define NR_CLOCK_GETTIME 257U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, #function\n"
    "_start:\n"
    "    mov 0, %fp\n"
    "    add %sp, 64, %o0\n"
    "    sub %sp, 64, %sp\n"
    "    call _start_c\n"
    "     nop\n"
);

#elif defined(__riscv)
static inline long sys_call(long nr, long a0, long a1, long a2)
{
    register long a7 __asm__("a7") = nr;
    register long r0 __asm__("a0") = a0;
    register long r1 __asm__("a1") = a1;
    register long r2 __asm__("a2") = a2;
    __asm__ volatile("ecall" : "+r"(r0) : "r"(a7), "r"(r1), "r"(r2) : "memory");
    return r0;
}
#define FS_32BIT_TIME 0
#define NR_WRITE       64U
#define NR_GETPID      172U
#define NR_EXIT_GROUP  94U
#if __riscv_xlen == 32
#define NR_CLOCK_GETTIME 403U
#else
#define NR_CLOCK_GETTIME 113U
#endif
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, @function\n"
    "_start:\n"
    "    mv a0, sp\n"
    "    andi sp, sp, -16\n"
    "    tail _start_c\n"
);

#elif defined(__aarch64__)
static inline long sys_call(long nr, long a0, long a1, long a2)
{
    register long x8 __asm__("x8") = nr;
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
#define FS_32BIT_TIME 0
#define NR_WRITE       64U
#define NR_GETPID      172U
#define NR_EXIT_GROUP  94U
#define NR_CLOCK_GETTIME 113U
__asm__(
    ".text\n"
    ".globl _start\n"
    ".type _start, %function\n"
    "_start:\n"
    "    mov x0, sp\n"
    "    and sp, x0, #-16\n"
    "    bl _start_c\n"
);

#else
#error "Unsupported freestanding target architecture"
#endif

static bool get_monotonic_time(struct bench_timespec64 *ts)
{
#if FS_32BIT_TIME
    struct bench_timespec32 ts32;
    ts32.tv_sec  = 0;
    ts32.tv_nsec = 0;
    int32_t rc = sys_call(NR_CLOCK_GETTIME, 1U, (uint32_t)(uintptr_t)&ts32, 0U);
    if (rc != 0 || ts32.tv_sec < 0 || ts32.tv_nsec < 0 || ts32.tv_nsec >= 1000000000) {
        ts->tv_sec  = 0;
        ts->tv_nsec = 0;
        return false;
    }
    ts->tv_sec  = (int64_t)ts32.tv_sec;
    ts->tv_nsec = (int64_t)ts32.tv_nsec;
    return true;
#else
    ts->tv_sec  = 0;
    ts->tv_nsec = 0;
    long rc = sys_call(NR_CLOCK_GETTIME, 1, (long)(uintptr_t)ts, 0);
    if (rc != 0 || ts->tv_sec < 0 || ts->tv_nsec < 0 || ts->tv_nsec >= 1000000000LL) {
        ts->tv_sec  = 0;
        ts->tv_nsec = 0;
        return false;
    }
    return true;
#endif
}

static int32_t do_getpid(void)
{
    return (int32_t)sys_call(NR_GETPID, 0, 0, 0);
}

static void do_write_stdout(const char *buf, size_t len)
{
    (void)sys_call(NR_WRITE, 1, (long)(uintptr_t)buf, (long)len);
}

static void __attribute__((noreturn)) do_exit_group(int rc)
{
    (void)sys_call(NR_EXIT_GROUP, rc, 0, 0);
    __builtin_unreachable();
}

#endif /* !BENCH_FREESTANDING */

#endif /* RT_SERIES_BENCH_SYS_H */
