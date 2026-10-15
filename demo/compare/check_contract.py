#!/usr/bin/env python3
"""Validate the shared comparison contract of `demo/compare/` (P5-V1).

This checker is deliberately independent of both implementations. It reads the
contract and every case, re-derives the expected operations, rejections and
final state from the declared initial state plus the desired file, and fails if
the declaration and the derivation disagree. It needs no privileges, no network
namespace and no Linux kernel, so it also runs on Windows.

Usage:
    python3 demo/compare/check_contract.py [--json]
"""

from __future__ import annotations

import ipaddress
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "contract.json"

OPERATION_RANK = {
    "delete_route": 0,
    "delete_address": 1,
    "set_mtu": 2,
    "set_link_up": 3,
    "add_address": 4,
    "add_route": 5,
    "set_link_down": 6,
}

ROUTE_OPERATIONS = ("add_route", "delete_route")

# Operation parameters that both implementations must agree on, per operation
# kind. `interface_index` and `before` are observations, not declared intent.
# Case files may annotate an operation with extra checker hints such as
# `fails_with_errno`.
OPERATION_FIELDS = {
    "set_mtu": ("operation", "interface", "after"),
    "set_link_up": ("operation", "interface"),
    "set_link_down": ("operation", "interface"),
    "add_address": ("operation", "interface", "address", "prefix_length", "scope"),
    "delete_address": ("operation", "interface", "address", "prefix_length", "scope"),
    "add_route": (
        "operation", "interface", "destination", "prefix_length", "gateway",
        "table", "priority", "protocol", "scope",
    ),
    "delete_route": (
        "operation", "interface", "destination", "prefix_length", "gateway",
        "table", "priority", "protocol", "scope",
    ),
}

REJECTION_REASONS = (
    "InvalidField",
    "ConflictingIntent",
    "MissingInterface",
    "UnsupportedIntent",
    "UnsupportedCurrentResource",
    "ProtectedResource",
    "invalid interface name",
)

CASE_REQUIRED = (
    "id",
    "kind",
    "title_en",
    "title_zh",
    "intent_en",
    "intent_zh",
    "desired",
    "initial",
    "expected",
    "final",
)

EXPECTED_REQUIRED = (
    "plan_steps",
    "operations",
    "kernel_write_attempts",
    "compensation_attempts",
    "exit_status",
    "completed",
    "failed",
    "not_executed",
    "verification_satisfied",
    "rejection",
    "protected_resource",
)

INITIAL_REQUIRED = ("links", "present_addresses", "present_routes", "unmanaged")

LINK_KEYS = ("name", "ensure", "up", "mtu")
ADDRESS_KEYS = ("interface", "ensure", "address", "prefix_length", "scope")
ROUTE_KEYS = (
    "interface",
    "ensure",
    "destination",
    "prefix_length",
    "gateway",
    "table",
    "priority",
    "protocol",
    "scope",
)

INTEGER_RANGES = {
    "mtu": (1, 4294967295),
    "prefix_length": (0, 128),
    "scope": (0, 255),
    "table": (0, 4294967295),
    "priority": (0, 4294967295),
    "protocol": (0, 255),
}


class LiteralError(ValueError):
    """A JSON number that is not an unsigned decimal integer literal."""


def reject_int(text: str) -> int:
    if not re.fullmatch(r"[0-9]+", text):
        raise LiteralError(f"number token {text!r} is not an unsigned integer literal")
    return int(text)


def reject_float(text: str) -> float:
    raise LiteralError(f"number token {text!r} is not an unsigned integer literal")


def reject_constant(text: str) -> float:
    raise LiteralError(f"constant {text!r} is not a number")


def load_json(path: Path) -> object:
    if not path.is_file():
        raise ValueError(f"{path} is not a regular file")
    raw = path.read_bytes()
    if len(raw) > 1024 * 1024:
        raise ValueError(f"{path} exceeds 1 MiB")
    text = raw.decode("utf-8")
    return json.loads(
        text, parse_int=reject_int, parse_float=reject_float, parse_constant=reject_constant
    )


