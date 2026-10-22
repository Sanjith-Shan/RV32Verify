"""Bug-injection campaign: ./regress bugs [-n SEEDS] [--bug NAME ...]

Each bug is a realistic RTL mistake behind a `define in rtl/. For every bug
the core is rebuilt with that define and the regression runs against it:

  * the 42 rv32ui tests in both wait-state profiles (84 runs)
  * N constrained-random programs (seeds 1..N, all knob and wait profiles)

twice: once with every checker, once with SVA disabled (+verilator+noassert)
to show what the assertions add over the scoreboard alone.

The random programs are generated once by the clean build (+save_prog) and
replayed from hex for every bug, so each bug sees exactly the same stimulus
and the campaign does not pay the constraint-solver cost again.

Reported per bug: detected or not, the checker that stopped each failing
run, seeds to first failure (random seeds in order), and the earliest
failing cycle. Results: build/reports/bugs.json and build/reports/bugs.md.
"""
import json
import os

BUGS = [
    ("BUG_SLT_UNSIGNED",         "ALU",           "SLT/SLTI compare unsigned instead of signed"),
    ("BUG_SRA_LOGICAL",          "ALU",           "SRA/SRAI shift in zeros instead of copies of the sign bit"),
    ("BUG_ADDI_AS_SUB",          "decode",        "OP-IMM reuses the OP funct7 check, so ADDI with imm[10] = 1 subtracts"),
    ("BUG_SRAI_AS_SRLI",         "decode",        "immediate shifts ignore funct7: SRAI behaves as SRLI"),
    ("BUG_BRANCH_OFFSET",        "decode",        "B-type immediate off by +4"),
    ("BUG_BLTU_SIGNED",          "execute",       "BLTU compares signed"),
    ("BUG_JALR_NO_CLEAR_LSB",    "execute",       "JALR target keeps bit 0"),
    ("BUG_LB_ZERO_EXTEND",       "memory",        "LB zero-extends instead of sign-extending"),
    ("BUG_LHU_SIGN_EXTEND",      "memory",        "LHU sign-extends instead of zero-extending"),
    ("BUG_STORE_BYTE_LANE",      "memory",        "store byte enables ignore the low address bits"),
    ("BUG_WAIT_NO_BUBBLE",       "memory",        "MEM/WB is not bubbled during a data wait: the waiting instruction retires repeatedly"),
    ("BUG_FWD_PRIORITY",         "forwarding",    "MEM/WB wins over the younger EX/MEM producer"),
    ("BUG_NO_FWD_MEMWB",         "forwarding",    "no forwarding path from MEM/WB"),
    ("BUG_NO_WB_BYPASS",         "register file", "no write-through: ID reads the old value in the cycle WB writes it"),
    ("BUG_NO_LOADUSE_STALL",     "hazard",        "load-use stall never asserted"),
    ("BUG_LOADUSE_RS1_ONLY",     "hazard",        "load-use check only compares rs1"),
    ("BUG_LOADUSE_IGNORES_USE",  "hazard",        "load-use check ignores whether a field is a real source operand (spurious stalls)"),
    ("BUG_FLUSH_EX_MISSING",     "hazard",        "a redirect does not bubble ID/EX: one wrong-path instruction executes"),
    ("BUG_REDIRECT_DURING_WAIT", "hazard",        "redirect applied while MEM waits on data memory"),
    ("BUG_STALL_NO_REFRESH",     "hazard",        "operands of a held EX instruction are not refreshed during a data wait"),
    ("BUG_TRAP_NO_KILL",         "exceptions",    "a trap in MEM does not kill the instruction in EX"),
    ("BUG_FENCEI_NO_FLUSH",      "fetch",         "FENCE.I does not refetch the younger instructions"),
    ("BUG_IMEM_WAIT_DUP",        "fetch",         "IF/ID keeps its valid bit when the instruction port is not ready"),
]


def prepare_programs(R, a, n):
    """Generate random programs 1..n with the clean build and save them as hex."""
    simv = R.build()
    d = os.path.join(R.BUILD, "progs")
    os.makedirs(d, exist_ok=True)
    todo = [s for s in range(1, n + 1) if not os.path.exists(os.path.join(d, f"seed{s}.meta"))]

    def gen(s):
        args = R.random_args(s, tag="progs") + [f"+save_prog=progs/seed{s}"]
        return R.run_sim(simv, args)
    res = R.pmap(gen, todo, a.jobs)
    bad = [r for r in res if r["status"] != "PASS"]
    if bad:
        raise SystemExit(f"clean build fails on generated programs: {[r.get('name') for r in bad]}")
    progs = []
    for s in range(1, n + 1):
        meta = dict(l.strip().split("=") for l in open(os.path.join(d, f"seed{s}.meta")))
        progs.append((s, meta))
    return progs


