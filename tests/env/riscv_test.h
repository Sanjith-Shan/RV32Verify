// riscv_test.h -- minimal bare-metal test environment for riscv-tests on this core.
//
// The stock "p" environment sets up CSRs and a trap handler before the test
// body. This core has no CSRs, so the environment is reduced to: start at
// _start, run the test, and report through the tohost word.
//   pass:  tohost <= 1
//   fail:  tohost <= (test_number << 1) | 1
// The same convention is used by the HTIF in spike, so results read the same.
#ifndef RV32VERIFY_RISCV_TEST_H
#define RV32VERIFY_RISCV_TEST_H

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        init;

#define RVTEST_CODE_END                                                 \
        unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li a0, 1;                                                       \
        la t5, tohost;                                                  \
        sw a0, 0(t5);                                                   \
1:      j 1b;

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll a0, TESTNUM, 1;                                             \
        or a0, a0, 1;                                                   \
        la t5, tohost;                                                  \
        sw a0, 0(t5);                                                   \
2:      j 2b;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0; .size tohost, 8;   \
        .align 6; .global fromhost; fromhost: .dword 0; .size fromhost, 8; \
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
