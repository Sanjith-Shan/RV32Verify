// rv32_iss.h
// RV32I instruction set simulator: the functional (reference) model.
//
// Written from the RISC-V Unprivileged ISA specification, independently of
// the RTL. It executes one instruction per step() and returns a retirement
// record in the same format as the core's RVFI port, so the scoreboard can
// compare the two field by field.
//
// Conventions shared with the RTL's RVFI port (documented in docs/):
//   * rs1/rs2 are reported only when the instruction reads them, else 0.
//   * rd_addr/rd_wdata are 0 when nothing is written (or rd = x0).
//   * Memory is reported word-aligned: mem_addr = addr & ~3, the masks
//     select byte lanes, wdata is lane-shifted, rdata is the full bus word.
//   * An exception retires with trap = 1, no side effects, pc_wdata = 0,
//     and halts the hart (this configuration has no CSRs / trap vector).
#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace rv32 {

struct Retire {
  uint32_t pc = 0, insn = 0;
  uint32_t rs1_addr = 0, rs2_addr = 0, rs1_rdata = 0, rs2_rdata = 0;
  uint32_t rd_addr = 0, rd_wdata = 0;
  uint32_t pc_wdata = 0;
  uint32_t mem_addr = 0, mem_rmask = 0, mem_wmask = 0, mem_rdata = 0, mem_wdata = 0;
  bool trap = false;
  uint32_t cause = 0;
};

// Sparse byte-addressable memory, 4 KiB pages allocated on first touch.
class Memory {
 public:
  uint8_t read8(uint32_t a) const;
  void write8(uint32_t a, uint8_t v);
  uint32_t read32(uint32_t a) const;       // little endian, any alignment
  void write32(uint32_t a, uint32_t v);
  void clear() { pages_.clear(); }

 private:
  std::unordered_map<uint32_t, std::vector<uint8_t>> pages_;
};

enum Cause : uint32_t {
  kInsnMisaligned = 0,
  kIllegal = 2,
  kBreakpoint = 3,
  kLoadMisaligned = 4,
  kStoreMisaligned = 6,
  kEcallM = 11,
};

class Iss {
 public:
  void reset(uint32_t pc);
  Retire step();                           // execute one instruction

  // Load a $readmemh-style word hex file: "@<word index>" address lines,
  // one 32-bit word per line. Word index i maps to byte address base + 4*i.
  bool load_hex(const std::string& path, uint32_t base);

  Memory& mem() { return mem_; }
  uint32_t pc() const { return pc_; }
  uint32_t reg(unsigned i) const { return i ? x_[i & 31] : 0; }
  bool halted() const { return halted_; }
  uint64_t retired() const { return retired_; }

 private:
  uint32_t x_[32] = {};
  uint32_t pc_ = 0;
  bool halted_ = false;
  uint64_t retired_ = 0;
  Memory mem_;
};

// One-line disassembly, objdump style with ABI register names.
std::string disasm(uint32_t insn);

}  // namespace rv32
