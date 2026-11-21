# Runs for a gap

Reached from step 4 of "A spoolway update". It takes the GAP findings of step 3 to drafts. A run is one pass of a task through its pipeline (GLOSSARY); a draft is the task document that would start it.

## Which run

Take the evidence of the finding to the first row it fits.

| Evidence | Run |
|---|---|
| A bounded fix in one repository: a script, a CI pin, documentation, a config key, a test fixture. Its acceptance criteria fit one list. | **Developing**: one task per repository and per class (before, after) |
| Fixes that split into independent pieces, each needing its own review: `pipeline check` refuses prompts in several pipelines, or one removed command is used across many scripts. | **Materializing**: one spec issue, and the tickets come out of it |
| A question the release notes leave open: a removed capability with several replacements, a new feature that would change the shape of a pipeline, a rewrite of a flow that moves or destroys work. | **Architecting**: the question is the task's input and the answer is a decision |
| Nothing to change, something to file: a no-hit breaking change that taught something, a defect in the companion's types or in this skill, a pre-existing failure the probe found, a feature left unadopted on purpose. | **Feeding-back** |

A removed or renamed flag that guarded a destructive command changes what the command does, not only its spelling. Rule it on what the replacement destroys, and send it to Architecting when the safe order of steps is not obvious.

Developing: take the pipeline the checkout runs for infrastructure work (`spoolway pipeline list`). When it has a review variant and the change touches a script that moves or destroys work, propose the review variant. Ask the person to rule between them.

The checkout may lack the pipeline or the task template a run needs (`.spoolway/types.subset`, `.spoolway/templates/tasks/`). Say so, and leave that run as text for the person to move to another checkout.

## Write the draft

1. Template: the one in the checkout's `.spoolway/templates/tasks/` that matches the pipeline. Every key comes from `spoolway task contract`, run with the To-Be binary (`<dir>/bin/spoolway`; `<dir>` is the skill's work folder).
2. Place: `<draft>`, which is `./.scratch/<issue>-<slug>/`. A run with no issue yet uses `new` for `<issue>`; rename the folder when the issue exists. Open an issue only on the person's word.
3. Id: no dots, and its branch is absent from origin: `setup.sh fresh-id <id>` prints `free` (it runs `git ls-remote --heads origin task/<id>`). Repeat that check immediately before any queue add, since a branch that outlives a merged pull request makes a release refuse the task.
4. Check: `timeout 60 <dir>/bin/spoolway task contract --from <draft> < /dev/null`. A **before** task also passes it under the As-Is binary, so it can be queued today.
5. Non-goals of every draft: installing a binary, a real `sync` by the lane, `spoolway dispatch reload`. A non-goal about a lock file or a baseline names what a legitimate tool writes there (for a companion pin, what `setup.sh bump` writes) as the exception.
6. An **after** task sets `gate_at` to the step before the person's `sync`, so the person takes the sync in the task's worktree at the pause. A task that moves a plugin pin lists the plugin update in the worktree and the restart as a `to do:` of the same pause.

## Order

1. **Before** tasks first, in dependency order.
2. The person's steps (step 5 of the skill).
3. **After** tasks.

A checkout whose types come from the companion waits on the companion's own run: its pin moves with "A bump" once that run's pull request has merged, and its task is queued after the merge. `requires:` is a key spoolway passes through and does not enforce, so the order is kept by when you queue.

Before any queue add, report each project's active overrides (`override list`) and what they change. Queue with `timeout <n> spoolway queue add --from <draft> < /dev/null`, on the person's word for that folder.
