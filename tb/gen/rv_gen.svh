// rv_gen.svh  (placeholder until the M2 generator lands)
class rv_program;
  bit [31:0] words [bit [31:0]];
  bit [31:0] tohost;
  int unsigned n_instr;
  bit ends_in_trap;
  function void dump(string path); endfunction
endclass
class rv_gen_cfg;
  function void from_plusargs(); endfunction
endclass
class rv_gen;
  rv_gen_cfg cfg;
  function new(int unsigned seed); cfg = new; endfunction
  function rv_program generate_program(bit [31:0] base); $fatal(1, "generator not built"); return null; endfunction
endclass
