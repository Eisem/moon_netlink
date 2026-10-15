#!/usr/bin/env python3
"""JSON tool for the comparison script baseline (P5-V2).

The baseline keeps argument handling, sequencing and command execution in Bash
and delegates JSON to this tool, as `docs/comparison.md` declares. The tool owns

* strict validation of the shared configuration subset (its own implementation,
  independent of `demo/compare/check_contract.py` and of the MoonBit SDK),
* the read-only plan and rejection decision,
* the exact `ip` argv of every step, so Bash never builds arguments itself,
* the structured execution report and the independent `ip -j` comparison.

It never invokes MoonNetlink and never parses human-readable `ip` output.

Subcommands
    plan <config.json> [--dangerous]     validated plan document (JSON)
    commands <plan.json>                 the ip argv of every step, tab separated
    report --config C --plan P --state S structured execution report (JSON)
    verify <config.json>                 satisfaction of every declared resource
    observe                              the normalized observation used above
    format <document.json>               human-readable plan, report or verification
    succeeded <document.json>            exit 0 only when the document succeeded
"""

from __future__ import annotations

import ipaddress
import json
import re
import subprocess
import sys
from pathlib import Path

MAX_CONFIG_BYTES = 1024 * 1024
MAX_RESOURCES = 1024
MAX_NESTING = 64
SCOPE_NAMES = {0: "global", 200: "site", 253: "link", 254: "host", 255: "nowhere"}
SCOPE_BY_OBSERVED = {
    "global": 0,
    "universe": 0,
    "site": 200,
    "link": 253,
    "host": 254,
    "nowhere": 255,
}
# Route protocols from the Linux UAPI; iproute2 reports their names.
PROTOCOL_BY_OBSERVED = {
    "unspec": 0,
    "redirect": 1,
    "kernel": 2,
    "boot": 3,
    "static": 4,
    "gated": 8,
    "ra": 9,
    "mrt": 10,
    "zebra": 11,
    "bird": 12,
    "dnroute": 13,
    "xorp": 14,
    "ntk": 15,
    "dhcp": 16,
    "mrouted": 17,
    "keepalived": 18,
    "babel": 42,
    "bgp": 186,
    "isis": 187,
    "ospf": 188,
    "rip": 189,
    "eigrp": 192,
}
RANK = {
    "delete_route": 0,
    "delete_address": 1,
    "set_mtu": 2,
    "set_link_up": 3,
    "add_address": 4,
    "add_route": 5,
    "set_link_down": 6,
}
REASON = {
    "set_mtu": "declared MTU differs from the observed value",
    "set_link_up": "declared administrative state differs from the observed value",
    "set_link_down": "declared administrative state differs from the observed value",
    "add_address": "declared address is absent",
    "delete_address": "declared absent address is present",
    "add_route": "declared route is absent",
    "delete_route": "declared absent route is present",
}

LINK_KEYS = ("name", "ensure", "up", "mtu")
ADDRESS_KEYS = ("interface", "ensure", "address", "prefix_length", "scope")
ROUTE_KEYS = (
    "interface", "ensure", "destination", "prefix_length", "gateway", "table",
    "priority", "protocol", "scope",
)


class Rejected(Exception):
    """Configuration rejected before any mutation, per the shared contract."""

    def __init__(self, reason: str, detail: str, path: str = "") -> None:
        super().__init__(detail)
        self.reason = reason
        self.detail = detail
        self.path = path

    def document(self) -> dict:
        return {
            "status": "rejected",
            "reason": self.reason,
            "detail": self.detail,
            "path": self.path,
            "attempted_writes": 0,
        }


class ToolError(Exception):
    """An external tool failed; the message keeps its diagnostics."""


class LiteralError(ValueError):
    """A JSON number that is not an unsigned decimal integer literal."""


def strict_int(text: str) -> int:
    if not re.fullmatch(r"[0-9]+", text):
        raise LiteralError(f"number token {text!r} is not an unsigned integer literal")
    return int(text)


def strict_float(text: str) -> float:
    raise LiteralError(f"number token {text!r} is not an unsigned integer literal")


def strict_constant(text: str) -> float:
    raise LiteralError(f"constant {text!r} is not a number")


