#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
git diff --exit-code
git diff --cached --exit-code
version=$(python3 -c 'import re; print(re.search(r"^version = \"([^\"]+)\"", open("moon.mod").read(), re.M)[1])')
if [[ -n ${GITHUB_REF_NAME:-} && ${GITHUB_REF_TYPE:-} == tag ]]; then
  test "$GITHUB_REF_NAME" = "v$version"
fi
output="$PWD/_build/release"
mkdir -p "$output"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
name="moonnetlink-$version-linux-x86_64"
mkdir -p "$stage/$name"
moon build --target native --release cmd/moonnet
cp _build/native/release/build/cmd/moonnet/moonnet.exe "$stage/$name/moonnet"
chmod +x "$stage/$name/moonnet"
cp LICENSE .ci/toolchain-lock.json "$stage/$name/"
mkdir -p "$stage/$name/licenses"
cp .mooncakes/moonbitlang/async/LICENSE "$stage/$name/licenses/async-LICENSE"
moon_home=$(cd "$(dirname "$(command -v moon)")/.." && pwd)
cp "$moon_home/lib/core/LICENSE" "$stage/$name/licenses/core-LICENSE"
cp "$moon_home/CREDITS.md" "$stage/$name/licenses/toolchain-CREDITS.md"
{
  echo "version=$version"
  echo "commit=$(git rev-parse HEAD)"
  echo "built_at_source_epoch=$(git log -1 --format=%ct)"
  uname -srmo
  moon version --all
  cc --version | head -1
  ldd --version | head -1
} > "$stage/$name/BUILD.txt"
ldd "$stage/$name/moonnet" > "$stage/$name/RUNTIME.txt"
"$stage/$name/moonnet" link show --json | python3 -c 'import json,sys; x=json.load(sys.stdin); assert any(r["name"] == "lo" for r in x)'
epoch=$(git log -1 --format=%ct)
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner -C "$stage" -cf - "$name" | gzip -n > "$output/$name.tar.gz"
git archive --format=tar --prefix="moonnetlink-$version/" HEAD | gzip -n > "$output/moonnetlink-$version-source.tar.gz"
cp "$stage/$name/BUILD.txt" "$output/BUILD.txt"
cp "$stage/$name/RUNTIME.txt" "$output/RUNTIME.txt"
cp .ci/toolchain-lock.json "$output/toolchain-lock.json"
(
  cd "$output"
  sha256sum "$name.tar.gz" "moonnetlink-$version-source.tar.gz" BUILD.txt RUNTIME.txt toolchain-lock.json > SHA256SUMS
  sha256sum --check SHA256SUMS
)
# Smoke-test the exact distributable after extraction, not just the build tree.
mkdir -p "$stage/verify"
tar -xzf "$output/$name.tar.gz" -C "$stage/verify"
"$stage/verify/$name/moonnet" link show --json | python3 -c 'import json,sys; assert isinstance(json.load(sys.stdin), list)'
