#!/usr/bin/env bash
# The lane environment, inferred from the worktree path.
#
# A lane started by the dispatcher is handed SPOOLWAY_TASK, SPOOLWAY_TASK_FILE, SPOOLWAY_SCRATCH,
# SPOOLWAY_WORKTREE and SPOOLWAY_REPO. A lane resumed after a dispatcher restart, a reboot or a
# usage-limit stop can lose them, and an empty SPOOLWAY_SCRATCH resolves to `/`. The worktree is
# `<home>/worktrees/task-<id>`; the task file, the scratch space and the project's root are read
# from there.
#
# Source it to set the variables in the current shell, which guards every later use:
#
#   . scripts/spoolway/lane-env.sh || exit 1
#
# Run it to print them, to `eval`:
#
#   eval "$(scripts/spoolway/lane-env.sh)"
#
# `lane-env.sh scratch` prints the task's scratch space, `task` the task id and `task-file` the
# task file. Every form fails, printing nothing, when the current directory is not a lane worktree
# or the task file is missing.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

# Sourced: set the variables in the caller's shell. Executed: print them, or one of them.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _lane_env=$(lane_env) || return 1
  eval "$_lane_env"
  unset _lane_env
  return 0
fi

set -euo pipefail
case ${1:-env} in
  env) lane_env ;;
  scratch) lane_scratch ;;
  task) lane_id ;;
  task-file) lane_task_file ;;
  *) echo "lane-env: unknown argument \`$1\`; use env, scratch, task or task-file" >&2; exit 64 ;;
esac