def check_interface_name(value: object, where: str, problems: list[str]) -> None:
    if not isinstance(value, str) or value == "":
        problems.append(f"{where}: interface name must be a non-empty string")
        return
    if "\x00" in value:
        problems.append(f"{where}: interface name must not contain NUL")
        return
    if len(value.encode("utf-8")) > 15:
        problems.append(f"{where}: interface name exceeds the kernel limit of 15 UTF-8 bytes")


def integer_field(value: object, name: str, where: str, problems: list[str]) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        problems.append(f"{where}.{name}: expected an integer")
        return None
    low, high = INTEGER_RANGES[name]
    if not low <= value <= high:
        problems.append(f"{where}.{name}: {value} is outside [{low}, {high}]")
        return None
    return value


def parse_ip(value: object, where: str, problems: list[str]) -> ipaddress._BaseAddress | None:
    if not isinstance(value, str):
        problems.append(f"{where}: expected an IP address string")
        return None
    try:
        return ipaddress.ip_address(value)
    except ValueError as error:
        problems.append(f"{where}: {error}")
        return None


def normalize_desired(raw: object, where: str, problems: list[str]) -> dict:
    """Validate the documented input subset and apply the documented defaults."""
    result: dict = {"links": [], "addresses": [], "routes": []}
    if not isinstance(raw, dict):
        problems.append(f"{where}: expected an object")
        return result
    for key in raw:
        if key not in ("schema_version", "links", "addresses", "routes"):
            problems.append(f"{where}: unknown field {key!r}")
    if raw.get("schema_version") != 1:
        problems.append(f"{where}.schema_version: required version 1")

    for kind, keys in (("links", LINK_KEYS), ("addresses", ADDRESS_KEYS), ("routes", ROUTE_KEYS)):
        entries = raw.get(kind, [])
        if kind in raw and not isinstance(entries, list):
            problems.append(f"{where}.{kind}: expected an array")
            continue
        if len(entries) > 1024:
            problems.append(f"{where}.{kind}: more than 1024 resources")
        for index, entry in enumerate(entries):
            spot = f"{where}.{kind}[{index}]"
            if not isinstance(entry, dict):
                problems.append(f"{spot}: expected an object")
                continue
            for key in entry:
                if key not in keys:
                    problems.append(f"{spot}: unknown field {key!r}")

            def string_field(name: str, required: bool = True) -> str | None:
                value = entry.get(name)
                if value is None and not required:
                    return None
                if not isinstance(value, str):
                    problems.append(f"{spot}.{name}: expected a string")
                    return None
                return value

            ensure = string_field("ensure")
            if ensure is not None and ensure not in ("present", "absent"):
                problems.append(f"{spot}.ensure: expected 'present' or 'absent'")

            if kind == "links":
                name = string_field("name")
                if name is not None:
                    check_interface_name(name, spot, problems)
                up = entry.get("up")
                if up is not None and not isinstance(up, bool):
                    problems.append(f"{spot}.up: expected a boolean")
                    up = None
                mtu = entry.get("mtu")
                if mtu is not None:
                    mtu = integer_field(mtu, "mtu", spot, problems)
                result["links"].append(
                    {"name": name, "ensure": ensure, "up": up, "mtu": mtu}
                )
                continue

            interface = string_field("interface")
            if interface is not None:
                check_interface_name(interface, spot, problems)
            prefix = entry.get("prefix_length")
            prefix = None if prefix is None else integer_field(prefix, "prefix_length", spot, problems)

            if kind == "addresses":
                address = parse_ip(entry.get("address"), f"{spot}.address", problems)
                if address is not None and prefix is not None and prefix > address.max_prefixlen:
                    problems.append(f"{spot}.prefix_length: {prefix} exceeds the family width")
                scope = entry.get("scope", 0)
                scope = integer_field(scope, "scope", spot, problems) if scope is not None else 0
                result["addresses"].append(
                    {
                        "interface": interface,
                        "ensure": ensure,
                        "address": address,
                        "prefix_length": prefix,
                        "scope": scope,
                    }
                )
                continue

            destination = parse_ip(entry.get("destination"), f"{spot}.destination", problems)
            if destination is not None and prefix is not None:
                if prefix > destination.max_prefixlen:
                    problems.append(f"{spot}.prefix_length: {prefix} exceeds the family width")
                else:
                    try:
                        ipaddress.ip_network(f"{destination}/{prefix}", strict=True)
                    except ValueError as error:
                        problems.append(f"{spot}.destination: {error}")
            gateway = entry.get("gateway")
            gateway = None if gateway is None else parse_ip(gateway, f"{spot}.gateway", problems)
            if gateway is not None and destination is not None:
                if gateway.version != destination.version:
                    problems.append(f"{spot}.gateway: family differs from the destination")
            table = entry.get("table", 254)
            table = integer_field(table, "table", spot, problems) if table is not None else 254
            priority = entry.get("priority", 0)
            priority = (
                integer_field(priority, "priority", spot, problems) if priority is not None else 0
            )
            if destination is not None and destination.version == 6 and priority == 0:
                priority = 1024
            protocol = entry.get("protocol", 4)
            protocol = (
                integer_field(protocol, "protocol", spot, problems) if protocol is not None else 4
            )
            if "scope" in entry:
                scope = integer_field(entry["scope"], "scope", spot, problems)
            elif destination is not None and destination.version == 4 and gateway is None:
                scope = 253
            else:
                scope = 0
            result["routes"].append(
                {
                    "interface": interface,
                    "ensure": ensure,
                    "destination": destination,
                    "prefix_length": prefix,
                    "gateway": gateway,
                    "table": table,
                    "priority": priority,
                    "protocol": protocol,
                    "scope": scope,
                }
            )
    return result


