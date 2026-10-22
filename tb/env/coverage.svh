// coverage.svh  (placeholder until the M2 coverage model lands)
class coverage extends rvfi_subscriber;
  virtual pipe_probe_if probe;
  function new(virtual pipe_probe_if probe); this.probe = probe; endfunction
  virtual function void write(rvfi_txn t); endfunction
  task run_pipe(); endtask
  function void report(bit quiet); endfunction
endclass
