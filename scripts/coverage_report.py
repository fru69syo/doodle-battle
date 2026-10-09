#!/usr/bin/env python3
"""Summarise an lcov.info by directory and optionally enforce minimum line coverage.

SPEC §9: pure logic (analysis, battle, growth, NG words) must have >= 80% coverage.

Usage:
  python3 scripts/coverage_report.py app/coverage/lcov.info \
      --min lib/domain/battle=80 --min lib/features/drawing_analysis=80

Prints a Markdown table (appended to $GITHUB_STEP_SUMMARY when set). Exit 1 if a
--min gate is not met. A gated prefix with no lines in the report is skipped with a
warning (the area does not exist yet), so gates can be declared ahead of time.
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict


def parse(path: str) -> dict[str, tuple[int, int]]:
    files: dict[str, tuple[int, int]] = {}
    current, found, hit = None, 0, 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("SF:"):
                current, found, hit = line[3:], 0, 0
            elif line.startswith("DA:"):
                _, count = line[3:].split(",")[:2]
                found += 1
                hit += int(count) > 0
            elif line == "end_of_record" and current:
                files[current] = (found, hit)
                current = None
    return files


def norm(path: str) -> str:
    path = path.replace("\\", "/")
    i = path.find("lib/")
    return path[i:] if i >= 0 else path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("lcov")
    ap.add_argument("--min", action="append", default=[], metavar="PREFIX=PCT")
    ap.add_argument("--depth", type=int, default=3, help="directory depth for the table")
    args = ap.parse_args()

    files = {norm(k): v for k, v in parse(args.lcov).items()}
    groups: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    total = [0, 0]
    for f, (found, hit) in files.items():
        key = "/".join(f.split("/")[: args.depth])
        if key.endswith(".dart"):
            key = "/".join(f.split("/")[: args.depth - 1])
        groups[key][0] += found
        groups[key][1] += hit
        total[0] += found
        total[1] += hit

    def pct(found: int, hit: int) -> float:
        return 100.0 * hit / found if found else 100.0

    out = ["### Dart line coverage", "", "| area | lines | covered |", "|---|---:|---:|"]
    for k in sorted(groups):
        f, h = groups[k]
        out.append(f"| `{k}` | {f} | {pct(f, h):.1f}% |")
    out.append(f"| **total** | {total[0]} | **{pct(*total):.1f}%** |")

    failed = []
    for gate in args.min:
        prefix, _, want = gate.partition("=")
        f = sum(v[0] for k, v in files.items() if k.startswith(prefix))
        h = sum(v[1] for k, v in files.items() if k.startswith(prefix))
        if f == 0:
            out.append(f"\n- WARN gate `{prefix}`: no instrumented lines (skipped)")
            continue
        got = pct(f, h)
        ok = got >= float(want)
        out.append(f"\n- {'ok' if ok else 'FAIL'} gate `{prefix}` >= {want}%: {got:.1f}%")
        if not ok:
            failed.append(prefix)

    text = "\n".join(out) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(text)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
