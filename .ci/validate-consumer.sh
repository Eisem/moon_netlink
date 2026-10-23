#!/usr/bin/env bash
# This project lives outside the source checkout and resolves the registry version.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
version=${MOONNETLINK_CONSUMER_VERSION:-0.1.1}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
consumer=$(mktemp -d)
trap 'rm -rf -- "$consumer"' EXIT
mkdir -p "$consumer/cmd/main"
mkdir -p "$consumer/cmd/app" "$consumer/cmd/monitor"
cat > "$consumer/moon.mod" <<MOD
name = "moonnetlink-consumer/smoke"
version = "0.1.0"
preferred_target = "native"
import {
  "eisem/moonnetlink@$version",
  "moonbitlang/async@0.22.1",
}
MOD
cat > "$consumer/cmd/main/moon.pkg" <<'PKG'
import {
  "eisem/moonnetlink/transport",
  "moonbitlang/async",
}
supported_targets = "native"
pkgtype(kind: "executable")
PKG
cp "$repo_root/examples/inspect_links/main.mbt" "$consumer/cmd/main/main.mbt"
cp "$repo_root/examples/network_config_app/"*.mbt "$consumer/cmd/app/"
cp "$repo_root/examples/network_config_app/moon.pkg" "$consumer/cmd/app/"
cp "$repo_root/.ci/consumer/monitor.mbt" "$consumer/cmd/monitor/main.mbt"
cat > "$consumer/cmd/monitor/moon.pkg" <<'PKG'
import {
  "eisem/moonnetlink/transport",
  "moonbitlang/async",
  "moonbitlang/async/stdio",
}
supported_targets = "native"
pkgtype(kind: "executable")
PKG
cd "$consumer"
moon update
moon check --target native
moon build --target native
moon run --target native cmd/main
export MOONNETLINK_TEST_PARENT_NETNS=$(readlink /proc/self/ns/net)
unshare -Urn -- python3 "$repo_root/.ci/consumer/accept.py" "$consumer"
