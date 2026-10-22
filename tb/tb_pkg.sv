// tb_pkg.sv
// Bench package: DPI-C imports of the reference model and every bench class.
package tb_pkg;

  // ------------------------------------------------ reference model (DPI-C)
  import "DPI-C" function void iss_reset(input int unsigned pc);
  import "DPI-C" function int iss_load_hex(input string path, input int unsigned base);
  import "DPI-C" function void iss_write32(input int unsigned addr, input int unsigned data);
  import "DPI-C" function int unsigned iss_read32(input int unsigned addr);
  import "DPI-C" function int unsigned iss_reg(input int unsigned idx);
  import "DPI-C" function int unsigned iss_pc();
  import "DPI-C" function void iss_step(
      output int unsigned pc, output int unsigned insn,
      output int unsigned rs1_addr, output int unsigned rs2_addr,
      output int unsigned rs1_rdata, output int unsigned rs2_rdata,
      output int unsigned rd_addr, output int unsigned rd_wdata,
      output int unsigned pc_wdata,
      output int unsigned mem_addr, output int unsigned mem_rmask,
      output int unsigned mem_wmask, output int unsigned mem_rdata,
      output int unsigned mem_wdata,
      output int unsigned trap, output int unsigned cause);
  import "DPI-C" function string iss_disasm(input int unsigned insn);

  `include "env/tb_cfg.svh"
  `include "env/mem_model.svh"
  `include "env/rvfi_txn.svh"
  `include "env/mem_agent.svh"
  `include "env/rvfi_monitor.svh"
  `include "env/scoreboard.svh"
  `include "env/coverage.svh"
  `include "gen/rv_gen.svh"
  `include "env/tb_env.svh"

endpackage
