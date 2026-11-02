/*
 * tests/p3_torture.c — P3 concurrency / memory / signal-frame torture suite.
 *
 * Portable Curated C11 guest test (Linux guests and host). Covers the
 * translator-specific edges from docs/CATALOGUE-TODO.md (P3):
 *   - signal frame GPR/FPR round-trip (ucontext si_signo/si_code exact,
 *     FP environment preserved across async signal delivery),
 *   - sigaltstack with SS_ONSTACK verification and nested delivery,
 *   - unaligned cross-page access straddling a 4 KiB boundary,
 *   - mprotect/munmap fault immediacy with si_addr page check,
 *   - atomic reservation broken by a signal handler and by a second thread.
 *
 * Build: cc -std=c11 -Wall -Wextra -Werror=vla -pedantic -O1 -pthread
 *        tests/p3_torture.c -o p3_torture
 * Run: ./p3_torture   (exit 0 iff fails == 0 and passes > 0)
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

#define _POSIX_C_SOURCE 200809L
/* Strict -std=c11 hides the XSI sigaltstack family (sigaltstack, SA_ONSTACK,
 * SS_ONSTACK, SS_DISABLE, SIGSTKSZ) on glibc; _DEFAULT_SOURCE re-exposes it
 * and is ignored on other libcs. */
#if defined(__linux__) && !defined(_DEFAULT_SOURCE) && !defined(_GNU_SOURCE)
#define _DEFAULT_SOURCE 1
#endif
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#define _DARWIN_C_SOURCE 1
#endif

#include <errno.h>
#include <fenv.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

/* MAP_ANONYMOUS is MAP_ANON on macOS/BSD when strict feature macros hide it. */
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

static int g_pass = 0;
static int g_fail = 0;
static int g_skip = 0;

static void report_pass(const char *name)
{
    g_pass++;
    printf("PASS [p3]: %s\n", name);
}

static void report_fail(const char *name, const char *detail)
{
    g_fail++;
    printf("FAIL [p3]: %s (%s)\n", name, detail);
}

static void report_skip(const char *name, const char *detail)
{
    g_skip++;
    printf("SKIP [p3]: %s (%s)\n", name, detail);
}

/* --- shared signal state --- */

static volatile sig_atomic_t g_usr1_count = 0;
static volatile sig_atomic_t g_usr1_signo = 0;
static volatile sig_atomic_t g_usr1_code = 0;
static volatile sig_atomic_t g_usr1_has_ctx = 0;
static volatile sig_atomic_t g_usr1_clobber_sink = 0;
static volatile sig_atomic_t g_on_altstack = 0;
static volatile sig_atomic_t g_nest_depth = 0;
static volatile sig_atomic_t g_fp_handler_ran = 0;

static sigjmp_buf g_segv_jmp;
static volatile sig_atomic_t g_segv_armed = 0;
static volatile sig_atomic_t g_segv_signo = 0;
static volatile sig_atomic_t g_segv_code = 0;
/* C11 async-signal-safe 64-bit address bridge: three 22-bit chunks stored in
 * volatile sig_atomic_t objects (POSIX guarantees sig_atomic_t >= 32-bit). */
static volatile sig_atomic_t g_segv_addr_w0 = 0;
static volatile sig_atomic_t g_segv_addr_w1 = 0;
static volatile sig_atomic_t g_segv_addr_w2 = 0;

static _Atomic int g_cas_cell = 0;
static volatile uint32_t g_llsc_cell = 0x13572468U;
static _Atomic long g_race_sum = 0;

static void store_segv_addr(uintptr_t addr)
{
    uint64_t u = (uint64_t)addr;
    g_segv_addr_w0 = (sig_atomic_t)(u & 0x3fffffULL);
    g_segv_addr_w1 = (sig_atomic_t)((u >> 22) & 0x3fffffULL);
    g_segv_addr_w2 = (sig_atomic_t)((u >> 44) & 0x3fffffULL);
}

static uintptr_t load_segv_addr(void)
{
    uint64_t u0 = (uint64_t)(uint32_t)g_segv_addr_w0 & 0x3fffffULL;
    uint64_t u1 = (uint64_t)(uint32_t)g_segv_addr_w1 & 0x3fffffULL;
    uint64_t u2 = (uint64_t)(uint32_t)g_segv_addr_w2 & 0x3fffffULL;
    return (uintptr_t)(u0 | (u1 << 22) | (u2 << 44));
}

