#!/usr/bin/env bash
# The `handover` step of the Developing pipeline: `spoolway stack` opens this task's pull
# request, then the attribution trailer it appends is taken off the body and, for a task that
# waits on another project, what it waits on is written at the top. Same name in every
# consumer; this one has no extra repository to wait for.
#
# spoolway squashes to one commit whose message is the task's `title:` alone, and ends every
# pull request body with the line `Co-Authored-By: Claude Code`, which the pipeline's rule of no
# AI attribution anywhere cannot allow. Nothing configures it, so it is removed here.
#
# The pull request body is the task body, which never carries the frontmatter. A dependent task
# records what it waits on in `requires:`, so the reviewer would not see it: it is rendered
# here as a `## Waits on` section, unless the body has one already. A person keeps the order;
# nothing here checks the other pull request's state.
#
# A branch with no pull request after `stack` (an empty diff opens none) fails the step: the issue
# hook finds the pull request by branch, and without one reports "finished with no pull request".
# A task that should end that way names `handover` in `skip_steps`.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments handover "$@"
own_step handover

if step_skipped "${SPOOLWAY_TASK_FILE:-}" handover; then
  echo "handover: named in skip_steps, passing at once"
  exit 0
fi

cd "$root"

# The task title is the squashed commit's subject and the pull request's title, and
# nothing validates it at queue time.
if [ -n "${SPOOLWAY_TASK_FILE:-}" ]; then
  if ! title=$(frontmatter_value "$SPOOLWAY_TASK_FILE" title); then
    echo "handover: the task title cannot be read (above). Nothing was pushed. Stop the dispatcher, fix \`title:\` in the task file or unqueue and requeue it, then resume" >&2
    exit 1
  fi
  if ! why=$(conventional_title "$title"); then
    echo "handover: the task title \"$title\" is $why. Nothing was pushed. Stop the dispatcher, fix \`title:\` in the task file or unqueue and requeue it, then resume" >&2
    exit 1
  fi
fi

# The pull request body is the task body, notes from the lanes included. GitHub reads "close #N"
# as a closing reference even when a note negates it, and a merge then closes an issue nobody
# meant to close: refuse before anything is pushed. Part of #N and "leaves #N open" are fine.
if [ -n "${SPOOLWAY_TASK_FILE:-}" ] && lines=$(closing_keywords "$SPOOLWAY_TASK_FILE"); then
  echo "handover: the task body has a closing keyword before an issue; GitHub would close it on merge, whatever the sentence says. Nothing was pushed. Rewrite these lines (\`part of #N\`, \`leaves #N open\`) in the task file with the dispatcher stopped, then resume:" >&2
  printf '%s\n' "$lines" >&2
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)

spoolway stack

number=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')
if [ -z "$number" ]; then
  echo "handover: no pull request open on $branch after \`spoolway stack\`" >&2
  exit 1
fi

# What GitHub itself parsed has the last word: a closing reference to anything but nothing fails
# the step, with the pull request already open for the person to correct.
closing=$(gh pr view "$number" --json closingIssuesReferences --jq '[.closingIssuesReferences[].number | "#\(.)"] | join(" ")')
if [ -n "$closing" ]; then
  echo "handover: pull request #$number would close $closing on merge; edit its body to remove the closing keyword, then resume" >&2
  exit 1
fi

# Read the whole body first, change only its trailer and its waits-on section, and write the
# result back whole.
body=$(mktemp)
trap 'rm -f "$body" "$body.new"' EXIT
gh pr view "$number" --json body --jq .body > "$body"

requires=
[ -n "${SPOOLWAY_TASK_FILE:-}" ] && requires=$(frontmatter_value "$SPOOLWAY_TASK_FILE" requires)
{
  if [ -n "$requires" ] && ! grep -q '^## Waits on' "$body"; then
    printf '## Waits on\n\n%s\n\nThis pull request depends on work in another project. A person keeps the order: merge it only once that work is merged.\n\n' "$requires"
  fi
  strip_ai_trailer < "$body"
} > "$body.new"

if [ "$(cat "$body")" = "$(cat "$body.new")" ]; then
  echo "handover: pull request #$number needs no change to its body"
  exit 0
fi

gh pr edit "$number" --body-file "$body.new"
echo "handover: rewrote the body of pull request #$number"
