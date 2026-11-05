#!/usr/bin/env bash
# The `checks` step of the Developing pipeline: what CI runs on a pull request here, in the
# task's worktree. tests/spoolway-developing.test.sh fails when the commands between the two
# `gates` markers below and those of the Gates job in .github/workflows/ci.yml differ:
# change both together. Same name in every consumer; only the body differs.
# Exit 0 passes the step, anything else sends the task back to `implement`.
#
# This repository has no pages, no package manager and no extra repository: its checks are the
# machine-keys gate (a lane cap or price row `spoolway sync` wrote into the tracked config is red),
# the harness tests and the validity of the pipelines it carries.
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

for tool in bash git jq sha256sum spoolway; do
  if ! command -v "$tool" > /dev/null; then
    echo "ENVIRONMENT: $tool is not on PATH; the checks cannot run" >&2
    exit 1
  fi
done

# Nothing from the dispatcher's environment: CI has none of it, and the tests make their own.
unset "${!SPOOLWAY_@}"

# gates: begin
scripts/gates/run.sh machine-keys
for t in tests/*.test.sh; do bash "$t"; done
timeout 120 spoolway pipeline check < /dev/null
# gates: end