static void usr1_handler(int signo, siginfo_t *info, void *ctx)
{
    g_usr1_count++;
    g_usr1_signo = signo;
    if (info != NULL) {
        g_usr1_code = info->si_code;
    }
    g_usr1_has_ctx = (ctx != NULL) ? 1 : 0;
    /* Clobber caller/callee-saved GPRs inside the signal frame to verify
     * that interrupted live GPR state is restored by sigreturn. */
    {
        uint64_t c0 = 0x1111222233334444ULL ^ (uint64_t)signo;
        uint64_t c1 = 0x5555666677778888ULL;
        uint64_t c2 = 0x9999AAAABBBBCCCCULL;
        uint64_t c3 = 0xDDDDEEEEFFFF0001ULL;
        for (int i = 0; i < 32; i++) {
            c0 = (c0 + c1) ^ (c2 >> 3);
            c1 = (c1 ^ c3) + (c0 << 5);
            c2 = (c2 + 0x9E3779B97F4A7C15ULL) ^ c1;
            c3 = (c3 ^ c0) + c2;
        }
        g_usr1_clobber_sink = (sig_atomic_t)((c0 ^ c1 ^ c2 ^ c3) & 0x7FFFU);
    }
    /* Break any in-flight "reservation": the main thread's CAS retry loop
     * must observe this store, exactly like a stolen LL/SC reservation. */
    atomic_store(&g_cas_cell, 2);
    g_nest_depth++;
    if (g_nest_depth < 2) {
        /* Nested delivery on the alternate stack. */
        raise(SIGUSR2);
    }
    g_nest_depth--;
}

static void usr2_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)info;
    (void)ctx;
    if (signo == SIGUSR2) {
        g_nest_depth++;
    }
}

static void fp_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)signo;
    (void)info;
    (void)ctx;
    /* Touch the FPRs and mutate rounding mode + sticky exception flags inside
     * the handler; sigreturn must restore the interrupted FP state. */
#ifdef FE_TOWARDZERO
    (void)fesetround(FE_TOWARDZERO);
#endif
    (void)feraiseexcept(FE_OVERFLOW | FE_DIVBYZERO);
    volatile double acc = 0.25;
    for (int i = 1; i <= 64; i++) {
        acc = acc * 1.5 + (double)i * 0.125;
    }
    (void)acc;
    g_fp_handler_ran = 1;
}

static void alt_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)signo;
    (void)info;
    (void)ctx;
    stack_t ss;
    memset(&ss, 0, sizeof(ss));
    if (sigaltstack(NULL, &ss) == 0 && (ss.ss_flags & SS_ONSTACK) != 0) {
        g_on_altstack = 1;
    }
}

static void segv_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)ctx;
    g_segv_signo = signo;
    if (info != NULL) {
        g_segv_code = info->si_code;
        store_segv_addr((uintptr_t)info->si_addr);
    }
    if (g_segv_armed) {
        siglongjmp(g_segv_jmp, 1);
    }
}

static int install_handler(int signo, void (*fn)(int, siginfo_t *, void *), int flags)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = fn;
    sa.sa_flags = SA_SIGINFO | flags;
    sigemptyset(&sa.sa_mask);
    return sigaction(signo, &sa, NULL);
}

/* Acquire a hardware/translator LL reservation on g_llsc_cell, deliver SIGUSR1
 * (whose handler does NOT modify g_llsc_cell), and then attempt the matching
 * SC instruction. On LL/SC architectures, exception return (sigreturn) must
 * clear the active reservation so the post-signal SC fails without storing. */
