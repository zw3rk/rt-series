/*
 * tests/check_abi_invariants.c — Compile-time and runtime verification of frozen
 * ABI structures, offsets, signal frames, context layouts, and HWCAP masks in
 * `rt-series` (SPEC.md, docs/HOST-CONTRACT.md, docs/lanes/).
 *
 * Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "a32host.h"

/* --------------------------------------------------------------------------
 * 1. /dev/a32host wire layout (A32H_ABI 1.0 / 1.1)
 * -------------------------------------------------------------------------- */
_Static_assert(sizeof(a32h_info_t) == 256, "a32h_info_t must be 256 bytes");
_Static_assert(offsetof(a32h_info_t, abi_major) == 0, "abi_major offset");
_Static_assert(offsetof(a32h_info_t, abi_minor) == 2, "abi_minor offset");
_Static_assert(offsetof(a32h_info_t, flags) == 4, "flags offset");
_Static_assert(offsetof(a32h_info_t, caps) == 8, "caps offset");
_Static_assert(offsetof(a32h_info_t, window_hint) == 16, "window_hint offset");
_Static_assert(offsetof(a32h_info_t, page_size) == 24, "page_size offset");
_Static_assert(offsetof(a32h_info_t, aot_socket) == 32, "aot_socket offset");
_Static_assert(offsetof(a32h_info_t, _reserved) == 140, "_reserved offset");
_Static_assert(A32H_GET_INFO == 0x81006101UL, "A32H_GET_INFO ioctl number");

/* --------------------------------------------------------------------------
 * 2. i386 Linux UAPI _fpstate_32 layout (arch/x86/include/uapi/asm/sigcontext.h)
 *    624 bytes total (pure FXSR mode: status = sw, magic = 0x0000 = X86_FXSR_MAGIC;
 *    sw_reserved[12] zeroed when no XSAVE tail is appended; legacy 80B _st[8]
 *    and cw/sw/tag at 0x00..0x6b are authoritative for x87 restoration on 32-bit
 *    sigreturn while _xmm[8] and mxcsr at 0x88..0x18f are authoritative for SSE):
 *      0x000..0x01b: 7 x u32 legacy FPU env (cw..fos)
 *      0x01c..0x06b: 8 x 10-byte legacy _st[8] (80 B, authoritative x87 state)
 *      0x06c..0x06f: u16 status + u16 magic (0x0000 = X86_FXSR_MAGIC)
 *      0x070..0x087: u32 _fxsr_env[6] (24 B)
 *      0x088..0x08f: u32 mxcsr + u32 reserved (8 B)
 *      0x090..0x10f: 8 x 16-byte _fxsr_st[8] (128 B)
 *      0x110..0x18f: 8 x 16-byte _xmm[8] (128 B, authoritative XMM state)
 *      0x190..0x23f: u32 padding1[44] (176 B)
 *      0x240..0x26f: u32 sw_reserved[12] (48 B, zeroed when XSAVE is absent)
 * -------------------------------------------------------------------------- */
typedef struct {
    uint32_t cw, sw, tag, ipoff, cssel, dataoff, datasel;
    uint8_t  _st[80];
    uint16_t status;
    uint16_t magic;
    uint32_t _fxsr_env[6];
    uint32_t mxcsr;
    uint32_t reserved;
    uint8_t  _fxsr_st[128];
    uint8_t  _xmm[128];
    uint32_t padding1[44];
    uint32_t sw_reserved[12];
} i386_uapi_fpstate_t;

