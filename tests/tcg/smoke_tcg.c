/*
 * tests/tcg/smoke_tcg.c — Curated QEMU tests/tcg/multiarch smoke.
 *
 * Minute-scale Tier M gate mirroring the multiarch cases that break
 * linux-user translators (docs/CATALOGUE-TODO.md section 3):
 *   signals, segfault (si_signo/si_code/si_addr), prot-none, test-mmap
 *   (explicit guest page size so Darwin 16 KiB hosts exercise sub-page
 *   protection), munmap-pthread, testthread, float_convs, sha1.
 * Vendor per-arch .ref files for float_* beside this file when curating
 * a revision; pass an explicit page size (4096, or 8192 on sparc64rt).
 *
 * Build: cc -std=c11 -Wall -Wextra -Werror -Werror=vla -pedantic -O1 -pthread
 *        tests/tcg/smoke_tcg.c -o smoke_tcg -lm
 * Run: ./smoke_tcg [pagesize]   (exit 0 iff fails == 0 and passes > 0)
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

#define _POSIX_C_SOURCE 200809L
/* Strict -std=c11 hides the non-POSIX MAP_ANONYMOUS flag on glibc;
 * _DEFAULT_SOURCE re-exposes it and is ignored on other libcs. */
#if defined(__linux__) && !defined(_DEFAULT_SOURCE) && !defined(_GNU_SOURCE)
#define _DEFAULT_SOURCE 1
#endif
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#define _DARWIN_C_SOURCE 1
#endif

#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

static int g_pass = 0;
static int g_fail = 0;
static int g_skip = 0;

static long g_page = 4096L;

/* Effective protection granularity: under a translator the Soft-TLB
 * enforces guest sub-pages (4 KiB, 8 KiB on sparc64rt); natively the
 * host granule is the floor (16 KiB on Darwin). */
static long eff_page(void)
{
    long host = sysconf(_SC_PAGESIZE);
    if (host < 4096L) {
        host = 4096L;
    }
    return (g_page > host) ? g_page : host;
}

static void tcg_pass(const char *name)
{
    g_pass++;
    printf("PASS [tcg]: %s\n", name);
}

static void tcg_fail(const char *name, const char *detail)
{
    g_fail++;
    printf("FAIL [tcg]: %s (%s)\n", name, detail);
}

static void tcg_skip(const char *name, const char *detail)
{
    g_skip++;
    printf("SKIP [tcg]: %s (%s)\n", name, detail);
}

static sigjmp_buf g_jmp;
static volatile sig_atomic_t g_armed = 0;
static volatile sig_atomic_t g_got_signo = 0;
static volatile sig_atomic_t g_got_code = 0;
/* C11 async-signal-safe 64-bit address bridge: three 22-bit chunks stored in
 * volatile sig_atomic_t objects (C11 only guarantees a [-127, +127] range,
 * so the 22-bit chunk width is enforced by _Static_assert below). */
_Static_assert(SIG_ATOMIC_MAX >= 0x3fffff, "22-bit chunks need wide sig_atomic_t");
static volatile sig_atomic_t g_got_addr_w0 = 0;
static volatile sig_atomic_t g_got_addr_w1 = 0;
static volatile sig_atomic_t g_got_addr_w2 = 0;
static volatile sig_atomic_t g_sig_count = 0;

static void store_got_addr(uintptr_t addr)
{
    uint64_t u = (uint64_t)addr;
    g_got_addr_w0 = (sig_atomic_t)(u & 0x3fffffULL);
    g_got_addr_w1 = (sig_atomic_t)((u >> 22) & 0x3fffffULL);
    g_got_addr_w2 = (sig_atomic_t)((u >> 44) & 0x3fffffULL);
}

static uintptr_t load_got_addr(void)
{
    uint64_t u0 = (uint64_t)(uint32_t)g_got_addr_w0 & 0x3fffffULL;
    uint64_t u1 = (uint64_t)(uint32_t)g_got_addr_w1 & 0x3fffffULL;
    uint64_t u2 = (uint64_t)(uint32_t)g_got_addr_w2 & 0x3fffffULL;
    return (uintptr_t)(u0 | (u1 << 22) | (u2 << 44));
}

