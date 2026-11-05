#!/usr/bin/env bash
# The helper of the `dod` lane: what the lane cannot do by judgment alone.
# The lane runs it; it is not a step's `run:`. It reads and edits one issue through `gh`, and
# nothing else.
#
#   dod.sh criteria <issue>             the issue's checkboxes: `N<TAB>[ ]|[x]<TAB>text`, N counting
#                                       every checkbox of the body from 1
#   dod.sh questions <plan.json>        the questions the person is asked, as a JSON array: ONE batch
#                                       question for every criterion the harness proved, then ONE
#                                       question for each criterion only the person can judge and
#                                       for each handoff note (`needs a person:`, `for a person:`)
#   dod.sh apply <issue> <results.json> <task> <run>
#                                       ticks the criteria answered `met`, reads the body back and
#                                       fails on any difference but those boxes, posts the evidence
#                                       in ONE new comment, and exits 1 unless every checkbox of
#                                       the issue is ticked afterwards
#
# plan.json:    [{"n":1,"kind":"harness"|"person","text":"…","command":"…","output":"…"},
#                {"kind":"note","text":"needs a person: …"}]
# results.json: [{"n":1,"verdict":"met"|"not-met","by":"harness"|"<person>","command":"…","output":"…","answer":"…"}]
#
# No existing comment is ever edited; the body edit is the checkboxes and nothing else.
set -euo pipefail

die() { echo "dod: $*" >&2; exit 1; }
command -v gh > /dev/null && command -v jq > /dev/null || { echo "ENVIRONMENT: gh and jq must be on PATH" >&2; exit 1; }

# boxes <body-file>: `N<TAB>state<TAB>text` for each checkbox line.
boxes() {
  awk '/^[ \t]*[-*] \[[ xX]\] / {
    n++; l = $0; s = (l ~ /^[ \t]*[-*] \[ \]/) ? "[ ]" : "[x]"
    sub(/^[ \t]*[-*] \[[ xX]\] /, "", l); printf "%d\t%s\t%s\n", n, s, l }' "$1"
}

# read_body <issue> <file>: the body byte for byte as GitHub stores it. `--jq .body` would add a
# newline, so the JSON is decoded with `jq -j`, which prints the string and nothing else.
read_body() { gh issue view "$1" --json body | jq -j .body > "$2"; }

mode=${1:-}
[ $# -gt 0 ] && shift
case "$mode" in
  criteria)
    [ $# -eq 1 ] || die "usage: dod.sh criteria <issue>"
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    read_body "$1" "$tmp"
    boxes "$tmp"
    ;;

  questions)
    [ $# -eq 1 ] && [ -f "$1" ] || die "usage: dod.sh questions <plan.json>"
    jq '
      def proof: "\(.n). \(.text)\n   command: \(.command)\n   output:\n\(.output | split("\n") | map("     " + .) | join("\n"))";
      ([.[] | select(.kind == "harness")]) as $h
      | (if ($h | length) > 0 then [{
          kind: "batch",
          question: ("The harness proved these criteria. Accept them all?\n\n" + ($h | map(proof) | join("\n\n"))),
          options: ["Accept all", "Review them one by one"]
        }] else [] end)
        + [.[] | select(.kind == "person") | {kind: "individual", n: .n, question: "\(.n). \(.text)\nIs this criterion met?", options: ["Met", "Not met"]}]
        + [.[] | select(.kind == "note") | {kind: "note", question: .text, options: ["Done", "Not done"]}]
    ' "$1"
    ;;

  apply)
    [ $# -eq 4 ] && [ -f "$2" ] || die "usage: dod.sh apply <issue> <results.json> <task> <run>"
    issue=$1 results=$2 task=$3 run=$4
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    read_body "$issue" "$tmp/before"
    mapfile -t met < <(jq -r '.[] | select(.verdict == "met") | .n' "$results")
    # Expected body: the before body with exactly the met boxes ticked.
    awk -v list="${met[*]:-}" '
      BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
      /^[ \t]*[-*] \[[ xX]\] / { k++; if (want[k] && $0 ~ /^[ \t]*[-*] \[ \]/) sub(/\[ \]/, "[x]") }
      { print }
    ' "$tmp/before" > "$tmp/after"
    # awk ends every line with a newline; a body GitHub stores without one keeps it that way.
    [ -z "$(tail -c1 "$tmp/before")" ] || truncate -s -1 "$tmp/after"
    if ! cmp -s "$tmp/before" "$tmp/after"; then
      gh issue edit "$issue" --body-file "$tmp/after" > /dev/null
      read_body "$issue" "$tmp/readback"
      if ! cmp -s "$tmp/after" "$tmp/readback"; then
        diff "$tmp/after" "$tmp/readback" >&2 || true
        die "the issue body read back differs from what was written beyond the ticked boxes; nothing else was changed by this script"
      fi
    fi
    # The evidence: one new comment, verbatim.
    jq -r --arg title "## Definition of done — $task · $run" '
      $title + "\n\n" + (map(
        "### Criterion \(.n)\n\n" +
        (if .text then .text + "\n\n" else "" end) +
        "verified by: \(.by)\nverdict: \(.verdict)\n" +
        (if (.command // "") != "" then "\ncommand:\n\n```\n\(.command)\n```\n\noutput:\n\n```\n\(.output // "")\n```\n" else "" end) +
        (if (.answer // "") != "" then "\nanswer: \(.answer)\n" else "" end)
      ) | join("\n"))' "$results" > "$tmp/comment"
    gh issue comment "$issue" --body-file "$tmp/comment" > /dev/null
    read_body "$issue" "$tmp/final"
    unticked=$(boxes "$tmp/final" | awk -F'\t' '$2 == "[ ]" { print "  " $1 ". " $3 }')
    if [ -n "$unticked" ]; then
      printf 'dod: criteria still unticked:\n%s\n' "$unticked" >&2
      exit 1
    fi
    echo "dod: every criterion is ticked"
    ;;

  *) die "usage: dod.sh criteria|questions|apply" ;;
esac
