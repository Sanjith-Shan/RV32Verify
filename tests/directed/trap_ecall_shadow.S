# trap_ecall_shadow.S -- directed test: nothing behind a trap may take effect.
# ECALL is followed by a store to a canary word and a register write. The
# core must halt with the ECALL as its last retirement; the bench checks that
# nothing retires afterwards and that the canary in memory is untouched.
# Added after the bug-injection campaign (BUG_TRAP_NO_KILL, docs/BUG_INJECTION.md).
#include "riscv_test.h"
#include "test_macros.h"
RVTEST_RV32U
RVTEST_CODE_BEGIN
  la   t0, canary
  li   t1, 0x5a5a5a5a
  li   a0, 7
  ecall
  sw   t1, 0(t0)        # must never execute
  addi a0, a0, 1        # must never execute
  sw   a0, 4(t0)        # must never execute
1:j    1b
RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
canary: .word 0, 0
RVTEST_DATA_END
