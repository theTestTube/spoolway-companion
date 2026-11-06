#!/usr/bin/env bash
# The `extra-handover` step of the Developing pipeline: in a consumer with extra repositories it
# opens the pull request of each extra repository the task names.
# This repository has none, so the step passes at once. A task whose `repos` names more than one
# repository is a mistake here and blocks, so no extra pull request is silently skipped.
# Exit 0 passes the step, anything else blocks the task.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

no_arguments extra-handover "$@"
own_step extra-handover

if ! step_skipped "${SPOOLWAY_TASK_FILE:-}" extra-handover \
  && [ "$(frontmatter_list "${SPOOLWAY_TASK_FILE:-}" repos | grep -c .)" -gt 1 ]; then
  echo "ENVIRONMENT: the task's \`repos\` names more than one repository, and this repository has no extra one to act on; take the others out of \`repos\` or queue the task in their own project" >&2
  exit 1
fi
echo "extra-handover: this repository has no extra repository, passing at once"
