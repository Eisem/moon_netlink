#!/usr/bin/env bash
# Comparison script baseline (P5-V2).
#
# Bash owns argument handling, dependency checks, sequencing, command execution,
# write accounting, compensation, exit status and cleanup. Python is used only
# as the declared JSON tool for strict validation, plan/report documents, the
# step argv and the independent `ip -j` comparison. This baseline never calls
# MoonNetlink and never parses human-readable `ip` output.
#
# A failure or a termination signal stops execution between steps and then
# compensates the acknowledged operations in reverse order. That recovery is
# best effort over supported managed fields; it is not an atomic transaction.
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

`apply --yes` executes in plan order, stops at the first failure or at the next
step boundary after SIGINT/SIGTERM, then compensates acknowledged operations in
reverse order and re-observes the result. Recovery is best effort and is not an
atomic transaction.

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
cleanup() {
  printf 'moonnetlink-mutation-attempts:%d\n' "$(( ${attempts:-0} + ${compensations:-0} ))" >&2
  rm -rf "$work"
}
trap cleanup EXIT

plan_document="$work/plan.json"
command_list="$work/commands.tsv"
report_document="$work/report.json"
state_file="$work/state.env"
rollback_commands="$work/rollback.tsv"
rollback_records="$work/rollback-records.tsv"
: > "$rollback_records"

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
# first failure or between steps on a termination signal. Every attempted
# mutation is counted, so a repeated run that writes nothing is provable
# instead of inferred from the final state.
attempts=0
compensations=0
failed_index=""
failed_exit=""
failed_message=""
failed_command=""
failed_outcome_unknown=false
cancelled=false
compensated=false
interrupted=false
declare -a completed=()
declare -a not_executed=()

record_not_executed() {
  local next=$1
  local total=$2
  while (( next < total )); do
    not_executed+=("$next")
    next=$((next + 1))
  done
}

execute_plan() {
  local total
  total=$(wc -l < "$command_list" | tr -d ' ')
  local line
  while IFS= read -r line; do
    local -a fields=()
    IFS=$'\t' read -r -a fields <<< "$line"
    local index=${fields[0]}
    if $interrupted; then
      cancelled=true
      record_not_executed "$index" "$total"
      return 1
    fi
    local -a command=("${fields[@]:1}")
    attempts=$((attempts + 1))
    local output
    if output=$("${command[@]}" 2>&1); then
      completed+=("$index")
    else
      # ip(8) exits 2 for every kernel refusal, so this is the tool's exit
      # status and not the kernel errno; only the diagnostic text is available.
      # A signal-terminated command leaves the outcome unknown instead.
      failed_exit=$?
      failed_index=$index
      failed_message=${output//$'\n'/ }
      failed_command=${command[*]}
      if (( failed_exit >= 128 )); then
        failed_outcome_unknown=true
      fi
      record_not_executed $((index + 1)) "$total"
      return 1
    fi
  done < "$command_list"
  return 0
}

# Best-effort recovery: compensate only operations the kernel acknowledged, in
# reverse order, and keep going when one compensation fails. The plan document,
# computed from the observation taken before the first write, is the recorded
# pre-change state. This restores supported managed fields and identities, not
# arbitrary kernel metadata, and is not an atomic transaction.
compensate_completed() {
  ((${#completed[@]} > 0)) || return 0
  compensated=true
  "${TOOL[@]}" rollback --plan "$plan_document" --completed "${completed[*]}" \
    > "$rollback_commands"
  local line
  while IFS= read -r line; do
    local -a fields=()
    IFS=$'\t' read -r -a fields <<< "$line"
    local index=${fields[0]}
    local -a command=("${fields[@]:1}")
    compensations=$((compensations + 1))
    local output
    if output=$("${command[@]}" 2>&1); then
      printf '%s\tcompleted\t\n' "$index" >> "$rollback_records"
    else
      printf '%s\tfailed\t%s\n' "$index" "${output//$'\n'/ }" >> "$rollback_records"
    fi
  done < "$rollback_commands"
  return 0
}

write_state() {
  {
    printf 'attempts=%d\n' "$attempts"
    printf 'compensations=%d\n' "$compensations"
    printf 'cancelled=%s\n' "$cancelled"
    printf 'compensated=%s\n' "$compensated"
    printf 'completed=%s\n' "${completed[*]:-}"
    printf 'not_executed=%s\n' "${not_executed[*]:-}"
    if [[ -n $failed_index ]]; then
      printf 'failed_index=%d\n' "$failed_index"
      printf 'failed_exit=%d\n' "$failed_exit"
      printf 'failed_outcome_unknown=%s\n' "$failed_outcome_unknown"
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
    trap 'interrupted=true' INT TERM
    result=0
    execute_plan || result=$?
    if [[ -n $failed_index ]] || $cancelled; then
      compensate_completed
    fi
    write_state
    "${TOOL[@]}" report --config "$config" --plan "$plan_document" --state "$state_file" \
      --rollback "$rollback_records" > "$report_document"
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
