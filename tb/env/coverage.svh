// coverage.svh
// Functional coverage model. Two views:
//
//   architectural  sampled on every retirement from the RVFI transaction:
//                  opcode x operand value classes, immediates, branch
//                  direction and compare relation, load/store byte offsets
//                  and sign extension, x0 destinations, traps, register
//                  dependency distance per consumer
//   pipeline       sampled every cycle from the white-box probe: forwarding
//                  source per operand and consumer, write-through bypass,
//                  load-use stalls, memory wait states, redirects, and the
//                  combinations of hazards that interact
//
// Every bin maps to a line in docs/VERIFICATION_PLAN.md. Verilator writes
// per-bin hit counts to coverage.dat; scripts/cov_report.py merges runs and
// lists the holes.

typedef enum bit [5:0] {
  OP_LUI, OP_AUIPC, OP_JAL, OP_JALR,
  OP_BEQ, OP_BNE, OP_BLT, OP_BGE, OP_BLTU, OP_BGEU,
  OP_LB, OP_LH, OP_LW, OP_LBU, OP_LHU, OP_SB, OP_SH, OP_SW,
  OP_ADDI, OP_SLTI, OP_SLTIU, OP_XORI, OP_ORI, OP_ANDI, OP_SLLI, OP_SRLI, OP_SRAI,
  OP_ADD, OP_SUB, OP_SLL, OP_SLT, OP_SLTU, OP_XOR, OP_SRL, OP_SRA, OP_OR, OP_AND,
  OP_FENCE, OP_FENCE_I, OP_ECALL, OP_EBREAK, OP_ILLEGAL
} rv_op_e;

typedef enum bit [2:0] {V_ZERO, V_ONE, V_ALL1, V_MAXPOS, V_MINNEG, V_POS, V_NEG} val_class_e;
typedef enum bit [2:0] {I_ZERO, I_ONE, I_MINUS1, I_MAX, I_MIN, I_POS, I_NEG} imm_class_e;
typedef enum bit [1:0] {SH_ZERO, SH_ONE, SH_MAX, SH_OTHER} shamt_class_e;
// relation of two compare operands, signed and unsigned views
typedef enum bit [2:0] {REL_EQ, REL_LT_BOTH, REL_LT_SIGNED_ONLY, REL_LT_UNSIGNED_ONLY, REL_GT_BOTH} rel_e;
typedef enum bit [2:0] {C_ALU_R, C_ALU_I, C_LOAD, C_STORE, C_BRANCH, C_JALR, C_OTHER} cons_e;
typedef enum bit [2:0] {D_1 = 1, D_2 = 2, D_3 = 3, D_4 = 4, D_FAR = 5} dist_e;

