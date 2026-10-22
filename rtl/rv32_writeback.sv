// rv32_writeback.sv
// WB stage: register file write enable and the RVFI retirement port.
// Every instruction that leaves MEM/WB with valid = 1 retires here, exactly
// once, in program order; rvfi_order counts retirements.

module rv32_writeback
  import rv32_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  mem_wb_t     mem_wb,

  output logic        rf_we,

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
  output logic [3:0]  rvfi_trap_cause
);

  assign rf_we = mem_wb.valid && mem_wb.rf_we;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)          rvfi_order <= '0;
    else if (rvfi_valid) rvfi_order <= rvfi_order + 64'd1;
  end

  assign rvfi_valid      = mem_wb.valid;
  assign rvfi_insn       = mem_wb.insn;
  assign rvfi_trap       = mem_wb.trap;
  assign rvfi_halt       = mem_wb.trap;
  assign rvfi_intr       = 1'b0;
  assign rvfi_mode       = 2'd3;
  assign rvfi_ixl        = 2'd1;
  assign rvfi_rs1_addr   = mem_wb.rs1;
  assign rvfi_rs2_addr   = mem_wb.rs2;
  assign rvfi_rs1_rdata  = mem_wb.rs1_val;
  assign rvfi_rs2_rdata  = mem_wb.rs2_val;
  assign rvfi_rd_addr    = mem_wb.rf_we ? mem_wb.rd : 5'd0;
  assign rvfi_rd_wdata   = mem_wb.rf_we ? mem_wb.rd_val : 32'd0;
  assign rvfi_pc_rdata   = mem_wb.pc;
  assign rvfi_pc_wdata   = mem_wb.next_pc;
  assign rvfi_mem_addr   = mem_wb.mem_addr;
  assign rvfi_mem_rmask  = mem_wb.mem_rmask;
  assign rvfi_mem_wmask  = mem_wb.mem_wmask;
  assign rvfi_mem_rdata  = mem_wb.mem_rdata;
  assign rvfi_mem_wdata  = mem_wb.mem_wdata;
  assign rvfi_trap_cause = mem_wb.trap ? mem_wb.cause : 4'd0;

endmodule
