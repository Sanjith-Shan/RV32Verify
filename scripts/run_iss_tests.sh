#!/usr/bin/env bash
# Qualify the reference model on its own: run every rv32ui test on the ISS.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build/iss"
g++ -O2 -std=c++17 -Wall -Wextra -o "$ROOT/build/iss/rv32iss" "$ROOT/model/rv32_iss.cpp" "$ROOT/model/iss_main.cpp"
pass=0; fail=0
for h in "$ROOT"/build/tests/rv32ui/*.hex; do
  t=$(basename "$h" .hex)
  th=$(sed -n 's/^tohost=//p' "${h%.hex}.meta")
  if out=$("$ROOT/build/iss/rv32iss" "$h" --tohost "$th"); then pass=$((pass+1)); r=PASS; else fail=$((fail+1)); r=FAIL; fi
  printf "%-10s %s  %s\n" "$t" "$r" "$out"
done
echo "ISS rv32ui: $pass passed, $fail failed"
