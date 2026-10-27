/*
 * tests/bench_suite.c — Unified 11-architecture 5-workload benchmark & smoke suite
 *
 * Supports all 11 rt-series guest architectures plus native baselines:
 *   - aarch64, x86_64 (native & Rosetta baselines)
 *   - arm (A32 & Thumb-2), i386, mips32 (O32 LE/BE), ppc32, sparc32 (V8)
 *   - riscv64, riscv32, loongarch64, ppc64le (ELFv2), mips64 (N64/N32 LE/BE), sparc64 (V9)
 *
 * Modes:
 *   - Full Benchmark (default): 1 warmup + 4 timed trials, reports min us & ops/sec
 *   - Smoke Mode (--smoke or -DBENCH_SMOKE=1): 1 trial, 1/40th iterations, fast CRC gate
 *   - Freestanding (-DBENCH_FREESTANDING=1 -ffreestanding -nostdlib): zero-libc mode
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

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

static void get_monotonic_time(struct bench_timespec64 *ts)
{
    struct timespec hts = { 0, 0 };
    (void)clock_gettime(CLOCK_MONOTONIC, &hts);
    ts->tv_sec  = (int64_t)hts.tv_sec;
    ts->tv_nsec = (int64_t)hts.tv_nsec;
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

static void get_monotonic_time(struct bench_timespec64 *ts)
{
#if FS_32BIT_TIME
    struct bench_timespec32 ts32;
    ts32.tv_sec  = 0;
    ts32.tv_nsec = 0;
    (void)sys_call(NR_CLOCK_GETTIME, 1U, (uint32_t)(uintptr_t)&ts32, 0U);
    ts->tv_sec  = (int64_t)ts32.tv_sec;
    ts->tv_nsec = (int64_t)ts32.tv_nsec;
#else
    ts->tv_sec  = 0;
    ts->tv_nsec = 0;
    (void)sys_call(NR_CLOCK_GETTIME, 1, (long)(uintptr_t)ts, 0);
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

/* ========================================================================= */
/* Output Formatting & Software Division Helpers                             */
/* ========================================================================= */

static uint32_t u32_divmod(uint32_t num, uint32_t den, uint32_t *rem_out)
{
    if (den == 0U) {
        if (rem_out != NULL) {
            *rem_out = 0U;
        }
        return 0xFFFFFFFFU;
    }
    uint32_t quot = 0U;
    uint32_t rem  = 0U;
    for (int i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((num >> i) & 1U);
        if (rem >= den) {
            rem  -= den;
            quot |= (1U << i);
        }
    }
    if (rem_out != NULL) {
        *rem_out = rem;
    }
    return quot;
}

static size_t append_str(char *buf, size_t pos, const char *s)
{
    while (*s != '\0') {
        buf[pos++] = *s++;
    }
    return pos;
}

static size_t append_u32(char *buf, size_t pos, uint32_t val)
{
    char tmp[12];
    size_t n = 0U;
    if (val == 0U) {
        buf[pos++] = '0';
        return pos;
    }
    while (val > 0U) {
        uint32_t rem = 0U;
        val = u32_divmod(val, 10U, &rem);
        tmp[n++] = (char)('0' + rem);
    }
    while (n > 0U) {
        buf[pos++] = tmp[--n];
    }
    return pos;
}

static size_t append_hex32(char *buf, size_t pos, uint32_t val)
{
    static const char hex[] = "0123456789abcdef";
    buf[pos++] = '0';
    buf[pos++] = 'x';
    for (int i = 7; i >= 0; i--) {
        buf[pos++] = hex[(val >> (i * 4)) & 0xFU];
    }
    return pos;
}

static uint32_t elapsed_us_between(const struct bench_timespec64 *t0,
                                   const struct bench_timespec64 *t1)
{
    uint32_t sec_diff  = (uint32_t)(t1->tv_sec - t0->tv_sec);
    int32_t  nsec_diff = (int32_t)(t1->tv_nsec - t0->tv_nsec);
    if (nsec_diff < 0) {
        sec_diff--;
        nsec_diff += 1000000000;
    }
    uint32_t us = sec_diff * 1000000U + u32_divmod((uint32_t)nsec_diff, 1000U, NULL);
    return (us == 0U) ? 1U : us;
}

