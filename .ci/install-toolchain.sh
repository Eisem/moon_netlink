#!/usr/bin/env bash
# Official archives are content-pinned: upstream changes fail verification.
set -euo pipefail
destination=${1:-"$HOME/.moon"}
download=$(mktemp -d)
trap 'rm -rf -- "$download"' EXIT
curl --retry 3 -fsSL https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz -o "$download/toolchain.tar.gz"
curl --retry 3 -fsSL https://cli.moonbitlang.com/cores/core-latest.tar.gz -o "$download/core.tar.gz"
(
  cd "$download"
  sha256sum --check <<'SHA'
e9a52300d137d43d122f26b78d307e08aaaaa644b9fad50ebfd709d7ae927cf6  toolchain.tar.gz
a83410b3e337edf275176291a4532604997f9180fd5ed7a5ba7cf521ff0898e0  core.tar.gz
SHA
)
mkdir -p "$destination/lib"
tar -xzf "$download/toolchain.tar.gz" -C "$destination"
tar -xzf "$download/core.tar.gz" -C "$destination/lib"
export PATH="$destination/bin:$PATH"
moon version
moon -C "$destination/lib/core" bundle --warn-list -a --all
