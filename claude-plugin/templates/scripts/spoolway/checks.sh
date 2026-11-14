#!/usr/bin/env bash
# Written once by /spoolway-companion:setup from the companion's template, then yours: the
# companion never updates it; a later bump prints the template's changes for you to apply.
#
# The `checks` step of the Developing pipeline: what CI runs on a pull request, run in the
# task's worktree. Keep the lines between the two `gates` markers equal to your CI's.
# Same name in every consumer; only the body differs.
# Exit 0 passes the step, anything else sends the task back to `implement`.
#
# `ENVIRONMENT:` failures are not the implementer's to fix: the prompt tells it to block.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments checks "$@"
own_step checks

if step_skipped "${SPOOLWAY_TASK_FILE:-}" checks; then
  echo "checks: named in skip_steps, passing at once"
  exit 0
fi

cd "$root"

# Nothing from the dispatcher's environment: CI has none of it.
unset "${!SPOOLWAY_@}"

# gates: begin
@CHECKS@
# gates: end
