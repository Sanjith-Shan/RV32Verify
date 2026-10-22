# trap_misaligned_shadow.S -- directed test: a misaligned load followed by a
# load-use pair and a store. The trap must win over the younger stall, and
# nothing behind the trap may retire. Added with trap_ecall_shadow.S.
#include "riscv_test.h"
#include "test_macros.h"
RVTEST_RV32U
RVTEST_CODE_BEGIN
  la   t0, canary
  li   t1, 0x0badf00d
  lw   a0, 1(t0)        # misaligned word load: exception
  lw   a1, 0(t0)        # load ...
  add  a1, a1, a1       # ... and its consumer (load-use stall behind the trap)
  sw   t1, 4(t0)
1:j    1b
RVTEST_CODE_END
  .data
RVTEST_DATA_BEGIN
canary: .word 0, 0
RVTEST_DATA_END
