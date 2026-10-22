// rv_gen.svh
// Constrained-random RV32I program generator (the bench's test generator).
//
// Each instruction is an rv_instr object randomized under constraints driven
// by the knobs in rv_gen_cfg. Program-level structure (branch targets, loops,
// the data region, how the program ends) is assembled around it by rv_gen so
// every program is guaranteed to terminate and to stay inside its code and
// data regions. Same seed + same knobs = same program.
//
// Knobs (all plusargs, see rv_gen_cfg):
//   instruction mix       +w_alu_r= +w_alu_i= +w_shift= +w_lui= +w_auipc= +w_load=
//                         +w_store= +w_branch= +w_jal= +w_jalr= +w_fence= +w_reload=
//   dependency distance   +p_dep=  % of source operands tied to a recent destination
//                         +dep_max= distance range 1..dep_max (in instructions)
//   branches              +p_self_cmp= % of branches comparing a register with
//                         itself (direction known: beq/bge/bgeu taken, bne/blt/bltu not)
//                         +skip_max= forward branch distance, +p_loop= counted loops
//   memory                +mem_window= bytes of data region in use (small = aliasing)
//                         +p_alias= % of accesses reusing a recent address
//   operands              +p_special= % of immediates drawn from boundary values
//                         +p_x0= % of results written to x0
//   length / ending       +n_instr= body length, +p_end_trap= % of programs ending
//                         in an exception instead of the tohost write

typedef enum bit [3:0] {
  K_ALU_R, K_ALU_I, K_SHIFT_I, K_LUI, K_AUIPC, K_LOAD, K_STORE,
  K_BRANCH, K_JAL, K_JALR, K_FENCE, K_RELOAD, K_SEED
} instr_kind_e;

class rv_gen_cfg;
  int unsigned n_instr     = 800;
  int unsigned w_alu_r     = 22;
  int unsigned w_alu_i     = 18;
  int unsigned w_shift     = 6;
  int unsigned w_lui       = 3;
  int unsigned w_auipc     = 2;
  int unsigned w_load      = 16;
  int unsigned w_store     = 12;
  int unsigned w_branch    = 12;
  int unsigned w_jal       = 2;
  int unsigned w_jalr      = 2;
  int unsigned w_fence     = 1;
  int unsigned w_reload    = 4;
  int unsigned w_seed      = 6;
  int unsigned p_dep       = 55;
  int unsigned dep_max     = 4;
  int unsigned p_self_cmp  = 20;
  int unsigned skip_max    = 5;
  int unsigned p_loop      = 2;
  int unsigned mem_window  = 64;
  int unsigned p_alias     = 40;
  int unsigned p_special   = 30;
  int unsigned p_x0        = 4;
  int unsigned p_end_trap  = 25;

  function void from_plusargs();
    void'($value$plusargs("n_instr=%d", n_instr));
    void'($value$plusargs("w_alu_r=%d", w_alu_r));
    void'($value$plusargs("w_alu_i=%d", w_alu_i));
    void'($value$plusargs("w_shift=%d", w_shift));
    void'($value$plusargs("w_lui=%d", w_lui));
    void'($value$plusargs("w_auipc=%d", w_auipc));
    void'($value$plusargs("w_load=%d", w_load));
    void'($value$plusargs("w_store=%d", w_store));
    void'($value$plusargs("w_branch=%d", w_branch));
    void'($value$plusargs("w_jal=%d", w_jal));
    void'($value$plusargs("w_jalr=%d", w_jalr));
    void'($value$plusargs("w_fence=%d", w_fence));
    void'($value$plusargs("w_reload=%d", w_reload));
    void'($value$plusargs("w_seed=%d", w_seed));
    void'($value$plusargs("p_dep=%d", p_dep));
    void'($value$plusargs("dep_max=%d", dep_max));
    void'($value$plusargs("p_self_cmp=%d", p_self_cmp));
    void'($value$plusargs("skip_max=%d", skip_max));
    void'($value$plusargs("p_loop=%d", p_loop));
    void'($value$plusargs("mem_window=%d", mem_window));
    void'($value$plusargs("p_alias=%d", p_alias));
    void'($value$plusargs("p_special=%d", p_special));
    void'($value$plusargs("p_x0=%d", p_x0));
    void'($value$plusargs("p_end_trap=%d", p_end_trap));
    if (dep_max < 1) dep_max = 1;
    if (dep_max > 6) dep_max = 6;
    if (skip_max < 1) skip_max = 1;
    if (mem_window < 8) mem_window = 8;
    if (mem_window > 4096) mem_window = 4096;
  endfunction
