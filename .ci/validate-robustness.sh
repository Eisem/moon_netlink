#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in moon timeout; do command -v "$tool" >/dev/null; done
timeout --kill-after=5s 120s moon test core --target native --filter 'robustness:*'
timeout --kill-after=5s 120s moon test route --target native --filter 'robustness:*'
echo 'Fixed-seed protocol robustness passed within the per-package execution budget.'
