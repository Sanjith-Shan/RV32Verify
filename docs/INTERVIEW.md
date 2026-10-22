# Walkthrough for a CPU DV interview

How I would present this project to a design verification manager, in the
order I would draw it on a whiteboard. Every number quoted here is in
[RESULTS.md](RESULTS.md) with the command that produced it.

## 1. The 30-second version

I built a 5-stage RV32I pipeline and then spent most of the effort on
verifying it the way a CPU DV team would: an independent C++ instruction
set simulator as the reference model, called through DPI-C and compared
against every retired instruction in lockstep; a constrained-random
instruction generator written as SystemVerilog classes; functional coverage
on both the ISA and the pipeline hazards, driven to closure; SVA on the
pipeline invariants; and a bug-injection campaign that measures how many
realistic RTL bugs the bench actually catches, and with which checker.
riscv-formal (SymbiYosys) is the second, independent opinion on the core.

## 2. Bench architecture

```
  rv_gen (SV classes, randomize())          riscv-tests (hex)
            \                                   /
             +------> program image <----------+
                     /             \
             mem_model (SV)      C++ ISS memory (DPI)
                 |                      |
          mem_agent: imem/dmem         ISS
          random wait states            |
                 |                      |
             rv32_core ---- RVFI ---> rvfi_monitor ---> scoreboard (lockstep, DPI step)
                 |                          |-------> coverage (cg_* covergroups)
          bind rv32_core_sva                |-------> end_detector, trace_writer
          (pipeline invariants)
             pipe_probe_if  ----------------------> coverage (cg_pipe)
```

It is UVM-style rather than UVM: the same roles (generator, driver/responder,
monitor, scoreboard, coverage collector, environment, config object, an
analysis-port style broadcast from the monitor) written as plain SV classes,
because the open-source simulator I used (Verilator 5.053) does not run the
UVM library in this setup. Mapping each class to its UVM equivalent is
straightforward and is the first thing I would do with a commercial
simulator.

## 3. Why each checker exists

**Lockstep scoreboard.** Catches any architectural difference at the first
instruction where it shows up, with the PC and disassembly. A self-checking
test only says "test 7 failed" after the fact; lockstep tells you which
instruction, which field, and what the last few instructions were. It also
compares fields a self-checking test never looks at: which registers were
read, the memory byte masks, the next PC, the trap cause.

**Reference model written independently.** If I had generated expected
values from the RTL's own logic, a misunderstanding of the spec would be in
both and cancel out. The model is written from the ISA document in a
different style (a switch on the opcode, sparse byte memory) and qualified
alone on riscv-tests before the bench uses it.

**Two memory loaders.** The bus memory is loaded by an SV hex parser and the
model by its own C++ loader. A loader bug would otherwise corrupt both the
same way and the lockstep compare would still pass.

**End-of-test state compare.** RVFI only shows what retires. A write that
happens without retiring (a flushed store reaching memory, a register write
from a squashed instruction) only shows up later, or never. Comparing all
registers and every memory word at the end closes that gap.

**SVA.** The scoreboard sees the result; assertions see the mechanism. Three
reasons they earn their place:
1. *Earlier and closer.* A forwarding-priority bug fires `a_fwd_a_youngest`
   in the cycle the wrong mux select happens, naming the register, instead
   of a mismatch some instructions later.
2. *Bugs the scoreboard cannot see.* A spurious load-use stall is
   functionally invisible; only `a_loaduse_real` (stall only when there is a
   real dependency) flags it. The bug-injection table shows this case.
3. *Independent restatement.* The hazard condition in the assertions is
   re-derived from the raw instruction bits, not from the decoder's control
   signals, so a decoder mistake does not hide by being restated.

**Watchdog.** A lost ready/valid handshake shows up as nothing retiring.
Without a watchdog that is a hung simulation, not a failure.

## 4. Stimulus

- riscv-tests rv32ui: directed, community-written, good for each
  instruction's corner cases, weak on pipeline interactions because the
  tests are mostly straight-line code with result checks.
- The constrained-random generator is where the pipeline gets exercised.
  The constraints that matter:
  - *dependency distance*: a source register is tied to the destination of
    the instruction 1 to N back, which is what forces every forwarding path
    and the load-use stall;
  - *branch direction*: comparing a register with itself makes the outcome
    known in advance, so taken/not-taken can be biased per branch type;
  - *memory window and aliasing*: a small address window and reuse of recent
    addresses make stores and loads hit the same words with different sizes
    and byte offsets;
  - *boundary operands*: 0, 1, -1, INT_MAX, INT_MIN as register values and
    immediates;
  - *program structure*: only forward branches plus counted loops with a
    reserved counter register, so every program terminates; reserved
    registers are reshuffled per seed so every register gets used.
- Knob profiles (`default`, `alu_corner`, `mem_alias`, `branchy`,
  `hazard`) and five wait-state profiles; seed `s` uses `s % 5` and
  `(s / 5) % 5`, so 25 consecutive seeds hit every combination.
- The memory agent injects random wait states on both ports, which is what
  exercises stall-holds-state and the interactions between a data wait and
  a redirect, a load-use stall, or a producer retiring while EX is held.

## 5. Coverage closure, how it actually went

The first merged report was 82.8%. The holes, and what I did about them, are
in [COVERAGE.md](COVERAGE.md). Two of the holes turned out to be bugs in my
coverage model, not in the stimulus ([BUGS_FOUND.md](BUGS_FOUND.md)). One of
them I found because a cover property and a covergroup bin for the same event
disagreed (458 hits against 0). The others were real stimulus gaps closed by
adding a boundary-value seeding instruction to the generator, wrong-path
instructions after the final trap, and longer JALR setup sequences.