def read_config(path: str) -> dict:
    target = Path(path)
    if not target.is_file():
        raise Rejected("InvalidField", "configuration must be a regular file", "root")
    raw = target.read_bytes()
    if len(raw) > MAX_CONFIG_BYTES:
        raise Rejected("InvalidField", "configuration exceeds 1 MiB", "root")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise Rejected("InvalidField", f"configuration is not UTF-8: {error}", "root")
    try:
        parsed = json.loads(
            text, parse_int=strict_int, parse_float=strict_float, parse_constant=strict_constant
        )
    except LiteralError as error:
        raise Rejected("InvalidField", str(error), "root")
    except ValueError as error:
        raise Rejected("InvalidField", f"invalid JSON: {error}", "root")
    if not isinstance(parsed, dict):
        raise Rejected("InvalidField", "expected an object", "root")
    return parsed


def interface_name(value: object, path: str) -> str:
    if not isinstance(value, str) or value == "":
        raise Rejected("InvalidField", "expected a non-empty interface name", path)
    if "\x00" in value or any(character.isspace() for character in value) or "/" in value:
        raise Rejected("invalid interface name", "name contains NUL, whitespace or '/'", path)
    if len(value.encode("utf-8")) > 15:
        raise Rejected("invalid interface name", "name exceeds 15 UTF-8 bytes", path)
    return value


