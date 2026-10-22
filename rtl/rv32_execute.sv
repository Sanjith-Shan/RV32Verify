// rv32_execute.sv
// EX stage: operand forwarding muxes, ALU, branch resolution, jump target
// and memory address generation, misalignment checks, EX/MEM register.
//
// Branches and jumps resolve here. A taken branch / JAL / JALR / FENCE.I
// raises redirect_req; the hazard unit decides whether it takes effect this
// cycle (it does not while MEM is waiting on data memory or trapping).

module rv32_execute
  import rv32_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  id_ex_t      id_ex,

  // forwarding
  input  fwd_sel_e    fwd_a,
  input  fwd_sel_e    fwd_b,
  input  logic [31:0] exmem_fwd_val,
  input  logic [31:0] memwb_fwd_val,
  output logic [31:0] rs1_fwd,
  output logic [31:0] rs2_fwd,

  // control flow
  output logic        redirect_req,
  output logic [31:0] redirect_pc,

  input  logic        hold,          // data-memory wait: keep EX/MEM
  input  logic        bubble,        // trap in MEM: kill the EX instruction

  output ex_mem_t     ex_mem
);

  ctrl_t       c;
  logic [31:0] op_a, op_b, alu_y;
  logic [31:0] pc4, target, next_pc, result;
  logic        cond, taken, trap;
  logic [3:0]  cause;
  logic        misaligned_mem, misaligned_target;

  assign c   = id_ex.ctrl;
  assign pc4 = id_ex.pc + 32'd4;

  // ---------------------------------------------------------- forwarding
  always_comb begin
    unique case (fwd_a)
      FWD_EXMEM: rs1_fwd = exmem_fwd_val;
      FWD_MEMWB: rs1_fwd = memwb_fwd_val;
      default:   rs1_fwd = id_ex.rs1_val;
    endcase
    unique case (fwd_b)
      FWD_EXMEM: rs2_fwd = exmem_fwd_val;
      FWD_MEMWB: rs2_fwd = memwb_fwd_val;
      default:   rs2_fwd = id_ex.rs2_val;
    endcase
  end

  // ---------------------------------------------------------------- ALU
  always_comb begin
    unique case (c.a_sel)
      A_PC:    op_a = id_ex.pc;
      A_ZERO:  op_a = 32'b0;
      default: op_a = rs1_fwd;
    endcase
    op_b = c.b_imm ? c.imm : rs2_fwd;
  end

  rv32_alu u_alu (
    .op (c.alu_op),
    .a  (op_a),
    .b  (op_b),
    .y  (alu_y)
  );

  // ------------------------------------------------------------- branch
  always_comb begin
    unique case (c.funct3)
      3'b000:  cond = (rs1_fwd == rs2_fwd);                       // BEQ
      3'b001:  cond = (rs1_fwd != rs2_fwd);                       // BNE
      3'b100:  cond = ($signed(rs1_fwd) <  $signed(rs2_fwd));     // BLT
      3'b101:  cond = ($signed(rs1_fwd) >= $signed(rs2_fwd));     // BGE
`ifdef BUG_BLTU_SIGNED
      3'b110:  cond = ($signed(rs1_fwd) <  $signed(rs2_fwd));     // injected
`else
      3'b110:  cond = (rs1_fwd <  rs2_fwd);                       // BLTU
`endif
      3'b111:  cond = (rs1_fwd >= rs2_fwd);                       // BGEU
      default: cond = 1'b0;
    endcase
  end

`ifdef BUG_JALR_NO_CLEAR_LSB
  assign target = c.is_jalr ? (rs1_fwd + c.imm) : (id_ex.pc + c.imm);   // injected
`else
  assign target = c.is_jalr ? ((rs1_fwd + c.imm) & ~32'd1) : (id_ex.pc + c.imm);
`endif
  assign taken  = c.is_jal || c.is_jalr || (c.is_branch && cond);
  assign next_pc = taken ? target : pc4;

  // ---------------------------------------------------- exceptions in EX
  // No compressed extension: a taken control transfer must land on a
  // 4-byte boundary. Loads and stores must be naturally aligned.
  assign misaligned_target = taken && (target[1:0] != 2'b00);
  always_comb begin
    misaligned_mem = 1'b0;
    if (c.is_load || c.is_store) begin
      unique case (c.funct3[1:0])
        2'b00:   misaligned_mem = 1'b0;               // byte
        2'b01:   misaligned_mem = alu_y[0];           // half
        default: misaligned_mem = (alu_y[1:0] != 2'b00); // word
      endcase
    end
  end

  always_comb begin
    trap  = c.trap;
    cause = c.cause;
    if (!c.trap) begin
      if (misaligned_target) begin
        trap  = 1'b1;
        cause = CAUSE_INSN_MISALIGNED;
      end else if (misaligned_mem) begin
        trap  = 1'b1;
        cause = c.is_load ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED;
      end
    end
  end

`ifdef BUG_FENCEI_NO_FLUSH
  assign redirect_req = id_ex.valid && !trap && taken;                  // injected
`else
  assign redirect_req = id_ex.valid && !trap && (taken || c.is_fencei);
`endif
  assign redirect_pc  = taken ? target : pc4;

  assign result = (c.wb_sel == WB_PC4) ? pc4 : alu_y;

  // --------------------------------------------------------- EX/MEM reg
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem <= '0;
    end else if (hold) begin
      // keep
    end else if (bubble) begin
      ex_mem.valid <= 1'b0;
    end else begin
      ex_mem.valid    <= id_ex.valid;
      ex_mem.pc       <= id_ex.pc;
      ex_mem.insn     <= id_ex.insn;
      ex_mem.rf_we    <= c.rf_we && !trap;
      ex_mem.rd       <= c.rd;
      ex_mem.rs1      <= c.use_rs1 ? c.rs1 : 5'd0;
      ex_mem.rs2      <= c.use_rs2 ? c.rs2 : 5'd0;
      ex_mem.rs1_val  <= c.use_rs1 ? rs1_fwd : 32'd0;
      ex_mem.rs2_val  <= c.use_rs2 ? rs2_fwd : 32'd0;
      ex_mem.result   <= result;
      ex_mem.is_load  <= c.is_load && !trap;
      ex_mem.is_store <= c.is_store && !trap;
      ex_mem.funct3   <= c.funct3;
      ex_mem.wb_sel   <= c.wb_sel;
      ex_mem.next_pc  <= trap ? 32'd0 : next_pc;
      ex_mem.trap     <= trap;
      ex_mem.cause    <= cause;
    end
  end

endmodule
