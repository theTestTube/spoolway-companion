# developing-unblock

## The lane environment

The harness sets the task's environment. A lane resumed after a dispatcher restart, a reboot or a
usage-limit stop can lose it, and an empty `$SPOOLWAY_SCRATCH` resolves to `/`. Before the first
use, restore it from the worktree and stop if that fails:

    . scripts/spoolway/lane-env.sh || exit 1

Every command that reads or writes the scratch space begins with that line, in its own shell.

A task of the Developing pipeline stopped during a run nobody is watching. You get one attempt at
clearing it. This task only: the rest of the run is not yours.

## What you are looking at

- `## Blocker` and the last lines of `## Status Log` in the task file: which step stopped, and why.
- `## Handoff`: the findings of a failed review, and where a failed command step left its log.
- The stopped lane's transcript, through `spoolway lane`.
- The task's acceptance criteria and non-goals, and its input issue (`ticket` or `issues`), read
  live with `gh issue view <n> --json state,labels,body,comments`.

## How to do it here

1. Read `## Status Log` first. If any line of it contains `unblock attempt:`, this task has had
   its attempt. Change nothing. Leave one handoff note with what stopped it each time, what was
   tried, and the one decision a person has to take, then pause the task.
2. Otherwise start your one-line message with `unblock attempt:`, whatever the outcome.
3. Pause the task, naming what a person has to do, when the cause is any of these:
   - a device, a deploy, a secret, a login that expired, a release step;
   - a line starting `ENVIRONMENT:` in the checks log;
   - a `title:` the handover refused, or anything else that needs the task file edited;
   - an input issue whose live state contradicts the task, a `repos` entry the consumer's
     `extra-*` scripts refused, an `implementer` other than `implement` or `implement-spec`;
   - the `pin` step refusing a page: the pull request is already open, and a recompile now would
     send the task back through a second squash. Name the page. Never write its line in
     `stale-pages.md` yourself and never edit a page's pin;
   - the `pin` step stopped for any other reason: the pull request is already open, and sending
     the task back would squash it again;
   - a choice the task and its issue do not settle.
   - the `dod` step stopped, in any way that needs the person: a criterion only a person can judge,
     a rejected criterion, an unanswered question, a handoff line starting `needs a person:` or
     `for a person:`. Tick nothing, answer nothing for the person, edit no issue and post no
     comment on it, and never send the task past `dod`: it stays parked for the person. Only a
     `dod` block that names unmet work in code is yours to fix; then commit, push the branch and send the task back through `ci`.
4. When the cause is work, do the work: the failing check, the review's findings, what a lane
   that died left undone. A page declared `no-longer-holds` is work too: recompile it on the
   page write path as `.spoolway/prompts/developing-implement/PROMPT.md` says, in its step 4 of
   "Pages that cite what you changed". Stay inside the acceptance criteria and the
   non-goals. Run the typecheck and the single test files that cover what you changed,
   then commit. After a code fix to a `ci` or `dod` block, push the branch as it is (`git push`, never
   a force-push, never re-run `handover`): `ci` reads the pull request's remote checks, so an unpushed fix is not judged.
5. Your pass sends the task on: past an agent step that stopped, back through a command step
   that stopped. Choose where it goes:
   - stopped on `review`: name `review` as the next step. You never stand in for the review;
   - stopped on `ci`, or on `dod` after a code fix, once it is pushed: name `ci` as the next step (`--stage ci`). Never pass with
     no step named: that sends the task past `dod` to `signals`;
   - stopped on any other step: pass, with no step named.
6. Nobody is at the pane. Never ask a question and never use AskUserQuestion: decide, and leave
   the choice as a handoff note.

## Never

- Never make a check pass by weakening it: no skipped, deleted or loosened test, no change to
  `scripts/gates/` or to anything under `.spoolway/`.
- Never destroy work: no `git reset --hard`, no force-push, no deleted branch or worktree.
- Never merge or land anything, and never open an issue or a pull request: `handover` opens it.
- Never stop the dispatcher. Never resume, edit or queue another task, and never edit a task file.
- Never contact another session: no SendMessage, no ListAgents, no herdr or tmux command, no
  other lane's pane.
- Never run a deploy, a release or device command, or anything that reads or writes a secret.
- No commit, comment, file or message carries AI attribution.
