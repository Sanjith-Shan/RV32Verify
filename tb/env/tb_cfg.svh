// tb_cfg.svh
// Run configuration, filled from plusargs. One object shared by every
// component so a run is fully described by its command line.
//
//   +hex=<file>          program image ($readmemh word format)
//   +tohost=<hex>        tohost address (from the .meta file)
//   +gen                 generate a constrained-random program instead
//   +seed=<n>            seed for the generator and the memory agent
//   +imem_stall=<pct>    % of fetch cycles the instruction port is not ready
//   +dmem_stall=<pct>    % of data accesses cycles the data port is not ready
//   +max_cycles=<n>      hard timeout
//   +hang_cycles=<n>     watchdog: max cycles between two retirements
//   +trace=<file>        write a retirement trace (one line per instruction)
//   +quiet               suppress per-run summary lines except the result
//   +save_prog=<prefix>  (with +gen) save the program as <prefix>.hex / .meta
//   +end_trap_ok         (with +hex) the program is expected to end in a trap

class tb_cfg;
  string       hex_file    = "";
  bit          use_gen     = 0;
  int unsigned seed        = 1;
  int unsigned imem_stall  = 0;
  int unsigned dmem_stall  = 0;
  int unsigned max_cycles  = 500000;
  int unsigned hang_cycles = 1000;
  bit [31:0]   reset_pc    = 32'h8000_0000;
  bit [31:0]   tohost      = 32'h8000_1000;
  string       trace_file  = "";
  string       test_name   = "";
  bit          quiet       = 0;
  bit          end_trap_ok = 0;   // hex mode: program is meant to end in a trap
  string       save_prog   = ""; // gen mode: write the program to <prefix>.hex/.meta

  function void from_plusargs();
    string s;
    if ($value$plusargs("hex=%s", hex_file)) test_name = hex_file;
    if ($test$plusargs("gen")) use_gen = 1;
    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("imem_stall=%d", imem_stall));
    void'($value$plusargs("dmem_stall=%d", dmem_stall));
    void'($value$plusargs("max_cycles=%d", max_cycles));
    void'($value$plusargs("hang_cycles=%d", hang_cycles));
    if ($value$plusargs("tohost=%s", s)) tohost = s.atohex();
    void'($value$plusargs("trace=%s", trace_file));
    void'($value$plusargs("name=%s", test_name));
    if ($test$plusargs("quiet")) quiet = 1;
    if ($test$plusargs("end_trap_ok")) end_trap_ok = 1;
    void'($value$plusargs("save_prog=%s", save_prog));
    if (use_gen && test_name == "") test_name = $sformatf("random_seed%0d", seed);
  endfunction

  function string to_string();
    return $sformatf("test=%s seed=%0d imem_stall=%0d%% dmem_stall=%0d%% max_cycles=%0d",
                     test_name, seed, imem_stall, dmem_stall, max_cycles);
  endfunction
endclass
