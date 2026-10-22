// scoreboard.svh
// Lockstep checker. For every instruction the core retires, the reference
// model (C++ ISS over DPI-C) executes one instruction and the two
// retirement records are compared field by field. The first mismatch stops
// the test with a report: cycle, retirement number, PC, disassembly, every
// field expected vs actual, and the instructions that retired just before.
//
// Memory data is compared only in the byte lanes the masks enable.

class scoreboard extends rvfi_subscriber;
  int unsigned     checked = 0;
  bit              failed  = 0;
  string           fail_msg = "";
  longint unsigned fail_cycle = 0;
  bit [63:0]       next_order = 0;
  rvfi_txn         history[$];
  localparam int   HISTORY = 8;

  function rvfi_txn predict();
    rvfi_txn e = new;
    int unsigned pc, insn, rs1a, rs2a, rs1d, rs2d, rda, rdd, npc, ma, mrm, mwm, mrd, mwd, tr, ca;
    iss_step(pc, insn, rs1a, rs2a, rs1d, rs2d, rda, rdd, npc, ma, mrm, mwm, mrd, mwd, tr, ca);
    e.pc = pc; e.insn = insn;
    e.rs1_addr = 5'(rs1a); e.rs2_addr = 5'(rs2a);
    e.rs1_rdata = rs1d; e.rs2_rdata = rs2d;
    e.rd_addr = 5'(rda); e.rd_wdata = rdd;
    e.pc_wdata = npc;
    e.mem_addr = ma; e.mem_rmask = 4'(mrm); e.mem_wmask = 4'(mwm);
    e.mem_rdata = mrd; e.mem_wdata = mwd;
    e.trap = tr[0]; e.cause = 4'(ca);
    return e;
  endfunction

  static function bit [31:0] lanes(bit [3:0] m);
    return {{8{m[3]}}, {8{m[2]}}, {8{m[1]}}, {8{m[0]}}};
  endfunction

  virtual function void write(rvfi_txn a);
    rvfi_txn e;
    string   rows = "";
    int      nbad = 0;
    if (failed) return;
    e = predict();
    e.order = next_order;
    e.cycle = a.cycle;

    `define SB_CMP(F, W) \
      if (a.F !== e.F) begin nbad++; rows = {rows, $sformatf("    %-10s exp %08h  got %08h  <--\n", `"F`", W'(e.F), W'(a.F))}; end \
      else rows = {rows, $sformatf("    %-10s     %08h\n", `"F`", W'(a.F))};
    `SB_CMP(order, 32)
    `SB_CMP(pc, 32)
    `SB_CMP(insn, 32)
    `SB_CMP(trap, 32)
    if (a.trap || e.trap) `SB_CMP(cause, 32)
    `SB_CMP(rs1_addr, 32)
    `SB_CMP(rs1_rdata, 32)
    `SB_CMP(rs2_addr, 32)
    `SB_CMP(rs2_rdata, 32)
    `SB_CMP(rd_addr, 32)
    `SB_CMP(rd_wdata, 32)
    `SB_CMP(pc_wdata, 32)
    `SB_CMP(mem_addr, 32)
    `SB_CMP(mem_rmask, 32)
    `SB_CMP(mem_wmask, 32)
    `undef SB_CMP
    if ((a.mem_rdata & lanes(e.mem_rmask)) !== (e.mem_rdata & lanes(e.mem_rmask))) begin
      nbad++;
      rows = {rows, $sformatf("    %-10s exp %08h  got %08h  <-- (lanes %b)\n", "mem_rdata",
                              e.mem_rdata, a.mem_rdata, e.mem_rmask)};
    end
    if ((a.mem_wdata & lanes(e.mem_wmask)) !== (e.mem_wdata & lanes(e.mem_wmask))) begin
      nbad++;
      rows = {rows, $sformatf("    %-10s exp %08h  got %08h  <-- (lanes %b)\n", "mem_wdata",
                              e.mem_wdata, a.mem_wdata, e.mem_wmask)};
    end

    if (nbad != 0) begin
      string h = "";
      foreach (history[i]) h = {h, "    ", history[i].to_string(), "\n"};
      failed = 1;
      fail_cycle = a.cycle;
      fail_msg = $sformatf({"LOCKSTEP MISMATCH at cycle %0d, retirement #%0d\n",
                            "  pc %08h  insn %08h  %s\n",
                            "  expected (ISS): %s\n",
                            "  actual   (RTL): %s\n",
                            "  fields:\n%s",
                            "  previously retired:\n%s"},
                           a.cycle, a.order, e.pc, e.insn, e.disasm(),
                           e.to_string(), a.to_string(), rows, h);
      return;
    end

    checked++;
    next_order++;
    history.push_back(a);
    if (history.size() > HISTORY) void'(history.pop_front());
  endfunction
endclass
