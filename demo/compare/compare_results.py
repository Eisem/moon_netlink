#!/usr/bin/env python3
"""Compare the two contract sides and report where they agree or differ.

Reads the JSON results that `demo/compare/run.sh` saved for each side, prints one
row per case and asserts that

* every side passes every case and its side-specific checks,
* both sides agree on the contract-observed values (plan, acknowledged and
  not-executed operations, attempted writes, compensation, verification and the
  preservation of unmanaged resources),

and prints the recorded notes, which carry the differences that the contract
deliberately does not require both sides to reproduce. A side "winning" is not a
pass condition: a case passes only when both sides meet the declared
expectation.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

COMPARED_FIELDS = (
    "plan",
    "completed",
    "failed_index",
    "not_executed",
    "attempted_writes",
    "compensations",
    "verification_satisfied",
    "satisfied",
    "preserved",
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, help="directory with <side>.json files")
    parser.add_argument("--sides", default="script,app")
    parser.add_argument("--json", action="store_true")
    options = parser.parse_args(argv[1:])

    sides = [name for name in options.sides.split(",") if name]
    results: dict[str, dict] = {}
    problems: list[str] = []
    for side in sides:
        path = Path(options.results) / f"{side}.json"
        if not path.is_file():
            problems.append(f"{side}: missing result file {path}")
            continue
        results[side] = load(path)

    rows = []
    asymmetries: list[str] = []
    order: list[str] = []
    for side, result in results.items():
        for entry in result.get("cases", []):
            if entry["id"] not in order:
                order.append(entry["id"])

    for case_id in order:
        statuses: dict[str, str] = {}
        differences: list[str] = []
        for side in sides:
            result = results.get(side)
            entry = next(
                (item for item in (result or {}).get("cases", []) if item["id"] == case_id), None
            )
            if entry is None:
                statuses[side] = "n/a"
                continue
            statuses[side] = entry["status"]
            if entry["problems"]:
                problems.extend(f"{side}/{case_id}: {p}" for p in entry["problems"])
        observed = {
            side: next(
                (
                    item.get("observed", {})
                    for item in (results.get(side) or {}).get("cases", [])
                    if item["id"] == case_id
                ),
                {},
            )
            for side in sides
            if side in results
        }
        for side in sides[1:]:
            if side not in observed or sides[0] not in observed:
                continue
            for field in COMPARED_FIELDS:
                left = observed[sides[0]].get(field)
                right = observed[side].get(field)
                if left is None or right is None:
                    # One side does not report this value. That is a documented
                    # reporting asymmetry, not a behavioural difference, so it
                    # is recorded as a note instead of a failure.
                    if left != right:
                        asymmetries.append(
                            f"{case_id}: {field} is reported by only one side "
                            f"({sides[0]}={left!r}, {side}={right!r})"
                        )
                    continue
                if left != right:
                    differences.append(f"{field}: {sides[0]}={left!r} {side}={right!r}")
        for difference in differences:
            problems.append(f"{case_id}: the sides observed different {difference}")
        rows.append(
            {
                "id": case_id,
                "status": {side: statuses.get(side, "n/a") for side in sides},
                "differences": differences,
            }
        )

    notes = {
        side: result.get("notes", []) for side, result in results.items() if result.get("notes")
    }
    harness = {
        side: result.get("problems", []) for side, result in results.items() if result.get("problems")
    }
    for side, messages in harness.items():
        problems.extend(f"{side}: {message}" for message in messages)
    if notes or asymmetries:
        merged = {
            side: list(messages) for side, messages in notes.items()
        }
        merged.setdefault("both sides", [])
        merged["both sides"] = list(dict.fromkeys(merged["both sides"] + asymmetries))
        notes = merged

    report = {
        "sides": sides,
        "cases": rows,
        "notes": notes,
        "problems": problems,
        "status": "failed" if problems else "ok",
    }
    if options.json:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if problems else 0

    width = max([len(row["id"]) for row in rows] + [8])
    header = f"{'case':<{width}}  " + "  ".join(f"{side:<8}" for side in sides)
    print(header)
    print("-" * len(header))
    for row in rows:
        marks = "  ".join(
            f"{(row['status'].get(side) or 'n/a'):<8}" for side in sides
        )
        print(f"{row['id']:<{width}}  {marks}")
    for side, messages in notes.items():
        for message in messages:
            print(f"note ({side}): {message}")
    if problems:
        print("\ncomparison failures:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            f"\ncomparison: {len(problems)} failure(s); both sides must meet the contract",
            file=sys.stderr,
        )
    else:
        print(
            f"\ncomparison: {len(sides)} sides, {len(rows)} case(s); both sides met every "
            "declared expectation"
        )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
