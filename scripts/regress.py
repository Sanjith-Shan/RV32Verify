#!/usr/bin/env python3
"""RV32Verify regression runner. One command builds and runs everything.

    ./regress                     lint + ISS qualification + riscv-tests + random
    ./regress riscv-tests         official rv32ui suite, with and without wait states
    ./regress random -n 200       constrained-random seeds 1..200
    ./regress coverage -n 400     random seeds with merged functional coverage report
    ./regress bugs                bug-injection campaign (docs/BUG_INJECTION.md)
    ./regress lint | iss | build

Results are printed and written to build/reports/<suite>.json.
Standard library only.
"""
import argparse
import concurrent.futures as cf
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
REPORTS = os.path.join(BUILD, "reports")
TESTS = os.path.join(BUILD, "tests", "rv32ui")
TEST_GROUPS = ["rv32ui", "directed"]     # build/tests/<group>/<name>.hex


def list_tests():
    """(group, name, meta) for every built program test: rv32ui, then directed."""
    out = []
    for g in TEST_GROUPS:
        d = os.path.join(BUILD, "tests", g)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".hex"):
                n = f[:-4]
                meta = dict(l.strip().split("=", 1) for l in open(os.path.join(d, n + ".meta")))
                out.append((g, n, meta))
    return out
TOOLCHAIN = os.path.join(ROOT, ".cache", "toolchain")

# Tests that are expected to fail, and why. Reported separately, never hidden.
EXPECTED_FAIL = {
    "ma_data": "exercises misaligned loads/stores; this core raises a misaligned-access "
               "exception by design (allowed by the ISA) and has no trap handler to emulate them",
}

# Wait-state profiles for the memory agent: (name, imem_stall %, dmem_stall %)
STALL_PROFILES = [("nostall", 0, 0), ("stall30", 30, 30)]


def env():
    e = dict(os.environ)
    tc_bin = [os.path.join(TOOLCHAIN, "oss-cad-suite", "bin"), os.path.join(TOOLCHAIN, "riscv", "bin")]
    e["PATH"] = os.pathsep.join([p for p in tc_bin if os.path.isdir(p)] + [e.get("PATH", "")])
    return e


def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, env=env(), text=True, capture_output=True, **kw)


def log(msg):
    print(msg, flush=True)


def save(name, data):
    os.makedirs(REPORTS, exist_ok=True)
    data["date"] = dt.datetime.now().isoformat(timespec="seconds")
    with open(os.path.join(REPORTS, name + ".json"), "w") as f:
        json.dump(data, f, indent=1)


# ---------------------------------------------------------------- building
SIM_SOURCES = ["rtl", "tb", "model", "scripts/build_sim.sh"]


def newest_source_mtime():
    m = 0.0
    for s in SIM_SOURCES:
        p = os.path.join(ROOT, s)
        if os.path.isfile(p):
            m = max(m, os.path.getmtime(p))
            continue
        for d, _, files in os.walk(p):
            for f in files:
                m = max(m, os.path.getmtime(os.path.join(d, f)))
    return m


def build(variant="base", defines=(), force=False):
    out = os.path.join(BUILD, "sim", variant)
    simv = os.path.join(out, "simv")
    if not force and os.path.exists(simv) and os.path.getmtime(simv) > newest_source_mtime():
        return simv
    log(f"[build] {variant} {' '.join(defines)}")
    t0 = time.time()
    r = sh(["bash", "scripts/build_sim.sh", out] + [f"-D{d}" for d in defines])
    if r.returncode != 0 or not os.path.exists(simv):
        log(r.stdout[-4000:] + r.stderr[-4000:])
        sys.exit(f"[build] {variant} failed")
    log(f"[build] {variant} done in {time.time() - t0:.0f}s")
    return simv


def ensure_tests():
    d = os.path.join(BUILD, "tests", "directed")
    if not os.path.isdir(TESTS) or not any(f.endswith(".hex") for f in os.listdir(TESTS)) or not os.path.isdir(d):
        r = sh(["bash", "scripts/build_riscv_tests.sh"])
        if r.returncode != 0:
            log(r.stdout + r.stderr)
            sys.exit("cannot build riscv-tests")


# ----------------------------------------------------------------- running
RESULT_RE = re.compile(r"^RESULT: (PASS|FAIL) (.*)$", re.M)


def parse_kv(s):
    kv = dict(re.findall(r'(\w+)=("[^"]*"|\S+)', s))
    return {k: v.strip('"') for k, v in kv.items()}


