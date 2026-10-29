#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in moon ip unshare python3; do command -v "$tool" >/dev/null; done
moon build --target native --release cmd/moonnet
export MOONNETLINK_BENCH_PARENT_NETNS=$(readlink /proc/self/ns/net)
unshare -Urn -- python3 .ci/benchmark_queries.py "$@"
