# RV32Verify

A 5-stage pipelined RV32I CPU core in SystemVerilog, and a verification
environment around it built the way CPU design verification teams work: an
independent C++ reference model checking every retired instruction in
lockstep, the official RISC-V test suite, and a one-command regression.

The verification side is where the effort goes. The core is deliberately a
conventional in-order pipeline so that each part of the bench can be
explained, and its results checked, end to end.

> Status: **all four milestones done.** Core, reference model, lockstep
> scoreboard, riscv-tests, constrained-random generator, functional coverage,
> assertions, bug-injection campaign, riscv-formal, synthesis check, CI.
> Every number below comes from [docs/RESULTS.md](docs/RESULTS.md), which
> lists the command behind each one and the date.

## Results

Unflattering ones first.

| Check | Result |
|---|---|
| Functional RTL bugs found in the core by any of this | **none**. The core passed its first lockstep runs. The real bugs found were in the bench (5, see [BUGS_FOUND](docs/BUGS_FOUND.md)) |
| Bug injection: 23 realistic RTL bugs, bench as first built | **21 / 23 caught** (19 / 23 with assertions off). The 2 escapes were bench holes |
| Same, after closing the holes the campaign exposed | 23 / 23 caught (21 / 23 with assertions off; the other 2 change no architectural result, only an assertion can see them) |
| Functional coverage, riscv-tests + 250 random seeds | 97.7% of 1312 bins; every pipeline-hazard item 100%; the 30 open bins are ALU operand-value pairs, listed with the reason in [COVERAGE](docs/COVERAGE.md) |
| riscv-tests rv32ui, core vs model in lockstep, no wait states / 30% wait states | 41 / 42 pass in both (`ma_data`: see below) |
| 4 directed tests (FENCE.I over in-flight code, instructions behind a trap) | 4 / 4 pass in both wait profiles |
| Constrained-random, seeds 1-250, all knob and wait-state profiles | 250 / 250 pass, 248,151 instructions checked in lockstep |
| 23 SVA pipeline invariants | no failures in any clean run |
| riscv-formal (SymbiYosys), 45 checks, bounded depth 15 to 30 | **45 / 45 pass**; a planted bug fails with a counterexample, so the passes are not vacuous |
| Reference model alone on rv32ui + directed | 45 / 46 pass |
| RTL lint, Verilator `-Wall` | clean |
| Synthesis, Lattice ECP5-25 (Yosys + nextpnr) | 3968 logic cells, 1374 flip-flops, 56.9 MHz, no timing work done |
| CI (GitHub Actions, clean Ubuntu machine) | lint, model, riscv-tests, 25 random seeds green in about 3 minutes |

The one failing test, `ma_data`, needs misaligned loads and stores to
succeed. This core raises an address-misaligned exception instead (the ISA
permits either) and has no trap handler to emulate the access, so the test
stops at its first misaligned load. The model and the core agree on the trap.

## What is in here

```
rtl/        the core: fetch, decode/issue, execute, memory, writeback,
            hazard unit, register file, ALU, decoder, shared package
model/      C++ instruction set simulator (reference model), DPI-C glue,
            and a standalone runner used to qualify it
tb/         SystemVerilog bench: interfaces, memory agent, RVFI monitor,
            lockstep scoreboard, environment, top
tests/env/  minimal bare-metal environment for the official riscv-tests
scripts/    toolchain setup, test build, simulator build, lint, regression
tb/gen/     constrained-random instruction generator (SV classes, randomize())
tb/sva/     pipeline assertions, bound into the core
formal/     riscv-formal harness
tests/directed/  directed tests written for holes the campaign exposed
synth/      synthesis-only top level
docs/       verification plan, coverage, bug injection, bugs found,
            results, interview walkthrough
```

### The core

Classic 5-stage in-order pipeline, IF, ID, EX, MEM, WB, full RV32I.

- **Forwarding** from EX/MEM and MEM/WB into EX, plus a write-through register
  file that covers the WB to ID case.
- **Load-use hazard**: one-cycle stall, the dependent instruction waits in ID.
- **Branches and jumps** resolve in EX with static not-taken prediction; a
  taken branch flushes the two younger instructions.
- **Memory ports** with a ready handshake: an instruction-side wait inserts a
  bubble, a data-side wait holds the pipeline up to MEM. While EX is held,
  its operands keep being refreshed from the forwarding network so a
  producer that retires during the wait is not lost.
- **Exceptions**: illegal instruction, ECALL, EBREAK, misaligned load, store
  and jump target. The instruction retires with a trap flag and no side
  effects, and the core halts. There are no CSRs in this configuration.
- `FENCE` is a no-op (single hart, one memory port). `FENCE.I` flushes and
  refetches everything younger, which makes self-modifying code work.
- **Retirement port** in the RVFI format used by riscv-formal: PC, next PC,
  instruction, source and destination registers and values, memory address,
  byte masks and data, trap.

### The bench

```
                   +---------------------------------------------+
  program image -->|  mem_model  <--  mem_agent (random waits)   |
                   |                     |  imem / dmem buses    |
                   |                  rv32_core                  |
                   |                     |  RVFI retirement port |
                   |                rvfi_monitor                 |
                   |              /       |        \             |
                   |     scoreboard   end_detector  trace_writer |
                   |         |                                   |
                   |   C++ ISS (DPI-C)                           |
                   +---------------------------------------------+
```

