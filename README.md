# RV32Verify

A 5-stage pipelined RV32I CPU core in SystemVerilog, and a verification
environment around it built the way CPU design verification teams work: an
independent C++ reference model checking every retired instruction in
lockstep, the official RISC-V test suite, and a one-command regression.

The verification side is where the effort goes. The core is deliberately a
conventional in-order pipeline so that each part of the bench can be
explained, and its results checked, end to end.

> Status: **Milestones 1, 2 and 3 complete** (core, reference model,
> lockstep scoreboard, riscv-tests, constrained-random generator, functional
> coverage, assertions, bug-injection campaign). Formal verification with
> riscv-formal is in progress.
> All numbers below come from [docs/RESULTS.md](docs/RESULTS.md), which lists
> the command behind each one.

## Results so far

| Check | Result |
|---|---|
| RTL lint, Verilator `-Wall` | clean |
| Reference model alone, riscv-tests rv32ui | 41 / 42 pass |
| Core vs model in lockstep, rv32ui, no wait states / 30% wait states | 41 / 42 pass in both |
| 4 directed tests (FENCE.I over in-flight code, instructions behind a trap) | 4 / 4 pass in both wait profiles |
| Constrained-random, seeds 1-250, all knob and wait-state profiles | 250 / 250 pass, 248,151 instructions checked in lockstep |
| Functional coverage over those runs | 97.7% of 1312 bins; every pipeline-hazard item 100%; the 30 open bins are ALU operand-value pairs |
| 23 SVA pipeline invariants | no failures |
| Bug injection: 23 realistic RTL bugs, bench as first built | **21 / 23 caught** (19 / 23 with assertions off) |
| Same, after closing the two holes it exposed | 23 / 23 caught (21 / 23 with assertions off; the 2 only an assertion can see) |
| Functional RTL bugs found by the bench in the core | none so far; 5 real bugs and holes found and fixed in the bench itself, see [BUGS_FOUND](docs/BUGS_FOUND.md) |

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
- A **watchdog** fails the test if nothing retires for too long.

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
./regress bugs            # bug-injection campaign
```

The first run downloads the toolchain into `.cache/toolchain` (OSS CAD Suite
for Verilator, xPack GCC for RISC-V). Nothing is installed system-wide.

Run a single program with a retirement trace:

```
./regress build
cd build && ./sim/base/simv +hex=tests/rv32ui/add.hex +trace=add.trace +dmem_stall=30
```

### Windows

Development happened on a Windows 11 machine with Smart App Control enabled,
which refuses to run any locally compiled, unsigned executable, including
every Verilator-built simulator. The flow therefore runs inside WSL2
(Ubuntu 24.04) with the Linux builds of the same tools, still kept inside
this folder. `regress.ps1` is a wrapper that does this from PowerShell.

## Honest limitations (so far)

- No CSRs, no interrupts, no trap handler: an exception halts the core.
- `ma_data` from rv32ui fails by design, as explained above.
- The RISC-V architectural test suite (RISCOF) has not been run yet.
- Static not-taken prediction only; every taken branch costs two cycles.
