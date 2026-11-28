
## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

Another session got stuck on the task. Find out why and resolve the issue.
Make the task finish the pipeline without skipping important steps.

## Never

- Merging or landing anything.
- Stopping the dispatcher. It is the process running you.
