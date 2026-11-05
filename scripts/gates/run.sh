#!/usr/bin/env bash
# Gate runner.
#
# Runs a slice's mechanical gates and prints, for every check: name, command, expected,
# actual, verdict. Paste the full output on the slice ticket: it is the slice's evidence of done.
#
# Dependencies: bash, coreutils (head, tail, wc, cut, sort), grep, sed, git, jq. No python.
#
# Usage:
#   scripts/gates/run.sh <gate>...                 run the named gates
#   scripts/gates/run.sh --slice <id>              run the gates slices.json lists for a slice
#   scripts/gates/run.sh --list                    list gates and slices
#   scripts/gates/run.sh --write-baseline <gate>   regenerate a gate's checked-in baseline
#
# Exit status: 0 when no blocking check is RED, 1 when one is, 2 on usage error.
# GATES_ROOT overrides the repo root being measured (default: this checkout).
#
# Verdicts:
#   GREEN     check passed
#   RED       check failed; blocks (non-zero exit)
#   REPORT    printed, never blocks
#   JUDGMENT  a human ruling recorded on the ticket; printed as "JUDGMENT — see ticket"
#
# Adding a gate (done by the slice that first needs it):
#   1. Create gates.d/<name>.sh defining gate_<name> (hyphens become underscores). It measures
#      the tree under "$GATES_ROOT" and calls, once per check:
#        gate_result <check-name> <command> <expected> <actual> <GREEN|RED|REPORT>
#      <command> must be a shell line that reproduces <actual> when run from the repo root.
#      A gate with a checked-in baseline also defines baseline_<name>, which writes it.
#   2. Add <name> to the slice's list in slices.json. A judgment gate needs no file: list it
#      as "judgment:<label>".
#   3. Show the gate RED once on a deliberately broken input before the slice relies on it.
#
# The one gate here is `machine-keys`, which CI and the Developing pipeline's `checks` step run.
# This repository keeps no pages, so it has no `stale-pages` gate: scripts/spoolway/pins.sh passes
# at once while .spoolway/companion.env names no PAGES_DIR.

set -euo pipefail

GATES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATES_ROOT=${GATES_ROOT:-$(cd "$GATES_DIR/../.." && pwd)}
export GATES_DIR GATES_ROOT

n_green=0 n_red=0 n_report=0 n_judgment=0

gate_result() {
  local name=$1 command=$2 expected=$3 actual=$4 verdict=$5
  case $verdict in
    GREEN) n_green=$((n_green + 1)) ;;
    RED) n_red=$((n_red + 1)) ;;
    REPORT) n_report=$((n_report + 1)) ;;
    *) echo "gate_result: unknown verdict '$verdict' for $name" >&2; exit 2 ;;
  esac
  printf -- '--- %s\n' "$name"
  printf '  command:  %s\n' "$command"
  printf '  expected: %s\n' "$expected"
  printf '  actual:   %s\n' "$actual"
  printf '  verdict:  %s\n' "$verdict"
}

judgment_result() {
  n_judgment=$((n_judgment + 1))
  printf -- '--- %s\n' "$1"
  printf '  verdict:  JUDGMENT — see ticket\n'
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/gates/run.sh <gate>...                 run the named gates
  scripts/gates/run.sh --slice <id>              run the gates slices.json lists for a slice
  scripts/gates/run.sh --list                    list gates and slices
  scripts/gates/run.sh --write-baseline <gate>   regenerate a gate's checked-in baseline
USAGE
  exit 2
}

gate_file() { printf '%s/gates.d/%s.sh' "$GATES_DIR" "$1"; }

load_gate() {
  local file
  file=$(gate_file "$1")
  if [ ! -f "$file" ]; then
    echo "unknown gate: $1 (no $file)" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  . "$file"
}

run_gate() {
  local name=$1
  case $name in
    judgment:*) judgment_result "${name#judgment:}"; return ;;
  esac
  load_gate "$name"
  printf '=== gate: %s\n' "$name"
  local before=$((n_green + n_red + n_report))
  "gate_${name//-/_}"
  # A gate that reports nothing has not checked anything: never let that read as a pass.
  if [ $((n_green + n_red + n_report)) -eq "$before" ]; then
    gate_result "$name" "scripts/gates/run.sh $name" "at least one check reported" "none" RED
  fi
}

[ $# -gt 0 ] || usage

gates=()
case $1 in
  --list)
    printf 'gates:\n'
    for f in "$GATES_DIR"/gates.d/*.sh; do printf '  %s\n' "$(basename "$f" .sh)"; done
    printf 'slices:\n'
    jq -r 'to_entries[] | "  \(.key): \(.value | join(" "))"' "$GATES_DIR/slices.json"
    exit 0
    ;;
  --write-baseline)
    [ $# -eq 2 ] || usage
    load_gate "$2"
    "baseline_${2//-/_}"
    exit 0
    ;;
  --slice)
    [ $# -eq 2 ] || usage
    if ! jq -e --arg s "$2" 'has($s)' "$GATES_DIR/slices.json" >/dev/null; then
      echo "unknown slice: $2 (not in slices.json)" >&2
      exit 2
    fi
    while IFS= read -r g; do gates+=("$g"); done < <(jq -r --arg s "$2" '.[$s][]' "$GATES_DIR/slices.json")
    ;;
  -*) usage ;;
  *) gates=("$@") ;;
esac

for g in "${gates[@]}"; do run_gate "$g"; done

if [ "$n_red" -gt 0 ]; then overall=RED; else overall=GREEN; fi
printf '=== %s — %d green, %d red, %d report, %d judgment\n' \
  "$overall" "$n_green" "$n_red" "$n_report" "$n_judgment"
[ "$n_red" -eq 0 ]
