#!/usr/bin/env bash
# Build the Verilator simulation of tb_top.
#   build_sim.sh <out_dir> [extra verilator args, e.g. -DBUG_XYZ]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"
OUT="$(mkdir -p "${1:?out dir}" && cd "$1" && pwd)"; shift
mkdir -p "$OUT"
JOBS="${JOBS:-$(nproc)}"
verilator --binary --timing --assert --coverage-user -j "$JOBS" \
  --timescale 1ns/1ps --top-module tb_top \
  -Wno-UNDRIVEN -Wno-PROCASSINIT -Wno-WIDTH \
  -I"$ROOT/rtl" -I"$ROOT/tb" \
  --Mdir "$OUT/obj" -o "$OUT/simv" \
  "$@" \
  "$ROOT/rtl/rv32_pkg.sv" \
  "$ROOT/rtl/rv32_alu.sv" "$ROOT/rtl/rv32_regfile.sv" "$ROOT/rtl/rv32_decoder.sv" \
  "$ROOT/rtl/rv32_fetch.sv" "$ROOT/rtl/rv32_decode.sv" "$ROOT/rtl/rv32_execute.sv" \
  "$ROOT/rtl/rv32_memory.sv" "$ROOT/rtl/rv32_writeback.sv" "$ROOT/rtl/rv32_hazard.sv" \
  "$ROOT/rtl/rv32_core.sv" \
  "$ROOT/tb/rv32_bus_if.sv" "$ROOT/tb/rvfi_if.sv" "$ROOT/tb/pipe_probe_if.sv" \
  $(ls "$ROOT"/tb/sva/*.sv 2>/dev/null) \
  "$ROOT/tb/tb_pkg.sv" "$ROOT/tb/tb_top.sv" \
  "$ROOT/model/rv32_iss.cpp" "$ROOT/model/iss_dpi.cpp" \
  -CFLAGS "-std=c++17 -I$ROOT/model"
