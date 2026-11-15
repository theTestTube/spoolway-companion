#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `gates` step of the Materializing pipeline: what the `document` step wrote passes the
# repository's own gates before a pull request exists, so review is the only thing left to the
# owner. Exit 0 passes the step, anything else sends the task back to `document`.
#
# Three things, all of them run so one return can correct them all:
#
#   guards   what no gate can see from the tree alone. Nothing changes outside the paths
#            `ALLOWED` lists below: this pipeline's pull request holds pages and glossary only.
#            With `PAGES_DIR` set, no lane moves a drift pin: a page the base has keeps its
#            `source_commit` and `verified_commit`, and a new page names a commit the base
#            already holds, since `spoolway stack` squashes every commit this task made into one.
#   gates    `GATES` below: your repository's own gate command, the part of what CI runs that
#            applies to pages and glossary. Empty as shipped: the step says no gate is written
#            and the guards and pages alone decide. Fill it in.
#   pages    with `PAGES_DIR` set, `pins.sh check all`. A page that is red is answered for in the
#            record `stale-pages.md`, and the `pin` step moves its pin after the handover.
#
# A command step's output is kept in `commands/<task> · gates.log` only, which a lane is not told
# about, so what failed is also written to `gates.problems.md` in the task's scratch space: that
# is what `document` reads when the task comes back to it.
#
# `ENVIRONMENT:` failures are not the document lane's to fix: its prompt tells it to block.
#
#   materializing-gates.sh           the `gates` step, and only inside it.
#   materializing-gates.sh preview   run by the `document` lane, and only inside that step: the
#                                    same three things, read and reported, with nothing written.
#                                    The pipeline file never passes it.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

PAGES_DIR=$(companion_env PAGES_DIR)
PAGES_DIR=${PAGES_DIR#./}
PAGES_DIR=${PAGES_DIR%/}
PAGES_LOG=$(companion_env PAGES_LOG)

# The gate command, as words: the part of your CI that applies to what `document` writes, for
# example (scripts/gates/run.sh lint links). Exit 0 is green, anything else is red.
GATES=()

# The paths this pipeline's pull request may change: a file by its path, a directory by its path
# with a trailing slash. Add what your page write path also writes (its sources, its index).
ALLOWED=(CONTEXT.md)
[ -n "$PAGES_DIR" ] && ALLOWED+=("$PAGES_DIR/")
[ -n "$PAGES_LOG" ] && ALLOWED+=("${PAGES_LOG#./}")

usage() { echo "usage: materializing-gates.sh [preview]" >&2; exit 64; }
preview=
case $# in
  0) ;;
  1) [ "$1" = preview ] || usage; preview=1 ;;
  *) usage ;;
esac
if [ -n "$preview" ]; then own_step document preview; else own_step gates; fi

task_file=${SPOOLWAY_TASK_FILE:-}
if step_skipped "$task_file" gates; then
  echo "gates: named in skip_steps, passing at once"
  exit 0
fi

cd "$root"

problems=
if [ -z "$preview" ]; then
  scratch=$(task_scratch "$task_file")
  mkdir -p "$scratch"
  problems=$scratch/gates.problems.md
  rm -f "$problems"
fi

found=$(mktemp)
trap 'rm -f "$found"' EXIT
failed=0
# problem <text>: one finding, to the log and to the file the document step reads.
problem() {
  failed=$((failed + 1))
  printf '%s\n' "$1" >&2
  printf '%s\n\n' "$1" >> "$found"
}
finish() {
  if [ "$failed" -eq 0 ]; then
    echo "gates: GREEN"
    exit 0
  fi
  if [ -n "$problems" ]; then
    { echo "# What the gates step refused"; echo; cat "$found"; } > "$problems"
    echo "gates: $failed finding(s), written to $problems" >&2
  else
    echo "gates: $failed finding(s)" >&2
  fi
  exit 1
}

if ! base=$(branch_base "$root" "$task_file") || [ -z "$base" ]; then
  problem "ENVIRONMENT: gates: the branch this task was cut from resolves to no ref here; there is nothing to compare the change against"
  finish
fi

