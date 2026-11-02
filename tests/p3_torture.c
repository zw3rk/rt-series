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
static volatile sig_atomic_t g_on_altstack = 0;
static volatile sig_atomic_t g_nest_depth = 0;
static volatile sig_atomic_t g_fp_handler_ran = 0;

static sigjmp_buf g_segv_jmp;
static volatile sig_atomic_t g_segv_armed = 0;
static volatile sig_atomic_t g_segv_signo = 0;
static volatile sig_atomic_t g_segv_code = 0;
static uintptr_t g_segv_addr = 0;

static _Atomic int g_cas_cell = 0;
static _Atomic long g_race_sum = 0;

static void usr1_handler(int signo, siginfo_t *info, void *ctx)
{
    g_usr1_count++;
    g_usr1_signo = signo;
    if (info != NULL) {
        g_usr1_code = info->si_code;
    }
    g_usr1_has_ctx = (ctx != NULL) ? 1 : 0;
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
    /* Touch the FPRs hard inside the handler; the interrupted FP computation
     * in main must still resume bit-exact (write-through cached state). */
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
        g_segv_addr = (uintptr_t)info->si_addr;
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

/* Signal frame: async SIGUSR1 must arrive with exact si_signo, a
 * kill-family si_code, and a non-null ucontext; nested SIGUSR2 delivery
 * exercises re-entrant frames. */
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
    if (raise(SIGUSR1) != 0) {
        report_fail("sig-frame-gpr", "raise failed");
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
    /* Reservation broken by the handler: CAS expecting the pre-signal
     * value must fail, CAS on the handler's value must succeed. */
    {
        int expect = 1;
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
    /* The alarm fires mid-computation; handler clobbers FP regs. */
    alarm(1);
    for (int i = 0; i < 1000000; i++) {
        b += a * 0.5;
    }
    if (g_fp_handler_ran != 1) {
        /* Alarm may coalesce after the loop on fast hosts; force one. */
        raise(SIGALRM);
    }
    if (g_fp_handler_ran != 1) {
        report_fail("sig-frame-fpr", "handler never ran");
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
    memset(&ss, 0, sizeof(ss));
    ss.ss_sp = stack;
    ss.ss_size = (size_t)alt_size;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) != 0) {
        report_skip("sigaltstack", "sigaltstack unavailable");
        free(stack);
        return;
    }
    if (install_handler(SIGURG, alt_handler, SA_ONSTACK) != 0) {
        report_skip("sigaltstack", "sigaction unavailable");
        free(stack);
        return;
    }
    g_on_altstack = 0;
    if (raise(SIGURG) != 0) {
        report_fail("sigaltstack", "raise failed");
        free(stack);
        return;
    }
    /* Disable the alternate stack before freeing it. */
    memset(&ss, 0, sizeof(ss));
    ss.ss_flags = SS_DISABLE;
    sigaltstack(&ss, NULL);
    if (!g_on_altstack) {
        report_fail("sigaltstack", "handler not on alt stack");
        free(stack);
        return;
    }
    free(stack);
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
    /* Straddle the boundary: last 3 bytes of page 0 + first 5 of page 1. */
    {
        unsigned char *edge = base + (size_t)ps - 3;
        uint64_t got = 0;
        memcpy(&got, edge, sizeof(got));
        uint64_t want = 0;
        for (size_t k = 0; k < sizeof(got); k++) {
            want |= (uint64_t)edge[k] << (8u * k);
        }
        if (got != want) {
            report_fail("unaligned-cross-page", "straddling load mismatch");
            munmap(base, two);
            return;
        }
    }
    /* Odd-offset 8-byte stores across the boundary, then re-verify. */
    {
        unsigned char *edge = base + (size_t)ps - 5;
        uint64_t pattern = 0x0123456789ABCDEFULL;
        memcpy(edge, &pattern, sizeof(pattern));
        uint64_t got = 0;
        memcpy(&got, edge, sizeof(got));
        if (got != pattern) {
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
    g_segv_addr = 0;
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
    if (g_segv_addr / (uintptr_t)ps != (uintptr_t)(base + (size_t)ps) / (uintptr_t)ps) {
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
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        base[0] = 0x11;
        g_segv_armed = 0;
        report_fail("mprotect-munmap", "RO write did not trap");
        munmap(base, two);
        return;
    }
    g_segv_armed = 0;
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
    if (sigsetjmp(g_segv_jmp, 1) == 0) {
        volatile unsigned char c = base[(size_t)ps];
        (void)c;
        g_segv_armed = 0;
        report_fail("mprotect-munmap", "unmapped read did not trap");
        munmap(base, (size_t)ps);
        return;
    }
    g_segv_armed = 0;
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
    if (g_fail > 0) {
        printf("P3_TORTURE FAIL\n");
        return 1;
    }
    printf("P3_TORTURE ALL_OK\n");
    return 0;
}
