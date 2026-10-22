#!/usr/bin/env bash
# Download the pinned, project-local toolchain into .cache/toolchain (gitignored).
# Nothing is installed machine-wide. Linux x86-64 (native or WSL2).
#
#   OSS CAD Suite  : Verilator, Yosys, SymbiYosys, solvers
#   xPack GCC      : riscv-none-elf-gcc for building riscv-tests / arch tests
#
# Host prerequisites (already present on Ubuntu 24.04): g++, make, python3, curl, git.
set -euo pipefail

OSS_DATE="${OSS_DATE:-2026-10-21}"
XPACK_VER="${XPACK_VER:-15.2.0-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TC="$ROOT/.cache/toolchain"
DL="$ROOT/.cache/dl"
mkdir -p "$TC" "$DL"

oss_tag="${OSS_DATE}"
oss_file="oss-cad-suite-linux-x64-${OSS_DATE//-/}.tgz"
oss_url="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${oss_tag}/${oss_file}"
xp_file="xpack-riscv-none-elf-gcc-${XPACK_VER}-linux-x64.tar.gz"
xp_url="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VER}/${xp_file}"

fetch() { # url file
  if [ ! -s "$DL/$2" ]; then
    echo "downloading $2"
    curl -sSfL -o "$DL/$2.part" "$1"
    mv "$DL/$2.part" "$DL/$2"
  fi
}

if [ ! -x "$TC/oss-cad-suite/bin/verilator" ]; then
  fetch "$oss_url" "$oss_file"
  echo "extracting $oss_file"
  tar -xzf "$DL/$oss_file" -C "$TC"
fi

if [ ! -x "$TC/riscv/bin/riscv-none-elf-gcc" ]; then
  fetch "$xp_url" "$xp_file"
  echo "extracting $xp_file"
  tar -xzf "$DL/$xp_file" -C "$TC"
  rm -rf "$TC/riscv"
  mv "$TC/xpack-riscv-none-elf-gcc-${XPACK_VER}" "$TC/riscv"
fi

echo "OSS CAD Suite: $(cat "$TC/oss-cad-suite/VERSION" 2>/dev/null || echo '?')"
"$TC/oss-cad-suite/bin/verilator" --version
"$TC/riscv/bin/riscv-none-elf-gcc" --version | head -1
echo "toolchain ready in $TC"
