// mem_model.svh
// Sparse word-addressed memory backing both the instruction and data buses.
// Loaded by an SV hex parser (not the C++ loader the ISS uses), so a loader
// bug cannot hide by corrupting the RTL and the reference model alike.

class mem_model;
  bit [31:0] words [bit [29:0]];   // word index -> data

  function bit [31:0] read(bit [31:0] addr);
    bit [29:0] i = addr[31:2];
    return words.exists(i) ? words[i] : 32'h0;
  endfunction

  function void write(bit [31:0] addr, bit [31:0] data, bit [3:0] mask);
    bit [31:0] w = read(addr);
    for (int b = 0; b < 4; b++)
      if (mask[b]) w[b*8 +: 8] = data[b*8 +: 8];
    words[addr[31:2]] = w;
  endfunction

  // "$readmemh" word format: "@<word index>" lines and one word per line.
  function bit load_hex(string path, bit [31:0] base);
    int fd, n;
    string line;
    bit [31:0] idx = 0, val;
    fd = $fopen(path, "r");
    if (fd == 0) return 0;
    while (!$feof(fd)) begin
      line = "";
      n = $fgets(line, fd);
      if (n == 0 || line.len() < 2) continue;
      if (line[0] == "@") begin
        void'($sscanf(line.substr(1, line.len() - 1), "%h", idx));
      end else if ($sscanf(line, "%h", val) == 1) begin
        words[30'((base >> 2) + idx)] = val;
        idx++;
      end
    end
    $fclose(fd);
    return 1;
  endfunction
endclass
