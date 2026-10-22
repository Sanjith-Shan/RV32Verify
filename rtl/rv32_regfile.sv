// rv32_regfile.sv
// 32 x 32-bit register file, two combinational read ports, one write port.
// x0 is hardwired to zero. A write and a read of the same register in the
// same cycle returns the new value (write-through), which closes the
// WB -> ID hazard for an instruction three behind its producer.

module rv32_regfile (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [4:0]  raddr1,
  output logic [31:0] rdata1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata2,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata
);

  logic [31:0] regs [1:31];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 1; i < 32; i++) regs[i] <= '0;
    end else if (we && waddr != 5'd0) begin
      regs[waddr] <= wdata;
    end
  end

  function automatic logic [31:0] rd_port(input logic [4:0] a);
    if (a == 5'd0)
      return 32'b0;
`ifndef BUG_NO_WB_BYPASS
    else if (we && waddr == a)
      return wdata;
`endif
    else
      return regs[a];
  endfunction

  assign rdata1 = rd_port(raddr1);
  assign rdata2 = rd_port(raddr2);

endmodule