def link_identity(link: dict) -> str:
    parts = [f"link|{link['name']}"]
    if link["mtu"] is not None:
        parts.append(f"mtu={link['mtu']}")
    if link["up"] is not None:
        parts.append(f"up={'true' if link['up'] else 'false'}")
    return "|".join(parts)


def address_identity(address: dict) -> str:
    return f"address|{address['interface']}|{address['address']}/{address['prefix_length']}"


def route_identity(route: dict) -> str:
    gateway = "none" if route["gateway"] is None else str(route["gateway"])
    return (
        f"route|{route['interface']}|table={route['table']}"
        f"|{route['destination']}/{route['prefix_length']}"
        f"|gateway={gateway}|priority={route['priority']}"
    )


def desired_identities(desired: dict) -> list[str]:
    return (
        [link_identity(link) for link in desired["links"]]
        + [address_identity(address) for address in desired["addresses"]]
        + [route_identity(route) for route in desired["routes"]]
    )


def observed(initial: dict, name: str) -> dict | None:
    for link in initial["links"]:
        if link.get("name") == name:
            return link
    return None


def address_operation(operation: str, address: dict) -> dict:
    return {
        "operation": operation,
        "interface": address["interface"],
        "address": str(address["address"]),
        "prefix_length": address["prefix_length"],
        "scope": address["scope"],
    }


def route_operation(operation: str, route: dict) -> dict:
    return {
        "operation": operation,
        "interface": route["interface"],
        "destination": str(route["destination"]),
        "prefix_length": route["prefix_length"],
        "gateway": None if route["gateway"] is None else str(route["gateway"]),
        "table": route["table"],
        "priority": route["priority"],
        "protocol": route["protocol"],
        "scope": route["scope"],
    }


def route_slot(route: dict) -> tuple:
    return (
        str(route["destination"]),
        route["prefix_length"],
        route["table"],
        route["priority"],
    )


