#!/usr/bin/env bash
# Formal verification of rv32_core with riscv-formal (SymbiYosys).
#   run_formal.sh [extra yosys-slang defines, e.g. -DBUG_XYZ] 
# Env: JOBS (parallel checks), CHECKS (make targets, default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"
RVF_COMMIT="${RVF_COMMIT:-c992aa61fdfe0846c5ed90324c596202a1c69b76}"
RVF="$ROOT/.cache/src/riscv-formal"
CORE="$RVF/cores/rv32verify"
JOBS="${JOBS:-$(nproc)}"

if [ ! -d "$RVF/.git" ]; then
  git clone -q https://github.com/YosysHQ/riscv-formal.git "$RVF"
fi
git -C "$RVF" checkout -q "$RVF_COMMIT"

rm -rf "$CORE"
mkdir -p "$CORE"
cp "$ROOT/formal/rv32verify/wrapper.sv" "$ROOT/formal/rv32verify/checks.cfg" "$CORE/"

# 1. elaborate the SystemVerilog RTL into one flat Verilog module
yosys -q -m slang -p "read_slang $* --top rv32_core \
    $ROOT/rtl/rv32_pkg.sv $ROOT/rtl/rv32_alu.sv $ROOT/rtl/rv32_regfile.sv \
    $ROOT/rtl/rv32_decoder.sv $ROOT/rtl/rv32_fetch.sv $ROOT/rtl/rv32_decode.sv \
    $ROOT/rtl/rv32_execute.sv $ROOT/rtl/rv32_memory.sv $ROOT/rtl/rv32_writeback.sv \
    $ROOT/rtl/rv32_hazard.sv $ROOT/rtl/rv32_core.sv; \
  hierarchy -top rv32_core; proc; flatten; bwmuxmap; bmuxmap; demuxmap; opt_clean; \
  write_verilog -noattr $CORE/rv32_core_netlist.v"

# 2. generate and run the checks
cd "$CORE"
python3 ../../checks/genchecks.py
make -C checks -j"$JOBS" ${CHECKS:-} || true

# 3. collect results
mkdir -p "$ROOT/build/reports"
python3 - "$CORE/checks" "$ROOT/build/reports/formal.json" <<'PY'
import json, os, sys
d, out = sys.argv[1], sys.argv[2]
res = {}
for sby in sorted(f for f in os.listdir(d) if f.endswith(".sby")):
    name = sby[:-4]
    p = os.path.join(d, name)
    st = "NOT RUN"
    for f in ("PASS", "FAIL", "ERROR", "UNKNOWN", "TIMEOUT"):
        if os.path.exists(os.path.join(p, f)):
            st = f
    res[name] = st
json.dump(res, open(out, "w"), indent=1)
counts = {}
for v in res.values():
    counts[v] = counts.get(v, 0) + 1
print("riscv-formal:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
for k, v in res.items():
    if v != "PASS":
        print(f"  {k}: {v}")
PY