static void report_bench(const char *name, uint32_t iters, uint32_t us,
                         uint32_t crc, bool ok)
{
    uint32_t ops_sec;
    if (iters <= 4000U) {
        ops_sec = u32_divmod(iters * 1000000U, us, NULL);
    } else if (us >= 1000U) {
        uint32_t ms = u32_divmod(us, 1000U, NULL);
        ops_sec = u32_divmod(iters * 1000U, ms, NULL);
    } else {
        uint32_t denom = (us == 0U) ? 1U : us;
        ops_sec = u32_divmod(iters * 1000U, denom, NULL) * 1000U;
    }
    char line[128];
    size_t pos = 0U;
    pos = append_str(line, pos, "BENCH ");
    pos = append_str(line, pos, name);
    pos = append_str(line, pos, " us=");
    pos = append_u32(line, pos, us);
    pos = append_str(line, pos, " ops_sec=");
    pos = append_u32(line, pos, ops_sec);
    pos = append_str(line, pos, " crc=");
    pos = append_hex32(line, pos, crc);
    pos = append_str(line, pos, ok ? " PASS\n" : " FAIL\n");
    do_write_stdout(line, pos);
}

/* ========================================================================= */
/* Workload 1: CoreMark-style Integer Control, List Sort, MatMul & Tokenizer */
/* ========================================================================= */

typedef struct list_node {
    struct list_node *next;
    uint32_t val;
} list_node_t;

static uint16_t crc16_update(uint16_t crc, uint8_t byte)
{
    crc = (uint16_t)(crc ^ (uint16_t)((uint16_t)byte << 8));
    for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000U) != 0U) {
            crc = (uint16_t)((uint16_t)(crc << 1) ^ 0x1021U);
        } else {
            crc = (uint16_t)(crc << 1);
        }
    }
    return crc;
}

static int bench_coremark(bool smoke, uint32_t *out_us)
{
    const uint32_t iters      = smoke ? 50U : 2000U;
    const uint32_t trials     = smoke ? 1U : 5U;
    const uint16_t expect_crc = smoke ? 0xedd5U : 0x41ddU;
    uint32_t min_us = 0xFFFFFFFFU;
    uint16_t crc = 0xFFFFU;
    bool all_ok = true;

    for (uint32_t trial = 0U; trial < trials; trial++) {
        struct bench_timespec64 t0, t1;
        get_monotonic_time(&t0);

        crc = 0xFFFFU;
        for (uint32_t it = 0U; it < iters; it++) {
            int32_t A[4][4];
            int32_t B[4][4];
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 4; j++) {
                    A[i][j] = (int32_t)((it * 17U + (uint32_t)i * 5U + (uint32_t)j) & 0xFFU);
                    B[i][j] = (int32_t)((it * 13U + (uint32_t)j * 7U + (uint32_t)i) & 0xFFU);
                }
            }
            uint32_t c_sum = 0U;
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 4; j++) {
                    int32_t acc = 0;
                    for (int k = 0; k < 4; k++) {
                        acc += A[i][k] * B[k][j];
                    }
                    c_sum += (uint32_t)acc;
                }
            }

            list_node_t nodes[16];
            for (uint32_t k = 0U; k < 16U; k++) {
                nodes[k].next = (k + 1U < 16U) ? &nodes[k + 1U] : NULL;
                nodes[k].val  = (it * 31U + k * 19U + 7U) & 0xFFU;
            }
            for (int pass = 0; pass < 16; pass++) {
                list_node_t *curr = &nodes[0];
                while (curr != NULL && curr->next != NULL) {
                    if (curr->val > curr->next->val) {
                        uint32_t tmp    = curr->val;
                        curr->val       = curr->next->val;
                        curr->next->val = tmp;
                    }
                    curr = curr->next;
                }
            }
            uint32_t l_sum = 0U;
            list_node_t *p = &nodes[0];
            while (p != NULL) {
                l_sum += p->val;
                p = p->next;
            }

            static const char text[] = "int a = 123 + 456; /* test */ if (a > 0) a = a - 1;";
            uint32_t tokens = 0U;
            int state = 0;
            for (size_t s = 0U; s < sizeof(text) - 1U; s++) {
                char ch = text[s];
                if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
                    state = 0;
                } else if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
                    if (state != 1) {
                        tokens++;
                        state = 1;
                    }
                } else if (ch >= '0' && ch <= '9') {
                    if (state != 2) {
                        tokens++;
                        state = 2;
                    }
                } else {
                    tokens++;
                    state = 3;
                }
            }

            crc = crc16_update(crc, (uint8_t)(c_sum & 0xFFU));
            crc = crc16_update(crc, (uint8_t)((c_sum >> 8) & 0xFFU));
            crc = crc16_update(crc, (uint8_t)((c_sum >> 16) & 0xFFU));
            crc = crc16_update(crc, (uint8_t)((c_sum >> 24) & 0xFFU));
            crc = crc16_update(crc, (uint8_t)(l_sum & 0xFFU));
            crc = crc16_update(crc, (uint8_t)((l_sum >> 8) & 0xFFU));
            crc = crc16_update(crc, (uint8_t)(tokens & 0xFFU));
        }

        get_monotonic_time(&t1);
        if (crc != expect_crc) {
            all_ok = false;
        }
        if (smoke || trial >= 1U) {
            uint32_t us = elapsed_us_between(&t0, &t1);
            if (us < min_us) {
                min_us = us;
            }
        }
    }

    *out_us = min_us;
    report_bench("coremark", iters, min_us, (uint32_t)crc, all_ok);
    return all_ok ? 0 : 1;
}

