// rvfi_if.sv
// RVFI retirement port, observed by the retirement monitor.
interface rvfi_if (input logic clk);
  logic        valid;
  logic [63:0] order;
  logic [31:0] insn;
  logic        trap;
  logic        halt;
  logic        intr;
  logic [1:0]  mode;
  logic [1:0]  ixl;
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;
  logic [4:0]  rd_addr;
  logic [31:0] rd_wdata;
  logic [31:0] pc_rdata;
  logic [31:0] pc_wdata;
  logic [31:0] mem_addr;
  logic [3:0]  mem_rmask;
  logic [3:0]  mem_wmask;
  logic [31:0] mem_rdata;
  logic [31:0] mem_wdata;
  logic [3:0]  trap_cause;
endinterface
