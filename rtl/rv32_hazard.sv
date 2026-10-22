// rv32_hazard.sv
// Hazard unit: forwarding selection, load-use detection, and the stall /
// bubble / redirect controls for every pipeline register.
//
//   event              PC/IF-ID   ID/EX      EX/MEM     MEM/WB
//   data-memory wait   hold       hold*      hold       bubble
//   trap in MEM        halt+kill  bubble     bubble     advance
//   redirect from EX   load tgt   bubble     advance    advance
//   load-use in ID     hold       bubble     advance    advance
//   (* operands refreshed from the forwarding network while held)
//
// Priority is top to bottom. A redirect requested by EX only takes effect
// when MEM is neither waiting nor trapping; otherwise EX is held or killed
// and the request is re-evaluated later.

module rv32_hazard
  import rv32_pkg::*;
(
  /* verilator lint_off UNUSEDSIGNAL */   // only a few control fields are needed
  // ID
  input  logic       id_valid,
  input  ctrl_t      id_ctrl,
  // EX
  input  logic       ex_valid,
  input  ctrl_t      ex_ctrl,
  input  logic       ex_redirect_req,
  /* verilator lint_on UNUSEDSIGNAL */
  // MEM
  input  logic       mem_valid,
  input  logic       mem_rf_we,
  input  logic [4:0] mem_rd,
  input  logic       mem_is_load,
  input  logic       mem_wait,
  input  logic       mem_trap,
  // WB
  input  logic       wb_valid,
  input  logic       wb_rf_we,
  input  logic [4:0] wb_rd,

  output fwd_sel_e   fwd_a,
  output fwd_sel_e   fwd_b,
  output logic       load_use,
  output logic       stall_if,      // hold PC and IF/ID
  output logic       redirect,      // apply EX redirect now
  output logic       halt,          // stop fetch, trap is retiring
  output logic       hold_ex,       // hold ID/EX
  output logic       bubble_ex,     // bubble into ID/EX
  output logic       hold_mem,      // hold EX/MEM
  output logic       bubble_mem     // bubble into EX/MEM
);

  // --------------------------------------------------------- forwarding
  function automatic fwd_sel_e fwd_for(input logic use_rs, input logic [4:0] rs);
    if (!use_rs || rs == 5'd0)
      return FWD_NONE;
`ifdef BUG_FWD_PRIORITY
    // injected: the older (WB) result wins over the younger (MEM) one
    if (wb_valid && wb_rf_we && wb_rd == rs)
      return FWD_MEMWB;
    if (mem_valid && mem_rf_we && !mem_is_load && mem_rd == rs)
      return FWD_EXMEM;
`else
    if (mem_valid && mem_rf_we && !mem_is_load && mem_rd == rs)
      return FWD_EXMEM;
`ifndef BUG_NO_FWD_MEMWB
    if (wb_valid && wb_rf_we && wb_rd == rs)
      return FWD_MEMWB;
`endif
`endif
    return FWD_NONE;
  endfunction

  assign fwd_a = fwd_for(ex_ctrl.use_rs1, ex_ctrl.rs1);
  assign fwd_b = fwd_for(ex_ctrl.use_rs2, ex_ctrl.rs2);

  // ----------------------------------------------------------- load-use
  logic dep_rs1, dep_rs2;
`ifdef BUG_LOADUSE_IGNORES_USE
  assign dep_rs1 = id_ctrl.rs1 == ex_ctrl.rd;                          // injected
`else
  assign dep_rs1 = id_ctrl.use_rs1 && id_ctrl.rs1 == ex_ctrl.rd;
`endif
`ifdef BUG_LOADUSE_RS1_ONLY
  assign dep_rs2 = 1'b0;                                               // injected
`else
  assign dep_rs2 = id_ctrl.use_rs2 && id_ctrl.rs2 == ex_ctrl.rd;
`endif

`ifdef BUG_NO_LOADUSE_STALL
  assign load_use = 1'b0;                                              // injected
`else
  assign load_use = id_valid && ex_valid && ex_ctrl.is_load && ex_ctrl.rf_we &&
                    (dep_rs1 || dep_rs2);
`endif

  // ----------------------------------------------------------- controls
  assign halt       = mem_trap;
`ifdef BUG_REDIRECT_DURING_WAIT
  assign redirect   = ex_redirect_req && !mem_trap;                   // injected
`else
  assign redirect   = ex_redirect_req && !mem_wait && !mem_trap;
`endif
  assign stall_if   = mem_wait || load_use;
  assign hold_ex    = mem_wait;
`ifdef BUG_FLUSH_EX_MISSING
  assign bubble_ex  = mem_trap || load_use;                           // injected
`else
  assign bubble_ex  = redirect || mem_trap || load_use;
`endif
  assign hold_mem   = mem_wait;
`ifdef BUG_TRAP_NO_KILL
  assign bubble_mem = 1'b0;                                            // injected
`else
  assign bubble_mem = mem_trap;
`endif

endmodule