def run_sim(simv, args, timeout=600):
    t0 = time.time()
    try:
        p = subprocess.run([simv] + args, cwd=BUILD, env=env(), text=True, capture_output=True, timeout=timeout)
        out = p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") if isinstance(e.stdout, str) else ""
        out += "\nRESULT: FAIL reason=\"wall-clock timeout\""
    res = {"args": args, "secs": round(time.time() - t0, 2)}
    m = RESULT_RE.search(out)
    if m:
        res["status"] = m.group(1)
        res.update(parse_kv(m.group(2)))
    else:
        res["status"] = "FAIL"
        res["reason"] = "no RESULT line (simulator crashed or assertion fired)"
    sva = re.search(r"(SVA[^\n]*)", out)
    t = re.search(r"^\[(\d+)\] %(Error|Fatal)", out, re.M)
    if t:
        res["fail_cycle"] = int(t.group(1)) // 10000   # ps -> 10 ns clock cycles
    if res["status"] == "FAIL":
        res["checker"] = classify(out)
        if sva:
            res["sva"] = sva.group(1).strip()
        res["log_tail"] = out[-3000:]
    return res


def classify(out):
    """Which checker stopped the test."""
    if re.search(r"SVA ", out):
        return "assertion"
    if "LOCKSTEP MISMATCH" in out:
        return "scoreboard"
    if "END-OF-TEST STATE MISMATCH" in out:
        return "end-state"
    if "retired after the trap" in out:
        return "drain"
    if "hang:" in out:
        return "watchdog"
    if "timeout" in out:
        return "timeout"
    if "tohost=" in out or "program reported failure" in out:
        return "self-check"
    if "unexpected trap" in out:
        return "unexpected-trap"
    return "other"


def pmap(fn, items, jobs):
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        return list(ex.map(fn, items))


# ------------------------------------------------------------------ suites
def suite_lint(a):
    r = sh(["bash", "scripts/lint.sh"])
    ok = r.returncode == 0
    log(("[lint] PASS " if ok else "[lint] FAIL ") + (r.stdout + r.stderr).strip().splitlines()[-1])
    save("lint", {"pass": ok, "output": r.stdout + r.stderr})
    return ok


def suite_iss(a):
    ensure_tests()
    r = sh(["bash", "scripts/run_iss_tests.sh"])
    lines = r.stdout.strip().splitlines()
    fails = [l.split()[0] for l in lines if " FAIL " in l]
    unexpected = [f for f in fails if f not in EXPECTED_FAIL]
    log(f"[iss] {lines[-1]}  (expected failures: {', '.join(f for f in fails if f in EXPECTED_FAIL) or 'none'})")
    save("iss", {"summary": lines[-1], "fails": fails, "unexpected": unexpected})
    return not unexpected


def suite_riscv_tests(a):
    ensure_tests()
    simv = build()
    jobs = []
    for prof, ist, dst in STALL_PROFILES:
        for g, n, meta in list_tests():
            args = [f"+hex=tests/{g}/{n}.hex", f"+tohost={meta['tohost'][2:]}", f"+name={n}",
                    *(["+end_trap_ok"] if n.startswith("trap_") else []),
                    f"+imem_stall={ist}", f"+dmem_stall={dst}", "+seed=1", "+verilator+seed+1", "+quiet",
                    cov_arg("riscv-tests", f"{prof}_{n}")]
            jobs.append((prof, n if g == "rv32ui" else f"{g}/{n}", args))
    res = pmap(lambda j: dict(run_sim(simv, j[2]), profile=j[0], test=j[1]), jobs, a.jobs)
    ok = True
    summary = {}
    for prof, _, _ in STALL_PROFILES:
        rs = [r for r in res if r["profile"] == prof]
        npass = sum(r["status"] == "PASS" for r in rs)
        xfail = [r["test"] for r in rs if r["status"] == "FAIL" and r["test"] in EXPECTED_FAIL]
        ufail = [r["test"] for r in rs if r["status"] == "FAIL" and r["test"] not in EXPECTED_FAIL]
        upass = [r["test"] for r in rs if r["status"] == "PASS" and r["test"] in EXPECTED_FAIL]
        summary[prof] = {"total": len(rs), "pass": npass, "expected_fail": xfail, "unexpected_fail": ufail,
                         "unexpected_pass": upass}
        nd = [r for r in rs if r["test"].startswith("directed/")]
        ndp = sum(r["status"] == "PASS" for r in nd)
        log(f"[riscv-tests] {prof:8s} rv32ui {npass - ndp}/{len(rs) - len(nd)} pass, directed {ndp}/{len(nd)} pass; "
            f"expected fail: {', '.join(xfail) or 'none'}; "
            f"unexpected fail: {', '.join(ufail) or 'none'}")
        for r in rs:
            if r["test"] in ufail:
                log(f"    {r['test']}: {r.get('reason', '')}\n" + r.get("log_tail", "")[-1500:])
        ok &= not ufail
    save("riscv_tests", {"summary": summary, "expected_fail_reasons": EXPECTED_FAIL, "runs": res})
    return ok


def cov_arg(suite, name):
    # every run writes its own coverage database: build/cov/<suite>/<name>.dat
    d = os.path.join(BUILD, "cov", suite)
    os.makedirs(d, exist_ok=True)
    return f"+verilator+coverage+file+cov/{suite}/{name}.dat"


