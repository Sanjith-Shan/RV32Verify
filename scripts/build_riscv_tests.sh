#!/usr/bin/env bash
# Fetch the official riscv-tests at a pinned commit and build the rv32ui
# suite against tests/env (bare-metal, tohost reporting, no CSRs).
# Output: build/tests/rv32ui/<name>.{elf,hex,meta,dump}
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"
RISCV_TESTS_COMMIT="${RISCV_TESTS_COMMIT:-3df703cd52d5f0d8224e3c50bf03c6cb70efff98}"
SRC="$ROOT/.cache/src/riscv-tests"
OUT="$ROOT/build/tests/rv32ui"
CROSS="${CROSS:-riscv-none-elf-}"

if [ ! -d "$SRC/.git" ]; then
  git clone -q https://github.com/riscv-software-src/riscv-tests.git "$SRC"
fi
git -C "$SRC" fetch -q origin "$RISCV_TESTS_COMMIT" 2>/dev/null || true
git -C "$SRC" checkout -q "$RISCV_TESTS_COMMIT"

# the rv32ui test list, exactly as the upstream Makefrag defines it
tests=$(python3 -c '
import re, sys
txt = open(sys.argv[1]).read().replace("\\\n", " ")
print(re.search(r"^rv32ui_sc_tests\s*=\s*(.*)$", txt, re.M).group(1))
' "$SRC/isa/rv32ui/Makefrag")

mkdir -p "$OUT"
n=0
for t in $tests; do
  "${CROSS}gcc" -march=rv32i_zifencei -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden \
    -nostdlib -nostartfiles -I"$ROOT/tests/env" -I"$SRC/isa/macros/scalar" \
    -T"$ROOT/tests/env/link.ld" "$SRC/isa/rv32ui/$t.S" -o "$OUT/$t.elf"
  "${CROSS}objdump" -d "$OUT/$t.elf" > "$OUT/$t.dump"
  python3 "$ROOT/scripts/elf2hex.py" "$OUT/$t.elf" "$OUT/$t.hex"
  n=$((n+1))
done
echo "built $n rv32ui tests from riscv-tests $RISCV_TESTS_COMMIT into $OUT"
