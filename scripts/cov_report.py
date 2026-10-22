#!/usr/bin/env python3
"""Merge Verilator coverage.dat files and report functional coverage.

    cov_report.py [-o report.md] [--json out.json] run1.dat run2.dat ...

Reads the covergroup bins (and SVA cover properties) that Verilator writes
with --coverage-user, sums hit counts across runs, and prints per-covergroup
and per-coverpoint coverage with every unhit bin listed. Bins whose name
starts with "ign_" are ignore_bins and are not counted. Standard library only.
"""
import argparse
import collections
import json
import re
import sys

LINE_RE = re.compile(r"^C '(.*)' (\d+)$")


def parse_keys(s):
    out = {}
    for field in s.split("\x01"):
        if "\x02" in field:
            k, v = field.split("\x02", 1)
            out[k] = v
    return out


def load(paths):
    bins = collections.OrderedDict()     # (group, point, bin) -> count
    covers = collections.OrderedDict()   # cover property name -> count
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = LINE_RE.match(line.rstrip("\n"))
                if not m:
                    continue
                k = parse_keys(m.group(1))
                n = int(m.group(2))
                page = k.get("page", "")
                if page.startswith("v_covergroup/"):
                    group = page[len("v_covergroup/"):]
                    rest = k["h"][len(group) + 1:]
                    point, b = rest.split(".", 1)
                    key = (group.split("::")[-1], point, b)
                    bins[key] = bins.get(key, 0) + n
                elif page.startswith("v_user/") or k.get("t") == "user":
                    name = k.get("h", k.get("o", "?")).split(".")[-1]
                    covers[name] = covers.get(name, 0) + n
    return bins, covers


def summarize(bins):
    groups = collections.OrderedDict()
    for (g, pt, b), n in bins.items():
        if b.startswith("ign_"):
            continue
        groups.setdefault(g, collections.OrderedDict()).setdefault(pt, []).append((b, n))
    return groups


def pct(h, t):
    return 100.0 * h / t if t else 100.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dat", nargs="+")
    ap.add_argument("-o", "--out")
    ap.add_argument("--json")
    ap.add_argument("--title", default="Functional coverage")
    a = ap.parse_args()
    bins, covers = load(a.dat)
    groups = summarize(bins)

    lines = [f"## {a.title}", "", f"Merged from {len(a.dat)} run(s).", ""]
    tot_h = tot_t = 0
    rows = []
    for g, pts in groups.items():
        gh = sum(1 for p in pts.values() for _, n in p if n > 0)
        gt = sum(len(p) for p in pts.values())
        tot_h += gh
        tot_t += gt
        rows.append((g, gh, gt))
    lines += ["| Covergroup | Bins hit | Bins | Coverage |", "|---|---:|---:|---:|"]
    for g, gh, gt in rows:
        lines.append(f"| {g} | {gh} | {gt} | {pct(gh, gt):.1f}% |")
    lines.append(f"| **total** | **{tot_h}** | **{tot_t}** | **{pct(tot_h, tot_t):.1f}%** |")
    lines += ["", "### Coverpoints and crosses", "", "| Item | Hit | Bins | Coverage |", "|---|---:|---:|---:|"]
    for g, pts in groups.items():
        for pt, bl in pts.items():
            h = sum(1 for _, n in bl if n > 0)
            lines.append(f"| {g}.{pt} | {h} | {len(bl)} | {pct(h, len(bl)):.1f}% |")
    holes = [(g, pt, b) for g, pts in groups.items() for pt, bl in pts.items() for b, n in bl if n == 0]
    lines += ["", f"### Holes ({len(holes)} unhit bins)", ""]
    if holes:
        lines += ["```"] + [f"{g}.{pt}.{b}" for g, pt, b in holes] + ["```"]
    else:
        lines.append("None.")
    if covers:
        lines += ["", "### SVA cover properties", "", "| Cover | Hits |", "|---|---:|"]
        lines += [f"| {c} | {n} |" for c, n in covers.items()]
    text = "\n".join(lines) + "\n"
    if a.out:
        open(a.out, "w").write(text)
    else:
        sys.stdout.write(text)
    if a.json:
        json.dump({"bins_hit": tot_h, "bins_total": tot_t, "pct": round(pct(tot_h, tot_t), 2),
                   "groups": {g: {"hit": gh, "total": gt} for g, gh, gt in rows},
                   "holes": [".".join(x) for x in holes], "covers": covers}, open(a.json, "w"), indent=1)
    print(f"coverage: {tot_h}/{tot_t} bins = {pct(tot_h, tot_t):.1f}%  ({len(holes)} holes)", file=sys.stderr)


if __name__ == "__main__":
    main()