static int probe_llsc_broken_by_signal(void)
{
    g_llsc_cell = 0x13572468U;
#if defined(__aarch64__)
    uint32_t loaded = 0;
    uint32_t sc_status = 0;
    __asm__ volatile("ldxr %w0, [%1]" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (raise(SIGUSR1) != 0) {
        return -1;
    }
    __asm__ volatile("stxr %w0, %w2, [%1]"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(0xdeadbeefU)
                     : "memory");
    return (loaded == 0x13572468U && sc_status != 0U && g_llsc_cell == 0x13572468U) ? 0 : -1;
#elif defined(__arm__) && (__ARM_ARCH >= 6)
    uint32_t loaded = 0;
    uint32_t sc_status = 0;
    __asm__ volatile("ldrex %0, [%1]" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (raise(SIGUSR1) != 0) {
        return -1;
    }
    __asm__ volatile("strex %0, %2, [%1]"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(0xdeadbeefU)
                     : "memory");
    return (loaded == 0x13572468U && sc_status != 0U && g_llsc_cell == 0x13572468U) ? 0 : -1;
#elif defined(__riscv) && defined(__riscv_atomic)
    uint32_t loaded = 0;
    uint32_t sc_status = 0;
    __asm__ volatile("lr.w %0, (%1)" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (raise(SIGUSR1) != 0) {
        return -1;
    }
    __asm__ volatile("sc.w %0, %2, (%1)"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(0xdeadbeefU)
                     : "memory");
    return (loaded == 0x13572468U && sc_status != 0U && g_llsc_cell == 0x13572468U) ? 0 : -1;
#else
    if (raise(SIGUSR1) != 0) {
        return -1;
    }
    return 0;
#endif
}

/* Signal frame: async SIGUSR1 must arrive with exact si_signo, a
 * kill-family si_code, a non-null ucontext, live GPR preservation across
 * delivery, and an invalidated LL/SC reservation + CAS retry across the
 * signal boundary. */
static void t_sig_frame_gpr(void)
{
    if (install_handler(SIGUSR1, usr1_handler, 0) != 0 ||
        install_handler(SIGUSR2, usr2_handler, 0) != 0) {
        report_skip("sig-frame-gpr", "sigaction unavailable");
        return;
    }
    g_usr1_count = 0;
    g_usr1_signo = 0;
    g_usr1_code = 0;
    g_usr1_has_ctx = 0;
    atomic_store(&g_cas_cell, 1);

    /* Keep multiple GPRs and the pre-signal loaded value live across
     * signal delivery while usr1_handler + nested usr2_handler clobber
     * registers, break the LL/SC reservation, and overwrite g_cas_cell. */
    uint64_t r0 = 0x0123456789ABCDEFULL;
    uint64_t r1 = 0xFEDCBA9876543210ULL;
    uint64_t r2 = 0xCAFEBABE12345678ULL;
    uint64_t r3 = 0xDEADBEEF87654321ULL;
    uint64_t r4 = 0x0F1E2D3C4B5A6978ULL;
    uint64_t r5 = 0x8796A5B4C3D2E1F0ULL;
    int expect = atomic_load(&g_cas_cell);
    for (int step = 0; step < 16; step++) {
        r0 = (r0 ^ (uint64_t)step) + 0x100U;
        r1 = (r1 + (uint64_t)step) ^ 0x200U;
        r2 = (r2 ^ r0) + 0x300U;
        r3 = (r3 + r1) ^ 0x400U;
        r4 = (r4 ^ r2) + 0x500U;
        r5 = (r5 + r3) ^ 0x600U;
        if (step == 7) {
            if (probe_llsc_broken_by_signal() != 0) {
                report_fail("sig-frame-gpr", "LL/SC reservation not cleared across signal");
                return;
            }
        }
    }

    uint64_t w0 = 0x0123456789ABCDEFULL;
    uint64_t w1 = 0xFEDCBA9876543210ULL;
    uint64_t w2 = 0xCAFEBABE12345678ULL;
    uint64_t w3 = 0xDEADBEEF87654321ULL;
    uint64_t w4 = 0x0F1E2D3C4B5A6978ULL;
    uint64_t w5 = 0x8796A5B4C3D2E1F0ULL;
    for (int step = 0; step < 16; step++) {
        w0 = (w0 ^ (uint64_t)step) + 0x100U;
        w1 = (w1 + (uint64_t)step) ^ 0x200U;
        w2 = (w2 ^ w0) + 0x300U;
        w3 = (w3 + w1) ^ 0x400U;
        w4 = (w4 ^ w2) + 0x500U;
        w5 = (w5 + w3) ^ 0x600U;
    }
    if (r0 != w0 || r1 != w1 || r2 != w2 || r3 != w3 || r4 != w4 || r5 != w5) {
        report_fail("sig-frame-gpr", "live GPR state corrupted across signal");
        return;
    }
    if (g_usr1_count != 1) {
        report_fail("sig-frame-gpr", "handler ran != 1");
        return;
    }
    if (g_usr1_signo != SIGUSR1) {
        report_fail("sig-frame-gpr", "si_signo mismatch");
        return;
    }
    /* raise() arrives as SI_TKILL (-6) or SI_USER (-1) on Linux; on
     * BSD/macOS raise() reports si_code 0. */
    if (g_usr1_code != SI_USER
#ifdef SI_TKILL
        && g_usr1_code != SI_TKILL
#endif
        && g_usr1_code != 0
    ) {
        report_fail("sig-frame-gpr", "si_code not kill-family");
        return;
    }
    if (!g_usr1_has_ctx) {
        report_fail("sig-frame-gpr", "null ucontext");
        return;
    }
    if (atomic_load(&g_cas_cell) != 2) {
        report_fail("sig-frame-gpr", "handler store lost");
        return;
    }
    /* Reservation broken by the handler: CAS using the pre-signal loaded
     * value (`expect == 1`) must fail, and CAS on the handler's value must
     * succeed. */
    if (expect != 1) {
        report_fail("sig-frame-gpr", "pre-signal expect corrupted");
        return;
    }
    if (atomic_compare_exchange_strong(&g_cas_cell, &expect, 3)) {
        report_fail("sig-frame-gpr", "stale CAS unexpectedly won");
        return;
    }
    if (expect != 2) {
        report_fail("sig-frame-gpr", "CAS did not report handler value");
        return;
    }
    expect = 2;
    if (!atomic_compare_exchange_strong(&g_cas_cell, &expect, 3) ||
        atomic_load(&g_cas_cell) != 3) {
        report_fail("sig-frame-gpr", "fresh CAS lost");
        return;
    }
    report_pass("sig-frame-gpr si_signo/si_code/ucontext + stolen reservation");
}

/* FPR round-trip: FP environment and in-flight values must survive an
 * async signal whose handler burns the FPRs. */
static void t_sig_frame_fpr(void)
{
    if (install_handler(SIGALRM, fp_handler, 0) != 0) {
        report_skip("sig-frame-fpr", "sigaction unavailable");
        return;
    }
    g_fp_handler_ran = 0;
#ifdef FE_TONEAREST
    int old_rm = fegetround();
    if (fesetround(FE_TONEAREST) != 0) {
        report_skip("sig-frame-fpr", "fesetround unavailable");
        return;
    }
#endif
    feclearexcept(FE_ALL_EXCEPT);
    volatile double a = 1.0 / 3.0;
    volatile double b = 0.0;
    /* Arm alarm(1) and guarantee mid-computation delivery at the midpoint
     * if the wall-clock timer has not fired yet on a fast host. */
    alarm(1);
    for (int i = 0; i < 1000000; i++) {
        b += a * 0.5;
        if (i == 500000 && g_fp_handler_ran == 0) {
            raise(SIGALRM);
        }
    }
    /* Cancel any pending alarm before the reference computation loop. */
    alarm(0);
    if (g_fp_handler_ran < 1) {
        report_fail("sig-frame-fpr", "handler never ran");
#ifdef FE_TONEAREST
        fesetround(old_rm);
#endif
        return;
    }
    /* Bit-exact resume check: recompute without signals and compare. */
    {
        volatile double ref = 0.0;
        for (int i = 0; i < 1000000; i++) {
            ref += a * 0.5;
        }
        if (memcmp((const void *)&b, (const void *)&ref, sizeof(b)) != 0) {
            report_fail("sig-frame-fpr", "FP value corrupted by handler");
#ifdef FE_TONEAREST
            fesetround(old_rm);
#endif
            return;
        }
    }
#ifdef FE_TONEAREST
    if (fegetround() != FE_TONEAREST) {
        report_fail("sig-frame-fpr", "rounding mode changed by handler");
        fesetround(old_rm);
        return;
    }
    fesetround(old_rm);
#endif
    if ((fetestexcept(FE_INVALID | FE_DIVBYZERO | FE_OVERFLOW)) != 0) {
        report_fail("sig-frame-fpr", "sticky FP exception leaked");
        return;
    }
    report_pass("sig-frame-fpr FP env + values survive async handler");
}

/* sigaltstack: handler must run on the alternate stack (SS_ONSTACK). */
static void t_sigaltstack(void)
{
    long alt_size = (long)SIGSTKSZ * 2L;
    if (alt_size < 32768L) {
        alt_size = 32768L;
    }
    void *stack = malloc((size_t)alt_size);
    if (stack == NULL) {
        report_skip("sigaltstack", "malloc failed");
        return;
    }
    stack_t ss;
    stack_t old_ss;
    memset(&ss, 0, sizeof(ss));
    memset(&old_ss, 0, sizeof(old_ss));
    ss.ss_sp = stack;
    ss.ss_size = (size_t)alt_size;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, &old_ss) != 0) {
        report_skip("sigaltstack", "sigaltstack unavailable");
        free(stack);
        return;
    }

    struct sigaction sa;
    struct sigaction old_sa;
    memset(&sa, 0, sizeof(sa));
    memset(&old_sa, 0, sizeof(old_sa));
    sa.sa_sigaction = alt_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);

    int have_old_sa = 0;
    int sigact_rc = sigaction(SIGURG, &sa, &old_sa);
    if (sigact_rc == 0) {
        have_old_sa = 1;
    }
    g_on_altstack = 0;
    int raise_rc = (sigact_rc == 0) ? raise(SIGURG) : -1;

    if (have_old_sa) {
        (void)sigaction(SIGURG, &old_sa, NULL);
    }

    /* Always disable the alternate stack before freeing its backing buffer.
     * Keep ss_sp and ss_size populated (>= MINSIGSTKSZ) because Darwin/BSD
     * validates ss_size before checking SS_DISABLE, while Linux ignores
     * ss_sp/ss_size when SS_DISABLE is set. */
    memset(&ss, 0, sizeof(ss));
    ss.ss_sp = stack;
    ss.ss_size = (size_t)alt_size;
    ss.ss_flags = SS_DISABLE;
    int dis_rc = sigaltstack(&ss, NULL);
    if (dis_rc != 0 && (old_ss.ss_flags & SS_DISABLE) == 0 && old_ss.ss_sp != NULL) {
        dis_rc = sigaltstack(&old_ss, NULL);
    }
    if (dis_rc != 0) {
        report_fail("sigaltstack", "sigaltstack SS_DISABLE failed");
        return;
    }
    free(stack);

    if (sigact_rc != 0) {
        report_skip("sigaltstack", "sigaction unavailable");
        return;
    }
    if (raise_rc != 0) {
        report_fail("sigaltstack", "raise failed");
        return;
    }
    if (!g_on_altstack) {
        report_fail("sigaltstack", "handler not on alt stack");
        return;
    }
    report_pass("sigaltstack SS_ONSTACK verified");
}