/* ========================================================================= */
/* Workload 2: ChaCha20 20-Round ARX Stream Cipher                           */
/* ========================================================================= */

static inline uint32_t rotl32(uint32_t x, unsigned n)
{
    return (x << n) | (x >> (32U - n));
}

#define CHACHA_QR(a, b, c, d)             \
    do {                                  \
        (a) += (b);                       \
        (d) ^= (a);                       \
        (d) = rotl32((d), 16U);           \
        (c) += (d);                       \
        (b) ^= (c);                       \
        (b) = rotl32((b), 12U);           \
        (a) += (b);                       \
        (d) ^= (a);                       \
        (d) = rotl32((d), 8U);            \
        (c) += (d);                       \
        (b) ^= (c);                       \
        (b) = rotl32((b), 7U);            \
    } while (0)

static int bench_chacha20(bool smoke, uint32_t *out_us)
{
    const uint32_t blocks     = smoke ? 200U : 8000U;
    const uint32_t trials     = smoke ? 1U : 5U;
    const uint32_t expect_acc = smoke ? 0x5ff8eba4U : 0x065fe64fU;
    uint32_t min_us = 0xFFFFFFFFU;
    uint32_t acc = 0U;
    bool all_ok = true;

    for (uint32_t trial = 0U; trial < trials; trial++) {
        struct bench_timespec64 t0, t1;
        get_monotonic_time(&t0);

        acc = 0U;
        for (uint32_t blk = 0U; blk < blocks; blk++) {
            uint32_t x0  = 0x61707865U, x1  = 0x3320646eU, x2  = 0x79622d32U, x3  = 0x6b206574U;
            uint32_t x4  = 0x03020100U, x5  = 0x07060504U, x6  = 0x0b0a0908U, x7  = 0x0f0e0d0cU;
            uint32_t x8  = 0x13121110U, x9  = 0x17161514U, x10 = 0x1b1a1918U, x11 = 0x1f1e1d1cU;
            uint32_t x12 = blk ^ acc,   x13 = 0x00000000U, x14 = 0x4a000000U, x15 = 0x00000000U;

            for (int r = 0; r < 10; r++) {
                CHACHA_QR(x0, x4,  x8, x12);
                CHACHA_QR(x1, x5,  x9, x13);
                CHACHA_QR(x2, x6, x10, x14);
                CHACHA_QR(x3, x7, x11, x15);
                CHACHA_QR(x0, x5, x10, x15);
                CHACHA_QR(x1, x6, x11, x12);
                CHACHA_QR(x2, x7,  x8, x13);
                CHACHA_QR(x3, x4,  x9, x14);
            }
            acc ^= (x0 + x4 + x8 + x12) ^ (x3 + x7 + x11 + x15);
        }

        get_monotonic_time(&t1);
        if (acc != expect_acc) {
            all_ok = false;
        }
        if (smoke || trial >= 1U) {
            uint32_t us = elapsed_us_between(&t0, &t1);
            if (us < min_us) {
                min_us = us;
            }
        }
    }

    *out_us = min_us;
    report_bench("chacha20", blocks, min_us, acc, all_ok);
    return all_ok ? 0 : 1;
}

/* ========================================================================= */
/* Workload 3: Floating-Point & SIMD (FP32 MatVec + FP64 Mandelbrot)         */
/* ========================================================================= */

#if defined(__clang__)
#pragma STDC FP_CONTRACT OFF
#elif defined(__GNUC__)
#pragma GCC optimize ("fp-contract=off")
#endif

