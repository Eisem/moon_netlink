#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
for tool in unshare ip moon python3; do
  command -v "$tool" >/dev/null
done
export MOONNETLINK_TEST_PARENT_NETNS=$(readlink /proc/self/ns/net)

# User and network namespaces disappear with their last process on all exits.
# No host interface is visible to either MoonNetlink or the setup commands.
unshare -Urn -- bash -s <<'NAMESPACE'
set -euo pipefail
ip link set lo up
ip link add testveth type veth peer name testpeer
ip link set testpeer up
moon build --target native
python3 .ci/validate_mutations.py
NAMESPACE
