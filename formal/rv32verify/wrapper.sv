// wrapper.sv -- riscv-formal harness for rv32_core.
// Instruction and data memories are unconstrained inputs: every read value
// and every ready/wait pattern is allowed, so the checks hold for any
// program and any memory timing within the bounded depth.
module rvfi_wrapper (
  input  clock,
  input  reset,
  `RVFI_OUTPUTS
);
  (* keep *) `rvformal_rand_reg [31:0] imem_rdata;
  (* keep *) `rvformal_rand_reg        imem_ready;
  (* keep *) `rvformal_rand_reg [31:0] dmem_rdata;
  (* keep *) `rvformal_rand_reg        dmem_ready;

  (* keep *) wire        imem_req;
  (* keep *) wire [31:0] imem_addr;
  (* keep *) wire        dmem_req;
  (* keep *) wire        dmem_we;
  (* keep *) wire [31:0] dmem_addr;
  (* keep *) wire [3:0]  dmem_wmask;
  (* keep *) wire [31:0] dmem_wdata;
  (* keep *) wire [3:0]  trap_cause;

  rv32_core uut (
    .clk             (clock),
    .rst_n           (!reset),
    .imem_req        (imem_req),
    .imem_addr       (imem_addr),
    .imem_rdata      (imem_rdata),
    .imem_ready      (imem_ready),
    .dmem_req        (dmem_req),
    .dmem_we         (dmem_we),
    .dmem_addr       (dmem_addr),
    .dmem_wmask      (dmem_wmask),
    .dmem_wdata      (dmem_wdata),
    .dmem_rdata      (dmem_rdata),
    .dmem_ready      (dmem_ready),
    .rvfi_trap_cause (trap_cause),
    `RVFI_CONN
  );

`ifdef RV32VERIFY_FAIRNESS
  // liveness needs the memories to answer eventually: at most 2 wait cycles in a row
  reg [1:0] iwait = 0, dwait = 0;
  always @(posedge clock) begin
    iwait <= {iwait[0], imem_req && !imem_ready};
    dwait <= {dwait[0], dmem_req && !dmem_ready};
    assume (!(&iwait && imem_req && !imem_ready));
    assume (!(&dwait && dmem_req && !dmem_ready));
  end
`endif
endmodule
