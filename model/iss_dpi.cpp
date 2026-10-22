// iss_dpi.cpp
// DPI-C entry points that let the SystemVerilog bench drive the reference
// model: load the program, step one instruction, read the result back.
#include <string>

#include "rv32_iss.h"

namespace {
rv32::Iss g_iss;
std::string g_dis;
}  // namespace

extern "C" {

void iss_reset(unsigned int pc) {
  g_iss.mem().clear();
  g_iss.reset(pc);
}

int iss_load_hex(const char* path, unsigned int base) {
  return g_iss.load_hex(path, base) ? 1 : 0;
}

void iss_write32(unsigned int addr, unsigned int data) { g_iss.mem().write32(addr, data); }
unsigned int iss_read32(unsigned int addr) { return g_iss.mem().read32(addr); }
unsigned int iss_reg(unsigned int idx) { return g_iss.reg(idx); }
unsigned int iss_pc() { return g_iss.pc(); }

// Execute one instruction; every output mirrors an RVFI field.
void iss_step(unsigned int* pc, unsigned int* insn, unsigned int* rs1_addr,
              unsigned int* rs2_addr, unsigned int* rs1_rdata, unsigned int* rs2_rdata,
              unsigned int* rd_addr, unsigned int* rd_wdata, unsigned int* pc_wdata,
              unsigned int* mem_addr, unsigned int* mem_rmask, unsigned int* mem_wmask,
              unsigned int* mem_rdata, unsigned int* mem_wdata, unsigned int* trap,
              unsigned int* cause) {
  rv32::Retire r = g_iss.step();
  *pc = r.pc; *insn = r.insn;
  *rs1_addr = r.rs1_addr; *rs2_addr = r.rs2_addr;
  *rs1_rdata = r.rs1_rdata; *rs2_rdata = r.rs2_rdata;
  *rd_addr = r.rd_addr; *rd_wdata = r.rd_wdata;
  *pc_wdata = r.pc_wdata;
  *mem_addr = r.mem_addr; *mem_rmask = r.mem_rmask; *mem_wmask = r.mem_wmask;
  *mem_rdata = r.mem_rdata; *mem_wdata = r.mem_wdata;
  *trap = r.trap; *cause = r.cause;
}

const char* iss_disasm(unsigned int insn) {
  g_dis = rv32::disasm(insn);
  return g_dis.c_str();
}

}  // extern "C"