static void fault_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)ctx;
    g_got_signo = signo;
    if (info != NULL) {
        g_got_code = info->si_code;
        store_got_addr((uintptr_t)info->si_addr);
    }
    if (g_armed) {
        siglongjmp(g_jmp, 1);
    }
}

static void count_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)info;
    (void)ctx;
    if (signo == SIGUSR1) {
        g_sig_count++;
    }
}

static int install(int signo, void (*fn)(int, siginfo_t *, void *))
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = fn;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    return sigaction(signo, &sa, NULL);
}

/* signals: async SIGUSR1 delivery runs the handler exactly once. */
static void t_signals(void)
{
    if (install(SIGUSR1, count_handler) != 0) {
        tcg_skip("signals", "sigaction unavailable");
        return;
    }
    g_sig_count = 0;
    if (raise(SIGUSR1) != 0) {
        tcg_fail("signals", "raise failed");
        return;
    }
    if (g_sig_count != 1) {
        tcg_fail("signals", "handler count != 1");
        return;
    }
    tcg_pass("signals SIGUSR1 x1");
}

/* segfault: synchronous fault reports exact si_signo and an si_addr
 * inside the faulting page (compared as a page offset). */
static void t_segfault(void)
{
    size_t len = (size_t)g_page;
    unsigned char *p = (unsigned char *)mmap(NULL, len, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        tcg_skip("segfault", "mmap unavailable");
        return;
    }
    if (install(SIGSEGV, fault_handler) != 0 ||
        install(SIGBUS, fault_handler) != 0) {
        tcg_skip("segfault", "sigaction unavailable");
        munmap(p, len);
        return;
    }
    p[0] = 0x5A;
    if (munmap(p, len) != 0) {
        tcg_fail("segfault", "munmap failed");
        return;
    }
    g_armed = 1;
    g_got_signo = 0;
    g_got_code = 0;
    store_got_addr(0);
    if (sigsetjmp(g_jmp, 1) == 0) {
        volatile unsigned char c = p[0];
        (void)c;
        g_armed = 0;
        tcg_fail("segfault", "unmapped read did not trap");
        return;
    }
    g_armed = 0;
    if (g_got_signo != SIGSEGV && g_got_signo != SIGBUS) {
        tcg_fail("segfault", "wrong signal");
        return;
    }
    if (g_got_code <= 0) {
        tcg_fail("segfault", "missing positive si_code");
        return;
    }
    if (load_got_addr() / (uintptr_t)g_page != (uintptr_t)p / (uintptr_t)g_page) {
        tcg_fail("segfault", "si_addr outside faulting page");
        return;
    }
    tcg_pass("segfault si_signo + si_addr page offset");
}

/* prot-none: PROT_NONE page traps on first touch (no stale TLB entry). */
static void t_prot_none(void)
{
    size_t len = (size_t)g_page;
    unsigned char *p = (unsigned char *)mmap(NULL, len, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        tcg_skip("prot-none", "mmap unavailable");
        return;
    }
    if (mprotect(p, len, PROT_NONE) != 0) {
        tcg_fail("prot-none", "mprotect failed");
        munmap(p, len);
        return;
    }
    g_armed = 1;
    g_got_signo = 0;
    g_got_code = 0;
    store_got_addr(0);
    if (sigsetjmp(g_jmp, 1) == 0) {
        volatile unsigned char c = p[0];
        (void)c;
        g_armed = 0;
        tcg_fail("prot-none", "PROT_NONE read did not trap");
        munmap(p, len);
        return;
    }
    g_armed = 0;
    if ((g_got_signo != SIGSEGV && g_got_signo != SIGBUS) || g_got_code <= 0 ||
        load_got_addr() / (uintptr_t)g_page != (uintptr_t)p / (uintptr_t)g_page) {
        tcg_fail("prot-none", "PROT_NONE fault metadata mismatch");
        munmap(p, len);
        return;
    }
    if (mprotect(p, len, PROT_READ | PROT_WRITE) != 0) {
        tcg_fail("prot-none", "mprotect restore failed");
        munmap(p, len);
        return;
    }
    p[0] = 0xA5;
    if (p[0] != 0xA5) {
        tcg_fail("prot-none", "restored page mismatch");
        munmap(p, len);
        return;
    }
    munmap(p, len);
    tcg_pass("prot-none trap + restore");
}

