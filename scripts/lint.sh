#!/usr/bin/env bash
# Lint the RTL alone with every Verilator warning enabled.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"
verilator --lint-only -Wall --top-module rv32_core "$@" \
  "$ROOT/rtl/rv32_pkg.sv" "$ROOT/rtl/rv32_alu.sv" "$ROOT/rtl/rv32_regfile.sv" \
  "$ROOT/rtl/rv32_decoder.sv" "$ROOT/rtl/rv32_fetch.sv" "$ROOT/rtl/rv32_decode.sv" \
  "$ROOT/rtl/rv32_execute.sv" "$ROOT/rtl/rv32_memory.sv" "$ROOT/rtl/rv32_writeback.sv" \
  "$ROOT/rtl/rv32_hazard.sv" "$ROOT/rtl/rv32_core.sv"
echo "lint clean: rtl/ with -Wall"
