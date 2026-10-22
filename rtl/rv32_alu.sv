// rv32_alu.sv
// Purely combinational RV32I integer ALU.

module rv32_alu
  import rv32_pkg::*;
(
  input  alu_op_e     op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);

  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD:    y = a + b;
      ALU_SUB:    y = a - b;
      ALU_SLL:    y = a << shamt;
`ifdef BUG_SLT_UNSIGNED
      ALU_SLT:    y = {31'b0, a < b};                  // injected: signedness lost
`else
      ALU_SLT:    y = {31'b0, $signed(a) < $signed(b)};
`endif
      ALU_SLTU:   y = {31'b0, a < b};
      ALU_XOR:    y = a ^ b;
      ALU_SRL:    y = a >> shamt;
`ifdef BUG_SRA_LOGICAL
      ALU_SRA:    y = a >> shamt;                       // injected: sign fill lost
`else
      ALU_SRA:    y = $unsigned($signed(a) >>> shamt);
`endif
      ALU_OR:     y = a | b;
      ALU_AND:    y = a & b;
      ALU_PASS_B: y = b;
      default:    y = 32'b0;
    endcase
  end

endmodule
