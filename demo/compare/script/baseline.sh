#!/usr/bin/env bash
# Comparison script baseline (P5-V2).
#
# Bash owns argument handling, dependency checks, sequencing, command execution,
# exit status and cleanup. Python is used only as the declared JSON tool for
# strict validation, plan/report documents and the independent `ip -j`
# comparison. This baseline never calls MoonNetlink and never parses
# human-readable `ip` output.
#
# The isolated harness in `demo/compare/` runs it inside a disposable network
# namespace; like the SDK CLI it does not guard the caller by itself, so always
# give it a disposable interface.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOL=(python3 "$HERE/json_tool.py")

usage() {
  cat <<'USAGE'
Usage:
  baseline.sh plan   <config.json> [--json] [--dangerous]
  baseline.sh apply  <config.json> [--yes] [--json] [--dangerous]
  baseline.sh verify <config.json> [--json]

Dependencies: bash 4+, iproute2 (`ip`), python3 3.8+ as the declared JSON tool.

Exit status:
  0  plan produced, or the requested state was reached and verified
  1  configuration rejected before any write, or the target was not reached
  2  usage error
  3  missing dependency or iproute2 failure while observing state
USAGE
}

dependency_failure() {
  printf 'compare-baseline: %s\n' "$1" >&2
  exit 3
}

for tool in ip python3; do
  command -v "$tool" >/dev/null 2>&1 || dependency_failure "missing dependency: $tool"
done
(( BASH_VERSINFO[0] >= 4 )) || dependency_failure 'bash 4 or newer is required'

subcommand=${1-}
if [[ -z $subcommand ]]; then
  usage >&2
  exit 2
fi
shift

config=""
json=false
dangerous=false
confirmed=false
for argument in "$@"; do
  case "$argument" in
    --json) json=true ;;
    --dangerous) dangerous=true ;;
    --yes) confirmed=true ;;
    --*) printf 'compare-baseline: unknown option %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n $config ]]; then
        printf 'compare-baseline: exactly one configuration path is allowed\n' >&2
        exit 2
      fi
      config=$argument
      ;;
  esac
done
if [[ -z $config ]]; then
  usage >&2
  exit 2
fi
if [[ $subcommand != apply && $confirmed == true ]]; then
  printf 'compare-baseline: --yes is only valid for apply\n' >&2
  exit 2
fi

work=$(mktemp -d)
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

plan_document="$work/plan.json"
command_list="$work/commands.tsv"
report_document="$work/report.json"
state_file="$work/state.env"

build_plan() {
  local -a arguments=(plan "$config")
  $dangerous && arguments+=(--dangerous)
  "${TOOL[@]}" "${arguments[@]}" > "$plan_document"
  "${TOOL[@]}" commands "$plan_document" > "$command_list"
}

show_document() {
  if $json; then
    cat "$1"
  else
    "${TOOL[@]}" format "$1"
  fi
}

# Execute the validated plan through iproute2, in plan order, stopping at the
# first failure. Every attempted mutation is counted, so a repeated run that
# writes nothing is provable instead of inferred from the final state.
attempts=0
compensations=0
failed_index=""
failed_exit=""
failed_message=""
failed_command=""
declare -a completed=()
declare -a not_executed=()

execute_plan() {
  local total
  total=$(wc -l < "$command_list" | tr -d ' ')
  local line
  while IFS= read -r line; do
    local -a fields=()
    IFS=$'\t' read -r -a fields <<< "$line"
    local index=${fields[0]}
    local -a command=("${fields[@]:1}")
    attempts=$((attempts + 1))
    local output
    if output=$("${command[@]}" 2>&1); then
      completed+=("$index")
    else
      # ip(8) exits 2 for every kernel refusal, so this is the tool's exit
      # status and not the kernel errno; only the diagnostic text is available.
      failed_exit=$?
      failed_index=$index
      failed_message=${output//$'\n'/ }
      failed_command=${command[*]}
      local next=$((index + 1))
      while (( next < total )); do
        not_executed+=("$next")
        next=$((next + 1))
      done
      return 1
    fi
  done < "$command_list"
  return 0
}

write_state() {
  {
    printf 'attempts=%d\n' "$attempts"
    printf 'compensations=%d\n' "$compensations"
    printf 'completed=%s\n' "${completed[*]:-}"
    printf 'not_executed=%s\n' "${not_executed[*]:-}"
    if [[ -n $failed_index ]]; then
      printf 'failed_index=%d\n' "$failed_index"
      printf 'failed_exit=%d\n' "$failed_exit"
      printf 'failed_message=%s\n' "$failed_message"
      printf 'failed_command=%s\n' "$failed_command"
    fi
  } > "$state_file"
}

case "$subcommand" in
  plan)
    build_plan
    show_document "$plan_document"
    ;;
  apply)
    build_plan
    if ! $confirmed; then
      # An unconfirmed apply is the same read-only dry-run as plan.
      show_document "$plan_document"
      exit 0
    fi
    result=0
    execute_plan || result=$?
    write_state
    "${TOOL[@]}" report --config "$config" --plan "$plan_document" --state "$state_file" \
      > "$report_document"
    show_document "$report_document"
    if "${TOOL[@]}" succeeded "$report_document"; then
      exit 0
    fi
    exit 1
    ;;
  verify)
    "${TOOL[@]}" verify "$config" > "$work/verify.json"
    show_document "$work/verify.json"
    if "${TOOL[@]}" succeeded "$work/verify.json"; then
      exit 0
    fi
    exit 1
    ;;
  *)
    printf 'compare-baseline: unknown subcommand %s\n' "$subcommand" >&2
    usage >&2
    exit 2
    ;;
esac