static int bench_vfp_simd(bool smoke, uint32_t *out_us)
{
    const uint32_t iters      = smoke ? 1000U : 40000U;
    const uint32_t trials     = smoke ? 1U : 5U;
    const uint32_t expect_chk = smoke ? 0xfffff160U : 0xfffdaf18U;
    uint32_t min_us = 0xFFFFFFFFU;
    uint32_t chk = 0U;
    bool all_ok = true;

    for (uint32_t trial = 0U; trial < trials; trial++) {
        struct bench_timespec64 t0, t1;
        get_monotonic_time(&t0);

        float  mat_a[16] = {
            1.25f, 0.50f, -0.75f, 2.00f,
            0.25f, 1.50f,  0.50f, -1.00f,
           -0.50f, 0.75f,  1.25f, 0.25f,
            1.00f, -0.25f, 0.50f, 1.75f
        };
        float  vec_x[4] = { 1.0f, 2.0f, 3.0f, 4.0f };
        double m_acc    = 0.0;

        for (uint32_t it = 0U; it < iters; it++) {
            uint32_t step = it;
            __asm__ volatile("" : "+r"(step));
            float bias = (float)(step & 7U) * 0.015625f;
            float out[4];
            for (int r = 0; r < 4; r++) {
                out[r] = mat_a[r * 4 + 0] * vec_x[0] +
                         mat_a[r * 4 + 1] * vec_x[1] +
                         mat_a[r * 4 + 2] * vec_x[2] +
                         mat_a[r * 4 + 3] * vec_x[3] + bias;
            }
            vec_x[0] = out[0] * 0.25f;
            vec_x[1] = out[1] * 0.25f;
            vec_x[2] = out[2] * 0.25f;
            vec_x[3] = out[3] * 0.25f;

            double cr = -0.75 + (double)(step & 15U) * 0.00390625;
            double ci =  0.25;
            double zr = cr, zi = ci;
            for (int k = 0; k < 4; k++) {
                double zr2 = zr * zr - zi * zi + cr;
                double zi2 = 2.0 * zr * zi + ci;
                zr = zr2;
                zi = zi2;
            }
            m_acc += zr + zi;
        }

        get_monotonic_time(&t1);
        chk = (uint32_t)(int32_t)(m_acc * 16.0) ^
              (uint32_t)(int32_t)(vec_x[0] * 1024.0f);
        if (chk != expect_chk) {
            all_ok = false;
        }
        if (smoke || trial >= 1U) {
            uint32_t us = elapsed_us_between(&t0, &t1);
            if (us < min_us) {
                min_us = us;
            }
        }
    }

    *out_us = min_us;
    report_bench("vfp_simd", iters, min_us, chk, all_ok);
    return all_ok ? 0 : 1;
}

/* ========================================================================= */
/* Workload 4: Calls, Recursion & Indirect Branching (fib + vtable)          */
/* ========================================================================= */

static uint32_t __attribute__((noinline)) fib_rec(uint32_t n)
{
    __asm__ volatile("" : "+r"(n));
    if (n < 2U) {
        return n;
    }
    return fib_rec(n - 1U) + fib_rec(n - 2U);
}

typedef uint32_t (*vop_fn)(uint32_t x, uint32_t y);

static uint32_t __attribute__((noinline)) vop_add(uint32_t x, uint32_t y)
{
    return x + (y ^ 0x9e3779b9U);
}

static uint32_t __attribute__((noinline)) vop_xor(uint32_t x, uint32_t y)
{
    return (x ^ y) + 0x7f4a7c15U;
}

static uint32_t __attribute__((noinline)) vop_rol(uint32_t x, uint32_t y)
{
    return rotl32(x + y, 7U);
}

static uint32_t __attribute__((noinline)) vop_mul(uint32_t x, uint32_t y)
{
    return (x * 1664525U) + y + 1013904223U;
}