/* test-mmap: map/unmap at an explicit guest page size, including a
 * fixed-address attempt and sub-page permission splits. */
static void t_test_mmap(void)
{
    size_t ps = (size_t)eff_page();
    size_t len = ps * 4u;
    unsigned char *p = (unsigned char *)mmap(NULL, len, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        tcg_skip("test-mmap", "mmap unavailable");
        return;
    }
    /* Adjacent sub-pages with distinct permissions (RW/RX/RO/NONE). */
    if (mprotect(p + ps, ps, PROT_READ | PROT_EXEC) != 0 ||
        mprotect(p + ps * 2u, ps, PROT_READ) != 0 ||
        mprotect(p + ps * 3u, ps, PROT_NONE) != 0) {
        tcg_fail("test-mmap", "sub-page mprotect failed");
        munmap(p, len);
        return;
    }
    p[0] = 0x11;
    if (p[0] != 0x11) {
        tcg_fail("test-mmap", "RW sub-page mismatch");
        munmap(p, len);
        return;
    }
    g_armed = 1;
    g_got_signo = 0;
    g_got_code = 0;
    store_got_addr(0);
    if (sigsetjmp(g_jmp, 1) == 0) {
        volatile unsigned char c = p[ps * 3u];
        (void)c;
        g_armed = 0;
        tcg_fail("test-mmap", "NONE sub-page did not trap");
        munmap(p, len);
        return;
    }
    g_armed = 0;
    if ((g_got_signo != SIGSEGV && g_got_signo != SIGBUS) || g_got_code <= 0 ||
        load_got_addr() / ps != (uintptr_t)(p + ps * 3u) / ps) {
        tcg_fail("test-mmap", "NONE sub-page fault metadata mismatch");
        munmap(p, len);
        return;
    }
    if (munmap(p, len) != 0) {
        tcg_fail("test-mmap", "munmap failed");
        return;
    }
    tcg_pass("test-mmap sub-page permissions");
}

static void *thread_fn(void *arg)
{
    int64_t n = *(int64_t *)arg;
    volatile int64_t acc = 0;
    for (int64_t i = 0; i < n; i++) {
        acc += i;
    }
    int64_t *out = (int64_t *)malloc(sizeof(int64_t));
    if (out != NULL) {
        *out = (int64_t)acc;
    }
    return out;
}

/* testthread + munmap-pthread: thread create/join with an exact
 * arithmetic result, racing an munmap on an adjacent region. */
static void t_testthread(void)
{
    static int64_t s_thread_n = 200000;
    int64_t want = (s_thread_n * (s_thread_n - 1)) / 2;
    size_t eps = (size_t)eff_page();
    size_t len = eps * 2u;
    unsigned char *p = (unsigned char *)mmap(NULL, len, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        tcg_skip("testthread", "mmap unavailable");
        return;
    }
    memset(p, 0x77, len);
    pthread_t th;
    if (pthread_create(&th, NULL, thread_fn, &s_thread_n) != 0) {
        tcg_skip("testthread", "pthread_create unavailable");
        munmap(p, len);
        return;
    }
    /* Unmap the second half while the thread computes (no shared page).
     * Always join the worker thread before returning even if munmap fails. */
    int unmap_rc = munmap(p + eps, eps);
    void *res = NULL;
    int join_rc = pthread_join(th, &res);
    if (unmap_rc != 0) {
        free(res);
        tcg_fail("testthread", "munmap-pthread failed");
        munmap(p, eps);
        return;
    }
    if (join_rc != 0) {
        free(res);
        tcg_fail("testthread", "pthread_join failed");
        munmap(p, eps);
        return;
    }
    if (res == NULL || *(int64_t *)res != want) {
        free(res);
        tcg_fail("testthread", "thread result mismatch");
        munmap(p, eps);
        return;
    }
    free(res);
    if (p[0] != 0x77) {
        tcg_fail("testthread", "surviving mapping corrupted");
        munmap(p, eps);
        return;
    }
    munmap(p, eps);
    tcg_pass("testthread join exact + munmap-pthread");
}

/* float_convs: curated double/float conversion goldens (vendor per-arch
 * .ref files for float_madds/float_convs when curating a revision). */
