#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 .ci/test_coverage_gate.py
python3 .ci/check_critical_tests.py
moon coverage clean
moon test --target native --enable-coverage
mkdir -p _build/coverage
moon coverage report -f cobertura -o _build/coverage/cobertura.xml
moon coverage report -f html -o _build/coverage/html
python3 .ci/coverage_gate.py _build/coverage/cobertura.xml
