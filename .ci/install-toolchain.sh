#!/usr/bin/env bash
# Verified content-addressed cache also supports installation without network.
set -euo pipefail
destination=${1:-"$HOME/.moon"}
script_dir=$(cd "$(dirname "$0")" && pwd)
cache=${MOONNETLINK_TOOLCHAIN_CACHE:-"$HOME/.cache/moonnetlink-toolchain"}
archive_list=$(python3 "$script_dir/fetch_toolchain.py" "$cache")
mapfile -t archives <<< "$archive_list"
mkdir -p "$destination/lib"
tar -xzf "${archives[0]}" -C "$destination"
tar -xzf "${archives[1]}" -C "$destination/lib"
chmod +x "$destination"/bin/* "$destination/bin/internal/tcc"
export PATH="$destination/bin:$PATH"
moon version
moon -C "$destination/lib/core" bundle --warn-list -a --all
