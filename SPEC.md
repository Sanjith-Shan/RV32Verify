# RV32Verify — Project Spec

A pipelined RV32I CPU core in SystemVerilog, and the more important half, a full design
verification environment around it. Constrained-random stimulus, a C++ reference model
checking every retired instruction, functional coverage driven to closure, assertions, and
a measured bug-detection rate.

## Why this exists

Sanjith Shanmugavel (UCSD undergrad, incoming Tesla SWE intern Jan to Mar 2027) is going
after a **Summer 2027 Design Verification intern** role on an Apple CPU verification team in
Sunnyvale. The hiring manager posted the requirements himself:

- Strong academic record
- **Coursework or project experience in digital design and SystemVerilog**
- Fundamentals of computer architecture and logic design, **ability to debug methodically**

His own background (from his profile) is what the project should speak to. 15+ years of CPU
DV on MIPS, ARM and x86. Spec review, test planning, bench development (stimulus and
checker), coverage closure. Functional models and test generators for CPU verification.
SystemVerilog benches for processor modules (Fetch, Issue, Execution). UVM, OVM, VMM.
C/C++, Verilog, SystemVerilog, Tcl, Perl.

Sanjith has no SystemVerilog on record today. This project is the honest fix. Everything in
it must be real, run, and be reproducible, because a DV manager will ask him to walk through
the testbench line by line in an interview.

**The goal is not a toy core.** Plenty of students write a 5-stage pipeline. Almost none
build the verification side the way a CPU DV team does. That side is where the effort goes.

## Hard rules

1. **Never fabricate.** Every number in the README comes from a command anyone can rerun.
   If something did not work, the README says so. Unflattering results are stated first.
2. **No machine-wide installs on the mini PC.** Put the toolchain inside this project folder
   (OSS CAD Suite's portable Windows build is the expected route, it ships Verilator, Icarus,
   Yosys and SymbiYosys). If the Windows toolchain blocks real progress, say so in the run
   summary rather than silently cutting scope.
3. **Do not name or brand anything after Apple**, and do not imitate any company's internal
   design. This is a general RISC-V core with a public ISA and public test suites.
4. **No AI-tool attribution** in commits or files. No Co-Authored-By trailers. Authorship is
   Sanjith's.
5. **Big generated artifacts stay out of git** (waveforms, coverage databases, build dirs,
   the toolchain). Gitignore them.
6. Keep each claim at the level of what was actually built. If the bench is "UVM-style" but
   not real UVM because the simulator could not run the library, call it UVM-style.

## Milestones

Ship in this order. **Milestone 1 must land first and fast**, because the outreach message
goes out once it exists.

### M1 — Core plus lockstep checking (the minimum sendable project)

- **RTL.** 5-stage in-order pipeline (IF, ID, EX, MEM, WB), full RV32I base integer ISA
  (minus FENCE/ECALL/EBREAK details as appropriate, documented). Full forwarding, load-use
  hazard stall, branch resolution with flush. Clean module boundaries (fetch, decode/issue,
  execute, memory, writeback, hazard unit, register file) so each can be talked about alone.
- **Retirement interface.** Expose an RVFI-style retirement port (PC, instruction, rd,
  rd value, memory address/data/mask, next PC) so the checker sees every retired instruction.
- **Reference model.** An instruction set simulator in C++ (the "functional model"), written
  independently from the RTL, called from the bench through DPI-C. A scoreboard compares
  every retired instruction against the model in lockstep and stops on the first mismatch
  with a readable report (cycle, PC, disassembly, expected vs actual).
- **Official compliance.** Run the public `riscv-tests` rv32ui suite (and the RISC-V
  architectural tests via RISCOF if practical). Report pass counts honestly.
- **Regression runner** with one command to build and run everything.

### M2 — Constrained-random stimulus and coverage closure

- **Instruction stream generator** (the "test generator"). Constrained random with knobs
  for instruction mix, register dependency distance (to force every forwarding path and the
  load-use stall), branch density and direction, memory address alignment and aliasing.
  Seeded and reproducible. SV classes with `randomize()` if the simulator supports it well,
  otherwise a generator in C++ or Python feeding the bench, chosen for what actually works.
- **Verification plan** (`docs/VERIFICATION_PLAN.md`), written the way a DV team writes one.
  Features from the spec, each mapped to the test and the coverage item that closes it.
- **Functional coverage.** Opcode by operand classes, every forwarding source/destination
  pair, load-use stall, branch taken/not-taken by type, back-to-back hazards, x0 writes,
  misaligned and boundary values, sign extension cases. Drive it to closure and publish the
  coverage report with the holes that remain and why.
- **Assertions (SVA)** on pipeline invariants. One instruction retires at most per cycle,
  flushed instructions never retire, x0 stays zero, stalls hold state, PC sequencing.

### M3 — Prove the bench catches bugs

- **Bug injection campaign.** A set of realistic RTL mutations (wrong forwarding priority,
  missing stall, sign-extension error, off-by-one branch offset, wrong byte lane, and so on),
  each behind a define. Run the regression against each and report how many the bench
  catches, how fast (cycles or seeds to first failure), and which checker caught it. This
  produces the most defensible number in the project.
- **Debug write-ups.** Real bugs the bench found in the RTL during development, each with
  symptom, how it was localized (waveform, scoreboard report, assertion), root cause, fix.
  This is the "debug methodically" evidence. Only real bugs, never staged ones presented as
  real.

### M4 — Depth, as time allows

Pick what most raises the odds with a CPU DV manager. Candidates, not a checklist:

- Formal verification with **riscv-formal** via SymbiYosys (a public, respected standard).
- A real UVM bench if the toolchain can run UVM.
- RV32M extension, a simple branch predictor (gives the fetch unit real depth to verify),
  or a small instruction cache, each verified with the same rigor.
- Interrupt/exception handling (CSRs, traps) as a separate verified feature.
- Tcl or Perl only if it fits naturally, never for show.
- GitHub Actions CI running the regression.

## Deliverables

- `README.md`. What it is, how to run it, the headline results table, honest limitations.
- `docs/VERIFICATION_PLAN.md`, `docs/COVERAGE.md`, `docs/BUG_INJECTION.md`, `docs/BUGS_FOUND.md`.
- `docs/INTERVIEW.md`. The walkthrough Sanjith would give a DV manager. Bench architecture,
  why each checker exists, the hardest bug, what he would do next, likely questions with
  answers.
- `docs/RESULTS.md`. Every number, the exact command that produced it, the date.
- A private GitHub repo `Sanjith-Shan/RV32Verify`, pushed. Sanjith makes it public himself.

## What to report at the end of a run

- Which milestones are done and verified, which are partial, what failed and why.
- The headline numbers with their reproduce commands.
- Three candidate resume bullets in plain words (what was built, then the result), no em
  dashes, no jargon a non-engineer recruiter would trip on.
- What you would build next to raise the odds further.
