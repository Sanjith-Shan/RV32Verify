// rv32_fetch.sv
// IF stage: program counter, next-PC selection, IF/ID pipeline register.
//
// Static not-taken prediction: fetch always proceeds at pc+4. A taken branch,
// jump, or FENCE.I resolved in EX redirects the PC and kills the instruction
// sitting in IF/ID (the hazard unit kills the one in ID/EX).
//
// Instruction memory is a combinational-read port with a ready handshake.
// imem_ready = 0 inserts a bubble into ID; the PC holds.

module rv32_fetch
  import rv32_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h8000_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        stall,        // hold PC and IF/ID (load-use or data-memory wait)
  input  logic        redirect,     // taken branch / jump / FENCE.I from EX
  input  logic [31:0] redirect_pc,
  input  logic        halt,         // trap reached MEM: stop fetching for good

  output logic        imem_req,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,
  input  logic        imem_ready,

  output if_id_t      if_id,
  output logic [31:0] pc,
  output logic        halted
);

  assign imem_req  = !halted;
  assign imem_addr = pc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc          <= RESET_PC;
      halted      <= 1'b0;
      if_id       <= '0;
    end else if (halt) begin
      halted      <= 1'b1;
      if_id.valid <= 1'b0;
    end else if (redirect) begin
      pc          <= redirect_pc;
      if_id.valid <= 1'b0;
    end else if (!stall) begin
      if (imem_ready && !halted) begin
        if_id.valid <= 1'b1;
        if_id.pc    <= pc;
        if_id.insn  <= imem_rdata;
        pc          <= pc + 32'd4;
      end else begin
        if_id.valid <= 1'b0;
      end
    end
  end

endmodule
