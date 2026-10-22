# smc_fencei.S -- directed test: self-modifying code with FENCE.I.
#
# rv32ui fence_i patches code that is fetched long after the store, so in
# this 5-stage pipeline no stale copy of the patched instruction is ever in
# flight and a FENCE.I that does nothing still passes. This test patches
# instructions that are already in IF/ID when FENCE.I executes, which is
# exactly the case FENCE.I exists for. Added after the bug-injection campaign
# showed BUG_FENCEI_NO_FLUSH escaping (docs/BUG_INJECTION.md).

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # ---- case 2: patch the instruction directly after FENCE.I
  li TESTNUM, 2
  li a0, 0
  la t0, 1f
  li t1, 0x00a00513          # addi a0, zero, 10
  sw t1, 0(t0)
  fence.i
1:addi a0, zero, 1           # replaced before it executes
  li t2, 10
  bne a0, t2, fail

  # ---- case 3: patch the second instruction after FENCE.I
  li TESTNUM, 3
  li a1, 0
  la t0, 2f
  li t1, 0x01400593          # addi a1, zero, 20
  sw t1, 0(t0)
  fence.i
  nop
2:addi a1, zero, 2
  li t2, 20
  bne a1, t2, fail

  # ---- case 4: patch a branch into a jump over a failure
  li TESTNUM, 4
  la t0, 3f
  li t1, 0x0080006f          # jal zero, +8
  sw t1, 0(t0)
  fence.i
3:j fail                     # replaced by "jal zero, +8"
  j fail
  li t2, 1                   # landing point of the patched jump

  # ---- case 5: patch byte by byte (sb), then FENCE.I
  li TESTNUM, 5
  li a2, 0
  la t0, 4f
  li t1, 0x01e00613          # addi a2, zero, 30
  sb t1, 0(t0)
  srli t1, t1, 8
  sb t1, 1(t0)
  srli t1, t1, 8
  sb t1, 2(t0)
  srli t1, t1, 8
  sb t1, 3(t0)
  fence.i
4:addi a2, zero, 3
  li t2, 30
  bne a2, t2, fail

  RVTEST_PASS
fail:
  RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