class coverage extends rvfi_subscriber;
  virtual pipe_probe_if probe;

  // ------------------------------------------------- sampled variables
  rv_op_e       op;
  val_class_e   rs1c, rs2c;
  imm_class_e   immc;
  shamt_class_e shc;
  rel_e         rel;
  bit           taken;
  bit [1:0]     off;
  bit           msb;
  bit [3:0]     cause;
  cons_e        cons;
  dist_e        d1, d2;
  bit           x0_dest, jalr_odd, back_to_back_taken, trapped;

  // pipeline
  bit [1:0]     fwd_a, fwd_b;
  cons_e        ex_cons;
  bit           ex_a, ex_b;
  bit           shadow_a, shadow_b, bypass_rs1, bypass_rs2;
  bit [1:0]     load_use_kind;        // 1 rs1, 2 rs2, 3 both
  bit [1:0]     dmem_wait_kind;       // 1 load, 2 store
  bit           imem_wait;
  bit [2:0]     redirect_kind;        // 1 branch, 2 jal, 3 jalr, 4 fence.i
  bit           c_redirect_deferred, c_loaduse_during_wait, c_trap_kills_redirect,
                c_trap_kills_loaduse, c_redirect_during_imem_wait, c_stall_then_forward,
                c_wait_refresh_operand, c_back_to_back_redirect;

  // history for distances and sequences
  longint unsigned retire_idx = 0;
  longint unsigned last_write [32];
  bit              prev_taken = 0;
  int unsigned     cycles_since_load_use = 99;
  int unsigned     cycles_since_redirect = 99;

  // ------------------------------------------------------- covergroups
  covergroup cg_alu_r;
    cp_op:  coverpoint op { bins ADD = {OP_ADD}; bins SUB = {OP_SUB}; bins SLL = {OP_SLL}; bins SLT = {OP_SLT}; bins SLTU = {OP_SLTU}; bins XOR = {OP_XOR}; bins SRL = {OP_SRL}; bins SRA = {OP_SRA}; bins OR = {OP_OR}; bins AND = {OP_AND}; }
    cp_rs1: coverpoint rs1c;
    cp_rs2: coverpoint rs2c;
    x_op_rs1_rs2: cross cp_op, cp_rs1, cp_rs2;
  endgroup

  covergroup cg_alu_i;
    cp_op:  coverpoint op { bins ADDI = {OP_ADDI}; bins SLTI = {OP_SLTI}; bins SLTIU = {OP_SLTIU}; bins XORI = {OP_XORI}; bins ORI = {OP_ORI}; bins ANDI = {OP_ANDI}; }
    cp_rs1: coverpoint rs1c;
    cp_imm: coverpoint immc;
    x_op_rs1_imm: cross cp_op, cp_rs1, cp_imm;
  endgroup

  covergroup cg_shift;
    cp_op:  coverpoint op { bins SLLI = {OP_SLLI}; bins SRLI = {OP_SRLI}; bins SRAI = {OP_SRAI}; bins SLL = {OP_SLL}; bins SRL = {OP_SRL}; bins SRA = {OP_SRA}; }
    cp_rs1: coverpoint rs1c;
    cp_sh:  coverpoint shc;
    x_op_rs1_sh: cross cp_op, cp_rs1, cp_sh;
  endgroup

  covergroup cg_branch;
    cp_op:    coverpoint op { bins BEQ = {OP_BEQ}; bins BNE = {OP_BNE}; bins BLT = {OP_BLT}; bins BGE = {OP_BGE}; bins BLTU = {OP_BLTU}; bins BGEU = {OP_BGEU}; }
    cp_taken: coverpoint taken;
    cp_rel:   coverpoint rel;
    x_op_taken: cross cp_op, cp_taken;
    x_op_rel:   cross cp_op, cp_rel;
  endgroup

  covergroup cg_load;
    cp_op:  coverpoint op { bins LB = {OP_LB}; bins LH = {OP_LH}; bins LW = {OP_LW}; bins LBU = {OP_LBU}; bins LHU = {OP_LHU}; }
    cp_off: coverpoint off;
    cp_msb: coverpoint msb;   // sign bit of the loaded byte / half / word
    x_op_off_msb: cross cp_op, cp_off, cp_msb {
      ignore_bins ign_half_odd = x_op_off_msb with ((cp_op == OP_LH || cp_op == OP_LHU) && cp_off[0] == 1'b1);
      ignore_bins ign_word_off = x_op_off_msb with (cp_op == OP_LW && cp_off != 2'd0);
    }
  endgroup

  covergroup cg_store;
    cp_op:  coverpoint op { bins SB = {OP_SB}; bins SH = {OP_SH}; bins SW = {OP_SW}; }
    cp_off: coverpoint off;
    x_op_off: cross cp_op, cp_off {
      ignore_bins ign_half_odd = x_op_off with (cp_op == OP_SH && cp_off[0] == 1'b1);
      ignore_bins ign_word_off = x_op_off with (cp_op == OP_SW && cp_off != 2'd0);
    }
  endgroup

  covergroup cg_misc;
    cp_op:   coverpoint op;                            // every instruction retired
    cp_x0:   coverpoint op iff (x0_dest) {             // result discarded into x0
      bins alu_r = {[OP_ADD:OP_AND]};
      bins alu_i = {[OP_ADDI:OP_SRAI]};
      bins load  = {[OP_LB:OP_LHU]};
      bins jump  = {OP_JAL, OP_JALR};
      bins upper = {OP_LUI, OP_AUIPC};
    }
    cp_trap: coverpoint cause iff (trapped) {
      bins insn_misaligned  = {0};
      bins illegal          = {2};
      bins breakpoint       = {3};
      bins load_misaligned  = {4};
      bins store_misaligned = {6};
      bins ecall            = {11};
    }
    cp_jalr_odd:  coverpoint jalr_odd iff (op == OP_JALR) { bins lsb_cleared = {1}; bins even = {0}; }
    cp_b2b_taken: coverpoint back_to_back_taken { bins hit = {1}; }
  endgroup

  // register dependency distance seen at retirement, per consumer
  covergroup cg_dep;
    cp_cons: coverpoint cons { bins alu_r = {C_ALU_R}; bins alu_i = {C_ALU_I}; bins load = {C_LOAD}; bins store = {C_STORE}; bins branch = {C_BRANCH}; bins jalr = {C_JALR}; }
    cp_d1:   coverpoint d1;
    cp_d2:   coverpoint d2;
    x_rs1: cross cp_cons, cp_d1;
    x_rs2: cross cp_cons, cp_d2 {
      ignore_bins ign_no_rs2 = x_rs2 with (cp_cons inside {C_ALU_I, C_LOAD, C_JALR});
    }
  endgroup

  covergroup cg_pipe;
    cp_fwd_a: coverpoint fwd_a iff (ex_a) { bins none = {0}; bins exmem = {1}; bins memwb = {2}; }
    cp_fwd_b: coverpoint fwd_b iff (ex_b) { bins none = {0}; bins exmem = {1}; bins memwb = {2}; }
    x_fwd_ab: cross cp_fwd_a, cp_fwd_b iff (ex_a && ex_b);
    cp_cons_a: coverpoint ex_cons iff (ex_a) { bins alu_r = {C_ALU_R}; bins alu_i = {C_ALU_I}; bins load = {C_LOAD}; bins store = {C_STORE}; bins branch = {C_BRANCH}; bins jalr = {C_JALR}; }
    cp_cons_b: coverpoint ex_cons iff (ex_b) { bins alu_r = {C_ALU_R}; bins store = {C_STORE}; bins branch = {C_BRANCH}; }
    x_cons_fwd_a: cross cp_cons_a, cp_fwd_a iff (ex_a);
    x_cons_fwd_b: cross cp_cons_b, cp_fwd_b iff (ex_b);
    cp_shadow:     coverpoint {shadow_a, shadow_b} { bins rs1 = {2'b10}; bins rs2 = {2'b01}; bins both = {2'b11}; }
    cp_bypass:     coverpoint {bypass_rs1, bypass_rs2} { bins rs1 = {2'b10}; bins rs2 = {2'b01}; bins both = {2'b11}; }
    cp_load_use:   coverpoint load_use_kind { bins rs1 = {1}; bins rs2 = {2}; bins both = {3}; }
    cp_dmem_wait:  coverpoint dmem_wait_kind { bins load = {1}; bins store = {2}; }
    cp_imem_wait:  coverpoint imem_wait { bins hit = {1}; }
    cp_redirect:   coverpoint redirect_kind { bins branch = {1}; bins jal = {2}; bins jalr = {3}; bins fence_i = {4}; }
    cp_redirect_deferred:        coverpoint c_redirect_deferred        { bins hit = {1}; }
    cp_loaduse_during_wait:      coverpoint c_loaduse_during_wait      { bins hit = {1}; }
    cp_trap_kills_redirect:      coverpoint c_trap_kills_redirect      { bins hit = {1}; }
    cp_trap_kills_loaduse:       coverpoint c_trap_kills_loaduse       { bins hit = {1}; }
    cp_redirect_during_imem_wait: coverpoint c_redirect_during_imem_wait { bins hit = {1}; }
    cp_stall_then_forward:       coverpoint c_stall_then_forward       { bins hit = {1}; }
    cp_wait_refresh_operand:     coverpoint c_wait_refresh_operand     { bins hit = {1}; }
    cp_back_to_back_redirect:    coverpoint c_back_to_back_redirect    { bins hit = {1}; }
  endgroup

  function new(virtual pipe_probe_if probe);
    this.probe = probe;
    cg_alu_r  = new;
    cg_alu_i  = new;
    cg_shift  = new;
    cg_branch = new;
    cg_load   = new;
    cg_store  = new;
    cg_misc   = new;
    cg_dep    = new;
    cg_pipe   = new;
    foreach (last_write[i]) last_write[i] = 0;
  endfunction

  // ---------------------------------------------------------- classifiers
  static function rv_op_e decode_op(bit [31:0] in);
    bit [2:0] f3 = in[14:12];
    bit [6:0] f7 = in[31:25];
    case (in[6:0])
      7'h37: return OP_LUI;
      7'h17: return OP_AUIPC;
      7'h6f: return OP_JAL;
      7'h67: return f3 == 0 ? OP_JALR : OP_ILLEGAL;
      7'h63: case (f3) 0: return OP_BEQ; 1: return OP_BNE; 4: return OP_BLT; 5: return OP_BGE;
                       6: return OP_BLTU; 7: return OP_BGEU; default: return OP_ILLEGAL; endcase
      7'h03: case (f3) 0: return OP_LB; 1: return OP_LH; 2: return OP_LW; 4: return OP_LBU;
                       5: return OP_LHU; default: return OP_ILLEGAL; endcase
      7'h23: case (f3) 0: return OP_SB; 1: return OP_SH; 2: return OP_SW; default: return OP_ILLEGAL; endcase
      7'h13: case (f3)
               0: return OP_ADDI; 2: return OP_SLTI; 3: return OP_SLTIU; 4: return OP_XORI;
               6: return OP_ORI;  7: return OP_ANDI;
               1: return f7 == 0 ? OP_SLLI : OP_ILLEGAL;
               default: return f7 == 0 ? OP_SRLI : f7 == 7'h20 ? OP_SRAI : OP_ILLEGAL;
             endcase
      7'h33: begin
        if (f7 == 7'h20) return f3 == 0 ? OP_SUB : f3 == 5 ? OP_SRA : OP_ILLEGAL;
        if (f7 != 0) return OP_ILLEGAL;
        case (f3) 0: return OP_ADD; 1: return OP_SLL; 2: return OP_SLT; 3: return OP_SLTU;
                  4: return OP_XOR; 5: return OP_SRL; 6: return OP_OR; default: return OP_AND; endcase
      end
      7'h0f: return f3 == 0 ? OP_FENCE : f3 == 1 ? OP_FENCE_I : OP_ILLEGAL;
      7'h73: return in == 32'h73 ? OP_ECALL : in == 32'h0010_0073 ? OP_EBREAK : OP_ILLEGAL;
      default: return OP_ILLEGAL;
    endcase
  endfunction

  static function val_class_e vclass(bit [31:0] v);
    if (v == 32'h0)          return V_ZERO;
    if (v == 32'h1)          return V_ONE;
    if (v == 32'hffff_ffff)  return V_ALL1;
    if (v == 32'h7fff_ffff)  return V_MAXPOS;
    if (v == 32'h8000_0000)  return V_MINNEG;
    return v[31] ? V_NEG : V_POS;
  endfunction

  static function imm_class_e iclass(bit [11:0] i);
    if (i == 12'h000) return I_ZERO;
    if (i == 12'h001) return I_ONE;
    if (i == 12'hfff) return I_MINUS1;
    if (i == 12'h7ff) return I_MAX;
    if (i == 12'h800) return I_MIN;
    return i[11] ? I_NEG : I_POS;
  endfunction

  static function shamt_class_e sclass(bit [4:0] s);
    return s == 0 ? SH_ZERO : s == 1 ? SH_ONE : s == 31 ? SH_MAX : SH_OTHER;
  endfunction

  static function rel_e relation(bit [31:0] a, bit [31:0] b);
    bit lts = $signed(a) < $signed(b);
    bit ltu = a < b;
    if (a == b) return REL_EQ;
    if (lts && ltu) return REL_LT_BOTH;
    if (lts) return REL_LT_SIGNED_ONLY;
    if (ltu) return REL_LT_UNSIGNED_ONLY;
    return REL_GT_BOTH;
  endfunction

  static function cons_e consumer(rv_op_e o);
    if (o inside {[OP_ADD:OP_AND]}) return C_ALU_R;
    if (o inside {[OP_ADDI:OP_SRAI]}) return C_ALU_I;
    if (o inside {[OP_LB:OP_LHU]}) return C_LOAD;
    if (o inside {[OP_SB:OP_SW]}) return C_STORE;
    if (o inside {[OP_BEQ:OP_BGEU]}) return C_BRANCH;
    if (o == OP_JALR) return C_JALR;
    return C_OTHER;
  endfunction

  function dist_e distance(bit [4:0] r);
    longint unsigned d;
    if (r == 0 || last_write[r] == 0) return D_FAR;
    d = retire_idx - last_write[r];
    return d >= 5 ? D_FAR : dist_e'(d);
  endfunction

  // ---------------------------------------------- architectural sampling
  virtual function void write(rvfi_txn t);
    retire_idx++;
    op       = decode_op(t.insn);
    cause    = t.trap ? t.cause : 4'd0;
    trapped  = t.trap;
    rs1c     = vclass(t.rs1_rdata);
    rs2c     = vclass(t.rs2_rdata);
    taken    = (t.pc_wdata != t.pc + 32'd4);
    x0_dest  = 1'b0;
    jalr_odd = 1'b0;

    if (!t.trap) begin
      if (op inside {[OP_ADD:OP_AND]}) cg_alu_r.sample();
      if (op inside {[OP_ADDI:OP_ANDI]}) begin
        immc = iclass(t.insn[31:20]);
        cg_alu_i.sample();
      end
      if (op inside {OP_SLLI, OP_SRLI, OP_SRAI, OP_SLL, OP_SRL, OP_SRA}) begin
        shc = sclass(op inside {OP_SLL, OP_SRL, OP_SRA} ? t.rs2_rdata[4:0] : t.insn[24:20]);
        cg_shift.sample();
      end
      if (op inside {[OP_BEQ:OP_BGEU]}) begin
        rel = relation(t.rs1_rdata, t.rs2_rdata);
        cg_branch.sample();
      end
      if (op inside {[OP_LB:OP_LHU]}) begin
        bit [31:0] ea = t.rs1_rdata + {{20{t.insn[31]}}, t.insn[31:20]};
        bit [31:0] sh = t.mem_rdata >> (8 * ea[1:0]);
        off = ea[1:0];
        msb = (op inside {OP_LB, OP_LBU}) ? sh[7] : (op inside {OP_LH, OP_LHU}) ? sh[15] : sh[31];
        cg_load.sample();
      end
      if (op inside {[OP_SB:OP_SW]}) begin
        bit [31:0] ea = t.rs1_rdata + {{20{t.insn[31]}}, t.insn[31:25], t.insn[11:7]};
        off = ea[1:0];
        cg_store.sample();
      end
      if (op == OP_JALR) jalr_odd = t.rs1_rdata[0] ^ t.insn[20];
      x0_dest = (t.insn[11:7] == 5'd0) &&
                (op inside {[OP_ADD:OP_AND], [OP_ADDI:OP_SRAI], [OP_LB:OP_LHU], OP_JAL, OP_JALR, OP_LUI, OP_AUIPC});

      cons = consumer(op);
      if (cons != C_OTHER) begin
        d1 = distance(t.rs1_addr);
        d2 = distance(t.rs2_addr);
        cg_dep.sample();
      end
    end

    back_to_back_taken = prev_taken && taken && !t.trap;
    cg_misc.sample();
    prev_taken = taken && !t.trap && (op inside {[OP_BEQ:OP_BGEU], OP_JAL, OP_JALR});

    if (t.rd_addr != 0) last_write[t.rd_addr] = retire_idx;
  endfunction

  // --------------------------------------------------- pipeline sampling
  task run_pipe();
    forever begin
      @(negedge probe.clk);
      #1;  // after the memory agent has driven this cycle's ready signals
      sample_pipe();
    end
  endtask

  function void sample_pipe();
    rv_op_e eop = decode_op(probe.ex_insn);
    bit [4:0] ers1 = probe.ex_rs1, ers2 = probe.ex_rs2;
    ex_cons = consumer(eop);
    ex_a  = probe.ex_valid && probe.ex_use_rs1 && ers1 != 0;
    ex_b  = probe.ex_valid && probe.ex_use_rs2 && ers2 != 0;
    fwd_a = probe.fwd_a;
    fwd_b = probe.fwd_b;
    // both older instructions write the source: the younger one must win
    shadow_a = ex_a && probe.mem_valid && probe.mem_rf_we && probe.mem_rd == ers1 &&
               probe.wb_valid && probe.wb_rf_we && probe.rf_waddr == ers1;
    shadow_b = ex_b && probe.mem_valid && probe.mem_rf_we && probe.mem_rd == ers2 &&
               probe.wb_valid && probe.wb_rf_we && probe.rf_waddr == ers2;
    bypass_rs1 = probe.id_valid && probe.rf_we && probe.id_use_rs1 && probe.id_rs1 == probe.rf_waddr && probe.id_rs1 != 0;
    bypass_rs2 = probe.id_valid && probe.rf_we && probe.id_use_rs2 && probe.id_rs2 == probe.rf_waddr && probe.id_rs2 != 0;
    load_use_kind = !probe.load_use ? 2'd0 :
                    {probe.id_use_rs2 && probe.id_rs2 == probe.ex_rd, probe.id_use_rs1 && probe.id_rs1 == probe.ex_rd};
    dmem_wait_kind = !probe.mem_wait ? 2'd0 : probe.mem_is_load ? 2'd1 : 2'd2;
    imem_wait = probe.imem_req && !probe.imem_ready;
    redirect_kind = 3'd0;
    if (probe.redirect) begin
      if (eop inside {[OP_BEQ:OP_BGEU]}) redirect_kind = 3'd1;
      else if (eop == OP_JAL)            redirect_kind = 3'd2;
      else if (eop == OP_JALR)           redirect_kind = 3'd3;
      else if (eop == OP_FENCE_I)        redirect_kind = 3'd4;
    end
    c_redirect_deferred         = probe.ex_redirect_req && probe.mem_wait;
    c_loaduse_during_wait       = probe.load_use && probe.mem_wait;
    c_trap_kills_redirect       = probe.mem_trap && probe.ex_redirect_req;
    c_trap_kills_loaduse        = probe.mem_trap && probe.load_use;
    c_redirect_during_imem_wait = probe.redirect && imem_wait;
    // load-use stall two cycles ago, the consumer now takes the load data from MEM/WB
    c_stall_then_forward        = cycles_since_load_use == 1 &&
                                  ((ex_a && fwd_a == 2'd2) || (ex_b && fwd_b == 2'd2));
    c_wait_refresh_operand      = probe.mem_wait && ((ex_a && fwd_a == 2'd2) || (ex_b && fwd_b == 2'd2));
    c_back_to_back_redirect     = probe.redirect && cycles_since_redirect == 3;
    cg_pipe.sample();

    if (probe.load_use && !probe.mem_wait) cycles_since_load_use = 0;
    else if (cycles_since_load_use < 99 && !probe.mem_wait) cycles_since_load_use++;
    if (probe.redirect) cycles_since_redirect = 1;
    else if (cycles_since_redirect < 99) cycles_since_redirect++;
  endfunction

  function void report(bit quiet);
    if (quiet) return;
    $display("[cov] alu_r %5.1f%%  alu_i %5.1f%%  shift %5.1f%%  branch %5.1f%%  load %5.1f%%  store %5.1f%%",
             cg_alu_r.get_coverage(), cg_alu_i.get_coverage(), cg_shift.get_coverage(),
             cg_branch.get_coverage(), cg_load.get_coverage(), cg_store.get_coverage());
    $display("[cov] misc %5.1f%%  dep %5.1f%%  pipe %5.1f%%",
             cg_misc.get_coverage(), cg_dep.get_coverage(), cg_pipe.get_coverage());
  endfunction
endclass