_Static_assert(offsetof(i386_uapi_fpstate_t, _st) == 0x1c, "_st at 0x1c");
_Static_assert(offsetof(i386_uapi_fpstate_t, status) == 0x6c, "status at 0x6c");
_Static_assert(offsetof(i386_uapi_fpstate_t, magic) == 0x6e, "magic at 0x6e");
_Static_assert(offsetof(i386_uapi_fpstate_t, _fxsr_env) == 0x70, "_fxsr_env at 0x70");
_Static_assert(offsetof(i386_uapi_fpstate_t, mxcsr) == 0x88, "mxcsr at 0x88");
_Static_assert(offsetof(i386_uapi_fpstate_t, _fxsr_st) == 0x90, "_fxsr_st at 0x90");
_Static_assert(offsetof(i386_uapi_fpstate_t, _xmm) == 0x110, "_xmm at 0x110");
_Static_assert(offsetof(i386_uapi_fpstate_t, padding1) == 0x190, "padding1 at 0x190");
_Static_assert(offsetof(i386_uapi_fpstate_t, sw_reserved) == 0x240, "sw_reserved at 0x240");
_Static_assert(sizeof(i386_uapi_fpstate_t) == 624, "_fpstate_32 is 624 bytes");

/* --------------------------------------------------------------------------
 * 3. RV32 Linux UAPI signal structures (Linux v6.18 arch/riscv/include/uapi/asm/)
 * -------------------------------------------------------------------------- */
typedef struct {
    uint32_t sa_handler;
    uint32_t sa_flags;
    uint64_t sa_mask;
} rv32_kernel_sigaction_t;

_Static_assert(sizeof(rv32_kernel_sigaction_t) == 16, "rv32 kernel sigaction is 16 B");

typedef struct {
    uint64_t f[32];
    uint32_t fcsr;
    uint32_t _pad;
} rv32_d_ext_state_t;

_Static_assert(sizeof(rv32_d_ext_state_t) == 264, "rv32 __riscv_d_ext_state is 264 B");

typedef struct __attribute__((aligned(16))) {
    uint64_t f[64];
    uint32_t fcsr;
    uint32_t reserved[3];
} rv32_q_ext_state_t;

typedef union __attribute__((aligned(16))) {
    rv32_d_ext_state_t d;
    rv32_q_ext_state_t q;
} rv32_fp_state_t;

_Static_assert(sizeof(rv32_fp_state_t) == 528, "rv32 union __riscv_fp_state is 528 B");

typedef struct __attribute__((aligned(16))) {
    uint32_t        gregs[32];
    rv32_fp_state_t fpregs;
} rv32_sigcontext_t;

_Static_assert(sizeof(rv32_sigcontext_t) == 656, "rv32 sigcontext is 656 B");

typedef struct {
    uint32_t ss_sp;
    int32_t  ss_flags;
    uint32_t ss_size;
} rv32_stack_t;

_Static_assert(sizeof(rv32_stack_t) == 12, "rv32 stack_t is 12 B");

typedef struct __attribute__((aligned(16))) {
    uint32_t          uc_flags;
    uint32_t          uc_link;
    rv32_stack_t      uc_stack;
    uint32_t          uc_sigmask[2];
    uint8_t           uc_sigmask_ext[128 - 8];
    rv32_sigcontext_t uc_mcontext;
} rv32_ucontext_t;

_Static_assert(offsetof(rv32_ucontext_t, uc_mcontext) == 160, "rv32 uc_mcontext at 160");
_Static_assert(sizeof(rv32_ucontext_t) == 816, "rv32 ucontext is 816 B");

typedef struct __attribute__((aligned(16))) {
    uint8_t         info[128];
    rv32_ucontext_t uc;
} rv32_rt_sigframe_t;

_Static_assert(sizeof(rv32_rt_sigframe_t) == 944, "rv32 rt_sigframe is 944 B");

/* --------------------------------------------------------------------------
 * 4. MIPS32 frozen context layout (SPEC §5.1.2) — no overlapping fields
 * -------------------------------------------------------------------------- */