def duplicate_rejection(desired: dict) -> list[str]:
    reasons: list[str] = []
    names = [link["name"] for link in desired["links"]]
    if len(names) != len(set(names)):
        reasons.append("ConflictingIntent")
    identities = [address_identity(address) for address in desired["addresses"]]
    if len(identities) != len(set(identities)):
        reasons.append("ConflictingIntent")
    route_ids = [route_identity(route) for route in desired["routes"]]
    if len(route_ids) != len(set(route_ids)):
        reasons.append("ConflictingIntent")
    slots = [route_slot(route) for route in desired["routes"] if route["ensure"] == "present"]
    if len(slots) != len(set(slots)):
        reasons.append("ConflictingIntent")
    return reasons


def derive(desired: dict, initial: dict) -> dict:
    """Re-derive operations, rejections and protected resources independently."""
    operations: list[dict] = []
    reasons = duplicate_rejection(desired)
    if reasons:
        return {"operations": [], "rejections": reasons, "protected": []}

    def add(operation: dict) -> None:
        operations.append(operation)

    for link in desired["links"]:
        name = link["name"]
        if link["ensure"] == "absent":
            reasons.append("UnsupportedIntent")
            continue
        link_observed = observed(initial, name)
        if link_observed is None or not link_observed.get("exists"):
            reasons.append("MissingInterface")
            continue
        if link["mtu"] is not None and link["mtu"] != link_observed.get("mtu"):
            add({"operation": "set_mtu", "interface": name, "after": link["mtu"]})
        if link["up"] is not None and link["up"] != link_observed.get("up"):
            add({"operation": "set_link_up" if link["up"] else "set_link_down", "interface": name})

    for address in desired["addresses"]:
        if address["interface"] is None:
            continue
        if observed(initial, address["interface"]) is None:
            if address["ensure"] == "present":
                reasons.append("MissingInterface")
            continue
        matches = [
            present
            for present in initial["present_addresses"]
            if present["interface"] == address["interface"]
            and present["address"] == str(address["address"])
            and present["prefix_length"] == address["prefix_length"]
        ]
        if matches and any(present.get("scope", 0) != address["scope"] for present in matches):
            reasons.append("UnsupportedCurrentResource")
        exists = bool(matches)
        if address["ensure"] == "present" and not exists:
            add(address_operation("add_address", address))
        elif address["ensure"] == "absent" and exists:
            add(address_operation("delete_address", address))

    for route in desired["routes"]:
        if route["interface"] is None:
            continue
        if observed(initial, route["interface"]) is None:
            if route["ensure"] == "present":
                reasons.append("MissingInterface")
            continue
        matches = [
            present
            for present in initial["present_routes"]
            if present["interface"] == route["interface"]
            and present["destination"] == str(route["destination"])
            and present["prefix_length"] == route["prefix_length"]
            and present["table"] == route["table"]
            and (present["gateway"] or None) == (None if route["gateway"] is None else str(route["gateway"]))
            and present["priority"] == route["priority"]
        ]
        if matches and any(
            present.get("protocol", 4) != route["protocol"] or present.get("scope") != route["scope"]
            for present in matches
        ):
            reasons.append("UnsupportedCurrentResource")
        exists = bool(matches)
        if route["ensure"] == "present" and not exists:
            if any(
                present["destination"] == str(route["destination"])
                and present["prefix_length"] == route["prefix_length"]
                and present["table"] == route["table"]
                and present["priority"] == route["priority"]
                for present in initial["present_routes"]
            ):
                reasons.append("ConflictingIntent")
            add(route_operation("add_route", route))
        elif route["ensure"] == "absent" and exists:
            add(route_operation("delete_route", route))

    protected: list[dict] = []
    for operation in operations:
        name = operation["interface"]
        link_observed = observed(initial, name)
        loopback = name == "lo" or bool(link_observed and link_observed.get("loopback"))
        if loopback:
            protected.append({"kind": "link", "name": name})
        if operation["operation"] in ROUTE_OPERATIONS and operation["prefix_length"] == 0:
            protected.append(
                {
                    "kind": "route",
                    "interface": operation["interface"],
                    "destination": operation["destination"],
                    "prefix_length": operation["prefix_length"],
                    "gateway": operation["gateway"],
                    "table": operation["table"],
                    "priority": operation["priority"],
                }
            )
    if protected:
        reasons.append("ProtectedResource")
    return {"operations": operations, "rejections": reasons, "protected": protected}


