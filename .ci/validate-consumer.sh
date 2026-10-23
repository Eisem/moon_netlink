#!/usr/bin/env bash
# This project lives outside the source checkout and resolves the registry version.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
consumer=$(mktemp -d)
trap 'rm -rf -- "$consumer"' EXIT
mkdir -p "$consumer/cmd/main"
cat > "$consumer/moon.mod" <<'MOD'
name = "moonnetlink-consumer/smoke"
version = "0.1.0"
preferred_target = "native"
import {
  "eisem/moonnetlink@0.1.0",
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
cd "$consumer"
moon update
moon check --target native
moon build --target native
moon run --target native cmd/main
