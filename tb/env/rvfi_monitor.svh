// rvfi_monitor.svh
// Passive monitor on the RVFI retirement port. Samples once per cycle in the
// middle of the cycle (the port is a function of the MEM/WB register only),
// builds a transaction for each retirement, and broadcasts it.

class rvfi_monitor;
  virtual rvfi_if  vif;
  rvfi_subscriber  subs[$];
  longint unsigned cycle = 0;
  longint unsigned last_retire_cycle = 0;
  longint unsigned retired = 0;

  function new(virtual rvfi_if vif);
    this.vif = vif;
  endfunction

  function void connect(rvfi_subscriber s);
    subs.push_back(s);
  endfunction

  task run();
    forever begin
      @(negedge vif.clk);
      cycle++;
      if (vif.valid) begin
        rvfi_txn t = new;
        t.cycle     = cycle;
        t.order     = vif.order;
        t.pc        = vif.pc_rdata;
        t.insn      = vif.insn;
        t.pc_wdata  = vif.pc_wdata;
        t.rs1_addr  = vif.rs1_addr;
        t.rs2_addr  = vif.rs2_addr;
        t.rs1_rdata = vif.rs1_rdata;
        t.rs2_rdata = vif.rs2_rdata;
        t.rd_addr   = vif.rd_addr;
        t.rd_wdata  = vif.rd_wdata;
        t.mem_addr  = vif.mem_addr;
        t.mem_rmask = vif.mem_rmask;
        t.mem_wmask = vif.mem_wmask;
        t.mem_rdata = vif.mem_rdata;
        t.mem_wdata = vif.mem_wdata;
        t.trap      = vif.trap;
        t.cause     = vif.trap_cause;
        retired++;
        last_retire_cycle = cycle;
        foreach (subs[i]) subs[i].write(t);
      end
    end
  endtask
endclass
