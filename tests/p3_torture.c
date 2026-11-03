/*
 * tests/p3_torture.c — P3 concurrency / memory / signal-frame torture suite.
 * Note (RTS-R9-1): rt-series/tests/ hosts the shared cross-ISA P3 torture,
 * ABI-invariant, and benchmark reference suites; ISA-specific P1/P2/P4
 * suites live in each translator repository under tests/guest/.
 *
 * Build: cc -std=c11 -Wall -Wextra -Werror -Werror=vla -pedantic -O1 -pthread
 *        tests/p3_torture.c -o p3_torture
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */
#define _POSIX_C_SOURCE 200809L
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
#include <sys/wait.h>
#include <unistd.h>
#include "p3_llsc.h"
#include "sig_fault_addr.h"
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif
static int g_pass = 0, g_fail = 0, g_skip = 0;
static void report_pass(const char *name) { g_pass++; printf("PASS [p3]: %s\n", name); }
static void report_fail(const char *name, const char *d) { g_fail++; printf("FAIL [p3]: %s (%s)\n", name, d); }
static void report_skip(const char *name, const char *d) { g_skip++; printf("SKIP [p3]: %s (%s)\n", name, d); }
static volatile sig_atomic_t g_usr1_count = 0, g_usr1_signo = 0, g_usr1_code = 0;
static volatile sig_atomic_t g_usr1_has_ctx = 0, g_usr1_has_info = 0, g_usr1_info_signo = 0;
static volatile sig_atomic_t g_usr1_raise_rc = -1, g_usr1_on_altstack = 0, g_usr1_clobber_sink = 0;
static volatile sig_atomic_t g_usr2_count = 0, g_usr2_on_altstack = 0, g_usr2_saw_usr1_active = 0;
static char g_nest_stack[65536];
static volatile sig_atomic_t g_on_altstack = 0, g_nest_depth = 0, g_fp_handler_ran = 0;
static sigjmp_buf g_segv_jmp;
static volatile sig_atomic_t g_segv_armed = 0, g_segv_signo = 0, g_segv_code = 0;
/* Fault-address bridge; encode/decode lives in tests/sig_fault_addr.h. */
static struct sig_fault_addr_bridge g_segv_bridge = { 0, 0, 0 };
static _Atomic int g_cas_cell = 0;
static _Atomic long g_race_sum = 0;
static void store_segv_addr(uintptr_t addr)
{
    sig_fault_addr_store(&g_segv_bridge, addr);
}
static uintptr_t load_segv_addr(void)
{
    return sig_fault_addr_load(&g_segv_bridge);
}
static void usr1_handler(int signo, siginfo_t *info, void *ctx)
{
    stack_t ss;
    g_usr1_count++;
    g_usr1_signo = signo;
    if (info != NULL) {
        g_usr1_has_info = 1;
        g_usr1_info_signo = info->si_signo;
        g_usr1_code = info->si_code;
    }
    g_usr1_has_ctx = (ctx != NULL) ? 1 : 0;
    memset(&ss, 0, sizeof(ss));
    if (sigaltstack(NULL, &ss) == 0 && (ss.ss_flags & SS_ONSTACK) != 0) {
        g_usr1_on_altstack = 1;
    }
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
    /* Break any in-flight reservation like a stolen LL/SC reservation. */
    atomic_store(&g_cas_cell, 2);
    g_nest_depth++;
    if (g_nest_depth < 2) {
        g_usr1_raise_rc = (sig_atomic_t)raise(SIGUSR2);
    }
    g_nest_depth--;
}
static void usr2_handler(int signo, siginfo_t *info, void *ctx)
{
    stack_t ss;
    (void)info;
    (void)ctx;
    if (signo == SIGUSR2) {
        g_usr2_count++;
        if (g_nest_depth == 1) {
            g_usr2_saw_usr1_active = 1;
        }
        memset(&ss, 0, sizeof(ss));
        if (sigaltstack(NULL, &ss) == 0 && (ss.ss_flags & SS_ONSTACK) != 0) {
            g_usr2_on_altstack = 1;
        }
    }
}
static int drop_nest_stack(void)
{
    stack_t ss;
    memset(&ss, 0, sizeof(ss));
    ss.ss_sp = g_nest_stack;
    ss.ss_size = sizeof(g_nest_stack);
    ss.ss_flags = SS_DISABLE;
    return sigaltstack(&ss, NULL);
}
static void fp_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)signo;
    (void)info;
    (void)ctx;
    /* Burn FPRs/rounding in handler; sigreturn must restore FP state. */
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
/* LL/SC reservation vs SIGURG; vacuous pass where LL/SC is absent. */
static void t_llsc_reservation(void)
{
#if P3_HAVE_LLSC
    struct sigaction sa;
    struct sigaction old_sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = llsc_probe_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGURG, &sa, &old_sa) != 0) {
        report_skip("llsc-reservation", "sigaction unavailable");
        return;
    }
    if (probe_llsc_no_signal() != 0) {
        report_fail("llsc-control", "LL/SC without signal did not store");
    } else if (probe_llsc_broken_by_signal() != 0) {
        report_fail("llsc-signal-invalidate", "reservation not cleared across signal return");
    } else {
        report_pass("llsc-reservation control stores; signal return clears");
    }
    (void)sigaction(SIGURG, &old_sa, NULL);
