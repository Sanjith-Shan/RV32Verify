// rv32_core_sva.sv
// Pipeline invariants as SystemVerilog assertions, bound into rv32_core.
//
// The scoreboard proves that what retires is right. These assertions check
// how the pipeline gets there, at the cycle and the stage where a rule breaks,
// which is often hundreds of cycles before a wrong value reaches retirement.
// Several of them check properties the scoreboard cannot see at all
// (spurious stalls, operand refresh during a wait, forwarding priority).
//
// Hazard conditions are re-derived here from the raw instruction words, not
// from the decoder's control signals, so a decoder or hazard-unit mistake does
// not hide by being restated.
//
// Every failure message starts with "SVA <name>" so the regression can tell
// which checker fired.

module rv32_core_sva
  import rv32_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input if_id_t      if_id,
  input id_ex_t      id_ex,
  input ex_mem_t     ex_mem,
  input mem_wb_t     mem_wb,
  input logic [31:0] pc,
  input logic        halted,
  input logic        load_use,
  input logic        stall_if,
  input logic        redirect,
  input logic        halt,
  input logic        hold_ex,
  input logic        mem_wait,
  input logic        mem_trap,
  input logic        ex_redirect_req,
  input fwd_sel_e    fwd_a,
  input fwd_sel_e    fwd_b,
  input logic [31:0] rs1_fwd,
  input logic [31:0] rs2_fwd,
  input logic [4:0]  rf_raddr1,
  input logic [4:0]  rf_raddr2,
  input logic [31:0] rf_rdata1,
  input logic [31:0] rf_rdata2,
  input logic        rf_we,
  input logic        imem_req,
  input logic        dmem_req,
  input logic        dmem_we,
  input logic [3:0]  dmem_wmask,
  input logic        rvfi_valid,
  input logic [63:0] rvfi_order,
  input logic        rvfi_trap,
  input logic [31:0] rvfi_pc_rdata,
  input logic [31:0] rvfi_pc_wdata,
  input logic [4:0]  rvfi_rd_addr,
  input logic [31:0] rvfi_rd_wdata
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ------------------------------------------- independent decode helpers
  function automatic logic reads_rs1(input logic [31:0] in);
    case (in[6:0])
      7'b1100111, 7'b1100011, 7'b0000011, 7'b0100011, 7'b0010011, 7'b0110011: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction
  function automatic logic reads_rs2(input logic [31:0] in);
    case (in[6:0])
      7'b1100011, 7'b0100011, 7'b0110011: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction
  function automatic logic is_load(input logic [31:0] in);
    return in[6:0] == 7'b0000011;
  endfunction

  // A load in EX whose destination is a source of the instruction in ID.
  // (Illegal encodings are excluded by the decoder's own trap flag.)
  logic true_load_use;
  assign true_load_use = if_id.valid && id_ex.valid && is_load(id_ex.insn) &&
                         !id_ex.ctrl.trap && id_ex.insn[11:7] != 5'd0 && !id_ctrl_trap(if_id.insn) &&
                         ((reads_rs1(if_id.insn) && if_id.insn[19:15] == id_ex.insn[11:7]) ||
                          (reads_rs2(if_id.insn) && if_id.insn[24:20] == id_ex.insn[11:7]));
  // The decoder marks a malformed instruction as trapping; it reads nothing.
  function automatic logic id_ctrl_trap(input logic [31:0] in);
    logic [2:0] f3 = in[14:12];
    case (in[6:0])
      7'b1100111: return f3 != 3'b000;
      7'b1100011: return f3 == 3'b010 || f3 == 3'b011;
      7'b0000011: return f3 == 3'b011 || f3 == 3'b110 || f3 == 3'b111;
      7'b0100011: return f3[2] || f3[1:0] == 2'b11;
      7'b0010011: return (f3 == 3'b001 && in[31:25] != 7'b0) ||
                         (f3 == 3'b101 && in[31:25] != 7'b0 && in[31:25] != 7'b0100000);
      7'b0110011: return !(in[31:25] == 7'b0 ||
                           (in[31:25] == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101)));
      default:    return 1'b0;
    endcase
  endfunction

  // ===================================================== hazard detection
  // Stall exactly when there is a load-use dependency: never miss one
  // (wrong data) and never invent one (lost performance the scoreboard
  // cannot see).
  a_loaduse_needed: assert property (true_load_use |-> load_use)
    else $error("SVA a_loaduse_needed: load-use dependency in ID with no stall (ID %08h, EX %08h)",
                if_id.insn, id_ex.insn);
  a_loaduse_real: assert property (load_use |-> true_load_use)
    else $error("SVA a_loaduse_real: stall without a load-use dependency (ID %08h, EX %08h)",
                if_id.insn, id_ex.insn);

  // ========================================================== forwarding
  // The youngest producer wins. EX/MEM is younger than MEM/WB.
  logic exmem_hit_a, memwb_hit_a, exmem_hit_b, memwb_hit_b;
  assign exmem_hit_a = id_ex.ctrl.use_rs1 && id_ex.ctrl.rs1 != 0 && ex_mem.valid && ex_mem.rf_we &&
                       !ex_mem.is_load && ex_mem.rd == id_ex.ctrl.rs1;
  assign memwb_hit_a = id_ex.ctrl.use_rs1 && id_ex.ctrl.rs1 != 0 && mem_wb.valid && mem_wb.rf_we &&
                       mem_wb.rd == id_ex.ctrl.rs1;
  assign exmem_hit_b = id_ex.ctrl.use_rs2 && id_ex.ctrl.rs2 != 0 && ex_mem.valid && ex_mem.rf_we &&
                       !ex_mem.is_load && ex_mem.rd == id_ex.ctrl.rs2;
  assign memwb_hit_b = id_ex.ctrl.use_rs2 && id_ex.ctrl.rs2 != 0 && mem_wb.valid && mem_wb.rf_we &&
                       mem_wb.rd == id_ex.ctrl.rs2;

  a_fwd_a_youngest: assert property (id_ex.valid && exmem_hit_a |-> fwd_a == FWD_EXMEM)
    else $error("SVA a_fwd_a_youngest: rs1 x%0d not forwarded from EX/MEM", id_ex.ctrl.rs1);
  a_fwd_a_memwb: assert property (id_ex.valid && !exmem_hit_a && memwb_hit_a |-> fwd_a == FWD_MEMWB)
    else $error("SVA a_fwd_a_memwb: rs1 x%0d not forwarded from MEM/WB", id_ex.ctrl.rs1);
  a_fwd_b_youngest: assert property (id_ex.valid && exmem_hit_b |-> fwd_b == FWD_EXMEM)
    else $error("SVA a_fwd_b_youngest: rs2 x%0d not forwarded from EX/MEM", id_ex.ctrl.rs2);
  a_fwd_b_memwb: assert property (id_ex.valid && !exmem_hit_b && memwb_hit_b |-> fwd_b == FWD_MEMWB)
    else $error("SVA a_fwd_b_memwb: rs2 x%0d not forwarded from MEM/WB", id_ex.ctrl.rs2);

  // A load's result is never forwarded out of EX/MEM (its data is not there yet).
  a_no_load_fwd_from_exmem: assert property (
      !(id_ex.valid && ex_mem.valid && ex_mem.is_load &&
        ((fwd_a == FWD_EXMEM && ex_mem.rd == id_ex.ctrl.rs1) ||
         (fwd_b == FWD_EXMEM && ex_mem.rd == id_ex.ctrl.rs2))))
    else $error("SVA a_no_load_fwd_from_exmem");

  // ================================================================ x0
  a_x0_read_zero: assert property ((rf_raddr1 == 5'd0 -> rf_rdata1 == 32'd0) &&
                                   (rf_raddr2 == 5'd0 -> rf_rdata2 == 32'd0))
    else $error("SVA a_x0_read_zero: register file returned non-zero for x0");
  a_x0_never_written: assert property (rf_we |-> mem_wb.rd != 5'd0)
    else $error("SVA a_x0_never_written: write enable for x0");
  a_x0_retire: assert property (rvfi_valid && rvfi_rd_addr == 5'd0 |-> rvfi_rd_wdata == 32'd0)
    else $error("SVA a_x0_retire: retirement reports a value for x0");

  // ============================================================== stalls
  // load-use: PC and IF/ID hold, a bubble goes to EX
  a_loaduse_holds: assert property (load_use && !mem_wait && !mem_trap |=>
                                    $stable(pc) && $stable(if_id) && !id_ex.valid)
    else $error("SVA a_loaduse_holds: state moved during a load-use stall");
  // data-memory wait: everything up to MEM holds, WB gets a bubble
  a_wait_holds: assert property (mem_wait |=>
                                 $stable(pc) && $stable(if_id) && $stable(ex_mem) &&
                                 id_ex.valid == $past(id_ex.valid) && id_ex.pc == $past(id_ex.pc) &&
                                 id_ex.insn == $past(id_ex.insn) && id_ex.ctrl == $past(id_ex.ctrl) &&
                                 !mem_wb.valid)
    else $error("SVA a_wait_holds: state moved during a data-memory wait");
  // while held, EX keeps the freshest operand values: what EX sees after the
  // wait equals what the forwarding network produced during it
  a_wait_refresh: assert property (mem_wait && id_ex.valid |=>
                                   (!id_ex.ctrl.use_rs1 || id_ex.rs1_val == $past(rs1_fwd)) &&
                                   (!id_ex.ctrl.use_rs2 || id_ex.rs2_val == $past(rs2_fwd)))
    else $error("SVA a_wait_refresh: operand lost while EX was held (pc %08h)", id_ex.pc);

  // ===================================================== flush and redirect
  // control flow only changes when EX actually advances
  a_redirect_only_when_advancing: assert property (redirect |-> !mem_wait && !mem_trap)
    else $error("SVA a_redirect_only_when_advancing");
  // a redirect kills both younger instructions
  a_redirect_flushes: assert property (redirect |=> !if_id.valid && !id_ex.valid)
    else $error("SVA a_redirect_flushes: wrong-path instruction survived a redirect");
  // a trap reaching MEM kills everything younger, retires next, and is the last retirement
  a_trap_flushes: assert property (mem_trap |=> !if_id.valid && !id_ex.valid && !ex_mem.valid &&
                                   rvfi_valid && rvfi_trap)
    else $error("SVA a_trap_flushes");
  a_halted_quiet: assert property (halted |-> !imem_req && !if_id.valid)
    else $error("SVA a_halted_quiet: fetch after halt");

  // ========================================================= memory side
  a_dmem_req_legal: assert property (dmem_req |-> ex_mem.valid && !ex_mem.trap &&
                                     (ex_mem.is_load || ex_mem.is_store))
    else $error("SVA a_dmem_req_legal: memory access from an invalid or trapping instruction");
  a_store_has_mask: assert property (dmem_we |-> dmem_req && dmem_wmask != 4'b0)
    else $error("SVA a_store_has_mask");
  a_pc_aligned: assert property (pc[1:0] == 2'b00)
    else $error("SVA a_pc_aligned: PC %08h", pc);

  // ========================================================== retirement
  // Program order at retirement: each instruction starts where the previous
  // one said control would go. Catches flushed instructions retiring,
  // duplicates, and skipped instructions.
  logic [31:0] exp_pc;
  logic        have_exp_pc, trap_retired;
  logic [63:0] exp_order;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_exp_pc  <= 1'b0;
      trap_retired <= 1'b0;
      exp_order    <= '0;
      exp_pc       <= '0;
    end else if (rvfi_valid) begin
      have_exp_pc  <= 1'b1;
      exp_pc       <= rvfi_pc_wdata;
      exp_order    <= rvfi_order + 64'd1;
      if (rvfi_trap) trap_retired <= 1'b1;
    end
  end

  a_pc_sequence: assert property (rvfi_valid && have_exp_pc |-> rvfi_pc_rdata == exp_pc)
    else $error("SVA a_pc_sequence: retired pc %08h, previous instruction pointed to %08h",
                rvfi_pc_rdata, exp_pc);
  a_order_sequence: assert property (rvfi_valid |-> rvfi_order == exp_order)
    else $error("SVA a_order_sequence: order %0d, expected %0d", rvfi_order, exp_order);
  a_nothing_after_trap: assert property (trap_retired |-> !rvfi_valid)
    else $error("SVA a_nothing_after_trap");

  // ============================================================== covers
  c_loaduse_then_fwd:   cover property ((load_use && !mem_wait) ##2 (fwd_a == FWD_MEMWB || fwd_b == FWD_MEMWB));
  c_redirect_deferred:  cover property ((ex_redirect_req && mem_wait) ##[1:8] redirect);
  c_trap_over_redirect: cover property (mem_trap && ex_redirect_req);
  c_wait_then_loaduse:  cover property (mem_wait ##1 (!mem_wait && load_use));
  c_both_fwd:           cover property (fwd_a == FWD_EXMEM && fwd_b == FWD_MEMWB);

endmodule

bind rv32_core rv32_core_sva u_sva (.*);