endclass

// --------------------------------------------------------------- one instr
class rv_instr;
  rand instr_kind_e kind;
  rand bit [2:0]    f3;
  rand bit          alt;        // funct7[5]: SUB / SRA / SRAI
  rand bit [4:0]    rd, rs1, rs2;
  rand bit [2:0]    dep1, dep2; // 0: free choice, k: rs = destination k instructions back
  rand bit          to_x0;
  rand bit          self_cmp;
  // Immediates are drawn in post_randomize(), not by the solver: they have
  // no relation to the other fields, and keeping them out of the SMT problem
  // makes generation several times faster (see docs/RESULTS.md).
  bit               special;    // immediate drawn from boundary values
  bit [11:0]        imm12;
  bit [19:0]        imm20;
  bit [4:0]         shamt;

  // context, set by the generator before each randomize()
  rv_gen_cfg cfg;
  bit [4:0]  recent_rd [6];     // recent_rd[k-1]: destination k instructions back (0 if none)
  bit [4:0]  r_base, r_tmp, r_cnt;
  bit        in_loop;           // inside a counted loop body: straight-line code only

  constraint c_kind {
    kind dist {
      K_ALU_R   := cfg.w_alu_r,  K_ALU_I  := cfg.w_alu_i, K_SHIFT_I := cfg.w_shift,
      K_LUI     := cfg.w_lui,    K_AUIPC  := cfg.w_auipc, K_LOAD    := cfg.w_load,
      K_STORE   := cfg.w_store,  K_BRANCH := cfg.w_branch, K_JAL    := cfg.w_jal,
      K_JALR    := cfg.w_jalr,   K_FENCE  := cfg.w_fence, K_RELOAD  := cfg.w_reload,
      K_SEED    := cfg.w_seed
    };
    in_loop -> !(kind inside {K_BRANCH, K_JAL, K_JALR, K_RELOAD, K_SEED});
  }

  constraint c_f3 {
    kind == K_ALU_R   -> (alt == 0 || f3 inside {3'b000, 3'b101});
    kind == K_ALU_I   -> (f3 inside {3'b000, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111} && alt == 0);
    kind == K_SHIFT_I -> (f3 inside {3'b001, 3'b101} && (alt == 0 || f3 == 3'b101));
    kind == K_LOAD    -> (f3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101});
    kind == K_STORE   -> (f3 inside {3'b000, 3'b001, 3'b010});
    kind == K_BRANCH  -> (f3 inside {3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111});
    kind == K_FENCE   -> (f3 inside {3'b000, 3'b001});
  }

  // destinations: never a reserved register; x0 only by the p_x0 knob
  constraint c_rd {
    to_x0 dist {1 := cfg.p_x0, 0 := 100 - cfg.p_x0};
    to_x0  -> rd == 0;
    !to_x0 -> rd != 0;
    rd != r_base; rd != r_tmp; rd != r_cnt;
    kind == K_SEED -> !to_x0;
  }

  // dependency distance: tie a source to the destination k instructions back
  constraint c_dep {
    dep1 dist {0 := 100 - cfg.p_dep, [1:6] :/ cfg.p_dep};
    dep2 dist {0 := 100 - cfg.p_dep, [1:6] :/ cfg.p_dep};
    dep1 <= cfg.dep_max; dep2 <= cfg.dep_max;
    dep1 == 1 -> rs1 == recent_rd[0];  dep2 == 1 -> rs2 == recent_rd[0];
    dep1 == 2 -> rs1 == recent_rd[1];  dep2 == 2 -> rs2 == recent_rd[1];
    dep1 == 3 -> rs1 == recent_rd[2];  dep2 == 3 -> rs2 == recent_rd[2];
    dep1 == 4 -> rs1 == recent_rd[3];  dep2 == 4 -> rs2 == recent_rd[3];
    dep1 == 5 -> rs1 == recent_rd[4];  dep2 == 5 -> rs2 == recent_rd[4];
    dep1 == 6 -> rs1 == recent_rd[5];  dep2 == 6 -> rs2 == recent_rd[5];
  }

  // loads and stores address through the base register; branches may compare
  // a register with itself so the direction is known in advance
  constraint c_regs {
    kind inside {K_LOAD, K_STORE} -> rs1 == r_base;
    self_cmp dist {1 := cfg.p_self_cmp, 0 := 100 - cfg.p_self_cmp};
    (kind == K_BRANCH && self_cmp) -> rs2 == rs1;
  }

  // immediates: boundary classes or anything
  function void post_randomize();
    special = $urandom_range(99) < cfg.p_special;
    imm12 = 12'($urandom());
    imm20 = 20'($urandom());
    shamt = 5'($urandom());
    if (special) begin
      case ($urandom_range(6))
        0: begin imm12 = 12'h000; imm20 = 20'h00000; end
        1: imm12 = 12'h001;
        2: begin imm12 = 12'hfff; imm20 = 20'hfffff; end   // -1
        3: begin imm12 = 12'h7ff; imm20 = 20'h7ffff; end   // largest positive
        4: begin imm12 = 12'h800; imm20 = 20'h80000; end   // most negative
        5: imm12 = 12'(2 + $urandom_range(14));
        default: imm12 = 12'hff0 + 12'($urandom_range(14));
      endcase
      case ($urandom_range(2))
        0: shamt = 5'd0;
        1: shamt = 5'd1;
        default: shamt = 5'd31;
      endcase
    end
  endfunction
endclass

// ------------------------------------------------------------- program
class rv_program;
  bit [31:0]   words [bit [31:0]];   // byte address -> word, code and data
  bit [31:0]   code  [$];            // code words in order from base
  string       notes [$];
  bit [31:0]   base;
  bit [31:0]   tohost;
  int unsigned n_instr;
  bit          ends_in_trap;
  string       end_kind;

  function void dump(string path);
    int fd = $fopen(path, "w");
    if (fd == 0) return;
    foreach (code[i])
      $fdisplay(fd, "%08h: %08h  %-28s %s", base + 4 * i, code[i], iss_disasm(code[i]), notes[i]);
    $fclose(fd);
  endfunction
endclass

// --------------------------------------------------------------- generator
class rv_gen;
  rv_gen_cfg cfg;
  rv_instr   ins;

  localparam bit [31:0] DATA_BASE = 32'h8010_0000;   // data region
  localparam bit [31:0] TOHOST    = 32'h8020_0000;
  localparam bit [31:0] BASE_VAL  = DATA_BASE + 32'd2048;

  // slot fixups, resolved once the whole program is laid out
  typedef enum bit [1:0] {FIX_NONE, FIX_B, FIX_J, FIX_JALR} fix_e;
  bit [31:0] slot_word [$];
  bit        slot_target_ok [$];
  fix_e      slot_fix [$];
  int        slot_target [$];
  int        slot_ref [$];          // JALR: index of its AUIPC
  string     slot_note [$];

  bit [4:0]  r_base, r_tmp, r_cnt;
  bit [4:0]  recent [$];
  bit [31:0] recent_addr [$];
  int unsigned seed;

  function new(int unsigned seed);
    this.seed = seed;
    cfg = new;
    ins = new;
  endfunction

  // ----------------------------------------------------------- encoders
  static function bit [31:0] enc_r(bit [6:0] f7, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] f3, bit [4:0] rd, bit [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction
  static function bit [31:0] enc_i(bit [11:0] imm, bit [4:0] rs1, bit [2:0] f3, bit [4:0] rd, bit [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction
  static function bit [31:0] enc_s(bit [11:0] imm, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] f3);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
  endfunction
  static function bit [31:0] enc_b(bit [12:0] off, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] f3);
    return {off[12], off[10:5], rs2, rs1, f3, off[4:1], off[11], 7'b1100011};
  endfunction
  static function bit [31:0] enc_u(bit [19:0] imm, bit [4:0] rd, bit [6:0] op);
    return {imm, rd, op};
  endfunction
  static function bit [31:0] enc_j(bit [20:0] off, bit [4:0] rd);
    return {off[20], off[10:1], off[11], off[19:12], rd, 7'b1101111};
  endfunction

  // ------------------------------------------------------------ helpers
  function void emit(bit [31:0] w, string note = "", bit target_ok = 1, fix_e fix = FIX_NONE,
                     int target = -1, int ref_slot = -1);
    slot_word.push_back(w);
    slot_target_ok.push_back(target_ok);
    slot_fix.push_back(fix);
    slot_target.push_back(target);
    slot_ref.push_back(ref_slot);
    slot_note.push_back(note);
  endfunction

  function void note_rd(bit [4:0] rd);
    recent.push_front(rd);
    if (recent.size() > 6) void'(recent.pop_back());
  endfunction

  // load a 32-bit constant: lui + addi (addi alone when it fits)
  function void emit_li(bit [4:0] rd, bit [31:0] v, string note = "", bit ok_second = 0);
    bit [19:0] hi = 20'((v + 32'h800) >> 12);
    bit [11:0] lo = v[11:0];
    if ($signed(v) >= -2048 && $signed(v) < 2048) begin
      emit(enc_i(lo, 5'd0, 3'b000, rd, 7'b0010011), note);
    end else begin
      emit(enc_u(hi, rd, 7'b0110111), note);
      emit(enc_i(lo, rd, 3'b000, rd, 7'b0010011), note, ok_second);
    end
  endfunction

  function bit [31:0] interesting_value();
    case ($urandom_range(11))
      0:  return 32'h0000_0000;
      1:  return 32'h0000_0001;
      2:  return 32'hffff_ffff;
      3:  return 32'h7fff_ffff;
      4:  return 32'h8000_0000;
      5:  return 32'h0000_00ff;
      6:  return 32'hffff_ff80;
      7:  return 32'h0000_8000;
      8:  return 32'(int'($urandom_range(100)));
      9:  return -32'(int'($urandom_range(100)));
      default: return $urandom();
    endcase
  endfunction

  function bit [31:0] data_word();
    case ($urandom_range(7))
      0: return 32'h8080_8080;
      1: return 32'h7f7f_7f7f;
      2: return 32'hffff_ffff;
      3: return 32'h0000_0000;
      4: return 32'h8000_7fff;
      5: return 32'h00ff_ff00;
      default: return $urandom();
    endcase
  endfunction

  // address for a load/store: inside the window, aligned for its size,
  // and with p_alias probability one that was used recently
  function bit [11:0] mem_offset(bit [2:0] f3);
    bit [31:0] addr;
    int unsigned size = 1 << f3[1:0];
    if (recent_addr.size() > 0 && $urandom_range(99) < cfg.p_alias)
      addr = recent_addr[$urandom_range(recent_addr.size() - 1)];
    else
      addr = DATA_BASE + $urandom_range(cfg.mem_window - 1);
    addr = addr & ~(size - 1);
    recent_addr.push_front(addr);
    if (recent_addr.size() > 8) void'(recent_addr.pop_back());
    return 12'(addr - BASE_VAL);
  endfunction

  // ------------------------------------------------------- one instruction
  function void gen_one(bit in_loop);
    ins.cfg = cfg;
    ins.r_base = r_base; ins.r_tmp = r_tmp; ins.r_cnt = r_cnt;
    ins.in_loop = in_loop;
    foreach (ins.recent_rd[k]) ins.recent_rd[k] = (k < recent.size()) ? recent[k] : 5'd0;
    if (ins.randomize() == 0) $fatal(1, "[gen] randomize failed");

    case (ins.kind)
      K_ALU_R: begin
        emit(enc_r({1'b0, ins.alt, 5'b0}, ins.rs2, ins.rs1, ins.f3, ins.rd, 7'b0110011));
        note_rd(ins.rd);
      end
      K_ALU_I: begin
        emit(enc_i(ins.imm12, ins.rs1, ins.f3, ins.rd, 7'b0010011));
        note_rd(ins.rd);
      end
      K_SHIFT_I: begin
        emit(enc_i({1'b0, ins.alt, 5'b0, ins.shamt}, ins.rs1, ins.f3, ins.rd, 7'b0010011));
        note_rd(ins.rd);
      end
      K_LUI, K_AUIPC: begin
        // Field aliasing: half the time the bits where an rs1 field would be
        // (imm20[7:3] = insn[19:15]) name the previous destination. The
        // instruction does not read rs1, so a hazard unit that forgets to
        // check "is this field a real source" stalls for nothing.
        bit [19:0] im = ins.imm20;
        if (recent.size() > 0 && $urandom_range(1)) im[7:3] = recent[0];
        emit(enc_u(im, ins.rd, ins.kind == K_LUI ? 7'b0110111 : 7'b0010111));
        note_rd(ins.rd);
      end
      K_LOAD: begin
        emit(enc_i(mem_offset(ins.f3), r_base, ins.f3, ins.rd, 7'b0000011));
        note_rd(ins.rd);
      end
      K_STORE: begin
        emit(enc_s(mem_offset(ins.f3), ins.rs2, r_base, ins.f3));
        note_rd(5'd0);
      end
      K_BRANCH: begin
        int t = slot_word.size() + 1 + $urandom_range(cfg.skip_max);
        emit(enc_b(13'd0, ins.rs2, ins.rs1, ins.f3), ins.self_cmp ? "self-compare" : "",
             1, FIX_B, t);
        note_rd(5'd0);
      end
      K_JAL: begin
        int t = slot_word.size() + 1 + $urandom_range(cfg.skip_max);
        emit(enc_j(21'd0, ins.rd), "", 1, FIX_J, t);
        note_rd(ins.rd);
      end
      K_JALR: begin
        // auipc tmp, 0 ; 0-2 independent fillers ; jalr rd, off(tmp)
        int a = slot_word.size();
        int nfill = $urandom_range(4);
        emit(enc_u(20'd0, r_tmp, 7'b0010111), "jalr base");
        for (int i = 0; i < nfill; i++) begin
          bit [4:0] frd;
          do frd = 5'($urandom_range(31)); while (frd == 0 || frd == r_base || frd == r_tmp || frd == r_cnt);
          emit(enc_i(12'($urandom_range(4095)), 5'($urandom_range(31)), 3'b100, frd, 7'b0010011), "", 0);
        end
        emit(32'h0000_0067 | (32'(ins.rd) << 7) | (32'(r_tmp) << 15), "", 0, FIX_JALR,
             slot_word.size() + 1 + $urandom_range(cfg.skip_max - 1), a);
        note_rd(ins.rd);
      end
      K_FENCE: begin
        // FENCE iorw,iorw (pred = succ = 1111) or FENCE.I
        emit(ins.f3[0] ? 32'h0000_100f : 32'h0ff0_000f);
        note_rd(5'd0);
      end
      K_SEED: begin
        // put a boundary value (0, 1, -1, max, min, ...) into a register so the
        // operand-class crosses see them; later instructions depend on it
        emit_li(ins.rd, interesting_value(), "seed value");
        note_rd(ins.rd);
      end
      K_RELOAD: begin
        // re-materialize the base register so address operands get forwarded too
        emit_li(r_base, BASE_VAL, "reload base");
        note_rd(r_base);
      end
      default: ;
    endcase
  endfunction

  // counted loop: li cnt, N ; body ; addi cnt, cnt, -1 ; bne cnt, x0, body
  function void gen_loop();
    int n = 2 + $urandom_range(3);
    int len = 3 + $urandom_range(8);
    int head;
    emit(enc_i(12'(n), 5'd0, 3'b000, r_cnt, 7'b0010011), $sformatf("loop x%0d", n));
    head = slot_word.size();
    for (int i = 0; i < len; i++) begin
      int s = slot_word.size();
      gen_one(1);
      for (int j = s; j < slot_word.size(); j++) slot_target_ok[j] = 0;
    end
    emit(enc_i(12'hfff, r_cnt, 3'b000, r_cnt, 7'b0010011), "loop count", 0);
    emit(32'd0, "loop back", 0, FIX_B, head);
    slot_word[slot_word.size() - 1] = enc_b(13'd0, 5'd0, r_cnt, 3'b001);   // bne cnt, x0
    note_rd(5'd0);
  endfunction

  // ---------------------------------------------------------------- top
  function rv_program generate_program(bit [31:0] base);
    rv_program p = new;
    int body_start, end_slot;
    process::self().srandom(seed);
    ins.srandom(seed);
    p.base = base;
    p.tohost = TOHOST;

    // reserved registers differ per seed so every register gets used across a regression
    begin
      bit [4:0] pool [$];
      for (int r = 1; r < 32; r++) pool.push_back(5'(r));
      pool.shuffle();
      r_base = pool[0]; r_tmp = pool[1]; r_cnt = pool[2];
    end

    // preamble: every register gets an interesting value, the base register its address
    for (int r = 1; r < 32; r++) begin
      if (5'(r) == r_base) emit_li(5'(r), BASE_VAL, "base");
      else                 emit_li(5'(r), interesting_value(), "init");
    end
    // data region contents (both memories get them through prog.words)
    for (bit [31:0] a = DATA_BASE - 32'd64; a < DATA_BASE + cfg.mem_window + 32'd64; a += 4)
      p.words[a] = data_word();

    body_start = slot_word.size();
    while (slot_word.size() - body_start < cfg.n_instr) begin
      if ($urandom_range(99) < cfg.p_loop) gen_loop();
      else                                 gen_one(0);
    end

    // ending: tohost write or an exception
    end_slot = slot_word.size();
    p.ends_in_trap = $urandom_range(99) < cfg.p_end_trap;
    if (p.ends_in_trap) begin
      case ($urandom_range(5))
        0: begin p.end_kind = "ecall";   emit(32'h0000_0073, "end: ecall"); end
        1: begin p.end_kind = "ebreak";  emit(32'h0010_0073, "end: ebreak"); end
        2: begin p.end_kind = "illegal"; emit(32'h0000_0000, "end: illegal"); end
        4: begin p.end_kind = "misaligned store";
             emit(enc_s(12'(DATA_BASE + 2 - BASE_VAL), 5'd1, r_base, 3'b010), "end: misaligned sw");
           end
        3: begin p.end_kind = "misaligned load";
             emit(enc_i(12'(DATA_BASE + 1 - BASE_VAL), r_base, 3'b010, 5'd1, 7'b0000011), "end: misaligned lw");
             // the base register may have been reloaded but always holds BASE_VAL
           end
        default: begin p.end_kind = "misaligned jump";
             emit(enc_j(21'd6, 5'd1), "end: jal +6");
           end
      endcase
    end else begin
      p.end_kind = "tohost";
      emit_li(r_tmp, TOHOST, "end: tohost", 1);
      emit(enc_i(12'd1, 5'd0, 3'b000, r_cnt, 7'b0010011), "end");
      emit(enc_s(12'd0, r_cnt, r_tmp, 3'b010), "end: pass");
    end
    if (p.ends_in_trap) begin
      // wrong-path instructions behind the trap: fetched, never retired.
      // Either a taken branch (the trap must win over the redirect) or a
      // load-use pair (the trap must win over the stall).
      bit [4:0] r = (r_cnt == 5'd5) ? 5'd6 : 5'd5;
      if ($urandom_range(1)) emit(enc_b(13'd8, 5'd0, 5'd0, 3'b000), "shadow: beq taken");
      emit(enc_i(12'(DATA_BASE - BASE_VAL), r_base, 3'b010, r, 7'b0000011), "shadow: lw");
      emit(enc_r(7'd0, r, r, 3'b000, r, 7'b0110011), "shadow: add");
      emit(enc_s(12'(DATA_BASE - BASE_VAL), r, r_base, 3'b010), "shadow: sw");
    end
    emit(enc_j(21'd0, 5'd0), "end: j .");

    // resolve control-flow targets: clamp to the end, skip non-target slots
    foreach (slot_word[i]) begin
      int t = slot_target[i];
      if (slot_fix[i] == FIX_NONE) continue;
      if (slot_fix[i] != FIX_B || t > i) begin
        if (t > end_slot) t = end_slot;
        while (t < end_slot && !slot_target_ok[t]) t++;
      end
      case (slot_fix[i])
        FIX_B: begin
          bit [31:0] w = slot_word[i];
          slot_word[i] = enc_b(13'((t - i) * 4), w[24:20], w[19:15], w[14:12]);
        end
        FIX_J: slot_word[i] = enc_j(21'((t - i) * 4), slot_word[i][11:7]);
        FIX_JALR: begin
          // target relative to the auipc; odd offsets check that JALR clears bit 0
          int off = (t - slot_ref[i]) * 4 + ($urandom_range(3) == 0 ? 1 : 0);
          slot_word[i] = enc_i(12'(off), slot_word[i][19:15], 3'b000, slot_word[i][11:7], 7'b1100111);
        end
        default: ;
      endcase
    end

    foreach (slot_word[i]) begin
      p.words[base + 4 * i] = slot_word[i];
      p.code.push_back(slot_word[i]);
      p.notes.push_back(slot_note[i]);
    end
    p.n_instr = slot_word.size();
    return p;
  endfunction
endclass
