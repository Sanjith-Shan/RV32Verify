// rv32_pkg.sv
// Shared types for the RV32I 5-stage pipeline: opcodes, decoded control word,
// and the four pipeline register payloads (IF/ID, ID/EX, EX/MEM, MEM/WB).
//
// Every pipeline register carries the fields the RVFI retirement port needs
// (pc, instruction word, operand values, memory masks), so the checker sees
// exactly what each instruction did when it leaves WB.

package rv32_pkg;

  // ---------------------------------------------------------------- opcodes
  localparam logic [6:0] OPC_LUI    = 7'b0110111;
  localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
  localparam logic [6:0] OPC_JAL    = 7'b1101111;
  localparam logic [6:0] OPC_JALR   = 7'b1100111;
  localparam logic [6:0] OPC_BRANCH = 7'b1100011;
  localparam logic [6:0] OPC_LOAD   = 7'b0000011;
  localparam logic [6:0] OPC_STORE  = 7'b0100011;
  localparam logic [6:0] OPC_OPIMM  = 7'b0010011;
  localparam logic [6:0] OPC_OP     = 7'b0110011;
  localparam logic [6:0] OPC_FENCE  = 7'b0001111;
  localparam logic [6:0] OPC_SYSTEM = 7'b1110011;

  // ------------------------------------------------------------- ALU ops
  typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_SLL  = 4'd2,
    ALU_SLT  = 4'd3,
    ALU_SLTU = 4'd4,
    ALU_XOR  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_OR   = 4'd8,
    ALU_AND  = 4'd9,
    ALU_PASS_B = 4'd10   // LUI: result = immediate
  } alu_op_e;

  // operand A source
  typedef enum logic [1:0] {
    A_RS1  = 2'd0,
    A_PC   = 2'd1,
    A_ZERO = 2'd2
  } a_sel_e;

  // writeback source
  typedef enum logic [1:0] {
    WB_ALU = 2'd0,
    WB_PC4 = 2'd1,   // JAL / JALR link value
    WB_MEM = 2'd2    // load data
  } wb_sel_e;

  // forwarding source, as chosen by the hazard unit for each EX operand
  typedef enum logic [1:0] {
    FWD_NONE  = 2'd0,  // value read from the register file in ID
    FWD_EXMEM = 2'd1,  // result of the instruction one ahead (in MEM)
    FWD_MEMWB = 2'd2   // result of the instruction two ahead (in WB)
  } fwd_sel_e;

  // trap causes (mcause encoding, used by the RVFI trap report and the ISS)
  localparam logic [3:0] CAUSE_INSN_MISALIGNED  = 4'd0;
  localparam logic [3:0] CAUSE_ILLEGAL_INSN     = 4'd2;
  localparam logic [3:0] CAUSE_BREAKPOINT       = 4'd3;
  localparam logic [3:0] CAUSE_LOAD_MISALIGNED  = 4'd4;
  localparam logic [3:0] CAUSE_STORE_MISALIGNED = 4'd6;
  localparam logic [3:0] CAUSE_ECALL_M          = 4'd11;

  // ------------------------------------------------------ decoded control
  typedef struct packed {
    logic        rf_we;      // instruction writes rd (rd may still be x0)
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic        use_rs1;    // rs1 is a true source operand
    logic        use_rs2;    // rs2 is a true source operand
    alu_op_e     alu_op;
    a_sel_e      a_sel;
    logic        b_imm;      // operand B is the immediate (else rs2)
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        is_load;
    logic        is_store;
    logic        is_fencei;  // refetch everything younger
    logic [2:0]  funct3;     // branch condition / memory access size
    wb_sel_e     wb_sel;
    logic        trap;       // decode-time exception (illegal, ecall, ebreak)
    logic [3:0]  cause;
    logic [31:0] imm;
  } ctrl_t;

  // ------------------------------------------------- pipeline registers
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
    ctrl_t       ctrl;
    logic [31:0] rs1_val;    // operand values; refreshed while EX is stalled
    logic [31:0] rs2_val;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
    logic        rf_we;
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [31:0] rs1_val;    // operand values actually used (post-forwarding)
    logic [31:0] rs2_val;
    logic [31:0] result;     // ALU result, link value, or memory address
    logic        is_load;
    logic        is_store;
    logic [2:0]  funct3;
    wb_sel_e     wb_sel;
    logic [31:0] next_pc;
    logic        trap;
    logic [3:0]  cause;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] insn;
    logic        rf_we;
    logic [4:0]  rd;
    logic [31:0] rd_val;     // final value written to rd
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [31:0] rs1_val;
    logic [31:0] rs2_val;
    logic [31:0] next_pc;
    logic [31:0] mem_addr;   // word-aligned bus address
    logic [3:0]  mem_rmask;
    logic [3:0]  mem_wmask;
    logic [31:0] mem_rdata;  // raw bus word
    logic [31:0] mem_wdata;  // bus word, data already in its byte lanes
    logic        trap;
    logic [3:0]  cause;
  } mem_wb_t;

endpackage