if [ -n "$(git status --porcelain)" ]; then
  problem "gates: the worktree has uncommitted changes; what is gated is what the pull request will carry, so commit them: $(git status --porcelain | head -5 | tr '\n' ' ')"
fi

if git diff --quiet "$base" HEAD && [ -z "$(git status --porcelain)" ]; then
  echo "gates: the document step changed nothing; there is nothing to gate and no pull request to open"
  exit 0
fi

# --- guards -------------------------------------------------------------------------------------

allowed() {
  local path=$1 entry
  for entry in "${ALLOWED[@]}"; do
    case $entry in
      */) [ "${path#"$entry"}" != "$path" ] && return 0 ;;
      *) [ "$path" = "$entry" ] && return 0 ;;
    esac
  done
  return 1
}
outside=
while IFS= read -r path; do
  [ -n "$path" ] || continue
  allowed "$path" || outside=${outside:+$outside }$path
done < <(git diff --name-only "$base")
if [ -n "$outside" ]; then
  problem "gates: the change reaches outside ${ALLOWED[*]}: $outside. This pipeline's pull request holds pages and glossary only: put those paths back as $base has them (\`git checkout $base -- <path>\`, or \`git rm\` a new one), commit, and leave what they should say as a handoff note"
fi

# fm_commit <key> [<commit>:]<page>: the value of a frontmatter key, from the worktree or a commit.
fm_commit() {
  { case $2 in *:*) git show "$2" 2> /dev/null ;; *) cat "$2" 2> /dev/null ;; esac; } | awk -v key="$1" '
    $0 == "---" { if (++fences == 2) exit; next }
    fences == 0 { exit }
    index($0, key ":") == 1 { v = $0; sub(/^[^:]*:/, "", v); gsub(/[[:space:]"]/, "", v); print v; exit }'
}

if [ -n "$PAGES_DIR" ]; then
  while IFS= read -r page; do
    [ -n "$page" ] && [ -f "$page" ] || continue
    case $(basename "$page") in _*) continue ;; esac
    for key in source_commit verified_commit; do
      now=$(fm_commit "$key" "$page")
      if git cat-file -e "$base:$page" 2> /dev/null; then
        was=$(fm_commit "$key" "$base:$page")
        if [ "$now" != "$was" ]; then
          problem "gates: $page: \`$key\` was moved (${was:-absent} -> ${now:-absent}). A lane never moves a drift pin: put the line back as \`git show $base:$page\` has it and commit. A page you read and found still holding goes in the record \`stale-pages.md\`, and the \`pin\` step moves its pin after the handover"
        fi
      elif [ -n "$now" ] && ! git merge-base --is-ancestor "$now" "$base" 2> /dev/null; then
        problem "gates: $page is new and its \`$key\` is $now, which the base of this branch does not hold. The handover squashes this task's commits into one, so a commit made here is gone by then: write \`$key: $base\`"
      elif [ -z "$now" ] && [ "$key" = source_commit ]; then
        problem "gates: $page is new and carries no \`source_commit\`: write \`source_commit: $base\`"
      fi
    done
  done < <(git diff --name-only "$base" -- "$PAGES_DIR")
fi

# --- the gates ----------------------------------------------------------------------------------

if [ "${#GATES[@]}" -eq 0 ]; then
  echo "gates: no gate command is written in GATES of scripts/spoolway/materializing-gates.sh; the guards and the pages decide alone"
else
  echo "gates: ${GATES[*]}"
  rc=0
  out=$("${GATES[@]}" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" | tail -40
    problem "gates: \`${GATES[*]}\` is RED (exit $rc). Run it yourself to see every finding; its last lines:
$(printf '%s\n' "$out" | tail -40)"
  fi
fi

# --- the pages ----------------------------------------------------------------------------------

if [ -n "$PAGES_DIR" ]; then
  rc=0
  out=$("$here/pins.sh" check all 2>&1) || rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -ne 0 ]; then
    problem "gates: the drift-pin check is RED and the record does not answer for it. \`scripts/spoolway/pins.sh status all\` prints this again:
$(printf '%s\n' "$out" | grep -E '^(check|ENVIRONMENT): ' || true)"
  fi
fi

finish