## 5b. What the bug-injection campaign taught me

The bench as first built caught 21 of 23 injected bugs. The two escapes,
and a third bug caught only by luck, were all holes in the bench, not in the
idea of the bench:

- **A trap that does not kill the instruction behind it** escaped because
  my test ended in the cycle the trap retired. The leaked instruction would
  have retired one cycle later. Fix: a drain window with every checker live,
  plus directed tests that put a store, a taken branch and a load-use pair
  directly behind a trap.
- **FENCE.I that does nothing** passed even the official `fence_i` test,
  because in this pipeline a stale instruction can only exist right behind
  the FENCE.I, and nothing tested that window. Fix: a directed test that
  patches the next instruction.
- **A spurious load-use stall** was never produced by random programs: the
  precondition (an unused register field equal to the load's destination)
  happened about 1 time in 32 by chance and had no coverage bin. Fix: field
  aliasing in the generator and a new bin; it now fails 17 of 25 programs.

After the fixes the bench catches 23 of 23, but I report 21 of 23 as the
honest number, because round 2 and 3 were run knowing which bugs escaped.
It was also the most useful step of the project: it is the only one that
measured the bench instead of the design.

## 6. The hardest bug

Honest answer first: the bench has not found a functional bug in the core
RTL. The bugs it did find were in the verification environment (above). The
hardest *design* problem was one I reasoned out before simulation, and the
bug-injection campaign shows the bench would catch it:

**A producer retiring while its consumer is held in EX.** When the data
port is not ready, EX, MEM and everything before them hold. Suppose the
instruction in EX depends on the one in WB: in the first wait cycle it gets
that value through the MEM/WB forwarding path. At the next clock edge the
producer retires and MEM/WB becomes a bubble, so the forwarding path is gone,
while EX is still holding the operand it read from the register file in ID,
before the producer wrote it. When the wait ends, EX uses a stale value.
The fix is to keep loading the forwarded operand values into ID/EX while it
is held. `BUG_STALL_NO_REFRESH` removes that line. The SVA `a_wait_refresh`
catches it in the cycle it happens; the scoreboard catches it at
retirement. Random tests only hit it with data wait states and a dependency
at distance 2 at the same time, which is why both the wait-state agent and
the dependency-distance knob exist.

## 7. What I would do next

1. Port the bench to real UVM on a commercial simulator (sequences instead of
   the generator's loop, `uvm_analysis_port` instead of the subscriber list,
   a register model is not needed for this core).
2. Add CSRs and machine-mode traps so exceptions are recoverable, then run
   the RISC-V architectural test suite (RISCOF) with signatures.
3. A branch predictor in fetch: a BTB plus 2-bit counters gives the fetch
   stage real state, and new hazard classes (mispredict recovery, predictor
   update ordering) to verify with the same flow.
4. Mutation testing driven by the tool (Yosys `mutate`/MCY) to complement the
   hand-written bug list, which is biased towards bugs I thought of.
5. Run the generator through a faster solver path: constraint solving is
   most of the simulation time today.

## 8. Questions I expect, with answers

**Why a C++ model and not just riscv-tests?** riscv-tests check end results
of short sequences. They do not check every instruction, do not see the
register reads or memory masks, and do not cover pipeline interactions. The
model gives an expected value for every retirement of any program, including
random ones.

**How do you know the model is right?** It is qualified alone against
riscv-tests (41/42; the one miss is the documented misaligned-access test),
it was written independently from the RTL, and any disagreement stops the
test so I look at both sides. In a team the model would be shared and
qualified once against the architecture compliance suite.

**What does "coverage closure" mean here?** Every bin in the plan is hit, or
the remaining holes are listed with a reason. The plan was written before
the closure work, and each item maps to a feature in
[VERIFICATION_PLAN.md](VERIFICATION_PLAN.md). Line or toggle coverage is not
the goal; functional coverage is.

**Your bench passed the RTL first time. Isn't that suspicious?** It is the
right question. That is why the bug-injection campaign exists: it measures
the bench's ability to catch bugs, which "everything passes" cannot. The
formal checks are the other answer.

**How do you debug a mismatch?** Read the scoreboard report (cycle, PC,
disassembly, field diff, previous instructions). Rerun the seed with
`+trace` for a retirement log next to the model's own trace
(`build/iss/rv32iss --trace`). If the first wrong thing is an operand, look at
the forwarding select for that cycle (the SVA usually already fired). Then a
waveform of the few cycles before. Bisect on knobs (wait states off,
dependency knob off) to find the smallest program that still fails.

**What is a spurious stall and why does it matter?** A stall when no
dependency exists. Results are still correct, so the scoreboard passes, but
the core is slower than designed. Only a performance check or an assertion
catches it.

**Why are FENCE and FENCE.I handled that way?** One hart, one memory port,
in-order: memory ordering is already sequential, so FENCE has nothing to do.
FENCE.I must make earlier stores visible to fetch; flushing and refetching
everything younger does that, because the store has already reached memory
by the time the younger instructions are fetched again.

**What did formal add, and what does a bounded pass mean?** riscv-formal
checks every instruction, register-file consistency, PC sequencing,
causality, unique retirement order and liveness with both memories left
completely free, which no simulation can do. All 45 checks pass, but they
are bounded: "no failure within 15 to 30 cycles after reset", for every
possible program and memory timing in that window. To show the passes are
not vacuous, I ran the same flow on a build with a planted SLT bug: the SLT
check fails with a counterexample and the cover check shows instructions do
retire inside the window. The hardest check, PC-forward at depth 30, took
52 minutes; I raced two solvers on it rather than lower the depth.
