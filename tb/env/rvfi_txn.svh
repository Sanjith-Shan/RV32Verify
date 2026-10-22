// rvfi_txn.svh
// One retired instruction, as reported by the RVFI port or predicted by the
// reference model, plus the analysis-port style subscriber base class.

class rvfi_txn;
  longint unsigned cycle;
  bit [63:0] order;
  bit [31:0] pc, insn, pc_wdata;
  bit [4:0]  rs1_addr, rs2_addr, rd_addr;
  bit [31:0] rs1_rdata, rs2_rdata, rd_wdata;
  bit [31:0] mem_addr, mem_rdata, mem_wdata;
  bit [3:0]  mem_rmask, mem_wmask;
  bit        trap;
  bit [3:0]  cause;

  function string disasm();
    return iss_disasm(insn);
  endfunction

  function string to_string();
    string s;
    s = $sformatf("#%0d pc=%08h insn=%08h %-28s", order, pc, insn, disasm());
    if (trap)      s = {s, $sformatf(" TRAP cause=%0d", cause)};
    if (rd_addr != 0) s = {s, $sformatf(" x%0d=%08h", rd_addr, rd_wdata)};
    if (mem_wmask != 0) s = {s, $sformatf(" [%08h]<=%08h/%b", mem_addr, mem_wdata, mem_wmask)};
    if (mem_rmask != 0) s = {s, $sformatf(" [%08h]=>%08h/%b", mem_addr, mem_rdata, mem_rmask)};
    return s;
  endfunction
endclass

// Anything that wants to see retired instructions (scoreboard, coverage,
// trace writer) extends this and registers with the monitor.
virtual class rvfi_subscriber;
  pure virtual function void write(rvfi_txn t);
endclass
