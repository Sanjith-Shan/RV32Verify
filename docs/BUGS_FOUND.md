# Bugs found during development

Only real bugs are listed here, in the order they were found: things that
were actually wrong in this repository and were caught by a check. The
deliberately injected mutations live in [BUG_INJECTION.md](BUG_INJECTION.md)
and are never presented as findings.

## Summary, stated first

The bench has not found a functional bug in the core RTL so far. The core
passed riscv-tests and the first random seeds in lockstep on its first run.
That is not proof it is correct. The [bug-injection campaign](BUG_INJECTION.md)
measures whether the bench would have noticed if it were wrong, and the
45 riscv-formal checks give a second, independent opinion: they all pass at
their configured depths and also found no RTL bug ([RESULTS.md](RESULTS.md),
milestone 4).

The real bugs found so far were in the verification environment itself. A
coverage model that reports a hole that is not there, or misses a hole that
is, is a bug that leads to wrong sign-off decisions. So they are recorded the
same way.

| # | Where | Found by | Symptom | Root cause |
|---|---|---|---|---|
| 1 | coverage model | SVA cover vs covergroup disagreement | `cp_stall_then_forward` 0 hits over 122 runs while the SVA cover for the same event had 458 | cycle-count off by one in the sampling logic |
| 2 | coverage model | coverage hole review | `cp_trap.insn_misaligned` 0 hits over 100 seeds although the generator ends about 4% of programs with a misaligned jump | the coverpoint guard used `cause != 0` to mean "trapped", and cause 0 is a real cause |
| 3 | bench end-of-test logic | bug-injection campaign | `BUG_TRAP_NO_KILL` escaped every run | the test ended in the same cycle the trap retired, so an instruction that wrongly survived behind the trap was never observed |
| 4 | test plan (stimulus) | bug-injection campaign | `BUG_FENCEI_NO_FLUSH` escaped every run, including rv32ui `fence_i` | no test patched an instruction that was already fetched when FENCE.I executed, the only case where FENCE.I matters in this pipeline |
| 5 | stimulus and coverage model | bug-injection campaign | `BUG_LOADUSE_IGNORES_USE` (spurious stalls) never seen in random runs | the precondition (an unused register field naming the load's destination) occurred twice in 25 programs, and no coverage bin tracked it |

---

## 1. Load-use "stall then forward" bin never hit

**Symptom.** First merged coverage report (riscv-tests plus 40 random seeds):
`cg_pipe.cp_stall_then_forward` had 0 hits. The SVA cover property
`c_loaduse_then_fwd`, which describes the same event (a load-use stall,
then the consumer taking the load's data from MEM/WB), had 458 hits in the
same runs. Two coverage mechanisms disagreeing about one event means one of
them is wrong.

**Localization.** The event is easy to walk cycle by cycle:

| cycle | IF/ID | ID/EX | EX/MEM | MEM/WB | `load_use` |
|---|---|---|---|---|---|
| t | consumer | load | | | 1 |
| t+1 | consumer (held) | bubble | load | | 0 |
| t+2 | next | consumer | bubble | load | 0, consumer forwards from MEM/WB |

The covergroup sampled at the end of each cycle set a counter to 0 in cycle t
and incremented it at the end of t+1, so in cycle t+2 the counter read 1. The
condition tested for 2.

**Fix.** Compare against 1 (`tb/env/coverage.svh`, `c_stall_then_forward`).
The bin is hit after the fix (see [COVERAGE.md](COVERAGE.md)).

**Lesson.** A cover property and a covergroup bin written independently for
the same event cross-check each other for free. The cover property was
written as a temporal sequence (`load_use ##2 fwd == MEMWB`), which made the
timing explicit and is why it was right.

## 2. Instruction-address-misaligned trap never covered

**Symptom.** After 100 random seeds, `cg_misc.cp_trap.insn_misaligned` was
still 0, while the program listings showed endings with `jal ra, +6` (a jump
to a misaligned target). The scoreboard had compared those traps (cause 0)
and passed them, so the stimulus was reaching the core.

**Localization.** The coverpoint guard was
`iff (op == OP_ECALL || op == OP_EBREAK || op == OP_ILLEGAL || cause != 0)`.
The idea was "sample only when the instruction trapped", written as
"cause is not zero". The misaligned-jump trap is a JAL (not in the opcode
list) with cause 0, so the guard was false exactly when the bin should have
been hit.

**Fix.** Sample on the transaction's own trap flag (`iff (trapped)`).

**Lesson.** Encoding "no event" as a value that is also a legal event value
hides that event. The RTL makes the same choice (`cause` is only meaningful
when `trap` is set), and the coverage model should have followed it.

## 3. The test ended too early to see a trap leak

**Symptom.** Bug-injection round 1: `BUG_TRAP_NO_KILL` (a trap in MEM does
not kill the instruction in EX) passed all 107 runs, with and without
assertions.

**Localization.** With the bug, the instruction behind the trap moves into
MEM one cycle after the trap and retires one cycle after it. The
environment stopped the test in the cycle the trap retired, so that
retirement never happened inside the simulation. The SVA `a_trap_flushes`
would have fired one cycle later, which was also after the end.

**Fix.** A drain window (`tb/env/tb_env.svh`): after the end condition the
core keeps running for 30 cycles with every checker live, and after a trap
any further retirement fails the test. In round 2 the bug was caught, but by
only 1 run: just 4 of the 25 random programs end in a trap, and the bug only
shows if an instruction happens to be in EX behind the trap (with heavy
fetch wait states there often is none). Three directed tests (`trap_*`) now
put a store, a taken branch and a load-use pair directly behind a trap.

**Lesson.** "When does the test end" is part of the checker. Ending on the
first sign of success hides whatever was still in flight.

## 4. FENCE.I was only tested where it does not matter

**Symptom.** Round 1: `BUG_FENCEI_NO_FLUSH` (FENCE.I does not refetch)
passed every run, including the official `fence_i` test.

**Localization.** In this pipeline stores reach memory in MEM, two stages
ahead of fetch. A stale instruction can only exist if it was fetched before
the store wrote memory, which means it sits right behind the FENCE.I. The
official test patches code that runs much later, so it passes with or
without the flush. The random generator never writes to code at all.

**Fix.** Directed test `tests/directed/smc_fencei.S`, which patches the
first and the second instruction after FENCE.I (word store and byte stores)
and patches a jump. Caught in round 2.

**Lesson.** A compliance test checks the architectural promise for the
code it contains; whether it reaches the micro-architectural window where the
promise is hard to keep is a separate question, and it has to be asked per
design.

## 5. The precondition for a spurious stall never occurred

**Symptom.** Rounds 1 and 2: `BUG_LOADUSE_IGNORES_USE` (load-use check ignores
whether a register field is a real source) was caught only by two rv32ui
tests, never by the 25 random programs.

**Localization.** The bug only shows when the instruction right after a
load does not read rs1 or rs2 but has the load's destination number in
those bits (LUI, AUIPC, JAL, FENCE, SYSTEM). A static count over the 25
programs found 357 load-then-such-instruction pairs and only 2 with
matching bits, roughly the 1 in 32 chance. No coverage bin tracked it.

**Fix.** The generator now aliases the would-be rs1 bits of LUI/AUIPC to
the previous destination half of the time, and `cg_pipe` gained the bin
`cp_unused_field_matches_load`.

**Lesson.** A coverage model written from the list of features covers what
the design must do. A bug of the form "does something it should not" needs
its own precondition covered, and that only became obvious after measuring
which injected bugs escaped.
