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

Numbers in this section were produced at commit `b539a7a`. The generator
changed in M3, so rerunning the same command at a later commit gives
slightly different counts (see the M3 section).

| Result | Number | Command |
|---|---|---|
| Constrained-random regression, seeds 1-250 (all 25 knob x wait-state combinations, 10 times each) | 250 / 250 pass, 244,599 instructions retired and checked in lockstep, 383,214 cycles | `./regress coverage -n 250 -j 2` |
| Same run: riscv-tests rv32ui in both wait-state profiles | 41 / 42 pass in each (`ma_data` expected fail) | same |
| Functional coverage, merged over those 334 runs | **98.2% (1288 / 1311 bins)**; every pipeline, dependency, branch, load/store, x0 and trap item 100%; 23 open bins, all operand-value pairs in the ALU crosses | same; report in [COVERAGE.md](COVERAGE.md) |
| SVA: 23 assertions bound into the core | 0 failures in all runs above | same |
| SVA cover properties | load-use then forward 1744, redirect deferred by a data wait 321, trap beats a younger redirect 21, wait then load-use 70, both operands forwarded from different stages 427 | same |
| Wall time of that regression | 15 min 23 s (2 parallel jobs) | same |
| Random program generation time | about 6.7 s per 950-instruction program, almost all in the z3 constraint solver; was about 9.5 s before immediates were moved out of the solver into `post_randomize()` | `/usr/bin/time ./sim/base/simv +gen +seed=1 +quiet` (in `build/`, with `scripts/env.sh` sourced) |

## Milestone 3 (2026-10-22)

| Result | Number | Command |
|---|---|---|
| Bug-injection, round 1 (bench as first built) | **21 / 23 injected bugs caught**; 19 / 23 with assertions off | `git checkout b539a7a && ./regress bugs` (the M2 commit, which already contains all 23 bug defines) |
| Round 1 escapes | `BUG_TRAP_NO_KILL`, `BUG_FENCEI_NO_FLUSH` (0 failing runs of 107 each) | same |
| Bug-injection, round 3 (after closing the round-1 holes) | **23 / 23 caught**; 21 / 23 with assertions off (the two misses change no architectural result) | `./regress bugs` |
| Runs per bug, round 3 | 82 rv32ui + 8 directed + 25 random = 115, twice (SVA on / off) | same |
| Spurious-stall bug, random programs failing | 0 / 25 in rounds 1-2, 17 / 25 in round 3 (after field-aliasing stimulus) | same |
| Campaign wall time | about 16 min (23 builds of about 31 s each plus the runs, 2 jobs) | same |
| Reference model alone, rv32ui + 4 directed tests | 45 / 46 pass (`ma_data` expected fail) | `./regress iss` |
| Core in lockstep, 4 directed tests, both wait profiles | 4 / 4 pass in each | `./regress riscv-tests` |
| Coverage regression after the M3 generator change: random seeds 1-250 | 250 / 250 pass, 248,151 instructions checked in lockstep, 393,647 cycles | `./regress coverage -n 250 -j 2` |
| Functional coverage after M3 (one bin added) | **97.7% (1282 / 1312)**; all non-ALU-operand items 100%; 30 open bins, all operand-value pairs in the ALU crosses | same; [COVERAGE.md](COVERAGE.md) |