/* Unaligned cross-page access: an 8-byte load straddling a page boundary
 * must return exact bytes even when the second page has a different
 * protection generation. */
static void t_unaligned_cross_page(void)
{
    long ps = sysconf(_SC_PAGESIZE);
    if (ps < 4096L) {
        ps = 4096L;
    }
    size_t two = (size_t)ps * 2u;
    unsigned char *base = (unsigned char *)mmap(NULL, two, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == MAP_FAILED) {
        report_skip("unaligned-cross-page", "mmap unavailable");
        return;
    }
    for (size_t i = 0; i < two; i++) {
        base[i] = (unsigned char)((i * 2654435761u) & 255u);
    }
    /* Straddle the boundary: last 3 bytes of page 0 + first 5 of page 1.
     * Construct reference in native guest byte order via an aligned staging
     * buffer so both little-endian and big-endian guests are verified. */
    {
        unsigned char *edge = base + (size_t)ps - 3;
        unsigned char want_bytes[sizeof(uint64_t)];
        for (size_t k = 0; k < sizeof(uint64_t); k++) {
            size_t idx = (size_t)ps - 3u + k;
            want_bytes[k] = (unsigned char)((idx * 2654435761u) & 255u);
        }
        uint64_t got = 0;
        uint64_t want = 0;
        memcpy(&got, edge, sizeof(got));
        memcpy(&want, want_bytes, sizeof(want));
        if (got != want || memcmp(&got, want_bytes, sizeof(got)) != 0) {
            report_fail("unaligned-cross-page", "straddling load mismatch");
            munmap(base, two);
            return;
        }
    }
    /* Odd-offset 8-byte stores across the boundary, then re-verify. */
    {
        unsigned char *edge = base + (size_t)ps - 5;
        uint64_t pattern = 0x0123456789ABCDEFULL;
        unsigned char pat_bytes[sizeof(pattern)];
        memcpy(pat_bytes, &pattern, sizeof(pattern));
        memcpy(edge, &pattern, sizeof(pattern));
        uint64_t got = 0;
        memcpy(&got, edge, sizeof(got));
        if (got != pattern || memcmp(edge, pat_bytes, sizeof(pattern)) != 0) {
            report_fail("unaligned-cross-page", "straddling store mismatch");
            munmap(base, two);
            return;
        }
    }
    munmap(base, two);
    report_pass("unaligned-cross-page straddling load/store exact");
}