def initially_satisfied(desired: dict, initial: dict, derivation: dict) -> list[str]:
    needed = {
        json.dumps(canonical_operation(operation), sort_keys=True)
        for operation in derivation["operations"]
    }
    satisfied: list[str] = []
    for link in desired["links"]:
        if link["ensure"] != "present":
            continue
        link_observed = observed(initial, link["name"])
        if link_observed is None or not link_observed.get("exists"):
            continue
        if (link["mtu"] is None or link["mtu"] == link_observed.get("mtu")) and (
            link["up"] is None or link["up"] == link_observed.get("up")
        ):
            satisfied.append(link_identity(link))
    for address in desired["addresses"]:
        operation = address_operation("add_address", address)
        if address["ensure"] == "present" and json.dumps(operation, sort_keys=True) not in needed:
            satisfied.append(address_identity(address))
    for route in desired["routes"]:
        operation = route_operation("add_route", route)
        if route["ensure"] == "present" and json.dumps(operation, sort_keys=True) not in needed:
            satisfied.append(route_identity(route))
    return satisfied


def canonical_operation(operation: dict) -> dict:
    fields = OPERATION_FIELDS.get(operation.get("operation"))
    if fields is None:
        return dict(operation)
    return {key: operation.get(key) for key in fields}


def compare_operations(declared: list[dict], derived: list[dict]) -> list[str]:
    problems: list[str] = []
    key = lambda item: json.dumps(canonical_operation(item), sort_keys=True)  # noqa: E731
    missing = sorted(key(item) for item in derived)
    declared_keys = sorted(key(item) for item in declared)
    if missing != declared_keys:
        for item in missing:
            if item not in declared_keys:
                problems.append(f"expected.operations: missing derived operation {item}")
        for item in declared_keys:
            if item not in missing:
                problems.append(f"expected.operations: undeclared operation {item}")
    ranks = [OPERATION_RANK.get(item.get("operation"), -1) for item in declared]
    if ranks != sorted(ranks):
        problems.append(f"expected.operations: operations are not in plan order {ranks}")
    for item in declared:
        kind = item.get("operation")
        if kind not in OPERATION_FIELDS:
            problems.append(f"expected.operations: unknown operation {kind!r}")
            continue
        documented = set(OPERATION_FIELDS[kind]) | {"fails_with_errno"}
        unexpected = sorted(set(item) - documented)
        missing_keys = sorted(set(OPERATION_FIELDS[kind]) - set(item))
        if unexpected:
            problems.append(f"expected.operations: {kind} has unexpected keys {unexpected}")
        if missing_keys:
            problems.append(f"expected.operations: {kind} is missing keys {missing_keys}")
    return problems


