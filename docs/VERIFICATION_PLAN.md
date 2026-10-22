# Verification plan: rv32_core

## 1. Design under test

`rv32_core` is a single-issue, in-order RV32I pipeline with five stages
(IF, ID, EX, MEM, WB), one instruction port and one data port, both
combinational-read with a ready handshake. The reference for intended
behaviour is the RISC-V Unprivileged ISA (RV32I, Zifencei) plus the
micro-architecture choices listed below, which the ISA leaves open:

| Choice | This core |
|---|---|
| Misaligned load / store | address-misaligned exception (not emulated) |
| Misaligned jump / branch target | instruction-address-misaligned exception on the jump |
| Exceptions | the trapping instruction retires with `rvfi_trap = 1`, no side effects, `pc_wdata = 0`; the core halts (no CSRs in this configuration) |
| FENCE | no-op (one hart, one memory port, in order) |
| FENCE.I | flush and refetch everything younger |
| Branch prediction | static not-taken, resolved in EX, 2-cycle penalty |
| Retirement port | RVFI, aligned-memory convention (`RISCV_FORMAL_ALIGNED_MEM`) |

## 2. Strategy

Two independent ways of knowing the answer, plus white-box rules for how
the pipeline gets there.

**Checkers**

| Checker | What it proves | Where |
|---|---|---|
| Lockstep scoreboard | every retired instruction matches the C++ reference model in all RVFI fields (pc, insn, operands read, rd write, next pc, memory address/masks/data, trap and cause) | `tb/env/scoreboard.svh`, `model/` |
| End-of-test state compare | all 31 registers and every memory word equal the model after the last retirement, catching writes that never appear at retirement | `tb/env/tb_env.svh` |
| SVA | pipeline invariants at the cycle they break: hazard detection, forwarding priority, stall holds, flushes, x0, retirement order | `tb/sva/rv32_core_sva.sv` |
| Watchdog / timeout | no retirement for `hang_cycles` (deadlock, lost handshake) | `tb/env/tb_env.svh` |
| Drain window | after the end condition the core keeps running for 30 cycles with every checker live; after a trap nothing may retire | `tb/env/tb_env.svh` |
| Self-checking tests | riscv-tests compute and compare their own results and report through `tohost` | `tests/env/` |
| Formal (riscv-formal, SymbiYosys) | every RV32I instruction, register-file consistency, PC sequencing forward and backward, causality, unique retirement order, liveness and illegal-instruction trapping, for all programs and all memory timings up to a bounded depth (15 to 30 cycles) | `formal/rv32verify/`, `scripts/run_formal.sh` |

The model is written from the ISA document, not from the RTL, and is
qualified on its own against riscv-tests (`./regress iss`) before it is
trusted. Bus memory and model memory are loaded by two different loaders.

**Stimulus**

| Source | Purpose |
|---|---|
| riscv-tests rv32ui (42 tests) | directed, community-written, each instruction's corner cases |
| Directed tests (`tests/directed/`, 4 tests) | written for this core after the bug-injection campaign exposed holes: FENCE.I over instructions already in flight, and instructions directly behind a trap |
| Constrained-random generator (`tb/gen/rv_gen.svh`) | SV classes with `randomize()`; knobs for mix, dependency distance, branch direction, loops, address window and aliasing, boundary operands, x0 destinations, program ending |
| Knob profiles (`scripts/regress.py`) | `default`, `alu_corner`, `mem_alias`, `branchy`, `hazard` |
| Memory agent (`tb/env/mem_agent.svh`) | random wait states on each port, 5 profiles from 0% to 50% |

Seed `s` of the random regression uses wait profile `s % 5` and knob
profile `(s / 5) % 5`, so any 25 consecutive seeds cover every combination.

## 3. Features, tests, checkers and coverage

Status is the state at the last coverage run recorded in
[COVERAGE.md](COVERAGE.md).

### 3.1 Architectural (ISA) features

