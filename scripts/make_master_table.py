#!/usr/bin/env python3
"""Aggregate baseline benchmark results into MASTER.csv + MASTER.tex.

Reads:
  datasets/results/baseline/sledge/*.log
  datasets/results/baseline/prover/*.csv
  datasets/results/baseline/planner/*.csv

Writes:
  datasets/results/baseline/MASTER.csv
  datasets/results/baseline/MASTER.tex
"""
from __future__ import annotations

import argparse
import csv
import re
import statistics
from pathlib import Path
from typing import Iterable

BASE: Path = Path(__file__).resolve().parent.parent / "datasets" / "results" / "baseline"

# --- sledge log parsing -----------------------------------------------------

SLEDGE_SUMMARY_RE = re.compile(
    r"Success:\s*(\d+)\s*/\s*(\d+)\s*\(([\d.]+)%\).*?Median time:\s*([\d.]+)s.*?Average time:\s*([\d.]+)s",
    re.DOTALL,
)


def parse_sledge_log(path: Path) -> dict | None:
    text = path.read_text(errors="ignore")
    m = SLEDGE_SUMMARY_RE.search(text)
    if not m:
        return None
    return {
        "pipeline": "B0_sledge",
        "dataset": path.stem,
        "n": int(m.group(2)),
        "success": int(m.group(1)),
        "pass_rate": float(m.group(3)) / 100.0,
        "median_s": float(m.group(4)),
        "mean_s": float(m.group(5)),
    }


# --- prover / planner CSV parsing -------------------------------------------

def parse_csv(path: Path, pipeline: str) -> dict | None:
    rows = list(csv.DictReader(path.open()))
    if not rows:
        return None
    n = len(rows)
    succ = sum(1 for r in rows if (r.get("success") or "").lower() == "true")
    times = [float(r["elapsed_s"]) for r in rows if r.get("elapsed_s")]
    res = {
        "pipeline": pipeline,
        "dataset": path.stem,
        "n": n,
        "success": succ,
        "pass_rate": succ / n if n else 0.0,
        "median_s": statistics.median(times) if times else 0.0,
        "mean_s": statistics.mean(times) if times else 0.0,
    }
    if pipeline == "B2_planner":
        had_sorry = sum(1 for r in rows if (r.get("had_sorry") or "").lower() == "true")
        fills = [int(r["fills"]) for r in rows if (r.get("fills") or "").isdigit()]
        failed_holes = [
            int(r["failed_holes"]) for r in rows if (r.get("failed_holes") or "").isdigit()
        ]
        res.update({
            "had_sorry_count": had_sorry,
            "fills_median": int(statistics.median(fills)) if fills else 0,
            "failed_holes_median": int(statistics.median(failed_holes)) if failed_holes else 0,
        })
    return res


def collect() -> list[dict]:
    rows: list[dict] = []

    for log in sorted((BASE / "sledge").glob("*.log")):
        r = parse_sledge_log(log)
        if r:
            rows.append(r)

    for csvp in sorted((BASE / "prover").glob("*.csv")):
        r = parse_csv(csvp, "B1_prover")
        if r:
            rows.append(r)

    for csvp in sorted((BASE / "planner").glob("*.csv")):
        r = parse_csv(csvp, "B2_planner")
        if r:
            rows.append(r)

    return rows


# --- output writers ---------------------------------------------------------

MAIN_COLS = ["pipeline", "dataset", "n", "success", "pass_rate", "median_s", "mean_s"]
PLANNER_EXTRA = ["had_sorry_count", "fills_median", "failed_holes_median"]


def write_csv(rows: Iterable[dict], out: Path) -> None:
    rows = list(rows)
    cols = MAIN_COLS + PLANNER_EXTRA
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"[csv] {out}  ({len(rows)} rows)")


def fmt_pct(x: float) -> str:
    return f"{100 * x:.1f}\\%"


def write_tex(rows: list[dict], out: Path) -> None:
    rows.sort(key=lambda r: (r["dataset"], r["pipeline"]))
    lines = [
        "\\begin{tabular}{lllrrrrr}",
        "\\toprule",
        "Pipeline & Dataset & $n$ & Success & Pass\\% & Median (s) & Mean (s) & Notes \\\\",
        "\\midrule",
    ]
    for r in rows:
        notes = ""
        if r["pipeline"] == "B2_planner":
            notes = (
                f"sorry={r.get('had_sorry_count', 0)} "
                f"fills~={r.get('fills_median', 0)} "
                f"fh~={r.get('failed_holes_median', 0)}"
            )
        lines.append(
            f"{r['pipeline']} & {r['dataset'].replace('_', '\\_')} & {r['n']} & {r['success']} & "
            f"{fmt_pct(r['pass_rate'])} & {r['median_s']:.1f} & {r['mean_s']:.1f} & {notes} \\\\"
        )
    lines += ["\\bottomrule", "\\end{tabular}"]
    out.write_text("\n".join(lines))
    print(f"[tex] {out}  ({len(rows)} rows)")


def main() -> None:
    global BASE
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=str(BASE))
    ap.add_argument("--out-csv", default=None)
    ap.add_argument("--out-tex", default=None)
    args = ap.parse_args()

    BASE = Path(args.base)
    out_csv = Path(args.out_csv) if args.out_csv else BASE / "MASTER.csv"
    out_tex = Path(args.out_tex) if args.out_tex else BASE / "MASTER.tex"

    rows = collect()
    if not rows:
        print(f"[warn] no rows collected from {BASE}")
        return
    write_csv(rows, out_csv)
    write_tex(rows, out_tex)


if __name__ == "__main__":
    main()
