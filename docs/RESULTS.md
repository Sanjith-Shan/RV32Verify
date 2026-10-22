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
| Random program generation plus simulation time, one program | 7.3 s and 7.9 s in two runs (seed 1, 941 instructions retired), almost all of it in the z3 constraint solver; re-measured at the M4 commit because the original M2 measurement was taken with a mistyped seed. Moving immediates out of the solver into `post_randomize()` cut it from about 9.5 s to about 6.7 s (that before/after pair was measured on seed 0) | `/usr/bin/time ./sim/base/simv +gen +seed=1 +verilator+seed+1 +quiet` (in `build/`, with `scripts/env.sh` sourced) |

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

## Milestone 4 (2026-10-22)

### Formal verification: riscv-formal (SymbiYosys)

| Result | Number | Command |
|---|---|---|
| riscv-formal checks for RV32I, aligned-memory convention, memories fully unconstrained (any data, any ready/wait pattern) | **45 / 45 PASS** at the depths in `formal/rv32verify/checks.cfg`; no depth was lowered | `./regress formal` (or `bash scripts/run_formal.sh`) |
| Instruction checks (`insn_*`, one per RV32I instruction, 37 checks) | all PASS, bounded model check to depth 20; 6 to 44 s each | same |
| `reg`, `pc_fwd`, `pc_bwd`, `causal`, `unique`, `liveness`, `ill`, `cover` | all PASS; `reg` depth 25 (445 s), `pc_fwd` depth 30 (3130 s), `pc_bwd`, `causal`, `unique`, `liveness` depth 30 (5 to 14 s), `ill` depth 15, `cover` depth 15 | same |
| Sanity: the same flow on the `BUG_SLT_UNSIGNED` build | `insn_slt_ch0` FAIL with a counterexample trace; `cover` PASS (instructions do retire within the depth, so passes are not vacuous) | `CHECKS="insn_slt_ch0 cover" bash scripts/run_formal.sh -DBUG_SLT_UNSIGNED` |
| Solver | boolector via yosys-smtbmc for every check. `pc_fwd` was run with yices and boolector in parallel (same model, same depth); boolector finished first. Two bitwuzla runs on the Windows host were started to use the two cores WSL2 does not get, and stopped once boolector passed | engine section of `checks/pc_fwd_ch0.sby` changed to two engines |
| Wall time | sum of check times 4160 s; on this machine a full run takes 1 to 2 hours with 2 parallel jobs, dominated by `pc_fwd` | same |

A bounded check proves the property for every execution up to that many
cycles after reset, not for all time. riscv-formal toolchain: commit
c992aa61fdfe0846c5ed90324c596202a1c69b76; the RTL is elaborated with
yosys-slang into one Verilog netlist first because riscv-formal reads plain
Verilog. Per-check results: `build/reports/formal_full_run.json` (not in git).

### Synthesis sanity check (Yosys + nextpnr-ecp5)

| Result | Number | Command |
|---|---|---|
| Target | Lattice ECP5 LFE5U-25F, CABGA381, speed grade 6; top = `synth/rv32_synth_top.sv` (both memory ports, RVFI port left unconnected and removed) | `./regress synth` |
| Yosys `synth_ecp5` cells | 3716 LUT4, 1374 flip-flops, 110 carry (CCU2C) cells, no block RAM | same |
| nextpnr utilisation | 3968 / 24288 logic cells (16%), 1374 / 24288 flip-flops (5%), 171 / 197 I/O | same |
| Fmax | **56.86 MHz** (critical path 17.6 ns: 6.0 ns logic, 11.6 ns routing; unconstrained pins, placer seed 1) | same |

The register file uses flip-flops (992 of the 1374) because it is reset;
without the reset it could map to distributed RAM. No timing work has been
done on the RTL.

### Continuous integration

| Result | Number | Command |
|---|---|---|
| GitHub Actions on ubuntu-24.04, clean machine, toolchain downloaded by the same script | lint, model qualification, riscv-tests in both wait profiles and 25 random seeds all pass; 2 min 56 s for the whole job | `.github/workflows/regress.yml`, run 39741726613 |

