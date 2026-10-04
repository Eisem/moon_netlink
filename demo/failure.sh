#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in moon unshare ip python3; do command -v "$tool" >/dev/null; done
moon build --target native
export MOONNETLINK_DEMO_PARENT_NETNS=$(readlink /proc/self/ns/net)
unshare -Urn -- bash -s <<'NAMESPACE'
set -euo pipefail
test "$(readlink /proc/self/ns/net)" != "$MOONNETLINK_DEMO_PARENT_NETNS"
ip link set lo up
ip link add testveth type veth peer name testpeer
ip link set testpeer up
python3 demo/failure.py
NAMESPACE
echo 'Expected failures verified; disposable namespace released.'
