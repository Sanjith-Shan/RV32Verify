// rv32_iss.cpp
// RV32I reference model. See rv32_iss.h for the reporting conventions.
#include "rv32_iss.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>

namespace rv32 {

// ------------------------------------------------------------------ memory
uint8_t Memory::read8(uint32_t a) const {
  auto it = pages_.find(a >> 12);
  return it == pages_.end() ? 0 : it->second[a & 0xfff];
}

void Memory::write8(uint32_t a, uint8_t v) {
  auto& p = pages_[a >> 12];
  if (p.empty()) p.assign(4096, 0);
  p[a & 0xfff] = v;
}

uint32_t Memory::read32(uint32_t a) const {
  return uint32_t(read8(a)) | uint32_t(read8(a + 1)) << 8 |
         uint32_t(read8(a + 2)) << 16 | uint32_t(read8(a + 3)) << 24;
}

void Memory::write32(uint32_t a, uint32_t v) {
  for (int i = 0; i < 4; i++) write8(a + i, uint8_t(v >> (8 * i)));
}

// --------------------------------------------------------------- helpers
namespace {

inline uint32_t bits(uint32_t v, int hi, int lo) {
  return (v >> lo) & ((hi - lo == 31) ? 0xffffffffu : ((1u << (hi - lo + 1)) - 1));
}
inline int32_t sext(uint32_t v, int width) {
  uint32_t m = 1u << (width - 1);
  v &= (width == 32) ? 0xffffffffu : ((1u << width) - 1);
  return int32_t((v ^ m) - m);
}

// Immediate formats, ISA spec chapter 2.3.
inline int32_t imm_i(uint32_t in) { return sext(in >> 20, 12); }
inline int32_t imm_s(uint32_t in) { return sext((bits(in, 31, 25) << 5) | bits(in, 11, 7), 12); }
inline int32_t imm_b(uint32_t in) {
  return sext((bits(in, 31, 31) << 12) | (bits(in, 7, 7) << 11) |
              (bits(in, 30, 25) << 5) | (bits(in, 11, 8) << 1), 13);
}
inline uint32_t imm_u(uint32_t in) { return in & 0xfffff000u; }
inline int32_t imm_j(uint32_t in) {
  return sext((bits(in, 31, 31) << 20) | (bits(in, 19, 12) << 12) |
              (bits(in, 20, 20) << 11) | (bits(in, 30, 21) << 1), 21);
}

}  // namespace

// ------------------------------------------------------------------ hart
void Iss::reset(uint32_t pc) {
  std::memset(x_, 0, sizeof(x_));
  pc_ = pc;
  halted_ = false;
  retired_ = 0;
}

bool Iss::load_hex(const std::string& path, uint32_t base) {
  std::ifstream f(path);
  if (!f) return false;
  std::string tok;
  uint32_t idx = 0;
  while (f >> tok) {
    if (tok.rfind("//", 0) == 0) { std::getline(f, tok); continue; }
    if (tok[0] == '@') { idx = uint32_t(std::stoul(tok.substr(1), nullptr, 16)); continue; }
    mem_.write32(base + 4 * idx, uint32_t(std::stoul(tok, nullptr, 16)));
    idx++;
  }
  return true;
}

Retire Iss::step() {
  Retire r;
  const uint32_t in = mem_.read32(pc_);
  r.pc = pc_;
  r.insn = in;

  const uint32_t opcode = bits(in, 6, 0);
  const uint32_t rd = bits(in, 11, 7);
  const uint32_t f3 = bits(in, 14, 12);
  const uint32_t rs1 = bits(in, 19, 15);
  const uint32_t rs2 = bits(in, 24, 20);
  const uint32_t f7 = bits(in, 31, 25);
  const uint32_t a = x_[rs1];
  const uint32_t b = x_[rs2];

  bool reads1 = false, reads2 = false, writes = false;
  uint32_t wval = 0;
  uint32_t npc = pc_ + 4;
  bool trap = false;
  uint32_t cause = 0;

  auto illegal = [&] { trap = true; cause = kIllegal; };

  switch (opcode) {
    case 0x37:  // LUI
      writes = true; wval = imm_u(in);
      break;
    case 0x17:  // AUIPC
      writes = true; wval = pc_ + imm_u(in);
      break;
    case 0x6f: {  // JAL
      uint32_t t = pc_ + uint32_t(imm_j(in));
      if (t & 3) { trap = true; cause = kInsnMisaligned; break; }
      writes = true; wval = pc_ + 4; npc = t;
      break;
    }
    case 0x67: {  // JALR
      if (f3 != 0) { illegal(); break; }
      reads1 = true;
      uint32_t t = (a + uint32_t(imm_i(in))) & ~1u;
      if (t & 3) { trap = true; cause = kInsnMisaligned; break; }
      writes = true; wval = pc_ + 4; npc = t;
      break;
    }
    case 0x63: {  // BRANCH
      bool take;
      switch (f3) {
        case 0: take = a == b; break;
        case 1: take = a != b; break;
        case 4: take = int32_t(a) < int32_t(b); break;
        case 5: take = int32_t(a) >= int32_t(b); break;
        case 6: take = a < b; break;
        case 7: take = a >= b; break;
        default: illegal(); take = false; break;
      }
      if (trap) break;
      reads1 = reads2 = true;
      if (take) {
        uint32_t t = pc_ + uint32_t(imm_b(in));
        if (t & 3) { trap = true; cause = kInsnMisaligned; break; }
        npc = t;
      }
      break;
    }
    case 0x03: {  // LOAD
      if (f3 == 3 || f3 == 6 || f3 == 7) { illegal(); break; }
      reads1 = true;
      uint32_t ea = a + uint32_t(imm_i(in));
      unsigned size = 1u << (f3 & 3);
      if (ea & (size - 1)) { trap = true; cause = kLoadMisaligned; break; }
      uint32_t word = mem_.read32(ea & ~3u);
      uint32_t sh = (ea & 3) * 8;
      uint32_t raw = word >> sh;
      switch (f3) {
        case 0: wval = uint32_t(sext(raw, 8)); break;
        case 1: wval = uint32_t(sext(raw, 16)); break;
        case 2: wval = raw; break;
        case 4: wval = raw & 0xff; break;
        case 5: wval = raw & 0xffff; break;
      }
      writes = true;
      r.mem_addr = ea & ~3u;
      r.mem_rmask = ((1u << size) - 1) << (ea & 3);
      r.mem_rdata = word;
      break;
    }
    case 0x23: {  // STORE
      if (f3 > 2) { illegal(); break; }
      reads1 = reads2 = true;
      uint32_t ea = a + uint32_t(imm_s(in));
      unsigned size = 1u << f3;
      if (ea & (size - 1)) { trap = true; cause = kStoreMisaligned; break; }
      for (unsigned i = 0; i < size; i++) mem_.write8(ea + i, uint8_t(b >> (8 * i)));
      r.mem_addr = ea & ~3u;
      r.mem_wmask = ((1u << size) - 1) << (ea & 3);
      r.mem_wdata = (size == 4 ? b : (b & ((1u << (8 * size)) - 1))) << ((ea & 3) * 8);
      break;
    }
    case 0x13: {  // OP-IMM
      reads1 = true;
      int32_t imm = imm_i(in);
      uint32_t sh = bits(in, 24, 20);
      switch (f3) {
        case 0: wval = a + uint32_t(imm); break;
        case 2: wval = int32_t(a) < imm; break;
        case 3: wval = a < uint32_t(imm); break;
        case 4: wval = a ^ uint32_t(imm); break;
        case 6: wval = a | uint32_t(imm); break;
        case 7: wval = a & uint32_t(imm); break;
        case 1:
          if (f7 != 0) { illegal(); break; }
          wval = a << sh; break;
        case 5:
          if (f7 == 0x00) wval = a >> sh;
          else if (f7 == 0x20) wval = uint32_t(int32_t(a) >> sh);
          else illegal();
          break;
      }
      if (trap) { reads1 = false; break; }
      writes = true;
      break;
    }
    case 0x33: {  // OP
      uint32_t sh = b & 31;
      bool ok = true;
      if (f7 == 0x00) {
        switch (f3) {
          case 0: wval = a + b; break;
          case 1: wval = a << sh; break;
          case 2: wval = int32_t(a) < int32_t(b); break;
          case 3: wval = a < b; break;
          case 4: wval = a ^ b; break;
          case 5: wval = a >> sh; break;
          case 6: wval = a | b; break;
          case 7: wval = a & b; break;
        }
      } else if (f7 == 0x20 && f3 == 0) {
        wval = a - b;
      } else if (f7 == 0x20 && f3 == 5) {
        wval = uint32_t(int32_t(a) >> sh);
      } else {
        ok = false;
      }
      if (!ok) { illegal(); break; }
      reads1 = reads2 = true; writes = true;
      break;
    }
    case 0x0f:  // MISC-MEM: FENCE is a no-op, FENCE.I has no visible effect here
      if (f3 != 0 && f3 != 1) illegal();
      break;
    case 0x73:  // SYSTEM
      trap = true;
      cause = in == 0x00000073 ? kEcallM : in == 0x00100073 ? kBreakpoint : kIllegal;
      break;
    default:
      illegal();
      break;
  }

  if (reads1) { r.rs1_addr = rs1; r.rs1_rdata = a; }
  if (reads2) { r.rs2_addr = rs2; r.rs2_rdata = b; }

  if (trap) {
    r.trap = true;
    r.cause = cause;
    r.pc_wdata = 0;
    halted_ = true;
  } else {
    if (writes && rd != 0) {
      x_[rd] = wval;
      r.rd_addr = rd;
      r.rd_wdata = wval;
    }
    r.pc_wdata = npc;
    pc_ = npc;
  }
  retired_++;
  return r;
}

// ------------------------------------------------------------ disassembly
namespace {
const char* kAbi[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
                        "s0",   "s1", "a0", "a1", "a2", "a3", "a4", "a5",
                        "a6",   "a7", "s2", "s3", "s4", "s5", "s6", "s7",
                        "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6"};
}

std::string disasm(uint32_t in) {
  const uint32_t op = bits(in, 6, 0), rd = bits(in, 11, 7), f3 = bits(in, 14, 12);
  const uint32_t rs1 = bits(in, 19, 15), rs2 = bits(in, 24, 20), f7 = bits(in, 31, 25);
  char buf[96];
  auto R = [](uint32_t r) { return kAbi[r & 31]; };
  switch (op) {
    case 0x37: snprintf(buf, sizeof buf, "lui     %s, 0x%x", R(rd), in >> 12); break;
    case 0x17: snprintf(buf, sizeof buf, "auipc   %s, 0x%x", R(rd), in >> 12); break;
    case 0x6f: snprintf(buf, sizeof buf, "jal     %s, %d", R(rd), imm_j(in)); break;
    case 0x67: snprintf(buf, sizeof buf, "jalr    %s, %d(%s)", R(rd), imm_i(in), R(rs1)); break;
    case 0x63: {
      static const char* n[8] = {"beq", "bne", "b?2", "b?3", "blt", "bge", "bltu", "bgeu"};
      snprintf(buf, sizeof buf, "%-7s %s, %s, %d", n[f3], R(rs1), R(rs2), imm_b(in));
      break;
    }
    case 0x03: {
      static const char* n[8] = {"lb", "lh", "lw", "l?3", "lbu", "lhu", "l?6", "l?7"};
      snprintf(buf, sizeof buf, "%-7s %s, %d(%s)", n[f3], R(rd), imm_i(in), R(rs1));
      break;
    }
    case 0x23: {
      static const char* n[8] = {"sb", "sh", "sw", "s?3", "s?4", "s?5", "s?6", "s?7"};
      snprintf(buf, sizeof buf, "%-7s %s, %d(%s)", n[f3], R(rs2), imm_s(in), R(rs1));
      break;
    }
    case 0x13: {
      static const char* n[8] = {"addi", "slli", "slti", "sltiu", "xori", "srli", "ori", "andi"};
      if (f3 == 1 || f3 == 5) {
        const char* m = f3 == 1 ? "slli" : (f7 & 0x20) ? "srai" : "srli";
        snprintf(buf, sizeof buf, "%-7s %s, %s, %u", m, R(rd), R(rs1), rs2);
      } else {
        snprintf(buf, sizeof buf, "%-7s %s, %s, %d", n[f3], R(rd), R(rs1), imm_i(in));
      }
      break;
    }
    case 0x33: {
      static const char* n[8] = {"add", "sll", "slt", "sltu", "xor", "srl", "or", "and"};
      const char* m = n[f3];
      if (f7 == 0x20 && f3 == 0) m = "sub";
      if (f7 == 0x20 && f3 == 5) m = "sra";
      snprintf(buf, sizeof buf, "%-7s %s, %s, %s", m, R(rd), R(rs1), R(rs2));
      break;
    }
    case 0x0f: snprintf(buf, sizeof buf, f3 == 1 ? "fence.i" : "fence"); break;
    case 0x73:
      snprintf(buf, sizeof buf, "%s", in == 0x73 ? "ecall" : in == 0x00100073 ? "ebreak" : "system?");
      break;
    default: snprintf(buf, sizeof buf, ".word   0x%08x", in); break;
  }
  return buf;
}

}  // namespace rv32
