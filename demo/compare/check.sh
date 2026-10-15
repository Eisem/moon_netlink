#!/usr/bin/env bash
# Run the comparison contract against one implementation side in a disposable
# user and network namespace (P5-V2).
#
# Every case gets fresh namespace state through `ip`; the caller's network is
# never touched. The namespace disappears when the last process exits, so no
# cleanup step can be forgotten.
set -euo pipefail
cd "$(dirname "$0")/../.."

for tool in unshare ip python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'compare-check: missing dependency: %s\n' "$tool" >&2
    exit 3
  }
done

side=script
arguments=()
while (( $# > 0 )); do
  case "$1" in
    --side) side=${2-}; shift 2 ;;
    --case | --exclude | --json)
      arguments+=("$1")
      if [[ $1 != --json ]]; then
        arguments+=("${2-}")
        shift
      fi
      shift
      ;;
    *) printf 'compare-check: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ $side != script && $side != app ]]; then
  printf 'compare-check: unknown side %s\n' "$side" >&2
  exit 2
fi
if [[ $side == app ]]; then
  command -v moon >/dev/null 2>&1 || {
    printf 'compare-check: missing dependency: moon\n' >&2
    exit 3
  }
  moon build --target native
fi

export MOONNETLINK_DEMO_PARENT_NETNS=$(readlink /proc/self/ns/net)
export MOONNETLINK_DEMO_PARENT_USERNS=$(readlink /proc/self/ns/user)
unshare -Urn -- bash -c '
set -euo pipefail
test "$(readlink /proc/self/ns/net)" != "$MOONNETLINK_DEMO_PARENT_NETNS"
test "$(readlink /proc/self/ns/user)" != "$MOONNETLINK_DEMO_PARENT_USERNS"
exec python3 demo/compare/run_cases.py "$@"
' compare-check --side "$side" "${arguments[@]+"${arguments[@]}"}"
