#!/usr/bin/env bash
# Qualify the reference model on its own: run every rv32ui and directed test on the ISS.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build/iss"
g++ -O2 -std=c++17 -Wall -Wextra -o "$ROOT/build/iss/rv32iss" "$ROOT/model/rv32_iss.cpp" "$ROOT/model/iss_main.cpp"
pass=0; fail=0
for h in "$ROOT"/build/tests/rv32ui/*.hex "$ROOT"/build/tests/directed/*.hex; do
  t=$(basename "$h" .hex)
  th=$(sed -n 's/^tohost=//p' "${h%.hex}.meta")
  out=$("$ROOT/build/iss/rv32iss" "$h" --tohost "$th"); rc=$?
  # trap_* directed tests are written to end in an exception
  case "$t" in trap_*) [[ "$out" == TRAP* ]] && rc=0 || rc=1 ;; esac
  if [ $rc -eq 0 ]; then pass=$((pass+1)); r=PASS; else fail=$((fail+1)); r=FAIL; fi
  printf "%-10s %s  %s\n" "$t" "$r" "$out"
done
echo "ISS rv32ui + directed: $pass passed, $fail failed"