def integer(value: object, low: int, high: int, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise Rejected("InvalidField", "expected an integer", path)
    if not low <= value <= high:
        raise Rejected("InvalidField", f"value {value} is outside [{low}, {high}]", path)
    return value


def boolean(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise Rejected("InvalidField", "expected a boolean", path)
    return value


def parse_address(value: object, path: str):
    if not isinstance(value, str):
        raise Rejected("InvalidField", "expected an IP address string", path)
    try:
        return ipaddress.ip_address(value)
    except ValueError as error:
        raise Rejected("InvalidField", str(error), path)


def only_keys(entry: dict, allowed: tuple, path: str) -> None:
    for key in entry:
        if key not in allowed:
            raise Rejected("InvalidField", f"unknown field {key!r}", f"{path}.{key}")


def ensure_intent(entry: dict, path: str) -> str:
    value = entry.get("ensure")
    if value not in ("present", "absent"):
        raise Rejected("InvalidField", "expected present or absent", f"{path}.ensure")
    return value


def validate(parsed: dict) -> dict:
    """Return normalized resources with the contract's documented defaults."""
    if "schema_version" not in parsed or parsed.get("schema_version") != 1:
        raise Rejected("InvalidField", "required schema_version 1", "schema_version")
    only_keys(parsed, ("schema_version", "links", "addresses", "routes"), "root")
    result = {"links": [], "addresses": [], "routes": []}
    for kind, keys, prefix_limit in (
        ("links", LINK_KEYS, None),
        ("addresses", ADDRESS_KEYS, 128),
        ("routes", ROUTE_KEYS, 128),
    ):
        entries = parsed.get(kind, [])
        if not isinstance(entries, list):
            raise Rejected("InvalidField", "expected an array", kind)
        if len(entries) > MAX_RESOURCES:
            raise Rejected("InvalidField", f"more than {MAX_RESOURCES} resources", kind)
        for index, entry in enumerate(entries):
            path = f"{kind}[{index}]"
            if not isinstance(entry, dict):
                raise Rejected("InvalidField", "expected an object", path)
            only_keys(entry, keys, path)
            ensure = ensure_intent(entry, path)
            if kind == "links":
                name = interface_name(entry.get("name"), f"{path}.name")
                up = None if "up" not in entry else boolean(entry["up"], f"{path}.up")
                mtu = (
                    None
                    if "mtu" not in entry
                    else integer(entry["mtu"], 1, 4294967295, f"{path}.mtu")
                )
                result["links"].append({"name": name, "ensure": ensure, "up": up, "mtu": mtu})
                continue

            interface = interface_name(entry.get("interface"), f"{path}.interface")
            if "prefix_length" not in entry:
                raise Rejected("InvalidField", "required integer", f"{path}.prefix_length")
            prefix = integer(entry["prefix_length"], 0, prefix_limit, f"{path}.prefix_length")

            if kind == "addresses":
                address = parse_address(entry.get("address"), f"{path}.address")
                if prefix > address.max_prefixlen:
                    raise Rejected(
                        "InvalidField", f"prefix {prefix} exceeds the family width", f"{path}.prefix_length"
                    )
                scope = 0 if "scope" not in entry else integer(
                    entry["scope"], 0, 255, f"{path}.scope"
                )
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

            destination = parse_address(entry.get("destination"), f"{path}.destination")
            if prefix > destination.max_prefixlen:
                raise Rejected(
                    "InvalidField", f"prefix {prefix} exceeds the family width", f"{path}.prefix_length"
                )
            try:
                ipaddress.ip_network(f"{destination}/{prefix}", strict=True)
            except ValueError as error:
                raise Rejected("InvalidField", str(error), f"{path}.destination")
            gateway = None
            if "gateway" in entry:
                gateway = parse_address(entry["gateway"], f"{path}.gateway")
                if gateway.version != destination.version:
                    raise Rejected("InvalidField", "gateway family differs", f"{path}.gateway")
            table = 254 if "table" not in entry else integer(
                entry["table"], 0, 4294967295, f"{path}.table"
            )
            priority = 0 if "priority" not in entry else integer(
                entry["priority"], 0, 4294967295, f"{path}.priority"
            )
            if destination.version == 6 and priority == 0:
                priority = 1024
            protocol = 4 if "protocol" not in entry else integer(
                entry["protocol"], 0, 255, f"{path}.protocol"
            )
            if "scope" in entry:
                scope = integer(entry["scope"], 0, 255, f"{path}.scope")
            elif destination.version == 4 and gateway is None:
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


def duplicate_check(desired: dict) -> None:
    names = [link["name"] for link in desired["links"]]
    if len(names) != len(set(names)):
        raise Rejected("ConflictingIntent", "duplicate link name", "links")
    identities = [address_identity(address) for address in desired["addresses"]]
    if len(identities) != len(set(identities)):
        raise Rejected("ConflictingIntent", "duplicate address identity", "addresses")
    route_ids = [route_identity(route) for route in desired["routes"]]
    if len(route_ids) != len(set(route_ids)):
        raise Rejected("ConflictingIntent", "duplicate route identity", "routes")
    slots = [
        (str(route["destination"]), route["prefix_length"], route["table"], route["priority"])
        for route in desired["routes"]
        if route["ensure"] == "present"
    ]
    if len(slots) != len(set(slots)):
        raise Rejected("ConflictingIntent", "two present routes share one slot", "routes")


def ip_json(*args: str):
    completed = subprocess.run(
        ["ip", "-j", *args], text=True, capture_output=True, timeout=30
    )
    if completed.returncode != 0:
        raise ToolError(f"ip -j {' '.join(args)} failed: {completed.stderr.strip()}")
    try:
        return json.loads(completed.stdout)
    except ValueError as error:
        raise ToolError(f"ip -j {' '.join(args)} returned invalid JSON: {error}")


def table_number(value: object) -> int:
    """`ip -j` reports the table as a name or a decimal string."""
    if value is None:
        return 254  # iproute2 omits the field for the main table
    if isinstance(value, int):
        return value
    text = str(value).lower()
    if text in ("main", "local", "default"):
        return {"main": 254, "local": 255, "default": 253}[text]
    return int(text) if text.isdigit() else -1


def protocol_number(value: object) -> int:
    """`ip -j` reports the route protocol as a name."""
    if isinstance(value, int):
        return value
    return PROTOCOL_BY_OBSERVED.get(str(value).lower(), -1)


def scope_number(value: object) -> int:
    """`ip -j` reports scope names, while the configuration uses numbers."""
    if value is None:
        return 0
    if isinstance(value, int):
        return value
    return SCOPE_BY_OBSERVED.get(str(value).lower(), 0)


def snapshot() -> dict:
    links = {}
    for row in ip_json("link", "show"):
        links[row["ifname"]] = {
            "index": row["ifindex"],
            "mtu": row.get("mtu"),
            "up": "UP" in row.get("flags", []),
            "loopback": row.get("link_type") == "loopback" or row["ifname"] == "lo",
        }
    addresses = []
    for row in ip_json("address", "show"):
        for info in row.get("addr_info", []):
            if info.get("family") not in ("inet", "inet6"):
                continue
            addresses.append(
                {
                    "interface": row["ifname"],
                    "address": info["local"],
                    "prefix_length": info["prefixlen"],
                    "scope": scope_number(info.get("scope")),
                    "family": info["family"],
                }
            )
    routes = []
    for family, flag in ((4, "-4"), (6, "-6")):
        for row in ip_json(flag, "route", "show", "table", "all"):
            destination = row.get("dst")
            if destination in (None, "default"):
                network, prefix = ipaddress.ip_address("0.0.0.0" if family == 4 else "::"), 0
            else:
                net = ipaddress.ip_network(destination, strict=False)
                network, prefix = net.network_address, net.prefixlen
            metric = row.get("metric")
            if metric is None:
                metric = 0 if family == 4 else 1024
            routes.append(
                {
                    "interface": row.get("dev"),
                    "destination": str(network),
                    "prefix_length": prefix,
                    "gateway": row.get("gateway"),
                    "table": table_number(row.get("table")),
                    "priority": metric,
                    "protocol": protocol_number(row.get("protocol")),
                    "scope": scope_number(row.get("scope")),
                    "family": family,
                }
            )
    return {"links": links, "addresses": addresses, "routes": routes}


def observed_link(state: dict, name: str) -> dict | None:
    return state["links"].get(name)


def address_operation(operation: str, address: dict) -> dict:
    return {
        "operation": operation,
        "interface": address["interface"],
        "interface_index": None,
        "address": str(address["address"]),
        "prefix_length": address["prefix_length"],
        "scope": address["scope"],
    }


def route_operation(operation: str, route: dict) -> dict:
    return {
        "operation": operation,
        "interface": route["interface"],
        "interface_index": None,
        "destination": str(route["destination"]),
        "prefix_length": route["prefix_length"],
        "gateway": None if route["gateway"] is None else str(route["gateway"]),
        "table": route["table"],
        "priority": route["priority"],
        "protocol": route["protocol"],
        "scope": route["scope"],
    }


def rejects(state: dict, desired: dict) -> None:
    """Every rejection happens here, before Bash executes anything."""
    for address in desired["addresses"]:
        if address["scope"] not in SCOPE_NAMES:
            raise Rejected(
                "UnsupportedIntent",
                f"ip(8) cannot express address scope {address['scope']}",
                "addresses",
            )
    for link in desired["links"]:
        if link["ensure"] == "absent":
            raise Rejected(
                "UnsupportedIntent",
                "absent Link requires link deletion, which the shared subset excludes",
                "links",
            )
        if observed_link(state, link["name"]) is None:
            raise Rejected("MissingInterface", f"interface {link['name']!r} does not exist", "links")
    for address in desired["addresses"]:
        if address["ensure"] == "present" and observed_link(state, address["interface"]) is None:
            raise Rejected(
                "MissingInterface", f"interface {address['interface']!r} does not exist", "addresses"
            )
        for current in state["addresses"]:
            if (
                current["interface"] == address["interface"]
                and current["address"] == str(address["address"])
                and current["prefix_length"] == address["prefix_length"]
                and current["scope"] != address["scope"]
            ):
                raise Rejected(
                    "UnsupportedCurrentResource",
                    "an existing address with this identity has a different scope",
                    "addresses",
                )
    for route in desired["routes"]:
        if route["ensure"] == "present" and observed_link(state, route["interface"]) is None:
            raise Rejected(
                "MissingInterface", f"interface {route['interface']!r} does not exist", "routes"
            )
        if route["scope"] not in SCOPE_NAMES:
            raise Rejected(
                "UnsupportedIntent", f"ip(8) cannot express route scope {route['scope']}", "routes"
            )
        for current in matching_routes(state, route):
            if current["protocol"] != route["protocol"] or current["scope"] != route["scope"]:
                raise Rejected(
                    "UnsupportedCurrentResource",
                    "an existing route with this identity has a different protocol or scope",
                    "routes",
                )


def matching_routes(state: dict, route: dict) -> list[dict]:
    return [
        current
        for current in state["routes"]
        if current["interface"] == route["interface"]
        and current["destination"] == str(route["destination"])
        and current["prefix_length"] == route["prefix_length"]
        and current["table"] == route["table"]
        and (current["gateway"] or None)
        == (None if route["gateway"] is None else str(route["gateway"]))
        and current["priority"] == route["priority"]
    ]


def order_key(change: dict):
    operation = change["operation"]
    if operation in ("add_address", "delete_address"):
        address = ipaddress.ip_address(change["address"])
        return (change["interface"], address.version, int(address))
    if operation in ("add_route", "delete_route"):
        return (
            change["interface"],
            ipaddress.ip_address(change["destination"]).version,
            int(ipaddress.ip_address(change["destination"])),
            change["prefix_length"],
            change["table"],
            change["priority"],
            change["gateway"] or "",
        )
    return (change["interface"],)


def plan(desired: dict, state: dict, dangerous: bool) -> dict:
    duplicate_check(desired)
    rejects(state, desired)
    changes: list[dict] = []
    for link in desired["links"]:
        current = observed_link(state, link["name"])
        index = current["index"]
        if link["mtu"] is not None and link["mtu"] != current["mtu"]:
            changes.append(
                {
                    "operation": "set_mtu",
                    "interface": link["name"],
                    "interface_index": index,
                    "before": current["mtu"],
                    "after": link["mtu"],
                }
            )
        if link["up"] is not None and link["up"] != current["up"]:
            changes.append(
                {
                    "operation": "set_link_up" if link["up"] else "set_link_down",
                    "interface": link["name"],
                    "interface_index": index,
                    "before": current["up"],
                    "after": link["up"],
                }
            )
    for address in desired["addresses"]:
        index = observed_link(state, address["interface"])["index"]
        present = any(
            current["interface"] == address["interface"]
            and current["address"] == str(address["address"])
            and current["prefix_length"] == address["prefix_length"]
            for current in state["addresses"]
        )
        if address["ensure"] == "present" and not present:
            operation = address_operation("add_address", address)
            operation["interface_index"] = index
            changes.append(operation)
        elif address["ensure"] == "absent" and present:
            operation = address_operation("delete_address", address)
            operation["interface_index"] = index
            changes.append(operation)
    for route in desired["routes"]:
        index = observed_link(state, route["interface"])["index"]
        present = bool(matching_routes(state, route))
        if route["ensure"] == "present" and not present:
            for current in state["routes"]:
                if (
                    current["destination"] == str(route["destination"])
                    and current["prefix_length"] == route["prefix_length"]
                    and current["table"] == route["table"]
                    and current["priority"] == route["priority"]
                ):
                    raise Rejected(
                        "ConflictingIntent",
                        "a route already occupies the declared destination, table and priority",
                        "routes",
                    )
            operation = route_operation("add_route", route)
            operation["interface_index"] = index
            changes.append(operation)
        elif route["ensure"] == "absent" and present:
            operation = route_operation("delete_route", route)
            operation["interface_index"] = index
            changes.append(operation)

    for change in changes:
        name = change["interface"]
        current = observed_link(state, name)
        change["_protected"] = bool(
            (current and current["loopback"])
            or (change["operation"] in ("add_route", "delete_route") and change["prefix_length"] == 0)
        )
    protected = [change for change in changes if change["_protected"]]
    if protected and not dangerous:
        first = protected[0]
        detail = (
            "loopback change"
            if observed_link(state, first["interface"])["loopback"]
            else "default-route change"
        )
        raise Rejected("ProtectedResource", f"{detail} requires --dangerous", first["interface"])
    changes.sort(key=lambda change: (RANK[change["operation"]], order_key(change)))
    return {
        "schema_version": 1,
        "steps": [
            {
                "change": {key: value for key, value in change.items() if key != "_protected"},
                "reason": REASON[change["operation"]],
                "dangerous": change["_protected"],
            }
            for change in changes
        ],
    }


def step_argv(change: dict) -> list[str]:
    operation = change["operation"]
    interface = change["interface"]
    if operation == "set_mtu":
        return ["ip", "link", "set", "dev", interface, "mtu", str(change["after"])]
    if operation == "set_link_up":
        return ["ip", "link", "set", "dev", interface, "up"]
    if operation == "set_link_down":
        return ["ip", "link", "set", "dev", interface, "down"]
    scope = SCOPE_NAMES.get(change.get("scope", 0))
    if operation in ("add_address", "delete_address"):
        verb = "add" if operation == "add_address" else "delete"
        argv = [
            "ip", "address", verb,
            f"{change['address']}/{change['prefix_length']}", "dev", interface,
        ]
        if scope is not None and scope != "global":
            argv += ["scope", scope]
        return argv
    family = "-6" if ":" in change["destination"] else "-4"
    verb = "add" if operation == "add_route" else "delete"
    argv = ["ip", family, "route", verb, f"{change['destination']}/{change['prefix_length']}"]
    if change["gateway"]:
        argv += ["via", change["gateway"]]
    argv += ["dev", interface, "table", str(change["table"])]
    if change["priority"] != 0:
        argv += ["metric", str(change["priority"])]
    argv += ["proto", "static"]
    if scope is not None:
        argv += ["scope", scope]
    return argv


def satisfied_identities(desired: dict, state: dict) -> tuple[list[str], int]:
    """Evaluate every declared resource against one observation."""
    satisfied: list[str] = []
    remaining = 0
    for link in desired["links"]:
        current = observed_link(state, link["name"])
        if current is None:
            remaining += 1
            continue
        if (link["mtu"] is None or link["mtu"] == current["mtu"]) and (
            link["up"] is None or link["up"] == current["up"]
        ):
            satisfied.append(link_identity(link))
        else:
            remaining += 1
    for address in desired["addresses"]:
        present = any(
            current["interface"] == address["interface"]
            and current["address"] == str(address["address"])
            and current["prefix_length"] == address["prefix_length"]
            for current in state["addresses"]
        )
        if present == (address["ensure"] == "present"):
            satisfied.append(address_identity(address))
        else:
            remaining += 1
    for route in desired["routes"]:
        present = bool(matching_routes(state, route))
        if present == (route["ensure"] == "present"):
            satisfied.append(route_identity(route))
        else:
            remaining += 1
    return satisfied, remaining


def read_state(path: str) -> dict:
    state = {"attempts": 0, "completed": [], "not_executed": [], "rollback": []}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        key, _, value = line.partition("=")
        if key in ("attempts", "failed_index", "failed_exit", "compensations"):
            state[key] = int(value)
        elif key in ("completed", "not_executed", "compensation", "compensated"):
            state[key] = [int(item) for item in value.split()] if value.strip() else []
        elif key == "rollback":
            state[key] = [
                {"index": int(token.partition(":")[0]), "status": token.partition(":")[2]}
                for token in value.split()
            ]
        else:
            state[key] = value
    return state


def build_report(config_path: str, plan_path: str, state_path: str) -> dict:
    desired = validate(read_config(config_path))
    steps = json.loads(Path(plan_path).read_text(encoding="utf-8"))["steps"]
    state = read_state(state_path)
    completed = state.get("completed", [])
    failed_index = state.get("failed_index")
    failed = None
    if failed_index is not None:
        # ip(8) collapses every kernel refusal into exit status 2, so no kernel
        # errno exists on this side; the kernel diagnostic text is preserved.
        failed = {
            "index": failed_index,
            "error": {
                "kind": "CommandFailed",
                "exit_status": state.get("failed_exit"),
                "message": state.get("failed_message", ""),
                "command": state.get("failed_command", ""),
            },
            "outcome_unknown": False,
        }
    observation = snapshot()
    satisfied, remaining = satisfied_identities(desired, observation)
    succeeded = failed is None and remaining == 0 and len(completed) == len(steps)
    return {
        "schema_version": 1,
        "dry_run": False,
        "plan": {"schema_version": 1, "steps": steps},
        "completed": completed,
        "failed": failed,
        "not_executed": state.get("not_executed", []),
        "rollback": state.get("rollback", []),
        "attempted_writes": state.get("attempts", 0),
        "compensations": state.get("compensations", 0),
        "verification": {
            "satisfied": remaining == 0,
            "remaining_steps": remaining,
            "satisfied_resources": satisfied,
            "observation": {key: observation[key] for key in ("links", "addresses", "routes")},
        },
        "succeeded": succeeded,
    }


def human_plan(document: dict) -> str:
    steps = document.get("steps", [])
    lines = [f"Dry-run: {len(steps)} operation(s); no changes applied"]
    for index, step in enumerate(steps):
        change = step["change"]
        details = " ".join(
            f"{key}={json.dumps(value)}"
            for key, value in change.items()
            if key not in ("operation", "interface", "interface_index")
        )
        marker = " [dangerous]" if step.get("dangerous") else ""
        lines.append(
            f"{index + 1}. {change['operation']} {change['interface']} {details}{marker}".rstrip()
        )
        lines.append(f"   {step.get('reason', '')}")
    return "\n".join(lines)


def human_report(document: dict) -> str:
    steps = len(document.get("plan", {}).get("steps", []))
    lines: list[str] = []
    failed = document.get("failed")
    if failed is None:
        lines.append(f"Applied {len(document.get('completed', []))} of {steps} operation(s)")
    else:
        error = failed.get("error", {})
        lines.append(f"Apply failed at operation {failed['index'] + 1}: {error.get('message', '')}")
        lines.append(f"   command: {error.get('command', '')}")
        lines.append(
            f"   completed: {document.get('completed', [])}; "
            f"not executed: {document.get('not_executed', [])}"
        )
    lines.append(
        f"Attempted writes: {document.get('attempted_writes', 0)}; "
        f"compensations: {document.get('compensations', 0)}"
    )
    verification = document.get("verification", {})
    if verification.get("satisfied"):
        lines.append("Verification: requested state satisfied by a fresh ip -j observation")
    else:
        lines.append(
            f"Verification: {verification.get('remaining_steps')} declared resource(s) still "
            "unsatisfied"
        )
    return "\n".join(lines)


def human_verification(document: dict) -> str:
    if document.get("satisfied"):
        return "Verification: requested state satisfied by a fresh ip -j observation"
    return (
        f"Verification: {document.get('remaining_steps')} declared resource(s) not satisfied"
    )


def format_document(document: dict) -> str:
    if "steps" in document:
        return human_plan(document)
    if "completed" in document:
        return human_report(document)
    if "satisfied" in document:
        return human_verification(document)
    raise ToolError("unrecognized document shape")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    command, rest = argv[1], argv[2:]
    try:
        if command == "plan":
            dangerous = "--dangerous" in rest
            paths = [item for item in rest if not item.startswith("--")]
            if len(paths) != 1:
                print("plan requires exactly one configuration path", file=sys.stderr)
                return 2
            desired = validate(read_config(paths[0]))
            # Parse-level rejections must not open a route socket.
            duplicate_check(desired)
            print(json.dumps(plan(desired, snapshot(), dangerous), indent=2))
            return 0
        if command == "commands":
            if len(rest) != 1:
                print("commands requires one plan path", file=sys.stderr)
                return 2
            steps = json.loads(Path(rest[0]).read_text(encoding="utf-8"))["steps"]
            for index, step in enumerate(steps):
                argv_line = "\t".join(step_argv(step["change"]))
                print(f"{index}\t{argv_line}")
            return 0
        if command == "report":
            options = dict(zip(rest[0::2], rest[1::2]))
            print(
                json.dumps(
                    build_report(options["--config"], options["--plan"], options["--state"]),
                    indent=2,
                )
            )
            return 0
        if command == "verify":
            if len(rest) != 1:
                print("verify requires one configuration path", file=sys.stderr)
                return 2
            desired = validate(read_config(rest[0]))
            observation = snapshot()
            satisfied, remaining = satisfied_identities(desired, observation)
            print(
                json.dumps(
                    {
                        "satisfied": remaining == 0,
                        "remaining_steps": remaining,
                        "satisfied_resources": satisfied,
                    },
                    indent=2,
                )
            )
            return 0
        if command == "observe":
            print(json.dumps(snapshot(), indent=2))
            return 0
        if command == "format":
            if len(rest) != 1:
                print("format requires one document path", file=sys.stderr)
                return 2
            document = json.loads(Path(rest[0]).read_text(encoding="utf-8"))
            print(format_document(document))
            return 0
        if command == "succeeded":
            if len(rest) != 1:
                print("succeeded requires one document path", file=sys.stderr)
                return 2
            document = json.loads(Path(rest[0]).read_text(encoding="utf-8"))
            result = document.get("succeeded", document.get("satisfied"))
            return 0 if result is True else 1
    except Rejected as rejection:
        print(json.dumps(rejection.document(), indent=2), file=sys.stderr)
        return 1
    except ToolError as error:
        print(f"compare-baseline: {error}", file=sys.stderr)
        return 3
    print(f"unknown subcommand {command!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