#else
    report_pass("llsc-reservation no LL/SC on this arch (vacuous)");
#endif
}
/* SIGUSR1 frame: signo/si_signo/si_code/ucontext + nested SIGUSR2 on
 * altstack; 16-step GPR fold must survive delivery (value-level check). */
static void t_sig_frame_gpr(void)
{
    stack_t nest_ss;
    memset(&nest_ss, 0, sizeof(nest_ss));
    nest_ss.ss_sp = g_nest_stack;
    nest_ss.ss_size = sizeof(g_nest_stack);
    nest_ss.ss_flags = 0;
    if (sigaltstack(&nest_ss, NULL) != 0) {
        report_skip("sig-frame-gpr", "sigaltstack unavailable");
        return;
    }
    if (install_handler(SIGUSR1, usr1_handler, SA_ONSTACK) != 0 ||
        install_handler(SIGUSR2, usr2_handler, SA_ONSTACK) != 0) {
        report_skip("sig-frame-gpr", "sigaction unavailable");
        (void)drop_nest_stack();
        return;
    }
    g_usr1_count = 0;
    g_usr1_signo = 0;
    g_usr1_code = 0;
    g_usr1_has_ctx = 0;
    g_usr1_has_info = 0;
    g_usr1_info_signo = 0;
    g_usr1_raise_rc = -1;
    g_usr1_on_altstack = 0;
    g_usr2_count = 0;
    g_usr2_on_altstack = 0;
    g_usr2_saw_usr1_active = 0;
    atomic_store(&g_cas_cell, 1);
    /* Fold-check: sequence split around nested raise(); must match. */
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
            /* Async delivery mid-fold: the handler breaks the CAS cell
             * (stale-CAS check below) while GPR state must survive. */
            if (raise(SIGUSR1) != 0) {
                report_fail("sig-frame-gpr", "raise failed");
                (void)drop_nest_stack();
                return;
            }
        }
    }
    /* Handlers ran inside raise(); drop the stack first. */
    if (drop_nest_stack() != 0) {
        report_fail("sig-frame-gpr", "sigaltstack SS_DISABLE failed");
        return;
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
        report_fail("sig-frame-gpr", "handler signo mismatch");
        return;
    }
    if (!g_usr1_has_info) {
        report_fail("sig-frame-gpr", "missing siginfo");
        return;
    }
    if (g_usr1_info_signo != SIGUSR1) {
        report_fail("sig-frame-gpr", "si_signo mismatch");
        return;
    }
    /* raise(): SI_TKILL/SI_USER on Linux, si_code 0 on BSD/macOS. */
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
    if (g_usr1_raise_rc != 0 || g_usr2_count != 1) {
        report_fail("sig-frame-gpr", "nested SIGUSR2 delivery failed");
        return;
    }
    if (!g_usr2_saw_usr1_active) {
        report_fail("sig-frame-gpr", "nested handler did not run inside SIGUSR1");
        return;
    }
    if (!g_usr1_on_altstack) {
        report_fail("sig-frame-gpr", "SIGUSR1 handler not on alt stack");
        return;
    }
    if (!g_usr2_on_altstack) {
        report_fail("sig-frame-gpr", "nested SIGUSR2 handler not on alt stack");
        return;
    }
    if (atomic_load(&g_cas_cell) != 2) {
        report_fail("sig-frame-gpr", "handler store lost");
        return;
    }
    /* Stolen reservation: stale CAS must fail, fresh CAS must win. */
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
    report_pass("sig-frame-gpr si_signo/si_code/ucontext + nested altstack + stolen reservation");
}
/* FPR round-trip: FP env and in-flight values must survive handler. */
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
    /* Guarantee mid-computation delivery on fast hosts. */
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
    /* Bit-exact check via plain-double snapshots (no volatile memcmp). */
    {
        volatile double ref = 0.0;
        for (int i = 0; i < 1000000; i++) {
            ref += a * 0.5;
        }
        double b_snap = b;
        double ref_snap = ref;
        if (memcmp(&b_snap, &ref_snap, sizeof(b_snap)) != 0) {
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
    /* Soft-TLB generation check: protect the second page independently to
     * PROT_READ. A cross-page load spanning the boundary must still
     * succeed while a cross-page store spilling into the RO page must
     * fault (SIGSEGV/SIGBUS via sigsetjmp/siglongjmp). Then restore RW. */
    if (install_handler(SIGSEGV, segv_handler, 0) != 0 ||
        install_handler(SIGBUS, segv_handler, 0) != 0) {
        report_fail("unaligned-cross-page", "sigaction unavailable");
        munmap(base, two);
        return;
    }
    if (mprotect(base + (size_t)ps, (size_t)ps, PROT_READ) != 0) {
        report_fail("unaligned-cross-page", "mprotect RO failed");
        munmap(base, two);
        return;
    }
    {
        unsigned char *edge = base + (size_t)ps - 5;
        uint64_t got = 0;
        memcpy(&got, edge, sizeof(got));
        if (got != 0x0123456789ABCDEFULL) {
            report_fail("unaligned-cross-page", "RO cross-page load mismatch");
            mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE);
            munmap(base, two);
            return;
        }
    }
    {
        unsigned char pre_first[5];
        memcpy(pre_first, base + (size_t)ps - 5, sizeof(pre_first));
        g_segv_armed = 1;
        g_segv_signo = 0;
        g_segv_code = 0;
        store_segv_addr(0);
        if (sigsetjmp(g_segv_jmp, 1) == 0) {
            volatile unsigned char *vedge =
                (volatile unsigned char *)(base + (size_t)ps - 5);
            for (size_t k = 8u; k > 0u; k--) {
                vedge[k - 1u] = (unsigned char)(0xA0u + k);
            }
            atomic_signal_fence(memory_order_seq_cst);
            g_segv_armed = 0;
            report_fail("unaligned-cross-page", "RO cross-page store did not trap");
            mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE);
            munmap(base, two);
            return;
        }
        g_segv_armed = 0;
        if (g_segv_signo != SIGSEGV && g_segv_signo != SIGBUS) {
            report_fail("unaligned-cross-page", "wrong signal on RO cross-page store");
            mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE);
            munmap(base, two);
            return;
        }
        if (load_segv_addr() < (uintptr_t)(base + (size_t)ps) ||
            load_segv_addr() >= (uintptr_t)(base + two) ||
            memcmp(base + (size_t)ps - 5, pre_first, sizeof(pre_first)) != 0) {
            report_fail("unaligned-cross-page", "si_addr not on RO 2nd page or 1st page mutated");
            mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE);
            munmap(base, two);
            return;
        }
    }
    if (mprotect(base + (size_t)ps, (size_t)ps, PROT_READ | PROT_WRITE) != 0) {
        report_fail("unaligned-cross-page", "mprotect RW restore failed");
        munmap(base, two);
        return;
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
    /* Volatile probes so the compiler cannot optimize away any deliberate
     * faulting or post-restoration access. */
    volatile uint8_t *vbase = (volatile uint8_t *)base;
    volatile uint8_t *vsecond = (volatile uint8_t *)(base + (size_t)ps);
    vbase[0] = 0xAA;
    vsecond[0] = 0xBB;
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
        volatile uint8_t c = vsecond[0];
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
    vsecond[0] = 0xCC;
    {
        volatile uint8_t check = vsecond[0];
        if (check != 0xCC) {
            report_fail("mprotect-munmap", "RW re-access mismatch");
            munmap(base, two);
            return;
        }
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
        vbase[0] = 0x11;
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
        volatile uint8_t c = vsecond[0];
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
static void t_smc_clear_cache(void)
{
    long ps = sysconf(_SC_PAGESIZE); size_t sz; unsigned char *p; int (*fn)(void) = NULL; int r1, r2;
    uint32_t patch = 0; int patch_x86 = 0; int use_jit = 0; (void)use_jit;
    if (ps < 4096L) { ps = 4096L; } sz = (size_t)ps; p = (unsigned char *)mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) { report_skip("smc-clear-cache", "mmap unavailable"); return; }
    if (mprotect(p, sz, PROT_READ | PROT_EXEC) != 0) {
        if (errno != EACCES && errno != ENOTSUP) { report_fail("smc-clear-cache", "mprotect probe failed"); munmap(p, sz); return; }
#if defined(__APPLE__) && defined(MAP_JIT)
        munmap(p, sz); p = (unsigned char *)mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT, -1, 0);
        if (p == MAP_FAILED) { report_skip("smc-clear-cache", "MAP_JIT mmap failed"); return; }
        use_jit = 1;
#else
        report_skip("smc-clear-cache", "W^X mprotect denied"); munmap(p, sz); return;
#endif
    } else if (mprotect(p, sz, PROT_READ | PROT_WRITE) != 0) { report_fail("smc-clear-cache", "mprotect RW restore failed"); munmap(p, sz); return; }
#if defined(__APPLE__) && defined(MAP_JIT)
    if (use_jit) { pthread_jit_write_protect_np(0); }
#endif
#if defined(__aarch64__)
    { uint32_t w[2] = { 0x52800540U, 0xD65F03C0U }; memcpy(p, w, sizeof(w)); patch = 0x52800C60U; }
#elif defined(__x86_64__)
    { static const unsigned char c[6] = { 0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3 }; memcpy(p, c, sizeof(c)); patch_x86 = 1; }
#elif defined(__riscv)
    { uint32_t w[2] = { 0x02A00513U, 0x00008067U }; memcpy(p, w, sizeof(w)); patch = 0x06300513U; }
#elif defined(__mips__)
    { uint32_t w[3] = { 0x2402002AU, 0x03E00008U, 0x00000000U }; memcpy(p, w, sizeof(w)); patch = 0x24020063U; }
#elif defined(__powerpc__) || defined(__ppc__) || defined(__PPC__)
    { uint32_t w[2] = { 0x3860002AU, 0x4E800020U }; memcpy(p, w, sizeof(w)); patch = 0x38600063U; }
#elif defined(__sparc__)
    { uint32_t w[3] = { 0x9010202AU, 0x81C3E008U, 0x01000000U }; memcpy(p, w, sizeof(w)); patch = 0x90102063U; }
#elif defined(__loongarch__)
    { uint32_t w[2] = { 0x0280A804U, 0x4C000020U }; memcpy(p, w, sizeof(w)); patch = 0x02818C04U; }
#else
    report_skip("smc-clear-cache", "arch codegen unsupported"); munmap(p, sz); return;
#endif
    __builtin___clear_cache((char *)p, (char *)(p + 64));
#if defined(__APPLE__) && defined(MAP_JIT)
    if (use_jit) { pthread_jit_write_protect_np(1); } else
#endif
    if (mprotect(p, sz, PROT_READ | PROT_EXEC) != 0) { report_fail("smc-clear-cache", "mprotect RX seal failed"); munmap(p, sz); return; }
    memcpy(&fn, &p, sizeof(fn)); r1 = fn(); if (r1 != 42) { report_fail("smc-clear-cache", "first call != 42"); munmap(p, sz); return; }
#if defined(__APPLE__) && defined(MAP_JIT)
    if (use_jit) { pthread_jit_write_protect_np(0); } else
#endif
    if (mprotect(p, sz, PROT_READ | PROT_WRITE) != 0) { report_fail("smc-clear-cache", "mprotect RW failed"); munmap(p, sz); return; }
    if (patch_x86) { p[1] = 0x63; } else { memcpy(p, &patch, sizeof(patch)); }
    __builtin___clear_cache((char *)p, (char *)(p + 64));
#if defined(__APPLE__) && defined(MAP_JIT)
    if (use_jit) { pthread_jit_write_protect_np(1); } else
#endif
    if (mprotect(p, sz, PROT_READ | PROT_EXEC) != 0) { report_fail("smc-clear-cache", "mprotect RX reseal failed"); munmap(p, sz); return; }
    memcpy(&fn, &p, sizeof(fn)); r2 = fn();
    if (r2 != 99) { report_fail("smc-clear-cache", "rewritten call != 99"); munmap(p, sz); return; }
    munmap(p, sz); report_pass("smc-clear-cache RET 42->99 with icache clear");
}
static void t_vm_fork_cow(void)
{
    long ps = sysconf(_SC_PAGESIZE);
    if (ps < 4096L || ((unsigned long)ps & ((unsigned long)ps - 1UL)) != 0UL) {
        report_fail("vm-fork-cow", "AT_PAGESZ / _SC_PAGESIZE invalid"); return;
    }
    size_t two = (size_t)ps * 2u;
    volatile uint8_t *p = (volatile uint8_t *)mmap(NULL, two, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == (volatile uint8_t *)MAP_FAILED) { report_skip("vm-fork-cow", "mmap failed"); return; }
    p[0] = 0x42U; p[(size_t)ps] = 0x24U;
    pid_t pid = fork();
    if (pid < 0) { munmap((void *)p, two); report_skip("vm-fork-cow", "fork unavailable"); return; }
    if (pid == 0) {
        p[0] = 0x99U; p[(size_t)ps] = 0x88U;
        _exit((p[0] == 0x99U && p[(size_t)ps] == 0x88U) ? 0 : 1);
    }
    int st = 0;
    if (waitpid(pid, &st, 0) != pid || !WIFEXITED(st) || WEXITSTATUS(st) != 0 ||
        p[0] != 0x42U || p[(size_t)ps] != 0x24U) {
        munmap((void *)p, two); report_fail("vm-fork-cow", "COW isolation failed"); return;
    }
    munmap((void *)p, two);
    report_pass("vm-fork-cow private-COW isolation + page size check");
}

int main(void)
{
    const char *allow_skip_env = getenv("TORTURE_ALLOW_SKIP");
    int allow_skip = (allow_skip_env != NULL && strcmp(allow_skip_env, "1") == 0);
    printf("== P3 torture: signal frames, sigaltstack, VM, atomics ==\n");
    t_sig_frame_gpr();
    t_llsc_reservation();
    t_sig_frame_fpr();
    t_sigaltstack();
    t_unaligned_cross_page();
    t_mprotect_munmap();
    t_atomic_race();
    t_smc_clear_cache();
    t_vm_fork_cow();
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
