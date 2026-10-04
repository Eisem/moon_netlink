#!/usr/bin/env python3
"""Compare MoonNetlink's stable JSON with iproute2's JSON on Linux."""

from __future__ import annotations

import ipaddress
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_json(command: list[str]) -> list[dict]:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    value = json.loads(completed.stdout)
    if not isinstance(value, list):
        raise RuntimeError(f"expected a JSON array from {' '.join(command)}")
    return value


def moon(kind: str) -> list[dict]:
    return run_json(
        ["moon", "run", "--target", "native", "cmd/moonnet", "--", kind, "show", "--json"]
    )


def fail(kind: str, missing: set[tuple], extra: set[tuple]) -> None:
    print(f"{kind}: mismatch", file=sys.stderr)
    if missing:
        print("  missing from moonnet:", file=sys.stderr)
        for item in sorted(missing, key=repr):
            print(f"    {item!r}", file=sys.stderr)
    if extra:
        print("  missing from ip -j:", file=sys.stderr)
        for item in sorted(extra, key=repr):
            print(f"    {item!r}", file=sys.stderr)
    raise SystemExit(1)


def operstate(value: str) -> str:
    lowered = value.lower()
    return {"notpresent": "not-present", "lowerlayerdown": "lower-layer-down"}.get(
        lowered, lowered
    )


def compare_links(moon_links: list[dict], ip_links: list[dict]) -> dict[str, int]:
    moon_rows = {
        (row["index"], row["name"], row["mtu"], row["mac"], row["operstate"])
        for row in moon_links
    }
    ip_rows = {
        (
            row["ifindex"],
            row["ifname"],
            row.get("mtu"),
            row.get("address") if row.get("link_type") in ("ether", "loopback") else None,
            operstate(row.get("operstate", "-")),
        )
        for row in ip_links
    }
    if moon_rows != ip_rows:
        fail("link", ip_rows - moon_rows, moon_rows - ip_rows)
    return {"moonnet": len(moon_rows), "ip": len(ip_rows)}


SCOPE = {"global": 0, "link": 253, "host": 254, "nowhere": 255}


def compare_addresses(moon_rows: list[dict], ip_links: list[dict]) -> dict[str, int]:
    moon_values = {
        (
            row["interface_index"],
            row["interface_name"],
            row["family"],
            row["local_address"] or row["address"],
            row["prefix_length"],
            row["scope"],
        )
        for row in moon_rows
    }
    ip_values = set()
    for link in ip_links:
        for row in link.get("addr_info", []):
            family = {"inet": "ipv4", "inet6": "ipv6"}.get(row.get("family"))
            if family is None:
                continue
            ip_values.add(
                (
                    link["ifindex"],
                    link["ifname"],
                    family,
                    row["local"],
                    row["prefixlen"],
                    SCOPE[row["scope"]],
                )
            )
    if moon_values != ip_values:
        fail("address", ip_values - moon_values, moon_values - ip_values)
    return {"moonnet": len(moon_values), "ip": len(ip_values)}


TABLE = {"default": 253, "main": 254, "local": 255}


def prefix(value: str | None, family: str) -> tuple[str | None, int]:
    if value in (None, "default"):
        return None, 0
    network = ipaddress.ip_network(value, strict=False)
    expected = 4 if family == "ipv4" else 6
    if network.version != expected:
        raise RuntimeError(f"unexpected {family} prefix: {value}")
    return str(network.network_address), network.prefixlen


def table_number(value: object) -> int:
    if value is None:
        return 254
    if isinstance(value, int):
        return value
    return TABLE.get(str(value), int(value) if str(value).isdigit() else -1)


def compare_routes(
    moon_rows: list[dict], ip4_rows: list[dict], ip6_rows: list[dict]
) -> dict[str, int]:
    links = {row["name"]: row["index"] for row in moon("link")}
    moon_values = {
        (
            row["family"],
            row["destination"],
            row["destination_prefix_length"],
            row["gateway"],
            row["output_interface"],
            row["table"],
            row["priority"],
        )
        for row in moon_rows
    }
    ip_values = set()
    for family, rows in (("ipv4", ip4_rows), ("ipv6", ip6_rows)):
        for row in rows:
            destination, length = prefix(row.get("dst"), family)
            ip_values.add(
                (
                    family,
                    destination,
                    length,
                    row.get("gateway"),
                    links.get(row.get("dev")),
                    table_number(row.get("table")),
                    row.get("metric"),
                )
            )
    # iproute2 suppresses some kernel-only route records. Every row that it
    # does report must agree with MoonNetlink on the shared core fields.
    missing = ip_values - moon_values
    if missing:
        fail("route", missing, set())
    return {"moonnet": len(moon_values), "ip": len(ip_values)}


def compare_neighbors(moon_rows: list[dict], ip_rows: list[dict]) -> dict[str, int]:
    links = {row["name"]: row["index"] for row in moon("link")}
    moon_values = {
        (
            row["destination"],
            row["interface_index"],
            row["link_layer_address"],
            row["state"],
        )
        for row in moon_rows
        if row["destination"] is not None
    }
    ip_values = set()
    for row in ip_rows:
        state = row.get("state", "none")
        if isinstance(state, list):
            state = state[0] if len(state) == 1 else "other"
        ip_values.add(
            (
                row["dst"],
                links[row["dev"]],
                row.get("lladdr"),
                str(state).lower(),
            )
        )
    missing = ip_values - moon_values
    if missing:
        fail("neighbor", missing, set())
    return {"moonnet": len(moon_values), "ip": len(ip_values)}


def main() -> None:
    report = {
        "link": compare_links(moon("link"), run_json(["ip", "-j", "link", "show"])),
        "address": compare_addresses(
            moon("address"), run_json(["ip", "-j", "address", "show"])
        ),
        "route": compare_routes(
            moon("route"),
            run_json(["ip", "-j", "-4", "route", "show", "table", "all"]),
            run_json(["ip", "-j", "-6", "route", "show", "table", "all"]),
        ),
        "neighbor": compare_neighbors(
            moon("neighbor"), run_json(["ip", "-j", "neighbor", "show"])
        ),
    }
    print(json.dumps({"status": "ok", "objects": report}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