typedef struct __attribute__((aligned(16))) {
    uint32_t gpr[32];        /* 0x000..0x07f */
    uint32_t pc;             /* 0x080..0x083 */
    uint32_t next_pc;        /* 0x084..0x087 */
    uint32_t hi;             /* 0x088..0x08b */
    uint32_t lo;             /* 0x08c..0x08f */
    uint32_t ulr;            /* 0x090..0x093 */
    uint32_t fcsr;           /* 0x094..0x097 */
    uint8_t  in_delay_slot;  /* 0x098 */
    uint8_t  fr_mode;        /* 0x099 */
    uint8_t  llbit;          /* 0x09a */
    uint8_t  nan2008;        /* 0x09b */
    uint32_t lladdr;         /* 0x09c..0x09f */
    uint32_t llval;          /* 0x0a0..0x0a3 */
    uint32_t cp0_config1;    /* 0x0a4..0x0a7 */
    uint64_t guest_base;     /* 0x0a8..0x0af */
    uint64_t ibtc_ptr;       /* 0x0b0..0x0b7 */
    uint32_t exit_reason;    /* 0x0b8..0x0bb */
    uint32_t exit_info;      /* 0x0bc..0x0bf */
    uint64_t fpr[32];        /* 0x0c0..0x1bf */
} mips32_ctx_layout_t;

_Static_assert(offsetof(mips32_ctx_layout_t, pc) == 0x080, "mips32 pc at 0x080");
_Static_assert(offsetof(mips32_ctx_layout_t, ulr) == 0x090, "mips32 ulr at 0x090");
_Static_assert(offsetof(mips32_ctx_layout_t, fcsr) == 0x094, "mips32 fcsr at 0x094");
_Static_assert(offsetof(mips32_ctx_layout_t, in_delay_slot) == 0x098, "mips32 delay_slot at 0x098");
_Static_assert(offsetof(mips32_ctx_layout_t, lladdr) == 0x09c, "mips32 lladdr at 0x09c");
_Static_assert(offsetof(mips32_ctx_layout_t, llval) == 0x0a0, "mips32 llval at 0x0a0");
_Static_assert(offsetof(mips32_ctx_layout_t, guest_base) == 0x0a8, "mips32 guest_base at 0x0a8");
_Static_assert(offsetof(mips32_ctx_layout_t, fpr) == 0x0c0, "mips32 fpr at 0x0c0");
_Static_assert(sizeof(mips32_ctx_layout_t) == 0x1c0, "mips32_ctx_layout_t is 0x1c0 B");

/* --------------------------------------------------------------------------
 * 5. SPARC32 & SPARC64 signal frame prefix `sparc_stackf` and complete
 *    fixed `rt_signal_frame` layouts (Linux arch/sparc/include/uapi/asm/ptrace.h,
 *    arch/sparc/kernel/signal_32.c, arch/sparc/kernel/signal_64.c)
 * -------------------------------------------------------------------------- */
typedef struct {
    uint32_t locals[8];
    uint32_t ins[6];
    uint32_t fp;
    uint32_t callers_pc;
    uint32_t structptr;
    uint32_t xargs[6];
    uint32_t xxargs[1];
} sparc32_stackf_t;

_Static_assert(sizeof(sparc32_stackf_t) == 96, "sparc32_stackf_t is 96 B");

typedef struct {
    uint32_t psr;
    uint32_t pc;
    uint32_t npc;
    uint32_t y;
    uint32_t u_regs[16];
} sparc32_pt_regs_t;

_Static_assert(sizeof(sparc32_pt_regs_t) == 80, "sparc32_pt_regs_t is 80 B");

typedef struct {
    uint32_t ss_sp;
    int32_t  ss_flags;
    uint32_t ss_size;
} sparc32_stack_t;

typedef struct {
    sparc32_stackf_t  ss;            /* 0x000..0x05f (96 B) */
    uint8_t           info[128];     /* 0x060..0x0df (128 B) */
    sparc32_pt_regs_t regs;          /* 0x0e0..0x12f (80 B) */
    uint32_t          mask[2];       /* 0x130..0x137 (8 B sigset_t) */
    uint32_t          fpu_save;      /* 0x138..0x13b (4 B ptr) */
    uint32_t          insns[2];      /* 0x13c..0x143 (8 B) */
    sparc32_stack_t   stack;         /* 0x144..0x14f (12 B) */
    uint32_t          extra_size;    /* 0x150..0x153 (4 B) */
    uint32_t          rwin_save;     /* 0x154..0x157 (4 B ptr) */
} sparc32_rt_signal_frame_t;

