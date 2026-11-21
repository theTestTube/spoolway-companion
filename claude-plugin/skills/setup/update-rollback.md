# Going back

Reached from step 1 of "A spoolway update" when the To-Be is older than the As-Is. A rollback is a flight forward: the dispatcher and the lanes already hold the newer binary, tracked files and queued task documents were written by it, and the older one may not read them. The binary belongs to the machine, so the rollback reaches every project the machine dispatches, not only this checkout.

Steps 2 and 3 run as written, with the older binary as the probe: what it refuses on this checkout is what the rollback breaks. This file replaces steps 4 and 5. Nothing destructive runs before the person's opt-in (R4).

Vocabulary and consent follow `spoolway-repair`: **salvage** is copying what a teardown would destroy; **the person's word** is a yes to the exact command shown; the rollback is a **one-way door**.

## R1. List what runs under the As-Is

Every project home under `~/.spoolway/` that has a `project.toml` records its checkout there (`root`). `setup.sh queue-snapshot` runs `spoolway queue list --json -C <checkout>` with the As-Is binary for each and prints every task with its state, lane, branch and unpushed commits. A home whose checkout is gone is named `unreadable` and left.

For each task that is queued, started or parked: its id, project, group, stage and step, whether a lane is running it, its worktree and branch, its commits that origin lacks, and what its working tree holds uncommitted.

Read what an unqueue does from `spoolway queue unqueue --help` of the As-Is binary, and write it beside the list: which tasks it takes with this one (the ones after it in its group), what it deletes (worktree, local branch), and whether it commits first. A task that never started has nothing to lose.

Done when every project home that has a `project.toml` is listed or named as unreadable, every task has its row, and each row says what its unqueue destroys.

## R2. Salvage

For each started task, `setup.sh salvage <task>` copies what its unqueue would delete into `./.scratch/salvage-<task>/`: the diff of tracked files, the untracked files, the command logs, the scratch space, and the commits origin lacks as a bundle, which it checks with `git bundle verify` (a `bundle` line says `verified`, or `none` when no commit is missing). Check each copy by name and size.

Pushing the branch is the person's: name it as a `to do:` line per branch (commit what the worktree holds, then push), and confirm with `git ls-remote --heads origin task/<id>` that origin holds the tip.

Done when every started task has a verified salvage copy, and each branch is either confirmed on origin or covered by a verified bundle.

## R3. Propose the unqueue

Show, per task and in group order: `queue pause <task>` when a lane runs it, then `queue unqueue <task>`, each exact command with what it destroys and what else it moves. Run none yet.

Done when each task has its proposed commands shown.

## R4. The opt-in

The person's opt-in is a sentence of their own that names the To-Be, says they accept an abrupt rollback, and names what stays running or queued under it. A bare yes to "shall I continue" does not count. Without that sentence, stop: leave the list, the salvage and the proposals in `<dir>`, and say that nothing was changed.

Done when the opt-in sentence is quoted in the answer, or the answer says "stopped before any rollback step". No `queue pause` or `queue unqueue` has run before it.

## R5. Unqueue, then the person's steps

With the opt-in, run each command of R3 with the As-Is binary on the person's word for that command, before anything is installed. A task whose unqueue the person declines is named as left standing under a binary that did not write its state, and that sentence is part of what the opt-in accepted.

Then give the `to do:` lines of the rollback, in this order:

1. stop the dispatcher and any lane still running under the As-Is
2. install the older binary (the probe's asset and hash check)
3. revert the tracked files the newer sync wrote (`git revert` of its commit, reviewed in a pull request): an older binary refuses a config a newer one wrote. A migration of the machine's override layer may not be reversible; say which entries the older binary reads wrong, from `override list`
4. start the dispatcher, then `spoolway dispatch reload` once the revert has merged
5. queue the unqueued tasks again, on the person's word, after `git ls-remote` shows their branches absent from origin

Done when every task is unqueued or named as declined, every `to do:` line stands in that order, and the consequences the person accepted are listed beside it.

## R6. Verify

When the person says the older binary is installed, run `--version`, `pipeline check` and `doctor --no-live`, save them under `<dir>/after/`, and compare them with the probe's outputs of step 2.

Done when each output equals its probe counterpart, or each difference is named with its cause.