| ID | Feature | Stimulus | Checker | Coverage item |
|---|---|---|---|---|
| A01 | Register-register ALU: ADD SUB SLL SLT SLTU XOR SRL SRA OR AND, every operand value class on both sides (0, 1, -1, max, min, other positive, other negative) | rv32ui, random (`alu_corner`) | scoreboard | `cg_alu_r.x_op_rs1_rs2` |
| A02 | Register-immediate ALU: ADDI SLTI SLTIU XORI ORI ANDI against immediate classes (0, 1, -1, 2047, -2048, other) | rv32ui, random | scoreboard | `cg_alu_i.x_op_rs1_imm` |
| A03 | Shifts by 0, 1, 31 and other amounts, immediate and register forms | rv32ui, random | scoreboard | `cg_shift.x_op_rs1_sh` |
| A04 | Branch types taken and not taken | rv32ui, random (`branchy`, self-compare knob) | scoreboard, SVA `a_pc_sequence` | `cg_branch.x_op_taken` |
| A05 | Branch compare relation: equal, less in both views, less signed only, less unsigned only, greater in both | random | scoreboard | `cg_branch.x_op_rel` |
| A06 | JAL / JALR link value and target; JALR clears bit 0 | rv32ui, random (odd JALR offsets) | scoreboard | `cg_misc.cp_op`, `cg_misc.cp_jalr_odd` |
| A07 | LUI / AUIPC | rv32ui, random | scoreboard | `cg_misc.cp_op` |
| A08 | Loads: size x byte offset x sign bit (sign and zero extension) | rv32ui, random (`mem_alias`) | scoreboard | `cg_load.x_op_off_msb` |
| A09 | Stores: size x byte lane | rv32ui, random | scoreboard, end-of-test memory compare | `cg_store.x_op_off` |
| A10 | x0 as destination of every writing class discards the result | random (`p_x0`) | scoreboard, SVA `a_x0_*` | `cg_misc.cp_x0` |
| A11 | FENCE, FENCE.I (self-modifying code), including patching the instructions already fetched behind FENCE.I | rv32ui `fence_i`, directed `smc_fencei`, random | scoreboard | `cg_misc.cp_op`, `cg_pipe.cp_redirect.fence_i` |
| A12 | Exceptions: illegal instruction, ECALL, EBREAK, load / store / instruction-address misaligned | random program endings, directed `trap_*` | scoreboard (trap + cause), SVA `a_trap_flushes`, `a_nothing_after_trap` | `cg_misc.cp_trap` |
| A13 | Back-to-back taken control transfers | random | scoreboard | `cg_misc.cp_b2b_taken` |
| A14 | Register dependency distance 1, 2, 3, 4, 5+ for each consumer type and operand | random (`p_dep`, `dep_max`) | scoreboard | `cg_dep.x_rs1`, `cg_dep.x_rs2` |

### 3.2 Pipeline (micro-architectural) features