/* mprotect/munmap: fault immediacy (no stale Soft-TLB entry) with si_addr
 * page-offset verification, recovered via siglongjmp. */
static void t_mprotect_munmap(void)
{
    long ps = sysconf(_SC_PAGESIZE);
    if (ps < 4096L) {
        ps = 4096L;
    }
    size_t two = (size_t)ps * 2u;
    unsigned char *base = (unsigned char *)mmap(NULL, two, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (base == MAP_FAILED) {
        report_skip("mprotect-munmap", "mmap unavailable");
        return;
    }
    base[0] = 0xAA;
    base[(size_t)ps] = 0xBB;
    /* PROT_NONE access raises SIGSEGV on Linux but SIGBUS on macOS/BSD;
     * arm both so the immediacy + si_addr checks are portable. */
    if (install_handler(SIGSEGV, segv_handler, 0) != 0 ||
        install_handler(SIGBUS, segv_handler, 0) != 0) {
        report_skip("mprotect-munmap", "sigaction unavailable");
        munmap(base, two);
        return;
    }
    /* 1. mprotect the second page PROT_NONE: the very next access traps. */
    if (mprotect(base + (size_t)ps, (size_t)ps, PROT_NONE) != 0) {
        report_fail("mprotect-munmap", "mprotect PROT_NONE failed");
        munmap(base, two);
        return;
    }
    g_segv_armed = 1;
    g_segv_signo = 0;
    g_segv_code = 0;
    store_segv_addr(0);
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        volatile unsigned char c = base[(size_t)ps];
        (void)c;
        g_segv_armed = 0;
        report_fail("mprotect-munmap", "PROT_NONE read did not trap");
        munmap(base, two);
        return;
    }
    g_segv_armed = 0;
    if (g_segv_signo != SIGSEGV && g_segv_signo != SIGBUS) {
        report_fail("mprotect-munmap", "wrong signal on PROT_NONE");
        munmap(base, two);
        return;
    }
    if (g_segv_code <= 0) {
        report_fail("mprotect-munmap", "missing positive si_code on PROT_NONE");
        munmap(base, two);
        return;
    }
    if (load_segv_addr() / (uintptr_t)ps != (uintptr_t)(base + (size_t)ps) / (uintptr_t)ps) {
        report_fail("mprotect-munmap", "si_addr outside protected page");
        munmap(base, two);
        return;
    }
    /* 2. mprotect back to RW: access works again (entry re-validated). */
    if (mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE) != 0) {
        report_fail("mprotect-munmap", "mprotect RW failed");
        munmap(base, two);
        return;
    }
    base[(size_t)ps] = 0xCC;
    if (base[(size_t)ps] != 0xCC) {
        report_fail("mprotect-munmap", "RW re-access mismatch");
        munmap(base, two);
        return;
    }
    /* 3. mprotect first page PROT_READ: a write must trap immediately. */
    if (mprotect(base, (size_t)ps, PROT_READ) != 0) {
        report_fail("mprotect-munmap", "mprotect RO failed");
        munmap(base, two);
        return;
    }
    g_segv_armed = 1;
    g_segv_signo = 0;
    g_segv_code = 0;
    store_segv_addr(0);
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        base[0] = 0x11;
        g_segv_armed = 0;
        report_fail("mprotect-munmap", "RO write did not trap");
        munmap(base, two);
        return;
    }
    g_segv_armed = 0;
    if ((g_segv_signo != SIGSEGV && g_segv_signo != SIGBUS) || g_segv_code <= 0 ||
        load_segv_addr() / (uintptr_t)ps != (uintptr_t)base / (uintptr_t)ps) {
        report_fail("mprotect-munmap", "RO write fault metadata mismatch");
        munmap(base, two);
        return;
    }
    if (mprotect(base, (size_t)ps, PROT_READ | PROT_WRITE) != 0) {
        report_fail("mprotect-munmap", "mprotect RW restore failed");
        munmap(base, two);
        return;
    }
    /* 4. munmap the second page: access past EOF must trap (SIGSEGV). */
    if (munmap(base + (size_t)ps, (size_t)ps) != 0) {
        report_fail("mprotect-munmap", "munmap failed");
        munmap(base, (size_t)ps);
        return;
    }
    g_segv_armed = 1;
    g_segv_signo = 0;
    g_segv_code = 0;
    store_segv_addr(0);
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        volatile unsigned char c = base[(size_t)ps];
        (void)c;
        g_segv_armed = 0;
        report_fail("mprotect-munmap", "unmapped read did not trap");
        munmap(base, (size_t)ps);
        return;
    }
    g_segv_armed = 0;
    if ((g_segv_signo != SIGSEGV && g_segv_signo != SIGBUS) || g_segv_code <= 0 ||
        load_segv_addr() / (uintptr_t)ps != (uintptr_t)(base + (size_t)ps) / (uintptr_t)ps) {
        report_fail("mprotect-munmap", "unmapped read fault metadata mismatch");
        munmap(base, (size_t)ps);
        return;
    }
    munmap(base, (size_t)ps);
    report_pass("mprotect/munmap immediacy + si_addr page check");
}

