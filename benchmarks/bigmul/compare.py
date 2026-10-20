#!/usr/bin/env python3
"""Compare paired C benchmark CSV files from one native machine/compiler setup.

Usage: python3 compare.py baseline.csv candidate.csv
Exact algorithm, machine, and compiler identity belong in the experiment log;
this tool cannot infer or verify those facts from the CSV.
"""
import csv
import math
import sys

FIELDS = ("pattern", "bits_a", "bits_b")


def read(path):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    result = {}
    for row in rows:
        key = tuple(row[k] for k in FIELDS)
        if key in result:
            raise ValueError(f"duplicate case {key} in {path}")
        median = float(row["median_ns"])
        if not math.isfinite(median) or median <= 0:
            raise ValueError(f"invalid median for {key}: {median}")
        result[key] = row
    return result


def compare(base, candidate, out):
    base_rows = read(base)
    cand_rows = read(candidate)
    common = sorted(base_rows.keys() & cand_rows.keys(),
                    key=lambda x: (int(x[1]), int(x[2]), int(x[0])))
    writer = csv.writer(out)
    writer.writerow([*FIELDS, "base_algorithm", "candidate_algorithm",
                     "base_median_ns", "candidate_median_ns", "speedup_base_over_candidate"])
    for key in common:
        b = base_rows[key]
        c = cand_rows[key]
        bt = float(b["median_ns"])
        ct = float(c["median_ns"])
        writer.writerow([*key, b["implementation"], c["implementation"],
                         f"{bt:.3f}", f"{ct:.3f}", f"{bt/ct:.4f}"])
    if not common:
        raise ValueError("no matching cases; compare needs matching pattern, bits_a, bits_b")
    missing_base = len(cand_rows.keys() - base_rows.keys())
    missing_cand = len(base_rows.keys() - cand_rows.keys())
    if missing_base or missing_cand:
        print(f"warning: unpaired cases: only candidate={missing_base}, "
              f"only baseline={missing_cand}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: compare.py baseline.csv candidate.csv")
    compare(sys.argv[1], sys.argv[2], sys.stdout)
