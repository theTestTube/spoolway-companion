#!/usr/bin/env bash
# Shipped with the Materializing pipeline in this plugin's types, at the revision
# .spoolway/plugin.lock records: a retake rewrites it, so it carries no project's specifics. What
# differs between consumers is read from .spoolway/companion.env.
#
# The `bind` step of the Materializing pipeline: refuses a task that is not bound to an open spec,
# or that would let a merge close it. Same name in every consumer.
#
# A Materializing task is bound to its spec by `ticket:`, and a spec outlives its task: it closes
# when its tickets are done, not when one pull request merges. The issue hook withholds the
# closing label only when the task document says `close_on_merge: false`, and spoolway never
# validates a pass-through key, so a task queued without it is stopped here, before any lane has
# spent anything.
# Exit 0 passes the step, anything else blocks the task.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments bind "$@"
own_step bind

task_file=$SPOOLWAY_TASK_FILE

if step_skipped "$task_file" bind; then
  echo "bind: \`skip_steps\` names \`bind\`, and this step is never skipped: a spec without \`close_on_merge: false\` is closed by a merge. Take \`bind\` out of \`skip_steps\` in the task file with the dispatcher stopped, then resume" >&2
  exit 1
fi

if ! command -v gh > /dev/null; then
  echo "ENVIRONMENT: gh is not on PATH; the spec's state cannot be read" >&2
  exit 1
fi

fix="Add it to the task file's frontmatter with the dispatcher stopped, then resume"
ticket=$(frontmatter_value "$task_file" ticket)
if ! issue_url "$ticket"; then
  echo "bind: \`ticket:\` is \"$ticket\", not the full URL of the spec's issue (https://github.com/<owner>/<repo>/issues/<n>). $fix" >&2
  exit 1
fi
close=$(frontmatter_value "$task_file" close_on_merge | tr '[:upper:]' '[:lower:]')
if [ "$close" != false ]; then
  echo "bind: the task is bound to the spec $ticket without \`close_on_merge: false\`, so a merged pull request of this task would close the spec. $fix" >&2
  exit 1
fi
if ! state=$(gh issue view "$ticket" --json state --jq .state 2>&1); then
  echo "ENVIRONMENT: bind: could not read the spec $ticket: $state" >&2
  exit 1
fi
if [ "$state" != OPEN ]; then
  echo "bind: the spec $ticket is $state, not OPEN. A closed spec is not materialized: reopen it or unqueue this task" >&2
  exit 1
fi
echo "bind: bound to the open spec $ticket, which stays open when this task ends"
