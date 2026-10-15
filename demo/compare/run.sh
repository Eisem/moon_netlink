#!/usr/bin/env bash
# Fair two-sided acceptance entry point (P5-V5).
#
# Runs the script baseline and the MoonBit application sample against the same
# comparison contract, each in its own disposable user and network namespace,
# bounds every side in time, terminates leftover process groups, saves the raw
# results and prints a pass/fail table. The run succeeds only when both sides
# meet every declared expectation; a side "winning" is not a pass condition.
#
# Missing namespace privileges fail explicitly; the run never falls back to the
# caller's network namespace.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE/../.."

usage() {
  cat <<'USAGE'
Usage:
  bash demo/compare/run.sh [options]

Options:
  --sides <list>     comma separated sides to run (default: script,app)
  --case <id>        run one contract case (repeatable)
  --results <dir>    where to save raw results (default: _build/compare/<utc>)
  --timeout <sec>    bound per side (default: 900)
  --json             pass --json to the comparison report

Dependencies: bash 4+, iproute2, python3, unshare with working user and network
namespaces, and the MoonBit toolchain for the application side.

Results are saved as <dir>/<side>.json, <dir>/<side>.err and <dir>/report.txt.
Exit status: 0 only when every side passed every case and both sides agreed on
the contract-observed values; 2 usage error; 3 missing dependency or privilege.
USAGE
}

sides=script,app
results=""
limit=900
cases=()
json=""
while (( $# > 0 )); do
  case "$1" in
    --sides) sides=${2-}; shift 2 ;;
    --case) cases+=(--case "${2-}"); shift 2 ;;
    --results) results=${2-}; shift 2 ;;
    --timeout) limit=${2-}; shift 2 ;;
    --json) json=--json; shift ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'compare-run: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n $sides ]] || { usage >&2; exit 2; }
[[ $limit =~ ^[0-9]+$ ]] || { printf 'compare-run: --timeout needs seconds\n' >&2; exit 2; }

missing=()
for tool in unshare ip python3; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ -z $results ]]; then
  results="_build/compare/$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$results"

if (( ${#missing[@]} > 0 )); then
  printf 'compare-run: missing dependencies: %s\n' "${missing[*]}" >&2
  exit 3
fi
if [[ $sides == *app* ]]; then
  if ! command -v moon >/dev/null 2>&1; then
    printf 'compare-run: the application side needs the MoonBit toolchain (moon)\n' >&2
    exit 3
  fi
fi

# Explicit privilege check: never continue into the caller's network namespace.
if ! unshare -Urn -- true 2>/dev/null; then
  printf 'compare-run: user and network namespaces are required; refusing to touch the host network\n' >&2
  exit 3
fi

timed_out=0
run_bounded() {
  local seconds=$1
  local output=$2
  local errors=$3
  shift 3
  timed_out=0
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" > "$output" 2> "$errors" &
  else
    "$@" > "$output" 2> "$errors" &
  fi
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= seconds )); then
      kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      timed_out=1
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  local status=0
  wait "$pid" || status=$?
  return "$status"
}

failed=0
IFS=',' read -r -a side_list <<< "$sides"
for side in "${side_list[@]}"; do
  [[ -n $side ]] || continue
  printf '=== %s side (bound %ss) ===\n' "$side" "$limit"
  status=0
  run_bounded "$limit" "$results/$side.json" "$results/$side.err" \
    bash "$HERE/check.sh" --side "$side" --json "${cases[@]+"${cases[@]}"}" || status=$?
  if (( timed_out )); then
    printf 'compare-run: %s exceeded %ss and its process group was terminated\n' "$side" "$limit" >&2
    failed=1
  elif (( status != 0 )); then
    printf 'compare-run: %s side reported %s check failure(s) or a harness error\n' \
      "$side" "$(grep -c '"status": "failed"' "$results/$side.json" 2>/dev/null || printf '?')" >&2
    failed=1
  else
    printf '%s side: all checks passed\n' "$side"
  fi
done

report_status=0
python3 "$HERE/compare_results.py" --results "$results" --sides "$sides" \
  ${json:+--json} | tee "$results/report.txt" || report_status=$?
if (( report_status != 0 )); then
  failed=1
fi

printf '\nraw results: %s\n' "$results"
if (( failed )); then
  printf 'comparison acceptance: failed\n' >&2
  exit 1
fi
printf 'comparison acceptance: passed\n'
