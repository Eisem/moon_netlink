#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

for tool in unshare ip moon python3; do
  command -v "$tool" >/dev/null
done

# The namespace disappears when its last process exits, including on failure.
# All topology setup stays inside this new user/network namespace.
unshare -Urn -- bash -s <<'NAMESPACE'
set -euo pipefail
ip link set lo up
ip link add reviewtun type ipip local 192.0.2.1 remote 192.0.2.2
ip link add reviewveth type veth peer name reviewpeer
ip link set reviewveth up
ip address add 192.0.2.10/24 dev reviewveth

moon test --target native transport --filter 'live*'

python3 - <<'PY'
import json
import subprocess


def query(kind):
    result = subprocess.run(
        ["moon", "run", "--target", "native", "cmd/moonnet", "--", kind, "show", "--json"],
        check=True, text=True, capture_output=True, timeout=30,
    )
    return json.loads(result.stdout)


links = query("link")
by_name = {row["name"]: row for row in links}
assert by_name["reviewtun"]["kind"] == "ipip"
assert by_name["reviewtun"]["mac"] is None
assert by_name["reviewveth"]["mac"] is not None
assert [row["index"] for row in links] == sorted(row["index"] for row in links)

addresses = query("address")
assert any(
    row["interface_name"] == "reviewveth" and row["local_address"] == "192.0.2.10"
    for row in addresses
)
routes = query("route")
assert any(row["output_interface"] == by_name["reviewveth"]["index"] for row in routes)
neighbors = query("neighbor")
assert isinstance(neighbors, list)
print("isolated IPIP/veth Link, Address, Route and Neighbor queries: ok")
PY

python3 .ci/diff_ip_json.py
NAMESPACE
