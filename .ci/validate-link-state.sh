#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

command -v unshare >/dev/null
command -v ip >/dev/null
command -v moon >/dev/null

# -U maps the invoking user to root only inside a fresh user namespace; -n
# creates a fresh network namespace. No host interface can be reached here.
unshare -Urn -- bash -c '
  set -euo pipefail
  ip link set lo up
  moon run --target native examples/set_link_state -- 1 down
  if ip -j link show lo | python3 -c '\''import json,sys; raise SystemExit("UP" in json.load(sys.stdin)[0]["flags"])'\''; then
    :
  else
    echo "loopback remained UP after MoonNetlink DOWN" >&2
    exit 1
  fi
  moon run --target native examples/set_link_state -- 1 up
  ip -j link show lo | python3 -c '\''import json,sys; raise SystemExit(0 if "UP" in json.load(sys.stdin)[0]["flags"] else 1)'\''
'

echo "isolated Link DOWN/UP ACK round-trip: ok"
