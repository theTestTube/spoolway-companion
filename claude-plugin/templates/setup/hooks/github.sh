#!/bin/sh
# Written once by `spoolway init`, then yours: a template the companion never updates; `spoolway update` never
# touches it. Called with `open` as a document with no `ticket:` is queued,
# `fetch` when someone runs `spoolway issue show`, then on queued, blocked,
# paused and done.
#
# spoolway-requires: gh >= 2.97.0
# spoolway-login: gh auth status
#
# A task is bound to the issue it was queued against: its
# `ticket:` is that issue, a full URL when it lives in another repository.
# This hook never opens an issue. It writes three labels and no other:
# `spoolway:in-progress`, `spoolway:review`, and `spoolway:task`, the label
# `.github/workflows/spoolway-issues.yml` requires before it closes an issue
# on merge. Triage labels are read, never written.
#
# The closing label is withheld, so a merge leaves the issue open, when the
# task document's frontmatter says `close_on_merge: false` (a spec), when the
# issue carries `wayfinder:map` or `ready-for-human`, or when the issue lives
# in another repository than the pull request.
#
# The hook treats GitHub as a mirror: failures are reported back to spoolway,
# while config decides whether they should pause delivery.

code_repo=$SPOOLWAY_PROJECT_KEY           # `[issue_tracking] project_key`: where pull requests live

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# An issue reference, split into the repository that owns it and its number:
# a full issue URL names its own repository, a bare number or `#number` is an
# issue of `$code_repo`. Sets `ticket_repo`, `ticket_number`, `ticket_url`.
resolve_ticket() {
  case "$1" in
    https://github.com/*/*/issues/[0-9]*)
      ticket_repo=${1#https://github.com/}
      ticket_number=${ticket_repo##*/issues/}
      ticket_number=${ticket_number%%[!0-9]*}
      ticket_repo=${ticket_repo%%/issues/*}
      ;;
    *)
      ticket_repo=$code_repo
      ticket_number=${1#'#'}
      ;;
  esac
  case "$ticket_repo" in
    */*/*|/*|*/|'') ticket_number= ;;
    */*) ;;
    *) ticket_number= ;;
  esac
  case "$ticket_number" in
    ''|*[!0-9]*)
      echo "github.sh: not an issue reference: $1" >&2
      return 1
      ;;
  esac
  ticket_url=https://github.com/$ticket_repo/issues/$ticket_number
}

# Where the task document is right now, or nothing. `done` fires in the same
# dispatcher pass that archives the task, so by the time this hook reads the
# document it may have moved from `queue/` to `archive/` beside it.
task_document() {
  [ -n "$SPOOLWAY_TASK_FILE" ] || return 0
  if [ -f "$SPOOLWAY_TASK_FILE" ]; then
    printf '%s\n' "$SPOOLWAY_TASK_FILE"
    return 0
  fi
  archived=$(dirname "$(dirname "$SPOOLWAY_TASK_FILE")")/archive/$(basename "$SPOOLWAY_TASK_FILE")
  [ -f "$archived" ] && printf '%s\n' "$archived"
  return 0
}

# One section's own content out of a task file, matching the boundary rule
# `Task::find_section` uses in src/task.rs: a line equal to `heading` (case
# folded, trailing space trimmed) starts it, and it ends at the next line
# whose own leading `#`s number 1 through heading's own level — a
# sub-heading nested deeper stays inside the section instead of ending it.
# Leading and trailing blank lines are trimmed off what is printed. Prints
# nothing at all for a missing section, a missing file, or a blank
# `$SPOOLWAY_TASK_FILE` — the `open` event may carry the empty string there
# for a document with no file of its own (see `tracking.rs`'s own doc on
# `open_env`).
extract_section() {
  file=$1
  heading=$2
  [ -n "$file" ] && [ -f "$file" ] || return 0
  awk -v heading="$heading" '
    function hashes(l,    n) {
      n = 0
      while (substr(l, n + 1, 1) == "#") n++
      return n
    }
    BEGIN { level = hashes(heading); found = 0; n = 0 }
    {
      line = $0
      sub(/[ \t\r]+$/, "", line)
      if (!found) {
        if (tolower(line) == tolower(heading)) found = 1
        next
      }
      lvl = hashes(line)
      if (lvl > 0 && lvl <= level) exit
      buf[++n] = line
    }
    END {
      start = 1
      while (start <= n && buf[start] == "") start++
      last = n
      while (last >= start && buf[last] == "") last--
      for (i = start; i <= last; i++) print buf[i]
    }
  ' "$file"
}

# `heading` and its content from `$SPOOLWAY_TASK_FILE`, tight against its
# heading: `## Status Log` and `## Handoff` are already bulleted lists in the
# document, with no blank line under the heading, and a comment reproduces
# that instead of inventing one. Nothing when the document has no such section.
comment_section() {
  content=$(extract_section "$(task_document)" "$1")
  [ -n "$content" ] && printf '%s\n%s\n\n' "$1" "$content"
}

# One frontmatter value out of a task document, unquoted; nothing for a
# missing key or a document with no frontmatter.
frontmatter() {
  awk -v key="$1" '
    NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
    /^---[ \t\r]*$/ { exit }
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/[ \t]+#.*$/, "", value)
      gsub(/^[ \t"\047]+|[ \t\r"\047]+$/, "", value)
      print value
      exit
    }
  ' "$2"
}

# Whether a merge of the task's pull request should close the ticket. The
# issue's labels are read here and nowhere else. A document that cannot be
# read cannot say `close_on_merge: false`, so it closes nothing: an issue left
# open by mistake costs a click, a spec closed by mistake loses its slices.
closes_on_merge() {
  [ "$(lower "$ticket_repo")" = "$(lower "$code_repo")" ] || return 1
  document=$(task_document)
  if [ -z "$document" ]; then
    after="$after The task document could not be read, so the closing label was withheld."
    return 1
  fi
  [ "$(lower "$(frontmatter close_on_merge "$document")")" = false ] && return 1
  labels=$(gh issue view "$ticket_number" -R "$ticket_repo" \
    --json labels --jq '.labels[].name') || exit $?
  case "
$labels
" in
    *"
wayfinder:map
"*|*"
ready-for-human
"*) return 1 ;;
  esac
  return 0
}

# GitHub issues only have open/closed as native states. This label means the
# task has entered spoolway; blocked and paused are comments instead of state
# labels because spoolway has no matching event when either condition clears.
mark_in_progress() {
  gh issue edit "$ticket_number" -R "$ticket_repo" \
    --add-label spoolway:in-progress
}

# `done` means spoolway handed the task to a pull request, not that the change
# merged. Leave closure to GitHub's merge event: mark the issue for review and
# put a machine-readable issue marker on the PR for the repository workflow.
# A task whose pipeline opens no pull request ends here too: its issue leaves
# `spoolway:in-progress` and gains nothing.
hand_off_for_review() {
  pr=
  if [ -n "$SPOOLWAY_BRANCH" ]; then
    # `pr list` answers nothing, and exits 0, when the branch has no pull
    # request; a non-zero exit is a real failure, left for spoolway to retry.
    pr=$(gh pr list -R "$code_repo" --head "$SPOOLWAY_BRANCH" --state all \
      --json url --jq '.[0].url // empty') || exit $?
  fi
  if [ -z "$pr" ]; then
    gh issue edit "$ticket_number" -R "$ticket_repo" \
      --remove-label spoolway:in-progress || exit $?
    gh issue comment "$ticket_number" -R "$ticket_repo" --body \
      "**spoolway** — \`$SPOOLWAY_TASK\` finished with no pull request."
    return
  fi

  # Write the merge marker first: if a later cosmetic update fails under the
  # mirror's non-blocking `on_fail`, GitHub can still close the issue safely.
  gh pr comment "$pr" -R "$code_repo" --body \
    "**spoolway:** tracks $ticket_url

<!-- spoolway-issue: $ticket_url -->" || exit $?

  after="This issue stays open after the pull request merges."
  if closes_on_merge; then
    gh issue edit "$ticket_number" -R "$ticket_repo" \
      --remove-label spoolway:in-progress \
      --add-label spoolway:review --add-label spoolway:task || exit $?
    after="GitHub will close this issue after the pull request merges."
  else
    # `spoolway:task` exists where the workflow runs, so it can only be taken
    # off an issue of that repository.
    set -- gh issue edit "$ticket_number" -R "$ticket_repo" \
      --remove-label spoolway:in-progress --add-label spoolway:review
    [ "$(lower "$ticket_repo")" = "$(lower "$code_repo")" ] &&
      set -- "$@" --remove-label spoolway:task
    "$@" || exit $?
  fi

  gh issue comment "$ticket_number" -R "$ticket_repo" --body \
    "**spoolway** — \`$SPOOLWAY_TASK\` is ready for review in $pr. $after"
}

# A `blocked` or `paused` comment carries only what just changed — the log
# of steps taken and whatever the last one is handing forward — never the
# whole document behind it.
comment_snapshot() {
  {
    echo "**spoolway** — \`$SPOOLWAY_TASK\` is **$SPOOLWAY_EVENT** at \`$SPOOLWAY_FROM\`"
    echo
    comment_section "## Status Log"
    comment_section "## Handoff"
  } | gh issue comment "$ticket_number" -R "$ticket_repo" --body-file -
}

if [ "$SPOOLWAY_EVENT" = fetch ]; then
  resolve_ticket "$SPOOLWAY_REF" || exit 1
  gh issue view "$ticket_number" -R "$ticket_repo" \
    --json number,url,title,state,labels,body,comments \
    --jq '{ref: (.number | tostring), url, title, state: (.state | ascii_downcase),
           labels: [.labels[].name], body,
           comments: [.comments[] | {author: .author.login, body}]}' \
    > "$SPOOLWAY_OUT"
  exit 0
fi

# The weekly Feeding-back routine is a fixed file, so it carries no `ticket:`: its task binds
# to the one open "Weekly digest" issue of `$code_repo`, matched on the title prefix alone,
# case-folded (the way `scripts/spoolway/findings.sh` finds it). Any other number than one is
# a refusal, which queues nothing.
bind_weekly_digest() {
  digests=$(gh issue list -R "$code_repo" --state open --limit 100 \
    --search "weekly digest in:title" --json number,title \
    --jq '.[] | select(.title | ascii_downcase | startswith("weekly digest")) | .number') || return 1
  count=$(printf '%s\n' "$digests" | grep -c .) || count=0
  if [ "$count" -ne 1 ]; then
    if [ "$count" -eq 0 ]; then
      echo "github.sh: \`$SPOOLWAY_TASK\` is in group feeding-back-weekly but $code_repo has no open issue whose title starts with \"weekly digest\"" >&2
    else
      echo "github.sh: \`$SPOOLWAY_TASK\` is in group feeding-back-weekly but $code_repo has $count open weekly digests: $(printf '%s' "$digests" | sed 's/^/#/' | tr '\n' ' ')" >&2
    fi
    return 1
  fi
  resolve_ticket "$digests"
}

if [ "$SPOOLWAY_EVENT" = open ]; then
  if [ "${SPOOLWAY_GROUP:-}" = feeding-back-weekly ]; then
    bind_weekly_digest || exit 1
    { echo "ticket=$ticket_url"; echo "slug=gh-$ticket_number"
      echo "url=$ticket_url"; } > "$SPOOLWAY_OUT"
    exit 0
  fi
  # spoolway runs `open` only for a document with no `ticket:`. Nothing is
  # minted: the task binds to the issue its `source:` names, and a document
  # with no issue behind it is refused, which refuses its whole submission.
  case "$SPOOLWAY_SOURCE" in
    https://github.com/*/*/issues/[0-9]*) resolve_ticket "$SPOOLWAY_SOURCE" || exit 1 ;;
    *)
      echo "github.sh: \`$SPOOLWAY_TASK\` names no issue: set \`ticket:\` (or \`source:\`) to the URL of the issue it is queued against" >&2
      exit 1
      ;;
  esac
  # The short handle spoolway puts in generated names when `key_in_names` is
  # on, with a `gh-` prefix so the slug starts with a letter the way every
  # spoolway id does. No `epic=`: a group has no issue of its own.
  { echo "ticket=$ticket_url"; echo "slug=gh-$ticket_number"
    echo "url=$ticket_url"; } > "$SPOOLWAY_OUT"
  exit 0
fi

[ -n "$SPOOLWAY_TICKET" ] || exit 0
resolve_ticket "$SPOOLWAY_TICKET" || exit 1

case "$SPOOLWAY_EVENT" in
  queued)
    mark_in_progress
    ;;
  blocked)
    comment_snapshot
    ;;
  paused)
    comment_snapshot
    ;;
  done)
    hand_off_for_review
    ;;
esac
