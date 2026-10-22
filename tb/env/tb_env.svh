// tb_env.svh
// Bench environment: builds and connects the components, loads the program
// into both the bus memory and the reference model, applies reset, and
// decides when and how a test ends.
//
// A test ends on the first of:
//   * scoreboard mismatch                          -> FAIL (lockstep)
//   * retirement of a store to tohost              -> PASS if tohost == 1
//   * retirement of a trapping instruction         -> PASS only if the program
//                                                     was generated to end that way
//   * no retirement for hang_cycles                -> FAIL (hang)
//   * max_cycles                                   -> FAIL (timeout)
// and then has to survive two end-of-test checks:
//   * all 31 architectural registers equal the reference model's
//   * every memory word equals the reference model's memory

class trace_writer extends rvfi_subscriber;
  int fd;
  function new(string path);
    fd = $fopen(path, "w");
  endfunction
  virtual function void write(rvfi_txn t);
    if (fd != 0) $fdisplay(fd, "%8d %s", t.cycle, t.to_string());
  endfunction
  function void close();
    if (fd != 0) $fclose(fd);
  endfunction
endclass

// Watches retirements for the end-of-test conditions.
class end_detector extends rvfi_subscriber;
  bit [31:0] tohost;
  bit        done = 0;
  bit        saw_tohost = 0;
  bit        saw_trap = 0;
  rvfi_txn   last;
  function new(bit [31:0] tohost);
    this.tohost = tohost;
  endfunction
  virtual function void write(rvfi_txn t);
    last = t;
    if (done) return;
    if (t.mem_wmask != 0 && t.mem_addr == {tohost[31:2], 2'b00}) begin
      saw_tohost = 1;
      done = 1;
    end else if (t.trap) begin
      saw_trap = 1;
      done = 1;
    end
  endfunction
endclass

class tb_env;
  tb_cfg        cfg;
  mem_model     mem;
  mem_agent     agent;
  rvfi_monitor  mon;
  scoreboard    sb;
  end_detector  ender;
  trace_writer  tracer;
  coverage      cov;
  rv_program    prog;

  virtual rv32_bus_if   bus;
  virtual rvfi_if       rvfi;
  virtual pipe_probe_if probe;

  function new(virtual rv32_bus_if bus, virtual rvfi_if rvfi, virtual pipe_probe_if probe);
    this.bus   = bus;
    this.rvfi  = rvfi;
    this.probe = probe;
    cfg = new;
    cfg.from_plusargs();
    mem   = new;
    agent = new(bus, mem, cfg);
    mon   = new(rvfi);
    sb    = new;
    ender = new(cfg.tohost);
    cov   = new(probe);
    mon.connect(sb);
    mon.connect(ender);
    mon.connect(cov);
    if (cfg.trace_file != "") begin
      tracer = new(cfg.trace_file);
      mon.connect(tracer);
    end
  endfunction

  // Put the program image into the bus memory and the reference model.
  function void load_program();
    iss_reset(cfg.reset_pc);
    if (cfg.use_gen) begin
      rv_gen gen = new(cfg.seed);
      gen.cfg.from_plusargs();
      prog = gen.generate_program(cfg.reset_pc);
      cfg.tohost = prog.tohost;
      ender.tohost = prog.tohost;
      foreach (prog.words[a]) begin
        mem.words[a[31:2]] = prog.words[a];
        iss_write32(a, prog.words[a]);
      end
      if (!cfg.quiet) $display("[env] generated %0d instructions (%0d words incl. data), seed %0d",
                               prog.n_instr, prog.words.size(), cfg.seed);
      if ($test$plusargs("dump_prog")) prog.dump("program.lst");
      if (cfg.save_prog != "") save_program();
    end else begin
      if (cfg.hex_file == "") $fatal(1, "[env] need +hex=<file> or +gen");
      if (!mem.load_hex(cfg.hex_file, cfg.reset_pc)) $fatal(1, "[env] cannot read %s", cfg.hex_file);
      if (iss_load_hex(cfg.hex_file, cfg.reset_pc) == 0) $fatal(1, "[env] ISS cannot read %s", cfg.hex_file);
    end
  endfunction

  // Write the generated program in the same hex format riscv-tests use, so it
  // can be replayed (+hex) against other builds with identical stimulus.
  function void save_program();
    int fd = $fopen({cfg.save_prog, ".hex"}, "w");
    bit [31:0] expect_idx = 32'hffff_ffff;
    foreach (prog.words[a]) begin
      bit [31:0] idx = (a - cfg.reset_pc) >> 2;
      if (idx != expect_idx) $fdisplay(fd, "@%08h", idx);
      $fdisplay(fd, "%08h", prog.words[a]);
      expect_idx = idx + 1;
    end
    $fclose(fd);
    fd = $fopen({cfg.save_prog, ".meta"}, "w");
    $fdisplay(fd, "tohost=0x%08h", prog.tohost);
    $fdisplay(fd, "ends_in_trap=%0d", prog.ends_in_trap);
    $fdisplay(fd, "end_kind=%s", prog.end_kind);
    $fclose(fd);
  endfunction

  function int end_of_test_checks(output string msg);
    int bad = 0;
    msg = "";
    for (int i = 1; i < 32; i++) begin
      bit [31:0] exp = iss_reg(i);
      if (probe.arch_regs[i] !== exp) begin
        bad++;
        msg = {msg, $sformatf("  x%0d: expected %08h, register file holds %08h\n", i, exp, probe.arch_regs[i])};
      end
    end
    foreach (mem.words[w]) begin
      bit [31:0] a = {w, 2'b00};
      bit [31:0] exp = iss_read32(a);
      if (mem.words[w] !== exp) begin
        bad++;
        if (bad < 20) msg = {msg, $sformatf("  mem[%08h]: expected %08h, bus memory holds %08h\n", a, exp, mem.words[w])};
      end
    end
    return bad;
  endfunction

  task run();
    string reason = "";
    bit    pass = 0;
    longint unsigned cycles = 0;
    if (!cfg.quiet) $display("[env] %s", cfg.to_string());
    load_program();

    bus.rst_n = 1'b0;
    fork
      agent.run();
      mon.run();
      cov.run_pipe();
    join_none
    repeat (4) @(negedge bus.clk);
    bus.rst_n = 1'b1;

    forever begin
      @(negedge bus.clk);
      #2;  // after the monitors have sampled this cycle
      cycles++;
      if (sb.failed) begin reason = "lockstep mismatch"; break; end
      if (ender.done) break;
      if (mon.cycle - mon.last_retire_cycle > longint'(cfg.hang_cycles)) begin
        reason = $sformatf("hang: no retirement for %0d cycles", cfg.hang_cycles);
        break;
      end
      if (cycles >= longint'(cfg.max_cycles)) begin reason = "timeout"; break; end
    end

    // Drain: keep the core running and every checker live for a while after
    // the end condition. Whatever is still in the pipeline must either keep
    // matching the model (a tohost ending loops on "j .") or, after a trap,
    // never retire at all. Without this window a trap that fails to kill the
    // instruction behind it goes unseen (found by the bug-injection campaign).
    if (reason == "" && ender.done) begin
      longint unsigned retired_at_end = mon.retired;
      repeat (cfg.drain_cycles) begin
        @(negedge bus.clk);
        #2;
        if (sb.failed) begin reason = "lockstep mismatch"; break; end
      end
      if (reason == "" && ender.saw_trap && mon.retired != retired_at_end)
        reason = $sformatf("%0d instruction(s) retired after the trap", mon.retired - retired_at_end);
    end

    if (reason == "") begin
      if (ender.saw_tohost) begin
        bit [31:0] v = mem.read(cfg.tohost);
        if (v == 32'd1) pass = 1;
        else reason = $sformatf("program reported failure: tohost=%0d (test %0d)", v, v >> 1);
      end else if (ender.saw_trap) begin
        if ((cfg.use_gen && prog.ends_in_trap) || cfg.end_trap_ok) pass = 1;
        else reason = $sformatf("unexpected trap, cause %0d at pc %08h", ender.last.cause, ender.last.pc);
      end
    end

    if (pass) begin
      string m;
      if (end_of_test_checks(m) != 0) begin
        pass = 0;
        reason = "end-of-test state mismatch";
        $display("END-OF-TEST STATE MISMATCH\n%s", m);
      end
    end

    if (sb.failed) $display("%s", sb.fail_msg);
    if (tracer != null) tracer.close();
    cov.report(cfg.quiet);

    $display("RESULT: %s name=%s cycles=%0d retired=%0d checked=%0d imem_wait=%0d dmem_wait=%0d%s",
             pass ? "PASS" : "FAIL", cfg.test_name, mon.cycle, mon.retired, sb.checked,
             agent.imem_wait_cycles, agent.dmem_wait_cycles,
             pass ? "" : {" reason=\"", reason, "\""});
    if (!pass) begin
      // let the regression tell a failing test apart without parsing
      $fatal(1, "test failed: %s", reason);
    end
    $finish;
  endtask
endclass