def replay_args(R, s, meta, sva):
    w = R.WAIT_PROFILES[s % 5]
    args = [f"+hex=progs/seed{s}.hex", f"+tohost={meta['tohost'][2:]}", f"+name=seed{s}",
            f"+seed={s}", f"+verilator+seed+{s}", f"+imem_stall={w[0]}", f"+dmem_stall={w[1]}", "+quiet"]
    if meta.get("ends_in_trap") == "1":
        args.append("+end_trap_ok")
    if not sva:
        args.append("+verilator+noassert")
    return args


def rv32ui_jobs(R, sva):
    jobs = []
    for prof, ist, dst in R.STALL_PROFILES:
        for f in sorted(os.listdir(R.TESTS)):
            if not f.endswith(".hex"):
                continue
            n = f[:-4]
            if n in R.EXPECTED_FAIL:
                continue
            meta = dict(l.strip().split("=") for l in open(os.path.join(R.TESTS, n + ".meta")))
            args = [f"+hex=tests/rv32ui/{n}.hex", f"+tohost={meta['tohost'][2:]}", f"+name={n}_{prof}",
                    f"+imem_stall={ist}", f"+dmem_stall={dst}", "+seed=1", "+verilator+seed+1", "+quiet"]
            if not sva:
                args.append("+verilator+noassert")
            jobs.append(("rv32ui", n, args))
    return jobs


def summarize(name, runs):
    out = {"runs": len(runs), "fail": 0, "checkers": {}, "first_seed": None, "min_cycle": None,
           "rv32ui_fail": 0, "random_fail": 0, "first_reason": None}
    for r in runs:
        if r["status"] == "PASS":
            continue
        out["fail"] += 1
        out[r["kind"] + "_fail"] += 1
        c = r.get("checker", "other")
        out["checkers"][c] = out["checkers"].get(c, 0) + 1
        cyc = int(r.get("fail_cycle", r.get("cycles", 0)) or 0)
        if cyc and (out["min_cycle"] is None or cyc < out["min_cycle"]):
            out["min_cycle"] = cyc
        if r["kind"] == "random":
            s = int(r["seed"])
            if out["first_seed"] is None or s < out["first_seed"]:
                out["first_seed"] = s
                out["first_reason"] = r.get("sva") or r.get("reason")
    out["detected"] = out["fail"] > 0
    return out


def run(a, R):
    n = a.n if a.n != 50 else 25          # default: 25 seeds = every knob x wait combination
    bugs = [b for b in BUGS if not a.bug or b[0] in a.bug]
    progs = prepare_programs(R, a, n)
    results = []
    for bug, area, desc in bugs:
        simv = R.build(variant=bug.lower(), defines=[bug])
        entry = {"bug": bug, "area": area, "desc": desc}
        for sva in (True, False):
            jobs = rv32ui_jobs(R, sva)
            jobs += [("random", s, replay_args(R, s, meta, sva)) for s, meta in progs]
            res = R.pmap(lambda j: dict(R.run_sim(simv, j[2], timeout=300), kind=j[0], seed=j[1]), jobs, a.jobs)
            for r in res:
                r.pop("log_tail", None)
            entry["with_sva" if sva else "without_sva"] = summarize(bug, res)
        w, wo = entry["with_sva"], entry["without_sva"]
        R.log(f"[bugs] {bug:26s} {'CAUGHT' if w['detected'] else 'MISSED':6s} "
              f"fails {w['fail']:3d}/{w['runs']} (rv32ui {w['rv32ui_fail']}, random {w['random_fail']}); "
              f"first seed {w['first_seed']}; min cycle {w['min_cycle']}; checkers {w['checkers']}; "
              f"without SVA: {wo['fail']} fails {wo['checkers']}")
        results.append(entry)
    R.save("bugs", {"seeds": n, "results": results})
    write_md(R, results, n)
    caught = sum(e["with_sva"]["detected"] for e in results)
    caught_wo = sum(e["without_sva"]["detected"] for e in results)
    R.log(f"[bugs] detected {caught}/{len(results)} with all checkers, {caught_wo}/{len(results)} without SVA")
    return True


def write_md(R, results, n):
    L = ["| Bug | Area | Caught | Failing runs (rv32ui / random) | First failing seed | Earliest failing cycle | Checkers that stopped runs | Without SVA |",
         "|---|---|---|---|---:|---:|---|---|"]
    for e in results:
        w, wo = e["with_sva"], e["without_sva"]
        ch = ", ".join(f"{k} {v}" for k, v in sorted(w["checkers"].items(), key=lambda kv: -kv[1]))
        wch = ", ".join(f"{k} {v}" for k, v in sorted(wo["checkers"].items(), key=lambda kv: -kv[1]))
        L.append(f"| `{e['bug']}` | {e['area']} | {'yes' if w['detected'] else '**no**'} | "
                 f"{w['rv32ui_fail']} / {w['random_fail']} | {w['first_seed'] or '-'} | {w['min_cycle'] or '-'} | "
                 f"{ch or '-'} | {('caught: ' + wch) if wo['detected'] else '**missed**'} |")
    open(os.path.join(R.REPORTS, "bugs.md"), "w").write("\n".join(L) + "\n")
