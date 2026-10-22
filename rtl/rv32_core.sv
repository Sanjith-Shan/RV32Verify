// rv32_core.sv
// Top level of the 5-stage in-order RV32I pipeline.
//
//   IF  rv32_fetch    PC, next-PC select, IF/ID
//   ID  rv32_decode   decoder, register file read, ID/EX
//   EX  rv32_execute  forwarding muxes, ALU, branch resolve, EX/MEM
//   MEM rv32_memory   data bus, load align/extend, MEM/WB
//   WB  rv32_writeback register file write, RVFI retirement port
//   rv32_hazard       forwarding select, load-use stall, flush, holds
//   rv32_regfile      32x32, 2R1W, write-through
//
// The RVFI port follows the riscv-formal convention with aligned memory
// (RISCV_FORMAL_ALIGNED_MEM): mem_addr is word aligned, masks select lanes.
//
// Traps: an instruction that raises an exception (illegal, ECALL, EBREAK,
// misaligned load/store/jump target) retires with rvfi_trap = 1 and no side
// effects, and the core halts. There are no CSRs in this configuration.

module rv32_core
  import rv32_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h8000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  // instruction memory
  output logic        imem_req,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  input  logic        imem_ready,

  // data memory
  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [3:0]  dmem_wmask,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_ready,

  // retirement (RVFI)
  output logic        rvfi_valid,
  output logic [63:0] rvfi_order,
  output logic [31:0] rvfi_insn,
  output logic        rvfi_trap,
  output logic        rvfi_halt,
  output logic        rvfi_intr,
  output logic [1:0]  rvfi_mode,
  output logic [1:0]  rvfi_ixl,
  output logic [4:0]  rvfi_rs1_addr,
  output logic [4:0]  rvfi_rs2_addr,
  output logic [31:0] rvfi_rs1_rdata,
  output logic [31:0] rvfi_rs2_rdata,
  output logic [4:0]  rvfi_rd_addr,
  output logic [31:0] rvfi_rd_wdata,
  output logic [31:0] rvfi_pc_rdata,
  output logic [31:0] rvfi_pc_wdata,
  output logic [31:0] rvfi_mem_addr,
  output logic [3:0]  rvfi_mem_rmask,
  output logic [3:0]  rvfi_mem_wmask,
  output logic [31:0] rvfi_mem_rdata,
  output logic [31:0] rvfi_mem_wdata,
  output logic [3:0]  rvfi_trap_cause    // not part of RVFI; for the scoreboard
);

  if_id_t      if_id;
  id_ex_t      id_ex;
  ex_mem_t     ex_mem;
  mem_wb_t     mem_wb;
  ctrl_t       id_ctrl;

  // pc, halted and load_use are not consumed inside the core; they are kept
  // as named signals for the assertions, coverage probes and waveforms.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] pc;
  logic        halted;
  logic        load_use;
  /* verilator lint_on UNUSEDSIGNAL */

  logic [4:0]  rf_raddr1, rf_raddr2;
  logic [31:0] rf_rdata1, rf_rdata2;
  logic        rf_we;

  fwd_sel_e    fwd_a, fwd_b;
  logic [31:0] rs1_fwd, rs2_fwd, exmem_fwd_val;
  logic        ex_redirect_req;
  logic [31:0] ex_redirect_pc;
  logic        mem_wait, mem_trap;
  logic        stall_if, redirect, halt;
  logic        hold_ex, bubble_ex, hold_mem, bubble_mem;

  // ------------------------------------------------------------------ IF
  rv32_fetch #(.RESET_PC(RESET_PC)) u_fetch (
    .clk, .rst_n,
    .stall       (stall_if),
    .redirect    (redirect),
    .redirect_pc (ex_redirect_pc),
    .halt        (halt),
    .imem_req, .imem_addr, .imem_rdata, .imem_ready,
    .if_id       (if_id),
    .pc          (pc),
    .halted      (halted)
  );

  // ------------------------------------------------------------------ ID
  rv32_decode u_decode (
    .clk, .rst_n,
    .if_id       (if_id),
    .rf_raddr1, .rf_raddr2, .rf_rdata1, .rf_rdata2,
    .hold        (hold_ex),
    .bubble      (bubble_ex),
    .ex_rs1_fwd  (rs1_fwd),
    .ex_rs2_fwd  (rs2_fwd),
    .id_ctrl     (id_ctrl),
    .id_ex       (id_ex)
  );

  rv32_regfile u_regfile (
    .clk, .rst_n,
    .raddr1 (rf_raddr1), .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2), .rdata2 (rf_rdata2),
    .we     (rf_we),
    .waddr  (mem_wb.rd),
    .wdata  (mem_wb.rd_val)
  );

  // ------------------------------------------------------------------ EX
  rv32_execute u_execute (
    .clk, .rst_n,
    .id_ex         (id_ex),
    .fwd_a, .fwd_b,
    .exmem_fwd_val (exmem_fwd_val),
    .memwb_fwd_val (mem_wb.rd_val),
    .rs1_fwd, .rs2_fwd,
    .redirect_req  (ex_redirect_req),
    .redirect_pc   (ex_redirect_pc),
    .hold          (hold_mem),
    .bubble        (bubble_mem),
    .ex_mem        (ex_mem)
  );

  // ----------------------------------------------------------------- MEM
  rv32_memory u_memory (
    .clk, .rst_n,
    .ex_mem   (ex_mem),
    .dmem_req, .dmem_we, .dmem_addr, .dmem_wmask, .dmem_wdata, .dmem_rdata, .dmem_ready,
    .mem_wait (mem_wait),
    .mem_trap (mem_trap),
    .fwd_val  (exmem_fwd_val),
    .mem_wb   (mem_wb)
  );

  // -------------------------------------------------------------- hazard
  rv32_hazard u_hazard (
    .id_valid        (if_id.valid),
    .id_ctrl         (id_ctrl),
    .ex_valid        (id_ex.valid),
    .ex_ctrl         (id_ex.ctrl),
    .ex_redirect_req (ex_redirect_req),
    .mem_valid       (ex_mem.valid),
    .mem_rf_we       (ex_mem.rf_we),
    .mem_rd          (ex_mem.rd),
    .mem_is_load     (ex_mem.is_load),
    .mem_wait        (mem_wait),
    .mem_trap        (mem_trap),
    .wb_valid        (mem_wb.valid),
    .wb_rf_we        (mem_wb.rf_we),
    .wb_rd           (mem_wb.rd),
    .fwd_a, .fwd_b,
    .load_use, .stall_if, .redirect, .halt,
    .hold_ex, .bubble_ex, .hold_mem, .bubble_mem
  );

  // ------------------------------------------------------------------ WB
  rv32_writeback u_writeback (
    .clk, .rst_n,
    .mem_wb (mem_wb),
    .rf_we  (rf_we),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_trap, .rvfi_halt, .rvfi_intr,
    .rvfi_mode, .rvfi_ixl, .rvfi_rs1_addr, .rvfi_rs2_addr, .rvfi_rs1_rdata,
    .rvfi_rs2_rdata, .rvfi_rd_addr, .rvfi_rd_wdata, .rvfi_pc_rdata, .rvfi_pc_wdata,
    .rvfi_mem_addr, .rvfi_mem_rmask, .rvfi_mem_wmask, .rvfi_mem_rdata,
    .rvfi_mem_wdata, .rvfi_trap_cause
  );

endmodule
