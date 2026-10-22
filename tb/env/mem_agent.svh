// mem_agent.svh
// Responder for the instruction and data buses (the "driver" side of the
// bench). Both ports are combinational-read with a ready handshake; the
// agent answers at the falling edge for the request the core is presenting
// in that cycle, so the core samples a settled response at the rising edge.
//
// Wait states are injected at random (+imem_stall / +dmem_stall percent)
// to exercise every stall path in the pipeline.

class mem_agent;
  virtual rv32_bus_if vif;
  mem_model           mem;
  tb_cfg              cfg;

  int unsigned imem_wait_cycles = 0;
  int unsigned dmem_wait_cycles = 0;
  int unsigned stores = 0;
  int unsigned loads  = 0;

  function new(virtual rv32_bus_if vif, mem_model mem, tb_cfg cfg);
    this.vif = vif;
    this.mem = mem;
    this.cfg = cfg;
  endfunction

  task run();
    vif.imem_ready = 1'b0;
    vif.imem_rdata = '0;
    vif.dmem_ready = 1'b0;
    vif.dmem_rdata = '0;
    forever begin
      @(negedge vif.clk);
      if (!vif.rst_n) continue;

      // instruction port
      if (vif.imem_req && $urandom_range(99) < cfg.imem_stall) begin
        vif.imem_ready = 1'b0;
        imem_wait_cycles++;
      end else begin
        vif.imem_ready = 1'b1;
      end
      vif.imem_rdata = mem.read(vif.imem_addr);

      // data port
      if (vif.dmem_req && $urandom_range(99) < cfg.dmem_stall) begin
        vif.dmem_ready = 1'b0;
        dmem_wait_cycles++;
      end else begin
        vif.dmem_ready = 1'b1;
        if (vif.dmem_req) begin
          if (vif.dmem_we) begin
            mem.write(vif.dmem_addr, vif.dmem_wdata, vif.dmem_wmask);
            stores++;
          end else begin
            loads++;
          end
        end
      end
      vif.dmem_rdata = mem.read(vif.dmem_addr);
    end
  endtask
endclass
