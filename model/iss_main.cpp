// iss_main.cpp
// Standalone runner for the reference model. Used to qualify the ISS on the
// official riscv-tests before trusting it as the bench's golden model.
//
//   rv32iss <prog.hex> [--base 0x80000000] [--tohost ADDR] [--max N] [--trace]
//
// Exit code 0 when the program writes 1 to tohost, 1 otherwise.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rv32_iss.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s prog.hex [--base A] [--tohost A] [--max N] [--trace]\n", argv[0]);
    return 2;
  }
  std::string hex = argv[1];
  uint32_t base = 0x80000000u, tohost = 0x80001000u;
  uint64_t max = 1000000;
  bool trace = false;
  for (int i = 2; i < argc; i++) {
    if (!std::strcmp(argv[i], "--base") && i + 1 < argc) base = std::strtoul(argv[++i], nullptr, 0);
    else if (!std::strcmp(argv[i], "--tohost") && i + 1 < argc) tohost = std::strtoul(argv[++i], nullptr, 0);
    else if (!std::strcmp(argv[i], "--max") && i + 1 < argc) max = std::strtoull(argv[++i], nullptr, 0);
    else if (!std::strcmp(argv[i], "--trace")) trace = true;
  }
  rv32::Iss iss;
  iss.reset(base);
  if (!iss.load_hex(hex, base)) { std::fprintf(stderr, "cannot read %s\n", hex.c_str()); return 2; }

  for (uint64_t n = 0; n < max; n++) {
    rv32::Retire r = iss.step();
    if (trace) {
      std::printf("%8llu %08x %08x %-32s", (unsigned long long)n, r.pc, r.insn, rv32::disasm(r.insn).c_str());
      if (r.rd_addr) std::printf(" x%-2u=%08x", r.rd_addr, r.rd_wdata);
      if (r.mem_wmask) std::printf(" mem[%08x]<=%08x/%x", r.mem_addr, r.mem_wdata, r.mem_wmask);
      if (r.mem_rmask) std::printf(" mem[%08x]=>%08x/%x", r.mem_addr, r.mem_rdata, r.mem_rmask);
      std::printf("\n");
    }
    if (r.trap) {
      std::printf("TRAP cause=%u at pc=%08x insn=%08x after %llu instructions\n", r.cause, r.pc, r.insn,
                  (unsigned long long)n + 1);
      return 1;
    }
    if (r.mem_wmask && r.mem_addr == (tohost & ~3u)) {
      uint32_t v = iss.mem().read32(tohost);
      if (v == 1) {
        std::printf("PASS after %llu instructions\n", (unsigned long long)n + 1);
        return 0;
      }
      std::printf("FAIL test %u after %llu instructions\n", v >> 1, (unsigned long long)n + 1);
      return 1;
    }
  }
  std::printf("TIMEOUT after %llu instructions\n", (unsigned long long)max);
  return 1;
}
