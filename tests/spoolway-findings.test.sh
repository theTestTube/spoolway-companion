#!/usr/bin/env bash
# Offline test for the shipped run-report.sh and findings.sh: a crossed
# threshold files one run report per run, none crossed files nothing, a finding without evidence is
# dropped, a sixth is cut, and no open digest exits 3. `gh` and `spoolway` are fakes on PATH that
# record their calls; nothing reaches GitHub or the network.
# Usage: tests/spoolway-findings.test.sh (needs bash, jq and awk)

set -u

unset "${!SPOOLWAY_@}" RUN_REPORT_REPO FINDINGS_REPO COMPANION_ENV_FILE

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-}"; fi; }

mkdir -p "$work/bin" "$work/home/queue" "$work/app/scripts/spoolway"
shipped="$repo/claude-plugin/spoolway/types/scripts/spoolway"
cp "$shipped"/*.sh "$work/app/scripts/spoolway/"
export CALLS="$work/calls" DIGEST_URL=

# spoolway: `eval` answers one ledger row for run r1, `doctor` reports the problems in $DOCTOR_PROBLEMS.
cat > "$work/bin/spoolway" <<'FAKE'
#!/bin/sh
echo "spoolway $*" >> "$CALLS"
case "$*" in
  *" eval "*) echo '{"rows":[{"run":"r1","blocks":0,"cost_usd":1,"pipeline_version":"1"}]}' ;;
  *" doctor "*) echo "{\"problems\":${DOCTOR_PROBLEMS:-0}}" ;;
esac
exit 0
FAKE
# gh: `issue list` answers $DIGEST_URL (the digest) or nothing; `issue create` and `issue comment`
# print a URL; `api` lists no comment. Every call is logged, the bodies are kept.
cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "repo view") [ -n "${GH_FAIL:-}" ] && exit 1; echo example/project ;;
  "issue list") case "$*" in *weekly*) [ -n "$DIGEST_URL" ] && echo "$DIGEST_URL" ;; esac ;;
  "issue create"|"issue comment")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$BODY_OUT"; shift; done
    echo "https://github.com/example/project/issues/99" ;;
esac
exit 0
FAKE
chmod +x "$work/bin/spoolway" "$work/bin/gh"

task=$work/home/queue/t1.md
scratch=$work/home/scratch/t1
export BODY_OUT="$work/body.out"
make_task() {
  { printf -- '---\nid: t1\nstage: %s\npipeline: developing\nrun: r1\nticket: https://github.com/example/project/issues/5\nbranch: task/t1\n' "$1"
    [ $# -gt 1 ] && shift && printf '%s\n' "$@"
    printf -- '---\n\n## Status Log\n- a line\n'; } > "$task"
  rm -rf "$scratch" "$BODY_OUT"; : > "$CALLS"
}
run() {
  local script=$1; shift
  (cd "$work/app" && PATH="$work/bin:$PATH" SPOOLWAY_TASK_FILE="$task" SPOOLWAY_TASK=t1 bash "scripts/spoolway/$script" "$@") > "$work/out" 2> "$work/err"
  rc=$?
}
thresholds=(--blocks 1 --implement-arrivals 3 --environment-failures 1 --spend-usd 20 --spend-median-x 2 --spend-min-runs 5 --doctor-problems 1)

# --- run-report.sh: signals ---------------------------------------------------------------------

check "the INTERIM header is gone" '! grep -q INTERIM "$shipped/run-report.sh"'

make_task signals
run run-report.sh signals "${thresholds[@]}"
check "signals: none crossed leaves no verdict" '[ $rc -eq 0 ] && grep -q "no signal crossed" "$work/out" && ! ls "$scratch"/run-report.r1.md 2>/dev/null'
run run-report.sh file
check "file: none crossed files nothing" '[ $rc -eq 0 ] && ! grep -q "issue create" "$CALLS"' "rc=$rc $(cat "$work/err")"

make_task signals "arrivals:" "  implement: 3"
run run-report.sh signals "${thresholds[@]}"
check "signals: a crossed threshold leaves a verdict" '[ $rc -eq 0 ] && [ -s "$scratch/run-report.r1.md" ]' "rc=$rc $(cat "$work/err")"
make_task report "arrivals:" "  implement: 3"
mkdir -p "$scratch"
printf 'Run `r1`: crossed.\n' > "$scratch/run-report.r1.md"
run run-report.sh file
check "file: a verdict files once, in this repository, labelled run-report" \
  '[ $rc -eq 0 ] && [ "$(grep -c "issue create" "$CALLS")" = 1 ] && grep "issue create" "$CALLS" | grep -q -- "--repo example/project" && grep "issue create" "$CALLS" | grep -q -- "--label run-report" && ! grep "issue create" "$CALLS" | grep -q P1-high' "rc=$rc $(cat "$work/err") $(cat "$CALLS")"
run run-report.sh file
check "file: no repository named, the run's own is used" 'grep -q "repo view" "$CALLS"'
check "file: a second call for the same run files nothing more" '[ $rc -eq 0 ] && [ "$(grep -c "issue create" "$CALLS")" = 1 ] && grep -q "already filed" "$work/out"'

make_task report
run run-report.sh file --urgent "the gate is broken"
check "file --urgent files with P1-high and the line" \
  '[ $rc -eq 0 ] && grep "issue create" "$CALLS" | grep -q -- "--label P1-high" && grep -q "the gate is broken" "$BODY_OUT"' "rc=$rc $(cat "$work/err")"

# An unresolvable repository must not lose an urgent finding, and must not be asked for when
# there is nothing to file or the run is already filed.
make_task report
GH_FAIL=1 run run-report.sh file --urgent "the gate is broken"
check "file: an urgent finding is printed when the repository cannot be resolved" \
  '[ $rc -eq 2 ] && grep -qxF "run-report: urgent finding not filed: the gate is broken" "$work/err" && ! grep -q "issue create" "$CALLS"' "rc=$rc $(cat "$work/err")"
make_task report
GH_FAIL=1 run run-report.sh file
check "file: with nothing to file, no repository is resolved and gh is not called" \
  '[ $rc -eq 0 ] && [ ! -s "$CALLS" ] && grep -q "nothing to file" "$work/out"' "rc=$rc $(cat "$work/err") $(cat "$CALLS")"
make_task report
mkdir -p "$scratch"; echo https://github.com/example/project/issues/7 > "$scratch/run-report.r1.url"
GH_FAIL=1 run run-report.sh file --urgent "again"
check "file: an already filed run resolves no repository and calls no gh" \
  '[ $rc -eq 0 ] && [ ! -s "$CALLS" ] && grep -q "already filed" "$work/out"' "rc=$rc $(cat "$work/err") $(cat "$CALLS")"
run run-report.sh nope
check "run-report refuses an unknown subcommand" '[ $rc -eq 64 ]'
make_task checks
run run-report.sh signals "${thresholds[@]}"
check "signals refuses to run on another step's stage" '[ $rc -eq 64 ]'

# --- findings.sh --------------------------------------------------------------------------------

block() { # <title> <evidence>
  printf '## %s\n- class: bug\n- evidence: %s\n- where: task t1\n- type: Developing\n- priority: P1-high\n\n' "$1" "$2"
}
make_task report
mkdir -p "$scratch"
{ block "has evidence" "scripts/x.sh:3"; block "no evidence" ""; } > "$scratch/findings.md"
export DIGEST_URL=https://github.com/example/project/issues/50
run findings.sh write
check "findings: one with evidence is written as a comment on the digest, and the one without is dropped" \
  '[ $rc -eq 0 ] && [ "$(grep -c "issue comment" "$CALLS")" = 1 ] && grep -q "^### has evidence" "$BODY_OUT" && ! grep -q "no evidence" "$BODY_OUT" && grep -q "dropped (no evidence)" "$work/err"' "rc=$rc $(cat "$work/err")"
check "findings: the digest is searched in this repository" 'grep "issue list" "$CALLS" | grep -q -- "--repo example/project"'
check "findings: the comment goes to the digest, not the work issue" 'grep "issue comment" "$CALLS" | grep -q "issues/50"'

make_task report
mkdir -p "$scratch" "$work/app/.spoolway"
block "has evidence" "scripts/x.sh:3" > "$scratch/findings.md"
printf 'FINDINGS_REPO=example/digests\nRUN_REPORT_REPO=example/reports\n' > "$work/app/.spoolway/companion.env"
run findings.sh write
check "findings: FINDINGS_REPO in companion.env names the digest's repository" 'grep "issue list" "$CALLS" | grep -q -- "--repo example/digests" && ! grep -q "repo view" "$CALLS"' "$(cat "$CALLS")"
make_task report
run run-report.sh file --urgent "named elsewhere"
check "file: RUN_REPORT_REPO in companion.env names the report's repository" 'grep "issue create" "$CALLS" | grep -q -- "--repo example/reports"' "$(cat "$CALLS")"
make_task report
RUN_REPORT_REPO=example/env run run-report.sh file --urgent "the environment wins"
check "file: the environment variable wins over companion.env" 'grep "issue create" "$CALLS" | grep -q -- "--repo example/env"' "$(cat "$CALLS")"

# --- run-report.sh repo: the Feeding-back intake asks it, bound to no task --------------------
# run_bare runs a script the way an intake lane does: no SPOOLWAY_TASK_FILE, no SPOOLWAY_TASK.
run_bare() {
  local script=$1; shift
  : > "$CALLS"
  (cd "$work/app" && PATH="$work/bin:$PATH" bash "scripts/spoolway/$script" "$@") > "$work/out" 2> "$work/err"
  rc=$?
}
RUN_REPORT_REPO=example/env run_bare run-report.sh repo
check "repo: prints RUN_REPORT_REPO from the environment with no task file, asking gh nothing" \
  '[ $rc -eq 0 ] && [ "$(cat "$work/out")" = example/env ] && ! grep -q "^gh " "$CALLS"' "rc=$rc out=$(cat "$work/out") err=$(cat "$work/err")"
run_bare run-report.sh repo
check "repo: prints RUN_REPORT_REPO from companion.env with no task file, asking gh nothing" \
  '[ $rc -eq 0 ] && [ "$(cat "$work/out")" = example/reports ] && ! grep -q "^gh " "$CALLS"' "rc=$rc out=$(cat "$work/out") err=$(cat "$work/err")"
rm -f "$work/app/.spoolway/companion.env"
run_bare run-report.sh repo
check "repo: with neither set, prints the run repository gh reads from the checkout" \
  '[ $rc -eq 0 ] && [ "$(cat "$work/out")" = example/project ] && grep -q "^gh repo view" "$CALLS"' "rc=$rc out=$(cat "$work/out") err=$(cat "$work/err")"
GH_FAIL=1 run_bare run-report.sh repo
check "repo: exits 2 and prints nothing on stdout when gh cannot tell the repository" \
  '[ $rc -eq 2 ] && [ ! -s "$work/out" ] && grep -qF "cannot tell which repository" "$work/err"' "rc=$rc out=$(cat "$work/out") err=$(cat "$work/err")"
run_bare run-report.sh signals "${thresholds[@]}"
check "signals still refuses to run with no task file" '[ $rc -eq 64 ] && grep -qF "names no task file" "$work/err"' "rc=$rc"
run_bare run-report.sh file
check "file still refuses to run with no task file" '[ $rc -eq 64 ] && grep -qF "names no task file" "$work/err"' "rc=$rc"

make_task report
mkdir -p "$scratch"
for i in 1 2 3 4 5 6; do block "finding $i" "file:$i"; done > "$scratch/findings.md"
run findings.sh write
check "findings: a sixth is cut" \
  '[ $rc -eq 0 ] && [ "$(grep -c "^### " "$BODY_OUT")" = 5 ] && ! grep -q "finding 6" "$BODY_OUT" && grep -q "past the limit of 5: finding 6" "$work/err"' "rc=$rc $(cat "$work/err")"

make_task report
mkdir -p "$scratch"
block "a finding" "file:1" > "$scratch/findings.md"
DIGEST_URL= run findings.sh write
check "findings: no digest open exits 3 and writes nothing" '[ $rc -eq 3 ] && ! grep -q "issue comment" "$CALLS"' "rc=$rc $(cat "$work/err")"

make_task report
mkdir -p "$scratch"
block "no evidence" "" > "$scratch/findings.md"
run findings.sh write
check "findings: none admitted writes no comment" '[ $rc -eq 0 ] && ! grep -q "issue comment" "$CALLS"'

make_task report
run findings.sh write
check "findings: no findings.md writes no comment" '[ $rc -eq 0 ] && ! grep -q "issue comment" "$CALLS"'

echo
if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failure(s)"
  exit 1
fi