def check_case(path: Path, problems: list[str], summary: list[dict]) -> None:
    def fail(message: str) -> None:
        problems.append(f"{path.name}: {message}")

    try:
        case = load_json(path)
    except (ValueError, LiteralError) as error:
        fail(f"cannot load case: {error}")
        return
    if not isinstance(case, dict):
        fail("case must be an object")
        return
    for key in CASE_REQUIRED:
        if key not in case:
            fail(f"missing required key {key!r}")
            return
    if case["id"] != path.stem:
        fail(f"id {case['id']!r} does not match the file name")
    if case["kind"] not in ("apply", "reject"):
        fail(f"kind must be 'apply' or 'reject', not {case['kind']!r}")
        return
    for key in ("title_en", "title_zh", "intent_en", "intent_zh"):
        value = case.get(key)
        if not isinstance(value, str) or not value.strip():
            fail(f"{key} must be a non-empty string")

    initial = case["initial"]
    if not isinstance(initial, dict):
        fail("initial must be an object")
        return
    for key in INITIAL_REQUIRED:
        if key not in initial:
            fail(f"initial is missing {key!r}")
            return
    if not isinstance(initial["links"], list) or not initial["links"]:
        fail("initial.links must be a non-empty array")
        return
    for link in initial["links"]:
        if not isinstance(link, dict) or "name" not in link or "exists" not in link:
            fail("initial.links entries need name and exists")
            return
    for key in ("present_addresses", "present_routes", "unmanaged"):
        if not isinstance(initial[key], list):
            fail(f"initial.{key} must be an array")
            return
    for entry in initial["unmanaged"]:
        if not isinstance(entry, dict) or not entry.get("identity") or not entry.get("command"):
            fail("initial.unmanaged entries need a non-empty identity and command")
            return
    for entry in initial["present_routes"]:
        if not isinstance(entry, dict) or "protocol" not in entry or "scope" not in entry:
            fail(
                "initial.present_routes entries need protocol and scope so that "
                "satisfaction of a declared route stays provable"
            )
            return
    if (initial["present_addresses"] or initial["present_routes"]) and not initial.get("fixture"):
        fail("a case with pre-existing resources must declare its fixture commands")

    expected = case["expected"]
    if not isinstance(expected, dict):
        fail("expected must be an object")
        return
    for key in EXPECTED_REQUIRED:
        if key not in expected:
            fail(f"expected is missing {key!r}")
            return
    final = case["final"]
    if not isinstance(final, dict):
        fail("final must be an object")
        return
    for key in ("satisfied", "preserved"):
        if not isinstance(final.get(key), list):
            fail(f"final.{key} must be an array")
            return

    desired_path = (path.parent / str(case["desired"])).resolve()
    try:
        raw_desired = load_json(desired_path)
    except (ValueError, LiteralError) as error:
        fail(f"cannot load {case['desired']}: {error}")
        return
    desired_problems: list[str] = []
    desired = normalize_desired(raw_desired, case["desired"], desired_problems)

    derivation = derive(desired, initial)
    unmanaged = [entry["identity"] for entry in initial["unmanaged"]]
    declared_operations = expected["operations"]
    if not isinstance(declared_operations, list):
        fail("expected.operations must be an array")
        return
    if expected["plan_steps"] != len(declared_operations):
        fail("expected.plan_steps differs from the declared operation count")

    if case["kind"] == "apply":
        if desired_problems:
            for problem in desired_problems:
                fail(f"{case['desired']}: {problem}")
        if expected["rejection"] is not None:
            fail("an apply case must not declare a rejection")
        if expected["protected_resource"] is not None:
            fail("an apply case must not declare a protected resource")
        for problem in compare_operations(declared_operations, derivation["operations"]):
            fail(problem)
        if derivation["rejections"]:
            fail(f"apply case derives rejection(s) {sorted(set(derivation['rejections']))}")
        failed = expected["failed"]
        annotated = [
            index
            for index, operation in enumerate(declared_operations)
            if "fails_with_errno" in operation
        ]
        if failed is None and annotated:
            fail("only a failing case may annotate an operation with fails_with_errno")
        if failed is None:
            if expected["exit_status"] != 0:
                fail("a successful case must exit zero")
            if expected["completed"] != list(range(len(declared_operations))):
                fail("completed must cover every operation")
            if expected["not_executed"] != []:
                fail("a successful case must not skip operations")
            if expected["compensation_attempts"] != 0:
                fail("a successful case must not compensate")
            if expected["kernel_write_attempts"] != len(declared_operations):
                fail("every operation must be attempted exactly once")
            if expected["verification_satisfied"] is not True:
                fail("a successful case must satisfy the final verification")
            if final["remaining_steps"] != 0:
                fail("a successful case must leave zero remaining steps")
            if sorted(final["satisfied"]) != sorted(desired_identities(desired)):
                fail("final.satisfied must list every declared present resource")
        else:
            if not isinstance(failed, dict) or "index" not in failed or "errno" not in failed:
                fail("expected.failed needs index, errno and outcome_unknown")
                return
            index = failed["index"]
            if not 0 <= index < len(declared_operations):
                fail("expected.failed.index is outside the plan")
                return
            if expected["exit_status"] != "nonzero":
                fail("a failed case must exit nonzero")
            if expected["completed"] != list(range(index)):
                fail("completed must list exactly the acknowledged operations before the failure")
            if expected["not_executed"] != list(range(index + 1, len(declared_operations))):
                fail("not_executed must list exactly the operations after the failure")
            if expected["kernel_write_attempts"] != index + 1:
                fail("kernel_write_attempts must count the acknowledged operations plus the failure")
            if expected["compensation_attempts"] != index:
                fail("compensation must cover every acknowledged operation")
            if expected["verification_satisfied"] is not False:
                fail("a failed case must not satisfy the final verification")
            if final["remaining_steps"] != len(declared_operations):
                fail("compensation must restore the initial state, leaving the whole plan")
            if sorted(final["satisfied"]) != sorted(initially_satisfied(desired, initial, derivation)):
                fail("final.satisfied must equal the resources already satisfied before the run")
            operation = declared_operations[index]
            if annotated != [index]:
                fail("only the failing operation may carry fails_with_errno")
            if operation.get("fails_with_errno") != failed["errno"]:
                fail("the failing operation must carry the same errno as expected.failed")
            if failed.get("outcome_unknown") is not False:
                fail("a reported kernel errno is a determinate outcome")
    else:
        if desired_problems and expected["rejection"] != "InvalidField" and not derivation["rejections"]:
            for problem in desired_problems:
                fail(f"{case['desired']}: {problem}")
        if expected["rejection"] not in REJECTION_REASONS:
            fail(f"expected.rejection must be one of {REJECTION_REASONS}")
        elif expected["rejection"] not in derivation["rejections"]:
            fail(
                f"expected.rejection {expected['rejection']!r} is not derivable; "
                f"derived {sorted(set(derivation['rejections']))}"
            )
        if expected["plan_steps"] != 0 or declared_operations != []:
            fail("a rejected case must declare no plan")
        if expected["kernel_write_attempts"] != 0 or expected["compensation_attempts"] != 0:
            fail("a rejected case must not write or compensate")
        if expected["exit_status"] != "nonzero":
            fail("a rejected case must exit nonzero")
        if expected["completed"] != [] or expected["not_executed"] != []:
            fail("a rejected case has no executed operations")
        if expected["failed"] is not None:
            fail("a rejected case has no failed operation")
        if expected["verification_satisfied"] is not False:
            fail("a rejected case cannot verify a target")
        if expected["rejection"] == "ProtectedResource":
            resource = expected["protected_resource"]
            if resource not in derivation["protected"]:
                fail(f"protected resource {resource!r} is not derived as protected")
        elif expected["protected_resource"] is not None:
            fail("only a ProtectedResource rejection may declare a protected resource")
        if final.get("state_unchanged") is not True:
            fail("a rejected case must assert that the observed state is unchanged")
        if final["remaining_steps"] is not None:
            fail("a rejected case has no remaining plan")
        if final["satisfied"] != []:
            fail("a rejected case satisfies nothing")
        if expected["rejection"] == "ProtectedResource" and not derivation["protected"]:
            fail("ProtectedResource was declared but no protected operation was derived")

    if sorted(final["preserved"]) != sorted(unmanaged):
        fail("final.preserved must list exactly the declared unmanaged resources")

    summary.append(
        {
            "id": case["id"],
            "kind": case["kind"],
            "plan_steps": expected["plan_steps"],
            "kernel_write_attempts": expected["kernel_write_attempts"],
            "compensation_attempts": expected["compensation_attempts"],
            "exit_status": expected["exit_status"],
            "rejection": expected["rejection"],
            "status": "ok",
        }
    )


