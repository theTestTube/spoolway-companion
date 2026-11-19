#!/usr/bin/env bash
# Run reports: a run files one issue only when an objective signal crosses its threshold. The
# issue goes to RUN_REPORT_REPO, from the environment or `.spoolway/companion.env`, else to the
# run's own repository (`run_report_repo` in lib.sh).
#
#   run-report.sh signals <thresholds>   the `signals` command step. Measures the run against the
#                                        thresholds the pipeline file passes, and leaves a verdict
#                                        in the task's scratch space: `run-report.<run>.md`, the issue
#                                        body, when at least one signal crossed; nothing otherwise.
#   run-report.sh file [--urgent <line>] run by the `report` lane. Opens the issue the verdict
#                                        calls for, once per run, and prints its URL.
#   run-report.sh repo                   prints the report repository, `[HOST/]OWNER/REPO`, for the
#                                        Feeding-back intake. Needs no task: an intake lane is bound
#                                        to none.
#
# The thresholds live in the pipeline file and nowhere else: `signals` refuses to run without
# every one of them, and `file` decides nothing: it opens what `signals` left, or an urgent
# finding the lane names, the one signal that is a lane's judgment.
#
# Exit codes of `file`: 0 filed, already filed, or nothing to file; 2 the tracker refused.
# Exit codes of `repo`: 0 printed; 2 the report repository cannot be told (nothing on stdout).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

REPORT_REPO=
REPORT_LABEL=run-report
URGENT_LABEL=P1-high

# `repo` reads no task, so it answers before the task file is required.
if [ "${1:-}" = repo ]; then
  run_report_repo || exit 2
  exit 0
fi

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "run-report: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
task=${SPOOLWAY_TASK:-$(frontmatter_value "$task_file" id)}
# The project's home holds queue/, scratch/ and the command logs; the task file sits one level in.
home=$(cd "$(dirname "$task_file")/.." && pwd)
# A command step is handed no SPOOLWAY_SCRATCH and a lane is, so both subcommands derive the same
# directory from the task file and neither reads that variable. Every file carries the run id: a
# later run of the same task id never reads an earlier run's verdict or marker.
scratch=$home/scratch/$task
run=$(frontmatter_value "$task_file" run)
verdict=$scratch/run-report.$run.md
filed=$scratch/run-report.$run.url

# frontmatter_map_value <file> <map> <key>: one value of a one-level frontmatter map, as
# `arrivals:` / `  implement: 2`; nothing when the map or the key is missing.
frontmatter_map_value() {
  awk -v map="$2" -v key="$3" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
    /^---[ \t\r]*$/ { exit }
    /^[^ \t]/ { inmap = (index($0, map ":") == 1); next }
    inmap {
      line = $0; sub(/^[ \t]+/, "", line)
      if (index(line, key ":") == 1) {
        value = substr(line, length(key) + 2)
        gsub(/^[ \t"\047]+|[ \t\r"\047]+$/, "", value)
        print value
        exit
      }
    }
  ' "$1"
}

# moves_into <file> <step>: how many times the task moved into <step>, the larger of the sums over
# the `steps:` and the `rounds:` maps' `<from>-><step>` keys; 0 when there are none.
moves_into() {
  awk -v to="->$2:" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
    /^---[ \t\r]*$/ { exit }
    /^[^ \t]/ { map = (index($0, "steps:") == 1) ? "steps" : (index($0, "rounds:") == 1) ? "rounds" : ""; next }
    map != "" {
      line = $0; gsub(/[ \t"\047]/, "", line)
      at = index(line, to)
      if (at > 0) total[map] += substr(line, at + length(to))
    }
    END { print (total["steps"] > total["rounds"] ? total["steps"] : total["rounds"]) + 0 }
  ' "$1"
}

# at_least <value> <threshold>, above <value> <threshold>: numeric comparisons, decimals allowed.
at_least() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }
above() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }

signals() {
  local blocks='' arrivals='' environment='' doctor='' spend_x='' spend_min='' spend_usd=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --blocks) blocks=$2 ;;
      --implement-arrivals) arrivals=$2 ;;
      --environment-failures) environment=$2 ;;
      --doctor-problems) doctor=$2 ;;
      --spend-median-x) spend_x=$2 ;;
      --spend-min-runs) spend_min=$2 ;;
      --spend-usd) spend_usd=$2 ;;
      *) echo "run-report: unknown threshold $1" >&2; exit 64 ;;
    esac
    shift 2
  done
  for name in blocks arrivals environment doctor spend_x spend_min spend_usd; do
    if [ -z "${!name}" ]; then
      echo "run-report: the pipeline file passes no threshold for $name; every signal needs one" >&2
      exit 64
    fi
  done

  own_step signals signals
  if step_skipped "$task_file" signals; then
    echo "signals: named in skip_steps, passing at once"
    exit 0
  fi

  mkdir -p "$scratch"
  rm -f "$verdict"

  local repo=${SPOOLWAY_REPO:-.}
  local pipeline
  pipeline=$(frontmatter_value "$task_file" pipeline)

  local rows="$scratch/run-report.rows"
  : > "$rows"
  local crossed=0
  # row <signal> <value> <threshold> <crossed: yes|no|unread>
  row() {
    printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >> "$rows"
    echo "signals: $1 = $2 (threshold $3): $4"
    if [ "$4" = yes ]; then crossed=$((crossed + 1)); fi
  }

  # The ledger, one row per run of a task. This run's own row carries what its lanes have banked
  # so far: the `report` lane has not run yet, so its spend is never part of the comparison.
  local ledger="$scratch/run-report.ledger.json" have_ledger=no mine=''
  # `--json` may print a line naming the checkout before the document: keep the one with rows.
  if spoolway -C "$repo" eval --by task --pipeline "$pipeline" --json 2>/dev/null \
    | jq -es 'map(select(type == "object" and has("rows")))[0] // empty' > "$ledger" 2>/dev/null \
    && [ -s "$ledger" ]; then
    have_ledger=yes
    mine=$(jq -c --arg run "$run" '[.rows[] | select(.run == $run)][0] // empty' "$ledger")
  fi

  # 1. The task touched `blocked`: the largest of three counts of the same thing. A lane of this
  #    run ended blocked (the ledger's BLOCKS), the task file counts an arrival at `blocked`, or
  #    it counts moves into `blocked` in its `steps:` or `rounds:` map (`implement->blocked: 1`).
  local touched=0 count
  [ -n "$mine" ] && touched=$(jq -r '.blocks // 0' <<< "$mine")
  for count in "$(frontmatter_map_value "$task_file" arrivals blocked)" "$(moves_into "$task_file" blocked)"; do
    if above "${count:-0}" "$touched"; then touched=$count; fi
  done
  if at_least "$touched" "$blocks"; then row "task touched \`blocked\`" "$touched" "≥ $blocks" yes
  else row "task touched \`blocked\`" "$touched" "≥ $blocks" no; fi

  # 2. The loop was spent: arrivals at `implement`, the first included.
  local arrived
  arrived=$(frontmatter_map_value "$task_file" arrivals implement)
  arrived=${arrived:-0}
  if at_least "$arrived" "$arrivals"; then row "arrivals at \`implement\`" "$arrived" "≥ $arrivals" yes
  else row "arrivals at \`implement\`" "$arrived" "≥ $arrivals" no; fi

  # 3. A check failed for an environment reason: `ENVIRONMENT:` lines in the checks step's log.
  local env_lines=0 log
  while IFS= read -r log; do
    env_lines=$((env_lines + $(grep -c '^ENVIRONMENT:' "$log" || true)))
  done < <(find "$home" -maxdepth 3 -type f -name "$task · checks.log" 2>/dev/null)
  if at_least "$env_lines" "$environment"; then row "\`ENVIRONMENT:\` check failures" "$env_lines" "≥ $environment" yes
  else row "\`ENVIRONMENT:\` check failures" "$env_lines" "≥ $environment" no; fi

  # 4. Spend: above the fixed ceiling from the first run on, or above <x> times the median of the
  #    earlier runs of this pipeline and version once there are enough of them.
  if [ -z "$mine" ]; then
    if [ "$have_ledger" = yes ]; then row "spend (USD)" "no ledger row for run $run" "> $spend_usd" unread
    else row "spend (USD)" "the ledger could not be read" "> $spend_usd" unread; fi
  else
    local cost version stats prior median
    cost=$(jq -r '.cost_usd // 0' <<< "$mine")
    version=$(jq -r '.pipeline_version // ""' <<< "$mine")
    if above "$cost" "$spend_usd"; then row "spend (USD)" "$cost" "> $spend_usd" yes
    else row "spend (USD)" "$cost" "> $spend_usd" no; fi
    stats=$(jq -r --arg run "$run" --arg version "$version" '
      [.rows[] | select(.run != $run and .pipeline_version == $version) | .cost_usd] | sort
      | length as $n
      | (if $n == 0 then 0 elif $n % 2 == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end) as $median
      | "\($n) \($median)"' "$ledger")
    prior=${stats% *}
    median=${stats#* }
    local what="spend against the median of $pipeline $version" bar="> $spend_x × median, from $spend_min earlier runs"
    if ! at_least "$prior" "$spend_min"; then row "$what" "$cost, $prior earlier runs" "$bar" no
    elif above "$cost" "$(awk -v m="$median" -v x="$spend_x" 'BEGIN { print m * x }')"; then row "$what" "$cost, median $median over $prior" "$bar" yes
    else row "$what" "$cost, median $median over $prior" "$bar" no; fi
  fi

  # 5. `spoolway doctor` reports a problem. Its notes are standing remarks, not problems.
  local problems
  #    It exits non-zero exactly when it has one to report, so its exit code is not read.
  if problems=$( { spoolway -C "$repo" doctor --json 2>/dev/null || true; } \
    | jq -ers 'map(select(type == "object" and has("problems")))[0].problems | numbers'); then
    if at_least "$problems" "$doctor"; then row "\`spoolway doctor\` problems" "$problems" "≥ $doctor" yes
    else row "\`spoolway doctor\` problems" "$problems" "≥ $doctor" no; fi
  else
    row "\`spoolway doctor\` problems" "doctor could not be read" "≥ $doctor" unread
  fi

  if [ "$crossed" -eq 0 ]; then
    rm -f "$rows" "$ledger"
    echo "signals: no signal crossed its threshold; this run files no report"
    exit 0
  fi

  {
    echo "Run \`$run\` of task \`$task\` crossed $crossed objective signal(s). Filed by the pipeline's rule, not by a lane's judgment."
    echo
    echo "- Pipeline: \`$pipeline\`${mine:+ $(jq -r '.pipeline_version // ""' <<< "$mine")}"
    echo "- Ticket: $(frontmatter_value "$task_file" ticket)"
    echo "- Branch: \`$(frontmatter_value "$task_file" branch)\`"
    echo
    echo "## Signals"
    echo
    echo "| Signal | Value | Threshold | Crossed |"
    echo "|---|---|---|---|"
    cat "$rows"
    echo
    awk '/^## Status Log/ { on = 1 } on && /^## / && !/^## Status Log/ { exit } on' "$task_file"
  } > "$verdict"
  rm -f "$rows" "$ledger"
  echo "signals: $crossed signal(s) crossed; the report lane files $verdict"
}

file_report() {
  local urgent=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --urgent) urgent=$2; shift 2 ;;
      *) echo "run-report: unknown option $1" >&2; exit 64 ;;
    esac
  done

  if [ ! -f "$verdict" ] && [ -z "$urgent" ]; then
    echo "run-report: no signal crossed its threshold and no urgent finding was named; nothing to file"
    exit 0
  fi

  local pipeline
  pipeline=$(frontmatter_value "$task_file" pipeline)

  # Exactly one issue per run: the marker this script leaves, then the tracker itself.
  if [ -s "$filed" ]; then
    echo "run-report: already filed for run $run: $(cat "$filed")"
    exit 0
  fi

  # The tracker is needed from here on. A refused resolution must not lose an urgent finding.
  if ! REPORT_REPO=$(run_report_repo); then
    [ -n "$urgent" ] && echo "run-report: urgent finding not filed: $urgent" >&2
    exit 2
  fi

  local existing
  if ! existing=$(gh issue list --repo "$REPORT_REPO" --label "$REPORT_LABEL" --state all --search "\"$run\" in:body" --json url --jq '.[0].url // empty' 2>&1); then
    echo "REFUSED: could not read $REPORT_REPO to check for an earlier report: $existing" >&2
    exit 2
  fi
  if [ -n "$existing" ]; then
    mkdir -p "$scratch"
    echo "$existing" > "$filed"
    echo "run-report: already filed for run $run: $existing"
    exit 0
  fi

  mkdir -p "$scratch"
  local body="$scratch/run-report.body.md"
  local labels=(--label "$REPORT_LABEL")
  if [ -f "$verdict" ]; then
    cp "$verdict" "$body"
  else
    {
      echo "Run \`$run\` of task \`$task\` crossed no measured signal. Filed for the urgent finding below."
      echo
      echo "- Pipeline: \`$pipeline\`"
      echo "- Ticket: $(frontmatter_value "$task_file" ticket)"
      echo "- Branch: \`$(frontmatter_value "$task_file" branch)\`"
    } > "$body"
  fi
  if [ -n "$urgent" ]; then
    labels+=(--label "$URGENT_LABEL")
    printf '\n## Urgent finding\n\nA lane'\''s judgment, not a measured signal.\n\n%s\n' "$urgent" >> "$body"
  fi

  local url
  if ! url=$(gh issue create --repo "$REPORT_REPO" --title "run report: $pipeline · $task · $run" "${labels[@]}" --body-file "$body" 2>&1); then
    echo "REFUSED: $REPORT_REPO did not take the report: $url" >&2
    exit 2
  fi
  echo "$url" > "$filed"
  echo "run-report: filed $url"
}

case "${1:-}" in
  signals) shift; signals "$@" ;;
  file) shift; file_report "$@" ;;
  *) echo "usage: run-report.sh signals <thresholds> | file [--urgent <line>] | repo" >&2; exit 64 ;;
esac
