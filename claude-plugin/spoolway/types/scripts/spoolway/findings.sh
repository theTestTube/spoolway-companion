#!/usr/bin/env bash
# Findings: what a run noticed about the product and its documents that does not
# belong to its own issue goes out as one comment on the project's weekly digest issue, where a
# Feeding-back batch reads it. Run by the `report` lane of the Materializing pipeline. The
# digest's repository is FINDINGS_REPO, from the environment or `.spoolway/companion.env`, else
# the run's own repository.
#
#   findings.sh write    reads `findings.md` in the task's scratch space, keeps what is admitted,
#                        and writes it as one comment per run on the digest issue.
#
# The lane writes each finding as a block:
#
#   ## <the finding, one line>
#   - class: bug | enhancement
#   - evidence: <a file and line, a command with its output, or an internal issue link>
#   - where: <the task, issue or pull request it was seen in>
#   - type: Architecting | Materializing | Developing
#   - priority: <a suggested priority, such as P1-high, or none>
#
# A finding without evidence is dropped, as at the backing gate, and so is one with a field
# missing or out of its values. At most five are written, in the order given: the lane puts the
# most severe first. A run with none writes no comment.
#
# The digest issue is the open issue of that repository whose title starts with
# "weekly digest". Feeding-back opens it, or a person does. This script opens no
# issue: with no digest open it says so and exits 3, and the lane leaves the findings in its
# handoff.
#
# Exit codes: 0 written, already written for this run, or nothing to write; 2 the tracker
# refused; 3 no digest issue is open.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

DIGEST_REPO=
MAX_FINDINGS=5

[ "${1:-}" = write ] || { echo "usage: findings.sh write" >&2; exit 64; }

task_file=${SPOOLWAY_TASK_FILE:-}
if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
  echo "findings: SPOOLWAY_TASK_FILE names no task file" >&2
  exit 64
fi
task=${SPOOLWAY_TASK:-$(frontmatter_value "$task_file" id)}
scratch=$(task_scratch "$task_file")
run=$(frontmatter_value "$task_file" run)
run=${run:-$task}
source_file=$scratch/findings.md
written=$scratch/findings.$run.url
marker="<!-- spoolway-findings: $run -->"

if [ -s "$written" ]; then
  echo "findings: already written for run $run: $(cat "$written")"
  exit 0
fi
if [ ! -s "$source_file" ]; then
  echo "findings: no findings.md; nothing to write"
  exit 0
fi

mkdir -p "$scratch"
body=$scratch/findings.body.md
# One pass: a block is admitted when its five fields are there and within their values. Admitted
# blocks past the fifth are counted, never written.
summary=$(awk -v max="$MAX_FINDINGS" -v out="$body.blocks" '
  function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
  function flush(   why) {
    if (title == "") return
    why = ""
    if (class != "bug" && class != "enhancement") why = "class is neither bug nor enhancement"
    else if (evidence == "") why = "no evidence"
    else if (where == "") why = "no place it was seen"
    else if (type != "Architecting" && type != "Materializing" && type != "Developing") why = "type is none of Architecting, Materializing, Developing"
    else if (priority == "") why = "no suggested priority"
    if (why != "") { dropped++; printf "findings: dropped (%s): %s\n", why, title > "/dev/stderr" }
    else if (kept >= max) { over++; printf "findings: not written, past the limit of %d: %s\n", max, title > "/dev/stderr" }
    else {
      kept++
      printf "### %s\n\n- Class: `%s`\n- Evidence: %s\n- Seen in: %s\n- Suggested type: %s\n- Suggested priority: %s\n\n", title, class, evidence, where, type, priority > out
    }
    title = ""
  }
  BEGIN { printf "" > out }
  /^## / { flush(); title = trim(substr($0, 4)); class = evidence = where = type = priority = ""; next }
  title != "" && /^[ \t]*-[ \t]*[a-z]+:/ {
    line = $0; sub(/^[ \t]*-[ \t]*/, "", line)
    key = line; sub(/:.*$/, "", key)
    value = trim(substr(line, length(key) + 2))
    if (key == "class") class = tolower(value)
    else if (key == "evidence") evidence = value
    else if (key == "where") where = value
    else if (key == "type") type = value
    else if (key == "priority") priority = value
  }
  END { flush(); printf "%d %d %d\n", kept, dropped, over }
' "$source_file")
kept=${summary%% *}
if [ "$kept" -eq 0 ]; then
  rm -f "$body.blocks"
  echo "findings: none admitted; nothing to write"
  exit 0
fi

# The digest: the newest open issue whose title starts with "weekly digest", in any letter case.
# Only what the tracker printed is an answer: its warnings go to a file, never into the URL.
err=$scratch/findings.err
DIGEST_REPO=$(companion_env FINDINGS_REPO)
if [ -z "$DIGEST_REPO" ] && ! DIGEST_REPO=$(cd "${SPOOLWAY_REPO:-.}" && gh repo view --json nameWithOwner --jq .nameWithOwner 2> "$err"); then
  echo "REFUSED: cannot tell which repository holds the weekly digest: set FINDINGS_REPO or run inside a GitHub checkout gh can read: $(cat "$err")" >&2
  exit 2
fi
if ! digest=$(gh issue list --repo "$DIGEST_REPO" --state open --search "weekly digest in:title sort:created-desc" --json url,title \
  --jq '[.[] | select(.title | ascii_downcase | startswith("weekly digest"))][0].url // empty' 2> "$err"); then
  echo "REFUSED: could not read $DIGEST_REPO to find the weekly digest issue: $(cat "$err")" >&2
  exit 2
fi
if [ -z "$digest" ]; then
  echo "NO DIGEST: $DIGEST_REPO has no open issue whose title starts with \"weekly digest\"; nothing was written" >&2
  exit 3
fi

# Exactly one comment per run: the marker file above, then the digest's own comments.
number=${digest##*/}
if ! existing=$(gh api "repos/$DIGEST_REPO/issues/$number/comments" --paginate \
  --jq ".[] | select(.body | contains(\"$marker\")) | .html_url" 2> "$err"); then
  echo "REFUSED: could not read the comments of $digest: $(cat "$err")" >&2
  exit 2
fi
existing=$(printf '%s\n' "$existing" | grep -E '^https://github\.com/' | head -1 || true)
if [ -n "$existing" ]; then
  echo "$existing" > "$written"
  rm -f "$body.blocks"
  echo "findings: already written for run $run: $existing"
  exit 0
fi

{
  echo "## Findings of run \`$run\`"
  echo
  echo "- Pipeline: \`$(frontmatter_value "$task_file" pipeline)\`"
  echo "- Task: \`$task\`"
  # In a code span: a bare URL would write a cross-reference on the work issue's timeline.
  echo "- Bound to: \`$(frontmatter_value "$task_file" ticket)\`"
  echo
  cat "$body.blocks"
  echo "$marker"
} > "$body"
rm -f "$body.blocks"

if ! url=$(gh issue comment "$digest" --body-file "$body" 2> "$err"); then
  echo "REFUSED: $digest did not take the findings: $(cat "$err")" >&2
  exit 2
fi
url=$(printf '%s\n' "$url" | grep -Eo 'https://github\.com/[^[:space:]]+' | tail -1 || true)
echo "${url:-$digest}" > "$written"
echo "findings: wrote $kept finding(s) on ${url:-$digest}"