- **mem_agent** answers both buses and injects random wait states.
- **rvfi_monitor** turns every retirement into a transaction and broadcasts it.
- **scoreboard** steps the C++ reference model one instruction per
  retirement and compares every RVFI field. The first mismatch stops the test
  with the cycle, retirement number, PC, disassembly, each field expected vs
  actual, and the instructions retired just before.
- **End-of-test checks** compare all 31 registers and every memory word
  against the model, which catches writes that never show up at retirement.
- A **watchdog** fails the test if nothing retires for too long, and a
  **drain window** keeps every checker live for 30 cycles after the end of
  a test (after a trap, nothing may retire).
- **SVA** (`tb/sva/`): 23 pipeline invariants bound into the core. The hazard
  conditions are re-derived from raw instruction bits, not from the decoder.
- **Constrained-random generator** (`tb/gen/`): SV classes with
  `randomize()`; knobs for instruction mix, dependency distance, branch
  direction, loops, memory window and aliasing, boundary operands, x0
  destinations and program endings. Five knob profiles x five wait-state
  profiles; 25 consecutive seeds cover every combination.
- **Functional coverage** (`tb/env/coverage.svh`): native covergroups for the
  ISA (operand classes, branch relations, byte lanes, sign extension, traps,
  dependency distance) and the pipeline (every forwarding path per consumer,
  load-use, wait states, redirects, and the hazards that interact). Per-run
  databases are merged by `scripts/cov_report.py`.
- **Formal** (`formal/`): the riscv-formal checks run on the same RTL,
  elaborated by yosys-slang, with both memories unconstrained.

It is UVM-style, not UVM: the same roles (generator, responder, monitor,
analysis broadcast, scoreboard, coverage, config, environment) as plain SV
classes, because Verilator does not run the UVM library in this setup.

The reference model is written from the ISA specification, not from the RTL,
and is qualified on its own against riscv-tests before the bench trusts it.
The bench memory is loaded by an SV hex parser and the model by its own C++
loader, so a loader bug cannot corrupt both sides in the same way.

## Running it

Linux (or WSL2) with `g++`, `make`, `python3`, `curl`, `git`:

```
./regress                 # lint, model qualification, riscv-tests, 25 random seeds
./regress riscv-tests     # the official suite, with and without wait states
./regress random -n 200   # constrained-random seeds 1..200
./regress coverage -n 250 # random + riscv-tests with a merged coverage report
./regress bugs            # bug-injection campaign (about 16 min)
./regress formal          # riscv-formal, 45 checks (1 to 2 hours on 2 cores)
./regress synth           # Yosys + nextpnr-ecp5 size and Fmax
```

The first run downloads the toolchain into `.cache/toolchain` (OSS CAD Suite
for Verilator, xPack GCC for RISC-V). Nothing is installed system-wide.

Run a single program with a retirement trace:

```
./regress build
cd build && ./sim/base/simv +hex=tests/rv32ui/add.hex +trace=add.trace +dmem_stall=30
. ../scripts/env.sh   # puts z3 on PATH, needed by randomize() for +gen runs
./sim/base/simv +gen +seed=7 +dump_prog +trace=r7.trace
```

### Windows

Development happened on a Windows 11 machine with Smart App Control enabled,
which refuses to run any locally compiled, unsigned executable, including
every Verilator-built simulator. The flow therefore runs inside WSL2
(Ubuntu 24.04) with the Linux builds of the same tools, still kept inside
this folder. `regress.ps1` is a wrapper that does this from PowerShell.

## Beyond the spec, and why

Things added that SPEC.md did not ask for, each because it is what a CPU DV
team would expect to see and each run and recorded in RESULTS.md:

| Addition | Why it helps |
|---|---|
| Bug campaign run twice, with assertions on and off | shows exactly what the SVA adds over the scoreboard (2 bugs only assertions can see, and earlier, named failures for the rest) |
| Reporting the round-1 detection rate, not just the final one | the honest measure of a bench is how it does before you know the answers |
| Directed tests and a drain window driven by campaign escapes | shows the loop a DV engineer actually runs: measure, find the hole, close it, re-measure |
| Formal with riscv-formal | a second, independent method on the same RTL, with a non-vacuity check |
| Synthesis on an FPGA flow | shows the RTL is real hardware, with size and Fmax |
| GitHub Actions CI | the regression reproduces on a clean machine, not just this one |
| Field-aliasing stimulus and an "unused field matches" coverage bin | stimulus for bugs where the design does something it should not, which feature-driven coverage misses |
| Cover properties next to covergroups | two independent counts of the same event; their disagreement found a coverage-model bug |

## Honest limitations

- No functional bug was found in the core, so the debug write-ups are about
  bench bugs, not RTL bugs.
- After the bench fixes the bug list is no longer a blind test of the bench;
  a fresh set of bugs from someone else would be the fair re-measurement.
- No CSRs, no interrupts, no trap handler: an exception halts the core, so a
  program can only take one trap, which limits trap stimulus.
- `ma_data` from rv32ui fails by design, as explained above.
- The RISC-V architectural test suite (RISCOF) was not run: it needs a
  reference simulator plugin (Sail or Spike) and CSR/trap support for its
  test framework. Not attempted.
- Formal checks are bounded (15 to 30 cycles after reset), not unbounded
  proofs.
- 30 ALU operand-value pairs in the coverage model are still open.
- Random generation is slow (about 7 s per 950-instruction program), almost
  all of it in the z3 solver that Verilator uses for `randomize()`.
- Static not-taken prediction only; every taken branch costs two cycles. No
  timing optimisation (56.9 MHz on ECP5).
