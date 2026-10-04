#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if (( $# > 1 )); then
  echo 'Usage: bash demo/run.sh [all|container|reconcile|monitor|failure|invalid]' >&2
  exit 2
fi
scenario=${1:-all}
case "$scenario" in
  all)
    for name in container reconcile monitor failure; do
      echo "=== $name ==="
      bash "demo/$name.sh"
    done
    python3 -u demo/reject.py
    echo 'All demonstration assertions passed.'
    ;;
  container|reconcile|monitor|failure)
    bash "demo/$scenario.sh"
    ;;
  invalid)
    moon build --target native
    python3 -u demo/reject.py
    ;;
  *)
    echo "Unknown demo: $scenario" >&2
    exit 2
    ;;
esac
