# Results

Every number in this repository, the command that produced it, and the date.
Machine: AMD Ryzen 3 4300U mini PC (4 cores, 16 GB), Windows 11; simulations run in WSL2
Ubuntu 24.04 (2 vCPU). Toolchain: OSS CAD Suite 2026-10-21 (Verilator 5.053
devel rev v5.052-521-g6388139f7), xPack riscv-none-elf-gcc 15.2.0-1,
riscv-tests at commit 3df703cd52d5f0d8224e3c50bf03c6cb70efff98.

## Milestone 1 (2026-10-21)

| Result | Number | Command |
|---|---|---|
| RTL lint, `verilator --lint-only -Wall` | 0 warnings | `./regress lint` |
| Reference model alone on rv32ui | 41 / 42 pass (`ma_data` expected fail, see below) | `./regress iss` |
| Core in lockstep with the model, rv32ui, no wait states | 41 / 42 pass | `./regress riscv-tests` |
| Same, 30% random wait states on both buses | 41 / 42 pass | `./regress riscv-tests` |

`ma_data` performs misaligned loads and stores. The ISA allows an
implementation to either support them or raise an address-misaligned
exception. This core raises the exception, and in this configuration there is
no trap handler to emulate the access, so the test stops at its first
misaligned load. The reference model makes the same choice independently, and
the lockstep checker confirms the core and the model agree on the trap
(cause 4, load address misaligned, at the same PC).
