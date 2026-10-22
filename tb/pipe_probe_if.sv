// pipe_probe_if.sv
// White-box view of pipeline events for functional coverage. Driven in
// tb_top from hierarchical references into the core; read-only.
interface pipe_probe_if (input logic clk);
  // ID
  logic        id_valid;
  logic        id_use_rs1, id_use_rs2;
  logic [4:0]  id_rs1, id_rs2;
  // EX
  logic        ex_valid;
  logic [31:0] ex_insn;
  logic        ex_use_rs1, ex_use_rs2;
  logic [1:0]  fwd_a, fwd_b;           // rv32_pkg::fwd_sel_e
  logic        ex_redirect_req;
  // MEM
  logic        mem_valid;
  logic        mem_is_load, mem_is_store;
  logic        mem_wait;
  logic        mem_trap;
  // WB
  logic        wb_valid;
  logic        rf_we;
  logic [4:0]  rf_waddr;
  // hazard controls
  logic        load_use;
  logic        redirect;
  logic        halt;
  logic        imem_ready;
  logic        imem_req;
  // architectural register file, for the end-of-test state compare
  logic [31:0] arch_regs [32];
endinterface
