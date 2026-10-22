# Bug-injection campaign

**Question:** if the core had a bug, would this bench notice, how quickly,
and which checker would say so?

**Method.** 23 realistic RTL mistakes, each behind a `` `define `` in `rtl/`
(search for `BUG_`). They are the kind of mistakes made when writing a
pipeline: wrong signedness, a dropped funct7 check, a missing stall
condition, a flush that misses one stage, a forwarding priority inverted, an
interaction with memory wait states handled wrong. For each one the core is
rebuilt with only that define and the regression runs against it:

- the 41 passing rv32ui tests and the 4 directed tests, in both wait-state
  profiles (90 runs; the directed tests were added during this campaign, see
  below)
- 25 constrained-random programs (seeds 1 to 25, which cover every knob
  profile and every wait-state profile once)

Every run stops at the first failure. The runner records which checker
stopped it: `scoreboard` (lockstep mismatch against the reference model),
`assertion` (an SVA invariant), `end-state` (register/memory compare after
the last instruction), `watchdog` (nothing retired for 1000 cycles),
`self-check` (a riscv-test reported its own failure through `tohost`).

The whole campaign runs twice, the second time with every assertion
disabled at run time (`+verilator+noassert`), to show what the assertions
add on top of the scoreboard.

The random programs are generated once by the clean build and saved as hex
(`+save_prog`). Every bug build replays exactly the same programs with the
same wait-state patterns, so the columns are comparable.

Reproduce: `./regress bugs` (about 17 minutes on the machine in
[RESULTS.md](RESULTS.md)); one bug: `./regress bugs --bug BUG_FWD_PRIORITY`.

## Results

### Headline, stated first

| Round | Bench | Caught, all checkers | Caught, scoreboard only (SVA off) |
|---|---|---|---|
| 1 | as designed before the campaign | **21 / 23** | 19 / 23 |
| 2 | + drain window after the end of a test, + FENCE.I directed test | 23 / 23 | 21 / 23 |
| 3 | + three trap directed tests, + field-aliasing stimulus, + new coverage bin | **23 / 23** | 21 / 23 |

**Round 1 is the honest number for the bench as first built: 21 of 23.**
Rounds 2 and 3 were run after looking at which bugs escaped and fixing the
bench, so they are no longer a blind measurement of the bench; they show
that the holes were closed. A fair re-measurement would need a fresh set of
bugs written by someone else, which is noted as future work. The two bugs the
scoreboard alone misses in every round are explained below; they are not
holes in the bench.

### Round 3, per bug (current bench)

| Bug | Area | Caught | Failing runs (rv32ui / directed / random) | First failing seed | Earliest failing cycle | Checkers that stopped runs | Without SVA |
|---|---|---|---|---:|---:|---|---|
| `BUG_SLT_UNSIGNED` | ALU | yes | 4 / 0 / 25 | 1 | 30 | scoreboard 29 | caught: scoreboard 29 |
| `BUG_SRA_LOGICAL` | ALU | yes | 6 / 0 / 25 | 1 | 14 | scoreboard 31 | caught: scoreboard 31 |
| `BUG_ADDI_AS_SUB` | decode | yes | 82 / 4 / 25 | 1 | 8 | scoreboard 111 | caught: scoreboard 111 |
| `BUG_SRAI_AS_SRLI` | decode | yes | 4 / 0 / 25 | 1 | 14 | scoreboard 29 | caught: scoreboard 29 |
| `BUG_BRANCH_OFFSET` | decode | yes | 78 / 0 / 25 | 1 | 11 | scoreboard 103 | caught: scoreboard 103 |
| `BUG_BLTU_SIGNED` | execute | yes | 2 / 0 / 23 | 1 | 35 | scoreboard 25 | caught: scoreboard 25 |
| `BUG_JALR_NO_CLEAR_LSB` | execute | yes | 0 / 0 / 24 | 1 | 59 | scoreboard 24 | caught: scoreboard 24 |
| `BUG_LB_ZERO_EXTEND` | memory | yes | 8 / 0 / 17 | 1 | 12 | scoreboard 25 | caught: scoreboard 25 |
| `BUG_LHU_SIGN_EXTEND` | memory | yes | 2 / 0 / 22 | 2 | 20 | scoreboard 24 | caught: scoreboard 24 |
| `BUG_STORE_BYTE_LANE` | memory | yes | 18 / 2 / 25 | 1 | 12 | scoreboard 45 | caught: scoreboard 45 |
| `BUG_WAIT_NO_BUBBLE` | memory | yes | 23 / 1 / 15 | 2 | 11 | assertion 39 | caught: scoreboard 39 |
| `BUG_FWD_PRIORITY` | forwarding | yes | 79 / 2 / 25 | 1 | 9 | assertion 106 | caught: scoreboard 106 |
| `BUG_NO_FWD_MEMWB` | forwarding | yes | 77 / 2 / 25 | 1 | 8 | assertion 104 | caught: scoreboard 104 |
| `BUG_NO_WB_BYPASS` | register file | yes | 81 / 2 / 25 | 1 | 12 | scoreboard 108 | caught: scoreboard 108 |
| `BUG_NO_LOADUSE_STALL` | hazard | yes | 12 / 1 / 25 | 1 | 11 | assertion 38 | caught: scoreboard 37 |
| `BUG_LOADUSE_RS1_ONLY` | hazard | yes | 2 / 0 / 19 | 1 | 11 | assertion 21 | caught: scoreboard 21 |
| `BUG_LOADUSE_IGNORES_USE` | hazard | yes | 2 / 0 / 17 | 1 | 60 | assertion 19 | **missed** |
| `BUG_FLUSH_EX_MISSING` | hazard | yes | 82 / 2 / 25 | 1 | 9 | assertion 109 | caught: scoreboard 109 |
| `BUG_REDIRECT_DURING_WAIT` | hazard | yes | 11 / 1 / 9 | 2 | 17 | assertion 21 | **missed** |
| `BUG_STALL_NO_REFRESH` | hazard | yes | 3 / 1 / 10 | 2 | 76 | assertion 14 | caught: scoreboard 14 |
| `BUG_TRAP_NO_KILL` | exceptions | yes | 0 / 3 / 3 | 19 | 12 | assertion 6 | caught: scoreboard 6 |
| `BUG_FENCEI_NO_FLUSH` | fetch | yes | 0 / 2 / 0 | - | 16 | scoreboard 2 | caught: scoreboard 2 |
| `BUG_IMEM_WAIT_DUP` | fetch | yes | 41 / 2 / 15 | 1 | 9 | scoreboard 58 | caught: scoreboard 58 |

Columns: failing runs out of 82 rv32ui runs, 8 directed runs and 25 random
programs; "first failing seed" is the lowest random seed that failed (all
25 are run, in parallel); "earliest failing cycle" is the smallest failing
cycle over all failing runs, counted from time 0 including 4 reset cycles.

### Round 1 escapes, and what changed

| Bug | Round 1 | Why it escaped | Fix | Round 3 |
|---|---|---|---|---|
| `BUG_TRAP_NO_KILL` | missed by all 107 runs | the test ended in the cycle the trap retired, before the leaked instruction could retire | 30-cycle drain window with every checker live; 3 directed tests with a store, a taken branch and a load-use pair directly behind a trap | caught by all 3 directed tests (both wait profiles) and 3 random programs |
| `BUG_FENCEI_NO_FLUSH` | missed by all 107 runs, including rv32ui `fence_i` | nothing patched an instruction already fetched behind FENCE.I, the only case where the flush matters in this pipeline | directed `smc_fencei` | caught by `smc_fencei` in both wait profiles |
| `BUG_LOADUSE_IGNORES_USE` | caught by 2 rv32ui runs, 0 random | its precondition (an unused register field equal to the load's destination) happened about 1 time in 32 by chance; no coverage bin | field aliasing in LUI/AUIPC; bin `cp_unused_field_matches_load` | caught in 17 of 25 random programs |

The full write-ups are entries 3 to 5 in [BUGS_FOUND.md](BUGS_FOUND.md).
Raw per-round data: `build/reports/bugs_round1.json`,
`bugs_round2.json`, `bugs.json` (not in git; regenerate with the command
above at the matching commit).

## Reading the table

- **The scoreboard carries most of the load.** 21 of 23 bugs produce a
  wrong architectural result and the lockstep compare catches all of them.
- **Where assertions are on, they usually fire first.** For every hazard,
  forwarding and stall bug the run was stopped by an assertion, in the cycle
  and at the stage where the rule broke, rather than by the scoreboard some
  instructions later. That is what makes those failures quick to debug.
- **Two bugs are invisible to the scoreboard by nature.**
  `BUG_LOADUSE_IGNORES_USE` only adds stall cycles: results stay correct, the
  core is just slower. `BUG_REDIRECT_DURING_WAIT` applies a redirect while EX
  is held; because EX stays held and re-applies the same redirect, the
  architectural result does not change in this pipeline. Both are rule
  violations that only `a_loaduse_real` and `a_redirect_only_when_advancing`
  catch. They are kept in the list because they are exactly what a real
  design rule review would flag, and because they measure what the
  assertions add.
- **Directed tests still matter.** Two of the three round-1 escapes were
  closed with a directed test, because the micro-architectural window that
  exposes them is narrow (one instruction behind FENCE.I, one behind a
  trap). Random stimulus with the current knobs reaches the trap window in
  only 3 of 25 programs.
- **Wait states expose a different class of bug.** `BUG_STALL_NO_REFRESH`,
  `BUG_WAIT_NO_BUBBLE`, `BUG_REDIRECT_DURING_WAIT` and `BUG_IMEM_WAIT_DUP`
  can only fail when the memory agent inserts wait states; with the
  no-wait profile alone they would pass most runs.

### Which assertion fired (round 3, lowest failing random seed)

| Bug | First failure message |
|---|---|
| `BUG_WAIT_NO_BUBBLE` | `SVA a_wait_holds: state moved during a data-memory wait` |
| `BUG_FWD_PRIORITY` | `SVA a_fwd_a_youngest: rs1 x26 not forwarded from EX/MEM` |
| `BUG_NO_FWD_MEMWB` | `SVA a_fwd_a_memwb: rs1 x13 not forwarded from MEM/WB` |
| `BUG_NO_LOADUSE_STALL` | `SVA a_loaduse_needed: load-use dependency in ID with no stall (ID 00ff6263, EX 80cd2783)` |
| `BUG_LOADUSE_RS1_ONLY` | same message, same program point: the dependent instruction is a branch reading the load result as rs2 |
| `BUG_LOADUSE_IGNORES_USE` | `SVA a_loaduse_real: stall without a load-use dependency (ID 30d28137, EX 830d2283)` (a LUI whose immediate bits alias the load's rd) |
| `BUG_FLUSH_EX_MISSING` | `SVA a_redirect_flushes: wrong-path instruction survived a redirect` |
| `BUG_REDIRECT_DURING_WAIT` | `SVA a_redirect_only_when_advancing` |
| `BUG_STALL_NO_REFRESH` | `SVA a_wait_refresh: operand lost while EX was held (pc 80000564)` |
| `BUG_TRAP_NO_KILL` | `SVA a_trap_flushes` |

Every assertion that fired is the one written for that rule, which is the
point of writing them per invariant: the failure message names the broken
rule, not just a wrong value.