static int bench_calls_ibtc(bool smoke, uint32_t *out_us)
{
    const uint32_t fib_n        = smoke ? 18U : 28U;
    const uint32_t expect_fib   = smoke ? 2584U : 317811U;
    const uint32_t vtable_iters = smoke ? 5000U : 200000U;
    const uint32_t trials       = smoke ? 1U : 5U;
    const uint32_t expect_state = smoke ? 0x5b06486eU : 0xed9c5a0aU;
    uint32_t min_us = 0xFFFFFFFFU;
    uint32_t state = 0U;
    bool all_ok = true;

    for (uint32_t trial = 0U; trial < trials; trial++) {
        struct bench_timespec64 t0, t1;
        get_monotonic_time(&t0);

        uint32_t fn_res = fib_rec(fib_n);

        vop_fn table[4] = { vop_add, vop_xor, vop_rol, vop_mul };
        __asm__ volatile("" : "+m"(table));

        state = fn_res;
        for (uint32_t i = 0U; i < vtable_iters; i++) {
            vop_fn fn = table[(state ^ i) & 3U];
            state = fn(state, i);
        }

        get_monotonic_time(&t1);
        if (fn_res != expect_fib || state != expect_state) {
            all_ok = false;
        }
        if (smoke || trial >= 1U) {
            uint32_t us = elapsed_us_between(&t0, &t1);
            if (us < min_us) {
                min_us = us;
            }
        }
    }

    *out_us = min_us;
    report_bench("calls_ibtc", (smoke ? 8361U : 1028457U) + vtable_iters,
                 min_us, state, all_ok);
    return all_ok ? 0 : 1;
}

/* ========================================================================= */
/* Workload 5: Syscall ABI Shim Throughput (getpid syscalls)                 */
/* ========================================================================= */

static int bench_syscalls(bool smoke, uint32_t *out_us)
{
    const uint32_t iters  = smoke ? 100U : 4000U;
    const uint32_t trials = smoke ? 1U : 5U;
    uint32_t min_us = 0xFFFFFFFFU;
    uint32_t acc = 0U;
    bool all_ok = true;

    for (uint32_t trial = 0U; trial < trials; trial++) {
        struct bench_timespec64 t0, t1;
        get_monotonic_time(&t0);

        acc = 0U;
        int32_t first_pid = do_getpid();
        for (uint32_t i = 0U; i < iters; i++) {
            int32_t p = do_getpid();
            if (p == first_pid) {
                acc++;
            }
        }

        get_monotonic_time(&t1);
        if (acc != iters || first_pid <= 0) {
            all_ok = false;
        }
        if (smoke || trial >= 1U) {
            uint32_t us = elapsed_us_between(&t0, &t1);
            if (us < min_us) {
                min_us = us;
            }
        }
    }

    *out_us = min_us;
    report_bench("syscalls", iters, min_us, acc, all_ok);
    return all_ok ? 0 : 1;
}

static int run_suite(bool smoke)
{
    uint32_t us_cm = 0U, us_cc = 0U, us_fp = 0U, us_cl = 0U, us_sc = 0U;
    int rc = 0;
    rc |= bench_coremark(smoke, &us_cm);
    rc |= bench_chacha20(smoke, &us_cc);
    rc |= bench_vfp_simd(smoke, &us_fp);
    rc |= bench_calls_ibtc(smoke, &us_cl);
    rc |= bench_syscalls(smoke, &us_sc);

    uint32_t total_us = us_cm + us_cc + us_fp + us_cl + us_sc;
    char msg[96];
    size_t pos = 0U;
    pos = append_str(msg, pos, "BENCH total_us=");
    pos = append_u32(msg, pos, total_us);
    pos = append_str(msg, pos, (rc == 0) ? " ALL_PASS\n" : " FAILED\n");
    do_write_stdout(msg, pos);
    return rc;
}

static bool str_eq(const char *a, const char *b)
{
    if (a == NULL || b == NULL) return false;
    while (*a != '\0' && *b != '\0') {
        if (*a != *b) return false;
        a++;
        b++;
    }
    return *a == *b;
}

#if defined(BENCH_SMOKE) && BENCH_SMOKE
#define BENCH_DEFAULT_SMOKE true
#else
#define BENCH_DEFAULT_SMOKE false
#endif

#if defined(BENCH_FREESTANDING)
void __attribute__((noreturn)) _start_c(uintptr_t *sp)
{
    bool smoke = BENCH_DEFAULT_SMOKE;
    if (sp != NULL && sp[0] >= 1U && sp[0] <= 64U) {
        for (uintptr_t i = 1U; i < sp[0]; i++) {
            const char *arg = (const char *)sp[1U + i];
            if (str_eq(arg, "--smoke")) smoke = true;
            else if (str_eq(arg, "--full")) smoke = false;
        }
    }
    do_exit_group(run_suite(smoke));
}
#else
int main(int argc, char **argv)
{
    bool smoke = BENCH_DEFAULT_SMOKE;
    for (int i = 1; i < argc; i++) {
        if (str_eq(argv[i], "--smoke")) smoke = true;
        else if (str_eq(argv[i], "--full")) smoke = false;
    }
    return run_suite(smoke);
}
#endif
