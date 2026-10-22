// rv32_bus_if.sv
// Instruction and data memory buses between the core and the bench's memory
// agent, plus reset (owned by the bench).
interface rv32_bus_if (input logic clk);
  logic        rst_n;

  logic        imem_req;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic        imem_ready;

  logic        dmem_req;
  logic        dmem_we;
  logic [31:0] dmem_addr;
  logic [3:0]  dmem_wmask;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;
  logic        dmem_ready;
endinterface
