/*
 * tests/sig_fault_addr.h — Signal-safe 64-bit fault-address bridge.
 *
 * Carries a faulting si_addr out of an async-signal handler using three
 * 22-bit chunks stored in volatile sig_atomic_t objects (C11 only
 * guarantees a [-127, +127] range, so the 22-bit chunk width is enforced
 * by _Static_assert below). Each fixture keeps its own separate bridge
 * instance; the encode/decode helpers are shared here so the
 * portability-sensitive representation is defined once.
 *
 * Curated C11, no VLAs, no banned string functions, no x18 use.
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef SIG_FAULT_ADDR_H
#define SIG_FAULT_ADDR_H

#include <signal.h>
#include <stdint.h>

/* Three 22-bit words cover 66 bits, enough for any 64-bit address. */
_Static_assert(SIG_ATOMIC_MAX >= 0x3fffff, "22-bit chunks need wide sig_atomic_t");

struct sig_fault_addr_bridge {
    volatile sig_atomic_t w0;
    volatile sig_atomic_t w1;
    volatile sig_atomic_t w2;
};

static inline void sig_fault_addr_store(struct sig_fault_addr_bridge *bridge, uintptr_t addr)
{
    uint64_t u = (uint64_t)addr;
    bridge->w0 = (sig_atomic_t)(u & 0x3fffffULL);
    bridge->w1 = (sig_atomic_t)((u >> 22) & 0x3fffffULL);
    bridge->w2 = (sig_atomic_t)((u >> 44) & 0x3fffffULL);
}

static inline uintptr_t sig_fault_addr_load(const struct sig_fault_addr_bridge *bridge)
{
    uint64_t u0 = (uint64_t)(uint32_t)bridge->w0 & 0x3fffffULL;
    uint64_t u1 = (uint64_t)(uint32_t)bridge->w1 & 0x3fffffULL;
    uint64_t u2 = (uint64_t)(uint32_t)bridge->w2 & 0x3fffffULL;
    return (uintptr_t)(u0 | (u1 << 22) | (u2 << 44));
}

#endif /* SIG_FAULT_ADDR_H */