def check_contract(problems: list[str]) -> tuple[dict, list[dict]]:
    try:
        contract = load_json(CONTRACT_PATH)
    except (ValueError, LiteralError) as error:
        problems.append(f"contract.json: {error}")
        return {}, []
    if not isinstance(contract, dict):
        problems.append("contract.json: expected an object")
        return {}, []

    def require(path: str, predicate, message: str) -> None:
        node: object = contract
        for part in path.split("."):
            if not isinstance(node, dict) or part not in node:
                problems.append(f"contract.json: missing {path}")
                return
            node = node[part]
        if not predicate(node):
            problems.append(f"contract.json: {message}")

    require("contract_version", lambda value: value == 1, "contract_version must be 1")
    require("purpose_en", lambda value: isinstance(value, str) and value.strip() != "", "purpose_en is empty")
    require("purpose_zh", lambda value: isinstance(value, str) and value.strip() != "", "purpose_zh is empty")
    require(
        "topology.managed_interface",
        lambda value: isinstance(value, str) and value != "",
        "managed_interface is empty",
    )
    require("topology.seed_commands", lambda value: isinstance(value, list) and value, "seed_commands is empty")
    require("input_scope.root_keys", lambda value: isinstance(value, list) and value, "root_keys is empty")
    require("input_scope.resource_keys", lambda value: isinstance(value, dict) and len(value) == 3, "resource_keys must cover link/address/route")
    require("input_scope.integer_fields", lambda value: isinstance(value, dict) and value, "integer_fields is empty")
    require("input_scope.defaults", lambda value: isinstance(value, dict) and value, "defaults is empty")
    require(
        "input_scope.rejected_before_write",
        lambda value: isinstance(value, list) and value,
        "rejected_before_write is empty",
    )
    require("comparison.observations", lambda value: isinstance(value, list) and value, "observations is empty")
    require("comparison.participating", lambda value: isinstance(value, list) and value, "participating is empty")
    require("comparison.excluded", lambda value: isinstance(value, list) and value, "excluded is empty")
    require("cases", lambda value: isinstance(value, list) and value, "cases is empty")

    for section in ("observations", "participating", "excluded"):
        for entry in contract.get("comparison", {}).get(section, []) or []:
            if not isinstance(entry, dict):
                problems.append(f"contract.json: comparison.{section} entries must be objects")
                continue
            if section == "excluded":
                for key in ("reason_en", "reason_zh"):
                    if not str(entry.get(key, "")).strip():
                        problems.append(
                            f"contract.json: comparison.excluded {entry.get('field')!r} needs {key}"
                        )
    declared = contract.get("cases", [])
    if isinstance(declared, list):
        names = [str(item) for item in declared]
        if len(names) != len(set(names)):
            problems.append("contract.json: duplicate case paths")
        on_disk = sorted(
            item.name for item in HERE.joinpath("cases").glob("*.json")
        )
        listed = sorted(Path(name).name for name in names)
        if on_disk != listed:
            problems.append(
                f"contract.json: case files on disk {on_disk} differ from the declared list {listed}"
            )
    return contract, [HERE / str(name) for name in contract.get("cases", [])]


def main(argv: list[str]) -> int:
    as_json = "--json" in argv[1:]
    problems: list[str] = []
    contract, case_paths = check_contract(problems)
    summary: list[dict] = []
    for path in case_paths:
        check_case(path, problems, summary)

    report = {
        "contract_version": contract.get("contract_version"),
        "cases": summary,
        "problems": problems,
        "status": "failed" if problems else "ok",
    }
    if as_json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        for entry in summary:
            print(
                f"{entry['id']:<24} {entry['kind']:<7} steps={entry['plan_steps']} "
                f"writes={entry['kernel_write_attempts']} "
                f"compensation={entry['compensation_attempts']} "
                f"exit={entry['exit_status']} "
                f"rejection={entry['rejection'] or '-'}"
            )
        if problems:
            print("\ncontract violations:", file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
            print(f"\ncomparison contract: {len(problems)} violation(s)", file=sys.stderr)
        else:
            print(
                f"\ncomparison contract: {len(summary)} case(s) consistent with "
                "the declared initial state and target"
            )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