_Static_assert(offsetof(sparc32_rt_signal_frame_t, regs) == 0xe0, "sparc32 regs at 0xe0");
_Static_assert(offsetof(sparc32_rt_signal_frame_t, mask) == 0x130, "sparc32 mask at 0x130");
_Static_assert(offsetof(sparc32_rt_signal_frame_t, fpu_save) == 0x138, "sparc32 fpu_save at 0x138");
_Static_assert(offsetof(sparc32_rt_signal_frame_t, stack) == 0x144, "sparc32 stack at 0x144");
_Static_assert(offsetof(sparc32_rt_signal_frame_t, extra_size) == 0x150, "sparc32 extra_size at 0x150");
_Static_assert(offsetof(sparc32_rt_signal_frame_t, rwin_save) == 0x154, "sparc32 rwin_save at 0x154");
_Static_assert(sizeof(sparc32_rt_signal_frame_t) == 344, "sparc32_rt_signal_frame_t is 344 B");

typedef struct {
    uint64_t locals[8];
    uint64_t ins[6];
    uint64_t fp;
    uint64_t callers_pc;
    uint64_t structptr;
    uint64_t xargs[6];
    uint64_t xxargs[1];
} sparc64_stackf_t;

_Static_assert(sizeof(sparc64_stackf_t) == 192, "sparc64_stackf_t is 192 B");

typedef struct {
    uint64_t u_regs[16];
    uint64_t tstate;
    uint64_t tpc;
    uint64_t tnpc;
    uint32_t y;
    uint32_t magic;
} sparc64_pt_regs_t;

_Static_assert(sizeof(sparc64_pt_regs_t) == 160, "sparc64_pt_regs_t is 160 B");

typedef struct {
    uint64_t ss_sp;
    int32_t  ss_flags;
    int32_t  _pad;
    uint64_t ss_size;
} sparc64_stack_t;

typedef struct {
    sparc64_stackf_t  ss;         /* 0x000..0x0bf (192 B) */
    uint8_t           info[128];  /* 0x0c0..0x13f (128 B) */
    sparc64_pt_regs_t regs;       /* 0x140..0x1df (160 B) */
    uint64_t          fpu_save;   /* 0x1e0..0x1e7 (8 B ptr) */
    sparc64_stack_t   stack;      /* 0x1e8..0x1ff (24 B) */
    uint64_t          mask;       /* 0x200..0x207 (8 B sigset_t) */
    uint64_t          rwin_save;  /* 0x208..0x20f (8 B ptr) */
} sparc64_rt_signal_frame_t;

_Static_assert(offsetof(sparc64_rt_signal_frame_t, regs) == 0x140, "sparc64 regs at 0x140");
_Static_assert(offsetof(sparc64_rt_signal_frame_t, fpu_save) == 0x1e0, "sparc64 fpu_save at 0x1e0");
_Static_assert(offsetof(sparc64_rt_signal_frame_t, stack) == 0x1e8, "sparc64 stack at 0x1e8");
_Static_assert(offsetof(sparc64_rt_signal_frame_t, mask) == 0x200, "sparc64 mask at 0x200");
_Static_assert(offsetof(sparc64_rt_signal_frame_t, rwin_save) == 0x208, "sparc64 rwin_save at 0x208");
_Static_assert(sizeof(sparc64_rt_signal_frame_t) == 528, "sparc64_rt_signal_frame_t is 528 B");

/* --------------------------------------------------------------------------
 * 6. LoongArch64 & PPC64 symbolic HWCAP / CPUCFG masks (Phase 2 integer vs Phase 3 FP/SIMD)
 * -------------------------------------------------------------------------- */