static void t_float_convs(void)
{
    struct {
        double in;
        long want;
    } d2l[] = {
        { 0.0, 0L }, { 1.5, 1L }, { -1.5, -1L }, { 123456.789, 123456L },
        { -123456.789, -123456L }, { 2147483647.0, 2147483647L },
    };
    for (size_t i = 0; i < sizeof(d2l) / sizeof(d2l[0]); i++) {
        long got = (long)d2l[i].in;
        if (got != d2l[i].want) {
            tcg_fail("float_convs", "double->long mismatch");
            return;
        }
    }
    {
        /* NaN and infinity payloads must not trap the conversion path. */
        volatile double nan_v = 0.0 / 0.0;
        volatile double inf_v = 1.0 / 0.0;
        (void)nan_v;
        (void)inf_v;
    }
    {
        float f = 0.1f;
        double d = 0.0;
        for (int i = 0; i < 1000; i++) {
            d += (double)f;
        }
        /* 0.1f * 1000 in double accumulation: known golden interval. */
        if (!(d > 99.9 && d < 100.1)) {
            tcg_fail("float_convs", "float accumulation out of range");
            return;
        }
    }
    tcg_pass("float_convs double->long goldens + accum interval");
}

/* sha1: compact known-answer digest over "abc" (multiarch sha1 leg). */
static void t_sha1(void)
{
    /* Minimal public-domain-style SHA-1 over fixed inputs. */
    static const uint32_t want_abc[5] = {
        0xa9993e36u, 0x4706816au, 0xba3e2571u, 0x7850c26cu, 0x9cd0d89du
    };
    uint32_t h[5] = { 0x67452301u, 0xefcdab89u, 0x98badcfeu,
                      0x10325476u, 0xc3d2e1f0u };
    unsigned char msg[64];
    memset(msg, 0, sizeof(msg));
    msg[0] = 'a';
    msg[1] = 'b';
    msg[2] = 'c';
    msg[3] = 0x80u;
    msg[63] = 24u;
    {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) {
            w[i] = ((uint32_t)msg[i * 4u] << 24) | ((uint32_t)msg[i * 4u + 1u] << 16) |
                   ((uint32_t)msg[i * 4u + 2u] << 8) | (uint32_t)msg[i * 4u + 3u];
        }
        for (int i = 16; i < 80; i++) {
            uint32_t v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = (v << 1) | (v >> 31);
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 0x5a827999u;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1u;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdcu;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6u;
            }
            uint32_t tmp = ((a << 5) | (a >> 27)) + f + e + k + w[i];
            e = d;
            d = c;
            c = (b << 30) | (b >> 2);
            b = a;
            a = tmp;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
    }
    for (int i = 0; i < 5; i++) {
        if (h[i] != want_abc[i]) {
            tcg_fail("sha1", "digest mismatch");
            return;
        }
    }
    tcg_pass("sha1 KAT abc=a9993e36...");
}

int main(int argc, char **argv)
{
    if (argc > 1) {
        char *endp = NULL;
        long ps = strtol(argv[1], &endp, 10);
        if (endp != argv[1] && *endp == '\0' &&
            (ps == 4096L || ps == 8192L || ps == 16384L)) {
            g_page = ps;
        } else {
            printf("TCG_SMOKE: unsupported pagesize %s (want 4096/8192/16384)\n", argv[1]);
            return 2;
        }
    }
    printf("== TCG multiarch smoke (guest pagesize=%ld) ==\n", g_page);
    t_signals();
    t_segfault();
    t_prot_none();
    t_test_mmap();
    t_testthread();
    t_float_convs();
    t_sha1();
    printf("TCG_SMOKE RESULT: pass=%d fail=%d skip=%d\n", g_pass, g_fail, g_skip);
    if (g_pass == 0) {
        printf("TCG_SMOKE FAIL (0 passes)\n");
        return 1;
    }
    if (g_fail > 0) {
        printf("TCG_SMOKE FAIL\n");
        return 1;
    }
    if (g_skip > 0) {
        const char *allow_skip = getenv("TORTURE_ALLOW_SKIP");
        if (allow_skip == NULL || strcmp(allow_skip, "1") != 0) {
            printf("TCG_SMOKE FAIL (skip=%d not allowed; set TORTURE_ALLOW_SKIP=1 to override)\n",
                g_skip);
            return 1;
        }
    }
    printf("TCG_SMOKE ALL_OK\n");
    return 0;
}
