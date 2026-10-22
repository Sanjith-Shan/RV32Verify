# trap_illegal_shadow.S -- directed test: an illegal instruction followed by a
# taken branch. The trap must win over the younger redirect, and nothing
# behind the trap may retire. Added with trap_ecall_shadow.S.
#include "riscv_test.h"
#include "test_macros.h"
RVTEST_RV32U
RVTEST_CODE_BEGIN
  la   t0, canary
  li   t1, 0x12345678
  .word 0x00000000      # illegal instruction
  beq  zero, zero, 2f   # taken branch directly behind the trap
  sw   t1, 0(t0)
2:sw   t1, 4(t0)
1:j    1b
RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
canary: .word 0, 0
RVTEST_DATA_END
