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

HERE = Path(__file__).resolve().parent
EXTRA_CHECKS = {"script": ("cancellation", "unknown-outcome"), "app": ("simulated-outcomes",)}

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


def valid_observation(field: str, value: object) -> bool:
    if field == "failed_index":
        return value is None or (type(value) is int and value >= 0)
    if field == "attempted_writes":
        return type(value) is int and value >= 0
    if field in ("verification_satisfied", "state_unchanged"):
        return type(value) is bool
    if field == "rejection":
        return isinstance(value, str)
    if not isinstance(value, list):
        return False
    if field in ("completed", "not_executed", "compensations"):
        return all(type(item) is int and item >= 0 for item in value)
    if field in ("preserved", "satisfied"):
        return all(type(item) is bool for item in value)
    return all(isinstance(item, dict) for item in value)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, help="directory with <side>.json files")
    parser.add_argument("--sides", default="script,app")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--case", action="append", default=[])
    options = parser.parse_args(argv[1:])

    sides = [name for name in options.sides.split(",") if name]
    if not sides or len(sides) != len(set(sides)) or set(sides) - EXTRA_CHECKS.keys():
        parser.error("--sides must contain distinct script/app names")
    contract = load(HERE / "contract.json")
    cases = {load(HERE / path)["id"]: load(HERE / path) for path in contract["cases"]}
    if set(options.case) - cases.keys():
        parser.error("unknown contract case(s)")
    selected = [case_id for case_id in cases if not options.case or case_id in options.case]
    results: dict[str, dict] = {}
    problems: list[str] = []
    for side in sides:
        path = Path(options.results) / f"{side}.json"
        if not path.is_file():
            problems.append(f"{side}: missing result file {path}")
            continue
        try:
            result = load(path)
            if not isinstance(result, dict) or not isinstance(result.get("cases"), list):
                raise ValueError("expected a result object with cases")
            if result.get("side") != side:
                raise ValueError("result side does not match file name")
            entries = result["cases"]
            if any(not isinstance(item, dict) or not isinstance(item.get("id"), str)
                   or not isinstance(item.get("problems"), list) for item in entries):
                raise ValueError("invalid case record")
            ids = [item["id"] for item in entries]
            expected = set(selected) | set(EXTRA_CHECKS[side])
            if len(ids) != len(set(ids)):
                problems.append(f"{side}: duplicate case records")
            if set(ids) != expected:
                problems.append(f"{side}: case coverage differs: missing={sorted(expected - set(ids))}, unexpected={sorted(set(ids) - expected)}")
            if result.get("selected") != selected:
                problems.append(f"{side}: selected cases do not match requested cases")
            if result.get("status") != "ok":
                problems.append(f"{side}: result status is not ok")
            if not isinstance(result.get("problems"), list):
                raise ValueError("missing harness problems list")
            results[side] = result
        except (OSError, ValueError, TypeError) as error:
            problems.append(f"{side}: invalid result: {error}")

    rows = []
    order: list[str] = list(selected)
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
            statuses[side] = entry.get("status", "invalid")
            if entry.get("status") != "ok":
                problems.append(f"{side}/{case_id}: case status is not ok")
            if case_id in selected:
                fields = (("rejection", "attempted_writes", "preserved", "state_unchanged")
                          if cases[case_id]["kind"] == "reject" else COMPARED_FIELDS)
                observation = entry.get("observed")
                if not isinstance(observation, dict):
                    problems.append(f"{side}/{case_id}: missing observation")
                else:
                    for field in fields:
                        if field not in observation:
                            problems.append(f"{side}/{case_id}: missing required observation {field}")
                        elif not valid_observation(field, observation[field]):
                            problems.append(f"{side}/{case_id}: invalid required observation {field}")
            if entry["problems"]:
                problems.extend(f"{side}/{case_id}: {p}" for p in entry["problems"])
        observed = {
            side: next(
                (
                    (item.get("observed") if isinstance(item.get("observed"), dict) else {})
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
            if case_id not in selected:
                continue
            fields = (("rejection", "attempted_writes", "preserved", "state_unchanged")
                      if cases[case_id]["kind"] == "reject" else COMPARED_FIELDS)
            for field in fields:
                left = observed[sides[0]].get(field)
                right = observed[side].get(field)
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
