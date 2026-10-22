// rv32_decode.sv
// ID stage (decode / issue): decodes the IF/ID instruction, reads the
// register file, and loads the ID/EX pipeline register.
//
// ID/EX update priority:
//   hold    (data-memory wait)  operands are refreshed with the forwarded
//                               values so a producer that retires during
//                               the wait is not lost
//   bubble  (load-use stall, redirect, trap in MEM)
//   advance

module rv32_decode
  import rv32_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  if_id_t      if_id,

  // register file read ports
  output logic [4:0]  rf_raddr1,
  output logic [4:0]  rf_raddr2,
  input  logic [31:0] rf_rdata1,
  input  logic [31:0] rf_rdata2,

  input  logic        hold,          // EX stalled by data-memory wait
  input  logic        bubble,        // insert a bubble into EX
  input  logic [31:0] ex_rs1_fwd,    // forwarded operand values seen in EX now
  input  logic [31:0] ex_rs2_fwd,

  output ctrl_t       id_ctrl,       // decoded control of the IF/ID instruction
  output id_ex_t      id_ex
);

  rv32_decoder u_decoder (
    .insn (if_id.insn),
    .ctrl (id_ctrl)
  );

  assign rf_raddr1 = id_ctrl.rs1;
  assign rf_raddr2 = id_ctrl.rs2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex <= '0;
    end else if (hold) begin
`ifndef BUG_STALL_NO_REFRESH
      id_ex.rs1_val <= ex_rs1_fwd;
      id_ex.rs2_val <= ex_rs2_fwd;
`endif
    end else if (bubble) begin
      id_ex.valid <= 1'b0;
    end else begin
      id_ex.valid   <= if_id.valid;
      id_ex.pc      <= if_id.pc;
      id_ex.insn    <= if_id.insn;
      id_ex.ctrl    <= id_ctrl;
      id_ex.rs1_val <= rf_rdata1;
      id_ex.rs2_val <= rf_rdata2;
    end
  end

endmodule
