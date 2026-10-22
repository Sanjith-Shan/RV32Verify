# Source this to put the project-local toolchain on PATH:  . scripts/env.sh
_rv_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -d "$_rv_root/.cache/toolchain/oss-cad-suite/bin" ]; then
  export PATH="$_rv_root/.cache/toolchain/oss-cad-suite/bin:$_rv_root/.cache/toolchain/riscv/bin:$PATH"
fi
unset _rv_root