# Random test variants: generator knob profiles (see tb/gen/rv_gen.svh). Seed s
# uses wait-state profile s % 5 and knob profile (s // 5) % 5, so every 25
# consecutive seeds cover all 25 combinations.
WAIT_PROFILES = [(0, 0), (20, 0), (0, 30), (25, 25), (50, 50)]
KNOB_PROFILES = [
    ("default",    []),
    ("alu_corner", ["+w_alu_r=40", "+w_alu_i=30", "+w_shift=15", "+w_seed=35", "+p_special=50",
                    "+p_dep=80", "+dep_max=3", "+w_load=6", "+w_store=4", "+w_branch=6"]),
    ("mem_alias",  ["+w_load=30", "+w_store=25", "+mem_window=16", "+p_alias=70", "+w_reload=8"]),
    ("branchy",    ["+w_branch=30", "+w_jal=6", "+w_jalr=6", "+p_self_cmp=40", "+skip_max=3", "+p_loop=6"]),
    ("hazard",     ["+p_dep=90", "+dep_max=2", "+w_load=25", "+w_store=12"]),
]


def random_args(seed, extra=(), tag="random"):
    w = WAIT_PROFILES[seed % 5]
    k = KNOB_PROFILES[(seed // 5) % 5]
    return (["+gen", f"+seed={seed}", f"+verilator+seed+{seed}", f"+imem_stall={w[0]}",
             f"+dmem_stall={w[1]}", f"+name=seed{seed}_{k[0]}", "+quiet", cov_arg(tag, f"seed{seed}")]
            + k[1] + list(extra))


def suite_random(a, extra=(), simv=None, tag="random"):
    simv = simv or build()
    seeds = list(range(a.seed0, a.seed0 + a.n))
    res = pmap(lambda s: dict(run_sim(simv, random_args(s, extra, tag)), seed=s), seeds, a.jobs)
    npass = sum(r["status"] == "PASS" for r in res)
    retired = sum(int(r.get("retired", 0)) for r in res)
    cycles = sum(int(r.get("cycles", 0)) for r in res)
    log(f"[{tag}] {npass}/{len(res)} seeds pass, {retired} instructions retired and checked, {cycles} cycles")
    for r in res:
        if r["status"] != "PASS":
            log(f"    seed {r['seed']}: {r.get('reason', '')} [{r.get('checker', '')}]")
    save(tag, {"seeds": [seeds[0], seeds[-1]], "pass": npass, "total": len(res), "retired": retired,
               "cycles": cycles, "runs": res})
    return npass == len(res)


def suite_coverage(a):
    """Fresh coverage databases from riscv-tests + N random seeds, merged into one report."""
    for s in ("random", "riscv-tests"):
        shutil.rmtree(os.path.join(BUILD, "cov", s), ignore_errors=True)
    ok = suite_riscv_tests(a)
    ok &= suite_random(a)
    dats = []
    for s in ("riscv-tests", "random"):
        d = os.path.join(BUILD, "cov", s)
        dats += sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".dat"))
    os.makedirs(REPORTS, exist_ok=True)
    r = sh(["python3", "scripts/cov_report.py", "-o", os.path.join(REPORTS, "coverage.md"),
            "--json", os.path.join(REPORTS, "coverage.json"),
            "--title", f"Functional coverage: rv32ui (2 wait-state profiles) + random seeds "
                       f"{a.seed0}..{a.seed0 + a.n - 1}"] + dats)
    log("[coverage] " + r.stderr.strip() + f"  -> build/reports/coverage.md")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("suite", nargs="?", default="all",
                    choices=["all", "lint", "iss", "build", "riscv-tests", "random", "coverage", "bugs"])
    ap.add_argument("-n", type=int, default=50, help="number of random seeds")
    ap.add_argument("--seed0", type=int, default=1, help="first random seed")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--bug", action="append", default=[], help="bugs suite: only these bug names")
    a = ap.parse_args()

    if a.suite == "build":
        build(force=True)
        return 0
    if a.suite == "all":
        ok = True
        if a.n == 50:
            a.n = 25        # default for "all": 25 seeds = every knob x wait profile once
        for name, fn in [("lint", suite_lint), ("iss", suite_iss), ("riscv-tests", suite_riscv_tests),
                         ("random", suite_random)]:
            ok &= bool(fn(a))
        log("REGRESSION " + ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    fn = {"lint": suite_lint, "iss": suite_iss, "riscv-tests": suite_riscv_tests, "random": suite_random,
          "coverage": suite_coverage}.get(a.suite)
    if fn is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location(a.suite, os.path.join(ROOT, "scripts", f"suite_{a.suite}.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        fn = lambda args: mod.run(args, sys.modules[__name__])
    return 0 if fn(a) else 1


if __name__ == "__main__":
    sys.exit(main())
