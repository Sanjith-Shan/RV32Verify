#!/usr/bin/env bash
# Synthesis sanity check: does the RTL synthesize, how big is it, how fast
# could it run. Target: Lattice ECP5 LFE5U-25F (open toolchain: Yosys +
# nextpnr-ecp5). Output: build/synth/{yosys.log,nextpnr.log}, summary on stdout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"
OUT="$ROOT/build/synth"
mkdir -p "$OUT"
SRCS="$ROOT/rtl/rv32_pkg.sv $ROOT/rtl/rv32_alu.sv $ROOT/rtl/rv32_regfile.sv $ROOT/rtl/rv32_decoder.sv \
      $ROOT/rtl/rv32_fetch.sv $ROOT/rtl/rv32_decode.sv $ROOT/rtl/rv32_execute.sv $ROOT/rtl/rv32_memory.sv \
      $ROOT/rtl/rv32_writeback.sv $ROOT/rtl/rv32_hazard.sv $ROOT/rtl/rv32_core.sv $ROOT/synth/rv32_synth_top.sv"

yosys -m slang -l "$OUT/yosys.log" -q -p "read_slang --top rv32_synth_top $SRCS; \
  synth_ecp5 -top rv32_synth_top -json $OUT/rv32_core.json; tee -o $OUT/stat.txt stat"
# top = synth/rv32_synth_top.sv (memory ports only, RVFI left open); pins unconstrained
nextpnr-ecp5 --25k --package CABGA381 --json "$OUT/rv32_core.json" --freq 100 \
  --timing-allow-fail --seed 1 -l "$OUT/nextpnr.log" -q >/dev/null 2>&1 || true

echo "== cells (Yosys synth_ecp5) =="
grep -E "^\s+[0-9]+ .*(LUT4|TRELLIS_FF|CCU2C|DP16KD|TRELLIS_DPR16X4|MULT18X18D)" "$OUT/stat.txt" || grep -E "LUT4|TRELLIS_FF|CCU2C" "$OUT/stat.txt"
echo "== timing (nextpnr-ecp5, 25k, speed 6) =="
grep -E "Max frequency for clock" "$OUT/nextpnr.log" | tail -1
grep -E "Device utilisation" -A 14 "$OUT/nextpnr.log" | grep -E "TRELLIS_IO|TRELLIS_COMB|TRELLIS_FF|DP16KD|TRELLIS_RAMW" | tail -5
