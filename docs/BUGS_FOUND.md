# Bugs found during development

Only real bugs are listed here, in the order they were found: things that
were actually wrong in this repository and were caught by a check. The
deliberately injected mutations live in [BUG_INJECTION.md](BUG_INJECTION.md)
and are never presented as findings.

## Summary, stated first

The bench has not found a functional bug in the core RTL so far. The core
passed riscv-tests and the first random seeds in lockstep on its first run.
That is not proof it is correct. The [bug-injection campaign](BUG_INJECTION.md)
measures whether the bench would have noticed if it were wrong, and formal
checks with riscv-formal give a second, independent opinion (results below
and in [RESULTS.md](RESULTS.md)).

The real bugs found so far were in the verification environment itself. A
coverage model that reports a hole that is not there, or misses a hole that
is, is a bug that leads to wrong sign-off decisions. So they are recorded the
same way.

| # | Where | Found by | Symptom | Root cause |
|---|---|---|---|---|
| 1 | coverage model | SVA cover vs covergroup disagreement | `cp_stall_then_forward` 0 hits over 122 runs while the SVA cover for the same event had 458 | cycle-count off by one in the sampling logic |
| 2 | coverage model | coverage hole review | `cp_trap.insn_misaligned` 0 hits over 100 seeds although the generator ends about 4% of programs with a misaligned jump | the coverpoint guard used `cause != 0` to mean "trapped", and cause 0 is a real cause |

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
