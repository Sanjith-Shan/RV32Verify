// rv32_decoder.sv
// Combinational RV32I decoder: instruction word -> control word.
// Anything outside RV32I (plus FENCE / FENCE.I / ECALL / EBREAK) is flagged
// illegal. Legality is checked on every field the base ISA fixes
// (funct3, funct7, the shift-immediate high bits, the SYSTEM encodings).

module rv32_decoder
  import rv32_pkg::*;
(
  input  logic [31:0] insn,
  output ctrl_t       ctrl
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  assign opcode = insn[6:0];
  assign funct3 = insn[14:12];
  assign funct7 = insn[31:25];

  assign imm_i = {{20{insn[31]}}, insn[31:20]};
  assign imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
`ifdef BUG_BRANCH_OFFSET
  assign imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0} + 32'd4; // injected
`else
  assign imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
`endif
  assign imm_u = {insn[31:12], 12'b0};
  assign imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};

  always_comb begin
    ctrl          = '0;
    ctrl.rd       = insn[11:7];
    ctrl.rs1      = insn[19:15];
    ctrl.rs2      = insn[24:20];
    ctrl.funct3   = funct3;
    ctrl.alu_op   = ALU_ADD;
    ctrl.a_sel    = A_RS1;
    ctrl.wb_sel   = WB_ALU;

    unique case (opcode)
      OPC_LUI: begin
        ctrl.rf_we  = 1'b1;
        ctrl.a_sel  = A_ZERO;
        ctrl.b_imm  = 1'b1;
        ctrl.alu_op = ALU_PASS_B;
        ctrl.imm    = imm_u;
      end

      OPC_AUIPC: begin
        ctrl.rf_we  = 1'b1;
        ctrl.a_sel  = A_PC;
        ctrl.b_imm  = 1'b1;
        ctrl.imm    = imm_u;
      end

      OPC_JAL: begin
        ctrl.rf_we  = 1'b1;
        ctrl.is_jal = 1'b1;
        ctrl.wb_sel = WB_PC4;
        ctrl.imm    = imm_j;
      end

      OPC_JALR: begin
        ctrl.rf_we   = 1'b1;
        ctrl.is_jalr = 1'b1;
        ctrl.use_rs1 = 1'b1;
        ctrl.wb_sel  = WB_PC4;
        ctrl.b_imm   = 1'b1;
        ctrl.imm     = imm_i;
        if (funct3 != 3'b000) ctrl.trap = 1'b1;
      end

      OPC_BRANCH: begin
        ctrl.is_branch = 1'b1;
        ctrl.use_rs1   = 1'b1;
        ctrl.use_rs2   = 1'b1;
        ctrl.imm       = imm_b;
        if (funct3 == 3'b010 || funct3 == 3'b011) ctrl.trap = 1'b1;
      end

      OPC_LOAD: begin
        ctrl.rf_we   = 1'b1;
        ctrl.is_load = 1'b1;
        ctrl.use_rs1 = 1'b1;
        ctrl.b_imm   = 1'b1;
        ctrl.wb_sel  = WB_MEM;
        ctrl.imm     = imm_i;
        // legal: LB LH LW LBU LHU
        if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) ctrl.trap = 1'b1;
      end

      OPC_STORE: begin
        ctrl.is_store = 1'b1;
        ctrl.use_rs1  = 1'b1;
        ctrl.use_rs2  = 1'b1;
        ctrl.b_imm    = 1'b1;
        ctrl.imm      = imm_s;
        if (funct3[2] || funct3[1:0] == 2'b11) ctrl.trap = 1'b1;
      end

      OPC_OPIMM: begin
        ctrl.rf_we   = 1'b1;
        ctrl.use_rs1 = 1'b1;
        ctrl.b_imm   = 1'b1;
        ctrl.imm     = imm_i;
        unique case (funct3)
`ifdef BUG_ADDI_AS_SUB
          3'b000: ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD;           // injected
`else
          3'b000: ctrl.alu_op = ALU_ADD;
`endif
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: begin
            ctrl.alu_op = ALU_SLL;
            if (funct7 != 7'b0000000) ctrl.trap = 1'b1;
          end
          3'b101: begin
`ifdef BUG_SRAI_AS_SRLI
            ctrl.alu_op = ALU_SRL;                                       // injected
`else
            ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
`endif
            if ({funct7[6], funct7[4:0]} != 6'b0) ctrl.trap = 1'b1;
          end
          default: ;
        endcase
      end

      OPC_OP: begin
        ctrl.rf_we   = 1'b1;
        ctrl.use_rs1 = 1'b1;
        ctrl.use_rs2 = 1'b1;
        unique case (funct3)
          3'b000: ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
          3'b001: ctrl.alu_op = ALU_SLL;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          default: ;
        endcase
        // funct7 must be 0, or 0100000 for SUB / SRA only
        if (!(funct7 == 7'b0000000 ||
              (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101))))
          ctrl.trap = 1'b1;
      end

      OPC_FENCE: begin
        // FENCE is a no-op on this in-order, single-hart core with one memory
        // port. FENCE.I flushes and refetches everything younger.
        if (funct3 == 3'b001)      ctrl.is_fencei = 1'b1;
        else if (funct3 != 3'b000) ctrl.trap = 1'b1;
      end

      OPC_SYSTEM: begin
        if (insn == 32'h0000_0073)      begin ctrl.trap = 1'b1; ctrl.cause = CAUSE_ECALL_M;    end
        else if (insn == 32'h0010_0073) begin ctrl.trap = 1'b1; ctrl.cause = CAUSE_BREAKPOINT; end
        else                            ctrl.trap = 1'b1;   // CSRs / MRET / WFI: not in M1
      end

      default: ctrl.trap = 1'b1;
    endcase

    // Anything flagged above without a specific cause is an illegal instruction.
    if (ctrl.trap && ctrl.cause == 4'd0)
      ctrl.cause = CAUSE_ILLEGAL_INSN;

    // A trapping instruction has no architectural side effects and reads
    // no operands.
    if (ctrl.trap) begin
      ctrl.use_rs1   = 1'b0;
      ctrl.use_rs2   = 1'b0;
      ctrl.rf_we     = 1'b0;
      ctrl.is_load   = 1'b0;
      ctrl.is_store  = 1'b0;
      ctrl.is_branch = 1'b0;
      ctrl.is_jal    = 1'b0;
      ctrl.is_jalr   = 1'b0;
      ctrl.is_fencei = 1'b0;
    end

    // Writes to x0 are discarded; dropping rf_we here keeps x0 out of the
    // forwarding network and the load-use check.
    if (ctrl.rd == 5'd0) ctrl.rf_we = 1'b0;
  end

endmodule
