# developing-dod

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

You close a Developing task: its pull request is open and its CI is green. Your job is that every
acceptance criterion of the input issue is ticked, with its evidence in one new comment. A person
is at this pane, or will be: you wait for them here.

## Read first

- `skip_steps` in the task file's frontmatter: if it names `dod`, change nothing and report a pass.
- `ticket` (or `issues`), read live: `gh issue view <n> --json state,labels,body,comments`.
  `scripts/spoolway/dod.sh criteria <issue>` lists its checkboxes, numbered.
- `## Handoff`: every line starting `needs a person:` or `for a person:` is a question for the person.
- `## Status Log`: the `ci` step passed. A task whose live issue contradicts the task: block.

## Do

1. Prove each criterion you can, with a command run now in this worktree (a test, a gate, a
   check, a log of the CI run) and the lines of its output that decide it. A criterion about a
   device, a look, a deploy or a decision is not provable: do not guess it.
2. Write `$SPOOLWAY_SCRATCH/dod-plan.json` (shape in `dod.sh`), then run
   `scripts/spoolway/dod.sh questions $SPOOLWAY_SCRATCH/dod-plan.json`. Ask exactly those questions,
   in this pane, with AskUserQuestion, in Spanish (the person's language), keeping the commands
   and output verbatim. The batch question is asked once, for every criterion you proved.
   "Review them one by one" asks each of those again alone; a rejection there is `not-met`.
3. A criterion you proved not met needs no question: it is `not-met`.
4. Write the answers to `$SPOOLWAY_SCRATCH/dod-results.json` and run
   `scripts/spoolway/dod.sh apply <issue> $SPOOLWAY_SCRATCH/dod-results.json <task id> <run>`.
   It ticks only the accepted boxes, checks the body, and posts the evidence as one new comment,
   in English. It exits 1 while any box is unticked.
5. Exit 0: report a pass. Exit 1: report a block naming each unmet criterion with its evidence.

## Never

- Never tick a box, by hand or otherwise, that the person did not accept or you did not prove.
- Never edit an existing comment; never edit the issue but through `dod.sh`; never rewrite a criterion.
- Never end your turn or report while a question is unanswered: wait. Nobody else answers it.
- Never relay a question to another session, and never use the unblocker's answer for the person.
- No commit, comment or message carries AI attribution. No closing keyword before an issue.
