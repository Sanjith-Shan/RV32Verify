// tb_top.sv
// Bench top: clock, the core, its interfaces, and the white-box probe.
// All test behaviour lives in tb_env (tb_pkg); this module only wires.
module tb_top;
  import tb_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  rv32_bus_if   bus   (clk);
  rvfi_if       rvfi  (clk);
  pipe_probe_if probe (clk);

  rv32_core #(.RESET_PC(32'h8000_0000)) dut (
    .clk            (clk),
    .rst_n          (bus.rst_n),
    .imem_req       (bus.imem_req),
    .imem_addr      (bus.imem_addr),
    .imem_rdata     (bus.imem_rdata),
    .imem_ready     (bus.imem_ready),
    .dmem_req       (bus.dmem_req),
    .dmem_we        (bus.dmem_we),
    .dmem_addr      (bus.dmem_addr),
    .dmem_wmask     (bus.dmem_wmask),
    .dmem_wdata     (bus.dmem_wdata),
    .dmem_rdata     (bus.dmem_rdata),
    .dmem_ready     (bus.dmem_ready),
    .rvfi_valid     (rvfi.valid),
    .rvfi_order     (rvfi.order),
    .rvfi_insn      (rvfi.insn),
    .rvfi_trap      (rvfi.trap),
    .rvfi_halt      (rvfi.halt),
    .rvfi_intr      (rvfi.intr),
    .rvfi_mode      (rvfi.mode),
    .rvfi_ixl       (rvfi.ixl),
    .rvfi_rs1_addr  (rvfi.rs1_addr),
    .rvfi_rs2_addr  (rvfi.rs2_addr),
    .rvfi_rs1_rdata (rvfi.rs1_rdata),
    .rvfi_rs2_rdata (rvfi.rs2_rdata),
    .rvfi_rd_addr   (rvfi.rd_addr),
    .rvfi_rd_wdata  (rvfi.rd_wdata),
    .rvfi_pc_rdata  (rvfi.pc_rdata),
    .rvfi_pc_wdata  (rvfi.pc_wdata),
    .rvfi_mem_addr  (rvfi.mem_addr),
    .rvfi_mem_rmask (rvfi.mem_rmask),
    .rvfi_mem_wmask (rvfi.mem_wmask),
    .rvfi_mem_rdata (rvfi.mem_rdata),
    .rvfi_mem_wdata (rvfi.mem_wdata),
    .rvfi_trap_cause(rvfi.trap_cause)
  );

  // ------------------------------------------------ white-box probe wiring
  assign probe.id_valid        = dut.if_id.valid;
  assign probe.id_use_rs1      = dut.id_ctrl.use_rs1;
  assign probe.id_use_rs2      = dut.id_ctrl.use_rs2;
  assign probe.id_rs1          = dut.id_ctrl.rs1;
  assign probe.id_rs2          = dut.id_ctrl.rs2;
  assign probe.ex_valid        = dut.id_ex.valid;
  assign probe.ex_insn         = dut.id_ex.insn;
  assign probe.ex_use_rs1      = dut.id_ex.ctrl.use_rs1;
  assign probe.ex_use_rs2      = dut.id_ex.ctrl.use_rs2;
  assign probe.fwd_a           = dut.fwd_a;
  assign probe.fwd_b           = dut.fwd_b;
  assign probe.ex_redirect_req = dut.ex_redirect_req;
  assign probe.mem_valid       = dut.ex_mem.valid;
  assign probe.mem_is_load     = dut.ex_mem.is_load;
  assign probe.mem_is_store    = dut.ex_mem.is_store;
  assign probe.mem_wait        = dut.mem_wait;
  assign probe.mem_trap        = dut.mem_trap;
  assign probe.wb_valid        = dut.mem_wb.valid;
  assign probe.rf_we           = dut.rf_we;
  assign probe.rf_waddr        = dut.mem_wb.rd;
  assign probe.load_use        = dut.load_use;
  assign probe.redirect        = dut.redirect;
  assign probe.halt            = dut.halt;
  assign probe.imem_ready      = bus.imem_ready;
  assign probe.imem_req        = bus.imem_req;
  assign probe.arch_regs[0]    = 32'h0;
  for (genvar i = 1; i < 32; i++) begin : g_regs
    assign probe.arch_regs[i] = dut.u_regfile.regs[i];
  end

  initial begin
    tb_env env;
    env = new(bus, rvfi, probe);
    env.run();
  end
endmodule
