// rv32_synth_top.sv -- synthesis-only top level.
// Exposes the core's two memory ports and leaves the RVFI retirement port
// unconnected. RVFI exists for verification; with it the core has more
// outputs than the FPGA package has pins, and the logic that only feeds it
// (retirement counter, operand copies in the pipeline registers) is removed
// by synthesis. The numbers in docs/RESULTS.md are for this top.
module rv32_synth_top (
  input  logic        clk,
  input  logic        rst_n,
  output logic        imem_req,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  input  logic        imem_ready,
  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [3:0]  dmem_wmask,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_ready
);
  rv32_core u_core (
    .clk, .rst_n,
    .imem_req, .imem_addr, .imem_rdata, .imem_ready,
    .dmem_req, .dmem_we, .dmem_addr, .dmem_wmask, .dmem_wdata, .dmem_rdata, .dmem_ready,
    .rvfi_valid(), .rvfi_order(), .rvfi_insn(), .rvfi_trap(), .rvfi_halt(), .rvfi_intr(),
    .rvfi_mode(), .rvfi_ixl(), .rvfi_rs1_addr(), .rvfi_rs2_addr(), .rvfi_rs1_rdata(),
    .rvfi_rs2_rdata(), .rvfi_rd_addr(), .rvfi_rd_wdata(), .rvfi_pc_rdata(), .rvfi_pc_wdata(),
    .rvfi_mem_addr(), .rvfi_mem_rmask(), .rvfi_mem_wmask(), .rvfi_mem_rdata(),
    .rvfi_mem_wdata(), .rvfi_trap_cause()
  );
endmodule