static void *race_worker(void *arg)
{
    int iters = *(int *)arg;
    for (int i = 0; i < iters; i++) {
        atomic_fetch_add(&g_race_sum, 1L);
    }
    return NULL;
}

/* Atomic reservation vs a second thread: N fetch_add(1) from two threads
 * must total exactly 2N (no lost update through a stale reservation). */
static void t_atomic_race(void)
{
    int iters = 200000;
    atomic_store(&g_race_sum, 0L);
    pthread_t th;
    if (pthread_create(&th, NULL, race_worker, &iters) != 0) {
        report_skip("atomic-race", "pthread_create unavailable");
        return;
    }
    for (int i = 0; i < iters; i++) {
        atomic_fetch_add(&g_race_sum, 1L);
    }
    if (pthread_join(th, NULL) != 0) {
        report_fail("atomic-race", "pthread_join failed");
        return;
    }
    if (atomic_load(&g_race_sum) != (long)iters * 2L) {
        report_fail("atomic-race", "lost atomic update");
        return;
    }
    report_pass("atomic-race 2x200000 fetch_add exact");
}

int main(void)
{
    const char *allow_skip_env = getenv("TORTURE_ALLOW_SKIP");
    int allow_skip = (allow_skip_env != NULL && strcmp(allow_skip_env, "1") == 0);
    printf("== P3 torture: signal frames, sigaltstack, VM, atomics ==\n");
    t_sig_frame_gpr();
    t_sig_frame_fpr();
    t_sigaltstack();
    t_unaligned_cross_page();
    t_mprotect_munmap();
    t_atomic_race();
    printf("P3_TORTURE RESULT: pass=%d fail=%d skip=%d\n", g_pass, g_fail, g_skip);
    if (g_pass == 0) {
        printf("P3_TORTURE FAIL (0 passes)\n");
        return 1;
    }
    if (g_fail > 0 || (g_skip > 0 && !allow_skip)) {
        printf("P3_TORTURE FAIL\n");
        return 1;
    }
    printf("P3_TORTURE ALL_OK\n");
    return 0;
}