enum {
    LA_HWCAP_CPUCFG  = (1U << 0),
    LA_HWCAP_LAM     = (1U << 1),
    LA_HWCAP_UAL     = (1U << 2),
    LA_HWCAP_FPU     = (1U << 3),
    LA_HWCAP_LSX     = (1U << 4),
    LA_HWCAP_LASX    = (1U << 5),
    LA_HWCAP_CRC32   = (1U << 6),
    LA_HWCAP_P2_INT_PROFILE = (LA_HWCAP_CPUCFG | LA_HWCAP_LAM | LA_HWCAP_UAL |
                               LA_HWCAP_CRC32),
    LA_HWCAP_BASE_PROFILE   = (LA_HWCAP_P2_INT_PROFILE | LA_HWCAP_FPU),
    LA_HWCAP_SIMD_PROFILE   = (LA_HWCAP_BASE_PROFILE | LA_HWCAP_LSX | LA_HWCAP_LASX),
    LA_CPUCFG2_FP           = (1U << 0),
    LA_CPUCFG2_FP_SP        = (1U << 1),
    LA_CPUCFG2_FP_DP        = (1U << 2),
    LA_CPUCFG2_FP_VER_1     = (1U << 3),
    LA_CPUCFG2_LSX          = (1U << 6),
    LA_CPUCFG2_LASX         = (1U << 7),
    LA_CPUCFG2_LLFTP        = (1U << 14),
    LA_CPUCFG2_LLFTP_VER_1  = (1U << 15),
    LA_CPUCFG2_LAM          = (1U << 22),
    LA_CPUCFG2_LAM_BH       = (1U << 27),
    LA_CPUCFG2_LAMCAS       = (1U << 28)
};

_Static_assert(LA_HWCAP_P2_INT_PROFILE == 0x0047U, "LoongArch P2 int HWCAP == 0x0047");
_Static_assert(LA_HWCAP_BASE_PROFILE == 0x004fU, "LoongArch scalar+FPU HWCAP == 0x004f");
_Static_assert(LA_HWCAP_SIMD_PROFILE == 0x007fU, "LoongArch SIMD HWCAP == 0x007f");
_Static_assert((LA_CPUCFG2_LAM & (1U << 22)) != 0U, "CPUCFG2_LAM is bit 22");

#define PPC_FEAT_32           0x80000000U
#define PPC_FEAT_64           0x40000000U
#define PPC_FEAT_ALTIVEC      0x10000000U
#define PPC_FEAT_FPU          0x08000000U
#define PPC_FEAT_MMU          0x04000000U
#define PPC_FEAT_ICACHE_SNOOP 0x00002000U
#define PPC_FEAT_ARCH_2_05    0x00001000U
#define PPC_FEAT_ARCH_2_06    0x00000100U
#define PPC_FEAT_VSX          0x00000080U
#define PPC_FEAT_TRUE_LE      0x00000002U
#define PPC64_HWCAP_PROFILE   (PPC_FEAT_32 | PPC_FEAT_64 | PPC_FEAT_ALTIVEC | \
                               PPC_FEAT_FPU | PPC_FEAT_MMU | PPC_FEAT_ICACHE_SNOOP | \
                               PPC_FEAT_ARCH_2_05 | PPC_FEAT_ARCH_2_06 | \
                               PPC_FEAT_VSX | PPC_FEAT_TRUE_LE)

_Static_assert(PPC64_HWCAP_PROFILE == 0xdc003182U, "PPC64 HWCAP == 0xdc003182");

int main(void) {
    /* Verify i386 signal stack alignment formula: ((sp + 4) & ~15) - 4 */
    for (uint32_t raw_sp = 0xbfff0000U; raw_sp < 0xbfff0020U; ++raw_sp) {
        uint32_t sp = ((raw_sp + 4U) & ~15U) - 4U;
        if ((sp & 15U) != 12U || sp > raw_sp) {
            fprintf(stderr, "FAIL: i386 signal sp alignment for 0x%08x -> 0x%08x\n",
                    raw_sp, sp);
            return 1;
        }
    }
    printf("CHECK-ABI-INVARIANTS OK\n");
    return 0;
}
