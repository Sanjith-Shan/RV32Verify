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

## Milestone 2 (2026-10-22)

| Result | Number | Command |
|---|---|---|
| Constrained-random regression, seeds 1-250 (all 25 knob x wait-state combinations, 10 times each) | 250 / 250 pass, 244,599 instructions retired and checked in lockstep, 383,214 cycles | `./regress coverage -n 250 -j 2` |
| Same run: riscv-tests rv32ui in both wait-state profiles | 41 / 42 pass in each (`ma_data` expected fail) | same |
| Functional coverage, merged over those 334 runs | **98.2% (1288 / 1311 bins)**; every pipeline, dependency, branch, load/store, x0 and trap item 100%; 23 open bins, all operand-value pairs in the ALU crosses | same; report in [COVERAGE.md](COVERAGE.md) |
| SVA: 23 assertions bound into the core | 0 failures in all runs above | same |
| SVA cover properties | load-use then forward 1744, redirect deferred by a data wait 321, trap beats a younger redirect 21, wait then load-use 70, both operands forwarded from different stages 427 | same |
| Wall time of that regression | 15 min 23 s (2 parallel jobs) | same |
| Random program generation time | about 6.7 s per 950-instruction program, almost all in the z3 constraint solver; was about 9.5 s before immediates were moved out of the solver into `post_randomize()` | `/usr/bin/time ./sim/base/simv +gen +seed=1 +quiet` (in `build/`, with `scripts/env.sh` sourced) |
