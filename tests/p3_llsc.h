/*
 * tests/p3_llsc.h — LL/SC reservation probe helpers for p3_torture.
 *
 * Defines P3_HAVE_LLSC for the LL/SC-capable guest/host arch list and,
 * only on those targets, provides g_llsc_cell, g_llsc_probe_seen, and the
 * four static helpers (llsc_probe_handler, llsc_pair, probe_llsc_no_signal,
 * probe_llsc_broken_by_signal). On non-LL/SC targets (i686, sparc32,
 * sparc64, x86_64, ...) the header defines nothing with linkage, so
 * tests/p3_torture.c compiles cleanly under -Wall -Wextra -Werror with
 * zero -Wunused-function / -Wunused-variable warnings.
 *
 * P3_FORCE_NO_LLSC (e.g. -DP3_FORCE_NO_LLSC) forces P3_HAVE_LLSC to 0 to
 * prove the non-LL/SC build path on any host.
 *
 * Curated C11, no VLAs, no banned string functions, no x18 use.
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef P3_LLSC_H
#define P3_LLSC_H

#include <signal.h>
#include <stdint.h>

#if !defined(P3_FORCE_NO_LLSC) && \
    (defined(__aarch64__) || defined(__arm__) || defined(__riscv) || \
     defined(__powerpc__) || defined(__powerpc64__) || defined(__mips__) || \
     defined(__loongarch64))
#define P3_HAVE_LLSC 1
#else
#define P3_HAVE_LLSC 0
#endif

#if P3_HAVE_LLSC

static volatile sig_atomic_t g_llsc_probe_seen = 0;
static volatile uint32_t g_llsc_cell = 0x13572468U;

/* Dedicated probe handler: counts its own signal only (no atomics, libc,
 * nesting, or clobbering), isolating the signal-return boundary. */
static void llsc_probe_handler(int signo, siginfo_t *info, void *ctx)
{
    (void)info;
    (void)ctx;
    if (signo == SIGURG) {
        g_llsc_probe_seen++;
    }
}

/* LL/SC pair shared by the control (do_signal == 0) and the interrupted
 * probe. Caller owns the SIGURG disposition. stored: 1 = stored new_val,
 * 0 = reservation lost. Returns -1 when the raise failed. */
static int llsc_pair(int do_signal, uint32_t new_val, uint32_t *loaded_out, int *stored_out)
{
    uint32_t loaded = 0;
    int stored = 0;
#if defined(__aarch64__)
    uint32_t sc_status = 0;
    __asm__ volatile("ldxr %w0, [%1]" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("stxr %w0, %w2, [%1]"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(new_val)
                     : "memory");
    stored = (sc_status == 0);
#elif defined(__arm__) && (__ARM_ARCH >= 6)
    uint32_t sc_status = 0;
    __asm__ volatile("ldrex %0, [%1]" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("strex %0, %2, [%1]"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(new_val)
                     : "memory");
    stored = (sc_status == 0);
#elif defined(__riscv) && defined(__riscv_atomic)
    uint32_t sc_status = 0;
    __asm__ volatile("lr.w %0, (%1)" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("sc.w %0, %2, (%1)"
                     : "=&r"(sc_status)
                     : "r"(&g_llsc_cell), "r"(new_val)
                     : "memory");
    stored = (sc_status == 0);
#elif defined(__mips__)
    uint32_t sc_word = new_val;
    __asm__ volatile("ll %0, 0(%1)" : "=r"(loaded) : "r"(&g_llsc_cell) : "memory");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("sc %0, 0(%1)"
                     : "+r"(sc_word)
                     : "r"(&g_llsc_cell)
                     : "memory");
    stored = (sc_word == 1U);
#elif defined(__powerpc__) || defined(__powerpc64__) || defined(__ppc__)
    /* stwcx. reports via CR0[EQ] (0x20000000 after mfcr). */
    uint32_t cr = 0;
    __asm__ volatile("lwarx %0, 0, %1"
                     : "=r"(loaded)
                     : "r"(&g_llsc_cell)
                     : "memory", "cc");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("stwcx. %2, 0, %1\n\tmfcr %0"
                     : "=r"(cr)
                     : "r"(&g_llsc_cell), "r"(new_val)
                     : "memory", "cc");
    stored = ((cr & 0x20000000U) != 0U);
#elif defined(__loongarch__) || defined(__loongarch64)
    uint32_t sc_word = new_val;
    __asm__ volatile("ll.w %0, %1, 0"
                     : "=r"(loaded)
                     : "r"(&g_llsc_cell)
                     : "memory");
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    __asm__ volatile("sc.w %0, %1, 0"
                     : "+r"(sc_word)
                     : "r"(&g_llsc_cell)
                     : "memory");
    stored = (sc_word == 1U);
#else
    (void)new_val;
    if (do_signal && raise(SIGURG) != 0) {
        return -1;
    }
    loaded = g_llsc_cell;
    stored = 0;
#endif
    *loaded_out = loaded;
    *stored_out = stored;
    return 0;
}

/* Bounded no-signal control: the same pair without delivery must store
 * (retries bound spurious losses; persistent failure = always-fail SC). */
static int probe_llsc_no_signal(void)
{
    for (int i = 0; i < 32; i++) {
        uint32_t loaded = 0;
        int stored = 0;
        g_llsc_cell = 0x13572468U;
        if (llsc_pair(0, 0xdeadbeefU, &loaded, &stored) != 0) {
            return -1;
        }
        if (loaded == 0x13572468U && stored != 0 && g_llsc_cell == 0xdeadbeefU) {
            return 0;
        }
    }
    return -1;
}

/* Interrupted probe: hold the reservation across one SIGURG delivery, then
 * SC. sigreturn must have cleared it, so the SC fails without storing. */
static int probe_llsc_broken_by_signal(void)
{
    uint32_t loaded = 0;
    int stored = 0;
    g_llsc_cell = 0x13572468U;
    g_llsc_probe_seen = 0;
    if (llsc_pair(1, 0xdeadbeefU, &loaded, &stored) != 0) {
        return -1;
    }
    if (g_llsc_probe_seen != 1) {
        return -1;
    }
    return (loaded == 0x13572468U && stored == 0 && g_llsc_cell == 0x13572468U) ? 0 : -1;
}

#endif /* P3_HAVE_LLSC */

#endif /* P3_LLSC_H */
