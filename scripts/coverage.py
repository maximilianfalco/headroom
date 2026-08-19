#!/usr/bin/env python3
"""Prints line coverage for shipping code and fails below the floor.

Test sources are excluded. A suite that covers itself proves nothing.
"""
import json
import os
import sys

EXCLUDED = ("TestSupport.swift",)


def main() -> int:
    report = json.load(sys.stdin)
    files = [
        f
        for target in report.get("targets", [])
        for f in target.get("files", [])
        if not f["name"].endswith("Tests.swift") and f["name"] not in EXCLUDED
    ]
    if not files:
        print("No shipping sources in the coverage report.", file=sys.stderr)
        return 1

    covered = sum(f["coveredLines"] for f in files)
    total = sum(f["executableLines"] for f in files)
    percent = covered / total * 100

    for f in sorted(files, key=lambda f: f["lineCoverage"]):
        name, pct = f["name"], f["lineCoverage"] * 100
        print(f"  {pct:6.1f}%  {name:<26} ({f['coveredLines']}/{f['executableLines']})")
    print(f"\nShipping code: {covered}/{total} = {percent:.1f}%")

    floor = float(os.environ.get("COVERAGE_FLOOR", "80"))
    if percent < floor:
        print(f"Coverage {percent:.1f}% is below the {floor:.0f}% floor.", file=sys.stderr)
        return 1
    print(f"At or above the {floor:.0f}% floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