| ID | Feature | Stimulus | Checker | Coverage item |
|---|---|---|---|---|
| P01 | Forward from EX/MEM, per operand, per consumer type (ALU, load address, store address and data, branch, JALR) | random (`hazard`) | scoreboard, SVA `a_fwd_a_youngest`, `a_fwd_b_youngest` | `cg_pipe.x_cons_fwd_a`, `x_cons_fwd_b` |
| P02 | Forward from MEM/WB, same breakdown | random | scoreboard, SVA `a_fwd_*_memwb` | same |
| P03 | Both operands forwarded, every source pair | random | scoreboard | `cg_pipe.x_fwd_ab` |
| P04 | Priority: two older producers of the same register, the younger wins | random (`hazard`) | SVA `a_fwd_*_youngest`, scoreboard | `cg_pipe.cp_shadow` |
| P05 | WB to ID write-through in the register file | random | scoreboard | `cg_pipe.cp_bypass` |
| P06 | Load-use stall on rs1, rs2, both; never a missing or a spurious stall | random (`hazard`) | SVA `a_loaduse_needed`, `a_loaduse_real`, `a_loaduse_holds`, scoreboard | `cg_pipe.cp_load_use` |
| P07 | After a load-use stall the consumer takes the load data from MEM/WB | random | scoreboard | `cg_pipe.cp_stall_then_forward`, cover `c_loaduse_then_fwd` |
| P08 | Load data never forwarded from EX/MEM | random | SVA `a_no_load_fwd_from_exmem` | (assertion only) |
| P09 | Redirect on taken branch, JAL, JALR, FENCE.I flushes both younger instructions | rv32ui, random | SVA `a_redirect_flushes`, `a_pc_sequence` | `cg_pipe.cp_redirect` |
| P10 | Redirect at the target of a redirect (3 cycles apart) | random (`branchy`) | scoreboard | `cg_pipe.cp_back_to_back_redirect` |
| P11 | Instruction-port wait states, including during a redirect | wait profiles | scoreboard, watchdog | `cg_pipe.cp_imem_wait`, `cp_redirect_during_imem_wait` |
| P12 | Data-port wait states on loads and stores hold IF..MEM, bubble WB | wait profiles | SVA `a_wait_holds`, scoreboard | `cg_pipe.cp_dmem_wait` |
| P13 | Operands of a held EX instruction are refreshed while its producer retires | wait profiles + `hazard` | SVA `a_wait_refresh`, scoreboard | `cg_pipe.cp_wait_refresh_operand` |
| P14 | A redirect is deferred while MEM waits | wait profiles + `branchy` | SVA `a_redirect_only_when_advancing` | `cg_pipe.cp_redirect_deferred`, cover `c_redirect_deferred` |
| P15 | Load-use stall coinciding with a data wait | wait profiles | SVA `a_wait_holds` | `cg_pipe.cp_loaduse_during_wait`, cover `c_wait_then_loaduse` |
| P16 | Trap in MEM wins over a younger redirect and a younger load-use stall | random endings with shadow instructions | SVA `a_trap_flushes`, `a_nothing_after_trap` | `cg_pipe.cp_trap_kills_redirect`, `cp_trap_kills_loaduse` |
| P17 | Retirement is in program order, once per instruction, nothing from a wrong path | all | SVA `a_pc_sequence`, `a_order_sequence`, scoreboard | (assertion only) |
| P18 | Data requests only from valid, non-trapping loads and stores; stores always carry a mask | all | SVA `a_dmem_req_legal`, `a_store_has_mask`, end-of-test memory compare | (assertion only) |
| P19 | No fetch after halt, PC always word aligned | all | SVA `a_halted_quiet`, `a_pc_aligned` | (assertion only) |
| P20 | x0 reads as zero on both register-file ports and is never write-enabled | all | SVA `a_x0_read_zero`, `a_x0_never_written` | (assertion only) |
| P21 | No spurious load-use stall when an unused register field of the ID instruction happens to name the load's destination | random (field aliasing in LUI/AUIPC) | SVA `a_loaduse_real` | `cg_pipe.cp_unused_field_matches_load` |
| P22 | Nothing behind a trap takes effect: no retirement, no memory write, during and after the drain window | directed `trap_*`, random trap endings | bench drain check, end-of-test memory compare, SVA `a_trap_flushes`, `a_nothing_after_trap` | `cg_pipe.cp_trap_kills_redirect`, `cp_trap_kills_loaduse` |

## 4. Sign-off criteria

1. `./regress` green: lint clean, model qualified, rv32ui passing in both
   wait profiles except the documented `ma_data`, every random seed passing.
2. 100% of the pipeline items (`cg_pipe`, `cg_dep`, `cg_misc`, branch, load,
   store groups). These are the features the core was built to handle.
3. Operand-value crosses (`cg_alu_r`, `cg_alu_i`, `cg_shift`) closed or every
   remaining hole listed with a reason in [COVERAGE.md](COVERAGE.md).
4. The bench detects the injected bugs in [BUG_INJECTION.md](BUG_INJECTION.md);
   any bug it misses is explained.

## 5. Out of scope in this configuration

- CSRs, interrupts, privilege modes, trap handlers.
- Misaligned access emulation (the core traps by design).
- Multi-hart memory ordering (single hart, FENCE is a no-op).
- Reset in the middle of execution (reset is applied once, at start).
- Timing, area and power (a synthesis sanity check is planned separately).
