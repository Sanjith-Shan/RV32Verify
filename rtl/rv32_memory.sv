// rv32_memory.sv
// MEM stage: data-memory request, byte-lane steering for stores, load data
// alignment and sign/zero extension, MEM/WB register.
//
// The data bus is word-addressed with byte write enables. Store data is
// shifted into its byte lanes; load data is taken from the lanes selected
// by the low address bits. dmem_ready = 0 holds the whole pipeline up to
// and including MEM, and sends a bubble into WB.

module rv32_memory
  import rv32_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  ex_mem_t     ex_mem,

  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [3:0]  dmem_wmask,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_ready,

  output logic        mem_wait,     // access issued but not yet completed
  output logic        mem_trap,     // trapping instruction is in MEM
  output logic [31:0] fwd_val,      // value forwarded from EX/MEM

  output mem_wb_t     mem_wb
);

  logic [1:0]  off;
  logic [3:0]  size_mask;
  logic [3:0]  lane_mask;
  logic [31:0] load_val, rd_val;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] shifted;   // upper bits unused for byte / half loads
  /* verilator lint_on UNUSEDSIGNAL */

  assign off = ex_mem.result[1:0];

  always_comb begin
    unique case (ex_mem.funct3[1:0])
      2'b00:   size_mask = 4'b0001;
      2'b01:   size_mask = 4'b0011;
      default: size_mask = 4'b1111;
    endcase
  end
`ifdef BUG_STORE_BYTE_LANE
  assign lane_mask = size_mask;                      // injected: ignores address offset
`else
  assign lane_mask = size_mask << off;
`endif

  assign dmem_req   = ex_mem.valid && (ex_mem.is_load || ex_mem.is_store);
  assign dmem_we    = ex_mem.valid && ex_mem.is_store;
  assign dmem_addr  = {ex_mem.result[31:2], 2'b00};
  assign dmem_wmask = dmem_we ? lane_mask : 4'b0000;
  // store data shifted into its lanes; lanes outside the mask are driven 0
  assign dmem_wdata = (ex_mem.rs2_val << {off, 3'b000}) &
                      {{8{dmem_wmask[3]}}, {8{dmem_wmask[2]}}, {8{dmem_wmask[1]}}, {8{dmem_wmask[0]}}};

  assign mem_wait = dmem_req && !dmem_ready;
  assign mem_trap = ex_mem.valid && ex_mem.trap;

  // ----------------------------------------------------- load alignment
  assign shifted = dmem_rdata >> {off, 3'b000};
  always_comb begin
    unique case (ex_mem.funct3)
`ifdef BUG_LB_ZERO_EXTEND
      3'b000:  load_val = {24'b0, shifted[7:0]};                     // injected
`else
      3'b000:  load_val = {{24{shifted[7]}}, shifted[7:0]};          // LB
`endif
      3'b001:  load_val = {{16{shifted[15]}}, shifted[15:0]};        // LH
      3'b100:  load_val = {24'b0, shifted[7:0]};                     // LBU
`ifdef BUG_LHU_SIGN_EXTEND
      3'b101:  load_val = {{16{shifted[15]}}, shifted[15:0]};        // injected
`else
      3'b101:  load_val = {16'b0, shifted[15:0]};                    // LHU
`endif
      default: load_val = dmem_rdata;                                // LW
    endcase
  end

  assign rd_val  = (ex_mem.wb_sel == WB_MEM) ? load_val : ex_mem.result;

  // Loads are never forwarded from EX/MEM: their data is not ready until
  // the end of MEM. The load-use stall guarantees no consumer needs it.
  assign fwd_val = ex_mem.result;

  // --------------------------------------------------------- MEM/WB reg
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb <= '0;
`ifndef BUG_WAIT_NO_BUBBLE
    end else if (mem_wait) begin
      mem_wb.valid <= 1'b0;
`endif
    end else begin
      mem_wb.valid     <= ex_mem.valid;
      mem_wb.pc        <= ex_mem.pc;
      mem_wb.insn      <= ex_mem.insn;
      mem_wb.rf_we     <= ex_mem.rf_we;
      mem_wb.rd        <= ex_mem.rd;
      mem_wb.rd_val    <= rd_val;
      mem_wb.rs1       <= ex_mem.rs1;
      mem_wb.rs2       <= ex_mem.rs2;
      mem_wb.rs1_val   <= ex_mem.rs1_val;
      mem_wb.rs2_val   <= ex_mem.rs2_val;
      mem_wb.next_pc   <= ex_mem.next_pc;
      mem_wb.mem_addr  <= dmem_req ? dmem_addr : 32'd0;
      mem_wb.mem_rmask <= (dmem_req && !dmem_we) ? lane_mask : 4'b0000;
      mem_wb.mem_wmask <= dmem_wmask;
      mem_wb.mem_rdata <= (dmem_req && !dmem_we) ? dmem_rdata : 32'd0;
      mem_wb.mem_wdata <= dmem_we ? dmem_wdata : 32'd0;
      mem_wb.trap      <= ex_mem.trap;
      mem_wb.cause     <= ex_mem.cause;
    end
  end

endmodule
